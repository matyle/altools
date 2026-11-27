import Foundation

/// The Battery plugin's settings, from its `ALTOOLS_SETTING_*` variables (the choices in plugin.json).
public struct BatterySettings: Equatable, Sendable {
  public enum Ears: Sendable { case whenLow, always, off }

  /// Percentage at or below which a device is low.
  public var threshold: Int
  public var ears: Ears
  /// Whether the menu-bar item shows the weakest device.
  public var menuBar: Bool

  public init(threshold: Int = 20, ears: Ears = .whenLow, menuBar: Bool = false) {
    self.threshold = threshold
    self.ears = ears
    self.menuBar = menuBar
  }

  public init(environment: [String: String]) {
    let threshold = environment["ALTOOLS_SETTING_THRESHOLD"].flatMap { Int($0.filter(\.isNumber)) }
    let ears: Ears = switch environment["ALTOOLS_SETTING_EARS"] {
    case "Always": .always
    case "Off": .off
    default: .whenLow
    }
    self.init(threshold: min(max(threshold ?? 20, 5), 50), ears: ears, menuBar: environment["ALTOOLS_SETTING_MENUBAR"] == "Lowest device")
  }
}

/// The plugin's output object (PLUGINS.md › Output).
public enum BatteryOutput {
  public static func json(devices: [BatteryDevice], alerts: [LowBatteryAlert], settings: BatterySettings, chinese: Bool, now: Date) -> Data {
    let strings = Strings(chinese: chinese)
    let low = devices.filter { !$0.charging && $0.level <= settings.threshold }
    let weakestInUse = devices.first { !$0.charging } ?? devices.first
    let earsDevice = switch settings.ears {
    case .whenLow: low.first
    case .always: weakestInUse
    case .off: nil as BatteryDevice?
    }
    let output = Output(
      ears: earsDevice.map { Output.Ears(symbol: $0.symbol, text: "\($0.level)%", tint: Tone($0, settings.threshold).hex) },
      menubar: settings.menuBar ? weakestInUse.map { device in
        Output.MenuBar(symbol: device.symbol, text: "\(device.level)%", tint: low.contains(device) ? Tone.low.hex : nil)
      } : nil,
      home: Output.Home(view: home(devices, settings: settings, strings: strings)),
      tab: Output.Tab(title: strings.title, view: page(devices, settings: settings, strings: strings, now: now)),
      alerts: alerts.map { alert in
        Output.Alert(id: alert.id, title: strings.alertTitle(alert), body: strings.alertBody(alert), symbol: alert.device.symbol,
                     tint: alert.severity == .critical ? Tone.low.hex : Tone.fair.hex)
      }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encoder.encode(output)) ?? Data("{}".utf8)
  }

  /// A header, then the four weakest devices: symbol and name on the left, level on the right.
  static func home(_ devices: [BatteryDevice], settings: BatterySettings, strings: Strings) -> Node {
    let header = Node.hstack(spacing: 5, [.symbol("battery.75percent", size: 10, color: "cyan"),
                                          .text(strings.title, size: 11, weight: "semibold")])
    guard !devices.isEmpty else { return .vstack(spacing: 5, [header, .text(strings.noDevices, size: 10, color: "tertiary")]) }
    let rows = devices.prefix(4).map { device in
      let tone = Tone(device, settings.threshold)
      var row: [Node] = [.symbol(device.symbol, size: 10, color: "secondary"), .text(device.name, size: 11, lines: 1), .spacer]
      if device.charging { row.append(.symbol("bolt.fill", size: 8, color: "green")) }
      row.append(.text("\(device.level)%", size: 11, weight: "medium", color: tone.textColor, mono: true))
      return Node.hstack(spacing: 5, row)
    }
    return .vstack(spacing: 5, [header] + rows)
  }

  /// A card per device (level, bar, AirPods' parts, charging), then when it was read and a refresh button.
  static func page(_ devices: [BatteryDevice], settings: BatterySettings, strings: Strings, now: Date) -> Node {
    guard !devices.isEmpty else { return .vstack(spacing: 6, [.text(strings.noDevices, size: 11, color: "secondary")]) }
    let cards = devices.map { device in
      let tone = Tone(device, settings.threshold)
      var children: [Node] = [
        .hstack(spacing: 5, [
          .symbol(device.symbol, size: 12, color: "secondary"),
          .text(device.name, size: 12, weight: "semibold", lines: 1),
          .spacer,
          .text("\(device.level)%", size: 12, weight: "semibold", color: tone.textColor, mono: true),
        ]),
        .progress(Double(device.level) / 100, color: tone.name),
      ]
      var details: [Node] = device.parts.count > 1
        ? device.parts.map { Node.text("\(strings.name(of: $0.part)) \($0.percent)%", size: 10, color: "tertiary", mono: true) }
        : []
      if device.charging {
        details += [.spacer, .hstack(spacing: 3, [.symbol("bolt.fill", size: 9, color: "green"), .text(strings.charging, size: 10, color: "green")])]
      }
      if !details.isEmpty { children.append(.hstack(spacing: 8, details)) }
      return Node.card(padding: 8, children)
    }
    let time = DateFormatter()
    time.dateFormat = "HH:mm"
    let footer = Node.hstack(spacing: 5, [
      .text(strings.updated(time.string(from: now)), size: 10, color: "tertiary"),
      .spacer,
      .hstack(spacing: 3, [.symbol("arrow.clockwise", size: 9, color: "secondary"), .text(strings.refresh, size: 10, color: "secondary")],
              action: Action(run: "refresh")),
    ])
    return .vstack(spacing: 6, [.grid(columns: cards.count > 4 ? 3 : 2, spacing: 5, cards), footer])
  }
}

/// How healthy a level is, in view colour names and in hex for the parts that take only hex.
enum Tone {
  case low, fair, good

  init(_ device: BatteryDevice, _ threshold: Int) {
    self = device.charging || device.level > threshold + 20 ? .good : device.level > threshold ? .fair : .low
  }

  var name: String {
    switch self {
    case .low: "red"
    case .fair: "orange"
    case .good: "green"
    }
  }

  var hex: String {
    switch self {
    case .low: "#E06C75"
    case .fair: "#D19A66"
    case .good: "#98C379"
    }
  }

  /// Healthy levels stay in the default text colour; only fair and low ones are coloured.
  var textColor: String? { self == .good ? nil : name }
}

/// The plugin's text in English or Chinese (ALTOOLS_LANG).
struct Strings {
  let chinese: Bool

  var title: String { chinese ? "电量" : "Battery" }
  var noDevices: String { chinese ? "没有设备上报电量" : "No devices report their battery" }
  var charging: String { chinese ? "充电中" : "Charging" }
  var refresh: String { chinese ? "刷新" : "Refresh" }

  func updated(_ time: String) -> String { chinese ? "更新于 \(time)" : "Updated \(time)" }

  func name(of part: BatteryReading.Part) -> String {
    switch part {
    case .left: chinese ? "左" : "Left"
    case .right: chinese ? "右" : "Right"
    case .case: chinese ? "充电盒" : "Case"
    case .single: ""
    }
  }

  func alertTitle(_ alert: LowBatteryAlert) -> String {
    let name = alert.device.name
    return switch alert.severity {
    case .low: chinese ? "\(name) 电量低" : "\(name) is low on battery"
    case .critical: chinese ? "\(name) 快没电了" : "\(name) is almost out of battery"
    }
  }

  /// The level (per bud for AirPods), and for a low alert a nudge to charge.
  func alertBody(_ alert: LowBatteryAlert) -> String {
    let device = alert.device
    let worn = device.parts.filter { $0.part != .case }
    let levels = worn.count > 1 ? worn.map { "\(name(of: $0.part)) \($0.percent)%" }.joined(separator: " · ") : nil
    switch (alert.severity, chinese) {
    case (.low, false): return levels.map { "\($0) — charge them soon." } ?? "\(device.level)% left — charge it soon."
    case (.low, true): return (levels ?? "剩余 \(device.level)%") + "，记得充电。"
    case (.critical, false): return levels.map { "\($0)." } ?? "Only \(device.level)% left."
    case (.critical, true): return (levels ?? "只剩 \(device.level)%") + "。"
    }
  }
}

/// A node of the view tree (PLUGINS.md › Views); unset properties are left out of the JSON.
struct Node: Encodable, Equatable {
  var type: String
  var text: String?
  var name: String?
  var size: Double?
  var weight: String?
  var color: String?
  var mono: Bool?
  var lines: Int?
  var spacing: Double?
  var columns: Int?
  var padding: Double?
  var value: Double?
  var action: Action?
  var children: [Node]?

  static let spacer = Node(type: "spacer")

  static func vstack(spacing: Double, _ children: [Node]) -> Node { Node(type: "vstack", spacing: spacing, children: children) }

  static func hstack(spacing: Double, _ children: [Node], action: Action? = nil) -> Node {
    Node(type: "hstack", spacing: spacing, action: action, children: children)
  }

  static func grid(columns: Int, spacing: Double, _ children: [Node]) -> Node {
    Node(type: "grid", spacing: spacing, columns: columns, children: children)
  }

  static func card(padding: Double, _ children: [Node]) -> Node { Node(type: "card", padding: padding, children: children) }

  static func text(_ text: String, size: Double, weight: String? = nil, color: String? = nil, mono: Bool? = nil, lines: Int? = nil) -> Node {
    Node(type: "text", text: text, size: size, weight: weight, color: color, mono: mono, lines: lines)
  }

  static func symbol(_ name: String, size: Double, color: String? = nil) -> Node { Node(type: "symbol", name: name, size: size, color: color) }

  static func progress(_ value: Double, color: String) -> Node { Node(type: "progress", color: color, value: value) }
}

struct Action: Encodable, Equatable {
  var run: String
}

struct Output: Encodable {
  var ears: Ears?
  var menubar: MenuBar?
  var home: Home
  var tab: Tab
  var alerts: [Alert]

  struct Ears: Encodable {
    var symbol: String
    var text: String
    var tint: String
  }

  struct MenuBar: Encodable {
    var symbol: String
    var text: String
    var tint: String?
  }

  struct Home: Encodable {
    var view: Node
  }

  struct Tab: Encodable {
    var title: String
    var view: Node
  }

  struct Alert: Encodable {
    var id: String
    var title: String
    var body: String
    var symbol: String
    var tint: String
  }
}
