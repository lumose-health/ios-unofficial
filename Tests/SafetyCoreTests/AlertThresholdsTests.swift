import Testing
import SafetyCore

@Suite("Alert thresholds and classification")
struct AlertThresholdsTests {
    @Test func rejectsBrokenOrderingAndBounds() throws {
        let valid = (55, 70, 180, 250)
        let invalid = [
            (19, valid.1, valid.2, valid.3),
            (71, valid.1, valid.2, valid.3),
            (valid.0, valid.0 - 1, valid.2, valid.3),
            (valid.0, valid.1, valid.1, valid.3),
            (valid.0, valid.1, valid.3 + 1, valid.3),
            (valid.0, valid.1, valid.2, 501),
        ]
        for (a, b, c, d) in invalid {
            #expect(throws: AlertThresholdsError.invalidOrdering) {
                try AlertThresholds(urgentLow: a, low: b, high: c, urgentHigh: d)
            }
        }
        let bounds = SafetyConstants.glucoseValidRange
        let edge = try AlertThresholds(
            urgentLow: Int(bounds.lowerBound), low: valid.1,
            high: valid.2, urgentHigh: Int(bounds.upperBound)
        )
        #expect(edge.urgentLow == Int(bounds.lowerBound))
        #expect(edge.urgentHigh == Int(bounds.upperBound))
    }

    @Test func inclusiveUrgentFirstClassificationAndRounding() throws {
        let thresholds = try AlertThresholds(urgentLow: 55, low: 70, high: 180, urgentHigh: 250)
        let cases: [(Double, AlertType?)] = [
            (20, .lowUrgent), (55, .lowUrgent), (56, .lowWarning),
            (70, .lowWarning), (70.4, .lowWarning), (70.5, nil),
            (71, nil), (179, nil), (180, .highWarning),
            (249, .highWarning), (250, .highUrgent), (500, .highUrgent),
        ]
        for (value, expected) in cases {
            #expect(AlertClassifier.classify(try Glucose(mgdl: value), against: thresholds) == expected)
        }
    }
}
