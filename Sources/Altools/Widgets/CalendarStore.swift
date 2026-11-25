import AppKit
import EventKit
import SwiftUI

/// Events for the calendar widget: one month for the grid's dots, plus a selected day.
final class CalendarStore: ObservableObject {
  struct Event: Identifiable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var color: Color
    var joinURL: URL?
  }

  @Published private(set) var granted = [.fullAccess, .authorized].contains(EKEventStore.authorizationStatus(for: .event))
  @Published var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
  @Published var selected = Calendar.current.startOfDay(for: Date())
  /// Events in the shown month, keyed by the start of each day they touch.
  @Published private(set) var byDay: [Date: [Event]] = [:]
  private let store = EKEventStore()
  private var observer: Any?

  init() {
    observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
      self?.reload()
    }
  }

  func requestAccess() {
    store.requestFullAccessToEvents { [weak self] granted, _ in
      DispatchQueue.main.async {
        self?.granted = granted
        self?.reload()
      }
    }
  }

  var selectedEvents: [Event] { byDay[selected] ?? [] }

  /// The 6×7 grid of days for the shown month, starting on the locale's first weekday.
  var gridDays: [Date] {
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: month)
    let lead = (weekday - calendar.firstWeekday + 7) % 7
    let start = calendar.date(byAdding: .day, value: -lead, to: month)!
    return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
  }

  func shiftMonth(_ delta: Int) {
    month = Calendar.current.date(byAdding: .month, value: delta, to: month)!
    reload()
  }

  func goToToday() {
    month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    selected = Calendar.current.startOfDay(for: Date())
    reload()
  }

  func reload() {
    guard granted else { return }
    let calendar = Calendar.current
    guard let first = gridDays.first, let last = gridDays.last.flatMap({ calendar.date(byAdding: .day, value: 1, to: $0) }) else { return }
    let events = store.events(matching: store.predicateForEvents(withStart: first, end: last, calendars: nil))
      .filter { $0.status != .canceled }
    var map: [Date: [Event]] = [:]
    for event in events {
      let item = Event(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "Event", start: event.startDate,
                       end: event.endDate, allDay: event.isAllDay, color: Color(cgColor: event.calendar.cgColor),
                       joinURL: RemindersStore.joinURL(in: [event.url?.absoluteString, event.location, event.notes]))
      var day = calendar.startOfDay(for: event.startDate)
      // Multi-day events show on every day they cover (end is exclusive).
      while day < event.endDate || day == calendar.startOfDay(for: event.startDate) {
        map[day, default: []].append(item)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day), next < event.endDate else { break }
        day = next
      }
    }
    for key in map.keys { map[key]?.sort { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) } }
    byDay = map
  }

  /// Creates an event on the selected day in the default calendar. Returns an error message on failure.
  @discardableResult
  func create(title: String, start: Date, minutes: Int) -> String? {
    guard granted, let calendar = store.defaultCalendarForNewEvents else { return "No calendar to write to" }
    guard calendar.allowsContentModifications else { return "That calendar is read-only" }
    let event = EKEvent(eventStore: store)
    event.title = title.isEmpty ? "New Event" : title
    event.startDate = start
    event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
    event.calendar = calendar
    do {
      try store.save(event, span: .thisEvent, commit: true)
      reload()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  func openCalendarApp(at date: Date? = nil) {
    if let date, let url = URL(string: "ical://ekevent/\(Int(date.timeIntervalSinceReferenceDate))?method=show&options=more") {
      NSWorkspace.shared.open(url)
    } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
      NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
  }
}
