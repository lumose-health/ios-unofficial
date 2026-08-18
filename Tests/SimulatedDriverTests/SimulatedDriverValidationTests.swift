import Foundation
import Testing

@_spi(DriverPlatform) import DriverAPI
@testable import SimulatedDriver

/// Every simulated value passes validation: glucose through the real
/// `SafetyLimitsValidator` path, and insulin-on-board through its own
/// throwing initializer. The SPI import is needed only to CONSTRUCT the
/// validator the way the platform does — `SimulatedDriver` itself never
/// imports the SPI, and `driver_guards.sh` would fail the build if it did.
@Suite("Simulated values pass validation")
struct SimulatedDriverValidationTests {

    @Test("Every glucose value the generator produces passes SafetyLimitsValidator, over a long run")
    func everyGlucoseValuePassesValidation() throws {
        let limits = try SafetyLimits(glucoseLower: 20, glucoseUpper: 500)
        let validator = SafetyLimitsValidator(limits: limits)
        var generator = SimulatedGenerator(seed: SimulatedDriver.defaultSeed)
        for _ in 0..<20_000 {
            let tick = generator.advance()
            _ = try validator.validate(mgdl: tick.glucoseMgdl)
        }
    }

    @Test("A narrower configured limit still admits every generated value")
    func narrowerLimitsStillAdmitTheTrace() throws {
        let limits = try SafetyLimits(
            glucoseLower: SimulatedGenerator.lowerSimBound,
            glucoseUpper: SimulatedGenerator.upperSimBound
        )
        let validator = SafetyLimitsValidator(limits: limits)
        var generator = SimulatedGenerator(seed: SimulatedDriver.defaultSeed)
        for _ in 0..<5_000 {
            let tick = generator.advance()
            _ = try validator.validate(mgdl: tick.glucoseMgdl)
        }
    }

    @Test("Insulin-on-board values construct without throwing, over a long run")
    func insulinOnBoardValuesAreValid() throws {
        var generator = SimulatedGenerator(seed: SimulatedDriver.defaultSeed)
        let reference = Date(timeIntervalSince1970: 0)
        for _ in 0..<20_000 {
            let tick = generator.advance()
            _ = try InsulinOnBoardSample(units: tick.insulinOnBoardUnits, calculatedAt: reference)
        }
    }

    @Test("A value the configured limits reject surfaces as a typed DriverFailure, not a silent nil (AD-13)")
    func rejectedValueSurfacesAsATypedFailureNotASilentNil() async throws {
        // Legal but far narrower than anything the generator's trace ever
        // reaches (it starts at baseline 110 and the default seed's first
        // tick stays well under 150) — every early tick is rejected.
        let limits = try SafetyLimits(glucoseLower: 150, glucoseUpper: 160)
        let validator = SafetyLimitsValidator(limits: limits)
        let clock = ManualClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let scheduler = ManualScheduler()
        let driver = SimulatedDriver(clock: clock, scheduler: scheduler, validator: validator)
        guard case .glucoseSource(let port) = driver.capability(.glucoseSource) else {
            Issue.record("expected a glucoseSource port")
            return
        }

        try await driver.activate()
        clock.advance(by: SimulatedDriver.defaultTickInterval)
        await scheduler.tick()

        await #expect(throws: DriverFailure.self) {
            _ = try await port.latestReading()
        }
    }
}
