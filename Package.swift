// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sixty",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: state machine, call rules, phrases. No AppKit, fully unit-tested.
        .target(name: "SixtyCore"),
        // The menu-bar app: macOS adapters (CoreAudio, CoreMediaIO, idle time) and UI.
        .executableTarget(name: "Sixty", dependencies: ["SixtyCore"]),
        .testTarget(name: "SixtyCoreTests", dependencies: ["SixtyCore"]),
    ]
)
