import Foundation
import SafetyCore

public enum TandemPumpTime: Sendable {
    public static func date(pumpSeconds: UInt32, in zone: TimeZone) -> Date? {
        guard let utc = TimeZone(identifier: "UTC") else { return nil }
        let wallClock = Date(
            timeIntervalSince1970: SafetyConstants.tandemEpochOffset + TimeInterval(pumpSeconds)
        )
        var source = Calendar(identifier: .gregorian)
        source.timeZone = utc
        let parts = source.dateComponents([.year, .month, .day, .hour, .minute, .second], from: wallClock)
        var destination = Calendar(identifier: .gregorian)
        destination.timeZone = zone
        return destination.date(from: parts)
    }
}
