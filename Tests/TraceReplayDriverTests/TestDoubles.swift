#if TRACE_REPLAY_DRIVER_ENABLED
import SafetyCore
import Foundation
@testable import TraceReplayDriver
import TandemWire

final class RecordingTraceLog: TraceReplayLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    var recorded: [String] { lock.lock(); defer { lock.unlock() }; return calls }
    private func append(_ call: String) { lock.lock(); defer { lock.unlock() }; calls.append(call) }
    func valueRejected(frame: Int, bound: String) { append("rejected:\(frame):\(bound)") }
    func sensorReadingUnusable(frame: Int, egvStatusID: UInt8) { append("unusable:\(frame):\(egvStatusID)") }
    func outOfRange(frame: Int, side: TandemGlucoseRangeSide) { append("range:\(frame):\(side)") }
    func notRead(frame: Int) { append("notRead:\(frame)") }
    func halted(frame: Int, detail: String) { append("halt:\(frame):\(detail)") }
}

struct FixedTraceClock: Clock { let now: Date }
#endif
