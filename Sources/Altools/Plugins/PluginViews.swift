import AltoolsCore
import SwiftUI

extension Color {
  /// "#RRGGBB" from a plugin; nil for anything else.
  init?(pluginHex: String?) {
    guard let hex = pluginHex.flatMap(PluginManifest.normalizedHex), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
    self.init(hex: value)
  }
}

/// A plugin's rows; clicking one performs its action.
struct PluginRowList: View {
  let rows: [PluginOutput.Row]
  let pluginID: String
  var tint: Color = .orange
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 4 : 2) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        Button {
          if let action = row.action { PluginHost.shared.perform(action, plugin: pluginID) }
        } label: {
          HStack(spacing: 8) {
            if let symbol = row.symbol {
              Image(systemName: symbol)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(Color(pluginHex: row.tint) ?? tint)
                .frame(width: compact ? 14 : 18)
            }
            VStack(alignment: .leading, spacing: 0) {
              Text(row.title).font(.system(size: compact ? 11 : 12, weight: .medium)).lineLimit(1)
              if !compact, let subtitle = row.subtitle {
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
              }
            }
            Spacer(minLength: 4)
            if let value = row.value {
              Text(value).font(.system(size: compact ? 10 : 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
          }
          .padding(.horizontal, compact ? 0 : 8).padding(.vertical, compact ? 0 : 5)
          .background(compact ? Color.clear : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.action == nil)
      }
    }
  }
}

/// A plugin's card on Home: its own layout when it gives one, otherwise its title and first rows.
struct PluginHomeCard: View {
  let plugin: PluginHost.Plugin

  var body: some View {
    let tint = Color(pluginHex: plugin.manifest?.tint) ?? .orange
    VStack(alignment: .leading, spacing: 6) {
      if let error = plugin.error {
        header(tint)
        Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(3)
      } else if let view = plugin.output?.home?.view {
        PluginNodeView(node: view, pluginID: plugin.id, folder: plugin.folder, accent: tint)
      } else if let rows = plugin.output?.home?.rows, !rows.isEmpty {
        header(tint)
        PluginRowList(rows: Array(rows.prefix(3)), pluginID: plugin.id, tint: tint, compact: true)
      } else {
        header(tint)
        Text(plugin.running ? "Loading…" : "Nothing to show").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func header(_ tint: Color) -> some View {
    HStack(spacing: 5) {
      Image(systemName: plugin.manifest?.icon ?? "puzzlepiece.extension.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
      Text(plugin.output?.home?.title ?? plugin.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
    }
  }
}

/// A plugin's page, shown when its tab in the notch's tab row is open.
struct PluginPage: View {
  let plugin: PluginHost.Plugin

  var body: some View {
    let tint = Color(pluginHex: plugin.manifest?.tint) ?? .orange
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        if let error = plugin.error {
          Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
        }
        if let view = plugin.output?.tab?.view {
          PluginNodeView(node: view, pluginID: plugin.id, folder: plugin.folder, accent: tint)
        } else {
          ForEach(Array((plugin.output?.tab?.sections ?? []).enumerated()), id: \.offset) { _, section in
            if let title = section.title {
              Text(title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.white.opacity(0.4))
            }
            PluginRowList(rows: section.rows, pluginID: plugin.id, tint: tint)
          }
        }
        if plugin.output == nil, plugin.error == nil {
          Text(plugin.running ? "Loading…" : "Nothing to show yet").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.never)
  }
}

/// An alert dropped from the notch by a plugin.
struct PluginAlertCard: View {
  let pluginID: String
  let alert: PluginOutput.Alert
  let dismiss: () -> Void

  var body: some View {
    let plugin = PluginHost.shared.plugins.first { $0.id == pluginID }
    let tint = Color(pluginHex: alert.tint ?? plugin?.manifest?.tint) ?? .orange
    Button {
      if let action = alert.action { PluginHost.shared.perform(action, plugin: pluginID) }
      dismiss()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: alert.symbol ?? plugin?.manifest?.icon ?? "puzzlepiece.extension.fill")
          .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
          .frame(width: 36, height: 36).background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 6) {
            Text(alert.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(plugin?.name ?? pluginID).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
          }
          if let body = alert.body {
            Text(body).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
          }
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
