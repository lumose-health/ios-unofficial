import Foundation

/// Process-local wall-clock trust state (FR-72). It is never persisted: a rewind
/// while the process is dead leaves no mark, and the first evaluation afterwards
/// fails toward alarming.
///
/// A maximum of wall time alone cannot tell a clock correction from time passing,
/// because evaluations arrive minutes apart. Each observation therefore compares
/// how far the wall clock moved with how far the continuous clock moved.
public struct WallClockHighWaterMark: Sendable {
    private var mark: Date?
    private var lastWall: Date?
    private var lastElapsed: TimeInterval?
    private var suppressedSince: TimeInterval?

    public init() {}

    /// Forward drift beyond ``SafetyConstants/alertFloorMaxFutureSkew`` is a correction:
    /// the mark becomes `now` and any suppression ends. Backward drift beyond it is a
    /// rewind even when wall time is still above the mark. Suppression is timed on the
    /// continuous clock from its first observation, so a further backward step cannot
    /// extend it, and it ends at ``SafetyConstants/alertFloorClockSuppressionBound``.
    /// Repeating a call with the same two values changes nothing.
    public mutating func isRewound(at now: Date, elapsed: TimeInterval) -> Bool {
        guard let lastWall, let lastElapsed, let mark else {
            self.mark = now
            self.lastWall = now
            self.lastElapsed = elapsed
            return false
        }
        let expected = lastWall.addingTimeInterval(elapsed - lastElapsed)
        let drift = now.timeIntervalSince(expected)
        self.lastWall = now
        self.lastElapsed = elapsed
        let skew = SafetyConstants.alertFloorMaxFutureSkew
        if drift > skew {
            self.mark = now
            suppressedSince = nil
            return false
        }
        let currentMark = drift < -skew ? max(mark, expected) : mark
        if now.addingTimeInterval(skew) < currentMark {
            self.mark = currentMark
            let since = suppressedSince ?? elapsed
            suppressedSince = since
            if elapsed - since >= SafetyConstants.alertFloorClockSuppressionBound {
                self.mark = now
                suppressedSince = nil
                return false
            }
            return true
        }
        self.mark = max(currentMark, now)
        suppressedSince = nil
        return false
    }
}

public enum AlertDataTrustResult: Hashable, Sendable {
    case trusted, clockRewound, thresholdsNotConfigured, notFresh

    public func notWatchingReason(backendConfigured: Bool) -> NotWatchingReason? {
        switch self {
        case .trusted: nil
        case .clockRewound: .clockUntrusted
        case .notFresh: .noFreshReading
        case .thresholdsNotConfigured:
            backendConfigured ? .thresholdsNotSynced : .thresholdsNotConfigured
        }
    }
}

public enum AlertDataTrust {
    public static func evaluate(
        sensorTimestamp: Date,
        thresholds: AlertThresholdSetting,
        now: Date,
        elapsed: TimeInterval,
        mark: inout WallClockHighWaterMark,
        freshness: FreshnessThresholds = FreshnessPolicy.cgm
    ) -> AlertDataTrustResult {
        if mark.isRewound(at: now, elapsed: elapsed) { return .clockRewound }
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
