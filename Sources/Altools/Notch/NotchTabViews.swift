import SwiftUI
import UniformTypeIdentifiers

// MARK: To-do

struct TodoTab: View {
  @ObservedObject var reminders: RemindersStore
  @State private var draft = ""

  var body: some View {
    switch reminders.reminderAccess {
    case .granted: list
    case .notDetermined, .denied:
      VStack(spacing: 10) {
        Image(systemName: "checklist").font(.system(size: 28)).foregroundStyle(.orange)
        Text("Reminders access needed").font(.system(size: 14, weight: .semibold))
        Text("To-dos are your Reminders, synced to your phone by iCloud. Nothing leaves your Mac through Altools.")
          .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center).frame(maxWidth: 380)
        PermissionChip(title: "Allow access", symbol: "lock.open", denied: reminders.reminderAccess == .denied,
                       action: reminders.requestReminders)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var list: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "plus.circle.fill").foregroundStyle(.orange)
        TextField("Add a to-do, e.g. “report tomorrow 3pm”", text: $draft)
          .textFieldStyle(.plain).font(.system(size: 13))
          .onSubmit {
            reminders.add(draft, listName: AppSettings.shared.todoList)
            draft = ""
          }
        if let due = RemindersStore.parseDue(draft).due, !draft.isEmpty {
          Text(due, format: .dateTime.weekday(.abbreviated).hour().minute())
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
        }
        Button { reminders.openInReminders() } label: { Image(systemName: "arrow.up.forward.app") }
          .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).help("Open in Reminders")
      }
      .padding(.horizontal, 12).frame(height: 34)
      .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      if reminders.overdue.isEmpty && reminders.today.isEmpty && reminders.upcoming.isEmpty {
        VStack(spacing: 6) {
          Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(.green)
          Text("All done").font(.system(size: 14, weight: .semibold))
          Text("Nothing due today or in the next 7 days").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            section("Overdue", reminders.overdue, tint: .red)
            section("Today", reminders.today, tint: .orange)
            section("Next 7 days", reminders.upcoming, tint: .white.opacity(0.5))
          }
        }
        .scrollIndicators(.never)
      }
      if let done = reminders.lastCompleted {
        HStack {
          Text("Completed “\(done.title)”").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
          Spacer()
          Button("Undo", action: reminders.undoComplete).buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.snappy, value: reminders.lastCompleted)
  }

  @ViewBuilder private func section(_ title: String, _ items: [RemindersStore.Todo], tint: Color) -> some View {
    if !items.isEmpty {
      Text(title.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(tint)
        .padding(.top, 6).padding(.leading, 4)
      ForEach(items) { todo in TodoRow(todo: todo, reminders: reminders, overdue: tint == .red) }
    }
  }
}

private struct TodoRow: View {
  let todo: RemindersStore.Todo
  let reminders: RemindersStore
  let overdue: Bool
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 10) {
      Button { reminders.complete(todo) } label: {
        Image(systemName: hovering ? "checkmark.circle" : "circle")
          .font(.system(size: 15)).foregroundStyle(todo.color)
      }
      .buttonStyle(.plain)
      Text(todo.title).font(.system(size: 13)).lineLimit(1)
      Spacer()
      if hovering {
        HStack(spacing: 4) {
          snooze("1h", .hour)
          snooze("Tonight", .tonight)
          snooze("Tomorrow", .tomorrow)
        }
        .transition(.opacity)
      } else if let due = todo.due {
        Text(dueText(due)).font(.system(size: 11).monospacedDigit()).foregroundStyle(overdue ? .red : .white.opacity(0.45))
      }
    }
    .padding(.horizontal, 6).frame(height: 28)
    .background(hovering ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
    .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
  }

  private func snooze(_ title: String, _ option: RemindersStore.Snooze) -> some View {
    Button(title) { reminders.snooze(todo, option) }
      .buttonStyle(.plain)
      .font(.system(size: 10, weight: .semibold))
      .padding(.horizontal, 7).frame(height: 20)
      .background(Color.white.opacity(0.12), in: Capsule())
  }

  private func dueText(_ due: Date) -> String {
    if Calendar.current.isDateInToday(due) { return todo.hasTime ? due.formatted(date: .omitted, time: .shortened) : "Today" }
    if todo.hasTime { return due.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
    return due.formatted(.dateTime.month(.abbreviated).day())
  }
}

// MARK: Notes

struct NotesTab: View {
  @ObservedObject var notes: NotesStore
  @FocusState private var editorFocused: Bool

  var body: some View {
    HStack(spacing: 10) {
      VStack(spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
          TextField("Search", text: $notes.query).textFieldStyle(.plain).font(.system(size: 12))
          Button { notes.newNote(); editorFocused = true } label: { Image(systemName: "square.and.pencil") }
            .buttonStyle(.plain).foregroundStyle(.yellow).help("New note ⌥⇧N")
        }
        .padding(.horizontal, 9).frame(height: 28)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        if notes.visibleNotes.isEmpty {
          VStack(spacing: 4) {
            Text(notes.query.isEmpty ? "No notes yet" : "No matches").font(.system(size: 12, weight: .semibold))
            Text("⌥⇧N jots one down, saved as a .md file").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            VStack(spacing: 2) {
              ForEach(notes.visibleNotes) { note in noteRow(note) }
            }
          }
          .scrollIndicators(.never)
        }
      }
      .frame(width: 180)

      NotchCard(padding: 10) {
        if notes.selected != nil {
          VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $notes.text)
              .font(.system(size: 13))
              .scrollContentBackground(.hidden)
              .focused($editorFocused)
            HStack {
              Text(notes.unwritable ? "The notes folder is read-only or gone" : "Saved as Markdown 0.5s after you stop typing")
                .foregroundStyle(notes.unwritable ? .red : .white.opacity(0.35))
              Spacer()
              Button("Show in Finder", action: notes.revealFolder).buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 10))
          }
        } else {
          VStack(spacing: 8) {
            Image(systemName: "note.text").font(.system(size: 26)).foregroundStyle(.yellow.opacity(0.8))
            Button("New note") { notes.newNote(); editorFocused = true }
              .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
              .padding(.horizontal, 12).frame(height: 26)
              .background(Color.yellow.opacity(0.25), in: Capsule())
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .onAppear { if notes.selected != nil { editorFocused = true } }
  }

  private func noteRow(_ note: NotesStore.Note) -> some View {
    let selected = notes.selected == note.url
    let pinned = notes.pinned.contains(note.url.lastPathComponent)
    return Button { notes.open(note); editorFocused = true } label: {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          if pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange) }
          Text(note.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        Text(note.preview.isEmpty ? note.modified.formatted(.relative(presentation: .named)) : note.preview)
          .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 8).padding(.vertical, 5)
      .background(selected ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(pinned ? "Unpin" : "Pin") { notes.togglePin(note) }
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
      Divider()
      Button("Move to Trash", role: .destructive) { notes.delete(note) }
    }
  }
}

// MARK: Shelf

struct ShelfTab: View {
  @ObservedObject var shelf: ShelfStore
  let actions: NotchActions
  @State private var targeted = false

  var body: some View {
    HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
          .foregroundStyle(targeted ? Color.accentColor : Color.white.opacity(0.18))
          .background(targeted ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 14))
        if shelf.files.isEmpty {
          VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).foregroundStyle(.white.opacity(0.5))
            Text("Drop files onto the notch").font(.system(size: 13, weight: .semibold))
            Text("They wait here until you drag them out").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
          }
        } else {
          VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 10) {
                ForEach(shelf.files, id: \.self) { url in ShelfItem(url: url, shelf: shelf) }
              }
              .padding(.horizontal, 12)
            }
            HStack {
              Text("\(shelf.files.count) file(s) · drag out to use").foregroundStyle(.white.opacity(0.4))
              Spacer()
              Button("Clear") { shelf.clear() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size: 10)).padding(.horizontal, 12)
          }
        }
      }
      .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
        Self.loadURLs(providers) { shelf.add($0) }
        return true
      }

      VStack(spacing: 10) {
        DropZone(symbol: "airplayaudio", title: "AirDrop", detail: "Send to devices nearby", tint: .blue) { urls in
          NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
        }
        DropZone(symbol: "text.viewfinder", title: "Recognize text", detail: "Copies an image's text", tint: .cyan) { urls in
          guard let url = urls.first, let image = NSImage(contentsOf: url) else {
            ActivityCenter.shared.report("Drop an image to recognize text", symbol: "exclamationmark.triangle.fill")
            return
          }
          OCR.recognize(image) { text in
            guard let text, !text.isEmpty else { return ActivityCenter.shared.report("No text found", symbol: "text.viewfinder") }
            Pasteboard.copy(text)
            ActivityCenter.shared.report("Copied \(text.count) characters", symbol: "text.viewfinder")
          }
        }
      }
      .frame(width: 200)
    }
  }

  static func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    for provider in providers {
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url { DispatchQueue.main.async { completion([url]) } }
      }
    }
  }
}

private struct DropZone: View {
  let symbol: String
  let title: String
  let detail: String
  let tint: Color
  let perform: ([URL]) -> Void
  @State private var targeted = false

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
        .frame(width: 34, height: 34).background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 12, weight: .semibold))
        Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxHeight: .infinity)
    .background(targeted ? tint.opacity(0.25) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
      var collected: [URL] = []
      let group = DispatchGroup()
      for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          DispatchQueue.main.async {
            if let url { collected.append(url) }
            group.leave()
          }
        }
      }
      group.notify(queue: .main) { if !collected.isEmpty { perform(collected) } }
      return true
    }
  }
}

private struct ShelfItem: View {
  let url: URL
  let shelf: ShelfStore
  @State private var hovering = false

  var body: some View {
    VStack(spacing: 4) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        .resizable().frame(width: 48, height: 48)
        .overlay(alignment: .topTrailing) {
          if hovering {
            Button { shelf.remove(url) } label: {
              Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, .gray)
            }
            .buttonStyle(.plain).offset(x: 6, y: -6)
          }
        }
      Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
    }
    .frame(width: 78)
    .onHover { hovering = $0 }
    .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    .contextMenu {
      Button("Open") { NSWorkspace.shared.open(url) }
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
      Button("AirDrop…") { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url]) }
      Divider()
      Button("Remove from Shelf") { shelf.remove(url) }
    }
  }
}

// MARK: AI usage

struct UsageTab: View {
  @ObservedObject var usage: AIUsage

  var body: some View {
    HStack(spacing: 10) {
      ProviderCard(name: "Claude Code", tint: Color(red: 0.85, green: 0.47, blue: 0.34), provider: usage.claude,
                   connect: usage.connectClaude, refresh: { usage.refresh(force: true) })
      ProviderCard(name: "Codex", tint: Color(red: 0.36, green: 0.78, blue: 0.62), provider: usage.codex,
                   connect: nil, refresh: { usage.refresh(force: true) })
    }
    .onAppear { usage.refresh() }
  }
}

private struct ProviderCard: View {
  let name: String
  let tint: Color
  let provider: AIUsage.Provider
  let connect: (() -> Void)?
  let refresh: () -> Void

  var body: some View {
    NotchCard(padding: 14) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          Circle().fill(tint).frame(width: 8, height: 8)
          Text(name).font(.system(size: 13, weight: .bold))
          if !provider.plan.isEmpty {
            Text(provider.plan).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
              .padding(.horizontal, 6).padding(.vertical, 2).background(tint.opacity(0.18), in: Capsule())
          }
          Spacer()
          if provider.status == .loading {
            ProgressView().controlSize(.mini)
          } else {
            Button(action: refresh) { Image(systemName: "arrow.clockwise") }
              .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
          }
        }
        content
        Spacer(minLength: 0)
        footer
      }
    }
  }

  @ViewBuilder private var content: some View {
    switch provider.status {
    case .notInstalled:
      message("Not installed", "Its plan quota shows here once it is.")
    case .notConnected:
      VStack(alignment: .leading, spacing: 8) {
        Text("Show your plan's 5-hour and weekly quota.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        if let connect {
          Button(action: connect) {
            Label("Connect", systemImage: "link")
              .font(.system(size: 11, weight: .semibold))
              .padding(.horizontal, 10).frame(height: 24)
              .background(tint.opacity(0.3), in: Capsule())
          }
          .buttonStyle(.plain)
        }
        Text("Reads Claude Code's sign-in the way Claude Code does; only Anthropic's usage endpoint sees it.")
          .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).fixedSize(horizontal: false, vertical: true)
      }
    case .signedOut(let hint):
      message("Not signed in", "Run `\(hint)` in Terminal once, then refresh.")
    case .noData(let text):
      message("No quota data", text)
    case .failed(let text):
      message("Couldn't read usage", text)
    case .idle, .loading, .ok:
      VStack(alignment: .leading, spacing: 10) {
        ForEach(provider.windows) { window in WindowBar(window: window, tint: tint) }
      }
    }
  }

  @ViewBuilder private var footer: some View {
    HStack {
      if let tokens = provider.tokensToday {
        Text("Tokens today").foregroundStyle(.white.opacity(0.4))
        Text(tokens.formatted(.number.notation(.compactName))).fontWeight(.semibold)
      }
      Spacer()
      if let updated = provider.updated {
        Text(updated, format: .relative(presentation: .named)).foregroundStyle(.white.opacity(0.35))
      }
    }
    .font(.system(size: 10))
  }

  private func message(_ title: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.system(size: 12, weight: .semibold))
      Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct WindowBar: View {
  let window: AIUsage.Window
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline) {
        Text(window.name).font(.system(size: 11, weight: .semibold))
        if let reset = window.resetsAt {
          Text("resets " + reset.formatted(.relative(presentation: .numeric)))
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
        Spacer()
        Text("\(Int(window.percent.rounded()))%").font(.system(size: 15, weight: .bold).monospacedDigit())
          .foregroundStyle(window.percent >= 90 ? .red : window.percent >= 70 ? .orange : .white)
      }
      HStack(spacing: 2) {
        ForEach(0..<20, id: \.self) { i in
          RoundedRectangle(cornerRadius: 1.5)
            .fill(Double(i) < window.percent / 5 ? (window.percent >= 90 ? Color.red : tint) : Color.white.opacity(0.12))
            .frame(height: 6)
        }
      }
    }
  }
}
