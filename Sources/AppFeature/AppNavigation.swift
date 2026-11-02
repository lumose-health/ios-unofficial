import Foundation
import DriverAPI

/// Tabs reflect the modes that are actually available.
public enum AppTab: String, CaseIterable, Sendable, Equatable, Hashable {
    case home, aiChat, alerts, settings

    public var title: String {
        switch self {
        case .home: "Home"
        case .aiChat: "AI Chat"
        case .alerts: "Alerts"
        case .settings: "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: "house"
        case .aiChat: "bubble.left.and.bubble.right"
        case .alerts: "bell"
        case .settings: "gearshape"
        }
    }

    public var accessibilityIdentifier: String {
        switch self {
        case .home: "tab.home"
        case .aiChat: "tab.aiChat"
        case .alerts: "tab.alerts"
        case .settings: "tab.settings"
        }
    }

    public static func visible(backend: BackendConfiguration) -> [AppTab] {
        switch backend {
        case .notConfigured: [.home, .alerts, .settings]
        case .configured: [.home, .aiChat, .alerts, .settings]
        }
    }

    public static func effectiveSelection(_ selected: AppTab, visible: [AppTab]) -> AppTab {
        visible.contains(selected) ? selected : .home
    }
}

/// The start destination depends only on onboarding completion, so an expired
/// or absent session still reaches local data while offline.
public enum StartDestination: Sendable, Equatable {
    case main, onboarding

    public static func resolve(onboardingComplete: Bool) -> Self {
        onboardingComplete ? .main : .onboarding
    }
}

public enum OnboardingCompletion {
    public static let key = "onboardingComplete"
    /// An unset key means onboarding was never finished.
    public static let valueWhenUnset = false

    public static func isComplete(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? valueWhenUnset : defaults.bool(forKey: key)
    }

    public static func record(_ complete: Bool, in defaults: UserDefaults) {
        defaults.set(complete, forKey: key)
    }
}

public enum AppRoute: Hashable, CaseIterable, Sendable {
    case licenses

    public var title: String { "Open Source Licenses" }
    public var hidesTabBar: Bool { true }
}
