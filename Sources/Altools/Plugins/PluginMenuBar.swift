import AltoolsCore
import AppKit
import SwiftUI

/// Menu-bar items for plugins whose manifest lists `menubar` and whose output has a `menubar` part.
/// Clicking one opens a panel with the plugin's page (its `tab` view or rows).
final class PluginMenuBar {
  private var items: [String: (item: NSStatusItem, panel: MenuBarPanel)] = [:]

  /// Adds, updates and removes items to match the plugins' current output.
  func sync() {
    let host = PluginHost.shared
    let wanted = AppSettings.shared.pluginsEnabled ? host.plugins.filter { $0.shows(.menubar) && $0.output?.menubar != nil } : []
    for id in items.keys where !wanted.contains(where: { $0.id == id }) {
      if let entry = items.removeValue(forKey: id) {
        entry.panel.close()
        NSStatusBar.system.removeStatusItem(entry.item)
      }
    }
    for plugin in wanted {
      let entry = items[plugin.id] ?? add(plugin)
      update(entry.item, with: plugin)
    }
  }

  private func add(_ plugin: PluginHost.Plugin) -> (item: NSStatusItem, panel: MenuBarPanel) {
    // First placement beside the system icons, like the built-in widgets (points from the right edge).
    let positionKey = "NSStatusItem Preferred Position altools.plugin.\(plugin.id)"
    if UserDefaults.standard.object(forKey: positionKey) == nil { UserDefaults.standard.set(360 + items.count * 10, forKey: positionKey) }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.autosaveName = "altools.plugin.\(plugin.id)"
    let id = plugin.id
    let panel = MenuBarPanel(button: item.button) { _ in PluginMenuBarPanel(pluginID: id) }
    item.button?.target = self
    item.button?.action = #selector(clicked(_:))
    item.button?.identifier = NSUserInterfaceItemIdentifier(plugin.id)
    let entry = (item, panel)
    items[plugin.id] = entry
    return entry
  }

  private func update(_ item: NSStatusItem, with plugin: PluginHost.Plugin) {
    guard let bar = plugin.output?.menubar, let button = item.button else { return }
    let image = bar.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: plugin.name) }?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
    if button.image !== image { button.image = image }
    button.imagePosition = bar.text == nil ? .imageOnly : .imageLeading
    button.contentTintColor = bar.tint.flatMap { Color(pluginHex: $0) }.map(NSColor.init)
    let title = bar.text.map { (image == nil ? "" : " ") + $0 } ?? ""
    if button.title != title {
      button.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }
    button.toolTip = plugin.name
  }

  @objc private func clicked(_ sender: NSStatusBarButton) {
    guard let id = sender.identifier?.rawValue else { return }
    items[id]?.panel.toggle()
  }
}

/// The panel under a plugin's menu-bar item.
private struct PluginMenuBarPanel: View {
  let pluginID: String
  @ObservedObject private var host = PluginHost.shared

  var body: some View {
    let plugin = host.plugins.first { $0.id == pluginID }
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: plugin?.manifest?.icon ?? "puzzlepiece.extension.fill")
          .foregroundStyle(Color(pluginHex: plugin?.manifest?.tint) ?? .orange)
        Text(plugin?.output?.tab?.title ?? plugin?.name ?? pluginID).font(.system(size: 13, weight: .semibold))
        Spacer()
        Button { host.refresh(pluginID) } label: { Image(systemName: "arrow.clockwise") }
          .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help("Refresh")
      }
      if let plugin { PluginPage(plugin: plugin) }
    }
    .padding(14)
    .frame(width: 360, height: 300, alignment: .topLeading)
    .foregroundStyle(.white)
    .background(Color(hex: 0x1C1E24))
    .environment(\.colorScheme, .dark)
  }
}
