import Foundation
import DriverAPI
import SafetyCore

/// Every way the on-device store refuses, declared ONCE.
///
/// One enum for the whole unit, the same posture `DriverFailure` takes for the
/// Driver boundary (AD-13): a consumer that has to branch on a different error
/// taxonomy per call site is a consumer that will miss one. `DomainCore` owns
/// recovery for these; nothing silently absorbs a failure it did not originate.
///
/// ## Why a refusal and not a repair
///
/// Every case below is a place the store could have guessed instead: clamped a
/// glucose value into range, kept whichever row arrived last, trimmed a retention
/// window to something it liked. A guess produces a database that looks right and
/// is not, and there is no later point at which the guess announces itself
/// (AD-5). So the store hands the decision back.
public enum PersistenceFailure: Error, Hashable, Sendable {

    /// A glucose value did not survive ``SafetyCore/Glucose``'s absolute bound.
    ///
    /// Carries the underlying reason — out of range, or not a finite number — so
    /// a caller can tell a plausible-looking number the bound rejects from a
    /// decode artefact. The rejected value is in the payload for logging; it must
    /// never be displayed as a reading.
    case glucoseRejected(GlucoseError)

    /// A stored insulin delivery did not survive ``DriverAPI/DoseRecord``'s own
    /// refusal on the way back out.
    ///
    /// Writes cannot produce this: a `DoseRecord` exists only if its initializer
    /// accepted it. A read that produces it means the row came from somewhere
    /// else, and a quantity no pump could have delivered must not reach the
    /// insulin summary — it would understate or poison insulin on board, the
    /// direction that hides a low.
    case doseRejected(DriverFailure)

    /// A source identifier was empty or carried surrounding whitespace.
    ///
    /// Source identity decides collisions, so a source that is sometimes
    /// `"tandem"` and sometimes `" tandem "` is two sources, and the precedence
    /// order silently stops applying to one of them.
    case sourceRejected(identifier: String)

    /// A precedence order listed the same source twice, so "which of these two
    /// ranks higher" had two answers.
    case precedenceRejected(detail: String)

    /// A retention window outside the settable range.
    case retentionOutOfRange(days: Int)

    /// A row already exists for this key, from the SAME source, carrying
    /// different values.
    ///
    /// Precedence cannot break this tie — both candidates have identical standing
    /// — and picking one by arrival order would make the stored value depend on
    /// the order a replay happened to run in. A source contradicting itself is
    /// something the caller has to see.
    case conflictingRecord(detail: String)

    /// The file carries migrations this build does not know, so it was written by
    /// a newer version of the app. Migrations are forward-only: there is no
    /// downgrade path, and running the older schema against the newer file would
    /// read columns whose meaning it does not have.
    case schemaFromNewerVersion(applied: [String])

    /// At-rest protection could not be applied to a file the store owns.
    ///
    /// Fatal to opening the store, deliberately. A database that opened but is
    /// unprotected is worse than one that did not open: it works, so nobody looks
    /// at it again.
    case protectionUnavailable(path: String, detail: String)

    /// SQLite, or the file system underneath it, refused. Carries the underlying
    /// description rather than a code, because the recoverer is a human reading a
    /// diagnostic, not a branch.
    case storageFailed(detail: String)
}
