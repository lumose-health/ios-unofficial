/// The four boundaries used to colour a glucose value on the phone and wrist.
/// This range is independent of the thresholds that govern alerts (SI-3).
public struct TargetRange: Hashable, Sendable {
    public let urgentLow: Double
    public let low: Double
    public let high: Double
    public let urgentHigh: Double

    public init(urgentLow: Double, low: Double, high: Double, urgentHigh: Double) throws {
        let bounds = SafetyConstants.glucoseValidRange
        guard urgentLow.isFinite, low.isFinite, high.isFinite, urgentHigh.isFinite,
              bounds.lowerBound <= urgentLow, urgentLow <= low, low < high,
              high <= urgentHigh, urgentHigh <= bounds.upperBound else {
            throw TargetRangeError.invalidBoundaries
        }
        self.urgentLow = urgentLow
        self.low = low
        self.high = high
        self.urgentHigh = urgentHigh
    }

    // Android GlucoseRangeStore.kt:66-69 and GlucoseHero.kt:44-56.
    // `try!` is safe because these fixed defaults satisfy every validated boundary.
    public static let `default` = try! TargetRange(urgentLow: 55, low: 70, high: 180, urgentHigh: 250)

    public func severity(of glucose: Glucose) -> GlucoseSeverity {
        let value = glucose.mgdl.rounded(.toNearestOrAwayFromZero)
        // Time-in-range buckets deliberately have different boundary rules (FR-58).
        if value <= urgentLow { return .urgentLow }
        if value <= low { return .low }
        if value < high { return .inRange }
        if value < urgentHigh { return .high }
        return .urgentHigh
    }
}

public enum TargetRangeError: Error, Hashable, Sendable {
    case invalidBoundaries
}

public enum GlucoseSeverity: Hashable, Sendable {
    case urgentLow, low, inRange, high, urgentHigh
}
