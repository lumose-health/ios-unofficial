import SwiftUI
import AppFeature
import SimulatedDriver
#if TRACE_REPLAY_DRIVER_ENABLED
import TraceReplayDriver
#endif
import SafetyCore
import DomainCore
@_spi(DriverPlatform) import DriverAPI

@main
struct GlycemicGPTApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: HomeModel
    @State private var driversModel: DriversModel
    @State private var onboarding: OnboardingModel
    private let startDestination: StartDestination

    init() {
        startDestination = StartDestination.resolve(onboardingComplete: OnboardingCompletion.isComplete(in: .standard))
        let validator = AppComposition.makeSafetyValidator()
        let simulated = SimulatedDriver(clock: SystemClock(), scheduler: WallClockScheduler(), validator: validator)
        var drivers: [any Driver] = [simulated]
#if TRACE_REPLAY_DRIVER_ENABLED
        drivers.append(TraceReplayDriver(validator: validator))
#endif
        let store = FileDriverSelectionStore(fileURL: AppComposition.driverSelectionFileURL)
        let registry: DriverRegistry
        do { registry = try DriverRegistry(drivers: drivers, store: store) }
        catch { preconditionFailure("Driver identifiers in this build must be unique: \(error)") }
        let startup = Task {
            await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: SimulatedDriver.identifier)
        }
        _model = State(initialValue: HomeModel(registry: registry, awaitStartup: { await startup.value },
                                              demoIdentifiers: AppComposition.demoIdentifiers(for: drivers.map { $0.descriptor })))
        _driversModel = State(initialValue: DriversModel(registry: registry))
        _onboarding = State(initialValue: OnboardingModel(backend: UnavailableOnboardingBackend(), authorizations: SystemOnboardingAuthorizations(), defaults: .standard))
    }

    var body: some Scene {
        WindowGroup {
            AppShell(startDestination: startDestination, onboarding: onboarding)
                .task { await model.setScenePhaseActive(true).value }
            .environment(model)
            .environment(driversModel)
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
