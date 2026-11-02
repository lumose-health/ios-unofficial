---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-7c-trace-replay-kill-switch-app-composition-and-demo-label.md.stamp.json
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

# Story 1.7c: Ship the Trace-Replay Driver — kill switch, app composition and the DEMO DATA label

Status: review

<!-- Planning note (for the maintainer): third of three parts of epics.md Story 1.7 (split explained
in 1-7a). DEPENDS ON 1.7b merged to develop. Estimate: ~250 reviewable lines over ~12 files,
mostly small edits plus two test files. Inside budget.

This is the first Driver behind a compile-time kill switch (FR-27, FR-189, AD-17). The mechanism
chosen here becomes the pattern Medtronic (Epic 7) and, later, the Simulated Driver follow:
- one in-repository boolean in `Package.swift` adds the `TRACE_REPLAY_DRIVER_ENABLED`
  compilation condition to the package targets that need it;
- the same condition is set in the app target's three build configurations;
- a test fails if those two disagree;
- `scripts/ci-local.sh` lists the condition in `ALL_DRIVER_CONDITIONS`, so the every-Driver
  build compiles and tests the Driver even when the boolean is false.
A disabled build compiles the TraceReplayDriver module to nothing, drops its catalog entry and
its bundled traces. `TandemWire` is not a Driver and stays compiled; nothing reaches it while
the Trace-Replay Driver is off and no Tandem Driver exists.

Protected-path note: this touches `Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj` and
`scripts/ci-local.sh`, but no CI workflow, no signing, no dependency or lockfile. Route: NOT
chosen here; the PM routes via /v1/route. -->

## Story

As a Builder,
I want the Trace-Replay Driver in the Driver list of every configuration, labelled Beta and
DEMO DATA, and removable at build time by one setting,
so that the only hardware-free parser check ships everywhere without anyone mistaking it for my
glucose, and a build that must not carry it can drop it entirely.

## Acceptance Criteria

From epics.md Story 1.7 and the PRD rules it brings in: FR-27, FR-36 and FR-189 (kill switch,
not `#if DEBUG`), §8.1 and §8.3 (Beta, permanently), and the DEMO DATA label (1.13a). AC
numbering is local to this file.

1. **One in-repository switch, default on (FR-189, AD-17).** `Package.swift` declares
   `let traceReplayDriverEnabled = true` near the top, with a comment that says what turning it
   off does and that composition is subtractive only. When true it adds
   `.define("TRACE_REPLAY_DRIVER_ENABLED")` to the `swiftSettings` of `DriverAPI`,
   `DriverAPITests`, `TraceReplayDriver` and `TraceReplayDriverTests`, and the
   `TraceReplayDriver` target's `resources` are `[.copy("Traces")]`; when false, neither. No
   other target changes. The switch only removes; nothing anywhere adds a capability.
2. **Off means absent, not inert (FR-27).** Every file under `Sources/Drivers/TraceReplay/`
   is wrapped whole in `#if TRACE_REPLAY_DRIVER_ENABLED`; so is the catalog entry in
   `DriverCatalog.swift` and every test file in `Tests/TraceReplayDriverTests/`. With the
   condition undefined, the module compiles empty, `DriverCatalog.entries` has one entry, and
   the app neither imports nor constructs the Driver.
3. **The app agrees with the package.** The app target's `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
   carries `TRACE_REPLAY_DRIVER_ENABLED` in Debug, Development and Release (Release currently
   has no such setting; add one). `Tests/DriverAPITests/DriverKillSwitchTests.swift` reads
   `Package.swift` and `project.pbxproj` and fails unless all three app configurations carry
   the condition exactly when `traceReplayDriverEnabled` is `true`. The same test file holds a
   table from condition name to Driver target name (`TRACE_REPLAY_DRIVER_ENABLED` →
   `TraceReplayDriver`) and asserts each named target is a Driver target in the manifest, so
   renaming the target without the switch fails (FR-27's "keyed off the Driver's own id",
   as close as a compilation condition can get; see Dev Notes).
4. **The every-Driver build covers it (FR-27, FR-208).** `scripts/ci-local.sh` sets
   `ALL_DRIVER_CONDITIONS=(TRACE_REPLAY_DRIVER_ENABLED)`. Its `driver_conditions` tripwire
   passes. `--self-test` still passes, under both `bash` and `/bin/bash` (3.2).
5. **Catalog tests hold in both states.** `DriverCatalogTests` asserts two entries with the
   condition defined and one without, and `everyDriverInTheTreeIsRegistered` subtracts the
   gated-off target from the manifest set when the condition is undefined (and only then).
   Nothing else in the assertion is loosened.
6. **Composed into the app, never the default (FR-22, FR-36).** `GlycemicGPTApp` builds
   `[simulated]`, plus `TraceReplayDriver(validator: validator)` under the condition, and passes
   that array to `DriverRegistry`. The Xcode project links the `TraceReplayDriver` package
   product. `DriverStartup`'s `firstLaunchDefault` stays `SimulatedDriver.identifier`. The user
   reaches the Trace-Replay Driver only by activating it on the Drivers screen; activating it
   moves the glucose and insulin slots to it (FR-23), and the Drivers screen row reads
   "Verification Status: Beta".
7. **DEMO DATA follows from the catalog, not from a list someone remembers.** A new
   `AppComposition.demoIdentifiers(for descriptors: [DriverDescriptor]) -> Set<DriverIdentifier>`
   in AppFeature returns every descriptor whose transport is `.inProcess`. The app passes
   `AppComposition.demoIdentifiers(for: drivers.map { $0.descriptor })` instead of the literal
   `[SimulatedDriver.identifier]`. AppFeature tests: Simulated-like and Trace-Replay-like
   descriptors (built in the test) are both in the set; a `.bluetoothLowEnergy` and a
   `.network` descriptor are not. With the Trace-Replay Driver active, Home shows the DEMO DATA
   banner and every hero accessibility label carries the "DEMO DATA — not your glucose" prefix
   (existing behaviour, keyed by this set).
8. **Beta means what §8.1 says.** `VerificationStatus.beta`'s doc comment in DriverAPI is
   rewritten to §8.1's definition (implemented, with a named unproven element; for the
   Simulated and Trace-Replay Drivers, permanently, because no device exists to validate
   against). Doc comment only; no case changes. `DriverCatalog`'s "Why a list" doc says the
   catalog can now lose an entry to a compilation condition, and that this is the only
   condition allowed there.
9. **A gated-off build keeps the user's choice (FR-27).** No new code: the registry already
   reports a persisted id that is not in the build as `absentFromBuild` and keeps it
   (`Tests/DomainCoreTests/DriverRegistryTests.swift:357`), and an empty glucose slot is the
   no-active-Driver state from 1.12b. The Dev Agent Record cites both.
10. **Gates and evidence.** All nine frontmatter gates pass. The Dev Agent Record holds (a) a
    Simulator screenshot of Home with the Trace-Replay Driver active, showing the DEMO DATA
    banner, and (b) the result of one local run with `traceReplayDriverEnabled = false`:
    `swift build`, `swift test` and the app `xcodebuild build` all pass and the Drivers screen
    has no Trace-Replay row; then the switch is set back to `true`. If the sandbox cannot run
    them, say so; the PM runs both and records them.

## Tasks / Subtasks

- [ ] Task 1: the switch (AC 1, 2)
  - [ ] `Package.swift`: the boolean, a `traceReplayDriverSettings: [SwiftSetting]` and a
        `traceReplayDriverResources: [Resource]`, applied per AC 1. Keep every target's
        `.swiftLanguageMode(.v6)`; append with `+`.
  - [ ] Wrap each file under `Sources/Drivers/TraceReplay/` (Swift files only; JSON and README
        are not compiled) and under `Tests/TraceReplayDriverTests/`.
  - [ ] `Sources/DriverAPI/DriverCatalog.swift`: wrap the entry; update the doc (AC 8).
- [ ] Task 2: Xcode project (AC 3, 6). Exact edits in Dev Notes.
- [ ] Task 3: `scripts/ci-local.sh` (AC 4): the one array line and its comment.
- [ ] Task 4: app composition and DEMO DATA (AC 6, 7)
  - [ ] `Sources/AppFeature/DriverHost.swift`: `AppComposition.demoIdentifiers(for:)`.
  - [ ] `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: conditional import, the drivers array,
        the derived demo set.
  - [ ] `Tests/AppFeatureTests/`: the demo-set tests (new small file or an existing suite).
- [ ] Task 5: tests (AC 3, 5): `Tests/DriverAPITests/DriverKillSwitchTests.swift`;
      `DriverCatalogTests` conditional expectations.
- [ ] Task 6: `Sources/DriverAPI/DriverDescriptor.swift`: the `.beta` doc comment (AC 8).
- [ ] Task 7: gates, screenshot, gate-off run (AC 10).

## Dev Notes

### Known pitfalls (read before writing code)

- The worker cannot compile, so write carefully. A `switch` after any statement in a function or getter needs `return switch`. Test functions that `await` must be `async`. In Swift Testing, `#expect` over a key-path closure such as `allSatisfy(\.x)` is treated as throwing, so bind it to a `let` first. Typed-throws closures can't call `NSLock.withLock` and throw a typed error; use `lock()`/`defer unlock()`. In an init, assign every stored property before reading any `self` property.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs in `#if os(iOS)`.
- Never write a numeric safety constant inline, and never disguise one. Literals equal to safety constants (for example 18, 20, 21, 55, 58, 61, 70, 180, 250) trip the guard. Hex colour components count too.
- Swift 6 strict concurrency. Tests that check state that settles asynchronously must wait with the existing `eventually` helper, not assert immediately.
- Code comments must not mention stories, epics, AC numbers, agents or cycles. No private UIKit API.
- Diff budget: about 800 reviewable lines.

### Rules of the road

- **Not `#if DEBUG`.** The only new condition is `TRACE_REPLAY_DRIVER_ENABLED`, and it is
  defined in Release as well as Debug and Development (FR-189: the hardware-free Drivers ship
  in every configuration).
- **Subtractive only (AD-17).** The switch removes a Driver. No other `-D` flag, no setting
  that adds behaviour.
- **Do not edit** `Sources/Wire/**`, `Sources/SafetyCore/**`, `Sources/DomainCore/**`, CI
  workflow files or the guards. Do not change the Trace-Replay Driver's behaviour; only wrap it.
- **`bash` 3.2:** the one `ci-local.sh` line must stay 3.2-safe (a plain array assignment is).
- **Scratch files only under `.build/`.**

### Xcode project edits (exact)

`Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj` uses hand-assigned ids; 35 and 36 are
free. Mirror the `SimulatedDriver` lines (ids 32 and 34):
- Add `A10000000000000000000035 = {isa = XCSwiftPackageProductDependency; package =
  A10000000000000000000030; productName = TraceReplayDriver; };`
- Add `A10000000000000000000036 = {isa = PBXBuildFile; productRef = A10000000000000000000035; };`
- Frameworks phase `A10000000000000000000021`: append `A10000000000000000000036,` to `files`.
- Native target `A10000000000000000000001`: append `A10000000000000000000035,` to
  `packageProductDependencies`.
- App target configurations: in `A10000000000000000000060` (Debug) and
  `A10000000000000000000061` (Development) change `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;`
  to `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG TRACE_REPLAY_DRIVER_ENABLED";`. In
  `A10000000000000000000062` (Release) add
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS = TRACE_REPLAY_DRIVER_ENABLED;` in alphabetical position.
  Leave the project-level configurations (63, 64, 65) alone.

The kill-switch test parses those three app-configuration lines by id, so keep each on one line
as the file already does.

### The app composition, after the change

```swift
#if TRACE_REPLAY_DRIVER_ENABLED
import TraceReplayDriver
#endif
...
var drivers: [any Driver] = [simulated]
#if TRACE_REPLAY_DRIVER_ENABLED
drivers.append(TraceReplayDriver(validator: validator))
#endif
...
registry = try DriverRegistry(drivers: drivers, store: store)
...
demoIdentifiers: AppComposition.demoIdentifiers(for: drivers.map { $0.descriptor })
```

`descriptor` is `nonisolated`, so the closure needs no `await`. Use a closure, not a key path, to keep the compiler away from key paths into an actor existential. The registry's
duplicate-identifier precondition stays as is.

### "Keyed off the Driver's own id" — what is possible

FR-27 asks that the gate be keyed off the Driver's canonical id constant so a rename cannot
leave the switch pointing nowhere. A Swift compilation condition is a bare identifier and cannot
be computed from a string constant. The test in AC 3 gives the same protection: it names the
target each condition gates and fails if that target is not a Driver target in the manifest.
Record this as a stated deviation in the Dev Agent Record.

### Known follow-ups (do not build here)

- The Simulated Driver is not behind a switch yet. FR-189 says it should be governed by the
  same mechanism. Applying the pattern is a small follow-up the PM should schedule.
- The Simulated Driver's catalog verification is `.unverified`; §8.3 says Beta. Not changed
  here.
- A CI lane that builds with the switch off. AC 10 covers it once by hand; an automated lane
  belongs with the build-matrix work.

### Existing code to build on

- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: current composition (one Driver, literal demo
  set).
- `Sources/AppFeature/DriverHost.swift`: `AppComposition` (validator, selection file URL),
  `HomeModel`'s `demoIdentifiers`.
- `Sources/AppFeature/HomeScaffold.swift`: `DemoDataLabel` (text and visibility rule).
- `Sources/AppFeature/DriversScreen.swift`: "Verification Status: Beta" rendering.
- `scripts/ci-local.sh`: `ALL_DRIVER_CONDITIONS`, `driver_conditions`.
- `Tests/DriverAPITests/DriverCatalogTests.swift`: `DriverAPISource.repositoryRoot`, the
  manifest reader used by `everyDriverInTheTreeIsRegistered`.

### Testing standards

- Swift Testing. File-reading tests resolve the repository root the way
  `DriverCatalogTests` does.
- `DriverAPITests` gets the define through AC 1, so `#if TRACE_REPLAY_DRIVER_ENABLED` in its
  files reflects the package build. In the every-Driver build the condition is always defined.
- Known flake: `WallClockSchedulerTests`. One re-run allowed; record it.

### Project structure notes

- New: `Tests/DriverAPITests/DriverKillSwitchTests.swift`, an AppFeature test file for the demo
  set (or extend `DriverHostTests.swift`).
- Modified: `Package.swift`; `Sources/DriverAPI/DriverCatalog.swift`;
  `Sources/DriverAPI/DriverDescriptor.swift` (doc only); every Swift file under
  `Sources/Drivers/TraceReplay/` and `Tests/TraceReplayDriverTests/` (wrap only);
  `Sources/AppFeature/DriverHost.swift`; `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`;
  `Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj`; `scripts/ci-local.sh`;
  `Tests/DriverAPITests/DriverCatalogTests.swift`.
- Branch from `develop` after 1.7b merges, for example `feat/trace-replay-kill-switch`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 1.7; Story 8.8 (every-Driver build)]
- [Source: prd.md FR-22 (:534), FR-23 (:545), FR-27 (:592), FR-36 (:714), FR-189 (:3828),
  §8.1 (Beta), §8.3 Trace-Replay row (:5932), OQ-15 (:6301)]
- [Source: ARCHITECTURE-SPINE.md AD-17]
- [Source: 1-13a (DEMO DATA banner), 1-12b (no active Driver), 8-8 (`ALL_DRIVER_CONDITIONS`)]

## Dev Agent Record

### Agent Model Used

Amelia / GPT-6 coding agent.

### Debug Log References

- `git diff --check`: passed.
- `plutil -lint Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj`: passed.
- `bash scripts/guards/safety_guards.sh`: passed.
- `bash scripts/guards/driver_guards.sh`: passed.
- `bash scripts/ci-local.sh --self-test`: passed; all cases passed, including the undeclared Driver condition tripwire.
- Both guard `--self-test` commands were also run directly through `/bin/bash`; they passed. The self-tests take several minutes and completed all injected failure cases.
- `swift build` and `swift test`: unable to start because SwiftPM's manifest compiler writes its module cache to `~/.cache/clang/ModuleCache`, which is outside the writable workspace. An in-workspace `SWIFTPM_MODULECACHE_OVERRIDE` did not avoid the sandbox failure (`sandbox-exec: sandbox_apply: Operation not permitted`).
- `xcodebuild test -scheme GlycemicGPT-Package ...`: could not run because CoreSimulatorService was unavailable and Xcode reported that the root directory did not contain an Xcode project, workspace, or package for that scheme invocation.
- `xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj ...`: could not resolve the Swift package because the same external SwiftPM/Clang caches are not writable; CoreSimulatorService was also unavailable.
- Switch-off attempt: temporarily set `traceReplayDriverEnabled` to `false` and removed the condition from the app target's three configurations, then attempted `swift build`, `swift test`, and the app build. All were blocked at manifest/cache resolution; the app build also could not access simulator services. The enabled configuration was restored in `finally`. No Drivers screen screenshot could be captured because no Simulator runtime was available.

### Completion Notes List

- Added `traceReplayDriverEnabled` (default `true`) and applied its define to `DriverAPI`, `DriverAPITests`, `TraceReplayDriver`, and `TraceReplayDriverTests`; Trace-Replay source/test files, catalog entry, and trace resources are absent when the switch is off.
- Linked TraceReplayDriver into the app and set the condition for Debug, Development, and Release. The first-launch default remains SimulatedDriver.
- Added kill-switch agreement/target tests, conditional catalog assertions, and AppComposition tests for in-process DEMO DATA identifiers. Existing hero/banner and Drivers screen tests already cover the DEMO DATA prefix and Beta row behavior.
- `VerificationStatus.beta` now documents the §8.1 meaning, including permanent Beta status for hardware-free Drivers. The catalog documentation identifies its sole allowed compilation condition.
- Deviation: Swift compilation conditions cannot be derived from a Driver's string identifier. `DriverKillSwitchTests` binds the condition to the declared `TraceReplayDriver` manifest target and its `Sources/Drivers/` path.
- The existing registry behavior preserves a saved selection as `absentFromBuild` when its Driver is omitted (`Tests/DomainCoreTests/DriverRegistryTests.swift:357`); the empty glucose slot remains the no-active-Driver state.
- Simulator screenshots and successful on/off Swift/Xcode build evidence remain unavailable in this sandbox; the PM must rerun those gates and capture the active-driver screen when Simulator services are available.

- Completion pass (unsandboxed, 2026-11-02):
  - Compile fix: Swift rejects `#if` inside an array literal. `DriverCatalog.entries` is now declared twice under `#if TRACE_REPLAY_DRIVER_ENABLED` / `#else`, with the full list first, because `driver_guards.sh` reads only the first `entries` literal. I tried a runtime `.filter` first and dropped it: it left the descriptor strings in the switch-off binary (inert, not absent).
  - `Package.swift`: the test target reuses `traceReplayDriverResources`. `PackageManifestTests.traceReplayDependencies` now asserts `resources:traceReplayDriverResources` on both targets, and that the constant is `.copy("Traces")` exactly when the switch is on.
  - Scope check: the diffs to the Trace-Replay sources and tests are `#if`/`#endif` wraps only (7 pairs). There was no behaviour change, so nothing was reverted.
  - Switch OFF (Package.swift false, condition removed from all 3 app configs): `swift build --build-tests` passed; `swift test` passed 484 tests in 62 suites (switch on: 499 in 64). The TraceReplayDriver objects carry only compiler metadata and no resource bundle is produced. The app Debug `xcodebuild build` passed, and the app has no trace bundle and no `trace-replay`/`TraceReplay` strings. In the Simulator, the Drivers screen listed only the Simulated Driver. Both files were then restored to the enabled state.
  - Every-Driver build, after the PM ruling: `Package.swift` now derives `traceReplayDriverCompiled = traceReplayDriverEnabled || everyDriverBuild`, where `everyDriverBuild` reads `GLYCEMICGPT_ALL_DRIVERS == "1"` from `ProcessInfo`. That one value drives both the define and `traceReplayDriverResources`. The every-Driver `swift build` and `swift test` in `scripts/ci-local.sh` set `GLYCEMICGPT_ALL_DRIVERS=1` with a plain env prefix, which works in bash 3.2 and 5. `DriverKillSwitchTests` still compares the committed constant with the Xcode project. `PackageManifestTests` asserts the derivation and that both the define and the resources follow it. `docs/ci-checks.md` documents the override.
    - Switch off, env unset: `swift test` 484/62 passed; no TraceReplay bundle; module objects hold only compiler metadata; the app has no Trace-Replay strings or resources.
    - Switch off, env set: the every-Driver build and test passed (499 tests in 64 suites), and `GlycemicGPT_TraceReplayDriver.bundle/Traces` is present.
    - Switch off in `Package.swift` only (Xcode left on): `DriverKillSwitchTests` failed as intended.
    - Switch on: every gate re-run and passed, as listed below. Enabled state restored.
  - Gates (switch on): swift build, swift build -c release, swift test ×2 (499/499 both), safety/driver guards and their self-tests, ci-local self-test (bash and /bin/bash), xcodebuild package test, and the app Debug build all passed.
  - Simulator (Release build, iPhone 17 iOS 26.5): Drivers lists Simulated (active, the default) and Trace-Replay ("Verification Status: Beta"). After activating Trace-Replay, Simulated went inactive. Home shows 118 mg/dL "just now" under the DEMO DATA banner. The hero's accessibility label is "DEMO DATA — not your glucose, 118 mg/dL, trend unknown, just now". IOB 2.50u is marked Stale. Screenshots: scratchpad `on-drivers.png`, `on-home-trace.png`, `off-drivers.png`.
  - Diff size: 17 tracked files, +114/−22, plus two new test files (53 lines). About 190 reviewable lines.

### File List

- `Package.swift`
- `Sources/DriverAPI/DriverCatalog.swift`
- `Sources/DriverAPI/DriverDescriptor.swift`
- `Sources/Drivers/TraceReplay/TraceFile.swift`
- `Sources/Drivers/TraceReplay/TraceReplayCapabilityPorts.swift`
- `Sources/Drivers/TraceReplay/TraceReplayDriver.swift`
- `Sources/Drivers/TraceReplay/TraceReplayLog.swift`
- `Sources/AppFeature/DriverHost.swift`
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
- `Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj`
- `Tests/DriverAPITests/DriverCatalogTests.swift`
- `Tests/DriverAPITests/DriverKillSwitchTests.swift`
- `Tests/TraceReplayDriverTests/TestDoubles.swift`
- `Tests/TraceReplayDriverTests/TraceFileTests.swift`
- `Tests/TraceReplayDriverTests/TraceReplayDriverTests.swift`
- `Tests/AppFeatureTests/AppCompositionTests.swift`
- `scripts/ci-local.sh`
- `Tests/SafetyCoreTests/PackageManifestTests.swift`
- `docs/ci-checks.md`

### PM notes before dispatch (2026-11-02)
- PR #30 (Trace-Replay Driver) merged. The Driver re-anchors so that its newest frame lands at replay start. It never emits out-of-range frames as numbers. `deactivate()` clears its state.
- The DEMO DATA label has to cover the Trace-Replay Driver as well as the Simulated Driver. Derive it from the platform's own knowledge of the Driver (its in-process transport), never from anything the Driver supplies. Test that both Drivers get the label and that a non-in-process Driver does not.
- Shipped builds keep the Simulated Driver as the first-launch default. Trace-Replay is listed in the Drivers screen and can be activated there. It is Beta, and the Drivers screen must show that.
- Known pitfalls for the worker, which can't compile:
  - `return switch` after any statement.
  - Mark tests that `await` as `async`.
  - Bind a key-path `#expect` to a `let`.
  - Use `lock()`/`defer unlock()` in typed-throws closures.
  - In an `init`, assign every stored property before you read `self`.
  - Guard iOS-only APIs with `#if os(iOS)`.
  - Use `eventually` for state that settles asynchronously.
  - No literal may equal a safety constant.
  - The kill-switch flag has to agree in both `Package.swift` and the Xcode project. The story's test checks this.
- budget: CONTINUATION_REQUIRED sha256:23836c6791b698540d946f6fe6389af1c90e51f7773221866e06230cfce6a39e cycle 1 2026-11-02T09:17:01Z
