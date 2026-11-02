import Foundation
import SafetyCore

public struct AlertFloorNotification: Equatable, Sendable {
    public let slotIdentifier: String
    public let alertIdentifier: String
    public let type: AlertType
    public let severity: AlertSeverity
    public let tier: AlertDeliveryTier
    public let glucose: Glucose
    public let sensorTimestamp: Date
    public let body: String

    public init(type: AlertType, glucose: Glucose, sensorTimestamp: Date, unit: GlucoseUnit) {
        self.slotIdentifier = AlertFloorContent.slotIdentifier(for: type)
        self.alertIdentifier = AlertFloorContent.alertIdentifier(for: type, sensorTimestamp: sensorTimestamp)
        self.type = type
        self.severity = type == .lowUrgent || type == .highUrgent ? .urgent : .warning
        self.tier = type.deliveryTier
        self.glucose = glucose
        self.sensorTimestamp = sensorTimestamp
        self.body = AlertFloorContent.body(for: type, glucose: glucose, unit: unit)
    }
}

public enum AlertFloorContent {
    public static func slotIdentifier(for type: AlertType) -> String {
        "\(type.rawValue)|"
    }

    public static func alertIdentifier(for type: AlertType, sensorTimestamp: Date) -> String {
        let milliseconds = (sensorTimestamp.timeIntervalSince1970 * 1_000).rounded(.down)
        return "local-floor:\(type.rawValue):\(String(format: "%.0f", milliseconds))"
    }

    public static func headline(for type: AlertType) -> String {
        switch type {
        case .lowUrgent: "Urgent low glucose"
        case .lowWarning: "Low glucose"
        case .highWarning: "High glucose"
        case .highUrgent: "Urgent high glucose"
        default: "Glucose alert"
        }
    }

    public static func body(for type: AlertType, glucose: Glucose, unit: GlucoseUnit) -> String {
        "\(headline(for: type)) \(GlucoseFormatter.stringWithLabel(glucose, in: unit)) — computed on your phone from your last sensor reading. Threshold-only, no prediction. Not a replacement for your CGM app."
    }
}
