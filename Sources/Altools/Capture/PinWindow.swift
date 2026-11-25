import AppKit
import SwiftUI

/// A screenshot floating above all windows. Drag to move, scroll to zoom,
/// double-click or Esc to close, right-click for more.
final class PinWindow: NSPanel {
  var onClose: (() -> Void)?
  private let image: NSImage
  private let baseSize: NSSize
  private var zoom: CGFloat = 1

  init(image: NSImage) {
    self.image = image
    let visible = ScreenGeometry.activeScreen.visibleFrame
    let ratio = min(1, visible.width * 0.6 / image.size.width, visible.height * 0.6 / image.size.height)
    baseSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
    super.init(contentRect: NSRect(origin: .zero, size: baseSize),
               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isMovableByWindowBackground = true
    hasShadow = true
    backgroundColor = .clear
    isReleasedWhenClosed = false
    let mouse = NSEvent.mouseLocation
    setFrameOrigin(NSPoint(x: mouse.x - baseSize.width / 2, y: mouse.y - baseSize.height / 2))
    contentView = PinContentView(image: image, owner: self)
  }

  override var canBecomeKey: Bool { true }

  override func cancelOperation(_ sender: Any?) { closePin() }

  override func scrollWheel(with event: NSEvent) {
    zoom = min(max(zoom * (1 + event.scrollingDeltaY * 0.01), 0.2), 4)
    let center = NSPoint(x: frame.midX, y: frame.midY)
    let size = NSSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
    setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), display: true)
  }

  func closePin() {
    orderOut(nil)
    onClose?()
  }

  func menu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(ClosureMenuItem("Copy") { [weak self] in
      guard let self else { return }
      Pasteboard.copy(self.image)
      Toast.show("Copied")
    })
    menu.addItem(ClosureMenuItem("Save to Pictures") { [weak self] in
      if let image = self?.image { CaptureController.save(image) }
    })
    menu.addItem(ClosureMenuItem("Copy Text (OCR)") { [weak self] in
      guard let image = self?.image else { return }
      OCR.recognize(image) { text in
        guard let text, !text.isEmpty else { return Toast.show("No text found", symbol: "text.viewfinder") }
        Pasteboard.copy(text)
        Toast.show("Text copied", symbol: "text.viewfinder")
      }
    })
    menu.addItem(.separator())
    for opacity in [100, 75, 50] {
      menu.addItem(ClosureMenuItem("Opacity \(opacity)%") { [weak self] in self?.alphaValue = CGFloat(opacity) / 100 })
    }
    menu.addItem(.separator())
    menu.addItem(ClosureMenuItem("Close") { [weak self] in self?.closePin() })
    return menu
  }
}

private final class PinContentView: NSImageView {
  weak var owner: PinWindow?

  init(image: NSImage, owner: PinWindow) {
    self.owner = owner
    super.init(frame: .zero)
    self.image = image
    imageScaling = .scaleAxesIndependently
    wantsLayer = true
    layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
    layer?.borderWidth = 1
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override var mouseDownCanMoveWindow: Bool { true }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { owner?.closePin() } else { super.mouseDown(with: event) }
  }

  override func menu(for event: NSEvent) -> NSMenu? { owner?.menu() }
}

/// NSMenuItem that runs a closure, so menus can be built without @objc targets.
final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], handler: @escaping () -> Void) {
    self.handler = handler
    super.init(title: title, action: #selector(run), keyEquivalent: key)
    keyEquivalentModifierMask = modifiers
    target = self
  }

  required init(coder: NSCoder) { fatalError("not used") }

  @objc private func run() { handler() }
}
