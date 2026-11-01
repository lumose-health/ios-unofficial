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
    public var failed: [RestoreFailure] = []
    /// Persisted claimants skipped because a lower id already holds the slot.
    public var removedConflicts: [DriverIdentifier] = []
    /// Skipped claimants and failed ids that are still persisted because the save failed.
    public var unremoved: [DriverIdentifier] = []
    public var selectionFailure: DriverSelectionStoreFailure?
}

/// Owns lifecycle transitions and the persisted active selection.
public actor DriverRegistry {
    private let drivers: [DriverIdentifier: any Driver]
    private let descriptors: [DriverDescriptor]
    private let store: any DriverSelectionStore
    private var persisted: Set<String>
    private var loadFailure: DriverSelectionStoreFailure?
    private var lifecycles: [DriverIdentifier: DriverLifecycle]
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var onEnqueue: (@Sendable () -> Void)?
    private var transitionFault: (@Sendable (DriverIdentifier, DriverLifecycleState) -> DriverFailure?)?

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
            self.persisted = try store.load()
            self.loadFailure = nil
        } catch {
            self.persisted = []
            self.loadFailure = error
        }
    }

    public var slots: DriverSlots {
        let known = Set(drivers.keys.filter { persisted.contains($0.rawValue) })
        return DriverSlots.derive(active: known, descriptors: descriptors)
    }

    public var persistedSelection: Set<String> { persisted }

    public func lifecycleState(of id: DriverIdentifier) -> DriverLifecycleState? {
        lifecycles[id]?.state
    }

    /// Test seam: called each time an operation queues behind a running one.
    func setEnqueueHook(_ hook: (@Sendable () -> Void)?) { onEnqueue = hook }

    /// Test seam: a non-nil result makes that lifecycle transition fail.
    func setTransitionFault(_ fault: (@Sendable (DriverIdentifier, DriverLifecycleState) -> DriverFailure?)?) {
        transitionFault = fault
    }

    private func enter() async {
        if !isBusy { isBusy = true; return }
        await withCheckedContinuation {
            waiters.append($0)
            onEnqueue?()
        }
    }

    private func leave() {
        if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
    }

    private func advance(_ id: DriverIdentifier, to next: DriverLifecycleState) throws(DriverRegistryError) {
        guard var lifecycle = lifecycles[id] else { throw .unknownDriver(id) }
        if let fault = transitionFault?(id, next) { throw .lifecycle(fault) }
        do { try lifecycle.advance(to: next) }
        catch { throw .lifecycle(error) }
        lifecycles[id] = lifecycle
    }

    private func save(_ ids: Set<String>) throws(DriverRegistryError) {
        do { try store.save(ids) }
        catch { throw .persistenceFailed(error) }
        persisted = ids
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
        if let state = lifecycles[id]?.state, state == .active || state == .degraded { return [] }
        let incoming = driver.descriptor.capabilities.filter { $0.cardinality == .singleInstance }
        let conflicts = descriptors.filter {
            $0.identifier != id && persisted.contains($0.identifier.rawValue) &&
                !$0.capabilities.isDisjoint(with: incoming)
        }.map(\.identifier).sorted { $0.rawValue < $1.rawValue }
        try advance(id, to: .activating)
        do { try await driver.activate() }
        catch {
            try advance(id, to: .failed)
            if persisted.contains(id.rawValue) { try? save(persisted.subtracting([id.rawValue])) }
            throw .activationFailed(id, error)
        }
        try advance(id, to: .active)
        // One write: the incoming Driver replaces every conflict, so no persisted
        // state ever holds both, and a failed write leaves the incumbents in place.
        let selection = persisted.union([id.rawValue]).subtracting(conflicts.map(\.rawValue))
        if selection != persisted {
            do { try save(selection) }
            catch {
                try advance(id, to: .deactivating)
                await driver.deactivate()
                try advance(id, to: .notActivated)
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
    /// capability is already held by a running or lower restored Driver is not started;
    /// it is removed from the selection with the failed ids in one save.
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
                report.failed.append(RestoreFailure(id: id, failure: error))
                dropped.append(id)
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
