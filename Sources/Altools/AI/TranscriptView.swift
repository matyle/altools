import AltoolsCore
import SwiftUI

/// Renders an AIRunner transcript: user prompts, Markdown answers, tool calls, errors.
struct TranscriptView: View {
  @ObservedObject var runner: AIRunner

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(groups) { group in
            switch group.kind {
            case .tools(let entries): ToolSteps(entries: entries)
            case .single(let entry): row(entry)
            }
          }
          if runner.isRunning, runner.entries.last?.kind != .text {
            ThinkingDots()
          }
          Color.clear.frame(height: 1).id("bottom")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .textSelection(.enabled)
      }
      .scrollIndicators(.automatic)
      .onChange(of: runner.entries) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
    }
  }

  /// Consecutive tool calls collapse into one expandable step list.
  private var groups: [Group] {
    var result: [Group] = []
    for entry in runner.entries {
      if entry.kind == .tool, case .tools(let previous)? = result.last?.kind {
        result[result.count - 1] = Group(id: previous[0].id, kind: .tools(previous + [entry]))
      } else {
        result.append(Group(id: entry.id, kind: entry.kind == .tool ? .tools([entry]) : .single(entry)))
      }
    }
    return result
  }

  private struct Group: Identifiable {
    enum Kind { case tools([AIRunner.Entry]), single(AIRunner.Entry) }
    let id: UUID
    let kind: Kind
  }

  @ViewBuilder
  private func row(_ entry: AIRunner.Entry) -> some View {
    switch entry.kind {
    case .user:
      HStack {
        Spacer(minLength: 80)
        Text(entry.content)
          .font(.system(size: 13))
          .lineLimit(8)
          .padding(.horizontal, 12).padding(.vertical, 8)
          .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
    case .text:
      MarkdownView(text: entry.content)
    case .tool:
      ToolSteps(entries: [entry])
    case .error:
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text(entry.content).font(.system(size: 13))
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }
}

private struct ToolSteps: View {
  let entries: [AIRunner.Entry]
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button { withAnimation(.snappy) { expanded.toggle() } } label: {
        HStack(spacing: 6) {
          Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 10))
          Text(entries.count == 1 ? "Used 1 tool" : "Used \(entries.count) tools")
          Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
      }
      .buttonStyle(.plain)
      if expanded {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(entries) { entry in
            Text(entry.content)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .truncationMode(.middle)
          }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 2) }
      }
    }
  }
}

private struct ThinkingDots: View {
  var body: some View {
    TimelineView(.animation) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      HStack(spacing: 5) {
        ForEach(0..<3) { i in
          Circle()
            .fill(Color.purple.opacity(0.8))
            .frame(width: 6, height: 6)
            .opacity(0.3 + 0.7 * max(0, sin(t * 4 - Double(i) * 0.7)))
        }
      }
    }
    .frame(height: 16)
  }
}

/// Block-level Markdown good enough for chat answers: headings, bullet and numbered
/// lists, quotes, fenced code blocks; inline styles via AttributedString.
struct MarkdownView: View {
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
        switch block {
        case .paragraph(let s):
          Text(inline(s)).font(.system(size: 14)).lineSpacing(3)
        case .heading(let level, let s):
          Text(inline(s)).font(.system(size: level == 1 ? 18 : level == 2 ? 16 : 14, weight: .semibold))
            .padding(.top, 4)
        case .bullet(let marker, let s, let indent):
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker).font(.system(size: 14)).foregroundStyle(.secondary).frame(minWidth: 14, alignment: .trailing)
            Text(inline(s)).font(.system(size: 14)).lineSpacing(3)
          }
          .padding(.leading, CGFloat(indent) * 14)
        case .quote(let s):
          Text(inline(s)).font(.system(size: 14)).foregroundStyle(.secondary)
            .padding(.leading, 10)
            .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3) }
        case .code(let language, let code):
          CodeBlock(language: language, code: code)
        }
      }
    }
  }

  private func inline(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(s)
  }
}

private struct CodeBlock: View {
  let language: String
  let code: String
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(language.isEmpty ? "code" : language).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        Spacer()
        Button {
          Pasteboard.copy(code)
          copied = true
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
          Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 12).padding(.vertical, 6)
      .background(Color.primary.opacity(0.05))
      ScrollView(.horizontal, showsIndicators: false) {
        Text(code)
          .font(.system(size: 12, design: .monospaced))
          .padding(12)
      }
    }
    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
  }
}
