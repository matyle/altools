import AppKit

/// Agents in tuios panes waiting for the person: blocked on an approval, a plan, a question
/// or an error, or done with a turn nobody has looked at yet. Read from tuios's Inbox
/// (`tuios list-attention`); a finished item closes when its pane is focused.
///
/// `tuios subscribe --types attention` signals every Inbox change; each one triggers a
/// fresh read of the list, so a missed or unparsed event costs nothing. When the daemon
/// isn't running the stream exits and is retried every 10 s.
final class AgentInbox: ObservableObject {
  struct Item: Identifiable, Equatable {
    let id: String
    let kind: String
    let name: String
    let summary: String
    let harness: String?
    let session: String
    let window: String
    let since: Date

    var title: String {
      switch kind {
      case "approval": "Needs approval"
      case "plan": "Plan to review"
      case "ask", "question": "Has a question"
      case "errored": "Stopped with an error"
      case "finished": "Finished"
      default: kind.capitalized
      }
    }

    var symbol: String {
      switch kind {
      case "approval": "hand.raised.fill"
      case "plan": "list.bullet.clipboard.fill"
      case "errored": "exclamationmark.triangle.fill"
      case "finished": "checkmark.circle.fill"
      default: "questionmark.bubble.fill"
      }
    }

    /// The agent can't go on without the person; a finished turn can wait.
    var isBlocking: Bool { kind != "finished" }
  }

  /// Blocking items first, each group oldest first.
  @Published private(set) var items: [Item] = []
  /// Called on the main queue for each item that wasn't in the previous read.
  var onNew: (Item) -> Void = { _ in }

  private static let kinds = ["approval", "plan", "ask", "question", "errored", "finished"]
  private var stream: Process?
  private var running = false
  private var refreshWork: DispatchWorkItem?
  private var known: Set<String> = []
  /// Items the person clicked; hidden here even while tuios keeps them open (an unanswered
  /// question stays in its Inbox until answered). Kept until tuios closes the item.
  private var dismissed: Set<String> = []
  private var lastRead: [Item] = []

  static let shared = AgentInbox()
  private var primed = false

  static var executable: URL? {
    ["/opt/homebrew/bin/tuios", "/usr/local/bin/tuios", NSHomeDirectory() + "/.local/bin/tuios", NSHomeDirectory() + "/go/bin/tuios"]
      .first { FileManager.default.isExecutableFile(atPath: $0) }
      .map(URL.init(fileURLWithPath:))
  }

  func start() {
    guard !running else { return }
    running = true
    Self.killOrphanedStreams()
    subscribe()
    refresh()
  }

  func stop() {
    running = false
    refreshWork?.cancel()
    stream?.terminationHandler = nil
    stream?.terminate()
    stream = nil
    items = []
    known = []
    primed = false
  }

  /// Brings the pane to the front: tuios switches to its workspace, then the terminal
  /// app attached to that session is activated.
  static func open(_ item: Item) {
    shared.dismiss(item)
    guard let tuios = executable else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      _ = run(tuios, ["focus-window", item.window, "-s", item.session])
      let app = terminalApp(for: item.session, tuios: tuios)
      DispatchQueue.main.async { app?.activate() }
    }
  }

  /// Streams left by an Altools that was killed rather than quit; launchd adopted them.
  private static func killOrphanedStreams() {
    let pkill = Process()
    pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    pkill.arguments = ["-P", "1", "-f", "tuios subscribe --types attention"]
    try? pkill.run()
    pkill.waitUntilExit()
  }

  private func subscribe() {
    guard running, let tuios = Self.executable else { return }
    let process = Process()
    process.executableURL = tuios
    process.arguments = ["subscribe", "--types", "attention"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      guard !handle.availableData.isEmpty else { return }
      DispatchQueue.main.async { self?.scheduleRefresh() }
    }
    process.terminationHandler = { [weak self] _ in
      pipe.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        guard let self, self.running else { return }
        self.subscribe()
        self.refresh()
      }
    }
    do {
      try process.run()
      stream = process
    } catch {
      NSLog("Altools: tuios subscribe failed: \(error)")
    }
  }

  /// Events come in bursts (an item opens, its pane changes state); one read covers them.
  private func scheduleRefresh() {
    refreshWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.refresh() }
    refreshWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }

  private func refresh() {
    guard running, let tuios = Self.executable else { return }
    let arguments = ["list-attention", "--json", "--host", "local"] + Self.kinds.flatMap { ["--kind", $0] }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let output = Self.run(tuios, arguments) else { return }
      let items = Self.parse(output)
      DispatchQueue.main.async { self?.update(items) }
    }
  }

  private func dismiss(_ item: Item) {
    dismissed.insert(item.id)
    update(lastRead)
  }

  private func update(_ read: [Item]) {
    guard running else { return }
    lastRead = read
    dismissed.formIntersection(read.map(\.id))
    let open = read.filter { !dismissed.contains($0.id) }
    let fresh = open.filter(\.isBlocking) + open.filter { !$0.isBlocking }
    // Items already open when Altools starts are listed on Home, not announced with a card each.
    if primed {
      fresh.filter { !known.contains($0.id) }.forEach(onNew)
    }
    primed = true
    known = Set(read.map(\.id))
    if fresh != items { items = fresh }
  }

  static func parse(_ data: Data) -> [Item] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = root["items"] as? [[String: Any]] else { return [] }
    return rows.compactMap { row in
      guard let id = row["id"] as? String, let kind = row["kind"] as? String,
            let window = row["window"] as? String, let session = row["session"] as? String else { return nil }
      // `since` is Unix time in nanoseconds.
      let since = (row["since"] as? Double).map { Date(timeIntervalSince1970: $0 / 1e9) } ?? Date()
      return Item(id: id, kind: kind, name: row["name"] as? String ?? "Agent", summary: row["summary"] as? String ?? "",
                  harness: row["harness"] as? String, session: session, window: window, since: since)
    }
  }

  /// Output of a short tuios command, or nil when it fails or runs past 5 s.
  private static func run(_ tuios: URL, _ arguments: [String]) -> Data? {
    let process = Process()
    process.executableURL = tuios
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: deadline)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    deadline.cancel()
    return process.terminationStatus == 0 ? data : nil
  }

  /// The GUI app whose process tree holds the tuios client attached to `session`.
  private static func terminalApp(for session: String, tuios: URL) -> NSRunningApplication? {
    guard let data = run(tuios, ["list-clients", "--json"]),
          let clients = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
    let pids = clients.filter { ($0["session"] as? String) == session }.compactMap { $0["pid"] as? Int }
    for pid in pids {
      var current = pid_t(pid)
      while current > 1 {
        if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
        current = parent(of: current)
      }
    }
    return nil
  }

  private static func parent(of pid: pid_t) -> pid_t {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
    return info.kp_eproc.e_ppid
  }
}
