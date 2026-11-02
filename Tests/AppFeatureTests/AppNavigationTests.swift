import Testing
@testable import AppFeature
import DriverAPI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private struct NavigationAuthorizations: OnboardingAuthorizations {
    func requestNotificationAuthorization(options: NotificationAuthorizationOptions) async -> NotificationAuthorizationOutcome { .granted }
    func requestBluetoothAuthorization() async -> BluetoothAuthorizationOutcome { .allowed }
}

@Suite("App navigation")
struct AppNavigationTests {
    private var configuredBackend: BackendConfiguration {
        .configured(.init(sync: .init(hasError: false, pendingCount: 0, lastSync: nil), reachability: .reachable))
    }

    @Test func visibleTabsFollowBackendConfiguration() {
        let localTabs: [AppTab] = [.home, .alerts, .settings]
        let configuredTabs: [AppTab] = [.home, .aiChat, .alerts, .settings]
        #expect(AppTab.visible(backend: .notConfigured) == localTabs)
        #expect(AppTab.visible(backend: configuredBackend) == configuredTabs)
        for tab in [AppTab.home, .alerts, .settings] {
            #expect(localTabs.contains(tab))
            #expect(configuredTabs.contains(tab))
        }
        #expect(!localTabs.contains(.aiChat))
        #expect(configuredTabs.contains(.aiChat))
    }

    @Test func tabMetadataMatchesNavigationContractAndIdentifiersAreUnique() {
        #expect(AppTab.allCases.map(\.title) == ["Home", "AI Chat", "Alerts", "Settings"])
        #expect(AppTab.allCases.map(\.systemImage) == ["house", "bubble.left.and.bubble.right", "bell", "gearshape"])
        let identifiers = AppTab.allCases.map(\.accessibilityIdentifier)
        #expect(identifiers == ["tab.home", "tab.aiChat", "tab.alerts", "tab.settings"])
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test func removedSelectedTabFallsBackToHome() {
        let localTabs = AppTab.visible(backend: .notConfigured)
        #expect(AppTab.effectiveSelection(.aiChat, visible: localTabs) == .home)
        #expect(AppTab.effectiveSelection(.alerts, visible: localTabs) == .alerts)
        for tab in AppTab.allCases {
            let expected = localTabs.contains(tab) ? tab : .home
            #expect(AppTab.effectiveSelection(tab, visible: localTabs) == expected)
            #expect(AppTab.effectiveSelection(tab, visible: AppTab.visible(backend: configuredBackend)) == tab)
        }
    }

    @Test func startDestinationDependsOnOnboardingCompletion() {
        #expect(StartDestination.resolve(onboardingComplete: true) == .main)
        #expect(StartDestination.resolve(onboardingComplete: false) == .onboarding)
    }

    @Test func onboardingCompletionPersistsStoredValuesAndDefaultsWhenUnset() {
        let suiteName = "AppNavigationTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(OnboardingCompletion.key == "onboardingComplete")
        #expect(OnboardingCompletion.isComplete(in: defaults) == OnboardingCompletion.valueWhenUnset)
        #expect(OnboardingCompletion.valueWhenUnset == false)
        #expect(StartDestination.resolve(onboardingComplete: OnboardingCompletion.isComplete(in: defaults)) == .onboarding)

        OnboardingCompletion.record(true, in: defaults)
        #expect(OnboardingCompletion.isComplete(in: defaults))
        OnboardingCompletion.record(false, in: defaults)
        #expect(!OnboardingCompletion.isComplete(in: defaults))
        #expect(StartDestination.resolve(onboardingComplete: OnboardingCompletion.isComplete(in: defaults)) == .onboarding)
    }

    @Test func onboardingCompletionReadsLaunchArgumentStrings() {
        let suiteName = "AppNavigationTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // A `-onboardingComplete NO` launch argument arrives as a string, not a Bool.
        defaults.set("NO", forKey: OnboardingCompletion.key)
        #expect(!OnboardingCompletion.isComplete(in: defaults))
        defaults.set("YES", forKey: OnboardingCompletion.key)
        #expect(OnboardingCompletion.isComplete(in: defaults))
    }

    @Test func detailRoutesHideTabBarAndHaveExpectedTitle() {
        let allHide = AppRoute.allCases.allSatisfy { $0.hidesTabBar }
        #expect(allHide)
        #expect(AppRoute.licenses.title == "Open Source Licenses")
    }

    @MainActor @Test func shellKeepsBannerAtRootForBothDestinations() {
        let suiteName = "AppNavigationShell-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = OnboardingModel(backend: UnavailableOnboardingBackend(), authorizations: NavigationAuthorizations(), defaults: defaults)
        let mainBody = AppShell(startDestination: .main, onboarding: model).body
        let onboardingBody = AppShell(startDestination: .onboarding, onboarding: model).body
        #expect(String(describing: type(of: mainBody)).hasPrefix("DemoDataBannerRoot<"))
        #expect(String(describing: type(of: onboardingBody)).hasPrefix("DemoDataBannerRoot<"))
    }
}

#if canImport(UIKit)
extension AppNavigationTests {
    @Test func everyTabSymbolResolvesToAnSFSymbol() {
        for tab in AppTab.allCases {
            #expect(UIImage(systemName: tab.systemImage) != nil, "Missing SF Symbol: \(tab.systemImage)")
        }
    }
}
#elseif canImport(AppKit)
extension AppNavigationTests {
    @Test func everyTabSymbolResolvesToAnSFSymbol() {
        for tab in AppTab.allCases {
            #expect(NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: nil) != nil, "Missing SF Symbol: \(tab.systemImage)")
        }
    }
}
#endif
