import Foundation
import Testing

@testable import SafetyCore

/// Boundary pins for the half-open classification rule (AC 1): `age < staleAfter`
/// is Fresh, `staleAfter <= age < tooStaleAfter` is Stale, `age >= tooStaleAfter`
/// is TooStale — matching Android `Freshness.kt` exactly.
@Suite("Freshness classification")
struct FreshnessTests {

    // staleAfter = 360s, tooStaleAfter = 900s.
    private let thresholds = FreshnessPolicy.cgm

    @Test("One second below staleAfter is Fresh")
    func belowStaleBoundaryIsFresh() {
        #expect(thresholds.classify(age: 359) == .fresh)
    }

    @Test("Exactly staleAfter is Stale")
    func atStaleBoundaryIsStale() {
        #expect(thresholds.classify(age: 360) == .stale)
    }

    @Test("One second below tooStaleAfter is Stale")
    func belowTooStaleBoundaryIsStale() {
        #expect(thresholds.classify(age: 899) == .stale)
    }

    @Test("Exactly tooStaleAfter is TooStale")
    func atTooStaleBoundaryIsTooStale() {
        #expect(thresholds.classify(age: 900) == .tooStale)
    }

    @Test("Well beyond tooStaleAfter is TooStale")
    func wellBeyondTooStaleIsTooStale() {
        #expect(thresholds.classify(age: 3600) == .tooStale)
    }

    @Test("A negative age is Fresh for display")
    func negativeAgeIsFresh() {
        #expect(thresholds.classify(age: -30) == .fresh)
        #expect(thresholds.classify(age: -90) == .fresh)
    }

    @Test("classify(_:asOf:) drives the same result through GlucoseReading.age(asOf:)")
    func classifyFromReading() throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let reading = GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference)
        let clock = FixedClock(now: reference.addingTimeInterval(400))
        #expect(thresholds.classify(reading, asOf: clock) == .stale)
    }
}

@Suite("FreshnessThresholds validation")
struct FreshnessThresholdsValidationTests {

    @Test("staleAfter must be strictly positive")
    func rejectsNonPositiveStaleAfter() {
        #expect(throws: FreshnessThresholdsError.self) {
            _ = try FreshnessThresholds(staleAfter: 0, tooStaleAfter: 10)
        }
        #expect(throws: FreshnessThresholdsError.self) {
            _ = try FreshnessThresholds(staleAfter: -5, tooStaleAfter: 10)
        }
    }

    @Test("staleAfter must be strictly less than tooStaleAfter")
    func rejectsStaleAfterNotLessThanTooStaleAfter() {
        #expect(throws: FreshnessThresholdsError.self) {
            _ = try FreshnessThresholds(staleAfter: 10, tooStaleAfter: 10)
        }
        #expect(throws: FreshnessThresholdsError.self) {
            _ = try FreshnessThresholds(staleAfter: 20, tooStaleAfter: 10)
        }
    }

    @Test("Bounds must be finite")
    func rejectsNonFiniteBounds() {
        // An infinite tooStaleAfter is the case the ordering checks alone let
        // through: it would build a policy under which no age is ever TooStale.
        #expect(throws: FreshnessThresholdsError.self) {
            _ = try FreshnessThresholds(staleAfter: 10, tooStaleAfter: .infinity)
        }
        #expect(throws: FreshnessThresholdsError.self) {
            _ = try FreshnessThresholds(staleAfter: .infinity, tooStaleAfter: .infinity)
        }
        #expect(throws: FreshnessThresholdsError.self) {
            _ = try FreshnessThresholds(staleAfter: .nan, tooStaleAfter: 10)
        }
        #expect(throws: FreshnessThresholdsError.self) {
            _ = try FreshnessThresholds(staleAfter: 10, tooStaleAfter: .nan)
        }
    }

    @Test("Valid bounds construct successfully")
    func acceptsValidBounds() throws {
        let thresholds = try FreshnessThresholds(staleAfter: 5, tooStaleAfter: 10)
        #expect(thresholds.staleAfter == 5)
        #expect(thresholds.tooStaleAfter == 10)
    }
}

@Suite("FreshnessPolicy canonical CGM thresholds")
struct FreshnessPolicyTests {

    @Test("CGM staleAfter is 360 seconds (6 minutes)")
    func cgmStaleAfter() {
        #expect(FreshnessPolicy.cgm.staleAfter == 360)
    }

    @Test("CGM tooStaleAfter is 900 seconds (15 minutes)")
    func cgmTooStaleAfter() {
        #expect(FreshnessPolicy.cgm.tooStaleAfter == 900)
    }
}
