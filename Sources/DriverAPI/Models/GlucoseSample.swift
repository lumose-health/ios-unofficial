import Foundation
import SafetyCore

/// One continuous-glucose reading, as a Driver hands it to the platform.
///
/// The value is a ``SafetyCore/Glucose``, so a sample that exists is in range —
/// there is no path by which an out-of-bound number becomes a sample and then a
/// displayed reading (AD-5, SI-2). A Driver that decodes an out-of-range number
/// throws ``DriverFailure/valueRejected(bound:)`` instead of constructing one.
public struct GlucoseSample: Hashable, Sendable {

    /// The reading itself, canonical mg/dL (SI-3).
    public let glucose: Glucose

    /// When the SENSOR produced the reading — not when the Driver decoded it.
    ///
    /// Freshness is judged against this instant (``SafetyCore/Freshness``), so a
    /// Driver that substitutes its own receive time makes a stale reading look
    /// fresh. A pump epoch is converted at the Driver boundary and never leaks
    /// inward.
    public let recordedAt: Date

    /// The direction the sensor reports, when it reports one.
    public let trend: GlucoseTrend?

    public init(glucose: Glucose, recordedAt: Date, trend: GlucoseTrend? = nil) {
        self.glucose = glucose
        self.recordedAt = recordedAt
        self.trend = trend
    }
}

/// The rate-of-change arrow a CGM reports alongside a reading.
///
/// A closed vocabulary rather than a raw number: sensors disagree about the units
/// and the smoothing behind their arrows, so the shared shape is the arrow. A
/// Driver whose sensor reports a direction this vocabulary does not name maps it
/// to ``unknown`` rather than to the nearest-looking neighbour.
public enum GlucoseTrend: String, CaseIterable, Hashable, Sendable {
    case fallingQuickly
    case falling
    case fallingSlowly
    case steady
    case risingSlowly
    case rising
    case risingQuickly

    /// The sensor reported a direction, and it is not one of the above.
    case unknown
}

/// One fingerstick reading from a blood-glucose meter.
///
/// Distinct from ``GlucoseSample`` because the two are not interchangeable
/// upstream: a fingerstick is a point measurement of blood, a CGM sample is an
/// interpolated measurement of interstitial fluid, and they disagree by design.
/// Collapsing them into one type is how a meter reading ends up decaying on a
/// CGM's freshness schedule.
public struct FingerstickSample: Hashable, Sendable {

    /// The reading itself, canonical mg/dL (SI-3).
    public let glucose: Glucose

    /// When the METER produced the reading.
    public let recordedAt: Date

    public init(glucose: Glucose, recordedAt: Date) {
        self.glucose = glucose
        self.recordedAt = recordedAt
    }
}
