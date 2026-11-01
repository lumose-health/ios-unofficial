import Foundation
import DriverAPI

public enum PumpConnectionState: Sendable, Equatable {
    /// The platform's view of FR-8's model until a pump Driver reports one.
    case disconnected, scanning, connecting, authenticating, authFailed, connected, reconnecting
}

public enum StatusGlyph: CaseIterable, Sendable, Equatable { case linked, searching, reconnecting, crossedOut, cloudSlash, syncProgress, transfer, cloudCheck }
public enum StatusColor: Sendable, Equatable { case primary, caution, error, muted }

public struct PumpLinkIndicator: Sendable, Equatable {
    public let glyph: StatusGlyph
    public let color: StatusColor
    public let text: String?
    public let accessibilityLabel: String

    public static func make(_ state: PumpConnectionState) -> Self {
        switch state {
        case .connected: .init(glyph: .linked, color: .primary, text: nil, accessibilityLabel: "Pump connected")
        case .connecting, .authenticating: .init(glyph: .searching, color: .caution, text: "Connecting...", accessibilityLabel: "Connecting to pump")
        case .reconnecting: .init(glyph: .reconnecting, color: .caution, text: "Reconnecting...", accessibilityLabel: "Reconnecting to pump")
        case .scanning: .init(glyph: .searching, color: .caution, text: "Scanning...", accessibilityLabel: "Scanning for pump")
        case .authFailed: .init(glyph: .crossedOut, color: .error, text: "Pairing failed", accessibilityLabel: "Pump pairing failed")
        case .disconnected: .init(glyph: .crossedOut, color: .muted, text: "No pump", accessibilityLabel: "No pump connected")
        }
    }
}

public struct BackendSyncInput: Sendable, Equatable {
    public let hasError: Bool
    public let pendingCount: Int
    public let lastSync: Date?
    public init(hasError: Bool, pendingCount: Int, lastSync: Date?) { self.hasError = hasError; self.pendingCount = pendingCount; self.lastSync = lastSync }
}
public enum BackendReachability: Sendable, Equatable { case reachable, backendUnreachable, offline }
public struct BackendStatus: Sendable, Equatable {
    public let sync: BackendSyncInput
    public let reachability: BackendReachability
    public init(sync: BackendSyncInput, reachability: BackendReachability) { self.sync = sync; self.reachability = reachability }
}
public enum BackendConfiguration: Sendable, Equatable { case notConfigured, configured(BackendStatus) }

public struct SyncIndicator: Sendable, Equatable {
    public let glyph: StatusGlyph
    public let color: StatusColor
    public let accessibilityLabel: String
    public static func make(_ input: BackendSyncInput) -> Self {
        if input.hasError { .init(glyph: .cloudSlash, color: .error, accessibilityLabel: "Sync error") }
        else if input.pendingCount > 0 { .init(glyph: .syncProgress, color: .caution, accessibilityLabel: "\(input.pendingCount) readings pending sync") }
        else if input.lastSync != nil { .init(glyph: .transfer, color: .primary, accessibilityLabel: "Synced to cloud") }
        else { .init(glyph: .cloudSlash, color: .muted, accessibilityLabel: "Not synced") }
    }
}
public struct ReachabilityIndicator: Sendable, Equatable {
    public let glyph: StatusGlyph
    public let color: StatusColor
    public let text: String?
    public let accessibilityLabel: String
    public static func make(_ state: BackendReachability) -> Self {
        switch state {
        case .reachable: .init(glyph: .cloudCheck, color: .primary, text: nil, accessibilityLabel: "Backend reachable")
        case .backendUnreachable: .init(glyph: .cloudSlash, color: .error, text: "Backend unreachable", accessibilityLabel: "Backend unreachable")
        case .offline: .init(glyph: .cloudSlash, color: .error, text: "Offline", accessibilityLabel: "Device offline")
        }
    }
}

public struct BrandMark: Sendable, Equatable {
    public let name: String
    public let assetName: String
    public let height: Double
    public init(name: String, assetName: String, height: Double) { self.name = name; self.assetName = assetName; self.height = height }
    /// UI-test handle for this mark: `status.brand.<name lowercased>`.
    public var accessibilityIdentifier: String { "status.brand.\(name.lowercased())" }
}
public enum DriverBrandMarks {
    public typealias Lookup = @Sendable (DriverIdentifier) -> BrandMark?
    public static let productionLookup: Lookup = { _ in nil }
    public static func make(_ identifiers: [DriverIdentifier], lookup: Lookup = productionLookup) -> [DriverBrandMark] {
        identifiers.sorted { $0.rawValue < $1.rawValue }.compactMap { id in lookup(id).map { (id, $0) } }
            .map { DriverBrandMark(identifier: $0.0, mark: $0.1) }
    }
}

public struct DriverBrandMark: Sendable, Equatable, Identifiable {
    public let identifier: DriverIdentifier
    public let mark: BrandMark
    public var id: DriverIdentifier { identifier }
}

public struct StatusRowState: Sendable, Equatable {
    public let pumpLink: PumpLinkIndicator
    public let sync: SyncIndicator?
    public let reachability: ReachabilityIndicator?
    public let marks: [DriverBrandMark]
    public static func make(connection: PumpConnectionState, backend: BackendConfiguration, activeDrivers: [DriverIdentifier], brandLookup: DriverBrandMarks.Lookup = DriverBrandMarks.productionLookup) -> Self {
        let sync: SyncIndicator?, reachability: ReachabilityIndicator?
        switch backend {
        case .notConfigured: sync = nil; reachability = nil
        case .configured(let status): sync = .make(status.sync); reachability = .make(status.reachability)
        }
        return .init(pumpLink: .make(connection), sync: sync, reachability: reachability, marks: DriverBrandMarks.make(activeDrivers, lookup: brandLookup))
    }
}
