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
        #expect(AlertDataTrust.evaluate(sensorTimestamp: base, thresholds: configured, now: base, elapsed: 0, mark: &mark) == .trusted)
        let rewind = base.addingTimeInterval(-SafetyConstants.alertFloorMaxFutureSkew - 0.001)
        #expect(AlertDataTrust.evaluate(sensorTimestamp: base, thresholds: .notConfigured, now: rewind, elapsed: 0, mark: &mark) == .clockRewound)
        let stillRewound = mark.isRewound(at: rewind, elapsed: 0)
        #expect(stillRewound)
        #expect(AlertDataTrust.evaluate(sensorTimestamp: base, thresholds: .notConfigured, now: base, elapsed: 0, mark: &mark) == .thresholdsNotConfigured)
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
                now: now, elapsed: 0, mark: &mark
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

    private typealias Step = (wall: TimeInterval, elapsed: TimeInterval, rewound: Bool)

    /// Replays observations against one mark; `wall` is seconds from a fixed origin.
    private func replay(_ steps: [Step], on mark: inout WallClockHighWaterMark, sourceLocation: SourceLocation = #_sourceLocation) {
        let origin = Date(timeIntervalSince1970: 10_000)
        for (index, step) in steps.enumerated() {
            let rewound = mark.isRewound(at: origin.addingTimeInterval(step.wall), elapsed: step.elapsed)
            #expect(rewound == step.rewound, "step \(index)", sourceLocation: sourceLocation)
        }
    }

    private let skew = SafetyConstants.alertFloorMaxFutureSkew
    private let bound = SafetyConstants.alertFloorClockSuppressionBound
    private let gap = SafetyConstants.cgmNominalSampleInterval

    @Test func markIsProcessLocalAndRepeatedObservationsAreIdempotent() {
        #expect(!((WallClockHighWaterMark() as Any) is any Encodable))
        #expect(!((WallClockHighWaterMark() as Any) is any Decodable))
        var mark = WallClockHighWaterMark()
        replay([(0, 0, false), (-skew - 1, 0, true), (-skew - 1, 0, true)], on: &mark)
        var freshProcess = WallClockHighWaterMark()
        replay([(-skew - 1, 0, false)], on: &freshProcess)
    }

    @Test func forwardCorrectionAndContinuousDetector() {
        var mark = WallClockHighWaterMark()
        replay([
            (0, 0, false), (gap, gap, false),
            (gap - skew, gap, false), (gap - skew - 0.001, gap, true),
            (gap - 0.001, gap, false), (gap + 0.001, gap, false),
        ], on: &mark)

        var longGap = WallClockHighWaterMark()
        replay([(0, 0, false), (gap - skew, gap, false), (gap - skew - 0.001, gap, false)], on: &longGap)
        var longGapRewind = WallClockHighWaterMark()
        replay([(0, 0, false), (gap - skew - 0.001, gap, true)], on: &longGapRewind)
    }

    @Test func suppressionBoundUsesFirstContinuousObservation() {
        var mark = WallClockHighWaterMark()
        let back = -skew - 1
        replay([(0, 0, false), (back, 1, true), (back - 1, bound, true), (back - 1, bound + 1, false)], on: &mark)
    }

    @Test func wallTimeCatchingTheMarkEndsSuppressionBeforeTheBound() {
        var mark = WallClockHighWaterMark()
        let later = -2 * skew
        replay([
            (0, 0, false), (-skew - 10, 1, true), (-skew + 2, 13, false),
            (later, 14, true), (later, 14 + bound - 0.001, true), (later, 14 + bound, false),
        ], on: &mark)
    }

    @Test func reasonMappingHasDistinctClockAndFreshnessNames() {
        #expect(AlertDataTrustResult.clockRewound.notWatchingReason(backendConfigured: false) == .clockUntrusted)
        #expect(AlertDataTrustResult.notFresh.notWatchingReason(backendConfigured: false) == .noFreshReading)
        #expect(AlertDataTrustResult.thresholdsNotConfigured.notWatchingReason(backendConfigured: true) == .thresholdsNotSynced)
        #expect(AlertDataTrustResult.thresholdsNotConfigured.notWatchingReason(backendConfigured: false) == .thresholdsNotConfigured)
        #expect(AlertDataTrustResult.trusted.notWatchingReason(backendConfigured: false) == nil)
        #expect(NotWatchingReason(rawValue: "FUTURE_REASON") != .clockUntrusted)
    }

    @Test func notWatchingReasonsKeepTheirWireNames() {
        let reasons: [NotWatchingReason] = [
            .notificationsDenied, .thresholdsNotSynced, .thresholdsNotConfigured, .pumpDisconnected,
            .noFreshReading, .backendHasNoData, .safetyLimitsTooNarrow, .clockUntrusted,
        ]
        #expect(reasons.map(\.rawValue) == [
            "NOTIFICATIONS_DENIED", "THRESHOLDS_NOT_SYNCED", "THRESHOLDS_NOT_CONFIGURED", "PUMP_DISCONNECTED",
            "NO_FRESH_READING", "BACKEND_HAS_NO_DATA", "SAFETY_LIMITS_TOO_NARROW", "CLOCK_UNTRUSTED",
        ])
    }

    @Test func exactForwardToleranceDoesNotResetASuppressedMark() {
        var mark = WallClockHighWaterMark()
        let sixHours: TimeInterval = 6 * 3600
        replay([(0, 0, false), (sixHours, 0, false), (0, 0, true), (skew, 0, true), (2 * skew + 0.001, 0, false)], on: &mark)
    }

    @Test func backwardStepCannotRestartSuppressionWindow() {
        var mark = WallClockHighWaterMark()
        replay([
            (0, 0, false), (-skew - 1, 1, true), (-skew - 2, bound / 2, true),
            (-skew - 2, bound + 1 - 0.001, true), (-skew - 2, bound + 1, false),
        ], on: &mark)
    }

    @Test func aRewindAfterTheBoundGetsItsOwnSuppression() {
        var mark = WallClockHighWaterMark()
        let back = -skew - 1
        let later = back - skew - 1
        replay([
            (0, 0, false), (back, 1, true), (back, 1 + bound, false),
            (later, bound + 2, true), (later, 2 * bound + 2 - 0.001, true),
        ], on: &mark)
    }

    @Test func aRewindAfterAForwardCorrectionGetsTheWholeBound() {
        // The rewind directly follows the correction: any ordinary observation between
        // them would clear the earlier suppression by itself and prove nothing here.
        var mark = WallClockHighWaterMark()
        let corrected: TimeInterval = 2 * 3600
        let back = corrected + bound - skew - 1
        replay([
            (0, 0, false), (-skew - 1, 1, true), (corrected, 2, false),
            (back, 2 + bound, true), (back, 2 + 2 * bound - 0.001, true), (back, 2 + 2 * bound, false),
        ], on: &mark)
    }

    @Test func theContinuousDetectorKeepsTheMarkItRaised() {
        var mark = WallClockHighWaterMark()
        let back = gap - skew - 1
        replay([(0, 0, false), (back, gap, true), (back + 0.5, gap + 0.5, true), (back + 1, gap + 1, false)], on: &mark)
    }

    @Test func aSecondRewindCannotLowerTheMark() {
        var mark = WallClockHighWaterMark()
        let sixHours: TimeInterval = 6 * 3600
        let back = -skew - 1
        replay([(0, 0, false), (sixHours, 0, false), (0, 1, true), (back, 2, true), (back + 5, 7, true)], on: &mark)
    }

    @Test func systemElapsedClockMeasuresOnTheSleepSurvivingClock() throws {
        // A unit test cannot sleep the device, and a clock that stops during sleep would
        // read every overnight gap as a forward correction, so the source pins the choice.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/SafetyCore/ElapsedClock.swift"), encoding: .utf8
        )
        let code = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined()
        #expect(code.contains("ContinuousClock()"))
        #expect(!code.contains("SuspendingClock"))
    }

    @Test func systemElapsedClockNeverRunsBackward() {
        let clock = SystemElapsedClock()
        let first = clock.elapsed
        let second = clock.elapsed
        #expect(first >= 0 && second >= first)
    }

    @Test func oneTrustCallIsIdempotentForWallAndElapsedPair() throws {
        let setting = AlertThresholdSetting.configured(
            try AlertThresholds(urgentLow: 80, low: 100, high: 150, urgentHigh: 200), .local
        )
        let start = Date(timeIntervalSince1970: 10_000)
        var mark = WallClockHighWaterMark()
        let first = AlertDataTrust.evaluate(sensorTimestamp: start, thresholds: setting, now: start, elapsed: 0, mark: &mark)
        let repeated = AlertDataTrust.evaluate(sensorTimestamp: start, thresholds: setting, now: start, elapsed: 0, mark: &mark)
        let back = start.addingTimeInterval(-SafetyConstants.alertFloorMaxFutureSkew - 1)
        let rewind = AlertDataTrust.evaluate(sensorTimestamp: start, thresholds: setting, now: back, elapsed: 1, mark: &mark)
        let repeatedRewind = AlertDataTrust.evaluate(sensorTimestamp: start, thresholds: setting, now: back, elapsed: 1, mark: &mark)
        #expect(first == .trusted && repeated == .trusted)
        #expect(rewind == .clockRewound && repeatedRewind == .clockRewound)
    }
}
