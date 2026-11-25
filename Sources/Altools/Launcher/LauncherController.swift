import AppKit

final class LauncherController {
  let model = LauncherModel()
  private lazy var panel: FloatingPanel = {
    let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: LauncherLayout.size))
    panel.setRoot(LauncherView(model: model))
    panel.onResignKey = { [weak self] in self?.hide(reason: "resignKey") }
    panel.onEscape = { [weak self] in self?.model.escape() }
    return panel
  }()
  private var keyMonitor: Any?

  init(commands: @escaping () -> [LauncherCommand]) {
    model.commands = commands
    model.dismiss = { [weak self] in self?.hide(reason: "model.dismiss") }
    AppIndex.shared.refreshIfStale()
  }

  var isVisible: Bool { panel.isVisible }
  var window: NSWindow { panel }

  func toggle(_ mode: LauncherModel.Mode) {
    if panel.isVisible, model.mode == mode { hide() } else { show(mode) }
  }

  func show(_ mode: LauncherModel.Mode) {
    AppIndex.shared.refreshIfStale()
    model.open(in: mode)
    let visible = ScreenGeometry.activeScreen.visibleFrame
    let size = panel.frame.size
    // Upper third of the screen, like Spotlight.
    panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.62 - size.height / 2))
    panel.makeKeyAndOrderFront(nil)
    installKeyMonitor()
  }

  /// Opens straight into AI mode, keeping a conversation that is already open.
  func showAI(prompt: String? = nil) {
    show(.ai)
    if let prompt, !prompt.isEmpty {
      model.query = prompt
      model.submit()
    }
  }

  /// Who closed the panel last; read by the live self-test.
  private(set) var lastHideReason: String?

  func hide(reason: String = "hide") {
    guard panel.isVisible else { return }
    lastHideReason = reason
    panel.orderOut(nil)
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
  }

  /// Arrow keys, Tab and ⌘-shortcuts are taken before the text field sees them;
  /// the field editor would otherwise move the caret or focus instead.
  private func installKeyMonitor() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, event.window === self.panel else { return event }
      let command = event.modifierFlags.contains(.command)
      switch Int(event.keyCode) {
      case 125: model.moveSelection(1); return nil                     // ↓
      case 126: model.moveSelection(-1); return nil                    // ↑
      case 48 where model.mode == .search: model.askAI(); return nil   // ⇥
      case 36, 76:                                                     // ↩
        command ? model.submitAlternate() : model.submit()
        return nil
      case 51 where command && model.mode == .clipboard:               // ⌘⌫
        model.deleteSelectedClipboardItem(); return nil
      case 53: model.escape(); return nil                              // esc
      default: return event
      }
    }
  }
}
