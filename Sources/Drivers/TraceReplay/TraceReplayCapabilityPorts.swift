import Foundation
import DriverAPI

struct TraceReplayGlucosePort: GlucoseSource {
    let readings: AsyncStream<GlucoseSample>
    let driver: TraceReplayDriver
    func latestReading() async throws(DriverFailure) -> GlucoseSample? {
        try await driver.currentGlucose()
    }
}

struct TraceReplayInsulinPort: InsulinSource {
    let insulinOnBoard: AsyncStream<InsulinOnBoardSample>
    let driver: TraceReplayDriver
    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord] {
        try await driver.doses(since: since)
    }
}

// Each frame yields at most one sample per stream, so a buffer the size of the
// largest accepted trace never drops a sample before a late subscriber reads it.
final class TraceReplayStreams: @unchecked Sendable {
    private let lock = NSLock()
    private var glucosePair = AsyncStream<GlucoseSample>.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))
    private var insulinPair = AsyncStream<InsulinOnBoardSample>.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))

    var glucose: AsyncStream<GlucoseSample> {
        lock.lock(); defer { lock.unlock() }
        return glucosePair.stream
    }
    var insulin: AsyncStream<InsulinOnBoardSample> {
        lock.lock(); defer { lock.unlock() }
        return insulinPair.stream
    }
    func yield(_ sample: GlucoseSample) {
        lock.lock()
        let continuation = glucosePair.continuation
        lock.unlock()
        continuation.yield(sample)
    }
    func yield(_ sample: InsulinOnBoardSample) {
        lock.lock()
        let continuation = insulinPair.continuation
        lock.unlock()
        continuation.yield(sample)
    }
    func finish() {
        lock.lock()
        let glucose = glucosePair.continuation
        let insulin = insulinPair.continuation
        lock.unlock()
        glucose.finish()
        insulin.finish()
    }
    func renew() {
        lock.lock()
        let oldGlucose = glucosePair.continuation
        let oldInsulin = insulinPair.continuation
        glucosePair = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))
        insulinPair = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))
        lock.unlock()
        oldGlucose.finish()
        oldInsulin.finish()
    }
}
