import Foundation
import DriverAPI

/// One step of simulated physiology: everything ``SimulatedDriver`` needs to
/// turn into `DriverAPI` values, before any Safety Limit or timestamp is
/// attached.
struct SimulatedTick: Equatable {
    let glucoseMgdl: Double
    let glucoseDeltaMgdl: Double
    let insulinOnBoardUnits: Double

    /// Doses completed this tick: zero, one, or (rarely, when a meal and a
    /// basal segment land on the same tick) two. The periodic meal dose is
    /// the only discrete "bolus" this model has; the continuous basal
    /// contribution is folded into ``insulinOnBoardUnits`` every tick and is
    /// additionally reported once per basal segment as its own record, so
    /// `doses(since:)` can see it — `DoseCategory` has no basal case
    /// (it mirrors Android's bolus-only category vocabulary), so it is
    /// reported as ``DoseCategory/other``, the vocabulary's honest catch-all.
    let completedDoses: [CompletedDose]
}

/// One completed dose the generator is reporting this tick — not yet a
/// `DriverAPI` `DoseRecord`, which requires a `Clock`-stamped `completedAt`
/// this pure model does not have.
struct CompletedDose: Equatable {
    let units: Double
    let category: DoseCategory
    let deviceLabel: String
}

/// A seeded, deterministic CGM-and-insulin trace.
///
/// ## The model, briefly
///
/// Glucose chases a smooth 24-hour TARGET curve — a baseline, a diurnal dip
/// around 03:00, and three meal-shaped rises (breakfast/lunch/dinner, each a
/// half-sine bump over three hours) — perturbed by small seeded noise. It
/// does not jump to that target: every tick, ``glucoseMgdl`` moves toward it
/// by a step CLAMPED to ``maxStepDelta``. That clamp is what makes
/// step-to-step deltas bounded BY CONSTRUCTION rather than by convention, and
/// it is also what keeps the value inside ``lowerSimBound``...``upperSimBound``
/// — comfortably inside the platform's absolute 20...500 bound — so nothing
/// this generator produces is ever rejected by `SafetyLimitsValidator`.
///
/// Insulin on board is a single exponentially-decaying pool: a small
/// continuous basal contribution every tick, plus a larger dose added
/// periodically (the "meal dose"), both decaying with the same time
/// constant. The periodic meal dose is returned as a completed record, and
/// the basal contribution is additionally reported once per hour as its own
/// completed record — summing exactly the continuous contribution already
/// folded into the pool over that hour, so the record documents delivery
/// that already happened rather than adding to it a second time.
///
/// The model is a pure function of the seed and the number of ticks taken —
/// no wall-clock input anywhere in it — so two generators started from the
/// same seed and advanced the same number of times produce IDENTICAL
/// sequences. `SimulatedDriver` supplies timestamps separately, from the
/// `Clock` it was given, when it turns a tick into a `DriverAPI` sample.
struct SimulatedGenerator: Equatable {

    // MARK: Tuning constants — the "briefly" in "document the model briefly"

    /// 5-minute ticks across a simulated 24-hour day.
    static let ticksPerDay = 288
    /// Roughly three meals a day.
    static let ticksPerMealDose = ticksPerDay / 3
    /// Hourly basal segments, at the 5-minute tick length below — a typical
    /// cadence for a pump reporting completed basal delivery in segments
    /// rather than continuously.
    static let ticksPerBasalDose = 12

    static let lowerSimBound = 65.0
    static let upperSimBound = 260.0
    /// Per-tick clamp on how far ``glucoseMgdl`` may move toward its target —
    /// about 2.4 mg/dL/minute at the 5-minute tick length below, comparable to
    /// a real CGM's fastest reported rate of change.
    static let maxStepDelta = 12.0

    private static let baselineMgdl = 110.0
    private static let diurnalAmplitude = 12.0
    private static let troughDayPhase = 0.125                 // ~03:00
    /// Breakfast, lunch and dinner, as minutes since midnight over minutes
    /// per day — 07:00, 12:30, 18:30.
    private static let mealDayPhases = [420.0 / 1440, 750.0 / 1440, 1110.0 / 1440]
    private static let mealDurationDayPhase = 180.0 / 1440
    private static let mealAmplitude = 70.0
    private static let noiseRange = -2.0...2.0

    /// Insulin action time constant, in ticks — 65 minutes of rapid-acting
    /// action at 5 minutes/tick, close enough to a real exponential IOB model
    /// for a simulated trace.
    private static let insulinTimeConstantTicks = 65.0 / 5.0
    /// 0.9 U/hr, expressed per 5-minute tick.
    private static let basalUnitsPerTick = 0.9 / 12.0
    /// What one hourly basal segment sums to: exactly ``basalUnitsPerTick``
    /// times the ticks in that segment, so the reported record matches what
    /// the continuous contribution already added to the pool.
    private static let basalDoseUnitsPerSegment = basalUnitsPerTick * Double(ticksPerBasalDose)
    private static let mealDoseUnits = 4.5

    let seed: UInt64
    private(set) var tickIndex = 0
    private var rng: SplitMix64
    private var glucoseMgdl = SimulatedGenerator.baselineMgdl
    private var insulinOnBoardUnits = 0.0

    init(seed: UInt64) {
        self.seed = seed
        self.rng = SplitMix64(seed: seed)
    }

    static func == (lhs: SimulatedGenerator, rhs: SimulatedGenerator) -> Bool {
        lhs.seed == rhs.seed && lhs.tickIndex == rhs.tickIndex
            && lhs.glucoseMgdl == rhs.glucoseMgdl && lhs.insulinOnBoardUnits == rhs.insulinOnBoardUnits
    }

    /// Advances one tick and returns it. Mutates `self`, so replaying the same
    /// sequence of calls from the same seed reproduces the same outputs.
    mutating func advance() -> SimulatedTick {
        defer { tickIndex += 1 }

        let dayPhase = Double(tickIndex % Self.ticksPerDay) / Double(Self.ticksPerDay)
        let target = Self.baselineMgdl
            + Self.diurnalDrift(dayPhase: dayPhase)
            + Self.mealBump(dayPhase: dayPhase)
            + rng.uniform(in: Self.noiseRange)

        // The reported delta is the change actually APPLIED, measured after
        // the sim-bound clamp, not the pre-clamp step. With the current
        // constants the two are always equal (the target curve never reaches
        // either bound), but deriving the delta from the applied change keeps
        // it truthful if a retuning ever makes that clamp engage.
        let step = min(max(target - glucoseMgdl, -Self.maxStepDelta), Self.maxStepDelta)
        let previousGlucoseMgdl = glucoseMgdl
        glucoseMgdl = min(max(glucoseMgdl + step, Self.lowerSimBound), Self.upperSimBound)
        let delta = glucoseMgdl - previousGlucoseMgdl

        let decay = exp(-1.0 / Self.insulinTimeConstantTicks)
        insulinOnBoardUnits = insulinOnBoardUnits * decay + Self.basalUnitsPerTick

        var doses: [CompletedDose] = []
        if tickIndex % Self.ticksPerMealDose == 0 {
            insulinOnBoardUnits += Self.mealDoseUnits
            doses.append(CompletedDose(units: Self.mealDoseUnits, category: .food, deviceLabel: "Simulated meal bolus"))
        }
        if tickIndex % Self.ticksPerBasalDose == 0 {
            doses.append(CompletedDose(units: Self.basalDoseUnitsPerSegment, category: .other, deviceLabel: "Simulated basal"))
        }

        return SimulatedTick(
            glucoseMgdl: glucoseMgdl,
            glucoseDeltaMgdl: delta,
            insulinOnBoardUnits: insulinOnBoardUnits,
            completedDoses: doses
        )
    }

    private static func diurnalDrift(dayPhase: Double) -> Double {
        -diurnalAmplitude * cos(2 * Double.pi * (dayPhase - troughDayPhase))
    }

    private static func mealBump(dayPhase: Double) -> Double {
        mealDayPhases.reduce(0.0) { total, mealPhase in
            var sinceMeal = dayPhase - mealPhase
            if sinceMeal < 0 { sinceMeal += 1 }
            guard sinceMeal < mealDurationDayPhase else { return total }
            return total + mealAmplitude * sin(.pi * sinceMeal / mealDurationDayPhase)
        }
    }
}
