import Foundation
import DriverAPI

/// The read side of ``SimulatedDriver``'s ``Capability/glucoseSource``.
///
/// A plain struct rather than the actor itself: ``Driver/capability(_:)`` is
/// `nonisolated`, so this has to be constructible without awaiting the actor.
/// It is — ``readings`` is the current activation's stream, captured when the
/// port is vended, so every read of ``readings`` returns the SAME stream. It
/// finishes when ``SimulatedDriver`` deactivates; the platform reads the port
/// again after the next activation, per the contract on that requirement.
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
