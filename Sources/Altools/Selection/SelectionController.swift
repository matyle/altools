import AltoolsCore
import AppKit
import SwiftUI

/// An action bar over selected text in any app: copy, search, AI translate /
/// explain / polish, and local text transforms. Appears after a mouse selection
/// (when auto popup is on) or on the hotkey.
final class SelectionController {
  enum AIAction: String, CaseIterable {
    case translate = "Translate", explain = "Explain", polish = "Polish", summarize = "Summarize"

    var symbol: String {
      switch self {
      case .translate: "character.bubble"
      case .explain: "questionmark.bubble"
      case .polish: "wand.and.stars"
      case .summarize: "text.alignleft"
      }
    }

    func prompt(for text: String) -> String {
      switch self {
      case .translate:
        let target = TextTransform.isMostlyCJK(text) ? "English" : AppSettings.shared.translateTarget
        return "Translate the text below into \(target). Output only the translation and keep the original formatting.\n\n\(text)"
      case .explain:
        return "Explain the text below concisely for a technical reader. Answer in the same language as the text.\n\n\(text)"
      case .polish:
        return "Rewrite the text below so it is clear, natural and grammatically correct. Keep its meaning, language and tone. Output only the rewritten text.\n\n\(text)"
      case .summarize:
        return "Summarize the text below in a few bullet points, in the same language as the text.\n\n\(text)"
      }
    }

    /// Whether the result is a drop-in replacement for the selection.
    var replacesSelection: Bool { self == .translate || self == .polish }
  }

  var askAI: (String) -> Void = { _ in }

  let bar = FloatingPanel(contentRect: .zero, canBecomeKey: false)
  let resultPanel = FloatingPanel(contentRect: NSRect(origin: .zero, size: SelectionResultView.size))
  let runner = AIRunner()
  private let result = SelectionResultModel()
  private var monitors: [Any] = []
  private var mouseDownPoint: NSPoint = .zero
  /// Counts clicks, scrolls and key presses, so a delayed selection read can tell the user has moved on.
  private var inputCount = 0
  private var currentText = ""

  init() {
    resultPanel.setRoot(SelectionResultView(model: result, runner: runner,
                                            onSwitch: { [weak self] action in self?.runAI(action) },
                                            onCopy: { [weak self] in self?.copyResult() },
                                            onReplace: { [weak self] in self?.replaceSelection() },
                                            onClose: { [weak self] in self?.closeResult() }))
    resultPanel.onEscape = { [weak self] in self?.closeResult() }
  }

  func start() {
    stop()
    let down = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
      if event.type == .leftMouseDown { self?.mouseDownPoint = NSEvent.mouseLocation }
      self?.inputCount += 1
      self?.hideBar()
    }
    let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
      self?.handleMouseUp(event)
    }
    monitors = [down, up].compactMap { $0 }
  }

  func stop() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    hideBar()
  }

  /// Hotkey path: works in apps without Accessibility selection by falling back to ⌘C.
  func triggerFromHotkey() {
    guard Permissions.accessibilityGranted else {
      Permissions.requestAccessibility()
      Toast.show("Allow Altools under Accessibility to use text actions", symbol: "hand.raised.fill", duration: 3)
      return
    }
    if let text = SelectionReader.readViaAccessibility() {
      showBar(for: text)
      return
    }
    SelectionReader.readViaCopy { [weak self] text in
      guard let text else { return Toast.show("No text selected", symbol: "text.cursor") }
      self?.showBar(for: text)
    }
  }

  private func handleMouseUp(_ event: NSEvent) {
    guard AppSettings.shared.selectionEnabled, AppSettings.shared.selectionAutoPopup, Permissions.accessibilityGranted else { return }
    let app = NSWorkspace.shared.frontmostApplication
    guard app?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
    let mouse = NSEvent.mouseLocation
    let dragged = hypot(mouse.x - mouseDownPoint.x, mouse.y - mouseDownPoint.y) > 6
    guard dragged || event.clickCount >= 2 else { return }
    // Give the app a moment to update its selection. Chromium apps get two more tries: the first
    // time, their accessibility has only just been switched on and the page tree is still building.
    let waits = SelectionReader.wakeChromiumAccessibility(app) ? [0.12, 0.4, 0.7] : [0.12]
    readSelection(waits: waits[...], inputCount: inputCount)
  }

  /// Reads the selection after each wait in turn until some turns up, giving up once the user
  /// clicks, scrolls or types.
  private func readSelection(waits: ArraySlice<Double>, inputCount count: Int) {
    guard let wait = waits.first else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
      guard let self, self.inputCount == count else { return }
      guard let text = SelectionReader.readViaAccessibility() else {
        return self.readSelection(waits: waits.dropFirst(), inputCount: count)
      }
      if text.count < 20_000 { self.showBar(for: text) }
    }
  }

  private func showBar(for text: String) {
    currentText = text
    let view = SelectionBar(
      onCopy: { [weak self] in
        Pasteboard.copy(text)
        self?.hideBar()
        Toast.show("Copied")
      },
      onSearch: { [weak self] in
        let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(q)") { NSWorkspace.shared.open(url) }
        self?.hideBar()
      },
      onAI: { [weak self] action in self?.runAI(action) },
      onAsk: { [weak self] in
        self?.hideBar()
        self?.askAI(text)
      },
      onTransform: { [weak self] transform in self?.runTransform(transform) },
      pluginActions: pluginActions()
    )
    bar.setRoot(view)
    let size = NSHostingView(rootView: view).fittingSize
    bar.setFrame(ScreenGeometry.frame(near: NSEvent.mouseLocation, size: size, offset: 14), display: true)
    bar.orderFrontRegardless()
  }

  func hideBar() {
    if bar.isVisible { bar.orderOut(nil) }
  }

  /// Translates text that did not come from a selection (the notch, the clipboard).
  func translate(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      ActivityCenter.shared.report("Copy some text first, then Translate", symbol: "character.bubble")
      return
    }
    currentText = trimmed
    runAI(.translate)
  }

  func runAI(_ action: AIAction) {
    hideBar()
    runner.reset()
    result.title = action.rawValue
    result.aiAction = action
    result.source = currentText
    result.mode = .ai
    result.canReplace = action.replacesSelection
    result.staticText = ""
    showResultPanel()
    runner.send(action.prompt(for: currentText), mode: .quick, showPrompt: false)
  }

  /// Every enabled plugin's `selection` actions.
  private func pluginActions() -> [SelectionPluginAction] {
    guard AppSettings.shared.pluginsEnabled else { return [] }
    return PluginHost.shared.plugins.filter { $0.enabled && $0.problem == nil }.flatMap { plugin in
      (plugin.manifest?.selectionActions ?? []).map { action in
        SelectionPluginAction(id: "\(plugin.id).\(action.id)", title: action.title,
                              icon: action.icon ?? plugin.manifest?.icon ?? "puzzlepiece.extension") { [weak self] in
          self?.runPluginAction(plugin.id, action)
        }
      }
    }
  }

  /// Sends the selection to a plugin and shows its `result`; Replace appears when the plugin asks for it.
  func runPluginAction(_ pluginID: String, _ action: PluginCommand) {
    hideBar()
    let text = currentText
    result.title = action.title
    result.aiAction = nil
    result.source = text
    result.mode = .text
    result.staticText = "Running…"
    result.canReplace = false
    showResultPanel()
    Task { @MainActor [weak self] in
      let output = await PluginHost.shared.request(pluginID, event: .selection(action.id), input: text)
      guard let self else { return }
      self.result.staticText = output?.result?.text ?? "No result — see the plugin's log in Settings › Plugins."
      self.result.canReplace = output?.result?.replace ?? false
    }
  }

  func runTransform(_ transform: TextTransform) {
    hideBar()
    do {
      let output = try transform.apply(currentText)
      result.title = transform.title
      result.aiAction = nil
      result.source = currentText
      result.mode = .text
      result.staticText = output
      result.canReplace = transform.replacesSelection
      showResultPanel()
    } catch {
      Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
    }
  }

  private func showResultPanel() {
    guard !resultPanel.isVisible else { return }
    resultPanel.setFrame(ScreenGeometry.frame(near: NSEvent.mouseLocation, size: resultPanel.frame.size, offset: 16), display: true)
    resultPanel.orderFrontRegardless()
  }

  private var resultText: String {
    result.mode == .ai ? runner.lastAnswer : result.staticText
  }

  private func copyResult() {
    Pasteboard.copy(resultText)
    closeResult()
    Toast.show("Copied")
  }

  /// Pastes the result over the selection. The panel never activated Altools, so
  /// the original app is still frontmost with its selection intact.
  func replaceSelection() {
    let text = resultText
    closeResult()
    if !Pasteboard.paste(text) {
      Toast.show("Copied — allow Accessibility to paste automatically", symbol: "doc.on.clipboard", duration: 2.5)
    }
  }

  func closeResult() {
    runner.cancel()
    resultPanel.orderOut(nil)
  }
}

