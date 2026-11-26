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
  private var refs: [UInt32: EventHotKeyRef] = [:]
  private var registered: [(id: UInt32, binding: Binding)] = []
  private var nextID: UInt32 = 1
  var bindings: [Binding] { registered.map(\.binding) }
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

  /// Returns an id for `unregister`, or nil when macOS refused the combination.
  @discardableResult
  func register(_ binding: Binding, action: @escaping () -> Void) -> UInt32? {
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
      return nil
    }
    refs[id] = ref
    handlers[id] = action
    registered.append((id, binding))
    return id
  }

  func unregister(_ id: UInt32) {
    if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    handlers[id] = nil
    registered.removeAll { $0.id == id }
  }

  /// "⌥⇧T", "⌘⌃K" or "option+shift+t", "cmd+ctrl+space"; nil without a modifier or a key it knows.
  static func parse(_ text: String, title: String) -> Binding? {
    var modifiers = 0
    var display = ""
    var remainder = text.trimmingCharacters(in: .whitespaces)
    let symbols: [(Character, Int, String)] = [("⌃", controlKey, "⌃"), ("⌥", optionKey, "⌥"), ("⇧", shiftKey, "⇧"), ("⌘", cmdKey, "⌘")]
    let words: [String: (Int, String)] = ["ctrl": (controlKey, "⌃"), "control": (controlKey, "⌃"), "opt": (optionKey, "⌥"), "option": (optionKey, "⌥"),
                                          "alt": (optionKey, "⌥"), "shift": (shiftKey, "⇧"), "cmd": (cmdKey, "⌘"), "command": (cmdKey, "⌘")]
    if remainder.contains("+") {
      var parts = remainder.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
      remainder = parts.popLast() ?? ""
      for part in parts {
        guard let (flag, sign) = words[part] else { return nil }
        modifiers |= flag
        display += sign
      }
    } else {
      while let first = remainder.first, let match = symbols.first(where: { $0.0 == first }) {
        modifiers |= match.1
        display += match.2
        remainder.removeFirst()
      }
    }
    let key = remainder.trimmingCharacters(in: .whitespaces).lowercased()
    let letters: [String: Int] = ["a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
      "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M,
      "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
      "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
      "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
      "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
      "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "escape": kVK_Escape, "esc": kVK_Escape,
      "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
      "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
      "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12]
    guard modifiers != 0, let code = letters[key] else { return nil }
    return Binding(title: title, display: display + " " + (key.count == 1 ? key.uppercased() : key.capitalized), keyCode: code, modifiers: modifiers)
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
