import Foundation

/// Insulin on board, as the device itself calculates it.
///
/// The platform reports the DEVICE's number rather than recomputing one: two
/// disagreeing IoB figures on the same screen is worse than one the user can
/// reconcile with their pump.
public struct InsulinOnBoardSample: Hashable, Sendable {

    /// Units of insulin still active.
    public let units: Double

    /// When the device calculated it.
    public let calculatedAt: Date

    /// Creates a sample, refusing a quantity no device can have measured.
    ///
    /// The same posture ``GlucoseSample`` gets from ``SafetyCore/Glucose``: a
    /// sample that exists carries a physically possible number, so a garbage
    /// frame cannot become a platform record by being constructed (AD-22).
    ///
    /// Every refusal here is value-class, non-finite included: this is a
    /// POST-PARSE validator, so a Driver whose bytes did not parse surfaces
    /// ``DriverFailure/decodeFailed(detail:)`` before constructing anything,
    /// and a NaN that reaches this point re-reads to the same NaN — refusing it
    /// decode-class would wedge the cursor behind it forever. The record is
    /// consumed, the cursor advances, the value is dropped (AD-22; the full
    /// argument is on ``DriverFailure``).
    ///
    /// - Throws: ``DriverFailure/valueRejected(bound:)`` when `units` is
    ///   negative, NaN or infinite.
    public init(units: Double, calculatedAt: Date) throws(DriverFailure) {
        guard units.isFinite, units >= 0 else {
            throw .valueRejected(bound: "insulin on board must be a finite, non-negative number of units")
        }
        self.units = units
        self.calculatedAt = calculatedAt
    }
}

/// One COMPLETED insulin dose read back from a device (SI-7).
///
/// Completed only. A dose that was requested and interrupted, or that is still
/// running, is not a `DoseRecord` — the platform counts insulin that reached the
/// patient, and a partial delivery counted as whole is an overstatement of
/// insulin on board in the direction that hides a low.
public struct DoseRecord: Hashable, Sendable {

    /// Units delivered. This is the amount that COMPLETED, not the amount asked for.
    public let units: Double

    /// When the device finished the dose.
    public let completedAt: Date

    /// The platform-standard category, mapped from the device's own label by the
    /// Driver's ``DoseCategoryProvider``.
    public let category: DoseCategory

    /// The device's own label for the category, kept verbatim for display and
    /// for diagnosing a mapping that returned ``DoseCategory/other``.
    public let deviceCategoryLabel: String?

    /// Creates a record, refusing a quantity no pump can have completed.
    ///
    /// A negative or non-finite completed dose is not a dose; admitted, it
    /// flows into the insulin summary and understates or poisons insulin on
    /// board — the direction that hides a low (AD-22).
    ///
    /// Value-class for every refusal, non-finite included — this is a
    /// post-parse validator, and bytes that did not parse surface
    /// ``DriverFailure/decodeFailed(detail:)`` before any record is
    /// constructed; the reasoning is on
    /// ``InsulinOnBoardSample/init(units:calculatedAt:)`` and ``DriverFailure``.
    ///
    /// - Throws: ``DriverFailure/valueRejected(bound:)`` when `units` is
    ///   negative, NaN or infinite.
    public init(
        units: Double,
        completedAt: Date,
        category: DoseCategory,
        deviceCategoryLabel: String? = nil
    ) throws(DriverFailure) {
        guard units.isFinite, units >= 0 else {
            throw .valueRejected(bound: "a completed dose must be a finite, non-negative number of units")
        }
        self.units = units
        self.completedAt = completedAt
        self.category = category
        self.deviceCategoryLabel = deviceCategoryLabel
    }
}

/// The platform-standard dose categories every device's labels map onto.
///
/// Mirrors Android's `BolusCategory`
/// (`app/.../domain/model/BolusCategory.kt`) case for case, with `OVERRIDE`
/// spelled ``manualOverride`` because `override` is a Swift keyword.
///
/// ``other`` is the honest destination for a label this vocabulary does not
/// name. A Driver that guesses the nearest-looking neighbour instead produces an
/// insulin summary that is confidently wrong.
public enum DoseCategory: String, CaseIterable, Hashable, Sendable {
    case autoCorrection
    case food
    case foodAndCorrection
    case correction
    case manualOverride
    case aiSuggested
    case other
}
