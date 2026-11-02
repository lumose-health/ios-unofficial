import Testing
import SafetyCore

@Suite("Alert vocabulary")
struct AlertVocabularyTests {
    @Test func openStringsAndTiers() {
        #expect(AlertType(rawValue: "made_up").rawValue == "made_up")
        #expect(AlertSeverity(rawValue: "other").rawValue == "other")
        #expect(AlertType.lowSet == [.lowUrgent, .lowWarning])
        #expect(AlertType.highSet == [.highWarning, .highUrgent])
        for type in AlertType.lowSet.union(AlertType.highSet) {
            #expect(type.deliveryTier == .interrupting)
        }
        for type in [AlertType.iobWarning, .noData, AlertType(rawValue: "made_up")] {
            #expect(type.deliveryTier == .informational)
        }
        #expect(AlertSeverity.warning.rawValue == "warning")
        #expect(AlertSeverity.urgent.rawValue == "urgent")
        #expect(AlertSeverity.emergency.rawValue == "emergency")
    }

    @Test func interruptionLevelUsesRuntimeSetting() {
        #expect(AlertDeliveryTier.interrupting.interruptionLevel(criticalAlertsEnabled: true) == .critical)
        #expect(AlertDeliveryTier.interrupting.interruptionLevel(criticalAlertsEnabled: false) == .timeSensitive)
        #expect(AlertDeliveryTier.informational.interruptionLevel(criticalAlertsEnabled: true) == .active)
        #expect(AlertDeliveryTier.informational.interruptionLevel(criticalAlertsEnabled: false) == .active)
    }
}
