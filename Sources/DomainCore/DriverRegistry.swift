import Foundation
@_spi(DriverPlatform) import DriverAPI

public enum DriverRegistryError: Error, Hashable, Sendable {
    case duplicateIdentifier(DriverIdentifier)
    case unknownDriver(DriverIdentifier)
    case activationFailed(DriverIdentifier, DriverFailure)
    case selectionUnavailable(DriverSelectionStoreFailure)
    case persistenceFailed(DriverSelectionStoreFailure)
    case lifecycle(DriverFailure)
    /// The incoming Driver is active and is the only persisted claimant, but the
    /// listed evicted Drivers did not reach `notActivated`.
    case evictionIncomplete(evicted: [DriverIdentifier], failedToDeactivate: [DriverIdentifier: DriverFailure])
    /// The selection write failed and the incoming Driver could not be torn down, so it
    /// is still live although the persisted selection does not name it.
    case persistenceFailedDriverStillLive(DriverSelectionStoreFailure, live: DriverIdentifier)
}

public struct RestoreFailure: Equatable, Sendable {
    public let id: DriverIdentifier
    public let failure: DriverFailure

    public init(id: DriverIdentifier, failure: DriverFailure) {
        self.id = id
        self.failure = failure
    }
}

public struct RestoreReport: Equatable, Sendable {
    public var restored: [DriverIdentifier] = []
    public var absentFromBuild: [String] = []
    /// Drivers whose start failed permanently; their selection was cleared.
    public var failed: [RestoreFailure] = []
    /// Drivers whose start failed transiently (see ``DriverFailure/isTransient``).
    /// Their selection stays persisted and they stay out of `active`; a later
    /// `restore()` starts them again. They keep their slot claim, so no other
    /// persisted claimant is started in their place.
    public var deferred: [RestoreFailure] = []
    /// Persisted claimants skipped because a lower id already holds the slot.
    public var removedConflicts: [DriverIdentifier] = []
    /// Skipped claimants and failed ids that are still persisted because the save failed.
    public var unremoved: [DriverIdentifier] = []
    public var selectionFailure: DriverSelectionStoreFailure?
}

/// Owns lifecycle transitions and the persisted active selection.
public actor DriverRegistry {
    private let drivers: [DriverIdentifier: any Driver]
    public nonisolated let descriptors: [DriverDescriptor]
    public nonisolated let initialSlots: DriverSlots
    private let store: any DriverSelectionStore
    private var persisted: Set<String>
    private var loadFailure: DriverSelectionStoreFailure?
    private var lifecycles: [DriverIdentifier: DriverLifecycle]
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
    #if DEBUG
    private var onEnqueue: (@Sendable () -> Void)?
    private var transitionFault: (@Sendable (DriverIdentifier, DriverLifecycleState) -> DriverFailure?)?
    #endif

    public init(drivers: [any Driver], store: any DriverSelectionStore) throws(DriverRegistryError) {
        var byID: [DriverIdentifier: any Driver] = [:]
        for driver in drivers {
            let id = driver.descriptor.identifier
            guard byID[id] == nil else { throw .duplicateIdentifier(id) }
            byID[id] = driver
        }
        self.drivers = byID
        self.descriptors = drivers.map(\.descriptor)
        self.lifecycles = Dictionary(uniqueKeysWithValues: byID.keys.map { ($0, DriverLifecycle()) })
        self.store = store
        do {
            let loaded = try store.load()
            self.persisted = loaded
            self.loadFailure = nil
            let known = Set(byID.keys.filter { loaded.contains($0.rawValue) })
            self.initialSlots = DriverSlots.derive(active: known, descriptors: self.descriptors)
        } catch {
            self.persisted = []
            self.loadFailure = error
            self.initialSlots = DriverSlots.derive(active: [], descriptors: self.descriptors)
        }
    }

    /// Slots derived from the persisted selection (AD-2, AD-3), not from which
    /// Drivers are running. A persisted Driver that is not running still names its
    /// slot: one whose restore was deferred by a transient failure, or one whose
    /// removal save failed. That is a known limit; the caller compares
    /// ``lifecycleState(of:)`` to report such a slot as "not running".
    public var slots: DriverSlots {
        let known = Set(drivers.keys.filter { persisted.contains($0.rawValue) })
        return DriverSlots.derive(active: known, descriptors: descriptors)
    }

    public var persistedSelection: Set<String> { persisted }

    /// Yields after any lifecycle transition or selection save. Consecutive
    /// changes may coalesce into one element, so an observer re-reads the state
    /// it cares about rather than counting elements.
    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func notifyChanged() {
        for continuation in observers.values { continuation.yield() }
    }

    public func lifecycleState(of id: DriverIdentifier) -> DriverLifecycleState? {
        lifecycles[id]?.state
    }

    /// Reads one selected slot without waiting for lifecycle operations on other Drivers.
    public func port(for capability: Capability) async throws(CapabilityReadError) -> HeldPort {
        guard capability.cardinality == .singleInstance else { throw .notSingleInstance(capability) }
        while true {
            if Task.isCancelled { throw .cancelled }
            guard let holder = slots.holder(of: capability) else { throw .noActiveDriver(capability) }
            let state = lifecycles[holder]?.state ?? .notActivated
            guard state == .active || state == .degraded else {
                throw .holderNotRunning(holder, capability, state)
            }
            guard let driver = drivers[holder] else { throw .noActiveDriver(capability) }
            let port = await driver.capability(capability)
            if Task.isCancelled { throw .cancelled }
            let currentState = lifecycles[holder]?.state ?? .notActivated
            guard slots.holder(of: capability) == holder,
                  currentState == .active || currentState == .degraded else { continue }
            guard let port, port.capability == capability else { throw .portUnavailable(holder, capability) }
            return HeldPort(holder: holder, port: port)
        }
    }

    #if DEBUG
    /// Test seam: called each time an operation queues behind a running one.
    func setEnqueueHook(_ hook: (@Sendable () -> Void)?) { onEnqueue = hook }

    /// Test seam: a non-nil result makes that lifecycle transition fail.
    func setTransitionFault(_ fault: (@Sendable (DriverIdentifier, DriverLifecycleState) -> DriverFailure?)?) {
        transitionFault = fault
    }
    #endif

    private func enter() async {
        if !isBusy { isBusy = true; return }
        await withCheckedContinuation {
            waiters.append($0)
            #if DEBUG
            onEnqueue?()
            #endif
        }
    }

    private func leave() {
        if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
    }

    private func advance(_ id: DriverIdentifier, to next: DriverLifecycleState) throws(DriverRegistryError) {
        guard var lifecycle = lifecycles[id] else { throw .unknownDriver(id) }
        #if DEBUG
        if let fault = transitionFault?(id, next) { throw .lifecycle(fault) }
        #endif
        do { try lifecycle.advance(to: next) }
        catch { throw .lifecycle(error) }
        lifecycles[id] = lifecycle
        notifyChanged()
    }

    private func save(_ ids: Set<String>) throws(DriverRegistryError) {
        do { try store.save(ids) }
        catch { throw .persistenceFailed(error) }
        persisted = ids
        notifyChanged()
    }

    private func tearDown(_ id: DriverIdentifier) async throws(DriverRegistryError) {
        guard let driver = drivers[id], let state = lifecycles[id]?.state else { return }
        switch state {
        case .activating, .active, .degraded, .failed:
            try advance(id, to: .deactivating)
            await driver.deactivate()
            try advance(id, to: .notActivated)
        case .notActivated, .deactivating: break
        }
    }

    @discardableResult
    public func activate(_ id: DriverIdentifier) async throws(DriverRegistryError) -> [DriverIdentifier] {
        await enter()
        defer { leave() }
        guard let driver = drivers[id] else { throw .unknownDriver(id) }
        if let loadFailure { throw .selectionUnavailable(loadFailure) }
        let incoming = driver.descriptor.capabilities.filter { $0.cardinality == .singleInstance }
        // A Driver left live but unpersisted (e.g. after `.evictionIncomplete`) still
        // holds the slot, so it is evicted alongside the persisted holders.
        let conflicts = descriptors.filter {
            $0.identifier != id && !$0.capabilities.isDisjoint(with: incoming) &&
                (persisted.contains($0.identifier.rawValue) ||
                    (lifecycles[$0.identifier]?.state ?? .notActivated) != .notActivated)
        }.map(\.identifier).sorted { $0.rawValue < $1.rawValue }
        let state = lifecycles[id]?.state
        let running = state == .active || state == .degraded
        // Already running is only settled when the selection names it and nothing
        // else still holds its slot. Otherwise the hook is skipped (it already ran,
        // and `active` cannot re-enter `activating`) and the save and eviction run.
        if running && persisted.contains(id.rawValue) && conflicts.isEmpty { return [] }
        if !running {
            try advance(id, to: .activating)
            do { try await driver.activate() }
            catch {
                try advance(id, to: .failed)
                if persisted.contains(id.rawValue) { try? save(persisted.subtracting([id.rawValue])) }
                throw .activationFailed(id, error)
            }
            try advance(id, to: .active)
        }
        // One write: the incoming Driver replaces every conflict, so no persisted
        // state ever holds both, and a failed write leaves the incumbents in place.
        let selection = persisted.union([id.rawValue]).subtracting(conflicts.map(\.rawValue))
        if selection != persisted {
            do { try save(selection) }
            catch {
                // A Driver that was already running keeps running: the call leaves
                // things as it found them.
                guard case .persistenceFailed(let failure) = error, !running else { throw error }
                do { try await tearDown(id) }
                catch { throw .persistenceFailedDriverStillLive(failure, live: id) }
                throw error
            }
        }
        var failedToDeactivate: [DriverIdentifier: DriverFailure] = [:]
        for conflict in conflicts {
            do { try await tearDown(conflict) }
            catch {
                failedToDeactivate[conflict] = switch error {
                case .lifecycle(let failure): failure
                default: .illegalTransition(from: lifecycles[conflict]?.state ?? .notActivated, to: .deactivating)
                }
            }
        }
        if !failedToDeactivate.isEmpty {
            throw .evictionIncomplete(evicted: conflicts, failedToDeactivate: failedToDeactivate)
        }
        return conflicts
    }

    public func deactivate(_ id: DriverIdentifier) async throws(DriverRegistryError) {
        await enter()
        defer { leave() }
        guard drivers[id] != nil else { throw .unknownDriver(id) }
        if let loadFailure { throw .selectionUnavailable(loadFailure) }
        let state = lifecycles[id]?.state
        let running = state == .activating || state == .active || state == .degraded || state == .failed
        if !persisted.contains(id.rawValue) && !running { return }
        if persisted.contains(id.rawValue) { try save(persisted.subtracting([id.rawValue])) }
        try await tearDown(id)
    }

    /// Starts the persisted Drivers in raw-id order. A Driver whose single-instance
    /// capability is already held by a running, lower restored or lower deferred
    /// Driver is not started; it is removed from the selection with the permanently
    /// failed ids in one save.
    ///
    /// A start that fails transiently (Bluetooth off, device out of range, timeout,
    /// cancellation) does not clear the selection: the Driver stays persisted and
    /// inactive, is reported in ``RestoreReport/deferred``, and is retried by the
    /// next `restore()`. Until then it still names its slot (see ``slots``).
    public func restore() async -> RestoreReport {
        await enter()
        defer { leave() }
        var report = RestoreReport()
        if let failure = loadFailure, failure.isTransient {
            do {
                persisted = try store.load()
                loadFailure = nil
            } catch {
                loadFailure = error
            }
        }
        if let loadFailure {
            report.selectionFailure = loadFailure
            return report
        }
        var claimed: Set<Capability> = []
        for descriptor in descriptors where persisted.contains(descriptor.identifier.rawValue) {
            let state = lifecycles[descriptor.identifier]?.state
            if state == .active || state == .degraded { claimed.formUnion(singleInstance(descriptor)) }
        }
        var dropped: [DriverIdentifier] = []
        for rawID in persisted.sorted() {
            guard let id = DriverIdentifier(rawID), let driver = drivers[id] else {
                report.absentFromBuild.append(rawID)
                continue
            }
            if lifecycles[id]?.state == .active || lifecycles[id]?.state == .degraded { continue }
            let singles = singleInstance(driver.descriptor)
            let overlap = singles.intersection(claimed)
            if !overlap.isEmpty {
                report.removedConflicts.append(id)
                dropped.append(id)
                for capability in overlap.sorted(by: { $0.rawValue < $1.rawValue }) {
                    NSLog("Driver selection conflict removed: %@, %@", rawID, capability.rawValue)
                }
                continue
            }
            do {
                try advance(id, to: .activating)
                try await driver.activate()
                try advance(id, to: .active)
                report.restored.append(id)
                claimed.formUnion(singles)
            } catch let error as DriverFailure {
                try? advance(id, to: .failed)
                if error.isTransient {
                    report.deferred.append(RestoreFailure(id: id, failure: error))
                    claimed.formUnion(singles)
                } else {
                    report.failed.append(RestoreFailure(id: id, failure: error))
                    dropped.append(id)
                }
            } catch let error as DriverRegistryError {
                if case .lifecycle(let failure) = error {
                    report.failed.append(RestoreFailure(id: id, failure: failure))
                }
                dropped.append(id)
            } catch {
                dropped.append(id)
            }
        }
        if !dropped.isEmpty {
            do { try save(persisted.subtracting(dropped.map(\.rawValue))) }
            catch {
                if case .persistenceFailed(let failure) = error { report.selectionFailure = failure }
                report.unremoved = dropped
            }
        }
        return report
    }

    private func singleInstance(_ descriptor: DriverDescriptor) -> Set<Capability> {
        descriptor.capabilities.filter { $0.cardinality == .singleInstance }
    }
}
