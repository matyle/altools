import Foundation

/// Evaluates arithmetic typed into the launcher.
///
/// Supports `+ - * / % ^`, parentheses, unary minus, the constants `pi` and `e`,
/// and the functions `sqrt abs sin cos tan log ln round floor ceil`.
/// `%` is modulo, not percent. Returns `nil` for anything that is not a complete,
/// finite expression, so callers can treat `nil` as "not a calculation".
public enum Calculator {
  public static func evaluate(_ input: String) -> Double? {
    var parser = Parser(Array(input.lowercased().replacingOccurrences(of: "×", with: "*")
      .replacingOccurrences(of: "÷", with: "/")))
    guard let value = parser.parseExpression() else { return nil }
    parser.skipSpaces()
    guard parser.atEnd, value.isFinite else { return nil }
    return value
  }

  /// True when the input looks like a calculation rather than a bare number or word,
  /// so typing "2024" or "pi" in the launcher does not show a calculator row.
  public static func looksLikeExpression(_ input: String) -> Bool {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    guard trimmed.contains(where: \.isNumber) else { return false }
    return trimmed.dropFirst().contains(where: { "+-*/%^()×÷".contains($0) })
      || trimmed.contains("(")
  }

  public static func format(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 {
      return String(Int64(value))
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 10
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  private struct Parser {
    let chars: [Character]
    var pos = 0
    init(_ chars: [Character]) { self.chars = chars }

    var atEnd: Bool { pos >= chars.count }

    mutating func skipSpaces() {
      while !atEnd, chars[pos] == " " { pos += 1 }
    }

    mutating func peek() -> Character? {
      skipSpaces()
      return atEnd ? nil : chars[pos]
    }

    // expression := term (('+' | '-') term)*
    mutating func parseExpression() -> Double? {
      guard var lhs = parseTerm() else { return nil }
      while let op = peek(), op == "+" || op == "-" {
        pos += 1
        guard let rhs = parseTerm() else { return nil }
        lhs = op == "+" ? lhs + rhs : lhs - rhs
      }
      return lhs
    }

    // term := unary (('*' | '/' | '%') unary)*
    mutating func parseTerm() -> Double? {
      guard var lhs = parseUnary() else { return nil }
      while let op = peek(), op == "*" || op == "/" || op == "%" {
        pos += 1
        guard let rhs = parseUnary() else { return nil }
        switch op {
        case "*": lhs *= rhs
        case "/": lhs /= rhs
        default: lhs = lhs.truncatingRemainder(dividingBy: rhs)
        }
      }
      return lhs
    }

    // unary := ('-' | '+') unary | power   — so -2^2 is -(2^2)
    mutating func parseUnary() -> Double? {
      if peek() == "-" {
        pos += 1
        return parseUnary().map { -$0 }
      }
      if peek() == "+" {
        pos += 1
        return parseUnary()
      }
      return parsePower()
    }

    // power := primary ('^' unary)?   (right-associative; 2^-1 allowed)
    mutating func parsePower() -> Double? {
      guard let base = parsePrimary() else { return nil }
      if peek() == "^" {
        pos += 1
        guard let exponent = parseUnary() else { return nil }
        return pow(base, exponent)
      }
      return base
    }

    mutating func parsePrimary() -> Double? {
      guard let c = peek() else { return nil }
      if c == "(" {
        pos += 1
        let value = parseExpression()
        guard peek() == ")" else { return nil }
        pos += 1
        return value
      }
      if c.isNumber || c == "." { return parseNumber() }
      if c.isLetter { return parseIdentifier() }
      return nil
    }

    mutating func parseNumber() -> Double? {
      let start = pos
      while !atEnd, chars[pos].isNumber || chars[pos] == "." || chars[pos] == "," { pos += 1 }
      let text = String(chars[start..<pos]).replacingOccurrences(of: ",", with: "")
      return Double(text)
    }

    mutating func parseIdentifier() -> Double? {
      let start = pos
      while !atEnd, chars[pos].isLetter { pos += 1 }
      let name = String(chars[start..<pos])
      switch name {
      case "pi": return Double.pi
      case "e": return M_E
      default: break
      }
      let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "abs": { abs($0) },
        "sin": sin, "cos": cos, "tan": tan,
        "log": log10, "ln": log,
        "round": { $0.rounded() }, "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) },
      ]
      guard let fn = functions[name], peek() == "(" else { return nil }
      pos += 1
      guard let arg = parseExpression(), peek() == ")" else { return nil }
      pos += 1
      return fn(arg)
    }
  }
}
