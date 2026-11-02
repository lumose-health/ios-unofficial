import Foundation
import DriverAPI

public enum DriverSettingsStoreFailure: Error, Hashable, Sendable {
    case unreadable(detail: String)
    case unwritable(detail: String)
    case nonFiniteNumber
}

/// Platform-owned settings files. Each handle is bound to one Driver identifier.
public final class FileDriverSettingsStore: @unchecked Sendable {
    private struct SettingsFile: Codable {
        let version: Int
        var values: [String: DriverSettingValue]
    }

    private struct Handle: DriverSettings {
        let store: FileDriverSettingsStore
        let driver: DriverIdentifier

        func value(for key: DriverSettingKey) -> DriverSettingValue? {
            store.value(for: key, driver: driver)
        }
    }

    private let directory: URL
    private let lock = NSLock()
    private var cache: [DriverIdentifier: [String: DriverSettingValue]] = [:]

    public init(directory: URL) { self.directory = directory }

    public func settings(for driver: DriverIdentifier) -> any DriverSettings {
        Handle(store: self, driver: driver)
    }

    public func save(_ value: DriverSettingValue, for key: DriverSettingKey,
                     driver: DriverIdentifier) throws(DriverSettingsStoreFailure) {
        if case .number(let number) = value, !number.isFinite { throw .nonFiniteNumber }
        lock.lock()
        defer { lock.unlock() }
        var values = try load(driver)
        values[key.rawValue] = value
        try write(values, driver: driver)
        cache[driver] = values
    }

    public func removeValue(for key: DriverSettingKey,
                            driver: DriverIdentifier) throws(DriverSettingsStoreFailure) {
        lock.lock()
        defer { lock.unlock() }
        var values = try load(driver)
        values.removeValue(forKey: key.rawValue)
        try write(values, driver: driver)
        cache[driver] = values
    }

    private func value(for key: DriverSettingKey, driver: DriverIdentifier) -> DriverSettingValue? {
        lock.lock()
        defer { lock.unlock() }
        guard let values = try? load(driver) else { return nil }
        return values[key.rawValue]
    }

    /// Lowercased so the name means the same file on case-sensitive and
    /// case-insensitive volumes. The registry refuses identifiers that differ
    /// only in case, so no two Drivers share a file.
    private func fileURL(for driver: DriverIdentifier) -> URL {
        directory.appendingPathComponent(driver.rawValue.lowercased() + ".json")
    }

    /// Records only the Driver and the kind of failure; the file's contents and
    /// the underlying error text stay out of the log.
    private func logUnreadable(_ driver: DriverIdentifier, kind: String) {
        NSLog("Driver settings file unreadable for %@: %@", driver.rawValue, kind)
    }

    private func load(_ driver: DriverIdentifier) throws(DriverSettingsStoreFailure) -> [String: DriverSettingValue] {
        if let cached = cache[driver] { return cached }
        let url = fileURL(for: driver)
        guard FileManager.default.fileExists(atPath: url.path) else {
            cache[driver] = [:]
            return [:]
        }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch {
            logUnreadable(driver, kind: "read failed")
            throw .unreadable(detail: String(describing: error))
        }
        let file: SettingsFile
        do { file = try JSONDecoder().decode(SettingsFile.self, from: data) }
        catch {
            logUnreadable(driver, kind: "corrupt")
            throw .unreadable(detail: String(describing: error))
        }
        guard file.version == 1 else {
            logUnreadable(driver, kind: "unsupported version")
            throw .unreadable(detail: "Unsupported settings format version")
        }
        cache[driver] = file.values
        return file.values
    }

    private func write(_ values: [String: DriverSettingValue],
                       driver: DriverIdentifier) throws(DriverSettingsStoreFailure) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(SettingsFile(version: 1, values: values))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS) || os(watchOS)
            try data.write(to: fileURL(for: driver), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL(for: driver), options: [.atomic])
            #endif
        } catch { throw .unwritable(detail: String(describing: error)) }
    }
}
