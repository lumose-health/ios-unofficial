import Foundation
import Testing
import SafetyCore

@Suite("Alert data trust")
struct AlertDataTrustTests {
    @Test func orderAndMonotonicMark() throws {
        let thresholds = try AlertThresholds(urgentLow: 55, low: 70, high: 180, urgentHigh: 250)
        let configured = AlertThresholdSetting.configured(thresholds, .local)
        let base = Date(timeIntervalSince1970: 10_000)
        var mark = WallClockHighWaterMark()
        #expect(AlertDataTrust.evaluate(sensorTimestamp: base, thresholds: configured, now: base, mark: &mark) == .trusted)
        let rewind = base.addingTimeInterval(-SafetyConstants.alertFloorMaxFutureSkew - 0.001)
        #expect(AlertDataTrust.evaluate(sensorTimestamp: base, thresholds: .notConfigured, now: rewind, mark: &mark) == .clockRewound)
        #expect(mark.isRewound(at: rewind))
        #expect(AlertDataTrust.evaluate(sensorTimestamp: base, thresholds: .notConfigured, now: base, mark: &mark) == .thresholdsNotConfigured)
    }

    @Test func freshnessBoundariesAndBackendEvidence() throws {
        let thresholds = try AlertThresholds(urgentLow: 55, low: 70, high: 180, urgentHigh: 250)
        let setting = AlertThresholdSetting.configured(thresholds, .backend)
        let now = Date(timeIntervalSince1970: 10_000)
        let cases: [(TimeInterval, AlertDataTrustResult)] = [
            (359.999, .trusted), (360, .notFresh),
            (-60, .trusted), (-60.001, .notFresh), (-120, .notFresh),
        ]
        for (age, expected) in cases {
            var mark = WallClockHighWaterMark()
            let result = AlertDataTrust.evaluate(
                sensorTimestamp: now.addingTimeInterval(-age), thresholds: setting,
                now: now, mark: &mark
            )
            #expect(result == expected)
        }
        #expect(BackendAlertingStatus.notConfigured.isDegraded)
        #expect(BackendAlertingStatus.configured(networkReachable: true, streamConnected: true, backendHasFreshGlucose: false).isDegraded)
        #expect(BackendAlertingStatus.configured(networkReachable: true, streamConnected: true, backendHasFreshGlucose: nil).isDegraded)
        #expect(!BackendAlertingStatus.configured(networkReachable: true, streamConnected: true, backendHasFreshGlucose: true).isDegraded)
        #expect(BackendAlertingStatus.configured(networkReachable: false, streamConnected: true, backendHasFreshGlucose: true).isDegraded)
        #expect(BackendAlertingStatus.configured(networkReachable: true, streamConnected: false, backendHasFreshGlucose: true).isDegraded)
    }
}
