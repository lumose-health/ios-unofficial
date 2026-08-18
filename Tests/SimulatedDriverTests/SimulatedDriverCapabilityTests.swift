import Foundation
import Testing

@_spi(DriverPlatform) import DriverAPI
@testable import SimulatedDriver

/// `SimulatedDriver` conforms to `Driver` and provides its declared
/// capabilities through the same ports a real Driver uses.
@Suite("Simulated Driver capabilities")
struct SimulatedDriverCapabilityTests {

    private func makeDriver(
        seed: UInt64 = SimulatedDriver.defaultSeed
    ) throws -> (driver: SimulatedDriver, clock: ManualClock, scheduler: ManualScheduler) {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let scheduler = ManualScheduler()
        let limits = try SafetyLimits(glucoseLower: 20, glucoseUpper: 500)
        let validator = SafetyLimitsValidator(limits: limits)
        let driver = SimulatedDriver(clock: clock, scheduler: scheduler, validator: validator, seed: seed)
        return (driver, clock, scheduler)
    }

    @Test("The descriptor declares exactly the capabilities this Driver can honestly provide")
    func descriptorDeclaresItsCapabilities() throws {
        let (driver, _, _) = try makeDriver()
        #expect(driver.descriptor.capabilities == [.glucoseSource, .insulinSource])
        #expect(driver.descriptor.transport == .inProcess)
        #expect(driver.descriptor.verification == .unverified)
        #expect(driver.descriptor.targetName == "SimulatedDriver")
        #expect(driver.descriptor.identifier == SimulatedDriver.identifier)
    }

    /// The descriptor exists twice by necessity: the instance carries one, and
    /// `DriverCatalog.entries` carries an independent literal (DriverAPI cannot
    /// import SimulatedDriver, so the catalog cannot reference the instance).
    /// This is the assertion that keeps the two copies from drifting: a field
    /// changed in one place only fails here.
    @Test("The instance descriptor and the DriverCatalog entry are the same descriptor")
    func descriptorMatchesTheCatalogEntry() throws {
        let (driver, _, _) = try makeDriver()
        #expect(DriverCatalog.entry(for: SimulatedDriver.identifier) == driver.descriptor)
    }

    @Test("capability(_:) answers a port for exactly what the descriptor declares, and nil otherwise")
    func capabilityMatchesDescriptor() throws {
        let (driver, _, _) = try makeDriver()
        #expect(driver.capability(.glucoseSource) != nil)
        #expect(driver.capability(.insulinSource) != nil)
        for capability in Capability.allCases where !driver.descriptor.capabilities.contains(capability) {
            #expect(driver.capability(capability) == nil, "\(capability)")
        }
    }

    @Test("capability(_:) hands back the port that matches the Capability asked for")
    func capabilityReturnsTheMatchingPortCase() throws {
        let (driver, _, _) = try makeDriver()
        guard let glucosePort = driver.capability(.glucoseSource) else {
            Issue.record("expected a glucoseSource port")
            return
        }
        #expect(glucosePort.capability == .glucoseSource)

        guard let insulinPort = driver.capability(.insulinSource) else {
            Issue.record("expected an insulinSource port")
            return
        }
        #expect(insulinPort.capability == .insulinSource)
    }

    @Test("Before any emission, latestReading() and doses(since:) answer nothing rather than trapping")
    func readsBeforeAnyEmissionAreVacuous() async throws {
        let (driver, clock, _) = try makeDriver()
        guard case .glucoseSource(let glucosePort) = driver.capability(.glucoseSource),
              case .insulinSource(let insulinPort) = driver.capability(.insulinSource) else {
            Issue.record("expected both ports")
            return
        }
        #expect(try await glucosePort.latestReading() == nil)
        #expect(try await insulinPort.doses(since: clock.now).isEmpty)
    }
}
