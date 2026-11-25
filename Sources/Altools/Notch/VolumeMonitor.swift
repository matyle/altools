import AudioToolbox
import CoreAudio
import Foundation

/// Reports changes to the default output device's volume and mute state, for the notch's
/// volume bar. Follows the default output when it switches (AirPods connecting, etc.).
final class VolumeMonitor {
  struct Level: Equatable {
    /// 0…1
    var volume: Float
    var muted: Bool
    var deviceName: String
    var isHeadphones: Bool
  }

  var onChange: ((Level) -> Void)?

  private var device = AudioObjectID(0)
  private var last: Level?
  private let queue = DispatchQueue.main
  private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
  private lazy var defaultListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachToDefaultDevice() }

  private static let virtualMainVolume = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)

  func start() {
    var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, defaultListener)
    attachToDefaultDevice()
  }

  func stop() {
    var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, defaultListener)
    detach()
  }

  private func attachToDefaultDevice() {
    detach()
    var id = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else { return }
    device = id
    for selector in Self.watchedSelectors {
      var a = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
      if AudioObjectHasProperty(device, &a) { AudioObjectAddPropertyListenerBlock(device, &a, queue, deviceListener) }
    }
    // Remember the starting level without announcing it; only changes are shown.
    last = currentLevel()
  }

  private func detach() {
    guard device != 0 else { return }
    for selector in Self.watchedSelectors {
      var a = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
      if AudioObjectHasProperty(device, &a) { AudioObjectRemovePropertyListenerBlock(device, &a, queue, deviceListener) }
    }
    device = 0
  }

  /// Bluetooth headphones often expose only the virtual main volume, built-in speakers
  /// the per-device scalar; watching both covers either.
  private static let watchedSelectors: [AudioObjectPropertySelector] = [
    virtualMainVolume, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute,
  ]

  private func volumeChanged() {
    guard let level = currentLevel(), level != last else { return }
    last = level
    onChange?(level)
  }

  private func currentLevel() -> Level? {
    guard device != 0 else { return nil }
    var volume: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    var address = Self.address(Self.virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) != noErr {
      address = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
      guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
    }
    var muted: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    address = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
    return Level(volume: volume, muted: muted != 0, deviceName: name(of: device), isHeadphones: isBluetooth(device))
  }

  private func name(of device: AudioObjectID) -> String {
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var address = Self.address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return "" }
    return name.takeRetainedValue() as String
  }

  private func isBluetooth(_ device: AudioObjectID) -> Bool {
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = Self.address(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
    return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
  }

  private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }
}
