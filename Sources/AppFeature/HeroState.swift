import Foundation
import SafetyCore
import DriverAPI
public enum HeroColor: Hashable, Sendable {
    case green, amber, red, secondary
}
public enum HeroMetricKind: String, Hashable, Sendable {
    case iob = "IOB"
    case basal = "Basal"
    case battery = "Battery"
    case reservoir = "Reservoir"
}
public enum BasalMode: String, Hashable, Sendable {
    case sleep = " Sleep", exercise = " Exercise", automated = " Automated"
}
public struct HeroMetric: Hashable, Sendable {
    public let kind: HeroMetricKind
    public let text: String
    public let badge: FreshnessBadge
    public let isDeemphasised: Bool
    public let accessibilityLabel: String
    public init(kind: HeroMetricKind, text: String, badge: FreshnessBadge, isDeemphasised: Bool, isDemo: Bool) {
        self.kind = kind
        self.text = text
        self.badge = badge
        self.isDeemphasised = isDeemphasised
        self.accessibilityLabel = "\(isDemo ? "\(DemoDataLabel.text), " : "")\(kind.rawValue), \(text)\(badge.text.map { ", \($0)" } ?? "")"
    }
}
public struct HeroState: Hashable, Sendable {
    public let valueText: String
    public let unitText: String
    public let valueColor: HeroColor
    public let glyph: String?
    public let glyphColor: HeroColor
    public let ageCaption: String?
    public let ageColor: HeroColor
    public let badge: FreshnessBadge
    public let metrics: [HeroMetric]
    public let accessibilityLabel: String
    public static func make(
        sample: GlucoseSample?,
        trendSourceTimestamp: Date?,
        iob: InsulinOnBoardSample?,
        pumpStatus: PumpStatusSnapshot?,
        basalRateUnitsPerHour: Double? = nil,
        basalObservedAt: Date? = nil,
        basalMode: BasalMode? = nil,
        targetRange: TargetRange,
        unit: GlucoseUnit,
        now: Date,
        isDemo: Bool
    ) -> HeroState {
        let metrics = metrics(iob: iob, pumpStatus: pumpStatus, basalRateUnitsPerHour: basalRateUnitsPerHour,
                              basalObservedAt: basalObservedAt, basalMode: basalMode, now: now, isDemo: isDemo)
        guard let sample else {
            return HeroState(valueText: "--", unitText: unit.label, valueColor: .secondary,
                             glyph: nil, glyphColor: .secondary, ageCaption: nil, ageColor: .secondary,
                             badge: .none, metrics: [],
                             accessibilityLabel: isDemo ? "\(DemoDataLabel.text), --" : "--")
        }
        let valueTier = tier(sample.recordedAt, now: now)
        let sourceTier = trendSourceTimestamp.map { tier($0, now: now) }
        let valueColor: HeroColor = valueTier == .tooStale ? .secondary : color(targetRange.severity(of: sample.glucose))
        let direction = glyph(for: sample.trend)
        let glyph: String = sourceTier == nil || sourceTier == .tooStale ? "?" : direction
        let glyphColor: HeroColor
        if glyph == "?" || valueTier == .tooStale { glyphColor = .secondary }
        else { glyphColor = valueColor }
        let age = now.timeIntervalSince(sample.recordedAt)
        let caption = ageText(age)
        let labelPrefix = isDemo ? "\(DemoDataLabel.text), " : ""
        return HeroState(
            valueText: GlucoseFormatter.string(sample.glucose, in: unit), unitText: unit.label,
            valueColor: valueColor, glyph: glyph, glyphColor: glyphColor,
            ageCaption: caption, ageColor: captionColor(valueTier), badge: FreshnessBadge(valueTier),
            metrics: metrics,
            accessibilityLabel: "\(labelPrefix)\(GlucoseFormatter.stringWithLabel(sample.glucose, in: unit)), \(spokenTrend(sample.trend, glyph: glyph)), \(caption)\(FreshnessBadge(valueTier).text.map { ", \($0)" } ?? "")"
        )
    }
    private static func tier(_ timestamp: Date, now: Date) -> Freshness {
        FreshnessPolicy.cgm.classify(age: now.timeIntervalSince(timestamp))
    }
    private static func color(_ severity: GlucoseSeverity) -> HeroColor {
        switch severity {
        case .urgentLow, .urgentHigh: .red
        case .low, .high: .amber
        case .inRange: .green
        }
    }
    private static func captionColor(_ freshness: Freshness) -> HeroColor {
        switch freshness {
        case .fresh: .green
        case .stale: .amber
        case .tooStale: .secondary
        }
    }
    private static func glyph(for trend: GlucoseTrend?) -> String {
        switch trend {
        case .risingQuickly: "⇈"
        case .rising: "↑"
        case .risingSlowly: "↗"
        case .steady: "→"
        case .fallingSlowly: "↘"
        case .falling: "↓"
        case .fallingQuickly: "⇊"
        case .unknown, nil: "?"
        }
    }
    private static func spokenTrend(_ trend: GlucoseTrend?, glyph: String) -> String {
        guard glyph != "?" else { return "trend unknown" }
        return switch trend {
        case .risingQuickly: "rising quickly"
        case .rising: "rising"
        case .risingSlowly: "rising slowly"
        case .steady: "steady"
        case .fallingSlowly: "falling slowly"
        case .falling: "falling"
        case .fallingQuickly: "falling quickly"
        case .unknown, nil: "trend unknown"
        }
    }
    private static func ageText(_ age: TimeInterval) -> String {
        let minute = Measurement(value: 1, unit: UnitDuration.minutes).converted(to: .seconds).value
        let hour = Measurement(value: 1, unit: UnitDuration.hours).converted(to: .seconds).value
        if age < minute { return "just now" }
        if age < hour { return "\(Int(age / minute))m ago" }
        if age < 86400 { return "\(Int(age / hour))h ago" }
        return "\(Int(age / 86400))d ago"
    }
    private static func metrics(iob: InsulinOnBoardSample?, pumpStatus: PumpStatusSnapshot?, basalRateUnitsPerHour: Double?,
                                basalObservedAt: Date?, basalMode: BasalMode?, now: Date, isDemo: Bool) -> [HeroMetric] {
        var result: [HeroMetric] = []
        if let iob {
            result.append(metric(.iob, String(format: "%.2fu", iob.units), at: iob.calculatedAt, now: now, isDemo: isDemo))
        }
        if let basalRateUnitsPerHour, let basalObservedAt {
            result.append(metric(.basal, String(format: "%.2f u/hr", basalRateUnitsPerHour) + (basalMode?.rawValue ?? ""),
                                 at: basalObservedAt, now: now, isDemo: isDemo))
        }
        if let pumpStatus {
            if let battery = pumpStatus.batteryFraction {
                result.append(metric(.battery, "\(Int((battery * 100).rounded()))%", at: pumpStatus.observedAt, now: now, isDemo: isDemo))
            }
            if let reservoir = pumpStatus.reservoirUnits {
                result.append(metric(.reservoir, String(format: "%.0fu", reservoir), at: pumpStatus.observedAt, now: now, isDemo: isDemo))
            }
        }
        return result
    }
    private static func metric(_ kind: HeroMetricKind, _ text: String, at timestamp: Date, now: Date, isDemo: Bool) -> HeroMetric {
        let freshness = FreshnessPolicy.pump.classify(age: now.timeIntervalSince(timestamp))
        return HeroMetric(kind: kind, text: text, badge: FreshnessBadge(freshness), isDeemphasised: freshness != .fresh, isDemo: isDemo)
    }
}
