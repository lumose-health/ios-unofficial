import Foundation
import Testing

@testable import SafetyCore

/// A scheduler the test drives by hand: tests call `tick()` themselves rather than
/// waiting on real elapsed time, proving ``FreshnessMonitor`` decays purely from
/// its tick schedule. `@unchecked Sendable` with a lock, mirroring
/// `TickingClock` in ClockTests.swift — an established pattern in this test target
/// for a mutable test double, not the production type the concurrency
/// discipline binds.
final class ManualScheduler: Scheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [@Sendable () async -> Void] = []
    private var intervals: [TimeInterval] = []
    private var cancelled: [Bool] = []

    func scheduleRepeating(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> SchedulerRegistration {
        lock.lock()
        let index = actions.count
        actions.append(action)
        intervals.append(interval)
        cancelled.append(false)
        lock.unlock()
        return Registration(scheduler: self, index: index)
    }

    /// How many times something registered a repeating action — used to prove a
    /// new reading does not re-register (and so does not reset) the schedule.
    var registrationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return actions.count
    }

    var lastRegisteredInterval: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return intervals.last
    }

    /// How many registrations have been cancelled — used to prove a monitor
    /// cancels its registration when deinitialized.
    var cancelledCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cancelled.filter { $0 }.count
    }

    /// Fires every non-cancelled registered action once, simulating one tick
    /// elapsing.
    func tick() async {
        for action in registeredActions() { await action() }
    }

    // Synchronous, so the lock is never held across a suspension point — NSLock's
    // lock()/unlock() are unavailable from an async context directly.
    private func registeredActions() -> [@Sendable () async -> Void] {
        lock.lock(); defer { lock.unlock() }
        return zip(actions, cancelled).filter { !$0.1 }.map(\.0)
    }

    fileprivate func markCancelled(_ index: Int) {
        lock.lock()
        cancelled[index] = true
        lock.unlock()
    }

    /// The registration handed back from `scheduleRepeating`; cancelling it marks
    /// the corresponding action so `tick()` skips it and `cancelledCount` counts
    /// it, mirroring what a real ``Scheduler`` registration guarantees.
    private final class Registration: SchedulerRegistration, @unchecked Sendable {
        private weak var scheduler: ManualScheduler?
        private let index: Int

        init(scheduler: ManualScheduler, index: Int) {
            self.scheduler = scheduler
            self.index = index
        }

        func cancel() {
            scheduler?.markCancelled(index)
        }
    }
}

/// A clock whose `now` the test advances explicitly, so a reading's age can grow
/// with no new reading arriving — the exact scenario
/// ``FreshnessMonitor`` is required to decay under. `@unchecked Sendable` with a lock, same
/// pattern as `TickingClock` in ClockTests.swift.
final class AdjustableClock: SafetyCore.Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date) { self.current = now }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }
}

@Suite("FreshnessMonitor")
struct FreshnessMonitorTests {

    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Classification updates on tick with no new reading arriving")
    func decaysOnTickAlone() async throws {
        let thresholds = try FreshnessThresholds(staleAfter: 360, tooStaleAfter: 900)
        let clock = AdjustableClock(now: reference)
        let scheduler = ManualScheduler()
        let monitor = FreshnessMonitor(thresholds: thresholds, clock: clock, scheduler: scheduler)

        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference))
        var freshness = await monitor.freshness
        #expect(freshness == .fresh)

        // Past staleAfter, before tooStaleAfter — no new reading arrives.
        clock.advance(by: 400)
        await scheduler.tick()
        freshness = await monitor.freshness
        #expect(freshness == .stale)

        // Past tooStaleAfter.
        clock.advance(by: 600)
        await scheduler.tick()
        freshness = await monitor.freshness
        #expect(freshness == .tooStale)
    }

    @Test("A new reading does not reset or replace the tick schedule")
    func newReadingDoesNotRescheduleTimer() async throws {
        let thresholds = try FreshnessThresholds(staleAfter: 360, tooStaleAfter: 900)
        let clock = AdjustableClock(now: reference)
        let scheduler = ManualScheduler()
        let monitor = FreshnessMonitor(thresholds: thresholds, clock: clock, scheduler: scheduler)

        #expect(scheduler.registrationCount == 1)

        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference))
        clock.advance(by: 100)
        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 121), timestamp: clock.now))
        clock.advance(by: 100)
        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 122), timestamp: clock.now))

        // Still exactly one registration — new readings reclassify in place, they
        // never call scheduleRepeating again.
        #expect(scheduler.registrationCount == 1)
    }

    @Test("A new reading reclassifies immediately, without waiting for a tick")
    func newReadingReclassifiesImmediately() async throws {
        let thresholds = try FreshnessThresholds(staleAfter: 360, tooStaleAfter: 900)
        let clock = AdjustableClock(now: reference)
        let scheduler = ManualScheduler()
        let monitor = FreshnessMonitor(thresholds: thresholds, clock: clock, scheduler: scheduler)

        clock.advance(by: 400)
        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference))
        let freshness = await monitor.freshness
        #expect(freshness == .stale)
    }

    @Test("An existing tick reclassifies from the latest reading, not the one the schedule started with")
    func tickUsesLatestReadingNotTheOriginal() async throws {
        let thresholds = try FreshnessThresholds(staleAfter: 360, tooStaleAfter: 900)
        let clock = AdjustableClock(now: reference)
        let scheduler = ManualScheduler()
        let monitor = FreshnessMonitor(thresholds: thresholds, clock: clock, scheduler: scheduler)

        // Original reading at t=0.
        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference))

        // Replacement reading at t=100 — still the same, single registration.
        clock.advance(by: 100)
        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 121), timestamp: clock.now))
        #expect(scheduler.registrationCount == 1)

        // Advance to t=400 overall and fire the EXISTING registration's tick.
        clock.advance(by: 300)
        await scheduler.tick()

        // Replacement's age is 400 - 100 = 300 (Fresh). If the tick still
        // classified the original reading, its age would be 400 (Stale).
        let freshness = await monitor.freshness
        #expect(freshness == .fresh)
    }

    @Test("An out-of-order older reading is ignored and cannot regress freshness")
    func olderReadingDoesNotRegressFreshness() async throws {
        let thresholds = try FreshnessThresholds(staleAfter: 360, tooStaleAfter: 900)
        let clock = AdjustableClock(now: reference)
        let scheduler = ManualScheduler()
        let monitor = FreshnessMonitor(thresholds: thresholds, clock: clock, scheduler: scheduler)

        // A current reading arrives at t=400 (age 0, Fresh)...
        clock.advance(by: 400)
        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: clock.now))
        var freshness = await monitor.freshness
        #expect(freshness == .fresh)

        // ...then a backfilled reading stamped t=0 (age 400, would be Stale) is
        // re-delivered late. The newest known sample wins: still Fresh.
        await monitor.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 118), timestamp: reference))
        freshness = await monitor.freshness
        #expect(freshness == .fresh)
    }

    @Test("A monitor cancels its scheduler registration when deinitialized")
    func monitorCancelsRegistrationOnDeinit() async throws {
        let clock = AdjustableClock(now: reference)
        let scheduler = ManualScheduler()
        var monitor: FreshnessMonitor? = FreshnessMonitor(
            thresholds: FreshnessPolicy.cgm, clock: clock, scheduler: scheduler
        )
        await monitor?.updateReading(GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference))
        #expect(scheduler.cancelledCount == 0)

        monitor = nil

        #expect(scheduler.cancelledCount == 1)
    }

    @Test("The tick interval is one quarter of staleAfter, clamped to Android's ticker bounds")
    func tickIntervalMatchesQuarterRule() {
        #expect(FreshnessMonitor.tickInterval(staleAfter: 360) == 30)  // 90s clamped down to 30s
        #expect(FreshnessMonitor.tickInterval(staleAfter: 8) == 2)     // 2s clamped up to 2s
        #expect(FreshnessMonitor.tickInterval(staleAfter: 40) == 10)   // unclamped quarter
    }

    @Test("The monitor registers the clamped quarter-boundary interval with the scheduler")
    func registersClampedInterval() async throws {
        let clock = AdjustableClock(now: reference)
        let scheduler = ManualScheduler()
        _ = FreshnessMonitor(thresholds: FreshnessPolicy.cgm, clock: clock, scheduler: scheduler)
        #expect(scheduler.lastRegisteredInterval == 30)
    }
}
