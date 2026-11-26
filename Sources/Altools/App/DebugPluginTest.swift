#if DEBUG
import AltoolsCore
import AppKit
import SwiftUI

/// Debug builds only: with ALTOOLS_PLUGIN_TEST=<output dir> and ALTOOLS_PLUGIN_EXAMPLES=<repo>/examples/plugins,
/// installs the example plugins plus three deliberately broken ones into the Plugins folder, runs
/// them through the real PluginHost, prints what each produced, exercises a `run` action, renders the
/// notch surfaces they feed, then removes the folders it added and quits.
enum DebugPluginTest {
  /// ALTOOLS_IMPORT_TEST=<zip or folder>: imports it without the confirmation and prints what landed.
  static func importIfRequested() -> Bool {
    guard let path = ProcessInfo.processInfo.environment["ALTOOLS_IMPORT_TEST"] else { return false }
    PluginPackage.autoConfirm = true
    let before = Set((try? FileManager.default.contentsOfDirectory(atPath: PluginHost.folder.path)) ?? [])
    PluginPackage.install(from: URL(fileURLWithPath: path), source: "test")
    let added = Set((try? FileManager.default.contentsOfDirectory(atPath: PluginHost.folder.path)) ?? []).subtracting(before)
    print("IMPORTED \(added.sorted())")
    for id in added { try? FileManager.default.removeItem(at: PluginHost.folder.appendingPathComponent(id)) }
    NSApp.terminate(nil)
    return true
  }

  static func runIfRequested() -> Bool {
    let env = ProcessInfo.processInfo.environment
    guard let dir = env["ALTOOLS_PLUGIN_TEST"], let examples = env["ALTOOLS_PLUGIN_EXAMPLES"] else { return false }
    let out = URL(fileURLWithPath: dir)
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    NSApp.appearance = NSAppearance(named: .darkAqua)

    let fm = FileManager.default
    var added: [URL] = []
    for name in (try? fm.contentsOfDirectory(atPath: examples)) ?? [] {
      let target = PluginHost.folder.appendingPathComponent(name)
      guard !fm.fileExists(atPath: target.path) else { continue }
      if (try? fm.copyItem(at: URL(fileURLWithPath: examples).appendingPathComponent(name), to: target)) != nil { added.append(target) }
    }
    let broken: [(String, String, String)] = [
      ("test-bad-json", #"{"id": "test-bad-json", "run": "run.sh"}"#, "#!/bin/sh\necho 'not json'\n"),
      ("test-exit", #"{"id": "test-exit", "run": "run.sh"}"#, "#!/bin/sh\necho 'boom' >&2\nexit 3\n"),
      ("test-slow", #"{"id": "test-slow", "run": "run.sh", "timeout": 1}"#, "#!/bin/sh\nsleep 5\necho '{}'\n"),
    ]
    for (id, manifest, script) in broken {
      let folder = PluginHost.folder.appendingPathComponent(id)
      try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
      try? manifest.write(to: folder.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
      try? script.write(to: folder.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
      added.append(folder)
    }

    let host = PluginHost.shared
    var alerts: [String] = []
    host.onAlert = { alert, plugin in alerts.append("\(plugin.id): \(alert.title)") }
    host.start()
    for folder in added { host.setEnabled(folder.lastPathComponent, true) }

    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
      for plugin in host.plugins where added.contains(where: { $0.lastPathComponent == plugin.id }) {
        let o = plugin.output
        print("PLUGIN \(plugin.id): error=\(plugin.error ?? "-") ears=\(o?.ears?.text ?? "-") home=\(o?.home?.rows.map(\.title) ?? []) tabSections=\(o?.tab?.sections.count ?? 0)")
      }
      print("ALERTS \(alerts)")
      host.perform(.run("greet"), plugin: "hello")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
      print("AFTER ACTION hello home first row: \(host.plugins.first { $0.id == "hello" }?.output?.home?.rows.first?.title ?? "-")")
      let settings = AppSettings.shared
      let savedSlots = settings.homeCards
      settings.homeSlotList = [.builtin(.media), .plugin("hello"), .plugin("ticktick")]
      func notch(_ setup: @escaping (NotchModel) -> Void) -> () -> AnyView {
        {
          let model = NotchModel()
          model.hasNotch = true
          model.notchSize = CGSize(width: 190, height: 32)
          setup(model)
          return AnyView(NotchView(model: model, actions: NotchActions()))
        }
      }
      let scenes: [(String, CGSize, () -> AnyView)] = [
        ("plugin-ears", CGSize(width: 680, height: 80), notch { _ in }),
        ("plugin-home", CGSize(width: 760, height: 320), notch { $0.tab = .home; $0.expanded = true }),
        ("plugin-tab", CGSize(width: 760, height: 320), notch { $0.tab = .plugins; $0.expanded = true }),
        ("plugin-alert", CGSize(width: 680, height: 140), notch {
          $0.card = .plugin(id: "hello", alert: PluginOutput.Alert(id: "x", title: "Hello from a plugin", body: "Shown once a day. Edit run.sh to change me.", symbol: nil, tint: nil, action: nil))
        }),
        ("plugin-settings", CGSize(width: 1100, height: 900), { AnyView(SettingsRoot(actions: SettingsActions(), page: .module("notch"))) }),
      ]
      var delay = 0.5
      for (name, size, view) in scenes {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { DebugRender.render(view, size: size, to: out.appendingPathComponent("\(name).png")) }
        delay += 0.9
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5) {
        settings.homeCards = savedSlots
        for folder in added { host.setEnabled(folder.lastPathComponent, false); try? fm.removeItem(at: folder) }
        NSApp.terminate(nil)
      }
    }
    return true
  }
}
#endif
