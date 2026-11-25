import AppKit

/// Keeps menu bar icons out from under the island on displays without a hardware notch.
///
/// macOS lines status icons up from the right edge with no gap, and offers no way for an app
/// to reorder other apps' icons (synthesized ⌘-drags are not honoured). So the user places
/// this invisible item once, by ⌘-dragging it to just left of the first icon past the
/// island; from then on it widens itself back to the island's left edge, so icons to its
/// left shift out from under the island (macOS hides those that no longer fit). On a display
/// with a real notch macOS already leaves that gap, so the spacer stays a sliver.
final class NotchSpacer {
  private var item: NSStatusItem?
  private var timer: Timer?
  private var monitors: [Any] = []
  private var commandHeld = false
  /// Width kept clear around the screen's centre: the drawn notch plus room for its ears.
  var reservedWidth: CGFloat = 250

  private static let minimum: CGFloat = 14

  var debugDescription: String {
    "spacer=\(item?.button?.window.map { NSStringFromRect($0.frame) } ?? "none") length=\(item?.length ?? 0) command=\(commandHeld)"
  }

  func start() {
    guard item == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: Self.minimum)
    item.autosaveName = "altools.notch.spacer"
    item.button?.toolTip = "Notch spacer: ⌘-drag this to just left of the first icon past the island"
    item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notch spacer")?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    item.button?.appearsDisabled = true
    self.item = item
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.fit() }
    let flags: (NSEvent) -> Void = { [weak self] event in
      // Only highlight it; changing its width mid-drag would move icons out from under the pointer.
      self?.commandHeld = event.modifierFlags.contains(.command)
      self?.item?.button?.appearsDisabled = self?.commandHeld != true
      if self?.commandHeld == true { self?.watchCommandRelease() }
    }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(global) }
    if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(local) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.fit() }
  }

  /// Clears a ⌘ state left stuck by a key remapper that released ⌘ without a flags event.
  private func watchCommandRelease() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      guard let self, self.commandHeld else { return }
      if CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) {
        self.watchCommandRelease()
      } else {
        self.commandHeld = false
        self.item?.button?.appearsDisabled = true
      }
    }
  }

  func stop() {
    timer?.invalidate()
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    if let item { NSStatusBar.system.removeStatusItem(item) }
    item = nil
  }

  /// Widens the spacer from its right edge back to the island's left edge, when it sits past the island.
  private func fit() {
    // While ⌘ is held the user may be dragging icons; a wide spacer would leave no room.
    guard let item, !commandHeld, NSEvent.pressedMouseButtons == 0, let window = item.button?.window, let screen = window.screen else { return }
    var length = Self.minimum
    if screen.safeAreaInsets.top == 0 {
      let islandLeft = screen.frame.midX - reservedWidth / 2
      let islandRight = screen.frame.midX + reservedWidth / 2
      let right = window.frame.maxX
      // Placed at or past the island's right edge (but not far past, which would push many icons away).
      if right >= islandRight - 4, right <= islandRight + 160 {
        let menusRight = MenuBarHider.appMenusRightEdge() ?? (screen.frame.minX + 300)
        // Never wider than the free space, or macOS drops the item altogether.
        length = min(max(right - islandLeft, Self.minimum), max(Self.minimum, right - menusRight - 8))
      }
    }
    if abs(item.length - length) > 1 { item.length = length }
  }
}
