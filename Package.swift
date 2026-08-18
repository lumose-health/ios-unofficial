// swift-tools-version: 6.0
//
// glycemicgpt-ios-unofficial — package manifest.
//
// This manifest grows one target per story (AD-2). Today it declares SafetyCore,
// the keystone every later target depends on, and DriverAPI, the closed set of
// Capability ports every Driver implements; Drivers, DomainCore, UI and the watch
// target arrive with their own stories. Empty scaffolding is deliberately absent —
// a directory that exists before it has an owner invites drift.
//
// macOS is present so `swift build` / `swift test` run host-side in CI and on a
// dev machine without a simulator. iOS 17 / watchOS 10 are the shipping floors.
//
// Swift 6 language mode is set explicitly on every target. It implies COMPLETE
// strict-concurrency checking — data-race safety is enforced by the compiler, not
// requested by a separate flag — so `.swiftLanguageMode(.v6)` is the whole of that
// requirement and an extra `StrictConcurrency` upcoming-feature flag would be a
// no-op restating it.

import PackageDescription

let package = Package(
    name: "GlycemicGPT",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SafetyCore", targets: ["SafetyCore"]),
        .library(name: "DriverAPI", targets: ["DriverAPI"]),
        .library(name: "SimulatedDriver", targets: ["SimulatedDriver"]),
    ],
    targets: [
        // SafetyCore has ZERO dependencies and must keep them (AD-3): it sits at
        // the bottom of the one-way dependency direction, so anything it imports
        // becomes a transitive dependency of every surface in the app.
        .target(
            name: "SafetyCore",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SafetyCoreTests",
            dependencies: ["SafetyCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // DriverAPI depends on SafetyCore and NOTHING else (AD-3). It is the layer
        // every Driver is allowed to see, so a dependency added here is a
        // dependency every Driver inherits — including the vendor targets that
        // must not acquire their own storage or network path.
        .target(
            name: "DriverAPI",
            dependencies: ["SafetyCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DriverAPITests",
            dependencies: ["DriverAPI", "SafetyCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The first Driver: no device, no network, so everything above the
        // driver boundary is buildable and demonstrable without hardware
        // (story 1.5). Its dependency list is DriverAPI and SafetyCore only,
        // the same ceiling every Driver is held to (AD-3), and its directory
        // sits under Sources/Drivers/ so scripts/guards/driver_guards.sh's
        // catalog-completeness rule now runs against a real target.
        .target(
            name: "SimulatedDriver",
            dependencies: ["DriverAPI", "SafetyCore"],
            path: "Sources/Drivers/Simulated",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SimulatedDriverTests",
            dependencies: ["SimulatedDriver", "DriverAPI", "SafetyCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
