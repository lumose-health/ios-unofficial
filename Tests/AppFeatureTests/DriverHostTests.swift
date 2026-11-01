import Testing
import Foundation
import AppFeature
import SafetyCore
import DriverAPI
@_spi(DriverPlatform) import DriverAPI

@Suite("Driver host")
struct DriverHostTests {
    @Test @MainActor func demoFlagExistsBeforeActivationAndAfterSuccess() async {
        let driver = HostTestDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier])
        #expect(model.isDemo)
        #expect(model.lifecycleState == .notActivated)

        await model.activateIfNeeded()

        #expect(model.isDemo)
        #expect(model.lifecycleState == .active)
        #expect(model.ports?.identifier == driver.descriptor.identifier)
    }

    @Test @MainActor func demoFlagRemainsOnAfterActivationFailureAndLifecycleFails() async {
        let driver = HostTestDriver(activationFailure: .transportUnavailable)
        let model = HomeModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier])
        #expect(model.isDemo)

        await model.activateIfNeeded()

        #expect(model.isDemo)
        #expect(model.lifecycleState == .failed)
        guard case .activation(.transportUnavailable)? = model.hostError else {
            Issue.record("Expected the activation failure to retain its DriverFailure")
            return
        }
        #expect(await driver.didDeactivate)
    }

    @Test @MainActor func unavailableGlucosePortDeactivatesAndFails() async {
        let model = HomeModel(driver: HostTestDriver(missing: .glucoseSource), demoIdentifiers: [])
        await model.activateIfNeeded()
        #expect(model.lifecycleState == .failed)
        guard case .glucosePortUnavailable? = model.hostError else { Issue.record("Expected glucose port error"); return }
    }

    @Test @MainActor func unavailableInsulinPortDeactivatesAndFails() async {
        let model = HomeModel(driver: HostTestDriver(missing: .insulinSource), demoIdentifiers: [])
        await model.activateIfNeeded()
        #expect(model.lifecycleState == .failed)
        guard case .insulinPortUnavailable? = model.hostError else { Issue.record("Expected insulin port error"); return }
    }

    @Test @MainActor func repeatedActivationDoesNotReactivateHostedDriver() async {
        let driver = HostTestDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [])
        await model.activateIfNeeded()
        await model.activateIfNeeded()
        #expect(await driver.activationCount == 1)
    }

    @Test func canonicalSafetyValidatorCanBeConstructed() {
        let validator = AppComposition.makeSafetyValidator()
        #expect(validator.limitsInForce.glucoseRange == SafetyConstants.glucoseValidRange)
    }

    @Test @MainActor func heroDecaysOnInjectedTickWithoutNewSample() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = HostAdjustableClock(now: now)
        let scheduler = HostManualScheduler()
        let sample = GlucoseSample(glucose: try Glucose(mgdl: 120), recordedAt: now, trend: .rising)
        let driver = HostTestDriver(initialSample: sample)
        let model = HomeModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier], clock: clock, scheduler: scheduler)
        await model.activateIfNeeded()

        #expect(model.heroState.valueText == "120")
        #expect(model.heroState.valueColor == .green)
        #expect(model.heroState.glyph == "↑")
        #expect(model.heroState.accessibilityLabel.hasPrefix("DEMO DATA — not your glucose"))
        #expect(scheduler.interval == 30)

        clock.advance(by: 400)
        await scheduler.tick()
        #expect(model.heroState.badge == .stale)
        #expect(model.heroState.ageCaption == "6m ago")

        clock.advance(by: 600)
        await scheduler.tick()
        #expect(model.heroState.valueText == "120")
        #expect(model.heroState.valueColor == .secondary)
        #expect(model.heroState.glyphColor == .secondary)
        #expect(model.heroState.badge == .tooStale)
    }

    @Test @MainActor func stopCancelsTicksAndAllowsReactivation() async {
        let driver = HostTestDriver()
        let scheduler = HostManualScheduler()
        let model = HomeModel(driver: driver, demoIdentifiers: [], scheduler: scheduler)
        await model.activateIfNeeded()

        await model.stop()
        #expect(scheduler.isCancelled)
        #expect(model.lifecycleState == .notActivated)
        #expect(model.ports?.identifier == nil)
        #expect(await driver.didDeactivate)

        await model.activateIfNeeded()
        #expect(model.lifecycleState == .active)
        #expect(await driver.activationCount == 2)
        await model.stop()
    }

    @Test @MainActor func reactivationDuringStopKeepsTickerAndDecaysReading() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = HostAdjustableClock(now: now)
        let scheduler = HostManualScheduler()
        let gate = HostDeactivationGate()
        let sample = GlucoseSample(glucose: try Glucose(mgdl: 120), recordedAt: now, trend: .steady)
        let driver = HostTestDriver(initialSample: sample, deactivationGate: gate)
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: scheduler)
        await model.activateIfNeeded()

        let stopping = Task { await model.stop() }
        await gate.waitUntilEntered()
        await model.activateIfNeeded()
        #expect(!scheduler.isCancelled)
        clock.advance(by: 1000)
        await scheduler.tick()
        #expect(model.heroState.badge == .tooStale)
        await gate.release()
        await stopping.value
        #expect(model.lifecycleState == .active)
        #expect(await driver.activationCount == 2)
        #expect(!scheduler.isCancelled)
    }

    @Test @MainActor func stopDuringActivationDoesNotAttachLateStreams() async throws {
        let gate = HostDeactivationGate()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = GlucoseSample(glucose: try Glucose(mgdl: 120), recordedAt: now, trend: .steady)
        let driver = HostTestDriver(initialSample: sample, activationGate: gate)
        let model = HomeModel(driver: driver, demoIdentifiers: [])
        let activating = Task { await model.activateIfNeeded() }
        await gate.waitUntilEntered()
        #expect(model.lifecycleState == .activating)
        await model.stop()
        await gate.release()
        await activating.value
        #expect(model.lifecycleState == .notActivated)
        #expect(model.ports == nil)
        #expect(model.latestGlucose == nil)
        #expect(await driver.didDeactivate)
    }

    @Test @MainActor func secondBackgroundClearsPendingReactivation() async {
        let gate = HostDeactivationGate()
        let driver = HostTestDriver(deactivationGate: gate)
        let scheduler = HostManualScheduler()
        let model = HomeModel(driver: driver, demoIdentifiers: [], scheduler: scheduler)
        await model.activateIfNeeded()
        let stopping = Task { await model.stop() }
        await gate.waitUntilEntered()
        await model.activateIfNeeded()
        await model.stop()
        await gate.release()
        await stopping.value
        #expect(model.lifecycleState == .notActivated)
        #expect(await driver.activationCount == 1)
        #expect(scheduler.isCancelled)
    }

    @Test @MainActor func liveUpdatesResumeAfterStopAndReactivation() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = HostAdjustableClock(now: now)
        let driver = StreamingHostDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler())
        await model.activateIfNeeded()

        let first = GlucoseSample(glucose: try Glucose(mgdl: 110), recordedAt: now, trend: .steady)
        await driver.emit(first)
        #expect(await eventually { model.latestGlucose == first })

        await model.stop()
        await model.activateIfNeeded()

        clock.advance(by: 300)
        let second = GlucoseSample(glucose: try Glucose(mgdl: 140), recordedAt: clock.now, trend: .rising)
        await driver.emit(second)
        #expect(await eventually { model.latestGlucose == second }, "streams must deliver after reactivation")
        await model.stop()
    }

    @Test @MainActor func lateBackgroundRequestActsOnLatestScenePhase() async {
        let driver = StreamingHostDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value

        // Background then foreground in quick succession, with the tasks
        // completing in the opposite order to how they were requested.
        let background = model.setScenePhaseActive(false)
        let foreground = model.setScenePhaseActive(true)
        await foreground.value
        await background.value
        #expect(model.lifecycleState == .active)
        #expect(model.ports != nil)

        await model.setScenePhaseActive(false).value
        #expect(model.lifecycleState == .notActivated)
    }

    @Test @MainActor func foregroundDuringBackgroundTeardownReactivates() async {
        let gate = HostDeactivationGate()
        let driver = StreamingHostDriver(deactivationGate: gate)
        let model = HomeModel(driver: driver, demoIdentifiers: [], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value

        let background = model.setScenePhaseActive(false)
        await gate.waitUntilEntered()
        let foreground = model.setScenePhaseActive(true)
        await foreground.value
        await gate.release()
        await background.value
        #expect(model.lifecycleState == .active)
        #expect(await driver.activationCount == 2)
    }

    @Test @MainActor func futureDatedGlucoseBeyondSkewIsDroppedAndDoesNotBlockLaterSamples() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = HostAdjustableClock(now: now)
        let driver = StreamingHostDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler())
        await model.activateIfNeeded()

        let skew = SafetyConstants.alertFloorMaxFutureSkew
        let future = GlucoseSample(glucose: try Glucose(mgdl: 200), recordedAt: now.addingTimeInterval(skew + 3600), trend: .steady)
        await driver.emit(future)
        let valid = GlucoseSample(glucose: try Glucose(mgdl: 120), recordedAt: now, trend: .steady)
        await driver.emit(valid)
        #expect(await eventually { model.latestGlucose == valid })
        #expect(model.heroState.valueText == "120")

        let withinSkew = GlucoseSample(glucose: try Glucose(mgdl: 125), recordedAt: now.addingTimeInterval(skew), trend: .steady)
        await driver.emit(withinSkew)
        #expect(await eventually { model.latestGlucose == withinSkew }, "skew up to the tolerance is accepted")
        await model.stop()
    }

    @Test @MainActor func futureDatedIOBAndPumpStatusBeyondSkewAreDropped() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = HostAdjustableClock(now: now)
        let driver = StreamingHostDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler())
        await model.activateIfNeeded()

        let tooFar = now.addingTimeInterval(SafetyConstants.alertFloorMaxFutureSkew + 1)
        await driver.emit(try InsulinOnBoardSample(units: 9, calculatedAt: tooFar))
        await driver.emit(try InsulinOnBoardSample(units: 1.5, calculatedAt: now))
        #expect(await eventually { model.latestIOB?.calculatedAt == now })
        #expect(model.latestIOB?.units == 1.5)

        await driver.emit(try PumpStatusSnapshot(batteryFraction: 0.9, observedAt: tooFar))
        await driver.emit(try PumpStatusSnapshot(batteryFraction: 0.4, observedAt: now))
        #expect(await eventually { model.latestPumpStatus?.observedAt == now })
        #expect(model.latestPumpStatus?.batteryFraction == 0.4)
        await model.stop()
    }
}

private actor HostTestDriver: Driver {
    static let simulatedIdentifier = DriverIdentifier("com.glycemicgpt.simulated")!
    nonisolated let descriptor: DriverDescriptor
    private let glucose: HostGlucoseSource
    private let insulin = HostInsulinSource()
    private let activationFailure: DriverFailure?
    private let missing: Capability?
    private let deactivationGate: HostDeactivationGate?
    private let activationGate: HostDeactivationGate?
    private(set) var activationCount = 0
    private(set) var didDeactivate = false

    init(activationFailure: DriverFailure? = nil, missing: Capability? = nil, initialSample: GlucoseSample? = nil,
         deactivationGate: HostDeactivationGate? = nil, activationGate: HostDeactivationGate? = nil) {
        self.activationFailure = activationFailure
        self.missing = missing
        self.glucose = HostGlucoseSource(initialSample: initialSample)
        self.deactivationGate = deactivationGate
        self.activationGate = activationGate
        self.descriptor = DriverDescriptor(
            identifier: Self.simulatedIdentifier,
            targetName: "HostTestDriver",
            displayName: "Host test Driver",
            transport: .inProcess,
            version: "1.0.0",
            capabilities: [.glucoseSource, .insulinSource],
            verification: .unverified
        )
    }

    func capability(_ capability: Capability) -> CapabilityPort? {
        guard capability != missing else { return nil }
        return switch capability {
        case .glucoseSource: .glucoseSource(glucose)
        case .insulinSource: .insulinSource(insulin)
        case .pumpStatus, .bgmSource, .dataSync, .doseCategoryProvider: nil
        }
    }

    func activate() async throws(DriverFailure) {
        activationCount += 1
        await activationGate?.enter()
        if let activationFailure { throw activationFailure }
    }

    func deactivate() async {
        didDeactivate = true
        await deactivationGate?.enter()
    }
}

private actor HostDeactivationGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func enter() async {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private struct HostGlucoseSource: GlucoseSource {
    let initialSample: GlucoseSample?
    var readings: AsyncStream<GlucoseSample> { AsyncStream { $0.finish() } }
    func latestReading() async throws(DriverFailure) -> GlucoseSample? { initialSample }
}

private struct HostInsulinSource: InsulinSource {
    var insulinOnBoard: AsyncStream<InsulinOnBoardSample> { AsyncStream { $0.finish() } }
    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord] { [] }
}

private final class HostAdjustableClock: SafetyCore.Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(now: Date) { current = now }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(by interval: TimeInterval) {
        lock.lock(); current = current.addingTimeInterval(interval); lock.unlock()
    }
}

private final class HostManualScheduler: Scheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () async -> Void)?
    private var registeredInterval: TimeInterval?
    private var cancelled = false
    var interval: TimeInterval? { lock.lock(); defer { lock.unlock() }; return registeredInterval }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func scheduleRepeating(interval: TimeInterval, action: @escaping @Sendable () async -> Void) -> SchedulerRegistration {
        lock.lock(); registeredInterval = interval; self.action = action; cancelled = false; lock.unlock()
        return HostRegistration { [weak self] in self?.cancel() }
    }
    func tick() async {
        await currentAction()?()
    }
    private func currentAction() -> (@Sendable () async -> Void)? {
        lock.lock(); defer { lock.unlock() }; return action
    }
    private func cancel() {
        lock.lock(); cancelled = true; action = nil; lock.unlock()
    }
}

private struct HostRegistration: SchedulerRegistration {
    let onCancel: @Sendable () -> Void
    func cancel() { onCancel() }
}

@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

/// Follows the Capability stream contract: each activation feeds fresh
/// streams and teardown finishes them.
private actor StreamingHostDriver: Driver {
    nonisolated let descriptor = DriverDescriptor(
        identifier: DriverIdentifier("com.glycemicgpt.streaming-test")!,
        targetName: "StreamingHostDriver",
        displayName: "Streaming host test Driver",
        transport: .inProcess,
        version: "1.0.0",
        capabilities: [.glucoseSource, .insulinSource, .pumpStatus],
        verification: .unverified
    )
    private let deactivationGate: HostDeactivationGate?
    private(set) var activationCount = 0
    private var glucose = AsyncStream<GlucoseSample>.makeStream()
    private var insulin = AsyncStream<InsulinOnBoardSample>.makeStream()
    private var pump = AsyncStream<PumpStatusSnapshot>.makeStream()

    init(deactivationGate: HostDeactivationGate? = nil) {
        self.deactivationGate = deactivationGate
    }

    func capability(_ capability: Capability) -> CapabilityPort? {
        switch capability {
        case .glucoseSource: .glucoseSource(StreamGlucosePort(readings: glucose.stream))
        case .insulinSource: .insulinSource(StreamInsulinPort(insulinOnBoard: insulin.stream))
        case .pumpStatus: .pumpStatus(StreamPumpPort(status: pump.stream))
        case .bgmSource, .dataSync, .doseCategoryProvider: nil
        }
    }

    func activate() async throws(DriverFailure) {
        activationCount += 1
        glucose = AsyncStream.makeStream()
        insulin = AsyncStream.makeStream()
        pump = AsyncStream.makeStream()
    }

    func deactivate() async {
        glucose.continuation.finish()
        insulin.continuation.finish()
        pump.continuation.finish()
        await deactivationGate?.enter()
    }

    func emit(_ sample: GlucoseSample) { glucose.continuation.yield(sample) }
    func emit(_ sample: InsulinOnBoardSample) { insulin.continuation.yield(sample) }
    func emit(_ status: PumpStatusSnapshot) { pump.continuation.yield(status) }
}

private struct StreamGlucosePort: GlucoseSource {
    let readings: AsyncStream<GlucoseSample>
    func latestReading() async throws(DriverFailure) -> GlucoseSample? { nil }
}

private struct StreamInsulinPort: InsulinSource {
    let insulinOnBoard: AsyncStream<InsulinOnBoardSample>
    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord] { [] }
}

private struct StreamPumpPort: PumpStatusSource {
    let status: AsyncStream<PumpStatusSnapshot>
    func latestStatus() async throws(DriverFailure) -> PumpStatusSnapshot? { nil }
}
