import Testing

@testable import SimulatedDriver

/// The pure math behind ``SimulatedDriver``'s trace: determinism, bound
/// adherence, and delta plausibility, exercised directly on the generator
/// without any `Clock` or `Scheduler` involved.
@Suite("Simulated generator")
struct SimulatedGeneratorTests {

    @Test("The same seed reproduces the same sequence")
    func deterministic() {
        var a = SimulatedGenerator(seed: 42)
        var b = SimulatedGenerator(seed: 42)
        let ticksA = (0..<500).map { _ in a.advance() }
        let ticksB = (0..<500).map { _ in b.advance() }
        #expect(ticksA == ticksB)
    }

    @Test("Different seeds produce different sequences")
    func differentSeedsDiverge() {
        var a = SimulatedGenerator(seed: 1)
        var b = SimulatedGenerator(seed: 2)
        let ticksA = (0..<50).map { _ in a.advance() }
        let ticksB = (0..<50).map { _ in b.advance() }
        #expect(ticksA != ticksB)
    }

    @Test("Glucose never leaves the documented simulated bound over a long run")
    func boundsHoldOverALongRun() {
        var generator = SimulatedGenerator(seed: SimulatedDriver.defaultSeed)
        for _ in 0..<20_000 {
            let tick = generator.advance()
            #expect(tick.glucoseMgdl >= SimulatedGenerator.lowerSimBound)
            #expect(tick.glucoseMgdl <= SimulatedGenerator.upperSimBound)
        }
    }

    @Test("Consecutive glucose deltas stay within the documented step bound")
    func deltasStayBounded() {
        var generator = SimulatedGenerator(seed: 7)
        var previous: Double?
        for _ in 0..<20_000 {
            let tick = generator.advance()
            #expect(abs(tick.glucoseDeltaMgdl) <= SimulatedGenerator.maxStepDelta)
            if let previous {
                #expect(abs(tick.glucoseMgdl - previous) <= SimulatedGenerator.maxStepDelta)
            }
            previous = tick.glucoseMgdl
        }
    }

    @Test("Insulin on board is always finite and non-negative")
    func insulinOnBoardStaysWellFormed() {
        var generator = SimulatedGenerator(seed: 99)
        for _ in 0..<20_000 {
            let tick = generator.advance()
            #expect(tick.insulinOnBoardUnits.isFinite)
            #expect(tick.insulinOnBoardUnits >= 0)
        }
    }

    @Test("The periodic meal dose is a completed, non-negative, categorised bolus")
    func periodicMealDoseIsWellFormed() {
        var generator = SimulatedGenerator(seed: 5)
        var mealDoseCount = 0
        for _ in 0..<SimulatedGenerator.ticksPerDay {
            let tick = generator.advance()
            let mealDoses = tick.completedDoses.filter { $0.category == .food }
            #expect(mealDoses.count <= 1)
            if let mealDose = mealDoses.first {
                #expect(mealDose.units > 0)
                mealDoseCount += 1
            }
        }
        #expect(mealDoseCount == SimulatedGenerator.ticksPerDay / SimulatedGenerator.ticksPerMealDose)
    }

    @Test("A basal dose is completed once per hour, categorised as other, alongside meal boluses")
    func periodicBasalDoseIsReportedHourly() {
        var generator = SimulatedGenerator(seed: 5)
        var basalDoseCount = 0
        for _ in 0..<SimulatedGenerator.ticksPerDay {
            let tick = generator.advance()
            let basalDoses = tick.completedDoses.filter { $0.category == .other }
            #expect(basalDoses.count <= 1)
            if let basalDose = basalDoses.first {
                #expect(basalDose.units > 0)
                basalDoseCount += 1
            }
        }
        #expect(basalDoseCount == SimulatedGenerator.ticksPerDay / SimulatedGenerator.ticksPerBasalDose)
    }

    @Test("A recorded bolus changes IOB by roughly its recorded amount, then IOB decays tick-over-tick until the next dose")
    func bolusChangesIOBByItsRecordedAmountThenDecaysMonotonically() {
        var generator = SimulatedGenerator(seed: 5)
        var previousIOB = 0.0
        var sawDose = false
        var ticksObservedAfterDose = 0

        for _ in 0..<SimulatedGenerator.ticksPerMealDose {
            let tick = generator.advance()
            if let mealDose = tick.completedDoses.first(where: { $0.category == .food }) {
                let increase = tick.insulinOnBoardUnits - previousIOB
                #expect(abs(increase - mealDose.units) < 0.5, "the jump at a bolus tick should track the recorded dose")
                sawDose = true
            } else if sawDose {
                #expect(tick.insulinOnBoardUnits <= previousIOB, "IOB should decay tick-over-tick once no further dose lands")
                ticksObservedAfterDose += 1
            }
            previousIOB = tick.insulinOnBoardUnits
        }

        #expect(sawDose)
        #expect(ticksObservedAfterDose > 0)
    }
}
