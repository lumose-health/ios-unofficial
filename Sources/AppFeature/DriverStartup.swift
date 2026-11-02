import Foundation
import DomainCore
@_spi(DriverPlatform) import DriverAPI

public struct DriverStartupOutcome: Sendable, Equatable {
    public let report: RestoreReport
    public let seededID: DriverIdentifier?
    public let seedError: DriverRegistryError?
    /// The first-launch default that was activated or tried, if a seed ran.
    public let seedTarget: DriverIdentifier?

    public init(report: RestoreReport, seededID: DriverIdentifier?, seedError: DriverRegistryError?,
                seedTarget: DriverIdentifier? = nil) {
        self.report = report
        self.seededID = seededID
        self.seedError = seedError
        self.seedTarget = seedTarget ?? seededID
    }
}

public enum DriverStartup {
    public static func run(
        registry: DriverRegistry,
        store: any DriverSelectionStore,
        firstLaunchDefault: DriverIdentifier?
    ) async -> DriverStartupOutcome {
        let report = await registry.restore()
        guard report.selectionFailure == nil,
              !store.hasSavedSelection(),
              await registry.persistedSelection.isEmpty,
              let firstLaunchDefault else {
            return DriverStartupOutcome(report: report, seededID: nil, seedError: nil)
        }
        do {
            try await registry.activate(firstLaunchDefault)
            return DriverStartupOutcome(report: report, seededID: firstLaunchDefault, seedError: nil)
        } catch {
            return DriverStartupOutcome(report: report, seededID: nil, seedError: error, seedTarget: firstLaunchDefault)
        }
    }

    /// Runs restore again after a selection that could not be read yet, such as
    /// before first unlock. It never seeds: the selection file exists, so the
    /// first-launch default must not replace what the user chose.
    public static func retryRestore(registry: DriverRegistry) async -> DriverStartupOutcome {
        DriverStartupOutcome(report: await registry.restore(), seededID: nil, seedError: nil)
    }
}
