import SwiftUI

/// Assigns each app with menu bar icons to Shown, Hidden or Always hidden. Takes effect at
/// once; apps placed in a section while not running stay listed so they can be moved back.
struct MenuBarLayoutCard: View {
  @ObservedObject private var settings = AppSettings.shared
  @State private var apps: [MenuBarApp] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("\(rows.count) apps with menu bar icons").font(.system(size: 12)).foregroundStyle(Theme.dim)
        Spacer()
        Button("Re-read menu bar") { reload() }.buttonStyle(SoftPillButtonStyle())
      }
      if !SystemMenuBarVisibility.isAvailable {
        Text("Hiding needs macOS 27.").font(.system(size: 12)).foregroundStyle(.orange)
      } else if !AXIsProcessTrusted() {
        Text("Grant Accessibility to list the menu bar icons.").font(.system(size: 12)).foregroundStyle(.orange)
      }
      SettingsCard {
        ForEach(rows) { app in
          HStack(spacing: 10) {
            if let icon = MenuBarApp.icon(for: app.bundleID) {
              Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
              Image(systemName: "app.dashed").frame(width: 22, height: 22).foregroundStyle(Theme.dim)
            }
            VStack(alignment: .leading, spacing: 1) {
              Text(app.name).font(.system(size: 13, weight: .medium))
              if app.iconCount > 1 {
                Text("\(app.iconCount) icons hide together").font(.system(size: 11)).foregroundStyle(Theme.dim)
              } else if app.iconCount == 0 {
                Text(NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty ? "Not running" : "Hidden now").font(.system(size: 11)).foregroundStyle(Theme.dim)
              }
            }
            Spacer()
            Picker("", selection: binding(for: app)) {
              ForEach(MenuBarHider.Section.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
        }
      }
    }
    .onAppear(perform: reload)
  }

  /// Running apps with icons, plus apps the user already sorted that aren't running now.
  private var rows: [MenuBarApp] {
    let running = Set(apps.map(\.bundleID))
    let absent = settings.hiderSections.keys.filter { !running.contains($0) }.map {
      MenuBarApp(bundleID: $0, name: settings.hiderAppNames[$0] ?? $0, iconCount: 0)
    }
    return apps + absent.sorted { $0.name < $1.name }
  }

  private func binding(for app: MenuBarApp) -> Binding<MenuBarHider.Section> {
    Binding(get: { MenuBarHider.section(of: app.bundleID) }, set: { MenuBarHider.setSection($0, for: app) })
  }

  private func reload() {
    DispatchQueue.global(qos: .userInitiated).async {
      let found = MenuBarApp.current()
      DispatchQueue.main.async { apps = found }
    }
  }
}
