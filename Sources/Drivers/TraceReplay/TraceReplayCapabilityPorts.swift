#if TRACE_REPLAY_DRIVER_ENABLED
import Foundation
import DriverAPI

struct TraceReplayGlucosePort: GlucoseSource {
    let readings: AsyncStream<GlucoseSample>
    let sensorRangeExcursions: AsyncStream<SensorRangeExcursion>
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

// Each frame yields at most one value per stream, so a buffer the size of the
// largest accepted trace never drops a value before a late subscriber reads it.
final class TraceReplayStreams: @unchecked Sendable {
    private let lock = NSLock()
    private var glucosePair = AsyncStream<GlucoseSample>.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))
    private var insulinPair = AsyncStream<InsulinOnBoardSample>.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))
    private var excursionPair = AsyncStream<SensorRangeExcursion>.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))

    var glucose: AsyncStream<GlucoseSample> {
        lock.lock(); defer { lock.unlock() }
        return glucosePair.stream
    }
    var insulin: AsyncStream<InsulinOnBoardSample> {
        lock.lock(); defer { lock.unlock() }
        return insulinPair.stream
    }
    var excursions: AsyncStream<SensorRangeExcursion> {
        lock.lock(); defer { lock.unlock() }
        return excursionPair.stream
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
    func yield(_ excursion: SensorRangeExcursion) {
        lock.lock()
        let continuation = excursionPair.continuation
        lock.unlock()
        continuation.yield(excursion)
    }
    func finish() {
        lock.lock()
        let glucose = glucosePair.continuation
        let insulin = insulinPair.continuation
        let excursions = excursionPair.continuation
        lock.unlock()
        glucose.finish()
        insulin.finish()
        excursions.finish()
    }
    func renew() {
        lock.lock()
        let oldGlucose = glucosePair.continuation
        let oldInsulin = insulinPair.continuation
        let oldExcursions = excursionPair.continuation
        glucosePair = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))
        insulinPair = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))
        excursionPair = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(TraceFile.maximumFrameCount))
        lock.unlock()
        oldGlucose.finish()
        oldInsulin.finish()
        oldExcursions.finish()
    }
}
#endif
