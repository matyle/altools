import AppKit

/// Quick notes, one Markdown file per note in a folder (default ~/Documents/Altools Notes).
/// The folder is watched, so edits made in another editor show up straight away.
final class NotesStore: ObservableObject {
  struct Note: Identifiable, Equatable {
    var url: URL
    var title: String
    var preview: String
    var modified: Date
    var id: URL { url }
  }

  @Published private(set) var notes: [Note] = []
  @Published var selected: URL?
  @Published var text = "" {
    didSet { if text != oldValue, !loading { scheduleSave() } }
  }
  @Published var query = ""
  @Published private(set) var pinned: Set<String>
  /// The folder is read-only or gone; open notes stay readable.
  @Published private(set) var unwritable = false

  private var loading = false
  private var saveWork: DispatchWorkItem?
  private var watcher: DispatchSourceFileSystemObject?
  private let pinnedKey = "notesPinned"

  init() {
    pinned = Set(UserDefaults.standard.stringArray(forKey: pinnedKey) ?? [])
  }

  var folder: URL {
    let custom = AppSettings.shared.notesFolder
    if !custom.isEmpty { return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true) }
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Altools Notes", isDirectory: true)
  }

  var visibleNotes: [Note] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    let filtered = q.isEmpty ? notes : notes.filter { $0.title.lowercased().contains(q) || $0.preview.lowercased().contains(q) }
    return filtered.sorted { a, b in
      let pa = pinned.contains(a.url.lastPathComponent), pb = pinned.contains(b.url.lastPathComponent)
      return pa != pb ? pa : a.modified > b.modified
    }
  }

  func start() {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    reload()
    watch()
  }

  func reload() {
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
    notes = files.filter { $0.pathExtension.lowercased() == "md" }.map { url in
      let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      return Note(url: url, title: Self.title(of: content), preview: Self.preview(of: content), modified: modified)
    }
    unwritable = !FileManager.default.isWritableFile(atPath: folder.path)
    // Pick up outside edits to the open note, unless the user has unsaved typing.
    if let selected, saveWork == nil {
      if let content = try? String(contentsOf: selected, encoding: .utf8), content != text { setText(content) }
      if !FileManager.default.fileExists(atPath: selected.path) { self.selected = nil; setText("") }
    }
  }

  func open(_ note: Note) {
    flush()
    selected = note.url
    setText((try? String(contentsOf: note.url, encoding: .utf8)) ?? "")
  }

  func newNote(initialText: String = "") {
    flush()
    let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
      .replacingOccurrences(of: ":", with: ".")
    let url = folder.appendingPathComponent("Note \(stamp).md")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try initialText.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      unwritable = true
      return
    }
    selected = url
    setText(initialText)
    reload()
  }

  func delete(_ note: Note) {
    if selected == note.url { saveWork?.cancel(); saveWork = nil; selected = nil; setText("") }
    try? FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
    reload()
  }

  func togglePin(_ note: Note) {
    let name = note.url.lastPathComponent
    if pinned.contains(name) { pinned.remove(name) } else { pinned.insert(name) }
    UserDefaults.standard.set(Array(pinned), forKey: pinnedKey)
  }

  func revealFolder() {
    NSWorkspace.shared.activateFileViewerSelecting([selected ?? folder])
  }

  /// Writes pending edits now (on switching notes or closing the notch).
  func flush() {
    guard let work = saveWork else { return }
    work.cancel()
    saveWork = nil
    write()
  }

  private func setText(_ value: String) {
    loading = true
    text = value
    loading = false
  }

  /// Saved 0.5 s after typing stops.
  private func scheduleSave() {
    saveWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.saveWork = nil
      self?.write()
    }
    saveWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }

  private func write() {
    guard let selected else { return }
    do {
      try text.write(to: selected, atomically: true, encoding: .utf8)
      unwritable = false
    } catch {
      unwritable = true
    }
    if let index = notes.firstIndex(where: { $0.url == selected }) {
      notes[index].title = Self.title(of: text)
      notes[index].preview = Self.preview(of: text)
      notes[index].modified = Date()
    }
  }

  private func watch() {
    watcher?.cancel()
    let fd = Darwin.open(folder.path, O_EVTONLY)
    guard fd >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
    source.setEventHandler { [weak self] in self?.reload() }
    source.setCancelHandler { close(fd) }
    source.resume()
    watcher = source
  }

  static func title(of content: String) -> String {
    let line = content.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    let title = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
    return title.isEmpty ? "Untitled" : String(title.prefix(80))
  }

  static func preview(of content: String) -> String {
    content.split(separator: "\n", omittingEmptySubsequences: true).dropFirst().prefix(2)
      .joined(separator: " ").trimmingCharacters(in: .whitespaces)
  }
}
