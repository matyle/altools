#if DEBUG
import AltoolsCore
import AppKit

/// Debug builds only: with ALTOOLS_PLUGIN_SHARE_TEST=1 (plus ALTOOLS_PLUGIN_EXAMPLES, ALTOOLS_BUILTIN_PLUGINS
/// and ALTOOLS_REGISTRY_URL), checks the Markets migration and built-in plugin, a package export and
/// import, an install from GitHub and the store listing, printing one line per check, then cleans up.
enum DebugPluginShareTest {
  static func runIfRequested() -> Bool {
    let env = ProcessInfo.processInfo.environment
    guard env["ALTOOLS_PLUGIN_SHARE_TEST"] != nil, let examples = env["ALTOOLS_PLUGIN_EXAMPLES"],
          let ref = env["ALTOOLS_TEST_REF"] else { return false }
    let fm = FileManager.default
    let defaults = UserDefaults.standard
    let settings = AppSettings.shared
    let host = PluginHost.shared
    PluginPackage.autoConfirm = true

    // 1. Migration from the built-in Markets.
    defaults.removeObject(forKey: "migratedMarketsToPlugin")
    defaults.set(["crypto:SOLUSDT", "us:TSLA"], forKey: "marketWatchlist")
    let savedCards = settings.homeCards, savedDisabled = settings.disabledCapabilities
    settings.homeCards = ["media", "markets"]
    settings.disabledCapabilities.insert("notch.ticker")
    host.start()
    let pluginSettings = defaults.dictionary(forKey: "pluginSettings") as? [String: [String: String]] ?? [:]
    print("MIGRATE homeCards=\(settings.homeCards) watchlist=\(pluginSettings["markets"]?["watchlist"] ?? "-") ears=\(pluginSettings["markets"]?["ears"] ?? "-") tickerCapGone=\(!settings.disabledCapabilities.contains("notch.ticker"))")

    // 2. Package round trip with hello.
    let hello = PluginHost.folder.appendingPathComponent("hello")
    try? fm.copyItem(at: URL(fileURLWithPath: examples).appendingPathComponent("hello"), to: hello)
    let package = fm.temporaryDirectory.appendingPathComponent("hello.altoolsplugin")
    do { try PluginPackage.zip(hello, to: package) } catch { print("EXPORT failed: \(error)") }
    try? fm.removeItem(at: hello)
    host.reload()
    PluginPackage.install(from: package, source: "hello.altoolsplugin")
    print("PACKAGE exported=\(fm.fileExists(atPath: package.path)) reinstalled=\(fm.fileExists(atPath: hello.appendingPathComponent("run.sh").path)) enabled=\(host.plugins.first { $0.id == "hello" }?.enabled ?? false)")

    // 3. Install from GitHub (this branch).
    PluginPackage.install(repo: "matyle/altools", path: "examples/plugins/text-tools", ref: ref)

    // 4. Store.
    let store = PluginStore()
    store.load()

    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
      let markets = host.plugins.first { $0.id == "markets" }
      print("BUILTIN markets builtin=\(markets?.builtin ?? false) enabled=\(markets?.enabled ?? false) error=\(markets?.error ?? "-") ears=\(markets?.output?.ears?.text ?? "-") rows=\(markets?.output?.tab?.sections.flatMap(\.rows).map(\.title) ?? [])")
      let tools = PluginHost.folder.appendingPathComponent("text-tools")
      print("GITHUB installed=\(fm.fileExists(atPath: tools.appendingPathComponent("plugin.json").path)) enabled=\(host.plugins.first { $0.id == "text-tools" }?.enabled ?? false)")
      print("STORE listings=\(store.listings.map { "\($0.manifest.name)\($0.featured ? "*" : "")" }) problem=\(store.problem ?? "-")")
      for id in ["hello", "text-tools"] { host.setEnabled(id, false); try? fm.removeItem(at: PluginHost.folder.appendingPathComponent(id)) }
      settings.homeCards = savedCards
      settings.disabledCapabilities = savedDisabled
      for key in ["pluginSettings", "migratedMarketsToPlugin", "pluginSeenAlerts", "enabledPlugins"] { defaults.removeObject(forKey: key) }
      try? fm.removeItem(at: package)
      NSApp.terminate(nil)
    }
    return true
  }
}
#endif
