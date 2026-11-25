import AppKit
import SwiftUI

// MARK: Shared pieces

struct WidgetPanel<Content: View>: View {
  let title: String
  let symbol: String
  let tint: Color
  var accessory: AnyView?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
          .frame(width: 28, height: 28).background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        Text(title).font(.system(size: 15, weight: .bold))
        Spacer()
        if let accessory { accessory }
      }
      content
    }
    .padding(16)
    .frame(width: 340)
    .foregroundStyle(.white)
    .background(Color(hex: 0x14161E))
    .environment(\.colorScheme, .dark)
  }
}

struct WidgetCard<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 8) { content }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

struct InfoRow: View {
  let label: String
  let value: String
  var tint: Color = .white
  var body: some View {
    HStack {
      Text(label).foregroundStyle(Theme.dim)
      Spacer()
      Text(value).foregroundStyle(tint).monospacedDigit().lineLimit(1).truncationMode(.middle)
    }
    .font(.system(size: 12))
  }
}

/// A filled line chart of recent samples, scaled to its own peak (or a fixed max).
struct Sparkline: View {
  let values: [Double]
  var maxValue: Double?
  var tint: Color
  var height: CGFloat = 36

  var body: some View {
    GeometryReader { geo in
      let peak = max(maxValue ?? (values.max() ?? 1), 0.0001)
      let step = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : geo.size.width
      let points = values.enumerated().map { i, v in
        CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(v / peak, 1))))
      }
      ZStack {
        Path { p in
          guard let first = points.first else { return }
          p.move(to: CGPoint(x: first.x, y: geo.size.height))
          points.forEach { p.addLine(to: $0) }
          p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
          p.closeSubpath()
        }
        .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
        Path { p in
          guard let first = points.first else { return }
          p.move(to: first)
          points.dropFirst().forEach { p.addLine(to: $0) }
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
      }
    }
    .frame(height: height)
  }
}

struct UsageBar: View {
  let segments: [(Double, Color)]
  var body: some View {
    GeometryReader { geo in
      HStack(spacing: 1) {
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
          Rectangle().fill(segment.1).frame(width: max(0, geo.size.width * CGFloat(min(segment.0, 1))))
        }
        Spacer(minLength: 0)
      }
      .background(Color.white.opacity(0.1))
      .clipShape(Capsule())
    }
    .frame(height: 6)
  }
}

struct WidgetButton: View {
  let title: String
  let symbol: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity).frame(height: 30)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

private func openSettingsPane(_ id: String) {
  if let url = URL(string: "x-apple.systempreferences:\(id)") { NSWorkspace.shared.open(url) }
}

// MARK: System

struct SystemWidgetPanel: View {
  @ObservedObject var stats: SystemStats

  var body: some View {
    WidgetPanel(title: "System", symbol: "cpu", tint: Color(hex: 0x22C55E)) {
      WidgetCard {
        HStack(alignment: .firstTextBaseline) {
          Text("CPU").font(.system(size: 12, weight: .semibold))
          Spacer()
          Text(percent(stats.cpu.total)).font(.system(size: 18, weight: .bold).monospacedDigit())
        }
        Sparkline(values: stats.cpuHistory, maxValue: 1, tint: Color(hex: 0x22C55E))
        HStack(spacing: 12) {
          legend("User", percent(stats.cpu.user), Color(hex: 0x22C55E))
          legend("System", percent(stats.cpu.system), Color(hex: 0x3B82F6))
        }
      }
      WidgetCard {
        HStack(alignment: .firstTextBaseline) {
          Text("Memory").font(.system(size: 12, weight: .semibold))
          Spacer()
          Text("\(SystemStats.bytes(Double(stats.memory.used))) / \(SystemStats.bytes(Double(stats.memory.total)))")
            .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.dim)
          Text(percent(stats.memory.fraction)).font(.system(size: 18, weight: .bold).monospacedDigit())
        }
        let total = Double(max(stats.memory.total, 1))
        UsageBar(segments: [(Double(stats.memory.app) / total, Color(hex: 0xA855F7)),
                            (Double(stats.memory.wired) / total, Color(hex: 0xF59E0B)),
                            (Double(stats.memory.compressed) / total, Color(hex: 0x3B82F6))])
        HStack(spacing: 12) {
          legend("App", SystemStats.bytes(Double(stats.memory.app)), Color(hex: 0xA855F7))
          legend("Wired", SystemStats.bytes(Double(stats.memory.wired)), Color(hex: 0xF59E0B))
          legend("Compr.", SystemStats.bytes(Double(stats.memory.compressed)), Color(hex: 0x3B82F6))
        }
      }
      WidgetCard {
        HStack {
          Text("Storage").font(.system(size: 12, weight: .semibold))
          Spacer()
          Text("\(SystemStats.bytes(Double(stats.storage.free))) free of \(SystemStats.bytes(Double(stats.storage.total)))")
            .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.dim)
        }
        UsageBar(segments: [(stats.storage.fraction, Color(hex: 0x06B6D4))])
      }
      // Five fixed rows, so the panel keeps its size while `ps` results arrive.
      WidgetCard {
        Text("Top usage").font(.system(size: 12, weight: .semibold))
        ForEach(0..<5, id: \.self) { index in
          if index < stats.topProcesses.count {
            let process = stats.topProcesses[index]
            InfoRow(label: process.name, value: String(format: "%.1f%%", process.cpu))
          } else {
            InfoRow(label: index == 0 ? "Reading process usage…" : " ", value: "")
          }
        }
      }
      HStack(spacing: 8) {
        WidgetButton(title: "Activity Monitor", symbol: "waveform.path.ecg") {
          if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
          }
        }
        WidgetButton(title: "Storage", symbol: "internaldrive") { openSettingsPane("com.apple.settings.Storage") }
      }
    }
  }

  private func legend(_ name: String, _ value: String, _ color: Color) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 6, height: 6)
      Text(name).foregroundStyle(Theme.dim)
      Text(value).monospacedDigit()
    }
    .font(.system(size: 11))
    .lineLimit(1)
    .fixedSize()
  }
}

// MARK: Battery

struct BatteryWidgetPanel: View {
  let details: BatteryDetails

  var body: some View {
    WidgetPanel(title: "Battery", symbol: "battery.100percent.bolt", tint: Color(hex: 0x84CC16)) {
      if !details.hasBattery {
        WidgetCard { Text("No built-in battery").foregroundStyle(Theme.dim) }
      } else {
        WidgetCard {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(details.percent)%").font(.system(size: 34, weight: .bold).monospacedDigit())
            if details.isCharging { Image(systemName: "bolt.fill").foregroundStyle(.green) }
            Spacer()
            Text(state).font(.system(size: 12)).foregroundStyle(Theme.dim).multilineTextAlignment(.trailing)
          }
          UsageBar(segments: [(Double(details.percent) / 100, details.percent <= 20 && !details.onAC ? .red : Color(hex: 0x84CC16))])
        }
        WidgetCard {
          if let health = details.health { InfoRow(label: "Health", value: "\(Int((health * 100).rounded()))% of design capacity", tint: health < 0.8 ? .orange : .white) }
          if let cycles = details.cycles { InfoRow(label: "Cycles", value: "\(cycles)") }
          InfoRow(label: "Charger", value: details.onAC ? (details.adapterWatts.map { "\($0)W power adapter" } ?? "Connected") : "Not connected")
          if let temperature = details.temperature { InfoRow(label: "Temperature", value: String(format: "%.1f °C", temperature)) }
        }
        WidgetButton(title: "Battery Settings", symbol: "gearshape") { openSettingsPane("com.apple.Battery-Settings.extension") }
      }
    }
  }

  private var state: String {
    if details.isCharging {
      return details.minutesToFull.map { "Charging · \(duration($0)) to full" } ?? "Charging"
    }
    if details.onAC { return details.percent >= 99 ? "Fully charged" : "Plugged in · not charging" }
    return details.minutesRemaining.map { "On battery · \(duration($0)) left" } ?? "On battery"
  }

  private func duration(_ minutes: Int) -> String {
    minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
  }
}

// MARK: Calendar

struct CalendarWidgetPanel: View {
  @ObservedObject var store: CalendarStore
  @State private var newTitle = ""
  @State private var newStart = Date()
  @State private var newMinutes = 30
  @State private var message: String?

  var body: some View {
    WidgetPanel(title: store.month.formatted(.dateTime.month(.wide).year()), symbol: "calendar", tint: Color(hex: 0xEF4444),
                accessory: AnyView(navigation)) {
      if !store.granted {
        WidgetCard {
          Text("Allow calendar access").font(.system(size: 13, weight: .semibold))
          Text("Reads only times and titles, to draw the month and your next meeting.").font(.system(size: 12)).foregroundStyle(Theme.dim)
          Button("Allow access", action: store.requestAccess).buttonStyle(SoftPillButtonStyle())
        }
      } else {
        monthGrid
        dayList
        composer
        WidgetButton(title: "Open in Calendar", symbol: "arrow.up.forward.app") { store.openCalendarApp() }
      }
    }
    .onAppear { store.reload() }
  }

  private var navigation: some View {
    HStack(spacing: 4) {
      navButton("chevron.left") { store.shiftMonth(-1) }
      Button("Today", action: store.goToToday).buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8).frame(height: 24).background(Color.white.opacity(0.08), in: Capsule())
      navButton("chevron.right") { store.shiftMonth(1) }
    }
  }

  private func navButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 24, height: 24)
        .background(Color.white.opacity(0.08), in: Circle())
    }
    .buttonStyle(.plain)
  }

  private var monthGrid: some View {
    let calendar = Calendar.current
    let symbols = calendar.veryShortWeekdaySymbols
    let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
    return VStack(spacing: 4) {
      HStack(spacing: 0) {
        ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
          Text(s).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity)
        }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
        ForEach(store.gridDays, id: \.self) { day in dayCell(day) }
      }
    }
  }

  private func dayCell(_ day: Date) -> some View {
    let calendar = Calendar.current
    let inMonth = calendar.isDate(day, equalTo: store.month, toGranularity: .month)
    let isToday = calendar.isDateInToday(day)
    let isSelected = calendar.isDate(day, inSameDayAs: store.selected)
    let events = store.byDay[day] ?? []
    return Button { store.selected = day } label: {
      VStack(spacing: 2) {
        Text("\(calendar.component(.day, from: day))")
          .font(.system(size: 12, weight: isToday ? .bold : .regular).monospacedDigit())
          .foregroundStyle(isToday ? .white : inMonth ? .white.opacity(0.85) : Theme.faint)
          .frame(width: 26, height: 22)
          .background(isToday ? Color(hex: 0xEF4444) : isSelected ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        HStack(spacing: 2) {
          ForEach(Array(events.prefix(3).enumerated()), id: \.offset) { _, e in Circle().fill(e.color).frame(width: 4, height: 4) }
        }
        .frame(height: 4)
      }
      .frame(maxWidth: .infinity).frame(height: 32)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var dayList: some View {
    WidgetCard {
      Text(store.selected.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        .font(.system(size: 12, weight: .semibold))
      if store.selectedEvents.isEmpty {
        Text("Nothing on this day").font(.system(size: 12)).foregroundStyle(Theme.dim)
      } else {
        ForEach(store.selectedEvents.prefix(5)) { event in
          HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
              Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
              Text(event.allDay ? "All day" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.dim)
            }
            Spacer()
            if let url = event.joinURL {
              Button("Join") { RemindersStore.join(url) }.buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 9).frame(height: 22)
                .background(Color.green.opacity(0.85), in: Capsule())
            }
          }
        }
      }
    }
  }

  private var composer: some View {
    WidgetCard {
      HStack(spacing: 6) {
        Image(systemName: "plus.circle.fill").foregroundStyle(Color(hex: 0xEF4444))
        TextField("New event on this day", text: $newTitle).textFieldStyle(.plain).font(.system(size: 12))
          .onSubmit(create)
      }
      HStack(spacing: 8) {
        DatePicker("", selection: $newStart, displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field).frame(width: 80)
        Picker("", selection: $newMinutes) {
          Text("15m").tag(15); Text("30m").tag(30); Text("1h").tag(60); Text("2h").tag(120)
        }
        .pickerStyle(.segmented).labelsHidden()
        Button("Add", action: create).buttonStyle(SoftPillButtonStyle())
      }
      if let message { Text(message).font(.system(size: 11)).foregroundStyle(.orange) }
    }
  }

  private func create() {
    let calendar = Calendar.current
    let time = calendar.dateComponents([.hour, .minute], from: newStart)
    let start = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: store.selected) ?? store.selected
    message = store.create(title: newTitle, start: start, minutes: newMinutes)
    if message == nil { newTitle = "" }
  }
}

// MARK: Network

struct NetworkWidgetPanel: View {
  @ObservedObject var stats: SystemStats
  let info: NetworkInfo
  @State private var publicIP: String?
  @State private var lookingUp = false

  var body: some View {
    WidgetPanel(title: "Network", symbol: "network", tint: Color(hex: 0x0EA5E9),
                accessory: AnyView(HStack(spacing: 5) {
                  Circle().fill(info.connected ? Color.green : .red).frame(width: 7, height: 7)
                  Text(info.connected ? "Connected" : "Offline").font(.system(size: 12)).foregroundStyle(Theme.dim)
                })) {
      WidgetCard {
        HStack(spacing: 18) {
          rate("arrow.down", SystemStats.bytes(stats.download, perSecond: true), Color(hex: 0x0EA5E9))
          rate("arrow.up", SystemStats.bytes(stats.upload, perSecond: true), Color(hex: 0xF97316))
        }
        ZStack {
          Sparkline(values: stats.downloadHistory, maxValue: max(stats.downloadHistory.max() ?? 1, stats.uploadHistory.max() ?? 1), tint: Color(hex: 0x0EA5E9))
          Sparkline(values: stats.uploadHistory, maxValue: max(stats.downloadHistory.max() ?? 1, stats.uploadHistory.max() ?? 1), tint: Color(hex: 0xF97316))
        }
        InfoRow(label: "Since Altools started", value: "↓ \(SystemStats.bytes(Double(stats.downloadedTotal)))  ↑ \(SystemStats.bytes(Double(stats.uploadedTotal)))")
      }
      WidgetCard {
        InfoRow(label: info.isWiFi ? "Wi-Fi" : "Interface", value: info.isWiFi ? (info.ssid ?? "Name hidden by macOS") : (info.interface.isEmpty ? "—" : info.interface))
        if let signal = info.signalLabel, let rssi = info.rssi { InfoRow(label: "Signal", value: "\(signal) · \(rssi) dBm") }
        if let channel = info.channel { InfoRow(label: "Channel", value: channel) }
        if let rate = info.linkRate { InfoRow(label: "Link", value: "\(Int(rate)) Mbps") }
        if let security = info.security { InfoRow(label: "Security", value: security) }
        InfoRow(label: "Local", value: info.localIP ?? "—")
        InfoRow(label: "Router", value: info.router ?? "—")
        HStack {
          Text("Public").foregroundStyle(Theme.dim)
          Spacer()
          if let publicIP {
            Button {
              Pasteboard.copy(publicIP)
              ActivityCenter.shared.report("Copied \(publicIP)", symbol: "network")
            } label: { Text(publicIP).monospacedDigit() }.buttonStyle(.plain).help("Copy public IP")
          } else {
            Button(lookingUp ? "Looking up…" : "Look up") {
              lookingUp = true
              NetworkInfo.lookUpPublicIP { ip in publicIP = ip ?? "Unavailable"; lookingUp = false }
            }
            .buttonStyle(.plain).foregroundStyle(Color(hex: 0x0EA5E9)).disabled(lookingUp)
          }
        }
        .font(.system(size: 12))
      }
      WidgetButton(title: "Network Settings", symbol: "gearshape") { openSettingsPane("com.apple.Network-Settings.extension") }
    }
  }

  private func rate(_ symbol: String, _ value: String, _ tint: Color) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
      Text(value).font(.system(size: 18, weight: .bold).monospacedDigit())
    }
  }
}
