import Foundation
import DriverAPI

public struct ContributedCard: Hashable, Sendable, Identifiable {
    public let driver: DriverIdentifier
    public let card: DashboardCardDescriptor
    /// Card ids are unique only within one Driver, so the id pairs them with
    /// the Driver rather than joining them into one string that could collide.
    public struct ID: Hashable, Sendable {
        public let driver: DriverIdentifier
        public let card: String

        public init(driver: DriverIdentifier, card: String) {
            self.driver = driver
            self.card = card
        }
    }

    public var id: ID { ID(driver: driver, card: card.id) }

    public init(driver: DriverIdentifier, card: DashboardCardDescriptor) {
        self.driver = driver
        self.card = card
    }

    public static func ordered(_ cards: [ContributedCard]) -> [ContributedCard] {
        cards.sorted {
            if $0.card.priority != $1.card.priority { return $0.card.priority < $1.card.priority }
            if $0.driver.rawValue != $1.driver.rawValue { return $0.driver.rawValue < $1.driver.rawValue }
            return $0.card.id < $1.card.id
        }
    }
}

public enum DashboardCardValidation {
    /// True when the text holds any decimal digit, ASCII or any other Unicode script
    /// (general category Nd), such as full-width digits.
    static func containsDecimalDigit(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.generalCategory == .decimalNumber }
    }

    static func containsDecimalDigit(_ card: DashboardCardDescriptor) -> Bool {
        if containsDecimalDigit(card.title) { return true }
        return card.elements.contains { element in
            switch element {
            case .label(let text, _), .statusBadge(let text, _): containsDecimalDigit(text)
            }
        }
    }

    /// Returns the cards the platform will show, in their original order. A card is refused when
    /// its id or title is blank, its priority is below the Driver minimum, its id repeats an
    /// earlier card, or its title or any element text contains a decimal digit. Refused cards are
    /// dropped whole and logged; their text is never altered.
    public static func accepted(
        _ cards: [DashboardCardDescriptor],
        from driver: DriverIdentifier,
        log: (String) -> Void = { _ in }
    ) -> [DashboardCardDescriptor] {
        var identifiers: Set<String> = []
        var accepted: [DashboardCardDescriptor] = []
        for card in cards {
            let rule: String?
            if card.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rule = "empty id" }
            else if card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rule = "empty title" }
            else if card.priority < DashboardCardDescriptor.minimumDriverPriority { rule = "priority below minimum" }
            else if identifiers.contains(card.id) { rule = "duplicate id" }
            else { rule = nil }
            if containsDecimalDigit(card) {
                // Only the Driver and the reason are logged: the card text may hold a clinical value.
                log("Driver \(driver.rawValue) card refused: digit in card text")
            } else if let rule {
                log("Driver \(driver.rawValue) card \(card.id) refused: \(rule)")
            } else {
                identifiers.insert(card.id)
                accepted.append(card)
            }
        }
        return accepted
    }
}
