import Testing
import Foundation
import AppFeature
import SafetyCore
import DriverAPI
@_spi(DriverPlatform) import DriverAPI

@Suite("Driver host")
struct DriverHostTests {
    @Test @MainActor func demoFlagExistsBeforeActivationAndAfterSuccess() async {
        let driver = HostTestDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier])
        #expect(model.isDemo)
        #expect(model.lifecycleState == .notActivated)

        await model.activateIfNeeded()

        #expect(model.isDemo)
        #expect(model.lifecycleState == .active)
        #expect(model.ports?.identifier == driver.descriptor.identifier)
    }

    @Test @MainActor func demoFlagRemainsOnAfterActivationFailureAndLifecycleFails() async {
        let driver = HostTestDriver(activationFailure: .transportUnavailable)
        let model = HomeModel(driver: driver, demoIdentifiers: [HostTestDriver.simulatedIdentifier])
        #expect(model.isDemo)

        await model.activateIfNeeded()

        #expect(model.isDemo)
        #expect(model.lifecycleState == .failed)
        guard case .activation(.transportUnavailable)? = model.hostError else {
            Issue.record("Expected the activation failure to retain its DriverFailure")
            return
        }
        #expect(await driver.didDeactivate)
    }

    @Test @MainActor func unavailableGlucosePortDeactivatesAndFails() async {
        let model = HomeModel(driver: HostTestDriver(missing: .glucoseSource), demoIdentifiers: [])
        await model.activateIfNeeded()
        #expect(model.lifecycleState == .failed)
        guard case .glucosePortUnavailable? = model.hostError else { Issue.record("Expected glucose port error"); return }
    }

    @Test @MainActor func unavailableInsulinPortDeactivatesAndFails() async {
        let model = HomeModel(driver: HostTestDriver(missing: .insulinSource), demoIdentifiers: [])
        await model.activateIfNeeded()
        #expect(model.lifecycleState == .failed)
        guard case .insulinPortUnavailable? = model.hostError else { Issue.record("Expected insulin port error"); return }
    }

    @Test @MainActor func repeatedActivationDoesNotReactivateHostedDriver() async {
        let driver = HostTestDriver()
        let model = HomeModel(driver: driver, demoIdentifiers: [])
        await model.activateIfNeeded()
        await model.activateIfNeeded()
        #expect(await driver.activationCount == 1)
    }

    @Test func canonicalSafetyValidatorCanBeConstructed() {
        let validator = AppComposition.makeSafetyValidator()
        #expect(validator.limitsInForce.glucoseRange == SafetyConstants.glucoseValidRange)
    }
}

private actor HostTestDriver: Driver {
    static let simulatedIdentifier = DriverIdentifier("com.glycemicgpt.simulated")!
    nonisolated let descriptor: DriverDescriptor
    private let glucose = HostGlucoseSource()
    private let insulin = HostInsulinSource()
    private let activationFailure: DriverFailure?
    private let missing: Capability?
    private(set) var activationCount = 0
    private(set) var didDeactivate = false

    init(activationFailure: DriverFailure? = nil, missing: Capability? = nil) {
        self.activationFailure = activationFailure
        self.missing = missing
        self.descriptor = DriverDescriptor(
            identifier: Self.simulatedIdentifier,
            targetName: "HostTestDriver",
            displayName: "Host test Driver",
            transport: .inProcess,
            version: "1.0.0",
            capabilities: [.glucoseSource, .insulinSource],
            verification: .unverified
        )
    }

    func capability(_ capability: Capability) -> CapabilityPort? {
        guard capability != missing else { return nil }
        return switch capability {
        case .glucoseSource: .glucoseSource(glucose)
        case .insulinSource: .insulinSource(insulin)
        case .pumpStatus, .bgmSource, .dataSync, .doseCategoryProvider: nil
        }
    }

    func activate() async throws(DriverFailure) {
        activationCount += 1
        if let activationFailure { throw activationFailure }
    }

    func deactivate() async { didDeactivate = true }
}

private struct HostGlucoseSource: GlucoseSource {
    var readings: AsyncStream<GlucoseSample> { AsyncStream { $0.finish() } }
    func latestReading() async throws(DriverFailure) -> GlucoseSample? { nil }
}

private struct HostInsulinSource: InsulinSource {
    var insulinOnBoard: AsyncStream<InsulinOnBoardSample> { AsyncStream { $0.finish() } }
    func doses(since: Date) async throws(DriverFailure) -> [DoseRecord] { [] }
}
