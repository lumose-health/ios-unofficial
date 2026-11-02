import Foundation
import Observation
import SafetyCore
import DomainCore
@_spi(DriverPlatform) import DriverAPI

public enum HomeSource: Sendable, Equatable {
    case pending
    case connected(DriverIdentifier)
    case noActiveDriver
    case startFailed(DriverIdentifier, DriverFailure)
    /// The first-launch default could not be activated.
    case seedFailed(DriverIdentifier, DriverRegistryError)
    case deferred(DriverIdentifier, DriverFailure)
    /// The saved selection could not be read yet (for example before first
    /// unlock). It is still on disk, and restore runs again on the next foreground.
    case selectionDeferred(DriverSelectionStoreFailure)
    case unavailable(CapabilityReadError)
}

public struct HomeSourceMessage: Sendable, Equatable {
    public let title: String
    public let body: String
    public let identifier: String

    public init(title: String, body: String, identifier: String) {
        self.title = title
        self.body = body
        self.identifier = identifier
    }

    /// `hasCachedGlucose` keeps a reconnect from hiding a reading that is
    /// already on screen: "Starting…" appears only when nothing is cached.
    public static func make(source: HomeSource, hasCachedGlucose: Bool = false,
                            displayName: (DriverIdentifier) -> String?) -> Self? {
        switch source {
        case .connected: return nil
        case .pending:
            if hasCachedGlucose { return nil }
            return Self(title: "Starting…",
                        body: "Connecting to your data source.",
                        identifier: "home.starting")
        // A glucose read never yields the remaining errors, but if one did, nothing
        // is providing glucose; say so rather than fall through to the dashboard.
        case .noActiveDriver, .unavailable(.noActiveDriver), .unavailable(.notSingleInstance),
             .unavailable(.cancelled):
            return Self(title: "No glucose source",
                        body: "No active Driver is providing glucose readings, so there is nothing to show here.",
                        identifier: "home.no-glucose-source")
        case .startFailed(let id, _), .seedFailed(let id, _), .unavailable(.holderNotRunning(let id, _, _)):
            return Self(title: "Unable to start data source",
                        body: "\(displayName(id) ?? id.rawValue) didn't start. Restart the app to try again.",
                        identifier: "home.source-failed")
        case .deferred(let id, _):
            return Self(title: "Data source not running",
                        body: "\(displayName(id) ?? id.rawValue) isn't running. It will retry when the app starts again.",
                        identifier: "home.source-deferred")
        case .selectionDeferred:
            return Self(title: "Data source not running",
                        body: "Your data source isn't running yet. It will retry when you return to the app.",
                        identifier: "home.source-deferred")
        case .unavailable(.portUnavailable(let id, _)):
            return Self(title: "Unable to start data source",
                        body: "\(displayName(id) ?? id.rawValue) isn't providing glucose readings. Restart the app to try again.",
                        identifier: "home.source-failed")
        }
    }
}

public struct ActiveDriverPorts: Sendable {
    public let identifier: DriverIdentifier
    public let glucoseSource: any GlucoseSource
    public let insulinSource: (any InsulinSource)?
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
    public private(set) var isDemo: Bool
    public private(set) var source: HomeSource = .pending
    public private(set) var slotErrors: [CapabilityReadError] = []
    public private(set) var lifecycleState = DriverLifecycleState.notActivated
    public private(set) var ports: ActiveDriverPorts?
    public private(set) var latestGlucose: GlucoseSample?
    public private(set) var latestIOB: InsulinOnBoardSample?
    public private(set) var latestPumpStatus: PumpStatusSnapshot?
    /// A read from an earlier connection cannot block or update the current one.
    public var isRefreshing: Bool { refreshGeneration == connectionGeneration }
    public private(set) var heroState: HeroState
    public let backend: BackendConfiguration
    public var statusRow: StatusRowState {
        // No hosted Driver currently reports pump-link state, so never infer it from activation.
        let active: [DriverIdentifier] = if case .connected(let id) = source { [id] } else { [] }
        return StatusRowState.make(connection: .disconnected, backend: backend, activeDrivers: active)
    }
    public var glucoseUnit: GlucoseUnit = .mgdl {
        didSet { refreshHero() }
    }

    private let registry: DriverRegistry
    private let awaitStartup: @Sendable () async -> DriverStartupOutcome
    private let demoIdentifiers: Set<DriverIdentifier>
    private let clock: any Clock
    private let scheduler: any Scheduler
    private let log: any HomeLogging
    private let readGap: @Sendable (TimeInterval) async -> Void
    private var foregroundReadSatisfied = false
    // Counts inactive transitions so a read that was in flight while the scene
    // went inactive cannot mark the next foreground as already read.
    private var inactiveTransitions = 0
    private var wantsActive = false
    private var connecting = false
    private var connectionGeneration = 0
    private var refreshGeneration: Int?
    private var startupOutcome: DriverStartupOutcome?
    // Set when a connection is dropped while `connect()` is running, so that
    // call connects again instead of a second one racing it.
    private var reconnectAfterConnect = false
    // The Driver whose values are cached. A different holder never inherits them.
    private var cacheHolder: DriverIdentifier?
    // These handles are mutated on the main actor and only read outside it during deinit.
    @ObservationIgnored nonisolated(unsafe) private var tickRegistration: SchedulerRegistration?
    @ObservationIgnored nonisolated(unsafe) private var streamTasks: [Task<Void, Never>] = []
    @ObservationIgnored nonisolated(unsafe) private var registryObserver: Task<Void, Never>?

    deinit {
        tickRegistration?.cancel()
        registryObserver?.cancel()
        for task in streamTasks { task.cancel() }
    }

    public init(registry: DriverRegistry, awaitStartup: @escaping @Sendable () async -> DriverStartupOutcome,
                demoIdentifiers: Set<DriverIdentifier>, backend: BackendConfiguration = .notConfigured,
                clock: any Clock = SystemClock(), scheduler: any Scheduler = WallClockScheduler(),
                log: any HomeLogging = OSHomeLog(),
                readGap: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.registry = registry
        self.awaitStartup = awaitStartup
        self.demoIdentifiers = demoIdentifiers
        self.backend = backend
        self.clock = clock
        self.scheduler = scheduler
        self.log = log
        self.readGap = readGap
        let isDemo = DemoDataLabel.isVisible(
            activeGlucoseDriver: registry.initialSlots.holder(of: .glucoseSource),
            demoIdentifiers: demoIdentifiers
        )
        self.isDemo = isDemo
        self.heroState = HeroState.make(sample: nil, trendSourceTimestamp: nil, iob: nil, pumpStatus: nil,
                                        targetRange: .default, unit: .mgdl, now: clock.now, isDemo: isDemo)
        // A Driver torn down by the registry may never finish its streams, so
        // the connection is also checked against the registry on every change.
        registryObserver = Task { [weak self, registry] in
            for await _ in await registry.changes() {
                guard let self else { return }
                await self.validateConnection()
            }
        }
    }

    /// What Home shows in place of the dashboard, or nil to show the dashboard.
    public var sourceMessage: HomeSourceMessage? {
        HomeSourceMessage.make(source: source, hasCachedGlucose: latestGlucose != nil, displayName: displayName(of:))
    }

    public var footerMessage: String? {
        HomeScaffoldModel.footer(isConnected: HomeScaffoldModel.isConnected(lifecycleState), hasGlucose: latestGlucose != nil)
    }

    public func displayName(of id: DriverIdentifier) -> String? {
        registry.descriptors.first(where: { $0.identifier == id })?.displayName
    }

    /// Records the latest scene phase before dispatching any asynchronous work.
    @discardableResult
    public func setScenePhaseActive(_ active: Bool) -> Task<Void, Never> {
        wantsActive = active
        return Task { [weak self] in
            guard let self else { return }
            if !self.wantsActive {
                self.tickRegistration?.cancel()
                self.tickRegistration = nil
                self.foregroundReadSatisfied = false
                return
            }
            self.startTickerIfNeeded()
            if case .connected = self.source {
                if self.foregroundReadSatisfied { self.foregroundReadSatisfied = false }
                else { await self.refresh() }
            } else { await self.connect() }
        }
    }

    public func sceneBecameInactive() {
        inactiveTransitions &+= 1
        foregroundReadSatisfied = false
    }

    private func connect() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        repeat {
            reconnectAfterConnect = false
            await connectOnce()
        } while reconnectAfterConnect && wantsActive
    }

    private func loadStartupOutcome() async -> DriverStartupOutcome {
        guard let previous = startupOutcome else { return await awaitStartup() }
        guard previous.report.selectionFailure?.isTransient == true else { return previous }
        return await DriverStartup.retryRestore(registry: registry)
    }

    private func connectOnce() async {
        startTickerIfNeeded()
        refreshHero()
        let generation = connectionGeneration
        let outcome = await loadStartupOutcome()
        guard generation == connectionGeneration else { return }
        startupOutcome = outcome
        let glucoseHeld: HeldPort
        do { glucoseHeld = try await registry.port(for: .glucoseSource) }
        catch {
            guard generation == connectionGeneration else { return }
            if error == .cancelled { return }
            if error == .noActiveDriver(.glucoseSource) {
                if let failure = outcome.report.selectionFailure, failure.isTransient {
                    source = .selectionDeferred(failure)
                } else if let failed = glucoseFailure(in: outcome.report.failed) {
                    source = .startFailed(failed.id, failed.failure)
                } else if let deferred = glucoseFailure(in: outcome.report.deferred) {
                    source = .deferred(deferred.id, deferred.failure)
                } else if let seedError = outcome.seedError, let target = outcome.seedTarget {
                    source = .seedFailed(target, seedError)
                } else { source = .noActiveDriver }
            } else if case .holderNotRunning(let id, _, _) = error,
                      let deferred = outcome.report.deferred.first(where: { $0.id == id }) {
                source = .deferred(id, deferred.failure)
            } else { source = .unavailable(error) }
            ports = nil
            if case .holderNotRunning(_, _, let state) = error {
                lifecycleState = state
            } else {
                lifecycleState = .notActivated
            }
            isDemo = false
            refreshHero()
            return
        }
        guard case .glucoseSource(let glucose) = glucoseHeld.port else {
            source = .unavailable(.portUnavailable(glucoseHeld.holder, .glucoseSource))
            isDemo = false
            refreshHero()
            return
        }
        var errors: [CapabilityReadError] = []
        let insulin: (any InsulinSource)?
        do {
            let held = try await registry.port(for: .insulinSource)
            if case .insulinSource(let value) = held.port { insulin = value } else { insulin = nil }
        } catch {
            if error == .cancelled { return }
            if error != .noActiveDriver(.insulinSource) { errors.append(error) }
            insulin = nil
        }
        let pump: (any PumpStatusSource)?
        do {
            let held = try await registry.port(for: .pumpStatus)
            if case .pumpStatus(let value) = held.port { pump = value } else { pump = nil }
        } catch {
            if error == .cancelled { return }
            if error != .noActiveDriver(.pumpStatus) { errors.append(error) }
            pump = nil
        }
        guard generation == connectionGeneration else { return }
        if cacheHolder != glucoseHeld.holder {
            // Another Driver's values must not be shown as this one's, and its
            // timestamps must not gate this Driver's samples.
            cacheHolder = glucoseHeld.holder
            latestGlucose = nil
            latestIOB = nil
            latestPumpStatus = nil
        }
        let activePorts = ActiveDriverPorts(identifier: glucoseHeld.holder, glucoseSource: glucose,
                                            insulinSource: insulin, pumpStatusSource: pump)
        ports = activePorts
        slotErrors = errors
        lifecycleState = await registry.lifecycleState(of: glucoseHeld.holder) ?? .notActivated
        guard generation == connectionGeneration else { return }
        isDemo = DemoDataLabel.isVisible(activeGlucoseDriver: glucoseHeld.holder, demoIdentifiers: demoIdentifiers)
        refreshHero()
        if !isRefreshing {
            let inactiveTransitionsBeforeRead = inactiveTransitions
            await runReadSequence(ports: activePorts, generation: generation)
            guard generation == connectionGeneration else { return }
            if !Task.isCancelled, inactiveTransitions == inactiveTransitionsBeforeRead { foregroundReadSatisfied = true }
        }
        source = .connected(glucoseHeld.holder)
        streamTasks.append(Task { [weak self] in
            for await sample in glucose.readings {
                guard let self, self.connectionGeneration == generation else { return }
                self.receive(sample)
            }
            if !Task.isCancelled { self?.streamEnded(generation: generation) }
        })
        if let insulin {
            streamTasks.append(Task { [weak self] in
                for await sample in insulin.insulinOnBoard {
                    guard let self, self.connectionGeneration == generation else { return }
                    self.receive(sample)
                }
                if !Task.isCancelled { self?.streamEnded(generation: generation) }
            })
        }
        if let pump {
            streamTasks.append(Task { [weak self] in
                for await status in pump.status {
                    guard let self, self.connectionGeneration == generation else { return }
                    self.receive(status)
                }
                if !Task.isCancelled { self?.streamEnded(generation: generation) }
            })
        }
        // The registry may have torn the holder down before `ports` was set,
        // when no change could yet be matched against this connection.
        await validateConnection()
    }

    private func glucoseFailure(in failures: [RestoreFailure]) -> RestoreFailure? {
        failures.filter { failure in
            registry.descriptors.first(where: { $0.identifier == failure.id })?
                .capabilities.contains(.glucoseSource) == true
        }.min { $0.id.rawValue < $1.id.rawValue }
    }

    private func streamEnded(generation: Int) {
        guard generation == connectionGeneration else { return }
        dropConnection(keepCache: true)
    }

    /// Drops the connection when its glucose holder is no longer the running
    /// holder of the slot. A failed read on the same holder never gets here.
    private func validateConnection() async {
        guard let ports else { return }
        let generation = connectionGeneration
        let holder = await registry.slots.holder(of: .glucoseSource)
        let state = await registry.lifecycleState(of: ports.identifier)
        guard generation == connectionGeneration, self.ports != nil else { return }
        if holder == ports.identifier, state == .active || state == .degraded { return }
        dropConnection(keepCache: holder == ports.identifier)
    }

    /// With `keepCache`, the cached values stay on screen at their true age
    /// while Home reconnects to the same holder. A different holder never
    /// inherits them, so they are cleared before anything is shown.
    private func dropConnection(keepCache: Bool) {
        connectionGeneration &+= 1
        refreshGeneration = nil
        foregroundReadSatisfied = false
        for task in streamTasks { task.cancel() }
        streamTasks.removeAll()
        ports = nil
        lifecycleState = .notActivated
        if !keepCache {
            cacheHolder = nil
            latestGlucose = nil
            latestIOB = nil
            latestPumpStatus = nil
        }
        source = .pending
        refreshHero()
        guard wantsActive else { return }
        if connecting { reconnectAfterConnect = true }
        else { Task { [weak self] in await self?.connect() } }
    }

    public func refresh() async {
        guard !isRefreshing, lifecycleState == .active, let ports else { return }
        await runReadSequence(ports: ports, generation: connectionGeneration)
    }

    private func runReadSequence(ports: ActiveDriverPorts, generation: Int) async {
        refreshGeneration = generation
        defer { if refreshGeneration == generation { refreshGeneration = nil } }
        await readSequence(ports: ports, generation: generation)
    }

    private func readSequence(ports: ActiveDriverPorts, generation: Int) async {
        if let pump = ports.pumpStatusSource {
            do {
                if let status = try await pump.latestStatus(), generation == connectionGeneration { receive(status) }
            } catch { log.refreshReadFailed(step: .pumpStatus, failure: error) }
            guard generation == connectionGeneration, !Task.isCancelled else { return }
            await readGap(Self.pumpReadGap)
            guard generation == connectionGeneration, !Task.isCancelled else { return }
        }
        do {
            if let sample = try await ports.glucoseSource.latestReading(), generation == connectionGeneration { receive(sample) }
        } catch { log.refreshReadFailed(step: .glucose, failure: error) }
        guard generation == connectionGeneration, !Task.isCancelled else { return }
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

}

public enum AppComposition {
    public static var driverSelectionFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "DriverSelection/selection.json")
    }

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
