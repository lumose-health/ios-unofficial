import Foundation
import Testing
import DriverAPI
import DomainCore

@Suite("Driver settings files")
struct DriverSettingsStoreTests {
    private var first: DriverIdentifier { DriverIdentifier("test.settings.first")! }
    private var second: DriverIdentifier { DriverIdentifier("test.settings.second")! }
    private var key: DriverSettingKey { DriverSettingKey("display.mode")! }

    @Test func valuesSurviveNewStoreAndStayNamespaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileDriverSettingsStore(directory: directory)
        let values: [(DriverSettingKey, DriverSettingValue)] = [
            (DriverSettingKey("enabled")!, .bool(true)),
            (DriverSettingKey("count")!, .integer(3)),
            (DriverSettingKey("ratio")!, .number(1.5)),
            (key, .text("compact"))
        ]
        for (key, value) in values { try store.save(value, for: key, driver: first) }
        let reopened = FileDriverSettingsStore(directory: directory)
        for (key, value) in values {
            #expect(reopened.settings(for: first).value(for: key) == value)
            #expect(reopened.settings(for: second).value(for: key) == nil)
        }
        #expect(reopened.settings(for: first).number(for: DriverSettingKey("count")!) == nil)
        try reopened.save(.text("other"), for: key, driver: second)
        try reopened.removeValue(for: key, driver: first)
        #expect(reopened.settings(for: first).text(for: key) == nil)
        #expect(reopened.settings(for: second).text(for: key) == "other")
    }

    @Test func fileNameIsTheLowercasedIdentifier() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mixed = DriverIdentifier("Test.Settings.Mixed")!
        try FileDriverSettingsStore(directory: directory).save(.bool(true), for: key, driver: mixed)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names == ["test.settings.mixed.json"])
        #expect(FileDriverSettingsStore(directory: directory).settings(for: mixed).value(for: key) == .bool(true))
    }

    @Test func refusesNonFiniteAndUnreadableFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileDriverSettingsStore(directory: directory)
        #expect(throws: DriverSettingsStoreFailure.nonFiniteNumber) {
            try store.save(.number(.infinity), for: key, driver: first)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("bad json".utf8).write(to: directory.appendingPathComponent(first.rawValue + ".json"))
        #expect(store.settings(for: first).value(for: key) == nil)
        #expect(throws: DriverSettingsStoreFailure.self) {
            try store.save(.text("value"), for: key, driver: first)
        }
    }
}
