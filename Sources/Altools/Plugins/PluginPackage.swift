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
      var cancelled = false
      guard let folder = findPlugin(in: root, subpath: subpath, cancelled: &cancelled) else {
        if cancelled { return }
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
  /// `fallbacks` are tried in order when the server refuses `url`.
  static func install(remote url: URL, source: String? = nil, subpath: String? = nil, fallbacks: [URL] = []) {
    Toast.show("Downloading plugin…", symbol: "arrow.down.circle", duration: 2)
    ProxySession.shared.downloadTask(with: url) { file, response, error in
      // The temporary file is deleted when this handler returns, so keep a copy.
      var kept: URL?
      if let file, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("altools-download-\(UUID().uuidString).zip")
        if (try? FileManager.default.moveItem(at: file, to: copy)) != nil { kept = copy }
      }
      DispatchQueue.main.async {
        if kept == nil, let next = fallbacks.first {
          return install(remote: next, source: source, subpath: subpath, fallbacks: Array(fallbacks.dropFirst()))
        }
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
    let source = "github.com/\(repo)" + (path.map { "/\($0)" } ?? "")
    Toast.show("Downloading plugin…", symbol: "arrow.down.circle", duration: 2)
    Task { @MainActor in
      // Just the plugin's files: small, and not caught by filters that block repository archives.
      if let folder = await downloadFiles(repo: repo, path: path, ref: ref ?? "HEAD") {
        install(from: folder, source: source)
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        return
      }
      // The API can be rate-limited (60 calls an hour without a token); fall back to the archive.
      // codeload serves "HEAD" as the default branch; a ref with a slash (feature/x) is only found in
      // its full form, and it may be a branch or a tag.
      let base = "https://codeload.github.com/\(repo)/zip/"
      let refs = ref.map { [$0, "refs/heads/\($0)", "refs/tags/\($0)"] } ?? ["HEAD"]
      let urls = refs.compactMap { URL(string: base + $0) }
      install(remote: urls[0], source: source, subpath: path, fallbacks: Array(urls.dropFirst()))
    }
  }

  /// Downloads the files under `path` (the whole repository when nil) into a temporary folder,
  /// keeping executable bits; nil when the listing or any file can't be fetched, or it's too big
  /// to be a plugin (over 200 files or 20 MB).
  private static func downloadFiles(repo: String, path: String?, ref: String) async -> URL? {
    struct Tree: Decodable {
      struct Entry: Decodable { let path: String; let type: String; let mode: String; let size: Int? }
      let tree: [Entry]
      let truncated: Bool
    }
    let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? ref
    guard let listURL = URL(string: "https://api.github.com/repos/\(repo)/git/trees/\(encodedRef)?recursive=1") else { return nil }
    var request = URLRequest(url: listURL, timeoutInterval: 15)
    request.setValue("Altools", forHTTPHeaderField: "User-Agent")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    guard let (data, response) = try? await ProxySession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let tree = try? JSONDecoder().decode(Tree.self, from: data), !tree.truncated else { return nil }
    let prefix = path.map { $0.hasSuffix("/") ? $0 : $0 + "/" } ?? ""
    let files = tree.tree.filter { $0.type == "blob" && $0.path.hasPrefix(prefix) && !$0.path.contains("/.") && !$0.path.hasPrefix(".") }
    guard !files.isEmpty, files.count <= 200, files.reduce(0, { $0 + ($1.size ?? 0) }) <= 20_000_000 else { return nil }
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("altools-github-\(UUID().uuidString)")
    let folder = staging.appendingPathComponent(path.map { ($0 as NSString).lastPathComponent } ?? repo.split(separator: "/").last.map(String.init) ?? "plugin")
    let session = ProxySession.shared
    let ok = await withTaskGroup(of: Bool.self) { group in
      for file in files {
        group.addTask {
          let relative = String(file.path.dropFirst(prefix.count))
          guard let raw = URL(string: "https://raw.githubusercontent.com/\(repo)/\(encodedRef)/\(file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path)"),
                let (bytes, response) = try? await session.data(from: raw), (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
          let target = folder.appendingPathComponent(relative)
          try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
          guard (try? bytes.write(to: target)) != nil else { return false }
          if file.mode == "100755" { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path) }
          return true
        }
      }
      var all = true
      for await result in group { all = all && result }
      return all
    }
    if !ok { try? FileManager.default.removeItem(at: staging) }
    return ok ? folder : nil
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

  /// The plugin folder in an archive or folder: `root/subpath` when given (also under the archive's
  /// top folder), otherwise every folder with a plugin.json up to five levels down (a GitHub
  /// "Download ZIP" puts examples/plugins/<id> under a top folder). With several, the user picks one.
  private static func findPlugin(in root: URL, subpath: String?, cancelled: inout Bool) -> URL? {
    let fm = FileManager.default
    let has = { (folder: URL) in fm.fileExists(atPath: folder.appendingPathComponent("plugin.json").path) }
    let skipped: Set<String> = ["__MACOSX", "node_modules", ".git", ".build"]
    let children = { (folder: URL) in
      ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !skipped.contains($0.lastPathComponent) }
    }
    if let subpath, !subpath.contains("..") {
      let direct = root.appendingPathComponent(subpath)
      if has(direct) { return direct }
      for top in children(root) where has(top.appendingPathComponent(subpath)) { return top.appendingPathComponent(subpath) }
      return nil
    }
    // Breadth-first, and a plugin folder's own subfolders aren't searched.
    var found: [URL] = []
    var level = [root]
    for _ in 0...5 where !level.isEmpty {
      var next: [URL] = []
      for folder in level {
        if has(folder) { found.append(folder) } else { next += children(folder) }
      }
      level = next
    }
    if found.count <= 1 { return found.first }
    let chosen = choose(among: found)
    cancelled = chosen == nil
    return chosen
  }

  /// Asks which plugin to install when an archive holds several.
  private static func choose(among folders: [URL]) -> URL? {
    #if DEBUG
    if autoConfirm { return folders.first }
    #endif
    let names = folders.map { folder -> String in
      let manifest = try? PluginManifest.decode(Data(contentsOf: folder.appendingPathComponent("plugin.json")))
      return manifest.map { "\($0.name) (\($0.id))" } ?? folder.lastPathComponent
    }
    let alert = NSAlert()
    alert.messageText = "This download holds \(folders.count) plugins"
    alert.informativeText = "Choose the one to install; import the file again for another."
    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
    popup.addItems(withTitles: names)
    alert.accessoryView = popup
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate()
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    return folders[popup.indexOfSelectedItem]
  }

  #if DEBUG
  /// Debug runtime tests only: install without the confirmation dialog.
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
    #if DEBUG
    if autoConfirm { return print("PLUGIN ALERT \(title): \(detail)") }
    #endif
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
