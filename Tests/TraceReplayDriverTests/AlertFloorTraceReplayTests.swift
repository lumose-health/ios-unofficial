#if TRACE_REPLAY_DRIVER_ENABLED
import Foundation
import Testing
@_spi(DriverPlatform) import DriverAPI
import DomainCore
import SafetyCore
@testable import TraceReplayDriver

private actor RecordingAlertPort: AlertNotifying {
    private(set) var posted: [AlertFloorNotification] = []
    func canPostAlerts() async -> Bool { true }
    func post(_ notification: AlertFloorNotification) async throws(AlertPostFailure) {
        posted.append(notification)
    }
}

/// Frames are the committed bytes from `tandem-status-01.json`: a VALID
/// reading, then a status frame whose sensor reports a range excursion. The
/// excursion frame is newest, so it replays at the activation instant.
@Suite("Sensor range parser to alert floor")
struct AlertFloorTraceReplayTests {
    private static let validFrame = "000123010880e80d207b000100561f"
    private static let lowFrame = "0005230508d8ea0d20340002001fe8"
    private static let highFrame = "000623060804ec0d209a0103008a93"
    private let start = Date(timeIntervalSince1970: 1_737_030_400)

    private func trace(excursionFrame: String) -> Data {
        Data(#"""
        {
          "format": "glycemicgpt-trace",
          "version": 1,
          "vendor": "tandem",
          "description": "Valid glucose followed by an out-of-range status",
          "pumpTimeZone": "America/Chicago",
          "provenance": {"source": "synthesized", "method": "Committed frame bytes", "reviewedBy": null},
          "frames": [
            {"channel": "currentStatus", "receivedAt": "2025-01-15T14:00:05Z", "notifications": ["\#(Self.validFrame)"], "note": "VALID"},
            {"channel": "currentStatus", "receivedAt": "2025-01-15T14:10:05Z", "notifications": ["\#(excursionFrame)"], "note": "status still carries a value"}
          ]
        }
        """#.utf8)
    }

    /// Replays the two-frame trace and returns the single excursion and the
    /// glucose samples the Driver produced.
    private func replay(excursionFrame: String) async throws -> (SensorRangeExcursion?, [GlucoseSample]) {
        let bounds = SafetyConstants.glucoseValidRange
        let validator = SafetyLimitsValidator(limits: try SafetyLimits(
            glucoseLower: bounds.lowerBound, glucoseUpper: bounds.upperBound
        ))
        let driver = TraceReplayDriver(
            validator: validator, trace: .data(trace(excursionFrame: excursionFrame)), clock: FixedTraceClock(now: start)
        )
        guard case .glucoseSource(let port) = driver.capability(.glucoseSource) else {
            throw DriverFailure.capabilityUnavailable(.glucoseSource)
        }
        try await driver.activate()
        await driver.deactivate()
        var excursions: [SensorRangeExcursion] = []
        for await excursion in port.sensorRangeExcursions { excursions.append(excursion) }
        var samples: [GlucoseSample] = []
        for await sample in port.readings { samples.append(sample) }
        #expect(excursions.count == 1)
        return (excursions.first, samples)
    }

    private var thresholds: AlertThresholdSetting {
        get throws { .configured(try AlertThresholds(urgentLow: 40, low: 90, high: 300, urgentHigh: 450), .local) }
    }

    @Test("A decoded LOW frame fires an urgent low without inventing glucose")
    func lowFrameFires() async throws {
        let (replayed, samples) = try await replay(excursionFrame: Self.lowFrame)
        let excursion = try #require(replayed)
        #expect(excursion.side == .below)
        #expect(excursion.recordedAt == start)
        #expect(samples.map(\.glucose.mgdl) == [123])

        let notifier = RecordingAlertPort()
        let floor = AlertFloor(notifier: notifier, clock: FixedTraceClock(now: start))
        #expect(await floor.evaluate(excursion, thresholds: .notConfigured, backend: .notConfigured, unit: .mgdl) == .suppressed(.dataTrust(.thresholdsNotConfigured)))
        guard case .fired(let notification) = await floor.evaluate(
            excursion, thresholds: try thresholds, backend: .notConfigured, unit: .mgdl
        ) else {
            Issue.record("expected urgent low"); return
        }
        #expect(notification.type == .lowUrgent)
        #expect(notification.severity == .urgent)
        #expect(notification.tier == .interrupting)
        #expect(notification.glucose == nil)
        #expect(notification.alertIdentifier == "local-floor:low_urgent:\(Int(start.timeIntervalSince1970 * 1_000))")
        #expect(notification.body == "Urgent low glucose below the sensor's range — computed on your phone from your last sensor reading. Threshold-only, no prediction. Not a replacement for your CGM app.")
        let digits = notification.body.contains(where: \.isNumber)
        #expect(!digits)
        let posted = await notifier.posted
        #expect(posted == [notification])
    }

    @Test("A decoded HIGH frame fires an urgent high without inventing glucose")
    func highFrameFires() async throws {
        let (replayed, samples) = try await replay(excursionFrame: Self.highFrame)
        let excursion = try #require(replayed)
        #expect(excursion.side == .above)
        #expect(excursion.recordedAt == start)
        #expect(samples.map(\.glucose.mgdl) == [123])

        let floor = AlertFloor(notifier: RecordingAlertPort(), clock: FixedTraceClock(now: start))
        guard case .fired(let notification) = await floor.evaluate(
            excursion, thresholds: try thresholds, backend: .notConfigured, unit: .mmol
        ) else {
            Issue.record("expected urgent high"); return
        }
        #expect(notification.type == .highUrgent)
        #expect(notification.severity == .urgent)
        #expect(notification.tier == .interrupting)
        #expect(notification.glucose == nil)
        #expect(notification.body == "Urgent high glucose above the sensor's range — computed on your phone from your last sensor reading. Threshold-only, no prediction. Not a replacement for your CGM app.")
        let digits = notification.body.contains(where: \.isNumber)
        #expect(!digits)
    }

    @Test("A replayed LOW frame that has gone stale does not alarm")
    func staleLowFrameIsSuppressed() async throws {
        let (replayed, _) = try await replay(excursionFrame: Self.lowFrame)
        let excursion = try #require(replayed)
        let notifier = RecordingAlertPort()
        let later = FixedTraceClock(now: start.addingTimeInterval(SafetyConstants.cgmStaleAfter))
        let floor = AlertFloor(notifier: notifier, clock: later)
        #expect(await floor.evaluate(excursion, thresholds: try thresholds, backend: .notConfigured, unit: .mgdl) == .suppressed(.dataTrust(.notFresh)))
        let posted = await notifier.posted
        #expect(posted.isEmpty)
    }
}
#endif
