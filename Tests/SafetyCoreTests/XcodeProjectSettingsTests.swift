import Foundation
import Testing

@Suite("Xcode project settings")
struct XcodeProjectSettingsTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    @Test func bluetoothUsageDescriptionIsPresentOnEveryAppConfiguration() throws {
        let source = try String(contentsOf: Self.root.appendingPathComponent("Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj"), encoding: .utf8)
        let expected = "GlycemicGPT uses Bluetooth to connect to your insulin pump and read its status. It never sends commands that change your insulin delivery."
        let key = "INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = \"\(expected)\";"
        for id in ["A10000000000000000000060", "A10000000000000000000061", "A10000000000000000000062"] {
            let line = try #require(source.components(separatedBy: .newlines).first { $0.contains(id + " = {") })
            #expect(line.contains(key))
        }
        #expect(source.components(separatedBy: "INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription =").count - 1 == 3)
    }
}
