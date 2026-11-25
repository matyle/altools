import AppKit

/// Hides menu bar icons the user doesn't need to see, like Hidden Bar / Ice.
///
/// Layout, right to left: [entry icon] [shown icons] | divider | [hidden icons] | always-divider | [always hidden icons].
/// A divider "hides" the icons to its left by growing until they no longer fit beside the
/// app's menus, so macOS stops drawing them. The width must still fit itself: macOS drops
/// a status item that is wider than the free space and lays the others out as if it were
/// not there. So the width is measured to the free space and re-measured when the
/// frontmost app (and with it the menus' width) changes. While wide, the divider's
/// visible part is the empty stretch of menu bar, so clicking or hovering there reveals.
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

  private enum Reveal { case none, hidden, all }

  private var entry: NSStatusItem?
  private var divider: NSStatusItem?
  private var alwaysDivider: NSStatusItem?
  private var reveal = Reveal.none
  private var autoHide: DispatchWorkItem?
  private var hoverWork: DispatchWorkItem?
  private var monitors: [Any] = []

  private static let dividerWidth: CGFloat = 12
  private var activationObserver: Any?
  private var remeasureTimer: Timer?

  var isRevealed: Bool { reveal != .none }

  /// Screen frames of the entry and dividers, for the live self-test report.
  var debugFrames: String {
    [("entry", entry), ("divider", divider), ("always", alwaysDivider)].map { name, item in
      "\(name)=\(item?.button?.window.map { NSStringFromRect($0.frame) } ?? "none")"
    }.joined(separator: " ")
  }

  func start() {
    guard entry == nil else { return }
    // New status items appear at the left end; place the entry once at the right end, next to
    // the system icons, so every existing icon starts out "shown" (left of the entry, right of the dividers).
    let defaults = UserDefaults.standard
    // Positions are points from the screen's right edge; 300 lands just left of Wi-Fi, battery and the clock.
    if defaults.integer(forKey: "hiderEntryPlacedVersion") < 2 {
      defaults.set(2, forKey: "hiderEntryPlacedVersion")
      defaults.set(300, forKey: "NSStatusItem Preferred Position altools.hider.entry")
    }
    let entry = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    entry.autosaveName = "altools.hider.entry"
    entry.button?.target = self
    entry.button?.action = #selector(entryClicked)
    entry.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    self.entry = entry

    let divider = NSStatusBar.system.statusItem(withLength: Self.dividerWidth)
    divider.autosaveName = "altools.hider.divider"
    divider.button?.target = self
    divider.button?.action = #selector(emptySpaceClicked)
    divider.button?.sendAction(on: [.leftMouseUp])
    divider.button?.toolTip = "Icons left of this line hide. ⌘-drag icons across it."
    self.divider = divider

    let alwaysDivider = NSStatusBar.system.statusItem(withLength: Self.dividerWidth)
    alwaysDivider.autosaveName = "altools.hider.always"
    alwaysDivider.button?.toolTip = "Icons left of this line stay hidden until you double-click the entry."
    self.alwaysDivider = alwaysDivider

    // Start with both dividers narrow so macOS lays the items out at their saved positions,
    // then collapse; created wide, the entry gets squeezed next to the dividers instead.
    apply(.all)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self, self.entry != nil else { return }
      if UserDefaults.standard.bool(forKey: "hiderTipShown") { self.apply(.none) }
    }
    installHover()
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.remeasure() }
    }
    remeasureTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.remeasure() }
    if !UserDefaults.standard.bool(forKey: "hiderTipShown") {
      UserDefaults.standard.set(true, forKey: "hiderTipShown")
      apply(.all)
      Toast.show("Hold ⌘ and drag icons left of the │ line to hide them", symbol: "ellipsis", duration: 6)
    }
  }

  func stop() {
    autoHide?.cancel()
    remeasureTimer?.invalidate()
    if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    [entry, divider, alwaysDivider].compactMap { $0 }.forEach(NSStatusBar.system.removeStatusItem)
    entry = nil
    divider = nil
    alwaysDivider = nil
  }

  /// ⌥B: show the hidden band, or tuck it away.
  func toggle() {
    apply(reveal == .none ? .hidden : .none)
  }

  /// Re-reads the entry icon after a settings change.
  func refreshIcon() {
    apply(reveal)
  }

  @objc private func entryClicked() {
    guard let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseUp {
      showMenu()
    } else if event.clickCount >= 2, AppSettings.shared.hiderDoubleClickAll {
      apply(.all)
    } else {
      toggle()
    }
  }

  /// The collapsed divider spans the empty menu bar, so this is a click on empty space.
  @objc private func emptySpaceClicked() {
    guard reveal == .none, AppSettings.shared.hiderClickEmpty else { return }
    apply(.hidden)
  }

  private func apply(_ value: Reveal) {
    reveal = value
    // Narrow first so both dividers are laid out and measurable, then widen the closed ones.
    divider?.length = Self.dividerWidth
    alwaysDivider?.length = Self.dividerWidth
    DispatchQueue.main.async { [weak self] in self?.widenClosedDividers() }
    // Dividers draw a hairline only while their side is open, so a revealed band reads as "hidden past here".
    divider?.button?.image = value == .none ? nil : Self.line
    alwaysDivider?.button?.image = value == .all ? Self.line : nil
    let icon = EntryIcon(rawValue: AppSettings.shared.hiderIcon) ?? .dot
    let image = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: value == .none ? "Show hidden icons" : "Hide icons")
    let config = NSImage.SymbolConfiguration(pointSize: icon == .dot ? 6 : 13, weight: .semibold)
    entry?.button?.image = image?.withSymbolConfiguration(config)
    entry?.button?.appearsDisabled = value != .none
    scheduleAutoHide()
  }

  /// Grows each closed divider to fill the free menu bar to its left, pushing the icons
  /// beyond it out of the space macOS will draw.
  private func widenClosedDividers() {
    if reveal == .none, let divider { divider.length = fillLength(for: divider) }
    if reveal != .all, let alwaysDivider { alwaysDivider.length = fillLength(for: alwaysDivider) }
  }

  /// From the end of the app menus (or the hardware notch) to the divider's right edge, less a margin.
  private func fillLength(for item: NSStatusItem) -> CGFloat {
    guard let window = item.button?.window, let screen = window.screen ?? NSScreen.main else { return 200 }
    var leftLimit = Self.appMenusRightEdge() ?? (screen.frame.minX + 360)
    if let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
      leftLimit = max(leftLimit, screen.frame.maxX - right.width)
    }
    return max(Self.dividerWidth, window.frame.maxX - leftLimit - 6)
  }

  /// Re-fits the closed dividers when the menus' width may have changed. A divider that
  /// became too wide was dropped by macOS (its window is no longer on screen), so it is
  /// narrowed and re-measured.
  private func remeasure() {
    guard reveal != .all else { return }
    let closed = reveal == .none ? [divider, alwaysDivider] : [alwaysDivider]
    let stale = closed.compactMap { $0 }.contains { item in
      guard let window = item.button?.window, let screen = window.screen else { return true }
      return window.frame.minX < screen.frame.minX || abs(item.length - fillLength(for: item)) > 2
    }
    if stale { apply(reveal) }
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

  private static let line: NSImage = {
    let image = NSImage(size: NSSize(width: 2, height: 14), flipped: false) { rect in
      NSColor.labelColor.withAlphaComponent(0.45).setFill()
      NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
      return true
    }
    image.isTemplate = true
    return image
  }()

  /// Tucks the band away after the delay, but not while the pointer is in the menu bar.
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

  private var pointerInMenuBar: Bool {
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return false }
    return mouse.y >= screen.frame.maxY - max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
  }

  // MARK: Hover

  private func installHover() {
    let handler: (NSEvent) -> Void = { [weak self] _ in self?.trackHover() }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { monitors.append(global) }
    let flags: (NSEvent) -> Void = { [weak self] event in self?.commandChanged(event.modifierFlags.contains(.command)) }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(global) }
    if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(local) }
  }

  /// While ⌘ is held everything opens up, so ⌘-dragging icons has room to land (a closed
  /// divider fills all free space). The previous state returns shortly after ⌘ is released.
  private var revealBeforeCommand: Reveal?
  private var commandRestore: DispatchWorkItem?

  private func commandChanged(_ down: Bool) {
    if down {
      commandRestore?.cancel()
      commandRestore = nil
      guard revealBeforeCommand == nil else { return }
      revealBeforeCommand = reveal
      apply(.all)
    } else if let previous = revealBeforeCommand {
      commandRestore?.cancel()
      let work = DispatchWorkItem { [weak self] in
        guard let self, !NSEvent.modifierFlags.contains(.command) else { return }
        // Still dragging an icon: wait until the button is released.
        if NSEvent.pressedMouseButtons & 1 != 0 { return self.commandChanged(false) }
        self.revealBeforeCommand = nil
        self.apply(previous)
      }
      commandRestore = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
  }

  /// Resting on the empty menu bar (the collapsed divider's visible area) reveals.
  private func trackHover() {
    guard reveal == .none, AppSettings.shared.hiderHover,
          let frame = divider?.button?.window?.frame else {
      hoverWork?.cancel()
      hoverWork = nil
      return
    }
    let mouse = NSEvent.mouseLocation
    let visible = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.frame ?? .zero
    guard NSMouseInRect(mouse, frame.intersection(visible), false) else {
      hoverWork?.cancel()
      hoverWork = nil
      return
    }
    guard hoverWork == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      self?.hoverWork = nil
      if let self, self.reveal == .none, NSMouseInRect(NSEvent.mouseLocation, frame, false) { self.apply(.hidden) }
    }
    hoverWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.shared.hiderHoverDelay, execute: work)
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.addItem(ClosureMenuItem(reveal == .none ? "Show Hidden Icons" : "Hide Icons", key: "") { [weak self] in self?.toggle() })
    menu.addItem(ClosureMenuItem("Show All, Including Always Hidden") { [weak self] in self?.apply(.all) })
    menu.addItem(.separator())
    let hint = NSMenuItem(title: "⌘-drag icons across the │ lines to hide them", action: nil, keyEquivalent: "")
    hint.isEnabled = false
    menu.addItem(hint)
    entry?.menu = menu
    entry?.button?.performClick(nil)
    entry?.menu = nil
  }
}
