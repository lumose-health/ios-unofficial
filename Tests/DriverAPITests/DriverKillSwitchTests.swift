import Foundation
import Testing

@testable import DriverAPI

@Suite("Trace-Replay build switch")
struct DriverKillSwitchTests {
    @Test func packageAndAppConditionsAgreeAndNameADeclaredDriver() throws {
        let root = DriverAPISource.repositoryRoot
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let project = try String(contentsOf: root.appendingPathComponent("Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj"), encoding: .utf8)
        let enabled = try #require(manifest.range(of: #"let traceReplayDriverEnabled = (true|false)"#, options: .regularExpression))
        let enabledValue = manifest[enabled].hasSuffix("true")
        let condition = "TRACE_REPLAY_DRIVER_ENABLED"
        let appConfigurationIDs = [
            "A10000000000000000000060",
            "A10000000000000000000061",
            "A10000000000000000000062",
        ]
        for id in appConfigurationIDs {
            let line = try #require(project.components(separatedBy: .newlines).first { $0.contains("\(id) = {isa = XCBuildConfiguration") })
            #expect(line.contains(condition) == enabledValue, "\(id) must agree with Package.swift")
        }

        let gatedDrivers = [(condition: condition, target: "TraceReplayDriver")]
        for gate in gatedDrivers {
            let targetPattern = #"\.target\([^)]*name: "\#(gate.target)"[^)]*path: "Sources/Drivers/"#
            #expect(manifest.range(of: targetPattern, options: .regularExpression) != nil,
                    "\(gate.condition) must name a declared Driver target")
        }
    }
}
