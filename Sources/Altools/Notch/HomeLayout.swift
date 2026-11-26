import SwiftUI

/// The cards on the notch's Home tab, in the order Settings › Notch › Home layout keeps.
enum HomeCard: String, CaseIterable, Identifiable {
  case media, agenda, usage
  var id: String { rawValue }

  static let defaults: [HomeCard] = [.media, .agenda]

  var title: String {
    switch self {
    case .media: "Now playing"
    case .agenda: "Calendar & to-dos"
    case .usage: "AI usage"
    }
  }

  var symbol: String {
    switch self {
    case .media: "music.note"
    case .agenda: "calendar"
    case .usage: "gauge.with.dots.needle.67percent"
    }
  }

  /// Fixed width on Home; nil takes the remaining space.
  var width: CGFloat? {
    switch self {
    case .media: 206
    case .agenda: nil
    case .usage: 140
    }
  }

  /// The capability that must be on for the card to show; nil when it has none.
  var capability: String? {
    switch self {
    case .usage: "notch.usage"
    default: nil
    }
  }
}

/// The buttons along the bottom of Home.
enum HomeAction: String, CaseIterable, Identifiable {
  case capture, ocr, color, clips, translate, ai, launcher, settings
  var id: String { rawValue }

  static let defaults: [HomeAction] = [.capture, .ocr, .color, .clips, .translate, .ai]
  static let maximum = 7

  var title: String {
    switch self {
    case .capture: "Capture"
    case .ocr: "OCR"
    case .color: "Color"
    case .clips: "Clips"
    case .translate: "Translate"
    case .ai: "Ask AI"
    case .launcher: "Launcher"
    case .settings: "Settings"
    }
  }

  var symbol: String {
    switch self {
    case .capture: "camera.viewfinder"
    case .ocr: "text.viewfinder"
    case .color: "eyedropper"
    case .clips: "doc.on.clipboard.fill"
    case .translate: "character.bubble.fill"
    case .ai: "sparkles"
    case .launcher: "magnifyingglass"
    case .settings: "gearshape.fill"
    }
  }

  var tint: Color {
    switch self {
    case .capture: .blue
    case .ocr: .cyan
    case .color: .pink
    case .clips: .teal
    case .translate: .indigo
    case .ai: .purple
    case .launcher: .orange
    case .settings: .gray
    }
  }

  func perform(_ actions: NotchActions) {
    switch self {
    case .capture: actions.captureArea()
    case .ocr: actions.recognizeText()
    case .color: actions.pickColor()
    case .clips: actions.openClipboard()
    case .translate: actions.translate(NSPasteboard.general.string(forType: .string) ?? "")
    case .ai: actions.askAI()
    case .launcher: actions.openLauncher()
    case .settings: actions.openSettings()
    }
  }
}

/// One place on Home: a built-in card, or the Home card of a plugin.
enum HomeSlot: Hashable, Identifiable {
  case builtin(HomeCard)
  case plugin(String)

  /// Home out of the box: Now playing, Calendar & to-dos, and the built-in Markets plugin.
  static let defaults: [HomeSlot] = HomeCard.defaults.map(HomeSlot.builtin) + [.plugin("markets")]

  /// Stored form in `AppSettings.homeCards`: a HomeCard raw value, or "plugin:<id>".
  init?(rawValue: String) {
    if rawValue.hasPrefix("plugin:") {
      let id = String(rawValue.dropFirst("plugin:".count))
      guard !id.isEmpty else { return nil }
      self = .plugin(id)
    } else if let card = HomeCard(rawValue: rawValue) {
      self = .builtin(card)
    } else {
      return nil
    }
  }

  var rawValue: String {
    switch self {
    case .builtin(let card): card.rawValue
    case .plugin(let id): "plugin:\(id)"
    }
  }

  var id: String { rawValue }

  var title: String {
    switch self {
    case .builtin(let card): card.title
    case .plugin(let id): PluginHost.shared.plugins.first { $0.id == id }?.name ?? id
    }
  }

  /// Fixed width on Home; nil takes the remaining space.
  var width: CGFloat? {
    switch self {
    case .builtin(let card): card.width
    // Plugin cards share the row like Calendar & to-dos.
    case .plugin: nil
    }
  }
}

extension AppSettings {
  var homeSlotList: [HomeSlot] {
    get { homeCards.compactMap(HomeSlot.init(rawValue:)) }
    set { homeCards = newValue.map(\.rawValue) }
  }

  var homeActionList: [HomeAction] {
    get { homeActions.compactMap(HomeAction.init(rawValue:)) }
    set { homeActions = newValue.map(\.rawValue) }
  }
}

/// Settings › Notch › Home layout: which cards show and in what order, and which buttons.
struct HomeLayoutEditor: View {
  @ObservedObject private var settings = AppSettings.shared
  @ObservedObject private var plugins = PluginHost.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SettingsCard {
        ForEach(rows) { slot in
          let shown = settings.homeSlotList.contains(slot)
          SettingsRow(slot.title, note: note(for: slot)) {
            HStack(spacing: 6) {
              if shown {
                MoveButton(symbol: "chevron.up", enabled: settings.homeSlotList.first != slot) { move(slot, by: -1) }
                MoveButton(symbol: "chevron.down", enabled: settings.homeSlotList.last != slot) { move(slot, by: 1) }
              }
              PillToggle(isOn: Binding(get: { shown }, set: { toggle(slot, on: $0) }))
            }
          }
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Buttons (up to \(HomeAction.maximum))").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
        FlowChips(selected: settings.homeActionList) { action in
          var list = settings.homeActionList
          if let index = list.firstIndex(of: action) {
            list.remove(at: index)
          } else if list.count < HomeAction.maximum {
            list.append(action)
          }
          settings.homeActionList = list
        }
      }
      Button("Reset to default") {
        settings.homeSlotList = HomeSlot.defaults
        settings.homeActionList = HomeAction.defaults
      }
      .buttonStyle(SoftPillButtonStyle())
    }
  }

  /// Shown slots in their order, then hidden built-in cards and plugins that offer a Home card.
  private var rows: [HomeSlot] {
    let shown = settings.homeSlotList
    let builtins = HomeCard.allCases.map(HomeSlot.builtin)
    let pluginSlots = plugins.plugins.filter { $0.manifest?.slots.contains(.home) == true }.map { HomeSlot.plugin($0.id) }
    return shown + (builtins + pluginSlots).filter { !shown.contains($0) }
  }

  private func note(for slot: HomeSlot) -> String? {
    switch slot {
    case .builtin(let card):
      guard let capability = card.capability, !settings.isOn(capability) else { return nil }
      return "Hidden while \(card.title) is switched off below."
    case .plugin(let id):
      guard let plugin = plugins.plugins.first(where: { $0.id == id }) else { return "Plugin not installed." }
      return plugin.enabled ? "Plugin" : "Plugin — switch it on under Plugins below."
    }
  }

  private func toggle(_ slot: HomeSlot, on: Bool) {
    var list = settings.homeSlotList
    list.removeAll { $0 == slot }
    if on { list.append(slot) }
    settings.homeSlotList = list
  }

  private func move(_ slot: HomeSlot, by offset: Int) {
    var list = settings.homeSlotList
    guard let index = list.firstIndex(of: slot), list.indices.contains(index + offset) else { return }
    list.swapAt(index, index + offset)
    settings.homeSlotList = list
  }
}

private struct MoveButton: View {
  let symbol: String
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 10, weight: .bold))
        .frame(width: 22, height: 22)
        .background(Theme.iconFill, in: RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .foregroundStyle(enabled ? Theme.ink : Theme.faint)
    .disabled(!enabled)
  }
}

/// Every action as a chip; selected ones are numbered in the order they appear on Home.
private struct FlowChips: View {
  let selected: [HomeAction]
  let toggle: (HomeAction) -> Void

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
      ForEach(HomeAction.allCases) { action in
        let position = selected.firstIndex(of: action)
        Button { toggle(action) } label: {
          HStack(spacing: 6) {
            Image(systemName: action.symbol).foregroundStyle(position == nil ? Theme.faint : action.tint)
            Text(action.title).foregroundStyle(position == nil ? Theme.dim : Theme.ink)
            Spacer(minLength: 0)
            if let position { Text("\(position + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent) }
          }
          .font(.system(size: 12, weight: .medium))
          .padding(.horizontal, 10).frame(height: 30)
          .background(position == nil ? Theme.card : Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(position == nil ? Theme.cardBorder : Theme.accent.opacity(0.5)))
        }
        .buttonStyle(.plain)
      }
    }
  }
}
