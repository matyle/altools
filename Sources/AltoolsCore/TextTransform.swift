import Foundation

/// Local text transforms offered on a text selection. None of these call the network.
public enum TextTransform: String, CaseIterable, Identifiable, Sendable {
  case uppercase, lowercase, titleCase, trimWhitespace
  case urlEncode, urlDecode, base64Encode, base64Decode
  case jsonPretty, count

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .uppercase: "UPPERCASE"
    case .lowercase: "lowercase"
    case .titleCase: "Title Case"
    case .trimWhitespace: "Trim whitespace"
    case .urlEncode: "URL encode"
    case .urlDecode: "URL decode"
    case .base64Encode: "Base64 encode"
    case .base64Decode: "Base64 decode"
    case .jsonPretty: "Format JSON"
    case .count: "Count"
    }
  }

  /// `count` produces a summary meant for display, not for replacing the selection.
  public var replacesSelection: Bool { self != .count }

  /// Throws `TextTransformError` when the input is not valid for this transform
  /// (bad Base64, bad percent-encoding, invalid JSON).
  public func apply(_ text: String) throws -> String {
    switch self {
    case .uppercase: return text.uppercased()
    case .lowercase: return text.lowercased()
    case .titleCase: return text.capitalized
    case .trimWhitespace:
      return text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    case .urlEncode:
      var allowed = CharacterSet.urlQueryAllowed
      allowed.remove(charactersIn: "&=+?#")
      return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    case .urlDecode:
      guard let decoded = text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
        throw TextTransformError.invalidInput("Not valid percent-encoding")
      }
      return decoded
    case .base64Encode:
      return Data(text.utf8).base64EncodedString()
    case .base64Decode:
      let compact = text.filter { !$0.isWhitespace }
      let padded = compact.padding(toLength: (compact.count + 3) / 4 * 4, withPad: "=", startingAt: 0)
      guard let data = Data(base64Encoded: padded), let decoded = String(data: data, encoding: .utf8) else {
        throw TextTransformError.invalidInput("Not valid Base64 text")
      }
      return decoded
    case .jsonPretty:
      guard let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            let result = String(data: pretty, encoding: .utf8) else {
        throw TextTransformError.invalidInput("Not valid JSON")
      }
      return result
    case .count:
      let words = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).count
      let cjk = text.unicodeScalars.filter(Self.isCJK).count
      let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
      var parts = ["\(text.count) characters", "\(words) words", "\(lines) lines"]
      if cjk > 0 { parts.append("\(cjk) CJK characters") }
      return parts.joined(separator: " · ")
    }
  }

  static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
      || (0x3040...0x30FF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
  }

  /// True when more than a third of the letters are CJK, used to pick the
  /// translation direction.
  public static func isMostlyCJK(_ text: String) -> Bool {
    let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
    guard !letters.isEmpty else { return false }
    return Double(letters.filter(isCJK).count) / Double(letters.count) > 0.33
  }
}

public enum TextTransformError: LocalizedError, Equatable {
  case invalidInput(String)
  public var errorDescription: String? {
    switch self { case .invalidInput(let message): message }
  }
}
