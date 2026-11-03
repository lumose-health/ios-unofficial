import Foundation
import Testing
import SafetyCore
import DomainCore
import DriverAPI

final class AlertTestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ now: Date) { value = now }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value = value.addingTimeInterval(interval)
    }
}

actor FakeAlertNotifier: AlertNotifying {
    var allowed = true
    var fails = false
    private(set) var checks = 0
    private(set) var attempts = 0
    private(set) var posted: [AlertFloorNotification] = []

    func canPostAlerts() async -> Bool {
        checks += 1
        return allowed
    }
    func post(_ notification: AlertFloorNotification) async throws(AlertPostFailure) {
        attempts += 1
        if fails { throw .unavailable }
        posted.append(notification)
    }
    func setAllowed(_ value: Bool) { allowed = value }
    func setFails(_ value: Bool) { fails = value }
    func calls() -> (Int, Int) { (checks, attempts) }
    func notifications() -> [AlertFloorNotification] { posted }
}

private actor PausingAlertNotifier: AlertNotifying {
    private var started = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var posts = 0

    func canPostAlerts() async -> Bool { true }
    func post(_ notification: AlertFloorNotification) async throws(AlertPostFailure) {
        posts += 1
        started = true
        startedWaiter?.resume()
        startedWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitUntilPostStarts() async {
        if started { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }
    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

/// Suspends the first post until released, then succeeds or fails on demand.
/// Later posts complete immediately.
private actor GatedAlertNotifier: AlertNotifying {
    private var gated = true
    private var started = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var releaseFails = false
    private(set) var attempts = 0
    private(set) var posted: [AlertFloorNotification] = []

    func canPostAlerts() async -> Bool { true }
    func post(_ notification: AlertFloorNotification) async throws(AlertPostFailure) {
        attempts += 1
        if gated {
            gated = false
            started = true
            startedWaiter?.resume()
            startedWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
            if releaseFails { throw .unavailable }
        }
        posted.append(notification)
    }
    func waitUntilPostStarts() async {
        if started { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }
    func release(failing: Bool) {
        releaseFails = failing
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@Suite("Alert floor gates and episodes")
struct AlertFloorTests {
    private func setup() throws -> (AlertFloor, FakeAlertNotifier, AlertTestClock, AlertThresholdSetting) {
        let clock = AlertTestClock(Date(timeIntervalSince1970: 175))
        let notifier = FakeAlertNotifier()
        let floor = AlertFloor(notifier: notifier, clock: clock)
        let thresholds = try AlertThresholds(urgentLow: 55, low: 70, high: 180, urgentHigh: 250)
        return (floor, notifier, clock, .configured(thresholds, .local))
    }

    private func reading(_ value: Double, at timestamp: Date) throws -> GlucoseReading {
        GlucoseReading(glucose: try Glucose(mgdl: value), timestamp: timestamp)
    }

    @Test func unconfiguredAndInRangeStopBeforePort() async throws {
        let (floor, port, clock, setting) = try setup()
        let low = try reading(54, at: clock.now)
        #expect(await floor.evaluate(low, thresholds: .notConfigured, backend: .notConfigured, unit: .mgdl) == .suppressed(.dataTrust(.thresholdsNotConfigured)))
        #expect(await floor.evaluate(try reading(100, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .inRange)
        let calls = await port.calls()
        #expect(calls.0 == 0 && calls.1 == 0)
    }

    @Test func excursionsUseThresholdAndFreshnessGates() async throws {
        let (floor, port, clock, setting) = try setup()
        let below = SensorRangeExcursion(side: .below, recordedAt: clock.now)
        #expect(await floor.evaluate(below, thresholds: .notConfigured, backend: .notConfigured, unit: .mgdl) == .suppressed(.dataTrust(.thresholdsNotConfigured)))
        let stale = SensorRangeExcursion(side: .below, recordedAt: clock.now.addingTimeInterval(-SafetyConstants.cgmStaleAfter))
        #expect(await floor.evaluate(stale, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.dataTrust(.notFresh)))
        let healthy = BackendAlertingStatus.configured(networkReachable: true, streamConnected: true, backendHasFreshGlucose: true)
        #expect(await floor.evaluate(below, thresholds: setting, backend: healthy, unit: .mgdl) == .suppressed(.backendAlerting))
        let calls = await port.calls()
        #expect(calls.0 == 0 && calls.1 == 0)
    }

    @Test func excursionNotificationUsesWordsAndNoGlucoseValue() async throws {
        let (floor, _, clock, setting) = try setup()
        let below = SensorRangeExcursion(side: .below, recordedAt: clock.now)
        guard case .fired(let low) = await floor.evaluate(below, thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("below-range report should fire"); return
        }
        #expect(low.type == .lowUrgent)
        #expect(low.severity == .urgent && low.tier == .interrupting)
        #expect(low.alertIdentifier == "local-floor:low_urgent:175000")
        #expect(low.glucose == nil)
        #expect(low.body == "Urgent low glucose below the sensor's range — computed on your phone from your last sensor reading. Threshold-only, no prediction. Not a replacement for your CGM app.")

        let above = SensorRangeExcursion(side: .above, recordedAt: clock.now)
        guard case .fired(let high) = await floor.evaluate(above, thresholds: setting, backend: .notConfigured, unit: .mmol) else {
            Issue.record("above-range report should fire"); return
        }
        #expect(high.type == .highUrgent)
        #expect(high.severity == .urgent && high.tier == .interrupting)
        #expect(high.glucose == nil)
        #expect(high.body == "Urgent high glucose above the sensor's range — computed on your phone from your last sensor reading. Threshold-only, no prediction. Not a replacement for your CGM app.")
        // The edge number the frame carries is never shown, in either unit.
        let numbers = [low.body, high.body].filter { $0.contains(where: \.isNumber) }
        #expect(numbers.isEmpty)
    }

    @Test func belowRangeFiresDuringAcknowledgedLowWarningAndRearmsIt() async throws {
        let (floor, port, clock, setting) = try setup()
        let configured = try #require(setting.configuredThresholds)
        let warning = try reading(Double(configured.low), at: clock.now)
        guard case .fired = await floor.evaluate(warning, thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("low warning should fire"); return
        }
        await floor.acknowledge(.lowWarning)
        let below = SensorRangeExcursion(side: .below, recordedAt: clock.now)
        guard case .fired = await floor.evaluate(below, thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("below-range report should fire during warning cooldown"); return
        }
        #expect(await floor.evaluate(below, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        guard case .fired = await floor.evaluate(warning, thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("acknowledged low warning should re-arm"); return
        }
        let posted = await port.notifications()
        #expect(posted.map(\.type) == [.lowWarning, .lowUrgent, .lowWarning])
    }

    @Test func numericUrgentLowCoolsDownABelowRangeReport() async throws {
        let (floor, port, clock, setting) = try setup()
        let t = try fixture(setting)
        guard case .fired = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("numeric urgent low should fire"); return
        }
        clock.advance(1)
        let below = SensorRangeExcursion(side: .below, recordedAt: clock.now)
        #expect(await floor.evaluate(below, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        let posted = await port.notifications()
        #expect(posted.map(\.type) == [.lowUrgent])
        let allNumeric = posted.allSatisfy { $0.glucose != nil }
        #expect(allNumeric)
    }

    @Test func belowRangeReportCoolsDownANumericUrgentLow() async throws {
        let (floor, port, clock, setting) = try setup()
        let t = try fixture(setting)
        let below = SensorRangeExcursion(side: .below, recordedAt: clock.now)
        guard case .fired = await floor.evaluate(below, thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("below-range report should fire"); return
        }
        clock.advance(1)
        #expect(await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        let posted = await port.notifications()
        #expect(posted.map(\.type) == [.lowUrgent])
        #expect(posted.map(\.glucose) == [nil])
    }

    @Test func acknowledgedUrgentLowRearmsSoABelowRangeReportFires() async throws {
        let (floor, port, clock, setting) = try setup()
        let t = try fixture(setting)
        _ = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl)
        await floor.acknowledge(.lowUrgent)
        let below = SensorRangeExcursion(side: .below, recordedAt: clock.now)
        #expect(await floor.evaluate(below, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        guard case .fired = await floor.evaluate(try reading(Double(t.low), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("low warning should fire"); return
        }
        guard case .fired(let rearmed) = await floor.evaluate(below, thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("a different type must re-arm the acknowledged urgent low for a below-range report"); return
        }
        #expect(rearmed.glucose == nil)
        let posted = await port.notifications()
        #expect(posted.map(\.type) == [.lowUrgent, .lowWarning, .lowUrgent])
    }

    @Test func backendGateStopsBeforeTrustAndPort() async throws {
        let (floor, port, clock, setting) = try setup()
        let stale = try reading(54, at: clock.now.addingTimeInterval(-SafetyConstants.cgmStaleAfter))
        let healthy = BackendAlertingStatus.configured(networkReachable: true, streamConnected: true, backendHasFreshGlucose: true)
        #expect(await floor.evaluate(stale, thresholds: setting, backend: healthy, unit: .mgdl) == .suppressed(.backendAlerting))
        let calls = await port.calls()
        #expect(calls.0 == 0 && calls.1 == 0)
    }

    @Test func trustGateStopsBeforePort() async throws {
        let (floor, port, clock, setting) = try setup()
        let stale = try reading(54, at: clock.now.addingTimeInterval(-SafetyConstants.cgmStaleAfter))
        #expect(await floor.evaluate(stale, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.dataTrust(.notFresh)))
        let calls = await port.calls()
        #expect(calls.0 == 0 && calls.1 == 0)
    }

    @Test func rewindDoesNotRearmAcknowledgedEpisodeOrCallPort() async throws {
        let (floor, port, clock, setting) = try setup()
        let low = try reading(54, at: clock.now)
        _ = await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl)
        await floor.acknowledge(.lowUrgent)
        clock.advance(-SafetyConstants.alertFloorMaxFutureSkew - 0.001)
        #expect(await floor.evaluate(try reading(100, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.clockRewound))
        let calls = await port.calls()
        #expect(calls.0 == 1 && calls.1 == 1)
        clock.advance(SafetyConstants.alertFloorMaxFutureSkew + 0.001)
        #expect(await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
    }

    @Test func permissionGateDoesNotStampCooldown() async throws {
        let (floor, port, clock, setting) = try setup()
        await port.setAllowed(false)
        let low = try reading(54, at: clock.now)
        #expect(await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.cannotPost))
        let before = await port.calls()
        #expect(before.0 == 1 && before.1 == 0)
        await port.setAllowed(true)
        guard case .fired = await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("permission recovery should fire immediately"); return
        }
    }

    @Test func cooldownBoundaryAndUnacknowledgedRecovery() async throws {
        let (floor, port, clock, setting) = try setup()
        let low = try reading(54, at: clock.now)
        guard case .fired = await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("first low should fire"); return
        }
        #expect(await floor.evaluate(try reading(100, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .inRange)
        clock.advance(SafetyConstants.alertFloorCooldown - 0.001)
        #expect(await floor.evaluate(try reading(54, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        clock.advance(0.001)
        guard case .fired = await floor.evaluate(try reading(54, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("cooldown boundary should fire"); return
        }
        let calls = await port.calls()
        #expect(calls.0 == 3 && calls.1 == 2)
    }

    @Test func acknowledgementRearmsOnRecoveryAndRestartsSustainedCooldown() async throws {
        let (floor, _, clock, setting) = try setup()
        let low = try reading(54, at: clock.now)
        _ = await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl)
        await floor.acknowledge(.lowUrgent)
        #expect(await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        clock.advance(SafetyConstants.alertFloorCooldown)
        guard case .fired = await floor.evaluate(try reading(54, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("sustained condition should re-alarm after acknowledgement cooldown"); return
        }
        await floor.acknowledge(.lowUrgent)
        _ = await floor.evaluate(try reading(100, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl)
        guard case .fired = await floor.evaluate(try reading(54, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("re-cross should re-alarm immediately"); return
        }
    }

    @Test func acknowledgingOneTypePreservesOtherTypeCooldown() async throws {
        let (floor, port, clock, setting) = try setup()
        _ = await floor.evaluate(try reading(54, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl)
        _ = await floor.evaluate(try reading(260, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl)
        await floor.acknowledge(.lowUrgent)
        #expect(await floor.evaluate(try reading(260, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        let posted = await port.notifications()
        #expect(posted.map(\.type) == [.lowUrgent, .highUrgent])
    }

    @Test func anOverlappingEvaluationCannotPostTwice() async throws {
        let clock = AlertTestClock(Date(timeIntervalSince1970: 175))
        let port = PausingAlertNotifier()
        let floor = AlertFloor(notifier: port, clock: clock)
        let setting = try AlertThresholdSetting.configured(
            AlertThresholds(urgentLow: 55, low: 70, high: 180, urgentHigh: 250), .local
        )
        let low = try reading(54, at: clock.now)
        let first = Task { await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl) }
        await port.waitUntilPostStarts()
        let second = await floor.evaluate(low, thresholds: setting, backend: .notConfigured, unit: .mgdl)
        #expect(second == .suppressed(.coolingDown))
        await port.release()
        guard case .fired = await first.value else { Issue.record("first post should complete"); return }
        let posts = await port.posts
        #expect(posts == 1)
    }

    @Test func failedPostRollsBackAndBackendWithoutGlucoseDegrades() async throws {
        let (floor, port, clock, setting) = try setup()
        let backend = BackendAlertingStatus.configured(networkReachable: true, streamConnected: true, backendHasFreshGlucose: false)
        await port.setFails(true)
        let low = try reading(54, at: clock.now)
        #expect(await floor.evaluate(low, thresholds: setting, backend: backend, unit: .mgdl) == .suppressed(.postFailed))
        await port.setFails(false)
        guard case .fired(let notification) = await floor.evaluate(low, thresholds: setting, backend: backend, unit: .mgdl) else {
            Issue.record("failed post must be retried"); return
        }
        #expect(notification.type == .lowUrgent)
        let calls = await port.calls()
        #expect(calls.0 == 2 && calls.1 == 2)
    }

    @Test func notificationContentAndOnlyGlucoseTypes() async throws {
        let (floor, _, clock, setting) = try setup()
        guard case .fired(let notification) = await floor.evaluate(try reading(54, at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("expected floor notification"); return
        }
        #expect(notification.slotIdentifier == "low_urgent|")
        #expect(notification.alertIdentifier == "local-floor:low_urgent:175000")
        #expect(notification.severity == .urgent)
        #expect(notification.tier == .interrupting)
        #expect(notification.sensorTimestamp == clock.now)
        #expect(notification.body == "Urgent low glucose 54 mg/dL — computed on your phone from your last sensor reading. Threshold-only, no prediction. Not a replacement for your CGM app.")
        let glucose = try #require(notification.glucose)
        let mmol = AlertFloorContent.body(for: .lowUrgent, glucose: glucose, unit: .mmol)
        #expect(mmol.contains(GlucoseFormatter.stringWithLabel(glucose, in: .mmol)))
        let thresholds = try #require(setting.configuredThresholds)
        for value in stride(from: 20, through: 500, by: 1) {
            let type = AlertClassifier.classify(try Glucose(mgdl: value), against: thresholds)
            #expect(type != .iobWarning && type != .noData)
        }
    }

    private func fixture(_ setting: AlertThresholdSetting) throws -> AlertThresholds {
        try #require(setting.configuredThresholds)
    }

    @Test func urgentLowFiresDuringLowWarningCooldownAndHighFamilyIsUntouched() async throws {
        let (floor, port, clock, setting) = try setup()
        let t = try fixture(setting)
        guard case .fired = await floor.evaluate(try reading(Double(t.low), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("low warning should fire"); return
        }
        guard case .fired = await floor.evaluate(try reading(Double(t.high), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("high warning should fire"); return
        }
        clock.advance(10 * 60)
        guard case .fired(let urgent) = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("urgent low inside the low warning cooldown must fire"); return
        }
        #expect(urgent.type == .lowUrgent)
        #expect(await floor.evaluate(try reading(Double(t.low), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        #expect(await floor.evaluate(try reading(Double(t.high), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        guard case .fired = await floor.evaluate(try reading(Double(t.urgentHigh), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("urgent high has its own cooldown"); return
        }
        let posted = await port.notifications()
        #expect(posted.map(\.type) == [.lowWarning, .highWarning, .lowUrgent, .highUrgent])
    }

    @Test func acknowledgedUrgentLowRearmsOnLowWarning() async throws {
        let (floor, port, clock, setting) = try setup()
        let t = try fixture(setting)
        _ = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl)
        await floor.acknowledge(.lowUrgent)
        guard case .fired = await floor.evaluate(try reading(Double(t.low), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("low warning should fire"); return
        }
        guard case .fired = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("a different type must re-arm the acknowledged urgent low"); return
        }
        let posted = await port.notifications()
        #expect(posted.map(\.type) == [.lowUrgent, .lowWarning, .lowUrgent])
    }

    @Test func rearmHappensEvenWhenALaterGateStopsTheReading() async throws {
        let healthy = BackendAlertingStatus.configured(networkReachable: true, streamConnected: true, backendHasFreshGlucose: true)
        let cases: [(BackendAlertingStatus, TimeInterval, AlertFloorSuppression)] = [
            (healthy, 0, .backendAlerting),
            (.notConfigured, SafetyConstants.cgmStaleAfter, .dataTrust(.notFresh)),
        ]
        for (backend, age, expected) in cases {
            let (floor, port, clock, setting) = try setup()
            let t = try fixture(setting)
            _ = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl)
            await floor.acknowledge(.lowUrgent)
            let warning = try reading(Double(t.low), at: clock.now.addingTimeInterval(-age))
            #expect(await floor.evaluate(warning, thresholds: setting, backend: backend, unit: .mgdl) == .suppressed(expected))
            guard case .fired = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
                Issue.record("re-arm must not depend on the later gates (\(expected))"); return
            }
            let posted = await port.notifications()
            #expect(posted.map(\.type) == [.lowUrgent, .lowUrgent])
        }
    }

    @Test func failedPostRestoresAcknowledgement() async throws {
        let (floor, port, clock, setting) = try setup()
        let t = try fixture(setting)
        _ = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl)
        await floor.acknowledge(.lowUrgent)
        clock.advance(SafetyConstants.alertFloorCooldown)
        await port.setFails(true)
        #expect(await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.postFailed))
        await port.setFails(false)
        // A small correction inside the rewind tolerance puts the acknowledgement back
        // inside its cooldown, so only the restored acknowledgement can re-arm it.
        clock.advance(-SafetyConstants.alertFloorMaxFutureSkew / 2)
        #expect(await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        guard case .fired = await floor.evaluate(try reading(Double(t.low), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("low warning should fire"); return
        }
        guard case .fired = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("restored acknowledgement must re-arm on a different type"); return
        }
        let posted = await port.notifications()
        #expect(posted.map(\.type) == [.lowUrgent, .lowWarning, .lowUrgent])
    }

    @Test func readingSuppressedBehindAFailingPostFiresOnTheNextReading() async throws {
        let (_, _, clock, setting) = try setup()
        let port = GatedAlertNotifier()
        let floor = AlertFloor(notifier: port, clock: clock)
        let t = try fixture(setting)
        let a = try reading(Double(t.urgentLow), at: clock.now)
        let first = Task { await floor.evaluate(a, thresholds: setting, backend: .notConfigured, unit: .mgdl) }
        await port.waitUntilPostStarts()
        clock.advance(1)
        let b = try reading(Double(t.urgentLow), at: clock.now)
        #expect(await floor.evaluate(b, thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        await port.release(failing: true)
        #expect(await first.value == .suppressed(.postFailed))
        clock.advance(1)
        guard case .fired(let notification) = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("the alarm held back behind a failed post must fire"); return
        }
        #expect(notification.type == .lowUrgent)
        let attempts = await port.attempts
        let posted = await port.posted
        #expect(attempts == 2 && posted.count == 1)
    }

    @Test func acknowledgementCooldownBoundary() async throws {
        let (floor, port, clock, setting) = try setup()
        let t = try fixture(setting)
        _ = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl)
        // Acknowledge later than the post, so the boundary below is measured from the acknowledgement.
        clock.advance(10 * 60)
        await floor.acknowledge(.lowUrgent)
        clock.advance(SafetyConstants.alertFloorCooldown - 0.001)
        #expect(await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) == .suppressed(.coolingDown))
        clock.advance(0.001)
        guard case .fired = await floor.evaluate(try reading(Double(t.urgentLow), at: clock.now), thresholds: setting, backend: .notConfigured, unit: .mgdl) else {
            Issue.record("acknowledgement cooldown boundary should fire"); return
        }
        let calls = await port.calls()
        #expect(calls.1 == 2)
    }
}
