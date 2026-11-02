import Foundation
import Testing
import AppFeature
import DomainCore
@_spi(DriverPlatform) import DriverAPI

@Suite("Driver startup")
struct DriverStartupTests {
    private let id = DriverIdentifier("test.startup.demo")!

    @Test func firstLaunchSeedsOnceAndLaterLaunchRestores() async throws {
        let store = StartupStore(ids: [], saved: false)
        let first = StartupDriver(id: id)
        let registry = try DriverRegistry(drivers: [first], store: store)
        let outcome = await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: id)
        #expect(outcome.seededID == id)
        #expect(outcome.seedError == nil)
        #expect(outcome.report.restored.isEmpty)
        #expect(store.savedSets == [[id.rawValue]])
        #expect(await first.activationCount == 1)

        let second = StartupDriver(id: id)
        let nextRegistry = try DriverRegistry(drivers: [second], store: store)
        let next = await DriverStartup.run(registry: nextRegistry, store: store, firstLaunchDefault: id)
        #expect(next.seededID == nil)
        #expect(next.report.restored == [id])
        #expect(store.savedSets == [[id.rawValue]])
        #expect(await second.activationCount == 1)
    }

    @Test func savedEmptySelectionStaysEmpty() async throws {
        let store = StartupStore(ids: [], saved: true)
        let driver = StartupDriver(id: id)
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let outcome = await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: id)
        #expect(outcome.seededID == nil)
        #expect(store.savedSets.isEmpty)
        #expect(await driver.activationCount == 0)
    }

    @Test func savedSelectionIsRestoredBeforeAnySeed() async throws {
        let store = StartupStore(ids: [id.rawValue], saved: true)
        let driver = StartupDriver(id: id)
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let outcome = await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: id)
        #expect(outcome.report.restored == [id])
        #expect(outcome.seededID == nil)
        #expect(store.savedSets.isEmpty)
        #expect(await driver.activationCount == 1)
    }

    @Test func unreadableSelectionNeverSeedsOrSaves() async throws {
        let store = StartupStore(ids: [], saved: false, loadFailure: .unreadable(detail: "injected"))
        let driver = StartupDriver(id: id)
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let outcome = await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: id)
        #expect(outcome.report.selectionFailure == .unreadable(detail: "injected"))
        #expect(outcome.seededID == nil)
        #expect(store.savedSets.isEmpty)
        #expect(await driver.activationCount == 0)
    }

    @Test func failedSeedIsReturnedAndNotSaved() async throws {
        let store = StartupStore(ids: [], saved: false)
        let driver = StartupDriver(id: id, failure: .authenticationRejected)
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let outcome = await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: id)
        #expect(outcome.seededID == nil)
        #expect(outcome.seedError == .activationFailed(id, .authenticationRejected))
        #expect(store.savedSets.isEmpty)
    }
}

private final class StartupStore: DriverSelectionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String>
    private var saved: Bool
    private let loadFailure: DriverSelectionStoreFailure?
    private var saves: [Set<String>] = []

    init(ids: Set<String>, saved: Bool, loadFailure: DriverSelectionStoreFailure? = nil) {
        self.ids = ids
        self.saved = saved
        self.loadFailure = loadFailure
    }
    var savedSets: [Set<String>] { lock.withLock { saves } }
    func hasSavedSelection() -> Bool { lock.withLock { saved } }
    func load() throws(DriverSelectionStoreFailure) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let loadFailure { throw loadFailure }
        return ids
    }
    func save(_ ids: Set<String>) throws(DriverSelectionStoreFailure) {
        lock.withLock {
            self.ids = ids
            saved = true
            saves.append(ids)
        }
    }
}

private actor StartupDriver: Driver {
    nonisolated let descriptor: DriverDescriptor
    private let failure: DriverFailure?
    private(set) var activationCount = 0

    init(id: DriverIdentifier, failure: DriverFailure? = nil) {
        descriptor = DriverDescriptor(identifier: id, targetName: "StartupDriver", displayName: "Startup Driver",
            transport: .inProcess, version: "1.0.0", capabilities: [.glucoseSource], verification: .unverified)
        self.failure = failure
    }
    func capability(_ capability: Capability) -> CapabilityPort? { nil }
    func activate() async throws(DriverFailure) {
        activationCount += 1
        if let failure { throw failure }
    }
    func deactivate() async {}
}
