import AppKit

/// Installed applications, scanned from the standard folders.
final class AppIndex {
  static let shared = AppIndex()

  struct App: Hashable {
    let name: String
    let url: URL
  }

  private(set) var apps: [App] = []
  private var lastScan: Date = .distantPast
  private var iconCache: [URL: NSImage] = [:]
  private let queue = DispatchQueue(label: "altools.appindex", qos: .utility)

  private let roots: [URL] = [
    URL(fileURLWithPath: "/Applications"),
    URL(fileURLWithPath: "/Applications/Utilities"),
    URL(fileURLWithPath: "/System/Applications"),
    URL(fileURLWithPath: "/System/Applications/Utilities"),
    URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
  ]

  /// Rescans in the background if the last scan is older than a few minutes.
  func refreshIfStale() {
    guard Date().timeIntervalSince(lastScan) > 300 else { return }
    lastScan = Date()
    queue.async { [roots] in
      var seen = Set<String>()
      var found: [App] = []
      for root in roots {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in items where url.pathExtension == "app" {
          let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
          if seen.insert(name).inserted { found.append(App(name: name, url: url)) }
        }
      }
      found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      DispatchQueue.main.async { self.apps = found }
    }
  }

  func icon(for url: URL) -> NSImage {
    if let cached = iconCache[url] { return cached }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    icon.size = NSSize(width: 32, height: 32)
    iconCache[url] = icon
    return icon
  }
}
