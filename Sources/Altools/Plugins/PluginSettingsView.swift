import AltoolsCore
import AppKit
import SwiftUI

/// Settings › Plugins: make a plugin with AI, install the examples, and switch each
/// plugin on, fill in its settings and read its log.
struct PluginSettingsView: View {
  @ObservedObject private var host = PluginHost.shared
  @StateObject private var maker = PluginMaker()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Button("Open Plugins folder") { NSWorkspace.shared.open(PluginHost.folder) }
        Button("Import…") { PluginPackage.importWithPanel() }
        Button("Install examples") { installExamples() }
        Button("Plugin guide") { NSWorkspace.shared.open(URL(string: "https://github.com/matyle/altools/blob/main/PLUGINS.md")!) }
        Button("Reload") { host.reload() }
      }
      .buttonStyle(SoftPillButtonStyle())

      makerCard

      PluginStoreView()

      if host.plugins.isEmpty {
        Text("No plugins yet. Make one above, install the examples, or drop a plugin folder into the Plugins folder.")
          .font(.system(size: 12)).foregroundStyle(Theme.dim)
      }
      ForEach(host.plugins) { plugin in
        PluginCard(plugin: plugin, fix: { maker.fix(plugin) }, fixing: maker.isRunning)
      }
    }
  }

  private var makerCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Make a plugin with AI").font(.system(size: 13, weight: .semibold))
      Text("Describe it; \(AppSettings.shared.aiProvider.displayName) writes it into the Plugins folder, runs it once to check, and switches it on. It may run the plugin, curl and file commands while it works.")
        .font(.system(size: 11.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        TextField("e.g. Show my TickTick tasks due today, or the top 5 Hacker News stories", text: $maker.prompt, axis: .vertical)
          .textFieldStyle(.plain).lineLimit(1...3)
          .padding(.horizontal, 10).padding(.vertical, 7)
          .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
          .onSubmit { maker.make() }
        Button(maker.isRunning ? "Working…" : "Make") { maker.make() }
          .buttonStyle(SoftPillButtonStyle())
          .disabled(maker.isRunning || maker.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      if !maker.runner.entries.isEmpty {
        TranscriptView(runner: maker.runner)
          .frame(height: 220)
          .padding(8)
          .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
      }
    }
    .padding(14)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
  }

  /// Copies the bundled examples into the Plugins folder; existing folders are left alone.
  private func installExamples() {
    guard let source = Bundle.main.url(forResource: "PluginExamples", withExtension: nil),
          let examples = try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else {
      Toast.show("No examples in this build", symbol: "exclamationmark.triangle", duration: 2)
      return
    }
    var added = 0
    for example in examples {
      let target = PluginHost.folder.appendingPathComponent(example.lastPathComponent)
      guard !FileManager.default.fileExists(atPath: target.path) else { continue }
      if (try? FileManager.default.copyItem(at: example, to: target)) != nil { added += 1 }
    }
    host.reload()
    Toast.show(added == 0 ? "Examples already installed" : "Installed \(added) example\(added == 1 ? "" : "s"); switch them on below",
               symbol: "puzzlepiece.extension", duration: 2.5)
  }
}

private struct PluginCard: View {
  let plugin: PluginHost.Plugin
  let fix: () -> Void
  let fixing: Bool
  @ObservedObject private var host = PluginHost.shared
  @State private var showLog = false

  var body: some View {
    let tint = Color(pluginHex: plugin.manifest?.tint) ?? Theme.accent
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Image(systemName: plugin.manifest?.icon ?? "puzzlepiece.extension.fill")
          .font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
          .frame(width: 30, height: 30).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(plugin.name).font(.system(size: 13, weight: .semibold))
            if let manifest = plugin.manifest {
              Text("v\(manifest.version)\(manifest.author.map { " · \($0)" } ?? "")").font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            if plugin.builtin {
              Text("Built in").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.accent.opacity(0.14), in: Capsule())
            }
          }
          Text(plugin.manifest?.summary ?? plugin.folder.lastPathComponent).font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(2)
        }
        Spacer()
        PillToggle(isOn: Binding(get: { plugin.enabled }, set: { host.setEnabled(plugin.id, $0) }))
          .disabled(plugin.problem != nil)
      }
      status
      if plugin.enabled, let settings = plugin.manifest?.settings, !settings.isEmpty {
        SettingsCard {
          ForEach(settings, id: \.key) { setting in
            SettingsRow(setting.title, note: setting.note) { field(for: setting) }
          }
        }
      }
      HStack(spacing: 8) {
        Button("Run now") { host.refresh(plugin.id) }.disabled(!plugin.enabled || plugin.running)
        Button(showLog ? "Hide log" : "Log") { showLog.toggle() }
        Button("Export…") { PluginPackage.export(plugin) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([plugin.folder]) }
        if plugin.error != nil, plugin.manifest != nil {
          Button("Fix with AI", action: fix).disabled(fixing)
        }
        Spacer()
        if !plugin.builtin { Button("Remove") { remove() } }
      }
      .buttonStyle(SoftPillButtonStyle())
      if showLog {
        ScrollView {
          Text(plugin.log.isEmpty ? "Nothing logged yet." : plugin.log)
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .frame(height: 140).padding(8)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
      }
    }
    .padding(14)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
  }

  @ViewBuilder private var status: some View {
    if let error = plugin.error {
      Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5)).foregroundStyle(Theme.warning)
    } else if plugin.running {
      Label("Running…", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
    } else if let lastRun = plugin.lastRun {
      Text("Last run \(lastRun.formatted(date: .omitted, time: .shortened)) · shows in \(slots)").font(.system(size: 11.5)).foregroundStyle(Theme.faint)
    } else if !plugin.enabled {
      Text("Off. Plugins run as you; switch on the ones you trust.").font(.system(size: 11.5)).foregroundStyle(Theme.faint)
    }
  }

  private var slots: String {
    guard let manifest = plugin.manifest else { return "" }
    let names: [PluginSlot: String] = [.ears: "beside the notch", .home: "Home", .tab: "its own notch tab", .alerts: "alerts", .menubar: "the menu bar"]
    var places = PluginSlot.allCases.filter(manifest.slots.contains).compactMap { names[$0] }
    if !manifest.commands.isEmpty { places.append(manifest.commands.contains { $0.hotkey != nil } ? "launcher commands and hotkeys" : "launcher commands") }
    if let keyword = manifest.search?.keyword { places.append("launcher search “\(keyword) …”") }
    if !manifest.selectionActions.isEmpty { places.append("selected text") }
    return places.isEmpty ? "nothing visible" : places.joined(separator: ", ")
  }

  @ViewBuilder private func field(for setting: PluginSetting) -> some View {
    let binding = Binding(get: { host.value(of: setting, for: plugin.id) },
                          set: { host.setValue($0, of: setting, for: plugin.id) })
    switch setting.kind {
    case .text:
      SettingsTextField(text: binding, prompt: setting.defaultValue ?? "")
    case .secret:
      SecureField("Stored in the Keychain", text: binding)
        .textFieldStyle(.plain).frame(width: 240)
        .padding(.horizontal, 10).frame(height: 28)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
        .onSubmit { host.refresh(plugin.id) }
    case .toggle:
      PillToggle(isOn: Binding(get: { binding.wrappedValue == "1" }, set: { binding.wrappedValue = $0 ? "1" : "0" }))
    case .choice:
      Picker("", selection: binding) {
        ForEach(setting.options, id: \.self) { Text($0).tag($0) }
      }
      .labelsHidden().frame(width: 200)
    }
  }

  private func remove() {
    host.setEnabled(plugin.id, false)
    NSWorkspace.shared.recycle([plugin.folder]) { _, _ in DispatchQueue.main.async { host.reload() } }
  }
}

/// Browse and install plugins from GitHub: featured ones first, then community repositories
/// tagged `altools-plugin`.
struct PluginStoreView: View {
  @StateObject private var store = PluginStore()
  @ObservedObject private var host = PluginHost.shared
  @State private var query = ""
  @State private var repo = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Plugin store").font(.system(size: 13, weight: .semibold))
        Spacer()
        if store.isLoading { ProgressView().controlSize(.small) }
        Button("Refresh") { store.load() }.buttonStyle(SoftPillButtonStyle()).disabled(store.isLoading)
      }
      Text("Featured plugins and any GitHub repository tagged “\(PluginStore.topic)”. Publishing yours: see PLUGINS.md › Publish.")
        .font(.system(size: 11.5)).foregroundStyle(Theme.dim)
      HStack(spacing: 8) {
        TextField("Search", text: $query).textFieldStyle(.plain)
          .padding(.horizontal, 10).frame(height: 28)
          .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
          .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardBorder))
        TextField("Install from GitHub: owner/repo or a link", text: $repo).textFieldStyle(.plain)
          .padding(.horizontal, 10).frame(height: 28)
          .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
          .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardBorder))
          .onSubmit { install() }
        Button("Install") { install() }.buttonStyle(SoftPillButtonStyle()).disabled(repo.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      if let problem = store.problem {
        Text(problem).font(.system(size: 11)).foregroundStyle(Theme.warning)
      }
      ForEach(filtered) { listing in row(listing) }
      if !store.isLoading, filtered.isEmpty {
        Text(store.listings.isEmpty ? "Nothing listed yet." : "No plugins match “\(query)”.").font(.system(size: 11.5)).foregroundStyle(Theme.faint)
      }
    }
    .padding(14)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
    .onAppear { if store.listings.isEmpty { store.load() } }
  }

  private var filtered: [PluginStore.Listing] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return store.listings }
    return store.listings.filter { l in
      [l.manifest.name, l.manifest.summary ?? "", l.manifest.author ?? "", l.repo].contains { $0.lowercased().contains(q) }
    }
  }

  private func install() {
    PluginStore.installFromGitHub(repo)
    repo = ""
  }

  private func row(_ listing: PluginStore.Listing) -> some View {
    let m = listing.manifest
    let tint = Color(pluginHex: m.tint) ?? Theme.accent
    let installed = host.plugins.first { $0.id == m.id && !$0.builtin }
    return HStack(spacing: 12) {
      Image(systemName: m.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
        .frame(width: 30, height: 30).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(m.name).font(.system(size: 13, weight: .semibold))
          if listing.featured {
            Text("Featured").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
              .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.accent.opacity(0.14), in: Capsule())
          }
          Text([m.author, "v\(m.version)", listing.stars.map { "★ \($0)" }].compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 11)).foregroundStyle(Theme.faint)
        }
        Text(m.summary ?? listing.id).font(.system(size: 11.5)).foregroundStyle(Theme.dim).lineLimit(2)
        Text(listing.id).font(.system(size: 10.5)).foregroundStyle(Theme.faint)
      }
      Spacer()
      if let installed, installed.manifest?.version == m.version {
        Text("Installed").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
      } else {
        Button(installed == nil ? "Install" : "Update") { store.install(listing) }.buttonStyle(SoftPillButtonStyle())
      }
    }
    .padding(.vertical, 4)
  }
}
