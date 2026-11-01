import Testing
import AppFeature
import DriverAPI

@Suite("Home scaffold")
struct HomeScaffoldTests {
    @Test func cardOrderAndOmission() {
        #expect(HomeScaffoldModel.order.map(\.rawValue) == ["statusRow", "glucoseHero", "recentMeal", "glucoseTrend", "timeInRange", "cgmStats", "insulinSummary", "recentBoluses", "driverCards", "footer"])
        #expect(HomeScaffoldModel.omittedWithoutData == [.recentMeal])
    }

    @Test func footerStringsAndLifecycleMapping() {
        #expect(HomeScaffoldModel.footer(isConnected: HomeScaffoldModel.isConnected(.notActivated), hasGlucose: false) == "Pair your pump in Settings to start")
        #expect(HomeScaffoldModel.footer(isConnected: HomeScaffoldModel.isConnected(.active), hasGlucose: false) == "Loading pump data...")
        #expect(HomeScaffoldModel.footer(isConnected: HomeScaffoldModel.isConnected(.active), hasGlucose: true) == nil)
        #expect(!HomeScaffoldModel.isConnected(.failed))
    }

    @Test func demoConditionAndHeroAccessibilityLabel() {
        let simulated = DriverIdentifier("com.glycemicgpt.simulated")!
        let other = DriverIdentifier("com.glycemicgpt.other")!
        #expect(DemoDataLabel.isVisible(activeGlucoseDriver: simulated, demoIdentifiers: [simulated]))
        #expect(!DemoDataLabel.isVisible(activeGlucoseDriver: other, demoIdentifiers: [simulated]))
        #expect(!DemoDataLabel.isVisible(activeGlucoseDriver: nil, demoIdentifiers: [simulated]))
        #expect(HomeScaffoldModel.heroAccessibilityLabel(demo: true) == "--, DEMO DATA — not your glucose")
        #expect(HomeScaffoldModel.heroAccessibilityLabel(demo: false) == "--")
    }

    @Test func emptyCardStringsMatchAndroid() {
        #expect(HomeScaffoldModel.cardTable.map(\.title) == ["Glucose Trend", "Time in Range", "CGM Stats", "Insulin Summary", "Recent Boluses"])
        #expect(HomeScaffoldModel.cardTable.map(\.emptyText) == [
            "No glucose readings yet",
            "No glucose readings for this period",
            "No glucose readings for this period",
            "No insulin data for this period",
            "No boluses for this period",
        ])
    }

    @Test func cardBodiesReflectAvailableDataAndPlaceholders() {
        let cards: [(HomeCard, String, String, Bool)] = [
            (.glucoseTrend, "No glucose readings yet", "Trend chart coming soon", true),
            (.timeInRange, "No glucose readings for this period", "Time in Range coming soon", true),
            (.cgmStats, "No glucose readings for this period", "CGM stats coming soon", true),
            (.insulinSummary, "No insulin data for this period", "Insulin summary coming soon", false),
            (.recentBoluses, "No boluses for this period", "Recent boluses coming soon", false),
        ]
        for (card, empty, soon, glucoseDriven) in cards where card != .recentBoluses {
            let noData = HomeScaffoldModel.body(for: card, hasGlucose: false, hasInsulinOnBoard: false)
            let withData = HomeScaffoldModel.body(for: card, hasGlucose: glucoseDriven, hasInsulinOnBoard: !glucoseDriven)
            #expect(noData == .empty(empty))
            #expect(withData == .comingSoon(soon))
        }
        #expect(HomeScaffoldModel.body(for: .recentBoluses, hasGlucose: false, hasInsulinOnBoard: false) == .comingSoon("Recent boluses coming soon"))
        #expect(HomeScaffoldModel.body(for: .recentBoluses, hasGlucose: true, hasInsulinOnBoard: true) == .comingSoon("Recent boluses coming soon"))
        #expect(HomeScaffoldModel.body(for: .statusRow, hasGlucose: true, hasInsulinOnBoard: true) == nil)
    }
}
