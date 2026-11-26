import SwiftUI

struct HomeTab: View {
  @ObservedObject var model: NotchModel
  @ObservedObject var nowPlaying: NowPlaying
  @ObservedObject var reminders: RemindersStore
  let actions: NotchActions

  @ObservedObject private var settings = AppSettings.shared
  @ObservedObject private var plugins = PluginHost.shared

  var body: some View {
    VStack(spacing: 6) {
      HStack(spacing: 6) {
        let cards = visibleSlots
        // Without a flexible card (Calendar & to-dos), the fixed ones share the width.
        let stretch = !cards.contains { $0.width == nil }
        ForEach(cards) { card in
          NotchCard(padding: 9) { content(for: card) }
            .frame(width: stretch ? nil : card.width)
            .frame(maxWidth: stretch || card.width == nil ? .infinity : nil)
            .contentShape(Rectangle())
            .onTapGesture { open(card) }
        }
      }
      // An agent waiting in tuios outranks the shortcuts; they come back once it's answered.
      if AppSettings.shared.isOn("notch.agents"), !model.agents.items.isEmpty {
        AgentStrip(agents: model.agents)
      } else if !settings.homeActionList.isEmpty {
        quickActions
      }
    }
  }

  private var visibleSlots: [HomeSlot] {
    settings.homeSlotList.filter { slot in
      switch slot {
      case .builtin(let card): card.capability.map(settings.isOn) ?? true
      case .plugin(let id): settings.isOn("notch.plugins") && plugins.plugins.contains { $0.id == id && $0.enabled && $0.manifest?.slots.contains(.home) == true }
      }
    }
  }

  @ViewBuilder private func content(for slot: HomeSlot) -> some View {
    switch slot {
    case .builtin(.media): mediaCard
    case .builtin(.agenda): agenda
    case .builtin(.usage): UsageSummary(usage: model.usage)
    case .plugin(let id):
      if let plugin = plugins.plugins.first(where: { $0.id == id }) { PluginHomeCard(plugin: plugin) }
    }
  }

  private func open(_ slot: HomeSlot) {
    let tab: NotchModel.Tab? = switch slot {
    case .builtin(.media): .media
    case .builtin(.usage): .usage
    case .builtin(.agenda): nil
    case .plugin(let id): plugins.plugins.first { $0.id == id }?.shows(.tab) == true ? .plugins : nil
    }
    if case .plugin(let id) = slot { model.pluginTab = id }
    if let tab { withAnimation(.snappy) { model.tab = tab } }
  }

  // MARK: Media

  @ViewBuilder private var mediaCard: some View {
    let track = nowPlaying.track
    HStack(spacing: 10) {
      Artwork(image: nowPlaying.artwork, size: 48, dimmed: track == nil)
      VStack(alignment: .leading, spacing: 4) {
        if let track {
          Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
          Text(track.artist.isEmpty ? track.appName : track.artist)
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
          TimelineView(.periodic(from: .now, by: 1)) { context in
            ProgressBar(value: track.duration > 0 ? track.elapsed(at: context.date) / track.duration : 0)
          }
          .padding(.top, 3)
          HStack(spacing: 18) {
            MediaButton(symbol: "backward.fill", size: 12, action: nowPlaying.previous)
            MediaButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 17, action: nowPlaying.playPause)
            MediaButton(symbol: "forward.fill", size: 12, action: nowPlaying.next)
          }
          .frame(maxWidth: .infinity)
        } else {
          Text("Nothing playing").font(.system(size: 12, weight: .semibold))
          Text(nowPlaying.automationDenied
               ? "Allow Altools under Privacy & Security › Automation."
               : "Music from any player shows here")
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  // MARK: Agenda

  @ViewBuilder private var agenda: some View {
    VStack(alignment: .leading, spacing: 8) {
      if reminders.calendarAccess == .granted {
        if let meeting = reminders.meetings.first {
          MeetingRow(meeting: meeting)
          if reminders.meetings.count > 1 {
            Text("+\(reminders.meetings.count - 1) more today").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
          }
        } else {
          Label("No more events today", systemImage: "calendar").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
        }
      } else {
        PermissionChip(title: "Show calendar", symbol: "calendar", denied: reminders.calendarAccess == .denied,
                       action: reminders.requestCalendar)
      }
      Divider().overlay(Color.white.opacity(0.08))
      if reminders.reminderAccess == .granted {
        Button { withAnimation(.snappy) { model.tab = .todo } } label: {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Image(systemName: "checklist").foregroundStyle(.orange)
              Text(reminders.todayCount == 0 ? "Nothing due today" : "\(reminders.todayCount) due today")
                .font(.system(size: 12, weight: .semibold))
              if !reminders.overdue.isEmpty {
                Text("\(reminders.overdue.count) overdue").font(.system(size: 10, weight: .semibold)).foregroundStyle(.red)
              }
            }
            ForEach((reminders.overdue + reminders.today).prefix(2)) { todo in
              Text("· \(todo.title)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } else {
        PermissionChip(title: "Show to-dos", symbol: "checklist", denied: reminders.reminderAccess == .denied,
                       action: reminders.requestReminders)
      }
    }
  }

  // MARK: Quick actions

  private var quickActions: some View {
    HStack(spacing: 6) {
      ForEach(settings.homeActionList) { action in
        QuickAction(symbol: action.symbol, title: action.title, tint: action.tint) { action.perform(actions) }
      }
    }
  }

}

struct MeetingRow: View {
  let meeting: RemindersStore.Meeting

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      RoundedRectangle(cornerRadius: 2).fill(meeting.color).frame(width: 3, height: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(meeting.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        TimelineView(.periodic(from: .now, by: 30)) { context in
          Text(Self.relative(meeting, now: context.date)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
        }
      }
      Spacer(minLength: 4)
      if let url = meeting.joinURL {
        Button("Join") { RemindersStore.join(url) }
          .buttonStyle(.plain)
          .font(.system(size: 11, weight: .semibold))
          .padding(.horizontal, 9).frame(height: 22)
          .background(Color.green.opacity(0.85), in: Capsule())
      }
    }
  }

  static func relative(_ meeting: RemindersStore.Meeting, now: Date) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = [.hour, .minute]
    if meeting.start > now {
      return "Starts in \(formatter.string(from: max(60, meeting.start.timeIntervalSince(now))) ?? "")"
    }
    return "Ends in \(formatter.string(from: max(60, meeting.end.timeIntervalSince(now))) ?? "")"
  }
}

struct PermissionChip: View {
  let title: String
  let symbol: String
  let denied: Bool
  let action: () -> Void

  var body: some View {
    Button {
      if denied {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
      } else {
        action()
      }
    } label: {
      Label(denied ? "\(title) — allow in Settings" : title, systemImage: symbol)
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10).frame(height: 24)
        .background(Color.white.opacity(0.1), in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

/// Claude Code's plan quotas in two bars, for Home.
private struct UsageSummary: View {
  @ObservedObject var usage: AIUsage

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 5) {
        Circle().fill(Color(red: 0.85, green: 0.47, blue: 0.34)).frame(width: 6, height: 6)
        Text("Claude Code").font(.system(size: 11, weight: .semibold)).lineLimit(1)
      }
      if usage.claude.windows.isEmpty {
        Text("Connect in Settings › Notch").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
      }
      ForEach(usage.claude.windows.prefix(2)) { window in
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text(window.name).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text("\(Int(window.percent.rounded()))%").font(.system(size: 11, weight: .semibold).monospacedDigit())
          }
          ProgressBar(value: window.percent / 100)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear { usage.refresh() }
  }
}

/// The first agent waiting in tuios (blocked ones before finished ones), with how many
/// more; click to jump to its pane.
private struct AgentStrip: View {
  @ObservedObject var agents: AgentInbox

  var body: some View {
    if let item = agents.items.first {
      let tint: Color = item.isBlocking ? .orange : .green
      Button { AgentInbox.open(item) } label: {
        HStack(spacing: 7) {
          Image(systemName: item.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
          Text(item.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
          Text(item.title).font(.system(size: 10, weight: .medium)).foregroundStyle(tint).lineLimit(1)
          Text(item.summary).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
          Spacer(minLength: 4)
          if agents.items.count > 1 {
            Text("+\(agents.items.count - 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
          }
          Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 26)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(agents.items.map { "\($0.name): \($0.title)" }.joined(separator: "\n"))
    }
  }
}

private struct QuickAction: View {
  let symbol: String
  let title: String
  let tint: Color
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
      }
      .frame(maxWidth: .infinity).frame(height: 26)
      .background(Color.white.opacity(hovering ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}

struct Artwork: View {
  let image: NSImage?
  let size: CGFloat
  var dimmed = false

  var body: some View {
    ZStack {
      if let image {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
      } else {
        LinearGradient(colors: [Color.pink.opacity(0.8), Color.orange.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
          .opacity(dimmed ? 0.3 : 1)
        Image(systemName: "music.note").font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
  }
}

struct MediaButton: View {
  let symbol: String
  let size: CGFloat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: size)).frame(width: size + 16, height: size + 12).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct ProgressBar: View {
  let value: Double

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.18))
        Capsule().fill(Color.white).frame(width: geo.size.width * min(max(value, 0), 1))
      }
    }
    .frame(height: 4)
  }
}

// MARK: Media tab

struct MediaTab: View {
  @ObservedObject var nowPlaying: NowPlaying
  @State private var scrub: Double?

  var body: some View {
    if let track = nowPlaying.track {
      HStack(spacing: 20) {
        Artwork(image: nowPlaying.artwork, size: 92)
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: track.bundleID) {
              Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
            }
            Text(track.appName).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
          }
          Text(track.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
          Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
            .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
          Spacer(minLength: 4)
          TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = scrub ?? track.elapsed(at: context.date)
            VStack(spacing: 4) {
              Scrubber(value: track.duration > 0 ? elapsed / track.duration : 0, enabled: track.canSeek) { fraction, done in
                scrub = fraction * track.duration
                if done {
                  nowPlaying.seek(to: fraction * track.duration)
                  scrub = nil
                }
              }
              HStack {
                Text(Self.time(elapsed))
                Spacer()
                Text(track.duration > 0 ? "-" + Self.time(track.duration - elapsed) : "")
              }
              .font(.system(size: 10, weight: .medium).monospacedDigit())
              .foregroundStyle(.white.opacity(0.45))
            }
          }
          HStack(spacing: 30) {
            MediaButton(symbol: "backward.fill", size: 16, action: nowPlaying.previous)
            MediaButton(symbol: track.isPlaying ? "pause.fill" : "play.fill", size: 24, action: nowPlaying.playPause)
            MediaButton(symbol: "forward.fill", size: 16, action: nowPlaying.next)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, 6)
    } else {
      VStack(spacing: 8) {
        Image(systemName: "music.note.list").font(.system(size: 30)).foregroundStyle(.white.opacity(0.3))
        Text("Nothing playing").font(.system(size: 15, weight: .semibold))
        Text("Start something in any player and it shows up here with controls.")
          .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  static func time(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
  }
}

private struct Scrubber: View {
  let value: Double
  let enabled: Bool
  let onChange: (Double, Bool) -> Void
  @State private var hovering = false

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.18))
        Capsule().fill(Color.white).frame(width: geo.size.width * min(max(value, 0), 1))
      }
      .frame(height: hovering && enabled ? 8 : 5)
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0)
        .onChanged { g in if enabled { onChange(min(max(g.location.x / geo.size.width, 0), 1), false) } }
        .onEnded { g in if enabled { onChange(min(max(g.location.x / geo.size.width, 0), 1), true) } })
    }
    .frame(height: 14)
    .onHover { hovering = $0 }
    .animation(.snappy, value: hovering)
  }
}
