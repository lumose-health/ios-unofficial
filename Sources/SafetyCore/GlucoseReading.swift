import Foundation

/// A glucose value with the instant it was measured.
///
/// The smallest thing that is both a reading and time-dependent, so it is where
/// the ``Clock`` contract (AD-14) first shows its shape: age is asked *of a
/// clock*, never of the wall clock.
public struct GlucoseReading: Hashable, Sendable {

    /// The canonical mg/dL value (SI-3).
    public let glucose: Glucose

    /// When the value was measured — not when it was received or displayed.
    public let timestamp: Date

    public init(glucose: Glucose, timestamp: Date) {
        self.glucose = glucose
        self.timestamp = timestamp
    }

    /// How old this reading is according to `clock`.
    ///
    /// Negative when the timestamp is in the future relative to the clock, which
    /// happens with ordinary device/pump clock skew. This type reports the signed
    /// age and leaves the interpretation to the caller: whether a small negative
    /// age reads as "just now" and a large one as "unknown time" is a freshness
    /// policy, and policy does not belong in the value type.
    public func age(asOf clock: some Clock) -> TimeInterval {
        clock.now.timeIntervalSince(timestamp)
    }
}
