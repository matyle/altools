// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Altools",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Altools", targets: ["Altools"]),
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
    .testTarget(name: "AltoolsCoreTests", dependencies: ["AltoolsCore"]),
  ],
  swiftLanguageModes: [.v5]
)
