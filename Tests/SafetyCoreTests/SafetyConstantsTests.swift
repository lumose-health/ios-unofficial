import Foundation
import Testing

@testable import SafetyCore

/// Canonical-value pins.
///
/// The guard script proves each constant is defined only *once* in `Sources/`;
/// these tests prove it is defined *correctly*. Both halves are needed — a single
/// definition site holding a drifted value is exactly as unsafe as two sites.
///
/// Every value below was verified against the Android app, which carries the
/// mirror-image guard in `SafetyConstantDriftGuardTest.kt`. Changing one of these
/// numbers is a cross-repo decision: Android and the backend must move with it.
@Suite("Safety constants")
struct SafetyConstantsTests {

    @Test("mg/dL per mmol/L matches the canonical factor")
    func conversionFactor() {
        #expect(SafetyConstants.mgdlPerMmol == 18.0156)
    }

    @Test("The glucose bound matches the canonical inclusive range")
    func glucoseBound() {
        #expect(SafetyConstants.glucoseValidRange.lowerBound == 20)
        #expect(SafetyConstants.glucoseValidRange.upperBound == 500)
        #expect(SafetyConstants.glucoseValidRange.contains(20))
        #expect(SafetyConstants.glucoseValidRange.contains(500))
        #expect(!SafetyConstants.glucoseValidRange.contains(19))
        #expect(!SafetyConstants.glucoseValidRange.contains(501))
    }

    @Test("The Tandem epoch offset matches the canonical value")
    func tandemEpochOffset() {
        #expect(SafetyConstants.tandemEpochOffset == 1_199_145_600)
    }

    /// The offset is only meaningful if it really lands on the pump epoch, so pin
    /// the instant it denotes rather than just the number: 1 January 2008,
    /// 00:00:00 UTC. A digit transposition that still "looks like" an epoch would
    /// pass a bare numeric comparison against a copy-pasted expectation.
    @Test("The Tandem epoch offset denotes 2008-01-01T00:00:00Z")
    func tandemEpochInstant() throws {
        var components = DateComponents()
        components.year = 2008
        components.month = 1
        components.day = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let epoch = try #require(calendar.date(from: components))
        #expect(epoch.timeIntervalSince1970 == SafetyConstants.tandemEpochOffset)
    }
}
