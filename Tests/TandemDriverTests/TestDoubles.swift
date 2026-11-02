import Foundation
import SafetyCore
import Testing
import TandemDriver

final class FakeCentral: BluetoothCentral, @unchecked Sendable {
    let events: AsyncStream<CentralEvent>
    private let continuation: AsyncStream<CentralEvent>.Continuation
    private let lock = NSLock()
    private var starts: [[String]] = []
    private var stops = 0
    private var terminated = false
    init() {
        let pair = AsyncStream<CentralEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }
    /// Marks the stream ended without capturing the central, so a consumer that stops
    /// iterating is observable even after the central itself is released.
    func onConsumerEnded(_ flag: Flag) { continuation.onTermination = { _ in flag.set() } }
    func startScan(services: [String]) { lock.withLock { starts.append(services) } }
    func stopScan() { lock.withLock { stops += 1 } }
    func send(_ event: CentralEvent) { continuation.yield(event) }
    var startCalls: [[String]] { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
}

final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_700_000_000)
    var now: Date { lock.withLock { value } }
    func advance(by seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

/// Runs registered actions only when a test calls `tick()`, and awaits each one, so a
/// tick's effects are visible as soon as it returns.
final class ManualScheduler: Scheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(action: @Sendable () async -> Void, cancelled: Bool)] = []
    func scheduleRepeating(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> SchedulerRegistration {
        let index = lock.withLock {
            entries.append((action, false))
            return entries.count - 1
        }
        return Token(owner: self, index: index)
    }
    func tick() async {
        for action in liveActions() { await action() }
    }
    var liveCount: Int { liveActions().count }
    private func liveActions() -> [@Sendable () async -> Void] {
        lock.withLock { entries.filter { !$0.cancelled }.map(\.action) }
    }
    fileprivate func cancel(_ index: Int) { lock.withLock { entries[index].cancelled = true } }
    private final class Token: SchedulerRegistration, @unchecked Sendable {
        weak var owner: ManualScheduler?
        let index: Int
        init(owner: ManualScheduler, index: Int) { self.owner = owner; self.index = index }
        func cancel() { owner?.cancel(index) }
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

/// Counts calls to a central factory and keeps only a weak reference to what it built.
final class CentralFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private weak var last: FakeCentral?
    let consumerEnded = Flag()
    func make() -> any BluetoothCentral {
        let central = FakeCentral()
        central.onConsumerEnded(consumerEnded)
        lock.withLock { calls += 1; last = central }
        return central
    }
    var callCount: Int { lock.withLock { calls } }
    var built: FakeCentral? { lock.withLock { last } }
}

/// Polls until `predicate` holds and records an issue if it never does, so a wait that
/// does not settle fails the test instead of passing silently.
func eventually(_ sourceLocation: SourceLocation = #_sourceLocation,
                _ predicate: @escaping () async -> Bool) async {
    for _ in 0..<1000 {
        if await predicate() { return }
        await Task.yield()
    }
    Issue.record("Condition did not settle", sourceLocation: sourceLocation)
}
