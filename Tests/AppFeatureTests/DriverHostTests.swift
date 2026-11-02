import Testing
import Foundation
import AppFeature
import SafetyCore
import DriverAPI
import DomainCore
@_spi(DriverPlatform) import DriverAPI

@MainActor
private func makeHostModel(
    driver: any Driver, demoIdentifiers: Set<DriverIdentifier>,
    backend: BackendConfiguration = .notConfigured, clock: any SafetyCore.Clock = SystemClock(),
    scheduler: any Scheduler = WallClockScheduler(), log: any HomeLogging = OSHomeLog(),
    readGap: @escaping @Sendable (TimeInterval) async -> Void = { _ in }
) -> HomeModel {
    let store = HostSelectionStore([driver.descriptor.identifier.rawValue])
    let registry = try! DriverRegistry(drivers: [driver], store: store)
    return HomeModel(registry: registry, awaitStartup: {
        await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
    }, demoIdentifiers: demoIdentifiers, backend: backend, clock: clock, scheduler: scheduler,
        log: log, readGap: readGap)
}

private final class HostSelectionStore: DriverSelectionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String>
    var saveFailure: DriverSelectionStoreFailure?
    var loadFailure: DriverSelectionStoreFailure?
    private let saved: Bool
    init(_ ids: Set<String>, saved: Bool = true) { self.ids = ids; self.saved = saved }
    func hasSavedSelection() -> Bool { saved }
    func load() throws(DriverSelectionStoreFailure) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let loadFailure { throw loadFailure }
        return ids
    }
    var savedIDs: Set<String> { lock.lock(); defer { lock.unlock() }; return ids }
    func save(_ ids: Set<String>) throws(DriverSelectionStoreFailure) {
        lock.lock()
        defer { lock.unlock() }
        if let saveFailure { throw saveFailure }
        self.ids = ids
    }
}

@Suite("Driver host")
struct DriverHostTests {
    @Test @MainActor func statusRowDefaultsToDisconnectedWithoutBackend() {
        let model = makeHostModel(driver: HostTestDriver(), demoIdentifiers: [])
        #expect(model.statusRow.pumpLink == PumpLinkIndicator.make(.disconnected))
        #expect(model.statusRow.sync == nil)
        #expect(model.statusRow.reachability == nil)
    }

    @Test @MainActor func configuredBackendAppearsInStatusRow() {
        let backend = BackendConfiguration.configured(.init(sync: .init(hasError: false, pendingCount: 0, lastSync: nil), reachability: .reachable))
        let model = makeHostModel(driver: HostTestDriver(), demoIdentifiers: [], backend: backend)
        #expect(model.statusRow.sync != nil)
        #expect(model.statusRow.reachability?.accessibilityLabel == "Backend reachable")
    }

    @Test @MainActor func demoFlagExistsBeforeActivationAndAfterSuccess() async {
        let driver = HostTestDriver()
        let model = makeHostModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier])
        #expect(model.isDemo)
        #expect(model.lifecycleState == .notActivated)

        await model.setScenePhaseActive(true).value

        #expect(model.isDemo)
        #expect(model.lifecycleState == .active)
        #expect(model.ports?.identifier == driver.descriptor.identifier)
    }

    @Test @MainActor func permanentRestoreFailureShowsStartFailed() async {
        let driver = HostTestDriver(activationFailure: .authenticationRejected)
        let model = makeHostModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier])
        #expect(model.isDemo)

        await model.setScenePhaseActive(true).value

        #expect(!model.isDemo)
        #expect(model.source == .startFailed(driver.descriptor.identifier, .authenticationRejected))
        #expect(model.ports == nil)
        let message = HomeSourceMessage.make(source: model.source, displayName: model.displayName(of:))
        #expect(message?.identifier == "home.source-failed")
        #expect(message?.body == "Host test Driver didn't start. Restart the app to try again.")
    }

    @Test @MainActor func unavailableGlucosePortIsVisible() async {
        let model = makeHostModel(driver: HostTestDriver(missing: .glucoseSource), demoIdentifiers: [])
        await model.setScenePhaseActive(true).value
        #expect(model.source == .unavailable(.portUnavailable(HostTestDriver.simulatedIdentifier, .glucoseSource)))
    }

    @Test @MainActor func unavailableInsulinPortIsOptionalError() async {
        let model = makeHostModel(driver: HostTestDriver(missing: .insulinSource), demoIdentifiers: [])
        await model.setScenePhaseActive(true).value
        #expect(model.source == .connected(HostTestDriver.simulatedIdentifier))
        #expect(model.slotErrors == [.portUnavailable(HostTestDriver.simulatedIdentifier, .insulinSource)])
        #expect(model.latestIOB == nil)
    }

    @Test @MainActor func glucoseOnlyDriverHasNoOptionalSlotError() async {
        let driver = HostTestDriver(hasInsulin: false)
        let model = makeHostModel(driver: driver, demoIdentifiers: [])
        await model.setScenePhaseActive(true).value
        #expect(model.source == .connected(driver.descriptor.identifier))
        #expect(model.latestIOB == nil)
        #expect(model.ports?.insulinSource == nil)
        #expect(model.slotErrors.isEmpty)
    }

    @Test @MainActor func sceneTransitionsDoNotReactivateRegistryDriver() async {
        let driver = HostTestDriver()
        let model = makeHostModel(driver: driver, demoIdentifiers: [])
        await model.setScenePhaseActive(true).value
        await model.setScenePhaseActive(false).value
        await model.setScenePhaseActive(true).value
        await model.setScenePhaseActive(false).value
        #expect(await driver.activationCount == 1)
        #expect(await driver.deactivationCount == 0)
    }

    @Test @MainActor func emptySelectionShowsNoGlucoseSource() async throws {
        let driver = HostTestDriver()
        let store = HostSelectionStore([])
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
        }, demoIdentifiers: [HostTestDriver.simulatedIdentifier], scheduler: HostManualScheduler())
        #expect(model.source == .pending)
        await model.setScenePhaseActive(true).value
        #expect(model.source == .noActiveDriver)
        #expect(model.ports == nil)
        #expect(!model.isDemo)
        #expect(model.statusRow.marks.isEmpty)
        let message = HomeSourceMessage.make(source: model.source, displayName: model.displayName(of:))
        #expect(message?.identifier == "home.no-glucose-source")
        #expect(message?.title == "No glucose source")
    }

    @Test @MainActor func failedRemovalSaveKeepsFailedHolderVisible() async throws {
        let driver = HostTestDriver(activationFailure: .authenticationRejected)
        let store = HostSelectionStore([driver.descriptor.identifier.rawValue])
        store.saveFailure = .unwritable(detail: "injected")
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
        }, demoIdentifiers: [], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value
        #expect(model.source == .unavailable(.holderNotRunning(driver.descriptor.identifier, .glucoseSource, .failed)))
        #expect(model.lifecycleState == .failed)
    }

    @Test @MainActor func backgroundKeepsStreamAndForegroundReadsWithoutRestart() async throws {
        let driver = StreamingHostDriver()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value
        await model.setScenePhaseActive(false).value
        let sample = GlucoseSample(glucose: try Glucose(mgdl: 120), recordedAt: now, trend: .steady)
        await driver.emit(sample)
        #expect(await eventually { model.latestGlucose == sample })
        await model.setScenePhaseActive(true).value
        #expect(await driver.activationCount == 1)
    }

    @Test @MainActor func backgroundStopsTickerAndForegroundRestartsIt() async {
        let scheduler = HostManualScheduler()
        let model = makeHostModel(driver: HostTestDriver(), demoIdentifiers: [], scheduler: scheduler)
        await model.setScenePhaseActive(true).value
        #expect(!scheduler.isCancelled)
        await model.setScenePhaseActive(false).value
        #expect(scheduler.isCancelled)
        await model.setScenePhaseActive(true).value
        #expect(!scheduler.isCancelled)
    }

    @Test @MainActor func registryTeardownDropsPortsAndReconnectsToEmptySlot() async throws {
        let driver = StreamingHostDriver()
        let store = HostSelectionStore([driver.descriptor.identifier.rawValue])
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
        }, demoIdentifiers: [], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value
        #expect(model.source == .connected(driver.descriptor.identifier))
        try await registry.deactivate(driver.descriptor.identifier)
        // Still in the foreground, so Home reconnects and finds the slot empty.
        #expect(await eventually { model.source == .noActiveDriver && model.ports == nil })
    }

    @Test @MainActor func transientSelectionLoadFailureShowsWillRetryAndForegroundRestores() async throws {
        let seedTarget = HostTestDriver()
        let selected = StreamingHostDriver()
        let store = HostSelectionStore([selected.descriptor.identifier.rawValue], saved: false)
        store.loadFailure = .unavailable(detail: "before first unlock")
        let registry = try DriverRegistry(drivers: [seedTarget, selected], store: store)
        let startup = Task {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: seedTarget.descriptor.identifier)
        }
        let model = HomeModel(registry: registry, awaitStartup: { await startup.value },
                              demoIdentifiers: [], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value
        #expect(model.source == .selectionDeferred(.unavailable(detail: "before first unlock")))
        #expect(model.ports == nil)
        let message = HomeSourceMessage.make(source: model.source, displayName: model.displayName(of:))
        #expect(message?.identifier == "home.source-deferred")
        #expect(message?.title == "Data source not running")

        store.loadFailure = nil
        await model.setScenePhaseActive(false).value
        await model.setScenePhaseActive(true).value
        #expect(model.source == .connected(selected.descriptor.identifier))
        #expect(await selected.activationCount == 1)
        // The first-launch default never replaces a selection that was only unreadable.
        #expect(await seedTarget.activationCount == 0)
        #expect(store.savedIDs == [selected.descriptor.identifier.rawValue])
        await model.setScenePhaseActive(false).value
    }

    @Test @MainActor func failedFirstLaunchSeedShowsDidntStart() async throws {
        let driver = HostTestDriver(activationFailure: .authenticationRejected)
        let id = driver.descriptor.identifier
        let store = HostSelectionStore([], saved: false)
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: id)
        }, demoIdentifiers: [id], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value
        #expect(model.source == .seedFailed(id, .activationFailed(id, .authenticationRejected)))
        #expect(!model.isDemo)
        let message = HomeSourceMessage.make(source: model.source, displayName: model.displayName(of:))
        #expect(message?.identifier == "home.source-failed")
        #expect(message?.body == "Host test Driver didn't start. Restart the app to try again.")
    }

    @Test @MainActor func pendingStartupShowsStartingMessage() async throws {
        let gate = HostDeactivationGate()
        let driver = HostTestDriver(activationGate: gate)
        let model = makeHostModel(driver: driver, demoIdentifiers: [], scheduler: HostManualScheduler())
        let connecting = model.setScenePhaseActive(true)
        await gate.waitUntilEntered()
        #expect(model.source == .pending)
        let message = HomeSourceMessage.make(source: model.source, displayName: model.displayName(of:))
        #expect(message?.identifier == "home.starting")
        #expect(message?.title == "Starting…")
        #expect(model.sourceMessage?.identifier == "home.starting")
        await gate.release()
        await connecting.value
        #expect(model.source == .connected(driver.descriptor.identifier))
        #expect(HomeSourceMessage.make(source: model.source, displayName: model.displayName(of:)) == nil)
    }

    @Test @MainActor func holderChangeClearsPreviousValuesAndDemoLabel() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let demoSample = try glucose(150, at: now)
        let demoStatus = try PumpStatusSnapshot(batteryFraction: 0.8, observedAt: now)
        let demo = HostTestDriver(glucoseReads: [.value(demoSample)], pumpReads: [.value(demoStatus)])
        let next = StreamingHostDriver()
        let store = HostSelectionStore([demo.descriptor.identifier.rawValue])
        let registry = try DriverRegistry(drivers: [demo, next], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
        }, demoIdentifiers: [demo.descriptor.identifier], clock: HostAdjustableClock(now: now),
            scheduler: HostManualScheduler(), readGap: { _ in })
        await model.setScenePhaseActive(true).value
        #expect(model.latestGlucose == demoSample)
        #expect(model.latestPumpStatus == demoStatus)
        #expect(model.heroState.accessibilityLabel.hasPrefix("DEMO DATA"))

        try await registry.activate(next.descriptor.identifier)
        #expect(await eventually { model.source == .connected(next.descriptor.identifier) })
        #expect(model.latestGlucose == nil)
        #expect(model.latestIOB == nil)
        #expect(model.latestPumpStatus == nil)
        #expect(!model.isDemo)
        #expect(model.heroState.valueText == "--")
        #expect(!model.heroState.accessibilityLabel.hasPrefix("DEMO DATA"))

        // An older sample from the new Driver is not held back by the old Driver's timestamp.
        let older = try glucose(110, at: now.addingTimeInterval(-120))
        await next.emit(older)
        #expect(await eventually { model.latestGlucose == older })
        await model.setScenePhaseActive(false).value
    }

    @Test @MainActor func sameHolderReconnectKeepsCachedValuesOnHome() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = HostAdjustableClock(now: now)
        let scheduler = HostManualScheduler()
        let gate = HostReadGate()
        let driver = StreamingHostDriver(glucoseReadGate: gate)
        let id = driver.descriptor.identifier
        let store = HostSelectionStore([id.rawValue])
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
        }, demoIdentifiers: [], clock: clock, scheduler: scheduler, readGap: { _ in })
        await model.setScenePhaseActive(true).value
        #expect(model.source == .connected(id))

        let sample = try glucose(120, at: now)
        let iob = try InsulinOnBoardSample(units: 1.5, calculatedAt: now)
        let status = try PumpStatusSnapshot(batteryFraction: 0.6, observedAt: now)
        await driver.emit(sample)
        await driver.emit(iob)
        await driver.emit(status)
        #expect(await eventually {
            model.latestGlucose == sample && model.latestIOB == iob && model.latestPumpStatus == status
        })

        // The glucose stream ends while the Driver stays active; the reconnect's
        // read is held so the in-between state can be checked.
        await gate.arm()
        await driver.endGlucoseStream()
        await gate.waitUntilEntered()
        #expect(model.source == .pending)
        #expect(model.sourceMessage == nil)
        #expect(model.latestGlucose == sample)
        #expect(model.latestIOB == iob)
        #expect(model.latestPumpStatus == status)
        clock.advance(by: 120)
        await scheduler.tick()
        #expect(model.heroState.valueText == "120")
        #expect(model.heroState.ageCaption == "2m ago")

        await gate.release()
        #expect(await eventually { model.source == .connected(id) })
        #expect(model.sourceMessage == nil)
        #expect(model.latestGlucose == sample)
        #expect(model.latestIOB == iob)
        #expect(model.latestPumpStatus == status)
        #expect(await driver.activationCount == 1)
        await model.setScenePhaseActive(false).value
    }

    @Test @MainActor func teardownWithoutStreamEndDropsConnection() async throws {
        // HostTestDriver's streams never finish, so only the registry can say it stopped.
        let driver = HostTestDriver(cards: [DashboardCardDescriptor(id: "visible", title: "Visible", priority: 100, elements: [])])
        let store = HostSelectionStore([driver.descriptor.identifier.rawValue])
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
        }, demoIdentifiers: [], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value
        #expect(model.source == .connected(driver.descriptor.identifier))
        #expect(await eventually { model.driverCards.map(\.card.id) == ["visible"] })
        try await registry.deactivate(driver.descriptor.identifier)
        #expect(await driver.didDeactivate)
        #expect(await eventually { model.source == .noActiveDriver && model.ports == nil })
        #expect(model.lifecycleState == .notActivated)
        #expect(model.driverCards.isEmpty)
    }

    @Test @MainActor func teardownDuringConnectReadDropsLateWritesAndAttachment() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let lateStatus = try PumpStatusSnapshot(batteryFraction: 0.7, observedAt: now)
        let gate = HostReadGate()
        let driver = HostTestDriver(glucoseReads: [.value(try glucose(120, at: now))],
                                    pumpReads: [.value(lateStatus)], pumpReadGate: gate)
        let store = HostSelectionStore([driver.descriptor.identifier.rawValue])
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
        }, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), readGap: { _ in })
        await gate.arm()
        let connecting = model.setScenePhaseActive(true)
        await gate.waitUntilEntered()
        #expect(model.isRefreshing)
        #expect(model.ports != nil)

        try await registry.deactivate(driver.descriptor.identifier)
        // The registry change drops the in-flight connection: the read's generation is stale.
        #expect(await eventually { model.ports == nil && !model.isRefreshing })
        await gate.release()
        await connecting.value

        #expect(model.latestPumpStatus == nil)
        #expect(model.latestGlucose == nil)
        // The held sequence stopped after its pump read and never read glucose.
        #expect(await driver.readCounts == (0, 1))
        #expect(model.source == .noActiveDriver)
        #expect(model.ports == nil)
    }

    @Test @MainActor func sourceMessagesCoverEveryState() {
        let id = HostTestDriver.simulatedIdentifier
        let name: (DriverIdentifier) -> String? = { _ in "Host test Driver" }
        #expect(HomeSourceMessage.make(source: .pending, displayName: name) ==
                HomeSourceMessage(title: "Starting…", body: "Connecting to your data source.", identifier: "home.starting"))
        #expect(HomeSourceMessage.make(source: .seedFailed(id, .activationFailed(id, .timedOut)), displayName: name) ==
                HomeSourceMessage(title: "Unable to start data source", body: "Host test Driver didn't start. Restart the app to try again.", identifier: "home.source-failed"))
        #expect(HomeSourceMessage.make(source: .selectionDeferred(.unavailable(detail: "locked")), displayName: name) ==
                HomeSourceMessage(title: "Data source not running", body: "Your data source isn't running yet. It will retry when you return to the app.", identifier: "home.source-deferred"))
        #expect(HomeSourceMessage.make(source: .connected(id), displayName: name) == nil)
        #expect(HomeSourceMessage.make(source: .noActiveDriver, displayName: name) ==
                HomeSourceMessage(title: "No glucose source", body: "No active Driver is providing glucose readings, so there is nothing to show here.", identifier: "home.no-glucose-source"))
        #expect(HomeSourceMessage.make(source: .startFailed(id, .authenticationRejected), displayName: name) ==
                HomeSourceMessage(title: "Unable to start data source", body: "Host test Driver didn't start. Restart the app to try again.", identifier: "home.source-failed"))
        #expect(HomeSourceMessage.make(source: .deferred(id, .transportUnavailable), displayName: name) ==
                HomeSourceMessage(title: "Data source not running", body: "Host test Driver isn't running. It will retry when the app starts again.", identifier: "home.source-deferred"))
        #expect(HomeSourceMessage.make(source: .unavailable(.holderNotRunning(id, .glucoseSource, .failed)), displayName: name)?.identifier == "home.source-failed")
        #expect(HomeSourceMessage.make(source: .unavailable(.cancelled), displayName: name)?.identifier == "home.no-glucose-source")
        #expect(HomeSourceMessage.make(source: .unavailable(.portUnavailable(id, .glucoseSource)), displayName: name) ==
                HomeSourceMessage(title: "Unable to start data source", body: "Host test Driver isn't providing glucose readings. Restart the app to try again.", identifier: "home.source-failed"))
    }

    @Test @MainActor func refreshAppliesNewReadingAndClearsFlag() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try glucose(110, at: now)
        let next = try glucose(125, at: now.addingTimeInterval(30))
        let gaps = HostGapRecorder()
        let driver = HostTestDriver(glucoseReads: [.value(first), .value(next)])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now.addingTimeInterval(30)), scheduler: HostManualScheduler(), readGap: { seconds in gaps.record(seconds) })
        await model.setScenePhaseActive(true).value
        await model.refresh()
        #expect(model.latestGlucose == next)
        #expect(model.heroState.valueText == "125")
        #expect(!model.isRefreshing)
        #expect(gaps.values.isEmpty)
    }

    @Test @MainActor func contributedCardOrderIsStableAcrossRefreshes() async throws {
        let a = DashboardCardDescriptor(id: "z", title: "Z", priority: 100, elements: [])
        let b = DashboardCardDescriptor(id: "a", title: "A", priority: 100, elements: [])
        let driver = HostTestDriver(cards: [a, b])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value
        let id = HostTestDriver.simulatedIdentifier
        let expected = [ContributedCard.ID(driver: id, card: "a"), ContributedCard.ID(driver: id, card: "z")]
        #expect(await eventually { model.driverCards.map(\.id) == expected })
        for _ in 0..<5 {
            let before = await driver.cardReadCount
            await model.refresh()
            var reread = false
            for _ in 0..<2000 where !reread {
                let count = await driver.cardReadCount
                let settled = await driver.allCardReadsFinished
                reread = count > before && settled
                if !reread { try await Task.sleep(nanoseconds: 1_000_000) }
            }
            #expect(reread)
            #expect(await eventually { model.driverCards.map(\.id) == expected })
        }
    }

    @Test @MainActor func hungCardDriverDoesNotBlockRefreshOrDeactivation() async throws {
        let hang = HostCardHang()
        let driver = HostTestDriver(cards: [DashboardCardDescriptor(id: "never", title: "Never", priority: 100, elements: [])],
                                    cardHang: hang)
        let store = HostSelectionStore([driver.descriptor.identifier.rawValue])
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = HomeModel(registry: registry, awaitStartup: {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: nil)
        }, demoIdentifiers: [], scheduler: HostManualScheduler(), readGap: { _ in })
        await model.setScenePhaseActive(true).value
        #expect(model.source == .connected(driver.descriptor.identifier))
        await hang.waitUntilEntered()

        await model.refresh()
        #expect(model.driverCards.isEmpty)

        try await registry.deactivate(driver.descriptor.identifier)
        #expect(await eventually { model.source == .noActiveDriver && model.ports == nil })
        #expect(model.driverCards.isEmpty)
        await hang.release()
    }

    @Test @MainActor func slowerEarlierCardReloadCannotReplaceLaterCards() async throws {
        let gate = HostReadGate()
        await gate.arm()
        let driver = HostTestDriver(cards: [DashboardCardDescriptor(id: "stale", title: "Stale", priority: 100, elements: [])],
                                    cardGate: gate)
        let model = makeHostModel(driver: driver, demoIdentifiers: [], scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value
        await gate.waitUntilEntered()

        await driver.setCards([DashboardCardDescriptor(id: "fresh", title: "Fresh", priority: 100, elements: [])])
        await model.refresh()
        #expect(await eventually { model.driverCards.map(\.card.id) == ["fresh"] })

        await gate.release()
        var finished = false
        for _ in 0..<2000 where !finished {
            finished = await driver.allCardReadsFinished
            if !finished { try await Task.sleep(nanoseconds: 1_000_000) }
        }
        #expect(finished)
        // Let any reload still holding the stale answer try to publish it.
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(model.driverCards.map(\.card.id) == ["fresh"])
    }

    @Test @MainActor func refreshFailureKeepsCachedReadingAndLogsOnlyStep() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let logger = HostRecordingLog()
        let driver = HostTestDriver(glucoseReads: [.value(sample), .failure(.timedOut)])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), log: logger, readGap: { _ in })
        await model.setScenePhaseActive(true).value
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
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), log: logger, readGap: { _ in })
        await model.setScenePhaseActive(true).value
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
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), log: logger, readGap: { seconds in gaps.record(seconds) })
        await model.setScenePhaseActive(true).value
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
        let model = makeHostModel(driver: driver, demoIdentifiers: [])
        await model.refresh()
        #expect(await driver.readCounts == (0, 0))
        #expect(!model.isRefreshing)
    }

    @Test @MainActor func failedReadsDoNotFailActivationAndAreLogged() async {
        let logger = HostRecordingLog()
        let driver = HostTestDriver(glucoseReads: [.failure(.timedOut)])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], log: logger, readGap: { _ in })
        await model.setScenePhaseActive(true).value
        #expect(model.lifecycleState == .active)
        #expect(model.source == .connected(driver.descriptor.identifier))
        #expect(logger.failures == ["glucose:timedOut"])
        #expect(!model.isRefreshing)
    }

    @Test @MainActor func refreshClearsFlagWhenEveryReadThrows() async {
        let logger = HostRecordingLog()
        let driver = HostTestDriver(glucoseReads: [.failure(.timedOut), .failure(.timedOut)], pumpReads: [.failure(.connectionLost), .failure(.connectionLost)])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], log: logger, readGap: { _ in })
        await model.setScenePhaseActive(true).value
        await model.refresh()
        #expect(!model.isRefreshing)
        #expect(model.lifecycleState == .active)
        #expect(model.source == .connected(driver.descriptor.identifier))
        #expect(logger.failures == ["pumpStatus:connectionLost", "glucose:timedOut", "pumpStatus:connectionLost", "glucose:timedOut"])
    }

    @Test @MainActor func tooStaleCachedValueSurvivesReadFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let clock = HostAdjustableClock(now: now)
        let driver = HostTestDriver(glucoseReads: [.value(sample), .failure(.timedOut)])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler(), readGap: { _ in })
        await model.setScenePhaseActive(true).value
        clock.advance(by: 20_000)
        await model.refresh()
        #expect(model.latestGlucose == sample)
        #expect(model.heroState.valueText == "120")
        #expect(model.heroState.valueColor == .secondary)
        #expect(model.heroState.badge == .tooStale)
    }

    @Test @MainActor func transientRestoreFailureShowsNotRunningWillRetry() async {
        let driver = HostTestDriver(activationFailure: .transportUnavailable)
        let model = makeHostModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier])
        await model.setScenePhaseActive(true).value
        await model.refresh()
        #expect(model.source == .deferred(driver.descriptor.identifier, .transportUnavailable))
        #expect(model.lifecycleState == .failed)
        #expect(model.ports == nil)
        #expect(!model.isDemo)
        #expect(await driver.readCounts == (0, 0))
        let message = HomeSourceMessage.make(source: model.source, displayName: model.displayName(of:))
        #expect(message?.identifier == "home.source-deferred")
        #expect(message?.body == "Host test Driver isn't running. It will retry when the app starts again.")
    }

    @Test @MainActor func overlappingRefreshIsDroppedWhileSequenceWaitsBetweenReads() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let gap = HostGapController()
        let driver = HostTestDriver(glucoseReads: [.value(sample), .value(sample)], pumpReads: [.value(nil), .value(nil)])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: HostAdjustableClock(now: now), scheduler: HostManualScheduler(), readGap: { _ in await gap.waitIfArmed() })
        await model.setScenePhaseActive(true).value
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





    @Test @MainActor func sceneTransitionsReadExactlyOncePerForeground() async {
        let driver = HostTestDriver()
        let model = makeHostModel(driver: driver, demoIdentifiers: [], readGap: { _ in })
        await model.setScenePhaseActive(true).value
        await model.setScenePhaseActive(true).value
        #expect(await driver.readCounts.0 == 1)

        model.sceneBecameInactive()
        await model.setScenePhaseActive(true).value
        #expect(await driver.readCounts.0 == 2)

        await model.setScenePhaseActive(false).value
        await model.setScenePhaseActive(true).value
        #expect(await driver.activationCount == 1)
        #expect(await driver.readCounts.0 == 3)
    }

    @Test @MainActor func inactiveDuringActivationReadStillReadsOnNextForeground() async {
        let gap = HostGapController()
        let driver = HostTestDriver(pumpReads: [.value(nil), .value(nil), .value(nil)])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], readGap: { _ in await gap.waitIfArmed() })
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
        await model.setScenePhaseActive(false).value
    }

    @Test @MainActor func equalReadingKeepsAgeAndBadge() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = try glucose(120, at: now)
        let clock = HostAdjustableClock(now: now)
        let driver = HostTestDriver(glucoseReads: [.value(sample), .value(sample)])
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler(), readGap: { _ in })
        await model.setScenePhaseActive(true).value
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
        let model = makeHostModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier], clock: clock, scheduler: scheduler)
        await model.setScenePhaseActive(true).value

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















    @Test @MainActor func futureDatedGlucoseBeyondSkewIsDroppedAndDoesNotBlockLaterSamples() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = HostAdjustableClock(now: now)
        let driver = StreamingHostDriver()
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value

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
        await model.setScenePhaseActive(false).value
    }

    @Test @MainActor func futureDatedIOBAndPumpStatusBeyondSkewAreDropped() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = HostAdjustableClock(now: now)
        let driver = StreamingHostDriver()
        let model = makeHostModel(driver: driver, demoIdentifiers: [], clock: clock, scheduler: HostManualScheduler())
        await model.setScenePhaseActive(true).value

        let tooFar = now.addingTimeInterval(SafetyConstants.alertFloorMaxFutureSkew + 1)
        await driver.emit(try InsulinOnBoardSample(units: 9, calculatedAt: tooFar))
        await driver.emit(try InsulinOnBoardSample(units: 1.5, calculatedAt: now))
        #expect(await eventually { model.latestIOB?.calculatedAt == now })
        #expect(model.latestIOB?.units == 1.5)

        await driver.emit(try PumpStatusSnapshot(batteryFraction: 0.9, observedAt: tooFar))
        await driver.emit(try PumpStatusSnapshot(batteryFraction: 0.4, observedAt: now))
        #expect(await eventually { model.latestPumpStatus?.observedAt == now })
        #expect(model.latestPumpStatus?.batteryFraction == 0.4)
        await model.setScenePhaseActive(false).value
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
    private let hasInsulin: Bool
    private let deactivationGate: HostDeactivationGate?
    private let activationGate: HostDeactivationGate?
    private var contributedCards: [DashboardCardDescriptor]
    private var reverseCards = false
    private let cardGate: HostReadGate?
    private let cardHang: HostCardHang?
    private(set) var cardReadCount = 0
    private(set) var finishedCardReads = 0
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    private(set) var didDeactivate = false

    init(activationFailure: DriverFailure? = nil, missing: Capability? = nil, hasInsulin: Bool = true,
         initialSample: GlucoseSample? = nil,
         glucoseReads: [HostReadResult<GlucoseSample>] = [], pumpReads: [HostReadResult<PumpStatusSnapshot>]? = nil,
         deactivationGate: HostDeactivationGate? = nil, activationGate: HostDeactivationGate? = nil,
         pumpReadGate: HostReadGate? = nil, cards: [DashboardCardDescriptor] = [],
         cardGate: HostReadGate? = nil, cardHang: HostCardHang? = nil) {
        self.activationFailure = activationFailure
        self.missing = missing
        self.hasInsulin = hasInsulin
        self.glucose = HostGlucoseSource(initialSample: initialSample, scripted: glucoseReads)
        self.pump = pumpReads.map { HostPumpSource(scripted: $0, gate: pumpReadGate) }
        self.deactivationGate = deactivationGate
        self.activationGate = activationGate
        self.contributedCards = cards
        self.cardGate = cardGate
        self.cardHang = cardHang
        self.descriptor = DriverDescriptor(
            identifier: Self.simulatedIdentifier,
            targetName: "HostTestDriver",
            displayName: "Host test Driver",
            transport: .inProcess,
            version: "1.0.0",
            capabilities: Set<Capability>([.glucoseSource] + (hasInsulin ? [.insulinSource] : []) + (pumpReads == nil ? [] : [.pumpStatus])),
            verification: .unverified
        )
    }

    func dashboardCards() async -> [DashboardCardDescriptor] {
        cardReadCount += 1
        // Captured before suspending, so a held read answers with the cards of its own time.
        let snapshot = contributedCards
        if let cardHang { await cardHang.hang() }
        await cardGate?.holdIfArmed()
        reverseCards.toggle()
        finishedCardReads += 1
        return reverseCards ? Array(snapshot.reversed()) : snapshot
    }

    func setCards(_ cards: [DashboardCardDescriptor]) { contributedCards = cards }

    var allCardReadsFinished: Bool { finishedCardReads == cardReadCount }

    func capability(_ capability: Capability) -> CapabilityPort? {
        guard capability != missing else { return nil }
        return switch capability {
        case .glucoseSource: .glucoseSource(glucose)
        case .insulinSource: hasInsulin ? .insulinSource(insulin) : nil
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
        deactivationCount += 1
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
    var readings: AsyncStream<GlucoseSample> { AsyncStream { _ in } }
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
    var status: AsyncStream<PumpStatusSnapshot> { AsyncStream { _ in } }
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
/// Holds every card read until released, standing in for a Driver that never answers.
private actor HostCardHang {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func hang() async {
        if released { return }
        for waiter in enteredWaiters { waiter.resume() }
        enteredWaiters.removeAll()
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        if !waiters.isEmpty { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

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
    var insulinOnBoard: AsyncStream<InsulinOnBoardSample> { AsyncStream { _ in } }
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
    private let glucoseReadGate: HostReadGate?
    private(set) var activationCount = 0
    private var glucose = AsyncStream<GlucoseSample>.makeStream()
    private var insulin = AsyncStream<InsulinOnBoardSample>.makeStream()
    private var pump = AsyncStream<PumpStatusSnapshot>.makeStream()

    init(deactivationGate: HostDeactivationGate? = nil, glucoseReadGate: HostReadGate? = nil) {
        self.deactivationGate = deactivationGate
        self.glucoseReadGate = glucoseReadGate
    }

    func capability(_ capability: Capability) -> CapabilityPort? {
        switch capability {
        case .glucoseSource: .glucoseSource(StreamGlucosePort(readings: glucose.stream, gate: glucoseReadGate))
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

    /// Ends the current glucose stream without deactivating, and gives the
    /// next connection a fresh one.
    func endGlucoseStream() {
        glucose.continuation.finish()
        glucose = AsyncStream.makeStream()
    }

    func emit(_ sample: GlucoseSample) { glucose.continuation.yield(sample) }
    func emit(_ sample: InsulinOnBoardSample) { insulin.continuation.yield(sample) }
    func emit(_ status: PumpStatusSnapshot) { pump.continuation.yield(status) }
}

private struct StreamGlucosePort: GlucoseSource {
    let readings: AsyncStream<GlucoseSample>
    var gate: HostReadGate?
    func latestReading() async throws(DriverFailure) -> GlucoseSample? {
        await gate?.holdIfArmed()
        return nil
    }
}

private struct StreamInsulinPort: InsulinSource {
    let insulinOnBoard: AsyncStream<InsulinOnBoardSample>
    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord] { [] }
}

private struct StreamPumpPort: PumpStatusSource {
    let status: AsyncStream<PumpStatusSnapshot>
    func latestStatus() async throws(DriverFailure) -> PumpStatusSnapshot? { nil }
}
