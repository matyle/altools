import AppKit
import SwiftUI

/// A floating panel that can take keyboard focus without activating Altools,
/// so the app the user was working in stays frontmost (needed to paste back into it).
final class FloatingPanel: NSPanel {
  /// Called when the panel loses key status, e.g. the user clicked elsewhere.
  var onResignKey: (() -> Void)?
  var onEscape: (() -> Void)?

  init(contentRect: NSRect, canBecomeKey: Bool = true) {
    self.allowsKey = canBecomeKey
    super.init(contentRect: contentRect,
               styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
               backing: .buffered, defer: false)
    isFloatingPanel = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    hidesOnDeactivate = false
    isMovableByWindowBackground = false
    isReleasedWhenClosed = false
  }

  private let allowsKey: Bool
  override var canBecomeKey: Bool { allowsKey }
  override var canBecomeMain: Bool { false }

  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }

  func setRoot<V: View>(_ view: V) {
    let hosting = FirstClickHostingView(rootView: AnyView(view))
    hosting.sizingOptions = []
    contentView = hosting
  }
}

/// Lets buttons respond to the first click in a panel that is not key, instead of
/// the first click only focusing the panel.
final class FirstClickHostingView: NSHostingView<AnyView> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The frosted rounded background shared by the floating panels.
struct PanelBackground: ViewModifier {
  var cornerRadius: CGFloat = 14
  func body(content: Content) -> some View {
    content
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

extension View {
  func panelBackground(cornerRadius: CGFloat = 14) -> some View { modifier(PanelBackground(cornerRadius: cornerRadius)) }
}

enum ScreenGeometry {
  /// The screen containing the mouse; panels open where the user is looking.
  static var activeScreen: NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
  }

  /// Places a rect of `size` near `point` (screen coordinates), kept fully on screen.
  static func frame(near point: NSPoint, size: NSSize, offset: CGFloat = 12) -> NSRect {
    let visible = (NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? activeScreen).visibleFrame
    var origin = NSPoint(x: point.x - size.width / 2, y: point.y + offset)
    if origin.y + size.height > visible.maxY { origin.y = point.y - offset - size.height }
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
    origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
    return NSRect(origin: origin, size: size)
  }
}

/// Filled accent button. Unlike `.borderedProminent`, it keeps its color in panels
/// that never become key (the selection result panel), where the system style turns grey.
struct AccentButtonStyle: ButtonStyle {
  var tint: Color = .accentColor

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(height: 30)
      .background(tint.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .contentShape(Rectangle())
  }
}

/// Quiet translucent button paired with AccentButtonStyle.
struct SoftButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .padding(.horizontal, 14)
      .frame(height: 30)
      .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .contentShape(Rectangle())
  }
}
