import AppKit
import SwiftUI

/// What the menu bar panel's buttons do; each closes the panel first.
struct StatusActions {
  var screenshot: () -> Void = {}
  var ocr: () -> Void = {}
  var translate: () -> Void = {}
  var pickColor: () -> Void = {}
  var clipboard: () -> Void = {}
  var settings: () -> Void = {}
  var quit: () -> Void = { NSApp.terminate(nil) }
}

/// The panel under Altools' menu bar icon: quick actions, every module's switch, Pause.
struct StatusPanelView: View {
  @ObservedObject var settings = AppSettings.shared
  let actions: StatusActions
  let close: () -> Void
  @AppStorage("statusPanelModulesExpanded") private var expanded = true

  var body: some View {
    let modules = SettingsCatalog.modules(settings)
    let running = modules.filter { $0.enabled.wrappedValue }.count
    VStack(spacing: 0) {
      header(running: running, total: modules.count)
      actionGrid
      Rectangle().fill(Theme.cardBorder).frame(height: 1)
      Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
        HStack {
          Text("All modules").font(.system(size: 14, weight: .medium))
          Spacer()
          Text("\(running)/\(modules.count)").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.dim)
          Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
            .rotationEffect(.degrees(expanded ? 0 : 180))
        }
        .padding(.horizontal, 18).frame(height: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if expanded {
        Rectangle().fill(Theme.cardBorder).frame(height: 1)
        VStack(spacing: 4) {
          ForEach(modules) { module in
            HStack(spacing: 12) {
              ModuleIcon(module: module, size: 26)
              Text(module.name).font(.system(size: 14))
                .foregroundStyle(module.enabled.wrappedValue ? .white : Theme.dim)
              Spacer()
              PillToggle(isOn: module.enabled)
            }
            .frame(height: 36)
          }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .transition(.opacity)
      }
      Rectangle().fill(Theme.cardBorder).frame(height: 1)
      footer(modules: modules, running: running)
    }
    .frame(width: 340)
    .foregroundStyle(.white)
    .background(Color(hex: 0x14161E))
    .environment(\.colorScheme, .dark)
  }

  private func header(running: Int, total: Int) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "square.grid.3x3.middle.filled")
        .font(.system(size: 14, weight: .semibold))
        .frame(width: 30, height: 30)
        .background(LinearGradient(colors: [Color(hex: 0x6366F1), Color(hex: 0x2DD4BF)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      Text("Altools").font(.system(size: 16, weight: .bold))
      Spacer()
      Circle().fill(running > 0 ? Color.green : .gray).frame(width: 7, height: 7)
      Text("\(running)/\(total)").font(.system(size: 13, weight: .semibold).monospacedDigit())
      Text(running > 0 ? "Running" : "Paused").font(.system(size: 13)).foregroundStyle(Theme.dim)
    }
    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
  }

  private var actionGrid: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Actions").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.faint)
      HStack(spacing: 0) {
        tile("Screenshot", "camera.viewfinder", Color(hex: 0xF97316), actions.screenshot)
        tile("OCR", "text.viewfinder", Color(hex: 0x3B82F6), actions.ocr)
        tile("Translate", "character.bubble.fill", Color(hex: 0x2563EB), actions.translate)
        tile("Colour", "eyedropper", Color(hex: 0xF59E0B), actions.pickColor)
        tile("Clipboard", "doc.on.clipboard.fill", Color(hex: 0xA855F7), actions.clipboard)
      }
    }
    .padding(.horizontal, 18).padding(.bottom, 16)
  }

  private func tile(_ title: String, _ symbol: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
    StatusTile(title: title, symbol: symbol, tint: tint) {
      close()
      // Let the panel close first, so screenshots and pickers don't catch it.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action)
    }
  }

  private func footer(modules: [ModuleSpec], running: Int) -> some View {
    HStack {
      Button { togglePause(modules) } label: {
        Label(running > 0 ? "Pause" : "Resume", systemImage: running > 0 ? "pause.circle" : "play.circle")
          .font(.system(size: 13, weight: .medium))
          .padding(.horizontal, 12).frame(height: 30)
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.14)))
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Spacer()
      iconButton("gearshape", help: "Settings") { close(); actions.settings() }
      iconButton("rectangle.portrait.and.arrow.right", help: "Quit Altools") { actions.quit() }
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
  }

  private func iconButton(_ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.dim)
        .frame(width: 32, height: 30).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  /// Pause turns every module off and remembers which were on; Resume turns those back on.
  private func togglePause(_ modules: [ModuleSpec]) {
    let defaults = UserDefaults.standard
    let on = modules.filter { $0.enabled.wrappedValue }
    if !on.isEmpty {
      defaults.set(on.map(\.id), forKey: "pausedModules")
      on.forEach { $0.enabled.wrappedValue = false }
    } else {
      let saved = Set(defaults.stringArray(forKey: "pausedModules") ?? modules.map(\.id))
      modules.filter { saved.contains($0.id) }.forEach { $0.enabled.wrappedValue = true }
    }
  }
}

private struct StatusTile: View {
  let title: String
  let symbol: String
  let tint: Color
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 7) {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
          .frame(width: 40, height: 40)
          .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .shadow(color: tint.opacity(hovering ? 0.6 : 0.3), radius: hovering ? 8 : 4)
          .scaleEffect(hovering ? 1.06 : 1)
        Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { h in withAnimation(.snappy(duration: 0.15)) { hovering = h } }
  }
}

/// A rounded, arrowless panel that drops down under a status item, like a menu; clicking
/// anywhere else or pressing Esc closes it.
final class MenuBarPanel {
  private let panel: FloatingPanel
  private weak var button: NSStatusBarButton?
  private var outsideMonitor: Any?
  private var measure: () -> NSSize = { NSSize(width: 340, height: 480) }
  var onShow: (() -> Void)?
  var onClose: (() -> Void)?

  init<Content: View>(button: NSStatusBarButton?, @ViewBuilder content: (_ close: @escaping () -> Void) -> Content) {
    self.button = button
    panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 400))
    panel.level = .popUpMenu
    var closeHandler: () -> Void = {}
    let view = content({ closeHandler() })
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
    panel.setRoot(view)
    // The panel's hosting view doesn't report a fitting size, so a separate one measures the content.
    measure = { NSHostingView(rootView: view).fittingSize }
    panel.onResignKey = { [weak self] in self?.close() }
    panel.onEscape = { [weak self] in self?.close() }
    closeHandler = { [weak self] in self?.close() }
  }

  var isVisible: Bool { panel.isVisible }

  func toggle() {
    panel.isVisible ? close() : show()
  }

  func show() {
    guard let button, let buttonWindow = button.window else { return }
    onShow?()
    let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    let size = measure()
    let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    // Right-aligned under the icon like a menu, kept on screen.
    var x = anchor.maxX - size.width + 12
    x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
    panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 6, width: size.width, height: size.height), display: true)
    panel.makeKeyAndOrderFront(nil)
    outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
  }

  func close() {
    guard panel.isVisible else { return }
    panel.orderOut(nil)
    if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
    outsideMonitor = nil
    onClose?()
  }
}

/// The panel under Altools' own menu bar icon.
final class StatusPanelController {
  private let panel: MenuBarPanel

  init(button: NSStatusBarButton?, actions: StatusActions) {
    panel = MenuBarPanel(button: button) { close in StatusPanelView(actions: actions, close: close) }
  }

  func toggle() { panel.toggle() }
}
