import Foundation
import Observation
import SafetyCore
@_spi(DriverPlatform) import DriverAPI

public enum DriverHostError: Error, Sendable {
    case activation(DriverFailure)
    case lifecycle(DriverFailure)
    case glucosePortUnavailable
    case insulinPortUnavailable

    public var recoverer: String { "Restart the app to try connecting again." }
}

public struct ActiveDriverPorts: Sendable {
    public let identifier: DriverIdentifier
    public let glucoseSource: any GlucoseSource
    public let insulinSource: any InsulinSource
    public let pumpStatusSource: (any PumpStatusSource)?
}

@MainActor @Observable
public final class HomeModel {
    /// The pause between a pump-status read and the glucose read that follows
    /// it. It paces sequential pump requests the way Android's
    /// `REQUEST_STAGGER_MS` does, so one refresh never sends the pump two
    /// requests back to back. It is request pacing, not a clinical bound, and
    /// it applies only when both reads run.
    public static let pumpReadGap: TimeInterval = 0.5
    public let isDemo: Bool
    public private(set) var lifecycleState = DriverLifecycleState.notActivated
    public private(set) var ports: ActiveDriverPorts?
    public private(set) var hostError: DriverHostError?
    public private(set) var latestGlucose: GlucoseSample?
    public private(set) var latestIOB: InsulinOnBoardSample?
    public private(set) var latestPumpStatus: PumpStatusSnapshot?
    /// True while a read sequence for the CURRENT activation is in flight. A
    /// sequence started by an earlier activation may still be suspended inside
    /// a slow Driver read after `stop()`, but it can no longer write anything,
    /// so it must not block the next activation's reads.
    public var isRefreshing: Bool { refreshGeneration == activationGeneration }
    public private(set) var heroState: HeroState
    public let backend: BackendConfiguration
    public var statusRow: StatusRowState {
        // No hosted Driver currently reports pump-link state, so never infer it from activation.
        StatusRowState.make(connection: .disconnected, backend: backend, activeDrivers: [driver.descriptor.identifier])
    }
    public var glucoseUnit: GlucoseUnit = .mgdl {
        didSet { refreshHero() }
    }

    private var lifecycle = DriverLifecycle()
    private let driver: any Driver
    private let clock: any Clock
    private let scheduler: any Scheduler
    private let log: any HomeLogging
    private let readGap: @Sendable (TimeInterval) async -> Void
    private var foregroundReadSatisfied = false
    // Counts inactive transitions so a read that was in flight while the scene
    // went inactive cannot mark the next foreground as already read.
    private var inactiveTransitions = 0
    private var pendingReactivation = false
    private var wantsActive = false
    private var activationGeneration = 0
    private var refreshGeneration: Int?
    // These handles are mutated on the main actor and only read outside it during deinit.
    @ObservationIgnored nonisolated(unsafe) private var tickRegistration: SchedulerRegistration?
    @ObservationIgnored nonisolated(unsafe) private var streamTasks: [Task<Void, Never>] = []

    deinit {
        tickRegistration?.cancel()
        for task in streamTasks { task.cancel() }
    }

    public init(driver: any Driver, demoIdentifiers: Set<DriverIdentifier>, backend: BackendConfiguration = .notConfigured, clock: any Clock = SystemClock(), scheduler: any Scheduler = WallClockScheduler(), log: any HomeLogging = OSHomeLog(), readGap: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.driver = driver
        self.backend = backend
        self.clock = clock
        self.scheduler = scheduler
        self.log = log
        self.readGap = readGap
        self.isDemo = DemoDataLabel.isVisible(
            activeGlucoseDriver: driver.descriptor.identifier,
            demoIdentifiers: demoIdentifiers
        )
        self.heroState = HeroState.make(sample: nil, trendSourceTimestamp: nil, iob: nil, pumpStatus: nil,
                                        targetRange: .default, unit: .mgdl, now: clock.now, isDemo: isDemo)
    }

    public var footerMessage: String? {
        HomeScaffoldModel.footer(isConnected: HomeScaffoldModel.isConnected(lifecycleState), hasGlucose: latestGlucose != nil)
    }

    /// Records whether the scene is active and moves the Driver toward that
    /// state. Call it synchronously from the scene-phase handler.
    ///
    /// Two quick scene changes start two unstructured tasks, and Swift does
    /// not promise which one runs first. Each task therefore acts on the
    /// LATEST recorded phase when it runs, not the phase that spawned it, so
    /// whichever runs last converges on the current phase. Transitions that
    /// overlap mid-flight are handled by `pendingReactivation` and the
    /// activation generation, as they are for direct calls.
    @discardableResult
    public func setScenePhaseActive(_ active: Bool) -> Task<Void, Never> {
        wantsActive = active
        return Task { [weak self] in
            guard let self else { return }
            if !self.wantsActive { await self.stop(); return }
            switch self.lifecycleState {
            case .notActivated, .deactivating: await self.activateIfNeeded()
            case .activating: break
            case .active:
                if self.foregroundReadSatisfied { self.foregroundReadSatisfied = false }
                else { await self.refresh() }
            case .failed, .degraded: break
            }
        }
    }

    public func sceneBecameInactive() {
        inactiveTransitions &+= 1
        foregroundReadSatisfied = false
    }

    public func activateIfNeeded() async {
        startTickerIfNeeded()
        refreshHero()
        if lifecycleState == .deactivating {
            pendingReactivation = true
            return
        }
        guard lifecycleState == .notActivated, hostError == nil else { return }
        do {
            try lifecycle.advance(to: .activating)
            lifecycleState = lifecycle.state
        } catch {
            hostError = .lifecycle(error)
            return
        }
        let generation = activationGeneration

        do {
            try await driver.activate()
        } catch {
            guard generation == activationGeneration else { return }
            await fail(.activation(error))
            return
        }
        guard generation == activationGeneration else { return }
        do {
            try lifecycle.advance(to: .active)
            lifecycleState = lifecycle.state
        } catch {
            await fail(.lifecycle(error))
            return
        }

        let glucosePort = await driver.capability(.glucoseSource)
        guard generation == activationGeneration else { return }
        guard case .glucoseSource(let glucose)? = glucosePort else {
            await fail(.glucosePortUnavailable)
            return
        }
        let insulinPort = await driver.capability(.insulinSource)
        guard generation == activationGeneration else { return }
        guard case .insulinSource(let insulin)? = insulinPort else {
            await fail(.insulinPortUnavailable)
            return
        }
        let pump: (any PumpStatusSource)?
        let pumpPort = await driver.capability(.pumpStatus)
        guard generation == activationGeneration else { return }
        if case .pumpStatus(let source)? = pumpPort { pump = source }
        else { pump = nil }
        let activePorts = ActiveDriverPorts(identifier: driver.descriptor.identifier, glucoseSource: glucose,
                                            insulinSource: insulin, pumpStatusSource: pump)
        ports = activePorts
        if !isRefreshing {
            let inactiveTransitionsBeforeRead = inactiveTransitions
            await runReadSequence(ports: activePorts, generation: generation)
            guard generation == activationGeneration else { return }
            if !Task.isCancelled, inactiveTransitions == inactiveTransitionsBeforeRead { foregroundReadSatisfied = true }
        }
        streamTasks.append(Task { [weak self] in
            for await sample in glucose.readings { self?.receive(sample) }
        })
        streamTasks.append(Task { [weak self] in
            for await sample in insulin.insulinOnBoard { self?.receive(sample) }
        })
        if let pump {
            streamTasks.append(Task { [weak self] in
                for await status in pump.status { self?.receive(status) }
            })
        }
    }

    public func refresh() async {
        guard !isRefreshing, lifecycleState == .active, let ports else { return }
        await runReadSequence(ports: ports, generation: activationGeneration)
    }

    private func runReadSequence(ports: ActiveDriverPorts, generation: Int) async {
        refreshGeneration = generation
        defer { if refreshGeneration == generation { refreshGeneration = nil } }
        await readSequence(ports: ports, generation: generation)
    }

    private func readSequence(ports: ActiveDriverPorts, generation: Int) async {
        if let pump = ports.pumpStatusSource {
            do {
                if let status = try await pump.latestStatus(), generation == activationGeneration { receive(status) }
            } catch { log.refreshReadFailed(step: .pumpStatus, failure: error) }
            guard generation == activationGeneration, !Task.isCancelled else { return }
            await readGap(Self.pumpReadGap)
            guard generation == activationGeneration, !Task.isCancelled else { return }
        }
        do {
            if let sample = try await ports.glucoseSource.latestReading(), generation == activationGeneration { receive(sample) }
        } catch { log.refreshReadFailed(step: .glucose, failure: error) }
        guard generation == activationGeneration, !Task.isCancelled else { return }
        refreshHero()
    }

    public var tickInterval: TimeInterval {
        FreshnessMonitor.tickInterval(staleAfter: FreshnessPolicy.cgm.staleAfter)
    }

    private func startTickerIfNeeded() {
        guard tickRegistration == nil else { return }
        tickRegistration = scheduler.scheduleRepeating(interval: tickInterval) { [weak self] in
            await self?.refreshHero()
        }
    }

    public func stop() async {
        activationGeneration &+= 1
        refreshGeneration = nil
        foregroundReadSatisfied = false
        pendingReactivation = false
        tickRegistration?.cancel()
        tickRegistration = nil
        for task in streamTasks { task.cancel() }
        streamTasks.removeAll()

        guard lifecycleState == .activating || lifecycleState == .active || lifecycleState == .degraded else { return }
        do {
            try lifecycle.advance(to: .deactivating)
            lifecycleState = lifecycle.state
            await driver.deactivate()
            try lifecycle.advance(to: .notActivated)
            lifecycleState = lifecycle.state
            ports = nil
            if pendingReactivation {
                pendingReactivation = false
                await activateIfNeeded()
            }
        } catch {
            hostError = .lifecycle(error)
        }
    }

    /// A timestamp further in the future than the alert floor's skew
    /// tolerance is a clock fault, not a reading. Holding one would block
    /// every later valid sample behind the ordering guard and show a
    /// negative age as Fresh, so it is dropped at ingest.
    private func isTooFarInFuture(_ timestamp: Date) -> Bool {
        timestamp.timeIntervalSince(clock.now) > SafetyConstants.alertFloorMaxFutureSkew
    }

    private func receive(_ sample: GlucoseSample) {
        guard !isTooFarInFuture(sample.recordedAt) else { return }
        guard latestGlucose.map({ sample.recordedAt >= $0.recordedAt }) ?? true else { return }
        latestGlucose = sample
        refreshHero()
    }

    private func receive(_ sample: InsulinOnBoardSample) {
        guard !isTooFarInFuture(sample.calculatedAt) else { return }
        guard latestIOB.map({ sample.calculatedAt >= $0.calculatedAt }) ?? true else { return }
        latestIOB = sample
        refreshHero()
    }

    private func receive(_ status: PumpStatusSnapshot) {
        guard !isTooFarInFuture(status.observedAt) else { return }
        guard latestPumpStatus.map({ status.observedAt >= $0.observedAt }) ?? true else { return }
        latestPumpStatus = status
        refreshHero()
    }

    private func refreshHero() {
        heroState = HeroState.make(sample: latestGlucose, trendSourceTimestamp: latestGlucose?.recordedAt,
                                   iob: latestIOB, pumpStatus: latestPumpStatus, targetRange: .default,
                                   unit: glucoseUnit, now: clock.now, isDemo: isDemo)
    }

    private func fail(_ error: DriverHostError) async {
        await driver.deactivate()
        do {
            try lifecycle.advance(to: .failed)
            lifecycleState = lifecycle.state
        } catch {
            // Keep the original activation or capability failure for recovery.
        }
        hostError = error
    }
}

public enum AppComposition {
    public static func makeSafetyValidator() -> SafetyLimitsValidator {
        do {
            let limits = try SafetyLimits(
                glucoseLower: SafetyConstants.glucoseValidRange.lowerBound,
                glucoseUpper: SafetyConstants.glucoseValidRange.upperBound
            )
            return SafetyLimitsValidator(limits: limits)
        } catch {
            preconditionFailure("Canonical glucose limits must be valid: \(error)")
        }
    }
}
