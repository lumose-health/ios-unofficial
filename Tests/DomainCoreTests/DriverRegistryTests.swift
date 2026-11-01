import Foundation
import Testing
import DriverAPI
@testable import DomainCore

@Suite("Driver registry")
struct DriverRegistryTests {
    private let pump: Set<Capability> = [.glucoseSource, .insulinSource, .pumpStatus]
    private var alphaID: DriverIdentifier { DriverIdentifier("test.pump.alpha")! }
    private var bravoID: DriverIdentifier { DriverIdentifier("test.pump.bravo")! }

    @Test func swapKeepsSlotOccupied() async throws {
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let b = TestDriver(id: "test.pump.bravo", capabilities: pump)
        let store = RecordingSelectionStore()
        let registry = try DriverRegistry(drivers: [a, b], store: store)
        try await registry.activate(alphaID)
        await b.setActivationHook {
            let slots = await registry.slots
            #expect(slots.holder(of: .glucoseSource) == a.descriptor.identifier)
        }
        let savesBefore = store.savedSets.count
        let evicted = try await registry.activate(bravoID)
        #expect(evicted == [alphaID])
        #expect(Array(store.savedSets.dropFirst(savesBefore)) == [[bravoID.rawValue]])
        #expect(await registry.slots.holder(of: .glucoseSource) == bravoID)
        #expect(await a.deactivateCount == 1)
        #expect(await registry.persistedSelection == [bravoID.rawValue])
        for selection in store.savedSets {
            let active = Set(selection.compactMap(DriverIdentifier.init))
            let slots = DriverSlots.derive(active: active, descriptors: [a.descriptor, b.descriptor])
            #expect(slots.holder(of: .glucoseSource) != nil)
        }
    }

    @Test func oneActivationEvictsSeveralHolders() async throws {
        let c = TestDriver(id: "test.cgm.charlie", capabilities: [.glucoseSource])
        let d = TestDriver(id: "test.status.delta", capabilities: [.pumpStatus])
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let registry = try DriverRegistry(drivers: [c, d, a], store: RecordingSelectionStore())
        try await registry.activate(c.descriptor.identifier)
        try await registry.activate(d.descriptor.identifier)
        #expect(try await registry.activate(alphaID) == [c.descriptor.identifier, d.descriptor.identifier])
        #expect(await c.deactivateCount == 1)
        #expect(await d.deactivateCount == 1)
    }

    @Test func activationIsIdempotentAndUnknownFails() async throws {
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let store = RecordingSelectionStore()
        let registry = try DriverRegistry(drivers: [a], store: store)
        try await registry.activate(alphaID)
        let saves = store.savedSets
        #expect(try await registry.activate(alphaID).isEmpty)
        #expect(await a.activateCount == 1)
        #expect(store.savedSets == saves)
        do { try await registry.activate(DriverIdentifier("test.unknown")!); Issue.record("unknown Driver activated") }
        catch { #expect(error == .unknownDriver(DriverIdentifier("test.unknown")!)) }
        #expect(store.savedSets == saves)
    }

    @Test func hookFailureRetainsIncumbent() async throws {
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let b = TestDriver(id: "test.pump.bravo", capabilities: pump)
        let store = RecordingSelectionStore()
        let registry = try DriverRegistry(drivers: [a, b], store: store)
        try await registry.activate(alphaID)
        let saves = store.savedSets
        await b.setFailure(.transportUnavailable)
        do { try await registry.activate(bravoID); Issue.record("hook failure was ignored") }
        catch { #expect(error == .activationFailed(bravoID, .transportUnavailable)) }
        #expect(await registry.lifecycleState(of: bravoID) == .failed)
        #expect(await registry.slots.holder(of: .glucoseSource) == alphaID)
        #expect(store.savedSets == saves)
        #expect(await a.deactivateCount == 0)
    }

    @Test func saveFailureTearsDownIncoming() async throws {
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let b = TestDriver(id: "test.pump.bravo", capabilities: pump)
        let store = RecordingSelectionStore()
        let registry = try DriverRegistry(drivers: [a, b], store: store)
        try await registry.activate(alphaID)
        store.saveFailure = .unwritable(detail: "injected")
        do { try await registry.activate(bravoID); Issue.record("save failure was ignored") }
        catch { #expect(error == .persistenceFailed(.unwritable(detail: "injected"))) }
        #expect(await b.deactivateCount == 1)
        #expect(await registry.lifecycleState(of: bravoID) == .notActivated)
        #expect(await registry.slots.holder(of: .glucoseSource) == alphaID)
    }

    @Test func saveFailureDuringEvictionKeepsIncumbentOnly() async throws {
        let c = TestDriver(id: "test.cgm.charlie", capabilities: [.glucoseSource])
        let d = TestDriver(id: "test.status.delta", capabilities: [.pumpStatus])
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let store = RecordingSelectionStore()
        let registry = try DriverRegistry(drivers: [c, d, a], store: store)
        try await registry.activate(c.descriptor.identifier)
        try await registry.activate(d.descriptor.identifier)
        let before = store.current
        store.saveFailure = .unwritable(detail: "injected")
        do { try await registry.activate(alphaID); Issue.record("save failure was ignored") }
        catch { #expect(error == .persistenceFailed(.unwritable(detail: "injected"))) }
        #expect(await a.deactivateCount == 1)
        #expect(await registry.lifecycleState(of: alphaID) == .notActivated)
        #expect(await c.deactivateCount == 0)
        #expect(await d.deactivateCount == 0)
        #expect(await registry.lifecycleState(of: c.descriptor.identifier) == .active)
        #expect(await registry.lifecycleState(of: d.descriptor.identifier) == .active)
        #expect(store.current == before)
        #expect(await registry.persistedSelection == before)
    }

    @Test func failedConflictTeardownStillEvictsTheRest() async throws {
        let c = TestDriver(id: "test.cgm.charlie", capabilities: [.glucoseSource])
        let d = TestDriver(id: "test.status.delta", capabilities: [.pumpStatus])
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let store = RecordingSelectionStore()
        let registry = try DriverRegistry(drivers: [c, d, a], store: store)
        try await registry.activate(c.descriptor.identifier)
        try await registry.activate(d.descriptor.identifier)
        let charlie = c.descriptor.identifier
        await registry.setTransitionFault { id, next in
            id == charlie && next == .deactivating ? .cancelled : nil
        }
        do { try await registry.activate(alphaID); Issue.record("teardown failure was ignored") }
        catch {
            #expect(error == .evictionIncomplete(evicted: [charlie, d.descriptor.identifier],
                                                 failedToDeactivate: [charlie: .cancelled]))
        }
        #expect(await d.deactivateCount == 1)
        #expect(await registry.lifecycleState(of: d.descriptor.identifier) == .notActivated)
        #expect(await registry.lifecycleState(of: alphaID) == .active)
        #expect(store.current == [alphaID.rawValue])
        #expect(await registry.slots.glucose == alphaID)
    }

    @Test func multiInstanceDriversCoexist() async throws {
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let b1 = TestDriver(id: "test.bgm.one", capabilities: [.bgmSource])
        let b2 = TestDriver(id: "test.bgm.two", capabilities: [.bgmSource])
        let sync = TestDriver(id: "test.sync.one", capabilities: [.dataSync])
        let registry = try DriverRegistry(drivers: [a, b1, b2, sync], store: RecordingSelectionStore())
        for driver in [a, b1, b2, sync] { #expect(try await registry.activate(driver.descriptor.identifier).isEmpty) }
        let slots = await registry.slots
        #expect(slots.pump == alphaID && slots.glucose == alphaID)
        #expect(slots.members(of: .bgmSource) == [b1.descriptor.identifier, b2.descriptor.identifier])
        try await registry.deactivate(b1.descriptor.identifier)
        #expect(await registry.slots.members(of: .bgmSource) == [b2.descriptor.identifier])
    }

    @Test func deactivateSavesBeforeHookAndIsIdempotent() async throws {
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let store = RecordingSelectionStore()
        let registry = try DriverRegistry(drivers: [a], store: store)
        try await registry.activate(alphaID)
        await a.setDeactivationHook { #expect(store.current.isEmpty) }
        try await registry.deactivate(alphaID)
        let saves = store.savedSets
        try await registry.deactivate(alphaID)
        #expect(store.savedSets == saves)
        #expect(await a.deactivateCount == 1)
    }

    @Test func operationsAreSerializedAndNewClaimSurvives() async throws {
        let entered = Gate()
        let release = Gate()
        let queued = Gate()
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let b = TestDriver(id: "test.pump.bravo", capabilities: pump)
        let registry = try DriverRegistry(drivers: [a, b], store: RecordingSelectionStore())
        try await registry.activate(alphaID)
        await b.setActivationHook { await entered.open(); await release.wait() }
        await registry.setEnqueueHook { Task { await queued.open() } }
        let activation = Task { try await registry.activate(bravoID) }
        await entered.wait()
        let deactivation = Task { try await registry.deactivate(alphaID) }
        await queued.wait()
        #expect(await a.deactivateCount == 0)
        #expect(await registry.slots.holder(of: .glucoseSource) == alphaID)
        await release.open()
        #expect(try await activation.value == [alphaID])
        try await deactivation.value
        #expect(await a.deactivateCount == 1)
        #expect(await registry.lifecycleState(of: bravoID) == .active)
        #expect(await registry.persistedSelection == [bravoID.rawValue])
    }

    @Test func secondActivationWaitsForFirstHook() async throws {
        let entered = Gate()
        let release = Gate()
        let secondStarted = Gate()
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let c = TestDriver(id: "test.cgm.charlie", capabilities: [.glucoseSource])
        let registry = try DriverRegistry(drivers: [a, c], store: RecordingSelectionStore())
        await a.setActivationHook { await entered.open(); await release.wait() }
        let first = Task { try await registry.activate(alphaID) }
        await entered.wait()
        let second = Task {
            await secondStarted.open()
            return try await registry.activate(c.descriptor.identifier)
        }
        await secondStarted.wait()
        #expect(await c.activateCount == 0)
        #expect(await registry.lifecycleState(of: alphaID) == .activating)
        await release.open()
        _ = try await first.value
        _ = try await second.value
        #expect(await c.activateCount == 1)
    }

    @Test func duplicateIdentifiersFailAtInit() {
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        do { _ = try DriverRegistry(drivers: [a, a], store: RecordingSelectionStore()); Issue.record("duplicate accepted") }
        catch { #expect(error == .duplicateIdentifier(alphaID)) }
    }

    @Test func relaunchRestoresSelectionAndPersistsDeactivation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selection.json")
        let first = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let registry1 = try DriverRegistry(drivers: [first], store: FileDriverSelectionStore(fileURL: url))
        try await registry1.activate(alphaID)
        #expect(try FileDriverSelectionStore(fileURL: url).load() == [alphaID.rawValue])
        let second = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let registry2 = try DriverRegistry(drivers: [second], store: FileDriverSelectionStore(fileURL: url))
        #expect(await registry2.slots.glucose == alphaID)
        let report = await registry2.restore()
        #expect(report.restored == [alphaID])
        #expect(await second.activateCount == 1)
        _ = await registry2.restore()
        #expect(await second.activateCount == 1)
        try await registry2.deactivate(alphaID)
        #expect(try FileDriverSelectionStore(fileURL: url).load().isEmpty)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == "{\"activeDriverIDs\":[],\"version\":1}")
    }

    @Test func absentDriverSurvivesLaterSaves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("selection.json")
        let store = FileDriverSelectionStore(fileURL: url)
        try store.save(["test.absent.old"])
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let registry = try DriverRegistry(drivers: [a], store: store)
        #expect(await registry.restore().absentFromBuild == ["test.absent.old"])
        try await registry.activate(alphaID)
        try await registry.deactivate(alphaID)
        #expect(try FileDriverSelectionStore(fileURL: url).load() == ["test.absent.old"])
    }

    @Test func failedRestoreRemovesSelection() async throws {
        let store = RecordingSelectionStore([alphaID.rawValue])
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        await a.setFailure(.transportUnavailable)
        let registry = try DriverRegistry(drivers: [a], store: store)
        let report = await registry.restore()
        #expect(report.failed == [RestoreFailure(id: alphaID, failure: .transportUnavailable)])
        #expect(store.current.isEmpty)
        #expect(await registry.lifecycleState(of: alphaID) == .failed)
        #expect(await registry.slots.glucose == nil)
    }

    @Test func staleSelectionIsRemovedAfterHookFailure() async throws {
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        await a.setFailure(.transportUnavailable)
        let store = RecordingSelectionStore([alphaID.rawValue])
        let registry = try DriverRegistry(drivers: [a], store: store)
        do { try await registry.activate(alphaID); Issue.record("hook failure was ignored") }
        catch { #expect(error == .activationFailed(alphaID, .transportUnavailable)) }
        #expect(store.current.isEmpty)
        #expect(await registry.lifecycleState(of: alphaID) == .failed)
    }

    @Test func restoreRemovesCompetingClaim() async throws {
        let store = RecordingSelectionStore([alphaID.rawValue, bravoID.rawValue])
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let b = TestDriver(id: "test.pump.bravo", capabilities: pump)
        let registry = try DriverRegistry(drivers: [b, a], store: store)
        let report = await registry.restore()
        #expect(report.removedConflicts == [bravoID])
        #expect(report.restored == [alphaID])
        #expect(store.current == [alphaID.rawValue])
        #expect(await b.activateCount == 0)
        #expect(await b.deactivateCount == 0)
        #expect(await registry.slots.glucose == alphaID)
    }

    @Test func restoreFallsToNextClaimantWhenWinnerFails() async throws {
        let store = RecordingSelectionStore([alphaID.rawValue, bravoID.rawValue])
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let b = TestDriver(id: "test.pump.bravo", capabilities: pump)
        await a.setFailure(.transportUnavailable)
        let registry = try DriverRegistry(drivers: [a, b], store: store)
        let report = await registry.restore()
        #expect(report.failed == [RestoreFailure(id: alphaID, failure: .transportUnavailable)])
        #expect(report.restored == [bravoID])
        #expect(report.removedConflicts.isEmpty)
        #expect(store.current == [bravoID.rawValue])
        #expect(await b.activateCount == 1)
        #expect(await registry.slots.glucose == bravoID)
    }

    @Test func restoreReportsConflictRemovalFailure() async throws {
        let store = RecordingSelectionStore([alphaID.rawValue, bravoID.rawValue])
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let b = TestDriver(id: "test.pump.bravo", capabilities: pump)
        let registry = try DriverRegistry(drivers: [a, b], store: store)
        store.saveFailure = .unwritable(detail: "injected")
        let report = await registry.restore()
        #expect(report.selectionFailure == .unwritable(detail: "injected"))
        #expect(report.unremoved == [bravoID])
        #expect(await b.activateCount == 0)
    }

    @Test func restoreRetriesTransientLoadFailure() async throws {
        let store = RecordingSelectionStore([alphaID.rawValue])
        store.loadFailure = .unavailable(detail: "locked")
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let registry = try DriverRegistry(drivers: [a], store: store)
        #expect(await registry.persistedSelection.isEmpty)
        store.loadFailure = nil
        let report = await registry.restore()
        #expect(report.selectionFailure == nil)
        #expect(report.restored == [alphaID])
        #expect(store.savedSets.isEmpty)
    }

    @Test func restoreDoesNotRetryUnreadableSelection() async throws {
        let store = RecordingSelectionStore([alphaID.rawValue])
        store.loadFailure = .unreadable(detail: "garbage")
        let a = TestDriver(id: "test.pump.alpha", capabilities: pump)
        let registry = try DriverRegistry(drivers: [a], store: store)
        store.loadFailure = nil
        #expect(await registry.restore().selectionFailure == .unreadable(detail: "garbage"))
        #expect(await a.activateCount == 0)
        #expect(store.savedSets.isEmpty)
    }

    @Test func unreadableSelectionCannotBeOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("selection.json")
        let original = Data("garbage".utf8)
        try original.write(to: url)
        let registry = try DriverRegistry(drivers: [TestDriver(id: "test.pump.alpha", capabilities: pump)],
                                          store: FileDriverSelectionStore(fileURL: url))
        #expect(await registry.restore().selectionFailure != nil)
        do { try await registry.activate(alphaID); Issue.record("unreadable selection accepted") }
        catch { if case .selectionUnavailable = error {} else { Issue.record("wrong error: \(error)") } }
        do { try await registry.deactivate(alphaID); Issue.record("unreadable selection accepted") }
        catch { if case .selectionUnavailable = error {} else { Issue.record("wrong error: \(error)") } }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func newerSelectionCannotBeOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("selection.json")
        let original = Data("{\"activeDriverIDs\":[\"test.pump.alpha\"],\"version\":2}".utf8)
        try original.write(to: url)
        let registry = try DriverRegistry(drivers: [TestDriver(id: "test.pump.alpha", capabilities: pump)],
                                          store: FileDriverSelectionStore(fileURL: url))
        #expect(await registry.restore().selectionFailure == .unsupportedVersion(2))
        do { try await registry.activate(alphaID); Issue.record("newer format accepted") }
        catch { #expect(error == .selectionUnavailable(.unsupportedVersion(2))) }
        #expect(try Data(contentsOf: url) == original)
    }
}
