/// Open reason vocabulary shared by coverage consumers (FR-83).
public struct NotWatchingReason: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let notificationsDenied = Self(rawValue: "NOTIFICATIONS_DENIED")
    public static let thresholdsNotSynced = Self(rawValue: "THRESHOLDS_NOT_SYNCED")
    public static let thresholdsNotConfigured = Self(rawValue: "THRESHOLDS_NOT_CONFIGURED")
    public static let pumpDisconnected = Self(rawValue: "PUMP_DISCONNECTED")
    public static let noFreshReading = Self(rawValue: "NO_FRESH_READING")
    public static let backendHasNoData = Self(rawValue: "BACKEND_HAS_NO_DATA")
    public static let safetyLimitsTooNarrow = Self(rawValue: "SAFETY_LIMITS_TOO_NARROW")
    public static let clockUntrusted = Self(rawValue: "CLOCK_UNTRUSTED")
}
