// swift-tools-version: 6.0
//
// glycemicgpt-ios-unofficial — package manifest.
//
// This manifest grows one target at a time (AD-2). Today it declares SafetyCore,
// the keystone every later target depends on; DriverAPI, the closed set of
// Capability ports every Driver implements; SimulatedDriver, the first Driver;
// and Persistence, the on-device store. DomainCore, UI and the watch target
// arrive with their own work. Empty scaffolding is deliberately absent — a
// directory that exists before it has an owner invites drift.
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
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    // The workspace's first and only external dependency (AD-6).
    //
    // GRDB UNFORKED, on plain SQLite. At-rest protection comes from iOS Data
    // Protection at `completeUntilFirstUserAuthentication`, not from SQLCipher —
    // which would mean editing GRDB's own manifest, carrying a fork, and managing
    // a passphrase for protection the platform already provides hardware-backed.
    //
    // Pinned EXACTLY, not by range. A store's schema behaviour is the last place
    // to accept a version nobody reviewed: a patch release picked up silently is
    // a migration surprise that reaches a user's health data. Moving the pin is a
    // deliberate change in a PR, with the gates re-run against the new version.
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
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
        // driver boundary is buildable and demonstrable without hardware.
        // Its dependency list is DriverAPI and SafetyCore only,
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
        // The on-device store, and the ONLY target allowed to see GRDB. Keeping
        // the SQL vendor behind one target is what makes it replaceable: a
        // consumer that imports GRDB to build a query has moved storage decisions
        // into a screen, and the manifest test pins that no other target does.
        .target(
            name: "Persistence",
            dependencies: ["SafetyCore", "DriverAPI", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "DriverAPI", "SafetyCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
