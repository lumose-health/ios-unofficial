/// Open wire-compatible names shared by the floor, Backend, and Watch (FR-65).
public struct AlertType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let lowUrgent = Self(rawValue: "low_urgent")
    public static let lowWarning = Self(rawValue: "low_warning")
    public static let highWarning = Self(rawValue: "high_warning")
    public static let highUrgent = Self(rawValue: "high_urgent")
    public static let iobWarning = Self(rawValue: "iob_warning")
    public static let noData = Self(rawValue: "no_data")

    public static let lowSet: Set<Self> = [.lowUrgent, .lowWarning]
    public static let highSet: Set<Self> = [.highWarning, .highUrgent]

    public var deliveryTier: AlertDeliveryTier {
        Self.lowSet.contains(self) || Self.highSet.contains(self) ? .interrupting : .informational
    }
}

public struct AlertSeverity: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let warning = Self(rawValue: "warning")
    public static let urgent = Self(rawValue: "urgent")
    public static let emergency = Self(rawValue: "emergency")
}

public enum AlertDeliveryTier: Hashable, Sendable {
    case interrupting, informational

    public func interruptionLevel(criticalAlertsEnabled: Bool) -> AlertInterruptionLevel {
        switch self {
        case .interrupting: criticalAlertsEnabled ? .critical : .timeSensitive
        case .informational: .active
        }
    }
}

public enum AlertInterruptionLevel: Hashable, Sendable {
    case critical, timeSensitive, active
}
