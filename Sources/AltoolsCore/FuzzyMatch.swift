import Foundation

public enum FuzzyMatch {
  /// Scores how well `query` matches `candidate` as an in-order subsequence.
  ///
  /// Returns `nil` when not every query character appears in order. Higher is better:
  /// a prefix match beats a word-start match, which beats a scattered match.
  public static func score(_ query: String, _ candidate: String) -> Int? {
    let q = Array(query.lowercased().filter { !$0.isWhitespace })
    if q.isEmpty { return 0 }
    let original = Array(candidate)
    let c = Array(candidate.lowercased())
    guard original.count == c.count else { return nil }

    var score = 0
    var qi = 0
    var previousMatch = -2
    for (ci, ch) in c.enumerated() where qi < q.count {
      guard ch == q[qi] else { continue }
      if ci == 0 {
        score += 30
      } else if isWordStart(original, ci) {
        score += 15
      }
      if ci == previousMatch + 1 { score += 10 }
      score += 1
      previousMatch = ci
      qi += 1
    }
    guard qi == q.count else { return nil }
    if c.starts(with: q) { score += 50 }
    // Prefer shorter candidates when everything else ties.
    return score - c.count / 4
  }

  private static func isWordStart(_ chars: [Character], _ index: Int) -> Bool {
    let prev = chars[index - 1]
    let cur = chars[index]
    return prev == " " || prev == "-" || prev == "_" || prev == "."
      || (prev.isLowercase && cur.isUppercase)
  }
}
