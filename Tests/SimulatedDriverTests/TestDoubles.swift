import Foundation
import SafetyCore

/// A clock the test advances explicitly, mirroring `AdjustableClock` in
/// `SafetyCoreTests/FreshnessMonitorTests.swift`. Duplicated rather than
/// shared because a test target cannot import another test target's
/// fixtures.
final class ManualClock: Clock, @unchecked Sendable {
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

/// A scheduler the test ticks by hand, mirroring `ManualScheduler` in
/// `SafetyCoreTests/FreshnessMonitorTests.swift`.
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

    /// How many times something registered a repeating action — used to prove
    /// a re-activation registers again rather than reusing a cancelled slot.
    var registrationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return actions.count
    }

    /// How many registrations are live right now — registered but not yet
    /// cancelled. Used to prove a (re)activation never stacks a second live
    /// tick source on top of one that was never torn down.
    var liveRegistrationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cancelled.filter { !$0 }.count
    }

    var lastRegisteredInterval: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return intervals.last
    }

    /// Fires every non-cancelled registered action once, simulating one tick
    /// elapsing.
    func tick() async {
        for action in registeredActions() { await action() }
    }

    private func registeredActions() -> [@Sendable () async -> Void] {
        lock.lock(); defer { lock.unlock() }
        return zip(actions, cancelled).filter { !$0.1 }.map(\.0)
    }

    fileprivate func markCancelled(_ index: Int) {
        lock.lock()
        cancelled[index] = true
        lock.unlock()
    }

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
