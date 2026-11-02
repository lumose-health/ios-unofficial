import Foundation

/// A validated key in one Driver's settings namespace.
public struct DriverSettingKey: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        let scalars = Array(rawValue.unicodeScalars)
        guard (1...128).contains(scalars.count),
              let first = scalars.first,
              first.isASCII && CharacterSet.letters.contains(first) else { return nil }
        guard scalars.dropFirst().allSatisfy({ scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) ||
                               scalar == "_" || scalar == "." || scalar == "-")
        }) else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public enum DriverSettingValue: Hashable, Sendable, Codable {
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case text(String)
}

/// Read-only settings for one Driver, namespaced by its DriverIdentifier.
/// The platform writes these values. Do not store credentials, pairing codes,
/// or other secrets here (SI-10). Settings never take part in glucose or dose validation.
public protocol DriverSettings: Sendable {
    func value(for key: DriverSettingKey) -> DriverSettingValue?
}

extension DriverSettings {
    public func bool(for key: DriverSettingKey) -> Bool? {
        if case .bool(let value) = value(for: key) { return value }
        return nil
    }

    public func integer(for key: DriverSettingKey) -> Int? {
        if case .integer(let value) = value(for: key) { return value }
        return nil
    }

    public func number(for key: DriverSettingKey) -> Double? {
        if case .number(let value) = value(for: key) { return value }
        return nil
    }

    public func text(for key: DriverSettingKey) -> String? {
        if case .text(let value) = value(for: key) { return value }
        return nil
    }
}
