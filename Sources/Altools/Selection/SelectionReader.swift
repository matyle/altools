import AppKit
import ApplicationServices

enum SelectionReader {
  /// Selected text in the focused element of the frontmost app, via Accessibility.
  /// Returns nil when nothing is selected, the app does not expose selection
  /// (many Electron apps), or Accessibility permission is missing.
  static func readViaAccessibility() -> String? {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
    var value: CFTypeRef?
    // swiftlint:disable:next force_cast
    guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
          let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }

  /// Fallback for apps without Accessibility selection: sends ⌘C, reads the
  /// clipboard, then puts the user's previous clipboard back. Calls back on the
  /// main thread with nil if the copy produced nothing.
  static func readViaCopy(completion: @escaping (String?) -> Void) {
    guard Permissions.accessibilityGranted else { return completion(nil) }
    let pb = NSPasteboard.general
    let saved = Pasteboard.snapshot()
    let before = pb.changeCount
    ClipboardStore.shared.ignoreNextChange()
    Keystrokes.command(Keystrokes.keyC)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
      let text = pb.changeCount != before ? pb.string(forType: .string) : nil
      if pb.changeCount != before { Pasteboard.restore(saved) }
      completion(text?.isEmpty == false ? text : nil)
    }
  }
}
