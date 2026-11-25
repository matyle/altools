import AltoolsCore
import AppKit
import ApplicationServices

/// End-to-end check on the real desktop, started with `open altools://selftest`.
///
/// Takes over keyboard and mouse for about half a minute: types into the launcher,
/// hovers the notch, selects text in a TextEdit document it creates, runs the
/// selection bar (transform, paste-back, AI translate), and captures the screen
/// into the annotation editor. Screenshots of the real windows and `report.txt`
/// go to ~/Library/Application Support/Altools/selftest. The temporary document
/// is closed and deleted afterwards.
@MainActor
final class LiveSelfTest {
  private static var running: LiveSelfTest?

  private let launcher: LauncherController
  private let notch: NotchController
  private let selection: SelectionController
  private let capture: CaptureController
  private let out = AppPaths.subdirectory("selftest")
  private var report: [String] = []
  private var failures = 0

  init(launcher: LauncherController, notch: NotchController, selection: SelectionController, capture: CaptureController) {
    self.launcher = launcher
    self.notch = notch
    self.selection = selection
    self.capture = capture
  }

  /// `only` limits the run to one flow ("launcher", "notch", "selection", "capture").
  func run(only: String? = nil) {
    guard Self.running == nil else { return }
    Self.running = self
    try? FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil)
      .forEach { try? FileManager.default.removeItem(at: $0) }
    Task { @MainActor in
      // Wait up to 15 minutes for both grants, then warn before taking over input.
      let deadline = Date().addingTimeInterval(900)
      if !(Permissions.accessibilityGranted && Permissions.screenRecordingGranted) {
        Toast.show("Self-test waits for Accessibility + Screen Recording", symbol: "lock.shield", duration: 4)
        // The system prompts add this exact build to both lists, so the user only flips the switch.
        if !Permissions.accessibilityGranted { Permissions.requestAccessibility() }
        if !Permissions.screenRecordingGranted { Permissions.requestScreenRecording() }
      }
      while !(Permissions.accessibilityGranted && Permissions.screenRecordingGranted), Date() < deadline {
        await wait(2)
      }
      await permissions()
      guard failures == 0 else {
        report.append("\nSTOPPED: permissions were not granted within 15 minutes")
        try? report.joined(separator: "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        Self.running = nil
        return
      }
      for remaining in stride(from: 5, through: 1, by: -1) {
        Toast.show("Altools self-test starts in \(remaining)s — hands off keyboard and mouse", symbol: "hand.raised.fill", duration: 1.2)
        await wait(1)
      }
      let mouse = NSEvent.mouseLocation
      if only == nil || only == "launcher" { await launcherFlow() }
      if only == nil || only == "notch" { await notchFlow() }
      if only == nil || only == "selection" { await selectionFlow() }
      if only == nil || only == "capture" { await captureFlow() }
      if only == "cards" { await cardsFlow() }
      if only == "menubar" { await menuBarFlow() }
      if only == "hider" {
        // A new status item lands at the far left: left of both dividers, so it should hide.
        let probe = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        probe.button?.title = "PROBE"
        let app = NSApp.delegate as? AppDelegate
        app?.toggleMenuBarHider()  // reveal, then collapse, so the dividers re-measure with the probe present
        await wait(0.8)
        app?.toggleMenuBarHider()
        await wait(1.2)
        func probeOnScreen() -> Bool {
          guard let frame = probe.button?.window?.frame else { return false }
          return NSScreen.screens.contains { $0.frame.intersects(frame) } && probe.button?.window?.occlusionState.contains(.visible) == true
        }
        report.append("INFO  collapsed: probe=\(probe.button?.window.map { NSStringFromRect($0.frame) } ?? "none") \(app?.menuBarHiderFrames ?? "")")
        await runProcess("/usr/sbin/screencapture", ["-x", "-R", "0,0,1920,34", out.appendingPathComponent("15-hider-collapsed.png").path])
        let hiddenWhenCollapsed = !probeOnScreen()
        app?.toggleMenuBarHider()
        await wait(1.0)
        await runProcess("/usr/sbin/screencapture", ["-x", "-R", "0,0,1920,34", out.appendingPathComponent("16-hider-revealed.png").path])
        report.append("INFO  revealed: probe=\(probe.button?.window.map { NSStringFromRect($0.frame) } ?? "none")")
        check("hidden icons disappear when collapsed", hiddenWhenCollapsed)
        app?.toggleMenuBarHider()
        await wait(0.5)
        NSStatusBar.system.removeStatusItem(probe)
      }
      if only == "widgets" {
        for kind in WidgetsController.Kind.allCases {
          (NSApp.delegate as? AppDelegate)?.toggleWidget(kind)
          await wait(kind == .system ? 2.5 : 1.0)
          let panel = NSApp.windows.first { $0.level == .popUpMenu && $0.isVisible }
          report.append("INFO  \(kind.rawValue) panel: \(panel.map { NSStringFromRect($0.frame) } ?? "not found")")
          await shot(panel, "17-widget-\(kind.rawValue)")
          (NSApp.delegate as? AppDelegate)?.toggleWidget(kind)
          await wait(0.3)
        }
        let height = Int((NSScreen.screens.first?.frame.maxY ?? 0) - (NSScreen.screens.first?.visibleFrame.maxY ?? 0))
        await runProcess("/usr/sbin/screencapture", ["-x", "-R", "1000,0,920,\(max(height, 24))", out.appendingPathComponent("18-widgets-menubar.png").path])
      }
      if only == "status" {
        (NSApp.delegate as? AppDelegate)?.toggleStatusPanel()
        await wait(0.8)
        let panel = NSApp.windows.first { $0.level == .popUpMenu && $0.isVisible }
        report.append("INFO  status panel: \(panel.map { NSStringFromRect($0.frame) } ?? "not found")")
        await shot(panel, "14-status-panel")
        (NSApp.delegate as? AppDelegate)?.toggleStatusPanel()
      }
      moveMouse(to: mouse)
      report.append(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
      try? report.joined(separator: "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
      Toast.show(failures == 0 ? "Self-test passed" : "Self-test: \(failures) failed",
                 symbol: failures == 0 ? "checkmark.seal.fill" : "xmark.octagon.fill", duration: 3)
      Self.running = nil
    }
  }

  // MARK: Flows

  private func permissions() async {
    check("Accessibility granted", Permissions.accessibilityGranted)
    check("Screen Recording granted", Permissions.screenRecordingGranted)
  }

  private func launcherFlow() async {
    launcher.show(.search)
    await wait(0.6)
    type("saf")
    await wait(0.6)
    check("typing reaches the launcher field", launcher.model.query == "saf", "query=\(launcher.model.query)")
    check("Safari is the top result", launcher.model.items.first?.title == "Safari", launcher.model.items.first?.title ?? "none")
    await shot(launcher.window, "1-launcher-search")
    key(125) // ↓
    await wait(0.2)
    check("arrow keys move the selection", launcher.model.selection == 1)
    key(53) // esc clears the query
    await wait(0.3)
    type("12*7")
    await wait(0.5)
    check("calculator answers 12*7", launcher.model.items.first?.title == "84", launcher.model.items.first?.title ?? "none")
    await shot(launcher.window, "2-launcher-calc")
    launcher.show(.clipboard)
    await wait(0.1)
    let shownAt = launcher.isVisible
    await wait(0.5)
    check("clipboard view stays open", launcher.isVisible,
          "visible after 0.1s=\(shownAt), hidden by=\(launcher.lastHideReason ?? "-")")
    await shot(launcher.window, "3-launcher-clipboard")
    launcher.showAI()
    await wait(0.6)
    await shot(launcher.window, "4-launcher-ai")
    launcher.hide()
    await wait(0.3)
  }

  private func notchFlow() async {
    for (index, screen) in NSScreen.screens.enumerated() {
      let name = screen.localizedName
      moveMouse(to: NSPoint(x: screen.frame.midX, y: screen.frame.midY))
      await wait(0.4)
      moveMouse(to: NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 6))
      await wait(1.0)
      check("hovering the notch opens the panel on \(name)", notch.model.expanded)
      await shot(notch.window, "5-notch-open-\(index)")
      moveMouse(to: NSPoint(x: screen.frame.midX, y: screen.frame.midY))
      await wait(1.0)
      check("moving away closes the panel on \(name)", !notch.model.expanded,
            "pinned=\(notch.model.pinned) key=\(notch.window?.isKeyWindow == true) mouse=\(NSStringFromPoint(NSEvent.mouseLocation))")
      await shot(notch.window, "5-notch-closed-\(index)")
    }
  }

  /// Another app's banner shows in the notch; a volume change shows the volume bar.
  private func cardsFlow() async {
    await runProcess("/usr/bin/osascript", ["-e", "display notification \"Lunch is ready\" with title \"Altools card test\""])
    var shown: NotificationWatcher.Banner?
    for _ in 0..<10 {
      await wait(0.5)
      if case .notification(let banner) = notch.model.card { shown = banner; break }
    }
    check("app notification drops down from the notch", shown?.title == "Altools card test",
          shown.map { "\($0.appName): \($0.title) — \($0.body)" } ?? "no card")
    await shot(notch.window, "10-notch-notification")
    notch.dismissCard()
    await wait(0.6)

    // HDMI / DisplayPort outputs have no software volume; there is nothing to show then.
    let probe = NSAppleScript(source: "output volume of (get volume settings)")?.executeAndReturnError(nil)
    guard probe?.descriptorType != typeType, probe?.stringValue != "missing value", probe?.int32Value != 0 || probe?.stringValue == "0" else {
      report.append("SKIP  volume: the current output has no volume control")
      return
    }
    let script = "set v to output volume of (get volume settings)\nset volume output volume (v - 1)\ndelay 0.4\nset volume output volume v"
    let volumeTask = Task { await runProcess("/usr/bin/osascript", ["-e", script]) }
    var sawVolume = false
    for _ in 0..<30 {
      await wait(0.1)
      if case .flash(let flash) = notch.model.activity, case .volume = flash.kind { sawVolume = true; break }
    }
    check("volume change shows in the notch", sawVolume)
    await shot(notch.window, "11-notch-volume")
    await volumeTask.value
  }

  /// Screenshots the menu bar collapsed and revealed; the hider is reached through the app delegate.
  private func menuBarFlow() async {
    guard let screen = NSScreen.screens.first else { return }
    let height = Int(screen.frame.maxY - screen.visibleFrame.maxY)
    let region = "0,0,\(Int(screen.frame.width)),\(max(height, 24))"
    await runProcess("/usr/sbin/screencapture", ["-x", "-R", region, out.appendingPathComponent("12-menubar-collapsed.png").path])
    (NSApp.delegate as? AppDelegate)?.toggleMenuBarHider()
    await wait(0.6)
    await runProcess("/usr/sbin/screencapture", ["-x", "-R", region, out.appendingPathComponent("13-menubar-revealed.png").path])
    (NSApp.delegate as? AppDelegate)?.toggleMenuBarHider()
    report.append("INFO  \((NSApp.delegate as? AppDelegate)?.menuBarHiderFrames ?? "")")
    report.append("INFO  screens: " + NSScreen.screens.map { "\($0.localizedName) \(NSStringFromRect($0.frame))" }.joined(separator: "; "))
    check("menu bar screenshots taken", FileManager.default.fileExists(atPath: out.appendingPathComponent("13-menubar-revealed.png").path))
  }

  private func selectionFlow() async {
    let original = "Altools live test: the quick brown fox naps in the sun."
    let file = out.appendingPathComponent("sample.txt")
    try? original.write(to: file, atomically: true, encoding: .utf8)
    guard let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else {
      check("TextEdit available", false)
      return
    }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    _ = try? await NSWorkspace.shared.open([file], withApplicationAt: textEdit, configuration: config)
    await wait(2.5)
    defer { try? FileManager.default.removeItem(at: file) }

    key(0, flags: .maskCommand) // ⌘A
    await wait(0.4)
    let selected = SelectionReader.readViaAccessibility()
    check("reads selected text from another app", selected == original, selected.map { "“\($0.prefix(40))”" } ?? "nil")

    selection.triggerFromHotkey()
    await wait(0.6)
    check("action bar appears over the selection", selection.bar.isVisible)
    await shot(selection.bar, "6-selection-bar")

    selection.runTransform(.uppercase)
    await wait(0.6)
    await shot(selection.resultPanel, "7-selection-result")
    selection.replaceSelection()
    await wait(1.2)
    let replaced = focusedValue()
    check("Replace pastes the result back into TextEdit", replaced == original.uppercased(), replaced.map { "“\($0.prefix(40))”" } ?? "nil")

    key(0, flags: .maskCommand)
    await wait(0.4)
    selection.triggerFromHotkey()
    await wait(0.5)
    selection.runAI(.translate)
    let deadline = Date().addingTimeInterval(90)
    await wait(0.5)
    while selection.runner.isRunning, Date() < deadline { await wait(0.3) }
    await wait(0.4)
    let answer = selection.runner.lastAnswer
    check("AI translate answers", TextTransform.isMostlyCJK(answer), "“\(answer.prefix(40))”")
    await shot(selection.resultPanel, "8-selection-translate")
    selection.closeResult()

    // Close the document; it is a scratch file, so discard the edit.
    key(13, flags: .maskCommand) // ⌘W
    await wait(0.8)
    key(2, flags: .maskCommand)  // ⌘D = "Don't Save" in the sheet, if one appears
    await wait(0.5)
  }

  private func captureFlow() async {
    let file = out.appendingPathComponent("capture-raw.png")
    let frame = (NSScreen.main ?? NSScreen.screens[0]).frame
    let region = "0,0,\(Int(min(1000, frame.width))),\(Int(min(620, frame.height)))"
    await runProcess("/usr/sbin/screencapture", ["-x", "-R", region, file.path])
    guard let image = NSImage(contentsOf: file) else {
      check("screen capture works", false)
      return
    }
    check("screen capture works", true, "\(Int(image.size.width))×\(Int(image.size.height))")
    capture.openEditor(image)
    await wait(1.0)
    await shot(capture.editors.last?.window, "9-capture-editor")
    capture.editors.last?.close()
    try? FileManager.default.removeItem(at: file)
  }

  // MARK: Helpers

  private func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if !ok { failures += 1 }
    report.append("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
  }

  private func wait(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }

  /// Captures the real on-screen window (with its blur and shadow) by window number.
  private func shot(_ window: NSWindow?, _ name: String) async {
    guard let window, window.isVisible else {
      report.append("INFO  no window for screenshot \(name)")
      return
    }
    await runProcess("/usr/sbin/screencapture", ["-x", "-l", "\(window.windowNumber)", out.appendingPathComponent("\(name).png").path])
  }

  private func runProcess(_ path: String, _ args: [String]) async {
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      let p = Process()
      p.executableURL = URL(fileURLWithPath: path)
      p.arguments = args
      p.terminationHandler = { _ in cont.resume() }
      do { try p.run() } catch { cont.resume() }
    }
  }

  private func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
      event?.flags = flags
      event?.post(tap: .cghidEventTap)
    }
  }

  private func type(_ text: String) {
    let source = CGEventSource(stateID: .combinedSessionState)
    for scalar in text.utf16 {
      for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
        var char = scalar
        event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
        event?.post(tap: .cghidEventTap)
      }
    }
  }

  /// `point` is in AppKit screen coordinates (origin bottom-left of the main screen).
  private func moveMouse(to point: NSPoint) {
    let mainHeight = NSScreen.screens[0].frame.height
    let cgPoint = CGPoint(x: point.x, y: mainHeight - point.y)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left)?
      .post(tap: .cghidEventTap)
  }

  private func focusedValue() -> String? {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
    var value: CFTypeRef?
    // swiftlint:disable:next force_cast
    AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &value)
    return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
