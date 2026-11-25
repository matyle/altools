#if DEBUG
import AltoolsCore
import AppKit
import SwiftUI

/// Debug builds only: with ALTOOLS_SELFTEST=1, exercises the real integrations
/// (CLIs, pasteboard, Vision, Carbon hotkeys, IOKit, app index, launcher flows)
/// without opening windows, prints PASS/FAIL per check, and exits non-zero on failure.
/// The user's clipboard is restored afterwards and their clipboard history is not touched.
/// Set ALTOOLS_SELFTEST_AI=0 to skip the checks that call the AI CLIs.
@MainActor
enum DebugSelfTest {
  private static var failures = 0

  static func runIfRequested() -> Bool {
    guard ProcessInfo.processInfo.environment["ALTOOLS_SELFTEST"] == "1" else { return false }
    Task { @MainActor in
      await run()
      print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
      exit(failures == 0 ? 0 : 1)
    }
    return true
  }

  private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if !ok { failures += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    fflush(stdout)
  }

  private static func info(_ name: String, _ detail: String) {
    print("INFO  \(name) — \(detail)")
    fflush(stdout)
  }

  private static func sleep(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }

  private static func run() async {
    print("Altools self-test\n")
    hotkeys()
    await launcher()
    await clipboard()
    await ocrAndAnnotation()
    environment()
    if ProcessInfo.processInfo.environment["ALTOOLS_SELFTEST_AI"] != "0" { await ai() }
  }

  // MARK: Checks

  private static func hotkeys() {
    let center = HotKeyCenter.shared
    for binding in [HotKeys.launcher, HotKeys.clipboard, HotKeys.askAI, HotKeys.captureArea, HotKeys.captureText, HotKeys.selection] {
      center.register(binding) {}
    }
    check("global hotkeys registered", center.failed.isEmpty,
          center.failed.isEmpty ? "\(center.bindings.count) shortcuts" : "taken: \(center.failed.map(\.display))")
  }

  private static func launcher() async {
    AppIndex.shared.refreshIfStale()
    for _ in 0..<40 where AppIndex.shared.apps.isEmpty { await sleep(0.1) }
    check("app index scanned", AppIndex.shared.apps.count > 20, "\(AppIndex.shared.apps.count) apps")

    let model = LauncherModel(clipboard: ClipboardStore(demoItems: []))
    model.commands = { [LauncherCommand(title: "Capture Area", keywords: "screenshot", symbol: "camera") {}] }
    model.open(in: .search)
    model.query = "safari"
    check("search ranks Safari first", model.items.first?.title == "Safari", model.items.first?.title ?? "none")
    model.query = "screensh"
    check("command keyword search", model.items.contains { $0.title == "Capture Area" })
    model.query = "2^10 + 1"
    check("calculator row", model.items.first?.title == "1025", model.items.first?.title ?? "none")
    model.query = "hello"
    model.askAI(nil)
    check("tab switches to AI mode", model.mode == .ai)
    model.runner.reset()
  }

  private static func clipboard() async {
    let pb = NSPasteboard.general
    let saved = Pasteboard.snapshot()
    defer { Pasteboard.restore(saved) }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("altools-selftest-clip.json")
    let store = ClipboardStore(fileURL: file)
    store.start()
    defer { store.stop(); try? FileManager.default.removeItem(at: file) }

    let marker = "altools-selftest-\(UUID().uuidString.prefix(8))"
    pb.clearContents()
    pb.setString(marker, forType: .string)
    await sleep(1.2)
    check("clipboard captures copied text", store.items.first?.value == marker)

    let secret = "secret-\(UUID().uuidString.prefix(6))"
    pb.clearContents()
    pb.setString(secret, forType: .string)
    pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    await sleep(1.2)
    check("clipboard skips password-manager items", !store.items.contains { $0.value == secret })

    let image = NSImage(size: NSSize(width: 40, height: 40), flipped: false) { rect in
      NSColor.systemPink.setFill(); rect.fill(); return true
    }
    pb.clearContents()
    pb.writeObjects([image])
    await sleep(1.2)
    check("clipboard captures images", store.items.first?.kind == .image)

    store.restoreToPasteboard(store.items.first { $0.value == marker }!)
    check("restoring an item puts it back on the pasteboard", pb.string(forType: .string) == marker)
    check("restored item moves to top", store.items.first?.value == marker)
  }

  private static func ocrAndAnnotation() async {
    let image = DebugRender.demoScreenshot(size: NSSize(width: 860, height: 470))
    let text: String? = await withCheckedContinuation { cont in OCR.recognize(image) { cont.resume(returning: $0) } }
    check("OCR reads text from an image", text?.contains("Quarterly Report") == true,
          text.map { "\($0.split(separator: "\n").count) lines" } ?? "nil")

    let model = AnnotationModel(image: image)
    model.marks = [Mark(tool: .rectangle, color: .red, lineWidth: 3, points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5)])]
    let output = model.rendered()
    let sameSize = output.size == image.size
    let changed = output.tiffRepresentation != image.tiffRepresentation
    check("annotation export keeps size and burns in marks", sameSize && changed, "\(output.size)")

    let saved = Pasteboard.snapshot()
    Pasteboard.copy(output)
    check("annotated image copies to pasteboard", NSImage(pasteboard: .general) != nil)
    Pasteboard.restore(saved)
  }

  private static func environment() {
    let battery = BatteryMonitor()
    battery.refresh()
    info("battery", battery.state.map { "\($0.percent)% \($0.isCharging ? "charging" : "on battery")" } ?? "no battery")
    let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    info("notch", screen.map { "notch screen found, inset \($0.safeAreaInsets.top)pt" } ?? "no notch screen; island shows on hover only")
    check("screencapture tool present", FileManager.default.isExecutableFile(atPath: "/usr/sbin/screencapture"))
    info("permission: Accessibility", Permissions.accessibilityGranted ? "granted" : "not granted (needed for selection bar + paste-back)")
    info("permission: Screen Recording", Permissions.screenRecordingGranted ? "granted" : "not granted (needed for other apps' windows)")
    let proxy = CLILocator.proxyFromShellAlias()
    check("proxy detected from claude alias", proxy != nil, proxy ?? "none")
  }

  private static func ai() async {
    let settings = AppSettings.shared
    let original = (settings.aiProvider, settings.workDirectory, settings.toolPolicy, settings.proxy)
    // Restoring writes values back; keys that were unset must end up unset again,
    // or first-launch proxy detection would think the user already chose one.
    let keys = ["aiProvider", "workDirectory", "toolPolicy", "proxy"]
    let unsetKeys = keys.filter { UserDefaults.standard.object(forKey: $0) == nil }
    defer {
      settings.aiProvider = original.0
      settings.workDirectory = original.1
      settings.toolPolicy = original.2
      settings.proxy = original.3
      unsetKeys.forEach(UserDefaults.standard.removeObject(forKey:))
    }
    settings.proxy = CLILocator.proxyFromShellAlias() ?? original.3
    settings.aiProvider = .claude
    settings.toolPolicy = .readOnly

    let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    settings.workDirectory = projectRoot.path

    let quick = AIRunner()
    quick.send("Reply with the single word: OK", mode: .quick, showPrompt: false)
    await waitFor(quick, timeout: 90)
    check("Claude quick mode answers", quick.lastAnswer.uppercased().contains("OK"), describe(quick))

    let swiftFiles = (FileManager.default.enumerator(atPath: projectRoot.appendingPathComponent("Sources").path)?
      .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }.count) ?? -1
    let agent = AIRunner()
    agent.send("Use your file tools to count the .swift files under Sources/ (recursively). Reply with only the number.", mode: .agent)
    await waitFor(agent, timeout: 180)
    let usedTool = agent.entries.contains { $0.kind == .tool }
    check("Claude agent mode uses tools", usedTool, agent.entries.filter { $0.kind == .tool }.map(\.content).joined(separator: " | "))
    check("Claude agent answer is correct", agent.lastAnswer.contains("\(swiftFiles)"), "expected \(swiftFiles), got “\(agent.lastAnswer.prefix(80))”")

    agent.send("What number did you just give me? Reply with only the number.", mode: .agent)
    await waitFor(agent, timeout: 120)
    check("follow-up resumes the same session", agent.lastAnswer.contains("\(swiftFiles)"), "got “\(agent.lastAnswer.prefix(80))”")

    let readOnlyProbe = AIRunner()
    let probeFile = projectRoot.appendingPathComponent("build/selftest-should-not-exist.txt")
    readOnlyProbe.send("Create the file build/selftest-should-not-exist.txt containing hi. If you cannot, say CANNOT.", mode: .agent)
    await waitFor(readOnlyProbe, timeout: 120)
    check("read-only policy blocks file writes", !FileManager.default.fileExists(atPath: probeFile.path))
    try? FileManager.default.removeItem(at: probeFile)

    settings.aiProvider = .codex
    let codex = AIRunner()
    codex.send("Reply with the single word: OK", mode: .quick, showPrompt: false)
    await waitFor(codex, timeout: 120)
    let codexOK = codex.lastAnswer.uppercased().contains("OK")
    let codexError = codex.entries.first { $0.kind == .error }?.content
    check("Codex answers or reports a readable error", codexOK || codexError != nil,
          codexOK ? "answered" : "error shown: \(codexError?.prefix(120) ?? "none")")
  }

  private static func waitFor(_ runner: AIRunner, timeout: Double) async {
    await sleep(0.3)
    let deadline = Date().addingTimeInterval(timeout)
    while runner.isRunning, Date() < deadline { await sleep(0.2) }
    await sleep(0.3) // let the final events land
    if runner.isRunning { runner.cancel() }
  }

  private static func describe(_ runner: AIRunner) -> String {
    if let error = runner.entries.first(where: { $0.kind == .error }) { return "error: \(error.content.prefix(160))" }
    return "“\(runner.lastAnswer.prefix(60))”"
  }
}
#endif
