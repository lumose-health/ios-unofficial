import Foundation
import GRDB

/// One writer connection per database file, for the life of the process.
///
/// ## Why a registry exists at all
///
/// The store is the sole writer (the Structural Seed says so), and that claim has
/// to mean something mechanical. Without this, "sole writer" is a property of how
/// carefully callers use ``LocalStore/open(at:clock:precedence:)`` — two calls for
/// one path would produce two independent connections, and the collision rules
/// would resolve against rows the other connection has not committed yet: the
/// higher-precedence source loses, intermittently, on a schedule nobody can
/// reproduce.
///
/// ## Sharing, not refusing
///
/// A second open of the same path gets the SAME writer, rather than an error. An
/// app opens its store on launch, and a scene, an extension entry point or a test
/// harness can all reasonably reach for it again; refusing would push every caller
/// into building a singleton of their own, which is this problem moved rather than
/// solved. Sharing keeps the invariant where it can be enforced — one connection
/// per file — while leaving ``LocalStore`` a cheap value that anyone may hold.
///
/// The clock and the precedence order are NOT shared: they belong to the store
/// value, so a caller that opens the same file with a different precedence gets
/// what it asked for over one connection.
///
/// An actor rather than a lock: the state is mutable and reachable from any task,
/// and actor isolation is the version of that the compiler checks. It is the
/// reason ``LocalStore/open(at:clock:precedence:)`` is `async`.
///
/// ## Lifetime
///
/// Registered connections are never dropped. ``LocalStore`` is a value anyone may
/// copy and hold, so closing a connection because this registry stopped tracking
/// it would be a use-after-close in whatever still holds the store; and an app has
/// one store file, so there is nothing here that grows. An open that fails AFTER
/// the connection was made — protection refused, a schema from a newer build —
/// leaves the connection registered and hands the caller the failure. Nothing is
/// written through it, and a retry re-runs those checks rather than remembering
/// their answer.
///
/// ## The constraint that comes with a path key
///
/// The key is a path, and a path can outlive the file it names. If the store file
/// were deleted or replaced while the process is running, a later open would hand
/// back the connection to the old file: on POSIX an unlinked file that is still
/// open keeps working, so writes would keep succeeding into something no other
/// connection can read.
///
/// Nothing in this app does that, and that is a constraint rather than an
/// accident. The store file lives in the app's own container, the retention sweep
/// deletes ROWS, and there is no code path that unlinks or swaps the file. The one
/// feature that would want to, an erase-all-data action or a restore, must go
/// through the store's own connection the way
/// ``LocalStore/sweepExpiredRecords(retaining:)`` does, deleting contents rather
/// than the file. A file-system-level erase would need this registry to be able
/// to retire an entry first, and building that is part of building the feature.
///
/// Keying on file identity instead was considered and not taken: it costs a stat
/// on every open, it still has a window between the check and the use, and it
/// would answer a replacement by handing out a second connection for a path a
/// live ``LocalStore`` value already holds one for: two writers on one path,
/// which is the invariant this type exists to keep.
actor StoreWriters {

    static let shared = StoreWriters()

    private var writers: [String: any DatabaseWriter] = [:]

    /// The writer for `path`, opening one through `make` the first time.
    func writer(
        forPath path: String,
        opening make: @Sendable () throws -> any DatabaseWriter
    ) throws -> any DatabaseWriter {
        if let existing = writers[path] { return existing }
        let opened = try make()
        writers[path] = opened
        return opened
    }

    /// The key a path is registered under: symlinks resolved and the path
    /// standardized, so `/var/…` and `/private/var/…` — which is what a temporary
    /// directory looks like from the two ends of the same lookup — are one entry
    /// rather than two writers on one file.
    nonisolated static func key(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
