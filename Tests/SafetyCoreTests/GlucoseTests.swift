import Testing

@testable import SafetyCore

/// The bound is INCLUSIVE at both ends and rejection THROWS — it does not clamp,
/// substitute a default, or `precondition` (AD-5, SI-2). These four values are the
/// contract: one below, both ends, one above.
@Suite("Glucose validity bound")
struct GlucoseBoundTests {

    @Test("19 mg/dL is rejected — one below the inclusive lower bound")
    func belowLowerBound() {
        #expect(throws: GlucoseError.outOfRange(mgdl: 19)) {
            try Glucose(mgdl: 19)
        }
    }

    @Test("20 mg/dL is a valid reading — the lower bound is inclusive")
    func atLowerBound() throws {
        #expect(try Glucose(mgdl: 20).mgdl == 20)
    }

    @Test("500 mg/dL is a valid reading — the upper bound is inclusive")
    func atUpperBound() throws {
        #expect(try Glucose(mgdl: 500).mgdl == 500)
    }

    @Test("501 mg/dL is rejected — one above the inclusive upper bound")
    func aboveUpperBound() {
        #expect(throws: GlucoseError.outOfRange(mgdl: 501)) {
            try Glucose(mgdl: 501)
        }
    }

    /// Just inside and just outside on the `Double` side of the bound: a value can
    /// miss by less than 1 mg/dL and must still be rejected rather than nudged in.
    @Test("Fractional values either side of each bound", arguments: [
        (19.999, false), (20.001, true), (499.999, true), (500.001, false),
    ])
    func fractionalBoundary(mgdl: Double, isValid: Bool) {
        if isValid {
            #expect(throws: Never.self) { try Glucose(mgdl: mgdl) }
        } else {
            #expect(throws: GlucoseError.outOfRange(mgdl: mgdl)) { try Glucose(mgdl: mgdl) }
        }
    }

    @Test("Negative and zero values are rejected", arguments: [-1.0, -100.0, 0.0])
    func negativeAndZero(mgdl: Double) {
        #expect(throws: GlucoseError.outOfRange(mgdl: mgdl)) {
            try Glucose(mgdl: mgdl)
        }
    }

    /// NaN and infinity get their own error case: they signal a decode or
    /// arithmetic failure upstream, not a plausible number the bound rejected.
    /// NaN is especially important — a bare range check on NaN is false, so
    /// without the explicit guard the diagnosis would be wrong even though the
    /// value would still (by luck) be refused.
    @Test("Non-finite values are rejected as not-finite, not as out-of-range")
    func nonFinite() {
        #expect(throws: GlucoseError.notFinite) { try Glucose(mgdl: Double.nan) }
        #expect(throws: GlucoseError.notFinite) { try Glucose(mgdl: Double.infinity) }
        #expect(throws: GlucoseError.notFinite) { try Glucose(mgdl: -Double.infinity) }
        #expect(throws: GlucoseError.notFinite) { try Glucose(mgdl: Double.signalingNaN) }
    }

    @Test("The integer initializer enforces the same bound")
    func integerInitializer() throws {
        #expect(try Glucose(mgdl: 20).mgdl == 20)
        #expect(try Glucose(mgdl: 500).mgdl == 500)
        #expect(throws: GlucoseError.outOfRange(mgdl: 19)) { try Glucose(mgdl: Int(19)) }
        #expect(throws: GlucoseError.outOfRange(mgdl: 501)) { try Glucose(mgdl: Int(501)) }
        #expect(throws: GlucoseError.outOfRange(mgdl: -5)) { try Glucose(mgdl: Int(-5)) }
    }

    /// The rejected number is carried on the error so it can be logged — the one
    /// place an out-of-range value is allowed to survive. It must never reach a
    /// display path as a reading.
    @Test("The rejected value is reported, not silently swallowed")
    func errorCarriesRejectedValue() {
        do {
            _ = try Glucose(mgdl: 900)
            Issue.record("900 mg/dL must not construct")
        } catch let error as GlucoseError {
            #expect(error == .outOfRange(mgdl: 900))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Glucose orders and compares by its canonical mg/dL value")
    func valueSemantics() throws {
        let low = try Glucose(mgdl: 70)
        let high = try Glucose(mgdl: 180)
        #expect(low < high)
        #expect(try low == Glucose(mgdl: 70))
        #expect(Set([low, high, try Glucose(mgdl: 70)]).count == 2)
    }
}
