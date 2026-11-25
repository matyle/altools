import AltoolsCore
import Combine
import EventKit
import ServiceManagement
import SwiftUI

/// One Dark: blue-grey surfaces, soft grey text, blue accent. Each module takes one of the
/// palette's syntax colours, shown as a coloured symbol on a faint tint of itself.
enum Theme {
  static let background = Color(hex: 0x282C34)
  static let sidebar = Color(hex: 0x21252B)
  static let card = Color(hex: 0x2C313A)
  static let cardBorder = Color(hex: 0x3E4451)
  static let ink = Color(hex: 0xD7DAE0)
  static let dim = Color(hex: 0xABB2BF).opacity(0.8)
  static let faint = Color(hex: 0x5C6370)
  static let iconFill = Color(hex: 0x3E4451).opacity(0.6)
  static let accent = Color(hex: 0x61AFEF)
  static let warning = Color(hex: 0xD19A66)

  static let purple = Color(hex: 0xC678DD)
  static let cyan = Color(hex: 0x56B6C2)
  static let blue = Color(hex: 0x61AFEF)
  static let red = Color(hex: 0xE06C75)
  static let green = Color(hex: 0x98C379)
  static let yellow = Color(hex: 0xE5C07B)
  static let orange = Color(hex: 0xD19A66)
}

/// A coloured symbol on a faint tint of the same colour.
struct TonalIcon: View {
  let symbol: String
  let tint: Color
  var size: CGFloat = 30
  var on = true

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.44, weight: .semibold))
      .foregroundStyle(on ? tint : Theme.faint)
      .frame(width: size, height: size)
      .background((on ? tint : Theme.faint).opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
  }
}

/// Quick actions the Overview's tiles trigger.
struct SettingsActions {
  var captureArea: () -> Void = {}
  var recognizeText: () -> Void = {}
  var translate: () -> Void = {}
  var pickColor: () -> Void = {}
  var openClipboard: () -> Void = {}
}

final class SettingsState: ObservableObject {
  enum Page: Hashable {
    case overview, module(String), shortcuts, permissions, ai, general, about
  }

  @Published var page: Page = .overview
  @Published var search = ""
  /// Capability to scroll to and highlight after a jump from Overview or search.
  @Published var focus: String?
  @Published var aiFound = true
  /// Bumped every couple of seconds so permission states refresh while the window is open.
  @Published var tick = 0
  private var timer: AnyCancellable?

  init(page: Page = .overview) {
    self.page = page
    timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick += 1 }
    DispatchQueue.global(qos: .utility).async {
      let settings = AppSettings.shared
      let found = AIProvider.allCases.contains { CLILocator.path(for: $0, configured: settings.binaryPath(for: $0)) != nil }
      DispatchQueue.main.async { self.aiFound = found }
    }
  }

  func open(_ capability: CapabilitySpec) {
    search = ""
    page = .module(capability.moduleID)
    focus = capability.id
  }
}

struct SettingsRoot: View {
  @ObservedObject var settings = AppSettings.shared
  @StateObject private var state: SettingsState
  let actions: SettingsActions

  init(actions: SettingsActions, page: SettingsState.Page = .overview) {
    self.actions = actions
    _state = StateObject(wrappedValue: SettingsState(page: page))
  }

  var body: some View {
    // Reading the tick re-renders every couple of seconds, so permission states stay current.
    let _ = state.tick
    let modules = SettingsCatalog.modules(settings)
    HStack(spacing: 0) {
      Sidebar(state: state, settings: settings, modules: modules)
        .frame(width: 236)
      Rectangle().fill(Theme.cardBorder).frame(width: 1)
      VStack(spacing: 0) {
        TopBar(state: state, modules: modules)
        content(modules)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Theme.background)
    .foregroundStyle(Theme.ink)
    .environment(\.colorScheme, .dark)
    .frame(minWidth: 940, minHeight: 620)
    .ignoresSafeArea()
  }

  @ViewBuilder private func content(_ modules: [ModuleSpec]) -> some View {
    if !state.search.isEmpty {
      SearchResults(state: state, modules: modules)
    } else {
      switch state.page {
      case .overview: OverviewPage(state: state, modules: modules, actions: actions)
      case .module(let id):
        if let module = modules.first(where: { $0.id == id }) { ModulePage(state: state, module: module) }
      case .shortcuts: ShortcutsPage()
      case .permissions: PermissionsPage()
      case .ai: AIServicesPage()
      case .general: GeneralPage(modules: modules)
      case .about: AboutPage()
      }
    }
  }
}

// MARK: Sidebar

private struct Sidebar: View {
  @ObservedObject var state: SettingsState
  @ObservedObject var settings: AppSettings
  let modules: [ModuleSpec]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer().frame(height: 58)
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          sectionTitle("Overview")
          SidebarRow(title: "Overview", symbol: "square.grid.2x2.fill", tint: Theme.accent, active: true,
                     selected: state.page == .overview) { go(.overview) }
          sectionTitle("Modules").padding(.top, 14)
          ForEach(modules) { module in
            SidebarRow(title: module.name, symbol: module.symbol, tint: module.tint, active: module.enabled.wrappedValue,
                       selected: state.page == .module(module.id)) { go(.module(module.id)) }
          }
          sectionTitle("System").padding(.top, 14)
          SidebarRow(title: "Shortcuts", symbol: "keyboard", active: true, selected: state.page == .shortcuts) { go(.shortcuts) }
          SidebarRow(title: "Permissions", symbol: "lock.shield", active: true, selected: state.page == .permissions) { go(.permissions) }
          SidebarRow(title: "AI Services", symbol: "sparkles", active: true, selected: state.page == .ai) { go(.ai) }
          SidebarRow(title: "General", symbol: "gearshape", active: true, selected: state.page == .general) { go(.general) }
          SidebarRow(title: "About", symbol: "info.circle", active: true, selected: state.page == .about) { go(.about) }
        }
        .padding(.horizontal, 12)
      }
      .scrollIndicators(.never)
      footer
    }
    .background(Theme.sidebar)
  }

  private var footer: some View {
    let running = modules.filter { $0.enabled.wrappedValue }.count
    let everything = Binding(
      get: { modules.allSatisfy { $0.enabled.wrappedValue } },
      set: { on in modules.forEach { $0.enabled.wrappedValue = on } }
    )
    return VStack(alignment: .leading, spacing: 12) {
      Rectangle().fill(Theme.cardBorder.opacity(0.6)).frame(height: 1)
      HStack(spacing: 6) {
        Circle().fill(running > 0 ? Color.green : .gray).frame(width: 7, height: 7)
        Text(running > 0 ? "Running ·" : "Paused ·").foregroundStyle(Theme.dim)
        Text("\(running)").fontWeight(.semibold)
        Text("/ \(modules.count) modules").foregroundStyle(Theme.dim)
      }
      .font(.system(size: 12))
      HStack {
        Text("Everything on").font(.system(size: 13))
        Spacer()
        PillToggle(isOn: everything)
      }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 18)
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.system(size: 11, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.faint)
      .padding(.horizontal, 10).padding(.bottom, 4)
  }

  private func go(_ page: SettingsState.Page) {
    state.search = ""
    withAnimation(.snappy(duration: 0.2)) { state.page = page }
  }
}

private struct SidebarRow: View {
  let title: String
  let symbol: String
  var tint: Color = Theme.dim
  let active: Bool
  let selected: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(active ? tint : Theme.faint)
          .frame(width: 20, height: 20)
        Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
          .foregroundStyle(active || selected ? Theme.ink : Theme.dim)
        Spacer()
      }
      .padding(.horizontal, 10).frame(height: 36)
      .background(selected ? Theme.cardBorder.opacity(0.6) : hovering ? Theme.cardBorder.opacity(0.3) : .clear,
                  in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}

// MARK: Top bar & search

private struct TopBar: View {
  @ObservedObject var state: SettingsState
  let modules: [ModuleSpec]
  @FocusState private var searchFocused: Bool

  var body: some View {
    HStack(spacing: 10) {
      if state.page != .overview {
        Button { state.page = .overview } label: {
          HStack(spacing: 6) {
            Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
            Text("Altools")
          }
          .font(.system(size: 13)).foregroundStyle(Theme.dim)
          .padding(.horizontal, 12).frame(height: 28)
          .overlay(Capsule().strokeBorder(Theme.cardBorder))
        }
        .buttonStyle(.plain)
        Text("/").foregroundStyle(Theme.faint)
      } else {
        Text("Altools").font(.system(size: 13)).foregroundStyle(Theme.dim)
        Text("·").foregroundStyle(Theme.faint)
      }
      HStack(spacing: 6) {
        if case .module(let id) = state.page, let module = modules.first(where: { $0.id == id }) {
          Circle().fill(module.enabled.wrappedValue ? module.tint : .gray).frame(width: 6, height: 6)
        }
        Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.dim)
      }
      .padding(.horizontal, 12).frame(height: 28)
      .background(Theme.card, in: Capsule())
      Spacer()
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.dim)
        TextField("Search", text: $state.search).textFieldStyle(.plain).font(.system(size: 13)).frame(width: 150)
          .focused($searchFocused)
        KeyCapLabel(text: "⌘F")
      }
      .padding(.horizontal, 12).frame(height: 32)
      .background(Theme.card, in: Capsule())
      .overlay(Capsule().strokeBorder(Theme.cardBorder))
      .background(Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden())
    }
    .padding(.leading, 28).padding(.trailing, 22)
    .frame(height: 58)
  }

  private var title: String {
    switch state.page {
    case .overview: "Overview"
    case .module(let id): modules.first { $0.id == id }?.name ?? ""
    case .shortcuts: "Shortcuts"
    case .permissions: "Permissions"
    case .ai: "AI Services"
    case .general: "General"
    case .about: "About"
    }
  }
}

private struct SearchResults: View {
  @ObservedObject var state: SettingsState
  let modules: [ModuleSpec]

  var body: some View {
    let q = state.search.lowercased()
    let matches = modules.flatMap { module in
      module.capabilities.filter {
        $0.title.lowercased().contains(q) || $0.detail.lowercased().contains(q) || $0.key.contains(q) || module.name.lowercased().contains(q)
      }.map { (module, $0) }
    }
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text(matches.isEmpty ? "Nothing matches “\(state.search)”" : "\(matches.count) capabilities")
          .font(.system(size: 13)).foregroundStyle(Theme.dim).padding(.bottom, 6)
        ForEach(matches, id: \.1.id) { module, capability in
          Button { state.open(capability) } label: {
            HStack(spacing: 12) {
              ModuleIcon(module: module, size: 30)
              VStack(alignment: .leading, spacing: 2) {
                Text(capability.title).font(.system(size: 14, weight: .semibold))
                Text(capability.detail).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
              }
              Spacer()
              Text(module.name).font(.system(size: 12)).foregroundStyle(Theme.faint)
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 48).padding(.vertical, 24)
    }
  }
}

// MARK: Overview

private struct OverviewPage: View {
  @ObservedObject var state: SettingsState
  let modules: [ModuleSpec]
  let actions: SettingsActions

  var body: some View {
    let running = modules.filter { $0.enabled.wrappedValue }.count
    let total = modules.reduce(0) { $0 + $1.capabilities.count }
    let live = modules.reduce(0) { $0 + $1.counts(aiFound: state.aiFound).live }
    let on = modules.reduce(0) { $0 + $1.counts(aiFound: state.aiFound).on }
    let shortcuts = HotKeyCenter.shared.bindings.count
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Overview").font(.system(size: 34, weight: .bold))
            Text("Every Altools module and capability, on one screen").font(.system(size: 17)).foregroundStyle(Theme.dim)
          }
          HStack(spacing: 10) {
            stat(running, "/ \(modules.count) modules running")
            Text("•").foregroundStyle(Theme.faint)
            stat(live, "/ \(total) capabilities live")
            Text("•").foregroundStyle(Theme.faint)
            stat(shortcuts, "shortcuts")
          }
          .font(.system(size: 15))
        }
        QuickTiles(actions: actions)
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text("Assembly").font(.system(size: 17, weight: .bold))
            Spacer()
            Text("Click a cell to jump to that capability").font(.system(size: 12)).foregroundStyle(Theme.dim)
          }
          VStack(spacing: 6) {
            ForEach(modules) { module in AssemblyRow(state: state, module: module) }
          }
          HStack(spacing: 18) {
            legend(Theme.accent, "On")
            legend(.clear, "Off", border: Theme.faint)
            legend(.clear, "Blocked", border: .orange)
          }
          .font(.system(size: 12)).foregroundStyle(Theme.dim)
          Rectangle().fill(Theme.cardBorder).frame(height: 1)
          HStack(alignment: .top) {
            bigStat("\(running)", "/\(modules.count)", "modules running")
            bigStat("\(on)", "/\(total)", "capabilities assembled")
            bigStat("\(on - live)", "", "to deal with", tint: on - live > 0 ? Theme.warning : Theme.ink)
          }
        }
        .padding(24)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.cardBorder))
      }
      .padding(.horizontal, 44).padding(.top, 20).padding(.bottom, 32)
    }
  }

  private func stat(_ value: Int, _ label: String) -> some View {
    HStack(spacing: 5) {
      Text("\(value)").fontWeight(.bold)
      Text(label).foregroundStyle(Theme.dim)
    }
  }

  private func bigStat(_ value: String, _ suffix: String, _ label: String, tint: Color = Theme.ink) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text(value).font(.system(size: 30, weight: .bold)).foregroundStyle(tint)
        Text(suffix).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.dim)
      }
      Text(label).font(.system(size: 13)).foregroundStyle(Theme.dim)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func legend(_ fill: Color, _ text: String, border: Color = .clear) -> some View {
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 11, height: 11)
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(border, lineWidth: 1.2))
      Text(text)
    }
  }
}

private struct QuickTiles: View {
  let actions: SettingsActions

  var body: some View {
    HStack(spacing: 0) {
      tile("Area screenshot", "camera.viewfinder", Theme.red, "⌥⇧A", actions.captureArea)
      divider
      tile("Recognize text", "text.viewfinder", Theme.blue, "⌥⇧O", actions.recognizeText)
      divider
      tile("Translate text", "character.bubble.fill", Theme.purple, "⌥⇧S", actions.translate)
      divider
      tile("Colour picker", "eyedropper", Theme.yellow, nil, actions.pickColor)
      divider
      tile("Clipboard", "doc.on.clipboard.fill", Theme.cyan, "⌥⇧V", actions.openClipboard)
    }
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder))
  }

  private var divider: some View { Rectangle().fill(Theme.cardBorder).frame(width: 1, height: 84) }

  private func tile(_ title: String, _ symbol: String, _ tint: Color, _ key: String?, _ action: @escaping () -> Void) -> some View {
    HoverButton(action: action) {
      // Icon and shortcut on top, the name below, so names fit in narrow windows.
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          TonalIcon(symbol: symbol, tint: tint)
          Spacer(minLength: 4)
          if let key { KeyCapLabel(text: key) }
        }
        Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
      }
      .padding(.horizontal, 16).padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct AssemblyRow: View {
  @ObservedObject var state: SettingsState
  let module: ModuleSpec

  var body: some View {
    let counts = module.counts(aiFound: state.aiFound)
    HStack(spacing: 12) {
      Button { state.page = .module(module.id) } label: {
        HStack(spacing: 12) {
          ModuleIcon(module: module, size: 30)
          Text(module.name).font(.system(size: 15, weight: .medium))
            .foregroundStyle(module.enabled.wrappedValue ? Theme.ink : Theme.dim)
          Text("\(counts.live)/\(module.capabilities.count)").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.faint)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Spacer()
      HStack(spacing: 5) {
        ForEach(module.capabilities) { capability in
          let s = module.state(capability, aiFound: state.aiFound)
          Button { state.open(capability) } label: {
            RoundedRectangle(cornerRadius: 4)
              .fill(s == .on ? module.tint.opacity(0.85) : s == .blocked ? Color.clear : module.tint.opacity(0.14))
              .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(s == .blocked ? Theme.warning : .clear, lineWidth: 1.5))
              .frame(width: 18, height: 18)
          }
          .buttonStyle(.plain)
          .help("\(capability.title) — \(s == .on ? "on" : s == .blocked ? "needs \(capability.requirement?.label ?? "setup")" : "off")")
        }
      }
    }
    .frame(height: 44)
  }
}

// MARK: Module page

private struct ModulePage: View {
  @ObservedObject var state: SettingsState
  let module: ModuleSpec

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ModuleHeader(module: module, aiFound: state.aiFound)
          if !module.enabled.wrappedValue {
            HStack(spacing: 12) {
              Image(systemName: "power").font(.system(size: 15)).foregroundStyle(Theme.dim)
              Text("The module is off, so none of these capabilities do anything for now — switch the power on and they come back exactly as they were.")
                .font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
            .padding(.horizontal, 40).padding(.top, 18)
          }
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(module.capabilities.enumerated()), id: \.element.id) { index, capability in
              CapabilityRow(index: index + 1, capability: capability, module: module, aiFound: state.aiFound,
                            highlighted: state.focus == capability.id, isLast: index == module.capabilities.count - 1)
                .id(capability.id)
            }
          }
          .padding(.horizontal, 40).padding(.top, 18).padding(.bottom, 40)
          .opacity(module.enabled.wrappedValue ? 1 : 0.45)
        }
      }
      .onAppear { scroll(proxy) }
      .onChange(of: state.focus) { _, _ in scroll(proxy) }
    }
  }

  private func scroll(_ proxy: ScrollViewProxy) {
    guard let focus = state.focus else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      withAnimation(.snappy) { proxy.scrollTo(focus, anchor: .center) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
      if state.focus == focus { withAnimation { state.focus = nil } }
    }
  }
}

private struct ModuleHeader: View {
  let module: ModuleSpec
  let aiFound: Bool

  var body: some View {
    let counts = module.counts(aiFound: aiFound)
    let on = module.enabled.wrappedValue
    HStack(alignment: .top, spacing: 18) {
      ModuleIcon(module: module, size: 60)
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          Text(module.name).font(.system(size: 26, weight: .semibold))
          HStack(spacing: 5) {
            Circle().fill(on ? Theme.accent : Theme.faint).frame(width: 6, height: 6)
            Text(on ? "Running" : "Off").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.dim)
          }
          .padding(.horizontal, 10).frame(height: 26)
          .background(Theme.iconFill, in: RoundedRectangle(cornerRadius: 7))
        }
        Text(module.tagline).font(.system(size: 15)).foregroundStyle(Theme.dim)
        HStack(spacing: 8) {
          Text("\(module.capabilities.count) capabilities · \(counts.on) on · \(counts.live) live")
            .font(.system(size: 13)).foregroundStyle(Theme.dim)
            .padding(.horizontal, 12).frame(height: 28)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
          ForEach(module.hotkeys, id: \.self) { KeyCapLabel(text: $0) }
        }
        HStack(spacing: 8) {
          Image(systemName: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(Theme.faint)
          Text(module.flow).font(.system(size: 13)).foregroundStyle(Theme.dim)
        }
      }
      Spacer()
      Button { module.enabled.wrappedValue.toggle() } label: {
        Image(systemName: "power").font(.system(size: 24, weight: .semibold))
          .foregroundStyle(on ? module.tint : Theme.dim)
          .frame(width: 64, height: 64)
          .background(on ? module.tint.opacity(0.18) : Theme.iconFill, in: Circle())
          .overlay(Circle().strokeBorder(on ? module.tint.opacity(0.5) : Theme.cardBorder, lineWidth: 1.5))
      }
      .buttonStyle(.plain)
      .help(on ? "Turn \(module.name) off" : "Turn \(module.name) on")
    }
    .padding(.horizontal, 40).padding(.top, 20).padding(.bottom, 22)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Theme.cardBorder).frame(height: 1)
    }
  }
}

private struct CapabilityRow: View {
  let index: Int
  let capability: CapabilitySpec
  let module: ModuleSpec
  let aiFound: Bool
  let highlighted: Bool
  let isLast: Bool

  var body: some View {
    let state = module.state(capability, aiFound: aiFound)
    VStack(alignment: .leading, spacing: 10) {
      header(state)
      if state == .blocked, let requirement = capability.requirement { BlockedNote(requirement: requirement) }
      if let settings = capability.settings { settings.padding(.top, 2) }
    }
    .padding(.horizontal, 18).padding(.vertical, 14)
    .background(highlighted ? Theme.accent.opacity(0.12) : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder))
    .padding(.bottom, 10)
  }

  private func header(_ state: CapabilityState) -> some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(capability.title).font(.system(size: 14, weight: .semibold))
            .foregroundStyle(state == .off ? Theme.dim : Theme.ink)
          if let hotkey = capability.hotkey { KeyCapLabel(text: hotkey) }
        }
        Text(capability.detail).font(.system(size: 12)).foregroundStyle(Theme.dim)
          .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 620, alignment: .leading)
      }
      Spacer(minLength: 12)
      if let value = capability.value {
        Text(value).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
      }
      if let toggle = capability.toggle {
        PillToggle(isOn: toggle, tint: Theme.accent)
      } else {
        HStack(spacing: 5) {
          Image(systemName: "lock").font(.system(size: 10))
          Text("On with the module")
        }
        .font(.system(size: 12)).foregroundStyle(Theme.faint)
      }
    }
  }
}

private struct BlockedNote: View {
  let requirement: Requirement

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
      Text("Needs \(requirement.label)").foregroundStyle(Theme.warning)
      Button(buttonTitle, action: fix)
        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 10).frame(height: 24)
        .background(Theme.warning.opacity(0.18), in: Capsule())
    }
    .font(.system(size: 12))
  }

  private var buttonTitle: String { requirement == .aiCLI ? "Set up" : "Grant" }

  private func fix() {
    switch requirement {
    case .accessibility:
      Permissions.requestAccessibility()
      Permissions.openPrivacyPane("Privacy_Accessibility")
    case .screenRecording:
      Permissions.requestScreenRecording()
      Permissions.openPrivacyPane("Privacy_ScreenCapture")
    case .calendar:
      EKEventStore().requestFullAccessToEvents { _, _ in }
    case .reminders:
      EKEventStore().requestFullAccessToReminders { _, _ in }
    case .aiCLI:
      NSWorkspace.shared.open(URL(string: "https://docs.anthropic.com/en/docs/claude-code")!)
    }
  }
}

// MARK: System pages

private struct PageScaffold<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
          Text(title).font(.system(size: 30, weight: .bold))
          Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.dim)
        }
        content
      }
      .padding(.horizontal, 44).padding(.top, 20).padding(.bottom, 32)
      .frame(maxWidth: 900, alignment: .leading)
    }
  }
}

private struct ShortcutsPage: View {
  var body: some View {
    PageScaffold(title: "Shortcuts", subtitle: "Global keys, available in every app") {
      SettingsCard {
        ForEach(HotKeyCenter.shared.bindings, id: \.title) { binding in
          SettingsRow(binding.title) { KeyCapLabel(text: binding.display, large: true) }
        }
        ForEach(HotKeyCenter.shared.failed, id: \.title) { binding in
          SettingsRow(binding.title, note: "Taken by another app; quit it or change its shortcut.") {
            KeyCapLabel(text: binding.display, large: true).opacity(0.4)
          }
        }
      }
    }
  }
}

private struct PermissionsPage: View {
  var body: some View {
    PageScaffold(title: "Permissions", subtitle: "What macOS lets Altools do") {
      SettingsCard {
        row("Accessibility", "hand.raised.fill", "Read selected text, paste back, notifications in the notch, Caps Lock.",
            granted: Permissions.accessibilityGranted) {
          Permissions.requestAccessibility()
          Permissions.openPrivacyPane("Privacy_Accessibility")
        }
        row("Screen Recording", "rectangle.dashed.badge.record", "Capture other apps' windows in screenshots.",
            granted: Permissions.screenRecordingGranted) {
          Permissions.requestScreenRecording()
          Permissions.openPrivacyPane("Privacy_ScreenCapture")
        }
        row("Calendar", "calendar", "Meeting countdowns and Join in the notch.", granted: Requirement.calendar.isMet(aiFound: true)) {
          EKEventStore().requestFullAccessToEvents { _, _ in }
        }
        row("Reminders", "checklist", "Your to-dos in the notch.", granted: Requirement.reminders.isMet(aiFound: true)) {
          EKEventStore().requestFullAccessToReminders { _, _ in }
        }
        row("Automation", "applescript", "Music and Spotify fallback when the system Now Playing is unavailable.", granted: nil) {
          Permissions.openPrivacyPane("Privacy_Automation")
        }
      }
    }
  }

  private func row(_ title: String, _ symbol: String, _ detail: String, granted: Bool?, action: @escaping () -> Void) -> some View {
    SettingsRow(title, note: detail, symbol: symbol) {
      HStack(spacing: 10) {
        if let granted {
          Text(granted ? "Granted" : "Not granted")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(granted ? .green : .orange)
            .padding(.horizontal, 9).frame(height: 22)
            .background((granted ? Color.green : .orange).opacity(0.14), in: Capsule())
        }
        if granted != true {
          Button("Grant", action: action).buttonStyle(SoftPillButtonStyle())
        }
      }
    }
  }
}

private struct AIServicesPage: View {
  @ObservedObject var settings = AppSettings.shared
  @StateObject private var tester = AIRunner()

  var body: some View {
    PageScaffold(title: "AI Services", subtitle: "The CLI that answers launcher questions and text actions") {
      SettingsCard {
        SettingsRow("Provider") {
          SettingsPicker(selection: $settings.aiProvider, options: AIProvider.allCases.map { ($0, $0.displayName) })
        }
        SettingsRow("Command", note: detected) {
          SettingsTextField(text: settings.aiProvider == .claude ? $settings.claudePath : $settings.codexPath, prompt: "Detect automatically")
        }
        SettingsRow("Model") { SettingsTextField(text: $settings.aiModel, prompt: "CLI default") }
        SettingsRow("Agent tools", note: "Text actions always run without tools, so they stay fast and cheap.") {
          SettingsPicker(selection: $settings.toolPolicy, options: ToolPolicy.allCases.map { ($0, $0.displayName) })
        }
        SettingsRow("Working directory") { SettingsTextField(text: $settings.workDirectory, prompt: "~") }
        SettingsRow("Proxy", note: "Read from your shell's claude alias when empty.") {
          SettingsTextField(text: $settings.proxy, prompt: "http://127.0.0.1:9000")
        }
        SettingsRow("Connection", note: tester.entries.last?.content) {
          Button(tester.isRunning ? "Testing…" : "Test") {
            tester.reset()
            tester.send("Reply with the single word: OK", mode: .quick, showPrompt: false)
          }
          .buttonStyle(SoftPillButtonStyle())
          .disabled(tester.isRunning)
        }
      }
    }
  }

  private var detected: String {
    CLILocator.path(for: settings.aiProvider, configured: settings.binaryPath(for: settings.aiProvider))
      .map { "Using \($0)" } ?? "Not found — install \(settings.aiProvider.displayName) or enter its path"
  }
}

private struct GeneralPage: View {
  let modules: [ModuleSpec]
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?

  var body: some View {
    PageScaffold(title: "General", subtitle: "How Altools starts and runs") {
      SettingsCard {
        SettingsRow("Launch at login", note: loginError) {
          PillToggle(isOn: Binding(get: { launchAtLogin }, set: { on in
            do {
              if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
              loginError = nil
            } catch {
              loginError = error.localizedDescription
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
          }))
        }
        SettingsRow("Everything on", note: "Turns every module on or off at once.") {
          PillToggle(isOn: Binding(get: { modules.allSatisfy { $0.enabled.wrappedValue } },
                                   set: { on in modules.forEach { $0.enabled.wrappedValue = on } }))
        }
      }
    }
  }
}

private struct AboutPage: View {
  var body: some View {
    PageScaffold(title: "About", subtitle: "") {
      HStack(spacing: 18) {
        Image(systemName: "square.grid.3x3.middle.filled").font(.system(size: 30, weight: .semibold))
          .frame(width: 72, height: 72).background(Theme.iconFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        VStack(alignment: .leading, spacing: 6) {
          Text("Altools").font(.system(size: 22, weight: .bold))
          Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
            .foregroundStyle(Theme.dim)
          Text("Launcher, clipboard, selection actions, capture, a notch island and a tidy menu bar — in one menu-bar app.")
            .foregroundStyle(Theme.dim)
        }
      }
    }
  }
}

// MARK: Building blocks

struct ModuleIcon: View {
  let module: ModuleSpec
  let size: CGFloat

  var body: some View {
    TonalIcon(symbol: module.symbol, tint: module.tint, size: size, on: module.enabled.wrappedValue)
  }
}

struct SettingsCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      _VariadicView.Tree(DividedLayout()) { content }
    }
    .padding(.horizontal, 22)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder))
    .frame(maxWidth: 760, alignment: .leading)
  }
}

/// Puts a hairline between the rows of a SettingsCard.
private struct DividedLayout: _VariadicView_MultiViewRoot {
  func body(children: _VariadicView.Children) -> some View {
    let last = children.last?.id
    ForEach(children) { child in
      child
      if child.id != last { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }
  }
}

struct SettingsRow<Control: View>: View {
  let title: String
  var note: String?
  var symbol: String?
  @ViewBuilder let control: Control

  init(_ title: String, note: String? = nil, symbol: String? = nil, @ViewBuilder control: () -> Control) {
    self.title = title
    self.note = note
    self.symbol = symbol
    self.control = control()
  }

  var body: some View {
    HStack(spacing: 14) {
      if let symbol {
        Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.dim).frame(width: 28, height: 28)
          .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 14))
        if let note, !note.isEmpty {
          Text(note).font(.system(size: 12)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 16)
      control
    }
    .padding(.vertical, 14)
  }
}

struct PillToggle: View {
  @Binding var isOn: Bool
  var tint: Color = Theme.accent

  var body: some View {
    Button { withAnimation(.snappy(duration: 0.18)) { isOn.toggle() } } label: {
      ZStack(alignment: isOn ? .trailing : .leading) {
        Capsule().fill(isOn ? tint : Theme.cardBorder).frame(width: 42, height: 24)
        Circle().fill(.white).frame(width: 18, height: 18).padding(3)
          .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
      }
    }
    .buttonStyle(.plain)
  }
}

struct SettingsPicker<Value: Hashable>: View {
  @Binding var selection: Value
  let options: [(Value, String)]

  var body: some View {
    Menu {
      ForEach(options, id: \.0) { value, label in
        Button { selection = value } label: {
          if value == selection { Label(label, systemImage: "checkmark") } else { Text(label) }
        }
      }
    } label: {
      HStack {
        Text(options.first { $0.0 == selection }?.1 ?? "—").font(.system(size: 13))
        Spacer()
        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
      }
      .padding(.horizontal, 12).frame(width: 220, height: 34)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
      .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.cardBorder))
      .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
  }
}

struct SettingsTextField: View {
  @Binding var text: String
  let prompt: String

  var body: some View {
    TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.faint))
      .textFieldStyle(.plain).font(.system(size: 13))
      .padding(.horizontal, 12).frame(width: 260, height: 34)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
      .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.cardBorder))
  }
}

struct KeyCapLabel: View {
  let text: String
  var large = false

  var body: some View {
    Text(text)
      .font(.system(size: large ? 13 : 11, weight: .medium, design: .rounded))
      .foregroundStyle(Theme.dim)
      .padding(.horizontal, large ? 9 : 6).frame(height: large ? 26 : 20)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder))
  }
}

struct SoftPillButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .padding(.horizontal, 14).frame(height: 28)
      .background(Theme.accent.opacity(configuration.isPressed ? 0.6 : 0.85), in: Capsule())
  }
}

private struct HoverButton<Label: View>: View {
  let action: () -> Void
  @ViewBuilder let label: Label
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      label.background(hovering ? Theme.card : .clear).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}


/// Segmented row of icon choices for the menu bar entry.
struct EntryIconPicker: View {
  @Binding var selection: String

  var body: some View {
    HStack(spacing: 2) {
      ForEach(MenuBarHider.EntryIcon.allCases) { icon in
        Button { selection = icon.rawValue } label: {
          Image(systemName: icon.symbol)
            .font(.system(size: icon == .dot ? 6 : 13, weight: .semibold))
            .foregroundStyle(selection == icon.rawValue ? Theme.ink : Theme.dim)
            .frame(width: 38, height: 30)
            .background(selection == icon.rawValue ? Theme.cardBorder : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(3)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
  }
}
