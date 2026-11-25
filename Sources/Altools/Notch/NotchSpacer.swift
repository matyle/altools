import AppKit

/// Keeps menu bar icons out from under the island on displays without a hardware notch.
///
/// macOS lines status icons up from the right edge with no gap, so on such displays the
/// drawn island would sit on top of them. This invisible status item, once ⌘-dragged to
/// sit under the island, widens itself so its span covers the island's area: icons to its
/// left move further left (and those that no longer fit are hidden by macOS). On a display
/// with a real notch macOS already leaves that gap, so the spacer stays a sliver.
final class NotchSpacer {
  private var item: NSStatusItem?
  private var timer: Timer?
  private var monitors: [Any] = []
  private var commandHeld = false
  /// Width kept clear around the island's centre: the notch shape plus room for its ears.
  var reservedWidth: CGFloat = 320

  private static let minimum: CGFloat = 14

  func start() {
    guard item == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: Self.minimum)
    item.autosaveName = "altools.notch.spacer"
    item.button?.toolTip = "Notch spacer: ⌘-drag this under the island and icons will keep clear of it."
    self.item = item
    updateImage()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.fit() }
    let flags: (NSEvent) -> Void = { [weak self] event in
      self?.commandHeld = event.modifierFlags.contains(.command)
      self?.updateImage()
      if self?.commandHeld == true { self?.item?.length = Self.minimum }
    }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(global) }
    if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(local) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.fit() }
  }

  func stop() {
    timer?.invalidate()
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    if let item { NSStatusBar.system.removeStatusItem(item) }
    item = nil
  }

  /// A faint notch glyph marks the spacer while it is narrow or while ⌘ is held (so it can
  /// be found and dragged); when it is wide the island covers it anyway.
  private func updateImage() {
    let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notch spacer")?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    item?.button?.image = image
    item?.button?.appearsDisabled = !commandHeld
  }

  /// Sizes the spacer so its span reaches from under the island's left edge to its own right edge.
  private func fit() {
    // While ⌘ is held the user may be dragging icons; a wide spacer would leave no room.
    guard let item, !commandHeld, let window = item.button?.window, let screen = window.screen else { return }
    var length = Self.minimum
    if screen.safeAreaInsets.top == 0 {
      let islandLeft = screen.frame.midX - reservedWidth / 2
      let islandRight = screen.frame.midX + reservedWidth / 2
      let right = window.frame.maxX
      // Only useful when the spacer ends at or right of the island; then fill back to its left edge.
      if right >= islandLeft + Self.minimum {
        let menusRight = MenuBarHider.appMenusRightEdge() ?? (screen.frame.minX + 300)
        let wanted = right - islandLeft
        // Never wider than the free space, or macOS drops the item altogether.
        length = min(max(wanted, Self.minimum), max(Self.minimum, right - menusRight - 8))
        if right > islandRight + 120 { length = Self.minimum }
      }
    }
    if abs(item.length - length) > 1 { item.length = length }
  }
}
