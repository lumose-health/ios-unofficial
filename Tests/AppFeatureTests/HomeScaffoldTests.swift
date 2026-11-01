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
}
