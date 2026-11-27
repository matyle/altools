import AppKit
import SwiftUI

struct Mark: Identifiable {
  enum Tool: String, CaseIterable, Identifiable {
    case rectangle, arrow, pen, highlight, text
    var id: String { rawValue }
    var symbol: String {
      switch self {
      case .rectangle: "rectangle"
      case .arrow: "arrow.up.right"
      case .pen: "scribble"
      case .highlight: "highlighter"
      case .text: "textformat"
      }
    }
  }

  let id = UUID()
  var tool: Tool
  var color: Color
  var lineWidth: CGFloat
  /// Positions as fractions of the image size (0…1, origin top-left), so the same
  /// marks draw correctly in the scaled-down editor and in the full-size export.
  var points: [CGPoint]
  var text = ""
}

/// Draws marks into a canvas of any size; shared by the editor and the export.
struct MarksLayer: View {
  let marks: [Mark]
  /// Multiplies line widths and font sizes (export size ÷ editor size).
  var scale: CGFloat = 1

  var body: some View {
    Canvas { context, size in
      for mark in marks { draw(mark, in: &context, size: size) }
    }
  }

  private func draw(_ mark: Mark, in context: inout GraphicsContext, size: CGSize) {
    let pts = mark.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    guard let first = pts.first else { return }
    let last = pts.last ?? first
    let style = StrokeStyle(lineWidth: mark.lineWidth * scale, lineCap: .round, lineJoin: .round)
    switch mark.tool {
    case .rectangle:
      context.stroke(Path(roundedRect: CGRect(p1: first, p2: last), cornerRadius: 2 * scale), with: .color(mark.color), style: style)
    case .highlight:
      context.fill(Path(CGRect(p1: first, p2: last)), with: .color(mark.color.opacity(0.35)))
    case .pen:
      var path = Path()
      path.addLines(pts)
      context.stroke(path, with: .color(mark.color), style: style)
    case .arrow:
      var path = Path()
      path.move(to: first)
      path.addLine(to: last)
      context.stroke(path, with: .color(mark.color), style: style)
      let angle = atan2(last.y - first.y, last.x - first.x)
      let head = max(12, mark.lineWidth * 4) * scale
      var tip = Path()
      tip.move(to: last)
      tip.addLine(to: CGPoint(x: last.x - head * cos(angle - .pi / 7), y: last.y - head * sin(angle - .pi / 7)))
      tip.addLine(to: CGPoint(x: last.x - head * cos(angle + .pi / 7), y: last.y - head * sin(angle + .pi / 7)))
      tip.closeSubpath()
      context.fill(tip, with: .color(mark.color))
    case .text:
      let text = Text(mark.text).font(.system(size: (12 + mark.lineWidth * 3) * scale, weight: .semibold)).foregroundColor(mark.color)
      context.draw(text, at: first, anchor: .topLeading)
    }
  }
}

private extension CGRect {
  init(p1: CGPoint, p2: CGPoint) {
    self.init(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
  }
}

final class AnnotationModel: ObservableObject {
  let image: NSImage
  @Published var marks: [Mark] = []
  @Published var draft: Mark?
  @Published var tool: Mark.Tool = .rectangle
  @Published var color: Color = .red
  @Published var lineWidth: CGFloat = 3
  /// Where a text mark is being typed (fractional coordinates).
  @Published var textAnchor: CGPoint?
  @Published var textDraft = ""

  init(image: NSImage) { self.image = image }

  func commitText() {
    defer { textAnchor = nil; textDraft = "" }
    guard let anchor = textAnchor, !textDraft.isEmpty else { return }
    marks.append(Mark(tool: .text, color: color, lineWidth: lineWidth, points: [anchor], text: textDraft))
  }

  func undo() {
    if !marks.isEmpty { marks.removeLast() }
  }

  /// The screenshot with marks burned in, at the screenshot's full pixel resolution.
  @MainActor
  func rendered() -> NSImage {
    guard !marks.isEmpty, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
    let pixelSize = CGSize(width: cg.width, height: cg.height)
    let content = ZStack {
      Image(decorative: cg, scale: 1).resizable()
      MarksLayer(marks: marks, scale: pixelSize.width / AnnotationModel.editorSize(for: image).width)
    }
    .frame(width: pixelSize.width, height: pixelSize.height)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    guard let output = renderer.cgImage else { return image }
    // Keep the point size so a Retina screenshot pastes at its on-screen size.
    return NSImage(cgImage: output, size: image.size)
  }

  /// The size the image is shown at in the editor: its point size, shrunk to fit the screen.
  static func editorSize(for image: NSImage) -> CGSize {
    let visible = ScreenGeometry.activeScreen.visibleFrame
    let ratio = min(1, (visible.width - 80) / image.size.width, (visible.height - 160) / image.size.height)
    return CGSize(width: max(image.size.width * ratio, 1), height: max(image.size.height * ratio, 1))
  }
}

struct AnnotationView: View {
  @ObservedObject var model: AnnotationModel
  let onCopy: () -> Void
  let onSave: () -> Void
  let onPin: () -> Void
  let onOCR: () -> Void
  let onClose: () -> Void

  /// Matches the height of a unified-style window toolbar, so the traffic lights center in this row.
  static let toolbarHeight: CGFloat = 52
  private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .white, .black]

  var body: some View {
    let size = AnnotationModel.editorSize(for: model.image)
    VStack(spacing: 0) {
      toolbar
      Divider()
      canvas(size: size)
        .padding(16)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .ignoresSafeArea(edges: .top)
  }

  /// Labelled buttons when the window is wide enough, icons only otherwise, so nothing is clipped.
  private var toolbar: some View {
    ViewThatFits(in: .horizontal) {
      toolbarRow(labelled: true)
      toolbarRow(labelled: false)
    }
    .frame(height: AnnotationView.toolbarHeight)
    .background(alignment: .center) {
      Button("Close", action: onClose).keyboardShortcut(.cancelAction).hidden()
    }
  }

  private func toolbarRow(labelled: Bool) -> some View {
    HStack(spacing: 10) {
      ForEach(Mark.Tool.allCases) { tool in
        Button { model.tool = tool } label: {
          Image(systemName: tool.symbol).frame(width: 26, height: 22)
        }
        .buttonStyle(.borderless)
        .background(model.tool == tool ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .help(tool.rawValue.capitalized)
      }
      Divider().frame(height: 18)
      ForEach(palette, id: \.self) { color in
        Circle().fill(color)
          .frame(width: 16, height: 16)
          .overlay(Circle().strokeBorder(Color.primary.opacity(model.color == color ? 0.9 : 0.2), lineWidth: model.color == color ? 2 : 1))
          .onTapGesture { model.color = color }
      }
      Picker("", selection: $model.lineWidth) {
        Text("S").tag(CGFloat(2)); Text("M").tag(CGFloat(3)); Text("L").tag(CGFloat(6))
      }
      .pickerStyle(.segmented).frame(width: 90).labelsHidden()
      Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(model.marks.isEmpty)
      Spacer()
      Button("Text", systemImage: "text.viewfinder", action: onOCR).help("Copy the text in this image")
      Button("Pin", systemImage: "pin", action: onPin).help("Float above all windows")
      Button("Save", systemImage: "square.and.arrow.down", action: onSave).keyboardShortcut("s", modifiers: .command)
      Button("Copy", systemImage: "doc.on.doc", action: onCopy)
        // While a text mark is being typed, ↩ finishes the text instead.
        .keyboardShortcut(model.textAnchor == nil ? KeyboardShortcut(.return, modifiers: []) : nil)
        .buttonStyle(AccentButtonStyle())
    }
    .labelStyle(LabelVisibility(labelled: labelled))
    // Leaves room for the window's close/minimize buttons, which share this row.
    .padding(.leading, 84)
    .padding(.trailing, 12)
  }

  private func canvas(size: CGSize) -> some View {
    ZStack(alignment: .topLeading) {
      Image(nsImage: model.image).resizable().frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.25), radius: 8)
      MarksLayer(marks: model.marks + (model.draft.map { [$0] } ?? []))
      if let anchor = model.textAnchor {
        TextField("Type, then ↩", text: $model.textDraft)
          .textFieldStyle(.plain)
          .font(.system(size: 12 + model.lineWidth * 3, weight: .semibold))
          .foregroundStyle(model.color)
          .frame(width: 220)
          .padding(2)
          .background(Color.black.opacity(0.15))
          .offset(x: anchor.x * size.width, y: anchor.y * size.height)
          .onSubmit(model.commitText)
      }
    }
    .frame(width: size.width, height: size.height)
    .contentShape(Rectangle())
    .gesture(drawGesture(size: size))
  }

  private func drawGesture(size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let p = CGPoint(x: min(max(value.location.x / size.width, 0), 1), y: min(max(value.location.y / size.height, 0), 1))
        if model.tool == .text { return }
        if model.draft == nil {
          let start = CGPoint(x: value.startLocation.x / size.width, y: value.startLocation.y / size.height)
          model.draft = Mark(tool: model.tool, color: model.color, lineWidth: model.lineWidth, points: [start, p])
        } else if model.tool == .pen {
          model.draft?.points.append(p)
        } else {
          model.draft?.points[1] = p
        }
      }
      .onEnded { value in
        if model.tool == .text {
          model.commitText()
          model.textAnchor = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
          return
        }
        // A click without dragging leaves no mark.
        if let draft = model.draft, hypot(value.translation.width, value.translation.height) > 3 {
          model.marks.append(draft)
        }
        model.draft = nil
      }
  }
}

@MainActor
final class AnnotationWindowController: NSObject, NSWindowDelegate {
  var onClose: (() -> Void)?
  private let model: AnnotationModel
  private weak var capture: CaptureController?
  private(set) var window: NSWindow?

  init(image: NSImage, capture: CaptureController) {
    model = AnnotationModel(image: image)
    self.capture = capture
  }

  func show() {
    let view = AnnotationView(
      model: model,
      onCopy: { [weak self] in
        guard let self else { return }
        model.commitText()
        let image = model.rendered()
        Pasteboard.copy(image)
        ActivityCenter.shared.report("Screenshot copied", symbol: "doc.on.doc.fill", image: image)
        close()
      },
      onSave: { [weak self] in
        guard let self else { return }
        model.commitText()
        CaptureController.save(model.rendered())
      },
      onPin: { [weak self] in
        guard let self else { return }
        model.commitText()
        capture?.pin(model.rendered())
        close()
      },
      onOCR: { [weak self] in
        guard let self else { return }
        OCR.recognize(model.image) { text in
          guard let text, !text.isEmpty else { return Toast.show("No text found", symbol: "text.viewfinder") }
          Pasteboard.copy(text)
          ActivityCenter.shared.report("Copied \(text.count) characters", symbol: "text.viewfinder")
        }
      },
      onClose: { [weak self] in self?.close() }
    )
    let hosting = NSHostingController(rootView: view)
    // The window size is set below; SwiftUI's preferred size would add the title bar height a second time.
    hosting.sizingOptions = []
    let window = NSWindow(contentViewController: hosting)
    window.title = "Screenshot"
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    // An empty unified toolbar makes the title bar as tall as our toolbar row.
    window.toolbar = NSToolbar(identifier: "annotation")
    window.toolbarStyle = .unified
    window.level = .floating
    // The content view spans the title bar, so its size is the whole window: toolbar row, divider, padded image.
    let image = AnnotationModel.editorSize(for: model.image)
    window.setContentSize(NSSize(width: Self.contentWidth(view), height: AnnotationView.toolbarHeight + 1 + image.height + 32))
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  /// At least as wide as the labelled toolbar and the padded image, capped to the screen
  /// (where the toolbar drops its labels instead).
  static func contentWidth(_ view: AnnotationView) -> CGFloat {
    let ideal = NSHostingView(rootView: view.fixedSize()).fittingSize
    let image = AnnotationModel.editorSize(for: view.model.image)
    return min(max(ideal.width, image.width + 32, 720), ScreenGeometry.activeScreen.visibleFrame.width - 40)
  }

  func close() {
    window?.close()
  }

  func windowWillClose(_ notification: Notification) {
    onClose?()
  }
}

private struct LabelVisibility: LabelStyle {
  let labelled: Bool

  func makeBody(configuration: Configuration) -> some View {
    if labelled {
      TitleAndIconLabelStyle().makeBody(configuration: configuration)
    } else {
      IconOnlyLabelStyle().makeBody(configuration: configuration)
    }
  }
}
