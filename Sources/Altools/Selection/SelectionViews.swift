import AltoolsCore
import SwiftUI

final class SelectionResultModel: ObservableObject {
  enum Mode { case ai, text }
  @Published var title = ""
  @Published var mode: Mode = .text
  /// The AI action shown, nil for a local transform.
  @Published var aiAction: SelectionController.AIAction?
  @Published var source = ""
  @Published var staticText = ""
  @Published var canReplace = false
}

struct SelectionBar: View {
  let onCopy: () -> Void
  let onSearch: () -> Void
  let onAI: (SelectionController.AIAction) -> Void
  let onAsk: () -> Void
  let onTransform: (TextTransform) -> Void

  var body: some View {
    HStack(spacing: 0) {
      BarButton(symbol: "doc.on.doc", title: "Copy", action: onCopy)
      BarButton(symbol: "magnifyingglass", title: "Search", action: onSearch)
      separator
      BarButton(symbol: "character.bubble", title: "Translate", tint: .blue) { onAI(.translate) }
      BarButton(symbol: "wand.and.stars", title: "Polish", tint: .pink) { onAI(.polish) }
      BarButton(symbol: "questionmark.bubble", title: "Explain", tint: .orange) { onAI(.explain) }
      BarButton(symbol: "sparkles", title: "Ask", tint: .purple, action: onAsk)
      separator
      Menu {
        Button("Summarize", systemImage: "text.alignleft") { onAI(.summarize) }
        Divider()
        ForEach(TextTransform.allCases) { transform in
          Button(transform.title) { onTransform(transform) }
        }
      } label: {
        Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .frame(width: 34, height: 30)
    }
    .padding(.horizontal, 4)
    .frame(height: 38)
    .panelBackground(cornerRadius: 11)
    .fixedSize()
  }

  private var separator: some View {
    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 3)
  }
}

private struct BarButton: View {
  let symbol: String
  let title: String
  var tint: Color = .primary
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: symbol).foregroundStyle(tint == .primary ? Color.secondary : tint)
        Text(title)
      }
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 8)
      .frame(height: 28)
      .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}

struct SelectionResultView: View {
  @ObservedObject var model: SelectionResultModel
  @ObservedObject var runner: AIRunner
  let onSwitch: (SelectionController.AIAction) -> Void
  let onCopy: () -> Void
  let onReplace: () -> Void
  let onClose: () -> Void

  static let size = CGSize(width: 500, height: 380)

  var body: some View {
    VStack(spacing: 0) {
      header
      sourceStrip
      Divider().opacity(0.6)
      Group {
        if model.mode == .ai {
          TranscriptView(runner: runner)
        } else {
          ScrollView {
            Text(model.staticText)
              .font(.system(size: 13, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(16)
          }
        }
      }
      .frame(maxHeight: .infinity)
      Divider().opacity(0.6)
      footer
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .panelBackground(cornerRadius: 16)
  }

  private var header: some View {
    HStack(spacing: 4) {
      if model.mode == .ai {
        ForEach(SelectionController.AIAction.allCases, id: \.self) { action in
          Button { onSwitch(action) } label: {
            Label(action.rawValue, systemImage: action.symbol)
              .font(.system(size: 12, weight: .medium))
              .padding(.horizontal, 9).frame(height: 26)
              .background(model.aiAction == action ? Color.accentColor.opacity(0.22) : .clear, in: Capsule())
              .foregroundStyle(model.aiAction == action ? Color.primary : Color.secondary)
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      } else {
        Label(model.title, systemImage: "textformat").font(.system(size: 13, weight: .semibold))
      }
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
          .frame(width: 22, height: 22).background(Color.primary.opacity(0.07), in: Circle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .frame(height: 46)
  }

  private var sourceStrip: some View {
    Text(model.source.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12).padding(.vertical, 8)
      .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .padding(.horizontal, 12).padding(.bottom, 10)
  }

  private var footer: some View {
    HStack(spacing: 8) {
      if model.mode == .ai {
        Text(runner.isRunning ? "Writing…" : AppSettings.shared.aiProvider.displayName)
          .font(.system(size: 11)).foregroundStyle(.tertiary)
      }
      Spacer()
      Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
        .buttonStyle(SoftButtonStyle())
      if model.canReplace {
        Button(action: onReplace) { Label("Replace", systemImage: "arrow.left.arrow.right") }
          .buttonStyle(AccentButtonStyle())
          .keyboardShortcut(.return, modifiers: .command)
      }
    }
    .disabled(model.mode == .ai && runner.isRunning)
    .opacity(model.mode == .ai && runner.isRunning ? 0.5 : 1)
    .padding(.horizontal, 12)
    .frame(height: 52)
  }
}
