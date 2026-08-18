import Foundation

/// A unit a glucose value can be *displayed* in.
///
/// This is a presentation choice, not a storage format. State is mg/dL
/// everywhere (SI-3); nothing in the app holds or computes a mmol/L number.
public enum GlucoseUnit: String, Hashable, Sendable, CaseIterable {

    /// Milligrams per decilitre — also the canonical internal unit.
    case mgdl

    /// Millimoles per litre — display only.
    case mmol

    /// The user-facing label, e.g. for a chart axis or a settings row.
    public var label: String {
        switch self {
        case .mgdl: "mg/dL"
        case .mmol: "mmol/L"
        }
    }
}

/// Turns a canonical ``Glucose`` into the string a person reads.
///
/// ## The mmol/L rule (SI-3)
///
/// mmol/L exists **only here**, and only as text. The canonical mg/dL value is
/// converted exactly once, at this boundary, and rounded last — after the
/// conversion, never before it and never again afterwards. A mmol/L number is
/// never stored, never compared, never fed back into a bound check, a threshold,
/// or plotting geometry; all of those stay mg/dL. Round-tripping display text
/// back into state is how two surfaces start disagreeing about one reading.
///
/// ## Rounding
///
/// One decimal place, ties away from zero — matching the Android display
/// convention (`GlucoseDisplayUtils.formatGlucose`, which formats with
/// `Locale.US` and Java's HALF_UP). The rounding mode is applied explicitly
/// rather than left to `printf`, which breaks ties to even and would print a
/// different digit from the watch and the phone for the values where the two
/// modes disagree. The decimal separator is always a dot, on every locale, so
/// that display text is stable across devices.
public enum GlucoseFormatter {

    /// The bare number shown in `unit` — no unit label.
    ///
    /// mg/dL renders as a whole number; mmol/L as one decimal place.
    public static func string(_ glucose: Glucose, in unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdl:
            return String(format: "%.0f", glucose.mgdl.rounded(.toNearestOrAwayFromZero))
        case .mmol:
            // Convert once...
            let mmol = glucose.mgdl / SafetyConstants.mgdlPerMmol
            // ...and round last, to one decimal, ties away from zero.
            let rounded = (mmol * 10).rounded(.toNearestOrAwayFromZero) / 10
            return String(format: "%.1f", rounded)
        }
    }

    /// The number and its unit label, e.g. `"120 mg/dL"` or `"6.7 mmol/L"`.
    public static func stringWithLabel(_ glucose: Glucose, in unit: GlucoseUnit) -> String {
        "\(string(glucose, in: unit)) \(unit.label)"
    }
}
