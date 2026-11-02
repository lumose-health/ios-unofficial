import SwiftUI

public struct AppShell: View {
    private let startDestination: StartDestination
    private let onboarding: OnboardingModel

    public init(startDestination: StartDestination, onboarding: OnboardingModel) {
        self.startDestination = startDestination
        self.onboarding = onboarding
    }

    public var body: some View {
        DemoDataBannerRoot { AppRootView(startDestination: startDestination, onboarding: onboarding) }
    }
}

struct AppRootView: View {
    @State private var destination: StartDestination
    let onboarding: OnboardingModel

    init(startDestination: StartDestination, onboarding: OnboardingModel) {
        _destination = State(initialValue: startDestination)
        self.onboarding = onboarding
    }

    var body: some View {
        switch destination {
        case .main: MainTabView()
        case .onboarding: OnboardingFlowView(model: onboarding, onFinished: { destination = .main })
        }
    }
}

struct MainTabView: View {
    @Environment(HomeModel.self) private var model
    @State private var selection: AppTab = .home
    @State private var paths: [AppTab: [AppRoute]] = [:]

    private var visibleTabs: [AppTab] { AppTab.visible(backend: model.backend) }

    private var selectedTab: Binding<AppTab> {
        Binding(
            get: { AppTab.effectiveSelection(selection, visible: visibleTabs) },
            set: { selection = $0 }
        )
    }

    var body: some View {
        // Tab bar buttons are matched by their stable titles. iOS 26 does not carry a
        // SwiftUI identifier (on `Tab`, its label, or `.tabItem`) onto the button.
        TabView(selection: selectedTab) {
            ForEach(visibleTabs, id: \.self) { tab in
                tabStack(tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .onChange(of: visibleTabs, initial: true) { _, tabs in
            let fallback = AppTab.effectiveSelection(selection, visible: tabs)
            if fallback != selection { selection = fallback }
        }
    }

    private func tabStack(_ tab: AppTab) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            tabRoot(tab)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .licenses: LicenseDestination(route: route)
                    case .drivers: DriversScreen()
                    }
                }
        }
    }

    @ViewBuilder private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            Group {
                if let message = model.sourceMessage {
                    VStack(spacing: 12) {
                        Text(message.title).font(.headline)
                        Text(message.body).foregroundStyle(.primary)
                    }
                    .padding(16)
                    .accessibilityIdentifier(message.identifier)
                } else {
                    HomeScreen()
                }
            }
            .hideNavigationBarOnIOS()
        case .aiChat: PlaceholderView(identifier: "placeholder.aiChat", title: tab.title, messages: ["AI Chat isn't available in this build yet."])
        case .alerts: PlaceholderView(identifier: "placeholder.alerts", title: tab.title, messages: ["Alerts aren't available in this build yet.", "This build does not alert on glucose. Use your CGM's own app or receiver for alarms."])
        case .settings:
            PlaceholderView(identifier: "placeholder.settings", title: tab.title, messages: ["Settings aren't available in this build yet.", "Pump pairing isn't available in this build yet."]) {
                NavigationLink(value: AppRoute.drivers) { Text("Drivers") }
                    .accessibilityIdentifier("settings.drivers")
                NavigationLink(value: AppRoute.licenses) {
                    Text("Open Source Licenses")
                }
                .accessibilityIdentifier("settings.licenses")
            }
        }
    }

    private func pathBinding(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { paths[tab, default: []] },
            set: { paths[tab] = $0 }
        )
    }
}

private struct PlaceholderView<Extra: View>: View {
    let identifier: String
    let title: String?
    let messages: [String]
    let extra: Extra

    init(identifier: String, title: String?, messages: [String], @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.identifier = identifier
        self.title = title
        self.messages = messages
        self.extra = extra()
    }

    var body: some View {
        Group {
            if let title {
                messageContent.navigationTitle(title)
            } else {
                messageContent
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(messages, id: \.self) { Text($0) }
            extra
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LicenseDestination: View {
    let route: AppRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GRDB.swift 7.11.1")
            Text("MIT License")
            Text("https://github.com/groue/GRDB.swift")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(route.title)
        .hideTabBarOnIOS(route.hidesTabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.licenses")
    }
}

private extension View {
    @ViewBuilder
    func hideNavigationBarOnIOS() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func hideTabBarOnIOS(_ hidden: Bool = true) -> some View {
        #if os(iOS)
        toolbar(hidden ? .hidden : .visible, for: .tabBar)
        #else
        self
        #endif
    }
}
