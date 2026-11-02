import Foundation
import DriverAPI
import SafetyCore
import TandemWire

public enum TraceSource: Sendable {
    case bundled(name: String)
    case data(Data)
}

// One result per consumed frame, plus the failure at a halted frame.
enum TraceFrameResult: Equatable, Sendable {
    case read(TandemReadOutcome)
    case valueRejected(bound: String)
    case decodeFailed(detail: String)
}

/// Replays one trace immediately. One offset, fixed at activation, maps the newest
/// frame's phone receive time to replay start, so recorded intervals are kept and no
/// replayed timestamp is later than the moment replay started.
///
/// Every replayed timestamp, glucose and IOB alike, is taken from the frame's phone
/// receive time (`receivedAt`) plus that offset. The pump's own EGV timestamp is still
/// decoded, so a bad one halts replay, but it does not set the replayed time: a skewed
/// pump clock or a wrong `pumpTimeZone` would otherwise move glucose relative to IOB,
/// whose time already comes from `receivedAt`, and could place readings in the future.
public actor TraceReplayDriver: Driver {
    public static let identifier = DriverIdentifier("com.glycemicgpt.trace-replay")!
    public static let defaultTraceName = "tandem-status-01"
    public nonisolated let descriptor = DriverDescriptor(
        identifier: TraceReplayDriver.identifier,
        targetName: "TraceReplayDriver",
        displayName: "Trace-Replay Driver",
        transport: .inProcess,
        version: "1.0.0",
        capabilities: [.glucoseSource, .insulinSource],
        verification: .beta
    )

    private let validator: SafetyLimitsValidator
    private let trace: TraceSource
    private let log: any TraceReplayLogging
    private let clock: any Clock
    private nonisolated let streams = TraceReplayStreams()
    private var active = false
    private var hasActivated = false
    private var latestGlucose: GlucoseSample?
    private var halt: DriverFailure?
    internal private(set) var cursor = 0
    internal private(set) var frameResults: [TraceFrameResult] = []

    public init(
        validator: SafetyLimitsValidator,
        trace: TraceSource = .bundled(name: TraceReplayDriver.defaultTraceName),
        log: some TraceReplayLogging = OSTraceReplayLog(),
        clock: some Clock = SystemClock()
    ) {
        self.validator = validator
        self.trace = trace
        self.log = log
        self.clock = clock
    }

    public nonisolated func capability(_ capability: Capability) -> CapabilityPort? {
        switch capability {
        case .glucoseSource: .glucoseSource(TraceReplayGlucosePort(readings: streams.glucose, driver: self))
        case .insulinSource: .insulinSource(TraceReplayInsulinPort(insulinOnBoard: streams.insulin, driver: self))
        case .pumpStatus, .bgmSource, .dataSync, .doseCategoryProvider: nil
        }
    }

    public func activate() async throws(DriverFailure) {
        guard !active || halt != nil else { return }
        if hasActivated { streams.renew() }
        hasActivated = true
        active = true
        halt = nil
        cursor = 0
        latestGlucose = nil
        frameResults = []
        let file: TraceFile
        do {
        switch trace {
        case .data(let data): file = try TraceFile.load(data)
        case .bundled(let name):
            guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Traces"),
                  let data = try? Data(contentsOf: url) else {
                throw DriverFailure.decodeFailed(detail: "trace file")
            }
            file = try TraceFile.load(data)
        }
        } catch {
            active = false
            streams.finish()
            throw DriverFailure.decodeFailed(detail: "trace file")
        }
        let mapper = TandemReadMapper(validator: validator)
        let startedAt = clock.now
        let newest = file.frames.map(\.receivedAt).max() ?? startedAt
        let offset = startedAt.timeIntervalSince(newest)
        for (index, frame) in file.frames.enumerated() {
            do {
                var assembler = TandemPacketAssembler()
                var message: TandemMessage?
                for (partIndex, notification) in frame.notifications.enumerated() {
                    if let assembled = try assembler.feed(notification) {
                        guard partIndex == frame.notifications.count - 1, message == nil,
                              assembled.count >= 3,
                              assembled.count == 3 + Int(assembled[2]) + 2,
                              let decoded = TandemMessage.decode(assembled, channel: frame.channel) else {
                            throw DriverFailure.decodeFailed(detail: "frame")
                        }
                        message = decoded
                    }
                }
                guard let message else { throw DriverFailure.decodeFailed(detail: "frame") }
                let outcome = try mapper.map(message, receivedAt: frame.receivedAt, pumpTimeZone: file.pumpTimeZone)
                let replayedAt = frame.receivedAt.addingTimeInterval(offset)
                let shifted: TandemReadOutcome
                switch outcome {
                case .glucose(let sample):
                    let value = GlucoseSample(glucose: sample.glucose, recordedAt: replayedAt, trend: sample.trend)
                    latestGlucose = value
                    streams.yield(value)
                    shifted = .glucose(value)
                case .insulinOnBoard(let sample):
                    let value = try InsulinOnBoardSample(units: sample.units, calculatedAt: replayedAt)
                    streams.yield(value)
                    shifted = .insulinOnBoard(value)
                case .outOfRange(let side, _):
                    log.outOfRange(frame: index, side: side)
                    shifted = .outOfRange(side, recordedAt: replayedAt)
                case .sensorReadingUnusable(let status):
                    log.sensorReadingUnusable(frame: index, egvStatusID: status)
                    shifted = outcome
                case .notRead:
                    log.notRead(frame: index)
                    shifted = outcome
                }
                frameResults.append(.read(shifted))
                cursor += 1
            } catch let failure as DriverFailure {
                switch failure {
                case .valueRejected(let bound):
                    frameResults.append(.valueRejected(bound: bound))
                    log.valueRejected(frame: index, bound: bound)
                    cursor += 1
                default:
                    let normalized = DriverFailure.decodeFailed(detail: "frame")
                    frameResults.append(.decodeFailed(detail: "frame"))
                    log.halted(frame: index, detail: "frame")
                    halt = normalized
                    return
                }
            } catch {
                frameResults.append(.decodeFailed(detail: "frame"))
                log.halted(frame: index, detail: "frame")
                halt = .decodeFailed(detail: "frame")
                return
            }
        }
    }

    public func deactivate() async {
        active = false
        latestGlucose = nil
        halt = nil
        streams.finish()
        // The finished streams are spent, so the next activation must renew them
        // even when no activation preceded this teardown.
        hasActivated = true
    }

    func currentGlucose() throws(DriverFailure) -> GlucoseSample? {
        if let halt { throw halt }
        return latestGlucose
    }
    func doses(since: Date) throws(DriverFailure) -> [DoseRecord] {
        if let halt { throw halt }
        return []
    }
}
