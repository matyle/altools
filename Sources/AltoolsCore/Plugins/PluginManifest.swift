import Foundation

/// A plugin's `plugin.json`: what it is, how to run it and where its output may appear.
/// The full contract is in PLUGINS.md.
public struct PluginManifest: Equatable, Sendable {
  /// The plugin API this build speaks; manifests asking for a newer one are refused.
  public static let apiVersion = 1
  public static let minimumInterval: TimeInterval = 10
  public static let defaultInterval: TimeInterval = 300
  public static let defaultTimeout: TimeInterval = 20
  public static let maximumTimeout: TimeInterval = 120

  /// Folder-safe identifier: lowercase letters, digits and dashes.
  public var id: String
  public var name: String
  public var version: String
  public var author: String?
  public var summary: String?
  public var api: Int
  /// SF Symbol name.
  public var icon: String
  /// "#RRGGBB", or nil for the default accent.
  public var tint: String?
  /// Executable path relative to the plugin folder.
  public var run: String
  /// Seconds between refreshes, at least `minimumInterval`.
  public var interval: TimeInterval
  /// Seconds a run may take before it is stopped, 1...`maximumTimeout`.
  public var timeout: TimeInterval
  public var slots: Set<PluginSlot>
  public var settings: [PluginSetting]

  public static func decode(_ data: Data) throws -> PluginManifest {
    let raw: Raw
    do {
      raw = try JSONDecoder().decode(Raw.self, from: data)
    } catch {
      throw PluginManifestError.unreadable(error.localizedDescription)
    }
    guard let id = raw.id, isValidID(id) else { throw PluginManifestError.invalidID(raw.id ?? "") }
    let api = raw.api ?? apiVersion
    guard api <= apiVersion else { throw PluginManifestError.unsupportedAPI(api) }
    guard let run = raw.run?.trimmingCharacters(in: .whitespaces), !run.isEmpty, !run.hasPrefix("/"), !run.contains("..") else {
      throw PluginManifestError.invalidRun(raw.run ?? "")
    }
    // Unknown slots are skipped so a manifest written for a later API still loads.
    let slots = Set((raw.slots ?? PluginSlot.allCases.map(\.rawValue)).compactMap(PluginSlot.init(rawValue:)))
    return PluginManifest(
      id: id,
      name: raw.name?.nonEmpty ?? id,
      version: raw.version?.nonEmpty ?? "0.0.0",
      author: raw.author?.nonEmpty,
      summary: raw.description?.nonEmpty,
      api: api,
      icon: raw.icon?.nonEmpty ?? "puzzlepiece.extension.fill",
      tint: raw.tint.flatMap(normalizedHex),
      run: run,
      interval: max(minimumInterval, raw.interval ?? defaultInterval),
      timeout: min(maximumTimeout, max(1, raw.timeout ?? defaultTimeout)),
      slots: slots,
      settings: (raw.settings ?? []).filter { isValidSettingKey($0.key) }
    )
  }

  public static func isValidID(_ id: String) -> Bool {
    !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
  }

  static func isValidSettingKey(_ key: String) -> Bool {
    !key.isEmpty && key.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
  }

  /// "#abc" / "abcdef" → "#AABBCC"; nil when it isn't a hex colour.
  public static func normalizedHex(_ value: String) -> String? {
    var hex = value.trimmingCharacters(in: .whitespaces).uppercased()
    if hex.hasPrefix("#") { hex.removeFirst() }
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
    return "#" + hex
  }

  private struct Raw: Decodable {
    var id: String?
    var name: String?
    var version: String?
    var author: String?
    var description: String?
    var api: Int?
    var icon: String?
    var tint: String?
    var run: String?
    var interval: TimeInterval?
    var timeout: TimeInterval?
    var slots: [String]?
    var settings: [PluginSetting]?
  }
}

public enum PluginSlot: String, CaseIterable, Sendable {
  /// Short status beside the notch when nothing more urgent is live.
  case ears
  /// A card on the notch's Home tab.
  case home
  /// A page under the notch's Plugins tab.
  case tab
  /// Cards that drop from the notch once per alert id.
  case alerts
}

/// One field the user fills in under Settings; the value reaches the script as
/// `ALTOOLS_SETTING_<KEY>`. Secrets are kept in the Keychain.
public struct PluginSetting: Decodable, Equatable, Sendable {
  public enum Kind: String, Decodable, Sendable { case text, secret, toggle, choice }

  public var key: String
  public var title: String
  public var kind: Kind
  public var options: [String]
  public var defaultValue: String?
  public var note: String?

  public var environmentName: String { "ALTOOLS_SETTING_" + key.uppercased() }

  enum CodingKeys: String, CodingKey { case key, title, type, options, `default`, note }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    key = try c.decode(String.self, forKey: .key)
    title = (try? c.decode(String.self, forKey: .title)) ?? key
    kind = (try? c.decode(Kind.self, forKey: .type)) ?? .text
    options = (try? c.decode([String].self, forKey: .options)) ?? []
    if let text = try? c.decode(String.self, forKey: .default) {
      defaultValue = text
    } else if let flag = try? c.decode(Bool.self, forKey: .default) {
      defaultValue = flag ? "1" : "0"
    } else {
      defaultValue = nil
    }
    note = try? c.decode(String.self, forKey: .note)
  }
}

public enum PluginManifestError: Error, Equatable, CustomStringConvertible {
  case unreadable(String)
  case invalidID(String)
  case invalidRun(String)
  case unsupportedAPI(Int)

  public var description: String {
    switch self {
    case .unreadable(let reason): "plugin.json can't be read: \(reason)"
    case .invalidID(let id): "\"id\" must be lowercase letters, digits and dashes (got \"\(id)\")"
    case .invalidRun(let run): "\"run\" must be a path inside the plugin folder (got \"\(run)\")"
    case .unsupportedAPI(let api): "needs plugin API \(api); this Altools speaks \(PluginManifest.apiVersion)"
    }
  }
}

extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
