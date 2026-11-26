import Foundation

/// A plugin's own layout, drawn natively by Altools like a widget: stacks, grids and cards of text,
/// symbols, images, badges, progress bars and sparklines. Any node may carry an action. Unknown types
/// and properties are skipped so a plugin written for a later Altools still shows what it can.
public indirect enum PluginNode: Equatable, Sendable {
  case stack(axis: Axis, alignment: Alignment, spacing: Double?, children: [PluginNode], style: Style)
  case grid(columns: Int, spacing: Double?, children: [PluginNode], style: Style)
  case card(padding: Double?, color: PluginColor?, children: [PluginNode], style: Style)
  case text(String, size: Double?, weight: Weight, color: PluginColor?, mono: Bool, lines: Int?, style: Style)
  case symbol(String, size: Double?, color: PluginColor?, style: Style)
  case image(url: String, radius: Double?, style: Style)
  case badge(String, color: PluginColor?, style: Style)
  case progress(Double, color: PluginColor?, style: Style)
  case sparkline([Double], color: PluginColor?, style: Style)
  case spacer
  case divider

  public enum Axis: Equatable, Sendable { case vertical, horizontal }
  public enum Alignment: String, Equatable, Sendable { case leading, center, trailing, top, bottom }
  public enum Weight: String, Equatable, Sendable { case regular, medium, semibold, bold }

  /// Properties every node accepts.
  public struct Style: Equatable, Sendable {
    public var width: Double?
    public var height: Double?
    /// Fills the available width.
    public var flex = false
    public var opacity: Double?
    public var action: PluginAction?

    public init(width: Double? = nil, height: Double? = nil, flex: Bool = false, opacity: Double? = nil, action: PluginAction? = nil) {
      self.width = width
      self.height = height
      self.flex = flex
      self.opacity = opacity
      self.action = action
    }
  }

  public static let maximumDepth = 12
  public static let maximumNodes = 400

  /// Parses a node tree from decoded JSON; nil when `json` isn't a node. Children past the depth or
  /// node limits are dropped.
  public static func decode(_ json: Any?) -> PluginNode? {
    var budget = maximumNodes
    return node(json, depth: 0, budget: &budget)
  }

  private static func node(_ json: Any?, depth: Int, budget: inout Int) -> PluginNode? {
    guard depth <= maximumDepth, budget > 0, let o = json as? [String: Any], let type = PluginOutput.string(o["type"]) else { return nil }
    budget -= 1
    let style = Style(
      width: PluginOutput.number(o["width"]).map { min(max($0, 0), 1_000) },
      height: PluginOutput.number(o["height"]).map { min(max($0, 0), 1_000) },
      flex: (o["flex"] as? Bool) ?? false,
      opacity: PluginOutput.number(o["opacity"]).map { min(max($0, 0), 1) },
      action: (o["action"] as? [String: Any]).flatMap(PluginAction.init(json:))
    )
    func children() -> [PluginNode] {
      var result: [PluginNode] = []
      for child in o["children"] as? [Any] ?? [] {
        guard budget > 0 else { break }
        if let n = node(child, depth: depth + 1, budget: &budget) { result.append(n) }
      }
      return result
    }
    let color = PluginColor(PluginOutput.string(o["color"]))
    let size = PluginOutput.number(o["size"])
    let spacing = PluginOutput.number(o["spacing"]).map { min(max($0, 0), 40) }
    switch type {
    case "vstack", "hstack":
      let axis: Axis = type == "vstack" ? .vertical : .horizontal
      let fallback: Alignment = axis == .vertical ? .leading : .center
      return .stack(axis: axis, alignment: PluginOutput.string(o["align"]).flatMap(Alignment.init(rawValue:)) ?? fallback,
                    spacing: spacing, children: children(), style: style)
    case "grid":
      let columns = Int(PluginOutput.number(o["columns"]) ?? 2)
      return .grid(columns: min(max(columns, 1), 6), spacing: spacing, children: children(), style: style)
    case "card":
      return .card(padding: PluginOutput.number(o["padding"]).map { min(max($0, 0), 30) }, color: color, children: children(), style: style)
    case "text":
      guard let text = PluginOutput.string(o["text"]) else { return nil }
      return .text(text, size: size.map { min(max($0, 9), 28) },
                   weight: PluginOutput.string(o["weight"]).flatMap(Weight.init(rawValue:)) ?? .regular,
                   color: color, mono: (o["mono"] as? Bool) ?? false,
                   lines: PluginOutput.number(o["lines"]).map { max(1, Int($0)) }, style: style)
    case "symbol":
      guard let name = PluginOutput.string(o["name"]) else { return nil }
      return .symbol(name, size: size.map { min(max($0, 6), 40) }, color: color, style: style)
    case "image":
      guard let url = PluginOutput.string(o["url"]) else { return nil }
      return .image(url: url, radius: PluginOutput.number(o["radius"]), style: style)
    case "badge":
      guard let text = PluginOutput.string(o["text"]) else { return nil }
      return .badge(String(text.prefix(16)), color: color, style: style)
    case "progress":
      return .progress(min(max(PluginOutput.number(o["value"]) ?? 0, 0), 1), color: color, style: style)
    case "sparkline":
      let values = (o["values"] as? [Any] ?? []).compactMap(PluginOutput.number).suffix(500)
      guard values.count >= 2 else { return nil }
      return .sparkline(Array(values), color: color, style: style)
    case "spacer": return .spacer
    case "divider": return .divider
    default: return nil
    }
  }
}

/// A colour a plugin names: "#RRGGBB", or a theme name the app maps to its palette.
public enum PluginColor: Equatable, Sendable {
  case hex(String)
  case named(Name)

  public enum Name: String, Sendable, CaseIterable {
    case primary, secondary, tertiary, green, red, orange, yellow, blue, purple, cyan
  }

  public init?(_ value: String?) {
    guard let value else { return nil }
    if let name = Name(rawValue: value.lowercased()) {
      self = .named(name)
    } else if let hex = PluginManifest.normalizedHex(value) {
      self = .hex(hex)
    } else {
      return nil
    }
  }
}
