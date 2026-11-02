---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/2-2-the-alert-floor-alarming-with-no-backend.md.stamp.json
persona: dev
memory_mode: advisory
gates:
  - "swift build"
  - "swift test"
  - "bash scripts/guards/safety_guards.sh"
  - "bash scripts/guards/safety_guards.sh --self-test"
  - "bash scripts/guards/driver_guards.sh"
  - "bash scripts/guards/driver_guards.sh --self-test"
  - "bash scripts/ci-local.sh --self-test"
  - "xcodebuild test -scheme GlycemicGPT-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd"
  - "xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj -scheme GlycemicGPT -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd CODE_SIGNING_ALLOWED=NO"
max_cycles: 3
---

# Story 2.2: The Alert Floor — alarming with no Backend (decision core)

Status: in-progress

<!-- Planning note (for the maintainer):

SPLIT. epics.md Story 2.2 plus the Tandem decoder follow-up ("below sensor range is an urgent
low", 1-7a Review fixes (b)) is about 1,100 reviewable lines. It is split in two:
- THIS FILE (2.2): the shared alert vocabulary, Alert Thresholds with provenance, the classifier,
  the data-trust bound, and the DomainCore Alert Floor engine with the fixed gate order behind an
  injected notification port. Numeric readings only. Estimate ~780 reviewable lines over ~14
  files, a little over half of it tests.
- 2-2b-below-sensor-range-is-an-urgent-low.md: the DriverAPI sample shape for an out-of-range
  outcome, the Trace-Replay Driver emitting it, and the Alert Floor classifying below-range as
  `low_urgent`. Depends on this file. The PM needs a sprint-status key for it.

NOTHING USER-VISIBLE CHANGES. The engine is not composed into the app here. Composition with the
real `UNUserNotificationCenter` adapter, foreground presentation and the title format is 2.4.
Even after 2.4 the floor stays disarmed in the app until 2.8 lets a user set thresholds, because
this story makes "no thresholds configured" structurally unable to alarm (SI-5). Sequencing the
PM must hold: 2.3 (clock-trust hardening) before 2.8 arms anything.

PROTECTED PATH: this is the alert floor. Merge always escalates to the maintainer. Touches
`SafetyConstants.swift` and `scripts/guards/safety_guards.sh` (one new constant). No dosing
logic, no ingestion mapper, no CI workflow, no dependency or lockfile change. Route: NOT chosen
here; the PM routes via /v1/route. Honest profile: ambiguity low (the PRD pins boundaries, gate
order and strings), blast radius medium (new SafetyCore public types that 2.3-2.12 and the Watch
build on; no existing behaviour changes). -->

## Story

As a user with no server configured,
I want my phone to alarm for a low from the reading it already has,
so that the app is useful and safe on its own.

## Acceptance Criteria

From epics.md Story 2.2 (FR-65, FR-71, SI-1) with the parts of FR-72, FR-73 and FR-74 the gate
order cannot be built or tested without. AC numbering is local to this file.

1. **One alert vocabulary, open, with its delivery tier (FR-65).** SafetyCore defines `AlertType`
   and `AlertSeverity` as open string types (a `RawRepresentable` struct over `String`, never a
   closed enum). Recognised types are exactly `low_urgent`, `low_warning`, `high_warning`,
   `high_urgent`, `iob_warning`, plus `no_data` named as a Backend caregiver type. Recognised
   severities are exactly `warning`, `urgent`, `emergency`. The low set is exactly
   {`low_urgent`, `low_warning`} and the high set exactly {`high_warning`, `high_urgent`}, each
   defined once. Low-set and high-set types have the interrupting tier; `iob_warning`, `no_data`
   and every unrecognised string (for example `"made_up"`) have the informational tier. Nothing
   decodes JSON here; the Backend decoder is Epic 5.
2. **The tier resolves to an interruption level by one runtime read (FR-66, decision 4).**
   `AlertDeliveryTier.interruptionLevel(criticalAlertsEnabled:)` returns `.critical` for the
   interrupting tier when `criticalAlertsEnabled` is true, `.timeSensitive` when it is false, and
   `.active` for the informational tier either way. `AlertInterruptionLevel` is a platform-neutral
   SafetyCore enum with exactly those three cases. There is no build flag and no other input.
   Mapping it to `UNNotificationInterruptionLevel`, and reading `criticalAlertSetting`, is the
   2.4 adapter's job.
3. **Alert Thresholds have provenance, and "not configured" cannot alarm (FR-73, SI-5).**
   `AlertThresholds` holds four integer mg/dL values and throws unless
   `20 ≤ urgentLow ≤ low < high ≤ urgentHigh ≤ 500`, with both bounds read from
   `SafetyConstants.glucoseValidRange`. It rejects, never clamps (FR-79). The setting the floor
   consumes is `AlertThresholdSetting`: `.notConfigured` or `.configured(AlertThresholds,
   AlertThresholdProvenance)`, provenance `.local` or `.backend`. No built-in default thresholds
   exist in this story's code. With `.notConfigured` the floor never fires at any glucose value.
4. **Classification, urgent bands first, inclusive at every edge (FR-71).** A pure SafetyCore
   function maps a `Glucose` and an `AlertThresholds` to `AlertType?`: value ≤ urgent low →
   `low_urgent`; ≥ urgent high → `high_urgent`; ≤ low → `low_warning`; ≥ high → `high_warning`;
   otherwise nil. The value is first rounded to the nearest integer, half away from zero, the
   same rounding `TargetRange.severity(of:)` uses. FR-71's pinned table passes with thresholds
   55/70/180/250 built in the test: 55 → `low_urgent`, 56 → `low_warning`, 70 → `low_warning`,
   71 → nil, 179 → nil, 180 → `high_warning`, 249 → `high_warning`, 250 → `high_urgent`. Also:
   20 and 500 classify; 70.4 → `low_warning`, 70.5 → nil.
5. **One data-trust bound, in SafetyCore, in FR-72's order.** `AlertDataTrust.evaluate(...)`
   runs exactly: (a) wall-clock rewind check against a `WallClockHighWaterMark` → `.clockRewound`;
   (b) advance the mark; (c) thresholds configured, else `.thresholdsNotConfigured`; (d)
   `AlertFloorEligibility.isEligible(age:thresholds:)` on the reading's own sensor timestamp, else
   `.notFresh`; otherwise `.trusted`. The mark suppresses while
   `now + SafetyConstants.alertFloorMaxFutureSkew < mark` and is process-local (a value held by
   the engine, never persisted). FR-72's pinned pairs pass through this function: age 359.999 s
   trusted, 360 s not; age -60 s trusted, -60.001 s not; age -120 s not.
6. **Backend-alerting degradation is evidence-based (FR-71 gate 4).** SafetyCore's
   `BackendAlertingStatus` is `.notConfigured` or `.configured(networkReachable:streamConnected:
   backendHasFreshGlucose:)` where the last input is `Bool?`. `isDegraded` is true when not
   configured, or when any of the three is false, or when the third is nil. A test pins FR-71's
   scenario: reachable, connected, no Backend-side glucose → degraded, and the floor fires an
   urgent low.
7. **Gate order is fixed and tested (FR-71).** `AlertFloor` (a DomainCore actor) evaluates one
   reading in this order and returns an `AlertFloorOutcome` naming where it stopped:
   1. clock rewound → `.suppressed(.clockRewound)`; no episode re-arm runs and the mark does not
      move;
   2. episode re-arm: every acknowledged type other than this reading's classification is fully
      re-armed (its last-fired time and acknowledged flag cleared);
   3. no classification → `.inRange`; when the setting is `.notConfigured` nothing is
      classified and the outcome is `.suppressed(.dataTrust(.thresholdsNotConfigured))`, still at
      this gate, so a later reader of the outcome is told why;
   4. Backend alerting not degraded → `.suppressed(.backendAlerting)`;
   5. data-trust bound not `.trusted` → `.suppressed(.dataTrust(<result>))`;
   6. the port's `canPostAlerts()` false → `.suppressed(.cannotPost)`, checked before any
      cooldown is stamped;
   7. same type fired or acknowledged less than `SafetyConstants.alertFloorCooldown` ago →
      `.suppressed(.coolingDown)`;
   8. fire: post one `AlertFloorNotification` → `.fired(notification)`.
   One test per gate proves that gate stops evaluation and that every later gate did not run
   (the fake port records `canPostAlerts()` and `post` calls).
8. **Cooldown and acknowledgement, in memory (FR-74 core).** The cooldown is
   `SafetyConstants.alertFloorCooldown`, a new constant of 1800 seconds. A second evaluation of
   the same type 1799.999 s after firing is cooling down; at exactly 1800 s it fires again.
   `acknowledge(_:)` stamps that type's last-fired time to `clock.now` and marks it acknowledged.
   Then: a reading that no longer classifies as that type re-arms it, so a re-cross fires at once
   even inside 30 minutes; an unacknowledged type does **not** re-arm on recovery (a hovering
   value does not re-alarm); a sustained acknowledged condition fires again exactly 1800 s after
   the acknowledgement; acknowledging one type leaves every other type's cooldown alone. A failed
   post leaves the type's previous cooldown state as it was, so the next evaluation retries.
9. **What a fired notification carries (FR-70, FR-71).** `AlertFloorNotification` holds: slot
   identifier `"<alertType>|"` (patient name is always empty for the floor), alert identifier
   `"local-floor:<alertType>:<sensor timestamp in whole ms, rounded down>"`, type, severity
   (`urgent` for the two urgent types, `warning` otherwise), tier, the glucose value, the sensor
   timestamp, and the body. The body is exactly
   `"<headline> <value with unit> — computed on your phone from your last sensor reading.
   Threshold-only, no prediction. Not a replacement for your CGM app."` with headline from
   {"Urgent low glucose", "Low glucose", "High glucose", "Urgent high glucose"}, fallback
   "Glucose alert", the value from `GlucoseFormatter.stringWithLabel(_:in:)` in the unit passed
   to `evaluate`, and the dash U+2014. Pinned: a reading of 54 mg/dL at Unix 175 s →
   identifier `local-floor:low_urgent:175000`, body
   `"Urgent low glucose 54 mg/dL — computed on your phone …"`; the same in mmol/L uses the
   formatter's mmol/L string. No title is built here (FR-69 is 2.4).
10. **Threshold-only, read-only, and quiet in the logs (FR-71, SI-1, SI-9).** The engine has no
    trajectory, prediction horizon or IOB input, never produces `iob_warning` or `no_data`, and
    never sets a patient name. It imports nothing that can reach a Driver or a pump. Its log
    protocol takes only alert types and outcome cases: no glucose value, timestamp or threshold
    reaches a log line.
11. **Exercised against the Simulated Driver.** A DomainCore test runs a real `SimulatedDriver`
    on a manual clock and scheduler, reads its glucose port, and feeds every sample to the floor
    with `.configured` local thresholds chosen in the test so the trace crosses them, Backend
    `.notConfigured`, and a fake port that can post. The floor fires at least once, every fired
    notification's type matches the classifier for its sample, and no type fires twice inside
    the cooldown. The same run with `.notConfigured` thresholds fires nothing.
12. **Gates.** All nine frontmatter gates pass. The guard's self-test carries the new constant's
    duplicate and drift cases.

## Tasks / Subtasks

- [x] Task 1: the new constant (AC 8, 12)
  - [x] `SafetyConstants.alertFloorCooldown: TimeInterval = 1800`, doc comment citing Android
        `AlertFloor.kt:339` (`FLOOR_COOLDOWN_MS = 30 * 60_000L`) and the Backend's 30-minute
        dedup window it mirrors (FR-74).
  - [x] `scripts/guards/safety_guards.sh`: `CANON_SPEC="$CANON_SPEC;alert-floor cooldown
        (seconds):1800:1710:1890"`, a band-rationale paragraph in the style of the skew entry,
        and self-test cases `dup-alert-floor-cooldown|FAIL|…|let duplicateCooldown = 1800` and
        `drifted-alert-floor-cooldown|FAIL|…|let cooldownCopy = 1799`. Run `--self-test`.
  - [x] A value test in `Tests/SafetyCoreTests/SafetyConstantsTests.swift`.
- [x] Task 2: SafetyCore vocabulary and tier (AC 1, 2) — `Sources/SafetyCore/AlertVocabulary.swift`
  - [x] `AlertType`, `AlertSeverity` (open string structs with static members), `lowSet`,
        `highSet`, `AlertDeliveryTier { interrupting, informational }`,
        `AlertType.deliveryTier`, `AlertInterruptionLevel { critical, timeSensitive, active }`,
        `AlertDeliveryTier.interruptionLevel(criticalAlertsEnabled:)`.
- [x] Task 3: thresholds and classifier (AC 3, 4) — `Sources/SafetyCore/AlertThresholds.swift`
  - [x] `AlertThresholds` (throwing init, typed error `AlertThresholdsError.invalidOrdering`),
        `AlertThresholdProvenance`, `AlertThresholdSetting`.
  - [x] `AlertClassifier.classify(_ glucose: Glucose, against: AlertThresholds) -> AlertType?`.
- [x] Task 4: data trust and Backend evidence (AC 5, 6) — `Sources/SafetyCore/AlertDataTrust.swift`
  - [x] `WallClockHighWaterMark` (struct, `isRewound(at:)`, `mutating observe(_:)`).
  - [x] `AlertDataTrustResult { trusted, clockRewound, thresholdsNotConfigured, notFresh }`.
  - [x] `AlertDataTrust.evaluate(sensorTimestamp:thresholds:now:mark:freshness:)` with `mark`
        `inout` and `freshness` defaulting to `FreshnessPolicy.cgm`.
  - [x] `BackendAlertingStatus` and `isDegraded`.
- [x] Task 5: the engine (AC 7-10) — `Sources/DomainCore/AlertFloor.swift`,
      `Sources/DomainCore/AlertFloorNotification.swift`
  - [x] `AlertNotifying` protocol: `func canPostAlerts() async -> Bool` and
        `func post(_: AlertFloorNotification) async throws(AlertPostFailure)`.
  - [x] `AlertFloorNotification`, `AlertFloorContent` (headline, body, identifiers).
  - [x] `AlertFloor` actor: `init(notifier:clock:freshness:log:)`,
        `evaluate(_ reading: GlucoseReading, thresholds:backend:unit:) async -> AlertFloorOutcome`,
        `acknowledge(_ type: AlertType)`.
  - [x] `AlertFloorLogging` protocol plus an `OSLog` adapter (category `AlertFloor`), modelled on
        `Sources/AppFeature/HomeLog.swift`.
- [x] Task 6: tests
  - [x] `Tests/SafetyCoreTests/AlertVocabularyTests.swift` (AC 1, 2)
  - [x] `Tests/SafetyCoreTests/AlertThresholdsTests.swift` (AC 3, 4: ordering rejections at
        each edge, 19 and 501 rejected, the FR-71 table, rounding)
  - [x] `Tests/SafetyCoreTests/AlertDataTrustTests.swift` (AC 5, 6: each result, order —
        a rewound clock with unconfigured thresholds reports `.clockRewound`; the mark does
        not move on a rewound evaluation; FR-72 pinned pairs; the FR-71 Backend scenario)
  - [x] `Tests/DomainCoreTests/AlertFloorTests.swift` (AC 7-10: one test per gate, the
        cooldown and acknowledgement cases, the failed-post rollback, the content and
        identifier pins, no `iob_warning`/`no_data` ever produced)
  - [x] `Tests/DomainCoreTests/AlertFloorSimulatedDriverTests.swift` (AC 11). Add
        `"SimulatedDriver"` to the `DomainCoreTests` dependency list in `Package.swift`; no
        production target's dependencies change.
- [ ] Task 7: gates and the Dev Agent Record (AC 12): final reviewable diff size; any
      NEEDS-HUMAN lines.

## Dev Notes

### Known pitfalls (read before writing code)

- The worker cannot compile, so write carefully. A `switch` after any statement in a function or getter needs `return switch`. Test functions that `await` must be `async`. In Swift Testing, `#expect` over a key-path closure such as `allSatisfy(\.x)` is treated as throwing, so bind it to a `let` first. Typed-throws closures can't call `NSLock.withLock` and throw a typed error; use `lock()`/`defer unlock()`. In an init, assign every stored property before reading any `self` property. Swift does not allow `#if` inside an array literal; put the whole declaration under `#if`/`#else`.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs (UIKit, UserNotifications specifics, CoreBluetooth specifics, AccessorySetupKit) in `#if os(iOS)`, or put them behind protocols.
- Never write a numeric safety constant inline, and never disguise one. Literals equal to safety constants (for example 18, 20, 21, 55, 58, 61, 70, 180, 250) trip the guard. Hex colour parts count too.
- Swift 6 strict concurrency; actors are reentrant across `await`. Tests whose state settles asynchronously must wait with `eventually`.
- Objects held only weakly by system APIs (CoreBluetooth delegates, `UNUserNotificationCenter` delegates) must be retained explicitly. Release builds free them early.
- Code comments must not mention stories, epics, AC numbers, agents or cycles. No private API.
- The diff budget is about 800 reviewable lines.

Specific to this story:
- **The guard scans `Sources/` only.** Threshold values such as 55/70/180/250 belong in tests,
  never in `Sources/`. In `Sources/` the only numbers allowed are ones read from
  `SafetyConstants`. Do not add built-in default thresholds; 2.3 decides whether the Watch relay
  needs them.
- **`1800` has exactly one home**, `SafetyConstants.swift`. In tests use
  `SafetyConstants.alertFloorCooldown` (and `- 0.001`) rather than retyping it, so the test
  follows the constant.
- **Reentrancy in `AlertFloor`.** `evaluate` awaits the port twice (`canPostAlerts`, `post`).
  Read `clock.now` once at the top and use that value for every gate. Do the cooldown check
  and the cooldown stamp with **no `await` between them**, then post. If `post` throws, restore
  the type's previous last-fired and acknowledged state, but only if nothing changed them while
  the post was suspended. This is what stops two overlapping evaluations from both firing.
- **No `try!`, force unwrap, `precondition` or `fatalError` on the alerting path (NFR-14).**
  `AlertThresholds` throws a typed error; tests use `try #require`.
- SafetyCore stays dependency-free. `AlertFloor` lives in DomainCore (spine structural seed:
  "DomainCore … Alert Floor"; AD-23 makes DomainCore the acknowledgement owner).

### Rules of the road

- Swift 6 language mode, typed throws, `Sendable` value types across module boundaries (AD-4).
- Current time only from the injected `Clock` (AD-14). The guard rejects `Date()` and friends.
- **No therapeutic write, ever (SI-1).** The engine has no Driver or port dependency at all.
- **Do not edit** `Sources/DriverAPI/**`, `Sources/Drivers/**`, `Sources/Wire/**`,
  `Sources/Persistence/**`, `Sources/AppFeature/**`, `Apps/**`, CI workflows. The only
  `Package.swift` edit is the one test-target dependency in Task 6. If you find you need more,
  write a NEEDS-HUMAN line in the Dev Agent Record.
- Comments and commit messages state requirements in plain words. FR-x, SI-x and AD-x ids are
  fine.
- Scratch files only under `.build/`. One operation per Bash call.

### Every number in this story, and where it comes from

| What | Value | Source in code | Authority |
|---|---|---|---|
| Glucose validity bound (threshold bounds, `Glucose`) | 20...500 mg/dL, inclusive | `SafetyConstants.glucoseValidRange` | SI-2, FR-79 |
| Fresh window for alerting | Fresh while age < 360 s | `FreshnessPolicy.cgm` ← `SafetyConstants.cgmStaleAfter` | FR-49, FR-72; Android `Freshness.kt:111` |
| Forward-skew tolerance | 60 s | `AlertFloorEligibility.maxFutureSkew` ← `SafetyConstants.alertFloorMaxFutureSkew` | FR-72; Android `Freshness.kt:59` |
| Wall-clock rewind tolerance | the same 60 s, not a second number | `SafetyConstants.alertFloorMaxFutureSkew` | FR-72 ("same skew tolerance"); Android `AlertFloor.kt:117-118` |
| Re-alarm cooldown | 1800 s | **new** `SafetyConstants.alertFloorCooldown` + CANON_SPEC | FR-74; Android `AlertFloor.kt:339`; Backend 30-minute dedup |
| Alert Thresholds | whatever the user or Backend set; none ship | `AlertThresholdSetting` | FR-73, SI-5 |

Not in this story, and not to be added: the 300 s clock-suppression bound and the >60 s
forward-correction reset (FR-72, 2.3 — note that `300` already appears in Sources as
`SimulatedDriver.defaultTickInterval`, so 2.3 must resolve that collision before adding the
constant), the 120 s × 5 re-alarm ladder (FR-76, 2.6, marked ASSUMPTION in the PRD), the
200-entry suppression record (FR-70, 2.5), and the built-in 55/70/180/250 defaults (FR-73; for
the Watch relay's display state, Epic 3). `TargetRange.default` (55/70/180/250) is the hero's
colour band and is never an alert input (SI-3, FR-47).

### Where each piece lives, and why

- **SafetyCore:** vocabulary, tier, interruption-level resolution, thresholds, classifier, the
  data-trust bound and the Backend evidence. FR-65 requires the low and high sets to have one
  definition shared by the floor, delivery and the Watch relay; FR-72 requires the data-trust
  bound to live in a module the app and the Watch both link; AD-2 says SafetyCore owns every
  shape two units must agree on; AD-10 puts the Coverage Claim selector (2.9) there, and it will
  reuse `BackendAlertingStatus` and `WallClockHighWaterMark`.
- **DomainCore:** the stateful engine (cooldown, acknowledgement, the mark), the port, the
  notification content. The state is process-local in this story; FR-74's persistence to shared
  storage is 2.6.

### The engine, in code shape

```swift
public enum AlertFloorOutcome: Equatable, Sendable {
    case inRange
    case suppressed(AlertFloorSuppression)
    case fired(AlertFloorNotification)
}
public enum AlertFloorSuppression: Equatable, Sendable {
    case clockRewound, backendAlerting, dataTrust(AlertDataTrustResult)
    case cannotPost, coolingDown, postFailed
}
```

`evaluate` order (mirrors Android `AlertFloor.onCgmReading`, lines 193-306):
1. `now = clock.now`. If `mark.isRewound(at: now)` → `.suppressed(.clockRewound)`.
2. `mark.observe(now)`.
3. `type = thresholds.configured.flatMap { classify(reading.glucose, against: $0) }`. For every
   acknowledged type `t != type`: remove from acknowledged, clear last-fired.
4. `type == nil` → `.inRange`, or `.suppressed(.dataTrust(.thresholdsNotConfigured))` when the
   setting is `.notConfigured`.
5. `!backend.isDegraded` → `.suppressed(.backendAlerting)`.
6. `AlertDataTrust.evaluate(...)` (re-runs the rewind check, known false, and observes again —
   harmless because the mark is a monotonic max; this keeps one bound in one place, exactly as
   Android does) → not `.trusted` → `.suppressed(.dataTrust(result))`.
7. `await notifier.canPostAlerts()` false → `.suppressed(.cannotPost)`.
8. Cooldown check against `now`; if cooling → `.suppressed(.coolingDown)`. Else stamp
   last-fired = `now`, remove from acknowledged, remember the previous state.
9. `try await notifier.post(n)`; on failure roll back (see pitfalls) → `.suppressed(.postFailed)`;
   on success → `.fired(n)`.

Gate 8 of FR-71 (episode guard against Backend alert history, FR-75) slots in between steps 8
and 9 in 2.6. There is no Backend history in this build, so leaving it out cannot suppress an
alarm.

### Android reference (copied here; the Android repo may not be readable from your sandbox)

`android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/AlertFloor.kt`:
- `noteWallClock` / `isWallClockRewound` (lines 105-118): monotonic max; rewound iff
  `nowMs + ALERT_FLOOR_MAX_FUTURE_SKEW_MS < wallClockHighWaterMs`.
- `classify(mgDl: Int)` (lines 129-135): `<= urgentLow` → LOW_URGENT, `>= urgentHigh` →
  HIGH_URGENT, `<= lowWarning` → LOW_WARNING, `>= highWarning` → HIGH_WARNING, else null.
- `isReadingAlertable` (lines 156-165): rewound → false; note; not configured → false;
  `isFreshForAlertFloor(nowMs - reading.timestamp)`.
- `onFloorAlertAcknowledged` (lines 178-186): last-fired = now, add to acked.
- `onCgmReading` (lines 193-306): the order above. Cooldown is `nowMs - lastFiredAtMs <
  FLOOR_COOLDOWN_MS`, so exactly 30 minutes fires.
- `buildFloorAlertEntity` (lines 315-333): `serverId = "local-floor:" + "$alertType:${epochMs}"`;
  severity URGENT for LOW_URGENT/HIGH_URGENT else WARNING; the message string pinned in AC 9.
- **Deliberate difference:** Android logs `reading.glucoseMgDl` and `ageMs` (lines 245-303).
  iOS logs neither (SI-9, NFR-24).

`.../domain/alerting/AlertTypes.kt` carries the type and severity strings. The FR-71 headlines
are `floorHeadline` (lines 341-347).

### Existing code to build on (develop @ e09202b)

- `Sources/SafetyCore/AlertFloorEligibility.swift`: `isEligible(age:thresholds:)` already
  implements the forward-skew and strict-Fresh rule. Call it; do not reimplement it.
- `Sources/SafetyCore/FreshnessPolicy.swift`: `FreshnessPolicy.cgm`.
- `Sources/SafetyCore/GlucoseReading.swift`: `glucose`, `timestamp`, `age(asOf:)`.
- `Sources/SafetyCore/TargetRange.swift`: the validated-ordering initializer pattern and the
  rounding rule to copy (`rounded(.toNearestOrAwayFromZero)`).
- `Sources/SafetyCore/GlucoseFormatter.swift`: `GlucoseUnit`, `stringWithLabel(_:in:)`.
- `Sources/AppFeature/HomeLog.swift`: the logging-protocol-plus-OSLog pattern.
- `Tests/SimulatedDriverTests/TestDoubles.swift`: `ManualClock` and `ManualScheduler` to copy
  into DomainCoreTests (test targets cannot share fixtures).
- `Sources/Drivers/Simulated/SimulatedGenerator.swift`: the trace stays within 65...260 mg/dL,
  so test thresholds such as 80/100/150/200 (chosen in the test, not in Sources) guarantee
  crossings within a simulated day. With a short `tickInterval` the generator fast-forwards.
  Each sample's `recordedAt` is `clock.now` at emission, so it is Fresh when evaluated at once.

### Out of scope, and who owns it

| Not here | Owner |
|---|---|
| Below/above sensor range as an alert input, DriverAPI sample shape | 2.2b |
| 300 s suppression bound, forward-correction reset, continuous-clock second detector, `CLOCK_UNTRUSTED`, threshold reasons, upgrade migration of provenance, Watch relay calling the same bound | 2.3 |
| `UNUserNotificationCenter` adapter, `criticalAlertSetting` read, foreground presentation, title format, silent-switch copy, composing the floor into the app | 2.4 |
| Sounds per tier, slot replacement behaviour, 200-entry suppression record | 2.5 |
| Persisting cooldown/acknowledgement state, FR-75 Backend-history guard, re-alarm ladder | 2.6 |
| "Got It" action, acknowledgement handler order, offline reconciliation | 2.7 |
| Threshold editor and storage (what actually arms the floor in the app) | 2.8 |
| Coverage Claim, Not-Watching reasons, expiry, dead-man's switch | 2.9, 2.10 |
| Alert history, notification status card | 2.11 |
| Debug-compressed freshness policy, fault injection | 2.12 |
| Backend alert decoding (open-string decode, loud on missing field) | Epic 5 |
| Watch vocabulary type and its distinctness test | Epic 3 |

### Testing standards

- Swift Testing (`@Test`, `#expect`, `#require`), as in the existing suites.
- A fake `AlertNotifying` actor records calls and can be told to refuse `canPostAlerts` or
  throw from `post`.
- Gate-order tests set up the state that trips exactly one gate and assert both the outcome and
  that no later gate ran.
- Run `bash scripts/guards/safety_guards.sh` after every Sources edit.

### References

- epics.md, Epic 2, Story 2.2 (and 2.3-2.12 for the out-of-scope table)
- prd.md §5.4: FR-65, FR-66, FR-70, FR-71, FR-72, FR-73, FR-74, FR-79; §0.1 decision 4; §4 SI-1,
  SI-5, SI-9
- addendum.md §2.2 (Critical Alerts: `.timeSensitive` with runtime upgrade)
- ARCHITECTURE-SPINE.md AD-2, AD-4, AD-10, AD-13, AD-14, AD-20, AD-23
- prd sections/6-nfrs.md NFR-4 (decision functions in the shared module), NFR-8 (background work
  order ends in "evaluate the Alert Floor"), NFR-14 (no trap on alerting paths), NFR-24
- 1-7a-tandem-wire-decoding-for-recorded-frames.md, Review fixes, follow-up (b)

## Dev Agent Record

### Agent Model Used

GPT-6 Codex (Amelia)

### Debug Log References

- `swift build` and `swift test` were attempted as written. SwiftPM's nested `sandbox-exec` cannot start in this workspace (`sandbox_apply: Operation not permitted`). Both pass with `--disable-sandbox --skip-update` and module caches under `.build/`; the pinned GRDB checkout was copied into ignored `.build/` from a sibling worktree for offline resolution. The full macOS suite passed: 516 tests, 67 suites.
- `bash scripts/guards/safety_guards.sh`: passed. `--self-test`: passed, 77 cases and 2 documented bypasses, including the new duplicate and drift probes for the cooldown.
- `bash scripts/guards/driver_guards.sh`: passed. `--self-test`: passed, 69 cases and 3 documented limits.
- `bash scripts/ci-local.sh --self-test`: passed, all cases.
- `xcodebuild test -scheme GlycemicGPT-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd`: attempted, exit 66. CoreSimulatorService was unavailable in the sandbox; Xcode also reported that the directory contains no recognized project, workspace, or package for this invocation.
- `xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj -scheme GlycemicGPT -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd CODE_SIGNING_ALLOWED=NO`: attempted, exit 74. CoreSimulatorService was unavailable and Xcode's SwiftPM manifest cache under `~/Library/Caches` was unwritable.
- `git diff --check`: passed. The implementation adds about 772 reviewable lines across the declared surface.

### Completion Notes List

- Added open alert names, delivery tiers, threshold validation, inclusive classification, wall-clock high-water trust, and evidence-based Backend degradation in SafetyCore.
- Added the DomainCore floor with fixed gate order, process-local cooldown and acknowledgement, rollback after failed posts, a privacy-limited logger, and deterministic notification content.
- Added boundary, gate-order, concurrency, content, and Simulated Driver tests. The floor has no Driver or pump import and is not composed into the app.
- AC 1-11 are implemented and pass host-side tests. AC 12 remains open until the two simulator gates run in an environment with working CoreSimulator services.
- Safety regression tests added after the safety review (no production change; none exposed a bug, and each was mutation-checked against the code it pins): urgent low fires inside a low warning's cooldown with the high family's cooldowns untouched; an acknowledged urgent low re-arms on a low-warning reading, including when that reading is then stopped by a healthy Backend or by stale data; a failed post restores the acknowledgement; a reading suppressed as cooling down behind a suspended post that then fails alarms on the next reading (gated port); `networkReachable: false` and `streamConnected: false` degrade the Backend; the acknowledgement cooldown at `alertFloorCooldown - 0.001` s does not fire.
- **HARD PREREQUISITE before the floor is armed** (before Alert Thresholds become user-settable): the FR-72 forward-clock-correction reset (>60 s) and the 300 s suppression cap on the wall-clock high-water mark must land first (2.3). Without them, a forward clock jump followed by a correction leaves the mark in the future, every later evaluation reads as rewound, and the floor is silenced permanently.
- **Acknowledge-skew note:** `acknowledge` stamps the cooldown with `clock.now`, and a backward correction within the 60 s rewind tolerance is not flagged, so the effective cooldown after an acknowledgement can stretch to at most 1860 s (1800 + 60). Android behaves the same; accepted as parity.

### File List

- `Package.swift`
- `Sources/SafetyCore/SafetyConstants.swift`
- `Sources/SafetyCore/AlertVocabulary.swift`
- `Sources/SafetyCore/AlertThresholds.swift`
- `Sources/SafetyCore/AlertDataTrust.swift`
- `Sources/DomainCore/AlertFloor.swift`
- `Sources/DomainCore/AlertFloorNotification.swift`
- `Tests/SafetyCoreTests/SafetyConstantsTests.swift`
- `Tests/SafetyCoreTests/AlertVocabularyTests.swift`
- `Tests/SafetyCoreTests/AlertThresholdsTests.swift`
- `Tests/SafetyCoreTests/AlertDataTrustTests.swift`
- `Tests/DomainCoreTests/AlertFloorTests.swift`
- `Tests/DomainCoreTests/AlertFloorSimulatedDriverTests.swift`
- `scripts/guards/safety_guards.sh`

### PM decisions on drafting open points (2026-11-02)
- **Above the sensor range is `high_urgent`.** This is conservative: an above-range reading alarms. 2.2b implements it.
- **PRD wording:** the FR-69 title and FR-71 body will be amended for below and above range in the next docs sync. Implement against this story.
- **2.3 constant conflict:** 2.3 must not introduce a constant equal to 300 s (the Simulated Driver's tick interval) without resolving the guard collision. This is recorded for 2.3.
- **Known pitfalls** are in the Dev Notes. The Alert Floor is the most safety-critical code in the product. Cite FR, SI or AD for every rule. Never clamp and never default a threshold.
- budget: CONTINUATION_REQUIRED sha256:1d93e9c4306eb71a02d599a68e142971b13228fbb8b0307457137e7239b5aec7 cycle 1 2026-11-02T11:23:45Z
