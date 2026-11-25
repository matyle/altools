import Carbon
import Foundation

/// System-wide hotkeys through Carbon's RegisterEventHotKey, which works without
/// Accessibility permission (unlike a global keyDown monitor).
final class HotKeyCenter {
  static let shared = HotKeyCenter()

  struct Binding {
    let title: String
    let display: String
    let keyCode: Int
    let modifiers: Int
  }

  private var handlers: [UInt32: () -> Void] = [:]
  private var refs: [EventHotKeyRef] = []
  private var nextID: UInt32 = 1
  private(set) var bindings: [Binding] = []
  /// Bindings macOS refused, usually because another app already owns the combination.
  private(set) var failed: [Binding] = []

  private init() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
      var hotKeyID = EventHotKeyID()
      GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
      let id = hotKeyID.id
      DispatchQueue.main.async { HotKeyCenter.shared.handlers[id]?() }
      return noErr
    }, 1, &spec, nil, nil)
  }

  func register(_ binding: Binding, action: @escaping () -> Void) {
    let id = nextID
    nextID += 1
    var ref: EventHotKeyRef?
    let signature = OSType(0x414C_544C) // "ALTL"
    let status = RegisterEventHotKey(UInt32(binding.keyCode), UInt32(binding.modifiers),
                                     EventHotKeyID(signature: signature, id: id),
                                     GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      failed.append(binding)
      NSLog("Altools: hotkey \(binding.display) is taken (status \(status))")
      return
    }
    refs.append(ref)
    handlers[id] = action
    bindings.append(binding)
  }
}

enum HotKeys {
  static let launcher = HotKeyCenter.Binding(title: "Open launcher", display: "⌥ Space", keyCode: kVK_Space, modifiers: optionKey)
  static let clipboard = HotKeyCenter.Binding(title: "Clipboard history", display: "⌥⇧ V", keyCode: kVK_ANSI_V, modifiers: optionKey | shiftKey)
  static let captureArea = HotKeyCenter.Binding(title: "Capture area", display: "⌥⇧ A", keyCode: kVK_ANSI_A, modifiers: optionKey | shiftKey)
  static let captureText = HotKeyCenter.Binding(title: "Capture text (OCR)", display: "⌥⇧ O", keyCode: kVK_ANSI_O, modifiers: optionKey | shiftKey)
  static let selection = HotKeyCenter.Binding(title: "Actions on selected text", display: "⌥⇧ S", keyCode: kVK_ANSI_S, modifiers: optionKey | shiftKey)
  static let askAI = HotKeyCenter.Binding(title: "Ask AI", display: "⌥⇧ Space", keyCode: kVK_Space, modifiers: optionKey | shiftKey)
  static let menuBar = HotKeyCenter.Binding(title: "Show hidden menu bar icons", display: "⌥ B", keyCode: kVK_ANSI_B, modifiers: optionKey)
  static let notch = HotKeyCenter.Binding(title: "Open the notch", display: "⌥ N", keyCode: kVK_ANSI_N, modifiers: optionKey)
  static let newNote = HotKeyCenter.Binding(title: "New note in the notch", display: "⌥⇧ N", keyCode: kVK_ANSI_N, modifiers: optionKey | shiftKey)
}
