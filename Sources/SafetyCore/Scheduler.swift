import Foundation

/// A handle to one ``Scheduler`` registration, letting its owner stop future
/// ticks.
///
/// ``FreshnessMonitor`` cancels its own registration when it deinitializes, so a
/// released monitor's ticks stop instead of running forever against a weakly
/// captured, now-nil owner.
public protocol SchedulerRegistration: Sendable {

    /// Stops future ticks for this registration. Idempotent, and safe to call
    /// from any context, including a `deinit`.
    func cancel()
}

/// Where periodic re-evaluation gets its ticks — the timing counterpart to
/// ``Clock`` (AD-14).
///
/// ``FreshnessMonitor`` re-evaluates on a schedule independent of new data
/// arriving: a reading that stops updating must still decay from Fresh to Stale to
/// TooStale on its own. A decay driven by a live timer cannot be tested at its
/// boundaries any more than code that reads the wall clock directly can, so the
/// schedule is injected exactly like ``Clock``: tests register a manual scheduler
/// and drive ticks themselves.
public protocol Scheduler: Sendable {

    /// Registers `action` to run repeatedly, roughly every `interval` seconds,
    /// until the returned registration is cancelled.
    ///
    /// - Precondition: `interval` is finite and greater than zero. A zero or
    ///   negative interval would make `Task.sleep`-backed implementations resume
    ///   immediately and hot-loop `action`; a non-finite one traps inside
    ///   `Duration` conversion. Implementations trap on violation rather than
    ///   schedule anything — ``FreshnessMonitor/tickInterval(staleAfter:)``'s
    ///   clamp guarantees every production interval satisfies this.
    func scheduleRepeating(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> SchedulerRegistration
}
