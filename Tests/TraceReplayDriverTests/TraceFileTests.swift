#if TRACE_REPLAY_DRIVER_ENABLED
import Foundation
import Testing
import DriverAPI
@testable import TraceReplayDriver

@Suite("Trace file format")
struct TraceFileTests {
    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "tandem-decode-failure-01", withExtension: "json", subdirectory: "Traces"))
        return try Data(contentsOf: url)
    }

    @Test("Every committed trace has valid provenance and format")
    func allCommittedTraces() throws {
        let testURL = try #require(Bundle.module.resourceURL?.appendingPathComponent("Traces"))
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Drivers/TraceReplay/Traces")
        for directory in [testURL, sourceURL] {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            #expect(!files.isEmpty)
            for url in files {
                let trace = try TraceFile.load(Data(contentsOf: url))
                #expect(["synthesized", "deidentified-capture"].contains(trace.provenance.source))
                if trace.provenance.source == "deidentified-capture" {
                    #expect(!(trace.provenance.reviewedBy ?? "").isEmpty)
                }
            }
        }
    }

    @Test("Unknown and malformed fields fail as trace file errors")
    func malformedFields() throws {
        let data = try fixture()
        let original = try #require(String(data: data, encoding: .utf8))
        let variants = [
            original.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2"),
            original.replacingOccurrences(of: "\"vendor\": \"tandem\"", with: "\"vendor\": \"medtronic\""),
            original.replacingOccurrences(of: "\"pumpTimeZone\": \"America/Chicago\"", with: "\"pumpTimeZone\": \"Unknown/Zone\""),
            original.replacingOccurrences(of: "\"reviewedBy\": null", with: "\"reviewedBy\": null, \"serialNumber\": \"secret\""),
            original.replacingOccurrences(of: "\"note\": \"VALID reading\"", with: "\"serialNumber\": \"secret\", \"note\": \"VALID reading\""),
            original.replacingOccurrences(of: "\"source\": \"synthesized\"", with: "\"source\": \"deidentified-capture\""),
            original.replacingOccurrences(of: "000123010880e80d20780001008a84", with: "abc"),
            original.replacingOccurrences(of: "000123010880e80d20780001008a84", with: "ABCDEF"),
            original.replacingOccurrences(of: "\"format\": \"glycemicgpt-trace\"", with: "\"extra\": 1, \"format\": \"glycemicgpt-trace\""),
        ]
        for variant in variants {
            #expect(throws: DriverFailure.decodeFailed(detail: "trace file")) {
                _ = try TraceFile.load(Data(variant.utf8))
            }
        }
    }

    @Test("Receive times that go backwards are rejected")
    func backwardsReceiveTime() throws {
        let original = try #require(String(data: try fixture(), encoding: .utf8))
        let backwards = original.replacingOccurrences(of: "\"receivedAt\": \"2025-01-15T14:10:05Z\"", with: "\"receivedAt\": \"2025-01-15T14:05:04Z\"")
        #expect(backwards != original)
        #expect(throws: DriverFailure.decodeFailed(detail: "trace file")) {
            _ = try TraceFile.load(Data(backwards.utf8))
        }
        let equal = original.replacingOccurrences(of: "\"receivedAt\": \"2025-01-15T14:10:05Z\"", with: "\"receivedAt\": \"2025-01-15T14:05:05Z\"")
        #expect(throws: Never.self) { _ = try TraceFile.load(Data(equal.utf8)) }
    }

    @Test("Oversized files and frame counts are rejected")
    func sizeBounds() throws {
        let original = try #require(String(data: try fixture(), encoding: .utf8))
        let padding = String(repeating: " ", count: TraceFile.maximumFileBytes)
        #expect(throws: DriverFailure.decodeFailed(detail: "trace file")) {
            _ = try TraceFile.load(Data((original + padding).utf8))
        }
        let frame = #"{"channel": "currentStatus", "receivedAt": "2025-01-15T14:00:05Z", "notifications": ["000123010880e80d20780001008a84"], "note": "VALID reading"}"#
        let framesStart = try #require(original.range(of: "\"frames\": ["))
        let head = original[..<framesStart.upperBound]
        func trace(frames count: Int) -> Data {
            Data((head + Array(repeating: frame, count: count).joined(separator: ",") + "]}").utf8)
        }
        #expect(throws: Never.self) { _ = try TraceFile.load(trace(frames: TraceFile.maximumFrameCount)) }
        #expect(throws: DriverFailure.decodeFailed(detail: "trace file")) {
            _ = try TraceFile.load(trace(frames: TraceFile.maximumFrameCount + 1))
        }
    }
}
#endif
