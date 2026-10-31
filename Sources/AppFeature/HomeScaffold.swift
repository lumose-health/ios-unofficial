import SwiftUI
import Observation
import SafetyCore
import DriverAPI

public enum HomeCard: String, CaseIterable, Sendable {
    case statusRow, glucoseHero, recentMeal, glucoseTrend, timeInRange, cgmStats
    case insulinSummary, recentBoluses, driverCards, footer
}

public enum HomeScaffoldModel {
    public static let order: [HomeCard] = [.statusRow, .glucoseHero, .recentMeal, .glucoseTrend, .timeInRange, .cgmStats, .insulinSummary, .recentBoluses, .driverCards, .footer]
    public static let omittedWithoutData: Set<HomeCard> = [.recentMeal]
    public static let cardTable: [(title: String, emptyText: String)] = [
        ("Glucose Trend", "No glucose readings yet"),
        ("Time in Range", "No glucose readings for this period"),
        ("CGM Stats", "No glucose readings for this period"),
        ("Insulin Summary", "No insulin data for this period"),
        ("Recent Boluses", "No boluses for this period"),
    ]

    public static func isConnected(_ state: DriverLifecycleState) -> Bool {
        // Interim derivation until pump-link status exists.
        state == .active || state == .degraded
    }

    public static func footer(isConnected: Bool, hasGlucose: Bool) -> String? {
        if !isConnected { return "Pair your pump in Settings to start" }
        if !hasGlucose { return "Loading pump data..." }
        return nil
    }

    public static func heroAccessibilityLabel(demo: Bool) -> String {
        demo ? "--, \(DemoDataLabel.text)" : "--"
    }
}

public enum DemoDataLabel {
    public static let text = "DEMO DATA — not your glucose"
    public static func isVisible(activeGlucoseDriver: DriverIdentifier?, demoIdentifiers: Set<DriverIdentifier>) -> Bool {
        guard let activeGlucoseDriver else { return false }
        return demoIdentifiers.contains(activeGlucoseDriver)
    }
}

public struct DemoDataBannerRoot<Content: View>: View {
    @Environment(HomeModel.self) private var model
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(spacing: 0) {
            if model.isDemo {
                Text(DemoDataLabel.text)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.orange)
                    .foregroundStyle(.black)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
    }
}

struct HomeScaffoldView: View {
    @Environment(HomeModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(HomeScaffoldModel.order.filter { !HomeScaffoldModel.omittedWithoutData.contains($0) }, id: \.self) { card in
                    cardView(card)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 88)
        }
    }

    @ViewBuilder private func cardView(_ card: HomeCard) -> some View {
        switch card {
        case .statusRow: Color.clear.frame(height: 1).accessibilityIdentifier("home.status-row-slot")
        case .glucoseHero:
            GlucoseHeroView(state: model.heroState)
        case .glucoseTrend: emptyCard(HomeScaffoldModel.cardTable[0])
        case .timeInRange: emptyCard(HomeScaffoldModel.cardTable[1])
        case .cgmStats: emptyCard(HomeScaffoldModel.cardTable[2])
        case .insulinSummary: emptyCard(HomeScaffoldModel.cardTable[3])
        case .recentBoluses: emptyCard(HomeScaffoldModel.cardTable[4])
        case .footer:
            if let message = model.footerMessage {
                Text(message).frame(maxWidth: .infinity).padding(.top, 12)
            }
        case .recentMeal, .driverCards: EmptyView()
        }
    }

    private func emptyCard(_ item: (title: String, emptyText: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(item.title).font(.headline); Text(item.emptyText).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

public struct HomeScreen: View {
    public init() {}
    public var body: some View { HomeScaffoldView() }
}
