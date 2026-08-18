/// The presentation state FR-51 assigns to each ``Freshness`` tier.
///
/// Modeled now so the alerting work's UI has one contract to render against once
/// the badge gets a UI target — this type renders nothing itself.
public enum FreshnessBadge: Hashable, Sendable {

    /// Nothing is shown — a fresh reading needs no staleness call-out.
    case none

    /// "Stale", in the amber semantic color.
    case stale

    /// "Too old", in the error semantic color.
    case tooStale

    /// The badge FR-51 assigns to `freshness`.
    public init(_ freshness: Freshness) {
        switch freshness {
        case .fresh: self = .none
        case .stale: self = .stale
        case .tooStale: self = .tooStale
        }
    }

    /// The literal text FR-51 pins, or `nil` when nothing renders.
    public var text: String? {
        switch self {
        case .none: nil
        case .stale: "Stale"
        case .tooStale: "Too old"
        }
    }

    /// The semantic color TOKEN — a case name, not an RGB value. The UI surface,
    /// when it arrives, maps this to its own color asset.
    public var color: FreshnessBadgeColor? {
        switch self {
        case .none: nil
        case .stale: .amber
        case .tooStale: .error
        }
    }
}

/// Semantic color tokens ``FreshnessBadge`` references by name, not by RGB value —
/// the concrete color lives in the UI layer's asset catalog, which does not exist
/// as a target yet.
public enum FreshnessBadgeColor: Hashable, Sendable {
    case amber
    case error
}
