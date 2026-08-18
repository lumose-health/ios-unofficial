import Foundation
import SafetyCore

@testable import DriverAPI

// A conforming implementation of each of the six Capability ports, and of
// `Driver` itself.
//
// These are not fixtures for other tests' convenience — they are the proof that
// the contract is implementable at all. A read-only protocol full of
// `AsyncStream` requirements is easy to write and can still be impossible to
// satisfy under Swift 6 strict concurrency; the only way to know is to satisfy
// it. Everything here is deliberately trivial: the contract is under test, not
// the stub.

struct StubGlucoseSource: GlucoseSource {
    let readings: AsyncStream<GlucoseSample> = AsyncStream { $0.finish() }
    func latestReading() async throws(DriverFailure) -> GlucoseSample? { nil }
}

struct StubInsulinSource: InsulinSource {
    let insulinOnBoard: AsyncStream<InsulinOnBoardSample> = AsyncStream { $0.finish() }
    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord] { [] }
}

struct StubPumpStatusSource: PumpStatusSource {
    let status: AsyncStream<PumpStatusSnapshot> = AsyncStream { $0.finish() }
    func latestStatus() async throws(DriverFailure) -> PumpStatusSnapshot? { nil }
}

struct StubBGMSource: BGMSource {
    let readings: AsyncStream<FingerstickSample> = AsyncStream { $0.finish() }
    func latestReading() async throws(DriverFailure) -> FingerstickSample? { nil }
}

struct StubDataSync: DataSync {
    let destination = SyncDestination(serviceName: "Nightscout", host: "nightscout.example")!
    let mirroredRecords: Set<MirroredRecordKind> = [.glucose]
    let state: AsyncStream<SyncState> = AsyncStream { $0.finish() }
    func lastMirroredAt() async throws(DriverFailure) -> Date? { nil }
}

struct StubDoseCategoryProvider: DoseCategoryProvider {
    let declaredCategories: Set<String> = ["CONTROL_IQ"]
    func platformCategory(for declaredCategory: String) -> DoseCategory? {
        declaredCategory == "CONTROL_IQ" ? .autoCorrection : nil
    }
}

/// A Driver that provides all six ports.
///
/// It also demonstrates the shape AD-16 requires: the entry points are here, and
/// there is no lifecycle state for the Driver to move — the platform holds a
/// ``DriverLifecycle`` this type cannot reach.
actor StubDriver: Driver {

    static let identifier = DriverIdentifier("com.glycemicgpt.stub")!

    nonisolated let descriptor = DriverDescriptor(
        identifier: StubDriver.identifier,
        targetName: "Stub",
        displayName: "Stub Driver",
        transport: .inProcess,
        version: "1.0.0",
        capabilities: Set(Capability.allCases),
        verification: .unverified
    )

    private(set) var activateCallCount = 0
    private(set) var deactivateCallCount = 0

    nonisolated func capability(_ capability: Capability) -> CapabilityPort? {
        switch capability {
        case .glucoseSource: return .glucoseSource(StubGlucoseSource())
        case .insulinSource: return .insulinSource(StubInsulinSource())
        case .pumpStatus: return .pumpStatus(StubPumpStatusSource())
        case .bgmSource: return .bgmSource(StubBGMSource())
        case .dataSync: return .dataSync(StubDataSync())
        case .doseCategoryProvider: return .doseCategoryProvider(StubDoseCategoryProvider())
        }
    }

    func activate() async throws(DriverFailure) {
        activateCallCount += 1
    }

    func deactivate() async {
        deactivateCallCount += 1
    }
}
