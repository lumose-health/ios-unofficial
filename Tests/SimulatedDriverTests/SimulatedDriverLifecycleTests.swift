import Foundation
import Testing

@_spi(DriverPlatform) import DriverAPI
@testable import SimulatedDriver

/// Exercises `SimulatedDriver` the way the platform actually calls it: through
/// a real `DriverLifecycle`, stepping states in the sequence the transition
/// table permits and calling `activate()`/`deactivate()` at the points the
/// platform does.
///
/// The SPI import is the point, not an implementation detail —
/// `DriverLifecycle` is invisible to an ordinary `import DriverAPI`, which is
/// what `Sources/Drivers/Simulated` itself writes; `driver_guards.sh` fails
/// the build on an `@_spi` import there. This test target may use it because
/// it is the platform's stand-in, not a Driver.
@Suite("Simulated Driver lifecycle")
struct SimulatedDriverLifecycleTests {

    private func makeDriver() throws -> (driver: SimulatedDriver, clock: ManualClock, scheduler: ManualScheduler) {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let scheduler = ManualScheduler()
        let limits = try SafetyLimits(glucoseLower: 20, glucoseUpper: 500)
        let validator = SafetyLimitsValidator(limits: limits)
        let driver = SimulatedDriver(clock: clock, scheduler: scheduler, validator: validator)
        return (driver, clock, scheduler)
    }

    @Test("Emissions happen only between activate() and deactivate()")
    func emitsOnlyWhileActive() async throws {
        let (driver, clock, scheduler) = try makeDriver()
        guard case .glucoseSource(let port) = driver.capability(.glucoseSource) else {
            Issue.record("expected a glucoseSource port")
            return
        }
        var lifecycle = DriverLifecycle()

        // Before activation: nothing is registered, so a tick is a no-op.
        await scheduler.tick()
        #expect(try await port.latestReading() == nil)

        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)

        clock.advance(by: SimulatedDriver.defaultTickInterval)
        await scheduler.tick()
        let whileActive = try await port.latestReading()
        #expect(whileActive != nil)

        try lifecycle.advance(to: .deactivating)
        await driver.deactivate()
        try lifecycle.advance(to: .notActivated)

        // The registration was cancelled: a further tick fires nothing new.
        clock.advance(by: SimulatedDriver.defaultTickInterval)
        await scheduler.tick()
        let afterTeardown = try await port.latestReading()
        #expect(afterTeardown == whileActive)
    }

    @Test("Teardown is idempotent, including on a Driver that was never activated")
    func teardownIsIdempotent() async throws {
        let (driver, _, _) = try makeDriver()

        await driver.deactivate()
        await driver.deactivate()

        try await driver.activate()
        await driver.deactivate()
        await driver.deactivate()

        // No trap and no throw across any of the calls above is the whole
        // assertion.
    }

    @Test("Re-activation after teardown produces a working Driver again")
    func reactivationWorksAgain() async throws {
        let (driver, clock, scheduler) = try makeDriver()
        guard case .glucoseSource(let port) = driver.capability(.glucoseSource) else {
            Issue.record("expected a glucoseSource port")
            return
        }
        var lifecycle = DriverLifecycle()

        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)

        clock.advance(by: SimulatedDriver.defaultTickInterval)
        await scheduler.tick()
        let firstReading = try await port.latestReading()
        #expect(firstReading != nil)

        try lifecycle.advance(to: .deactivating)
        await driver.deactivate()
        try lifecycle.advance(to: .notActivated)

        #expect(scheduler.registrationCount == 1)

        // A Core Bluetooth restoration or a user re-enabling the Driver
        // re-enters the SAME instance (AD-11) — this is the instance from
        // above, not a fresh one.
        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)
        #expect(scheduler.registrationCount == 2, "re-activation registers a fresh tick, not the cancelled one")

        clock.advance(by: SimulatedDriver.defaultTickInterval)
        await scheduler.tick()
        let secondReading = try await port.latestReading()
        #expect(secondReading != nil)
        #expect(secondReading != firstReading, "the re-activated Driver keeps producing new data")
    }

    @Test("A failed Driver activates again without a teardown in between")
    func failedDriverActivatesAgain() async throws {
        let (driver, clock, scheduler) = try makeDriver()
        guard case .glucoseSource(let port) = driver.capability(.glucoseSource) else {
            Issue.record("expected a glucoseSource port")
            return
        }
        var lifecycle = DriverLifecycle(restoring: .failed)

        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)

        clock.advance(by: SimulatedDriver.defaultTickInterval)
        await scheduler.tick()
        #expect(try await port.latestReading() != nil)
    }

    @Test("Failed-state recovery never stacks a second live registration on top of an untorn-down one")
    func failedRecoveryDoesNotLeakARegistration() async throws {
        let (driver, _, scheduler) = try makeDriver()
        var lifecycle = DriverLifecycle()

        // active: one live registration.
        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)
        #expect(scheduler.liveRegistrationCount == 1)

        // active -> failed is a DIRECT transition — the table never routes
        // through `deactivating`, so the platform never calls `deactivate()`
        // here. The prior registration is still live going into this state.
        try lifecycle.advance(to: .failed)
        #expect(scheduler.liveRegistrationCount == 1, "the platform did not call deactivate(), so the prior registration is untouched")

        // failed -> activating calls activate() again on the SAME instance,
        // with the untorn-down registration from above still live.
        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)
        #expect(scheduler.liveRegistrationCount == 1, "re-activation must cancel the prior registration, never stack a second live one")

        // Teardown from this recovered state leaves zero live registrations.
        try lifecycle.advance(to: .deactivating)
        await driver.deactivate()
        try lifecycle.advance(to: .notActivated)
        #expect(scheduler.liveRegistrationCount == 0)

        // Reactivation still produces exactly one live registration.
        try lifecycle.advance(to: .activating)
        try await driver.activate()
        try lifecycle.advance(to: .active)
        #expect(scheduler.liveRegistrationCount == 1)
    }
}
