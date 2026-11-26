import Testing
@testable import AltoolsCore

@Suite struct CalculatorTests {
  @Test(arguments: [
    ("1+2*3", 7.0), ("(1+2)*3", 9.0), ("2^3^2", 512.0), ("-2^2", -4.0),
    ("10 % 3", 1.0), ("2^-1", 0.5), ("sqrt(16)+1", 5.0), ("1,000 * 2", 2000.0), ("3×4÷2", 6.0),
  ])
  func evaluates(input: String, expected: Double) {
    #expect(Calculator.evaluate(input) == expected)
  }

  @Test(arguments: ["1+", "(1+2", "2 3", "foo(2)", "1/0", "hello", ""])
  func rejectsIncompleteOrNonFinite(input: String) {
    #expect(Calculator.evaluate(input) == nil)
  }

  @Test func looksLikeExpressionIgnoresBareNumbersAndWords() {
    #expect(!Calculator.looksLikeExpression("2024"))
    #expect(!Calculator.looksLikeExpression("safari"))
    #expect(!Calculator.looksLikeExpression("-5"))
    #expect(Calculator.looksLikeExpression("2+2"))
    #expect(Calculator.looksLikeExpression("sqrt(2)"))
  }

  @Test func formatsIntegersWithoutDecimals() {
    #expect(Calculator.format(42) == "42")
    #expect(Calculator.format(0.1 + 0.2) == "0.3")
  }
}

@Suite struct FuzzyMatchTests {
  @Test func prefixBeatsScattered() throws {
    let prefix = try #require(FuzzyMatch.score("saf", "Safari"))
    let scattered = try #require(FuzzyMatch.score("saf", "System Information Files"))
    #expect(prefix > scattered)
  }

  @Test func wordStartsMatch() {
    #expect(FuzzyMatch.score("vsc", "Visual Studio Code") != nil)
  }

  @Test func outOfOrderDoesNotMatch() {
    #expect(FuzzyMatch.score("fas", "Safari") == nil)
  }
}

@Suite struct TextTransformTests {
  @Test func base64RoundTrip() throws {
    let encoded = try TextTransform.base64Encode.apply("你好 hi")
    #expect(try TextTransform.base64Decode.apply(encoded) == "你好 hi")
  }

  @Test func base64DecodeAcceptsMissingPadding() throws {
    #expect(try TextTransform.base64Decode.apply("aGk") == "hi")
  }

  @Test func invalidInputThrows() {
    #expect(throws: TextTransformError.self) { try TextTransform.base64Decode.apply("@@@") }
    #expect(throws: TextTransformError.self) { try TextTransform.jsonPretty.apply("{bad") }
  }

  @Test func urlEncodeEscapesQuerySeparators() throws {
    #expect(try TextTransform.urlEncode.apply("a&b=c d") == "a%26b%3Dc%20d")
  }

  @Test func detectsCJK() {
    #expect(TextTransform.isMostlyCJK("今天天气不错"))
    #expect(!TextTransform.isMostlyCJK("The weather is nice"))
  }
}

@Suite struct AICommandTests {
  @Test func claudeQuickModeSkipsUserSettingsAndTools() {
    let args = AICommand.arguments(for: AIRequest(provider: .claude, mode: .quick, prompt: "-hi", toolPolicy: .full))
    #expect(args.contains("--no-session-persistence"))
    #expect(!args.contains("bypassPermissions"))
    #expect(Array(args.suffix(2)) == ["--", "-hi"])
  }

  @Test func claudeAgentAddsAllowedToolsExceptWhenFull() {
    let edits = AICommand.arguments(for: AIRequest(provider: .claude, mode: .agent, prompt: "x", toolPolicy: .acceptEdits,
                                                   allowedTools: ["Bash(python3:*)", "WebFetch"]))
    #expect(edits.contains("Bash(python3:*)"))
    #expect(edits.firstIndex(of: "--allowedTools")! < edits.firstIndex(of: "--")!)
    let full = AICommand.arguments(for: AIRequest(provider: .claude, mode: .agent, prompt: "x", toolPolicy: .full, allowedTools: ["WebFetch"]))
    #expect(!full.contains("--allowedTools"))
    let quick = AICommand.arguments(for: AIRequest(provider: .claude, mode: .quick, prompt: "x", allowedTools: ["WebFetch"]))
    #expect(!quick.contains("WebFetch"))
  }

  @Test func claudeAgentResumes() {
    let args = AICommand.arguments(for: AIRequest(provider: .claude, mode: .agent, prompt: "x", toolPolicy: .acceptEdits, resumeSessionID: "s1"))
    #expect(args.contains("acceptEdits"))
    #expect(args.firstIndex(of: "--resume").map { args[$0 + 1] } == "s1")
  }

  @Test func codexResumeUsesConfigOverrideInsteadOfSandboxFlag() {
    let args = AICommand.arguments(for: AIRequest(provider: .codex, mode: .agent, prompt: "x", toolPolicy: .full, resumeSessionID: "t1"))
    #expect(Array(args.prefix(2)) == ["exec", "resume"])
    #expect(!args.contains("-s"))
    #expect(args.contains("sandbox_mode=\"danger-full-access\""))
    #expect(Array(args.suffix(3)) == ["--", "t1", "x"])
  }
}

@Suite struct StreamParserTests {
  @Test func claudeTextComesFromDeltasOnly() {
    var parser = ClaudeStreamParser()
    let delta = #"{"type":"stream_event","session_id":"s","parent_tool_use_id":null,"event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"#
    let full = #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#
    #expect(parser.parse(line: delta) == [.session("s"), .text("hi")])
    #expect(parser.parse(line: full) == [])
  }

  @Test func claudeToolUseAndError() {
    var parser = ClaudeStreamParser()
    let tool = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#
    let error = #"{"type":"result","is_error":true,"result":"boom"}"#
    #expect(parser.parse(line: tool) == [.tool(name: "Bash", detail: "ls")])
    #expect(parser.parse(line: error) == [.error("boom")])
  }

  @Test func codexEvents() {
    var parser = CodexStreamParser()
    #expect(parser.parse(line: #"{"type":"thread.started","thread_id":"t"}"#) == [.session("t")])
    #expect(parser.parse(line: #"{"type":"error","message":"Reconnecting... 1/5"}"#) == [])
    #expect(parser.parse(line: #"{"type":"item.completed","item":{"type":"agent_message","text":"a"}}"#) == [.text("a")])
    #expect(parser.parse(line: #"{"type":"item.completed","item":{"type":"agent_message","text":"b"}}"#) == [.text("\n\nb")])
    #expect(parser.parse(line: #"{"type":"turn.failed","error":{"message":"403"}}"#) == [.error("403")])
  }
}

@Suite struct MarkdownBlockTests {
  @Test func parsesBlocks() {
    let md = "# Title\nIntro line\n\n- one\n  - nested\n2. two\n> quote\n```swift\nlet x = 1\n```"
    #expect(MarkdownBlock.parse(md) == [
      .heading(1, "Title"), .paragraph("Intro line"),
      .bullet(marker: "•", text: "one", indent: 0), .bullet(marker: "•", text: "nested", indent: 1),
      .bullet(marker: "2.", text: "two", indent: 0), .quote("quote"),
      .code(language: "swift", code: "let x = 1"),
    ])
  }

  @Test func unterminatedFenceStillRendersAsCode() {
    #expect(MarkdownBlock.parse("```\nabc") == [.code(language: "", code: "abc")])
  }

  @Test func hashWithoutSpaceIsNotHeading() {
    #expect(MarkdownBlock.parse("#hashtag\n1.5 is a number") == [.paragraph("#hashtag\n1.5 is a number")])
  }
}
