import AppKit
import Combine
import SwiftUI

/// Battery and connection details, re-read whenever their panel opens.
final class WidgetSnapshot: ObservableObject {
  @Published var battery = BatteryDetails.read()
  @Published var network = NetworkInfo.read()
}

/// Four menu bar items — system, battery, calendar, network — each opening its own panel.
final class WidgetsController {
  enum Kind: String, CaseIterable {
    case system, battery, calendar, network
    var capability: String { "widgets.\(rawValue)" }
  }

  let stats = SystemStats()
  let calendar = CalendarStore()
  private let snapshot = WidgetSnapshot()
  private var items: [Kind: NSStatusItem] = [:]
  private var panels: [Kind: MenuBarPanel] = [:]
  private var cancellables: Set<AnyCancellable> = []

  func start() {
    stats.start()
    sync()
    stats.objectWillChange
      .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
      .sink { [weak self] in self?.refreshTitles() }
      .store(in: &cancellables)
    AppSettings.shared.$disabledCapabilities
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in DispatchQueue.main.async { self?.sync() } }
      .store(in: &cancellables)
    // The calendar item's date and the next-meeting countdown change by the minute.
    Timer.publish(every: 30, on: .main, in: .common).autoconnect()
      .sink { [weak self] _ in self?.refreshTitles() }
      .store(in: &cancellables)
  }

  func stop() {
    cancellables = []
    stats.stop()
    for kind in Array(items.keys) { remove(kind) }
  }

  /// Adds or removes items to match the capability switches.
  private func sync() {
    for kind in Kind.allCases {
      let wanted = AppSettings.shared.isOn(kind.capability)
      if wanted, items[kind] == nil { add(kind) } else if !wanted, items[kind] != nil { remove(kind) }
    }
    refreshTitles()
  }

  private func add(_ kind: Kind) {
    // Place each item once on the right, beside the system icons (points from the right edge),
    // so it starts out in the shown part of the menu bar rather than the hidden one.
    let positionKey = "NSStatusItem Preferred Position altools.widget.\(kind.rawValue)"
    if UserDefaults.standard.object(forKey: positionKey) == nil {
      let order = Kind.allCases.firstIndex(of: kind) ?? 0
      UserDefaults.standard.set(310 + order * 10, forKey: positionKey)
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.autosaveName = "altools.widget.\(kind.rawValue)"
    item.button?.target = self
    item.button?.action = #selector(clicked(_:))
    item.button?.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
    items[kind] = item
    let panel: MenuBarPanel
    switch kind {
    case .system:
      panel = MenuBarPanel(button: item.button) { [stats] _ in SystemWidgetPanel(stats: stats) }
      panel.onShow = { [weak self] in self?.stats.wantsProcesses = true }
      panel.onClose = { [weak self] in self?.stats.wantsProcesses = false }
    case .battery:
      panel = MenuBarPanel(button: item.button) { [snapshot] _ in BatterySnapshotPanel(snapshot: snapshot) }
      panel.onShow = { [weak self] in self?.snapshot.battery = BatteryDetails.read() }
    case .calendar:
      panel = MenuBarPanel(button: item.button) { [calendar] _ in CalendarWidgetPanel(store: calendar) }
      panel.onShow = { [weak self] in self?.calendar.goToToday() }
    case .network:
      panel = MenuBarPanel(button: item.button) { [stats, snapshot] _ in NetworkSnapshotPanel(stats: stats, snapshot: snapshot) }
      panel.onShow = { [weak self] in self?.snapshot.network = NetworkInfo.read() }
    }
    panels[kind] = panel
  }

  private func remove(_ kind: Kind) {
    panels[kind]?.close()
    panels[kind] = nil
    if let item = items.removeValue(forKey: kind) { NSStatusBar.system.removeStatusItem(item) }
  }

  /// Opens or closes one widget's panel, as clicking its item does.
  func toggle(_ kind: Kind) {
    for (other, panel) in panels where other != kind { panel.close() }
    panels[kind]?.toggle()
  }

  @objc private func clicked(_ sender: NSStatusBarButton) {
    guard let raw = sender.identifier?.rawValue, let kind = Kind(rawValue: raw) else { return }
    // One panel at a time, like menus.
    for (other, panel) in panels where other != kind { panel.close() }
    panels[kind]?.toggle()
  }

  // MARK: Titles

  private func refreshTitles() {
    if let button = items[.system]?.button {
      button.image = symbol("cpu")
      button.imagePosition = .imageLeading
      button.attributedTitle = text(" \(Int((stats.cpu.total * 100).rounded()))%")
    }
    if let button = items[.battery]?.button {
      let battery = BatteryDetails.read()
      button.image = symbol(battery.isCharging ? "battery.100percent.bolt" : Self.batterySymbol(battery.percent))
      button.imagePosition = .imageLeading
      button.attributedTitle = text(battery.hasBattery ? " \(battery.percent)%" : "")
    }
    if let button = items[.calendar]?.button {
      button.image = nil
      button.attributedTitle = text(calendarTitle)
    }
    if let button = items[.network]?.button {
      button.image = nil
      button.attributedTitle = networkTitle
    }
  }

  /// "Tue 24", or a countdown when a meeting starts within 15 minutes.
  private var calendarTitle: String {
    let now = Date()
    if let next = calendar.byDay[Calendar.current.startOfDay(for: now)]?
      .first(where: { !$0.allDay && $0.start > now && $0.start.timeIntervalSince(now) <= 900 }) {
      return "\(next.title.prefix(14)) · \(Int(ceil(next.start.timeIntervalSince(now) / 60)))m"
    }
    return now.formatted(.dateTime.weekday(.abbreviated).day())
  }

  /// Two stacked lines, upload over download, in a small monospaced font.
  private var networkTitle: NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .right
    paragraph.maximumLineHeight = 10
    let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    let up = SystemStats.bytes(stats.upload, perSecond: true)
    let down = SystemStats.bytes(stats.download, perSecond: true)
    return NSAttributedString(string: "\(up) ↑\n\(down) ↓", attributes: [.font: font, .paragraphStyle: paragraph, .baselineOffset: -4])
  }

  private func text(_ string: String) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
  }

  private func symbol(_ name: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
  }

  static func batterySymbol(_ percent: Int) -> String {
    switch percent {
    case ..<13: "battery.0percent"
    case ..<38: "battery.25percent"
    case ..<63: "battery.50percent"
    case ..<88: "battery.75percent"
    default: "battery.100percent"
    }
  }
}

private struct BatterySnapshotPanel: View {
  @ObservedObject var snapshot: WidgetSnapshot
  var body: some View { BatteryWidgetPanel(details: snapshot.battery) }
}

private struct NetworkSnapshotPanel: View {
  @ObservedObject var stats: SystemStats
  @ObservedObject var snapshot: WidgetSnapshot
  var body: some View { NetworkWidgetPanel(stats: stats, info: snapshot.network) }
}
