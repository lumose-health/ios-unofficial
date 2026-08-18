import Foundation

/// Every Driver compiled into this build, listed at compile time (FR-22, AD-12).
///
/// ## Why a list and not a registry
///
/// Android discovers plugins at runtime. This does not, and the difference is the
/// design: `entries` is a `static let` on a caseless enum, so there is no
/// `register(_:)`, no bundle scan, no dynamic load, and no order of initialisation
/// that decides what the app can do. What ships is visible in this file, in the
/// diff, before the build.
///
/// That closes a specific hole. A runtime registration path is a place a
/// Capability can appear that no reviewer saw, and AD-17 requires composition to
/// be SUBTRACTIVE only: a build configuration may exclude a Driver, never add
/// one. Nothing here reads a build flag — exclusion happens by removing an entry
/// and its target together, in one change.
///
/// ## The first entry
///
/// `SimulatedDriver` is the first Driver to ship, and the first
/// registration here: `scripts/guards/driver_guards.sh` fails when a target
/// under `Sources/Drivers/` has no entry here, and when an entry names a
/// target the manifest does not declare.
public enum DriverCatalog {

    /// The Drivers in this build.
    ///
    /// A `let`, not a `var`: the catalog is not mutable at runtime, by anyone,
    /// including tests. A test that needs a Driver builds its own
    /// ``DriverDescriptor`` — it does not add one here, because a catalog a test
    /// can mutate is a catalog production code can mutate.
    public static let entries: [DriverDescriptor] = [
        DriverDescriptor(
            identifier: DriverIdentifier("com.glycemicgpt.simulated")!,
            targetName: "SimulatedDriver",
            displayName: "Simulated Driver",
            transport: .inProcess,
            version: "1.0.0",
            capabilities: [.glucoseSource, .insulinSource],
            verification: .unverified
        ),
    ]

    /// The entry with this identifier, or `nil`.
    public static func entry(for identifier: DriverIdentifier) -> DriverDescriptor? {
        entries.first { $0.identifier == identifier }
    }

    /// Every entry that claims `capability`, in catalog order.
    public static func entries(providing capability: Capability) -> [DriverDescriptor] {
        entries.filter { $0.capabilities.contains(capability) }
    }
}
