# Adversarial review: Story 1.5

- MAJOR — Failed-state recovery leaks the prior scheduler registration, so later recovery/teardown can leave an old tick source alive and produce duplicate emissions.
  Evidence: `SimulatedDriver.activate()` always schedules at `Sources/Drivers/Simulated/SimulatedDriver.swift:108`, while `RegistrationBox.set` overwrites without cancelling at line 172; a focused `active → failed → activating` probe observed live registrations `1 → 2`, teardown left `1`, and reactivation returned to `2`, whereas `failedDriverActivatesAgain()` starts from a fresh never-activated driver and cannot catch this.

- MAJOR — Legal safety-limit rejection is silently swallowed instead of surfacing the typed failure to its designated recovery owner.
  Evidence: all three validation/construction failures are erased with `try?` at `Sources/Drivers/Simulated/SimulatedDriver.swift:139-150`, and a focused probe with valid limits `150...160` produced `latestReading() == nil` with no thrown `DriverFailure`, contrary to AD-13's prohibition on silently absorbing failures.

- MAJOR — The shipped insulin capability does not provide the periodic basal events required by AC 2.
  Evidence: `Sources/Drivers/Simulated/SimulatedGenerator.swift:12-16` explicitly says basal never becomes a `DoseRecord`, and lines 112-118 create only periodic `.food` boluses, so `doses(since:)` can never return a basal event.

- MINOR — The claimed IOB/bolus consistency has no regression test relating the two outputs.
  Evidence: `Tests/SimulatedDriverTests/SimulatedGeneratorTests.swift:53-77` checks IOB only for finiteness/non-negativity and doses only for positivity/category/count; no assertion proves a bolus changes the emitted IOB by the recorded amount or then decays consistently.

VERDICT: CHANGES-REQUIRED — Recovery can duplicate emissions, validation failures disappear, and the required basal event surface is missing.

## Cycle 3 re-review

- RESOLVED — Registration leak. An independent `active → failed → activating → teardown → activating` probe observed live-registration counts `1 → 1 → 1 → 0 → 1`. `RegistrationBox.set` now replaces and cancels the prior registration, and `failedRecoveryDoesNotLeakARegistration` pins the same sequence.

- RESOLVED — Swallowed failures. With legal narrow limits `150...160`, the first rejected emission is observable from `latestReading()` as `DriverFailure.valueRejected(bound: "150.0...160.0 mg/dL")`, not `nil`; there is no `try?` on the simulated emission path.

- STILL OPEN — Basal events. The implementation does return `.other` basal `DoseRecord`s through `doses(since:)` at 3,600-second intervals, as confirmed by an independent capability-port probe. However, `periodicBasalDoseIsReportedHourly` checks only that 24 `.other` records occur in one day; mutating the generator to emit those 24 records on 24 consecutive ticks still passes. No shipped test calls `doses(since:)` after emission, so the required public-surface periodicity regression is not pinned.

- RESOLVED — IOB consistency. The regression relates the recorded food dose to the IOB jump and asserts subsequent decay. Mutating only the recorded bolus to disagree with the IOB addition by 1 unit makes the test fail (`1.075 < 0.5` is false), so it detects an inconsistent pair.

- Regression glance: idempotent double-cancel, a single pre-existing stream iterator across reactivation, and fixed-seed determinism all pass. The full suite passes (180 tests, 26 suites), and both safety and driver guards are clean.

VERDICT: CHANGES-REQUIRED — Basal delivery works, but the required regression does not pin hourly periodicity through `doses(since:)`.
