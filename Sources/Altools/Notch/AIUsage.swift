import Foundation

/// Plan quotas for Claude Code and Codex, as their own `/usage` shows them.
///
/// Claude: the OAuth sign-in Claude Code keeps in the keychain is read (only after the
/// user clicks Connect, and macOS asks them to allow it) and sent to Anthropic's usage
/// endpoint, the same one Claude Code calls. Tokens used today come from the local
/// transcripts in ~/.claude/projects. Codex: the latest rate-limit snapshot it writes
/// into its session logs in ~/.codex/sessions.
final class AIUsage: ObservableObject {
  struct Window: Identifiable, Equatable {
    var name: String
    /// 0…100
    var percent: Double
    var resetsAt: Date?
    var id: String { name }
  }

  enum Status: Equatable {
    case idle, loading, ok
    case notInstalled, notConnected, signedOut(hint: String), noData(String), failed(String)
  }

  struct Provider: Equatable {
    var status: Status = .idle
    var plan = ""
    var windows: [Window] = []
    var tokensToday: Int?
    var updated: Date?
  }

  @Published private(set) var claude = Provider()
  @Published private(set) var codex = Provider()
  private var lastRefresh = Date.distantPast

  #if DEBUG
  func loadDemo() {
    lastRefresh = Date()
    claude = Provider(status: .ok, plan: "Max", windows: [
      Window(name: "5 hours", percent: 46, resetsAt: Date().addingTimeInterval(7800)),
      Window(name: "This week", percent: 18, resetsAt: Date().addingTimeInterval(86400 * 4)),
    ], tokensToday: 12_400_000, updated: Date())
    codex = Provider(status: .noData("No plan quota in Codex's logs (API-key sign-in?)"))
  }
  #endif

  /// Refreshes at most once a minute unless forced.
  func refresh(force: Bool = false) {
    guard force || Date().timeIntervalSince(lastRefresh) > 60 else { return }
    lastRefresh = Date()
    refreshClaude()
    refreshCodex()
  }

  func connectClaude() {
    AppSettings.shared.claudeUsageConnected = true
    refresh(force: true)
  }

  /// The most-used window across both tools, for the collapsed notch's warning.
  var highest: (tool: String, window: Window)? {
    let all = claude.windows.map { ("Claude", $0) } + codex.windows.map { ("Codex", $0) }
    return all.max { $0.1.percent < $1.1.percent }.map { (tool: $0.0, window: $0.1) }
  }

  // MARK: Claude

  private func refreshClaude() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    // Both CLIs keep their state in a dot-folder; checking it avoids a slow login-shell PATH lookup here.
    let installed = FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path)
    guard installed else { claude.status = .notInstalled; return }
    if claude.windows.isEmpty { claude.status = .loading }

    DispatchQueue.global(qos: .utility).async { [weak self] in
      let tokens = Self.claudeTokensToday()
      DispatchQueue.main.async { self?.claude.tokensToday = tokens }
    }

    guard AppSettings.shared.claudeUsageConnected else {
      claude.status = .notConnected
      return
    }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let credentials = Self.claudeCredentials() else {
        DispatchQueue.main.async { self?.claude.status = .signedOut(hint: "claude") }
        return
      }
      var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
      request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
      request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
      request.timeoutInterval = 15
      ProxySession.shared.dataTask(with: request) { data, response, error in
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        DispatchQueue.main.async {
          guard let self else { return }
          self.claude.plan = credentials.plan
          if let error {
            self.claude.status = .failed(error.localizedDescription)
          } else if code == 401 || code == 403 {
            // The token expired; Claude Code refreshes it on its next run, so read the keychain again next time.
            Self.cachedCredentials = nil
            self.claude.status = .signedOut(hint: "claude")
          } else if code != 200 || parsed == nil {
            self.claude.status = .failed("HTTP \(code)")
          } else {
            self.claude.windows = Self.claudeWindows(parsed!)
            self.claude.status = self.claude.windows.isEmpty ? .noData("No usage API for this plan") : .ok
            self.claude.updated = Date()
          }
        }
      }.resume()
    }
  }

  static func claudeWindows(_ json: [String: Any]) -> [Window] {
    let names = [("five_hour", "5 hours"), ("seven_day", "This week"),
                 ("seven_day_opus", "Opus · week"), ("seven_day_sonnet", "Sonnet · week")]
    return names.compactMap { key, name in
      guard let window = json[key] as? [String: Any], let utilization = window["utilization"] as? Double else { return nil }
      return Window(name: name, percent: utilization, resetsAt: (window["resets_at"] as? String).flatMap(parseISODate))
    }
  }

  /// Kept for this run so the keychain is read once, not on every refresh; cleared on 401.
  private static var cachedCredentials: (token: String, plan: String)?

  /// Claude Code stores its sign-in with /usr/bin/security, so that tool is on the item's
  /// access list and reads it without a password prompt; reading it in-process would ask
  /// every time Claude Code re-saves the item (each token refresh resets the list).
  private static func claudeCredentials() -> (token: String, plan: String)? {
    if let cachedCredentials { return cachedCredentials }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String else { return nil }
    let credentials = (token: token, plan: (oauth["subscriptionType"] as? String ?? "").capitalized)
    cachedCredentials = credentials
    return credentials
  }

  /// Input + output + cache tokens in today's transcripts, each API response counted once.
  static func claudeTokensToday() -> Int {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    let startOfDay = Calendar.current.startOfDay(for: Date())
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
    var seen = Set<String>()
    var total = 0
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
      guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            modified >= startOfDay, let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
      for line in content.split(separator: "\n") where line.contains("\"usage\"") {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let stamp = (json["timestamp"] as? String).flatMap(parseISODate), stamp >= startOfDay,
              let message = json["message"] as? [String: Any], let usage = message["usage"] as? [String: Any] else { continue }
        let key = "\(message["id"] ?? "")|\(json["requestId"] ?? "")"
        guard seen.insert(key).inserted else { continue }
        for field in ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"] {
          total += usage[field] as? Int ?? 0
        }
      }
    }
    return total
  }

  // MARK: Codex

  private func refreshCodex() {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    guard FileManager.default.fileExists(atPath: root.path) else {
      codex.status = .notInstalled
      return
    }
    if codex.windows.isEmpty { codex.status = .loading }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let snapshot = Self.codexSnapshot(root: root.appendingPathComponent("sessions"))
      DispatchQueue.main.async {
        guard let self else { return }
        if let snapshot {
          self.codex.windows = snapshot.windows
          self.codex.plan = snapshot.plan
          self.codex.updated = snapshot.at
          self.codex.status = .ok
        } else {
          self.codex.status = .noData("No plan quota in Codex's logs (API-key sign-in?)")
        }
      }
    }
  }

  /// The newest rate-limit record across the 30 most recent session files.
  static func codexSnapshot(root: URL) -> (windows: [Window], plan: String, at: Date)? {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
    let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
      .map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
      .sorted { $0.1 > $1.1 }.prefix(30)
    for (url, _) in files {
      guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
      for line in content.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any] else { continue }
        let at = (json["timestamp"] as? String).flatMap(parseISODate) ?? Date()
        let windows = [("primary", "5 hours"), ("secondary", "This week")].compactMap { key, fallback -> Window? in
          guard let w = limits[key] as? [String: Any], let used = w["used_percent"] as? Double else { return nil }
          let reset: Date? = (w["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:))
            ?? (w["resets_in_seconds"] as? Double).map { at.addingTimeInterval($0) }
          return Window(name: windowName(minutes: w["window_minutes"] as? Double) ?? fallback, percent: used, resetsAt: reset)
        }
        if !windows.isEmpty { return (windows, (limits["plan_type"] as? String ?? "").capitalized, at) }
      }
    }
    return nil
  }

  private static func windowName(minutes: Double?) -> String? {
    guard let minutes else { return nil }
    if minutes >= 10_000 { return "This week" }
    if minutes >= 60 { return "\(Int(minutes / 60)) hours" }
    return "\(Int(minutes)) min"
  }

  static func parseISODate(_ string: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
  }
}

/// URLSession that goes through the proxy set in Settings › AI, like the CLIs do.
enum ProxySession {
  static var shared: URLSession {
    let config = URLSessionConfiguration.ephemeral
    if let url = URL(string: AppSettings.shared.proxy), let host = url.host, let port = url.port {
      config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable as String: true, kCFNetworkProxiesHTTPProxy as String: host, kCFNetworkProxiesHTTPPort as String: port,
        "HTTPSEnable": true, "HTTPSProxy": host, "HTTPSPort": port,
      ]
    }
    return URLSession(configuration: config)
  }
}
