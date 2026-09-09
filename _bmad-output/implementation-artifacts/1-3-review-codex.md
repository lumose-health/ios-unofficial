# Adversarial review: freshness tiers (cycle 1)

Reviewed the uncommitted `Sources/`, `Tests/`, and `scripts/` changes against
`origin/develop`, including all untracked files listed in the implementation record.

## Findings

### MINOR — The production scheduler leaves an immortal repeating task behind

`Scheduler` says each registration lasts for the lifetime of its owning object
(`Sources/SafetyCore/Scheduler.swift:16-18`), but `WallClockScheduler` discards the
unstructured `Task` handle (`Sources/SafetyCore/WallClockScheduler.swift:27-33`) and
the monitor captures itself weakly (`Sources/SafetyCore/FreshnessMonitor.swift:40-42`).
Destroying a monitor therefore prevents useful reevaluation but cannot stop its task;
each former monitor continues waking forever. The protocol needs a cancellation token
or another lifecycle mechanism, and the wall-clock loop must stop when the monitor or
registration ends.

Evidence/repro: repeatedly construct and release monitors with `WallClockScheduler`;
every call starts a `while !Task.isCancelled` loop, but no retained handle exists from
which any of those tasks can ever be cancelled.

### MINOR — The new ±5% guard bands do not support their stated drift rationale

The bands are `342...378` and `855...945`
(`scripts/guards/safety_guards.sh:211-212`). They catch the chosen 355/890 probes, but
those are only five- and ten-second changes, despite the comment and Dev Agent Record
calling them examples of an off-by-minute drift. Actual one-minute policy mistakes
such as 360→420 and 900→840 pass the classifier. Conversely, unrelated literals such
as `365` are rejected, contradicting the claim that the bands do not swallow ordinary
small integers. The header also still lists `let ceiling = 900` as an uncaught
outside-band example (`scripts/guards/safety_guards.sh:38`), although 900 is now an
exact canonical value and is caught. The exact-duplicate rule works; the heuristic's
coverage claim and tests need to be made honest, or its strategy needs revision.

Evidence/repro: direct `classify_numerics.awk` probes reported clean for 420 against
`360:342:378` and 840 against `900:855:945`, while reporting `365` as drift from 360.

### MINOR — The schedule-independence test does not prove ticks use the newest reading

`newReadingDoesNotRescheduleTimer` only checks that the registration count remains one
(`Tests/SafetyCoreTests/FreshnessMonitorTests.swift:100-118`). It never fires that
registration after replacing the reading. An implementation whose scheduled closure
continued classifying the first reading would satisfy the current decay test, immediate
update test, and registration-count test while violating the intended independent
schedule behavior. Add a test where the original reading is stale, a replacement is
fresh, then an existing tick fires and must leave the replacement fresh.

Evidence/repro: after installing a reading at t=0, install a replacement at t=100,
advance to t=400, call `tick()`, and assert Fresh (replacement age 300), not Stale
(original age 400); no current test exercises this distinction.

## Verified behavior

- Tier boundaries match Android `Freshness.kt:29-31,45-48`: 359/360 and 899/900 are
  pinned and implement the same half-open intervals.
- Negative display ages and alert-floor eligibility match Android
  `Freshness.kt:59,79-81`, including eligible at exactly -60s and ineligible below it.
- The quarter cadence and 2s/30s clamp match Android
  `AlertFloorStatusProvider.kt:64,135-136`.
- Actor isolation serializes `updateReading` and tick reevaluation; no unchecked
  production sendability or lost-update race was found.
- Exact 360/900 duplicates are caught across numeric spellings. Direct probes of
  `3.6e2` and `0x384` were rejected as second definitions. The new self-test cases do
  not pin those two spellings specifically, but the shared scanner coverage is real.
- The `SafetyConstants.swift` addition is necessary under the current guard design:
  `classify_numerics.awk:80-81` requires every `CANON_SPEC` literal to live in the one
  global `canonical_file`. Avoiding the frozen-file edit would require redesigning the
  guard's spec and classifier, not merely moving the literals.
- Badge cases, text literals, and semantic color tokens match the acceptance criteria.

## Gate evidence

- `swift build --disable-sandbox` — passed under Swift 6. The first plain invocation
  was blocked before compilation by this review sandbox's user-cache permissions.
- `swift test --disable-sandbox` — 59 tests in 11 suites passed.
- `bash scripts/guards/safety_guards.sh` — passed.
- `bash scripts/guards/safety_guards.sh --self-test` — 66 cases, 2 documented known
  bypasses, 0 unexpected results.
- `git diff --check origin/develop -- Sources Tests scripts` — passed.

VERDICT: CHANGES-REQUIRED — scheduler registrations cannot be terminated, and the guard/test evidence overstates the protection against threshold drift and schedule replacement.

## Cycle 2 re-review

### Findings

No findings.

### Verification

- Scheduler lifecycle is now terminable and race-free. `WallClockScheduler` retains
  the repeating `Task` in a registration whose `cancel()` delegates to the
  idempotent `Task.cancel()`, and the post-sleep cancellation check prevents a
  cancellation delivered during sleep from reaching the action. An action already
  in flight may finish, as documented, but it either holds the monitor strongly for
  the awaited actor call or observes the weak reference as nil; it cannot race the
  monitor's deinitialization or access released state.
- `RegistrationBox`'s `@unchecked Sendable` conformance is justified by its shape:
  its sole mutable field is read and written under the same `NSLock`, and the lock is
  released before invoking the registration. The apparent cancel-before-set lost
  cancellation cannot occur in this use: `set` completes synchronously inside the
  nonthrowing initializer before the initialized actor can deinitialize, and neither
  `scheduleRepeating` nor the remaining initialization path throws. Repeated cancel
  is safe under the `SchedulerRegistration` contract and for the production `Task`.
  A directly stored actor-isolated registration would reintroduce the Swift 6
  escaping-initializer restriction the box exists to solve; this is a reasonable
  safe shape for the deployment constraints.
- Guard coverage is now stated accurately. The configured bands remain
  `342...378` and `855...945`; comments and the Dev Agent Record describe them as
  catching nearby hand edits, explicitly disclose that 420/840 escape and that 365
  is a false positive, and the stale `ceiling = 900` header example is gone. Direct
  classifier probes rejected 355, 890, and 365 while allowing 420 and 840, matching
  the new self-test cases and prose.
- `tickUsesLatestReadingNotTheOriginal` registers once, installs the t=0 reading,
  replaces it at t=100 without registering again, advances to t=400, and fires the
  sole existing registration. It asserts Fresh for replacement age 300; a closure
  retaining the original reading would classify age 400 as Stale and fail. The
  existing tick-only decay test separately rules out a nonfunctional/no-op tick as
  the reason the state remains Fresh.
- `swift build --disable-sandbox` and `swift test --disable-sandbox` passed with
  compiler caches redirected under `.build`; 62 tests in 12 suites passed.
- `bash scripts/guards/safety_guards.sh` passed.
- `bash scripts/guards/safety_guards.sh --self-test` passed: 69 cases, 2 documented
  known bypasses, 0 unexpected results.
- `git diff --check origin/develop -- Sources Tests scripts` passed.

VERDICT: APPROVED — all three cycle-2 findings are resolved without introducing a cancellation race, an overstated guard claim, or a schedule-replacement coverage gap.
