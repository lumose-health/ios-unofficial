import Foundation

public enum TandemScanTiming {
    // FR-4; the 10-second age-out is an assumption pending device validation.
    public static let ageOut: TimeInterval = 10
    // FR-4; the 120-second idle stop is an assumption pending product confirmation.
    public static let idleStop: TimeInterval = 120
    // FR-4 housekeeping cadence.
    public static let housekeeping: TimeInterval = 1
    // Core Bluetooth reports 127 when signal strength is unavailable.
    public static let unavailableRSSI = 127
}
