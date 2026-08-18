import Foundation

/// A Driver that reports insulin on board and completed dose history, read-only.
///
/// Mirrors Android's `InsulinSource`
/// (`plugins/pump-driver-api/.../capabilities/InsulinSource.kt`), minus the
/// `SafetyLimits` parameter Android threads through `getBolusHistory`. Here the
/// limits are read fresh at the validation boundary instead (``SafetyLimits``),
/// so a stale copy cannot be captured by a Driver and reused after the user
/// narrows their range.
public protocol InsulinSource: Sendable {

    /// Insulin on board as the device recalculates it.
    ///
    /// Single consumer, obtained once, same stream on every read; the contract
    /// is stated in full on ``GlucoseSource/readings``.
    var insulinOnBoard: AsyncStream<InsulinOnBoardSample> { get }

    /// Doses the device COMPLETED at or after `since`, oldest first (SI-7).
    ///
    /// Side-effect free with respect to the device: it reads history. It may
    /// advance the Driver's own read cursor, and that cursor obeys AD-19 — a
    /// record whose bytes did not parse leaves the cursor where it was and
    /// surfaces ``DriverFailure/decodeFailed(detail:)``, while a record that
    /// parsed and carried an out-of-range value is consumed, dropped, and
    /// reported as ``DriverFailure/valueRejected(bound:)`` (AD-22). Conflating
    /// the two wedges history behind a value that will never become valid.
    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord]
}
