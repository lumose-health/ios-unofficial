import Foundation
import Testing
@testable import TandemWire

@Suite("Tandem pump time")
struct TandemPumpTimeTests {
    @Test func localWallClockAcrossZonesAndTransitions() throws {
        let rows: [(UInt32, String, String)] = [
            (506160000, "UTC", "2024-01-15T08:00:00Z"),
            (506160000, "America/Chicago", "2024-01-15T14:00:00Z"),
            (506160000, "Australia/Sydney", "2024-01-14T21:00:00Z"),
            (520678800, "America/Chicago", "2024-07-01T14:00:00Z"),
            (520678800, "Australia/Sydney", "2024-06-30T23:00:00Z"),
            (510892200, "America/Chicago", "2024-03-10T08:30:00Z"),
            (531451800, "America/Chicago", "2024-11-03T06:30:00Z"),
            (471039176, "UTC", "2022-12-04T20:12:56Z"),
        ]
        let formatter = ISO8601DateFormatter()
        for (seconds, zoneID, expected) in rows {
            let zone = try #require(TimeZone(identifier: zoneID))
            let date = try #require(TandemPumpTime.date(pumpSeconds: seconds, in: zone))
            #expect(formatter.string(from: date) == expected)
        }
    }
}
