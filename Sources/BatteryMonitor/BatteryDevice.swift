import Foundation

/// One battery macOS reports for an accessory: a keyboard, a mouse, or one part of a pair of AirPods.
public struct BatteryReading: Equatable, Sendable {
  /// Declared in display order.
  public enum Part: Int, Comparable, Sendable {
    case left, right, single, `case`

    public static func < (a: Part, b: Part) -> Bool { a.rawValue < b.rawValue }
  }

  public var name: String
  /// macOS's accessory category, such as "Keyboard", "Mouse" or "Headset".
  public var category: String?
  public var part: Part
  /// Shared by the parts of one device (AirPods' buds and case).
  public var group: String?
  /// 0–100.
  public var percent: Int
  public var charging: Bool

  public init(name: String, category: String? = nil, part: Part = .single, group: String? = nil, percent: Int, charging: Bool = false) {
    self.name = name
    self.category = category
    self.part = part
    self.group = group
    self.percent = percent
    self.charging = charging
  }

  /// One entry of macOS's power-source list, the list `pmset -g accps` prints. Nil for the Mac's own
  /// battery and UPSes, and for entries marked absent or lacking a name or level.
  public init?(powerSource entry: [String: Any]) {
    guard entry["Type"] as? String == "Accessory Source",
          (entry["Is Present"] as? NSNumber)?.boolValue != false,
          let name = (entry["Name"] as? String).map(Self.displayName), !name.isEmpty,
          let current = (entry["Current Capacity"] as? NSNumber)?.doubleValue else { return nil }
    let maximum = (entry["Max Capacity"] as? NSNumber)?.doubleValue ?? 100
    let part: Part = switch (entry["Part Identifier"] as? String)?.lowercased() {
    case "left": .left
    case "right": .right
    case "case": .case
    default: .single
    }
    self.init(
      name: name,
      category: entry["Accessory Category"] as? String,
      part: part,
      group: (entry["Group Identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 },
      percent: min(max(Int((maximum > 0 ? current / maximum * 100 : current).rounded()), 0), 100),
      charging: (entry["Is Charging"] as? NSNumber)?.boolValue == true || entry["Power Source State"] as? String == "AC Power"
    )
  }

  /// Drops the " - Find My" that macOS appends to devices it knows through Find My.
  static func displayName(_ raw: String) -> String {
    raw.replacingOccurrences(of: #"\s+-\s+Find My$"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// An accessory with one battery, or several that macOS groups together (AirPods' buds and case).
public struct BatteryDevice: Equatable, Sendable {
  public enum Kind: Sendable { case headphones, keyboard, mouse, trackpad, gamepad, pencil, other }

  /// Stable across runs: macOS's group identifier, or the name for a single-battery device.
  public var id: String
  public var name: String
  public var kind: Kind
  /// At least one, sorted left, right, single, case.
  public var parts: [BatteryReading]

  init(id: String, name: String, kind: Kind, parts: [BatteryReading]) {
    precondition(!parts.isEmpty, "a device has at least one battery")
    self.id = id
    self.name = name
    self.kind = kind
    self.parts = parts.sorted { $0.part < $1.part }
  }

  /// The battery that runs out first. A case counts only when the device has nothing else.
  public var weakest: BatteryReading {
    let worn = parts.filter { $0.part != .case }
    return (worn.isEmpty ? parts : worn).min { $0.percent < $1.percent }!
  }

  public var level: Int { weakest.percent }
  public var charging: Bool { weakest.charging }

  /// SF Symbol for the device.
  public var symbol: String {
    let lower = name.lowercased()
    switch kind {
    case .headphones:
      if lower.contains("airpods max") { return "airpodsmax" }
      if lower.contains("airpods pro") { return "airpodspro" }
      if lower.contains("airpods") { return "airpods" }
      if lower.contains("beats") { return "beats.headphones" }
      return parts.contains { $0.part == .left || $0.part == .right } ? "earbuds" : "headphones"
    case .keyboard: return "keyboard"
    case .mouse: return lower.contains("magic mouse") ? "magicmouse" : "computermouse"
    case .trackpad: return "rectangle.and.hand.point.up.left"
    case .gamepad: return "gamecontroller"
    case .pencil: return "applepencil"
    case .other: return "battery.75percent"
    }
  }

  /// One device per group identifier (or per name when there is none), weakest first.
  public static func devices(from readings: [BatteryReading]) -> [BatteryDevice] {
    Dictionary(grouping: readings) { $0.group ?? $0.name }
      .map { id, parts in
        let named = parts.first { $0.part != .case } ?? parts[0]
        return BatteryDevice(id: id, name: named.name, kind: kind(category: named.category, name: named.name), parts: parts)
      }
      .sorted { ($0.level, $0.name) < ($1.level, $1.name) }
  }

  /// From macOS's category when it names one, else from words in the device's name.
  static func kind(category: String?, name: String) -> Kind {
    let headphoneWords = ["headset", "headphone", "earphone", "earbud", "audio", "airpods", "beats", "buds", "耳机"]
    for text in [category, name].compactMap({ $0?.lowercased() }) {
      if text.contains("keyboard") || text.contains("键盘") { return .keyboard }
      if text.contains("mouse") || text.contains("鼠标") { return .mouse }
      if text.contains("trackpad") || text.contains("触控板") { return .trackpad }
      if headphoneWords.contains(where: text.contains) { return .headphones }
      if text.contains("game") || text.contains("controller") || text.contains("手柄") { return .gamepad }
      if text.contains("pencil") || text.contains("stylus") { return .pencil }
    }
    return .other
  }
}
