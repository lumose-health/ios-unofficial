import Foundation
import Testing
import DriverAPI
import DomainCore
import AppFeature

@Suite("Drivers screen")
struct DriversScreenTests {
    @Test func allMetadataAndLifecycleLabelsAreLiteral() {
        let states: [(DriverLifecycleState, String)] = [
            (.notActivated, "Inactive"), (.activating, "Starting…"), (.active, "Active"),
            (.degraded, "Running with problems"), (.deactivating, "Stopping…"), (.failed, "Failed to start")
        ]
        let transports: [(DriverTransport, String)] = [
            (.bluetoothLowEnergy, "Bluetooth"), (.network, "Network"), (.inProcess, "On device")
        ]
        let verifications: [(VerificationStatus, String)] = [
            (.unverified, "Unverified"),
            (.protocolCompatible, "Protocol-compatible (unverified on hardware)"),
            (.beta, "Beta"), (.hardwareVerified, "Verified on hardware")
        ]
        for (state, text) in states {
            let row = DriverRowState(row: DriverRow(descriptor: descriptor(), state: state),
                                     isSelected: false, isBusy: false, errorMessage: nil)
            #expect(row.stateText == text)
        }
        for (transport, text) in transports {
            let row = DriverRowState(row: DriverRow(descriptor: descriptor(transport: transport), state: .active),
                                     isSelected: true, isBusy: false, errorMessage: nil)
            #expect(row.transportText == text)
        }
        for (verification, text) in verifications {
            let row = DriverRowState(row: DriverRow(descriptor: descriptor(verification: verification), state: .active),
                                     isSelected: true, isBusy: false, errorMessage: nil)
            #expect(row.verificationText == text)
        }
    }

    private func descriptor(transport: DriverTransport = .inProcess,
                            verification: VerificationStatus = .unverified) -> DriverDescriptor {
        DriverDescriptor(identifier: DriverIdentifier("test.screen.labels")!, targetName: "ScreenTestDriver",
                         displayName: "Labels", transport: transport, version: "1.0.0",
                         capabilities: [], verification: verification)
    }

    @Test @MainActor func rowsAndConfirmationFollowRegistry() async throws {
        let first = ScreenTestDriver(id: "test.screen.first", name: "First Driver",
                                     capabilities: [.glucoseSource, .insulinSource], verification: .beta)
        let second = ScreenTestDriver(id: "test.screen.second", name: "Second Driver",
                                      capabilities: [.dataSync], verification: .protocolCompatible)
        let registry = try DriverRegistry(drivers: [first, second], store: ScreenSelectionStore())
        let model = DriversModel(registry: registry)
        #expect(model.rows.map(\.row.name) == ["First Driver", "Second Driver"])
        #expect(await screenEventually { model.rows.first?.stateText == "Inactive" })
        #expect(model.rows[0].verificationText == "Beta")
        #expect(model.rows[1].verificationText == "Protocol-compatible (unverified on hardware)")
        #expect(model.rows[0].transportText == "On device")

        try await registry.activate(first.descriptor.id)
        #expect(await screenEventually { model.rows[0].isSelected && model.rows[0].stateText == "Active" })
        model.requestDeactivation(first.descriptor.id)
        #expect(await first.deactivationCount == 0)
        #expect(await registry.persistedSelection == [first.descriptor.id.rawValue])
        let prompt = try #require(model.pendingDeactivation)
        #expect(prompt.title == "Deactivate Driver")
        #expect(prompt.confirmLabel == "Deactivate")
        #expect(prompt.cancelLabel == "Cancel")
        #expect(prompt.message == "Deactivating this Driver may stop glucose monitoring, insulin tracking, or other services it provides. Are you sure?\n\nFirst Driver provides: glucose readings, insulin on board and dose history.\nIts settings are kept.")
        model.cancelDeactivation()
        #expect(model.pendingDeactivation == nil)
        #expect(await first.deactivationCount == 0)
        model.requestDeactivation(first.descriptor.id)
        await model.confirmDeactivation()
        #expect(await first.deactivationCount == 1)
        #expect(model.rows[0].isSelected == false)
        await model.activate(first.descriptor.id)
        #expect(model.rows[0].isSelected)
        #expect(await first.activationCount == 2)
    }

    @Test @MainActor func activationFailureIsInline() async throws {
        let driver = ScreenTestDriver(id: "test.screen.failing", name: "Failing Driver",
                                      capabilities: [], verification: .unverified, failure: .transportUnavailable)
        let registry = try DriverRegistry(drivers: [driver], store: ScreenSelectionStore())
        let model = DriversModel(registry: registry)
        await model.activate(driver.descriptor.id)
        #expect(model.rows[0].errorMessage == "Couldn't activate Failing Driver.\nIt didn't start. Try again.")
        #expect(!model.rows[0].isSelected)
    }

    @Test @MainActor func swapShowsBusyLabelsAndLocksTheEvictedRow() async throws {
        let gate = ScreenGate()
        let first = ScreenTestDriver(id: "test.screen.current", name: "Current", capabilities: [.glucoseSource],
                                     verification: .beta)
        let second = ScreenTestDriver(id: "test.screen.next", name: "Next", capabilities: [.glucoseSource],
                                      verification: .beta, activationGate: gate)
        let registry = try DriverRegistry(drivers: [first, second], store: ScreenSelectionStore())
        let model = DriversModel(registry: registry)
        try await registry.activate(first.descriptor.id)
        #expect(await screenEventually { model.rows[0].isSelected && model.rows[0].stateText == "Active" })

        let swap = Task { await model.activate(second.descriptor.id) }
        await gate.waitUntilEntered()
        #expect(model.rows[1].stateText == "Starting…")
        #expect(model.rows[1].busyLabel == "Starting…")
        #expect(!model.rows[1].canActivate)
        #expect(model.rows[0].stateText == "Stopping…")
        #expect(!model.rows[0].canActivate)
        #expect(!model.rows[0].canDeactivate)
        await model.activate(first.descriptor.id)
        #expect(await first.activationCount == 1)

        await gate.release()
        await swap.value
        #expect(model.rows[1].isSelected && model.rows[1].stateText == "Active")
        #expect(!model.rows[0].isSelected && model.rows[0].stateText == "Inactive")
        #expect(model.rows[0].canActivate)
    }

    @Test @MainActor func unreadableSelectionIsSaidAndBlocksActions() async throws {
        let driver = ScreenTestDriver(id: "test.screen.locked", name: "Locked", capabilities: [.glucoseSource],
                                      verification: .beta)
        let store = ScreenSelectionStore(loadFailure: .unavailable(detail: "protected data unavailable"))
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let model = DriversModel(registry: registry)
        #expect(await screenEventually {
            model.selectionNotice == "Your driver selection can't be read until the phone is unlocked"
        })
        #expect(model.rows.allSatisfy { !$0.canActivate && !$0.canDeactivate })
        await model.activate(driver.descriptor.id)
        #expect(await driver.activationCount == 0)
    }
}

private actor ScreenTestDriver: Driver {
    nonisolated let descriptor: DriverDescriptor
    private let failure: DriverFailure?
    private let activationGate: ScreenGate?
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0

    init(id: String, name: String, capabilities: Set<Capability>, verification: VerificationStatus,
         failure: DriverFailure? = nil, activationGate: ScreenGate? = nil) {
        descriptor = DriverDescriptor(identifier: DriverIdentifier(id)!, targetName: "ScreenTestDriver",
                                      displayName: name, transport: .inProcess, version: "1.0.0",
                                      capabilities: capabilities, verification: verification)
        self.failure = failure
        self.activationGate = activationGate
    }
    func capability(_ capability: Capability) -> CapabilityPort? { nil }
    func activate() async throws(DriverFailure) {
        activationCount += 1
        await activationGate?.enter()
        if let failure { throw failure }
    }
    func deactivate() async { deactivationCount += 1 }
}

private final class ScreenSelectionStore: DriverSelectionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String> = []
    private let loadFailure: DriverSelectionStoreFailure?
    init(loadFailure: DriverSelectionStoreFailure? = nil) { self.loadFailure = loadFailure }
    func hasSavedSelection() -> Bool { true }
    func load() throws(DriverSelectionStoreFailure) -> Set<String> {
        if let loadFailure { throw loadFailure }
        lock.lock(); defer { lock.unlock() }; return ids
    }
    func save(_ ids: Set<String>) throws(DriverSelectionStoreFailure) {
        lock.lock(); defer { lock.unlock() }; self.ids = ids
    }
}

/// Holds the first `enter()` until `release()`.
private actor ScreenGate {
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

@MainActor private func screenEventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}
