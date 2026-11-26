import AltoolsCore
import AppKit

/// Finds the plugins in Application Support/Altools/Plugins, runs the enabled ones on their
/// schedule and keeps what each last printed. The contract (manifest, environment, output)
/// is in AltoolsCore and PLUGINS.md.
///
/// Plugins are arbitrary programs running as the user, so one found on disk starts disabled
/// until the user switches it on in Settings. Built-in plugins ship inside the app bundle
/// (Resources/BuiltinPlugins), start enabled and can be switched off but not removed; a user
/// plugin with the same id replaces the built-in one.
final class PluginHost: ObservableObject {
  struct Plugin: Identifiable {
    /// The folder name; equals manifest.id for a valid plugin.
    let id: String
    let folder: URL
    var manifest: PluginManifest?
    /// Why the plugin can't run at all (bad manifest, missing script); found on reload.
    var problem: String?
    /// Why the last run failed; cleared by the next successful run.
    var runError: String?
    var output: PluginOutput?
    var lastRun: Date?
    var running = false
    var enabled = false
    /// Shipped with Altools rather than installed by the user.
    var builtin = false
    /// Recent stderr and run outcomes, newest last.
    var log = ""

    var name: String { manifest?.name ?? id }
    var error: String? { problem ?? runError }
    func shows(_ slot: PluginSlot) -> Bool { enabled && error == nil && manifest?.slots.contains(slot) == true }
  }

  static let shared = PluginHost()
  static var folder: URL { AppPaths.subdirectory("Plugins") }
  static var builtinFolder: URL? {
    #if DEBUG
    // An unbundled debug run has no Resources; the runtime test points here instead.
    if let path = ProcessInfo.processInfo.environment["ALTOOLS_BUILTIN_PLUGINS"] { return URL(fileURLWithPath: path) }
    #endif
    return Bundle.main.url(forResource: "BuiltinPlugins", withExtension: nil)
  }

  @Published private(set) var plugins: [Plugin] = []
  /// Called on the main queue for each alert id a plugin hasn't announced before.
  var onAlert: (PluginOutput.Alert, Plugin) -> Void = { _, _ in }

  private var timers: [String: Timer] = [:]
  /// Running stream-mode plugins, their stdin, and the delay before the next restart.
  private var streams: [String: (process: Process, input: FileHandle)] = [:]
  private var streamDelay: [String: TimeInterval] = [:]
  private var pending: [String: [PluginEvent]] = [:]
  private var watcher: DispatchSourceFileSystemObject?
  private var reloadWork: DispatchWorkItem?
  private var started = false

  private static let logLimit = 8_000
  private static let enabledKey = "enabledPlugins"
  private static let disabledBuiltinKey = "disabledBuiltinPlugins"
  private static let settingsKey = "pluginSettings"
  private static let seenAlertsKey = "pluginSeenAlerts"

  func start() {
    guard !started else { return }
    started = true
    Self.migrateBuiltinMarkets()
    reload()
    watchFolder()
  }

  func stop() {
    started = false
    watcher?.cancel()
    watcher = nil
    timers.values.forEach { $0.invalidate() }
    timers = [:]
    for id in Array(streams.keys) { stopStream(id) }
  }

  // MARK: Discovery

  /// Re-reads every plugin folder, keeping the last output of plugins that are still there.
  func reload() {
    let fm = FileManager.default
    func folders(in root: URL?) -> [URL] {
      guard let root else { return [] }
      return ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
    let user = folders(in: Self.folder)
    let userIDs = Set(user.map(\.lastPathComponent))
    let builtins = folders(in: Self.builtinFolder).filter { !userIDs.contains($0.lastPathComponent) }
    let enabled = Self.enabledIDs
    let disabledBuiltins = Self.disabledBuiltinIDs
    var found: [Plugin] = []
    for (folder, builtin) in user.map({ ($0, false) }) + builtins.map({ ($0, true) }) {
      let id = folder.lastPathComponent
      var plugin = plugins.first { $0.id == id && $0.builtin == builtin } ?? Plugin(id: id, folder: folder)
      plugin.builtin = builtin
      plugin.enabled = builtin ? !disabledBuiltins.contains(id) : enabled.contains(id)
      plugin.problem = nil
      do {
        let manifest = try PluginManifest.decode(Data(contentsOf: folder.appendingPathComponent("plugin.json")))
        plugin.manifest = manifest
        if manifest.id != id {
          plugin.problem = "the folder name must equal \"id\" (\(manifest.id))"
        } else if !fm.fileExists(atPath: folder.appendingPathComponent(manifest.run).path) {
          plugin.problem = "\(manifest.run) is missing"
        }
      } catch let error as PluginManifestError {
        plugin.manifest = nil
        plugin.problem = error.description
      } catch {
        plugin.manifest = nil
        plugin.problem = "plugin.json is missing"
      }
      found.append(plugin)
    }
    plugins = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    reschedule()
  }

  private func watchFolder() {
    let fd = open(Self.folder.path, O_EVTONLY)
    guard fd >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
    source.setEventHandler { [weak self] in self?.scheduleReload() }
    source.setCancelHandler { close(fd) }
    source.resume()
    watcher = source
  }

  private func scheduleReload() {
    reloadWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.reload() }
    reloadWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }

  // MARK: Enabling and settings

  func setEnabled(_ id: String, _ on: Bool) {
    if plugins.first(where: { $0.id == id })?.builtin == true {
      var ids = Self.disabledBuiltinIDs
      if on { ids.remove(id) } else { ids.insert(id) }
      UserDefaults.standard.set(Array(ids), forKey: Self.disabledBuiltinKey)
    } else {
      var ids = Self.enabledIDs
      if on { ids.insert(id) } else { ids.remove(id) }
      UserDefaults.standard.set(Array(ids), forKey: Self.enabledKey)
    }
    update(id) { $0.enabled = on; if !on { $0.output = nil } }
    if !on { stopStream(id) }
    reschedule()
    // reschedule() already started a stream plugin; an interval plugin runs now.
    if on, plugins.first(where: { $0.id == id })?.manifest?.mode != .stream { refresh(id) }
  }

  private static var enabledIDs: Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? [])
  }

  private static var disabledBuiltinIDs: Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: disabledBuiltinKey) ?? [])
  }

  /// A setting's current value: the Keychain for secrets, user defaults otherwise.
  func value(of setting: PluginSetting, for id: String) -> String {
    if setting.kind == .secret { return PluginSecrets.get(plugin: id, key: setting.key) ?? "" }
    let all = UserDefaults.standard.dictionary(forKey: Self.settingsKey) as? [String: [String: String]] ?? [:]
    return all[id]?[setting.key] ?? setting.defaultValue ?? ""
  }

  func setValue(_ value: String, of setting: PluginSetting, for id: String) {
    if setting.kind == .secret {
      PluginSecrets.set(value, plugin: id, key: setting.key)
    } else {
      var all = UserDefaults.standard.dictionary(forKey: Self.settingsKey) as? [String: [String: String]] ?? [:]
      all[id, default: [:]][setting.key] = value
      UserDefaults.standard.set(all, forKey: Self.settingsKey)
    }
    objectWillChange.send()
  }

  // MARK: Running

  private func reschedule() {
    timers.values.forEach { $0.invalidate() }
    timers = [:]
    let runnable = plugins.filter { $0.enabled && $0.manifest != nil && $0.problem == nil }
    for id in Array(streams.keys) where !runnable.contains(where: { $0.id == id && $0.manifest?.mode == .stream }) { stopStream(id) }
    for plugin in runnable {
      if plugin.manifest?.mode == .stream {
        if streams[plugin.id] == nil { startStream(plugin.id) }
      } else if plugin.output == nil, !plugin.running {
        refresh(plugin.id)
      } else {
        schedule(plugin.id, after: plugin.manifest!.interval)
      }
    }
  }

  private func schedule(_ id: String, after seconds: TimeInterval) {
    timers[id]?.invalidate()
    timers[id] = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.refresh(id) }
  }

  /// Runs the plugin now; while a run is in progress the event waits its turn. A running stream
  /// plugin gets the event as a line on its stdin instead.
  func refresh(_ id: String, event: PluginEvent = .refresh) {
    guard let plugin = plugins.first(where: { $0.id == id }), plugin.enabled, plugin.problem == nil, let manifest = plugin.manifest else { return }
    if manifest.mode == .stream {
      if let stream = streams[id] {
        try? stream.input.write(contentsOf: Data((event.value + "\n").utf8))
      } else {
        startStream(id)
      }
      return
    }
    if plugin.running {
      pending[id, default: []].append(event)
      return
    }
    update(id) { $0.running = true }
    let env = environment(for: plugin, manifest: manifest, event: event)
    let executable = plugin.folder.appendingPathComponent(manifest.run)
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let result = Self.execute(executable, directory: plugin.folder, environment: env, timeout: manifest.timeout)
      DispatchQueue.main.async { self?.finish(id, event: event, result: result) }
    }
  }

  private func environment(for plugin: Plugin, manifest: PluginManifest, event: PluginEvent) -> [String: String] {
    let values = Dictionary(uniqueKeysWithValues: manifest.settings.map { ($0.key, value(of: $0, for: plugin.id)) })
    let dataDirectory = AppPaths.subdirectory("PluginData").appendingPathComponent(plugin.id, isDirectory: true)
    try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    var env = CLILocator.environment(proxy: AppSettings.shared.proxy)
    env.merge(PluginEnvironment.variables(manifest: manifest, pluginDirectory: plugin.folder.path, dataDirectory: dataDirectory.path,
                                          event: event, language: Self.language, settings: values)) { _, new in new }
    return env
  }

  // MARK: Stream mode

  /// Starts a stream plugin and applies each line it prints as an output; parts a line leaves out
  /// keep what was shown, so a line with only `alerts` just pops a card.
  private func startStream(_ id: String) {
    guard streams[id] == nil, let plugin = plugins.first(where: { $0.id == id }), plugin.enabled, plugin.problem == nil,
          let manifest = plugin.manifest, manifest.mode == .stream else { return }
    let executable = plugin.folder.appendingPathComponent(manifest.run)
    if !FileManager.default.isExecutableFile(atPath: executable.path) {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    let process = Process()
    process.executableURL = executable
    process.currentDirectoryURL = plugin.folder
    process.environment = environment(for: plugin, manifest: manifest, event: .refresh)
    let input = Pipe(), output = Pipe(), errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    var buffer = Data()
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let chunk = handle.availableData
      guard !chunk.isEmpty else { return }
      buffer.append(chunk)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = buffer[buffer.startIndex..<newline]
        buffer.removeSubrange(buffer.startIndex...newline)
        let text = String(decoding: line, as: UTF8.self)
        DispatchQueue.main.async { self?.applyStreamLine(text, plugin: id) }
      }
    }
    errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let chunk = handle.availableData
      guard !chunk.isEmpty else { return }
      let text = String(decoding: chunk, as: UTF8.self)
      DispatchQueue.main.async { self?.appendLog(text, plugin: id) }
    }
    let startedAt = Date()
    process.terminationHandler = { [weak self] finished in
      output.fileHandleForReading.readabilityHandler = nil
      errors.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.async { self?.streamEnded(id, status: finished.terminationStatus, ranFor: Date().timeIntervalSince(startedAt)) }
    }
    do {
      try process.run()
      streams[id] = (process, input.fileHandleForWriting)
      update(id) { $0.running = true; $0.runError = nil }
      appendLog("[\(Date().formatted(date: .omitted, time: .standard))] stream started\n", plugin: id)
    } catch {
      update(id) { $0.runError = "can't start \(manifest.run): \(error.localizedDescription)" }
    }
  }

  private func stopStream(_ id: String) {
    guard let stream = streams.removeValue(forKey: id) else { return }
    stream.process.terminationHandler = nil
    stream.process.terminate()
    update(id) { $0.running = false }
  }

  private func applyStreamLine(_ line: String, plugin id: String) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("{") else {
      if !trimmed.isEmpty { appendLog(trimmed + "\n", plugin: id) }
      return
    }
    do {
      let next = try PluginOutput.decode(Data(trimmed.utf8))
      update(id) { p in
        var merged = p.output ?? PluginOutput()
        if next.ears != nil { merged.ears = next.ears }
        if next.home != nil { merged.home = next.home }
        if next.tab != nil { merged.tab = next.tab }
        p.output = merged
        p.lastRun = Date()
        p.runError = nil
      }
      if let plugin = plugins.first(where: { $0.id == id }), plugin.shows(.alerts) { announce(next.alerts, from: plugin) }
    } catch let error as PluginOutputError {
      update(id) { $0.runError = error.description }
    } catch {}
  }

  /// A stream that exits is restarted after 5 s, doubling up to 5 minutes; one that ran for a
  /// minute or more counts as healthy and starts over at 5 s.
  private func streamEnded(_ id: String, status: Int32, ranFor: TimeInterval) {
    streams[id] = nil
    update(id) { $0.running = false }
    guard started, let plugin = plugins.first(where: { $0.id == id }), plugin.enabled, plugin.manifest?.mode == .stream else { return }
    let delay = ranFor >= 60 ? 5 : min((streamDelay[id] ?? 2.5) * 2, 300)
    streamDelay[id] = delay
    update(id) { $0.runError = status == 0 ? nil : "stream exited with status \(status); restarting in \(Int(delay)) s" }
    appendLog("[\(Date().formatted(date: .omitted, time: .standard))] stream exited (\(status)); restart in \(Int(delay)) s\n", plugin: id)
    timers[id]?.invalidate()
    timers[id] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.startStream(id) }
  }

  private func appendLog(_ text: String, plugin id: String) {
    update(id) { $0.log = String(($0.log + text).suffix(Self.logLimit)) }
  }

  private struct RunResult {
    var stdout = Data()
    var stderr = ""
    var status: Int32 = 0
    var timedOut = false
    var launchError: String?
  }

  private static func execute(_ executable: URL, directory: URL, environment: [String: String], timeout: TimeInterval) -> RunResult {
    var result = RunResult()
    // Scripts from a zip or written by an editor often lack the executable bit (the app bundle is read-only, so this only fixes user plugins).
    if !FileManager.default.isExecutableFile(atPath: executable.path) {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    let process = Process()
    process.executableURL = executable
    process.currentDirectoryURL = directory
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    do {
      try process.run()
    } catch {
      result.launchError = "can't start \(executable.lastPathComponent): \(error.localizedDescription)"
      return result
    }
    let deadline = DispatchWorkItem {
      guard process.isRunning else { return }
      result.timedOut = true
      process.terminate()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
    // Read both pipes concurrently so a chatty stderr can't fill its buffer and stall the script.
    let group = DispatchGroup()
    var stderrData = Data()
    group.enter()
    DispatchQueue.global().async { stderrData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    result.stdout = out.fileHandleForReading.readDataToEndOfFile()
    group.wait()
    process.waitUntilExit()
    deadline.cancel()
    result.status = process.terminationStatus
    result.stderr = String(decoding: stderrData, as: UTF8.self)
    return result
  }

  private func finish(_ id: String, event: PluginEvent, result: RunResult) {
    guard let plugin = plugins.first(where: { $0.id == id }), let manifest = plugin.manifest else { return }
    let stamp = Date().formatted(date: .omitted, time: .standard)
    var error: String?
    var output: PluginOutput?
    if let launchError = result.launchError {
      error = launchError
    } else if result.timedOut {
      error = "stopped after \(Int(manifest.timeout)) s without finishing"
    } else if result.status != 0 {
      error = "exited with status \(result.status)" + (result.stderr.isEmpty ? "" : ": " + Self.lastLine(result.stderr))
    } else {
      do { output = try PluginOutput.decode(result.stdout) } catch let decodeError as PluginOutputError { error = decodeError.description } catch {}
    }
    update(id) { p in
      p.running = false
      p.lastRun = Date()
      p.runError = error
      if let output { p.output = output }
      var entry = "[\(stamp)] \(event.value): " + (error ?? "ok") + "\n"
      if !result.stderr.isEmpty { entry += result.stderr.hasSuffix("\n") ? result.stderr : result.stderr + "\n" }
      p.log = String((p.log + entry).suffix(Self.logLimit))
    }
    if let output, let updated = plugins.first(where: { $0.id == id }), updated.shows(.alerts) {
      announce(output.alerts, from: updated)
    }
    if let next = pending[id]?.first {
      pending[id]?.removeFirst()
      refresh(id, event: next)
    } else if plugins.first(where: { $0.id == id })?.enabled == true {
      schedule(id, after: output?.next ?? manifest.interval)
    }
  }

  /// Alerts are announced once per id, remembered across launches (the newest 200 per plugin).
  private func announce(_ alerts: [PluginOutput.Alert], from plugin: Plugin) {
    var seen = UserDefaults.standard.dictionary(forKey: Self.seenAlertsKey) as? [String: [String]] ?? [:]
    var ids = seen[plugin.id] ?? []
    for alert in alerts where !ids.contains(alert.id) {
      ids.append(alert.id)
      onAlert(alert, plugin)
    }
    seen[plugin.id] = Array(ids.suffix(200))
    UserDefaults.standard.set(seen, forKey: Self.seenAlertsKey)
  }

  // MARK: Actions

  func perform(_ action: PluginAction, plugin id: String) {
    switch action {
    case .open(let url):
      NSWorkspace.shared.open(url)
    case .copy(let text):
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      Toast.show("Copied", symbol: "doc.on.doc", duration: 1.2)
    case .run(let actionID):
      refresh(id, event: .action(actionID))
    }
  }

  // MARK: Migration

  /// Markets used to be built into the notch; it is now the built-in "markets" plugin. Carries the
  /// old watchlist, its on/off switch, the ticker switch and its place on Home over, once.
  private static func migrateBuiltinMarkets() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: "migratedMarketsToPlugin") else { return }
    defaults.set(true, forKey: "migratedMarketsToPlugin")
    var pluginSettings = defaults.dictionary(forKey: settingsKey) as? [String: [String: String]] ?? [:]
    if let watchlist = defaults.stringArray(forKey: "marketWatchlist"), !watchlist.isEmpty {
      pluginSettings["markets", default: [:]]["watchlist"] = watchlist.joined(separator: ", ")
    }
    // These two live in AppSettings, already loaded; change them there so its next save keeps the change.
    let settings = AppSettings.shared
    if settings.disabledCapabilities.contains("notch.ticker") { pluginSettings["markets", default: [:]]["ears"] = "Off" }
    defaults.set(pluginSettings, forKey: settingsKey)
    if settings.disabledCapabilities.contains("notch.markets") {
      defaults.set(Array(disabledBuiltinIDs.union(["markets"])), forKey: disabledBuiltinKey)
    }
    settings.disabledCapabilities.subtract(["notch.markets", "notch.ticker"])
    // HomeSlot no longer reads "markets", so the old card would vanish from Home instead of moving.
    settings.homeCards = settings.homeCards.map { $0 == "markets" ? "plugin:markets" : $0 }
    for key in ["marketWatchlist", "tickerSymbol"] { defaults.removeObject(forKey: key) }
  }

  // MARK: Helpers

  private func update(_ id: String, _ change: (inout Plugin) -> Void) {
    guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
    change(&plugins[index])
  }

  private static var language: String {
    (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? "zh" : "en"
  }

  private static func lastLine(_ text: String) -> String {
    String(text.split(separator: "\n").last ?? "").trimmingCharacters(in: .whitespaces)
  }
}
