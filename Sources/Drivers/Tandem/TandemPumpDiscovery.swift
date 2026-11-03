import Foundation
import SafetyCore

public struct DiscoveredPumpHandle: Hashable, Sendable, CustomStringConvertible {
    fileprivate let peripheralID: UUID
    fileprivate init(_ id: UUID) { peripheralID = id }
    public var description: String { "pump" }
}

public struct DiscoveredPump: Hashable, Sendable {
    public let handle: DiscoveredPumpHandle
    public let name: String
    public let model: TandemPumpModel
    public let signalStrength: Int?
    public let firstSeen: Date
    public let lastSeen: Date
}

public enum BluetoothBlockedReason: Hashable, Sendable {
    case poweredOff, permissionDenied, permissionRestricted, unsupported, resetting
}
public enum ScanStopReason: Hashable, Sendable { case user, idleTimeout, pumpSelected }
public enum ScanState: Hashable, Sendable {
    case idle, waitingForBluetooth, scanning, blocked(BluetoothBlockedReason), stopped(ScanStopReason)
}
public struct PumpDiscoverySnapshot: Hashable, Sendable {
    public let state: ScanState
    public let pumps: [DiscoveredPump]
    public init(state: ScanState, pumps: [DiscoveredPump]) { self.state = state; self.pumps = pumps }
}

public actor TandemPumpDiscovery {
    private let makeCentral: @Sendable () -> any BluetoothCentral
    private let clock: any Clock
    private let scheduler: any Scheduler
    private var central: (any BluetoothCentral)?
    private var eventTask: Task<Void, Never>?
    private var registration: (any SchedulerRegistration)?
    private var observers: [UUID: AsyncStream<PumpDiscoverySnapshot>.Continuation] = [:]
    private var pumps: [UUID: DiscoveredPump] = [:]
    private var insertion: [UUID] = []
    private var radio: BluetoothRadioState = .unknown
    private var scanRequested = false
    private var state: ScanState = .idle
    private var lastInteraction: Date = .distantPast

    public init(makeCentral: @escaping @Sendable () -> any BluetoothCentral,
                clock: any Clock, scheduler: any Scheduler) {
        self.makeCentral = makeCentral
        self.clock = clock
        self.scheduler = scheduler
    }

    // The event loop holds the central strongly and the engine weakly; cancelling it ends
    // the loop, which releases the central and stops delivery to an engine that is gone.
    deinit {
        eventTask?.cancel()
        registration?.cancel()
    }

    public func snapshots() -> AsyncStream<PumpDiscoverySnapshot> {
        for continuation in observers.values { continuation.finish() }
        observers.removeAll()
        let id = UUID()
        let pair = AsyncStream<PumpDiscoverySnapshot>.makeStream()
        observers[id] = pair.continuation
        pair.continuation.yield(snapshot())
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return pair.stream
    }

    public func startScan() {
        if case .scanning = state { central?.stopScan(); cancelHousekeeping() }
        pumps.removeAll(); insertion.removeAll()
        scanRequested = true
        lastInteraction = clock.now
        ensureCentral()
        if let reason = Self.blockedReason(for: radio) { block(reason) }
        else if radio == .poweredOn { beginScan() }
        else { state = .waitingForBluetooth; publish() }
    }

    public func noteUserInteraction() {
        guard scanRequested else { return }
        lastInteraction = clock.now
    }

    public func stopScan() { stop(reason: .user) }

    /// Stops a scan that is running or waiting for the radio, and does nothing otherwise, so
    /// tearing the Driver down from idle, blocked or stopped keeps the reported state.
    public func stopScanIfActive() {
        guard scanRequested else { return }
        stop(reason: .user)
    }

    public func select(_ handle: DiscoveredPumpHandle) -> DiscoveredPump? {
        guard let result = pumps[handle.peripheralID] else { return nil }
        stop(reason: .pumpSelected)
        return result
    }

    public func currentSnapshot() -> PumpDiscoverySnapshot { snapshot() }

    private func ensureCentral() {
        guard central == nil else { return }
        let value = makeCentral()
        central = value
        eventTask = Task { [weak self] in
            for await event in value.events {
                guard !Task.isCancelled else { break }
                await self?.consume(event)
            }
        }
    }

    private func consume(_ event: CentralEvent) {
        switch event {
        case .radioStateChanged(let value):
            radio = value
            guard scanRequested else { return }
            if let reason = Self.blockedReason(for: value) {
                central?.stopScan()
                cancelHousekeeping()
                pumps.removeAll(); insertion.removeAll()
                block(reason)
            } else if value == .poweredOn {
                if state == .waitingForBluetooth { beginScan() }
            } else if state == .scanning {
                // The radio went back to unknown: not a blocking condition, so stop and
                // wait for power again rather than report a reason iOS did not give.
                central?.stopScan()
                cancelHousekeeping()
                pumps.removeAll(); insertion.removeAll()
                state = .waitingForBluetooth
                publish()
            }
        case .discovered(let sighting):
            guard case .scanning = state else { return }
            upsert(sighting)
            publish()
        }
    }

    private func beginScan() {
        guard let central else { return }
        scanRequested = true
        state = .scanning
        central.startScan(services: [TandemBluetooth.pumpServiceUUID])
        cancelHousekeeping()
        registration = scheduler.scheduleRepeating(interval: TandemScanTiming.housekeeping) { [weak self] in
            await self?.housekeeping()
        }
        publish()
    }

    /// The blocking condition a radio state represents, or nil for the two states that
    /// do not block a scan: powered on, and unknown (still being determined).
    static func blockedReason(for radio: BluetoothRadioState) -> BluetoothBlockedReason? {
        switch radio {
        case .poweredOff: .poweredOff
        case .unauthorized(.denied): .permissionDenied
        case .unauthorized(.restricted): .permissionRestricted
        case .unsupported: .unsupported
        case .resetting: .resetting
        case .unknown, .poweredOn: nil
        }
    }

    private func block(_ reason: BluetoothBlockedReason) {
        scanRequested = false
        state = .blocked(reason)
        publish()
    }

    private func stop(reason: ScanStopReason) {
        central?.stopScan()
        scanRequested = false
        cancelHousekeeping()
        state = .stopped(reason)
        publish()
    }

    private func cancelHousekeeping() { registration?.cancel(); registration = nil }

    private func housekeeping() {
        guard case .scanning = state else { return }
        if clock.now.timeIntervalSince(lastInteraction) >= TandemScanTiming.idleStop {
            stop(reason: .idleTimeout)
            return
        }
        let cutoff = clock.now.addingTimeInterval(-TandemScanTiming.ageOut)
        let expired = pumps.values.filter { $0.lastSeen < cutoff }.map { $0.handle.peripheralID }
        guard !expired.isEmpty else { return }
        for id in expired { pumps.removeValue(forKey: id); insertion.removeAll { $0 == id } }
        publish()
    }

    private func upsert(_ sighting: PeripheralSighting) {
        let now = clock.now
        let signal = sighting.rssi == TandemScanTiming.unavailableRSSI ? nil : sighting.rssi
        let old = pumps[sighting.identifier]
        let advertised = sighting.localName.flatMap { $0.isEmpty ? nil : $0 }
        let name = advertised ?? old?.name ?? "Tandem Pump"
        let model = advertised.map(TandemPumpModel.fromAdvertisedName) ?? old?.model ?? .unknown
        if old == nil { insertion.append(sighting.identifier) }
        pumps[sighting.identifier] = DiscoveredPump(handle: DiscoveredPumpHandle(sighting.identifier), name: name,
            model: model, signalStrength: signal, firstSeen: old?.firstSeen ?? now, lastSeen: now)
    }

    private func snapshot() -> PumpDiscoverySnapshot {
        let order = Dictionary(uniqueKeysWithValues: insertion.enumerated().map { ($1, $0) })
        let sorted = pumps.values.sorted { lhs, rhs in
            switch (lhs.signalStrength, rhs.signalStrength) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if lhs.firstSeen != rhs.firstSeen { return lhs.firstSeen < rhs.firstSeen }
                return (order[lhs.handle.peripheralID] ?? 0) < (order[rhs.handle.peripheralID] ?? 0)
            }
        }
        return PumpDiscoverySnapshot(state: state, pumps: sorted)
    }
    private func publish() { let value = snapshot(); for observer in observers.values { observer.yield(value) } }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}
