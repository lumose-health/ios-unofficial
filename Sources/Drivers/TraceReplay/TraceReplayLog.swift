import Foundation
import OSLog
import TandemWire

public protocol TraceReplayLogging: Sendable {
    func valueRejected(frame: Int, bound: String)
    func sensorReadingUnusable(frame: Int, egvStatusID: UInt8)
    func outOfRange(frame: Int, side: TandemGlucoseRangeSide)
    func notRead(frame: Int)
    func halted(frame: Int, detail: String)
}

public struct OSTraceReplayLog: TraceReplayLogging {
    private let logger = Logger(subsystem: "com.glycemicgpt.ios", category: "TraceReplayDriver")
    public init() {}
    public func valueRejected(frame: Int, bound: String) {
        logger.notice("frame \(frame) rejected by \(bound, privacy: .public)")
    }
    public func sensorReadingUnusable(frame: Int, egvStatusID: UInt8) {
        logger.notice("frame \(frame) unusable status \(egvStatusID)")
    }
    public func outOfRange(frame: Int, side: TandemGlucoseRangeSide) {
        logger.notice("frame \(frame) outside sensor range: \(String(describing: side), privacy: .public)")
    }
    public func notRead(frame: Int) { logger.notice("frame \(frame) has no reading") }
    public func halted(frame: Int, detail: String) {
        logger.error("frame \(frame) halted: \(detail, privacy: .public)")
    }
}
