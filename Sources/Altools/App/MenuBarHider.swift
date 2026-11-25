import AppKit

/// Hides the menu bar icons of apps the user put in the Hidden or Always-hidden section,
/// like iHive: the system stops drawing them (SystemMenuBarVisibility), nothing is moved.
/// The entry icon, ⌥B, a click or a rest on the empty menu bar brings them back for a while.
final class MenuBarHider {
  enum EntryIcon: String, CaseIterable, Identifiable {
    case dots, dot, chevron, arrow, eye, grid, sidebar
    var id: String { rawValue }
    var symbol: String {
      switch self {
      case .dots: "ellipsis"
      case .dot: "circle.fill"
      case .chevron: "chevron.compact.left"
      case .arrow: "arrow.left"
      case .eye: "eye.slash"
      case .grid: "square.grid.2x2"
      case .sidebar: "sidebar.left"
      }
    }
  }

  enum Section: String, CaseIterable, Identifiable {
    case shown, hidden, always
    var id: String { rawValue }
    var title: String {
      switch self {
      case .shown: "Shown"
      case .hidden: "Hidden"
      case .always: "Always hidden"
      }
    }
  }

  private enum Reveal { case none, hidden, all }

  private let visibility = SystemMenuBarVisibility()
  private var entry: NSStatusItem?
  private var reveal = Reveal.none
  private var autoHide: DispatchWorkItem?
  private var hoverWork: DispatchWorkItem?
  private var hoverPoint = NSPoint.zero
  private var monitors: [Any] = []
  private var launchObserver: Any?

  var isRevealed: Bool { reveal != .none }

  /// The entry's frame and what is hidden right now, for the live self-test report.
  var debugFrames: String {
    "entry=\(entry?.button?.window.map { NSStringFromRect($0.frame) } ?? "none") hidden=\(visibility.hidden.sorted())"
  }

  func start() {
    guard entry == nil else { return }
    let entry = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    entry.autosaveName = "altools.hider.entry"
    entry.button?.target = self
    entry.button?.action = #selector(entryClicked)
    entry.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    self.entry = entry
    installMonitors()
    // The allow-list names running apps only, so a newly launched app needs it rebuilt.
    launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.apply(self.reveal)
    }
    apply(.none)
    if !SystemMenuBarVisibility.isAvailable {
      Toast.show("Hiding menu bar icons needs macOS 27", symbol: "exclamationmark.triangle", duration: 5)
    } else if !UserDefaults.standard.bool(forKey: "hiderLayoutTipShown"), AppSettings.shared.hiderSections.isEmpty {
      UserDefaults.standard.set(true, forKey: "hiderLayoutTipShown")
      Toast.show("Pick the icons to hide in Settings › Menu Bar", symbol: "menubar.rectangle", duration: 6)
    }
  }

  func stop() {
    autoHide?.cancel()
    hoverWork?.cancel()
    visibility.release()
    if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
    launchObserver = nil
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    if let entry { NSStatusBar.system.removeStatusItem(entry) }
    entry = nil
  }

  /// ⌥B: show the hidden icons, or tuck them away.
  func toggle() {
    apply(reveal == .none ? .hidden : .none)
  }

  /// Re-reads the entry icon and the sections after a settings change.
  func refresh() {
    guard entry != nil else { return }
    apply(reveal)
  }

  static func section(of bundleID: String) -> Section {
    AppSettings.shared.hiderSections[bundleID].flatMap(Section.init(rawValue:)) ?? .shown
  }

  static func setSection(_ section: Section, for app: MenuBarApp) {
    let settings = AppSettings.shared
    if section == .shown {
      settings.hiderSections[app.bundleID] = nil
      settings.hiderAppNames[app.bundleID] = nil
    } else {
      settings.hiderSections[app.bundleID] = section.rawValue
      settings.hiderAppNames[app.bundleID] = app.name
    }
  }

  @objc private func entryClicked() {
    guard let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseUp {
      showMenu()
    } else if event.clickCount >= 2, AppSettings.shared.hiderDoubleClickAll {
      apply(.all)
    } else if event.modifierFlags.contains(.option) {
      apply(reveal == .all ? .none : .all)
    } else {
      toggle()
    }
  }

  private func apply(_ value: Reveal) {
    reveal = value
    let sections = AppSettings.shared.hiderSections
    let hidden = Set(sections.filter { _, section in
      switch value {
      case .none: section != Section.shown.rawValue
      case .hidden: section == Section.always.rawValue
      case .all: false
      }
    }.keys)
    visibility.hide(hidden)
    let icon = EntryIcon(rawValue: AppSettings.shared.hiderIcon) ?? .dot
    let image = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: value == .none ? "Show hidden icons" : "Hide icons")
    entry?.button?.image = image?.withSymbolConfiguration(.init(pointSize: icon == .dot ? 6 : 13, weight: .semibold))
    entry?.button?.appearsDisabled = value != .none
    scheduleAutoHide()
  }

  /// System Settings › Menu Bar, where each app's icon can be switched off for good.
  static func openSystemMenuBarSettings() {
    let pane = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
    if !NSWorkspace.shared.open(pane) {
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
  }

  /// The right edge of the frontmost app's menus, read through Accessibility.
  static func appMenusRightEdge() -> CGFloat? {
    guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    var bar: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &bar) == .success,
          let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
    var children: CFTypeRef?
    // swiftlint:disable:next force_cast
    guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
          let items = children as? [AXUIElement] else { return nil }
    return items.compactMap { item -> CGFloat? in
      var position: CFTypeRef?
      var size: CFTypeRef?
      guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success else { return nil }
      var point = CGPoint.zero
      var extent = CGSize.zero
      // swiftlint:disable:next force_cast
      AXValueGetValue(position as! AXValue, .cgPoint, &point)
      // swiftlint:disable:next force_cast
      AXValueGetValue(size as! AXValue, .cgSize, &extent)
      return point.x + extent.width
    }.max()
  }

  /// Tucks the icons away after the delay, but not while the pointer is in the menu bar.
  private func scheduleAutoHide() {
    autoHide?.cancel()
    let seconds = AppSettings.shared.hiderAutoHideSeconds
    guard reveal != .none, seconds > 0 else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      if self.pointerInMenuBar { self.scheduleAutoHide() } else { self.apply(.none) }
    }
    autoHide = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  private var pointerInMenuBar: Bool { Self.menuBarScreen(at: NSEvent.mouseLocation) != nil }

  /// The screen whose menu bar contains `point` (AppKit coordinates), if any.
  private static func menuBarScreen(at point: NSPoint) -> NSScreen? {
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return nil }
    let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
    return point.y >= screen.frame.maxY - height ? screen : nil
  }

  /// True when `point` is on the menu bar but over neither an app menu nor an icon.
  private static func isEmptyMenuBar(at point: NSPoint) -> Bool {
    guard menuBarScreen(at: point) != nil else { return false }
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(mainHeight - point.y), &element)
    guard result == .success, let element else { return result == .noValue }
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    return (role as? String) == kAXMenuBarRole
  }

  // MARK: Click and hover on the empty menu bar

  private func installMonitors() {
    let moved: (NSEvent) -> Void = { [weak self] _ in self?.trackHover() }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved) { monitors.append(global) }
    let clicked: (NSEvent) -> Void = { [weak self] _ in self?.menuBarClicked() }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: clicked) { monitors.append(global) }
  }

  private func menuBarClicked() {
    guard AppSettings.shared.hiderClickEmpty, !visibilityIsEmpty else { return }
    let point = NSEvent.mouseLocation
    guard Self.isEmptyMenuBar(at: point) else { return }
    toggle()
  }

  /// Nothing to reveal when no app is in a hidden section.
  private var visibilityIsEmpty: Bool { AppSettings.shared.hiderSections.isEmpty }

  /// Resting on the empty menu bar for the hover delay reveals the hidden icons.
  private func trackHover() {
    let point = NSEvent.mouseLocation
    guard reveal == .none, AppSettings.shared.hiderHover, !visibilityIsEmpty, Self.menuBarScreen(at: point) != nil else {
      hoverWork?.cancel()
      hoverWork = nil
      return
    }
    if hoverWork != nil, hypot(point.x - hoverPoint.x, point.y - hoverPoint.y) < 6 { return }
    hoverWork?.cancel()
    hoverPoint = point
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.hoverWork = nil
      let now = NSEvent.mouseLocation
      guard self.reveal == .none, hypot(now.x - point.x, now.y - point.y) < 6, Self.isEmptyMenuBar(at: now) else { return }
      self.apply(.hidden)
    }
    hoverWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + max(AppSettings.shared.hiderHoverDelay, 0.3), execute: work)
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.addItem(ClosureMenuItem(reveal == .none ? "Show Hidden Icons" : "Hide Icons", key: "") { [weak self] in self?.toggle() })
    menu.addItem(ClosureMenuItem("Show All, Including Always Hidden") { [weak self] in self?.apply(.all) })
    menu.addItem(.separator())
    menu.addItem(ClosureMenuItem("Choose Icons to Hide…") { MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.showSettings() } })
    entry?.menu = menu
    entry?.button?.performClick(nil)
    entry?.menu = nil
  }
}
