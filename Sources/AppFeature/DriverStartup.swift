import Foundation
import DomainCore
@_spi(DriverPlatform) import DriverAPI

public struct DriverStartupOutcome: Sendable, Equatable {
    public let report: RestoreReport
    public let seededID: DriverIdentifier?
    public let seedError: DriverRegistryError?

    public init(report: RestoreReport, seededID: DriverIdentifier?, seedError: DriverRegistryError?) {
        self.report = report
        self.seededID = seededID
        self.seedError = seedError
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
            return DriverStartupOutcome(report: report, seededID: nil, seedError: error)
        }
    }
}
