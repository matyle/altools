import AppKit

/// What is playing on this Mac, from any player.
///
/// Reads the system's Now Playing (what Control Center shows) through a small bridge
/// library loaded into `/usr/bin/perl`, the one process macOS still lets use the
/// private MediaRemote framework. If the bridge cannot start, falls back to asking
/// Music and Spotify over AppleScript.
final class NowPlaying: ObservableObject {
  struct Track: Equatable {
    var bundleID: String
    var title: String
    var artist: String
    var album = ""
    var isPlaying: Bool
    /// Seconds into the track at `fetchedAt`.
    var position: Double
    var duration: Double
    var rate: Double = 1
    var fetchedAt = Date()

    var appName: String {
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    /// Current position, advanced by the time passed since the last update while playing.
    func elapsed(at date: Date = Date()) -> Double {
      guard isPlaying else { return position }
      let value = position + date.timeIntervalSince(fetchedAt) * (rate == 0 ? 1 : rate)
      return duration > 0 ? min(value, duration) : value
    }

    var canSeek: Bool { duration > 0 }
  }

  @Published private(set) var track: Track?
  @Published private(set) var artwork: NSImage?
  /// Set when macOS denied Automation access, so the UI can say why nothing shows.
  @Published private(set) var automationDenied = false

  private var bridge: Process?
  private var bridgeInput: FileHandle?
  private var bridgeFailures = 0
  private var timer: Timer?
  private var artworkKey = ""

  func start() {
    if !AppSettings.shared.notchSystemNowPlaying || !startBridge() { startAppleScriptPolling() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    bridge?.terminationHandler = nil
    bridge?.terminate()
    bridge = nil
    bridgeInput = nil
  }

  #if DEBUG
  func loadDemo(_ track: Track) { self.track = track }
  #endif

  func playPause() { command("toggle", script: "playpause") }
  func next() { command("next", script: "next track") }
  func previous() { command("previous", script: "previous track") }

  func seek(to seconds: Double) {
    guard var current = track else { return }
    current.position = seconds
    current.fetchedAt = Date()
    track = current
    command("seek \(seconds)", script: "set player position to \(seconds)")
  }

  // MARK: System bridge

  private static let perlScript = """
  use DynaLoader;
  my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
  my $sym = DynaLoader::dl_find_symbol($lib, "altools_media_stream") or die "symbol missing";
  DynaLoader::dl_install_xsub("main::stream", $sym);
  stream();
  """

  private var bridgeLibrary: URL? {
    Bundle.main.privateFrameworksURL?.appendingPathComponent("libAltoolsMedia.dylib")
  }

  private func startBridge() -> Bool {
    guard bridgeFailures < 3, let library = bridgeLibrary, FileManager.default.fileExists(atPath: library.path) else { return false }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", Self.perlScript, library.path]
    let output = Pipe()
    let input = Pipe()
    process.standardOutput = output
    process.standardInput = input
    process.standardError = FileHandle.nullDevice
    var buffer = Data()
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let chunk = handle.availableData
      guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
      buffer.append(chunk)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = buffer[buffer.startIndex..<newline]
        buffer.removeSubrange(buffer.startIndex...newline)
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
        DispatchQueue.main.async { self?.apply(object) }
      }
    }
    process.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.bridge === process else { return }
        self.bridge = nil
        self.bridgeFailures += 1
        if !self.startBridge() { self.startAppleScriptPolling() }
      }
    }
    do {
      try process.run()
    } catch {
      return false
    }
    bridge = process
    bridgeInput = input.fileHandleForWriting
    return true
  }

  private func apply(_ info: [String: Any]) {
    let title = info["title"] as? String ?? ""
    guard !title.isEmpty else {
      if track != nil { track = nil; artwork = nil; artworkKey = "" }
      return
    }
    let playing = (info["playing"] as? Bool) ?? ((info["playing"] as? Int ?? 0) != 0)
    let elapsed = info["elapsed"] as? Double ?? 0
    // The elapsed time is as of `timestamp`, which can be well before this update arrives.
    let stamp = (info["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
    track = Track(bundleID: info["bundle"] as? String ?? "",
                  title: title,
                  artist: info["artist"] as? String ?? "",
                  album: info["album"] as? String ?? "",
                  isPlaying: playing,
                  position: elapsed,
                  duration: info["duration"] as? Double ?? 0,
                  rate: info["rate"] as? Double ?? 1,
                  fetchedAt: stamp)
    let key = "\(title)|\(track?.artist ?? "")"
    if let base64 = info["artwork"] as? String, let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
      artwork = image
      artworkKey = key
    } else if key != artworkKey {
      artwork = nil
    }
  }

  private func command(_ bridgeCommand: String, script: String) {
    if let bridgeInput {
      bridgeInput.write(Data("\(bridgeCommand)\nrefresh\n".utf8))
      return
    }
    guard let name = appleScriptPlayer(for: track?.bundleID) ?? runningScriptablePlayer else { return }
    _ = run("tell application \"\(name)\" to \(script)")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pollAppleScript() }
  }

  // MARK: AppleScript fallback (Music and Spotify only)

  private func startAppleScriptPolling() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.pollAppleScript() }
    pollAppleScript()
  }

  private static let scriptable = ["com.spotify.client": "Spotify", "com.apple.Music": "Music"]

  private func appleScriptPlayer(for bundleID: String?) -> String? {
    bundleID.flatMap { Self.scriptable[$0] }
  }

  private var runningScriptablePlayer: String? {
    // Checking first matters: `tell application "Music"` would launch Music.
    let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    if running.contains("com.spotify.client"),
       run("tell application \"Spotify\" to return player state as string")?.stringValue == "playing" { return "Spotify" }
    if running.contains("com.apple.Music") { return "Music" }
    if running.contains("com.spotify.client") { return "Spotify" }
    return nil
  }

  private func pollAppleScript() {
    guard let name = runningScriptablePlayer else {
      if track != nil { track = nil; artwork = nil; artworkKey = "" }
      return
    }
    let script = """
    tell application "\(name)"
      if player state is stopped then return {}
      set t to current track
      return {name of t, artist of t, player state as string, player position, duration of t, album of t}
    end tell
    """
    guard let result = run(script), result.numberOfItems >= 6 else {
      if track != nil { track = nil; artwork = nil; artworkKey = "" }
      return
    }
    var duration = result.atIndex(5)?.doubleValue ?? 0
    if name == "Spotify" { duration /= 1000 } // Spotify reports milliseconds
    let bundleID = Self.scriptable.first { $0.value == name }?.key ?? ""
    track = Track(bundleID: bundleID,
                  title: result.atIndex(1)?.stringValue ?? "",
                  artist: result.atIndex(2)?.stringValue ?? "",
                  album: result.atIndex(6)?.stringValue ?? "",
                  isPlaying: result.atIndex(3)?.stringValue == "playing",
                  position: result.atIndex(4)?.doubleValue ?? 0,
                  duration: duration)
    let key = "\(name)|\(track?.title ?? "")|\(track?.artist ?? "")"
    if key != artworkKey {
      artworkKey = key
      loadArtwork(name)
    }
  }

  private func loadArtwork(_ name: String) {
    artwork = nil
    if name == "Music" {
      if let data = run("tell application \"Music\" to return raw data of artwork 1 of current track")?.data,
         let image = NSImage(data: data) { artwork = image }
      return
    }
    guard let urlString = run("tell application \"Spotify\" to return artwork url of current track")?.stringValue,
          let url = URL(string: urlString) else { return }
    let expectedKey = artworkKey
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = NSImage(data: data) else { return }
      DispatchQueue.main.async {
        if self?.artworkKey == expectedKey { self?.artwork = image }
      }
    }.resume()
  }

  private func run(_ source: String) -> NSAppleEventDescriptor? {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let code = error?[NSAppleScript.errorNumber] as? Int {
      // -1743: the user has not allowed Altools to control this app.
      automationDenied = code == -1743
      return nil
    }
    if automationDenied { automationDenied = false }
    return result
  }
}

private extension NSAppleEventDescriptor {
  var doubleValue: Double? {
    if let s = stringValue, let v = Double(s) { return v }
    return coerce(toDescriptorType: typeIEEE64BitFloatingPoint).map { desc in
      var value: Double = 0
      (desc.data as NSData).getBytes(&value, length: MemoryLayout<Double>.size)
      return value
    }
  }
}
