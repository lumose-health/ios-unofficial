import Foundation
import Testing
import DomainCore

@Suite("Driver selection file")
struct FileDriverSelectionStoreTests {
    private func fixture() -> (URL, FileDriverSelectionStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (root, FileDriverSelectionStore(fileURL: root.appendingPathComponent("nested/selection.json")))
    }

    @Test func missingFileAndParent() throws {
        let (root, store) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try store.load().isEmpty)
        try store.save(["test.pump.alpha"])
        #expect(try FileDriverSelectionStore(fileURL: store.fileURL).load() == ["test.pump.alpha"])
    }

    @Test func sortedJSON() throws {
        let (root, store) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(["test.pump.bravo", "test.pump.alpha"])
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text == "{\"activeDriverIDs\":[\"test.pump.alpha\",\"test.pump.bravo\"],\"version\":1}")
    }

    @Test func malformedAndNewerVersion() throws {
        let (root, store) = fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.fileURL)
        #expect(throws: DriverSelectionStoreFailure.self) { try store.load() }
        try Data("{\"activeDriverIDs\":[],\"version\":2}".utf8).write(to: store.fileURL)
        do { _ = try store.load(); Issue.record("new version was accepted") }
        catch { #expect(error == .unsupportedVersion(2)) }
    }
}
