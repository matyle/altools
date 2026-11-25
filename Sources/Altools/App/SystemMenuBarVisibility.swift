import AppKit

/// Hides other apps' menu bar icons through macOS 27's private MenuBarClientCore.
///
/// The menu bar's assessment mode (built for exam lockdowns) keeps only the icons of an
/// allow-list of apps and system items while an assertion is held. Hiding a set of apps
/// means allowing every other running app; an app launched later is hidden until the
/// allow-list is rebuilt, so callers re-apply on launch. Quitting Altools drops the
/// assertion and every icon comes back.
final class SystemMenuBarVisibility {
  private var assertion: NSObject?
  private(set) var hidden: Set<String> = []

  static let isAvailable: Bool = {
    dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW) != nil
      && NSClassFromString("MBAssessmentModeAssertion") != nil
      && NSClassFromString("MBAssessmentModeConfiguration") != nil
  }()

  /// System items stay visible; hiding them would take the clock and Control Center away.
  /// MBSystemItemIdentifier raw values: battery, bluetooth, clock, displays, keyboard,
  /// volume, wifi, screenMirroring, primaryBentoBox (Control Center).
  private static let systemItems = (0...8).map { NSNumber(value: $0) }

  /// Hides the icons of these bundle identifiers; an empty set shows every icon.
  func hide(_ bundleIDs: Set<String>) {
    hidden = bundleIDs
    guard Self.isAvailable, !bundleIDs.isEmpty else { return release() }
    var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).subtracting(bundleIDs)
    if let own = Bundle.main.bundleIdentifier { allowed.insert(own) }
    guard let config = Self.configuration(allowed: Array(allowed)),
          let next = (NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type)?.init() else { return }
    let selector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    typealias Activate = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (NSError?) -> Void) -> Void
    let activate = unsafeBitCast(next.method(for: selector), to: Activate.self)
    let previous = assertion
    assertion = next
    activate(next, selector, config) { error in
      if let error { NSLog("Altools: menu bar assertion failed: \(error)") }
      // The new allow-list is in force before the old one goes, so nothing flickers back.
      DispatchQueue.main.async { previous?.perform(NSSelectorFromString("invalidate")) }
    }
  }

  func release() {
    assertion?.perform(NSSelectorFromString("invalidate"))
    assertion = nil
  }

  private static func configuration(allowed: [String]) -> AnyObject? {
    guard let cls = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
          let blank = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject else { return nil }
    let selector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    typealias Initialize = @convention(c) (AnyObject, Selector, NSArray, NSArray) -> AnyObject
    let initialize = unsafeBitCast(blank.method(for: selector), to: Initialize.self)
    return initialize(blank, selector, systemItems as NSArray, allowed as NSArray)
  }
}

/// An app that currently has icons in the menu bar.
struct MenuBarApp: Identifiable, Equatable {
  var id: String { bundleID }
  let bundleID: String
  let name: String
  let iconCount: Int

  /// Apps with status items, read through Accessibility; Altools and the system's own hosts are left out.
  static func current() -> [MenuBarApp] {
    guard AXIsProcessTrusted() else { return [] }
    let skipped: Set<String> = [Bundle.main.bundleIdentifier ?? "", "com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"]
    return NSWorkspace.shared.runningApplications.compactMap { app -> MenuBarApp? in
      guard let bundleID = app.bundleIdentifier, !skipped.contains(bundleID) else { return nil }
      let element = AXUIElementCreateApplication(app.processIdentifier)
      AXUIElementSetMessagingTimeout(element, 0.3)
      var bar: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success,
            let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
      var count: CFIndex = 0
      // swiftlint:disable:next force_cast
      AXUIElementGetAttributeValueCount(bar as! AXUIElement, kAXChildrenAttribute as CFString, &count)
      guard count > 0 else { return nil }
      return MenuBarApp(bundleID: bundleID, name: app.localizedName ?? bundleID, iconCount: count)
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Frames of this app's icons as Accessibility reports them (Quartz coordinates).
  static func iconFrames(of bundleID: String) -> [CGRect] {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return [] }
    var bar: CFTypeRef?, children: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), "AXExtrasMenuBar" as CFString, &bar) == .success,
          let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
    // swiftlint:disable:next force_cast
    AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children)
    return ((children as? [AXUIElement]) ?? []).map { item in
      var pos: CFTypeRef?, size: CFTypeRef?
      var p = CGPoint.zero, s = CGSize.zero
      // swiftlint:disable force_cast
      if AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &pos) == .success { AXValueGetValue(pos as! AXValue, .cgPoint, &p) }
      if AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success { AXValueGetValue(size as! AXValue, .cgSize, &s) }
      // swiftlint:enable force_cast
      return CGRect(origin: p, size: s)
    }
  }

  static func icon(for bundleID: String) -> NSImage? {
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, let icon = app.icon { return icon }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
  }
}
