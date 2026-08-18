import Foundation

/// The states a Driver can be in, declared ONCE for every Driver (AD-16).
///
/// Five implementers are coming — Tandem, Medtronic, Simulated, Trace-Replay and
/// the app-hosted Nightscout source. Without one declaration here they invent
/// five lifecycles, and the platform grows five recovery paths and five ways to
/// be half-connected. A Driver that needs a state this enum does not declare is a
/// `DriverAPI` change, not a local addition.
public enum DriverLifecycleState: String, CaseIterable, Hashable, Sendable {

    /// The Driver exists in the catalog and is doing nothing. The resting state,
    /// and the state teardown returns to.
    case notActivated

    /// The platform has called ``Driver/activate()`` and it has not returned yet.
    case activating

    /// Running, and providing everything its descriptor claims.
    case active

    /// Running, but NOT providing everything it claims — the pump is out of
    /// range, one capability's stream has dried up, a sync destination is
    /// refusing writes.
    ///
    /// A distinct state rather than a flag on ``active``, because the Coverage
    /// Claim must never overstate what is being watched (SI-6). A degraded Driver
    /// rendered as active is exactly that overstatement.
    case degraded

    /// The platform has called ``Driver/deactivate()`` and it has not returned.
    case deactivating

    /// The Driver stopped for a reason it cannot recover from on its own. The
    /// platform decides whether to retry; the Driver does not retry itself.
    case failed

    /// The states this state may legally move to.
    ///
    /// The table is here, on the state, rather than in whichever unit happens to
    /// drive transitions — the legal moves are a property of the lifecycle, and a
    /// second unit driving Drivers must obey the same table as the first.
    ///
    /// Self-transitions appear where repetition is expected rather than
    /// exceptional: ``notActivated`` to itself and ``deactivating`` to itself
    /// exist so that TEARDOWN IS IDEMPOTENT — a second ``Driver/deactivate()``,
    /// or one on a Driver that was never activated, is a no-op and not an error.
    /// ``failed`` to itself exists because a Driver can fail again, for a
    /// different reason, before anyone tears it down.
    ///
    /// ``active`` and ``degraded`` also permit themselves, so RE-ASSERTING the
    /// running state is an idempotent no-op rather than a platform bug: a
    /// Driver already degraded because its pump is out of range degrades again
    /// when a second capability's stream dries up, and a restoration re-entry
    /// can report a state the platform already holds. Neither self-transition
    /// reaches a Driver entry point — ``Driver/activate()`` runs only on entry
    /// into ``activating``, and ``activating`` to itself stays refused, so a
    /// second activation can never start while one is in flight.
    public var permittedSuccessors: Set<DriverLifecycleState> {
        switch self {
        case .notActivated:
            return [.activating, .notActivated]
        case .activating:
            return [.active, .degraded, .deactivating, .failed]
        case .active:
            return [.active, .degraded, .deactivating, .failed]
        case .degraded:
            return [.active, .degraded, .deactivating, .failed]
        case .deactivating:
            return [.notActivated, .deactivating, .failed]
        case .failed:
            return [.activating, .deactivating, .failed]
        }
    }

    /// Whether this state may move to `next`.
    public func permits(_ next: DriverLifecycleState) -> Bool {
        permittedSuccessors.contains(next)
    }
}

/// The lifecycle state of one Driver, and the only way to change it (AD-16).
///
/// ## Why a Driver cannot reach this
///
/// The platform owns every transition, and that is enforced by ACCESS rather than
/// by convention. This whole type is SPI: it is visible only to a module that
/// writes
///
/// ```swift
/// @_spi(DriverPlatform) import DriverAPI
/// ```
///
/// An ordinary `import DriverAPI` — what a Driver target writes — does not see
/// `DriverLifecycle` at all, so a Driver that tries to hold one, construct one or
/// advance one does not compile. Swift has no notion of a friend module, and SPI
/// is the nearest thing it does have: the capability is granted by an import that
/// names itself, in a file, in a diff.
///
/// The second half of the enforcement is mechanical, because the first half can be
/// defeated by typing the SPI import into a Driver: `scripts/guards/driver_guards.sh`
/// fails when any file under `Sources/Drivers/` carries an `@_spi` import. So a
/// self-transitioning Driver either does not build or does not pass the gate.
///
/// The rest of the shape supports the same claim: ``Driver`` declares entry points
/// the platform CALLS and no member that reports or mutates lifecycle state, so
/// there is nothing for a Driver to transition even if it could see this type.
///
/// A value type rather than a class, so a stale copy cannot be mutated behind the
/// platform's back: `advance` mutates in place, and every holder of a copy holds
/// a snapshot of a past state, not a second handle on the live one.
@_spi(DriverPlatform)
public struct DriverLifecycle: Hashable, Sendable {

    /// The current state. Readable by the platform, changeable only through
    /// ``advance(to:)``.
    public private(set) var state: DriverLifecycleState

    /// A Driver that has not been activated.
    public init() {
        self.state = .notActivated
    }

    /// Starts the lifecycle in `state`, for restoring a platform-held lifecycle
    /// after a Core Bluetooth restoration relaunch (AD-11).
    public init(restoring state: DriverLifecycleState) {
        self.state = state
    }

    /// Moves to `next`.
    ///
    /// - Throws: ``DriverFailure/illegalTransition(from:to:)`` when the table on
    ///   ``DriverLifecycleState/permittedSuccessors`` does not allow the move.
    ///   Throwing rather than trapping is deliberate: this runs during background
    ///   wakes and restoration re-entry, where killing the process is worse than
    ///   surfacing the bug (AD-13).
    public mutating func advance(to next: DriverLifecycleState) throws(DriverFailure) {
        guard state.permits(next) else {
            throw .illegalTransition(from: state, to: next)
        }
        state = next
    }
}
