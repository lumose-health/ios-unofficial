import Foundation

/// A Driver that reports pump hardware state, read-only.
///
/// Mirrors Android's `PumpStatus`
/// (`plugins/pump-driver-api/.../capabilities/PumpStatus.kt`), named
/// `…Source` here to match the convention that a port is a capability noun
/// (`GlucoseSource`), never a `…Manager` or a `…Service`.
///
/// Android's version also carries `disconnectAndForget` and the history-log
/// extraction helpers. Neither is here: disconnection is lifecycle, owned by the
/// platform (``Driver/deactivate()``, AD-16), and parsing is a Driver's private
/// business, not part of the contract every consumer sees.
public protocol PumpStatusSource: Sendable {

    /// Hardware state as the pump reports it changing.
    ///
    /// Single consumer, obtained once, same stream on every read; the contract
    /// is stated in full on ``GlucoseSource/readings``.
    var status: AsyncStream<PumpStatusSnapshot> { get }

    /// The most recent state the Driver holds, or `nil` if it holds none.
    ///
    /// Side-effect free: it reports what the Driver already has. It does not wake
    /// the pump, and it does not wait for the next frame.
    func latestStatus() async throws(DriverFailure) -> PumpStatusSnapshot?
}
