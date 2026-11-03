import Foundation

public enum TandemPumpModel: Hashable, Sendable {
    case tslimX2, mobi, unknown

    public var displayName: String {
        switch self {
        case .tslimX2: "t:slim X2"
        case .mobi: "Mobi"
        case .unknown: "Unknown Tandem Pump"
        }
    }
    public var hasScreen: Bool? {
        switch self {
        case .tslimX2: true
        case .mobi: false
        case .unknown: nil
        }
    }

    public static func fromAdvertisedName(_ name: String?) -> Self {
        guard let name else { return .unknown }
        let normalized = name.split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" })
            .joined(separator: " ")
        let folded = normalized.lowercased()
        if folded.hasPrefix("tslim x2") || folded.hasPrefix("t:slim x2") { return .tslimX2 }
        if folded.hasPrefix("tandem mobi") { return .mobi }
        return .unknown
    }
}
