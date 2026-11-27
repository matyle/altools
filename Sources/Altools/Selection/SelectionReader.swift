import AppKit
import ApplicationServices

enum SelectionReader {
  /// Selected text in the focused element of the frontmost app, via Accessibility.
  /// Returns nil when nothing is selected, the app does not expose selection
  /// (apps built on Chromium until `wakeChromiumAccessibility`), or Accessibility
  /// permission is missing.
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

  private static let chromiumBrowsers: Set<String> = [
    "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
    "org.chromium.Chromium", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
    "com.microsoft.edgemac.Canary", "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
    "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "company.thebrowser.Browser",
  ]

  /// Switches on accessibility in a Chromium browser or Electron app, which reports no selection until
  /// then; it stays on until the app quits. Returns whether `app` is such an app, whose page may need a
  /// moment to expose its selection the first time.
  static func wakeChromiumAccessibility(_ app: NSRunningApplication?) -> Bool {
    guard let app, isBuiltOnChromium(app) else { return false }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.5) // a busy app answers late; the default wait is 6 s
    // Reading the application's role turns on basic accessibility (`accessibilityRole` in Chromium's
    // chrome_browser_application_mac.mm and Electron's electron_application.mm). Setting
    // AXEnhancedUserInterface (or Electron's AXManualAccessibility) turns on full screen-reader mode.
    var role: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    return true
  }

  private static func isBuiltOnChromium(_ app: NSRunningApplication) -> Bool {
    if let id = app.bundleIdentifier, chromiumBrowsers.contains(id) { return true }
    guard let bundle = app.bundleURL else { return false }
    return FileManager.default.fileExists(atPath: bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
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
