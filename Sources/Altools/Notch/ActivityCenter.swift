import AppKit
import SwiftUI

/// Where other modules report things the notch should show: AI runs in progress and
/// "receipts" (screenshot taken, colour picked, text recognized). With the notch off,
/// receipts fall back to a toast.
final class ActivityCenter: ObservableObject {
  static let shared = ActivityCenter()

  struct Receipt: Equatable {
    let id = UUID()
    var symbol: String
    var title: String
    var image: NSImage?
    var tint: Color = .white
    /// Shown as a swatch instead of the symbol.
    var color: Color?
  }

  /// Number of AI requests streaming right now.
  @Published private(set) var aiRunning = 0
  @Published private(set) var receipt: Receipt?
  /// Set by the notch while it is on screen.
  var notchActive = false

  func aiStarted() { aiRunning += 1 }
  func aiFinished() { aiRunning = max(0, aiRunning - 1) }

  func report(_ receipt: Receipt) {
    guard notchActive, AppSettings.shared.isOn("notch.receipts") else {
      Toast.show(receipt.title, symbol: receipt.symbol)
      return
    }
    self.receipt = receipt
  }

  func report(_ title: String, symbol: String = "checkmark.circle.fill", image: NSImage? = nil) {
    report(Receipt(symbol: symbol, title: title, image: image))
  }
}

/// The system colour picker loupe; the picked colour is copied as hex.
enum ColorPicker {
  static func pick() {
    NSColorSampler().show { color in
      guard let color = color?.usingColorSpace(.sRGB) else { return }
      let hex = String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)),
                       Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
      Pasteboard.copy(hex)
      ActivityCenter.shared.report(.init(symbol: "eyedropper", title: "Copied \(hex)", color: Color(nsColor: color)))
    }
  }
}
