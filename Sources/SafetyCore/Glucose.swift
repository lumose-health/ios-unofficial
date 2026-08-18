/// Why a `Glucose` value cannot be invalid, and why it throws.
///
/// A pump or CGM can send garbage: a dropped BLE frame, a sensor in warm-up, a
/// firmware quirk. Three responses are possible and only one is safe (AD-5, SI-2):
///
/// - **Clamp** it into range — a clamped wrong number is a *lie* about a medical
///   value. A 900 mg/dL frame silently displayed as 500 looks like a real reading.
/// - **`precondition`** — the app crashes on data it does not control. A dropped
///   frame must degrade the UI, never kill the process.
/// - **Throw** — the caller is forced to decide, and there is no path by which an
///   out-of-range number becomes a displayed reading. This is what we do.
///
/// So `Glucose` has exactly one way in — a throwing initializer — and no mutating
/// API. If you hold a `Glucose`, its value is inside ``SafetyConstants/glucoseValidRange``.
public struct Glucose: Hashable, Sendable, Comparable {

    /// The canonical value, always mg/dL (SI-3).
    ///
    /// There is no mmol/L stored anywhere in the app. mmol/L exists only as a
    /// string produced at the display boundary; see ``GlucoseFormatter``.
    public let mgdl: Double

    /// Creates a reading from a canonical mg/dL value.
    ///
    /// - Throws: ``GlucoseError/notFinite`` for NaN or infinity,
    ///   ``GlucoseError/outOfRange(mgdl:)`` for a finite value outside
    ///   ``SafetyConstants/glucoseValidRange``. Never clamps, never substitutes.
    public init(mgdl: Double) throws {
        guard mgdl.isFinite else { throw GlucoseError.notFinite }
        guard SafetyConstants.glucoseValidRange.contains(mgdl) else {
            throw GlucoseError.outOfRange(mgdl: mgdl)
        }
        self.mgdl = mgdl
    }

    /// Creates a reading from an integer mg/dL value, as pumps and CGMs report it.
    ///
    /// - Throws: ``GlucoseError/outOfRange(mgdl:)`` outside
    ///   ``SafetyConstants/glucoseValidRange``.
    public init(mgdl: Int) throws {
        try self.init(mgdl: Double(mgdl))
    }

    public static func < (lhs: Glucose, rhs: Glucose) -> Bool {
        lhs.mgdl < rhs.mgdl
    }
}

/// The reasons a glucose value is rejected.
///
/// Distinct cases because they mean different things upstream: ``notFinite`` is a
/// decode or arithmetic failure, ``outOfRange(mgdl:)`` is a plausible-looking
/// number the safety bound rejects. The rejected value is carried so it can be
/// logged; it must never be displayed as a reading.
public enum GlucoseError: Error, Hashable, Sendable {

    /// The value was NaN or infinite — nothing sensible can be done with it.
    case notFinite

    /// The value was finite but outside ``SafetyConstants/glucoseValidRange``.
    case outOfRange(mgdl: Double)
}
