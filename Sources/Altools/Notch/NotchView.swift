import SwiftUI

/// Black shape hanging from the top edge: flat top, rounded bottom corners.
struct NotchShape: Shape {
  var bottomRadius: CGFloat
  var animatableData: CGFloat {
    get { bottomRadius }
    set { bottomRadius = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let r = min(bottomRadius, rect.height / 2, rect.width / 2)
    var p = Path()
    p.move(to: CGPoint(x: rect.minX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
    p.closeSubpath()
    return p
  }
}

struct NotchView: View {
  @ObservedObject var model: NotchModel
  let actions: NotchActions

  private var size: CGSize {
    if model.expanded { return NotchModel.expandedSize }
    if model.card != nil { return CGSize(width: NotchModel.cardSize.width, height: model.notchSize.height + NotchModel.cardSize.height - 14) }
    return model.collapsedSize
  }
  /// Without a hardware notch the idle island is invisible; it only shows when live or open.
  private var visible: Bool {
    if model.expanded || model.card != nil { return true }
    // A drawn notch at rest makes way while ⌘ is held, so the icons beneath can be dragged.
    if !model.hasNotch, model.commandHeld { return false }
    return model.hasNotch || model.drawsNotch || model.activity != nil
  }

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        NotchShape(bottomRadius: model.expanded ? 26 : model.card != nil ? 22 : 10).fill(Color.black)
        if model.expanded {
          ExpandedNotch(model: model, actions: actions)
            .padding(.top, model.notchSize.height)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        } else if let card = model.card {
          CardView(card: card, dismiss: model.dismissCard, openNotification: model.openNotification)
            .padding(.top, model.notchSize.height)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
        } else if let activity = model.activity {
          Ears(activity: activity, model: model)
            .frame(height: model.notchSize.height)
            .transition(.opacity)
            .id(activityKey(activity))
        }
      }
      .frame(width: size.width, height: size.height)
      .opacity(visible ? 1 : 0)
      .offset(x: model.xOffset)
      .shadow(color: .black.opacity(model.expanded || model.card != nil ? 0.4 : 0), radius: 14, y: 5)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .environment(\.colorScheme, .dark)
  }

  /// Identity per kind of activity, so switching kinds cross-fades instead of morphing text.
  private func activityKey(_ activity: NotchModel.Activity) -> String {
    switch activity {
    case .flash(let flash):
      if case .volume = flash.kind { "volume" } else { flash.id.uuidString }
    case .meeting(let m): "meeting-\(m.id)"
    case .lowBattery: "battery"
    case .sensors: "sensors"
    case .ai: "ai"
    case .music: "music"
    case .ticker: "ticker"
    }
  }
}

// MARK: Collapsed ears

/// The two sides of the island beside the hardware notch: a symbol on the left, a value on the right.
private struct Ears: View {
  let activity: NotchModel.Activity
  @ObservedObject var model: NotchModel

  var body: some View {
    HStack(spacing: 0) {
      left.frame(width: activity.earWidth - 14, alignment: .leading)
      Spacer(minLength: model.hasNotch ? model.notchSize.width : 12)
      right.frame(width: activity.earWidth - 14, alignment: .trailing)
    }
    .padding(.horizontal, 10)
    .font(.system(size: 11, weight: .semibold))
    .foregroundStyle(.white)
    .lineLimit(1)
    .contentShape(Rectangle())
    .onTapGesture {
      guard case .meeting(let meeting) = activity else { return }
      if let url = meeting.joinURL { RemindersStore.join(url) } else { CalendarStore().openCalendarApp() }
    }
    .help(helpText)
  }

  private var helpText: String {
    if case .meeting(let meeting) = activity {
      return meeting.joinURL == nil ? "\(meeting.title) — open Calendar" : "\(meeting.title) — click to join"
    }
    return ""
  }

  @ViewBuilder private var left: some View {
    switch activity {
    case .flash(let flash):
      switch flash.kind {
      case .receipt(let r):
        if let image = r.image {
          Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            .frame(width: 28, height: 20).clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let color = r.color {
          Circle().fill(color).frame(width: 16, height: 16).overlay(Circle().strokeBorder(.white.opacity(0.4)))
        } else {
          Image(systemName: r.symbol).foregroundStyle(r.tint)
        }
      case .power(_, let plugged):
        Image(systemName: plugged ? "bolt.fill" : "powerplug").foregroundStyle(plugged ? .green : .white.opacity(0.7))
      case .input(let symbol, _):
        Image(systemName: symbol).foregroundStyle(.white)
      case .download(let url):
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
      case .volume(let level):
        Image(systemName: Self.volumeSymbol(level)).foregroundStyle(.white)
          .contentTransition(.symbolEffect(.replace))
      }
    case .meeting(let m):
      HStack(spacing: 5) {
        Circle().fill(m.color).frame(width: 7, height: 7)
        Image(systemName: m.joinURL == nil ? "calendar" : "video.fill").foregroundStyle(m.color)
      }
    case .lowBattery:
      Image(systemName: "battery.0percent").foregroundStyle(.red)
    case .sensors(let s):
      Image(systemName: s.camera ? "video.fill" : "mic.fill").foregroundStyle(s.camera ? .green : .orange)
    case .ai:
      Image(systemName: "sparkles").foregroundStyle(.purple)
        .symbolEffect(.pulse, options: .repeating)
    case .ticker(let quote):
      // Bitcoin gets its symbol alone; other pairs show their short name.
      if CryptoTicker.base(of: quote.symbol) == "BTC" {
        Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(.orange)
      } else {
        Text(CryptoTicker.base(of: quote.symbol)).foregroundStyle(.orange)
      }
    case .music:
      Group {
        if let art = model.nowPlaying.artwork {
          Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else {
          Image(systemName: "music.note").foregroundStyle(.white)
        }
      }
      .frame(width: 20, height: 20)
      .clipShape(RoundedRectangle(cornerRadius: 5))
    }
  }

  @ViewBuilder private var right: some View {
    switch activity {
    case .flash(let flash):
      switch flash.kind {
      case .receipt(let r): Text(r.title).foregroundStyle(.white.opacity(0.9))
      case .power(let percent, let plugged): Text("\(percent)%").foregroundStyle(plugged ? .green : .white)
      case .input(_, let label): Text(label)
      case .download(let url): Text(url.lastPathComponent).truncationMode(.middle).foregroundStyle(.white.opacity(0.9))
      case .volume(let level):
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.2))
            Capsule().fill(level.muted ? Color.white.opacity(0.35) : .white)
              .frame(width: geo.size.width * CGFloat(level.muted ? 0 : level.volume))
          }
        }
        .frame(height: 5)
        .animation(.snappy(duration: 0.15), value: level.volume)
      }
    case .meeting(let m):
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(Self.countdown(to: m, now: context.date)).monospacedDigit().foregroundStyle(m.color)
      }
    case .lowBattery(let percent):
      Text("\(percent)%").foregroundStyle(.red)
    case .sensors(let s):
      if let app = s.microphoneApp {
        Text(app).foregroundStyle(.orange)
      } else {
        Circle().fill(s.camera ? Color.green : .orange).frame(width: 7, height: 7)
      }
    case .ai:
      ProgressView().controlSize(.mini).tint(.white)
    case .ticker(let quote):
      VStack(alignment: .trailing, spacing: -1) {
        Text(CryptoTicker.format(quote.price))
          .monospacedDigit()
          .contentTransition(.numericText(value: quote.price))
          .animation(.snappy, value: quote.price)
        Text(String(format: "%@%.2f%%", quote.change >= 0 ? "+" : "", quote.change))
          .font(.system(size: 8, weight: .semibold).monospacedDigit())
          .foregroundStyle(quote.change >= 0 ? Color.green : Color.red)
      }
    case .music:
      Image(systemName: "waveform")
        .foregroundStyle(.orange)
        .symbolEffect(.variableColor.iterative, options: .repeating)
    }
  }

  static func volumeSymbol(_ level: VolumeMonitor.Level) -> String {
    if level.muted || level.volume == 0 { return "speaker.slash.fill" }
    if level.isHeadphones { return level.deviceName.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "headphones" }
    return level.volume < 0.34 ? "speaker.wave.1.fill" : level.volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
  }

  static func countdown(to meeting: RemindersStore.Meeting, now: Date) -> String {
    let seconds = Int(meeting.start.timeIntervalSince(now))
    if seconds <= 0 { return "Now" }
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

// MARK: Expanded

private struct ExpandedNotch: View {
  @ObservedObject var model: NotchModel
  let actions: NotchActions

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 2) {
        ForEach(model.tabs) { tab in
          tabButton(tab).help(tab.title)
        }
        Spacer(minLength: 8)
        BatteryBadge(battery: model.battery)
        Button { model.pinned.toggle() } label: {
          Image(systemName: model.pinned ? "pin.fill" : "pin")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(model.pinned ? Color.orange : .white.opacity(0.5))
            .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.pinned ? "Unpin" : "Keep open")
      }
      Group {
        switch model.tab {
        case .home: HomeTab(model: model, nowPlaying: model.nowPlaying, reminders: model.reminders, actions: actions)
        case .media: MediaTab(nowPlaying: model.nowPlaying)
        case .todo: TodoTab(reminders: model.reminders)
        case .notes: NotesTab(notes: model.notes)
        case .shelf: ShelfTab(shelf: model.shelf, actions: actions)
        case .usage: UsageTab(usage: model.usage)
        case .markets: MarketsTab(markets: model.markets)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .foregroundStyle(.white)
  }

  private func tabButton(_ tab: NotchModel.Tab) -> some View {
    let selected = model.tab == tab
    return Button {
      withAnimation(.snappy) { model.tab = tab }
      if tab == .usage { model.usage.refresh() }
    } label: {
      // Only the open tab shows its name; the rest are icons, to keep the bar short.
      HStack(spacing: 5) {
        Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
        if selected { Text(badge(tab)).font(.system(size: 12, weight: .semibold)) }
      }
      .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
      .padding(.horizontal, selected ? 9 : 7).frame(height: 22)
      .background(selected ? Color.white.opacity(0.14) : .clear, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private func badge(_ tab: NotchModel.Tab) -> String {
    switch tab {
    case .todo where model.reminders.todayCount > 0: "\(tab.title) · \(model.reminders.todayCount)"
    case .shelf where !model.shelf.files.isEmpty: "\(tab.title) · \(model.shelf.files.count)"
    default: tab.title
    }
  }
}

struct BatteryBadge: View {
  @ObservedObject var battery: BatteryMonitor

  var body: some View {
    if let state = battery.state {
      HStack(spacing: 4) {
        if state.isCharging { Image(systemName: "bolt.fill").foregroundStyle(.green) }
        Text("\(state.percent)%").font(.system(size: 12, weight: .medium).monospacedDigit())
        Image(systemName: symbol(state.percent))
          .foregroundStyle(state.percent <= 20 && !state.onAC ? .red : .white)
      }
      .font(.system(size: 12))
      .padding(.trailing, 4)
    }
  }

  private func symbol(_ percent: Int) -> String {
    switch percent {
    case ..<13: "battery.0percent"
    case ..<38: "battery.25percent"
    case ..<63: "battery.50percent"
    case ..<88: "battery.75percent"
    default: "battery.100percent"
    }
  }
}

/// Shared styling for the notch's inner cards.
struct NotchCard<Content: View>: View {
  var padding: CGFloat = 12
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct NotchSectionTitle: View {
  let text: String
  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 10, weight: .bold))
      .tracking(0.6)
      .foregroundStyle(.white.opacity(0.4))
  }
}

// MARK: Cards

/// A meeting reminder or another app's notification, dropped down from the island.
private struct CardView: View {
  let card: NotchModel.Card
  let dismiss: () -> Void
  let openNotification: (NotificationWatcher.Banner) -> Void

  var body: some View {
    HStack(spacing: 12) {
      switch card {
      case .meeting(let meeting, let startingNow): meetingCard(meeting, startingNow: startingNow)
      case .notification(let banner): notificationCard(banner)
      case .agent(let item): agentCard(item)
      }
      Button(action: dismiss) {
        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
          .frame(width: 22, height: 22).background(Color.white.opacity(0.1), in: Circle())
      }
      .buttonStyle(.plain)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private func meetingCard(_ meeting: RemindersStore.Meeting, startingNow: Bool) -> some View {
    Image(systemName: meeting.joinURL == nil ? "calendar" : "video.fill")
      .font(.system(size: 15, weight: .semibold)).foregroundStyle(meeting.color)
      .frame(width: 36, height: 36).background(meeting.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    VStack(alignment: .leading, spacing: 2) {
      Text(meeting.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let seconds = Int(meeting.start.timeIntervalSince(context.date))
        Text(seconds > 0 ? "Starts in \(seconds / 60):\(String(format: "%02d", seconds % 60))" : "Starting now")
          .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(meeting.color)
      }
    }
    Spacer(minLength: 4)
    if let url = meeting.joinURL {
      Button {
        RemindersStore.join(url)
        dismiss()
      } label: {
        Text("Join \(RemindersStore.serviceName(for: url) ?? "")".trimmingCharacters(in: .whitespaces))
          .font(.system(size: 12, weight: .semibold))
          .padding(.horizontal, 12).frame(height: 28)
          .background(Color.green, in: Capsule())
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder private func agentCard(_ item: AgentInbox.Item) -> some View {
    Button {
      AgentInbox.open(item)
      dismiss()
    } label: {
      HStack(spacing: 12) {
        let tint: Color = item.isBlocking ? .orange : .green
        Image(systemName: item.symbol)
          .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
          .frame(width: 36, height: 36).background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 6) {
            Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(item.title).font(.system(size: 10, weight: .medium)).foregroundStyle(tint).lineLimit(1)
          }
          if !item.summary.isEmpty {
            Text(item.summary).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
          }
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Open the pane in tuios")
  }

  @ViewBuilder private func notificationCard(_ banner: NotificationWatcher.Banner) -> some View {
    Button {
      openNotification(banner)
      dismiss()
    } label: {
      HStack(spacing: 12) {
        Group {
          if let id = banner.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
          } else {
            Image(systemName: "bell.fill").foregroundStyle(.orange).frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
          }
        }
        .frame(width: 34, height: 34)
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 6) {
            Text(banner.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(banner.appName).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
          }
          if !banner.body.isEmpty {
            Text(banner.body).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
          }
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
