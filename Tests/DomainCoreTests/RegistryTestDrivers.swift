import Foundation
import DriverAPI
import DomainCore

actor TestDriver: Driver {
    nonisolated let descriptor: DriverDescriptor
    private(set) var activateCount = 0
    private(set) var deactivateCount = 0
    var activationFailure: DriverFailure?
    var onActivate: (@Sendable () async -> Void)?
    var onDeactivate: (@Sendable () async -> Void)?

    init(id: String, capabilities: Set<Capability>, transport: DriverTransport = .inProcess) {
        descriptor = DriverDescriptor(identifier: DriverIdentifier(id)!, targetName: "TestDriver",
            displayName: id, transport: transport, version: "1.0.0",
            capabilities: capabilities, verification: .unverified)
    }

    func capability(_ capability: Capability) -> CapabilityPort? { nil }
    func activate() async throws(DriverFailure) {
        activateCount += 1
        if let onActivate { await onActivate() }
        if let activationFailure { throw activationFailure }
    }
    func deactivate() async {
        deactivateCount += 1
        if let onDeactivate { await onDeactivate() }
    }
    func setFailure(_ failure: DriverFailure?) { activationFailure = failure }
    func setActivationHook(_ hook: (@Sendable () async -> Void)?) { onActivate = hook }
    func setDeactivationHook(_ hook: (@Sendable () async -> Void)?) { onDeactivate = hook }
}

final class RecordingSelectionStore: DriverSelectionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<String>
    private var saves: [Set<String>] = []
    var loadFailure: DriverSelectionStoreFailure?
    var saveFailure: DriverSelectionStoreFailure?

    init(_ ids: Set<String> = []) { self.ids = ids }
    var savedSets: [Set<String>] { lock.withLock { saves } }
    var current: Set<String> { lock.withLock { ids } }

    func load() throws(DriverSelectionStoreFailure) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let loadFailure { throw loadFailure }
        return ids
    }
    func save(_ ids: Set<String>) throws(DriverSelectionStoreFailure) {
        lock.lock()
        defer { lock.unlock() }
        if let saveFailure { throw saveFailure }
        self.ids = ids
        saves.append(ids)
    }
}

actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
