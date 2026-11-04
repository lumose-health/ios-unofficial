import Foundation
import os
import DriverAPI
import SafetyCore

public enum AlertPostFailure: Error, Hashable, Sendable {
    case unavailable
}

public protocol AlertNotifying: Sendable {
    func canPostAlerts() async -> Bool
    func post(_ notification: AlertFloorNotification) async throws(AlertPostFailure)
}

public enum AlertFloorSuppression: Equatable, Sendable {
    case clockRewound, backendAlerting, dataTrust(AlertDataTrustResult)
    case cannotPost, coolingDown, postFailed
}

public enum AlertFloorOutcome: Equatable, Sendable {
    case inRange
    case suppressed(AlertFloorSuppression)
    case fired(AlertFloorNotification)
}

/// The logger accepts only an alert type and a decision, never glucose or time (SI-9).
public protocol AlertFloorLogging: Sendable {
    func record(type: AlertType?, outcome: AlertFloorLogOutcome)
}

public enum AlertFloorLogOutcome: Sendable {
    case inRange, suppressed(AlertFloorSuppression), fired
}

public struct OSAlertFloorLog: AlertFloorLogging {
    private let logger = Logger(subsystem: "com.glycemicgpt.ios", category: "AlertFloor")
    public init() {}

    public func record(type: AlertType?, outcome: AlertFloorLogOutcome) {
        logger.info("Alert floor \(type?.rawValue ?? "none", privacy: .public): \(String(describing: outcome), privacy: .public)")
    }
}

/// Threshold-only fallback alarm engine with process-local episode state (FR-71, FR-74).
public actor AlertFloor {
    private enum Input {
        case reading(Glucose)
        case excursion(SensorRangeSide)
    }

    private let notifier: any AlertNotifying
    private let clock: any Clock
    private let freshness: FreshnessThresholds
    private let log: any AlertFloorLogging
    private var mark = WallClockHighWaterMark()
    private var lastFired: [AlertType: Date] = [:]
    private var acknowledged: Set<AlertType> = []

    public init(
        notifier: any AlertNotifying,
        clock: any Clock,
        freshness: FreshnessThresholds = FreshnessPolicy.cgm,
        log: any AlertFloorLogging = OSAlertFloorLog()
    ) {
        self.notifier = notifier
        self.clock = clock
        self.freshness = freshness
        self.log = log
    }

    public func acknowledge(_ type: AlertType) {
        lastFired[type] = clock.now
        acknowledged.insert(type)
    }

    public func evaluate(
        _ reading: GlucoseReading,
        thresholds: AlertThresholdSetting,
        backend: BackendAlertingStatus,
        unit: GlucoseUnit
    ) async -> AlertFloorOutcome {
        await evaluate(
            .reading(reading.glucose), sensorTimestamp: reading.timestamp,
            thresholds: thresholds, backend: backend, unit: unit
        )
    }

    /// A sensor range report has no number: below range is always an urgent low
    /// and above range an urgent high, but only through the same gates as a
    /// reading (configured thresholds, Backend status, data trust on the
    /// sensor timestamp, permission, cooldown; FR-72, FR-73, SI-5).
    public func evaluate(
        _ excursion: SensorRangeExcursion,
        thresholds: AlertThresholdSetting,
        backend: BackendAlertingStatus,
        unit: GlucoseUnit
    ) async -> AlertFloorOutcome {
        await evaluate(
            .excursion(excursion.side), sensorTimestamp: excursion.recordedAt,
            thresholds: thresholds, backend: backend, unit: unit
        )
    }

    private func evaluate(
        _ input: Input,
        sensorTimestamp: Date,
        thresholds: AlertThresholdSetting,
        backend: BackendAlertingStatus,
        unit: GlucoseUnit
    ) async -> AlertFloorOutcome {
        let now = clock.now
        if mark.isRewound(at: now) {
            return finish(.suppressed(.clockRewound), type: nil)
        }
        mark.observe(now)

        let type = thresholds.configuredThresholds.flatMap { configured -> AlertType? in
            switch input {
            case .reading(let glucose): AlertClassifier.classify(glucose, against: configured)
            case .excursion(let side): AlertClassifier.classify(side)
            }
        }
        for prior in acknowledged.filter({ $0 != type }) {
            acknowledged.remove(prior)
            lastFired.removeValue(forKey: prior)
        }
        guard let type else {
            if thresholds.configuredThresholds == nil {
                return finish(.suppressed(.dataTrust(.thresholdsNotConfigured)), type: nil)
            }
            return finish(.inRange, type: nil)
        }
        guard backend.isDegraded else {
            return finish(.suppressed(.backendAlerting), type: type)
        }
        let trust = AlertDataTrust.evaluate(
            sensorTimestamp: sensorTimestamp, thresholds: thresholds, now: now,
            mark: &mark, freshness: freshness
        )
        guard trust == .trusted else {
            return finish(.suppressed(.dataTrust(trust)), type: type)
        }
        guard await notifier.canPostAlerts() else {
            return finish(.suppressed(.cannotPost), type: type)
        }
        let previousTime = lastFired[type]
        let wasAcknowledged = acknowledged.contains(type)
        if let previousTime, now.timeIntervalSince(previousTime) < SafetyConstants.alertFloorCooldown {
            return finish(.suppressed(.coolingDown), type: type)
        }

        // Reserve the cooldown before suspension so overlapping evaluations cannot both post.
        lastFired[type] = now
        acknowledged.remove(type)
        let notification: AlertFloorNotification
        switch input {
        case .reading(let glucose):
            notification = AlertFloorNotification(
                type: type, glucose: glucose, sensorTimestamp: sensorTimestamp, unit: unit
            )
        case .excursion(let side):
            notification = AlertFloorNotification(side: side, sensorTimestamp: sensorTimestamp)
        }
        do {
            try await notifier.post(notification)
            return finish(.fired(notification), type: type)
        } catch {
            if lastFired[type] == now && !acknowledged.contains(type) {
                lastFired[type] = previousTime
                if wasAcknowledged { acknowledged.insert(type) }
            }
            return finish(.suppressed(.postFailed), type: type)
        }
    }

    private func finish(_ outcome: AlertFloorOutcome, type: AlertType?) -> AlertFloorOutcome {
        switch outcome {
        case .inRange: log.record(type: type, outcome: .inRange)
        case .suppressed(let reason): log.record(type: type, outcome: .suppressed(reason))
        case .fired: log.record(type: type, outcome: .fired)
        }
        return outcome
    }
}
