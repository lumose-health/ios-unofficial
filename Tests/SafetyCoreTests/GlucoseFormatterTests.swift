import Testing

@testable import SafetyCore

/// mmol/L is a *string*, produced once at the display boundary (SI-3).
///
/// These pins are the contract with the watch and the phone on Android, which
/// format the same reading with `GlucoseDisplayUtils.formatGlucose`: divide the
/// canonical mg/dL by the conversion factor exactly once, then round to one
/// decimal, ties away from zero, with a dot separator.
@Suite("Glucose display formatting")
struct GlucoseFormatterTests {

    @Test("mmol/L display pins", arguments: [
        (100.0, "5.6"),    // 5.5507… — the AC's worked example
        (180.0, "10.0"),   // 9.9913… — rounds up across the whole number; the
                           // trailing zero must survive, "10" would be a regression
        (20.0, "1.1"),     // the inclusive lower bound
        (500.0, "27.8"),   // the inclusive upper bound
        (120.0, "6.7"),
        (450.0, "25.0"),
    ])
    func mmolDisplay(mgdl: Double, expected: String) throws {
        let glucose = try Glucose(mgdl: mgdl)
        #expect(GlucoseFormatter.string(glucose, in: .mmol) == expected)
    }

    /// Straddling the 5.55 mmol/L rounding boundary. The two inputs differ by
    /// 0.01 mg/dL and must land on different displayed digits — proof the rounding
    /// happens after the conversion, not before it. (Rounding the mg/dL value
    /// first would collapse both to 100 mg/dL and print "5.6" twice.)
    @Test("Rounding happens after conversion, at the display boundary")
    func roundingBoundary() throws {
        #expect(try GlucoseFormatter.string(Glucose(mgdl: 99.98), in: .mmol) == "5.5")
        #expect(try GlucoseFormatter.string(Glucose(mgdl: 99.99), in: .mmol) == "5.6")
        // Exactly on the boundary: 99.98658 / 18.0156 == 5.55, which rounds up.
        #expect(try GlucoseFormatter.string(Glucose(mgdl: 99.98658), in: .mmol) == "5.6")
    }

    /// A value whose quotient is an *exact* binary tie, where the rounding mode is
    /// observable: 40.5351 / 18.0156 is exactly 2.25. Ties away from zero — what
    /// Android's `%.1f` with Java `HALF_UP` does — gives "2.3"; C `printf`, which
    /// breaks ties to even, would give "2.2". This test fails if the explicit
    /// rounding step is ever dropped in favour of letting the format string round,
    /// which would make the phone and the watch print different digits.
    @Test("Exact ties round away from zero, matching Android")
    func exactTieRoundsAwayFromZero() throws {
        let glucose = try Glucose(mgdl: 40.5351)
        #expect(glucose.mgdl / SafetyConstants.mgdlPerMmol == 2.25, "precondition: the quotient is an exact tie")
        #expect(GlucoseFormatter.string(glucose, in: .mmol) == "2.3")
    }

    @Test("mg/dL display is the whole number, with no decimal point")
    func mgdlDisplay() throws {
        #expect(try GlucoseFormatter.string(Glucose(mgdl: 100), in: .mgdl) == "100")
        #expect(try GlucoseFormatter.string(Glucose(mgdl: 20), in: .mgdl) == "20")
        #expect(try GlucoseFormatter.string(Glucose(mgdl: 500), in: .mgdl) == "500")
        #expect(try GlucoseFormatter.string(Glucose(mgdl: 99.6), in: .mgdl) == "100")
        #expect(try GlucoseFormatter.string(Glucose(mgdl: 99.4), in: .mgdl) == "99")
    }

    @Test("Unit labels")
    func labels() {
        #expect(GlucoseUnit.mgdl.label == "mg/dL")
        #expect(GlucoseUnit.mmol.label == "mmol/L")
    }

    @Test("Number and label together")
    func withLabel() throws {
        let glucose = try Glucose(mgdl: 120)
        #expect(GlucoseFormatter.stringWithLabel(glucose, in: .mgdl) == "120 mg/dL")
        #expect(GlucoseFormatter.stringWithLabel(glucose, in: .mmol) == "6.7 mmol/L")
    }

    /// Display text is one-way. Nothing parses a formatted mmol/L string back into
    /// state, and this test documents why: the string has lost precision, so a
    /// round trip does not return the reading it came from.
    @Test("mmol/L display is lossy — it is text, not a value")
    func displayIsLossy() throws {
        let a = try Glucose(mgdl: 100)
        let b = try Glucose(mgdl: 100.4)
        #expect(a.mgdl != b.mgdl)
        #expect(GlucoseFormatter.string(a, in: .mmol) == GlucoseFormatter.string(b, in: .mmol))
    }
}
