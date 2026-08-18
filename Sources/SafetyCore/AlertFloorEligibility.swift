import Foundation

/// The single definition of whether a reading's age is fresh enough to arm the
/// alert floor (AD-14, SI-5) — epic 2 consumes this instead of writing its own
/// staleness check.
///
/// Stricter than display freshness (mirrors Android `isFreshForAlertFloor`,
/// `Freshness.kt:79`): a negative age reads as Fresh for **display** — see
/// ``FreshnessThresholds/classify(age:)`` — but here a reading future-dated beyond
/// ``maxFutureSkew`` fails outright, so a forward-skewed sensor timestamp cannot
/// arm an alarm it should not.
public enum AlertFloorEligibility {

    /// Max future-dated skew the alert floor tolerates before refusing to treat a
    /// reading as fresh (Android `ALERT_FLOOR_MAX_FUTURE_SKEW_MS`, `Freshness.kt:59`).
    /// Pump and phone clocks drift by seconds in ordinary operation; a hard
    /// `age >= 0` would silently disable the floor whenever the pump clock runs
    /// slightly ahead of the phone's.
    ///
    /// The value itself lives in ``SafetyConstants`` — this is the guarded
    /// single definition site for a cross-target safety value, not a copy.
    public static let maxFutureSkew: TimeInterval = SafetyConstants.alertFloorMaxFutureSkew

    /// True only when a reading of the given `age` may arm the alert floor.
    ///
    /// Within ``maxFutureSkew`` of the future, and strictly ``Freshness/fresh`` once
    /// negative skew is floored to zero — ``Freshness/stale`` and
    /// ``Freshness/tooStale`` both fail, same as Android.
    public static func isEligible(age: TimeInterval, thresholds: FreshnessThresholds) -> Bool {
        age >= -maxFutureSkew && thresholds.classify(age: max(age, 0)) == .fresh
    }
}
