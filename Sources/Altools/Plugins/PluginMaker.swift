import AltoolsCore
import Combine
import Foundation

/// "Make a plugin": the user describes a plugin and the configured AI CLI writes it into the
/// Plugins folder, following PLUGINS.md (bundled with the app), and runs it once to check.
/// Plugins it creates are switched on, since the user asked for them.
final class PluginMaker: ObservableObject {
  let runner = AIRunner()
  @Published var prompt = ""

  private var existing: Set<String> = []
  private var watch: AnyCancellable?

  /// Commands the AI may run while building: the plugin itself, interpreters, curl and file
  /// listing, plus web lookups for API docs. Everything else still needs a permission it lacks.
  private static let tools = [
    "Bash(./*)", "Bash(sh:*)", "Bash(bash:*)", "Bash(zsh:*)", "Bash(python3:*)", "Bash(node:*)",
    "Bash(curl:*)", "Bash(chmod:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(mkdir:*)", "Bash(jq:*)",
    "Bash(env:*)", "Bash(ALTOOLS_EVENT=*)", "WebFetch", "WebSearch",
  ]

  init() {
    // Re-publish the transcript so views observing the maker redraw as it streams.
    watch = runner.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
  }

  var isRunning: Bool { runner.isRunning }

  func make() {
    let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !request.isEmpty, !runner.isRunning else { return }
    existing = Set(PluginHost.shared.plugins.map(\.id))
    runner.reset()
    send(request)
  }

  /// Sends the plugin's error and log back to the same conversation.
  func fix(_ plugin: PluginHost.Plugin) {
    guard !runner.isRunning else { return }
    existing = Set(PluginHost.shared.plugins.map(\.id)).subtracting([plugin.id])
    send("""
    The plugin in ./\(plugin.id)/ fails in Altools with: \(plugin.error ?? "no output").
    Its recent log:
    \(plugin.log.suffix(2_000))
    Fix it, run it again with ALTOOLS_EVENT=refresh, and confirm it prints one valid JSON object.
    """)
  }

  private func send(_ text: String) {
    runner.send(text, mode: .agent, systemPrompt: Self.systemPrompt, workDirectory: PluginHost.folder.path,
                toolPolicy: .acceptEdits, allowedTools: Self.tools)
    awaitFinish()
  }

  private func awaitFinish() {
    var cancellable: AnyCancellable?
    cancellable = runner.$isRunning.dropFirst().filter { !$0 }.first().receive(on: DispatchQueue.main).sink { [weak self] _ in
      self?.finish()
      _ = cancellable
    }
  }

  private func finish() {
    let host = PluginHost.shared
    host.reload()
    for plugin in host.plugins where !existing.contains(plugin.id) {
      host.setEnabled(plugin.id, true)
    }
    for plugin in host.plugins where plugin.enabled { host.refresh(plugin.id) }
  }

  private static var systemPrompt: String {
    let guide = Bundle.main.url(forResource: "PLUGINS", withExtension: "md").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
      ?? "Altools plugin API: see https://github.com/matyle/altools/blob/main/PLUGINS.md"
    return """
    You are building a plugin for Altools, a macOS notch app. The current directory is the Altools \
    Plugins folder. Follow this API exactly:

    \(guide)

    Rules:
    - Create exactly one new folder here named after the plugin id, with plugin.json and the program. \
    Don't touch other folders unless the user asks you to fix that plugin.
    - Prefer sh, curl and python3 with only the standard library. Make the program executable.
    - If it needs an API key or account, declare a "secret" setting and, when it's empty, output a row \
    telling the user what to fill in under Settings › Notch › Plugins.
    - Run it once with ALTOOLS_EVENT=refresh and the ALTOOLS_SETTING_* variables it uses, and make sure it \
    prints one valid JSON object and exits 0. Fix it until it does.
    - Finish with two or three sentences: what it shows where, and any setting to fill in. Reply in the \
    user's language.
    """
  }
}
