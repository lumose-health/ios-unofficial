import Foundation

/// What every Driver implements: an identity, a set of Capability ports, and two
/// entry points the platform calls (AD-16).
///
/// ## What is NOT here, and why
///
/// There is no `state` member and no way to set one. The lifecycle lives in
/// ``DriverLifecycle``, which the platform holds and the Driver is never given —
/// so "a Driver never self-transitions" is structural rather than a rule someone
/// has to remember. The two members below are entry points: the platform calls
/// them and moves the state itself, before and after.
///
/// There is likewise no member that reaches a pump. Every therapeutic write is
/// absent from the entire `DriverAPI` surface, so a Driver has nothing to call
/// (AD-12, SI-1), and `scripts/guards/driver_guards.sh` fails the build if a
/// delivery verb or a pump-write characteristic identifier appears in this target
/// or in any Driver.
///
/// ## When each entry point is called, exactly
///
/// The transition table on ``DriverLifecycleState/permittedSuccessors`` is the
/// contract, and these two members are described in its terms rather than in
/// prose that can drift from it:
///
/// * ``activate()`` is called once per entry into
///   ``DriverLifecycleState/activating``, which the table permits only from
///   ``DriverLifecycleState/notActivated`` and ``DriverLifecycleState/failed``.
///   A Driver that is running is therefore never re-activated, and `activate()`
///   never has to defend against a second platform call arriving while the first
///   is still in flight.
/// * ``deactivate()`` is called on entry into
///   ``DriverLifecycleState/deactivating``, and also on a Driver that was never
///   activated at all — the table permits `notActivated → notActivated` and
///   `deactivating → deactivating` precisely so that teardown is idempotent.
///
/// Both are REPEATABLE across the life of one instance. Core Bluetooth
/// restoration relaunches the app and re-enters a Driver after termination
/// (AD-11), and a Driver that failed is activated again from
/// ``DriverLifecycleState/failed`` without a fresh instance, so neither method
/// may assume it runs once.
public protocol Driver: Actor {

    /// What this Driver is, as the catalog and the Drivers screen describe it.
    ///
    /// Constant for the lifetime of the Driver: it is compile-time metadata, and
    /// the catalog's copy of it must not be able to drift from the instance's.
    nonisolated var descriptor: DriverDescriptor { get }

    /// The Capability ports this instance provides, one per declared
    /// ``Capability`` in ``DriverDescriptor/capabilities``.
    ///
    /// The return type is ``CapabilityPort`` — a six-case enum — and not an
    /// erased marker protocol. That is the closed set made structural: there is
    /// no supertype a Driver can conform a seventh capability to, so there is no
    /// case to hand a seventh capability back in.
    ///
    /// The enum does NOT make the port payloads non-downcastable — see the seam
    /// documented on ``CapabilityPort``, and the consumer-cast rule in
    /// `scripts/guards/driver_guards.sh` that forbids the narrowing step.
    ///
    /// - Returns: the port, or `nil` if this Driver does not provide `capability`.
    ///   A Driver whose descriptor claims a Capability must return a port for it,
    ///   and the port returned must be the one `capability` names; the platform
    ///   surfaces either mismatch as ``DriverFailure/capabilityUnavailable(_:)``
    ///   rather than absorbing it.
    func capability(_ capability: Capability) -> CapabilityPort?

    /// Brings the Driver up.
    ///
    /// Called by the platform on entry into ``DriverLifecycleState/activating``,
    /// which the transition table permits only from
    /// ``DriverLifecycleState/notActivated`` and ``DriverLifecycleState/failed``.
    /// The platform moves to ``DriverLifecycleState/active`` or
    /// ``DriverLifecycleState/failed`` when it returns.
    ///
    /// Repeatable, not re-entrant: the platform never calls it on a Driver that
    /// is already running, because the table refuses that transition — but it
    /// does call it again on the same instance after a teardown or a failure, so
    /// it must not assume it runs once.
    ///
    /// - Throws: any ``DriverFailure``. Throwing leaves the platform to decide
    ///   recovery; the Driver does not retry itself.
    func activate() async throws(DriverFailure)

    /// Tears the Driver down.
    ///
    /// IDEMPOTENT, and that is a contract term: calling it twice, calling it on a
    /// Driver that was never activated, and calling it while a previous teardown
    /// is still running must all be safe and must all end with the Driver holding
    /// no connection, no timer and no subscription. It does not throw — teardown
    /// that can fail is teardown a caller has to retry, and a caller that gets it
    /// wrong leaks a live Bluetooth link across a restoration cycle.
    ///
    /// The platform moves the lifecycle to ``DriverLifecycleState/deactivating``
    /// before and ``DriverLifecycleState/notActivated`` after.
    func deactivate() async
}
