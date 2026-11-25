import AppKit
import SwiftUI

/// A short message near the bottom of the active screen ("Copied", "Saved").
enum Toast {
  private static var panel: NSPanel?
  private static var hideWork: DispatchWorkItem?

  static func show(_ message: String, symbol: String = "checkmark.circle.fill", duration: TimeInterval = 1.6) {
    hideWork?.cancel()
    let view = Label(message, systemImage: symbol)
      .font(.system(size: 14, weight: .medium))
      .padding(.horizontal, 18).padding(.vertical, 11)
      .panelBackground(cornerRadius: 22)
      .fixedSize()
    let hosting = NSHostingView(rootView: view)
    let size = hosting.fittingSize
    let p = panel ?? {
      let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      p.level = .statusBar
      p.backgroundColor = .clear
      p.isOpaque = false
      p.ignoresMouseEvents = true
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      return p
    }()
    panel = p
    p.contentView = hosting
    let visible = ScreenGeometry.activeScreen.visibleFrame
    p.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 80, width: size.width, height: size.height), display: true)
    p.alphaValue = 1
    p.orderFrontRegardless()
    let work = DispatchWorkItem {
      NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
    }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
  }
}
