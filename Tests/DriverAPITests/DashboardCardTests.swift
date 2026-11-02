import Testing
import DriverAPI

@Suite("Dashboard card data")
struct DashboardCardTests {
    @Test func vocabularyIsClosedToTheShippedCases() {
        #expect(CardColor.allCases == [.standard, .success, .warning, .error, .info, .muted])
        #expect(CardLabelStyle.allCases == [.title, .subtitle, .body, .caption])
        func name(_ element: CardElement) -> String {
            switch element {
            case .label: "label"
            case .statusBadge: "statusBadge"
            }
        }
        #expect(name(.label(text: "x", style: .body)) == "label")
        #expect(name(.statusBadge(text: "x", color: .info)) == "statusBadge")
    }

    @Test func sourceHasNoPlatformUIImports() throws {
        let files = try DriverAPISource.files()
        #expect(files.allSatisfy { !$0.code.contains("import SwiftUI") })
        #expect(files.allSatisfy { !$0.code.contains("import UIKit") })
        #expect(files.allSatisfy { !$0.code.contains("import AppKit") })
    }

    @Test func defaultCardsAreEmpty() async {
        let driver = CardDefaultDriver()
        #expect(await driver.dashboardCards().isEmpty)
    }
}

private actor CardDefaultDriver: Driver {
    nonisolated let descriptor = DriverDescriptor(
        identifier: DriverIdentifier("test.card.default")!, targetName: "CardDefaultDriver",
        displayName: "Default", transport: .inProcess, version: "1", capabilities: [], verification: .unverified
    )
    func capability(_ capability: Capability) -> CapabilityPort? { nil }
    func activate() async throws(DriverFailure) {}
    func deactivate() async {}
}
