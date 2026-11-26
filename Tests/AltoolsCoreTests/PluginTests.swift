import Foundation
import Testing
@testable import AltoolsCore

@Suite struct PluginManifestTests {
  private func manifest(_ json: String) throws -> PluginManifest { try PluginManifest.decode(Data(json.utf8)) }

  @Test func decodesFullManifest() throws {
    let m = try manifest("""
    {"id": "ticktick", "name": "TickTick", "version": "1.2.0", "api": 1, "icon": "checklist", "tint": "#e5c07b",
     "run": "run.py", "interval": 120, "timeout": 30, "slots": ["ears", "home", "tab", "alerts"],
     "settings": [{"key": "token", "title": "API token", "type": "secret"},
                  {"key": "region", "type": "choice", "options": ["ticktick.com", "dida365.com"], "default": "dida365.com"},
                  {"key": "overdue", "type": "toggle", "default": true}]}
    """)
    #expect(m.id == "ticktick")
    #expect(m.tint == "#E5C07B")
    #expect(m.interval == 120)
    #expect(m.timeout == 30)
    #expect(m.slots == [.ears, .home, .tab, .alerts])
    #expect(m.settings.map(\.kind) == [.secret, .choice, .toggle])
    #expect(m.settings[1].defaultValue == "dida365.com")
    #expect(m.settings[2].defaultValue == "1")
    #expect(m.settings[0].environmentName == "ALTOOLS_SETTING_TOKEN")
  }

  @Test func fillsDefaultsAndClamps() throws {
    let m = try manifest(#"{"id": "hello", "run": "run.sh", "interval": 1, "timeout": 999, "slots": ["ears", "widgets"]}"#)
    #expect(m.name == "hello")
    #expect(m.icon == "puzzlepiece.extension.fill")
    #expect(m.interval == PluginManifest.minimumInterval)
    #expect(m.timeout == PluginManifest.maximumTimeout)
    #expect(m.slots == [.ears])
  }

  @Test func modeDefaultsToIntervalAndReadsStream() throws {
    #expect(try manifest(#"{"id": "a", "run": "x"}"#).mode == .interval)
    #expect(try manifest(#"{"id": "a", "run": "x", "mode": "stream"}"#).mode == .stream)
    #expect(try manifest(#"{"id": "a", "run": "x", "mode": "websocket"}"#).mode == .interval)
    #expect(PluginEvent.trigger("deploy").value == "trigger:deploy")
  }

  @Test func omittedSlotsMeansAll() throws {
    #expect(try manifest(#"{"id": "a", "run": "x"}"#).slots == Set(PluginSlot.allCases))
  }

  @Test(arguments: [
    (#"{"id": "Has Space", "run": "x"}"#, PluginManifestError.invalidID("Has Space")),
    (#"{"run": "x"}"#, PluginManifestError.invalidID("")),
    (#"{"id": "a", "run": "../escape.sh"}"#, PluginManifestError.invalidRun("../escape.sh")),
    (#"{"id": "a", "run": "/bin/sh"}"#, PluginManifestError.invalidRun("/bin/sh")),
    (#"{"id": "a"}"#, PluginManifestError.invalidRun("")),
    (#"{"id": "a", "run": "x", "api": 2}"#, PluginManifestError.unsupportedAPI(2)),
  ])
  func rejects(json: String, error: PluginManifestError) {
    #expect(throws: error) { try manifest(json) }
  }

  @Test func rejectsNonJSON() {
    #expect(throws: PluginManifestError.self) { try manifest("not json") }
  }

  @Test(arguments: [("#abc", "#AABBCC"), ("61afef", "#61AFEF"), ("#12345", nil), ("blue", nil)] as [(String, String?)])
  func normalizesHex(input: String, expected: String?) {
    #expect(PluginManifest.normalizedHex(input) == expected)
  }
}

@Suite struct PluginOutputTests {
  private func output(_ json: String) throws -> PluginOutput { try PluginOutput.decode(Data(json.utf8)) }

  @Test func decodesEverySlot() throws {
    let o = try output("""
    {"ears": {"symbol": "checklist", "text": 3},
     "home": {"title": "Today", "rows": [{"title": "Send invoice", "value": "15:00", "action": {"open": "https://example.com"}}]},
     "tab": {"rows": [{"title": "Loose"}], "sections": [{"title": "Work", "rows": [{"title": "Ship", "action": {"run": "complete:1"}}]}]},
     "alerts": [{"id": "a1", "title": "Due now", "action": {"copy": "hi"}}],
     "next": 60}
    """)
    #expect(o.ears == PluginOutput.Ears(symbol: "checklist", text: "3", tint: nil))
    #expect(o.home?.rows.first?.action == .open(URL(string: "https://example.com")!))
    #expect(o.tab?.sections.count == 2)
    #expect(o.tab?.sections.first?.title == nil)
    #expect(o.tab?.sections.last?.rows.first?.action == .run("complete:1"))
    #expect(o.alerts.first?.action == .copy("hi"))
    #expect(o.next == 60)
  }

  @Test func dropsMalformedPartsInsteadOfFailing() throws {
    let o = try output(#"{"ears": {"symbol": "x"}, "home": {"rows": [{"subtitle": "no title"}, {"title": "ok", "action": {"open": "not a url"}}]}, "alerts": [{"title": "no id"}]}"#)
    #expect(o.ears == nil)
    #expect(o.home?.rows.count == 1)
    #expect(o.home?.rows.first?.action == nil)
    #expect(o.alerts.isEmpty)
  }

  @Test func takesTheLastJSONLineAfterLogging() throws {
    let o = try output("fetching…\nwarning: slow\n{\"ears\": {\"text\": \"ok\"}}\n")
    #expect(o.ears?.text == "ok")
  }

  @Test func clampsNext() throws {
    #expect(try output(#"{"next": 1}"#).next == PluginManifest.minimumInterval)
  }

  @Test(arguments: ["", "[]", "hello", "{broken"])
  func rejectsNonObjects(stdout: String) {
    #expect(throws: PluginOutputError.self) { try output(stdout) }
  }

  @Test func environmentCarriesSettingsAndDefaults() throws {
    let m = try PluginManifest.decode(Data(#"{"id": "t", "run": "x", "settings": [{"key": "token"}, {"key": "region", "default": "cn"}]}"#.utf8))
    let env = PluginEnvironment.variables(manifest: m, pluginDirectory: "/p", dataDirectory: "/d", event: .action("done:1"),
                                          language: "zh", settings: ["token": "abc"])
    #expect(env["ALTOOLS_EVENT"] == "action:done:1")
    #expect(env["ALTOOLS_SETTING_TOKEN"] == "abc")
    #expect(env["ALTOOLS_SETTING_REGION"] == "cn")
    #expect(env["ALTOOLS_LANG"] == "zh")
  }
}

@Suite struct PluginViewTests {
  private func node(_ json: String) -> PluginNode? {
    PluginNode.decode(try? JSONSerialization.jsonObject(with: Data(json.utf8)))
  }

  @Test func decodesEveryNodeType() throws {
    let tree = node(##"""
    {"type": "vstack", "spacing": 4, "children": [
      {"type": "hstack", "align": "top", "children": [
        {"type": "badge", "text": "US", "color": "blue"},
        {"type": "text", "text": "AAPL", "weight": "bold", "size": 99, "mono": true},
        {"type": "spacer"},
        {"type": "symbol", "name": "arrow.up", "color": "#98c379"}]},
      {"type": "grid", "columns": 9, "children": [{"type": "card", "children": [{"type": "progress", "value": 2}]}]},
      {"type": "sparkline", "values": [1, "2", 3], "height": 20},
      {"type": "image", "url": "https://example.com/a.png", "radius": 4},
      {"type": "divider"}
    ]}
    """##)
    guard case .stack(.vertical, .leading, 4, let children, _) = tree else { Issue.record("not a vstack"); return }
    #expect(children.count == 5)
    guard case .stack(.horizontal, .top, _, let row, _) = children[0] else { Issue.record("not an hstack"); return }
    #expect(row[0] == .badge("US", color: .named(.blue), style: .init()))
    #expect(row[1] == .text("AAPL", size: 28, weight: .bold, color: nil, mono: true, lines: nil, style: .init()))
    #expect(row[3] == .symbol("arrow.up", size: nil, color: .hex("#98C379"), style: .init()))
    guard case .grid(let columns, _, let cells, _) = children[1], case .card(_, _, let inner, _) = cells[0] else { Issue.record("grid"); return }
    #expect(columns == 6)
    #expect(inner[0] == .progress(1, color: nil, style: .init()))
    #expect(children[2] == .sparkline([1, 2, 3], color: nil, style: .init(height: 20)))
  }

  @Test func skipsUnknownTypesAndKeepsActions() {
    let tree = node(#"{"type": "hstack", "children": [{"type": "chart3d"}, {"type": "text", "text": "Open", "action": {"open": "https://a.b"}}, {"type": "text"}]}"#)
    guard case .stack(_, _, _, let children, _) = tree else { Issue.record("not a stack"); return }
    #expect(children.count == 1)
    #expect(children[0] == .text("Open", size: nil, weight: .regular, color: nil, mono: false, lines: nil,
                                 style: .init(action: .open(URL(string: "https://a.b")!))))
  }

  @Test func enforcesDepthAndNodeLimits() {
    var deep = #"{"type": "text", "text": "leaf"}"#
    for _ in 0..<20 { deep = #"{"type": "vstack", "children": ["# + deep + "]}" }
    var depth = 0
    var current = node(deep)
    while case .stack(_, _, _, let children, _)? = current { depth += 1; current = children.first }
    #expect(depth <= PluginNode.maximumDepth + 1)
    let many = "[" + Array(repeating: #"{"type": "spacer"}"#, count: 1_000).joined(separator: ",") + "]"
    guard case .stack(_, _, _, let children, _) = node(#"{"type": "vstack", "children": "# + many + "}") else { Issue.record("stack"); return }
    #expect(children.count == PluginNode.maximumNodes - 1)
  }

  @Test func outputCarriesViews() throws {
    let o = try PluginOutput.decode(Data(#"{"home": {"view": {"type": "text", "text": "hi"}}, "tab": {"title": "T", "view": {"type": "divider"}}}"#.utf8))
    #expect(o.home?.view == .text("hi", size: nil, weight: .regular, color: nil, mono: false, lines: nil, style: .init()))
    #expect(o.tab?.view == .divider)
  }
}

