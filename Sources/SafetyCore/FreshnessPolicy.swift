/// The canonical, cross-target freshness policy per data source (AD-2, SI-4).
///
/// ``SafetyConstants/cgmStaleAfter`` and ``SafetyConstants/cgmTooStaleAfter`` hold the
/// literal values so `safety_guards.sh` can enforce they are spelled exactly once;
/// this type assembles them into the validated ``FreshnessThresholds`` every
/// consumer uses, so a second CGM policy never gets hand-rolled at a call site
/// (Android `FreshnessPolicy.CGM`, `Freshness.kt:111`).
public enum FreshnessPolicy {

    /// CGM glucose: ``Freshness/fresh`` under 6 minutes, ``Freshness/stale`` from 6 to
    /// 15 minutes, ``Freshness/tooStale`` at 15 minutes and beyond.
    ///
    /// `try!` is safe here: the bounds are fixed literals known valid at compile
    /// time, not caller-supplied input — the same reasoning that makes a throwing
    /// initializer the right shape for ``FreshnessThresholds`` in the first place
    /// does not require every *use* of a known-good literal to re-litigate it.
    public static let cgm = try! FreshnessThresholds(
        staleAfter: SafetyConstants.cgmStaleAfter,
        tooStaleAfter: SafetyConstants.cgmTooStaleAfter
    )
}
