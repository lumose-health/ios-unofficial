import SwiftUI
import Observation
import SafetyCore
import DriverAPI

public enum HomeCard: String, CaseIterable, Sendable {
    case statusRow, glucoseHero, recentMeal, glucoseTrend, timeInRange, cgmStats
    case insulinSummary, recentBoluses, driverCards, footer
}

public enum HomeCardBody: Equatable, Sendable { case empty(String), comingSoon(String) }

public enum HomeScaffoldModel {
    public static let order: [HomeCard] = [.statusRow, .glucoseHero, .recentMeal, .glucoseTrend, .timeInRange, .cgmStats, .insulinSummary, .recentBoluses, .driverCards, .footer]
    public static let omittedWithoutData: Set<HomeCard> = [.recentMeal]
    private static let textCards: [HomeCard] = [.glucoseTrend, .timeInRange, .cgmStats, .insulinSummary, .recentBoluses]
    public static let cardTable: [(title: String, emptyText: String)] = textCards.compactMap { card in
        content(for: card).map { (title: $0.title, emptyText: $0.emptyText) }
    }

    private static func content(for card: HomeCard) -> (title: String, emptyText: String, comingSoonText: String)? {
        switch card {
        case .glucoseTrend: ("Glucose Trend", "No glucose readings yet", "Trend chart coming soon")
        case .timeInRange: ("Time in Range", "No glucose readings for this period", "Time in Range coming soon")
        case .cgmStats: ("CGM Stats", "No glucose readings for this period", "CGM stats coming soon")
        case .insulinSummary: ("Insulin Summary", "No insulin data for this period", "Insulin summary coming soon")
        case .recentBoluses: ("Recent Boluses", "No boluses for this period", "Recent boluses coming soon")
        case .statusRow, .glucoseHero, .recentMeal, .driverCards, .footer: nil
        }
    }

    public static func title(for card: HomeCard) -> String? { content(for: card)?.title }

    public static func body(for card: HomeCard, hasGlucose: Bool, hasInsulinOnBoard: Bool) -> HomeCardBody? {
        guard let content = content(for: card) else { return nil }
        let hasData = switch card {
        case .glucoseTrend, .timeInRange, .cgmStats: hasGlucose
        case .insulinSummary: hasInsulinOnBoard
        // Doses are never read here, so the card must not claim there were none.
        case .recentBoluses: true
        case .statusRow, .glucoseHero, .recentMeal, .driverCards, .footer: false
        }
        return hasData ? .comingSoon(content.comingSoonText) : .empty(content.emptyText)
    }

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
        .accessibilityIdentifier("home.scroll")
        .refreshable { await model.refresh() }
    }

    @ViewBuilder private func cardView(_ card: HomeCard) -> some View {
        switch card {
        case .statusRow: StatusRowView(state: model.statusRow)
        case .glucoseHero:
            GlucoseHeroView(state: model.heroState, onRefresh: { Task { await model.refresh() } })
        case .glucoseTrend, .timeInRange, .cgmStats, .insulinSummary, .recentBoluses:
            if let body = HomeScaffoldModel.body(for: card, hasGlucose: model.latestGlucose != nil, hasInsulinOnBoard: model.latestIOB != nil),
               let title = HomeScaffoldModel.title(for: card) {
                textCard(card, title: title, body: body)
            }
        case .footer:
            if let message = model.footerMessage {
                Text(message).frame(maxWidth: .infinity).padding(.top, 12)
            }
        case .recentMeal, .driverCards: EmptyView()
        }
    }

    private func textCard(_ card: HomeCard, title: String, body: HomeCardBody) -> some View {
        let text = switch body { case .empty(let value), .comingSoon(let value): value }
        return VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("home.card.\(card.rawValue)")
    }

}

public struct HomeScreen: View {
    public init() {}
    public var body: some View { HomeScaffoldView() }
}
