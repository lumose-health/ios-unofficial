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
    case backendAlerting, dataTrust(AlertDataTrustResult)
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

    /// When a cooldown began, on both clocks. Either clock reaching the cooldown ends
    /// it, so a wall-clock rewind cannot stretch it, however small or often repeated.
    /// `elapsed` has no meaning across launches, so this stays in-process (FR-72, FR-74).
    private struct CooldownStamp: Equatable {
        let wall: Date
        let elapsed: TimeInterval

        func hasEnded(at now: Date, elapsed elapsedNow: TimeInterval) -> Bool {
            let cooldown = SafetyConstants.alertFloorCooldown
            return now.timeIntervalSince(wall) >= cooldown || elapsedNow - elapsed >= cooldown
        }
    }

    private let notifier: any AlertNotifying
    private let clock: any Clock
    private let elapsed: any ElapsedClock
    private let freshness: FreshnessThresholds
    private let log: any AlertFloorLogging
    private var mark = WallClockHighWaterMark()
    private var lastFired: [AlertType: CooldownStamp] = [:]
    private var acknowledged: Set<AlertType> = []

    public init(
        notifier: any AlertNotifying,
        clock: any Clock,
        elapsed: any ElapsedClock,
        freshness: FreshnessThresholds = FreshnessPolicy.cgm,
        log: any AlertFloorLogging = OSAlertFloorLog()
    ) {
        self.notifier = notifier
        self.clock = clock
        self.elapsed = elapsed
        self.freshness = freshness
        self.log = log
    }

    public func acknowledge(_ type: AlertType) {
        lastFired[type] = CooldownStamp(wall: clock.now, elapsed: elapsed.elapsed)
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
        let elapsedNow = elapsed.elapsed
        if mark.isRewound(at: now, elapsed: elapsedNow) {
            return finish(.suppressed(.dataTrust(.clockRewound)), type: nil)
        }

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
            sensorTimestamp: sensorTimestamp, thresholds: thresholds, now: now, elapsed: elapsedNow,
            mark: &mark, freshness: freshness
        )
        guard trust == .trusted else {
            return finish(.suppressed(.dataTrust(trust)), type: type)
        }
        // A stamp this far ahead of a trusted clock cannot latch the cooldown (FR-72).
        // Discard before suspending: `now` goes stale across the await, and a stamp an
        // overlapping evaluation reserves meanwhile is a real cooldown.
        if let stamp = lastFired[type], stamp.wall.timeIntervalSince(now) > SafetyConstants.alertFloorMaxFutureSkew {
            lastFired.removeValue(forKey: type)
            acknowledged.remove(type)
        }
        guard await notifier.canPostAlerts() else {
            return finish(.suppressed(.cannotPost), type: type)
        }
        let previousStamp = lastFired[type]
        let wasAcknowledged = acknowledged.contains(type)
        if let previousStamp, !previousStamp.hasEnded(at: now, elapsed: elapsedNow) {
            return finish(.suppressed(.coolingDown), type: type)
        }

        // Reserve the cooldown before suspension so overlapping evaluations cannot both post.
        let reserved = CooldownStamp(wall: now, elapsed: elapsedNow)
        lastFired[type] = reserved
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
            if lastFired[type] == reserved && !acknowledged.contains(type) {
                lastFired[type] = previousStamp
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
