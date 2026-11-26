import AltoolsCore
import AppKit
import UniformTypeIdentifiers

/// Sharing plugins: a `.altoolsplugin` file is the plugin folder zipped. Installing one (from a file,
/// a URL, or a GitHub repository) always shows what it is and who made it before anything is copied,
/// since a plugin is a program that runs as the user.
enum PluginPackage {
  static let fileExtension = "altoolsplugin"
  static var contentType: UTType { UTType(filenameExtension: fileExtension) ?? .zip }

  // MARK: Export

  /// Asks where to save, then writes `<id>.altoolsplugin`.
  static func export(_ plugin: PluginHost.Plugin) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(plugin.id).\(fileExtension)"
    panel.allowedContentTypes = [contentType]
    panel.message = "Anyone with Altools can double-click this file to install \(plugin.name)."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try zip(plugin.folder, to: url)
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      alert("Couldn't export \(plugin.name)", error.localizedDescription)
    }
  }

  /// The archive keeps the plugin folder at its root (ditto --keepParent), the layout `install` expects.
  static func zip(_ folder: URL, to destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, destination.path])
  }

  // MARK: Install

  /// Lets the user pick a `.altoolsplugin` file or a plugin folder.
  static func importWithPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [contentType, .zip, .folder]
    panel.canChooseDirectories = true
    panel.message = "Choose a .altoolsplugin file or a plugin folder"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    install(from: url, source: url.lastPathComponent)
  }

  /// Installs from a local package, zip or folder. `subpath` picks a plugin inside a larger archive
  /// (a repository holding several plugins).
  static func install(from url: URL, source: String, subpath: String? = nil) {
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("altools-plugin-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: staging) }
    do {
      var root = url
      if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", url.path, staging.path])
        root = staging
      }
      guard let folder = findPlugin(in: root, subpath: subpath) else {
        throw PackageError("no plugin.json in \(source)")
      }
      let manifest = try PluginManifest.decode(Data(contentsOf: folder.appendingPathComponent("plugin.json")))
      guard confirm(manifest, source: source) else { return }
      let target = PluginHost.folder.appendingPathComponent(manifest.id)
      try? FileManager.default.removeItem(at: target)
      try FileManager.default.copyItem(at: folder, to: target)
      let host = PluginHost.shared
      host.reload()
      host.setEnabled(manifest.id, true)
      Toast.show("Installed \(manifest.name)", symbol: "puzzlepiece.extension.fill", duration: 2)
    } catch let error as PluginManifestError {
      alert("This plugin can't be installed", error.description)
    } catch {
      alert("This plugin can't be installed", error.localizedDescription)
    }
  }

  /// Downloads a package (or any zip holding a plugin) through the proxy, then installs it.
  static func install(remote url: URL, source: String? = nil, subpath: String? = nil) {
    Toast.show("Downloading plugin…", symbol: "arrow.down.circle", duration: 2)
    ProxySession.shared.downloadTask(with: url) { file, response, error in
      // The temporary file is deleted when this handler returns, so keep a copy.
      var kept: URL?
      if let file, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("altools-download-\(UUID().uuidString).zip")
        if (try? FileManager.default.moveItem(at: file, to: copy)) != nil { kept = copy }
      }
      DispatchQueue.main.async {
        guard let kept else {
          alert("Couldn't download the plugin", error?.localizedDescription ?? "The server answered \((response as? HTTPURLResponse)?.statusCode ?? 0).")
          return
        }
        install(from: kept, source: source ?? url.host ?? url.absoluteString, subpath: subpath)
        try? FileManager.default.removeItem(at: kept)
      }
    }.resume()
  }

  /// Installs from a GitHub repository ("owner/name"), optionally a plugin in a subfolder, at a
  /// branch or tag (default: the repository's default branch).
  static func install(repo: String, path: String? = nil, ref: String? = nil) {
    let parts = repo.split(separator: "/")
    guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }) else {
      alert("That isn't a GitHub repository", "Use owner/name, e.g. matyle/altools.")
      return
    }
    // codeload serves "HEAD" as the default branch.
    let url = URL(string: "https://codeload.github.com/\(repo)/zip/\(ref ?? "HEAD")")!
    install(remote: url, source: "github.com/\(repo)" + (path.map { "/\($0)" } ?? ""), subpath: path)
  }

  /// Handles `altools://install-plugin?repo=owner/name[&path=sub/dir][&ref=v1.0]` or `?url=<https zip>`.
  static func handle(_ url: URL) -> Bool {
    guard url.scheme == "altools", url.host == "install-plugin",
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
    let value = { (name: String) in items.first { $0.name == name }?.value }
    if let repo = value("repo") {
      install(repo: repo, path: value("path"), ref: value("ref"))
    } else if let raw = value("url"), let remote = URL(string: raw), remote.scheme == "https" {
      install(remote: remote)
    } else {
      alert("This install link is incomplete", url.absoluteString)
    }
    return true
  }

  // MARK: Helpers

  /// plugin.json at `root/subpath`, at the root, or one or two folders down (an archive's
  /// top folder, or a repository's single plugin folder).
  private static func findPlugin(in root: URL, subpath: String?) -> URL? {
    let fm = FileManager.default
    let has = { (folder: URL) in fm.fileExists(atPath: folder.appendingPathComponent("plugin.json").path) }
    let children = { (folder: URL) in
      ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && $0.lastPathComponent != "__MACOSX" }
    }
    if let subpath, !subpath.contains("..") {
      let direct = root.appendingPathComponent(subpath)
      if has(direct) { return direct }
      for top in children(root) where has(top.appendingPathComponent(subpath)) { return top.appendingPathComponent(subpath) }
      return nil
    }
    if has(root) { return root }
    for child in children(root) {
      if has(child) { return child }
      let inner = children(child).filter(has)
      if inner.count == 1 { return inner[0] }
    }
    return nil
  }

  #if DEBUG
  /// Debug runtime test only: install without the confirmation dialog.
  static var autoConfirm = false
  #endif

  private static func confirm(_ manifest: PluginManifest, source: String) -> Bool {
    #if DEBUG
    if autoConfirm { return true }
    #endif
    let existing = PluginHost.shared.plugins.first { $0.id == manifest.id && !$0.builtin }
    let alert = NSAlert()
    alert.messageText = existing == nil
      ? "Install “\(manifest.name)” \(manifest.version)?"
      : "Replace “\(manifest.name)” \(existing?.manifest?.version ?? "") with \(manifest.version)?"
    let names: [PluginSlot: String] = [.ears: "beside the notch", .home: "on Home", .tab: "in the Plugins tab", .alerts: "as alert cards"]
    let places = PluginSlot.allCases.filter(manifest.slots.contains).compactMap { names[$0] }.joined(separator: ", ")
    alert.informativeText = [
      manifest.summary,
      "By \(manifest.author ?? "an unknown author") · from \(source)",
      places.isEmpty ? nil : "Shows \(places).",
      "A plugin is a program that runs on your Mac as you, every \(Int(manifest.interval)) s. Install plugins only from people you trust.",
    ].compactMap { $0 }.joined(separator: "\n\n")
    alert.addButton(withTitle: existing == nil ? "Install" : "Replace")
    alert.addButton(withTitle: "Cancel")
    alert.icon = NSImage(systemSymbolName: manifest.icon, accessibilityDescription: nil) ?? NSApp.applicationIconImage
    NSApp.activate()
    return alert.runModal() == .alertFirstButtonReturn
  }

  private static func alert(_ title: String, _ detail: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    NSApp.activate()
    alert.runModal()
  }

  private static func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let err = Pipe()
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw PackageError(String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private struct PackageError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }
}
