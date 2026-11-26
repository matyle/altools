import AltoolsCore
import Foundation
import SwiftUI

/// User preferences, persisted in UserDefaults. Read from the main thread only.
final class AppSettings: ObservableObject {
  static let shared = AppSettings()
  private let defaults = UserDefaults.standard

  @Published var aiProvider: AIProvider { didSet { save(aiProvider.rawValue, "aiProvider") } }
  /// Empty means "find it on PATH and the usual install locations".
  @Published var claudePath: String { didSet { save(claudePath, "claudePath") } }
  @Published var codexPath: String { didSet { save(codexPath, "codexPath") } }
  /// Empty means the CLI's own default model.
  @Published var aiModel: String { didSet { save(aiModel, "aiModel") } }
  @Published var toolPolicy: ToolPolicy { didSet { save(toolPolicy.rawValue, "toolPolicy") } }
  /// Working directory for agent runs; file tools act relative to it.
  @Published var workDirectory: String { didSet { save(workDirectory, "workDirectory") } }
  /// Sent to the CLI as HTTP_PROXY / HTTPS_PROXY when non-empty, e.g. http://127.0.0.1:9000.
  @Published var proxy: String { didSet { save(proxy, "proxy") } }
  /// Language that non-CJK text is translated into; CJK text is translated into English.
  @Published var translateTarget: String { didSet { save(translateTarget, "translateTarget") } }

  @Published var notchEnabled: Bool { didSet { save(notchEnabled, "notchEnabled") } }
  /// Also show the island on displays without a notch; it follows the pointer between displays.
  @Published var notchAllDisplays: Bool { didSet { save(notchAllDisplays, "notchAllDisplays") } }
  @Published var launcherEnabled: Bool { didSet { save(launcherEnabled, "launcherEnabled") } }
  @Published var widgetsEnabled: Bool { didSet { save(widgetsEnabled, "widgetsEnabled") } }
  @Published var selectionEnabled: Bool { didSet { save(selectionEnabled, "selectionEnabled") } }
  @Published var captureEnabled: Bool { didSet { save(captureEnabled, "captureEnabled") } }
  /// Capability keys ("notch.volume", "launcher.web", …) the user switched off; everything else is on.
  @Published var disabledCapabilities: Set<String> { didSet { save(Array(disabledCapabilities), "disabledCapabilities") } }
  /// Hide chosen apps' menu bar icons, revealed from the entry icon.
  @Published var hiderEnabled: Bool { didSet { save(hiderEnabled, "hiderEnabled") } }
  /// MenuBarHider.EntryIcon raw value for the menu bar entry.
  @Published var hiderIcon: String { didSet { save(hiderIcon, "hiderIcon") } }
  /// Clicking the empty part of the menu bar reveals hidden icons.
  @Published var hiderClickEmpty: Bool { didSet { save(hiderClickEmpty, "hiderClickEmpty") } }
  /// Double-clicking the entry also reveals the always-hidden icons.
  @Published var hiderDoubleClickAll: Bool { didSet { save(hiderDoubleClickAll, "hiderDoubleClickAll") } }
  /// Resting the pointer on the empty menu bar reveals hidden icons.
  @Published var hiderHover: Bool { didSet { save(hiderHover, "hiderHover") } }
  @Published var hiderHoverDelay: Double { didSet { save(hiderHoverDelay, "hiderHoverDelay") } }
  /// Hide revealed icons again after this many seconds; 0 keeps them shown.
  @Published var hiderAutoHideSeconds: Double { didSet { save(hiderAutoHideSeconds, "hiderAutoHideSeconds") } }
  /// Bundle identifier → MenuBarHider.Section raw value; apps not listed are shown.
  @Published var hiderSections: [String: String] { didSet { save(hiderSections, "hiderSections") } }
  /// Display names of apps in hiderSections, for listing them while they aren't running.
  @Published var hiderAppNames: [String: String] { didSet { save(hiderAppNames, "hiderAppNames") } }
  /// Show other apps' notification banners in the notch (read through Accessibility).
  @Published var notchNotifications: Bool { didSet { save(notchNotifications, "notchNotifications") } }
  /// Bundle IDs whose notifications stay out of the notch.
  @Published var notchMutedApps: [String] { didSet { save(notchMutedApps, "notchMutedApps") } }
  /// Draw a notch shape on displays without one; off leaves an invisible hover area there.
  @Published var notchDrawOnExternal: Bool { didSet { save(notchDrawOnExternal, "notchDrawOnExternal") } }
  /// Seconds the pointer rests on the notch before it opens.
  @Published var notchHoverDelay: Double { didSet { save(notchHoverDelay, "notchHoverDelay") } }
  /// Read Now Playing for every player through the system bridge, not just Music and Spotify.
  @Published var notchSystemNowPlaying: Bool { didSet { save(notchSystemNowPlaying, "notchSystemNowPlaying") } }
  /// Cards on the notch's Home tab, in order (HomeCard raw values).
  @Published var homeCards: [String] { didSet { save(homeCards, "homeCards") } }
  /// Buttons along the bottom of Home, in order (HomeAction raw values).
  @Published var homeActions: [String] { didSet { save(homeActions, "homeActions") } }
  /// Empty means ~/Documents/Altools Notes.
  @Published var notesFolder: String { didSet { save(notesFolder, "notesFolder") } }
  /// Reminders list for new to-dos by name; empty or unmatched uses the default list.
  @Published var todoList: String { didSet { save(todoList, "todoList") } }
  /// The user agreed to let Altools read Claude Code's sign-in from the keychain to show plan usage.
  @Published var claudeUsageConnected: Bool { didSet { save(claudeUsageConnected, "claudeUsageConnected") } }
  /// Show the action bar automatically after selecting text with the mouse.
  @Published var selectionAutoPopup: Bool { didSet { save(selectionAutoPopup, "selectionAutoPopup") } }
  @Published var clipboardEnabled: Bool { didSet { save(clipboardEnabled, "clipboardEnabled") } }

  private init() {
    aiProvider = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .claude
    claudePath = defaults.string(forKey: "claudePath") ?? ""
    codexPath = defaults.string(forKey: "codexPath") ?? ""
    aiModel = defaults.string(forKey: "aiModel") ?? ""
    toolPolicy = ToolPolicy(rawValue: defaults.string(forKey: "toolPolicy") ?? "") ?? .readOnly
    workDirectory = defaults.string(forKey: "workDirectory") ?? NSHomeDirectory()
    proxy = defaults.string(forKey: "proxy") ?? ""
    translateTarget = defaults.string(forKey: "translateTarget") ?? "Simplified Chinese"
    notchEnabled = defaults.object(forKey: "notchEnabled") as? Bool ?? true
    notchAllDisplays = defaults.object(forKey: "notchAllDisplays") as? Bool ?? true
    notchHoverDelay = defaults.object(forKey: "notchHoverDelay") as? Double ?? 0.2
    launcherEnabled = defaults.object(forKey: "launcherEnabled") as? Bool ?? true
    widgetsEnabled = defaults.object(forKey: "widgetsEnabled") as? Bool ?? true
    selectionEnabled = defaults.object(forKey: "selectionEnabled") as? Bool ?? true
    captureEnabled = defaults.object(forKey: "captureEnabled") as? Bool ?? true
    disabledCapabilities = Set(defaults.stringArray(forKey: "disabledCapabilities") ?? [])
    hiderEnabled = defaults.object(forKey: "hiderEnabled") as? Bool ?? true
    hiderAutoHideSeconds = defaults.object(forKey: "hiderAutoHideSeconds") as? Double ?? 5
    hiderIcon = defaults.string(forKey: "hiderIcon") ?? "dot"
    hiderClickEmpty = defaults.object(forKey: "hiderClickEmpty") as? Bool ?? true
    hiderDoubleClickAll = defaults.object(forKey: "hiderDoubleClickAll") as? Bool ?? true
    hiderHover = defaults.object(forKey: "hiderHover") as? Bool ?? true
    hiderHoverDelay = defaults.object(forKey: "hiderHoverDelay") as? Double ?? 0.2
    hiderSections = defaults.dictionary(forKey: "hiderSections") as? [String: String] ?? [:]
    hiderAppNames = defaults.dictionary(forKey: "hiderAppNames") as? [String: String] ?? [:]
    notchNotifications = defaults.object(forKey: "notchNotifications") as? Bool ?? true
    notchMutedApps = defaults.stringArray(forKey: "notchMutedApps") ?? []
    notchDrawOnExternal = defaults.object(forKey: "notchDrawOnExternal") as? Bool ?? true
    notchSystemNowPlaying = defaults.object(forKey: "notchSystemNowPlaying") as? Bool ?? true
    notesFolder = defaults.string(forKey: "notesFolder") ?? ""
    homeCards = defaults.stringArray(forKey: "homeCards") ?? HomeSlot.defaults.map(\.rawValue)
    homeActions = defaults.stringArray(forKey: "homeActions") ?? HomeAction.defaults.map(\.rawValue)
    todoList = defaults.string(forKey: "todoList") ?? ""
    claudeUsageConnected = defaults.object(forKey: "claudeUsageConnected") as? Bool ?? false
    selectionAutoPopup = defaults.object(forKey: "selectionAutoPopup") as? Bool ?? true
    clipboardEnabled = defaults.object(forKey: "clipboardEnabled") as? Bool ?? true
  }

  private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

  func isOn(_ capability: String) -> Bool { !disabledCapabilities.contains(capability) }

  func setOn(_ capability: String, _ on: Bool) {
    if on { disabledCapabilities.remove(capability) } else { disabledCapabilities.insert(capability) }
  }

  /// Once per install: adopt the proxy from the user's `claude` alias. Runs off the
  /// main thread and only fills an empty field, never replacing a proxy the user typed.
  func detectProxyOnce() {
    guard !defaults.bool(forKey: "proxyDetectionDone") else { return }
    DispatchQueue.global(qos: .utility).async {
      let found = CLILocator.proxyFromShellAlias()
      DispatchQueue.main.async {
        self.defaults.set(true, forKey: "proxyDetectionDone")
        if self.proxy.isEmpty, let found { self.proxy = found }
      }
    }
  }

  func binaryPath(for provider: AIProvider) -> String {
    provider == .claude ? claudePath : codexPath
  }
}

enum AppPaths {
  static let support: URL = {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Altools", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  static func subdirectory(_ name: String) -> URL {
    let url = support.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
