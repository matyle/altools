import AltoolsCore
import AppKit
import SwiftUI

/// Draws a plugin's own layout (PluginNode) with native views, in the notch's dark style.
struct PluginNodeView: View {
  let node: PluginNode
  let pluginID: String
  /// Local images resolve inside this folder only.
  let folder: URL?
  var accent: Color = .orange

  var body: some View { render(node) }

  private func render(_ node: PluginNode) -> AnyView {
    switch node {
    case let .stack(axis, alignment, spacing, children, style):
      let content: AnyView = axis == .vertical
        ? AnyView(VStack(alignment: horizontal(alignment), spacing: spacing.map { CGFloat($0) } ?? 6) { ForEach(children.indices, id: \.self) { render(children[$0]) } })
        : AnyView(HStack(alignment: vertical(alignment), spacing: spacing.map { CGFloat($0) } ?? 6) { ForEach(children.indices, id: \.self) { render(children[$0]) } })
      return styled(content, style)
    case let .grid(columns, spacing, children, style):
      let gap = spacing.map { CGFloat($0) } ?? 6
      let grid = LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap, alignment: .top), count: columns), alignment: .leading, spacing: gap) {
        ForEach(children.indices, id: \.self) { render(children[$0]) }
      }
      return styled(AnyView(grid), style)
    case let .card(padding, color, children, style):
      let tint = color.map(resolve)
      let card = VStack(alignment: .leading, spacing: 4) { ForEach(children.indices, id: \.self) { render(children[$0]) } }
        .padding(padding.map { CGFloat($0) } ?? 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((tint?.opacity(0.18)) ?? Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      return styled(AnyView(card), style)
    case let .text(text, size, weight, color, mono, lines, style):
      var font = Font.system(size: size.map { CGFloat($0) } ?? 12, weight: fontWeight(weight))
      if mono { font = font.monospacedDigit() }
      let view = Text(text).font(font).foregroundStyle(color.map(resolve) ?? .white).lineLimit(lines)
      return styled(AnyView(view), style)
    case let .symbol(name, size, color, style):
      let view = Image(systemName: name).font(.system(size: size.map { CGFloat($0) } ?? 12, weight: .semibold))
        .foregroundStyle(color.map(resolve) ?? accent)
      return styled(AnyView(view), style)
    case let .image(url, radius, style):
      return styled(AnyView(image(url).clipShape(RoundedRectangle(cornerRadius: radius.map { CGFloat($0) } ?? 4, style: .continuous))), style)
    case let .badge(text, color, style):
      let tint = color.map(resolve) ?? Color.white.opacity(0.6)
      let view = Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(tint.opacity(0.18), in: Capsule())
      return styled(AnyView(view), style)
    case let .progress(value, color, style):
      let tint = color.map(resolve) ?? accent
      let view = GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.15))
          Capsule().fill(tint).frame(width: geo.size.width * value)
        }
      }
      .frame(height: style.height.map { CGFloat($0) } ?? 4)
      return styled(AnyView(view), style, applyHeight: false)
    case let .sparkline(values, color, style):
      let view = PluginSparkline(values: values, color: color.map(resolve) ?? accent)
        .frame(height: style.height.map { CGFloat($0) } ?? 24)
      return styled(AnyView(view), style, applyHeight: false)
    case .spacer:
      return AnyView(Spacer(minLength: 0))
    case .divider:
      return AnyView(Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1))
    }
  }

  private func styled(_ view: AnyView, _ style: PluginNode.Style, applyHeight: Bool = true) -> AnyView {
    var result = view
    if style.width != nil || (applyHeight && style.height != nil) {
      result = AnyView(result.frame(width: style.width.map { CGFloat($0) }, height: applyHeight ? style.height.map { CGFloat($0) } : nil))
    }
    if style.flex { result = AnyView(result.frame(maxWidth: .infinity, alignment: .leading)) }
    if let opacity = style.opacity { result = AnyView(result.opacity(opacity)) }
    if let action = style.action {
      result = AnyView(Button { PluginHost.shared.perform(action, plugin: pluginID) } label: { result.contentShape(Rectangle()) }.buttonStyle(.plain))
    }
    return result
  }

  @ViewBuilder private func image(_ url: String) -> some View {
    if url.hasPrefix("https://"), let remote = URL(string: url) {
      AsyncImage(url: remote) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.white.opacity(0.06) }
    } else if let local = localImage(url) {
      Image(nsImage: local).resizable().aspectRatio(contentMode: .fill)
    } else {
      Color.white.opacity(0.06)
    }
  }

  /// A file inside the plugin folder; paths that leave it are refused.
  private func localImage(_ path: String) -> NSImage? {
    guard let folder else { return nil }
    let file = folder.appendingPathComponent(path).standardizedFileURL
    guard file.path.hasPrefix(folder.standardizedFileURL.path + "/") else { return nil }
    return NSImage(contentsOf: file)
  }

  private func resolve(_ color: PluginColor) -> Color {
    switch color {
    case .hex(let hex): Color(pluginHex: hex) ?? .white
    case .named(let name):
      switch name {
      case .primary: .white
      case .secondary: .white.opacity(0.6)
      case .tertiary: .white.opacity(0.4)
      case .green: Color(hex: 0x98C379)
      case .red: Color(hex: 0xE06C75)
      case .orange: Color(hex: 0xD19A66)
      case .yellow: Color(hex: 0xE5C07B)
      case .blue: Color(hex: 0x61AFEF)
      case .purple: Color(hex: 0xC678DD)
      case .cyan: Color(hex: 0x56B6C2)
      }
    }
  }

  private func fontWeight(_ weight: PluginNode.Weight) -> Font.Weight {
    switch weight {
    case .regular: .regular
    case .medium: .medium
    case .semibold: .semibold
    case .bold: .bold
    }
  }

  private func horizontal(_ alignment: PluginNode.Alignment) -> HorizontalAlignment {
    switch alignment {
    case .center: .center
    case .trailing: .trailing
    default: .leading
    }
  }

  private func vertical(_ alignment: PluginNode.Alignment) -> VerticalAlignment {
    switch alignment {
    case .top: .top
    case .bottom: .bottom
    default: .center
    }
  }
}

/// A line through the values, scaled to fill the frame.
private struct PluginSparkline: View {
  let values: [Double]
  let color: Color

  var body: some View {
    GeometryReader { geo in
      let low = values.min() ?? 0, high = values.max() ?? 1
      let range = max(high - low, .ulpOfOne)
      Path { path in
        for (index, value) in values.enumerated() {
          let point = CGPoint(x: geo.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                              y: geo.size.height * (1 - CGFloat((value - low) / range)))
          index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
      }
      .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
  }
}
