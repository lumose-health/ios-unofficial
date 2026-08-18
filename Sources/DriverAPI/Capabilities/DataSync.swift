import Foundation

/// A Driver that mirrors data to an external service the user already runs.
///
/// Mirrors Android's `DATA_SYNC` capability. Android declares the capability but
/// no interface for it; this is the shape it takes here.
///
/// ## Why this port carries no `sync()`
///
/// Mirroring is the one capability in the closed set whose data flows outward,
/// so it is the one where a command member would look reasonable. It has none.
/// The four members below DECLARE what the Driver will mirror and REPORT what it
/// is doing; when mirroring happens is lifecycle, driven by the platform through
/// ``Driver/activate()`` and ``Driver/deactivate()`` (AD-16).
///
/// That is not pedantry about AC wording. A `sync()` on this port is a member any
/// consumer can call, and the first consumer that calls it on a timer is the one
/// that turns a user's glucose history into an outbound request they did not ask
/// for. Keeping the trigger with the platform keeps consent in one place.
public protocol DataSync: Sendable {

    /// Where this Driver mirrors to, for the user to see before anything leaves.
    var destination: SyncDestination { get }

    /// What this Driver is willing to mirror. A declaration, not a command.
    var mirroredRecords: Set<MirroredRecordKind> { get }

    /// What the Driver is doing now, as it changes.
    ///
    /// Single consumer, obtained once, same stream on every read; the contract
    /// is stated in full on ``GlucoseSource/readings``.
    var state: AsyncStream<SyncState> { get }

    /// When the last mirror succeeded, or `nil` if none has.
    ///
    /// Side-effect free: it reports the Driver's own record of the last success.
    /// It does not contact the destination to ask.
    func lastMirroredAt() async throws(DriverFailure) -> Date?
}
