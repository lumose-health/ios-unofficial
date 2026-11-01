import SwiftUI
import AppFeature
import SimulatedDriver
import SafetyCore
@_spi(DriverPlatform) import DriverAPI

@main
struct GlycemicGPTApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: HomeModel
    @State private var onboarding: OnboardingModel
    private let startDestination: StartDestination

    init() {
        startDestination = StartDestination.resolve(onboardingComplete: OnboardingCompletion.isComplete(in: .standard))
        let validator = AppComposition.makeSafetyValidator()
        let driver = SimulatedDriver(clock: SystemClock(), scheduler: WallClockScheduler(), validator: validator)
        _model = State(initialValue: HomeModel(driver: driver, demoIdentifiers: [SimulatedDriver.identifier]))
        _onboarding = State(initialValue: OnboardingModel(backend: UnavailableOnboardingBackend(), defaults: .standard))
    }

    var body: some Scene {
        WindowGroup {
            AppShell(startDestination: startDestination, onboarding: onboarding)
                .task { await model.setScenePhaseActive(true).value }
            .environment(model)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    model.setScenePhaseActive(false)
                } else if phase == .inactive {
                    model.sceneBecameInactive()
                } else if phase == .active {
                    model.setScenePhaseActive(true)
                }
            }
        }
    }
}
