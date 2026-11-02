import Foundation
import Testing
import DriverAPI
@testable import DomainCore

@Suite("Capability reads")
struct CapabilityReadTests {
    private let id = DriverIdentifier("test.read.alpha")!

    @Test func noHolderDiffersFromEmptyHistory() async throws {
        let empty = try DriverRegistry(drivers: [], store: RecordingSelectionStore())
        do {
            _ = try await empty.port(for: .insulinSource)
            Issue.record("Expected no holder")
        } catch { #expect(error == .noActiveDriver(.insulinSource)) }

        let driver = PortTestDriver(id: id, capabilities: [.insulinSource])
        let registry = try DriverRegistry(drivers: [driver], store: RecordingSelectionStore([id.rawValue]))
        _ = await registry.restore()
        let held = try await registry.port(for: .insulinSource)
        #expect(held.holder == id)
        guard case .insulinSource(let insulin) = held.port else {
            Issue.record("Expected insulin port")
            return
        }
        #expect(try await insulin.doses(since: Date(timeIntervalSince1970: 0)).isEmpty)
    }

    @Test func everyCapabilityHasAnExplicitAbsentState() async throws {
        let registry = try DriverRegistry(drivers: [], store: RecordingSelectionStore())
        for capability in Capability.allCases {
            do {
                _ = try await registry.port(for: capability)
                Issue.record("Expected read failure for \(capability)")
            } catch {
                if capability.cardinality == .singleInstance {
                    #expect(error == .noActiveDriver(capability))
                } else {
                    #expect(error == .notSingleInstance(capability))
                }
            }
        }
    }

    @Test func glucoseOnlyDoesNotFillPumpSlot() async throws {
        let driver = PortTestDriver(id: id, capabilities: [.glucoseSource])
        let registry = try DriverRegistry(drivers: [driver], store: RecordingSelectionStore([id.rawValue]))
        _ = await registry.restore()
        do {
            _ = try await registry.port(for: .pumpStatus)
            Issue.record("Expected empty pump slot")
        } catch { #expect(error == .noActiveDriver(.pumpStatus)) }
    }

    @Test func selectedButUnstartedAndWrongPortAreDistinct() async throws {
        let driver = PortTestDriver(id: id, capabilities: [.glucoseSource], wrongPort: true)
        let registry = try DriverRegistry(drivers: [driver], store: RecordingSelectionStore([id.rawValue]))
        #expect(registry.initialSlots.holder(of: .glucoseSource) == id)
        do {
            _ = try await registry.port(for: .glucoseSource)
            Issue.record("Expected inactive holder")
        } catch { #expect(error == .holderNotRunning(id, .glucoseSource, .notActivated)) }
        _ = await registry.restore()
        do {
            _ = try await registry.port(for: .glucoseSource)
            Issue.record("Expected mismatched port")
        } catch { #expect(error == .portUnavailable(id, .glucoseSource)) }
    }

    @Test func cancelledReadTakesPriority() async throws {
        let registry = try DriverRegistry(drivers: [], store: RecordingSelectionStore())
        let task = Task { () -> CapabilityReadError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(CapabilityReadError) { _ = try await registry.port(for: .glucoseSource); return nil }
            catch { return error }
        }
        #expect(await task.value == .cancelled)
    }

    @Test func failedRestoreWithUnwritableRemovalRetainsFailedHolder() async throws {
        let driver = PortTestDriver(id: id, capabilities: [.glucoseSource], activationFailure: .authenticationRejected)
        let store = RecordingSelectionStore([id.rawValue])
        store.saveFailure = .unwritable(detail: "injected")
        let registry = try DriverRegistry(drivers: [driver], store: store)
        let report = await registry.restore()
        #expect(report.unremoved == [id])
        do {
            _ = try await registry.port(for: .glucoseSource)
            Issue.record("Expected failed holder")
        } catch { #expect(error == .holderNotRunning(id, .glucoseSource, .failed)) }
    }

    @Test func readContinuesWhileAnotherActivationOwnsOperationGate() async throws {
        let reader = PortTestDriver(id: id, capabilities: [.insulinSource])
        let other = TestDriver(id: "test.read.other", capabilities: [.pumpStatus])
        let entered = Gate()
        let release = Gate()
        await other.setActivationHook {
            await entered.open()
            await release.wait()
        }
        let registry = try DriverRegistry(drivers: [reader, other], store: RecordingSelectionStore([id.rawValue]))
        _ = await registry.restore()
        let activation = Task { try await registry.activate(other.descriptor.identifier) }
        await entered.wait()
        let held = try await registry.port(for: .insulinSource)
        #expect(held.holder == id)
        await release.open()
        _ = try await activation.value
    }
}

private actor PortTestDriver: Driver {
    nonisolated let descriptor: DriverDescriptor
    private let wrongPort: Bool
    private let activationFailure: DriverFailure?

    init(id: DriverIdentifier, capabilities: Set<Capability>, wrongPort: Bool = false,
         activationFailure: DriverFailure? = nil) {
        descriptor = DriverDescriptor(identifier: id, targetName: "PortTestDriver", displayName: id.rawValue,
            transport: .inProcess, version: "1.0.0", capabilities: capabilities, verification: .unverified)
        self.wrongPort = wrongPort
        self.activationFailure = activationFailure
    }

    func capability(_ capability: Capability) -> CapabilityPort? {
        if wrongPort { return .insulinSource(EmptyInsulinPort()) }
        return switch capability {
        case .glucoseSource where descriptor.capabilities.contains(.glucoseSource): .glucoseSource(EmptyGlucosePort())
        case .insulinSource where descriptor.capabilities.contains(.insulinSource): .insulinSource(EmptyInsulinPort())
        case .pumpStatus where descriptor.capabilities.contains(.pumpStatus): .pumpStatus(EmptyPumpPort())
        default: nil
        }
    }
    func activate() async throws(DriverFailure) {
        if let activationFailure { throw activationFailure }
    }
    func deactivate() async {}
}

private struct EmptyGlucosePort: GlucoseSource {
    var readings: AsyncStream<GlucoseSample> { AsyncStream { _ in } }
    func latestReading() async throws(DriverFailure) -> GlucoseSample? { nil }
}

private struct EmptyInsulinPort: InsulinSource {
    var insulinOnBoard: AsyncStream<InsulinOnBoardSample> { AsyncStream { _ in } }
    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord] { [] }
}

private struct EmptyPumpPort: PumpStatusSource {
    var status: AsyncStream<PumpStatusSnapshot> { AsyncStream { _ in } }
    func latestStatus() async throws(DriverFailure) -> PumpStatusSnapshot? { nil }
}
