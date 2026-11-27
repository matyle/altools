import AltoolsCore
import Foundation
import Testing
@testable import BatteryMonitor

/// A power-source entry shaped like those macOS returns (keys as `pmset -g accps` reads them).
private func source(_ name: String, category: String? = nil, percent: Int, max: Int = 100, part: String? = nil, group: String? = nil,
                    charging: Bool? = nil, type: String = "Accessory Source", present: Bool? = nil) -> [String: Any] {
  var entry: [String: Any] = ["Type": type, "Name": name, "Current Capacity": percent, "Max Capacity": max]
  if let category { entry["Accessory Category"] = category }
  if let part { entry["Part Identifier"] = part }
  if let group { entry["Group Identifier"] = group }
  if let charging { entry["Is Charging"] = charging }
  if let present { entry["Is Present"] = present }
  return entry
}

private func keyboard(_ percent: Int, charging: Bool = false) -> [BatteryDevice] {
  BatteryDevice.devices(from: [BatteryReading(name: "Desk Keyboard", category: "Keyboard", percent: percent, charging: charging)])
}

@Suite struct BatteryReadingTests {
  @Test func keepsOnlyPresentNamedAccessories() {
    let readings = [
      source("InternalBattery-0", percent: 80, type: "InternalBattery"),
      source("Desk Keyboard", category: "Keyboard", percent: 10),
      source("Old Mouse", category: "Mouse", percent: 50, present: false),
      source("  ", category: "Mouse", percent: 50),
    ].compactMap(BatteryReading.init(powerSource:))
    #expect(readings == [BatteryReading(name: "Desk Keyboard", category: "Keyboard", percent: 10)])
  }

  @Test func scalesToAPercentageAndDropsTheFindMySuffix() throws {
    let reading = try #require(BatteryReading(powerSource: source("Studio Headphones - Find My", category: "Headset", percent: 1500, max: 2000)))
    #expect(reading.name == "Studio Headphones")
    #expect(reading.percent == 75)
  }

  @Test func chargingOrPluggedInCountsAsCharging() {
    var plugged = source("Desk Keyboard", percent: 40)
    plugged["Power Source State"] = "AC Power"
    #expect(BatteryReading(powerSource: plugged)?.charging == true)
    #expect(BatteryReading(powerSource: source("Desk Keyboard", percent: 40, charging: true))?.charging == true)
    #expect(BatteryReading(powerSource: source("Desk Keyboard", percent: 40))?.charging == false)
  }
}

@Suite struct BatteryDeviceTests {
  @Test func groupsAirPodsAndRatesThemByTheWeakerBud() {
    let devices = BatteryDevice.devices(from: [
      source("AirPods Pro", category: "Headphones", percent: 5, part: "Case", group: "G1"),
      source("AirPods Pro", category: "Headphones", percent: 80, part: "Left", group: "G1"),
      source("AirPods Pro", category: "Headphones", percent: 35, part: "Right", group: "G1"),
      source("Desk Keyboard", category: "Keyboard", percent: 60),
    ].compactMap(BatteryReading.init(powerSource:)))
    #expect(devices.map(\.name) == ["AirPods Pro", "Desk Keyboard"])
    #expect(devices[0].level == 35)
    #expect(devices[0].parts.map(\.part) == [.left, .right, .case])
    #expect(devices[0].symbol == "airpodspro")
  }

  @Test func aCaseOnItsOwnUsesItsOwnLevel() {
    let devices = BatteryDevice.devices(from: [BatteryReading(name: "Case", category: "Audio Battery Case", part: .case, group: "G2", percent: 12)])
    #expect(devices.map(\.level) == [12])
  }

  @Test func kindComesFromTheCategoryThenTheName() {
    #expect(BatteryDevice.kind(category: "Mouse", name: "Gear Headset") == .mouse)
    #expect(BatteryDevice.kind(category: nil, name: "MX Keys") == .other)
    #expect(BatteryDevice.kind(category: nil, name: "小米蓝牙耳机") == .headphones)
    #expect(BatteryDevice.kind(category: nil, name: "罗技鼠标") == .mouse)
    #expect(BatteryDevice.devices(from: [BatteryReading(name: "Magic Mouse", category: "Mouse", percent: 50)]).first?.symbol == "magicmouse")
  }
}

@Suite struct LowBatteryTrackerTests {
  let start = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func alertsOnceEachTimeADeviceRunsLow() {
    var tracker = LowBatteryTracker()
    #expect(tracker.update(keyboard(40), threshold: 20, now: start).isEmpty)
    let first = tracker.update(keyboard(20), threshold: 20, now: start + 60)
    #expect(first.map(\.severity) == [.low])
    // Still low on later runs: the same id, which the host doesn't show again.
    #expect(tracker.update(keyboard(15), threshold: 20, now: start + 120).map(\.id) == first.map(\.id))
  }

  @Test func addsACriticalAlertAtFivePercent() {
    var tracker = LowBatteryTracker()
    _ = tracker.update(keyboard(18), threshold: 20, now: start)
    #expect(tracker.update(keyboard(6), threshold: 20, now: start + 60).map(\.severity) == [.low])
    #expect(tracker.update(keyboard(5), threshold: 20, now: start + 120).map(\.severity) == [.low, .critical])
  }

  @Test func aFivePercentThresholdSendsOneAlertNotTwo() {
    var tracker = LowBatteryTracker()
    #expect(tracker.update(keyboard(5), threshold: 5, now: start).map(\.severity) == [.low])
    #expect(tracker.update(keyboard(3), threshold: 5, now: start + 60).map(\.severity) == [.low])
  }

  @Test func aLevelWobblingAroundTheThresholdAlertsOnce() {
    var tracker = LowBatteryTracker()
    let first = tracker.update(keyboard(20), threshold: 20, now: start)
    #expect(tracker.update(keyboard(25), threshold: 20, now: start + 60).isEmpty)
    #expect(tracker.update(keyboard(19), threshold: 20, now: start + 120).map(\.id) == first.map(\.id))
  }

  @Test func chargingOrRecoveringLetsItAlertAgain() throws {
    var tracker = LowBatteryTracker()
    let first = try #require(tracker.update(keyboard(15), threshold: 20, now: start).first)
    #expect(tracker.update(keyboard(16, charging: true), threshold: 20, now: start + 60).isEmpty)
    let second = try #require(tracker.update(keyboard(18), threshold: 20, now: start + 120).first)
    #expect(second.id != first.id)
    #expect(tracker.update(keyboard(30), threshold: 20, now: start + 180).isEmpty)
    let third = try #require(tracker.update(keyboard(19), threshold: 20, now: start + 240).first)
    #expect(third.id != second.id)
  }

  @Test func aDeviceBackWithinAWeekKeepsItsAlertAndOneGoneLongerStartsOver() {
    var tracker = LowBatteryTracker()
    let first = tracker.update(keyboard(15), threshold: 20, now: start).map(\.id)
    _ = tracker.update([], threshold: 20, now: start + 86_400)
    #expect(tracker.update(keyboard(15), threshold: 20, now: start + 2 * 86_400).map(\.id) == first)
    _ = tracker.update([], threshold: 20, now: start + 10 * 86_400)
    let later = tracker.update(keyboard(15), threshold: 20, now: start + 10 * 86_400 + 60).map(\.id)
    #expect(later.count == 1 && later != first)
  }

  @Test func survivesSavingBetweenRuns() throws {
    var tracker = LowBatteryTracker()
    let first = tracker.update(keyboard(15), threshold: 20, now: start).map(\.id)
    var loaded = try JSONDecoder().decode(LowBatteryTracker.self, from: JSONEncoder().encode(tracker))
    #expect(loaded.update(keyboard(14), threshold: 20, now: start + 60).map(\.id) == first)
  }
}

@Suite struct BatteryOutputTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)

  /// One run's output, parsed the way Altools parses plugin output.
  private func run(_ readings: [BatteryReading], settings: BatterySettings = BatterySettings(), chinese: Bool = false) throws -> PluginOutput {
    let devices = BatteryDevice.devices(from: readings)
    var tracker = LowBatteryTracker()
    let alerts = tracker.update(devices, threshold: settings.threshold, now: now)
    return try PluginOutput.decode(BatteryOutput.json(devices: devices, alerts: alerts, settings: settings, chinese: chinese, now: now))
  }

  private let lowKeyboard = BatteryReading(name: "Desk Keyboard", category: "Keyboard", percent: 10)
  private let headphones = BatteryReading(name: "Studio Headphones", category: "Headset", percent: 79)

  @Test func aLowDeviceAlertsAndShowsBesideTheNotch() throws {
    let output = try run([headphones, lowKeyboard])
    #expect(output.ears?.symbol == "keyboard")
    #expect(output.ears?.text == "10%")
    #expect(output.alerts.map(\.title) == ["Desk Keyboard is low on battery"])
    #expect(output.alerts.first?.body == "10% left — charge it soon.")
    #expect(output.menubar == nil)
  }

  @Test func theEarsFollowTheSetting() throws {
    let healthy = BatteryReading(name: "Desk Keyboard", category: "Keyboard", percent: 60)
    #expect(try run([healthy]).ears == nil)
    #expect(try run([healthy], settings: BatterySettings(ears: .always)).ears?.text == "60%")
    #expect(try run([lowKeyboard], settings: BatterySettings(ears: .off)).ears == nil)
  }

  @Test func theMenuBarShowsTheWeakestDeviceWhenOn() throws {
    let output = try run([headphones, lowKeyboard], settings: BatterySettings(menuBar: true))
    #expect(output.menubar?.symbol == "keyboard")
    #expect(output.menubar?.text == "10%")
  }

  @Test func theTabHasACardPerDevice() throws {
    let output = try run([headphones, lowKeyboard])
    guard case .stack(_, _, _, let children, _)? = output.tab?.view, case .grid(_, _, let cards, _)? = children.first else {
      Issue.record("tab view isn't a stack holding a grid: \(String(describing: output.tab?.view))")
      return
    }
    #expect(cards.count == 2)
    #expect(output.home?.view != nil)
  }

  @Test func withNoDevicesItStillDrawsAndStaysQuiet() throws {
    let output = try run([])
    #expect(output.ears == nil && output.alerts.isEmpty)
    #expect(output.tab?.view != nil && output.home?.view != nil)
  }

  @Test func airPodsAlertsNameEachBud() throws {
    let output = try run([
      BatteryReading(name: "AirPods", category: "Headphones", part: .left, group: "G1", percent: 12),
      BatteryReading(name: "AirPods", category: "Headphones", part: .right, group: "G1", percent: 30),
      BatteryReading(name: "AirPods", category: "Headphones", part: .case, group: "G1", percent: 90),
    ])
    #expect(output.alerts.first?.body == "Left 12% · Right 30% — charge them soon.")
  }

  @Test func speaksChinese() throws {
    let output = try run([BatteryReading(name: "蓝牙键盘", category: "Keyboard", percent: 3)], chinese: true)
    #expect(output.alerts.map(\.title) == ["蓝牙键盘 电量低", "蓝牙键盘 快没电了"])
    #expect(output.alerts.map(\.body) == ["剩余 3%，记得充电。", "只剩 3%。"])
    #expect(output.tab?.title == "电量")
  }

  @Test func readsItsSettings() {
    let set = BatterySettings(environment: ["ALTOOLS_SETTING_THRESHOLD": "30%", "ALTOOLS_SETTING_EARS": "Off", "ALTOOLS_SETTING_MENUBAR": "Lowest device"])
    #expect(set == BatterySettings(threshold: 30, ears: .off, menuBar: true))
    #expect(BatterySettings(environment: [:]) == BatterySettings(threshold: 20, ears: .whenLow, menuBar: false))
  }

  @Test func understandsEveryChoiceInPluginJSON() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("../../Resources/BuiltinPlugins/battery/plugin.json").standardized
    let manifest = try PluginManifest.decode(Data(contentsOf: file))
    func options(_ key: String) throws -> [String] { try #require(manifest.settings.first { $0.key == key }).options }
    #expect(try options("threshold").map { BatterySettings(environment: ["ALTOOLS_SETTING_THRESHOLD": $0]).threshold } == [5, 10, 15, 20, 25, 30])
    #expect(try options("ears").map { BatterySettings(environment: ["ALTOOLS_SETTING_EARS": $0]).ears } == [.whenLow, .always, .off])
    #expect(try options("menubar").map { BatterySettings(environment: ["ALTOOLS_SETTING_MENUBAR": $0]).menuBar } == [false, true])
  }
}
