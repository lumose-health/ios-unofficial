import Foundation

/// Every way a Driver can fail, declared ONCE (AD-13, spine §141).
///
/// One enum, not one per Driver. Two Drivers with incomparable taxonomies force
/// every consumer to special-case each Driver, and the consumer that has not been
/// updated for the newest Driver is the one that silently swallows its errors. A
/// Driver that needs a failure this enum does not name is a `DriverAPI` change,
/// deliberate and reviewed, not a local `enum TandemError`.
///
/// A module-local error enum is still permitted inside a Driver for a failure
/// **no other unit consumes** — a parser's internal framing error, say. The moment
/// another unit branches on it, it belongs here.
///
/// ## Recovery has a named owner
///
/// `DomainCore` owns recovery for these; `AppFeature` owns what the user sees. No
/// unit silently absorbs a failure it did not originate (AD-13).
///
/// ## Decode failure and value rejection are not the same thing
///
/// ``decodeFailed(detail:)`` and ``valueRejected(bound:)`` look similar and must
/// never be merged (AD-22). Bytes that would not parse mean the record was not
/// consumed and the read cursor does NOT advance, so it will be retried. A record
/// that parsed cleanly and carried an out-of-range number IS consumed, the cursor
/// DOES advance, and the value is dropped. Treating the second as the first wedges
/// history forever behind a value that will never become valid — and since a
/// narrowed Safety Limit is what makes a value out-of-range, that wedge is
/// remotely triggerable.
///
/// Non-finite numbers land on the VALUE side of that line. The model
/// initializers in `Models/` are post-parse validators: a frame whose bytes did
/// not parse must surface ``decodeFailed(detail:)`` before any model is
/// constructed, so a NaN or infinite quantity that reaches an initializer was
/// extracted from a frame whose structure parsed. Re-reading that record yields
/// the same bits and the same NaN, so classifying it decode-class would hold the
/// cursor behind it forever — the exact wedge this distinction exists to
/// prevent. The record is consumed, the cursor advances, the value is dropped.
public enum DriverFailure: Error, Hashable, Sendable {

    /// No pairing credential exists for this device yet. The user must pair it.
    case notPaired

    /// A pairing credential exists and the device rejected it — the pump was
    /// re-paired elsewhere, or the credential was rotated. Distinct from
    /// ``notPaired`` because the recovery is different: re-pair, not pair.
    case authenticationRejected

    /// The transport itself is unavailable: Bluetooth off, permission not
    /// granted, no network for a sync destination. Nothing about the device is
    /// known, and retrying without the transport returning is pointless.
    case transportUnavailable

    /// The device was reachable and is not any more — out of range, or it dropped
    /// the link. Retrying is reasonable.
    case connectionLost

    /// The device did not answer within the Driver's own bound.
    case timedOut

    /// Bytes could not be parsed. The record is NOT consumed and the read cursor
    /// does not advance (AD-19, AD-22). `detail` names the frame or field, never
    /// its contents — a payload in a log line is a health value in a log line
    /// (SI-9).
    case decodeFailed(detail: String)

    /// A record parsed cleanly and carried a value outside the bound in force.
    /// The record IS consumed, the cursor advances, the value is dropped
    /// (AD-22). `bound` names the bound that rejected it, so the user can be told
    /// which limit is doing the rejecting.
    ///
    /// `bound` is a DIAGNOSTIC description — stable, English,
    /// locale-independent — for logs and support conversations. It is not the
    /// sentence a screen shows: the presentation layer says which limit
    /// rejected the reading by formatting the limits in force at the display
    /// boundary (the way `GlucoseFormatter` formats readings), never by
    /// rendering or parsing this string.
    case valueRejected(bound: String)

    /// The Driver does not provide the Capability that was asked of it. A
    /// programming error in the platform, surfaced rather than absorbed.
    case capabilityUnavailable(Capability)

    /// The device reported a fault in its own vocabulary. `code` is the device's
    /// code, kept verbatim so a support conversation can name it.
    case deviceFault(code: String)

    /// A lifecycle transition the state machine does not permit was attempted
    /// (AD-16). The platform owns transitions, so this is a platform bug — and it
    /// is a failure rather than a trap because a Core Bluetooth restoration can
    /// re-enter a Driver in a state the platform did not expect, and killing the
    /// process during a background wake is the one outcome worse than the bug.
    case illegalTransition(from: DriverLifecycleState, to: DriverLifecycleState)

    /// A ``SafetyLimits`` value was refused. The bounds in force are unchanged —
    /// last-known-good stays in force, nothing is clamped (SI-11, AD-13).
    case safetyLimitRejected(SafetyLimitRejection)

    /// The work was cancelled — the platform tore the Driver down, or the task
    /// was cancelled. Not an error condition to report to the user.
    case cancelled
}

/// Why a ``SafetyLimits`` value was refused (SI-11).
///
/// A payload on ``DriverFailure/safetyLimitRejected(_:)`` rather than a second
/// error type: the taxonomy stays single, and the reason stays branchable. The
/// rejected numbers travel with it so the user can be shown the bound that failed
/// instead of a generic refusal.
public enum SafetyLimitRejection: Hashable, Sendable {

    /// The requested bounds reach outside the absolute range. Limits NARROW the
    /// absolute bound or match it; they never widen it, in either direction.
    case widensAbsoluteBound(lower: Double, upper: Double)

    /// A bound was NaN or infinite.
    case notFinite

    /// The lower bound was not below the upper bound — an empty or inverted range
    /// admits nothing and would silently reject every reading.
    case emptyOrInverted(lower: Double, upper: Double)
}
