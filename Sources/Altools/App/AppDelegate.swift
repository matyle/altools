import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var statusPanel: StatusPanelController?
  private var launcher: LauncherController!
  private let capture = CaptureController()
  private let notch = NotchController()
  private let hider = MenuBarHider()
  private let widgets = WidgetsController()
  private let selection = SelectionController()
  private var settingsWindow: NSWindow?
  private var cancellables: Set<AnyCancellable> = []
  private let settings = AppSettings.shared

  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
    if DebugRender.runIfRequested() { return }
    if DebugSelfTest.runIfRequested() { return }
    if DebugPluginTest.runIfRequested() { return }
    if DebugPluginShareTest.runIfRequested() { return }
    #endif
    launcher = LauncherController(commands: { [weak self] in self?.launcherCommands() ?? [] })
    selection.askAI = { [weak self] text in
      self?.launcher.showAI(prompt: "Here is some text I selected:\n\n\(text)\n\n")
    }
    notch.actions = NotchActions(
      openLauncher: { [weak self] in self?.launcher.show(.search) },
      openClipboard: { [weak self] in self?.launcher.show(.clipboard) },
      captureArea: { [weak self] in self?.capture.capture(then: .annotate) },
      recognizeText: { [weak self] in self?.capture.capture(then: .ocr) },
      pickColor: { ColorPicker.pick() },
      askAI: { [weak self] in self?.launcher.showAI() },
      translate: { [weak self] text in self?.selection.translate(text) },
      openSettings: { [weak self] in self?.showSettings() }
    )

    settings.detectProxyOnce()
    setUpStatusItem()
    registerHotKeys()
    ClipboardStore.shared.start()

    // Turn modules on and off as their settings change.
    settings.$notchEnabled.removeDuplicates()
      .sink { [weak self] on in on ? self?.notch.start() : self?.notch.stop() }
      .store(in: &cancellables)
    settings.$widgetsEnabled.removeDuplicates()
      .sink { [weak self] on in on ? self?.widgets.start() : self?.widgets.stop() }
      .store(in: &cancellables)
    settings.$hiderEnabled.removeDuplicates()
      .sink { [weak self] on in on ? self?.hider.start() : self?.hider.stop() }
      .store(in: &cancellables)
    settings.$hiderIcon.map { _ in () }.merge(with: settings.$hiderSections.map { _ in () }).dropFirst()
      .sink { [weak self] _ in DispatchQueue.main.async { self?.hider.refresh() } }
      .store(in: &cancellables)
    settings.$selectionAutoPopup.merge(with: settings.$selectionEnabled).removeDuplicates()
      .sink { [weak self] _ in DispatchQueue.main.async { self?.selection.start() } }
      .store(in: &cancellables)

    if !Permissions.accessibilityGranted {
      // Without it: no auto popup on selection, no paste-back. Ask once at first launch.
      if !UserDefaults.standard.bool(forKey: "askedAccessibility") {
        UserDefaults.standard.set(true, forKey: "askedAccessibility")
        Permissions.requestAccessibility()
      }
    }
    if HotKeyCenter.shared.failed.count > 0 {
      let names = HotKeyCenter.shared.failed.map(\.display).joined(separator: ", ")
      Toast.show("Shortcut already in use by another app: \(names)", symbol: "keyboard", duration: 4)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    hider.stop()
    notch.stop()
  }

  private func registerHotKeys() {
    let center = HotKeyCenter.shared
    // Each shortcut does nothing while its module is switched off in Settings.
    let s = settings
    center.register(HotKeys.launcher) { [weak self] in if s.launcherEnabled { self?.launcher.toggle(.search) } }
    center.register(HotKeys.clipboard) { [weak self] in if s.clipboardEnabled { self?.launcher.toggle(.clipboard) } }
    center.register(HotKeys.askAI) { [weak self] in if s.launcherEnabled && s.isOn("launcher.ai") { self?.launcher.showAI() } }
    center.register(HotKeys.captureArea) { [weak self] in if s.captureEnabled { self?.capture.capture(then: .annotate) } }
    center.register(HotKeys.captureText) { [weak self] in if s.captureEnabled { self?.capture.capture(then: .ocr) } }
    center.register(HotKeys.selection) { [weak self] in if s.selectionEnabled { self?.selection.triggerFromHotkey() } }
    center.register(HotKeys.menuBar) { [weak self] in if s.hiderEnabled { self?.hider.toggle() } }
    center.register(HotKeys.notch) { [weak self] in if s.notchEnabled { self?.notch.toggleExpanded() } }
    center.register(HotKeys.newNote) { [weak self] in if s.notchEnabled && s.isOn("notch.notes") { self?.notch.newNote() } }
  }

  private func setUpStatusItem() {
    // Start beside the system icons (points from the right edge), where macOS drops it last when the bar is full.
    let positionKey = "NSStatusItem Preferred Position altools.main"
    if UserDefaults.standard.object(forKey: positionKey) == nil {
      UserDefaults.standard.set(290, forKey: positionKey)
    }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.autosaveName = "altools.main"
    statusItem.button?.image = AltoolsGlyph.template()
    let actions = StatusActions(
      screenshot: { [weak self] in self?.capture.capture(then: .annotate) },
      ocr: { [weak self] in self?.capture.capture(then: .ocr) },
      translate: { [weak self] in self?.selection.translate(NSPasteboard.general.string(forType: .string) ?? "") },
      pickColor: { ColorPicker.pick() },
      clipboard: { [weak self] in self?.launcher.show(.clipboard) },
      settings: { [weak self] in self?.showSettings() }
    )
    statusPanel = StatusPanelController(button: statusItem.button, actions: actions)
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusItemClicked)
  }

  @objc private func statusItemClicked() {
    statusPanel?.toggle()
  }

  private func launcherCommands() -> [LauncherCommand] {
    let hide = { [weak self] in self?.launcher.hide() }
    return [
      LauncherCommand(title: "Ask AI", keywords: "claude codex chat", symbol: "sparkles", tint: .purple) { [weak self] in
        self?.launcher.model.askAI()
      },
      LauncherCommand(title: "Clipboard History", keywords: "paste copy", symbol: "doc.on.clipboard", tint: .teal) { [weak self] in
        self?.launcher.model.open(in: .clipboard)
      },
      LauncherCommand(title: "Capture Area", keywords: "screenshot snap", symbol: "camera.viewfinder", tint: .blue) { [weak self] in
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.capture.capture(then: .annotate) }
      },
      LauncherCommand(title: "Capture Text (OCR)", keywords: "screenshot recognize", symbol: "text.viewfinder", tint: .indigo) { [weak self] in
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.capture.capture(then: .ocr) }
      },
      LauncherCommand(title: "Capture and Pin", keywords: "screenshot float sticky", symbol: "pin.fill", tint: .red) { [weak self] in
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.capture.capture(then: .pin) }
      },
      LauncherCommand(title: "Toggle Notch Panel", keywords: "island", symbol: "rectangle.topthird.inset.filled", tint: .black) { [weak self] in
        hide()
        self?.notch.toggleExpanded()
      },
      LauncherCommand(title: "Clear Clipboard History", keywords: "delete", symbol: "trash", tint: .gray) {
        ClipboardStore.shared.clear()
        hide()
        Toast.show("Clipboard history cleared")
      },
      LauncherCommand(title: "Sleep Displays", keywords: "lock screen off", symbol: "moon.fill", tint: .indigo) {
        hide()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
      },
      LauncherCommand(title: "Altools Settings", keywords: "preferences config", symbol: "gearshape.fill", tint: .gray) { [weak self] in
        hide()
        self?.showSettings()
      },
      LauncherCommand(title: "Quit Altools", keywords: "exit", symbol: "power", tint: .gray) { NSApp.terminate(nil) },
    ]
  }

  /// `altools://selftest` runs the live desktop self-test (see LiveSelfTest).
  func application(_ application: NSApplication, open urls: [URL]) {
    // A double-clicked .altoolsplugin, or an altools://install-plugin link.
    var handled = false
    for url in urls {
      if url.isFileURL, url.pathExtension == PluginPackage.fileExtension {
        PluginPackage.install(from: url, source: url.lastPathComponent)
        handled = true
      } else if PluginPackage.handle(url) {
        handled = true
      }
    }
    if handled { return }
    if urls.contains(where: { $0.host == "dump-notifications" }) {
      // Waits for a banner to be on screen, then writes its accessibility tree for inspection.
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let out = AppPaths.subdirectory("selftest").appendingPathComponent("notification-tree.txt")
        try? NotificationWatcher.dumpTree().write(to: out, atomically: true, encoding: .utf8)
      }
      return
    }
    guard let url = urls.first(where: { $0.host == "selftest" }) else { return }
    let only = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "only" }?.value
    LiveSelfTest(launcher: launcher, notch: notch, selection: selection, capture: capture).run(only: only)
  }

  func toggleMenuBarHider() { hider.toggle() }
  func toggleStatusPanel() { statusPanel?.toggle() }
  func toggleWidget(_ kind: WidgetsController.Kind) { widgets.toggle(kind) }
  var menuBarHiderFrames: String { hider.debugFrames }

  func showSettings() {
    if settingsWindow == nil {
      let actions = SettingsActions(
        captureArea: { [weak self] in self?.capture.capture(then: .annotate) },
        recognizeText: { [weak self] in self?.capture.capture(then: .ocr) },
        translate: { [weak self] in self?.selection.translate(NSPasteboard.general.string(forType: .string) ?? "") },
        pickColor: { ColorPicker.pick() },
        openClipboard: { [weak self] in self?.launcher.show(.clipboard) }
      )
      let hosting = NSHostingController(rootView: SettingsRoot(actions: actions))
      hosting.sizingOptions = []
      let window = NSWindow(contentViewController: hosting)
      window.title = "Altools"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.backgroundColor = NSColor(red: 0.055, green: 0.063, blue: 0.094, alpha: 1)
      window.appearance = NSAppearance(named: .darkAqua)
      window.setContentSize(NSSize(width: 1100, height: 720))
      window.minSize = NSSize(width: 940, height: 620)
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }
}
