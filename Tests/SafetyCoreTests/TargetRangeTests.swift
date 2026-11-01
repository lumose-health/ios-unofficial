import Testing
import SafetyCore

@Suite("Target range")
struct TargetRangeTests {
    @Test func defaultBoundaries() throws {
        let range = TargetRange.default
        #expect(range.urgentLow == 55)
        #expect(range.low == 70)
        #expect(range.high == 180)
        #expect(range.urgentHigh == 250)
        let cases: [(Double, GlucoseSeverity)] = [
            (55, .urgentLow), (56, .low), (70, .low), (70.4, .low),
            (71, .inRange), (179, .inRange), (179.6, .high), (180, .high),
            (249, .high), (250, .urgentHigh)
        ]
        for (value, severity) in cases {
            #expect(range.severity(of: try Glucose(mgdl: value)) == severity)
        }
    }

    @Test func rejectsEveryBrokenInequality() {
        let lower = SafetyConstants.glucoseValidRange.lowerBound
        let upper = SafetyConstants.glucoseValidRange.upperBound
        let invalid: [(Double, Double, Double, Double)] = [
            (lower - 1, 70, 180, 250), (71, 70, 180, 250),
            (55, 180, 180, 250), (55, 70, 251, 250),
            (55, 70, 180, upper + 1), (.nan, 70, 180, 250),
            (55, .infinity, 180, 250)
        ]
        for (urgentLow, low, high, urgentHigh) in invalid {
            #expect(throws: TargetRangeError.invalidBoundaries) {
                try TargetRange(urgentLow: urgentLow, low: low, high: high, urgentHigh: urgentHigh)
            }
        }
    }

    @Test func acceptsInclusiveOuterBoundariesAndNondefaultBanding() throws {
        let bounds = SafetyConstants.glucoseValidRange
        let range = try TargetRange(urgentLow: bounds.lowerBound, low: 80, high: 140, urgentHigh: bounds.upperBound)
        #expect(range.severity(of: try Glucose(mgdl: 80)) == .low)
        #expect(range.severity(of: try Glucose(mgdl: 80.6)) == .inRange)
        #expect(range.severity(of: try Glucose(mgdl: 140)) == .high)
        #expect(range.severity(of: try Glucose(mgdl: bounds.upperBound)) == .urgentHigh)
    }
}
