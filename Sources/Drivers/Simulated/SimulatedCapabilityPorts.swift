import Foundation
import DriverAPI

/// The read side of ``SimulatedDriver``'s ``Capability/glucoseSource``.
///
/// A plain struct rather than the actor itself: ``Driver/capability(_:)`` is
/// `nonisolated`, so this has to be constructible without awaiting the actor.
/// It is — ``readings`` is the stream ``SimulatedDriver`` created once in its
/// initializer, handed here unchanged, so every read of ``readings`` returns
/// the SAME stream, per the contract stated in full on that requirement.
struct SimulatedGlucoseSourcePort: GlucoseSource {
    let readings: AsyncStream<GlucoseSample>
    let driver: SimulatedDriver

    func latestReading() async throws(DriverFailure) -> GlucoseSample? {
        try await driver.currentGlucose()
    }
}

/// The read side of ``SimulatedDriver``'s ``Capability/insulinSource``.
struct SimulatedInsulinSourcePort: InsulinSource {
    let insulinOnBoard: AsyncStream<InsulinOnBoardSample>
    let driver: SimulatedDriver

    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord] {
        try await driver.doses(since: since)
    }
}
