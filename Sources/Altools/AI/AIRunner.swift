import AltoolsCore
import Foundation

/// Finds the claude / codex executables. GUI apps get a minimal PATH (no
/// ~/.local/bin, no Homebrew), so the usual install locations are checked
/// explicitly, then the user's login shell as a last resort.
enum CLILocator {
  private static var cache: [AIProvider: String] = [:]

  static let extraPathDirectories: [String] = [
    "\(NSHomeDirectory())/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
    "\(NSHomeDirectory())/.npm-global/bin", "\(NSHomeDirectory())/.bun/bin",
    "\(NSHomeDirectory())/.volta/bin", "/usr/bin", "/bin",
  ]

  /// Returns nil when the CLI cannot be found anywhere.
  static func path(for provider: AIProvider, configured: String) -> String? {
    if !configured.isEmpty {
      return FileManager.default.isExecutableFile(atPath: configured) ? configured : nil
    }
    if let cached = cache[provider], FileManager.default.isExecutableFile(atPath: cached) { return cached }
    let found = extraPathDirectories
      .map { "\($0)/\(provider.binaryName)" }
      .first { FileManager.default.isExecutableFile(atPath: $0) }
      ?? loginShellLookup(provider.binaryName)
    cache[provider] = found
    return found
  }

  /// `whence -p` ignores shell aliases and prints only real executables.
  private static func loginShellLookup(_ name: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "whence -p \(name)"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return output.isEmpty ? nil : output
  }

  /// Reads a proxy the user set inside a `claude` shell alias (e.g.
  /// `alias claude='HTTP_PROXY=http://127.0.0.1:9000 command claude'`); GUI apps
  /// never see aliases, so without this the CLI would run without the proxy.
  /// Looks in the shell startup files first (instant), then asks an interactive zsh.
  /// Returns nil when no alias sets a proxy.
  static func proxyFromShellAlias() -> String? {
    let home = NSHomeDirectory()
    for file in [".zshrc", ".zprofile", ".zshenv", ".bashrc", ".bash_profile"] {
      guard let text = try? String(contentsOfFile: "\(home)/\(file)", encoding: .utf8) else { continue }
      for line in text.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("alias claude="), let proxy = proxyValue(in: trimmed) else { continue }
        return proxy
      }
    }
    return proxyValue(in: interactiveShellOutput("alias claude", timeout: 15) ?? "")
  }

  static func proxyValue(in text: String) -> String? {
    guard let range = text.range(of: #"(?i)https?_proxy=([^\s'"]+)"#, options: .regularExpression) else { return nil }
    return String(text[range].split(separator: "=", maxSplits: 1)[1])
  }

  /// Output of `zsh -ic <command>`, read while it runs so a chatty .zshrc cannot
  /// fill the pipe and stall the shell. nil on timeout.
  private static func interactiveShellOutput(_ command: String, timeout: TimeInterval) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-ic", command]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    let lock = NSLock()
    var output = Data()
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let chunk = handle.availableData
      lock.lock(); output.append(chunk); lock.unlock()
    }
    do { try process.run() } catch { return nil }
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    pipe.fileHandleForReading.readabilityHandler = nil
    if process.isRunning { process.terminate(); return nil }
    lock.lock(); defer { lock.unlock() }
    return String(data: output, encoding: .utf8)
  }

  static func environment(proxy: String) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let existing = env["PATH"] ?? ""
    env["PATH"] = (extraPathDirectories + [existing]).joined(separator: ":")
    if !proxy.isEmpty {
      for key in ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"] { env[key] = proxy }
    }
    return env
  }
}

/// Runs one AI conversation through the claude or codex CLI and publishes the
/// streamed transcript. Follow-up calls to `send` resume the same CLI session.
final class AIRunner: ObservableObject {
  struct Entry: Identifiable, Equatable {
    enum Kind { case user, text, tool, error }
    let id = UUID()
    let kind: Kind
    var content: String
  }

  @Published private(set) var entries: [Entry] = []
  @Published private(set) var isRunning = false {
    didSet {
      guard isRunning != oldValue else { return }
      isRunning ? ActivityCenter.shared.aiStarted() : ActivityCenter.shared.aiFinished()
    }
  }

  private var process: Process?
  private var sessionID: String?
  private var sessionProvider: AIProvider?

  /// Text of the latest answer only (what "Copy" and "Replace" use).
  var lastAnswer: String {
    guard let lastUser = entries.lastIndex(where: { $0.kind == .user }) else {
      return entries.filter { $0.kind == .text }.map(\.content).joined()
    }
    return entries[(lastUser + 1)...].filter { $0.kind == .text }.map(\.content).joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func reset() {
    cancel()
    entries = []
    sessionID = nil
    sessionProvider = nil
  }

  /// `showPrompt` false hides the prompt in the transcript (used by text actions,
  /// whose prompt is a long template the user did not type).
  /// `workDirectory`, `toolPolicy` and `allowedTools` override Settings › AI for this call
  /// (the plugin maker works inside the new plugin's folder and may run its script).
  func send(_ prompt: String, mode: AIMode, systemPrompt: String? = nil, showPrompt: Bool = true,
            workDirectory: String? = nil, toolPolicy: ToolPolicy? = nil, allowedTools: [String] = []) {
    cancel()
    let settings = AppSettings.shared
    let provider = settings.aiProvider
    if showPrompt { entries.append(Entry(kind: .user, content: prompt)) }

    guard let executable = CLILocator.path(for: provider, configured: settings.binaryPath(for: provider)) else {
      entries.append(Entry(kind: .error, content:
        "Could not find the \(provider.binaryName) command. Install \(provider.displayName) and log in once in a terminal, or set its path in Settings › AI."))
      return
    }

    // A session from the other provider cannot be resumed.
    let resume = (mode == .agent && sessionProvider == provider) ? sessionID : nil
    let request = AIRequest(provider: provider, mode: mode, prompt: prompt, systemPrompt: systemPrompt,
                            model: settings.aiModel, toolPolicy: toolPolicy ?? settings.toolPolicy, resumeSessionID: resume,
                            allowedTools: allowedTools)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = AICommand.arguments(for: request)
    process.environment = CLILocator.environment(proxy: settings.proxy)
    let workDir = ((workDirectory ?? settings.workDirectory) as NSString).expandingTildeInPath
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.fileExists(atPath: workDir) ? workDir : NSHomeDirectory())
    process.standardInput = FileHandle.nullDevice

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    var parser = makeParser(for: provider)
    var lineBuffer = Data()
    var stderrTail = Data()
    var sawError = false

    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let chunk = handle.availableData
      guard !chunk.isEmpty else { return }
      lineBuffer.append(chunk)
      var lines: [String] = []
      while let newline = lineBuffer.firstIndex(of: 0x0A) {
        let lineData = lineBuffer[lineBuffer.startIndex..<newline]
        lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
        if let line = String(data: lineData, encoding: .utf8), !line.isEmpty { lines.append(line) }
      }
      let events = lines.flatMap { parser.parse(line: $0) }
      if events.contains(where: { if case .error = $0 { true } else { false } }) { sawError = true }
      guard !events.isEmpty else { return }
      DispatchQueue.main.async { self?.apply(events, provider: provider, process: process) }
    }
    stderr.fileHandleForReading.readabilityHandler = { handle in
      stderrTail.append(handle.availableData)
      if stderrTail.count > 8000 { stderrTail = stderrTail.suffix(4000) }
    }

    process.terminationHandler = { [weak self] proc in
      stdout.fileHandleForReading.readabilityHandler = nil
      stderr.fileHandleForReading.readabilityHandler = nil
      lineBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
      let tailEvents = String(data: lineBuffer, encoding: .utf8)?
        .split(separator: "\n").flatMap { parser.parse(line: String($0)) } ?? []
      if tailEvents.contains(where: { if case .error = $0 { true } else { false } }) { sawError = true }
      if !tailEvents.isEmpty {
        DispatchQueue.main.async { self?.apply(tailEvents, provider: provider, process: proc) }
      }
      let status = proc.terminationStatus
      let reason = proc.terminationReason
      let errorText = String(data: stderrTail, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      DispatchQueue.main.async {
        guard let self, self.process === proc else { return }
        self.isRunning = false
        self.process = nil
        // A cancelled run (SIGTERM) is not an error worth showing.
        if status != 0, reason == .exit, !sawError {
          let detail = errorText.isEmpty ? "exit code \(status)" : String(errorText.suffix(600))
          self.entries.append(Entry(kind: .error, content: "\(provider.displayName) failed: \(detail)"))
        }
      }
    }

    do {
      try process.run()
      self.process = process
      isRunning = true
    } catch {
      entries.append(Entry(kind: .error, content: "Could not start \(executable): \(error.localizedDescription)"))
    }
  }

  #if DEBUG
  /// Fills the transcript with canned entries for off-screen renders.
  func loadDemo(_ demo: [(Entry.Kind, String)], running: Bool = false) {
    entries = demo.map { Entry(kind: $0.0, content: $0.1) }
    isRunning = running
  }
  #endif

  func cancel() {
    if let process, process.isRunning { process.terminate() }
    process = nil
    isRunning = false
  }

  private func apply(_ events: [AIEvent], provider: AIProvider, process: Process) {
    guard self.process === process else { return } // a newer run replaced this one
    for event in events {
      switch event {
      case .text(let chunk):
        if let last = entries.indices.last, entries[last].kind == .text {
          entries[last].content += chunk
        } else {
          let trimmed = chunk.trimmingCharacters(in: .newlines)
          if !trimmed.isEmpty { entries.append(Entry(kind: .text, content: trimmed)) }
        }
      case .tool(let name, let detail):
        entries.append(Entry(kind: .tool, content: detail.isEmpty ? name : "\(name)  \(detail)"))
      case .session(let id):
        sessionID = id
        sessionProvider = provider
      case .error(let message):
        entries.append(Entry(kind: .error, content: message))
      }
    }
  }
}
