import AltoolsCore
import AppKit

/// Finds the plugins in Application Support/Altools/Plugins, runs the enabled ones on their
/// schedule and keeps what each last printed. The contract (manifest, environment, output)
/// is in AltoolsCore and PLUGINS.md.
///
/// Plugins are arbitrary programs running as the user, so one found on disk starts disabled
/// until the user switches it on in Settings.
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
    /// Recent stderr and run outcomes, newest last.
    var log = ""

    var name: String { manifest?.name ?? id }
    var error: String? { problem ?? runError }
    func shows(_ slot: PluginSlot) -> Bool { enabled && error == nil && manifest?.slots.contains(slot) == true }
  }

  static let shared = PluginHost()
  static var folder: URL { AppPaths.subdirectory("Plugins") }

  @Published private(set) var plugins: [Plugin] = []
  /// Called on the main queue for each alert id a plugin hasn't announced before.
  var onAlert: (PluginOutput.Alert, Plugin) -> Void = { _, _ in }

  private var timers: [String: Timer] = [:]
  private var pending: [String: [PluginEvent]] = [:]
  private var watcher: DispatchSourceFileSystemObject?
  private var reloadWork: DispatchWorkItem?
  private var started = false

  private static let logLimit = 8_000
  private static let enabledKey = "enabledPlugins"
  private static let settingsKey = "pluginSettings"
  private static let seenAlertsKey = "pluginSeenAlerts"

  func start() {
    guard !started else { return }
    started = true
    reload()
    watchFolder()
  }

  func stop() {
    started = false
    watcher?.cancel()
    watcher = nil
    timers.values.forEach { $0.invalidate() }
    timers = [:]
  }

  // MARK: Discovery

  /// Re-reads every plugin folder, keeping the last output of plugins that are still there.
  func reload() {
    let fm = FileManager.default
    let folders = (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
    let enabled = Self.enabledIDs
    var found: [Plugin] = []
    for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      let id = folder.lastPathComponent
      var plugin = plugins.first { $0.id == id } ?? Plugin(id: id, folder: folder)
      plugin.enabled = enabled.contains(id)
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
    var ids = Self.enabledIDs
    if on { ids.insert(id) } else { ids.remove(id) }
    UserDefaults.standard.set(Array(ids), forKey: Self.enabledKey)
    update(id) { $0.enabled = on; if !on { $0.output = nil } }
    reschedule()
    if on { refresh(id) }
  }

  private static var enabledIDs: Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: enabledKey) ?? [])
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
    for plugin in plugins where plugin.enabled && plugin.manifest != nil && plugin.problem == nil {
      if plugin.output == nil, !plugin.running { refresh(plugin.id) } else { schedule(plugin.id, after: plugin.manifest!.interval) }
    }
  }

  private func schedule(_ id: String, after seconds: TimeInterval) {
    timers[id]?.invalidate()
    timers[id] = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.refresh(id) }
  }

  /// Runs the plugin now; while a run is in progress the event waits its turn.
  func refresh(_ id: String, event: PluginEvent = .refresh) {
    guard let plugin = plugins.first(where: { $0.id == id }), plugin.enabled, plugin.problem == nil, let manifest = plugin.manifest else { return }
    if plugin.running {
      pending[id, default: []].append(event)
      return
    }
    update(id) { $0.running = true }
    let values = Dictionary(uniqueKeysWithValues: manifest.settings.map { ($0.key, value(of: $0, for: id)) })
    let dataDirectory = AppPaths.subdirectory("PluginData").appendingPathComponent(id, isDirectory: true)
    try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    var env = CLILocator.environment(proxy: AppSettings.shared.proxy)
    env.merge(PluginEnvironment.variables(manifest: manifest, pluginDirectory: plugin.folder.path, dataDirectory: dataDirectory.path,
                                          event: event, language: Self.language, settings: values)) { _, new in new }
    let executable = plugin.folder.appendingPathComponent(manifest.run)
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let result = Self.execute(executable, directory: plugin.folder, environment: env, timeout: manifest.timeout)
      DispatchQueue.main.async { self?.finish(id, event: event, result: result) }
    }
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
    // Scripts from a zip or written by an editor often lack the executable bit.
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
