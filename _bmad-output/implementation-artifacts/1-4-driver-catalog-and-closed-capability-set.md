---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
route: {provider: claude, cli: claude, model: opus, effort: high, agent: dev, fallback: [openai/gpt-5.6-sol]}
local_gpu: red
gates:
  - "swift build"
  - "swift test"
  - "bash scripts/guards/safety_guards.sh"
  - "bash scripts/guards/driver_guards.sh"
max_cycles: 4
---

# Story 1.4: The Driver Catalog and the closed Capability set

Status: done

<!-- Route rationale (for the maintainer): cross-cutting API design — the capability protocols,
lifecycle state machine and failure taxonomy every Driver (1.5, 1.7, Tandem, Medtronic)
will implement. Blast radius is the contract itself, so strong tier: opus/high.
Downgrade trigger: none; upgrade to fable only if a cycle fails on architectural
misjudgment rather than mechanics. NOT a protected path (no dosing/alert-floor logic,
no data migration; structural read-only scaffolding + guards) — PM merge authority
applies if all conditions hold. -->

## Story

As a Builder,
I want every Driver in my build listed explicitly with what it provides,
So that nothing can be loaded at runtime and nothing can go missing silently.

## Acceptance Criteria

1. A new SPM target `DriverAPI` exists under `Sources/DriverAPI/`, depending on
   `SafetyCore` and NOTHING else (Foundation only otherwise). The existing
   manifest test suite is extended: `DriverAPI`'s dependency list is exactly
   `[SafetyCore]`, and `SafetyCore` still has zero dependencies (AD-3).
2. The Capability set is EXACTLY six and closed — glucose source, insulin source,
   pump status, BGM source, data sync, bolus-category provider — expressed as six
   protocols in `DriverAPI`, with NO calibration member anywhere (FR-30, SI-1).
   A test pins the count at six and the absence of any calibration requirement.
3. No protocol in `DriverAPI` declares a write, command or set member toward a
   pump: the read-only posture is structural — there is nothing for a Driver to
   call (FR-31, AD-12, SI-1). Capability members are `get`-only properties,
   `AsyncSequence`/`AsyncStream` emissions, or side-effect-free queries.
4. The Driver lifecycle is declared ONCE in `DriverAPI` (AD-16): a state
   enum + a transition surface owned by the platform. A Driver never
   self-transitions; the protocol shape makes that structural (Drivers expose
   entry points the platform calls; they do not mutate lifecycle state). States
   must cover: not activated, activating, active, degraded, deactivating,
   failed — with teardown idempotence expressed in the contract's doc comments.
5. The Driver failure taxonomy is declared once in `DriverAPI` (AD-13 note in
   spine §141): a single error enum whose cases any consumer can branch on.
6. `DriverCatalog` is the sole registration path: a compile-time list of
   `DriverDescriptor` entries (name, protocol/transport, version, provided
   capability set, verification status vocabulary per FR-22). No runtime
   loading surface exists. With no shipped Drivers yet (Simulated arrives with
   its own work), the catalog compiles EMPTY — the mechanism ships now, the
   entries arrive with each Driver.
7. `SafetyLimits` lives in `DriverAPI`: validation passes read limits fresh
   every time (no caching member), and limits may only NARROW the absolute
   20-500 bound from `SafetyCore`, never widen it — the narrowing-only rule is
   enforced by the type (throwing init rejects bounds outside the absolute
   range) and pinned by tests (FR-32, SI-11).
8. The Drivers screen is MODELED, not rendered (no UI target exists until 1.13,
   same deferral the freshness badge used): a presentation row type carrying
   name, protocol, version, active state, and Verification Status for every
   catalog entry, with a test pinning the mapping from `DriverDescriptor`.
9. A new guard `scripts/guards/driver_guards.sh` (same conventions as
   `safety_guards.sh`: stock bash 3.2 + awk/sed/grep/find, `--help`,
   `--self-test`) enforces mechanically, today, what the future CI gate will
   also run (FR-21's "iOS Gate" arrives with the CI work; the guard is the
   local truth now):
   a. CATALOG COMPLETENESS: every target under `Sources/Drivers/` in
      `Package.swift` has a corresponding catalog entry (scan source for the
      descriptor registration). With zero driver targets it passes vacuously,
      and `--self-test` proves the failure mode by injecting a fake driver
      target + missing entry into a scratch tree.
   b. SYMBOL SCAN: no delivery verb or pump-write characteristic identifier in
      `DriverAPI` or any `Drivers/*` target — seed the deny-list with at least:
      bolus, deliver, setBasal, tempBasal, suspend, resume, prime, cannula
      (case-insensitive word-boundary matches in code, strings elided the way
      safety_guards.sh does). `--self-test` injects violations and asserts
      each is caught, with pass-through controls (e.g. "bolus" inside an
      elided string or a comment about the bolus-category READ capability must
      NOT trip it — the bolus-category capability name itself is legal as the
      read-side vocabulary; pick protocol member names so the deny-list and
      the legal read surface cannot collide, and document the choice).
10. All four gates green, including both guards' `--self-test`.

## Tasks / Subtasks

- [x] Task 1: `DriverAPI` target + manifest test extension (AC: 1)
- [x] Task 2: six capability protocols, read-only structural posture + count/no-calibration tests (AC: 2, 3)
- [x] Task 3: lifecycle state machine + failure taxonomy, platform-owned transitions (AC: 4, 5)
- [x] Task 4: `DriverDescriptor` + `DriverCatalog` (empty, compile-time) + verification-status vocabulary (AC: 6)
- [x] Task 5: `SafetyLimits` narrowing-only type + tests (AC: 7)
- [x] Task 6: Drivers-screen presentation row model + mapping test (AC: 8)
- [x] Task 7: `scripts/guards/driver_guards.sh` + `--self-test` (AC: 9)

## Dev Notes

### Builds on (frozen — do not modify existing production files except where an AC requires it)

`SafetyCore` (constants, `Glucose`, freshness, clock) is frozen; `DriverAPI`
references its types (absolute glucose bounds for `SafetyLimits`). Modifying
`SafetyConstants.swift` is NOT expected this story — `SafetyLimits` consumes
the existing absolute bounds, it does not add canonical constants. If additive
necessity emerges anyway, flag it in the Dev Agent Record with the reasoning.
`safety_guards.sh` should not need changes; `driver_guards.sh` is a SEPARATE
script so the two concerns stay independently testable.

### Architecture ground truth (read the spine sections before coding)

_bmad-output/ARCHITECTURE-SPINE.md (mirrored into this worktree)
— AD-2 (contract types live in SafetyCore only when TWO units must agree;
capability ports live in DriverAPI), AD-3 (dependency direction), AD-12 (no
therapeutic write exists to call; closed set of six), AD-16 (one lifecycle,
platform-owned), AD-17 (subtractive composition — nothing here may condition on
build configuration), Structural Seed (target layout), §141 (failure taxonomy).

### Android ground truth (read-only, for vocabulary parity only)

android-unofficial — the plugin/driver API
surface (search for the capability/driver registration surface). Mirror
CONCEPTS and naming vocabulary where they translate; do NOT mirror Android's
runtime-loading mechanics — iOS composition is compile-time by design (AD-12).

### Constraints

- Swift 6 strict concurrency, zero new dependencies anywhere.
- `DriverAPI` is pure contract: protocols, enums, value types, doc comments.
  No implementations beyond trivial value-type logic (SafetyLimits validation,
  catalog lookup). Anything that smells like orchestration belongs to
  DomainCore (later story) — leave it out.
- Worktree sandbox: `.claude/settings.local.json` grants Android read access +
  swift/bash allowlist; publish commands denied during implementation. Never
  commit `.claude/` or `_bmad-output/`. Scratch under `.build/`, not `/tmp`.
- Naming: pick capability protocol names that read as sources/providers
  (GlucoseSource, InsulinSource, PumpStatusSource, BGMSource, DataSync,
  BolusCategoryProvider or justified equivalents) — and record the final six
  in the Dev Agent Record.

### Testing standards summary

Swift Testing per the existing `Tests/SafetyCoreTests/` conventions, new suite
dir `Tests/DriverAPITests/`. Manifest assertions extend the existing
package-manifest test approach. Guard self-tests follow the safety_guards.sh
scratch-tree injection pattern.

### Project structure notes

Surface: `Package.swift` (new target wiring), `Sources/DriverAPI/*`,
`Tests/DriverAPITests/*`, `scripts/guards/driver_guards.sh` (+ lib if needed).
Branch from `develop` at or after 7ab9faa. PR targets `develop`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.4 (FR-21, FR-22, FR-30, FR-31, FR-32, SI-1, SI-11)]
- [Source: ARCHITECTURE-SPINE.md#AD-3, #AD-12, #AD-16, #AD-17, #Structural-Seed]
- [Source: _bmad-output/implementation-artifacts/1-2-*.md and 1-3-*.md Dev Agent Records — guard architecture + deferral precedents]

## Dev Agent Record

### Agent Model Used

claude-opus-5, effort high, dev persona (route as stamped). Cycles 1–4 of 4.
Local-GPU pre-assessment: RED — no delegate.sh on this host, and this is the
contract every Driver implements.

### Debug Log References

Gates, all run from the worktree root after a `rm -rf .build` clean rebuild.
Cycle-2 numbers:

| Gate | Result |
| --- | --- |
| `swift build` | Build complete, 0 warnings |
| `swift test` | 138 tests in 20 suites passed |
| `bash scripts/guards/safety_guards.sh` | clean |
| `bash scripts/guards/safety_guards.sh --self-test` | 72 cases, 2 documented bypasses, 0 unexpected |
| `bash scripts/guards/driver_guards.sh` | clean |
| `bash scripts/guards/driver_guards.sh --self-test` | 42 cases, 0 unexpected |

No changes were needed to `SafetyConstants.swift` or `safety_guards.sh`.
`SafetyLimits` consumes `SafetyConstants.glucoseValidRange` by reference and
never re-spells its numbers, so the single-definition-site rule holds unchanged
(safety_guards still reports the bound defined exactly once).

### Completion Notes List

**The final six Capabilities** (AC 2, and the naming the Dev Notes asked to be
recorded). Protocol / `Capability` case / Android counterpart:

| Protocol | Case | Android |
| --- | --- | --- |
| `GlucoseSource` | `.glucoseSource` | `GlucoseSource` |
| `InsulinSource` | `.insulinSource` | `InsulinSource` |
| `PumpStatusSource` | `.pumpStatus` | `PumpStatus` |
| `BGMSource` | `.bgmSource` | `BgmSource` |
| `DataSync` | `.dataSync` | `DATA_SYNC` (capability only, no interface) |
| `DoseCategoryProvider` | `.doseCategoryProvider` | `BolusCategoryProvider` |

Android's seventh, `CALIBRATION_TARGET`, is deliberately absent. It is the only
capability in that set whose direction is inward-to-outward, so it is the one
whose presence would make a therapeutic write look ordinary.

**The one rename, and why it is load-bearing rather than cosmetic (AC 9b).**
AC 9b requires the deny-list to include `bolus` and requires the legal read-side
surface not to collide with it. A plain `\b`-style word search cannot collide —
but it also cannot see `deliverBolus()`, which is how the write would actually be
spelled, so it would be a decorative guard. The scan therefore SPLITS
identifiers into words (camel humps, underscores, digits) and matches the
deny-list against the word sequence, which does catch `deliverBolus`,
`setBasalRate` and `set_basal`. That makes the collision real: `BolusCategoryProvider`
splits to `bolus category provider`.

Two ways out. An exemption list of legal identifiers was rejected — it is a place
a write surface can later be added by appending a line, and `safety_guards.sh`
already takes the position that a guard with an escape hatch stops being a guard
the first time someone is in a hurry. So the capability is named
`DoseCategoryProvider` instead, the parity with Android is recorded in its doc
comment and on `Capability.doseCategoryProvider`, and the guard carries no
per-symbol exemption at all. The choice is exercised by two self-test controls:
a comment naming Android's `BolusCategoryProvider` and the
`DoseCategoryProvider` identifier itself both pass, while a bare `bolus` and
`startBolus` fail.

**Known future friction, recorded in the guard header rather than left to be
discovered.** `suspend` and `resume` are denied words, and a Driver bridging
Core Bluetooth delegate callbacks into async/await will want
`continuation.resume(...)`. That will trip the guard, and it should — the PR that
introduces it decides, in review, whether to narrow the terms to their
therapeutic shapes (`resume delivery`) or restructure the bridge. What must not
happen is a silent exemption.

**Structural choices worth a reviewer's attention:**

- `Driver` is an `Actor` protocol (AD-4) declaring only `descriptor`,
  `capability(_:)`, `activate()` and `deactivate()`. It names no lifecycle
  member. `DriverLifecycle` — the only thing that can move a state — is a value
  the platform holds and a Driver is never handed, so "a Driver never
  self-transitions" is structural, not a rule to remember. A test asserts the
  stripped source of `Driver.swift` does not mention `DriverLifecycle` at all.
- `deactivate()` does not throw. Teardown that can fail is teardown a caller has
  to retry, and a caller that gets it wrong leaks a live Bluetooth link across a
  restoration cycle. Idempotence is in the doc comment AND in the transition
  table (`notActivated → notActivated`, `deactivating → deactivating`), with a
  test asserting the table permits what the doc promises.
- `DataSync` carries no `sync()`. Mirroring is the one capability whose data
  flows outward, so it is the one where a command member would look reasonable;
  the port declares a destination and reports state, and the trigger stays with
  the platform's lifecycle. Reasoning is in the file.
- `SafetyLimits` has a throwing init and no clamping factory. Android's
  `safeOf` clamps out-of-range configuration; a clamped safety bound is a bound
  the user did not configure being applied as though they had.
- Two `Error` types would weaken "declared once", so `SafetyLimitRejection` is a
  payload on `DriverFailure.safetyLimitRejected(_:)`, not an error type. A test
  scans the target and asserts exactly one `Error`-conforming type exists.
- Rule A3 in the guard (a directory under `Sources/Drivers/` that no target
  declares) is beyond the AC. It cost one loop and closes the third way the
  manifest, the catalog and the tree can disagree — and it is what catches a
  sabotaged manifest reader that goes quiet, which is a self-test case.

**On the source-scanning tests.** Several assertions are about what the source
does NOT contain, which can only be checked by reading it. They run over stripped
code (comments removed, string contents elided), because the doc comments
explaining why calibration is absent say "calibration" repeatedly. The stripper
lives in `Tests/DriverAPITests/DriverAPISource.swift` and has its own suite
asserting both directions, including that each absence-scan can still report a
presence — an absence assertion over an over-eager stripper is an assertion that
always passes.

**Deferred, as the story allows:** no UI target, so the Drivers screen is the
`DriverRow` model plus its mapping test; no shipped Drivers, so `DriverCatalog`
compiles empty and both completeness rules pass vacuously — proven non-vacuous
by the self-test's injected fake target.

### File List

Added:

- `Sources/DriverAPI/Capability.swift`
- `Sources/DriverAPI/Capabilities/GlucoseSource.swift`
- `Sources/DriverAPI/Capabilities/InsulinSource.swift`
- `Sources/DriverAPI/Capabilities/PumpStatusSource.swift`
- `Sources/DriverAPI/Capabilities/BGMSource.swift`
- `Sources/DriverAPI/Capabilities/DataSync.swift`
- `Sources/DriverAPI/Capabilities/DoseCategoryProvider.swift`
- `Sources/DriverAPI/Driver.swift`
- `Sources/DriverAPI/DriverLifecycle.swift`
- `Sources/DriverAPI/DriverFailure.swift`
- `Sources/DriverAPI/DriverDescriptor.swift`
- `Sources/DriverAPI/DriverCatalog.swift`
- `Sources/DriverAPI/SafetyLimits.swift`
- `Sources/DriverAPI/SafetyLimitsValidator.swift` (cycle 3)
- `Sources/DriverAPI/Models/GlucoseSample.swift`
- `Sources/DriverAPI/Models/InsulinModels.swift`
- `Sources/DriverAPI/Models/PumpStatusSnapshot.swift`
- `Sources/DriverAPI/Models/SyncModels.swift`
- `Sources/DriverAPI/Presentation/DriverRow.swift`
- `Tests/DriverAPITests/DriverAPISource.swift`
- `Tests/DriverAPITests/DriverAPISourceTests.swift`
- `Tests/DriverAPITests/CapabilityStubs.swift`
- `Tests/DriverAPITests/CapabilitySetTests.swift`
- `Tests/DriverAPITests/ReadOnlyPostureTests.swift`
- `Tests/DriverAPITests/DriverLifecycleTests.swift`
- `Tests/DriverAPITests/DriverFailureTests.swift`
- `Tests/DriverAPITests/DriverCatalogTests.swift`
- `Tests/DriverAPITests/SafetyLimitsTests.swift`
- `Tests/DriverAPITests/DriverRowTests.swift`
- `scripts/guards/driver_guards.sh`
- `scripts/guards/lib/manifest_driver_targets.awk`
- `scripts/guards/lib/catalog_entries.awk`
- `scripts/guards/lib/declared_types.awk` (cycle 3)
- `scripts/guards/lib/consumer_casts.awk` (cycle 3)

Modified:

- `Package.swift` — `DriverAPI` target and test target, `DriverAPI` product,
  header comment updated.
- `Tests/SafetyCoreTests/PackageManifestTests.swift` — added the DriverAPI
  dependency assertion; `onlySafetyCoreIsScaffolded` became
  `onlyDeclaredTargetsAreScaffolded` and now expects `["DriverAPI", "SafetyCore"]`.

## Cycle 2 — Dev Agent Record

### What the review was right about

Every cycle-1 invariant that mattered was a convention that well-formatted code
happened to satisfy. Each fix below is checked the way the review asked: the
counterexample either fails to compile or fails a gate, and I ran each one rather
than reasoning about it.

**1. The Capability surface is closed by a type, not by a marker.**
`DriverCapability` is gone. There is no protocol for a Driver target to conform a
seventh capability to, and ``Driver/capability(_:)`` now returns `CapabilityPort`
— a six-case enum whose payloads are the six concrete port protocols. There is
nothing to downcast because there is no erased supertype: the platform receives a
`.glucoseSource(any GlucoseSource)`, not an `any Marker` it can narrow.

A seventh case cannot be added without breaking the exhaustive
`CapabilityPort.capability` switch in `DriverAPI`, and the test suite switches
exhaustively over both enums, so a seventh case does not compile past the tests
either. Verified: an isolated `Sources/Drivers/Probe` target declaring
`protocol ExtraCapability: DriverCapability` failed with *cannot find type
'DriverCapability' in scope*.

The six port protocols now refine `Sendable` directly, and the port→case mapping
that used to live on `static var capability` lives on `CapabilityPort`. The
`exactlySixPortsAreDeclared` test was widened accordingly: it enumerates EVERY
protocol declared in the target and pins the set to the six ports plus the two
known non-ports (`Driver`, `SafetyLimitsSource`), so a seventh port hidden in an
unlikely file fails the same assertion.

What this does not close, stated plainly: a Driver's concrete type can carry
extra methods, and a composition root that imports that Driver target can call
them with an `as?`. No API shape prevents that. What DriverAPI can promise is
that it declares no write, so there is nothing to call through the contract, and
the symbol scan covers the Driver targets themselves.

**2. Registration means membership in `DriverCatalog.entries`.**
`lib/catalog_entries.awk` now walks the `entries` array literal and counts only
`targetName` occurrences inside its brackets. A `static let FakeEntry =
DriverDescriptor(…)` beside the array — the cycle-1 bypass, and the shape
cycle-1's own positive self-test case used — is no longer a registration. An
`entries` array the scan cannot read is an error rather than an empty answer,
because "no Drivers registered" and "the catalog could not be read" must not look
alike.

Three new self-test cases: `descriptor-outside-the-entries-array` (FAIL),
`two-drivers-both-registered` (PASS — the insertion path has to keep working once
the array is non-empty, or every positive case would only be testing a
one-element array), and `unreadable-entries-array` (FAIL). The self-test's
registration helper now writes into the array, so the positive cases assert real
membership.

`DriverCatalogTests.everyDriverInTheTreeIsRegistered` resolves the same question
by being the program instead of reading it: `DriverCatalog.entries` is the array,
compared against the directories under `Sources/Drivers/`. It is vacuous while no
Driver has shipped and stops being vacuous the moment one does.

**3. Lifecycle mutation is unreachable from a Driver target.**
`DriverLifecycle` is `@_spi(DriverPlatform)`. An ordinary `import DriverAPI` —
what a Driver writes — cannot see the type at all, so the reviewer's
self-transitioning Driver does not compile: verified, *cannot find
'DriverLifecycle' in scope*. Swift has no friend modules; SPI is the nearest
thing, and it makes the capability something a file asks for by name.

The way around it is to write the SPI import into a Driver, so `driver_guards.sh`
gained rule C: any `@_spi` import under `Sources/Drivers/` fails the gate.
Verified both ways — a probe Driver with `@_spi(DriverPlatform) import DriverAPI`
compiles and the guard fails it; a plain `import DriverAPI` passes. Four self-test
cases, including one that a plain import must not trip and one that DriverAPI's
own use of the attribute must not trip.

`DriverLifecycleState` stays public: it is inert data, and `DriverRow` renders it.

**4. The source scans read declarations, not lines.**
`DriverAPISource.declarations()` collapses each stripped file to a token stream
and reads `protocol`/`enum`/`struct`/`class`/`actor`/`extension` declarations with
their inheritance clauses, wherever the line breaks fall. Both cycle-1 blind spots
are now caught, and I confirmed it by adding the reviewer's counterexamples to
`Sources/DriverAPI/` and watching the suite fail: the line-wrapped `ExtraSource`
tripped `exactlySixPortsAreDeclared`, and the line-wrapped `OtherFailure: Error`
tripped `exactlyOneErrorType` (`declared.count → 2`). The scan also sees
`extension X: Error`, which no keyword-only scan would have seen at all. Both
tests carry a case that feeds the counterexample text to the scanner directly, so
the scanner cannot go quiet without a test saying so.

**5. Fresh limits are the only reachable limits.**
`SafetyLimits.validate(mgdl:)` and `SafetyLimits.absolute` are both internal now.
The public door is `SafetyLimitsSource`, a protocol with one requirement —
`currentLimits` — and a `validate(mgdl:)` extension that reads it on every call.
A Driver holding a `SafetyLimits` cannot validate against it: verified, *'validate'
is inaccessible due to 'internal' protection level*, and `SafetyLimits.absolute`
likewise. The intended shape still compiles from an isolated Driver target —
`let limits: any SafetyLimitsSource` and `limits.validate(mgdl:)` — which I also
checked, because an invariant that makes the legitimate use impossible is a
different bug.

`validationReadsLimitsFresh` now holds ONE receiver, changes what its source
reports, and validates the same number again: admitted, then refused after the
narrowing, then admitted again after widening. No reconstruction anywhere.

The gap the type system cannot close: a conforming type may capture its limits at
initialisation. That is visible in the conforming type instead of spread across
every call site, and it is stated in the protocol's doc comment.

**6. One re-entrancy story, told by the docs, the table and the tests.**
The table is the contract, and the docs now describe the table rather than
something adjacent to it: `activate()` runs once per entry into `.activating`,
which is permitted only from `.notActivated` and `.failed`, so a running Driver is
never re-activated and `activate()` never has to defend against a concurrent
second platform call. What it must survive is REPETITION across the life of one
instance — after a teardown, and after a failure.

`entryPointsAreRepeatable` (which called `activate()` twice from `.activating`, a
sequence the platform cannot produce) is replaced by three tests that walk the
table as defined: `activationRepeatsAcrossTeardown`,
`aRunningDriverIsNotReactivated` (which also pins that `.activating` is reachable
from exactly the two states the doc comment names), and `teardownRepeats`.

**7. Nothing verified was regressed.** The manifest assertions are untouched and
green, `SafetyConstants.swift` and `safety_guards.sh` are still unmodified, and
there is still no `#if` or build-configuration branch anywhere in `Sources/`
(AD-17). `SafetyLimits` still consumes `SafetyConstants.glucoseValidRange` by
reference and never re-spells its numbers.

### Cycle 2 file list

Added:

- `Sources/DriverAPI/SafetyLimitsSource.swift`

Modified:

- `Sources/DriverAPI/Capability.swift` — `DriverCapability` removed, `CapabilityPort` added
- `Sources/DriverAPI/Capabilities/*.swift` (all six) — refine `Sendable`; the
  `static var capability` extensions removed
- `Sources/DriverAPI/Driver.swift` — `capability(_:) -> CapabilityPort?`; the
  re-entrancy contract restated in the transition table's terms
- `Sources/DriverAPI/DriverLifecycle.swift` — `DriverLifecycle` is SPI
- `Sources/DriverAPI/SafetyLimits.swift` — `validate(mgdl:)` and `absolute` internal
- `Tests/DriverAPITests/DriverAPISource.swift` — token-stream declaration scanner
- `Tests/DriverAPITests/CapabilitySetTests.swift`, `DriverFailureTests.swift`,
  `DriverLifecycleTests.swift`, `SafetyLimitsTests.swift`,
  `DriverCatalogTests.swift`, `CapabilityStubs.swift` — per the findings above
- `scripts/guards/driver_guards.sh` — rule C (platform SPI), real registration in
  the self-test helper, seven new cases
- `scripts/guards/lib/catalog_entries.awk` — resolves membership in `entries`

## Cycle 2 — REQUIRED CHANGES from adversarial review

Read _bmad-output/implementation-artifacts/1-4-review-codex.md in full. Seven MAJOR
findings, each demonstrated with a compiling counterexample. The theme: the
invariants must be STRUCTURAL (unrepresentable in the type system or caught by a
robust scan), not conventions that well-formatted code happens to satisfy. Fix all:

1. Close the capability surface: no public marker protocol a Driver target can
   conform new types to, and no `any`-existential accessor whose result can be
   downcast into an escape hatch. Options include a frozen enum of capability
   witnesses, sealed protocol pattern (public protocol + non-public requirement),
   or capability accessors typed to the six concrete protocols only. A seventh
   capability declared in a Driver target must fail to COMPILE or fail a gate.
2. Catalog registration must be membership in `DriverCatalog.entries` itself:
   the guard must resolve actual entries (or the test must), not any
   `targetName:`-shaped line in the file. Kill the disconnected-descriptor
   bypass; self-test must include it as a caught case.
3. Lifecycle mutation must be inaccessible to Driver code: no public init or
   `advance(to:)` a Driver target can reach. Platform-side transition surface
   can live behind a non-public type, or transitions restricted via an
   access-controlled token the platform owns. The reviewer's self-transitioning
   Driver must become impossible or gate-caught.
4. Make the count/taxonomy source scans formatting-robust (multi-line
   declarations, conformance on following lines) — or replace source-text scans
   with compile-level assertions where possible. The reviewer's line-wrapped
   seventh protocol and second error enum must be caught.
5. Fresh limits: remove the cacheable public static, or restructure so
   validation pulls from a limits provider at call time; the test must prove a
   change in the provider's current limits is observed by the next validation
   without constructing a new receiver.
6. Reconcile the re-entrancy contract: doc comments, state transition table, and
   `entryPointsAreRepeatable` must tell one coherent story (activate() during
   .activating/.active — define exactly what happens and test it as defined).
7. Keep all existing verified behavior intact (manifest assertions and AD-17
   posture were confirmed — do not regress them). All four gates plus BOTH
   self-tests green. Update the Dev Agent Record per finding with what changed.

## Cycle 3 — Dev Agent Record

Both remaining MAJORs are of the form "a conformer can misbehave behind an
existential", which Swift cannot close at the type level. Each is answered the way
the cycle-3 brief specifies, and each is verified by an isolated `Probe` Driver
target built against the real `DriverAPI` — the same method the reviewer used, so
the claims below are compile/gate results rather than reasoning. Findings 2, 3, 4,
6 and 7 were not touched.

### Finding 1 — the downcast seam on `CapabilityPort`

**(a) `driver_guards.sh` rule D, consumer-side casts.** Everything under
`Sources/` except `Sources/DriverAPI/` is scanned for `as?`, `as!` and `is`
against a Capability port name, `Driver`, `CapabilityPort`, or any type a Driver
target declares. `DriverAPI` is excluded because it is where those types are
DECLARED; a rule that fired there would be a rule against declaring them.

The name lists are READ from the tree (`lib/declared_types.awk`), not typed into
the guard, so a renamed port or a new Driver type is covered the day it lands.
That reader going quiet would leave the rule scanning for nothing and reporting
green, so the port count is asserted at six — the closed set — and a scan that
reads any other number exits 2 rather than passing. `port-name-reader-goes-quiet`
sabotages the reader and pins that.

Matching (`lib/consumer_casts.awk`) reads a whole-file token stream over stripped
source, so a cast wrapped across lines is seen the same as one on a line, and
`any`/`some` between the operator and the type does not hide it. `?` and `!` are
kept as part of tokens, which is what keeps `is` a WORD — `isDriverActive`
tokenizes as one identifier, and that false positive would have made the rule
unusable, so it is a control.

Verified with the reviewer's counterexample, built for real:

| Probe | compile | guard |
| --- | --- | --- |
| `ExtraPort: DoseCategoryProvider` + `port as? ExtraPort` + `smuggled.performStepTwo()` | OK | **FAIL** |
| the same target with the downcast removed | OK | pass |

The control matters as much as the catch: without it the case would only be
showing that the guard dislikes new Driver targets.

**(b) deny-list extended** with `therapy`, `enact`, `administer`, `infuse`,
`inject` — the vocabulary a smuggled member is actually written in, none of which
contains a delivery verb. Collision checked before adding: those words appear in
`DriverAPI` only inside comments, which are elided, and `DoseCategoryProvider`
splits to `dose category provider`. Two controls pin the near misses that would
break the codebase if they fired — `injectedClock` (dependency injection is the
ordinary meaning of the word in Swift) and `therapeuticRange` (a therapeutic range
is a read). Five violation cases, one per new word.

**(c) the residual, stated and made executable.** An arbitrary-named extra member
on a concrete Driver port type — `func performStepTwo()` — is invisible to a text
scan: there is no vocabulary to match and no shape separating it from a helper. It
is unreachable from another target without the downcast (a) forbids, so what it
can do is bounded by what its own target can already do. That is written in the
guard header under THE SEAM THIS CLOSES, and pinned as
`known-limit-arbitrary-member-on-a-driver-type`, an expected-PASS case. If the
guard's reach ever grows to catch it, the self-test says so instead of the
documentation drifting.

The two doc comments that overclaimed were corrected rather than left standing:
``CapabilityPort`` now states the seam and what is actually true instead of it
(the platform can call only what the port declares; the narrowing step is a gate
failure), and ``Driver/capability(_:)`` no longer says there is "nothing for a
consumer to downcast".

### Finding 2 — captured limits behind `SafetyLimitsSource`

`SafetyLimitsSource` is deleted. Validation lives on `SafetyLimitsValidator`: a
`final class` in `DriverAPI` whose `init(limits:)` and `adopt(_:)` are
`@_spi(DriverPlatform)`. There is nothing to conform to, nothing to subclass, and
no reachable way to build one — a Driver RECEIVES a validator from the platform
and can only ask it. `adopt` rather than `apply`/`set`/`update` because those read
as commands and the command-verb scan fails on them.

| Probe | expected | result |
| --- | --- | --- |
| `SafetyLimitsValidator(limits: .absolute)` in a Driver | must not compile | `initializer is inaccessible due to '@_spi'` |
| `struct CapturedLimitsSource: SafetyLimitsSource` | must not compile | `cannot find type 'SafetyLimitsSource' in scope` |
| `limits.validate(mgdl:)` on a held `SafetyLimits` | must not compile | `'validate' is inaccessible due to 'internal'` |
| a Driver holding a RECEIVED validator and calling `validate` / `limitsInForce` | must compile | OK |
| the SPI import escape | gate must refuse | rule C **FAIL** (and `absolute` still inaccessible) |

The fourth row is there deliberately: an invariant that makes the legitimate use
impossible is a different bug.

`validationReadsLimitsFresh` now holds the real validator — one reference, handed
over once — narrows the platform's live limits, and asserts the same number is
refused; then widens and asserts it is admitted again. The previous version held
one receiver but that receiver was a TEST-DEFINED conformer, so it proved the
test's own type answers freshly, not that a Driver's has to.

`limitsCannotBeSuppliedByADriver` asserts the shape from the source side: no
`SafetyLimitsSource` declaration, `SafetyLimitsValidator` is `public final class`,
its only `public init` is SPI-annotated, `adopt` is SPI-annotated, and
`validate(mgdl:)` is NOT — a Driver must be able to use what it was handed. And
because the port scan enumerates every protocol in the target,
`expectedNonPortProtocols` is now `["Driver"]` alone: any replacement
driver-implementable protocol that supplies safety state fails that assertion the
moment it is declared, wherever it is put.

The backstop is doc-commented honestly on the type: a value a Driver already read
can be stale, a `Glucose` admitted a moment ago does not retroactively become
invalid, and the terminal enforcement is the write-time absolute-bound gate on the
persistence path (its own story), not this. What bounds the damage here is that a
captured `SafetyLimits` cannot validate anything.

### Cycle 3 gates

Run from the worktree root after `rm -rf` of the build products.

| Gate | Result |
| --- | --- |
| `swift build` | Build complete, 0 warnings |
| `swift test` | 139 tests in 20 suites passed |
| `bash scripts/guards/safety_guards.sh` | clean |
| `bash scripts/guards/safety_guards.sh --self-test` | 72 cases, 2 documented bypasses, 0 unexpected |
| `bash scripts/guards/driver_guards.sh` | clean |
| `bash scripts/guards/driver_guards.sh --self-test` | 64 cases, 0 unexpected (was 42) |

`SafetyConstants.swift` and `safety_guards.sh` remain unmodified. No `#if` or
build-configuration branch anywhere in `Sources/` (AD-17). The manifest assertions
are untouched and green.

### Cycle 3 file list

Added:

- `Sources/DriverAPI/SafetyLimitsValidator.swift`
- `scripts/guards/lib/declared_types.awk`
- `scripts/guards/lib/consumer_casts.awk`

Removed:

- `Sources/DriverAPI/SafetyLimitsSource.swift`

Modified:

- `Sources/DriverAPI/SafetyLimits.swift` — doc comments point at the validator and
  record both earlier shapes that were cacheable
- `Sources/DriverAPI/Capability.swift` — `CapabilityPort` states the downcast seam
  and what is true instead of it
- `Sources/DriverAPI/Driver.swift` — `capability(_:)` no longer overclaims
- `scripts/guards/driver_guards.sh` — rule D, five deny-list words, the residual in
  the header, 22 new self-test cases
- `Tests/DriverAPITests/SafetyLimitsTests.swift` — validation against the real
  validator; `limitsCannotBeSuppliedByADriver`
- `Tests/DriverAPITests/CapabilityStubs.swift` — the two `SafetyLimitsSource`
  conformers removed
- `Tests/DriverAPITests/CapabilitySetTests.swift` — `expectedNonPortProtocols` is
  `["Driver"]`

## Cycle 3 (FINAL) — REQUIRED CHANGES from re-review

Read the "Cycle 2 re-review" section of 1-4-review-codex.md. Findings 2,3,4,6,7 are
closed and FROZEN — do not touch those mechanisms. Two MAJORs remain, both of the
form "a conformer can misbehave behind an existential". Full type-level closure of
that class is impossible in Swift; the accepted fix pattern (per the 1-2 text-scan
precedent) is: move the invariant to a surface the PLATFORM owns, guard-forbid the
consumer-side abuse, and state the residual limit exactly with self-test probes
pinned as expected-uncaught.

1. Downcast seam on CapabilityPort: a Driver port conforming to a capability can
   carry extra public members reachable by downcast to the concrete type.
   Required: (a) driver_guards.sh gains a consumer-side rule — outside
   Sources/DriverAPI/, any `as?`/`as!`/`is` cast whose target relates to a
   capability protocol or a Driver-target type is a violation (string-elided,
   comment-safe, self-tested both directions); (b) extend the delivery deny-list
   with at least: therapy, enact, administer, infuse, inject (word-boundary,
   preserving the legal DoseCategoryProvider read vocabulary — verify no
   collision); (c) document the residual exactly in the guard header: an
   arbitrary-named extra member on a smuggled concrete type is uncatchable by
   text scan and unreachable without a consumer downcast, which (a) forbids —
   pin one such probe as an expected-uncaught case so the limit is executable.
2. Captured limits behind SafetyLimitsSource: relocate the fresh-read invariant
   to a platform-owned validator: a final, non-conformable type in DriverAPI
   (non-public init or equivalent — nothing a Driver target can instantiate or
   substitute) that owns the current-limits state and reads it at every
   validate call. Drivers receive only this validator; SafetyLimitsSource as a
   driver-implementable protocol goes away or becomes non-public. Test: mutate
   the validator's live limits between two validate calls on the SAME received
   reference and assert the second call observes the change. Doc-comment the
   backstop honestly: values a driver already read can be stale; the write-time
   absolute-bound gate (persistence work) is the terminal enforcement.

All four gates + both self-tests green. Dev Agent Record updated per finding.
This is the final cycle before escalation — no scope beyond these two items.

## Cycle 4 (maintainer-authorized doc-honesty round, 2026-08-18) — SCOPE LOCKED

the maintainer approved one final cycle restricted to documentation honesty for the single
open MAJOR (generic-cast laundering, see "Cycle 3 re-review"). NO new scan logic,
NO new awk rules, NO API changes. Exactly three deliverables:

1. Extend driver_guards.sh's header residual statement: the consumer-cast rule
   catches direct `as?`/`as!`/`is` syntax only; indirect casts laundered through
   generics, reflection, `unsafeBitCast`, or any Any-typed helper are NOT caught —
   text scanning cannot close that class. Name PR review of consumer targets as
   the present backstop and the swift-syntax static-analysis work as the closure
   point (mirror the wording discipline of safety_guards.sh's known-limit block,
   including its DEFERRED-WORK note style: new probes become expected-uncaught
   cases, never more awk).
2. Add the reviewer's generic-launder probe (a consumer target with
   `narrow<T>(_ value: Any, to: T.Type) -> T?` reaching a smuggled member) as an
   expected-uncaught `--self-test` case, counted separately like the existing
   known-limit cases, so the day the limit changes the self-test says so.
3. Update the Dev Agent Record: what cycle 4 changed and the exact residual claim
   now made.

All four gates + both self-tests green. Nothing else.

## Cycle 4 — Dev Agent Record

Documentation honesty only, as scoped. No scan logic, no awk, no API changes:
the diff is `driver_guards.sh`'s header plus self-test cases. `swift build`
output is byte-identical because no Swift file was touched.

### What the residual claim used to be, and what it is now

Cycle 3's header said an arbitrary-named member on a concrete Driver port type
"is unreachable from outside its own target without the downcast rule D forbids,
so what it can do is bounded by what that target can already do on its own."
The re-review's probe compiles, reaches the member, and the guard exits 0, so
that bound was false as stated. It is removed rather than qualified.

THE RESIDUAL now names two escapes and says they compose: the arbitrary member
name (nothing to match), and the fact that rule D matches cast SYNTAX — `as?`,
`as!`, `is` written out against a name it knows. The reviewer's helper is quoted
in the header verbatim, because the whole point is that it looks ordinary:

    func narrow<T>(_ value: Any, to type: T.Type) -> T? { value as? T }
    guard let smuggled = narrow(port, to: ExtraPort.self) else { return }

Reflection, `unsafeBitCast` and any `Any`-typed indirection are named as the
same move in different words, and the reason the class is closed to text
scanning is stated once: matching it means resolving what `T` binds to at each
call site, which means type-checking the program.

What is claimed instead is narrower and, I think, all that is true: DriverAPI
still declares no write, so nothing reached this way is part of the contract —
it is one Driver's own surface reached by one consumer that went looking; the
member has to be DECLARED in a Driver target, where the symbol scan reads its
vocabulary and only an arbitrary NAME escapes; and the laundering helper is a
line in a diff. PR REVIEW of consumer targets is named as the backstop, in those
words, with the note that it is a human one and the guard should not be read as
carrying that weight. `WHAT THIS GUARD DOES NOT CATCH` gained the matching
bullet, and rule D's one-line summary at the top now says "cast SYNTAX … and
only that".

A DEFERRED-WORK block follows, in safety_guards.sh's style and making the same
argument its own block makes: each awk hardening round has bought less than the
one before (cycle 3 taught rule D line-wrapped casts and `any` spellings; the
re-review walked past all of it through a generic), so the instruction is
explicit — do not harden the awk further in response to a new probe; add the
probe as a documented expected-uncaught case and take it to story 8-6. The 8-6
claim is deliberately not overstated: a parse tree is not a type checker, and
the block says so, naming swift-syntax as where the work becomes possible
rather than as the fix in itself.

### The probe, and the control that keeps it honest

`known-limit-generic-cast-laundering` is the re-review's two-target shape:
`Sources/Drivers/Probe` declares `ExtraPort: DoseCategoryProvider` with
`performStepTwo()`, and `Sources/PlatformProbe/Narrow.swift` — a consumer,
outside `Sources/Drivers/` exactly as the reviewer built it — launders the
narrowing through `narrow(_:to:)`. It runs as an xfail.

An expected-uncaught case can pass for the wrong reason: "not caught" and "that
path is never read" have the same shape. So the same probe, in the same file,
with the narrowing written out, is a FAIL case —
`consumer-outside-drivers-is-scanned`. I ran the substitution before adding it
and watched the xfail turn XPASS with
`Sources/PlatformProbe/Narrow.swift:7 — as? ExtraPort narrows a Capability
port…`, which is the evidence that the xfail is about the laundering rather than
about an unscanned directory. That control is one self-test case, not scan
logic — the only thing in this cycle beyond the three deliverables, and it is
what makes deliverable 2 mean anything.

Both known limits now run through `self_test_known_limit`, the xfail reporter
modelled on safety_guards.sh's `self_test_known_bypass`: they are counted
separately from the case total ("N documented known limit(s)"), because a case
that asserts what the guard does NOT catch inflates the number that is supposed
to mean "ways this guard was proven to fail". If either starts being caught the
run reports XPASS, fails the self-test, and prints the instruction to promote
the case and rewrite THE RESIDUAL in the same change. Case count reads 64 rather
than cycle 3's 64-including-the-limit because
`known-limit-arbitrary-member-on-a-driver-type` moved out of the total and
`consumer-outside-drivers-is-scanned` moved in.

### Cycle 4 gates

| Gate | Result |
| --- | --- |
| `swift build` | Build complete, 0 warnings |
| `swift test` | 139 tests in 20 suites passed |
| `bash scripts/guards/safety_guards.sh` | clean |
| `bash scripts/guards/safety_guards.sh --self-test` | 72 cases, 2 documented bypasses, 0 unexpected |
| `bash scripts/guards/driver_guards.sh` | clean |
| `bash scripts/guards/driver_guards.sh --self-test` | 64 cases, 2 documented known limits, 0 unexpected |

`--help` still prints the header. No Swift source, no awk helper, and no API
changed; `SafetyConstants.swift` and `safety_guards.sh` remain unmodified.

### Cycle 4 file list

Modified:

- `scripts/guards/driver_guards.sh` — THE RESIDUAL rewritten, DEFERRED-WORK
  block added, rule D summary and the not-caught list corrected;
  `self_test_known_limit` + separate counting; `self_test_add_generic_launderer`
  with its `direct` control shape; the laundering xfail and its scanned-path
  control.

## Merge log (PM, 2026-08-18)

PR #7 squash-merged to develop (9ef310c) under PM merge authority. Evidence:
stamped route claude/opus, 4 dev cycles (3 stamped + maintainer-authorized doc-honesty
cycle 4 for the generic-cast residual); 3 pre-PR cross-provider adversarial
review rounds (12 compiling counterexamples constructed; 10 closed structurally,
2 adopted as documented guard limits per the maintainer's authorization); PR wave green
across CodeRabbit/Devin/GitGuardian/Seer; 2 triage rounds handled 16 bot
findings (13 + 3), incl. two Devin BUGs that hardened the cast rule itself and
a SEC tighten on host validation; a third documented limit (retroactive-
conformance smuggle) added honestly during triage. Final gates: 152 tests /
21 suites, both guard self-tests 0 unexpected. Not a protected path (planning
stamp; no dosing/alert logic). Escalation record: max_cycles escalation to the maintainer
2026-08-18, resolved by his cycle-4 authorization.
