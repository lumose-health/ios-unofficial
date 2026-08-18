import Foundation

/// Holds a ``SchedulerRegistration`` outside of ``FreshnessMonitor``'s actor
/// isolation, guarded by its own lock rather than the actor's.
///
/// `FreshnessMonitor.init` hands the scheduler a `[weak self]` closure to avoid
/// keeping the monitor alive forever; once that escaping closure exists, Swift's
/// actor-initializer isolation rules forbid writing to any further actor-isolated
/// `var` from `init` (the closure could in principle run concurrently before
/// `init` returns). Routing the registration through this plain `Sendable` box —
/// a `let` on the actor, so reading the box itself needs no isolation — sidesteps
/// that, and lets `deinit`, which is `nonisolated` and cannot `await` the actor,
/// cancel the registration synchronously.
private final class RegistrationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var registration: SchedulerRegistration?

    func set(_ registration: SchedulerRegistration) {
        lock.lock()
        self.registration = registration
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let registration = registration
        lock.unlock()
        registration?.cancel()
    }
}

/// Re-evaluates a reading's ``Freshness`` on a timer, independent of new data
/// arriving (FR-50).
///
/// A reading that stops updating must still decay from Fresh to Stale to TooStale
/// on its own — nothing else drives that transition. So the monitor re-evaluates
/// on `scheduler`'s ticks, not only when ``updateReading(_:)`` is called; the tick
/// schedule is set up once, in `init`, and a later reading never resets or
/// replaces it. Deinitializing the monitor cancels that registration, so a
/// released monitor's ticks stop instead of continuing forever against a weakly
/// captured, now-nil `self`.
///
/// An actor, not a lock-guarded class: classification is read and written from
/// whichever context calls in (production: the scheduler's ticks and whatever
/// delivers new readings; tests: a manual scheduler), and actor isolation is the
/// concurrency-safe way to serialize that without `@unchecked Sendable`.
public actor FreshnessMonitor {

    /// The floor on the tick interval, mirroring Android's alert-floor ticker
    /// (`AlertFloorStatusProvider.kt:135`, `MIN_TICK_MS`): frequent enough that a
    /// short `staleAfter` (e.g. a compressed debug policy) still decays visibly.
    static let minTickInterval: TimeInterval = 2

    /// The ceiling on the tick interval (`AlertFloorStatusProvider.kt:136`,
    /// `MAX_TICK_MS`): never hot-loop, but never wait so long that a long-lived
    /// `staleAfter` decays only after a very stale delay.
    static let maxTickInterval: TimeInterval = 30

    private let thresholds: FreshnessThresholds
    private let clock: any Clock
    private var latestReading: GlucoseReading?

    /// The scheduler registration set up in `init`, cancelled in `deinit` so the
    /// tick loop does not outlive this monitor.
    private let registrationBox = RegistrationBox()

    /// The current classification. Starts ``Freshness/fresh`` before any reading
    /// has arrived — there is nothing to be stale yet.
    public private(set) var freshness: Freshness = .fresh

    public init(thresholds: FreshnessThresholds, clock: some Clock, scheduler: some Scheduler) {
        self.thresholds = thresholds
        self.clock = clock
        let interval = FreshnessMonitor.tickInterval(staleAfter: thresholds.staleAfter)
        let registration = scheduler.scheduleRepeating(interval: interval) { [weak self] in
            await self?.reevaluate()
        }
        registrationBox.set(registration)
    }

    deinit {
        registrationBox.cancel()
    }

    /// One quarter of `staleAfter` (FR-50), clamped to
    /// `[minTickInterval, maxTickInterval]` the way Android's alert-floor ticker is
    /// (`AlertFloorStatusProvider.kt:64`: `(thresholds.staleAfterMs / 4).coerceIn(...)`).
    static func tickInterval(staleAfter: TimeInterval) -> TimeInterval {
        min(max(staleAfter / 4, minTickInterval), maxTickInterval)
    }

    /// Records a new reading and reclassifies immediately from it. Does not touch
    /// the tick schedule set up in `init` — the timer keeps its own cadence
    /// regardless of how often data arrives.
    ///
    /// A reading older than the one already held is ignored: backfilled or
    /// re-delivered samples can arrive out of order, and classification tracks the
    /// newest known sample — a late-arriving older one must not flip a Fresh
    /// display back to Stale. An equal timestamp (a re-delivery of the same
    /// sample) is accepted and reclassifies harmlessly.
    public func updateReading(_ reading: GlucoseReading) {
        if let current = latestReading, reading.timestamp < current.timestamp { return }
        latestReading = reading
        reevaluate()
    }

    private func reevaluate() {
        guard let reading = latestReading else { return }
        // `clock` is stored as `any Clock` so FreshnessMonitor is not generic over
        // its clock type; that existential can't be passed to GlucoseReading's
        // `age(asOf: some Clock)`, so the age is computed the same way `age(asOf:)`
        // does internally, against the existential's `now` directly.
        let age = clock.now.timeIntervalSince(reading.timestamp)
        freshness = thresholds.classify(age: age)
    }
}
