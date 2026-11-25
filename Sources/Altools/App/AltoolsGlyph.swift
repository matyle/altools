import AppKit
import SwiftUI

/// The Altools mark in two forms: the full-colour app icon, and a one-colour glyph of the
/// same shape (a notch island over a 3×3 grid) for the menu bar and small labels.
enum AltoolsGlyph {
  /// The bundle's AppIcon; in an unbundled debug run, the system's generic app icon.
  static var appIcon: NSImage { NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage() }

  /// A template image (macOS tints it for light and dark menu bars), `size` points square.
  static func template(size: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
      let unit = rect.width / 18
      NSColor.black.setFill()
      // Island: a pill across the top.
      NSBezierPath(roundedRect: NSRect(x: 4.5 * unit, y: 1 * unit, width: 9 * unit, height: 2.6 * unit),
                   xRadius: 1.3 * unit, yRadius: 1.3 * unit).fill()
      // Grid: 3×3 rounded squares below it.
      let cell = 3.3 * unit, gap = 1.3 * unit
      let left = (rect.width - (cell * 3 + gap * 2)) / 2
      for row in 0..<3 {
        for col in 0..<3 {
          let r = NSRect(x: left + CGFloat(col) * (cell + gap), y: 5 * unit + CGFloat(row) * (cell + gap), width: cell, height: cell)
          NSBezierPath(roundedRect: r, xRadius: unit, yRadius: unit).fill()
        }
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Altools"
    return image
  }
}

/// The colour app icon as a SwiftUI view.
struct AltoolsAppIcon: View {
  var size: CGFloat = 30

  var body: some View {
    Image(nsImage: AltoolsGlyph.appIcon)
      .resizable()
      .interpolation(.high)
      .frame(width: size, height: size)
  }
}
