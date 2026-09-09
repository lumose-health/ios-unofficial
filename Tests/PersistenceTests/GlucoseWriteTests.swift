import Foundation
import DriverAPI
import SafetyCore
import Testing
@testable import Persistence

/// The absolute bound is enforced where the row is written (FR-138, AD-5).
///
/// Not narrowed, not clamped, not asserted: the write path builds a
/// ``SafetyCore/Glucose``, whose initializer already refuses, and the store never
/// spells the bound itself — it has one definition site and this is not it.
@Suite("Glucose write path")
struct GlucoseWriteTests {

    private let clock = FixedClock(now: instant())

    private func makeStore() throws -> LocalStore {
        try LocalStore.inMemory(clock: clock)
    }

    @Test("A value just under the lower bound is refused")
    func refusesJustBelowTheLowerBound() async throws {
        let store = try makeStore()
        let failure = await #expect(throws: PersistenceFailure.self) {
            try await store.recordGlucose(mgdl: 19.9, recordedAt: instant(), from: try source("pump"))
        }
        #expect(failure == .glucoseRejected(.outOfRange(mgdl: 19.9)))
        #expect(try await store.glucoseReadings().isEmpty)
    }

    @Test("A value just over the upper bound is refused")
    func refusesJustAboveTheUpperBound() async throws {
        let store = try makeStore()
        let failure = await #expect(throws: PersistenceFailure.self) {
            try await store.recordGlucose(mgdl: 500.1, recordedAt: instant(), from: try source("pump"))
        }
        #expect(failure == .glucoseRejected(.outOfRange(mgdl: 500.1)))
        #expect(try await store.glucoseReadings().isEmpty)
    }

    /// Both bounds are inclusive. An exclusive upper bound would silently make 500
    /// unstorable, which is the classic way a safety bound drifts by one.
    @Test("Both bounds themselves are stored", arguments: [20.0, 500.0])
    func acceptsTheBoundsThemselves(mgdl: Double) async throws {
        let store = try makeStore()
        try await store.recordGlucose(mgdl: mgdl, recordedAt: instant(), from: try source("pump"))
        let stored = try await store.glucoseReadings()
        #expect(stored.map(\.sample.glucose.mgdl) == [mgdl])
    }

    /// A non-finite value is a different kind of wrong from an out-of-range one —
    /// a decode or arithmetic artefact rather than a plausible number the bound
    /// rejects — and the refusal says which.
    @Test("A non-finite value is refused as a distinct kind of wrong",
          arguments: [Double.nan, .infinity, -.infinity])
    func refusesNonFiniteValues(mgdl: Double) async throws {
        let store = try makeStore()
        let failure = await #expect(throws: PersistenceFailure.self) {
            try await store.recordGlucose(mgdl: mgdl, recordedAt: instant(), from: try source("pump"))
        }
        #expect(failure == .glucoseRejected(.notFinite))
        #expect(try await store.glucoseReadings().isEmpty)
    }

    /// The refusal is a value the caller can branch on. A crash would take the app
    /// down over data it does not control, and a clamp would put a number on a
    /// screen that no sensor produced.
    @Test("The refusal is a typed error, and the store is still usable after it")
    func refusalIsRecoverable() async throws {
        let store = try makeStore()
        await #expect(throws: PersistenceFailure.self) {
            try await store.recordGlucose(mgdl: 900, recordedAt: instant(), from: try source("pump"))
        }
        try await store.recordGlucose(mgdl: 120, recordedAt: instant(), from: try source("pump"))
        #expect(try await store.glucoseReadings().map(\.sample.glucose.mgdl) == [120])
    }

    /// The bound is in the SCHEMA as well, which is the version of it that holds
    /// against a writer that is not this code. Nothing in the package can produce
    /// this row — the test opens the file the way another program would.
    @Test("The column itself refuses an out-of-bound value", arguments: [19.9, 500.1, 1000.0])
    func theSchemaRefusesAnOutOfBoundValue(mgdl: Double) async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
        let file = RawSQLiteFile(location.databaseURL)

        let refusal = #expect(throws: RawSQLiteFile.Refused.self) {
            try file.execute("""
                INSERT INTO glucose_reading (recorded_at, mgdl, trend, source)
                VALUES (\(instant().timeIntervalSince1970), \(mgdl), NULL, 'elsewhere')
                """)
        }
        #expect(refusal?.message.contains("CHECK") == true, "expected a CHECK refusal, got \(refusal as Any)")
        #expect(try await store.glucoseReadings().isEmpty)
    }

    /// The row the CHECK exists to stop, forced into the file anyway — SQLite lets
    /// a connection ignore check constraints, and a program that is not this one
    /// could have written the table before the constraint existed at all.
    ///
    /// Reads reconstruct `Glucose`, so the answer is the same typed refusal rather
    /// than a reading on a screen: the bound holds at the write, in the schema, and
    /// again on the way out.
    @Test("A row that got past the schema is still refused on the way out")
    func readRefusesATamperedRow() async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
        try RawSQLiteFile(location.databaseURL).execute("""
            PRAGMA ignore_check_constraints = ON;
            INSERT INTO glucose_reading (recorded_at, mgdl, trend, source)
            VALUES (\(instant().timeIntervalSince1970), 1000.0, NULL, 'elsewhere');
            """)

        let failure = await #expect(throws: PersistenceFailure.self) {
            _ = try await store.glucoseReadings()
        }
        #expect(failure == .glucoseRejected(.outOfRange(mgdl: 1000)))
    }

    /// The two assertions above stand on the raw connection actually reaching the
    /// store's file. One that silently wrote nowhere would make both of them pass
    /// against an empty table.
    @Test("The raw connection writes to the same file the store reads")
    func rawConnectionReachesTheStoresFile() async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
        try RawSQLiteFile(location.databaseURL).execute("""
            INSERT INTO glucose_reading (recorded_at, mgdl, trend, source)
            VALUES (\(instant().timeIntervalSince1970), 120.0, NULL, 'elsewhere')
            """)

        let stored = try await store.glucoseReadings()
        #expect(stored.map(\.sample.glucose.mgdl) == [120])
        #expect(stored.first?.source == (try source("elsewhere")))
    }

    @Test("A reading round-trips with its instant, trend and source")
    func roundTripsEveryField() async throws {
        let store = try makeStore()
        let pump = try source("pump")
        let written = try sample(137, at: instant(90), trend: .risingSlowly)
        try await store.record(written, from: pump)

        let stored = try #require(try await store.glucoseReadings().first)
        #expect(stored.sample == written)
        #expect(stored.source == pump)
    }

    /// A trend this build's vocabulary does not name is what `unknown` is for: the
    /// sensor reported a direction and this is not one we can draw. It is not a
    /// reason to refuse the reading, which is the part that matters.
    @Test("A reading with no trend round-trips as having none")
    func roundTripsAMissingTrend() async throws {
        let store = try makeStore()
        try await store.record(try sample(101, at: instant()), from: try source("pump"))
        #expect(try await store.glucoseReadings().first?.sample.trend == nil)
    }

    @Test("Readings come back oldest first, and `since` is inclusive")
    func readsAreOrderedAndFiltered() async throws {
        let store = try makeStore()
        for offset in [0.0, 60.0, 120.0] {
            try await store.record(try sample(100 + offset, at: instant(offset)), from: try source("pump"))
        }

        let all = try await store.glucoseReadings()
        #expect(all.map(\.sample.recordedAt) == [instant(0), instant(60), instant(120)])

        let recent = try await store.glucoseReadings(since: instant(60))
        #expect(recent.map(\.sample.recordedAt) == [instant(60), instant(120)])
    }
}
