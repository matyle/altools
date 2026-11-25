import SwiftUI

/// The cards on the notch's Home tab, in the order Settings › Notch › Home layout keeps.
enum HomeCard: String, CaseIterable, Identifiable {
  case media, agenda, markets, usage
  var id: String { rawValue }

  static let defaults: [HomeCard] = [.media, .agenda, .markets]

  var title: String {
    switch self {
    case .media: "Now playing"
    case .agenda: "Calendar & to-dos"
    case .markets: "Markets"
    case .usage: "AI usage"
    }
  }

  var symbol: String {
    switch self {
    case .media: "music.note"
    case .agenda: "calendar"
    case .markets: "chart.line.uptrend.xyaxis"
    case .usage: "gauge.with.dots.needle.67percent"
    }
  }

  /// Fixed width on Home; nil takes the remaining space.
  var width: CGFloat? {
    switch self {
    case .media: 206
    case .agenda: nil
    case .markets: 128
    case .usage: 140
    }
  }

  /// The capability that must be on for the card to show; nil when it has none.
  var capability: String? {
    switch self {
    case .markets: "notch.markets"
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

extension AppSettings {
  var homeCardList: [HomeCard] {
    get { homeCards.compactMap(HomeCard.init(rawValue:)) }
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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SettingsCard {
        ForEach(rows, id: \.self) { card in
          let shown = settings.homeCardList.contains(card)
          SettingsRow(card.title, note: note(for: card)) {
            HStack(spacing: 6) {
              if shown {
                MoveButton(symbol: "chevron.up", enabled: settings.homeCardList.first != card) { move(card, by: -1) }
                MoveButton(symbol: "chevron.down", enabled: settings.homeCardList.last != card) { move(card, by: 1) }
              }
              PillToggle(isOn: Binding(get: { shown }, set: { toggle(card, on: $0) }))
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
        settings.homeCardList = HomeCard.defaults
        settings.homeActionList = HomeAction.defaults
      }
      .buttonStyle(SoftPillButtonStyle())
    }
  }

  /// Shown cards in their order, then the hidden ones.
  private var rows: [HomeCard] {
    settings.homeCardList + HomeCard.allCases.filter { !settings.homeCardList.contains($0) }
  }

  private func note(for card: HomeCard) -> String? {
    guard let capability = card.capability, !settings.isOn(capability) else { return nil }
    return "Hidden while \(card.title) is switched off below."
  }

  private func toggle(_ card: HomeCard, on: Bool) {
    var list = settings.homeCardList
    list.removeAll { $0 == card }
    if on { list.append(card) }
    settings.homeCardList = list
  }

  private func move(_ card: HomeCard, by offset: Int) {
    var list = settings.homeCardList
    guard let index = list.firstIndex(of: card), list.indices.contains(index + offset) else { return }
    list.swapAt(index, index + offset)
    settings.homeCardList = list
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
