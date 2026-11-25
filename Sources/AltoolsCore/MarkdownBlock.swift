import Foundation

/// Block structure of a chat answer in Markdown. Inline styles are left in the text.
public enum MarkdownBlock: Equatable, Sendable {
  case paragraph(String)
  case heading(Int, String)
  /// `indent` counts nesting levels (two spaces each).
  case bullet(marker: String, text: String, indent: Int)
  case quote(String)
  case code(language: String, code: String)

  public static func parse(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var code: [String]?
    var language = ""

    func flushParagraph() {
      if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
      paragraph = []
    }

    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        if let lines = code {
          blocks.append(.code(language: language, code: lines.joined(separator: "\n")))
          code = nil
        } else {
          flushParagraph()
          language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
          code = []
        }
        continue
      }
      if code != nil { code?.append(line); continue }

      let indent = (line.prefix { $0 == " " }.count) / 2
      if trimmed.isEmpty {
        flushParagraph()
      } else if let hashes = trimmed.firstIndex(where: { $0 != "#" }), trimmed.hasPrefix("#"),
                trimmed[hashes] == " " {
        flushParagraph()
        let level = trimmed.distance(from: trimmed.startIndex, to: hashes)
        blocks.append(.heading(level, String(trimmed[hashes...]).trimmingCharacters(in: .whitespaces)))
      } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
        flushParagraph()
        blocks.append(.bullet(marker: "•", text: String(trimmed.dropFirst(2)), indent: indent))
      } else if let dot = trimmed.firstIndex(of: "."), trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty,
                trimmed[trimmed.index(after: dot)...].hasPrefix(" ") {
        flushParagraph()
        blocks.append(.bullet(marker: String(trimmed[...dot]), text: String(trimmed[trimmed.index(dot, offsetBy: 2)...]), indent: indent))
      } else if trimmed.hasPrefix(">") {
        flushParagraph()
        blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
      } else {
        paragraph.append(trimmed)
      }
    }
    // An unterminated fence while streaming still shows as code.
    if let lines = code { blocks.append(.code(language: language, code: lines.joined(separator: "\n"))) }
    flushParagraph()
    return blocks
  }
}
