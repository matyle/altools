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
