import Foundation

public enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
  case claude, codex
  public var id: String { rawValue }
  public var displayName: String { self == .claude ? "Claude Code" : "Codex" }
  public var binaryName: String { self == .claude ? "claude" : "codex" }
}

/// How much the agent may do on this Mac. Maps to Claude Code permission modes
/// and Codex sandbox modes.
public enum ToolPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
  case none, readOnly, acceptEdits, full
  public var id: String { rawValue }
  public var displayName: String {
    switch self {
    case .none: "No tools (plain answer)"
    case .readOnly: "Read-only (read files, search, web)"
    case .acceptEdits: "Edit files in working directory"
    case .full: "Full access (shell, no prompts)"
    }
  }
}

/// `quick` is for one-shot text actions (translate, rewrite): no tools, no user
/// settings or hooks loaded, no session saved. `agent` honors the tool policy and
/// keeps a session so follow-up questions can resume it.
public enum AIMode: Sendable { case quick, agent }

public struct AIRequest: Sendable {
  public var provider: AIProvider
  public var mode: AIMode
  public var prompt: String
  public var systemPrompt: String?
  public var model: String?
  public var toolPolicy: ToolPolicy
  /// Session to continue; only used in `agent` mode.
  public var resumeSessionID: String?

  public init(provider: AIProvider, mode: AIMode, prompt: String, systemPrompt: String? = nil,
              model: String? = nil, toolPolicy: ToolPolicy = .readOnly, resumeSessionID: String? = nil) {
    self.provider = provider
    self.mode = mode
    self.prompt = prompt
    self.systemPrompt = systemPrompt
    self.model = model
    self.toolPolicy = toolPolicy
    self.resumeSessionID = resumeSessionID
  }
}

public enum AICommand {
  /// Command-line arguments (excluding the executable). The prompt is passed as
  /// the last argument, never through a shell, so no quoting is needed.
  public static func arguments(for request: AIRequest) -> [String] {
    switch request.provider {
    case .claude: claudeArguments(request)
    case .codex: codexArguments(request)
    }
  }

  static func claudeArguments(_ r: AIRequest) -> [String] {
    var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
    if let model = r.model, !model.isEmpty { args += ["--model", model] }
    if let system = r.systemPrompt { args += ["--append-system-prompt", system] }

    let policy = r.mode == .quick ? ToolPolicy.none : r.toolPolicy
    if r.mode == .quick {
      // Skips the user's hooks, plugins and MCP servers: a one-line translation
      // otherwise pays for loading all of them on every call.
      args += ["--setting-sources", "", "--strict-mcp-config", "--no-session-persistence"]
    }
    switch policy {
    case .none:
      args += ["--tools", ""]
    case .readOnly:
      args += ["--allowedTools", "Read", "Glob", "Grep", "WebSearch", "WebFetch", "--permission-mode", "default"]
    case .acceptEdits:
      args += ["--permission-mode", "acceptEdits"]
    case .full:
      args += ["--permission-mode", "bypassPermissions"]
    }
    if r.mode == .agent, let session = r.resumeSessionID { args += ["--resume", session] }
    // "--" stops option parsing, so a prompt starting with "-" stays a prompt.
    args += ["--", r.prompt]
    return args
  }

  static func codexArguments(_ r: AIRequest) -> [String] {
    var args = ["exec"]
    let resuming = r.mode == .agent && r.resumeSessionID != nil
    if resuming { args.append("resume") }
    args += ["--skip-git-repo-check", "--json"]
    if r.mode == .quick { args.append("--ephemeral") }
    if let model = r.model, !model.isEmpty { args += ["-m", model] }

    let policy = r.mode == .quick ? ToolPolicy.none : r.toolPolicy
    // `codex exec resume` takes no --sandbox flag; the original session's sandbox applies,
    // so it is passed as a config override instead.
    let sandbox: String = switch policy {
    case .none, .readOnly: "read-only"
    case .acceptEdits: "workspace-write"
    case .full: "danger-full-access"
    }
    args += resuming ? ["-c", "sandbox_mode=\"\(sandbox)\""] : ["-s", sandbox]

    var prompt = r.prompt
    if let system = r.systemPrompt, !resuming {
      prompt = "\(system)\n\n\(r.prompt)"
    }
    if resuming, let session = r.resumeSessionID { args += ["--", session, prompt] } else { args += ["--", prompt] }
    return args
  }
}
