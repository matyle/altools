import BatteryMonitor
import Foundation
import IOKit.ps

// The built-in Battery plugin's program (Resources/BuiltinPlugins/battery; contract in PLUGINS.md):
// reads the accessories' batteries, alerts once each time one runs low, and prints the plugin output.

/// The accessory batteries macOS knows (AirPods, keyboards, mice…), the list `pmset -g accps` prints.
/// IOPSCopyPowerSourcesByType isn't in the public SDK, so it's looked up at runtime; nil when it's gone.
func accessoryPowerSources() -> [[String: Any]]? {
  typealias CopyPowerSourcesByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
  guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
        let symbol = dlsym(iokit, "IOPSCopyPowerSourcesByType") else { return nil }
  // 4 asks for the accessories; the public IOPSCopyPowerSourcesInfo() lists only the Mac's own battery.
  guard let blob = unsafeBitCast(symbol, to: CopyPowerSourcesByType.self)(4)?.takeRetainedValue() else { return [] }
  let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
  return sources.compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
}

let environment = ProcessInfo.processInfo.environment
guard let sources = accessoryPowerSources() else {
  FileHandle.standardError.write(Data("this macOS doesn't offer the accessory battery list\n".utf8))
  exit(1)
}
let settings = BatterySettings(environment: environment)
let devices = BatteryDevice.devices(from: sources.compactMap(BatteryReading.init(powerSource:)))
let stateFile = environment["ALTOOLS_DATA_DIR"].map { URL(fileURLWithPath: $0).appendingPathComponent("low-battery.json") }
var tracker = stateFile.flatMap { try? JSONDecoder().decode(LowBatteryTracker.self, from: Data(contentsOf: $0)) } ?? LowBatteryTracker()
let now = Date()
let alerts = tracker.update(devices, threshold: settings.threshold, now: now)
if let stateFile, let data = try? JSONEncoder().encode(tracker) { try? data.write(to: stateFile, options: .atomic) }
FileHandle.standardOutput.write(BatteryOutput.json(devices: devices, alerts: alerts, settings: settings,
                                                   chinese: environment["ALTOOLS_LANG"] == "zh", now: now))
