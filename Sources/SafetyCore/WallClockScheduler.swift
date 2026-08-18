import Foundation

// ============================================================================
// Structural analogue of SystemClock.swift's guard exemption — the ONE
// production adapter permitted to drive real timing. Do not add logic here:
// anything that *decides* a re-evaluation cadence (the quarter-boundary rule,
// clamping) belongs in FreshnessMonitor, which can be tested at its
// boundaries; this file only turns "every `interval` seconds" into a running
// Task.
//
// Unlike SystemClock, this file reads no wall-clock spelling from
// safety_guards.sh's CLOCK_FORBIDDEN list — `Task.sleep` suspends against the
// Swift Concurrency clock, not `Date()` — so it needs no guard exemption entry.
// It is still kept in its own single-purpose file, for the same reason
// SystemClock is: a real-timing adapter should not share a file with logic
// that wants to be tested without waiting on it.
// ============================================================================

/// The production ``Scheduler``: real elapsed time, via `Task.sleep`.
///
/// Inject this at the composition root and nowhere else. Tests inject a manual
/// scheduler instead, which is the entire point of the protocol.
public struct WallClockScheduler: Scheduler {

    public init() {}

    public func scheduleRepeating(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> SchedulerRegistration {
        // The ``Scheduler`` precondition, enforced before the Task exists: a
        // zero/negative interval would hot-loop `action` (Task.sleep returns
        // immediately for a non-positive Duration), and a non-finite one traps
        // inside the Duration conversion mid-loop instead of at the call site.
        precondition(interval.isFinite && interval > 0,
                     "scheduleRepeating requires a finite interval > 0, got \(interval)")
        let task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await action()
            }
        }
        return WallClockRegistration(task: task)
    }
}

/// Cancels the `Task` backing one `WallClockScheduler` registration.
private struct WallClockRegistration: SchedulerRegistration {
    let task: Task<Void, Never>

    func cancel() {
        task.cancel()
    }
}
