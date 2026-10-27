// swift-tools-version: 5.9
import PackageDescription

// Native macOS utility: Apple Vision + AVFoundation, no external dependencies.
let package = Package(
    name: "GestureMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GestureMac", targets: ["GestureMac"]),
        .executable(name: "GestureCoreChecks", targets: ["GestureCoreChecks"]),
        .library(name: "GestureCore", targets: ["GestureCore"])
    ],
    targets: [
        .target(name: "GestureCore"),
        .executableTarget(name: "GestureMac", dependencies: ["GestureCore"]),
        // CLT-only Macs do not include XCTest. The deterministic checks are a
        // dependency-free executable, so users do not need the full Xcode app.
        .executableTarget(name: "GestureCoreChecks", dependencies: ["GestureCore"], path: "Tests/GestureCoreTests")
    ],
    swiftLanguageVersions: [.v5]
)
