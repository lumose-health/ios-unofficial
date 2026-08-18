import Foundation
import SafetyCore
import Testing
@testable import Persistence

/// The schema is versioned, forward-only, and starts at v1 (AD-6).
@Suite("Store schema and migrations")
struct StoreSchemaTests {

    private let clock = FixedClock(now: instant())

    @Test("A store this build creates is at v1")
    func schemaStartsAtVersionOne() async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
        #expect(try await store.appliedMigrationIdentifiers() == ["v1"])
    }

    /// Opening is what runs migrations, and an app opens its store on every
    /// launch. A second open that re-ran v1 would recreate the tables it holds.
    @Test("Re-opening an existing store changes nothing")
    func openingIsIdempotent() async throws {
        let location = TemporaryStoreLocation()
        let reading = try sample(120, at: instant())

        do {
            let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
            try await store.record(reading, from: try source("pump"))
        }

        let reopened = try await LocalStore.open(at: location.databaseURL, clock: clock)
        #expect(try await reopened.appliedMigrationIdentifiers() == ["v1"])
        let stored = try await reopened.glucoseReadings()
        #expect(stored.count == 1)
        #expect(stored.first?.sample == reading)
    }

    /// Migrations run forward only. A file carrying a migration this build does
    /// not know was written by a newer app, and the older schema has no way to
    /// read columns whose meaning it does not have — so it refuses rather than
    /// opening and guessing.
    @Test("A file written by a newer build is refused, not downgraded")
    func refusesAFileFromANewerBuild() async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
        try await store.stampForeignMigration("v2")

        let failure = await #expect(throws: PersistenceFailure.self) {
            _ = try await LocalStore.open(at: location.databaseURL, clock: clock)
        }
        #expect(failure == .schemaFromNewerVersion(applied: ["v1", "v2"]))
    }

    /// v1 creates the four tables this work needs and no others: alert history,
    /// an outbound queue and meals arrive with the work that writes them.
    @Test("v1 creates exactly the tables the store owns")
    func schemaHoldsTheDeclaredTables() async throws {
        let store = try LocalStore.inMemory(clock: clock)
        #expect(
            try await store.tableNames()
                == ["glucose_reading", "insulin_dose", "pump_status", "raw_pump_history"]
        )
    }

    /// The rule that keeps retention honest as tables are added: every table in
    /// the file is named by the sweep's list. A table that escapes the sweep grows
    /// forever, and nothing else would say so.
    @Test("Every table in the file is bounded by the retention sweep")
    func everyTableIsSwept() async throws {
        let store = try LocalStore.inMemory(clock: clock)
        let inFile = Set(try await store.tableNames())
        let swept = Set(StoreSchema.retainedTables.map(\.name))
        #expect(inFile == swept, "tables not covered by the sweep: \(inFile.subtracting(swept))")
    }
}
