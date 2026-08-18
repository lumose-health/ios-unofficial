import Foundation
import DriverAPI
import GRDB
import SafetyCore

/// The device's local store: the one place app data is written, and the one place
/// it is read from.
///
/// ## Sole writer
///
/// Nothing else opens this file. Every write goes through one connection,
/// serialized by GRDB's `DatabasePool`, which holds exactly one writer and lets
/// readers proceed concurrently against WAL snapshots. That is the shape the
/// structural seed asks for, and it is also what makes the collision rules below
/// mean anything: a second writer would resolve a collision against a row the
/// first writer had not committed yet.
///
/// One connection per file is enforced rather than asked for — ``StoreWriters``
/// keeps the writer for a path, so opening the same store twice hands back the
/// same connection. That is why opening is `async`.
///
/// The type is a `Sendable` struct over Sendable parts — GRDB's writers are
/// `Sendable`, so is ``SafetyCore/Clock`` — so there is no `@unchecked Sendable`
/// anywhere in this target and no lock to reason about.
///
/// ## The absolute bound is enforced at the write, at the read, and in the schema
///
/// A glucose value reaches a row only by way of ``SafetyCore/Glucose``, whose
/// initializer throws outside the absolute bound (AD-5). The store does not spell
/// that bound — it has one definition site and this is not it — and it takes no
/// Safety Limits parameter: a narrowed limit is a validation concern upstream, and
/// a store that could be handed one would be a store whose contents depend on a
/// setting.
///
/// The column carries a CHECK derived from the same one definition site, so the
/// bound holds against a writer that is not this code at all. And reads
/// reconstruct `Glucose` too: a row outside the bound can only have arrived from
/// something that bypassed both, and the honest response is the same typed
/// refusal, not a reading on a screen.
public struct LocalStore: Sendable {

    private let writer: any DatabaseWriter
    private let clock: any Clock
    private let precedence: SourcePrecedence

    private init(writer: any DatabaseWriter, clock: any Clock, precedence: SourcePrecedence) {
        self.writer = writer
        self.clock = clock
        self.precedence = precedence
    }

    // MARK: - Opening

    /// Opens, protects and migrates the store at `url`, creating it if it is not
    /// there.
    ///
    /// At-rest protection is applied unconditionally. There is no parameter for it
    /// and no overload without it: an opt-out taken once is an unprotected file
    /// carrying health data, and this is the only way in.
    ///
    /// Opening the same path twice shares one writer connection, so "the store is
    /// the sole writer" is a property of the module rather than of how carefully
    /// callers use it. See ``StoreWriters``.
    ///
    /// - Throws: ``PersistenceFailure/protectionUnavailable(path:detail:)`` when
    ///   at-rest protection could not be applied,
    ///   ``PersistenceFailure/schemaFromNewerVersion(applied:)`` when the file was
    ///   written by a newer build, ``PersistenceFailure/storageFailed(detail:)``
    ///   for anything SQLite or the file system refused.
    public static func open(
        at url: URL,
        clock: some Clock,
        precedence: SourcePrecedence = .unranked
    ) async throws(PersistenceFailure) -> LocalStore {
        try await open(at: url, clock: clock, precedence: precedence, protection: SystemFileProtection())
    }

    /// The same open, with the protection seam injected.
    ///
    /// Internal, and reachable only through `@testable`: what varies here is
    /// whether protection SUCCEEDS, which is a thing tests need to drive and
    /// consumers must not choose.
    ///
    /// ## The order these steps happen in
    ///
    /// The containing directory is protected FIRST, on EVERY open, whether this
    /// open created it or found it there. On iOS a directory's protection class is
    /// the default for items created inside it, so this is what covers the files
    /// the store does not name: a `-wal` or `-shm` SQLite recreates later in the
    /// process, a `-journal` if WAL is ever unavailable. Protecting the directory
    /// only when the store created it would leave every launch after the first, and
    /// every store living in a container something else made (Application Support),
    /// carrying whatever class that container happened to have.
    ///
    /// The database file and its sidecars are then protected explicitly, after the
    /// first write has brought them into existence, so the ones that already exist
    /// do not depend on inheritance having been in place when they were made.
    ///
    /// A protection failure aborts the open. A store that opened but is
    /// unprotected is worse than one that did not: it works, so nobody looks at it
    /// again (SI-10).
    static func open(
        at url: URL,
        clock: some Clock,
        precedence: SourcePrecedence = .unranked,
        protection: some StoreFileProtecting
    ) async throws(PersistenceFailure) -> LocalStore {
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw .storageFailed(detail: String(describing: error))
            }
        }
        try applyProtection(protection, to: directory)

        let writer: any DatabaseWriter
        do {
            writer = try await StoreWriters.shared.writer(forPath: StoreWriters.key(for: url)) {
                var configuration = Configuration()
                configuration.label = "LocalStore"
                return try DatabasePool(path: url.path, configuration: configuration)
            }
        } catch {
            throw .storageFailed(detail: String(describing: error))
        }

        try migrate(writer)

        for file in storeFiles(of: url) where FileManager.default.fileExists(atPath: file.path) {
            try applyProtection(protection, to: file)
        }

        return LocalStore(writer: writer, clock: clock, precedence: precedence)
    }

    /// A store that exists only for the life of the process, for tests.
    ///
    /// There is no file, so there is nothing to protect, nothing to migrate
    /// forward from, and nothing for a second connection to contend over — but the
    /// schema and every rule above it are the same ones the on-disk store runs,
    /// because they come from the same migrator.
    public static func inMemory(
        clock: some Clock,
        precedence: SourcePrecedence = .unranked
    ) throws(PersistenceFailure) -> LocalStore {
        let writer: any DatabaseWriter
        do {
            writer = try DatabaseQueue()
        } catch {
            throw .storageFailed(detail: String(describing: error))
        }
        try migrate(writer)
        return LocalStore(writer: writer, clock: clock, precedence: precedence)
    }

    /// The database file and every sidecar SQLite keeps beside it: the write-ahead
    /// log and its shared-memory index in WAL mode, and the rollback journal for the
    /// case where WAL is not available. Whichever of them exist at open time are
    /// protected by name; ones created later inherit the directory's class, which is
    /// why the directory is protected on every open.
    private static func storeFiles(of url: URL) -> [URL] {
        let path = url.path
        return [
            url,
            URL(fileURLWithPath: path + "-wal"),
            URL(fileURLWithPath: path + "-shm"),
            URL(fileURLWithPath: path + "-journal"),
        ]
    }

    private static func applyProtection(
        _ protection: some StoreFileProtecting,
        to url: URL
    ) throws(PersistenceFailure) {
        do {
            try protection.protect(itemAt: url, as: .completeUntilFirstUserAuthentication)
        } catch {
            throw .protectionUnavailable(path: url.path, detail: String(describing: error))
        }
    }

    private static func migrate(_ writer: any DatabaseWriter) throws(PersistenceFailure) {
        let migrator = StoreSchema.migrator()
        do {
            let applied = try writer.read { db in try migrator.appliedIdentifiers(db) }
            let unknown = applied.subtracting(StoreSchema.identifiers)
            guard unknown.isEmpty else {
                throw PersistenceFailure.schemaFromNewerVersion(applied: applied.sorted())
            }
            try migrator.migrate(writer)
        } catch let failure as PersistenceFailure {
            throw failure
        } catch {
            throw .storageFailed(detail: String(describing: error))
        }
    }

    /// The migrations this file has had applied, in the order they were
    /// registered. `["v1"]` for a store this build created.
    public func appliedMigrationIdentifiers() async throws(PersistenceFailure) -> [String] {
        let migrator = StoreSchema.migrator()
        return try await performRead { db in try migrator.appliedMigrations(db) }
    }

    // MARK: - Writing

    /// Records a CGM reading from a raw device value, constructing
    /// ``SafetyCore/Glucose`` on the way in.
    ///
    /// This is the entry point for a Driver holding a decoded number. The value
    /// crosses into the store as a `Glucose` or it does not cross at all: 19.9 and
    /// 500.1 are refused here, 20 and 500 are stored, and a NaN is refused as a
    /// distinct kind of wrong.
    ///
    /// - Throws: ``PersistenceFailure/glucoseRejected(_:)`` outside the absolute
    ///   bound or for a non-finite value, plus anything ``record(_:from:)`` throws.
    public func recordGlucose(
        mgdl: Double,
        recordedAt: Date,
        trend: GlucoseTrend? = nil,
        from source: StoreSource
    ) async throws(PersistenceFailure) {
        let glucose: Glucose
        do {
            glucose = try Glucose(mgdl: mgdl)
        } catch let error as GlucoseError {
            throw .glucoseRejected(error)
        } catch {
            throw .storageFailed(detail: String(describing: error))
        }
        try await record(GlucoseSample(glucose: glucose, recordedAt: recordedAt, trend: trend), from: source)
    }

    /// Records a CGM reading that is already in range by construction.
    ///
    /// At most one reading survives per instant. When a row is already there, the
    /// two sources are compared by ``SourcePrecedence``: the winner's values end up
    /// in the row and the loser's are dropped without comment, which is what makes
    /// a re-run of the same backfill a no-op.
    ///
    /// - Throws: ``PersistenceFailure/conflictingRecord(detail:)`` when the SAME
    ///   source already wrote a DIFFERENT value at this instant — a source
    ///   contradicting itself is not something precedence can resolve, and picking
    ///   by arrival order would make the stored value depend on replay order.
    public func record(_ sample: GlucoseSample, from source: StoreSource) async throws(PersistenceFailure) {
        let precedence = self.precedence
        try await performWrite { db in
            let instant = sample.recordedAt.timeIntervalSince1970
            let existing = try Row.fetchOne(
                db,
                sql: "SELECT mgdl, trend, source FROM glucose_reading WHERE recorded_at = ?",
                arguments: [instant]
            )

            guard let existing else {
                try db.execute(
                    sql: """
                        INSERT INTO glucose_reading (recorded_at, mgdl, trend, source)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [instant, sample.glucose.mgdl, sample.trend?.rawValue, source.identifier]
                )
                return
            }

            let storedName: String = existing["source"]
            let storedSource = try StoreSource(storedName)
            switch precedence.standing(stored: storedSource, incoming: source) {
            case .storedWins:
                return
            case .sameSource:
                let storedValue: Double = existing["mgdl"]
                let storedTrend: String? = existing["trend"]
                guard storedValue != sample.glucose.mgdl || storedTrend != sample.trend?.rawValue else { return }
                throw PersistenceFailure.conflictingRecord(
                    detail: "\(source.identifier) already recorded a different glucose reading at this instant"
                )
            case .incomingWins:
                try db.execute(
                    sql: """
                        UPDATE glucose_reading SET mgdl = ?, trend = ?, source = ?
                        WHERE recorded_at = ?
                        """,
                    arguments: [sample.glucose.mgdl, sample.trend?.rawValue, source.identifier, instant]
                )
            }
        }
    }

    /// Records a pump-status snapshot.
    ///
    /// One row per instant, resolved by the same rule readings use: a snapshot is
    /// what the pump was at one moment, and two rows for one moment are two
    /// answers to a question that has one.
    ///
    /// - Throws: ``PersistenceFailure/conflictingRecord(detail:)`` when the same
    ///   source already wrote a different snapshot at this instant.
    public func record(_ snapshot: PumpStatusSnapshot, from source: StoreSource) async throws(PersistenceFailure) {
        let precedence = self.precedence
        try await performWrite { db in
            let instant = snapshot.observedAt.timeIntervalSince1970
            let existing = try Row.fetchOne(
                db,
                sql: """
                    SELECT battery_fraction, reservoir_units, model_name, firmware_version, source
                    FROM pump_status WHERE observed_at = ?
                    """,
                arguments: [instant]
            )

            guard let existing else {
                try db.execute(
                    sql: """
                        INSERT INTO pump_status
                            (observed_at, battery_fraction, reservoir_units, model_name, firmware_version, source)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        instant,
                        snapshot.batteryFraction,
                        snapshot.reservoirUnits,
                        snapshot.hardware?.modelName,
                        snapshot.hardware?.firmwareVersion,
                        source.identifier,
                    ]
                )
                return
            }

            let storedName: String = existing["source"]
            let storedSource = try StoreSource(storedName)
            switch precedence.standing(stored: storedSource, incoming: source) {
            case .storedWins:
                return
            case .sameSource:
                let stored = try Self.decodePumpStatus(row: existing, observedAt: snapshot.observedAt)
                guard stored.snapshot != snapshot else { return }
                throw PersistenceFailure.conflictingRecord(
                    detail: "\(source.identifier) already recorded a different pump status at this instant"
                )
            case .incomingWins:
                try db.execute(
                    sql: """
                        UPDATE pump_status
                        SET battery_fraction = ?, reservoir_units = ?, model_name = ?,
                            firmware_version = ?, source = ?
                        WHERE observed_at = ?
                        """,
                    arguments: [
                        snapshot.batteryFraction,
                        snapshot.reservoirUnits,
                        snapshot.hardware?.modelName,
                        snapshot.hardware?.firmwareVersion,
                        source.identifier,
                        instant,
                    ]
                )
            }
        }
    }

    /// Records one completed insulin delivery.
    ///
    /// One row per CATEGORY per instant — the one-basal-record-per-timestamp
    /// invariant FR-137 asks for, in the vocabulary this platform has for insulin
    /// that reached the patient. A pump runs basal continuously and puts boluses on
    /// top of it, so a basal segment and a meal bolus finishing on the same tick are
    /// two real deliveries and both are kept; two rows for the SAME category at one
    /// instant would be two answers to "how much basal reached the patient", and the
    /// wrong one flows into insulin on board (SI-7).
    ///
    /// ``DriverAPI/DoseCategory`` has no basal case — it mirrors Android's
    /// bolus-only vocabulary — so a Driver reporting basal delivery reports it as
    /// ``DriverAPI/DoseCategory/other``; every basal record therefore lands in one
    /// category, and one-per-category is one-per-basal-segment. The key is in the
    /// schema, so the invariant holds against a writer that is not this code;
    /// cross-source collisions on one category and instant resolve by the same
    /// ``SourcePrecedence`` rule readings and snapshots use.
    ///
    /// One record at a time, so one refusal ends the call. A caller walking a
    /// history log should hand the whole batch to the array overload below
    /// instead: it applies the same rule to every record and reports what it
    /// refused, rather than abandoning the rest of the log at the first collision.
    ///
    /// - Throws: ``PersistenceFailure/conflictingRecord(detail:)`` when the same
    ///   source already reported a different delivery of this category at this
    ///   instant.
    public func record(_ dose: DoseRecord, from source: StoreSource) async throws(PersistenceFailure) {
        let precedence = self.precedence
        let outcome = try await performWrite { db in
            try Self.applyDose(dose, from: source, resolvedBy: precedence, in: db)
        }
        if case .refused(let detail) = outcome {
            throw .conflictingRecord(detail: detail)
        }
    }

    /// Records a batch of completed insulin deliveries, carrying on past the ones
    /// the store refuses instead of stopping at the first.
    ///
    /// The per-record rule is exactly the single-record write's: same key, same
    /// precedence resolution, same refusal when one source reports two different
    /// deliveries of one category at one instant. Nothing here widens the key:
    /// widening it, on the device's own label or on the quantity, would let two
    /// rows claim one instant and one category, and "how much insulin reached
    /// the patient" would have two answers, both of which flow into insulin on
    /// board (SI-7).
    ///
    /// What changes is the shape of the failure. A backfill is a loop over history
    /// somebody else recorded, and a caller looping over the single-record write
    /// loses every record after the first refusal, so one pathological pair of
    /// rows ends the import. The batch collects refusals and keeps reading.
    ///
    /// A refused record is not dropped quietly: it comes back in the report, with
    /// its position in the batch, and the return value is not discardable. Two
    /// genuinely distinct deliveries that landed on one instant and one category,
    /// say an extended and a normal delivery finishing in the same stored second,
    /// are a real coincidence the caller has to see, and the store inventing a
    /// resolution for it would be the guess this whole file exists to avoid (AD-5).
    ///
    /// Everything that is NOT a collision (SQLite refusing, a stored source that
    /// will not decode) still throws and abandons the batch: those say the write
    /// path itself is not working, and a report counted through a broken one means
    /// nothing. The batch is one transaction, so an abandoned batch leaves the store
    /// as it was.
    ///
    /// - Returns: how many records the batch settled, and every one it refused.
    public func record(
        _ doses: [DoseRecord],
        from source: StoreSource
    ) async throws(PersistenceFailure) -> DoseIngestReport {
        let precedence = self.precedence
        return try await performWrite { db in
            var settled = 0
            var refused: [DoseIngestReport.Refusal] = []
            for (index, dose) in doses.enumerated() {
                switch try Self.applyDose(dose, from: source, resolvedBy: precedence, in: db) {
                case .settled:
                    settled += 1
                case .refused(let detail):
                    refused.append(DoseIngestReport.Refusal(index: index, dose: dose, detail: detail))
                }
            }
            return DoseIngestReport(settled: settled, refused: refused)
        }
    }

    /// One delivery's write, with the collision RETURNED rather than thrown.
    ///
    /// The single-record write turns a refusal into a typed error; the batch write
    /// records it and moves on. Both go through this, so the two cannot drift into
    /// resolving a collision differently.
    private static func applyDose(
        _ dose: DoseRecord,
        from source: StoreSource,
        resolvedBy precedence: SourcePrecedence,
        in db: Database
    ) throws -> DoseWriteOutcome {
        let instant = dose.completedAt.timeIntervalSince1970
        let category = dose.category.rawValue
        let existing = try Row.fetchOne(
            db,
            sql: """
                SELECT units, category, device_category_label, source
                FROM insulin_dose WHERE completed_at = ? AND category = ?
                """,
            arguments: [instant, category]
        )

        guard let existing else {
            try db.execute(
                sql: """
                    INSERT INTO insulin_dose
                        (completed_at, units, category, device_category_label, source)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    instant,
                    dose.units,
                    category,
                    dose.deviceCategoryLabel,
                    source.identifier,
                ]
            )
            return .settled
        }

        let storedName: String = existing["source"]
        let storedSource = try StoreSource(storedName)
        switch precedence.standing(stored: storedSource, incoming: source) {
        case .storedWins:
            return .settled
        case .sameSource:
            let stored = try Self.decodeDose(row: existing, completedAt: dose.completedAt)
            guard stored.dose != dose else { return .settled }
            return .refused(
                detail: """
                    \(source.identifier) already recorded a different \(category) \
                    insulin delivery at this instant
                    """
            )
        case .incomingWins:
            // The category is part of the key, so it is matched rather than
            // written: the row being replaced is by definition the one for this
            // category.
            try db.execute(
                sql: """
                    UPDATE insulin_dose
                    SET units = ?, device_category_label = ?, source = ?
                    WHERE completed_at = ? AND category = ?
                    """,
                arguments: [
                    dose.units,
                    dose.deviceCategoryLabel,
                    source.identifier,
                    instant,
                    category,
                ]
            )
            return .settled
        }
    }

    /// What one delivery's write did: either the store settled it (written,
    /// already there, or answered by a row a higher-precedence source owns) or it
    /// refused, and carries the reason.
    private enum DoseWriteOutcome {
        case settled
        case refused(detail: String)
    }

    /// Records one record of a pump's own history log.
    ///
    /// The key is the source and the pump's own sequence number, so two pumps that
    /// both number from zero coexist and precedence never comes up: rows from
    /// different sources do not compete for a key here. Re-reading a log the store
    /// already has writes nothing.
    ///
    /// - Throws: ``PersistenceFailure/conflictingRecord(detail:)`` when the same
    ///   pump has already filed a different record under this number.
    public func record(_ record: RawPumpHistoryRecord) async throws(PersistenceFailure) {
        try await performWrite { db in
            let instant = record.recordedAt.timeIntervalSince1970
            let existing = try Row.fetchOne(
                db,
                sql: """
                    SELECT recorded_at, event_type, payload FROM raw_pump_history
                    WHERE source = ? AND sequence_number = ?
                    """,
                arguments: [record.source.identifier, record.sequenceNumber]
            )

            guard let existing else {
                try db.execute(
                    sql: """
                        INSERT INTO raw_pump_history
                            (source, sequence_number, recorded_at, event_type, payload)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        record.source.identifier,
                        record.sequenceNumber,
                        instant,
                        record.eventTypeIdentifier,
                        record.payload,
                    ]
                )
                return
            }

            let storedInstant: Double = existing["recorded_at"]
            let storedType: Int = existing["event_type"]
            let storedPayload: Data = existing["payload"]
            guard storedInstant != instant
                    || storedType != record.eventTypeIdentifier
                    || storedPayload != record.payload else { return }
            throw PersistenceFailure.conflictingRecord(
                detail: "\(record.source.identifier) already filed a different record under this sequence number"
            )
        }
    }

    // MARK: - Reading

    /// Every stored reading at or after `since`, oldest first.
    ///
    /// - Throws: ``PersistenceFailure/glucoseRejected(_:)`` when a stored row is
    ///   outside the absolute bound. That cannot happen through this API, and the
    ///   column's own CHECK refuses it too; it means the file was written by
    ///   something that went around both, and a refusal is the only answer that
    ///   does not put an unbounded number on a screen.
    public func glucoseReadings(since: Date? = nil) async throws(PersistenceFailure) -> [StoredGlucoseSample] {
        try await performRead { db in
            try Self.rows(db, table: "glucose_reading", instantColumn: "recorded_at", since: since)
                .map { row in
                    let mgdl: Double = row["mgdl"]
                    let glucose: Glucose
                    do {
                        glucose = try Glucose(mgdl: mgdl)
                    } catch let error as GlucoseError {
                        throw PersistenceFailure.glucoseRejected(error)
                    }
                    let seconds: TimeInterval = row["recorded_at"]
                    // A stored arrow this build's vocabulary does not name is what
                    // `unknown` is for: the sensor reported a direction, and this
                    // is not one of the ones we can draw.
                    let rawTrend: String? = row["trend"]
                    let trend = rawTrend.map { GlucoseTrend(rawValue: $0) ?? .unknown }
                    let sourceName: String = row["source"]
                    return StoredGlucoseSample(
                        sample: GlucoseSample(
                            glucose: glucose,
                            recordedAt: Date(timeIntervalSince1970: seconds),
                            trend: trend
                        ),
                        source: try StoreSource(sourceName)
                    )
                }
        }
    }

    /// Every stored pump-status snapshot at or after `since`, oldest first.
    public func pumpStatuses(since: Date? = nil) async throws(PersistenceFailure) -> [StoredPumpStatus] {
        try await performRead { db in
            try Self.rows(db, table: "pump_status", instantColumn: "observed_at", since: since)
                .map { row in
                    let seconds: TimeInterval = row["observed_at"]
                    return try Self.decodePumpStatus(
                        row: row,
                        observedAt: Date(timeIntervalSince1970: seconds)
                    )
                }
        }
    }

    /// Every stored insulin delivery at or after `since`, oldest first, then by
    /// category — coincident deliveries of different categories are both kept, so
    /// the instant alone is not a total order and a caller comparing two reads would
    /// otherwise be comparing SQLite's row order.
    ///
    /// - Throws: ``PersistenceFailure/doseRejected(_:)`` when a stored row carries
    ///   a quantity ``DriverAPI/DoseRecord`` refuses. Nothing this API wrote can
    ///   produce that, and a number no pump could have delivered must not reach an
    ///   insulin summary.
    public func insulinDoses(since: Date? = nil) async throws(PersistenceFailure) -> [StoredDoseRecord] {
        try await performRead { db in
            try Self.rows(
                db,
                table: "insulin_dose",
                instantColumn: "completed_at",
                since: since,
                then: "category"
            )
                .map { row in
                    let seconds: TimeInterval = row["completed_at"]
                    return try Self.decodeDose(
                        row: row,
                        completedAt: Date(timeIntervalSince1970: seconds)
                    )
                }
        }
    }

    /// Every stored raw history record at or after `since`, oldest first, then by
    /// source and sequence number so the order is total.
    public func rawPumpHistory(since: Date? = nil) async throws(PersistenceFailure) -> [RawPumpHistoryRecord] {
        try await performRead { db in
            let filter = since == nil ? "" : "WHERE recorded_at >= ?"
            let arguments: StatementArguments = since.map { [$0.timeIntervalSince1970] } ?? []
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT source, sequence_number, recorded_at, event_type, payload
                    FROM raw_pump_history \(filter)
                    ORDER BY recorded_at ASC, source ASC, sequence_number ASC
                    """,
                arguments: arguments
            )
            return try rows.map { row in
                let sourceName: String = row["source"]
                let seconds: TimeInterval = row["recorded_at"]
                return RawPumpHistoryRecord(
                    source: try StoreSource(sourceName),
                    sequenceNumber: row["sequence_number"],
                    recordedAt: Date(timeIntervalSince1970: seconds),
                    eventTypeIdentifier: row["event_type"],
                    payload: row["payload"]
                )
            }
        }
    }

    // MARK: - Retention

    /// Deletes every row older than `window` in every table the store owns, and
    /// returns how many rows went (FR-139).
    ///
    /// The horizon comes from the injected clock, so the boundary is testable
    /// rather than reachable only by waiting (AD-14). Strictly older: a row
    /// sitting exactly on the horizon is kept, so a sweep run twice in the same
    /// instant does not take a different set the second time.
    ///
    /// Every table is swept in one transaction. A partial sweep would leave
    /// history whose pieces disagree about how far back they go.
    @discardableResult
    public func sweepExpiredRecords(
        retaining window: RetentionWindow = .default
    ) async throws(PersistenceFailure) -> Int {
        let horizon = clock.now.addingTimeInterval(-window.duration).timeIntervalSince1970
        let tables = StoreSchema.retainedTables
        return try await performWrite { db in
            var deleted = 0
            for table in tables {
                // The table and column names are this file's own constants, not
                // anything a caller supplies; the horizon is bound as a parameter.
                try db.execute(
                    sql: "DELETE FROM \(table.name) WHERE \(table.instantColumn) < ?",
                    arguments: [horizon]
                )
                deleted += db.changesCount
            }
            return deleted
        }
    }

    // MARK: - Internals the tests reach for

    /// Every table in the file, excluding SQLite's own and the migrator's
    /// bookkeeping. Used to pin that no table escapes the retention sweep.
    func tableNames() async throws(PersistenceFailure) -> [String] {
        try await performRead { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> ?
                    ORDER BY name
                    """,
                arguments: [StoreSchema.migrationBookkeepingTable]
            )
        }
    }

    /// Which connection this store writes through.
    ///
    /// Every writer GRDB offers is a class, so this is the connection's identity —
    /// what the sole-writer rule is a statement about. Used by the test that two
    /// opens of one path share one writer.
    var writerIdentity: ObjectIdentifier {
        ObjectIdentifier(writer as AnyObject)
    }

    /// Marks the file as having applied a migration this build does not know —
    /// what a database written by a NEWER version of the app looks like from here.
    ///
    /// Internal, and its only caller is the test that pins the forward-only rule.
    /// It goes through the store's OWN writer: a second connection opened here
    /// would be the module holding two writers on one file, which is the thing the
    /// sole-writer rule forbids. No production path writes to the migrator's
    /// bookkeeping table; a migration is recorded by running it.
    func stampForeignMigration(_ identifier: String) async throws(PersistenceFailure) {
        let table = StoreSchema.migrationBookkeepingTable
        try await performWrite { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS \(table) (identifier TEXT NOT NULL PRIMARY KEY)
                """)
            try db.execute(
                sql: "INSERT OR REPLACE INTO \(table) (identifier) VALUES (?)",
                arguments: [identifier]
            )
        }
    }

    // MARK: - Plumbing

    /// Rows from a table keyed on an instant, oldest first. `then` names a second
    /// ordering column for the tables where the instant is not unique on its own —
    /// without it the order of coincident rows would be SQLite's business rather
    /// than this API's.
    private static func rows(
        _ db: Database,
        table: String,
        instantColumn: String,
        since: Date?,
        then tieBreaker: String? = nil
    ) throws -> [Row] {
        let filter = since == nil ? "" : "WHERE \(instantColumn) >= ?"
        let order = [instantColumn, tieBreaker].compactMap { $0 }.map { "\($0) ASC" }.joined(separator: ", ")
        let arguments: StatementArguments = since.map { [$0.timeIntervalSince1970] } ?? []
        return try Row.fetchAll(
            db,
            sql: "SELECT * FROM \(table) \(filter) ORDER BY \(order)",
            arguments: arguments
        )
    }

    private static func decodePumpStatus(row: Row, observedAt: Date) throws -> StoredPumpStatus {
        let modelName: String? = row["model_name"]
        let firmwareVersion: String? = row["firmware_version"]
        // Both halves or neither: a hardware identity missing one of them is not a
        // partial identity, it is a row this build cannot read as one.
        var hardware: PumpHardwareInfo?
        if let modelName, let firmwareVersion {
            hardware = PumpHardwareInfo(modelName: modelName, firmwareVersion: firmwareVersion)
        }
        let batteryFraction: Double? = row["battery_fraction"]
        let reservoirUnits: Double? = row["reservoir_units"]
        let snapshot: PumpStatusSnapshot
        do {
            snapshot = try PumpStatusSnapshot(
                batteryFraction: batteryFraction,
                reservoirUnits: reservoirUnits,
                hardware: hardware,
                observedAt: observedAt
            )
        } catch {
            throw PersistenceFailure.storageFailed(
                detail: "a stored pump status carries a value no pump could have reported: \(error)"
            )
        }
        let sourceName: String = row["source"]
        return StoredPumpStatus(snapshot: snapshot, source: try StoreSource(sourceName))
    }

    private static func decodeDose(row: Row, completedAt: Date) throws -> StoredDoseRecord {
        let units: Double = row["units"]
        // A category this build's vocabulary does not name is what `other` is for,
        // and the device's own label is stored beside it — so a row written by a
        // build that knows more categories reads back as an uncategorised delivery
        // of the right size, rather than not reading back at all.
        let rawCategory: String = row["category"]
        let category = DoseCategory(rawValue: rawCategory) ?? .other
        let deviceCategoryLabel: String? = row["device_category_label"]
        let dose: DoseRecord
        do {
            dose = try DoseRecord(
                units: units,
                completedAt: completedAt,
                category: category,
                deviceCategoryLabel: deviceCategoryLabel
            )
        } catch {
            // `DoseRecord`'s initializer throws `DriverFailure` and nothing else,
            // so this binds to that type rather than to an opaque error.
            throw PersistenceFailure.doseRejected(error)
        }
        let sourceName: String = row["source"]
        return StoredDoseRecord(dose: dose, source: try StoreSource(sourceName))
    }

    private func performWrite<T: Sendable>(
        _ body: @Sendable (Database) throws -> T
    ) async throws(PersistenceFailure) -> T {
        do {
            return try await writer.write(body)
        } catch let failure as PersistenceFailure {
            throw failure
        } catch {
            throw .storageFailed(detail: String(describing: error))
        }
    }

    private func performRead<T: Sendable>(
        _ body: @Sendable (Database) throws -> T
    ) async throws(PersistenceFailure) -> T {
        do {
            return try await writer.read(body)
        } catch let failure as PersistenceFailure {
            throw failure
        } catch {
            throw .storageFailed(detail: String(describing: error))
        }
    }
}
