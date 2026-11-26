import AltoolsCore
import AppKit
import Combine
import SwiftUI

final class NotchModel: ObservableObject {
  enum Tab: String, CaseIterable, Identifiable {
    case home, media, todo, notes, shelf, usage, plugins
    var id: String { rawValue }
    var title: String {
      switch self {
      case .home: "Home"
      case .media: "Media"
      case .todo: "To-do"
      case .notes: "Notes"
      case .shelf: "Shelf"
      case .usage: "AI usage"
      case .plugins: "Plugins"
      }
    }
    var symbol: String {
      switch self {
      case .home: "house.fill"
      case .media: "music.note"
      case .todo: "checklist"
      case .notes: "note.text"
      case .shelf: "tray.full.fill"
      case .usage: "gauge.with.dots.needle.67percent"
      case .plugins: "puzzlepiece.extension.fill"
      }
    }
  }

  /// Something short-lived shown in the ears for a few seconds.
  struct Flash: Equatable {
    enum Kind: Equatable {
      case receipt(ActivityCenter.Receipt)
      case power(percent: Int, plugged: Bool)
      case input(symbol: String, label: String)
      case download(URL)
      case volume(VolumeMonitor.Level)
    }
    let id = UUID()
    var kind: Kind
  }

  /// What the collapsed island shows, highest priority first.
  enum Activity: Equatable {
    case flash(Flash)
    case meeting(RemindersStore.Meeting)
    case lowBattery(Int)
    case sensors(SystemSignals.Sensors)
    case ai
    case music
    /// A plugin's ears output; below music.
    case plugin(id: String, ears: PluginOutput.Ears)

    /// Width of each ear beside the notch.
    var earWidth: CGFloat {
      switch self {
      case .flash(let flash):
        switch flash.kind {
        case .receipt: 96
        case .power: 44
        case .input: 76
        case .download: 100
        case .volume: 80
        }
      case .meeting: 56
      case .lowBattery: 44
      case .sensors(let s): s.microphoneApp != nil ? 80 : 36
      case .ai: 36
      case .music: 36
      case .plugin(_, let ears): CGFloat(ears.sideWidth)
      }
    }
  }

  /// A card that drops down from the island without opening it fully: a meeting about
  /// to start, or another app's notification.
  enum Card: Equatable {
    case meeting(RemindersStore.Meeting, startingNow: Bool)
    case notification(NotificationWatcher.Banner)
    case agent(AgentInbox.Item)
    case plugin(id: String, alert: PluginOutput.Alert)
  }

  @Published var card: Card?
  /// Set by the controller; closes the card early.
  var dismissCard: () -> Void = {}
  /// Set by the controller; opens what a notification card points at.
  var openNotification: (NotificationWatcher.Banner) -> Void = { _ in }
  /// Set by the controller; a click on the collapsed island opens it.
  var requestExpand: () -> Void = {}
  /// Notifications received this run, newest first; cleared when Altools quits.
  @Published var inbox: [NotificationWatcher.Banner] = []
  @Published var expanded = false
  @Published var tab: Tab = .home
  /// The plugin whose page is open while `tab` is `.plugins`.
  @Published var pluginTab: String?
  /// "Keep open": the notch stays expanded when the pointer leaves.
  @Published var pinned = false
  @Published private(set) var flash: Flash?
  /// Size of the hardware notch, or a menu-bar-height stand-in on screens without one.
  @Published var notchSize = CGSize(width: 200, height: 32)
  @Published var hasNotch = false
  /// How far the island sits from its window's centre (the window is clamped to the screen).
  @Published var xOffset: CGFloat = 0
  /// Draw a notch on displays without one, so there is something to hover.
  @Published var drawsNotch = false
  /// ⌘ is held: the idle drawn notch steps aside so icons under it can be ⌘-dragged.
  @Published var commandHeld = false

  let nowPlaying = NowPlaying()
  let battery = BatteryMonitor()
  let shelf = ShelfStore()
  let reminders = RemindersStore()
  let notes = NotesStore()
  let usage = AIUsage()
  let signals = SystemSignals()
  let agents = AgentInbox.shared
  let plugins = PluginHost.shared
  let center = ActivityCenter.shared

  private var flashWork: DispatchWorkItem?

  var activity: Activity? {
    let on = AppSettings.shared.isOn
    if let flash { return .flash(flash) }
    if on("notch.meetings"), let meeting = reminders.imminentMeeting { return .meeting(meeting) }
    if on("notch.power"), let state = battery.state, state.percent <= 10, !state.onAC { return .lowBattery(state.percent) }
    if on("notch.sensors"), signals.sensors.active { return .sensors(signals.sensors) }
    if center.aiRunning > 0 { return .ai }
    if on("notch.nowplaying"), nowPlaying.track?.isPlaying == true { return .music }
    if AppSettings.shared.pluginsEnabled, let plugin = plugins.plugins.first(where: { $0.shows(.ears) && $0.output?.ears != nil }),
       let ears = plugin.output?.ears {
      return .plugin(id: plugin.id, ears: ears)
    }
    return nil
  }

  /// Tabs whose capability is on; Home always shows.
  var tabs: [Tab] {
    Tab.allCases.filter { tab in
      switch tab {
      case .home: true
      case .media: AppSettings.shared.isOn("notch.nowplaying")
      // Plugins get a tab each (pluginTabs); `.plugins` only marks that one of them is open.
      case .plugins: false
      default: AppSettings.shared.isOn("notch.\(tab.rawValue)")
      }
    }
  }

  /// Enabled plugins with a page, each shown as its own tab after the built-in ones.
  var pluginTabs: [PluginHost.Plugin] {
    guard AppSettings.shared.pluginsEnabled else { return [] }
    return plugins.plugins.filter { $0.shows(.tab) }
  }

  /// The open plugin page, or nil (and Home is shown) when that plugin is gone.
  var openPlugin: PluginHost.Plugin? {
    guard tab == .plugins, let id = pluginTab else { return nil }
    return pluginTabs.first { $0.id == id }
  }

  var collapsedSize: CGSize {
    let ears = (activity?.earWidth ?? 0) * 2
    // A floating pill has no hardware notch to leave room for in the middle.
    return CGSize(width: hasNotch || drawsNotch || ears == 0 ? notchSize.width + ears : ears + 12, height: notchSize.height)
  }

  static let expandedSize = CGSize(width: 540, height: 208)
  static let cardSize = CGSize(width: 380, height: 70)

  #if DEBUG
  func loadDemoFlash(_ kind: Flash.Kind) { flash = Flash(kind: kind) }
  #endif

  func show(_ kind: Flash.Kind, for seconds: Double = 2.5) {
    flashWork?.cancel()
    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { flash = Flash(kind: kind) }
    let work = DispatchWorkItem { [weak self] in
      withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self?.flash = nil }
    }
    flashWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }
}

/// Lets the notch take keyboard focus (to-do input, notes) without activating Altools.
private final class NotchPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  var onResignKey: (() -> Void)?
  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }
}

/// A borderless window over the notch. While collapsed it ignores the mouse so the
/// menu bar beneath stays clickable; resting the pointer on the notch expands it.
final class NotchController {
  let model = NotchModel()
  var actions = NotchActions()

  private(set) var window: NSPanel?
  private var monitors: [Any] = []
  private var collapseWork: DispatchWorkItem?
  private var expandWork: DispatchWorkItem?
  private var cancellables: Set<AnyCancellable> = []
  private let windowSize = CGSize(width: 640, height: 280)
  private let volume = VolumeMonitor()
  private let spacer = NotchSpacer()
  var spacerDescription: String { spacer.debugDescription }

  private let notifications = NotificationWatcher()
  private var cardWork: DispatchWorkItem?
  private var meetingTimer: Timer?
  /// Meetings already announced, as "id|stage", so each reminder shows once.
  private var announcedMeetings: Set<String> = []

  func start() {
    guard window == nil else { return }
    let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.acceptsMouseMovedEvents = true
    panel.isReleasedWhenClosed = false
    panel.onResignKey = { [weak self] in
      guard let self, self.model.expanded, !self.model.pinned else { return }
      if !self.pointerInsideExpanded { self.collapse() }
    }
    let hosting = FirstClickHostingView(rootView: AnyView(NotchView(model: model, actions: actions)))
    hosting.sizingOptions = []
    panel.contentView = hosting
    window = panel

    layout()
    panel.orderFrontRegardless()
    model.center.notchActive = true

    model.nowPlaying.start()
    let on = AppSettings.shared.isOn
    model.battery.onPowerChange = { [weak self] percent, plugged in
      if on("notch.power") { self?.model.show(.power(percent: percent, plugged: plugged)) }
    }
    model.battery.start()
    model.reminders.start()
    model.notes.start()
    model.signals.onCapsLock = { [weak self] caps in
      guard on("notch.input") else { return }
      self?.model.show(.input(symbol: caps ? "capslock.fill" : "capslock", label: caps ? "Caps Lock" : "Caps off"), for: 1.5)
    }
    model.signals.onInputSource = { [weak self] name in
      if on("notch.input") { self?.model.show(.input(symbol: "globe", label: name), for: 1.5) }
    }
    model.signals.onDownload = { [weak self] url in
      if on("notch.downloads") { self?.model.show(.download(url), for: 5) }
    }
    model.signals.start()
    if AppSettings.shared.notchAllDisplays { spacer.start() }
    volume.onChange = { [weak self] level in if on("notch.volume") { self?.model.show(.volume(level), for: 1.6) } }
    volume.start()
    notifications.onBanner = { [weak self] banner in self?.receive(banner) }
    model.plugins.onAlert = { [weak self] alert, plugin in self?.showCard(.plugin(id: plugin.id, alert: alert), for: 8) }
    model.agents.onNew = { [weak self] item in self?.showCard(.agent(item), for: 12) }
    if on("notch.agents") { model.agents.start() }
    AppSettings.shared.$disabledCapabilities.map { !$0.contains("notch.agents") }.removeDuplicates().dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] on in on ? self?.model.agents.start() : self?.model.agents.stop() }
      .store(in: &cancellables)
    // A card for an agent that was answered in the terminal goes away with it.
    model.agents.$items
      .receive(on: DispatchQueue.main)
      .sink { [weak self] items in
        guard let self, case .agent(let shown) = self.model.card, !items.contains(where: { $0.id == shown.id }) else { return }
        self.dismissCard()
      }
      .store(in: &cancellables)
    model.dismissCard = { [weak self] in self?.dismissCard() }
    model.openNotification = { [weak self] banner in self?.notifications.open(banner) }
    model.requestExpand = { [weak self] in self?.expand(tab: .home) }
    if AppSettings.shared.notchNotifications { notifications.start() }
    meetingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.checkMeetings() }

    let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
    if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in self?.trackMouse() }) {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
      self?.trackMouse()
      return event
    }) {
      monitors.append(local)
    }
    let flags: (NSEvent) -> Void = { [weak self] event in
      let held = event.modifierFlags.contains(.command)
      if self?.model.commandHeld != held { self?.model.commandHeld = held }
      if held { self?.watchCommandRelease() }
    }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(global) }
    if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(local) }
    if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
      guard let self, event.window === self.window, event.keyCode == 53 else { return event } // esc
      self.collapse()
      return nil
    }) {
      monitors.append(keys)
    }
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .sink { [weak self] _ in self?.layout() }
      .store(in: &cancellables)
    AppSettings.shared.$notchAllDisplays.merge(with: AppSettings.shared.$notchDrawOnExternal).dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in DispatchQueue.main.async { self?.layout() } }
      .store(in: &cancellables)
    AppSettings.shared.$notchNotifications.dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] on in on ? self?.notifications.start() : self?.notifications.stop() }
      .store(in: &cancellables)

    // The island's size depends on these stores; re-render the root when any changes.
    let sources: [AnyPublisher<Void, Never>] = [
      model.nowPlaying.objectWillChange.map { _ in }.eraseToAnyPublisher(),
      model.battery.objectWillChange.map { _ in }.eraseToAnyPublisher(),
      model.reminders.objectWillChange.map { _ in }.eraseToAnyPublisher(),
      model.signals.objectWillChange.map { _ in }.eraseToAnyPublisher(),
      model.center.objectWillChange.map { _ in }.eraseToAnyPublisher(),
      model.plugins.objectWillChange.map { _ in }.eraseToAnyPublisher(),
    ]
    Publishers.MergeMany(sources)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { self?.model.objectWillChange.send() }
      }
      .store(in: &cancellables)
    model.center.$receipt.compactMap { $0 }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] receipt in if on("notch.receipts") { self?.model.show(.receipt(receipt), for: 3) } }
      .store(in: &cancellables)
  }

  func stop() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    cancellables = []
    model.nowPlaying.stop()
    model.agents.stop()
    model.signals.stop()
    volume.stop()
    spacer.stop()
    notifications.stop()
    meetingTimer?.invalidate()
    model.notes.flush()
    model.center.notchActive = false
    window?.orderOut(nil)
    window = nil
  }

  /// A key remapper (e.g. Karabiner) can release ⌘ without a flags-changed event reaching
  /// Altools; re-check the real keyboard state until ⌘ is up, so the island never stays hidden.
  private func watchCommandRelease() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      guard let self, self.model.commandHeld else { return }
      if CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) {
        self.watchCommandRelease()
      } else {
        self.model.commandHeld = false
      }
    }
  }

  func toggleExpanded() {
    if !model.expanded { followPointer() }
    model.expanded ? collapse() : expand(tab: .home, focus: true)
  }

  func open(_ tab: NotchModel.Tab) {
    if !model.expanded { followPointer() }
    expand(tab: tab, focus: true)
  }

  /// ⌥⇧N: opens Notes on a fresh note with the cursor in it.
  func newNote() {
    model.notes.newNote()
    open(.notes)
  }

  /// The display the island is on now. With "All displays" it follows the pointer.
  private var screen: NSScreen = NSScreen.screens[0]

  private var builtInScreen: NSScreen {
    NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private var pointerScreen: NSScreen? {
    NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
  }

  /// The display the island should be on: the pointer's with "All displays", else the built-in one.
  private var targetScreen: NSScreen {
    AppSettings.shared.notchAllDisplays ? (pointerScreen ?? builtInScreen) : builtInScreen
  }

  /// Moves the island to the target display if it changed; only while collapsed, so an open notch never jumps.
  private func followPointer() {
    let target = targetScreen
    if target != screen { layout() }
  }

  private func layout() {
    guard let window else { return }
    screen = targetScreen
    let screen = screen
    let frame = screen.frame
    if screen.safeAreaInsets.top > 0,
       let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
      model.hasNotch = true
      model.drawsNotch = false
      model.notchSize = CGSize(width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    } else {
      model.drawsNotch = AppSettings.shared.notchAllDisplays && AppSettings.shared.notchDrawOnExternal
      model.hasNotch = false
      // The menu bar's height on this display; 0 when it has none (one menu bar across displays).
      model.notchSize = CGSize(width: 110, height: max(frame.maxY - screen.visibleFrame.maxY, 24))
    }
    islandCenterX = frame.midX
    let x = min(max(islandCenterX - windowSize.width / 2, frame.minX), frame.maxX - windowSize.width)
    window.setFrame(NSRect(x: x, y: frame.maxY - windowSize.height,
                           width: windowSize.width, height: windowSize.height), display: true)
    model.xOffset = offsetInWindow
  }

  /// The notch's on-screen rect for the given content size, in screen coordinates.
  /// Horizontal centre of the island: the middle of the top edge of its display.
  private var islandCenterX: CGFloat = 0

  /// The island's x relative to its window, which may be clamped at a screen edge.
  private var offsetInWindow: CGFloat {
    guard let window else { return 0 }
    return islandCenterX - window.frame.midX
  }

  private func rect(for size: CGSize, padding: CGFloat) -> NSRect {
    let frame = screen.frame
    return NSRect(x: islandCenterX - size.width / 2 - padding, y: frame.maxY - size.height - padding,
                  width: size.width + padding * 2, height: size.height + padding * 2)
  }

  // MARK: Cards

  private func receive(_ banner: NotificationWatcher.Banner) {
    if let id = banner.bundleID, AppSettings.shared.notchMutedApps.contains(id) { return }
    model.inbox.insert(banner, at: 0)
    if model.inbox.count > 30 { model.inbox.removeLast() }
    showCard(.notification(banner), for: 6)
  }

  /// Reminds once a minute before a meeting and once when it starts.
  private func checkMeetings() {
    guard AppSettings.shared.isOn("notch.meetings") else { return }
    let now = Date()
    for meeting in model.reminders.meetings {
      let untilStart = meeting.start.timeIntervalSince(now)
      let stage: String
      if untilStart <= 0, untilStart > -120 { stage = "start" } else if untilStart > 0, untilStart <= 60 { stage = "soon" } else { continue }
      let key = "\(meeting.id)|\(stage)"
      guard announcedMeetings.insert(key).inserted else { continue }
      if stage == "start" { announcedMeetings.insert("\(meeting.id)|soon") }
      showCard(.meeting(meeting, startingNow: stage == "start"), for: 20)
    }
  }

  func dismissCard() {
    cardWork?.cancel()
    cardWork = nil
    if !model.expanded { window?.ignoresMouseEvents = true }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.card = nil }
  }

  private func showCard(_ card: NotchModel.Card, for seconds: Double) {
    guard !model.expanded else { return }
    // An agent card stays its full time; a newer agent may replace it, nothing else.
    if case .agent = model.card, !isAgent(card) { return }
    followPointer()
    window?.ignoresMouseEvents = false
    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { model.card = card }
    scheduleCardDismiss(after: seconds)
  }

  private func isAgent(_ card: NotchModel.Card) -> Bool {
    if case .agent = card { return true }
    return false
  }

  /// Hovering a card keeps it; it leaves a moment after the pointer does.
  private func scheduleCardDismiss(after seconds: Double) {
    cardWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      if NSMouseInRect(NSEvent.mouseLocation, self.rect(for: NotchModel.cardSize, padding: 8), false) {
        self.scheduleCardDismiss(after: 1.5)
      } else {
        self.dismissCard()
      }
    }
    cardWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  /// A to-do or note is being edited: the field editor (an NSTextView) has keyboard focus.
  private var isTyping: Bool {
    guard let window, window.isKeyWindow else { return false }
    return window.firstResponder is NSTextView
  }

  private var pointerInsideExpanded: Bool {
    var area = rect(for: NotchModel.expandedSize, padding: 12)
    if !model.hasNotch { area.size.height = screen.frame.maxY - area.minY }
    return NSMouseInRect(NSEvent.mouseLocation, area, false)
  }

  private func trackMouse() {
    let mouse = NSEvent.mouseLocation
    if model.expanded {
      // Stay open while pinned, or while the user is typing in it.
      if pointerInsideExpanded || model.pinned || isTyping {
        collapseWork?.cancel()
        collapseWork = nil
      } else if collapseWork == nil {
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
      }
      return
    }
    guard model.card == nil else { return }
    followPointer()
    // A visible island takes clicks (it opens, or joins a meeting); elsewhere they reach the menu bar.
    let overIsland = NSMouseInRect(mouse, rect(for: model.collapsedSize, padding: 2), false)
    let takesClicks = islandVisible && overIsland
    if window?.ignoresMouseEvents == takesClicks { window?.ignoresMouseEvents = !takesClicks }
    // An invisible island sits over ordinary menu bar with icons in it; there it opens only with
    // the pointer pushed against the top edge, so clicking those icons doesn't trigger it.
    let overNotch = islandVisible
      ? NSMouseInRect(mouse, rect(for: model.collapsedSize, padding: 4), false)
      : abs(mouse.x - islandCenterX) <= max(model.collapsedSize.width, 150) / 2 + 4 && mouse.y >= screen.frame.maxY - 2
    guard overNotch else {
      expandWork?.cancel()
      expandWork = nil
      return
    }
    // Dragging a file onto the notch opens the shelf straight away.
    if NSEvent.pressedMouseButtons & 1 != 0 {
      expand(tab: .shelf)
      return
    }
    guard expandWork == nil else { return }
    let work = DispatchWorkItem { [weak self] in
      self?.expandWork = nil
      self?.expand(tab: .home)
    }
    expandWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.shared.notchHoverDelay, execute: work)
  }

  /// The collapsed island is on screen: a hardware notch, a drawn one, or live activity in the
  /// ears. A drawn island steps aside while ⌘ is held (see NotchView.visible).
  private var islandVisible: Bool {
    model.hasNotch || ((model.drawsNotch || model.activity != nil) && !model.commandHeld)
  }

  /// Opens the island on `tab` (Home unless a file is being dropped or a shortcut asks for another).
  private func expand(tab: NotchModel.Tab, focus: Bool = false) {
    model.tab = tab
    if model.card != nil { cardWork?.cancel(); cardWork = nil; model.card = nil }
    collapseWork?.cancel()
    collapseWork = nil
    expandWork?.cancel()
    expandWork = nil
    window?.ignoresMouseEvents = false
    if focus { window?.makeKey() }
    if model.tab == .usage { model.usage.refresh() }
    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { model.expanded = true }
  }

  private func collapse() {
    collapseWork = nil
    model.notes.flush()
    window?.ignoresMouseEvents = true
    // Hand keyboard focus back to the app the user was in.
    if let window, window.isKeyWindow {
      window.orderOut(nil)
      window.orderFrontRegardless()
    }
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.expanded = false }
  }
}

/// Quick actions the notch can trigger in other modules.
struct NotchActions {
  var openLauncher: () -> Void = {}
  var openClipboard: () -> Void = {}
  var captureArea: () -> Void = {}
  var recognizeText: () -> Void = {}
  var pickColor: () -> Void = {}
  var askAI: () -> Void = {}
  var translate: (String) -> Void = { _ in }
  var openSettings: () -> Void = {}
}
