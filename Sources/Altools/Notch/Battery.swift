import Foundation
import IOKit.ps

/// Battery level and charging state from IOKit; updates when the power source changes.
final class BatteryMonitor: ObservableObject {
  struct State: Equatable {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
  }

  /// nil on Macs without a battery.
  @Published private(set) var state: State?
  /// Fires when the charger is plugged in (true) or pulled out (false), with the current percent.
  var onPowerChange: ((Int, Bool) -> Void)?

  private var runLoopSource: CFRunLoopSource?

  func start() {
    refresh()
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard let source = IOPSNotificationCreateRunLoopSource({ context in
      guard let context else { return }
      let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
      DispatchQueue.main.async { monitor.refresh() }
    }, context)?.takeRetainedValue() else { return }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    runLoopSource = source
  }

  func refresh() {
    let previous = state
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
      state = nil
      return
    }
    for source in list {
      guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
            desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
      let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
      let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
      let newState = State(percent: max > 0 ? current * 100 / max : current,
                           isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                           onAC: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
      state = newState
      if let previous, previous.onAC != newState.onAC { onPowerChange?(newState.percent, newState.onAC) }
      return
    }
    state = nil
  }
}
