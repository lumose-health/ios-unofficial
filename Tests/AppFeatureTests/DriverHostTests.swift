import Testing
import Foundation
import AppFeature
import SafetyCore
import DriverAPI
@_spi(DriverPlatform) import DriverAPI

@Suite("Driver host")
struct DriverHostTests {
    @Test @MainActor func statusRowDefaultsToDisconnectedWithoutBackend() {
        let model = HomeModel(driver: HostTestDriver(), demoIdentifiers: [])
        #expect(model.statusRow.pumpLink == PumpLinkIndicator.make(.disconnected))
        #expect(model.statusRow.sync == nil)
        #expect(model.statusRow.reachability == nil)
    }

    @Test @MainActor func configuredBackendAppearsInStatusRow() {
        let backend = BackendConfiguration.configured(.init(sync: .init(hasError: false, pendingCount: 0, lastSync: nil), reachability: .reachable))
        let model = HomeModel(driver: HostTestDriver(), demoIdentifiers: [], backend: backend)
        #expect(model.statusRow.sync != nil)
        #expect(model.statusRow.reachability?.accessibilityLabel == "Backend reachable")
    }

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

    @Test @MainActor func refreshAppliesNewReadingAndClearsFlag() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try glucose(110, at: now)
        let next = try glucose(125, at: now.addingTimeInterval(30))
        let gaps = HostGapRecorder()
        let driver = HostTestDriver(glucoseReads: [.value(first), .value(next)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now.addingTimeInterval(30)), scheduler: HostManualScheduler(), readGap: { seconds in gaps.record(seconds) })
        await model.activateIfNeeded()
        await model.refresh()
        #expect(model.latestGlucose == next)
        #expect(model.heroState.valueText == "125")
        #expect(!model.isRefreshing)
        #expect(gaps.values.isEmpty)
    }

    @Test @MainActor func refreshFailureKeepsCachedReadingAndLogsOnlyStep() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let logger = HostRecordingLog()
        let driver = HostTestDriver(glucoseReads: [.value(sample), .failure(.timedOut)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), log: logger, readGap: { _ in })
        await model.activateIfNeeded()
        let before = model.heroState
        await model.refresh()
        #expect(model.latestGlucose == sample)
        #expect(model.heroState.valueText == before.valueText)
        #expect(model.heroState.valueColor == before.valueColor)
        #expect(model.heroState.badge == before.badge)
        #expect(logger.failures == ["glucose:timedOut"])
        #expect(!model.isRefreshing)
    }

    @Test @MainActor func nilGlucoseReadDoesNotChangeCachedReadingOrLog() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let logger = HostRecordingLog()
        let driver = HostTestDriver(glucoseReads: [.value(sample), .value(nil)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), log: logger, readGap: { _ in })
        await model.activateIfNeeded()
        let before = model.heroState
        await model.refresh()
        #expect(model.latestGlucose == sample)
        #expect(model.heroState == before)
        #expect(logger.failures.isEmpty)
    }

    @Test @MainActor func pumpFailureContinuesToGlucoseAndHonorsReadGap() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(130, at: now)
        let logger = HostRecordingLog()
        let gaps = HostGapRecorder()
        let driver = HostTestDriver(glucoseReads: [.value(sample)], pumpReads: [.failure(.connectionLost), .failure(.connectionLost)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), log: logger, readGap: { seconds in gaps.record(seconds) })
        await model.activateIfNeeded()
        await model.refresh()
        #expect(model.latestGlucose == sample)
        // Activation and the refresh each run the full sequence: a failed pump
        // read, the gap, then a glucose read.
        #expect(await driver.readCounts == (2, 2))
        #expect(gaps.values == [0.5, 0.5])
        #expect(logger.failures == ["pumpStatus:connectionLost", "pumpStatus:connectionLost"])
    }

    @Test @MainActor func refreshBeforeActivationPerformsNoRead() async {
        let driver = HostTestDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [])
        await model.refresh()
        #expect(await driver.readCounts == (0, 0))
        #expect(!model.isRefreshing)
    }

    @Test @MainActor func failedReadsDoNotFailActivationAndAreLogged() async {
        let logger = HostRecordingLog()
        let driver = HostTestDriver(glucoseReads: [.failure(.timedOut)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], log: logger, readGap: { _ in })
        await model.activateIfNeeded()
        #expect(model.lifecycleState == .active)
        #expect(model.hostError == nil)
        #expect(logger.failures == ["glucose:timedOut"])
        #expect(!model.isRefreshing)
    }

    @Test @MainActor func refreshClearsFlagWhenEveryReadThrows() async {
        let logger = HostRecordingLog()
        let driver = HostTestDriver(glucoseReads: [.failure(.timedOut), .failure(.timedOut)], pumpReads: [.failure(.connectionLost), .failure(.connectionLost)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], log: logger, readGap: { _ in })
        await model.activateIfNeeded()
        await model.refresh()
        #expect(!model.isRefreshing)
        #expect(model.lifecycleState == .active)
        #expect(model.hostError == nil)
        #expect(logger.failures == ["pumpStatus:connectionLost", "glucose:timedOut", "pumpStatus:connectionLost", "glucose:timedOut"])
    }

    @Test @MainActor func tooStaleCachedValueSurvivesReadFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let clock = HostAdjustableClock(now: now)
        let driver = HostTestDriver(glucoseReads: [.value(sample), .failure(.timedOut)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler(), readGap: { _ in })
        await model.activateIfNeeded()
        clock.advance(by: 20_000)
        await model.refresh()
        #expect(model.latestGlucose == sample)
        #expect(model.heroState.valueText == "120")
        #expect(model.heroState.valueColor == .secondary)
        #expect(model.heroState.badge == .tooStale)
    }

    @Test @MainActor func failedActivationDoesNotPermitRefreshReads() async {
        let driver = HostTestDriver(activationFailure: .transportUnavailable)
        let model = HomeModel(driver: driver, demoIdentifiers: [])
        await model.activateIfNeeded()
        await model.refresh()
        #expect(model.lifecycleState == .failed)
        #expect(await driver.readCounts == (0, 0))
    }

    @Test @MainActor func overlappingRefreshIsDroppedWhileSequenceWaitsBetweenReads() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let gap = HostGapController()
        let driver = HostTestDriver(glucoseReads: [.value(sample), .value(sample)], pumpReads: [.value(nil), .value(nil)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), readGap: { _ in await gap.waitIfArmed() })
        await model.activateIfNeeded()
        await gap.arm()
        let first = Task { await model.refresh() }
        await gap.waitUntilEntered()
        await model.refresh()
        // Activation read glucose and pump once. The first refresh has read pump
        // and is held in the gap, so glucose has not been read again, and the
        // overlapping refresh read nothing.
        #expect(await driver.readCounts == (1, 2))
        #expect(model.isRefreshing)
        await gap.release()
        await first.value
        #expect(await driver.readCounts == (2, 2))
        #expect(!model.isRefreshing)
    }

    @Test @MainActor func foregroundReadRunsWhileTornDownReadIsStillBlocked() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let lateStatus = try PumpStatusSnapshot(batteryFraction: 0.7, observedAt: now)
        let gate = HostReadGate()
        let driver = HostTestDriver(glucoseReads: [.value(sample), .value(sample), .value(sample)],
                                    pumpReads: [.value(nil), .value(lateStatus), .value(nil)], pumpReadGate: gate)
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), readGap: { _ in })
        await model.setScenePhaseActive(true).value
        #expect(await driver.readCounts == (1, 1))

        await gate.arm()
        let blocked = Task { await model.refresh() }
        await gate.waitUntilEntered()
        #expect(model.isRefreshing)

        await model.setScenePhaseActive(false).value
        #expect(!model.isRefreshing)
        await model.setScenePhaseActive(true).value
        // The foreground read ran even though the earlier read is still held.
        #expect(await driver.activationCount == 2)
        #expect(await driver.readCounts == (2, 3))
        #expect(!model.isRefreshing)

        await gate.release()
        await blocked.value
        // The held read belonged to the torn-down activation: its pump status is
        // never written and it does not go on to read glucose.
        #expect(await driver.readCounts == (2, 3))
        #expect(model.latestPumpStatus == nil)
        #expect(!model.isRefreshing)
        await model.stop()
    }

    @Test @MainActor func cancelledActivationReadStillAttachesStreams() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let driver = StreamingHostDriver()
        // Cancel the activating task from inside its read sequence, as a scene
        // change can, so the sequence stops early on cancellation.
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(),
                              readGap: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        await Task { await model.activateIfNeeded() }.value
        #expect(model.lifecycleState == .active)

        let sample = try glucose(140, at: now)
        await driver.emit(sample)
        #expect(await eventually { model.latestGlucose == sample })
        await model.stop()
    }

    @Test @MainActor func sceneTransitionsReadExactlyOncePerForeground() async {
        let driver = HostTestDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [], readGap: { _ in })
        await model.setScenePhaseActive(true).value
        await model.setScenePhaseActive(true).value
        #expect(await driver.readCounts.0 == 1)

        model.sceneBecameInactive()
        await model.setScenePhaseActive(true).value
        #expect(await driver.readCounts.0 == 2)

        await model.setScenePhaseActive(false).value
        await model.setScenePhaseActive(true).value
        #expect(await driver.activationCount == 2)
        #expect(await driver.readCounts.0 == 3)
    }

    @Test @MainActor func inactiveDuringActivationReadStillReadsOnNextForeground() async {
        let gap = HostGapController()
        let driver = HostTestDriver(pumpReads: [.value(nil), .value(nil), .value(nil)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], readGap: { _ in await gap.waitIfArmed() })
        await gap.arm()
        let activation = model.setScenePhaseActive(true)
        await gap.waitUntilEntered()
        // The scene goes inactive while the activation read is held between reads.
        model.sceneBecameInactive()
        await gap.release()
        await activation.value
        #expect(await driver.readCounts == (1, 1))

        await model.setScenePhaseActive(true).value
        // The activation read finished after the inactive transition, so it does
        // not count for this foreground and a new read runs.
        #expect(await driver.activationCount == 1)
        #expect(await driver.readCounts == (2, 2))
        await model.stop()
    }

    @Test @MainActor func equalReadingKeepsAgeAndBadge() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let clock = HostAdjustableClock(now: now)
        let driver = HostTestDriver(glucoseReads: [.value(sample), .value(sample)])
        let model = HomeModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler(), readGap: { _ in })
        await model.activateIfNeeded()
        let before = model.heroState
        let heldTimestamp = model.latestGlucose?.recordedAt
        clock.advance(by: 120)
        await model.refresh()
        #expect(model.latestGlucose?.recordedAt == heldTimestamp)
        #expect(model.heroState.badge == before.badge)
    }

    private func glucose(_ value: Double, at date: Date) throws -> GlucoseSample {
        GlucoseSample(glucose: try Glucose(mgdl: value), recordedAt: date, trend: .steady)
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
    private let pump: HostPumpSource?
    private let insulin = HostInsulinSource()
    private let activationFailure: DriverFailure?
    private let missing: Capability?
    private let deactivationGate: HostDeactivationGate?
    private let activationGate: HostDeactivationGate?
    private(set) var activationCount = 0
    private(set) var didDeactivate = false

    init(activationFailure: DriverFailure? = nil, missing: Capability? = nil, initialSample: GlucoseSample? = nil,
         glucoseReads: [HostReadResult<GlucoseSample>] = [], pumpReads: [HostReadResult<PumpStatusSnapshot>]? = nil,
         deactivationGate: HostDeactivationGate? = nil, activationGate: HostDeactivationGate? = nil,
         pumpReadGate: HostReadGate? = nil) {
        self.activationFailure = activationFailure
        self.missing = missing
        self.glucose = HostGlucoseSource(initialSample: initialSample, scripted: glucoseReads)
        self.pump = pumpReads.map { HostPumpSource(scripted: $0, gate: pumpReadGate) }
        self.deactivationGate = deactivationGate
        self.activationGate = activationGate
        self.descriptor = DriverDescriptor(
            identifier: Self.simulatedIdentifier,
            targetName: "HostTestDriver",
            displayName: "Host test Driver",
            transport: .inProcess,
            version: "1.0.0",
            capabilities: pumpReads == nil ? [.glucoseSource, .insulinSource] : [.glucoseSource, .insulinSource, .pumpStatus],
            verification: .unverified
        )
    }

    func capability(_ capability: Capability) -> CapabilityPort? {
        guard capability != missing else { return nil }
        return switch capability {
        case .glucoseSource: .glucoseSource(glucose)
        case .insulinSource: .insulinSource(insulin)
        case .pumpStatus: pump.map(CapabilityPort.pumpStatus)
        case .bgmSource, .dataSync, .doseCategoryProvider: nil
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

    var readCounts: (Int, Int) { get async { (glucose.readCount, pump?.readCount ?? 0) } }
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

private actor HostGapController {
    private var armed = false
    private var entered = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func arm() { armed = true }
    func waitIfArmed() async {
        guard armed else { return }
        entered = true
        waiter?.resume()
        waiter = nil
        if released { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private final class HostGapRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []
    var values: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return recorded }
    func record(_ value: TimeInterval) { lock.lock(); recorded.append(value); lock.unlock() }
}

private final class HostRecordingLog: HomeLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var failures: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    func refreshReadFailed(step: RefreshStep, failure: DriverFailure) {
        lock.lock(); recorded.append("\(step.rawValue):\(failure.caseName)"); lock.unlock()
    }
}

private enum HostReadResult<Value: Sendable>: Sendable {
    case value(Value?)
    case failure(DriverFailure)
}

private final class HostScriptedReads<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [HostReadResult<Value>]
    private var index = 0
    private var count = 0
    init(_ results: [HostReadResult<Value>]) { self.results = results }
    var readCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func next() throws(DriverFailure) -> Value? {
        lock.lock(); defer { lock.unlock() }
        count += 1
        guard index < results.count else { return nil }
        let result = results[index]
        index += 1
        return switch result {
        case .value(let value): value
        case .failure(let failure): throw failure
        }
    }
}

private struct HostGlucoseSource: GlucoseSource {
    let initialSample: GlucoseSample?
    let reads: HostScriptedReads<GlucoseSample>
    init(initialSample: GlucoseSample?, scripted: [HostReadResult<GlucoseSample>]) {
        self.initialSample = initialSample
        reads = HostScriptedReads(scripted.isEmpty ? [.value(initialSample)] : scripted)
    }
    var readings: AsyncStream<GlucoseSample> { AsyncStream { $0.finish() } }
    var readCount: Int { reads.readCount }
    func latestReading() async throws(DriverFailure) -> GlucoseSample? { try reads.next() }
}

private struct HostPumpSource: PumpStatusSource {
    let reads: HostScriptedReads<PumpStatusSnapshot>
    let gate: HostReadGate?
    init(scripted: [HostReadResult<PumpStatusSnapshot>], gate: HostReadGate? = nil) {
        reads = HostScriptedReads(scripted)
        self.gate = gate
    }
    var status: AsyncStream<PumpStatusSnapshot> { AsyncStream { $0.finish() } }
    var readCount: Int { reads.readCount }
    func latestStatus() async throws(DriverFailure) -> PumpStatusSnapshot? {
        let value = try reads.next()
        await gate?.holdIfArmed()
        return value
    }
}

/// Holds the first read that arrives after `arm()` until `release()`, and lets
/// every other read through. That models one slow Driver read without stalling
/// the reads that follow it.
private actor HostReadGate {
    private var armed = false
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func arm() { armed = true }
    func holdIfArmed() async {
        guard armed else { return }
        armed = false
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
