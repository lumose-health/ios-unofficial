import Foundation
import Testing

@Suite("Threshold source boundary")
struct AlertThresholdSourceBoundaryTests {
    @Test func displayTargetRangeCannotArmAlertThresholds() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(files.contains { $0.hasSuffix("/TargetRange.swift") })
        #expect(files.contains { $0.hasSuffix("/AlertThresholds.swift") })
        for path in files {
            let source = try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
            #expect(!(source.contains("TargetRange") && source.contains("AlertThreshold")), "\(path) mixes display defaults with alert settings")
        }
    }
}
