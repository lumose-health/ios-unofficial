/// User or Backend alert boundaries. No default alert thresholds exist (SI-5).
public struct AlertThresholds: Hashable, Sendable {
    public let urgentLow: Int
    public let low: Int
    public let high: Int
    public let urgentHigh: Int

    public init(urgentLow: Int, low: Int, high: Int, urgentHigh: Int) throws(AlertThresholdsError) {
        let bounds = SafetyConstants.glucoseValidRange
        guard Double(urgentLow) >= bounds.lowerBound,
              urgentLow <= low, low < high, high <= urgentHigh,
              Double(urgentHigh) <= bounds.upperBound else {
            throw .invalidOrdering
        }
        self.urgentLow = urgentLow
        self.low = low
        self.high = high
        self.urgentHigh = urgentHigh
    }
}

public enum AlertThresholdsError: Error, Hashable, Sendable {
    case invalidOrdering
}

public enum AlertThresholdProvenance: Hashable, Sendable {
    case local, backend
}

public enum AlertThresholdSetting: Hashable, Sendable {
    case notConfigured
    case configured(AlertThresholds, AlertThresholdProvenance)

    public var configuredThresholds: AlertThresholds? {
        guard case .configured(let thresholds, _) = self else { return nil }
        return thresholds
    }
}

public enum AlertClassifier {
    public static func classify(_ glucose: Glucose, against thresholds: AlertThresholds) -> AlertType? {
        let value = glucose.mgdl.rounded(.toNearestOrAwayFromZero)
        if value <= Double(thresholds.urgentLow) { return .lowUrgent }
        if value >= Double(thresholds.urgentHigh) { return .highUrgent }
        if value <= Double(thresholds.low) { return .lowWarning }
        if value >= Double(thresholds.high) { return .highWarning }
        return nil
    }
}
