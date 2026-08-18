import Foundation
import SafetyCore

/// The glucose bound a Driver validates against — the user's, never wider than
/// the absolute one (FR-32, SI-11).
///
/// ## Narrowing only, enforced by the type
///
/// The absolute bound is ``SafetyCore/SafetyConstants/glucoseValidRange`` and it
/// is the ceiling on what any configuration can express. A `SafetyLimits` may sit
/// inside it or match it; it cannot reach outside it in either direction, because
/// the initializer refuses to produce one that does. There is no clamping factory
/// and no lenient variant — Android's `SafetyLimits.safeOf` clamps out-of-range
/// input rather than throwing, and a clamped safety bound is a bound the user
/// did not configure being applied as though they had.
///
/// Widening is the direction that matters. A limit that reached BELOW the
/// absolute floor would admit sensor noise from a sensor in warm-up as a
/// hypoglycaemia reading; one that reached above the ceiling would admit a
/// garbage frame as a hyperglycaemia reading. Both are values the absolute bound
/// exists to reject, and both would arrive from a remote configuration.
///
/// ## Why nothing here can be cached and used later
///
/// This type is a VALUE — a pair of numbers that were checked once — and it is
/// deliberately not the thing anyone validates against. Validation lives on
/// ``SafetyLimitsValidator``, which the platform owns and a Driver receives; it
/// reads the limits in force inside every call.
///
/// Two earlier versions of this file got that wrong, in ways worth recording
/// because each looked correct:
///
/// * `validate(mgdl:)` was a public method here and `absolute` was a
///   `public static let`. Both are perfectly cacheable — a Driver writes
///   `private let limits = SafetyLimits.absolute`, validates against it forever,
///   and the user's narrowed bound never reaches the code that admits readings.
/// * validation then moved to a `SafetyLimitsSource` PROTOCOL with a
///   `currentLimits` requirement. Asked on every call — but answered by a
///   conformer the Driver writes, and a conformer that captures its limits at
///   `init` is the same stale bound with an extra hop.
///
/// So there is now nothing here to cache that can validate anything —
/// ``validate(mgdl:)`` is internal to `DriverAPI` — and the door is a final class
/// a Driver can neither construct nor stand in for.
///
/// ## Rejection leaves last-known-good in force
///
/// A refused `SafetyLimits` throws (AD-13). It does not partially apply, and it
/// does not fall back to the absolute bound — the caller keeps the limits it
/// already had and surfaces which bound failed (SI-11).
public struct SafetyLimits: Hashable, Sendable {

    /// The bound in force, always a subrange of (or equal to) the absolute bound.
    public let glucoseRange: ClosedRange<Double>

    /// The widest limits that can exist: the absolute bound itself.
    ///
    /// Built from ``SafetyCore/SafetyConstants/glucoseValidRange`` rather than
    /// from its numbers. Re-spelling the bound here would be a second definition
    /// site for a safety constant, which `scripts/guards/safety_guards.sh` fails
    /// the build over (AD-2, SI-4).
    ///
    /// INTERNAL, and that is the point: a public one is a limit any Driver can
    /// hold onto and validate against for the rest of the process, which is the
    /// cache this type exists to not have. A platform that wants to start a user
    /// at the widest legal bound constructs it from
    /// ``SafetyCore/SafetyConstants/glucoseValidRange`` through the throwing
    /// initializer, like every other configuration.
    static let absolute = SafetyLimits(unchecked: SafetyConstants.glucoseValidRange)

    private init(unchecked range: ClosedRange<Double>) {
        self.glucoseRange = range
    }

    /// Creates limits from a configured lower and upper mg/dL bound.
    ///
    /// - Throws: ``DriverFailure/safetyLimitRejected(_:)`` with
    ///   ``SafetyLimitRejection/notFinite`` for NaN or infinity,
    ///   ``SafetyLimitRejection/emptyOrInverted(lower:upper:)`` when the bounds do
    ///   not describe a non-empty range, and
    ///   ``SafetyLimitRejection/widensAbsoluteBound(lower:upper:)`` when either
    ///   bound reaches outside ``SafetyCore/SafetyConstants/glucoseValidRange``.
    ///   Never clamps, never substitutes.
    public init(glucoseLower lower: Double, glucoseUpper upper: Double) throws(DriverFailure) {
        guard lower.isFinite, upper.isFinite else {
            throw .safetyLimitRejected(.notFinite)
        }
        guard lower < upper else {
            throw .safetyLimitRejected(.emptyOrInverted(lower: lower, upper: upper))
        }
        guard SafetyConstants.glucoseValidRange.contains(lower),
              SafetyConstants.glucoseValidRange.contains(upper)
        else {
            throw .safetyLimitRejected(.widensAbsoluteBound(lower: lower, upper: upper))
        }
        self.glucoseRange = lower...upper
    }

    /// Validates one mg/dL value against these limits.
    ///
    /// INTERNAL. The public door is ``SafetyLimitsValidator/validate(mgdl:)``,
    /// which re-reads the limits in force before delegating here — so a caller
    /// cannot hold a `SafetyLimits` and keep validating against a bound the user
    /// has since narrowed.
    ///
    /// - Returns: a ``SafetyCore/Glucose``, so a value that passes cannot
    ///   subsequently be treated as out of range.
    /// - Throws: ``DriverFailure/valueRejected(bound:)`` naming the bound that
    ///   refused it. Per AD-22 the caller CONSUMES the record and advances its
    ///   cursor: the value parsed cleanly, it is simply not admissible, and
    ///   retrying it forever would wedge history behind a number that will never
    ///   become valid.
    func validate(mgdl: Double) throws(DriverFailure) -> Glucose {
        guard mgdl.isFinite else {
            throw .valueRejected(bound: "not a finite number")
        }
        guard glucoseRange.contains(mgdl) else {
            throw .valueRejected(bound: Self.describe(glucoseRange))
        }
        // The absolute bound is re-checked by `Glucose` itself; a `SafetyLimits`
        // cannot be wider than it, so this cannot throw for a value that passed
        // the check above. It is mapped rather than force-tried because a
        // force-try here would be a trap on a background path (AD-5).
        do {
            return try Glucose(mgdl: mgdl)
        } catch {
            throw .valueRejected(bound: Self.describe(SafetyConstants.glucoseValidRange))
        }
    }

    /// A range as text for the `bound` payload — the numbers the user
    /// configured, so the failure names the limit that rejected the reading.
    ///
    /// DIAGNOSTIC text, not display text: the interpolation is Swift's
    /// locale-independent `Double` rendering (`40.0...400.0 mg/dL`) and the
    /// `...` is source syntax. A screen that shows the user their limit
    /// formats the limits in force at the display boundary, the way
    /// ``SafetyCore/GlucoseFormatter`` formats readings — it does not parse or
    /// render this string. See ``DriverFailure/valueRejected(bound:)``.
    private static func describe(_ range: ClosedRange<Double>) -> String {
        "\(range.lowerBound)...\(range.upperBound) mg/dL"
    }
}
