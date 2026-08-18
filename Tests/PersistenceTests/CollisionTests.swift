import Foundation
import DriverAPI
import SafetyCore
import Testing
@testable import Persistence

/// Uniqueness and collision resolution at the write (FR-137).
///
/// The property under test throughout is that the same records, fed in any order,
/// leave the same database. A backfill that overlaps a previous one, or a live
/// poll racing a cloud sync, must not give two users different histories.
@Suite("Write-time uniqueness and collisions")
struct CollisionTests {

    private let clock = FixedClock(now: instant())

    private func makeStore(order: [String] = []) throws -> LocalStore {
        let precedence = order.isEmpty
            ? SourcePrecedence.unranked
            : try SourcePrecedence(order: order.map { try StoreSource($0) })
        return try LocalStore.inMemory(clock: clock, precedence: precedence)
    }

    // MARK: - One reading per instant

    @Test("Two readings at the same instant leave one row")
    func atMostOneReadingPerInstant() async throws {
        let store = try makeStore(order: ["pump", "cloud"])
        try await store.record(try sample(120, at: instant()), from: try source("pump"))
        try await store.record(try sample(180, at: instant()), from: try source("cloud"))

        #expect(try await store.glucoseReadings().count == 1)
    }

    /// The replay case, and the reason a backfill can be re-run freely: the same
    /// record written twice is not new information and is not an error.
    @Test("Re-writing the identical reading is a no-op")
    func replayingARecordIsANoOp() async throws {
        let store = try makeStore()
        let reading = try sample(120, at: instant())
        try await store.record(reading, from: try source("pump"))
        try await store.record(reading, from: try source("pump"))

        #expect(try await store.glucoseReadings().map(\.sample) == [reading])
    }

    /// Precedence cannot break this tie — the two candidates have identical
    /// standing — and choosing by arrival order would make the stored value depend
    /// on the order a replay happened to run in. So the store hands it back.
    @Test("One source contradicting itself is refused, not resolved")
    func sameSourceContradictionIsRefused() async throws {
        let store = try makeStore()
        try await store.record(try sample(120, at: instant()), from: try source("pump"))

        let failure = await #expect(throws: PersistenceFailure.self) {
            try await store.record(try sample(180, at: instant()), from: try source("pump"))
        }
        guard case .conflictingRecord = failure else {
            Issue.record("expected a conflict, got \(String(describing: failure))")
            return
        }
        #expect(try await store.glucoseReadings().map(\.sample.glucose.mgdl) == [120])
    }

    // MARK: - Cross-source precedence

    /// The ordered rule, and the property it exists for: the winner is the same
    /// whichever row arrived first.
    @Test("The higher-precedence source wins regardless of arrival order",
          arguments: [false, true])
    func precedenceIsIndependentOfArrivalOrder(cloudFirst: Bool) async throws {
        let store = try makeStore(order: ["pump", "cloud"])
        let fromPump = try sample(120, at: instant())
        let fromCloud = try sample(180, at: instant())

        if cloudFirst {
            try await store.record(fromCloud, from: try source("cloud"))
            try await store.record(fromPump, from: try source("pump"))
        } else {
            try await store.record(fromPump, from: try source("pump"))
            try await store.record(fromCloud, from: try source("cloud"))
        }

        let stored = try #require(try await store.glucoseReadings().first)
        #expect(stored.sample == fromPump)
        #expect(stored.source == (try source("pump")))
    }

    /// A source the precedence list does not name ranks after every source it
    /// does, so shipping a new Driver cannot displace a configured one until
    /// somebody says it should.
    @Test("An unlisted source never displaces a listed one", arguments: [false, true])
    func unlistedSourcesRankLast(unlistedFirst: Bool) async throws {
        let store = try makeStore(order: ["cloud"])
        let fromCloud = try sample(120, at: instant())
        let fromMeter = try sample(180, at: instant())

        if unlistedFirst {
            try await store.record(fromMeter, from: try source("meter"))
            try await store.record(fromCloud, from: try source("cloud"))
        } else {
            try await store.record(fromCloud, from: try source("cloud"))
            try await store.record(fromMeter, from: try source("meter"))
        }

        #expect(try await store.glucoseReadings().first?.source == (try source("cloud")))
    }

    /// Two sources nobody has ranked still have to resolve to something, and it
    /// must not be "whichever wrote first" — that is the property replay stability
    /// depends on. The identifier decides.
    @Test("Two unranked sources resolve on the identifier", arguments: [false, true])
    func unrankedSourcesResolveLexicographically(zebraFirst: Bool) async throws {
        let store = try makeStore()
        let fromAlpha = try sample(120, at: instant())
        let fromZebra = try sample(180, at: instant())

        if zebraFirst {
            try await store.record(fromZebra, from: try source("zebra"))
            try await store.record(fromAlpha, from: try source("alpha"))
        } else {
            try await store.record(fromAlpha, from: try source("alpha"))
            try await store.record(fromZebra, from: try source("zebra"))
        }

        let stored = try #require(try await store.glucoseReadings().first)
        #expect(stored.source == (try source("alpha")))
        #expect(stored.sample == fromAlpha)
    }

    // MARK: - Pump status

    /// The same permutation property readings get: one row per instant, and the
    /// same winner whichever arrived first.
    @Test("One pump-status row survives per instant, resolved the same way",
          arguments: [false, true])
    func pumpStatusFollowsTheSameRule(cloudFirst: Bool) async throws {
        let store = try makeStore(order: ["pump", "cloud"])
        let fromPump = try snapshot(battery: 0.75, at: instant())
        let fromCloud = try snapshot(battery: 0.25, at: instant())

        if cloudFirst {
            try await store.record(fromCloud, from: try source("cloud"))
            try await store.record(fromPump, from: try source("pump"))
        } else {
            try await store.record(fromPump, from: try source("pump"))
            try await store.record(fromCloud, from: try source("cloud"))
        }

        let stored = try await store.pumpStatuses()
        #expect(stored.count == 1)
        #expect(stored.first?.snapshot == fromPump)
        #expect(stored.first?.source == (try source("pump")))
    }

    @Test("An unlisted source never displaces a listed one for pump status",
          arguments: [false, true])
    func pumpStatusUnlistedSourcesRankLast(unlistedFirst: Bool) async throws {
        let store = try makeStore(order: ["cloud"])
        let fromCloud = try snapshot(battery: 0.25, at: instant())
        let fromBridge = try snapshot(battery: 0.75, at: instant())

        if unlistedFirst {
            try await store.record(fromBridge, from: try source("bridge"))
            try await store.record(fromCloud, from: try source("cloud"))
        } else {
            try await store.record(fromCloud, from: try source("cloud"))
            try await store.record(fromBridge, from: try source("bridge"))
        }

        let stored = try await store.pumpStatuses()
        #expect(stored.map(\.source) == [try source("cloud")])
        #expect(stored.first?.snapshot == fromCloud)
    }

    @Test("Two unranked sources resolve pump status on the identifier",
          arguments: [false, true])
    func pumpStatusUnrankedSourcesResolveLexicographically(zebraFirst: Bool) async throws {
        let store = try makeStore()
        let fromAlpha = try snapshot(battery: 0.25, at: instant())
        let fromZebra = try snapshot(battery: 0.75, at: instant())

        if zebraFirst {
            try await store.record(fromZebra, from: try source("zebra"))
            try await store.record(fromAlpha, from: try source("alpha"))
        } else {
            try await store.record(fromAlpha, from: try source("alpha"))
            try await store.record(fromZebra, from: try source("zebra"))
        }

        let stored = try await store.pumpStatuses()
        #expect(stored.map(\.source) == [try source("alpha")])
        #expect(stored.first?.snapshot == fromAlpha)
    }

    @Test("A pump contradicting its own snapshot is refused")
    func pumpStatusSameSourceContradiction() async throws {
        let store = try makeStore()
        try await store.record(try snapshot(battery: 0.25, at: instant()), from: try source("pump"))

        let failure = await #expect(throws: PersistenceFailure.self) {
            try await store.record(try snapshot(battery: 0.75, at: instant()), from: try source("pump"))
        }
        guard case .conflictingRecord = failure else {
            Issue.record("expected a conflict, got \(String(describing: failure))")
            return
        }
        #expect(try await store.pumpStatuses().map(\.snapshot.batteryFraction) == [0.25])
    }

    @Test("An identical pump-status snapshot re-writes as a no-op")
    func pumpStatusReplayIsANoOp() async throws {
        let store = try makeStore()
        let observed = try snapshot(battery: 0.25, at: instant())
        try await store.record(observed, from: try source("pump"))
        try await store.record(observed, from: try source("pump"))

        #expect(try await store.pumpStatuses().count == 1)
    }

    @Test("A pump-status snapshot round-trips its hardware identity")
    func pumpStatusRoundTripsHardware() async throws {
        let store = try makeStore()
        let observed = try PumpStatusSnapshot(
            batteryFraction: 0.5,
            reservoirUnits: 42,
            hardware: PumpHardwareInfo(modelName: "t:slim X2", firmwareVersion: "7.6"),
            observedAt: instant()
        )
        try await store.record(observed, from: try source("pump"))

        #expect(try await store.pumpStatuses().first?.snapshot == observed)
    }

    // MARK: - Insulin deliveries

    /// The invariant the insulin table actually carries: one delivery per CATEGORY
    /// per instant.
    ///
    /// A pump runs basal continuously and puts boluses on top of it, so a basal
    /// segment and a meal bolus finishing on the same tick are two real deliveries —
    /// exactly what `SimulatedDriver` emits when its hourly basal segment lands on a
    /// meal tick. Keying on the instant alone would keep whichever arrived first and
    /// drop the other, which makes stored insulin a function of poll order.
    @Test("A basal segment and a bolus completing together are both kept",
          arguments: [false, true])
    func coincidentBasalAndBolusAreBothKept(bolusFirst: Bool) async throws {
        let store = try makeStore()
        let pump = try source("pump")
        let basal = try dose(0.9, at: instant(), category: .other, deviceLabel: "Simulated basal")
        let bolus = try dose(4.5, at: instant(), category: .food, deviceLabel: "Simulated meal bolus")

        if bolusFirst {
            try await store.record(bolus, from: pump)
            try await store.record(basal, from: pump)
        } else {
            try await store.record(basal, from: pump)
            try await store.record(bolus, from: pump)
        }

        // Ordered by instant then category, so the final state is a value the test
        // can compare rather than a set: "food" sorts before "other".
        let stored = try await store.insulinDoses()
        #expect(stored.map(\.dose) == [bolus, basal])
        #expect(stored.map(\.source) == [pump, pump])
    }

    /// And within one category the rule still bites: two sources reporting basal for
    /// the same instant are two answers to one question, and precedence picks —
    /// whichever arrived first.
    @Test("Two basal records at one instant resolve to one by precedence",
          arguments: [false, true])
    func twoBasalRecordsAtOneInstantResolveByPrecedence(cloudFirst: Bool) async throws {
        let store = try makeStore(order: ["pump", "cloud"])
        let fromPump = try dose(0.9, at: instant(), category: .other, deviceLabel: "Simulated basal")
        let fromCloud = try dose(1.4, at: instant(), category: .other, deviceLabel: "Cloud basal")

        if cloudFirst {
            try await store.record(fromCloud, from: try source("cloud"))
            try await store.record(fromPump, from: try source("pump"))
        } else {
            try await store.record(fromPump, from: try source("pump"))
            try await store.record(fromCloud, from: try source("cloud"))
        }

        let stored = try await store.insulinDoses()
        #expect(stored.count == 1)
        #expect(stored.first?.dose == fromPump)
        #expect(stored.first?.source == (try source("pump")))
    }

    /// One delivery of one category per instant, and the same winner whichever
    /// arrived first. Two rows claiming one instant and one category would be two
    /// answers to "how much insulin reached the patient", and the wrong one flows
    /// into insulin on board (SI-7).
    @Test("One insulin delivery survives per instant, resolved the same way",
          arguments: [false, true])
    func insulinDoseFollowsTheSameRule(cloudFirst: Bool) async throws {
        let store = try makeStore(order: ["pump", "cloud"])
        let fromPump = try dose(2.5, at: instant())
        let fromCloud = try dose(4, at: instant())

        if cloudFirst {
            try await store.record(fromCloud, from: try source("cloud"))
            try await store.record(fromPump, from: try source("pump"))
        } else {
            try await store.record(fromPump, from: try source("pump"))
            try await store.record(fromCloud, from: try source("cloud"))
        }

        let stored = try await store.insulinDoses()
        #expect(stored.count == 1)
        #expect(stored.first?.dose == fromPump)
        #expect(stored.first?.source == (try source("pump")))
    }

    @Test("An unlisted source never displaces a listed one for insulin",
          arguments: [false, true])
    func insulinDoseUnlistedSourcesRankLast(unlistedFirst: Bool) async throws {
        let store = try makeStore(order: ["cloud"])
        let fromCloud = try dose(2.5, at: instant())
        let fromBridge = try dose(4, at: instant())

        if unlistedFirst {
            try await store.record(fromBridge, from: try source("bridge"))
            try await store.record(fromCloud, from: try source("cloud"))
        } else {
            try await store.record(fromCloud, from: try source("cloud"))
            try await store.record(fromBridge, from: try source("bridge"))
        }

        let stored = try await store.insulinDoses()
        #expect(stored.map(\.source) == [try source("cloud")])
        #expect(stored.first?.dose == fromCloud)
    }

    @Test("Two unranked sources resolve an insulin delivery on the identifier",
          arguments: [false, true])
    func insulinDoseUnrankedSourcesResolveLexicographically(zebraFirst: Bool) async throws {
        let store = try makeStore()
        let fromAlpha = try dose(2.5, at: instant())
        let fromZebra = try dose(4, at: instant())

        if zebraFirst {
            try await store.record(fromZebra, from: try source("zebra"))
            try await store.record(fromAlpha, from: try source("alpha"))
        } else {
            try await store.record(fromAlpha, from: try source("alpha"))
            try await store.record(fromZebra, from: try source("zebra"))
        }

        let stored = try await store.insulinDoses()
        #expect(stored.map(\.source) == [try source("alpha")])
        #expect(stored.first?.dose == fromAlpha)
    }

    @Test("Re-reading the same delivery stores nothing new")
    func insulinDoseReplayIsANoOp() async throws {
        let store = try makeStore()
        let delivered = try dose(2.5, at: instant())
        try await store.record(delivered, from: try source("pump"))
        try await store.record(delivered, from: try source("pump"))

        #expect(try await store.insulinDoses().map(\.dose) == [delivered])
    }

    /// A pump that reports two different amounts for one instant is contradicting
    /// itself about insulin that reached the patient. Precedence cannot break that
    /// tie, and picking by arrival order would make the stored amount depend on
    /// when a backfill ran.
    @Test("A pump contradicting its own delivery is refused")
    func insulinDoseSameSourceContradictionIsRefused() async throws {
        let store = try makeStore()
        try await store.record(try dose(2.5, at: instant()), from: try source("pump"))

        let failure = await #expect(throws: PersistenceFailure.self) {
            try await store.record(try dose(4, at: instant()), from: try source("pump"))
        }
        guard case .conflictingRecord = failure else {
            Issue.record("expected a conflict, got \(String(describing: failure))")
            return
        }
        #expect(try await store.insulinDoses().map(\.dose.units) == [2.5])
    }

    // MARK: - Batches of deliveries

    /// The failure mode a single-record loop has: a backfill that meets one refused
    /// record loses every record after it. The batch write applies the same rule to
    /// each record and keeps reading, so the collision costs one record instead of
    /// the rest of the history.
    ///
    /// Two deliveries of one category at one instant is the case that provokes
    /// it: an extended and a normal delivery finishing in the same stored second
    /// both map to one category.
    @Test("A batch carries on past a refused delivery and names it")
    func batchReportsRefusalsAndKeepsGoing() async throws {
        let store = try makeStore()
        let pump = try source("pump")
        let first = try dose(2.5, at: instant(), category: .food, deviceLabel: "Normal")
        let coincident = try dose(1.5, at: instant(), category: .food, deviceLabel: "Extended")
        let later = try dose(3, at: instant(300), category: .food)

        let report = try await store.record([first, coincident, later], from: pump)

        #expect(report.settled == 2)
        #expect(report.isComplete == false)
        #expect(report.refused.map(\.index) == [1])
        #expect(report.refused.map(\.dose) == [coincident])
        #expect(report.refused.first?.detail.contains("pump") == true)
        // The refused record is not in the store, and the record it collided with
        // is untouched: the store stored one answer and handed the other back.
        #expect(try await store.insulinDoses().map(\.dose) == [first, later])
    }

    /// The refusal is per record, not per batch: coincident deliveries of DIFFERENT
    /// categories are two real deliveries and both land, in one batch as in two
    /// calls.
    @Test("A batch of coincident deliveries of different categories settles whole")
    func batchWithoutCollisionsSettlesWhole() async throws {
        let store = try makeStore()
        let pump = try source("pump")
        let basal = try dose(0.9, at: instant(), category: .other, deviceLabel: "Simulated basal")
        let bolus = try dose(4.5, at: instant(), category: .food, deviceLabel: "Simulated meal bolus")

        let report = try await store.record([basal, bolus], from: pump)

        #expect(report.settled == 2)
        #expect(report.isComplete)
        #expect(try await store.insulinDoses().map(\.dose) == [bolus, basal])
    }

    /// Re-running a batch is the replay case, and it has to stay free: every record
    /// is already there, nothing is refused, and the store is unchanged.
    @Test("Re-running a batch settles every record and refuses none")
    func batchReplayIsANoOp() async throws {
        let store = try makeStore()
        let pump = try source("pump")
        let batch = [
            try dose(2.5, at: instant(), category: .food),
            try dose(0.9, at: instant(), category: .other),
        ]

        _ = try await store.record(batch, from: pump)
        let second = try await store.record(batch, from: pump)

        #expect(second.settled == 2)
        #expect(second.isComplete)
        #expect(try await store.insulinDoses().count == 2)
    }

    /// The category and the device's own label are part of the record, not
    /// decoration: `other` with the pump's label beside it is what diagnoses a
    /// mapping that fell through.
    @Test("A delivery round-trips its category and the device's own label")
    func insulinDoseRoundTripsItsCategory() async throws {
        let store = try makeStore()
        let delivered = try dose(1.25, at: instant(30), category: .foodAndCorrection, deviceLabel: "Meal+Corr")
        try await store.record(delivered, from: try source("pump"))

        let stored = try #require(try await store.insulinDoses().first)
        #expect(stored.dose == delivered)
        #expect(stored.source == (try source("pump")))
    }

    /// The key is in the schema, so the invariant does not depend on the write path
    /// being the one that ran — including for a writer that is not this code.
    @Test("The schema itself refuses a second delivery of one category at one instant")
    func insulinDoseUniquenessIsInTheSchema() async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
        try await store.record(try dose(2.5, at: instant()), from: try source("pump"))

        let refusal = #expect(throws: RawSQLiteFile.Refused.self) {
            try RawSQLiteFile(location.databaseURL).execute("""
                INSERT INTO insulin_dose (completed_at, units, category, device_category_label, source)
                VALUES (\(instant().timeIntervalSince1970), 4.0, 'correction', NULL, 'elsewhere')
                """)
        }
        #expect(refusal?.message.contains("UNIQUE") == true, "expected a key refusal, got \(refusal as Any)")
        #expect(try await store.insulinDoses().map(\.dose.units) == [2.5])
    }

    /// The other half of that key, and the reason it is a pair: the constraint has
    /// to admit a coincident delivery of a DIFFERENT category, or the test above
    /// would also pass on a table that refuses everything at that instant.
    @Test("The schema admits a coincident delivery of another category")
    func insulinDoseSchemaAdmitsAnotherCategory() async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
        try await store.record(try dose(2.5, at: instant()), from: try source("pump"))

        try RawSQLiteFile(location.databaseURL).execute("""
            INSERT INTO insulin_dose (completed_at, units, category, device_category_label, source)
            VALUES (\(instant().timeIntervalSince1970), 0.9, 'other', 'Simulated basal', 'pump')
            """)

        let stored = try await store.insulinDoses()
        #expect(stored.map(\.dose.category) == [.correction, .other])
        #expect(stored.map(\.dose.units) == [2.5, 0.9])
    }

    // MARK: - Raw pump history

    /// Two pumps number their own logs independently, so the key carries the
    /// source. Android keys this table on the sequence number alone while its own
    /// documentation says "unique per pump"; here the key says what the comment
    /// meant.
    @Test("Two pumps may both file a record under the same sequence number")
    func rawHistoryIsKeyedByPumpAndSequence() async throws {
        let store = try makeStore()
        try await store.record(try history(sequence: 1, from: "pump-a"))
        try await store.record(try history(sequence: 1, from: "pump-b"))

        #expect(try await store.rawPumpHistory().count == 2)
    }

    @Test("Re-reading a pump's log stores nothing new")
    func rawHistoryReplayIsANoOp() async throws {
        let store = try makeStore()
        let record = try history(sequence: 7, from: "pump-a")
        try await store.record(record)
        try await store.record(record)

        #expect(try await store.rawPumpHistory() == [record])
    }

    @Test("A pump filing different bytes under a number it already used is refused")
    func rawHistoryContradictionIsRefused() async throws {
        let store = try makeStore()
        try await store.record(try history(sequence: 7, from: "pump-a", payload: Data([0x01])))

        let failure = await #expect(throws: PersistenceFailure.self) {
            try await store.record(try history(sequence: 7, from: "pump-a", payload: Data([0x02])))
        }
        guard case .conflictingRecord = failure else {
            Issue.record("expected a conflict, got \(String(describing: failure))")
            return
        }
        #expect(try await store.rawPumpHistory().map(\.payload) == [Data([0x01])])
    }

    private func history(
        sequence: Int64,
        from identifier: String,
        at recordedAt: Date = instant(),
        payload: Data = Data([0xAB, 0xCD])
    ) throws -> RawPumpHistoryRecord {
        RawPumpHistoryRecord(
            source: try StoreSource(identifier),
            sequenceNumber: sequence,
            recordedAt: recordedAt,
            eventTypeIdentifier: 3,
            payload: payload
        )
    }
}
