import AppKit

/// Files parked on the notch shelf. Stores references to the original files
/// (nothing is copied); entries whose file disappeared are dropped on load.
final class ShelfStore: ObservableObject {
  @Published private(set) var files: [URL] = []
  private let key = "shelfFiles"

  init() {
    let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
    files = paths.map(URL.init(fileURLWithPath:)).filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  func add(_ urls: [URL]) {
    for url in urls where !files.contains(url) { files.append(url) }
    save()
  }

  func remove(_ url: URL) {
    files.removeAll { $0 == url }
    save()
  }

  func clear() {
    files = []
    save()
  }

  private func save() {
    UserDefaults.standard.set(files.map(\.path), forKey: key)
  }
}
