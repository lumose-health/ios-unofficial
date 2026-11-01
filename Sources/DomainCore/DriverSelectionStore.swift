import Foundation

/// Stores raw identifiers so absent Drivers survive an app upgrade.
public protocol DriverSelectionStore: Sendable {
    func load() throws(DriverSelectionStoreFailure) -> Set<String>
    func save(_ ids: Set<String>) throws(DriverSelectionStoreFailure)
}

public enum DriverSelectionStoreFailure: Error, Hashable, Sendable {
    /// The file exists but could not be read now, for example before first unlock.
    case unavailable(detail: String)
    /// The file was read but its contents are not a selection.
    case unreadable(detail: String)
    case unwritable(detail: String)
    case unsupportedVersion(Int)

    /// Whether a later load may succeed without anything rewriting the file.
    public var isTransient: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

/// An app-container file that survives relaunch and upgrade, but not app deletion.
public struct FileDriverSelectionStore: DriverSelectionStore {
    public static let formatVersion = 1
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    private struct SelectionFile: Codable {
        let activeDriverIDs: [String]
        let version: Int
    }

    public func load() throws(DriverSelectionStoreFailure) -> Set<String> {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && failure.code == CocoaError.fileReadNoSuchFile.rawValue {
                return []
            }
            throw .unavailable(detail: String(describing: error))
        }
        let file: SelectionFile
        do { file = try JSONDecoder().decode(SelectionFile.self, from: data) }
        catch { throw .unreadable(detail: String(describing: error)) }
        guard file.version == Self.formatVersion else { throw .unsupportedVersion(file.version) }
        return Set(file.activeDriverIDs)
    }

    public func save(_ ids: Set<String>) throws(DriverSelectionStoreFailure) {
        do {
            let file = SelectionFile(activeDriverIDs: ids.sorted(), version: Self.formatVersion)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(file)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            #if os(iOS) || os(watchOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: [.atomic])
            #endif
        } catch {
            throw .unwritable(detail: String(describing: error))
        }
    }
}
