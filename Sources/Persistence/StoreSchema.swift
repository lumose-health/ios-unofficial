import Foundation
import GRDB
import SafetyCore

/// A table the retention sweep bounds, and the column it is judged by.
///
/// Every table the store creates appears in ``StoreSchema/retainedTables``. That
/// list is what the sweep iterates, so a later table joins retention by adding one
/// entry beside its migration rather than by remembering to write another
/// `DELETE`. A test reads the schema back out of the file and fails when a table
/// exists that the list does not name — the failure mode being guarded against is
/// a table that quietly grows forever.
struct RetainedTable: Hashable, Sendable {

    /// The SQL table name.
    let name: String

    /// The column holding the instant a row is judged by. Epoch seconds, so the
    /// comparison is arithmetic rather than string ordering.
    let instantColumn: String
}

/// The database schema and its forward-only migrations (AD-6).
///
/// ## Forward-only, numbered, starting at v1
///
/// There is no down migration and no path that runs one. A schema change is a new
/// numbered migration appended to ``migrator()``; an existing one is never edited
/// once it has shipped, because a device that already applied it will not apply it
/// again and would end up with a schema the code does not expect.
///
/// v1 starts empty rather than inheriting Android's version 13. Android's schema
/// carries seven versions of decisions this app has not made yet, plus tables it
/// has (alerts, a sync queue) that arrive here with their own work. Starting at v1
/// means the migration history describes this app's schema instead of another
/// one's.
///
/// ## What v1 contains, and what it does not
///
/// Four tables: CGM readings, pump status, completed insulin doses, and the pump's
/// raw history log. No alert history, no outbound queue, no meals — those are
/// separate concerns with their own retention and their own consumers, and a table
/// created before it has a writer is a table nobody maintains.
enum StoreSchema {

    /// The first and, today, only migration.
    static let version1 = "v1"

    /// Every migration this build knows, in the order they apply. Read from the
    /// migrator itself rather than written out again: a hand-kept copy that missed
    /// a future migration would make ``LocalStore`` refuse every store that had
    /// already applied it, as a file from a newer build.
    static var identifiers: [String] { migrator().migrations }

    static let glucoseReadingTable = "glucose_reading"
    static let pumpStatusTable = "pump_status"
    static let insulinDoseTable = "insulin_dose"
    static let rawPumpHistoryTable = "raw_pump_history"

    /// GRDB's own bookkeeping table, which the store does not own and retention
    /// does not touch.
    static let migrationBookkeepingTable = "grdb_migrations"

    /// Every table the retention sweep bounds. Adding a table means adding a line.
    static let retainedTables: [RetainedTable] = [
        RetainedTable(name: glucoseReadingTable, instantColumn: "recorded_at"),
        RetainedTable(name: pumpStatusTable, instantColumn: "observed_at"),
        RetainedTable(name: insulinDoseTable, instantColumn: "completed_at"),
        RetainedTable(name: rawPumpHistoryTable, instantColumn: "recorded_at"),
    ]

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration(version1) { db in
            // Instants are stored as epoch seconds in a REAL column rather than as
            // a formatted string. Uniqueness here means "the same instant", and a
            // text encoding makes that a question about formatting — two encoders
            // that disagree about fractional seconds write two rows for one
            // reading. It also makes the retention sweep a numeric comparison.

            // At most one CGM reading per instant, whatever wrote it. The primary
            // key IS that rule: there is no path, including a direct SQL write,
            // that leaves two readings claiming the same moment.
            //
            // The CHECK is the same argument applied to the VALUE. The write path
            // builds ``SafetyCore/Glucose``, which already refuses outside the
            // absolute bound (AD-5) — but a bound enforced only in Swift is a
            // bound that holds for the code that went through Swift, and this file
            // is a SQLite database that other things can open. The bound is
            // interpolated from ``SafetyCore/SafetyConstants/glucoseValidRange``
            // rather than spelled here: it has one definition site, and a second
            // copy in DDL is a copy that drifts silently. Moving that range is a
            // NEW numbered migration that rebuilds this table, never an edit to
            // this one — devices that already ran v1 will not run it again.
            let absoluteBound = SafetyConstants.glucoseValidRange
            try db.execute(sql: """
                CREATE TABLE glucose_reading (
                    recorded_at REAL NOT NULL PRIMARY KEY,
                    mgdl REAL NOT NULL
                        CHECK (mgdl BETWEEN \(absoluteBound.lowerBound) AND \(absoluteBound.upperBound)),
                    trend TEXT,
                    source TEXT NOT NULL
                )
                """)

            // One pump-status row per instant, on the same rule: a snapshot is
            // what the pump was at one moment, so two rows for one moment is two
            // answers to a question with one.
            try db.execute(sql: """
                CREATE TABLE pump_status (
                    observed_at REAL NOT NULL PRIMARY KEY,
                    battery_fraction REAL,
                    reservoir_units REAL,
                    model_name TEXT,
                    firmware_version TEXT,
                    source TEXT NOT NULL
                )
                """)

            // One completed delivery per CATEGORY per instant, in the key, so the
            // invariant survives a writer that is not this one. A pump delivers
            // basal continuously and boluses on top of it, so a basal segment and
            // a meal bolus completing on the same tick are two real deliveries,
            // not two answers to one question — keying on the instant alone would
            // drop one of them, and which one it dropped would depend on which
            // arrived first. Within one category the rule still bites: a pump
            // cannot have finished two different basal segments at one instant,
            // and admitting both would double-count insulin on board (SI-7,
            // FR-137).
            //
            // The category is what stands in for "basal" here. ``DriverAPI``'s
            // ``DoseCategory`` mirrors Android's bolus-only vocabulary and has no
            // basal case, so a Driver reporting basal delivery reports it as
            // ``DoseCategory/other`` with the device's own label beside it — which
            // means every basal record lands in one category and one-per-category
            // is one-per-basal-segment. It is also the coarsest place the
            // distinction survives: `other` is the catch-all, so a basal segment
            // and some other unmapped delivery finishing at the same instant do
            // compete. Splitting them needs a DriverAPI shape that names basal,
            // and that is its own work.
            //
            // The leading key column is the instant, so the same index the key
            // builds serves the retention sweep and every `since:` read.
            //
            // The CHECK mirrors ``DriverAPI/DoseRecord``'s own refusal. Negative
            // delivered insulin is not a quantity a pump can report; admitted, it
            // understates insulin on board, which is the direction that hides a
            // low.
            try db.execute(sql: """
                CREATE TABLE insulin_dose (
                    completed_at REAL NOT NULL,
                    units REAL NOT NULL CHECK (units >= 0),
                    category TEXT NOT NULL,
                    device_category_label TEXT,
                    source TEXT NOT NULL,
                    PRIMARY KEY (completed_at, category)
                )
                """)

            // Raw history is keyed by the pump's own numbering, so two pumps that
            // both number from zero coexist, and re-reading a log stores nothing
            // new. The separate index on the instant is what the retention sweep
            // uses; the key's leading column is the source, so it cannot serve.
            try db.execute(sql: """
                CREATE TABLE raw_pump_history (
                    source TEXT NOT NULL,
                    sequence_number INTEGER NOT NULL,
                    recorded_at REAL NOT NULL,
                    event_type INTEGER NOT NULL,
                    payload BLOB NOT NULL,
                    PRIMARY KEY (source, sequence_number)
                )
                """)
            try db.execute(sql: """
                CREATE INDEX raw_pump_history_recorded_at
                    ON raw_pump_history (recorded_at)
                """)
        }

        return migrator
    }
}
