#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: with ALTOOLS_RENDER_DIR set, renders each UI surface with demo
/// data into PNGs in that folder, then quits. Windows are placed far off-screen and
/// never activated, and nothing else in the app starts (no hotkeys, menu bar item,
/// clipboard polling), so this does not disturb the desktop. Materials render without
/// blur because there is nothing behind them, so a gradient backdrop stands in.
enum DebugRender {
  static func runIfRequested() -> Bool {
    guard let dir = ProcessInfo.processInfo.environment["ALTOOLS_RENDER_DIR"] else { return false }
    let out = URL(fileURLWithPath: dir)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let dark = ProcessInfo.processInfo.environment["ALTOOLS_RENDER_LIGHT"] == nil
    NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    AppIndex.shared.refreshIfStale()

    let scenes = makeScenes()
    var delay = 1.0
    for (name, size, view) in scenes {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        render(view, size: size, to: out.appendingPathComponent("\(name).png"))
      }
      delay += 0.9
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) { NSApp.terminate(nil) }
    return true
  }

  private static func makeScenes() -> [(String, CGSize, () -> AnyView)] {
    let clips = demoClips()
    func launcher(_ setup: @escaping (LauncherModel) -> Void) -> () -> AnyView {
      {
        let model = LauncherModel(clipboard: ClipboardStore(demoItems: clips))
        model.commands = { demoCommands }
        setup(model)
        return AnyView(LauncherView(model: model))
      }
    }
    let launcherSize = LauncherLayout.size
    func notch(_ tab: NotchModel.Tab?, _ setup: @escaping (NotchModel) -> Void = { _ in }) -> () -> AnyView {
      {
        let model = NotchModel()
        model.hasNotch = true
        model.notchSize = CGSize(width: 190, height: 32)
        model.nowPlaying.loadDemo(.init(bundleID: "com.apple.Music", title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
                                        isPlaying: true, position: 98, duration: 243))
        model.reminders.loadDemo()
        model.usage.loadDemo()
        model.markets.loadDemo()
        if let tab { model.tab = tab; model.expanded = true }
        setup(model)
        return AnyView(NotchView(model: model, actions: NotchActions()))
      }
    }
    return [
      ("1-launcher-home", launcherSize, launcher { $0.open(in: .search) }),
      ("2-launcher-search", launcherSize, launcher { $0.open(in: .search); $0.query = "term" }),
      ("3-launcher-calc", launcherSize, launcher { $0.open(in: .search); $0.query = "1280*0.85+12^2" }),
      ("4-launcher-clipboard", launcherSize, launcher { $0.open(in: .clipboard); $0.selection = 1 }),
      ("5-launcher-ai-empty", launcherSize, launcher { $0.open(in: .ai) }),
      ("6-launcher-ai-answer", launcherSize, launcher { model in
        model.open(in: .ai)
        model.runner.loadDemo(demoTranscript)
      }),
      ("7-selection-bar", CGSize(width: 620, height: 60), {
        AnyView(SelectionBar(onCopy: {}, onSearch: {}, onAI: { _ in }, onAsk: {}, onTransform: { _ in }))
      }),
      ("8-selection-result", SelectionResultView.size, {
        let model = SelectionResultModel()
        model.mode = .ai
        model.aiAction = .translate
        model.canReplace = true
        model.source = "The quick brown fox jumps over the lazy dog, then naps in the warm afternoon sun."
        let runner = AIRunner()
        runner.loadDemo([(.text, "敏捷的棕色狐狸跳过了那只懒狗，然后在温暖的午后阳光下打了个盹。")])
        return AnyView(SelectionResultView(model: model, runner: runner, onSwitch: { _ in }, onCopy: {}, onReplace: {}, onClose: {}))
      }),
      ("9-notch-home", CGSize(width: 760, height: 320), notch(.home)),
      ("10-notch-media", CGSize(width: 760, height: 320), notch(.media)),
      ("10b-notch-todo", CGSize(width: 760, height: 320), notch(.todo)),
      ("10c-notch-notes", CGSize(width: 760, height: 320), notch(.notes)),
      ("10d-notch-shelf", CGSize(width: 760, height: 320), notch(.shelf)),
      ("10e-notch-usage", CGSize(width: 760, height: 320), notch(.usage)),
      ("10f-notch-markets", CGSize(width: 760, height: 320), notch(.markets)),
      ("11-notch-collapsed-playing", CGSize(width: 680, height: 80), notch(nil)),
      ("11b-notch-collapsed-meeting", CGSize(width: 680, height: 80), notch(nil) { $0.nowPlaying.loadDemo(.init(bundleID: "", title: "", artist: "", isPlaying: false, position: 0, duration: 0)) ; $0.reminders.loadDemo() }),
      ("11c-notch-collapsed-receipt", CGSize(width: 680, height: 80), notch(nil) { $0.loadDemoFlash(.receipt(.init(symbol: "eyedropper", title: "Copied #FF6B35", color: .orange))) }),
      ("11e-notch-volume", CGSize(width: 680, height: 80), notch(nil) { $0.loadDemoFlash(.volume(.init(volume: 0.62, muted: false, deviceName: "AirPods Pro", isHeadphones: true))) }),
      ("11f-notch-card-meeting", CGSize(width: 680, height: 140), notch(nil) { $0.card = .meeting(.init(id: "m", title: "Design sync", start: Date().addingTimeInterval(272), end: Date().addingTimeInterval(2000), color: .green, joinURL: URL(string: "https://acme.zoom.us/j/123456?pwd=x")), startingNow: false) }),
      ("11g-notch-card-notification", CGSize(width: 680, height: 140), notch(nil) { $0.card = .notification(.init(appName: "Messages", bundleID: "com.apple.MobileSMS", title: "Leo", body: "Are we still on for lunch? I booked the place near the office.")) }),
      ("11h-notch-card-agent", CGSize(width: 680, height: 140), notch(nil) {
        $0.card = .agent(.init(id: "1", kind: "approval", name: "api-server refactor", summary: "Run `swift test --filter Router` to check the new routes?",
                                harness: "claude-code", session: "work", window: "demo", since: Date()))
      }),
      ("11d-notch-collapsed-caps", CGSize(width: 680, height: 80), notch(nil) { $0.loadDemoFlash(.input(symbol: "capslock.fill", label: "Caps Lock")) }),
      ("20-settings-overview", CGSize(width: 1100, height: 720), { AnyView(SettingsRoot(actions: SettingsActions())) }),
      ("21-settings-notch", CGSize(width: 1100, height: 720), { AnyView(SettingsRoot(actions: SettingsActions(), page: .module("notch"))) }),
      ("22-settings-menubar", CGSize(width: 1100, height: 720), { AnyView(SettingsRoot(actions: SettingsActions(), page: .module("menubar"))) }),
      ("23-settings-permissions", CGSize(width: 1100, height: 720), { AnyView(SettingsRoot(actions: SettingsActions(), page: .permissions)) }),
      ("24-settings-ai", CGSize(width: 1100, height: 720), { AnyView(SettingsRoot(actions: SettingsActions(), page: .ai)) }),
      ("12-annotate", CGSize(width: 900, height: 560), {
        let image = demoScreenshot(size: NSSize(width: 860, height: 470))
        let model = AnnotationModel(image: image)
        model.marks = [
          Mark(tool: .rectangle, color: .red, lineWidth: 3, points: [CGPoint(x: 0.06, y: 0.12), CGPoint(x: 0.5, y: 0.42)]),
          Mark(tool: .arrow, color: .red, lineWidth: 3, points: [CGPoint(x: 0.75, y: 0.75), CGPoint(x: 0.53, y: 0.4)]),
          Mark(tool: .highlight, color: .yellow, lineWidth: 3, points: [CGPoint(x: 0.06, y: 0.55), CGPoint(x: 0.45, y: 0.65)]),
          Mark(tool: .text, color: .red, lineWidth: 3, points: [CGPoint(x: 0.62, y: 0.78)], text: "Fix this padding"),
        ]
        return AnyView(AnnotationView(model: model, onCopy: {}, onSave: {}, onPin: {}, onOCR: {}, onClose: {}))
      }),
    ]
  }

  private static func render(_ makeView: () -> AnyView, size: CGSize, to url: URL) {
    let backdrop = ZStack {
      LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.36), Color(red: 0.42, green: 0.22, blue: 0.4)],
                     startPoint: .topLeading, endPoint: .bottomTrailing)
      makeView()
    }
    .frame(width: size.width + 48, height: size.height + 48)
    let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: size.width + 48, height: size.height + 48),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: backdrop)
    window.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
      view.cacheDisplay(in: view.bounds, to: rep)
      try? rep.representation(using: .png, properties: [:])?.write(to: url)
      window.orderOut(nil)
    }
  }

  static func demoScreenshot(size: NSSize) -> NSImage {
    NSImage(size: size, flipped: true) { rect in
      NSColor(white: 0.97, alpha: 1).setFill()
      rect.fill()
      NSColor(white: 0.9, alpha: 1).setFill()
      NSRect(x: 0, y: 0, width: rect.width, height: 44).fill()
      let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .bold), .foregroundColor: NSColor.black]
      let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.darkGray]
      "Quarterly Report".draw(at: NSPoint(x: 60, y: 80), withAttributes: title)
      "Revenue grew 18% while costs stayed flat.".draw(at: NSPoint(x: 60, y: 130), withAttributes: body)
      "Next steps: hire two engineers, ship v2.".draw(at: NSPoint(x: 60, y: 270), withAttributes: body)
      NSColor.systemBlue.setFill()
      NSBezierPath(roundedRect: NSRect(x: 520, y: 90, width: 260, height: 150), xRadius: 12, yRadius: 12).fill()
      return true
    }
  }

  private static let demoCommands: [LauncherCommand] = [
    LauncherCommand(title: "Ask AI", keywords: "claude codex chat", symbol: "sparkles", tint: .purple) {},
    LauncherCommand(title: "Clipboard History", keywords: "paste copy", symbol: "doc.on.clipboard", tint: .teal) {},
    LauncherCommand(title: "Capture Area", keywords: "screenshot snap", symbol: "camera.viewfinder", tint: .blue) {},
    LauncherCommand(title: "Capture Text (OCR)", keywords: "screenshot recognize", symbol: "text.viewfinder", tint: .indigo) {},
    LauncherCommand(title: "Capture and Pin", keywords: "screenshot float", symbol: "pin.fill", tint: .red) {},
    LauncherCommand(title: "Altools Settings", keywords: "preferences", symbol: "gearshape.fill", tint: .gray) {},
  ]

  private static func demoClips() -> [ClipboardStore.Item] {
    let now = Date()
    return [
      .init(kind: .text, value: "https://developer.apple.com/documentation/screencapturekit", date: now.addingTimeInterval(-40), sourceApp: "Safari"),
      .init(kind: .text, value: "func greet(name: String) -> String {\n  \"Hello, \\(name)!\"\n}\n\nprint(greet(name: \"Altools\"))", date: now.addingTimeInterval(-300), sourceApp: "Xcode"),
      .init(kind: .text, value: "Meeting moved to Thursday 3pm — room 4B. Bring the Q4 numbers.", date: now.addingTimeInterval(-3600), sourceApp: "Slack"),
      .init(kind: .text, value: "terminal-notifier -title Build -message Done", date: now.addingTimeInterval(-7200), sourceApp: "Terminal"),
      .init(kind: .text, value: "{\"status\":\"ok\",\"items\":[1,2,3]}", date: now.addingTimeInterval(-86_400), sourceApp: "Postman"),
    ]
  }

  private static let demoTranscript: [(AIRunner.Entry.Kind, String)] = [
    (.user, "Which processes use the most memory right now?"),
    (.tool, "Bash  ps -axo pid,rss,comm -m | head -6"),
    (.tool, "Bash  vm_stat"),
    (.text, """
    ## Top memory users

    1. **Xcode** — 3.1 GB, mostly indexing
    2. **Safari** — 1.8 GB across 24 tabs
    3. **Docker (OrbStack)** — 1.2 GB

    You still have about **6 GB free**, so nothing is under pressure. To trim Safari:

    ```bash
    killall -HUP "Safari Web Content"
    ```
    """),
  ]
}
#endif
