import AppKit

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
// Menu-bar app: no Dock icon (LSUIElement in Info.plist does the same for the bundle).
app.setActivationPolicy(.accessory)
app.run()
