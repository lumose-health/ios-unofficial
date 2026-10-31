import SwiftUI
import AppFeature
import SimulatedDriver
import SafetyCore
@_spi(DriverPlatform) import DriverAPI

@main
struct GlycemicGPTApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: HomeModel

    init() {
        let validator = AppComposition.makeSafetyValidator()
        let driver = SimulatedDriver(clock: SystemClock(), scheduler: WallClockScheduler(), validator: validator)
        _model = State(initialValue: HomeModel(driver: driver, demoIdentifiers: [SimulatedDriver.identifier]))
    }

    var body: some Scene {
        WindowGroup {
            DemoDataBannerRoot {
                Group {
                    if let activationError = model.hostError {
                        VStack(spacing: 12) {
                            Text("Unable to start data source").font(.headline)
                            Text(activationError.recoverer)
                        }.padding(16)
                    } else {
                        HomeScreen()
                    }
                }
                .task { await model.activateIfNeeded() }
            }
            .environment(model)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    Task { await model.stop() }
                } else if phase == .active {
                    Task { await model.activateIfNeeded() }
                }
            }
        }
    }
}
