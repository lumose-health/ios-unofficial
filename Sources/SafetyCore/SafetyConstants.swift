import Foundation

/// The single definition site for every cross-target safety constant (AD-2, SI-4).
///
/// Nothing else in `Sources/` may spell these values again — not a private copy,
/// not an inline literal, not a "just this once" duplicate in a view model.
/// `scripts/guards/safety_guards.sh` enforces that mechanically: a second code
/// occurrence anywhere under `Sources/` fails the gate.
///
/// Why so strict: these values are also duplicated in the Android app and
/// the backend, on independent release cadences. When copies desync, glucose is
/// mis-converted or mis-validated, or a stale reading is judged by the wrong
/// clock — a patient-safety failure, not a cosmetic bug.
/// Android carries the mirror-image guard in
/// `app/src/test/java/com/glycemicgpt/mobile/contract/SafetyConstantDriftGuardTest.kt`;
/// the iOS values below were verified against it.
///
/// Changing any value here is a cross-repo decision, never a local one.
public enum SafetyConstants {

    /// mg/dL per mmol/L — the exact glucose mass-to-molarity factor.
    ///
    /// Canonical across Android (`GlucoseFormat.MGDL_PER_MMOL`,
    /// `GlucoseDisplayUtils.MGDL_PER_MMOL`) and the backend (`MGDL_PER_MMOL`).
    /// Never introduce a rounded variant such as 18.02 or 18.0182: the watch and
    /// the phone would then print different numbers for the same reading.
    ///
    /// This factor is a *presentation* input only. Canonical state is mg/dL
    /// everywhere (SI-3); see `GlucoseFormatter`.
    public static let mgdlPerMmol: Double = 18.0156

    /// The inclusive mg/dL bound outside which a glucose value is not a reading.
    ///
    /// Inclusive at both ends, matching the Android `20..500` platform invariant:
    /// the lower bound is a valid reading, the upper bound is a valid reading, and
    /// anything beyond either end is rejected outright rather than clamped (SI-2).
    ///
    /// Expressed over `Double` because sources report sub-integer values; the
    /// bound is a range check, not a storage format.
    public static let glucoseValidRange: ClosedRange<Double> = 20...500

    /// Seconds between the Unix epoch and the Tandem pump epoch
    /// (1 January 2008, 00:00:00 UTC).
    ///
    /// Tandem pumps report timestamps as seconds since that instant. Canonical
    /// value verified against Android
    /// `plugins/shipped/tandem/.../ble/messages/StatusResponseParser.kt`
    /// (`TANDEM_EPOCH_OFFSET`) and the backend `TANDEM_EPOCH_OFFSET_SECONDS`.
    ///
    /// Adding this offset converts pump time to Unix time; it says nothing about
    /// what "now" is. Current time always comes from a ``Clock`` (AD-14).
    public static let tandemEpochOffset: TimeInterval = 1_199_145_600

    /// Seconds a CGM reading may age before its ``Freshness`` flips from `fresh` to
    /// `stale` (Android `FreshnessPolicy.CGM`, `Freshness.kt:111`:
    /// `staleAfterMs = 6 * MINUTE_MS`).
    ///
    /// The literal lives here, not beside ``FreshnessThresholds`` or
    /// ``FreshnessPolicy``, so it stays covered by this file's single-definition-site
    /// guarantee; ``FreshnessPolicy/cgm`` assembles it into the validated type every
    /// consumer uses.
    public static let cgmStaleAfter: TimeInterval = 360

    /// Seconds a CGM reading may age before its ``Freshness`` flips from `stale` to
    /// `tooStale` (Android `FreshnessPolicy.CGM`, `Freshness.kt:111`:
    /// `tooStaleAfterMs = 15 * MINUTE_MS`).
    public static let cgmTooStaleAfter: TimeInterval = 900

    /// Max future-dated skew, in seconds, the alert floor tolerates before
    /// refusing to treat a reading as fresh (Android
    /// `ALERT_FLOOR_MAX_FUTURE_SKEW_MS`, `Freshness.kt:59`).
    ///
    /// The literal lives here, not in ``AlertFloorEligibility``, for the same
    /// reason the CGM thresholds above do: it gates whether a reading may arm an
    /// alarm, it is mirrored in the other targets, and only this file's
    /// single-definition-site guarantee detects a drifted copy.
    public static let alertFloorMaxFutureSkew: TimeInterval = 60
}
