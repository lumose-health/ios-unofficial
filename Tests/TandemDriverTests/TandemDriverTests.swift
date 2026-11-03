import Testing
import DriverAPI
import SafetyCore
@testable import TandemDriver

@Test func descriptorMatchesCatalogAndRemainsUnverified() async throws {
    let driver = TandemDriver(clock: ManualClock(), scheduler: ManualScheduler())
    let catalog = try #require(DriverCatalog.entry(for: TandemDriver.identifier))
    #expect(driver.descriptor == catalog)
    #expect(driver.descriptor.verification == .unverified)
    #expect(driver.descriptor.verification != .hardwareVerified)
    for capability in Capability.allCases {
        switch driver.capability(capability) {
        case nil: #expect(true)
        case .some: Issue.record("Tandem must not expose a capability before pairing")
        }
    }
    do {
        try await driver.activate()
        Issue.record("Activation should fail before pairing")
    } catch {
        #expect(error == .notPaired)
    }
    await driver.deactivate(); await driver.deactivate()
}

@Test func deactivateStopsOnlyAnActiveScan() async {
    let central = FakeCentral(), scheduler = ManualScheduler()
    let driver = TandemDriver(makeCentral: { central }, clock: ManualClock(), scheduler: scheduler)
    await driver.deactivate()
    #expect(await driver.discovery.currentSnapshot().state == .idle)
    #expect(central.stopCount == 0)

    await driver.discovery.startScan()
    central.send(.radioStateChanged(.poweredOn))
    await eventually { await driver.discovery.currentSnapshot().state == .scanning }
    await driver.deactivate()
    #expect(await driver.discovery.currentSnapshot().state == .stopped(.user))
    #expect(central.stopCount == 1)
    #expect(scheduler.liveCount == 0)
    await driver.deactivate()
    #expect(central.stopCount == 1)
}

@Test func deactivateLeavesABlockedScanReported() async {
    let central = FakeCentral()
    let driver = TandemDriver(makeCentral: { central }, clock: ManualClock(), scheduler: ManualScheduler())
    await driver.discovery.startScan()
    central.send(.radioStateChanged(.poweredOff))
    await eventually { await driver.discovery.currentSnapshot().state == .blocked(.poweredOff) }
    await driver.deactivate()
    #expect(await driver.discovery.currentSnapshot().state == .blocked(.poweredOff))
}

@Test func deactivateCancelsAScanWaitingForTheRadio() async {
    let central = FakeCentral()
    let driver = TandemDriver(makeCentral: { central }, clock: ManualClock(), scheduler: ManualScheduler())
    await driver.discovery.startScan()
    await driver.deactivate()
    #expect(await driver.discovery.currentSnapshot().state == .stopped(.user))
    #expect(central.startCalls.isEmpty)
}
