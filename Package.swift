// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Altools",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Altools", targets: ["Altools"]),
    // The built-in Battery plugin's program; build-app.sh puts it in Resources/BuiltinPlugins/battery.
    .executable(name: "altools-battery", targets: ["altools-battery"]),
  ],
  targets: [
    // Pure logic with no AppKit dependency, so it can be unit-tested.
    .target(name: "AltoolsCore"),
    .executableTarget(
      name: "Altools",
      dependencies: ["AltoolsCore"],
      linkerSettings: [
        .linkedFramework("Carbon"),
        .linkedFramework("IOKit"),
        .linkedFramework("Vision"),
        .linkedFramework("EventKit"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("CoreMediaIO"),
        .linkedFramework("CoreWLAN"),
        .linkedFramework("SystemConfiguration"),
      ]
    ),
    .target(name: "BatteryMonitor"),
    .executableTarget(name: "altools-battery", dependencies: ["BatteryMonitor"], linkerSettings: [.linkedFramework("IOKit")]),
    .testTarget(name: "AltoolsCoreTests", dependencies: ["AltoolsCore"]),
    .testTarget(name: "BatteryMonitorTests", dependencies: ["BatteryMonitor", "AltoolsCore"]),
  ],
  swiftLanguageModes: [.v5]
)
