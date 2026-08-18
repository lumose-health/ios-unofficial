import Foundation

/// A Driver that provides fingerstick blood-glucose readings.
///
/// Mirrors Android's `BgmSource`
/// (`plugins/pump-driver-api/.../capabilities/BgmSource.kt`), spelled with the
/// acronym uppercased per Swift naming.
///
/// A fingerstick arrives here and stops here. Android pairs its BGM capability
/// with `CALIBRATION_TARGET`, which sends a meter reading back to a sensor; that
/// capability does not exist in this set (see ``Capability``), so a reading a
/// meter produces has no path to any device.
public protocol BGMSource: Sendable {

    /// Fingerstick readings as the meter produces them.
    ///
    /// Single consumer, obtained once, same stream on every read; the contract
    /// is stated in full on ``GlucoseSource/readings``.
    var readings: AsyncStream<FingerstickSample> { get }

    /// The most recent fingerstick the Driver holds, or `nil` if it holds none.
    ///
    /// Side-effect free: it reports what the Driver already has and never asks
    /// the meter for a measurement.
    func latestReading() async throws(DriverFailure) -> FingerstickSample?
}
