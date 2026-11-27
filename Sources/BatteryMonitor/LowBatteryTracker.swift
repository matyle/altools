import Foundation

/// A low-battery alert to show. Its id stays the same while the device stays low, so the host, which
/// shows each id once, shows it once each time the device runs low.
public struct LowBatteryAlert: Equatable, Sendable {
  public enum Severity: Sendable { case low, critical }

  public var id: String
  public var severity: Severity
  public var device: BatteryDevice
}

/// Remembers between runs which devices are low (saved in the plugin's data folder).
public struct LowBatteryTracker: Codable, Equatable, Sendable {
  /// A device that has been low since `started` without being charged or recovering.
  struct Episode: Codable, Equatable, Sendable {
    var started: Date
    var lastSeen: Date
  }

  /// At or below this level a second, critical alert follows the low one, when the threshold is higher.
  public static let criticalPercent = 5
  /// A device must climb this far above the threshold (or be charged) before it can alert again, so a
  /// reading that wobbles around the threshold alerts once.
  public static let recoveryMargin = 10
  /// A device unseen this long is forgotten; one that returns sooner, still low, doesn't alert again.
  public static let forgetAfter: TimeInterval = 7 * 24 * 3600

  /// Keyed by `BatteryDevice.id`.
  private var episodes: [String: Episode] = [:]

  public init() {}

  /// Records this run's devices and returns the alerts for the devices that are low now. `threshold`
  /// is a percentage; a device at or below it is low.
  public mutating func update(_ devices: [BatteryDevice], threshold: Int, now: Date) -> [LowBatteryAlert] {
    var alerts: [LowBatteryAlert] = []
    for device in devices {
      if device.charging || device.level >= threshold + Self.recoveryMargin {
        episodes[device.id] = nil
        continue
      }
      if episodes[device.id] != nil {
        episodes[device.id]?.lastSeen = now
      } else if device.level <= threshold {
        episodes[device.id] = Episode(started: now, lastSeen: now)
      }
      guard let episode = episodes[device.id], device.level <= threshold else { continue }
      let suffix = "\(device.id)-\(Int(episode.started.timeIntervalSince1970))"
      alerts.append(LowBatteryAlert(id: "low-\(suffix)", severity: .low, device: device))
      if device.level <= Self.criticalPercent, threshold > Self.criticalPercent {
        alerts.append(LowBatteryAlert(id: "critical-\(suffix)", severity: .critical, device: device))
      }
    }
    episodes = episodes.filter { now.timeIntervalSince($0.value.lastSeen) < Self.forgetAfter }
    return alerts
  }
}
