import Foundation
import Testing
import DriverAPI
import TandemWire
@_spi(DriverPlatform) import DriverAPI
@testable import TraceReplayDriver

@Suite("Trace replay driver")
struct TraceReplayDriverTests {
    private let start = Date(timeIntervalSince1970: 1_737_030_400)

    private func makeDriver(
        trace: TraceSource = .bundled(name: TraceReplayDriver.defaultTraceName),
        log: RecordingTraceLog = RecordingTraceLog()
    ) throws -> (TraceReplayDriver, SafetyLimitsValidator, RecordingTraceLog) {
        let validator = SafetyLimitsValidator(limits: try SafetyLimits(glucoseLower: 20, glucoseUpper: 500))
        let fixed = start
        return (TraceReplayDriver(validator: validator, trace: trace, log: log, clock: FixedTraceClock(now: fixed)), validator, log)
    }

    private func glucose(_ driver: TraceReplayDriver) throws -> any GlucoseSource {
        guard case .glucoseSource(let port) = driver.capability(.glucoseSource) else {
            throw DriverFailure.capabilityUnavailable(.glucoseSource)
        }
        return port
    }
    private func insulin(_ driver: TraceReplayDriver) throws -> any InsulinSource {
        guard case .insulinSource(let port) = driver.capability(.insulinSource) else {
            throw DriverFailure.capabilityUnavailable(.insulinSource)
        }
        return port
    }

    private func rows(_ results: [TraceFrameResult]) -> [String] {
        results.map { result in
            switch result {
            case .read(.glucose(let sample)):
                return "glucose:\(Int(sample.glucose.mgdl)):\(Int(sample.recordedAt.timeIntervalSince(start)))"
            case .read(.insulinOnBoard(let sample)):
                return "iob:\(sample.units):\(Int(sample.calculatedAt.timeIntervalSince(start)))"
            case .read(.outOfRange(let side, let date)):
                return "range:\(side):\(Int(date.timeIntervalSince(start)))"
            case .read(.sensorReadingUnusable(let status)): return "unusable:\(status)"
            case .read(.notRead): return "notRead"
            case .valueRejected(let bound): return "rejected:\(bound)"
            case .decodeFailed(let detail): return "halt:\(detail)"
            }
        }
    }

    @Test("Descriptor, golden results, streams and log match the fixture")
    func golden() async throws {
        let (driver, validator, log) = try makeDriver()
        #expect(DriverCatalog.entry(for: TraceReplayDriver.identifier) == driver.descriptor)
        let glucosePort = try glucose(driver)
        let insulinPort = try insulin(driver)
        try await driver.activate()
        let rejected: String
        do { _ = try validator.validate(mgdl: 15); Issue.record("expected rejection"); return }
        catch DriverFailure.valueRejected(let bound) { rejected = bound }
        let expected = [
            "glucose:123:-2400", "iob:2.5:-2398", "glucose:131:-2100", "iob:1.5:-2098",
            "range:below:-1800", "range:above:-1500", "unusable:0", "unusable:4",
            "iob:2.5:-898", "rejected:\(rejected)", "range:above:-300", "glucose:118:0",
        ]
        #expect(rows(await driver.frameResults) == expected)
        #expect(await driver.cursor == 12)
        #expect(try await glucosePort.latestReading()?.glucose.mgdl == 118)
        #expect(try await insulinPort.doses(since: start).isEmpty)
        await driver.deactivate()
        var glucoseValues: [Double] = []
        for await sample in glucosePort.readings { glucoseValues.append(sample.glucose.mgdl) }
        var insulinValues: [Double] = []
        for await sample in insulinPort.insulinOnBoard { insulinValues.append(sample.units) }
        #expect(glucoseValues == [123, 131, 118])
        #expect(insulinValues == [2.5, 1.5, 2.5])
        #expect(log.recorded == ["range:4:below", "range:5:above", "unusable:6:0", "unusable:7:4", "rejected:9:\(rejected)", "range:10:above"])
    }

    @Test("A corrupt frame holds the cursor and keeps earlier samples")
    func decodeHalt() async throws {
        let url = try #require(Bundle.module.url(forResource: "tandem-decode-failure-01", withExtension: "json", subdirectory: "Traces"))
        let (driver, _, log) = try makeDriver(trace: .data(Data(contentsOf: url)))
        let port = try glucose(driver)
        let doses = try insulin(driver)
        try await driver.activate()
        #expect(await driver.cursor == 1)
        #expect(rows(await driver.frameResults) == ["glucose:120:-600", "halt:frame"])
        await #expect(throws: DriverFailure.decodeFailed(detail: "frame")) { _ = try await port.latestReading() }
        await #expect(throws: DriverFailure.decodeFailed(detail: "frame")) { _ = try await doses.doses(since: start) }
        await driver.deactivate()
        var values: [Double] = []
        for await sample in port.readings { values.append(sample.glucose.mgdl) }
        #expect(values == [120])
        #expect(log.recorded == ["halt:1:frame"])
        #expect(try await port.latestReading() == nil)
        #expect(try await doses.doses(since: start).isEmpty)
        try await driver.activate()
        #expect(await driver.cursor == 1)
        #expect(rows(await driver.frameResults) == ["glucose:120:-600", "halt:frame"])
    }

    @Test("Fresh instances and reactivation preserve results and renew streams")
    func deterministic() async throws {
        let (first, _, _) = try makeDriver()
        let (second, _, _) = try makeDriver()
        let old = try glucose(first).readings
        try await first.activate()
        try await second.activate()
        let expected = rows(await first.frameResults)
        #expect(rows(await second.frameResults) == expected)
        await first.deactivate()
        var oldValues: [Double] = []
        for await sample in old { oldValues.append(sample.glucose.mgdl) }
        try await first.activate()
        #expect(rows(await first.frameResults) == expected)
        let renewed = try glucose(first).readings
        await first.deactivate()
        var newValues: [Double] = []
        for await sample in renewed { newValues.append(sample.glucose.mgdl) }
        #expect(oldValues == newValues)
    }

    @Test("Limits adopted before activation are read for every frame")
    func narrowedLimits() async throws {
        let (driver, validator, _) = try makeDriver()
        validator.adopt(try SafetyLimits(glucoseLower: 100, glucoseUpper: 125))
        try await driver.activate()
        let results = rows(await driver.frameResults)
        #expect(results[0] == "glucose:123:-2400")
        #expect(results[2].hasPrefix("rejected:"))
        #expect(results[11] == "glucose:118:0")
    }

    private func bundledTrace() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Drivers/TraceReplay/Traces/\(TraceReplayDriver.defaultTraceName).json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func replayedDates(_ results: [TraceFrameResult]) -> [Date] {
        results.compactMap { result in
            switch result {
            case .read(.glucose(let sample)): sample.recordedAt
            case .read(.insulinOnBoard(let sample)): sample.calculatedAt
            case .read(.outOfRange(_, let date)): date
            default: nil
            }
        }
    }

    @Test("The newest frame maps to replay start and recorded intervals are kept")
    func reanchoring() async throws {
        let (driver, _, _) = try makeDriver()
        try await driver.activate()
        let results = await driver.frameResults
        guard case .read(.glucose(let first)) = results[0],
              case .read(.glucose(let second)) = results[2],
              case .read(.glucose(let last)) = results[11] else {
            Issue.record("expected glucose results")
            return
        }
        #expect(last.recordedAt == start)
        #expect(second.recordedAt.timeIntervalSince(first.recordedAt) == 300)
    }

    @Test("No replayed glucose or IOB timestamp is later than replay start")
    func nothingInTheFuture() async throws {
        let (driver, _, _) = try makeDriver()
        let glucosePort = try glucose(driver)
        let insulinPort = try insulin(driver)
        try await driver.activate()
        let dates = replayedDates(await driver.frameResults)
        #expect(dates.count == 9)
        #expect(dates.allSatisfy { $0 <= start })
        await driver.deactivate()
        for await sample in glucosePort.readings { #expect(sample.recordedAt <= start) }
        for await sample in insulinPort.insulinOnBoard { #expect(sample.calculatedAt <= start) }
    }

    @Test("A trace that opens with IOB anchors on the newest frame, not the first")
    func iobFirst() async throws {
        let firstFrame = #"    {"channel": "currentStatus", "receivedAt": "2025-01-15T14:00:05Z", "notifications": ["000123010880e80d207b000100561f"], "note": "VALID reading"},"# + "\n"
        let original = try bundledTrace()
        let trimmed = original.replacingOccurrences(of: firstFrame, with: "")
        #expect(trimmed != original)
        let (driver, _, _) = try makeDriver(trace: .data(Data(trimmed.utf8)))
        try await driver.activate()
        let results = rows(await driver.frameResults)
        #expect(results.first == "iob:2.5:-2398")
        #expect(results[1] == "glucose:131:-2100")
        #expect(results.last == "glucose:118:0")
        #expect(replayedDates(await driver.frameResults).allSatisfy { $0 <= start })
    }

    @Test("A wrong or skewed pump time zone does not move glucose relative to IOB")
    func skewedPumpTimeZone() async throws {
        let (reference, _, _) = try makeDriver()
        try await reference.activate()
        let expected = rows(await reference.frameResults)
        let original = try bundledTrace()
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            let skewed = original.replacingOccurrences(of: #""pumpTimeZone": "America/Chicago""#, with: #""pumpTimeZone": "\#(zone)""#)
            #expect(skewed != original)
            let (driver, _, _) = try makeDriver(trace: .data(Data(skewed.utf8)))
            try await driver.activate()
            #expect(rows(await driver.frameResults) == expected)
        }
    }

    @Test("Teardown clears the last reading so a later read never returns it")
    func deactivateClears() async throws {
        let (driver, _, _) = try makeDriver()
        let port = try glucose(driver)
        try await driver.activate()
        #expect(try await port.latestReading() != nil)
        await driver.deactivate()
        #expect(try await port.latestReading() == nil)
    }

    @Test("A teardown before the first activation still leaves the next activation's streams live")
    func deactivateBeforeFirstActivation() async throws {
        let (driver, _, _) = try makeDriver()
        await driver.deactivate()
        try await driver.activate()
        let port = try glucose(driver)
        var iterator = port.readings.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first != nil)
    }

    @Test("Missing trace is a typed load failure")
    func missingTrace() async throws {
        let (driver, _, _) = try makeDriver(trace: .bundled(name: "missing"))
        await #expect(throws: DriverFailure.decodeFailed(detail: "trace file")) { try await driver.activate() }
    }
}
