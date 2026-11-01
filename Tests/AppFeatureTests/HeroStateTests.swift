import Foundation
import Testing
import AppFeature
import DriverAPI
import SafetyCore
@Suite("Glucose hero state")
struct HeroStateTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func state(value: Double? = 120, age: TimeInterval = 0, trend: GlucoseTrend? = .steady,
                       sourceAge: TimeInterval? = 0, unit: GlucoseUnit = .mgdl, demo: Bool = false,
                       iob: InsulinOnBoardSample? = nil, pump: PumpStatusSnapshot? = nil,
                       basal: Double? = nil, basalAt: Date? = nil, basalMode: BasalMode? = nil) throws -> HeroState {
        let sample = try value.map { GlucoseSample(glucose: try Glucose(mgdl: $0), recordedAt: now.addingTimeInterval(-age), trend: trend) }
        return HeroState.make(sample: sample, trendSourceTimestamp: sourceAge.map { now.addingTimeInterval(-$0) },
                              iob: iob, pumpStatus: pump, basalRateUnitsPerHour: basal,
                              basalObservedAt: basalAt, basalMode: basalMode,
                              targetRange: .default, unit: unit, now: now, isDemo: demo)
    }
    @Test func emptyStateHasOnlyValueAndUnit() throws {
        let empty = try state(value: nil, demo: true)
        #expect(empty.valueText == "--")
        #expect(empty.unitText == "mg/dL")
        #expect(empty.valueColor == .secondary)
        #expect(empty.glyph == nil)
        #expect(empty.ageCaption == nil)
        #expect(empty.badge == .none)
        #expect(empty.metrics.isEmpty)
    }
    @Test func severityIsIndependentOfDisplayUnit() throws {
        for (value, color) in [(55.0, HeroColor.red), (70, .amber), (71, .green),
                               (180, .amber), (250, .red)] {
            #expect(try state(value: value).valueColor == color)
            #expect(try state(value: value, unit: .mmol).valueColor == color)
        }
        #expect(try state(value: 120, unit: .mmol).unitText == "mmol/L")
        #expect(try state(value: 120, unit: .mmol).valueText == "6.7")
    }
    @Test func everyTrendGlyph() throws {
        let cases: [(GlucoseTrend?, String)] = [
            (.risingQuickly, "⇈"), (.rising, "↑"), (.risingSlowly, "↗"),
            (.steady, "→"), (.fallingSlowly, "↘"), (.falling, "↓"),
            (.fallingQuickly, "⇊"), (.unknown, "?"), (nil, "?")
        ]
        for (trend, glyph) in cases { #expect(try state(trend: trend).glyph == glyph) }
    }
    @Test func trendProvenanceCannotFreshenAnOldValue() throws {
        let oldGlyph = try state(age: 240, trend: .rising, sourceAge: 960)
        #expect(oldGlyph.valueColor == .green)
        #expect(oldGlyph.ageCaption == "4m ago")
        #expect(oldGlyph.glyph == "?")
        #expect(oldGlyph.glyphColor == .secondary)
        let oldValue = try state(age: 960, trend: .rising, sourceAge: 60)
        #expect(oldValue.valueText == "120")
        #expect(oldValue.valueColor == .secondary)
        #expect(oldValue.glyph == "↑")
        #expect(oldValue.glyphColor == .secondary)
        #expect(oldValue.badge == .tooStale)
        #expect(try state(sourceAge: nil).glyph == "?")
        let staleGlyph = try state(age: 240, trend: .falling, sourceAge: 400)
        #expect(staleGlyph.valueColor == .green)
        #expect(staleGlyph.glyph == "↓")
        #expect(staleGlyph.glyphColor == .green)
        #expect(try state(value: 55, age: 240, trend: .falling, sourceAge: 400).glyphColor == .red)
        let equallyStale = try state(age: 400, trend: .falling, sourceAge: 240)
        #expect(equallyStale.glyphColor == equallyStale.valueColor)
    }

    @Test func captionBoundariesAndBadges() throws {
        let cases: [(TimeInterval, String, HeroColor, FreshnessBadge)] = [
            (0, "just now", .green, .none), (59, "just now", .green, .none),
            (60, "1m ago", .green, .none), (360, "6m ago", .amber, .stale),
            (900, "15m ago", .secondary, .tooStale),
            (3599, "59m ago", .secondary, .tooStale),
            (3600, "1h ago", .secondary, .tooStale),
            (86400, "1d ago", .secondary, .tooStale)
        ]
        for (age, caption, color, badge) in cases {
            let hero = try state(age: age, sourceAge: age)
            #expect(hero.ageCaption == caption)
            #expect(hero.ageColor == color)
            #expect(hero.badge == badge)
        }
    }

    @Test func metricsRenderWhenPresentAndDecayIndependently() throws {
        let iob = try InsulinOnBoardSample(units: 1.234, calculatedAt: now.addingTimeInterval(-900))
        let pump = try PumpStatusSnapshot(batteryFraction: 0.62, reservoirUnits: 123.4, observedAt: now)
        let hero = try state(iob: iob, pump: pump, basal: 0.8, basalAt: now, basalMode: .sleep)
        #expect(hero.metrics.map(\.kind) == [.iob, .basal, .battery, .reservoir])
        #expect(hero.metrics.map(\.text) == ["1.23u", "0.80 u/hr Sleep", "62%", "123u"])
        #expect(hero.metrics[0].badge == .stale)
        #expect(hero.metrics[0].isDeemphasised)
        #expect(hero.metrics[1...].allSatisfy { !$0.isDeemphasised })
        #expect(try state(iob: iob).metrics.map(\.kind) == [.iob])
        #expect(try state().metrics.isEmpty)
        #expect(try state(basal: 0.8).metrics.isEmpty)
        #expect(try state(pump: pump, basal: 0.8).metrics.map(\.kind) == [.battery, .reservoir])
        let oldBasal = try state(pump: pump, basal: 0.8, basalAt: now.addingTimeInterval(-900))
        #expect(oldBasal.metrics[0].badge == .stale)
        #expect(oldBasal.metrics[1].badge == .none)
    }

    @Test func demoLabelStartsWithWarningForRealValue() throws {
        let demo = try state(trend: .rising, demo: true)
        #expect(demo.accessibilityLabel.hasPrefix("DEMO DATA — not your glucose"))
        #expect(demo.accessibilityLabel.contains("120 mg/dL, rising, just now"))
        #expect(!((try state(demo: false)).accessibilityLabel.contains("DEMO DATA")))
        let old = try state(age: 960, sourceAge: 960, demo: true)
        #expect(old.accessibilityLabel.contains("Too old"))
        #expect(old.accessibilityLabel.contains("trend unknown"))
        let iob = try InsulinOnBoardSample(units: 1.25, calculatedAt: now)
        #expect(try state(demo: true, iob: iob).metrics[0].accessibilityLabel.hasPrefix("DEMO DATA — not your glucose"))
    }

    @Test func pumpFreshnessBoundaries() throws {
        let cases: [(TimeInterval, FreshnessBadge)] = [
            (899, .none), (900, .stale), (3599, .stale), (3600, .tooStale)
        ]
        for (age, badge) in cases {
            let iob = try InsulinOnBoardSample(units: 1.25, calculatedAt: now.addingTimeInterval(-age))
            #expect(try state(iob: iob).metrics[0].badge == badge)
        }
    }
}
