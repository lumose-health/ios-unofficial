import Foundation

/// Declarative card data only. The platform renders, validates, orders and labels
/// each card. A card must not carry a glucose or dose value until the platform
/// defines a safe element for displaying numeric values. Until then the platform
/// refuses, whole, any card whose title or element text contains a decimal digit
/// in any script, ASCII or otherwise; digits are never stripped to make a card fit.
public struct DashboardCardDescriptor: Hashable, Sendable, Identifiable {
    /// Driver cards appear at or after this priority; platform cards come first.
    public static let minimumDriverPriority = 100

    public let id: String
    public let title: String
    public let priority: Int
    public let elements: [CardElement]

    public init(id: String, title: String, priority: Int, elements: [CardElement]) {
        self.id = id
        self.title = title
        self.priority = priority
        self.elements = elements
    }
}

public enum CardElement: Hashable, Sendable {
    case label(text: String, style: CardLabelStyle)
    case statusBadge(text: String, color: CardColor)
}

public enum CardColor: String, CaseIterable, Hashable, Sendable {
    case standard, success, warning, error, info, muted
}

public enum CardLabelStyle: String, CaseIterable, Hashable, Sendable {
    case title, subtitle, body, caption
}
