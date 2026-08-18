/// How trustworthy a timestamped reading is, given its age (FR-49).
///
/// One classifier shared across every dashboard source so staleness is judged the
/// same way everywhere, instead of each surface re-deriving it — mirrors Android
/// `Freshness.kt:19` exactly.
///
/// - ``fresh``: recent; render normally.
/// - ``stale``: older than the source's expected cadence; still shown, with a badge
///   (see ``FreshnessBadge``) so the user knows it is cached.
/// - ``tooStale``: old enough that the value must not be presented as a current
///   reading.
///
/// See ``FreshnessThresholds/classify(age:)`` for how an age becomes a tier, and
/// ``AlertFloorEligibility`` for the separate, stricter question of whether a
/// reading may drive an alert.
public enum Freshness: Hashable, Sendable {
    case fresh
    case stale
    case tooStale
}
