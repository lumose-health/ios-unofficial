---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
route: {provider: claude, cli: claude, model: sonnet, effort: high, agent: dev, fallback: [openai/gpt-5.6-sol]}
local_gpu: red
gates:
  - "swift build"
  - "swift test"
  - "bash scripts/guards/safety_guards.sh"
max_cycles: 3
---

# Story 1.3: Freshness Tier classification and independent decay

Status: ready-for-review

<!-- Route rationale (for the maintainer): spec is airtight (semantics + values pinned from
Android Freshness.kt, half-open boundaries quoted verbatim), single-module, builds on
the frozen 1-2 API — the standard-tier profile. Sonnet/high; upgrade trigger: bump to
opus if cycle 1 fails gates or review finds semantic (not tooling) errors.
NOT a protected path (no safety-constant redefinitions; thresholds are NEW canonical
values added once, guarded) — PM merge authority applies if all conditions hold. -->

## Story

As a user glancing at a number,
I want the app to know how old that reading is on its own schedule,
So that a stale value is never presented as current.

## Acceptance Criteria

1. A `Freshness` classification with exactly three tiers — Fresh, Stale, TooStale —
   computed from a reading's age with **half-open boundaries, matching Android
   `Freshness.kt` exactly**: `age < staleAfter` → Fresh; `staleAfter <= age <
   tooStaleAfter` → Stale; `age >= tooStaleAfter` → TooStale. Tests pin each boundary
   value: exactly-at-staleAfter is Stale, exactly-at-tooStaleAfter is TooStale,
   one step below each boundary stays in the lower tier (FR-49).
2. The CGM thresholds are canonical constants defined **once**: staleAfter = 6 min,
   tooStaleAfter = 15 min (Android `FreshnessPolicy.CGM`, `Freshness.kt:111`).
   A `FreshnessThresholds` type validates `0 < staleAfter < tooStaleAfter` (throwing,
   not precondition — same AD-5 discipline as Glucose). The guard's canonical-value
   set is EXTENDED to cover both threshold values so a second definition fails the
   gate (AD-2, SI-4); guard self-test covers the new values.
3. Re-evaluation runs on a timer at **one quarter of the stale boundary**, independent
   of new data arriving (FR-50; Android `AlertFloorStatusProvider.kt:64` uses
   `staleAfterMs / 4` clamped — mirror the quarter rule; clamping bounds may follow
   Android's if adopted, else document the choice). The timer/scheduler is INJECTABLE
   (protocol like Clock) so tests drive ticks manually; the wall-clock scheduler
   implementation is the single exempt production use, in its own file, mirroring the
   SystemClock exemption pattern. Tests prove: classification updates on tick with NO
   new reading arriving; a new reading does NOT reset or replace the tick schedule.
4. A **negative age classifies as Fresh for display only** and is structurally unable
   to arm the Alert Floor (AD-14, SI-5): expose the single alert-floor eligibility
   predicate now — age must be `>= -60s` future skew AND within the alert-floor
   staleness window (mirror Android `alertFloorAccepts` /
   `ALERT_FLOOR_MAX_FUTURE_SKEW_MS = 60_000`, `Freshness.kt:59-80`) — so epic-2
   consumes this ONE definition instead of writing its own. Tests pin: age −30s →
   display Fresh AND floor-eligible; age −90s → display Fresh, NOT floor-eligible.
5. The staleness badge is modeled (not yet rendered — no UI target exists until 1.13)
   as a presentation state with exactly three cases carrying the FR-51 contract:
   Fresh → renders nothing; Stale → literal text "Stale", amber semantic colour;
   TooStale → literal text "Too old", error semantic colour. Colours are semantic
   TOKENS (enum case names), not RGB values. Tests pin text literals and case mapping.
6. All three gates green; guard self-test green including the extended canonical set.

## Tasks / Subtasks

- [x] Task 1: `Freshness` enum + `FreshnessThresholds` (throwing validation) +
      `FreshnessPolicy.cgm` canonical constants in `Sources/SafetyCore/` (AC: 1, 2)
- [x] Task 2: classification function on age (TimeInterval), driven via
      `GlucoseReading.age(asOf:)` — signed age passes through; boundary tests (AC: 1, 4)
- [x] Task 3: alert-floor eligibility predicate beside freshness (single definition,
      60s max future skew) + tests (AC: 4)
- [x] Task 4: injectable scheduler protocol + wall-clock impl (own file, guard-exempt
      like SystemClock) + `FreshnessMonitor` re-evaluating on quarter-boundary ticks;
      tests with a manual scheduler prove tick-driven reclassification and
      independence from data arrival (AC: 3)
- [x] Task 5: badge presentation model + tests (AC: 5)
- [x] Task 6: extend `scripts/guards/safety_guards.sh` canonical set with the two
      threshold values (in their stored unit) + self-test cases; all gates green (AC: 2, 6)

## Dev Notes

### Builds on (frozen 1-2 API — do not modify existing production files)

`Glucose`, `GlucoseReading` (`age(asOf: some Clock) -> TimeInterval`, signed,
interpretation-free by design — its doc comment says freshness policy lives HERE),
`Clock` protocol / `SystemClock` (exemption pattern), `SafetyConstants`.
Modifying existing `Sources/` files is allowed ONLY if additive necessity emerges
(e.g. none expected); flag any such change in the Dev Agent Record.

### Android ground truth (read-only)

- `app/src/main/java/com/glycemicgpt/mobile/domain/freshness/Freshness.kt` — tier
  semantics (lines 29-47), thresholds (line 111: 6/15 min), skew constant + floor
  predicate (lines 59-80). Mirror semantics EXACTLY; do not invent different values.
- `app/src/main/java/com/glycemicgpt/mobile/service/AlertFloorStatusProvider.kt:64` —
  quarter-boundary tick with clamp.
- Android's `debugFastStaleness` compressed policy is OUT OF SCOPE (story 2.12).

### Constraints

- SafetyCore keeps ZERO dependencies (Foundation only). No Combine/SwiftUI here.
- Swift 6 strict concurrency: `FreshnessMonitor` must be concurrency-clean
  (actor or Sendable-safe design); no `@unchecked Sendable` without written
  justification in the Dev Agent Record.
- Units: store thresholds as `TimeInterval` seconds (360, 900) — pick ONE canonical
  numeric representation, note it in the guard entry (the guard matches numeric
  values, any spelling).
- Worktree sandbox: `.claude/settings.local.json` grants Android read access +
  swift/bash allowlist; publish commands denied during implementation. Never commit
  `.claude/` or `_bmad-output/`. Scratch work under `.build/` inside the worktree,
  NOT `/tmp` (blocked).

### Testing standards summary

Swift Testing/XCTest per 1-2's existing test conventions (mirror what
`Tests/SafetyCoreTests/` already uses). Boundary pinning per AC; manual-scheduler
tick tests; no timer sleeps in tests (inject, don't wait).

### Project structure notes

Surface: `Sources/SafetyCore/Freshness*.swift` (+ scheduler file),
`Tests/SafetyCoreTests/Freshness*`, `scripts/guards/safety_guards.sh` (+ self-test).
Branch from `develop` AFTER story 1-2 merges — this story depends on it.
(1-2's PR #4 was closed when its branch was renamed to `feat/safetycore-constants`;
the live PR is now #5, same tree squashed to one clean commit.)
PR targets `develop`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.3 (FR-49, FR-50, FR-51, SI-5)]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md#AD-14, #Structural-Seed]
- [Source: android-unofficial Freshness.kt, AlertFloorStatusProvider.kt]
- [Source: _bmad-output/implementation-artifacts/1-2-safetycore-canonical-glucose-safety-constants-and-one-clock.md — API + guard architecture + Dev Agent Record]

## Dev Agent Record

### Agent Model Used

Sonnet 5 (route: claude/sonnet, effort high), cycle 1.

### Debug Log References

- `swift build` — clean, no warnings, from a fresh `.build/` (Swift 6 strict
  concurrency confirmed with no cache carried over).
- `swift test` — 59 tests, 11 suites, all passed.
- `bash scripts/guards/safety_guards.sh` — clean (5 canonical constants now
  checked, up from 3).
- `bash scripts/guards/safety_guards.sh --self-test` — 66 cases + 2 documented
  known bypasses, 0 unexpected results.

### Completion Notes List

- Modified an existing frozen 1-2 file: `SafetyConstants.swift` gained
  `cgmStaleAfter` / `cgmTooStaleAfter` (`TimeInterval` seconds, 360/900) and a
  one-word doc tweak ("these three values" → "these values", now that a fourth
  and fifth constant live there). This was additive necessity, not a style
  choice: `safety_guards.sh`'s classifier hardcodes ONE canonical file for every
  entry in `CANON_SPEC` (`classify_numerics.awk`'s `canonical_file` check), so
  the two new threshold literals had nowhere else to legally live once the guard
  was extended to cover them (AC 2). `FreshnessPolicy.cgm` assembles them into
  the validated `FreshnessThresholds` — no other file re-spells 360 or 900.
- `FreshnessThresholds.classify(_:asOf:)` (the `GlucoseReading` convenience) is
  unusable from `FreshnessMonitor`, where the clock is stored as `any Clock`:
  Swift 6 rejects passing an existential to `GlucoseReading.age(asOf: some
  Clock)`'s generic parameter (`type 'any Clock' cannot conform to 'Clock'`).
  `FreshnessMonitor.reevaluate()` computes the age directly
  (`clock.now.timeIntervalSince(reading.timestamp)`) instead — same arithmetic
  `age(asOf:)` does internally, just inlined at the one call site that needs it
  through an existential. Flagging because it means the convenience method is
  presently only exercised by tests holding a concrete `Clock`, not by
  production code.
- `WallClockScheduler` needed no `safety_guards.sh` clock-exemption entry: it
  drives ticks with `Task.sleep(for:)` against Swift Concurrency's clock, never
  `Date()` or any `CLOCK_FORBIDDEN` spelling. Kept in its own file anyway,
  mirroring `SystemClock`'s isolation, per the Dev Notes instruction — the guard
  script's comments call this out so the absence of a new exemption line isn't
  mistaken for an oversight.
- `FreshnessMonitor` is an actor (not `@unchecked Sendable`) holding `latestReading`
  and `freshness`; `Scheduler.scheduleRepeating`'s `action` closure is itself
  `async` (`@Sendable () async -> Void`) rather than sync-dispatching a `Task`,
  so a test's manual scheduler can `await` a tick through to completion
  deterministically instead of racing a fire-and-forget `Task`.
- Alert-floor skew constant (60s, `AlertFloorEligibility.maxFutureSkew`) was
  NOT added to the guard's canonical set — AC 2 and Task 6 both scope the guard
  extension to "the two threshold values" (staleAfter/tooStaleAfter), not the
  skew constant. Left as a plain `TimeInterval` literal in its own file.
- Guard band for the two new constants: ±5%. **Corrected in cycle 2** — this
  originally claimed to catch "off-by-a-minute drift (355, 890)"; neither
  example is a minute of drift (355 and 890 are 5s/10s off), and a real
  round-minute drift (420, 840) sits outside the band. See the cycle 2 section
  below. Self-test gained 4 new cases (`dup-`/`drifted-` for each new constant)
  plus the existing numeric-literal controls were extended to include 360/900 so
  comment/string-elision coverage doesn't regress for the new values.
- `FreshnessMonitor`'s quarter-boundary clamp bounds (2s floor, 30s ceiling) were
  adopted directly from Android's `AlertFloorStatusProvider.kt` `MIN_TICK_MS` /
  `MAX_TICK_MS` rather than re-derived, per the Dev Notes' "may follow Android's
  if adopted" option.

### File List

- `Sources/SafetyCore/SafetyConstants.swift` (modified — additive; see notes above)
- `Sources/SafetyCore/Freshness.swift` (new)
- `Sources/SafetyCore/FreshnessThresholds.swift` (new)
- `Sources/SafetyCore/FreshnessPolicy.swift` (new)
- `Sources/SafetyCore/AlertFloorEligibility.swift` (new)
- `Sources/SafetyCore/FreshnessBadge.swift` (new)
- `Sources/SafetyCore/Scheduler.swift` (new; modified cycle 2 — cancellation)
- `Sources/SafetyCore/WallClockScheduler.swift` (new; modified cycle 2 — cancellation)
- `Sources/SafetyCore/FreshnessMonitor.swift` (new; modified cycle 2 — cancellation)
- `Tests/SafetyCoreTests/FreshnessTests.swift` (new)
- `Tests/SafetyCoreTests/AlertFloorEligibilityTests.swift` (new)
- `Tests/SafetyCoreTests/FreshnessBadgeTests.swift` (new)
- `Tests/SafetyCoreTests/FreshnessMonitorTests.swift` (new; modified cycle 2 — new tests)
- `Tests/SafetyCoreTests/WallClockSchedulerTests.swift` (new, cycle 2)
- `scripts/guards/safety_guards.sh` (modified — extended CANON_SPEC, band
  rationale comment, and self-test cases per Task 6; modified again cycle 2 —
  corrected band rationale, new self-test cases)

## Cycle 2 — REQUIRED CHANGES from adversarial review

Read _bmad-output/implementation-artifacts/1-3-review-codex.md in full. Three MINOR
findings must be fixed this cycle (the review's "Verified behavior" list is frozen —
do not change any verified semantics):

1. Scheduler lifecycle: registrations must be terminable. Give the Scheduler
   protocol a cancellation mechanism (token/handle), make WallClockScheduler stop
   its repeating task when the registration is cancelled or the monitor ends, and
   prove it with a test (a released/cancelled monitor's tick loop stops).
2. Guard drift bands: make the coverage claim honest. Either widen/redesign the
   band strategy so genuine one-minute drifts (420, 840) are caught without
   swallowing unrelated literals like 365, or narrow the stated rationale in the
   script comments AND Dev Agent Record to what the bands actually do — and fix
   the stale header example that lists 900 as uncaught. Self-test cases must match
   whatever the final claim is.
3. Add the missing schedule-independence test exactly as the review specifies:
   original reading at t=0, replacement at t=100, advance to t=400, fire the
   EXISTING registration's tick, assert Fresh (age 300) not Stale (age 400).

All gates plus --self-test must be green. Update the Dev Agent Record with what
changed and why, per finding.

## Cycle 2 — Dev Agent Record

### Agent Model Used

Sonnet 5 (route: claude/sonnet, effort high), cycle 2.

### Debug Log References

- `swift build` — clean.
- `swift test` — 62 tests, 12 suites, all passed (up from 59/11 — one new suite,
  `WallClockSchedulerTests`, plus two new tests in `FreshnessMonitorTests`).
- `bash scripts/guards/safety_guards.sh` — clean (6 canonical constants checked,
  unchanged from cycle 1).
- `bash scripts/guards/safety_guards.sh --self-test` — 69 cases + 2 documented
  known bypasses, 0 unexpected results (up from 66, +3 for finding 2).

### Completion Notes List, per finding

1. **Scheduler lifecycle.** Added `SchedulerRegistration` (a `cancel()`
   protocol) returned from `Scheduler.scheduleRepeating`. `WallClockScheduler`
   now retains its `Task` behind a `WallClockRegistration` and checks
   `Task.isCancelled` again right after waking from sleep, before running the
   action, so a cancel that lands during the sleep skips the next action too.
   `FreshnessMonitor` stores the registration and cancels it in `deinit`.
   Getting there required a detour: writing the registration straight to an
   actor-isolated `var` from `init`, in the same statement that hands the
   scheduler a `[weak self]` escaping closure, doesn't compile under Swift 6 —
   "cannot access property here in nonisolated initializer" — because handing
   out that closure is treated as `self` potentially escaping before `init`
   completes, after which only *nonisolated* properties of `self` may be
   touched. `registration` is routed through a private `RegistrationBox`
   (`@unchecked Sendable`, its own `NSLock`) held in a `let` — reading a `let`
   property needs no actor isolation, so setting the box's contents after the
   closure exists is legal, and `deinit` (already `nonisolated`, can't
   `await`) can call `cancel()` on it synchronously.
   Proved with two tests: `WallClockSchedulerTests.cancelStopsTicking` runs the
   real `WallClockScheduler` at a 0.02s interval, cancels, and checks the tick
   counter stops climbing — this is the one test in the suite that waits on
   real elapsed time, same exemption as `SystemClock`'s test, because it is
   the one exempt production adapter under test. Cooperative cancellation
   means a tick already past the `isCancelled` check can still land right
   after `cancel()` returns, so the assertion doesn't pin an exact count at
   that instant; it takes two readings spaced apart afterward and requires
   them to agree. `FreshnessMonitorTests.monitorCancelsRegistrationOnDeinit`
   uses the (also updated) `ManualScheduler`, which now hands back a
   registration wired to a `cancelledCount`, and proves a released monitor
   cancels it.
2. **Guard drift bands.** The review is right that a contiguous band
   containing 420 (a full round-minute drift from 360) would have to contain
   365 too — there's no way to reach one without the other for a band
   centered on 360. Rather than widen the band (which the review's own "365"
   example shows just trades one false claim for a real false-positive
   problem), narrowed the claim to match what the band has always actually
   done: catches an off-by-a-few-seconds drift (355, 890), not a
   round-minute one. Fixed the header's stale "NOT CAUGHT" example, which
   listed `let ceiling = 900` — 900 is now an exact canonical value (added
   this story) and so is caught exactly; replaced it with `let
   staleAfterDrift = 420`, which is genuinely outside the band. Added three
   self-test cases that execute the corrected claim rather than leaving it as
   prose: `cgm-stale-after-minute-drift-uncaught` and
   `cgm-too-stale-after-minute-drift-uncaught` (420/840, expect PASS — not
   caught) and `cgm-band-swallows-unrelated-integer` (365, expect FAIL —
   caught, pinning the trade-off honestly instead of asserting around it).
   Also corrected this same overstatement in this story's own cycle 1
   Completion Notes entry above, per the review's instruction to fix the
   claim in both places.
3. **Schedule-independence test.** Added
   `FreshnessMonitorTests.tickUsesLatestReadingNotTheOriginal`, built exactly
   to the review's repro: install a reading at t=0, install a replacement at
   t=100 (still one registration), advance the clock to t=400 total, fire the
   existing registration's `tick()`, and assert `.fresh` — the replacement's
   age is 300 (< `staleAfter` 360), and the test would see `.stale` instead if
   the tick closure had somehow kept classifying the original reading (age
   400) rather than `latestReading` at call time.

No other production behavior changed — the tier boundaries, alert-floor
eligibility, badge mapping, and quarter-cadence math the cycle 1 review
verified are untouched.

## Merge log (PM, 2026-08-18)

PR #6 squash-merged to develop (7ab9faa) under PM merge authority. Evidence:
stamped route claude/sonnet, 2 dev cycles; cross-provider adversarial review
(2 rounds: CHANGES-REQUIRED with 3 MINOR findings, then APPROVED); PR wave all
green (CodeRabbit, Devin Review, GitGuardian, Seer); 1 triage round fixed 4
findings (2 CodeRabbit Majors, 1 Devin BUG, 1 monotonicity), 1 dispositioned;
final gates 65 tests/12 suites, self-test 72 cases/0 unexpected. Protected-path
call: story stamped NOT protected at planning; AlertFloorEligibility is
alert-floor-ADJACENT (data predicate, Android-mirrored, guarded) — actual
alarming behavior is epic 2 and will escalate on its own merge. Flagged here
for async audit.
