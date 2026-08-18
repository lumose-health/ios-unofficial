import Testing

@testable import SafetyCore

/// A negative age classifies as Fresh for display only, and is structurally
/// unable to arm the alert floor beyond the future-skew tolerance.
@Suite("AlertFloorEligibility")
struct AlertFloorEligibilityTests {

    private let thresholds = FreshnessPolicy.cgm

    @Test("The skew tolerance is the canonical 60-second SafetyConstants value")
    func skewToleranceIsCanonical() {
        #expect(AlertFloorEligibility.maxFutureSkew == 60)
        #expect(AlertFloorEligibility.maxFutureSkew == SafetyConstants.alertFloorMaxFutureSkew)
    }

    @Test("age -30s is display Fresh and floor-eligible")
    func negativeSkewWithinToleranceIsEligible() {
        #expect(thresholds.classify(age: -30) == .fresh)
        #expect(AlertFloorEligibility.isEligible(age: -30, thresholds: thresholds))
    }

    @Test("age -90s is display Fresh but NOT floor-eligible")
    func negativeSkewBeyondToleranceIsNotEligible() {
        #expect(thresholds.classify(age: -90) == .fresh)
        #expect(!AlertFloorEligibility.isEligible(age: -90, thresholds: thresholds))
    }

    @Test("Exactly -60s, the skew boundary, is still eligible")
    func exactSkewBoundaryIsEligible() {
        #expect(AlertFloorEligibility.isEligible(age: -60, thresholds: thresholds))
    }

    @Test("Just past -60s is not eligible")
    func justPastSkewBoundaryIsNotEligible() {
        #expect(!AlertFloorEligibility.isEligible(age: -60.001, thresholds: thresholds))
    }

    @Test("An ordinary positive age within staleAfter is eligible")
    func ordinaryFreshAgeIsEligible() {
        #expect(AlertFloorEligibility.isEligible(age: 30, thresholds: thresholds))
    }

    @Test("A Stale reading is not floor-eligible even though within skew")
    func staleReadingIsNotEligible() {
        #expect(thresholds.classify(age: 400) == .stale)
        #expect(!AlertFloorEligibility.isEligible(age: 400, thresholds: thresholds))
    }

    @Test("A TooStale reading is not floor-eligible")
    func tooStaleReadingIsNotEligible() {
        #expect(thresholds.classify(age: 1000) == .tooStale)
        #expect(!AlertFloorEligibility.isEligible(age: 1000, thresholds: thresholds))
    }
}
