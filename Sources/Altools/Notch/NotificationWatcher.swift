import AppKit
import ApplicationServices

/// Notices other apps' notification banners through Accessibility and reports who
/// sent them and what they say. Reads only the banner's text on screen; nothing is
/// stored past this run or sent anywhere.
final class NotificationWatcher {
  struct Banner: Equatable, Identifiable {
    let id = UUID()
    var appName: String
    var bundleID: String?
    var title: String
    var body: String
    var receivedAt = Date()
  }

  var onBanner: ((Banner) -> Void)?
  private var timer: Timer?
  private var seen: Set<String> = []
  /// The on-screen banner behind each reported Banner, so a click can press it; the newest 30.
  private var elements: [(id: UUID, element: AXUIElement)] = []

  func start() {
    timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.scan() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private var notificationCenterPID: pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier
  }

  private var primed = false

  private func scan() {
    guard AXIsProcessTrusted(), let pid = notificationCenterPID else { return }
    let app = AXUIElementCreateApplication(pid)
    var current: Set<String> = []
    for window in Self.children(of: app, attribute: kAXWindowsAttribute) {
      for group in Self.banners(in: window) {
        let key = Self.string(group, kAXIdentifierAttribute) ?? Self.string(group, kAXDescriptionAttribute) ?? ""
        guard !key.isEmpty else { continue }
        current.insert(key)
        // Banners already on screen when Altools starts are old news.
        guard primed, !seen.contains(key), let banner = Self.makeBanner(group) else { continue }
        elements.append((banner.id, group))
        if elements.count > 30 { elements.removeFirst() }
        onBanner?(banner)
      }
    }
    // Forget banners that left the screen; each banner has its own identifier, so a repeat message still counts.
    seen = current
    primed = true
  }

  /// Opens what the notification points at. Pressing the system banner lets the sending app
  /// handle it as a click on the notification (a chat app opens that conversation); once the
  /// banner has left the screen that no longer works, and the app is opened instead.
  func open(_ banner: Banner) {
    if let element = elements.first(where: { $0.id == banner.id })?.element, Self.press(element) { return }
    if let id = banner.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
  }

  /// AXPress, or the banner's "Show" action where AXPress isn't offered.
  private static func press(_ element: AXUIElement) -> Bool {
    if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return true }
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success, let actions = names as? [String] else { return false }
    let show = actions.first { $0.contains("Show") || $0.contains("显示") || $0.contains("打开") }
    return show.map { AXUIElementPerformAction(element, $0 as CFString) == .success } ?? false
  }

  /// Elements whose subrole marks them as a notification banner (AXNotificationCenterBanner).
  private static func banners(in window: AXUIElement) -> [AXUIElement] {
    var found: [AXUIElement] = []
    func walk(_ element: AXUIElement, depth: Int) {
      guard depth < 10 else { return }
      if (string(element, kAXSubroleAttribute) ?? "") == "AXNotificationCenterBanner" {
        found.append(element)
        return
      }
      for child in children(of: element, attribute: kAXChildrenAttribute) { walk(child, depth: depth + 1) }
    }
    walk(window, depth: 0)
    return found
  }

  /// The banner's texts carry identifiers title / subtitle / body; its description is
  /// "App, title, subtitle, body", so the app name is what comes before the title.
  static func makeBanner(_ group: AXUIElement) -> Banner? {
    var fields: [String: String] = [:]
    for child in children(of: group, attribute: kAXChildrenAttribute) {
      guard let id = string(child, kAXIdentifierAttribute), let value = string(child, kAXValueAttribute) else { continue }
      fields[id] = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let description = string(group, kAXDescriptionAttribute) ?? ""
    return makeBanner(description: description, title: fields["title"], subtitle: fields["subtitle"], body: fields["body"])
  }

  static func makeBanner(description: String, title: String?, subtitle: String?, body: String?) -> Banner? {
    let title = title ?? ""
    let appName: String
    if !title.isEmpty, let range = description.range(of: ", " + title) {
      appName = String(description[..<range.lowerBound])
    } else {
      appName = description.split(separator: ",").first.map(String.init) ?? ""
    }
    let lines = [subtitle, body].compactMap { $0 }.filter { !$0.isEmpty }
    guard !title.isEmpty || !lines.isEmpty else { return nil }
    let bundleID = NSWorkspace.shared.runningApplications.first { $0.localizedName == appName }?.bundleIdentifier
    return Banner(appName: appName, bundleID: bundleID, title: title.isEmpty ? appName : title, body: lines.joined(separator: " · "))
  }

  // MARK: AX helpers

  static func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
  }

  static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
  }

  /// Debug aid: the banner windows' accessibility tree as indented text.
  static func dumpTree() -> String {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier else {
      return "NotificationCenter not running"
    }
    var lines: [String] = []
    func walk(_ element: AXUIElement, depth: Int) {
      guard depth < 14 else { return }
      let parts = [kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute, kAXIdentifierAttribute]
        .compactMap { attr in string(element, attr).map { "\(attr.replacingOccurrences(of: "AX", with: ""))=\($0.prefix(80))" } }
      lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " | "))
      for child in children(of: element, attribute: kAXChildrenAttribute) { walk(child, depth: depth + 1) }
    }
    let app = AXUIElementCreateApplication(pid)
    for window in children(of: app, attribute: kAXWindowsAttribute) { walk(window, depth: 0) }
    return lines.isEmpty ? "no windows" : lines.joined(separator: "\n")
  }
}
