import Foundation
import DriverAPI
import SafetyCore
import Testing
@testable import Persistence

/// The retention window and the sweep that applies it (FR-139).
@Suite("Retention")
struct RetentionTests {

    // MARK: - The window itself

    @Test("The default window is seven days")
    func defaultIsSevenDays() {
        #expect(RetentionWindow.default.days == 7)
        #expect(RetentionWindow.default.days == RetentionWindow.defaultDays)
    }

    @Test("Both ends of the settable range are accepted", arguments: [1, 7, 30])
    func acceptsTheSettableRange(days: Int) throws {
        #expect(try RetentionWindow(days: days).days == days)
    }

    /// A window is set on a settings screen, which is where an out-of-range number
    /// arrives. Clamping would quietly keep data the user asked to drop, or drop
    /// data they asked to keep, and never say so.
    @Test("A window outside the range is refused, not clamped", arguments: [0, -1, 31, 365])
    func refusesOutsideTheRange(days: Int) {
        let failure = #expect(throws: PersistenceFailure.self) {
            _ = try RetentionWindow(days: days)
        }
        #expect(failure == .retentionOutOfRange(days: days))
    }

    /// Elapsed time, not calendar days: a calendar answer depends on a time zone
    /// and on daylight saving, so the same sweep would take a different set of
    /// rows depending on where the phone was.
    @Test("A window's duration is whole days of elapsed time")
    func durationIsElapsedTime() throws {
        #expect(try RetentionWindow(days: 3).duration == 3 * oneDay)
    }

    // MARK: - The sweep

    /// Strictly older. A row sitting exactly on the horizon is kept, so a sweep
    /// run twice in the same instant does not take a different set the second
    /// time.
    @Test("The sweep takes rows older than the horizon and leaves the rest")
    func sweepRemovesOnlyExpiredRows() async throws {
        let now = instant()
        let store = try LocalStore.inMemory(clock: FixedClock(now: now))
        let pump = try source("pump")

        let expired = now.addingTimeInterval(-8 * oneDay)
        let onTheHorizon = now.addingTimeInterval(-7 * oneDay)
        let fresh = now.addingTimeInterval(-oneDay)
        for recordedAt in [expired, onTheHorizon, fresh] {
            try await store.record(try sample(120, at: recordedAt), from: pump)
        }

        let deleted = try await store.sweepExpiredRecords()
        #expect(deleted == 1)
        #expect(try await store.glucoseReadings().map(\.sample.recordedAt) == [onTheHorizon, fresh])
    }

    /// The sweep is the store's, not one table's. A partial sweep would leave a
    /// history whose pieces disagree about how far back they go.
    ///
    /// One expired row per table, so the count taken is the number of tables the
    /// sweep names — a table added to that list without being written here fails
    /// this, which is the right way round.
    @Test("The sweep bounds every table the store owns")
    func sweepCoversEveryTable() async throws {
        let now = instant()
        let store = try LocalStore.inMemory(clock: FixedClock(now: now))
        let pump = try source("pump")
        let expired = now.addingTimeInterval(-8 * oneDay)
        let fresh = now.addingTimeInterval(-oneDay)

        for recordedAt in [expired, fresh] {
            try await store.record(try sample(120, at: recordedAt), from: pump)
            try await store.record(try snapshot(battery: 0.5, at: recordedAt), from: pump)
            try await store.record(try dose(2.5, at: recordedAt), from: pump)
            try await store.record(
                RawPumpHistoryRecord(
                    source: pump,
                    sequenceNumber: Int64(recordedAt.timeIntervalSince1970),
                    recordedAt: recordedAt,
                    eventTypeIdentifier: 3,
                    payload: Data([0x01])
                )
            )
        }

        let deleted = try await store.sweepExpiredRecords()
        #expect(deleted == StoreSchema.retainedTables.count)
        #expect(try await store.glucoseReadings().count == 1)
        #expect(try await store.pumpStatuses().count == 1)
        #expect(try await store.insulinDoses().count == 1)
        #expect(try await store.rawPumpHistory().count == 1)
    }

    /// A shorter window takes more. The horizon comes from the injected clock, so
    /// this is a value the test wrote rather than one it waited for (AD-14).
    @Test("A narrower window takes more rows")
    func windowChangesWhatTheSweepTakes() async throws {
        let now = instant()
        let store = try LocalStore.inMemory(clock: FixedClock(now: now))
        let pump = try source("pump")
        for age in [2.0, 5.0, 9.0] {
            try await store.record(try sample(120, at: now.addingTimeInterval(-age * oneDay)), from: pump)
        }

        #expect(try await store.sweepExpiredRecords(retaining: try RetentionWindow(days: 3)) == 2)
        #expect(try await store.glucoseReadings().count == 1)
    }

    @Test("A sweep with nothing to take reports nothing taken")
    func sweepOnAFreshStoreTakesNothing() async throws {
        let store = try LocalStore.inMemory(clock: FixedClock(now: instant()))
        #expect(try await store.sweepExpiredRecords() == 0)
    }
}
