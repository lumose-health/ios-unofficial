import Foundation

/// Process-local monotonic maximum of observed wall time (FR-72).
public struct WallClockHighWaterMark: Sendable {
    private var latest: Date?

    public init() {}

    public func isRewound(at now: Date) -> Bool {
        guard let latest else { return false }
        return now.addingTimeInterval(SafetyConstants.alertFloorMaxFutureSkew) < latest
    }

    public mutating func observe(_ now: Date) {
        if let latest {
            if now > latest { self.latest = now }
        } else {
            latest = now
        }
    }
}

public enum AlertDataTrustResult: Hashable, Sendable {
    case trusted, clockRewound, thresholdsNotConfigured, notFresh
}

public enum AlertDataTrust {
    public static func evaluate(
        sensorTimestamp: Date,
        thresholds: AlertThresholdSetting,
        now: Date,
        mark: inout WallClockHighWaterMark,
        freshness: FreshnessThresholds = FreshnessPolicy.cgm
    ) -> AlertDataTrustResult {
        if mark.isRewound(at: now) { return .clockRewound }
        mark.observe(now)
        guard thresholds.configuredThresholds != nil else { return .thresholdsNotConfigured }
        guard AlertFloorEligibility.isEligible(age: now.timeIntervalSince(sensorTimestamp), thresholds: freshness) else {
            return .notFresh
        }
        return .trusted
    }
}

public enum BackendAlertingStatus: Hashable, Sendable {
    case notConfigured
    case configured(networkReachable: Bool, streamConnected: Bool, backendHasFreshGlucose: Bool?)

    public var isDegraded: Bool {
        switch self {
        case .notConfigured: true
        case .configured(let reachable, let connected, let fresh):
            !reachable || !connected || fresh != true
        }
    }
}
