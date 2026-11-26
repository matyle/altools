import AltoolsCore
import AppKit
import SwiftUI

struct LauncherItem: Identifiable {
  enum Icon {
    case image(NSImage)
    /// SF Symbol drawn on a tinted rounded square.
    case symbol(String, Color)
  }

  let id: String
  /// Group heading shown above the first item of each section.
  var section: String
  let title: String
  var subtitle: String = ""
  let icon: Icon
  /// What ↩ does, shown on the selected row ("Open", "Paste", "Copy").
  var actionName: String = "Open"
  /// Trailing hint on unselected rows, e.g. "Application" or "2 min ago".
  var accessory: String = ""
  /// The clipboard entry this row shows, if any (drives the preview pane).
  var clip: ClipboardStore.Item?
  let action: () -> Void
}

/// A built-in command shown in launcher search ("Capture Area", "Quit Altools"…).
struct LauncherCommand {
  let title: String
  let keywords: String
  let symbol: String
  var tint: Color = .gray
  let action: () -> Void
}

final class LauncherModel: ObservableObject {
  enum Mode { case search, clipboard, ai }

  @Published var query = "" { didSet { if mode != .ai, query != oldValue { rebuild() } } }
  @Published private(set) var mode: Mode = .search
  @Published private(set) var items: [LauncherItem] = []
  @Published var selection = 0
  let runner = AIRunner()
  let clipboard: ClipboardStore

  var commands: () -> [LauncherCommand] = { [] }
  /// Hides the launcher panel. Actions call this before acting on another app.
  var dismiss: () -> Void = {}

  init(clipboard: ClipboardStore = .shared) {
    self.clipboard = clipboard
  }

  var selectedItem: LauncherItem? { items.indices.contains(selection) ? items[selection] : nil }

  /// Bumped on every open; the view puts the caret back in the field when it changes.
  @Published private(set) var focusRequest = 0

  func open(in newMode: Mode) {
    focusRequest += 1
    if newMode == .ai, mode == .ai { return }
    mode = newMode
    query = ""
    selection = 0
    if newMode != .ai { runner.reset() }
    rebuild()
  }

  // MARK: Keyboard

  func moveSelection(_ delta: Int) {
    guard !items.isEmpty else { return }
    selection = (selection + delta + items.count) % items.count
  }

  /// ↩: run the selected item, or send the prompt in AI mode.
  func submit() {
    switch mode {
    case .ai:
      let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !prompt.isEmpty else { return }
      query = ""
      runner.send(prompt, mode: .agent)
    case .search, .clipboard:
      selectedItem?.action()
    }
  }

  /// ⌘↩: copy instead of paste (clipboard), copy the answer (AI).
  func submitAlternate() {
    switch mode {
    case .ai:
      Pasteboard.copy(runner.lastAnswer)
      dismiss()
      Toast.show("Answer copied")
    case .clipboard, .search:
      guard let clip = selectedItem?.clip else { return submit() }
      clipboard.restoreToPasteboard(clip)
      dismiss()
      Toast.show("Copied")
    }
  }

  /// Tab: hand the current query to the AI.
  func askAI(_ prompt: String? = nil) {
    let text = (prompt ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
    mode = .ai
    runner.reset()
    query = ""
    if !text.isEmpty { runner.send(text, mode: .agent) }
  }

  /// Esc: cancel a running answer, then leave the mode, then close.
  func escape() {
    if mode == .ai, runner.isRunning {
      runner.cancel()
    } else if !query.isEmpty, mode != .ai {
      query = ""
    } else if mode != .search {
      open(in: .search)
    } else {
      dismiss()
    }
  }

  func deleteSelectedClipboardItem() {
    guard let clip = selectedItem?.clip else { return }
    clipboard.delete(clip)
    rebuild()
  }

  // MARK: Results

  func rebuild() {
    let previousID = selectedItem?.id
    items = mode == .clipboard ? clipboardItems(limit: 200, section: "") : searchItems()
    // Keep the highlighted row when the list changes underneath it (e.g. a delete),
    // but start from the top when the query changes.
    if mode == .clipboard, let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
      selection = index
    } else {
      selection = min(selection, max(items.count - 1, 0))
      if mode == .search { selection = 0 }
    }
  }

  private func searchItems() -> [LauncherItem] {
    let q = query.trimmingCharacters(in: .whitespaces)
    var result: [LauncherItem] = []

    let settings = AppSettings.shared
    if settings.isOn("launcher.calc"), Calculator.looksLikeExpression(q), let value = Calculator.evaluate(q) {
      let text = Calculator.format(value)
      result.append(LauncherItem(id: "calc", section: "Calculator", title: text, subtitle: q,
                                 icon: .symbol("equal", .orange), actionName: "Copy") { [weak self] in
        Pasteboard.copy(text)
        self?.dismiss()
        Toast.show("Copied \(text)")
      })
    }

    let commands = settings.isOn("launcher.commands") ? commands() : []
    if q.isEmpty {
      result += clipboardItems(limit: 3, section: "Recent Clipboard")
      result += commands.map { commandItem($0, section: "Commands") }
      return result
    }

    let apps = AppIndex.shared.apps
      .compactMap { app in FuzzyMatch.score(q, app.name).map { (app, $0) } }
      .sorted { $0.1 > $1.1 }
      .prefix(6)
    result += apps.map { app, _ in
      LauncherItem(id: app.url.path, section: "Applications", title: app.name,
                   icon: .image(AppIndex.shared.icon(for: app.url)), accessory: "Application") { [weak self] in
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
        self?.dismiss()
      }
    }

    result += commands
      .compactMap { cmd in FuzzyMatch.score(q, cmd.title).map { (cmd, $0) } ?? keywordMatch(q, cmd) }
      .sorted { $0.1 > $1.1 }
      .prefix(4)
      .map { commandItem($0.0, section: "Commands") }

    result += clipboardItems(limit: 3, section: "Clipboard", matching: q)

    let provider = settings.aiProvider.displayName
    if settings.isOn("launcher.ai") {
      result.append(LauncherItem(id: "ask-ai", section: "Use “\(q)” with…", title: "Ask \(provider)",
                                 subtitle: q, icon: .symbol("sparkles", .purple), actionName: "Ask",
                                 accessory: "⇥") { [weak self] in self?.askAI() })
    }
    guard settings.isOn("launcher.web") else { return result }
    result.append(LauncherItem(id: "web", section: "Use “\(q)” with…", title: "Search Google",
                               subtitle: q, icon: .symbol("globe", .blue), actionName: "Search") { [weak self] in
      let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
      if let url = URL(string: "https://www.google.com/search?q=\(encoded)") { NSWorkspace.shared.open(url) }
      self?.dismiss()
    })
    return result
  }

  /// Commands also match on their keywords ("screenshot" finds Capture Area), ranked below title matches.
  private func keywordMatch(_ q: String, _ cmd: LauncherCommand) -> (LauncherCommand, Int)? {
    cmd.keywords.split(separator: " ").contains { $0.lowercased().hasPrefix(q.lowercased()) } ? (cmd, 1) : nil
  }

  private func commandItem(_ cmd: LauncherCommand, section: String) -> LauncherItem {
    LauncherItem(id: "cmd-\(cmd.title)", section: section, title: cmd.title,
                 icon: .symbol(cmd.symbol, cmd.tint), actionName: "Run", accessory: "Command") {
      cmd.action()
    }
  }

  private func clipboardItems(limit: Int, section: String, matching q: String = "") -> [LauncherItem] {
    let filter = mode == .clipboard ? query.trimmingCharacters(in: .whitespaces) : q
    let matches = clipboard.items.filter {
      filter.isEmpty || ($0.kind == .text && $0.value.localizedCaseInsensitiveContains(filter))
    }
    return matches.prefix(limit).map { item in
      let title: String
      let icon: LauncherItem.Icon
      switch item.kind {
      case .text:
        title = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
          .components(separatedBy: .newlines).first { !$0.isEmpty } ?? item.value
        icon = .symbol(Self.symbol(forClip: item.value), .teal)
      case .image:
        title = "Image"
        icon = NSImage(contentsOf: clipboard.imageURL(for: item)).map(LauncherItem.Icon.image) ?? .symbol("photo", .teal)
      }
      return LauncherItem(id: item.id.uuidString, section: section, title: String(title.prefix(200)),
                          icon: icon, actionName: "Paste",
                          accessory: item.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)),
                          clip: item) { [weak self] in
        guard let self else { return }
        dismiss()
        clipboard.restoreToPasteboard(item)
        if Permissions.accessibilityGranted {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Keystrokes.command(Keystrokes.keyV) }
        } else {
          Toast.show("Copied — allow Accessibility to paste automatically", symbol: "doc.on.clipboard", duration: 2.5)
        }
      }
    }
  }

  static func symbol(forClip text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return "link" }
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.contains("func ") || trimmed.contains("def ") {
      return "curlybraces"
    }
    return "text.alignleft"
  }
}
