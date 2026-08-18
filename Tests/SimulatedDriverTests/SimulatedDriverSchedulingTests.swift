import Foundation
import Testing

@_spi(DriverPlatform) import DriverAPI
@testable import SimulatedDriver

/// Emission is driven by the injectable ``SafetyCore/Scheduler``, never by a
/// `Task.sleep` loop the driver runs itself: every test here advances
/// a manual clock and ticks a manual scheduler by hand.
@Suite("Simulated Driver emission is scheduler-driven")
struct SimulatedDriverSchedulingTests {

    private func makeDriver(
        tickInterval: TimeInterval = SimulatedDriver.defaultTickInterval
    ) throws -> (driver: SimulatedDriver, clock: ManualClock, scheduler: ManualScheduler) {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let scheduler = ManualScheduler()
        let limits = try SafetyLimits(glucoseLower: 20, glucoseUpper: 500)
        let validator = SafetyLimitsValidator(limits: limits)
        let driver = SimulatedDriver(clock: clock, scheduler: scheduler, validator: validator, tickInterval: tickInterval)
        return (driver, clock, scheduler)
    }

    @Test("Nothing is registered before activation")
    func nothingRegisteredBeforeActivation() throws {
        let (_, _, scheduler) = try makeDriver()
        #expect(scheduler.registrationCount == 0)
    }

    @Test("Activation registers exactly one repeating action, at the configured interval")
    func activationRegistersAtTheConfiguredInterval() async throws {
        let (driver, _, scheduler) = try makeDriver(tickInterval: 120)
        try await driver.activate()
        #expect(scheduler.registrationCount == 1)
        #expect(scheduler.lastRegisteredInterval == 120)
    }

    @Test("A manual scheduler tick after activation produces a reading, stamped from the injected clock")
    func manualTickProducesAReading() async throws {
        let (driver, clock, scheduler) = try makeDriver()
        guard case .glucoseSource(let port) = driver.capability(.glucoseSource) else {
            Issue.record("expected a glucoseSource port")
            return
        }
        var iterator = port.readings.makeAsyncIterator()

        try await driver.activate()
        clock.advance(by: SimulatedDriver.defaultTickInterval)
        await scheduler.tick()

        let sample = await iterator.next()
        #expect(sample != nil)
        #expect(sample?.recordedAt == clock.now)
    }

    @Test("Repeated manual ticks advance the model and produce successive, distinctly-timestamped samples")
    func repeatedTicksProduceSuccessiveSamples() async throws {
        let (driver, clock, scheduler) = try makeDriver()
        guard case .glucoseSource(let port) = driver.capability(.glucoseSource) else {
            Issue.record("expected a glucoseSource port")
            return
        }
        var iterator = port.readings.makeAsyncIterator()
        try await driver.activate()

        var samples: [GlucoseSample] = []
        for _ in 0..<5 {
            clock.advance(by: SimulatedDriver.defaultTickInterval)
            await scheduler.tick()
            if let sample = await iterator.next() { samples.append(sample) }
        }

        #expect(samples.count == 5)
        #expect(Set(samples.map(\.recordedAt)).count == 5, "each tick should stamp a distinct time")
    }

    @Test("Insulin-on-board emits alongside glucose on the same schedule")
    func insulinOnBoardEmitsOnTheSameSchedule() async throws {
        let (driver, clock, scheduler) = try makeDriver()
        guard case .insulinSource(let port) = driver.capability(.insulinSource) else {
            Issue.record("expected an insulinSource port")
            return
        }
        var iterator = port.insulinOnBoard.makeAsyncIterator()
        try await driver.activate()

        clock.advance(by: SimulatedDriver.defaultTickInterval)
        await scheduler.tick()

        let sample = await iterator.next()
        #expect(sample != nil)
        #expect(sample?.units.isFinite == true)
        #expect((sample?.units ?? -1) >= 0)
    }

    /// Reviewer-specified regression: `periodicBasalDoseIsReportedHourly`
    /// in `SimulatedGeneratorTests` only pins a COUNT (24 records over a
    /// simulated day), which a mutant that fires the basal record on 24
    /// CONSECUTIVE ticks instead of one per hour would still satisfy. This
    /// test drives the actual scheduler/clock and reads `doses(since:)` — the
    /// public surface a real caller uses — so it pins SPACING, not just count.
    @Test("Basal doses observed through doses(since:) land exactly one hour apart")
    func basalDosesArePublishedHourlyThroughThePublicSurface() async throws {
        let (driver, clock, scheduler) = try makeDriver()
        guard case .insulinSource(let port) = driver.capability(.insulinSource) else {
            Issue.record("expected an insulinSource port")
            return
        }
        let start = clock.now
        try await driver.activate()

        let ticksPerHour = Int(3600 / SimulatedDriver.defaultTickInterval)
        let hoursToObserve = 3
        for _ in 0..<(hoursToObserve * ticksPerHour) {
            clock.advance(by: SimulatedDriver.defaultTickInterval)
            await scheduler.tick()
        }

        let basalTimestamps = try await port.doses(since: start)
            .filter { $0.category == .other }
            .map(\.completedAt)
            .sorted()

        #expect(basalTimestamps.count == hoursToObserve)
        for (earlier, later) in zip(basalTimestamps, basalTimestamps.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) == 3600)
        }
    }
}
