import Foundation
import Testing
import SafetyCore
import DomainCore
import SimulatedDriver
@_spi(DriverPlatform) import DriverAPI

private final class FloorTestScheduler: Scheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () async -> Void)?

    func scheduleRepeating(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> SchedulerRegistration {
        lock.lock(); defer { lock.unlock() }
        self.action = action
        return FloorTestRegistration()
    }

    func tick() async {
        let action = currentAction()
        await action?()
    }

    private func currentAction() -> (@Sendable () async -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        let action = self.action
        return action
    }
}

private final class FloorTestRegistration: SchedulerRegistration, @unchecked Sendable {
    func cancel() {}
}

@Suite("Alert floor with the Simulated Driver")
struct AlertFloorSimulatedDriverTests {
    @Test func everyDriverSampleUsesTheSameClassifierAndCooldown() async throws {
        let clock = AlertTestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let scheduler = FloorTestScheduler()
        let limits = try SafetyLimits(glucoseLower: 20, glucoseUpper: 500)
        let driver = SimulatedDriver(
            clock: clock, scheduler: scheduler, validator: SafetyLimitsValidator(limits: limits),
            tickInterval: 60
        )
        guard case .glucoseSource(let glucosePort) = driver.capability(.glucoseSource) else {
            Issue.record("expected glucose port"); return
        }
        var iterator = glucosePort.readings.makeAsyncIterator()
        let notifier = FakeAlertNotifier()
        let unconfiguredNotifier = FakeAlertNotifier()
        let floor = AlertFloor(notifier: notifier, clock: clock)
        let unconfiguredFloor = AlertFloor(notifier: unconfiguredNotifier, clock: clock)
        let thresholds = try AlertThresholds(urgentLow: 80, low: 100, high: 150, urgentHigh: 200)
        let setting = AlertThresholdSetting.configured(thresholds, .local)
        var lastFired: [AlertType: Date] = [:]
        var firedCount = 0

        try await driver.activate()
        for index in 0..<288 {
            if index > 0 {
                clock.advance(60)
                await scheduler.tick()
            }
            let sample = try #require(await iterator.next())
            let reading = GlucoseReading(glucose: sample.glucose, timestamp: sample.recordedAt)
            let outcome = await floor.evaluate(reading, thresholds: setting, backend: .notConfigured, unit: .mgdl)
            if case .fired(let notification) = outcome {
                firedCount += 1
                #expect(notification.type == AlertClassifier.classify(sample.glucose, against: thresholds))
                if let previous = lastFired[notification.type] {
                    #expect(notification.sensorTimestamp.timeIntervalSince(previous) >= SafetyConstants.alertFloorCooldown)
                }
                lastFired[notification.type] = notification.sensorTimestamp
            }
            let unconfigured = await unconfiguredFloor.evaluate(reading, thresholds: .notConfigured, backend: .notConfigured, unit: .mgdl)
            #expect(unconfigured == .suppressed(.dataTrust(.thresholdsNotConfigured)))
        }
        #expect(firedCount > 0)
        let unconfiguredPosts = await unconfiguredNotifier.notifications()
        #expect(unconfiguredPosts.isEmpty)
        await driver.deactivate()
    }
}
