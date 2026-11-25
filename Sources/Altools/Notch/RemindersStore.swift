import AppKit
import EventKit
import SwiftUI

/// Reminders (overdue, today, next 7 days) and today's calendar events, from EventKit.
/// Data stays in the user's Reminders / Calendar; iCloud syncs it to their phone.
final class RemindersStore: ObservableObject {
  enum Access { case notDetermined, granted, denied }

  struct Todo: Identifiable, Equatable {
    let id: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var color: Color
  }

  struct Meeting: Identifiable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var color: Color
    /// A video-call link found in the event's URL, location or notes.
    var joinURL: URL?
  }

  @Published private(set) var reminderAccess: Access = .notDetermined
  @Published private(set) var calendarAccess: Access = .notDetermined
  @Published private(set) var overdue: [Todo] = []
  @Published private(set) var today: [Todo] = []
  @Published private(set) var upcoming: [Todo] = []
  /// Events still to come or in progress today, soonest first; all-day events left out.
  @Published private(set) var meetings: [Meeting] = []
  /// The last completed to-do, so its row can offer Undo.
  @Published private(set) var lastCompleted: Todo?

  private let store = EKEventStore()
  private var observer: Any?
  private var timer: Timer?

  init() {
    reminderAccess = Self.access(EKEventStore.authorizationStatus(for: .reminder))
    calendarAccess = Self.access(EKEventStore.authorizationStatus(for: .event))
  }

  func start() {
    observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
      self?.refresh()
    }
    // Meetings move from "starts in" to "ends in" and drop off as time passes.
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshMeetings() }
    refresh()
  }

  var todayCount: Int { overdue.count + today.count }

  func requestReminders() {
    store.requestFullAccessToReminders { [weak self] granted, _ in
      DispatchQueue.main.async {
        self?.reminderAccess = granted ? .granted : .denied
        self?.refresh()
      }
    }
  }

  func requestCalendar() {
    store.requestFullAccessToEvents { [weak self] granted, _ in
      DispatchQueue.main.async {
        self?.calendarAccess = granted ? .granted : .denied
        self?.refresh()
      }
    }
  }

  func refresh() {
    refreshReminders()
    refreshMeetings()
  }

  // MARK: Reminders

  private func refreshReminders() {
    guard reminderAccess == .granted else { return }
    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: Date())
    let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
    let endOfWeek = calendar.date(byAdding: .day, value: 8, to: startOfToday)!
    let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfWeek, calendars: nil)
    store.fetchReminders(matching: predicate) { [weak self] reminders in
      let todos = (reminders ?? []).compactMap { reminder -> Todo? in
        guard let components = reminder.dueDateComponents, let due = calendar.date(from: components) else { return nil }
        return Todo(id: reminder.calendarItemIdentifier,
                    title: reminder.title?.isEmpty == false ? reminder.title! : "(untitled)",
                    due: due,
                    hasTime: components.hour != nil,
                    color: Color(cgColor: reminder.calendar.cgColor))
      }
      .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
      let now = Date()
      DispatchQueue.main.async {
        guard let self else { return }
        // A to-do with a time is overdue once that time passes; a date-only one once its day ends.
        self.overdue = todos.filter { todo in
          guard let due = todo.due else { return false }
          return todo.hasTime ? due < now : due < startOfToday
        }
        self.today = todos.filter { todo in
          guard let due = todo.due, !self.overdue.contains(todo) else { return false }
          return due < endOfToday
        }
        self.upcoming = todos.filter { todo in
          guard let due = todo.due else { return false }
          return due >= endOfToday
        }
      }
    }
  }

  /// Adds a reminder, reading a date out of the text: "report tomorrow 3pm" is due tomorrow at 15:00.
  func add(_ text: String, listName: String = "") {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, reminderAccess == .granted else { return }
    let parsed = Self.parseDue(trimmed)
    let reminder = EKReminder(eventStore: store)
    reminder.title = parsed.title
    reminder.calendar = store.calendars(for: .reminder).first { $0.title == listName } ?? store.defaultCalendarForNewReminders()
    if let due = parsed.due {
      let fields: Set<Calendar.Component> = parsed.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
      reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: due)
      if parsed.hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
    } else {
      // Without a date it would fall outside "today and the next 7 days" and vanish from the list.
      reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    }
    save(reminder)
  }

  func complete(_ todo: Todo) {
    guard let reminder = store.calendarItem(withIdentifier: todo.id) as? EKReminder else { return }
    reminder.isCompleted = true
    save(reminder)
    lastCompleted = todo
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      if self?.lastCompleted == todo { self?.lastCompleted = nil }
    }
  }

  func undoComplete() {
    guard let todo = lastCompleted, let reminder = store.calendarItem(withIdentifier: todo.id) as? EKReminder else { return }
    reminder.isCompleted = false
    save(reminder)
    lastCompleted = nil
  }

  enum Snooze { case hour, tonight, tomorrow }

  func snooze(_ todo: Todo, _ option: Snooze) {
    guard let reminder = store.calendarItem(withIdentifier: todo.id) as? EKReminder else { return }
    let calendar = Calendar.current
    let now = Date()
    let due: Date
    switch option {
    case .hour: due = now.addingTimeInterval(3600)
    case .tonight: due = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
    case .tomorrow: due = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: 1, to: now)!)!
    }
    reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: due)
    reminder.alarms?.forEach(reminder.removeAlarm)
    reminder.addAlarm(EKAlarm(absoluteDate: due))
    save(reminder)
  }

  func openInReminders() {
    NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)
  }

  private func save(_ reminder: EKReminder) {
    do {
      try store.save(reminder, commit: true)
    } catch {
      Toast.show("Couldn't save the reminder: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
    }
    refreshReminders()
  }

  struct ParsedTodo: Equatable {
    var title: String
    var due: Date?
    var hasTime: Bool
  }

  /// Finds the first date in the text with NSDataDetector and removes it from the title.
  static func parseDue(_ text: String) -> ParsedTodo {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
          let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let date = match.date, let range = Range(match.range, in: text) else {
      return ParsedTodo(title: text, due: nil, hasTime: false)
    }
    let phrase = text[range].lowercased()
    // NSDataDetector gives date-only phrases a noon time; only keep a time the user wrote.
    let hasTime = phrase.range(of: #"\d\s*(am|pm|:|点|時|时)|noon|midnight|morning|evening|tonight|上午|下午|晚上|早上"#,
                               options: .regularExpression) != nil
    var title = text
    title.removeSubrange(range)
    title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    return ParsedTodo(title: title.isEmpty ? text : title, due: date, hasTime: hasTime)
  }

  // MARK: Meetings

  private func refreshMeetings() {
    guard calendarAccess == .granted else { return }
    let now = Date()
    let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
    let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
    meetings = store.events(matching: predicate)
      .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
      .sorted { $0.startDate < $1.startDate }
      .map { event in
        Meeting(id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Event",
                start: event.startDate,
                end: event.endDate,
                color: Color(cgColor: event.calendar.cgColor),
                joinURL: Self.joinURL(in: [event.url?.absoluteString, event.location, event.notes]))
      }
  }

  /// The soonest meeting starting within five minutes, or one in progress.
  var imminentMeeting: Meeting? {
    let now = Date()
    return meetings.first { $0.start <= now.addingTimeInterval(300) && $0.end > now }
  }

  private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                     "webex.com", "meeting.tencent.com", "voovmeeting.com", "feishu.cn", "larksuite.com",
                                     "dingtalk.com", "facetime.apple.com", "whereby.com", "around.co"]

  /// Opens a meeting link in its desktop app when installed (Zoom, Teams, Tencent Meeting), else the browser.
  static func join(_ url: URL) {
    if let app = appURL(for: url), NSWorkspace.shared.urlForApplication(toOpen: app) != nil {
      NSWorkspace.shared.open(app)
    } else {
      NSWorkspace.shared.open(url)
    }
  }

  /// "https://x.zoom.us/j/123?pwd=abc" → "zoommtg://zoom.us/join?action=join&confno=123&pwd=abc";
  /// Teams links switch to the msteams: scheme. nil for links without an app scheme.
  static func appURL(for url: URL) -> URL? {
    guard let host = url.host?.lowercased() else { return nil }
    if host == "zoom.us" || host.hasSuffix(".zoom.us") {
      let parts = url.pathComponents
      guard let index = parts.firstIndex(where: { $0 == "j" || $0 == "w" }), index + 1 < parts.count else { return nil }
      var components = URLComponents()
      components.scheme = "zoommtg"
      components.host = "zoom.us"
      components.path = "/join"
      var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[index + 1])]
      if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value {
        items.append(URLQueryItem(name: "pwd", value: pwd))
      }
      components.queryItems = items
      return components.url
    }
    if host.hasSuffix("teams.microsoft.com") || host.hasSuffix("teams.live.com") {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.scheme = "msteams"
      return components?.url
    }
    return nil
  }

  /// "Zoom", "Teams", … for the Join button, from the link's host.
  static func serviceName(for url: URL) -> String? {
    let host = url.host?.lowercased() ?? ""
    let names = [("zoom.us", "Zoom"), ("meet.google.com", "Meet"), ("teams.", "Teams"), ("webex.com", "Webex"),
                 ("meeting.tencent.com", "Tencent Meeting"), ("voovmeeting.com", "VooV"), ("feishu.cn", "Feishu"),
                 ("larksuite.com", "Lark"), ("facetime.apple.com", "FaceTime")]
    return names.first { host.contains($0.0) }?.1
  }

  static func joinURL(in fields: [String?]) -> URL? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    for field in fields.compactMap({ $0 }) {
      for match in detector.matches(in: field, range: NSRange(field.startIndex..., in: field)) {
        guard let url = match.url, let host = url.host?.lowercased() else { continue }
        if meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
      }
    }
    return nil
  }

  #if DEBUG
  func loadDemo() {
    reminderAccess = .granted
    calendarAccess = .granted
    let now = Date()
    overdue = [Todo(id: "1", title: "Send the Q3 invoice", due: now.addingTimeInterval(-7200), hasTime: true, color: .red)]
    today = [Todo(id: "2", title: "Review Leo's design doc", due: now.addingTimeInterval(5400), hasTime: true, color: .orange),
             Todo(id: "3", title: "Book flights for December", due: now, hasTime: false, color: .blue)]
    upcoming = [Todo(id: "4", title: "Dentist", due: now.addingTimeInterval(86400 * 2), hasTime: true, color: .purple)]
    meetings = [Meeting(id: "m", title: "Design sync", start: now.addingTimeInterval(240), end: now.addingTimeInterval(2040),
                        color: .green, joinURL: URL(string: "https://meet.google.com/abc"))]
  }
  #endif

  private static func access(_ status: EKAuthorizationStatus) -> Access {
    switch status {
    case .fullAccess, .authorized: .granted
    case .notDetermined: .notDetermined
    default: .denied
    }
  }
}
