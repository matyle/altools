import SwiftUI

enum LauncherLayout {
  static let size = CGSize(width: 760, height: 480)
}

struct LauncherView: View {
  @ObservedObject var model: LauncherModel
  @ObservedObject var settings = AppSettings.shared
  @FocusState private var fieldFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().opacity(0.6)
      content.frame(maxHeight: .infinity)
      Divider().opacity(0.6)
      LauncherFooter(model: model)
    }
    .frame(width: LauncherLayout.size.width, height: LauncherLayout.size.height)
    .panelBackground(cornerRadius: 18)
    .onAppear { fieldFocused = true }
    .onChange(of: model.mode) { _, _ in fieldFocused = true }
    // Reopening keeps the same view, so onAppear doesn't run again and the field would stay
    // unfocused; cycling the value makes SwiftUI focus it once the panel is key.
    .onChange(of: model.focusRequest) { _, _ in
      fieldFocused = false
      DispatchQueue.main.async { fieldFocused = true }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      if model.mode != .search {
        ModePill(mode: model.mode, provider: settings.aiProvider.displayName)
      } else {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(.secondary)
      }
      TextField(placeholder, text: $model.query)
        .textFieldStyle(.plain)
        .font(.system(size: 21))
        .focused($fieldFocused)
      if model.mode == .ai, model.runner.isRunning {
        ProgressView().controlSize(.small)
      }
    }
    .padding(.horizontal, 18)
    .frame(height: 60)
  }

  private var placeholder: String {
    switch model.mode {
    case .search: "Search apps, commands, clipboard — or type math"
    case .clipboard: "Filter clipboard history…"
    case .ai: model.runner.entries.isEmpty ? "Ask anything, or press esc to go back" : "Ask a follow-up…"
    }
  }

  @ViewBuilder private var content: some View {
    switch model.mode {
    case .search:
      ResultList(model: model)
    case .clipboard:
      HStack(spacing: 0) {
        ResultList(model: model).frame(width: 300)
        Divider().opacity(0.6)
        ClipPreview(item: model.selectedItem?.clip, store: model.clipboard)
      }
    case .ai:
      if model.runner.entries.isEmpty {
        AISuggestions { model.askAI($0) }
      } else {
        TranscriptView(runner: model.runner)
      }
    }
  }
}

private struct ModePill: View {
  let mode: LauncherModel.Mode
  let provider: String

  var body: some View {
    let (symbol, title, tint): (String, String, Color) = switch mode {
    case .clipboard: ("doc.on.clipboard.fill", "Clipboard", .teal)
    case .ai: ("sparkles", provider, .purple)
    case .search: ("magnifyingglass", "Search", .gray)
    }
    Label(title, systemImage: symbol)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 9).padding(.vertical, 5)
      .background(tint.opacity(0.16), in: Capsule())
  }
}

private struct ResultList: View {
  @ObservedObject var model: LauncherModel

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        // Not lazy: lists are short (≤ 200 rows) and a lazy stack redraws stale rows
        // for a frame when its data is replaced while typing.
        VStack(alignment: .leading, spacing: 1) {
          ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
            if !item.section.isEmpty, index == 0 || model.items[index - 1].section != item.section {
              Text(item.section)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, index == 0 ? 4 : 12)
                .padding(.bottom, 4)
            }
            LauncherRow(item: item, selected: index == model.selection, compact: model.mode == .clipboard)
              .id(item.id)
              // One handler that reads the click count: pairing a count-2 tap with a count-1 tap
              // makes SwiftUI hold every single click for the double-click interval (~0.3–0.5 s).
              .onTapGesture {
                model.selection = index
                if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { model.submit() }
              }
          }
        }
        .padding(8)
      }
      .scrollIndicators(.never)
      .onChange(of: model.selection) { _, index in
        if model.items.indices.contains(index) { proxy.scrollTo(model.items[index].id) }
      }
      .overlay {
        if model.items.isEmpty {
          EmptyState(symbol: model.mode == .clipboard ? "doc.on.clipboard" : "magnifyingglass",
                     title: model.mode == .clipboard ? "Nothing copied yet" : "No matches",
                     detail: model.mode == .clipboard ? "Text and images you copy show up here." : "Press ⇥ to ask AI instead.")
        }
      }
    }
  }
}

private struct LauncherRow: View {
  let item: LauncherItem
  let selected: Bool
  let compact: Bool

  var body: some View {
    HStack(spacing: 11) {
      IconView(icon: item.icon, size: compact ? 24 : 28)
      Text(item.title)
        .font(.system(size: 14, weight: selected ? .medium : .regular))
        .lineLimit(1)
      if !item.subtitle.isEmpty, !compact {
        Text(item.subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 8)
      if selected, !compact {
        HStack(spacing: 6) {
          Text(item.actionName).font(.system(size: 12)).foregroundStyle(.secondary)
          KeyCap("↩")
        }
      } else if !item.accessory.isEmpty {
        Text(item.accessory).font(.system(size: 12)).foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: compact ? 38 : 42)
    .background {
      if selected {
        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.2))
      }
    }
    .contentShape(Rectangle())
  }
}

struct IconView: View {
  let icon: LauncherItem.Icon
  var size: CGFloat = 28

  var body: some View {
    switch icon {
    case .image(let image):
      Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
    case .symbol(let name, let tint):
      Image(systemName: name)
        .font(.system(size: size * 0.48, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(
          LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.7)], startPoint: .top, endPoint: .bottom),
          in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        )
    }
  }
}

struct KeyCap: View {
  let key: String
  init(_ key: String) { self.key = key }

  var body: some View {
    Text(key)
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 5)
      .frame(minWidth: 20, minHeight: 18)
      .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
  }
}

struct EmptyState: View {
  let symbol: String
  let title: String
  let detail: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
      Text(title).font(.system(size: 14, weight: .medium))
      Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
    .padding()
  }
}

private struct ClipPreview: View {
  let item: ClipboardStore.Item?
  let store: ClipboardStore

  var body: some View {
    if let item {
      VStack(alignment: .leading, spacing: 0) {
        Group {
          switch item.kind {
          case .text:
            ScrollView {
              Text(item.value)
                .font(LauncherModel.symbol(forClip: item.value) == "curlybraces" ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
          case .image:
            if let image = NSImage(contentsOf: store.imageURL(for: item)) {
              Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
        }
        .frame(maxHeight: .infinity)
        Divider().opacity(0.6)
        VStack(spacing: 6) {
          meta("Source", item.sourceApp ?? "Unknown")
          meta("Copied", item.date.formatted(date: .abbreviated, time: .shortened))
          if item.kind == .text {
            meta("Content", "\(item.value.count) characters · \(item.value.split(whereSeparator: \.isNewline).count) lines")
          }
        }
        .padding(14)
      }
    } else {
      EmptyState(symbol: "eye", title: "No selection", detail: "Pick an item to preview it.")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func meta(_ label: String, _ value: String) -> some View {
    HStack {
      Text(label).foregroundStyle(.secondary)
      Spacer()
      Text(value).lineLimit(1)
    }
    .font(.system(size: 12))
  }
}

private struct AISuggestions: View {
  let onPick: (String) -> Void
  private let suggestions: [(String, String)] = [
    ("doc.on.clipboard", "Summarize what's on my clipboard"),
    ("folder", "What changed in my most recently modified files in ~/projects?"),
    ("terminal", "Write a shell one-liner to find the 10 largest files in my Downloads folder"),
    ("calendar", "Plan my afternoon: 3 focused blocks with breaks"),
  ]

  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: "sparkles")
        .font(.system(size: 34, weight: .light))
        .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
      Text("Ask \(AppSettings.shared.aiProvider.displayName)")
        .font(.system(size: 17, weight: .semibold))
      Text("Runs the CLI on this Mac with the tools allowed in Settings › AI.")
        .font(.system(size: 12)).foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach(suggestions, id: \.1) { symbol, text in
          Button { onPick(text == suggestions[0].1 ? clipboardPrompt : text) } label: {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: symbol).foregroundStyle(.purple).frame(width: 16)
              Text(text).font(.system(size: 12)).multilineTextAlignment(.leading)
              Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxWidth: 560)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var clipboardPrompt: String {
    let text = NSPasteboard.general.string(forType: .string) ?? ""
    return "Summarize this concisely:\n\n\(text.prefix(20_000))"
  }
}

private struct LauncherFooter: View {
  @ObservedObject var model: LauncherModel
  @ObservedObject var runner: AIRunner
  @ObservedObject var settings = AppSettings.shared

  init(model: LauncherModel) {
    self.model = model
    self.runner = model.runner
  }

  var body: some View {
    HStack(spacing: 14) {
      HStack(spacing: 6) {
        Image(nsImage: AltoolsGlyph.template(size: 13)).renderingMode(.template).foregroundStyle(.secondary)
        Text(leftLabel).foregroundStyle(.secondary)
      }
      .font(.system(size: 12))
      Spacer()
      ForEach(hints, id: \.1) { key, label in
        HStack(spacing: 5) {
          Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
          KeyCap(key)
        }
      }
    }
    .padding(.horizontal, 16)
    .frame(height: 36)
    .background(Color.primary.opacity(0.03))
  }

  private var leftLabel: String {
    switch model.mode {
    case .search: "Altools"
    case .clipboard: "\(model.clipboard.items.count) items"
    case .ai: settings.toolPolicy.displayName
    }
  }

  private var hints: [(String, String)] {
    switch model.mode {
    case .search:
      if model.selectedItem?.clip != nil { return [("↩", "Paste"), ("⌘↩", "Copy")] }
      return [("↩", model.selectedItem?.actionName ?? "Open"), ("⇥", "Ask AI")]
    case .clipboard: return [("↩", "Paste"), ("⌘↩", "Copy"), ("⌘⌫", "Delete")]
    case .ai:
      if runner.isRunning { return [("esc", "Stop")] }
      return runner.entries.isEmpty ? [("↩", "Ask"), ("esc", "Back")] : [("↩", "Send"), ("⌘↩", "Copy answer"), ("esc", "Back")]
    }
  }
}
