import Foundation

/// The age boundaries at which a reading's ``Freshness`` tier changes (FR-49).
///
/// Boundaries are half-open, matching Android `FreshnessThresholds` (`Freshness.kt:29`)
/// exactly: `age < staleAfter` is ``Freshness/fresh``, `staleAfter <= age <
/// tooStaleAfter` is ``Freshness/stale``, and `age >= tooStaleAfter` is
/// ``Freshness/tooStale``. So a reading exactly `staleAfter` old is Stale, and one
/// exactly `tooStaleAfter` old is TooStale — the lower tier ends one instant before
/// its boundary, not at it.
public struct FreshnessThresholds: Hashable, Sendable {

    /// The age, in seconds, at which ``Freshness/fresh`` flips to ``Freshness/stale``.
    public let staleAfter: TimeInterval

    /// The age, in seconds, at which ``Freshness/stale`` flips to ``Freshness/tooStale``.
    public let tooStaleAfter: TimeInterval

    /// - Throws: ``FreshnessThresholdsError/invalidBounds(staleAfter:tooStaleAfter:)``
    ///   unless both bounds are finite and `0 < staleAfter < tooStaleAfter` — same
    ///   AD-5 discipline as ``Glucose``: invalid bounds are a caller error to
    ///   handle, not a crash. Finiteness matters on its own: an infinite
    ///   `tooStaleAfter` would satisfy the ordering check yet build a policy under
    ///   which no reading ever becomes ``Freshness/tooStale``.
    public init(staleAfter: TimeInterval, tooStaleAfter: TimeInterval) throws {
        guard staleAfter.isFinite, tooStaleAfter.isFinite,
              staleAfter > 0, staleAfter < tooStaleAfter else {
            throw FreshnessThresholdsError.invalidBounds(staleAfter: staleAfter, tooStaleAfter: tooStaleAfter)
        }
        self.staleAfter = staleAfter
        self.tooStaleAfter = tooStaleAfter
    }

    /// Classifies a signed age (seconds) against these bounds.
    ///
    /// A negative age — clock skew, a future-dated reading — is always
    /// ``Freshness/fresh``: negative is less than `staleAfter`, which is always
    /// positive. Deciding whether that reading may drive an alert is a separate,
    /// stricter question; see ``AlertFloorEligibility``.
    public func classify(age: TimeInterval) -> Freshness {
        if age < staleAfter { return .fresh }
        if age < tooStaleAfter { return .stale }
        return .tooStale
    }

    /// Convenience: classify a reading directly from its age at `clock`, so callers
    /// do not compute the intermediate age themselves.
    public func classify(_ reading: GlucoseReading, asOf clock: some Clock) -> Freshness {
        classify(age: reading.age(asOf: clock))
    }
}

/// The reason a ``FreshnessThresholds`` could not be constructed.
public enum FreshnessThresholdsError: Error, Hashable, Sendable {

    /// A bound was not finite, `staleAfter` was not strictly positive, or
    /// `staleAfter` was not strictly less than `tooStaleAfter`.
    case invalidBounds(staleAfter: TimeInterval, tooStaleAfter: TimeInterval)
}
