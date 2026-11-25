import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {
  /// Needed to read selected text in other apps and to send ⌘C / ⌘V to them.
  static var accessibilityGranted: Bool { AXIsProcessTrusted() }

  static func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  /// Needed for screenshots of other apps' windows.
  static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

  static func requestScreenRecording() {
    _ = CGRequestScreenCaptureAccess()
  }

  static func openPrivacyPane(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
      NSWorkspace.shared.open(url)
    }
  }
}

enum Keystrokes {
  /// Sends ⌘ + key to the frontmost app. Silently does nothing without Accessibility
  /// permission, so callers check `Permissions.accessibilityGranted` first.
  static func command(_ keyCode: CGKeyCode) {
    let source = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cgAnnotatedSessionEventTap)
    up?.post(tap: .cgAnnotatedSessionEventTap)
  }

  static let keyC: CGKeyCode = 8
  static let keyV: CGKeyCode = 9
}

enum Pasteboard {
  /// Pastes `text` into the frontmost app, then restores the previous clipboard so
  /// the user's own clipboard survives. Falls back to copy-only without Accessibility.
  /// Returns false when it could only copy.
  @discardableResult
  static func paste(_ text: String, restoreAfter: Bool = true) -> Bool {
    let pb = NSPasteboard.general
    let saved = restoreAfter ? snapshot() : []
    ClipboardStore.shared.ignoreNextChange()
    pb.clearContents()
    pb.setString(text, forType: .string)
    guard Permissions.accessibilityGranted else { return false }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      Keystrokes.command(Keystrokes.keyV)
      if restoreAfter {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { restore(saved) }
      }
    }
    return true
  }

  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  static func copy(_ image: NSImage) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
  }

  static func snapshot() -> [NSPasteboardItem] {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
      let copy = NSPasteboardItem()
      for type in item.types {
        if let data = item.data(forType: type) { copy.setData(data, forType: type) }
      }
      return copy
    }
  }

  static func restore(_ items: [NSPasteboardItem]) {
    ClipboardStore.shared.ignoreNextChange()
    NSPasteboard.general.clearContents()
    if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
  }
}
