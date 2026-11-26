import Foundation

/// What a plugin run prints on stdout. Every part is optional; parts for slots the
/// manifest doesn't list are ignored by the host. See PLUGINS.md.
public struct PluginOutput: Equatable, Sendable {
  public var ears: Ears?
  public var home: Card?
  public var tab: Page?
  public var alerts: [Alert]
  /// Seconds until the next refresh, overriding the manifest's interval once.
  public var next: TimeInterval?

  public init(ears: Ears? = nil, home: Card? = nil, tab: Page? = nil, alerts: [Alert] = [], next: TimeInterval? = nil) {
    self.ears = ears
    self.home = home
    self.tab = tab
    self.alerts = alerts
    self.next = next
  }

  /// The two sides of the notch. Either the simple form (`symbol` on the left, `text` on the right)
  /// or views for `left` / `right`; views win when both are given.
  public struct Ears: Equatable, Sendable {
    public var symbol: String?
    public var text: String?
    public var tint: String?
    public var left: PluginNode?
    public var right: PluginNode?
    /// Points per side, 30–140; nil sizes the simple form to its text and views to 64.
    public var width: Double?

    public init(symbol: String? = nil, text: String? = nil, tint: String? = nil,
                left: PluginNode? = nil, right: PluginNode? = nil, width: Double? = nil) {
      self.symbol = symbol
      self.text = text
      self.tint = tint
      self.left = left
      self.right = right
      self.width = width
    }

    /// Width of each side: the given width, 64 for views, or enough for the text.
    public var sideWidth: Double {
      if let width { return width }
      if left != nil || right != nil { return 64 }
      let characters = Double((text ?? "").count)
      return min(max(30 + characters * 6.8, 44), 140)
    }
  }

  public struct Card: Equatable, Sendable {
    public var title: String?
    public var rows: [Row]
    /// The plugin's own layout; drawn instead of `rows` when present.
    public var view: PluginNode?

    public init(title: String? = nil, rows: [Row] = [], view: PluginNode? = nil) {
      self.title = title
      self.rows = rows
      self.view = view
    }
  }

  public struct Page: Equatable, Sendable {
    public var title: String?
    public var sections: [Section]
    /// The plugin's own layout; drawn instead of `sections` when present.
    public var view: PluginNode?

    public init(title: String? = nil, sections: [Section] = [], view: PluginNode? = nil) {
      self.title = title
      self.sections = sections
      self.view = view
    }
  }

  public struct Section: Equatable, Sendable {
    public var title: String?
    public var rows: [Row]

    public init(title: String? = nil, rows: [Row]) {
      self.title = title
      self.rows = rows
    }
  }

  public struct Row: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    public var symbol: String?
    public var tint: String?
    /// Short text on the right, e.g. a time or a number.
    public var value: String?
    public var action: PluginAction?

    public init(title: String, subtitle: String? = nil, symbol: String? = nil, tint: String? = nil, value: String? = nil, action: PluginAction? = nil) {
      self.title = title
      self.subtitle = subtitle
      self.symbol = symbol
      self.tint = tint
      self.value = value
      self.action = action
    }
  }

  public struct Alert: Equatable, Sendable {
    /// Announced once per id; a later run repeating it shows nothing new.
    public var id: String
    public var title: String
    public var body: String?
    public var symbol: String?
    public var tint: String?
    public var action: PluginAction?

    public init(id: String, title: String, body: String? = nil, symbol: String? = nil, tint: String? = nil, action: PluginAction? = nil) {
      self.id = id
      self.title = title
      self.body = body
      self.symbol = symbol
      self.tint = tint
      self.action = action
    }
  }

  /// Parses stdout. Unknown fields are ignored; a malformed part is dropped rather than
  /// failing the whole output, so one bad row doesn't blank the plugin.
  public static func decode(_ data: Data) throws -> PluginOutput {
    let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    // A script may log before its JSON; the last line holding an object is the output.
    let candidate = trimmed.hasPrefix("{") ? trimmed : (trimmed.split(separator: "\n").last(where: { $0.hasPrefix("{") }).map(String.init) ?? trimmed)
    guard let object = try? JSONSerialization.jsonObject(with: Data(candidate.utf8)) as? [String: Any] else {
      throw PluginOutputError.notJSONObject(String(candidate.prefix(200)))
    }
    return PluginOutput(
      ears: (object["ears"] as? [String: Any]).flatMap(ears),
      home: (object["home"] as? [String: Any]).map(card),
      tab: (object["tab"] as? [String: Any]).map(page),
      alerts: (object["alerts"] as? [[String: Any]] ?? []).compactMap(alert),
      next: number(object["next"]).map { max(PluginManifest.minimumInterval, $0) }
    )
  }

  private static func ears(_ o: [String: Any]) -> Ears? {
    let left = PluginNode.decode(o["left"]), right = PluginNode.decode(o["right"])
    let text = string(o["text"]).map { String($0.prefix(24)) }
    guard text != nil || left != nil || right != nil else { return nil }
    return Ears(symbol: string(o["symbol"]), text: text, tint: string(o["tint"]).flatMap(PluginManifest.normalizedHex),
                left: left, right: right, width: number(o["width"]).map { min(max($0, 30), 140) })
  }

  private static func card(_ o: [String: Any]) -> Card {
    Card(title: string(o["title"]), rows: rows(o["rows"]), view: PluginNode.decode(o["view"]))
  }

  /// `sections`, or plain `rows` as a single untitled section.
  private static func page(_ o: [String: Any]) -> Page {
    let sections = (o["sections"] as? [[String: Any]] ?? []).map { Section(title: string($0["title"]), rows: rows($0["rows"])) }
    let loose = rows(o["rows"])
    return Page(title: string(o["title"]), sections: loose.isEmpty ? sections : [Section(title: nil, rows: loose)] + sections,
                view: PluginNode.decode(o["view"]))
  }

  private static func rows(_ value: Any?) -> [Row] {
    (value as? [[String: Any]] ?? []).compactMap { o in
      guard let title = string(o["title"]) else { return nil }
      return Row(title: title, subtitle: string(o["subtitle"]), symbol: string(o["symbol"]),
                 tint: string(o["tint"]).flatMap(PluginManifest.normalizedHex), value: string(o["value"]),
                 action: (o["action"] as? [String: Any]).flatMap(PluginAction.init(json:)))
    }
  }

  private static func alert(_ o: [String: Any]) -> Alert? {
    guard let id = string(o["id"]), let title = string(o["title"]) else { return nil }
    return Alert(id: id, title: title, body: string(o["body"]), symbol: string(o["symbol"]),
                 tint: string(o["tint"]).flatMap(PluginManifest.normalizedHex),
                 action: (o["action"] as? [String: Any]).flatMap(PluginAction.init(json:)))
  }

  /// Strings, and numbers or booleans written where text was expected.
  static func string(_ value: Any?) -> String? {
    switch value {
    case let text as String: return text.nonEmpty
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
      return number.stringValue
    default: return nil
    }
  }

  static func number(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber: return number.doubleValue
    case let text as String: return Double(text)
    default: return nil
    }
  }
}

/// What happens when a row or alert is clicked.
public enum PluginAction: Equatable, Sendable {
  /// Opens a URL: a web page, an app's own scheme, or a file:// path.
  case open(URL)
  /// Runs the plugin again with `ALTOOLS_EVENT=action:<id>`; its output replaces the current one.
  case run(String)
  /// Copies text to the clipboard.
  case copy(String)

  public init?(json o: [String: Any]) {
    if let raw = PluginOutput.string(o["open"]), let url = URL(string: raw), url.scheme != nil {
      self = .open(url)
    } else if let id = PluginOutput.string(o["run"]) {
      self = .run(id)
    } else if let text = PluginOutput.string(o["copy"]) {
      self = .copy(text)
    } else {
      return nil
    }
  }
}

public enum PluginOutputError: Error, Equatable, CustomStringConvertible {
  case notJSONObject(String)

  public var description: String {
    switch self {
    case .notJSONObject(let start): "output isn't a JSON object: \(start.isEmpty ? "(empty)" : start)"
    }
  }
}

/// Why a plugin was run.
public enum PluginEvent: Equatable, Sendable {
  case refresh
  /// The user clicked an element whose action is `{"run": id}`.
  case action(String)
  /// Another program opened `altools://plugin/<id>/run?event=<name>`.
  case trigger(String)

  public var value: String {
    switch self {
    case .refresh: "refresh"
    case .action(let id): "action:\(id)"
    case .trigger(let name): "trigger:\(name)"
    }
  }
}

/// The environment a plugin run gets on top of the user's PATH and proxy.
public enum PluginEnvironment {
  public static func variables(manifest: PluginManifest, pluginDirectory: String, dataDirectory: String,
                               event: PluginEvent, language: String, settings: [String: String]) -> [String: String] {
    var env = [
      "ALTOOLS_API": String(PluginManifest.apiVersion),
      "ALTOOLS_EVENT": event.value,
      "ALTOOLS_PLUGIN_ID": manifest.id,
      "ALTOOLS_PLUGIN_DIR": pluginDirectory,
      "ALTOOLS_DATA_DIR": dataDirectory,
      "ALTOOLS_LANG": language,
    ]
    for setting in manifest.settings {
      env[setting.environmentName] = settings[setting.key] ?? setting.defaultValue ?? ""
    }
    return env
  }
}
