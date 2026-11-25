import Foundation

public enum AIEvent: Equatable, Sendable {
  /// A chunk of answer text, to be appended to what came before.
  case text(String)
  /// The agent used a tool; `detail` is a short human-readable summary.
  case tool(name: String, detail: String)
  /// Session/thread id that can be passed back as `resumeSessionID`.
  case session(String)
  case error(String)
}

/// Turns one line of CLI JSON output into events. Lines that carry nothing worth
/// showing (hooks, rate-limit notices, reconnect attempts) produce `[]`.
public protocol AIStreamParser {
  mutating func parse(line: String) -> [AIEvent]
}

public func makeParser(for provider: AIProvider) -> any AIStreamParser {
  switch provider {
  case .claude: ClaudeStreamParser()
  case .codex: CodexStreamParser()
  }
}

private func decode(_ line: String) -> [String: Any]? {
  guard let data = line.data(using: .utf8) else { return nil }
  return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// Parses `claude -p --output-format stream-json --include-partial-messages`.
///
/// Answer text is taken only from `text_delta` stream events; the complete
/// `assistant` messages repeat that text, so they are read only for tool calls.
public struct ClaudeStreamParser: AIStreamParser {
  private var sawSession = false
  private var sawText = false
  public init() {}

  public mutating func parse(line: String) -> [AIEvent] {
    guard let obj = decode(line), let type = obj["type"] as? String else { return [] }
    var events: [AIEvent] = []
    if !sawSession, let session = obj["session_id"] as? String, type == "system" || type == "stream_event" {
      sawSession = true
      events.append(.session(session))
    }
    switch type {
    case "stream_event":
      guard let event = obj["event"] as? [String: Any] else { break }
      // Ignore sub-agent output; only the top-level answer goes to the user.
      if obj["parent_tool_use_id"] is String { break }
      if event["type"] as? String == "content_block_delta",
         let delta = event["delta"] as? [String: Any],
         delta["type"] as? String == "text_delta",
         let text = delta["text"] as? String {
        sawText = true
        events.append(.text(text))
      } else if event["type"] as? String == "message_start", sawText {
        // A new assistant turn after a tool call: separate it from the previous text.
        events.append(.text("\n\n"))
      }
    case "assistant":
      let message = obj["message"] as? [String: Any]
      for block in message?["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "tool_use" {
        let name = block["name"] as? String ?? "tool"
        events.append(.tool(name: name, detail: Self.summarize(block["input"] as? [String: Any] ?? [:])))
      }
    case "result":
      if obj["is_error"] as? Bool == true {
        let message = (obj["result"] as? String) ?? (obj["subtype"] as? String) ?? "Claude Code reported an error"
        events.append(.error(message))
      }
    default:
      break
    }
    return events
  }

  static func summarize(_ input: [String: Any]) -> String {
    for key in ["command", "file_path", "pattern", "query", "url", "path", "description"] {
      if let value = input[key] as? String { return String(value.prefix(160)) }
    }
    return ""
  }
}

/// Parses `codex exec --json`.
public struct CodexStreamParser: AIStreamParser {
  private var answeredOnce = false
  public init() {}

  public mutating func parse(line: String) -> [AIEvent] {
    guard let obj = decode(line), let type = obj["type"] as? String else { return [] }
    switch type {
    case "thread.started":
      if let id = obj["thread_id"] as? String { return [.session(id)] }
    case "item.started":
      // Commands are reported when they start so the user sees progress.
      if let item = obj["item"] as? [String: Any], item["type"] as? String == "command_execution" {
        return [.tool(name: "shell", detail: String((item["command"] as? String ?? "").prefix(160)))]
      }
    case "item.completed":
      guard let item = obj["item"] as? [String: Any], let itemType = item["type"] as? String else { break }
      switch itemType {
      case "agent_message":
        let text = item["text"] as? String ?? ""
        defer { answeredOnce = true }
        return [.text(answeredOnce ? "\n\n" + text : text)]
      case "file_change":
        let changes = item["changes"] as? [[String: Any]] ?? []
        let paths = changes.compactMap { $0["path"] as? String }.joined(separator: ", ")
        return [.tool(name: "edit", detail: paths)]
      case "mcp_tool_call":
        return [.tool(name: "\(item["server"] as? String ?? "mcp").\(item["tool"] as? String ?? "")", detail: "")]
      case "web_search":
        return [.tool(name: "web_search", detail: item["query"] as? String ?? "")]
      default:
        break
      }
    case "turn.failed":
      let error = obj["error"] as? [String: Any]
      return [.error(error?["message"] as? String ?? "Codex failed")]
    default:
      // Top-level "error" lines are retry notices; the final failure arrives as turn.failed.
      break
    }
    return []
  }
}
