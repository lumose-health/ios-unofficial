import Foundation

/// A Driver that provides continuous glucose readings.
///
/// Mirrors Android's `GlucoseSource`
/// (`plugins/pump-driver-api/.../capabilities/GlucoseSource.kt`).
///
/// Both members are reads. There is nothing here to call that changes anything
/// on the device — that is AD-12 expressed structurally rather than by review:
/// the write does not exist to be found.
public protocol GlucoseSource: Sendable {

    /// Readings as the sensor produces them.
    ///
    /// The stream is the primary surface; ``latestReading()`` exists for a cold
    /// start, not as an alternative to observing. A consumer that polls this
    /// capability instead of observing it will miss readings, because a Driver
    /// is free to drop a sample it has already emitted.
    ///
    /// SINGLE consumer, obtained once. `AsyncStream` does not broadcast: two
    /// iterators of one stream SPLIT the elements between them, each silently
    /// missing what the other consumed — for this stream, missing glucose
    /// readings with no error anywhere. The platform is the one consumer;
    /// anything else that wants readings observes what the platform stores,
    /// never this port. A Driver vends the SAME stream on every read of this
    /// property, so the getter is side-effect free and a re-read is not a
    /// fresh subscription. Every stream on a Capability port carries this
    /// contract.
    var readings: AsyncStream<GlucoseSample> { get }

    /// The most recent reading the Driver holds, or `nil` if it holds none.
    ///
    /// Side-effect free: it reports what the Driver already has and never
    /// solicits a fresh measurement from the sensor.
    func latestReading() async throws(DriverFailure) -> GlucoseSample?
}
