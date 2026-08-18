import Foundation
import DriverAPI
import SafetyCore

/// The Simulated Driver: realistic, deterministic glucose and insulin data
/// with no Bluetooth and no network, so every surface above the driver
/// boundary is buildable and demonstrable without a device (FR-35).
///
/// ## What it provides, and why not more
///
/// Two of the six capabilities: ``Capability/glucoseSource`` and
/// ``Capability/insulinSource``. The other four all presuppose a real
/// device — hardware state, fingerstick meters, a device's own dose-category
/// vocabulary, a sync destination's connection state — and inventing one
/// would be simulating a specific pump, not a driver. Glucose and insulin on
/// board are the two surfaces every later story needs data for, and both can
/// be honestly produced from a model instead of a device.
///
/// ## Where the data comes from
///
/// See ``SimulatedGenerator`` for the trace itself. This type is the
/// `DriverAPI` plumbing around it: every glucose value is validated through
/// the `SafetyLimitsValidator` the platform hands it, every timestamp
/// is stamped from the injected ``Clock``, and emission is driven by
/// the injected ``Scheduler`` — never a `Task.sleep` loop of its own, so a
/// test can drive it tick by tick.
public actor SimulatedDriver: Driver {

    public static let identifier = DriverIdentifier("com.glycemicgpt.simulated")!

    /// Fixed, so a caller that does not care about reproducing a specific
    /// trace still gets one that is reproducible.
    public static let defaultSeed: UInt64 = 0x5349_4D55_4C41_5445

    /// Five minutes — a typical CGM cadence, comfortably inside the Fresh
    /// window (``SafetyConstants/cgmStaleAfter``).
    public static let defaultTickInterval: TimeInterval = 300

    /// One simulated day of samples at the default cadence. Bounds what each
    /// capability stream buffers for a consumer that has not started (or has
    /// stopped) iterating, so an unconsumed port never accumulates an
    /// unbounded backlog; a consumer that falls further behind than this sees
    /// the newest day of samples.
    private static let streamBufferLimit = 288

    /// How far back `doses(since:)` can reach: 24 hours, in seconds. Records
    /// older than this are pruned each tick, so a long-running session holds
    /// a bounded window of dose history rather than an ever-growing array.
    private static let doseRetentionWindow: TimeInterval = 86_400

    public nonisolated let descriptor = DriverDescriptor(
        identifier: SimulatedDriver.identifier,
        targetName: "SimulatedDriver",
        displayName: "Simulated Driver",
        transport: .inProcess,
        version: "1.0.0",
        capabilities: [.glucoseSource, .insulinSource],
        verification: .unverified
    )

    private let clock: any Clock
    private let scheduler: any Scheduler
    private let validator: SafetyLimitsValidator
    private let tickInterval: TimeInterval

    private var generator: SimulatedGenerator
    private var isActive = false

    private var latestGlucose: GlucoseSample?
    private var completedDoses: [DoseRecord] = []

    /// The most recent tick's failure on each capability's construction
    /// path, if any — cleared on the next tick that succeeds, and on
    /// `activate()`, so a recovered Driver does not keep reporting the fault
    /// from the run that failed. Surfaced
    /// through the throwing capability-port members rather than swallowed
    /// (AD-13): a Driver cannot self-transition its lifecycle (that surface
    /// is platform-only SPI, unreachable and unimportable from here, per
    /// `driver_guards.sh`), so the throwing reads on `GlucoseSource` and
    /// `InsulinSource` are the designated channel for a runtime fault.
    private var glucoseFailure: DriverFailure?
    private var insulinFailure: DriverFailure?

    /// Holds the tick registration outside of this actor's isolation, so
    /// `deinit` — nonisolated, and unable to `await` the actor — can cancel it
    /// synchronously. The same shape `FreshnessMonitor.RegistrationBox` uses,
    /// for the same reason.
    private let registrationBox = RegistrationBox()

    private nonisolated let glucoseStream: AsyncStream<GlucoseSample>
    private let glucoseContinuation: AsyncStream<GlucoseSample>.Continuation
    private nonisolated let insulinOnBoardStream: AsyncStream<InsulinOnBoardSample>
    private let insulinOnBoardContinuation: AsyncStream<InsulinOnBoardSample>.Continuation

    /// - Parameter tickInterval: The wall-clock spacing between emissions.
    ///   ``SimulatedGenerator``'s model step is nominally five simulated
    ///   minutes per tick regardless of this value, so an interval other than
    ///   ``defaultTickInterval`` replays the same trace compressed or dilated
    ///   in stamped time: at `tickInterval: 120`, the hourly basal segment
    ///   lands every 24 stamped minutes, and per-minute figures documented on
    ///   ``SimulatedGenerator/maxStepDelta`` hold only at the default. Tests
    ///   use short intervals for exactly that fast-forward effect; trend
    ///   classification accounts for the injected interval, see
    ///   ``trend(forDelta:)``.
    public init(
        clock: some Clock,
        scheduler: some Scheduler,
        validator: SafetyLimitsValidator,
        seed: UInt64 = SimulatedDriver.defaultSeed,
        tickInterval: TimeInterval = SimulatedDriver.defaultTickInterval
    ) {
        self.clock = clock
        self.scheduler = scheduler
        self.validator = validator
        self.tickInterval = tickInterval
        self.generator = SimulatedGenerator(seed: seed)

        let glucoseMake = AsyncStream<GlucoseSample>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.streamBufferLimit)
        )
        self.glucoseStream = glucoseMake.stream
        self.glucoseContinuation = glucoseMake.continuation

        let insulinMake = AsyncStream<InsulinOnBoardSample>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.streamBufferLimit)
        )
        self.insulinOnBoardStream = insulinMake.stream
        self.insulinOnBoardContinuation = insulinMake.continuation
    }

    deinit {
        registrationBox.cancel()
    }

    public nonisolated func capability(_ capability: Capability) -> CapabilityPort? {
        switch capability {
        case .glucoseSource:
            return .glucoseSource(SimulatedGlucoseSourcePort(readings: glucoseStream, driver: self))
        case .insulinSource:
            return .insulinSource(SimulatedInsulinSourcePort(insulinOnBoard: insulinOnBoardStream, driver: self))
        case .pumpStatus, .bgmSource, .dataSync, .doseCategoryProvider:
            return nil
        }
    }

    /// Registers a fresh tick, cancelling whatever registration is already
    /// live. Necessary because ``DriverLifecycleState/active`` permits a
    /// direct move to ``DriverLifecycleState/failed`` without passing through
    /// ``DriverLifecycleState/deactivating`` first, so `activate()` can be
    /// called again — `failed` → `activating` — while the PRIOR registration
    /// from the run that failed is still live. `registrationBox.set` cancels
    /// that prior registration itself, so this never stacks two live
    /// tick sources and never double-emits.
    public func activate() async throws(DriverFailure) {
        isActive = true
        // A re-activation starts a fresh run: a failure recorded by the run
        // that failed describes ticks that run took, not this one, so a
        // recovered Driver must not keep throwing it until its first new tick.
        glucoseFailure = nil
        insulinFailure = nil
        let registration = scheduler.scheduleRepeating(interval: tickInterval) { [weak self] in
            await self?.emitNextTick()
        }
        registrationBox.set(registration)
    }

    public func deactivate() async {
        isActive = false
        registrationBox.cancel()
    }

    // MARK: - Reads the capability ports call back into

    func currentGlucose() throws(DriverFailure) -> GlucoseSample? {
        if let glucoseFailure { throw glucoseFailure }
        return latestGlucose
    }

    func doses(since: Date) throws(DriverFailure) -> [DoseRecord] {
        if let insulinFailure { throw insulinFailure }
        return completedDoses.filter { $0.completedAt >= since }
    }

    // MARK: - Emission

    /// One scheduler tick: advance the model, validate, stamp, emit. Never
    /// called by this type directly — only via the registration `activate()`
    /// sets up, so this is the one place emission happens.
    private func emitNextTick() async {
        guard isActive else { return }
        let tick = generator.advance()
        let now = clock.now

        do {
            let glucose = try validator.validate(mgdl: tick.glucoseMgdl)
            let sample = GlucoseSample(glucose: glucose, recordedAt: now, trend: trend(forDelta: tick.glucoseDeltaMgdl))
            latestGlucose = sample
            glucoseFailure = nil
            glucoseContinuation.yield(sample)
        } catch {
            glucoseFailure = error
        }

        do {
            let sample = try InsulinOnBoardSample(units: tick.insulinOnBoardUnits, calculatedAt: now)
            insulinFailure = nil
            insulinOnBoardContinuation.yield(sample)
        } catch {
            insulinFailure = error
        }

        for completedDose in tick.completedDoses {
            do {
                let dose = try DoseRecord(
                    units: completedDose.units,
                    completedAt: now,
                    category: completedDose.category,
                    deviceCategoryLabel: completedDose.deviceLabel
                )
                completedDoses.append(dose)
            } catch {
                insulinFailure = error
            }
        }

        // Bounded retention: `doses(since:)` filters on read, so without this
        // no record would ever be dropped and a long-running session would
        // grow the array for its whole lifetime.
        let retentionCutoff = now.addingTimeInterval(-Self.doseRetentionWindow)
        completedDoses.removeAll { $0.completedAt < retentionCutoff }
    }

    /// Maps one tick's glucose change onto the trend vocabulary.
    ///
    /// The delta the generator reports covers ONE tick, and the stamped
    /// spacing of samples is `tickInterval`, so the delta is first normalized
    /// to the change over one DEFAULT five-minute tick; the classification is
    /// then a rate, stable under a shorter injected interval that
    /// fast-forwards the trace. The bands are the conventional CGM arrow
    /// bands of 0.5, 1.5 and 3 mg/dL per minute, scaled to five minutes.
    /// Classifying the raw per-tick delta against per-minute bands would
    /// exaggerate every arrow: noise-level movement of 2 mg/dL per
    /// five-minute tick (0.4 mg/dL per minute) would read as a fast rise
    /// or fall.
    private func trend(forDelta delta: Double) -> GlucoseTrend {
        let deltaPerDefaultTick = delta * (Self.defaultTickInterval / tickInterval)
        switch deltaPerDefaultTick {
        case ..<(-15): return .fallingQuickly
        case ..<(-7.5): return .falling
        case ..<(-2.5): return .fallingSlowly
        case ...2.5: return .steady
        case ...7.5: return .risingSlowly
        case ...15: return .rising
        default: return .risingQuickly
        }
    }
}

private final class RegistrationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var registration: SchedulerRegistration?

    /// Replaces whatever registration is held, cancelling the prior one
    /// first — so a second `activate()` on the same box (``failed`` →
    /// ``activating`` never passes through `deactivate()`) never leaves two
    /// live tick sources registered at once.
    func set(_ registration: SchedulerRegistration?) {
        lock.lock()
        let previous = self.registration
        self.registration = registration
        lock.unlock()
        previous?.cancel()
    }

    func cancel() {
        lock.lock()
        let registration = registration
        self.registration = nil
        lock.unlock()
        registration?.cancel()
    }
}
