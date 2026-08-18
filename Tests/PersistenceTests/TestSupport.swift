import Foundation
import SQLite3
import DriverAPI
import SafetyCore
@testable import Persistence

/// A clock that never moves, so every age and every retention horizon in these
/// tests is a value the test wrote rather than one it waited for (AD-14).
struct FixedClock: SafetyCore.Clock {
    let now: Date
}

/// An instant, built from an offset rather than from the wall clock so the whole
/// suite is reproducible.
///
/// The base is arbitrary and deliberately not "now": a test that passes only
/// while the machine's date is inside some window is a test that fails on a
/// build machine one day.
func instant(_ offsetSeconds: TimeInterval = 0) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + offsetSeconds)
}

/// One day, as the retention window measures it.
let oneDay: TimeInterval = 86_400

/// Records what the store asked to protect, instead of protecting it.
///
/// On macOS — where these gates run — the real attribute is a no-op, so a test
/// that read the file's attributes back would assert nothing at all. This
/// observes the store's INTENT: which files it protected, with which class, and
/// in which order. The attribute itself is verified on a device.
///
/// `@unchecked Sendable` with a lock, and this is the only opt-out in the package.
/// The protection seam is `Sendable` because the store applies it inside an async
/// open, and a recording double is mutable by definition — an actor cannot conform,
/// since the seam's method is synchronous. Every access to the recording goes
/// through `lock`, and in practice the store calls this serially from one task and
/// the test reads it after the open has returned.
final class RecordingFileProtection: StoreFileProtecting, @unchecked Sendable {

    private let lock = NSLock()
    private var calls: [(path: String, protection: StoreProtectionClass)] = []
    private var refusedSuffix: String?

    /// Every call, in order.
    var applied: [(path: String, protection: StoreProtectionClass)] {
        lock.withLock { calls }
    }

    /// When set, any path ending in this suffix is refused — the path where the
    /// platform will not protect a file the store is about to write to.
    var refusePathsEnding: String? {
        get { lock.withLock { refusedSuffix } }
        set { lock.withLock { refusedSuffix = newValue } }
    }

    func protect(itemAt url: URL, as protection: StoreProtectionClass) throws {
        if let refusePathsEnding, url.path.hasSuffix(refusePathsEnding) {
            throw ProtectionRefused()
        }
        lock.withLock { calls.append((url.path, protection)) }
    }

    struct ProtectionRefused: Error {}

    func protectedPaths() -> [String] { applied.map(\.path) }
}

/// A directory that does not exist yet, so the store is the one that creates it.
///
/// Each test gets its own, and takes it away when it is released: a suite that
/// shared one database would have tests that pass in isolation and fail in a run,
/// and one writer connection per path means two tests on one path would share it.
final class TemporaryStoreLocation {

    let directory: URL

    var databaseURL: URL { directory.appendingPathComponent("store.sqlite") }

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceTests-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A second, entirely independent SQLite connection to a store file — the thing
/// the schema's constraints have to hold against.
///
/// Deliberately NOT the store, and deliberately not GRDB: what these tests need to
/// model is another program opening the file, so they open it the way another
/// program would. That is also why the package's SQL vendor stays behind
/// `Sources/Persistence/` — nothing here imports it.
struct RawSQLiteFile {

    let path: String

    struct Refused: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    init(_ url: URL) {
        self.path = url.path
    }

    /// Runs `sql` — one statement or several — on its own connection.
    func execute(_ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open \(path)"
            sqlite3_close(handle)
            throw Refused(message: message)
        }
        defer { sqlite3_close(handle) }
        // The store holds this file open; a moment of contention is not the thing
        // under test.
        sqlite3_busy_timeout(handle, 2_000)

        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard code == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "sqlite refused with code \(code)"
            sqlite3_free(errorMessage)
            throw Refused(message: message)
        }
    }
}

/// A source, for tests that only care that one exists.
func source(_ identifier: String) throws -> StoreSource {
    try StoreSource(identifier)
}

/// A CGM sample in range, built the only way one can be built.
func sample(_ mgdl: Double, at recordedAt: Date, trend: GlucoseTrend? = nil) throws -> GlucoseSample {
    GlucoseSample(glucose: try Glucose(mgdl: mgdl), recordedAt: recordedAt, trend: trend)
}

/// A pump-status snapshot with a battery reading and nothing else, for tests that
/// need a snapshot rather than a particular one.
func snapshot(battery: Double, at observedAt: Date) throws -> PumpStatusSnapshot {
    try PumpStatusSnapshot(batteryFraction: battery, observedAt: observedAt)
}

/// A completed insulin delivery, for tests that need one rather than a particular
/// one.
func dose(
    _ units: Double,
    at completedAt: Date,
    category: DoseCategory = .correction,
    deviceLabel: String? = nil
) throws -> DoseRecord {
    try DoseRecord(
        units: units,
        completedAt: completedAt,
        category: category,
        deviceCategoryLabel: deviceLabel
    )
}
