import AppKit
import Carbon
import CoreAudio
import CoreMediaIO

/// Small system events the notch reports: Caps Lock, input source switches,
/// camera / microphone in use, and files that finish landing in Downloads.
final class SystemSignals: ObservableObject {
  /// Whether some app has the camera open, and which app (if known) is recording audio.
  struct Sensors: Equatable {
    var camera = false
    var microphone = false
    var microphoneApp: String?
    var active: Bool { camera || microphone }
  }

  @Published private(set) var sensors = Sensors()
  var onCapsLock: ((Bool) -> Void)?
  var onInputSource: ((String) -> Void)?
  var onDownload: ((URL) -> Void)?

  private var monitors: [Any] = []
  private var capsOn = NSEvent.modifierFlags.contains(.capsLock)
  private var inputObserver: Any?
  private var sensorTimer: Timer?
  private var downloadsWatcher: DispatchSourceFileSystemObject?
  private var knownDownloads: Set<String> = []

  func start() {
    let handler: (NSEvent) -> Void = { [weak self] event in
      guard let self else { return }
      let on = event.modifierFlags.contains(.capsLock)
      if on != capsOn {
        capsOn = on
        onCapsLock?(on)
      }
    }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { monitors.append(global) }
    if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { handler($0); return $0 }) { monitors.append(local) }

    inputObserver = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
    ) { [weak self] _ in
      if let name = Self.currentInputSourceName() { self?.onInputSource?(name) }
    }

    sensorTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pollSensors() }
    pollSensors()
    watchDownloads()
  }

  func stop() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    if let inputObserver { DistributedNotificationCenter.default().removeObserver(inputObserver) }
    sensorTimer?.invalidate()
    downloadsWatcher?.cancel()
  }

  static func currentInputSourceName() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
  }

  // MARK: Camera and microphone

  private func pollSensors() {
    let camera = Self.cameraInUse()
    let microphoneApp = Self.appRecordingAudio()
    let microphone = microphoneApp != nil || Self.defaultInputInUse()
    let next = Sensors(camera: camera, microphone: microphone, microphoneApp: microphoneApp)
    if next != sensors { sensors = next }
  }

  private static func cameraInUse() -> Bool {
    var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return false }
    var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &size, &devices) == 0 else { return false }
    return devices.contains { device in
      var running: UInt32 = 0
      var runningSize = UInt32(MemoryLayout<UInt32>.size)
      var runningAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                     mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                     mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
      return CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, runningSize, &runningSize, &running) == 0 && running != 0
    }
  }

  private static func defaultInputInUse() -> Bool {
    var device = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return false }
    var running: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
    return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
  }

  /// The name of an app (not Altools) whose audio input is running; macOS 14.2+.
  private static func appRecordingAudio() -> String? {
    guard #available(macOS 14.2, *) else { return nil }
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return nil }
    var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes) == noErr else { return nil }
    for process in processes {
      var running: UInt32 = 0
      var runningSize = UInt32(MemoryLayout<UInt32>.size)
      var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
      guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
      var pid: pid_t = 0
      var pidSize = UInt32(MemoryLayout<pid_t>.size)
      var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                  mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
      guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
            pid != ProcessInfo.processInfo.processIdentifier else { continue }
      if let app = NSRunningApplication(processIdentifier: pid) { return app.localizedName ?? app.bundleIdentifier }
    }
    return nil
  }

  // MARK: Downloads

  private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp"]

  private var downloadsFolder: URL {
    FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
  }

  private func watchDownloads() {
    knownDownloads = Set(currentDownloads())
    let fd = open(downloadsFolder.path, O_EVTONLY)
    guard fd >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
    source.setEventHandler { [weak self] in
      // Browsers rename "x.crdownload" to "x" when done; give the rename a moment to settle.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.checkDownloads() }
    }
    source.setCancelHandler { close(fd) }
    source.resume()
    downloadsWatcher = source
  }

  private func currentDownloads() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path)) ?? [])
      .filter { !$0.hasPrefix(".") && !Self.partialExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
  }

  private func checkDownloads() {
    let now = Set(currentDownloads())
    let added = now.subtracting(knownDownloads)
    knownDownloads = now
    let newest = added.map { downloadsFolder.appendingPathComponent($0) }
      .max { (Self.created($0) ?? .distantPast) < (Self.created($1) ?? .distantPast) }
    if let newest { onDownload?(newest) }
  }

  private static func created(_ url: URL) -> Date? {
    try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
  }
}
