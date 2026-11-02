import Foundation
import Observation
import SwiftUI
import DriverAPI
import DomainCore

public struct DriverRowState: Identifiable, Hashable, Sendable {
    public let row: DriverRow
    public let isSelected: Bool
    public let isBusy: Bool
    public let errorMessage: String?
    /// Shown in place of the lifecycle text while this screen has an operation
    /// on the Driver in flight, so the row never shows the state it is leaving.
    public let busyLabel: String?
    /// False while the saved selection cannot be read, when no row can honestly
    /// say whether its Driver is selected.
    public let selectionReadable: Bool

    public init(row: DriverRow, isSelected: Bool, isBusy: Bool, errorMessage: String?,
                busyLabel: String? = nil, selectionReadable: Bool = true) {
        self.row = row
        self.isSelected = isSelected
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.busyLabel = busyLabel
        self.selectionReadable = selectionReadable
    }

    public var id: DriverIdentifier { row.id }
    public var stateText: String { busyLabel ?? row.state.screenText }
    /// A Driver mid-transition, including one stopped by another's activation,
    /// cannot be activated until it settles.
    public var canActivate: Bool {
        selectionReadable && !isSelected && !isBusy && row.state != .activating && row.state != .deactivating
    }
    public var canDeactivate: Bool { selectionReadable && isSelected && !isBusy }
    public var transportText: String { row.transport.screenText }
    public var verificationText: String { row.verification.screenText }
}

public struct DeactivationPrompt: Identifiable, Hashable, Sendable {
    public let id: DriverIdentifier
    public let title: String
    public let message: String
    public let confirmLabel: String
    public let cancelLabel: String
}

@MainActor @Observable public final class DriversModel {
    public private(set) var rows: [DriverRowState]
    public private(set) var pendingDeactivation: DeactivationPrompt?
    /// Set while the saved selection cannot be read, for example before first unlock.
    public private(set) var selectionNotice: String?

    private enum Operation { case starting, stopping }

    private let registry: DriverRegistry
    private var operations: [DriverIdentifier: Operation] = [:]
    private var errors: [DriverIdentifier: String] = [:]
    @ObservationIgnored nonisolated(unsafe) private var registryObserver: Task<Void, Never>?

    public init(registry: DriverRegistry) {
        self.registry = registry
        self.rows = registry.descriptors.map {
            DriverRowState(row: DriverRow(descriptor: $0, state: .notActivated),
                           isSelected: false, isBusy: false, errorMessage: nil)
        }
        registryObserver = Task { [weak self, registry] in
            let changes = await registry.changes()
            await self?.refresh()
            for await _ in changes {
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    deinit { registryObserver?.cancel() }

    /// Re-reads the registry. The screen calls this when it appears, so it
    /// never shows a state from before it was last on screen.
    public func refresh() async {
        let selection = await registry.persistedSelection
        let selectionUnavailable: Bool
        if case .unavailable = await registry.selectionLoadFailure { selectionUnavailable = true }
        else { selectionUnavailable = false }
        var states: [DriverIdentifier: DriverLifecycleState] = [:]
        for descriptor in registry.descriptors {
            states[descriptor.id] = await registry.lifecycleState(of: descriptor.id) ?? .notActivated
        }
        selectionNotice = selectionUnavailable
            ? "Your driver selection can't be read until the phone is unlocked" : nil
        rows = registry.descriptors.map { descriptor in
            makeRow(descriptor, state: states[descriptor.id] ?? .notActivated,
                    isSelected: selection.contains(descriptor.id.rawValue),
                    selectionReadable: !selectionUnavailable)
        }
    }

    private func makeRow(_ descriptor: DriverDescriptor, state: DriverLifecycleState,
                         isSelected: Bool, selectionReadable: Bool) -> DriverRowState {
        let operation = operations[descriptor.id]
        let busyLabel: String? = switch operation {
        case .starting: "Starting…"
        case .stopping: "Stopping…"
        case nil: nil
        }
        return DriverRowState(row: DriverRow(descriptor: descriptor, state: state), isSelected: isSelected,
                              isBusy: operation != nil, errorMessage: errors[descriptor.id],
                              busyLabel: busyLabel, selectionReadable: selectionReadable)
    }

    /// Updates busy labels without waiting on the registry, so a tap shows at once.
    private func applyOperations() {
        rows = rows.compactMap { current in
            guard let descriptor = registry.descriptors.first(where: { $0.id == current.id }) else { return nil }
            return makeRow(descriptor, state: current.row.state, isSelected: current.isSelected,
                           selectionReadable: current.selectionReadable)
        }
    }

    public func activate(_ id: DriverIdentifier) async {
        guard let row = rows.first(where: { $0.id == id }), row.canActivate,
              let descriptor = registry.descriptors.first(where: { $0.id == id }) else { return }
        // Selected Drivers sharing a single-instance capability are stopped by
        // this activation, so they show as stopping and cannot be acted on.
        let claimed = descriptor.capabilities.filter { $0.cardinality == .singleInstance }
        let evicted = registry.descriptors.filter { other in
            other.id != id && rows.contains(where: { $0.id == other.id && $0.isSelected })
                && !other.capabilities.isDisjoint(with: claimed)
        }.map(\.id).filter { operations[$0] == nil }
        operations[id] = .starting
        for other in evicted { operations[other] = .stopping }
        errors[id] = nil
        applyOperations()
        do { _ = try await registry.activate(id) }
        catch {
            NSLog("Driver activation failed: %@", String(describing: error))
            errors[id] = Self.errorMessage(error, action: "activate", name: row.row.name)
        }
        operations[id] = nil
        for other in evicted { operations[other] = nil }
        await refresh()
    }

    public func requestDeactivation(_ id: DriverIdentifier) {
        guard let state = rows.first(where: { $0.id == id }), state.canDeactivate,
              let descriptor = registry.descriptors.first(where: { $0.id == id }) else { return }
        let names = Capability.allCases.filter { descriptor.capabilities.contains($0) }.map(\.screenText)
        let provides = names.isEmpty ? "" : "\(descriptor.displayName) provides: \(names.joined(separator: ", ")).\n"
        pendingDeactivation = DeactivationPrompt(
            id: id, title: "Deactivate Driver",
            message: "Deactivating this Driver may stop glucose monitoring, insulin tracking, or other services it provides. Are you sure?\n\n\(provides)Its settings are kept.",
            confirmLabel: "Deactivate", cancelLabel: "Cancel"
        )
    }

    public func cancelDeactivation() { pendingDeactivation = nil }

    public func confirmDeactivation() async {
        guard let prompt = pendingDeactivation, operations[prompt.id] == nil else { return }
        pendingDeactivation = nil
        operations[prompt.id] = .stopping
        errors[prompt.id] = nil
        applyOperations()
        do { try await registry.deactivate(prompt.id) }
        catch {
            NSLog("Driver deactivation failed: %@", String(describing: error))
            let name = registry.descriptors.first(where: { $0.id == prompt.id })?.displayName ?? prompt.id.rawValue
            errors[prompt.id] = Self.errorMessage(error, action: "deactivate", name: name)
        }
        operations[prompt.id] = nil
        await refresh()
    }

    private static func errorMessage(_ error: Error, action: String, name: String) -> String {
        let detail: String
        switch error {
        case DriverRegistryError.activationFailed: detail = "It didn't start. Try again."
        case DriverRegistryError.persistenceFailed,
             DriverRegistryError.persistenceFailedDriverStillLive,
             DriverRegistryError.selectionUnavailable:
            detail = "Your Driver choice couldn't be saved. Try again."
        case DriverRegistryError.evictionIncomplete: detail = "Another Driver didn't stop cleanly."
        default: detail = "Try again."
        }
        return "Couldn't \(action) \(name).\n\(detail)"
    }
}

private extension DriverLifecycleState {
    var screenText: String {
        switch self {
        case .notActivated: "Inactive"
        case .activating: "Starting…"
        case .active: "Active"
        case .degraded: "Running with problems"
        case .deactivating: "Stopping…"
        case .failed: "Failed to start"
        }
    }
}

private extension DriverTransport {
    var screenText: String {
        switch self {
        case .bluetoothLowEnergy: "Bluetooth"
        case .network: "Network"
        case .inProcess: "On device"
        }
    }
}

private extension VerificationStatus {
    var screenText: String {
        switch self {
        case .unverified: "Unverified"
        case .protocolCompatible: "Protocol-compatible (unverified on hardware)"
        case .beta: "Beta"
        case .hardwareVerified: "Verified on hardware"
        }
    }
}

private extension Capability {
    var screenText: String {
        switch self {
        case .glucoseSource: "glucose readings"
        case .insulinSource: "insulin on board and dose history"
        case .pumpStatus: "pump status"
        case .bgmSource: "meter readings"
        case .dataSync: "data sync"
        case .doseCategoryProvider: "dose categories"
        }
    }
}

public struct DriversScreen: View {
    @Environment(DriversModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        List {
            if let notice = model.selectionNotice {
                Text(notice).accessibilityIdentifier("drivers.selection-unavailable")
            }
            ForEach(model.rows) { state in
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.row.name).font(.headline)
                    Text("Protocol: \(state.transportText)")
                    Text("Version: \(state.row.version)")
                    Text("Verification Status: \(state.verificationText)")
                    Text(state.stateText)
                    if let error = state.errorMessage {
                        Text(error).foregroundStyle(StatusColor.error.swiftUIColor(colorScheme))
                            .accessibilityIdentifier("drivers.error.\(state.id.rawValue)")
                    }
                    if state.isSelected {
                        Button("Deactivate", role: .destructive) { model.requestDeactivation(state.id) }
                            .disabled(!state.canDeactivate)
                    } else {
                        Button(state.busyLabel ?? "Activate") {
                            Task { await model.activate(state.id) }
                        }
                        .disabled(!state.canActivate)
                    }
                }
                .accessibilityIdentifier("drivers.row.\(state.id.rawValue)")
            }
        }
        .navigationTitle("Drivers")
        .task { await model.refresh() }
        #if os(iOS)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .alert("Deactivate Driver", isPresented: Binding(
            get: { model.pendingDeactivation != nil },
            set: { _ in }
        ), presenting: model.pendingDeactivation) { prompt in
            Button(prompt.confirmLabel, role: .destructive) {
                Task { await model.confirmDeactivation() }
            }
            Button(prompt.cancelLabel, role: .cancel) { model.cancelDeactivation() }
        } message: { prompt in
            Text(prompt.message)
        }
    }
}
