import AltoolsCore
import EventKit
import SwiftUI

/// What a capability needs from macOS or the user before it can work.
enum Requirement: Equatable {
  case accessibility, screenRecording, calendar, reminders, aiCLI

  var label: String {
    switch self {
    case .accessibility: "Accessibility"
    case .screenRecording: "Screen Recording"
    case .calendar: "Calendar"
    case .reminders: "Reminders"
    case .aiCLI: "Claude Code or Codex"
    }
  }

  func isMet(aiFound: Bool) -> Bool {
    switch self {
    case .accessibility: Permissions.accessibilityGranted
    case .screenRecording: Permissions.screenRecordingGranted
    case .calendar: [.fullAccess, .authorized].contains(EKEventStore.authorizationStatus(for: .event))
    case .reminders: [.fullAccess, .authorized].contains(EKEventStore.authorizationStatus(for: .reminder))
    case .aiCLI: aiFound
    }
  }
}

enum CapabilityState { case on, off, blocked }

struct CapabilitySpec: Identifiable {
  /// Short name shown in mono before the title, e.g. "shell".
  let key: String
  let title: String
  let detail: String
  /// nil: on whenever its module is on ("On with the module").
  var toggle: Binding<Bool>?
  /// Current value summary shown after the dotted leader, e.g. "0.2 sec · All displays".
  var value: String?
  var hotkey: String?
  var requirement: Requirement?
  var settings: AnyView?
  var moduleID = ""
  var id: String { "\(moduleID).\(key)" }
}

struct ModuleSpec: Identifiable {
  let id: String
  let name: String
  let symbol: String
  let tint: Color
  let tagline: String
  let flow: String
  var hotkeys: [String] = []
  let enabled: Binding<Bool>
  var capabilities: [CapabilitySpec]

  func state(_ capability: CapabilitySpec, aiFound: Bool) -> CapabilityState {
    guard enabled.wrappedValue, capability.toggle?.wrappedValue ?? true else { return .off }
    if let requirement = capability.requirement, !requirement.isMet(aiFound: aiFound) { return .blocked }
    return .on
  }

  func counts(aiFound: Bool) -> (on: Int, live: Int) {
    let states = capabilities.map { state($0, aiFound: aiFound) }
    return (states.filter { $0 != .off }.count, states.filter { $0 == .on }.count)
  }
}

/// The modules and their capabilities, bound to AppSettings. Built per render so values stay current.
enum SettingsCatalog {
  static func modules(_ settings: AppSettings) -> [ModuleSpec] {
    func cap(_ key: String) -> Binding<Bool> {
      Binding(get: { settings.isOn(key) }, set: { settings.setOn(key, $0) })
    }
    func bind<T>(_ path: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
      Binding(get: { settings[keyPath: path] }, set: { settings[keyPath: path] = $0 })
    }

    var modules = [
      ModuleSpec(
        id: "launcher", name: "Launcher", symbol: "magnifyingglass", tint: Color(hex: 0xA855F7),
        tagline: "Open apps, do maths, run commands and ask AI from one box",
        flow: "⌥Space → type → ↩ opens · ⇥ hands it to AI",
        hotkeys: ["⌥Space"], enabled: bind(\.launcherEnabled),
        capabilities: [
          CapabilitySpec(key: "apps", title: "Applications", detail: "Fuzzy search across your Applications folders; the best match is ready on ↩."),
          CapabilitySpec(key: "calc", title: "Calculator", detail: "Type maths like 1280*0.85+12^2; ↩ copies the answer.", toggle: cap("launcher.calc")),
          CapabilitySpec(key: "commands", title: "Commands", detail: "Capture, clipboard, notch, sleep displays… type a command's name.", toggle: cap("launcher.commands")),
          CapabilitySpec(key: "web", title: "Web search", detail: "Search Google for whatever you typed.", toggle: cap("launcher.web")),
          CapabilitySpec(key: "ai", title: "Ask AI", detail: "⇥ hands the query to Claude Code or Codex; the answer streams in place, with tools if you allow them.",
                         toggle: cap("launcher.ai"), hotkey: "⌥⇧Space", requirement: .aiCLI),
        ]),
      ModuleSpec(
        id: "clipboard", name: "Clipboard", symbol: "doc.on.clipboard.fill", tint: Color(hex: 0x14B8A6),
        tagline: "Everything you copy, searchable and one keystroke from pasting back",
        flow: "Copy anything → ⌥⇧V → ↩ pastes into the app you were in",
        hotkeys: ["⌥⇧V"], enabled: bind(\.clipboardEnabled),
        capabilities: [
          CapabilitySpec(key: "history", title: "History", detail: "Text, links and images; copies from password managers are skipped."),
          CapabilitySpec(key: "paste", title: "Paste back", detail: "↩ pastes into the app you came from and puts your clipboard back.", requirement: .accessibility),
          CapabilitySpec(key: "preview", title: "Preview", detail: "See the full text or image, where it came from and when, before pasting."),
        ]),
      ModuleSpec(
        id: "selection", name: "Selection", symbol: "character.cursor.ibeam", tint: Color(hex: 0x3B82F6),
        tagline: "Select text in any app, then translate, polish, explain or transform it",
        flow: "Select text → the bar appears → pick an action → Replace or Copy",
        hotkeys: ["⌥⇧S"], enabled: bind(\.selectionEnabled),
        capabilities: [
          CapabilitySpec(key: "bar", title: "Action bar on select", detail: "A small bar follows a drag-select or double-click; off, use ⌥⇧S.",
                         toggle: bind(\.selectionAutoPopup), requirement: .accessibility),
          CapabilitySpec(key: "ai", title: "AI actions", detail: "Translate, explain, polish and summarize, answered by your CLI without tools so they stay fast.",
                         value: settings.translateTarget, requirement: .aiCLI,
                         settings: AnyView(SettingsCard { SettingsRow("Translate non-Chinese text into") {
                           SettingsTextField(text: bind(\.translateTarget), prompt: "Simplified Chinese")
                         } })),
          CapabilitySpec(key: "transform", title: "Text transforms", detail: "Case, trim, URL and Base64 encode/decode, pretty JSON, counts."),
          CapabilitySpec(key: "replace", title: "Replace in place", detail: "Puts the result back where the text was selected.", requirement: .accessibility),
        ]),
      ModuleSpec(
        id: "capture", name: "Capture", symbol: "camera.fill", tint: Color(hex: 0xF97316),
        tagline: "Screenshot an area or window, mark it up, pin it, or pull out its text",
        flow: "⌥⇧A → drag an area (Space for a window) → annotate → Copy",
        hotkeys: ["⌥⇧A", "⌥⇧O"], enabled: bind(\.captureEnabled),
        capabilities: [
          CapabilitySpec(key: "area", title: "Area & window", detail: "The system's own selection: drag an area, or press Space to pick a window.",
                         hotkey: "⌥⇧A", requirement: .screenRecording),
          CapabilitySpec(key: "ocr", title: "Recognize text", detail: "Chinese, English and Japanese text straight to the clipboard.", hotkey: "⌥⇧O"),
          CapabilitySpec(key: "annotate", title: "Annotate", detail: "Rectangles, arrows, pen, highlighter and text, exported at full resolution."),
          CapabilitySpec(key: "pin", title: "Pin", detail: "Float a screenshot above every window for reference."),
          CapabilitySpec(key: "save", title: "Save", detail: "⌘S saves into Pictures › Altools."),
        ]),
      ModuleSpec(
        id: "notch", name: "Notch", symbol: "rectangle.topthird.inset.filled", tint: Color(hex: 0x2DD4BF),
        tagline: "What is happening right now, beside the notch: playback, meetings, notifications, charging",
        flow: "An activity lands in the ears → hover or ⌥N opens → act on Home / drop files onto the shelf",
        hotkeys: ["⌥N", "⌥⇧N"], enabled: bind(\.notchEnabled),
        capabilities: notchCapabilities(settings, cap: cap, bind: bind)),
      ModuleSpec(
        id: "widgets", name: "Widgets", symbol: "square.grid.2x2.fill", tint: Color(hex: 0x22C55E),
        tagline: "Live status items on the right of the menu bar — system, battery, calendar, network — each with its own panel",
        flow: "A status item → click to open its panel",
        enabled: bind(\.widgetsEnabled),
        capabilities: [
          CapabilitySpec(key: "system", title: "System", detail: "CPU in the menu bar; the panel adds a one-minute chart, memory breakdown, storage and the top processes.",
                         toggle: cap("widgets.system")),
          CapabilitySpec(key: "battery", title: "Battery", detail: "Charge in the menu bar; the panel adds time left, health of design capacity, cycles, charger watts and temperature.",
                         toggle: cap("widgets.battery")),
          CapabilitySpec(key: "calendar", title: "Calendar", detail: "Today's date, or a countdown to a meeting within 15 minutes; the panel has the month, the day's events with Join, and a quick New Event.",
                         toggle: cap("widgets.calendar"), requirement: .calendar),
          CapabilitySpec(key: "network", title: "Network", detail: "Live upload and download in the menu bar; the panel adds a chart, Wi-Fi details, local, router and public addresses.",
                         toggle: cap("widgets.network")),
        ]),
      ModuleSpec(
        id: "menubar", name: "Menu Bar", symbol: "menubar.rectangle", tint: Color(hex: 0x6366F1),
        tagline: "Tuck away the menu-bar icons you rarely need, one click to bring them back",
        flow: "⌘-drag icons across the │ lines: shown / hidden / always hidden → click ••• , ⌥B or hover to reach them",
        hotkeys: ["⌥B"], enabled: bind(\.hiderEnabled),
        capabilities: [
          CapabilitySpec(key: "reveal", title: "Reveal the hidden band",
                         detail: "Click the entry icon or press ⌥B to show the icons left of the │ line, click again to tuck them away.",
                         hotkey: "⌥B",
                         settings: AnyView(SettingsCard {
                           SettingsRow("Entry icon") { EntryIconPicker(selection: bind(\.hiderIcon)) }
                           SettingsRow("Click empty space to reveal") { PillToggle(isOn: bind(\.hiderClickEmpty)) }
                           SettingsRow("Double-click reveals all", note: "Including the always-hidden icons.") { PillToggle(isOn: bind(\.hiderDoubleClickAll)) }
                         })),
          CapabilitySpec(key: "hover", title: "Reveal on hover",
                         detail: "Rest the pointer on the empty menu bar and the hidden icons appear — no click.",
                         toggle: bind(\.hiderHover), value: String(format: "%.1f sec", settings.hiderHoverDelay),
                         settings: AnyView(SettingsCard { SettingsRow("Hover delay") {
                           SettingsPicker(selection: bind(\.hiderHoverDelay), options: [(0.1, "0.1 sec"), (0.2, "0.2 sec"), (0.5, "0.5 sec"), (1.0, "1 sec")])
                         } })),
          CapabilitySpec(key: "rehide", title: "Hide again", detail: "Tucks them away again after the delay, once the pointer leaves the menu bar.",
                         value: settings.hiderAutoHideSeconds == 0 ? "never" : "\(Int(settings.hiderAutoHideSeconds)) sec",
                         settings: AnyView(SettingsCard { SettingsRow("Hide again after") {
                           SettingsPicker(selection: bind(\.hiderAutoHideSeconds),
                                          options: [(3.0, "3 sec"), (5.0, "5 sec"), (10.0, "10 sec"), (30.0, "30 sec"), (0.0, "Never")])
                         } })),
          CapabilitySpec(key: "always", title: "Always hidden",
                         detail: "Icons left of the second │ line stay out of sight even when the band is shown; double-click the entry to see them."),
        ]),
    ]
    for index in modules.indices {
      for c in modules[index].capabilities.indices { modules[index].capabilities[c].moduleID = modules[index].id }
    }
    return modules
  }

  private static func notchCapabilities(_ settings: AppSettings, cap: (String) -> Binding<Bool>,
                                        bind: (ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool>) -> [CapabilitySpec] {
    let delay = settings.notchHoverDelay == 0 ? "instant" : String(format: "%.1f sec", settings.notchHoverDelay)
    let hoverDelay = Binding(get: { settings.notchHoverDelay }, set: { settings.notchHoverDelay = $0 })
    let notesFolder = Binding(get: { settings.notesFolder }, set: { settings.notesFolder = $0 })
    let todoList = Binding(get: { settings.todoList }, set: { settings.todoList = $0 })
    return [
      CapabilitySpec(key: "shell", title: "Notch shell",
                     detail: "Invisible at rest, flush with the hardware notch; hover or ⌥N opens it, moving away closes it.",
                     value: "\(delay) · \(settings.notchAllDisplays ? "All displays" : "Notched display")", hotkey: "⌥N",
                     settings: AnyView(SettingsCard {
                       SettingsRow("Hover delay") {
                         SettingsPicker(selection: hoverDelay, options: [(0.0, "Instant"), (0.2, "0.2 sec"), (0.4, "0.4 sec"), (0.8, "0.8 sec")])
                       }
                       SettingsRow("Show on") {
                         SettingsPicker(selection: bind(\.notchAllDisplays), options: [(true, "All displays"), (false, "The notched display")])
                       }
                       SettingsRow("Draw a notch on displays without one") { PillToggle(isOn: bind(\.notchDrawOnExternal)) }
                     })),
      CapabilitySpec(key: "nowplaying", title: "Now playing",
                     detail: "Any player's cover, title and progress in the ears — NetEase, QQ Music, a browser; controls and scrubbing when open.",
                     toggle: cap("notch.nowplaying"),
                     settings: AnyView(SettingsCard {
                       SettingsRow("Read the system's Now Playing", note: "Through the system's own perl; a macOS update may close it, then only Music and Spotify show.") {
                         PillToggle(isOn: bind(\.notchSystemNowPlaying))
                       }
                     })),
      CapabilitySpec(key: "notifications", title: "App notifications",
                     detail: "When another app's banner appears, the notch shows who it is from; click to open the app. Reads only the banner's text, never stores or sends it.",
                     toggle: bind(\.notchNotifications), requirement: .accessibility),
      CapabilitySpec(key: "meetings", title: "Meetings",
                     detail: "A countdown in the ears from five minutes before; a card drops down with Join, which opens Zoom or Teams directly.",
                     toggle: cap("notch.meetings"), requirement: .calendar),
      CapabilitySpec(key: "volume", title: "Volume", detail: "Volume keys show a level bar in the notch, for speakers or AirPods.", toggle: cap("notch.volume")),
      CapabilitySpec(key: "power", title: "Battery", detail: "Shown for 2.5 s when the cable goes in or out; at 10% or less it stays until power is back.", toggle: cap("notch.power")),
      CapabilitySpec(key: "input", title: "Input source & Caps Lock", detail: "Switching input source or Caps Lock flashes the new state.", toggle: cap("notch.input")),
      CapabilitySpec(key: "sensors", title: "Camera & microphone", detail: "Green while an app has the camera, orange with the app name while one records audio.", toggle: cap("notch.sensors")),
      CapabilitySpec(key: "downloads", title: "Finished downloads", detail: "When a download or AirDrop lands in Downloads, the notch shows the file.", toggle: cap("notch.downloads")),
      CapabilitySpec(key: "receipts", title: "Receipts", detail: "Screenshots, picked colours and recognized text report in the notch instead of a toast.", toggle: cap("notch.receipts")),
      CapabilitySpec(key: "todo", title: "To-do", detail: "Your Reminders: overdue, today and the next 7 days; the input understands “tomorrow 3pm”.",
                     toggle: cap("notch.todo"), requirement: .reminders,
                     settings: AnyView(SettingsCard { SettingsRow("New to-dos go to") { SettingsTextField(text: todoList, prompt: "Default list") } })),
      CapabilitySpec(key: "notes", title: "Notes", detail: "One .md file per note in a folder you choose; edits from another editor show up at once.",
                     toggle: cap("notch.notes"), hotkey: "⌥⇧N",
                     settings: AnyView(SettingsCard { SettingsRow("Notes folder", note: "Can point into iCloud Drive or an Obsidian vault.") {
                       SettingsTextField(text: notesFolder, prompt: "~/Documents/Altools Notes")
                     } })),
      CapabilitySpec(key: "shelf", title: "Shelf", detail: "Drop files onto the notch to keep them handy; drag out, AirDrop or recognize text.", toggle: cap("notch.shelf")),
      CapabilitySpec(key: "usage", title: "AI usage",
                     detail: "Claude Code's and Codex's own plan quotas — five hours and the week, with reset times — and tokens used today.",
                     toggle: cap("notch.usage"), value: settings.claudeUsageConnected ? "Claude connected" : "Claude not connected",
                     settings: AnyView(SettingsCard {
                       SettingsRow("Claude Code plan usage", note: "Reads Claude Code's sign-in the way Claude Code does, with no password prompt.") {
                         PillToggle(isOn: bind(\.claudeUsageConnected))
                       }
                     })),
    ]
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}
