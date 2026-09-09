import Foundation
import Testing

@testable import SafetyCore

@Suite("WallClockScheduler")
struct WallClockSchedulerTests {

    /// A tick counter mutated from the scheduled task and read from the test —
    /// `@unchecked Sendable` with a lock, the same pattern `AdjustableClock` and
    /// `ManualScheduler` use for mutable test state shared across contexts.
    final class TickCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }
    }

    /// The one test in this suite that cannot inject its way out of waiting on
    /// real elapsed time: `WallClockScheduler` IS the real-timing adapter (the
    /// scheduler counterpart to `SystemClock`), so proving its cancellation stops
    /// the underlying `Task` means observing real ticks before and after.
    @Test("Cancelling a registration stops further ticks")
    func cancelStopsTicking() async throws {
        let scheduler = WallClockScheduler()
        let counter = TickCounter()

        let registration = scheduler.scheduleRepeating(interval: 0.02) {
            counter.increment()
        }

        // The first tick is WAITED FOR, not assumed to have landed by a deadline.
        // At a 0.02s interval a fixed 0.1s wait has almost no margin, and on a busy
        // machine the scheduler's first dispatch can arrive after it — which fails
        // this test for a reason that has nothing to do with cancellation. Polling
        // up to a second for a tick that normally arrives in 0.02s keeps the
        // assertion (it ticked) and drops the assumption (it ticked by then).
        var ticked = false
        for _ in 0..<50 {
            if counter.value > 0 {
                ticked = true
                break
            }
            try await Task.sleep(for: .seconds(0.02))
        }
        #expect(ticked, "the scheduler never ticked, so there is nothing to cancel")

        registration.cancel()

        // Cooperative cancellation permits one tick already past the
        // `Task.isCancelled` check to still land right after `cancel()` returns —
        // that is not what this test is pinning. So two readings are taken well
        // apart, after that grace window: if ticking had truly stopped they
        // agree; if the loop were still running the counter would keep climbing
        // between them.
        try await Task.sleep(for: .seconds(0.05))
        let settled1 = counter.value
        try await Task.sleep(for: .seconds(0.1))
        let settled2 = counter.value

        #expect(settled1 == settled2)
    }
}
