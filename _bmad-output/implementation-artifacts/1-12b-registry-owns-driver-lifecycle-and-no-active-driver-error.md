---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-12b-registry-owns-driver-lifecycle-and-no-active-driver-error.md.stamp.json
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

Status: done

> PR #20 merged 2026-11-01; dispatch now.
> PR #20 (`feat/driver-registry`): `DomainCore`, `DriverRegistry`, `DriverSlots` and
> `FileDriverSelectionStore`. Branch from `develop` after #20 lands. If PR #19 (onboarding) has also
> merged, `GlycemicGPTApp.swift` and `AppShell.swift` will carry the onboarding model too; keep it.

> **SPLIT AGAIN. This file is the registry going live in the app, plus FR-33. It is not all of
> what 1.12a deferred.** Everything 1.12a deferred comes to about 1,600-1,800 reviewable lines.
> Moving app start-up onto the registry is the prerequisite for both user-facing pieces: the
> deactivation confirmation needs a registry in the app to deactivate through, and Home can only
> show "no active Driver" honestly if it reads through the registry. It is also the most expensive
> piece, because `HomeModel` stops owning a Driver's lifecycle and about a third of
> `DriverHostTests` moves with it. So this file carries:
> - app composition, with restore at launch and Home consuming the registry
> - FR-33, the typed "no active Driver for this Capability" read error
> - Home's honest display of FR-33 and of FR-28 start failures
> - the 1.12a known limit (a slot naming a Driver that failed to start)
>
> **1.12c** (not written yet) carries FR-25's confirmation and the Drivers screen, FR-29's
> per-Driver settings, and FR-34's event channel. It is estimated at ~800-850 lines and may itself
> split FR-34 off into a 1.12d (see "Out of scope").
>
> The file name predates this split and still lists those items; the PM may rename it (see the
> open question in the Dev Agent Record notes).

# Story 1.12b: The registry goes live — start-up restore, and "no active Driver" as a distinguishable error

<!-- Planning note (for the maintainer): estimate ~780-880 reviewable lines over ~13 files, about
half of it tests and a large share of that rewritten DriverHostTests. At the edge of the budget;
over ~950, the worker stops and reports rather than trimming tests. Touches Package.swift (one new
internal edge, AppFeature → DomainCore, already in the spine's module graph; no external
dependency, no lockfile), DomainCore (one read API, one store query), AppFeature (HomeModel, the
Home tab) and the app target's composition. No DriverAPI, Driver, dosing, alert floor, ingestion
mapper, safety_validation, Persistence, CI or CODEOWNERS change. Behaviour change worth review:
the Simulated Driver is no longer stopped when the app goes to the background (see "Scene phase
under the registry"). Route: NOT chosen here; the PM routes via /v1/route. -->

## Story

As a Builder,
I want the app to start from the Drivers I chose, and to tell me plainly when no Driver is providing a reading,
so that an empty screen never passes for "nothing happened".

## Acceptance Criteria

From epics.md Story 1.12 (the FR-26 composition half and FR-33), FR-28's "reports this", and the
1.12a Dev Agent Record's known limit. FR-25, FR-29 and FR-34 are 1.12c.

1. **One lifecycle owner: the registry (AD-16, FR-26).** The app builds a `DriverRegistry` holding
   the Simulated Driver and a `FileDriverSelectionStore` at
   `URL.applicationSupportDirectory/DriverSelection/selection.json`. `HomeModel` no longer holds a
   `DriverLifecycle` and never calls `activate()` or `deactivate()` on a Driver. A test asserts that
   `HomeModel` going through background, foreground and a second background calls the test
   Driver's `activate()` exactly once (from the registry's restore) and `deactivate()` zero times.

2. **Restore runs at launch, before Home reads, with no scene needed (FR-26).** `GlycemicGPTApp.init`
   starts `DriverStartup.run(...)` in a `Task` straight away. `init` runs on a background
   relaunch too, where no view `.task` would run. `HomeModel` awaits that task's outcome before
   its first port read. The startup path takes no Backend, session or network input.

3. **First launch activates the demo Driver once, and only once.** `DriverStartup.run(registry:
   store:firstLaunchDefault:)`:
   - always calls `registry.restore()` first;
   - then, only if the restore report has no `selectionFailure` **and** the store reports no saved
     selection file **and** the persisted selection is empty, calls
     `registry.activate(firstLaunchDefault)`;
   - returns a `DriverStartupOutcome` holding the report, the seeded id (or `nil`) and any
     `DriverRegistryError` from the seed.

   Activating writes the file, so a later launch never seeds again. In particular, an install whose
   saved selection is the empty set (a Builder who deactivated everything, once 1.12c ships) stays
   empty. An existing install upgraded from a build without the registry has no file, so it is
   seeded with the Simulated Driver and looks as it did before. An unreadable or locked file
   (`selectionFailure` set) never triggers a seed, so a failed read is never followed by a write
   that would erase the Builder's choice (the 1.12a rule).

4. **FR-33: a slot-named read with a typed, distinguishable error.** `DriverRegistry` gains
   `public func port(for capability: Capability) async throws(CapabilityReadError) -> HeldPort`,
   with `HeldPort` carrying `holder: DriverIdentifier` and `port: CapabilityPort`.
   `CapabilityReadError` has exactly these cases:
   - `noActiveDriver(Capability)`: no persisted, present Driver holds the capability.
   - `holderNotRunning(DriverIdentifier, Capability, DriverLifecycleState)`: the selection names a
     holder whose lifecycle is not `active` or `degraded`.
   - `portUnavailable(DriverIdentifier, Capability)`: the holder returned `nil`, or a port for a
     different capability.
   - `notSingleInstance(Capability)`: BGM source and data sync are read through slot members,
     never through one holder.
   - `cancelled`: the calling task was cancelled.

   Tests pin these behaviours:
   - With no active Driver, reading `.insulinSource` throws `.noActiveDriver(.insulinSource)`.
     With a held test Driver whose `doses(since:)` returns `[]`, the read succeeds and the history
     is empty. The two are told apart in one test.
   - With only a glucose-only Driver active, reading `.pumpStatus` throws
     `.noActiveDriver(.pumpStatus)`. A CGM cannot satisfy a pump-slot read.
   - Every Capability is covered: each single-instance one with no holder throws `noActiveDriver`
     naming it, and `.bgmSource` and `.dataSync` throw `notSingleInstance`.
   - Cancelling the reading task before the read throws `.cancelled`, never `noActiveDriver`.
   - The read does not take the registry's operation gate. It still returns while another
     Driver's activation is held on a gate.

   No case returns an empty collection, a zero value or a default, and none is a `DriverFailure`.

5. **The 1.12a known limit is surfaced, not hidden.** If a restore removal save fails, the
   selection still names a Driver that failed to start. `port(for:)` then throws
   `.holderNotRunning(id, capability, .failed)`, which Home shows as that Driver failing to start
   (AC 7). A test reproduces it with a store whose save fails after the initial load and a Driver
   whose activation throws.

6. **Home reads through the registry.**
   - Glucose comes from `port(for: .glucoseSource)`. It is required for the Home dashboard to show.
   - Insulin comes from `port(for: .insulinSource)` and pump status from `port(for: .pumpStatus)`.
     Both are optional. `.noActiveDriver` for either is normal: that metric is simply absent, as a
     `nil` IOB or pump status is today, and it is not an error.
   - Any other error on an optional slot, except `.cancelled`, is kept in
     `HomeModel.slotErrors: [CapabilityReadError]` and the metric is absent. It never fails Home.
   - `ActiveDriverPorts.insulinSource` becomes optional.
   - `isDemo` starts from `registry.initialSlots` (the slots derived from the selection loaded at
     construction) and is recomputed from the glucose holder after each read. With no glucose
     holder it is `false`.
   - The status row's active Drivers are the glucose holder (if any), not a fixed Driver.

7. **Home tells no-Driver apart from no-data (FR-33, FR-28, SI-6).** `HomeModel.source` is a
   closed enum:
   - `pending`: startup has not finished, or the first read is still running.
   - `connected(DriverIdentifier)`
   - `noActiveDriver`: nothing holds glucose, and no glucose-capable Driver failed to start.
   - `startFailed(DriverIdentifier, DriverFailure)`: nothing holds glucose because the startup
     report's `failed` list has a Driver whose descriptor declares `.glucoseSource` (the
     lowest-id one). FR-28 removed it from the selection, so it would otherwise read as
     `noActiveDriver`.
   - `unavailable(CapabilityReadError)`: `holderNotRunning` or `portUnavailable` on the glucose
     read.

   `.cancelled` never changes `source`. A pure `HomeSourceMessage.make(source:displayName:)` gives
   the Home tab its copy:
   - `noActiveDriver`: title "No glucose source", body "No active Driver is providing glucose
     readings, so there is nothing to show here." Identifier `home.no-glucose-source`.
   - `startFailed` and `unavailable(.holderNotRunning)`: title "Unable to start data source"
     (today's string), body "\<Driver name\> didn't start. Restart the app to try again."
     Identifier `home.source-failed`.
   - `unavailable(.portUnavailable)`: the same title, body "\<Driver name\> isn't providing glucose
     readings. Restart the app to try again." Identifier `home.source-failed`.
   - `pending` and `connected`: no message. The Home dashboard renders.

   In the three message states the Home tab shows the message **instead of** the dashboard. The
   hero's "--" / "No glucose readings yet" is never shown when no Driver holds glucose. The copy
   uses no red text, no failure detail and no `DriverFailure` string. The Driver name comes from
   `registry.descriptors`. Tests cover every `source` value at model level and every message.

8. **Scene phase under the registry.**
   - **Foreground, not connected** (`pending`, `noActiveDriver`, `startFailed` or `unavailable`):
     run `connect()`. It awaits startup, reads the three ports, seeds from `latestReading()` and
     `latestStatus()`, and attaches the stream consumers.
   - **Foreground, connected:** behaves as 1.15 does today, with exactly one read sequence per
     foreground.
   - **Background:** cancels the hero ticker and nothing else. The stream consumers stay attached.
     The Driver is running, and the GlucoseSource contract says a consumer is cancelled only when
     the platform stops the Driver, because cancelling the `for await` terminates that
     activation's stream for good.
   - **A stream that ends while its task was not cancelled** means the registry tore the Driver
     down. Home then drops the ports, sets `source = .pending`, and reconnects on the next
     foreground.
   - The existing ordering guards (generation counter, `foregroundReadSatisfied`,
     `inactiveTransitions`) keep their meaning. The generation now counts connections instead of
     activations.

9. **Placement and edges (AD-1, AD-2, AD-3, AD-13).**
   - `AppFeature` depends on exactly `["SafetyCore", "DriverAPI", "DomainCore"]`, and
     `AppFeatureTests` gains `"DomainCore"`. `PackageManifestTests` pins the new AppFeature list.
   - No Driver target depends on `DomainCore` (unchanged).
   - `CapabilityReadError` and `port(for:)` live in `DomainCore`, not in `DriverAPI`. Drivers never
     read slots, and `DriverFailure` stays the Driver-side taxonomy.
   - No cast against `CapabilityPort` or a port protocol anywhere in `DomainCore` or `AppFeature`
     (driver guard rule D). Use `CapabilityPort.capability` and `case` patterns.

10. **Gates and budget.** All nine frontmatter gates pass. Report the reviewable diff in the Dev
    Agent Record. Past ~950 lines, stop and write a NEEDS-HUMAN line instead of trimming tests. The
    Dev Agent Record holds a simulator screenshot of a fresh-install launch showing the DEMO DATA
    banner and a hero value. If the sandbox cannot run the simulator, say so; the PM takes it.

## Tasks / Subtasks

- [ ] Task 1: DomainCore read API (AC 4, 5, 9)
  - [ ] New `Sources/DomainCore/CapabilityRead.swift`: `CapabilityReadError` (`Error, Hashable,
        Sendable`) and `HeldPort` (`Sendable`). Brief doc comments.
  - [ ] `Sources/DomainCore/DriverRegistry.swift`:
    - Make `descriptors` `public nonisolated let`.
    - Add `public nonisolated let initialSlots: DriverSlots`, derived in `init` from the loaded
      set ∩ known ids (empty if the load failed).
    - Add `port(for:)` following "Read algorithm" in Dev Notes. It does **not** call `enter()`.
  - [ ] `Sources/DomainCore/DriverSelectionStore.swift`: add
        `func hasSavedSelection() -> Bool` to the protocol. `FileDriverSelectionStore` answers
        `FileManager.default.fileExists(atPath: fileURL.path)`. Update
        `RecordingSelectionStore` in `Tests/DomainCoreTests/RegistryTestDrivers.swift` (one
        property, one method).
  - [ ] New `Tests/DomainCoreTests/CapabilityReadTests.swift` with a `PortTestDriver` that
        returns real ports (a glucose source, an insulin source with scripted `doses(since:)`, a
        pump status source), plus one that returns a wrong-capability port. Cover every AC 4 and
        AC 5 bullet and `initialSlots`.
- [ ] Task 2: package edge (AC 9)
  - [ ] `Package.swift`: `AppFeature` dependencies `["SafetyCore", "DriverAPI", "DomainCore"]`;
        `AppFeatureTests` add `"DomainCore"`. Update the comment above the AppFeature target in a
        line. Touch nothing else.
  - [ ] `Tests/SafetyCoreTests/PackageManifestTests.swift`: rename and update
        `appFeatureDependencies` to assert
        `dependencies:["SafetyCore","DriverAPI","DomainCore"]`.
- [ ] Task 3: startup (AC 2, 3)
  - [ ] New `Sources/AppFeature/DriverStartup.swift`: `DriverStartup.run(...)` and
        `DriverStartupOutcome` (`Sendable, Equatable`). Also add
        `AppComposition.driverSelectionFileURL` (a static computed `URL`) next to
        `makeSafetyValidator()`.
  - [ ] New `Tests/AppFeatureTests/DriverStartupTests.swift`, using an in-memory store double with
        a settable "has saved selection" flag and injectable failures:
    - first launch (no file) seeds once, and a second `run` on a new registry with the same store
      does not re-seed
    - an empty saved selection with the file present does not seed
    - a persisted selection is restored and not seeded over
    - a load failure (`.unreadable`) gives a report with `selectionFailure`, no seed and no save
    - a seed whose activation throws is returned in the outcome, and nothing is persisted
    - restore runs before the seed (the order is visible in the store's saved sets)
- [ ] Task 4: HomeModel consumes the registry (AC 1, 6, 7, 8)
  - [ ] `Sources/AppFeature/DriverHost.swift`, following "HomeModel changes" in Dev Notes.
  - [ ] Pure `HomeSourceMessage` (title, body, identifier) with `make(source:displayName:)`, in
        the same file or a new `Sources/AppFeature/HomeSource.swift`.
- [ ] Task 5: the Home tab and the app (AC 2, 7)
  - [ ] `Sources/AppFeature/AppShell.swift`: in `tabRoot(.home)`, replace the `hostError` branch
        with a `switch` on `model.source` that shows `HomeSourceMessage` for the three message
        states and `HomeScreen()` otherwise. Keep today's layout (`VStack(spacing: 12)`,
        `.headline` title, padding 16). Apply the identifier. Body text uses `.primary`.
  - [ ] `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: compose as in "App composition" in Dev
        Notes. The scene-phase handler keeps its three branches.
- [ ] Task 6: tests for Home (AC 1, 6, 7, 8)
  - [ ] `Tests/AppFeatureTests/DriverHostTests.swift`: add a `makeHostModel(...)` helper that wraps
        the test Driver(s) in a `DriverRegistry` over an in-memory store pre-seeded with their ids.
        It passes `awaitStartup` as a closure that runs `DriverStartup.run` with
        `firstLaunchDefault: nil`. Move every construction onto it. Then follow "DriverHostTests:
        what moves" in Dev Notes.
- [ ] Task 7: gates, screenshot, diff size (AC 10)

## Dev Notes

### Known pitfalls

- The worker cannot compile, so write carefully. A `switch` that follows any statement in a function or getter needs `return switch`. Test functions that `await` must be marked `async`. In Swift Testing, `#expect` over a key-path closure such as `allSatisfy(\.x)` is treated as throwing; bind it to a `let` first.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs (UIKit, `.tabBar` toolbars, `navigationBar*`, permission APIs) in `#if os(iOS)`.
- Every SF Symbol name needs a test that it exists on UIKit and AppKit.
- Small coloured text needs a contrast ratio of at least 4.5:1. Use the existing light/dark palette in `StatusRowView`.
- Never write a numeric safety constant inline, and never disguise one. Any literal that equals a safety constant's value (for example 18, 20, 55, 58, 70, 180, 250) trips the safety guard. Avoid such literals, or route them through named non-safety constants that are explained.
- Swift 6 strict concurrency; actors are reentrant across `await`.
- Code comments must not mention stories, epics, AC numbers, agents or cycles. No private UIKit API.
- Diff budget: about 800 reviewable lines. If the work exceeds that, split it and say so at the top.

This change adds no SF Symbol and no coloured small text. The Home messages use `.primary`.

### Read first (rules of the road)

- **Edit only these paths:**
  - `Package.swift` (the two AppFeature dependency lists and one comment line)
  - `Sources/DomainCore/DriverRegistry.swift`, `Sources/DomainCore/DriverSelectionStore.swift`,
    the new `Sources/DomainCore/CapabilityRead.swift`
  - `Sources/AppFeature/DriverHost.swift`, `Sources/AppFeature/AppShell.swift`, the new
    `Sources/AppFeature/DriverStartup.swift` and optionally `Sources/AppFeature/HomeSource.swift`
  - `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
  - `Tests/DomainCoreTests/**`, `Tests/AppFeatureTests/DriverHostTests.swift`, the new
    `Tests/AppFeatureTests/DriverStartupTests.swift`,
    `Tests/SafetyCoreTests/PackageManifestTests.swift`
  - this file's Dev Agent Record

  Do **not** edit `Sources/DriverAPI/**` (including `DriverFailure` and `DriverCatalog`),
  `Sources/Drivers/**`, `Sources/SafetyCore/**`, `Sources/Persistence/**`, the Xcode project, CI
  files, the guards or `Package.resolved`. If you need one, write a NEEDS-HUMAN line.
- **No therapeutic write (SI-1).** Reads only.
- **No wall-clock reads under `Sources/`** (AD-14). `URL.applicationSupportDirectory` is not a
  clock read.
- **Logging:** no new logger. FR-28's "reports this" is met by the startup outcome and
  `HomeModel.source`. The existing `HomeLogging` stays as it is.
- **Scratch files only under `.build/` in your worktree. One operation per Bash call.** Your
  sandbox likely cannot run SwiftPM or the Simulator; the launcher re-runs every gate.

### Existing code to build on (PR #20 merged into develop)

- `Sources/DomainCore/DriverRegistry.swift`, the `DriverRegistry` actor:
  - `init(drivers:store:) throws(DriverRegistryError)` loads synchronously and records a load
    failure instead of throwing.
  - `slots` is derived from `persisted ∩ known` on every read.
  - `lifecycleState(of:)` and `persistedSelection`.
  - `activate`, `deactivate` and `restore` are serialized by `enter()`/`leave()`. `restore`
    retries a transient (`.unavailable`) load, refuses a corrupt one, drops losing claimants and
    failed ids in one save, and reports `restored`, `absentFromBuild`, `failed`,
    `removedConflicts`, `unremoved` and `selectionFailure`.
  - The `#if DEBUG` seams `setEnqueueHook` and `setTransitionFault` are internal. Reach them with
    `@testable import DomainCore` if you need them.
- `Sources/DomainCore/DriverSlots.swift`: `holder(of:)`, `members(of:)`, `pump`, `glucose`.
- `Sources/DomainCore/DriverSelectionStore.swift`: the protocol, `FileDriverSelectionStore`
  (atomic JSON, Data Protection until first unlock on iOS), and `DriverSelectionStoreFailure` with
  `isTransient`.
- `Tests/DomainCoreTests/RegistryTestDrivers.swift`: `TestDriver` (whose `capability(_:)` returns
  `nil`), `RecordingSelectionStore` and `Gate`.
- `Sources/AppFeature/DriverHost.swift`:
  - `HomeModel` today takes `init(driver:demoIdentifiers:backend:clock:scheduler:log:readGap:)`.
  - It owns a private `DriverLifecycle` and drives `activate()`/`deactivate()` from
    `setScenePhaseActive(_:)`, `activateIfNeeded()` and `stop()`, with `pendingReactivation` and
    `activationGeneration`.
  - It reads ports with `case` patterns and seeds from `latestReading()`/`latestStatus()` through
    `runReadSequence`, honouring `pumpReadGap`.
  - `DriverHostError` and `hostError` feed the Home tab's "Unable to start data source" branch in
    `AppShell.swift`.
  - `statusRow` passes `[driver.descriptor.identifier]` as the active Drivers.
- `Sources/AppFeature/HomeScaffold.swift`: `DemoDataLabel.isVisible(activeGlucoseDriver:demoIdentifiers:)`
  returns `false` for a `nil` Driver. `DemoDataBannerRoot` reads `model.isDemo`.
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift` builds the Simulated Driver and `HomeModel`
  directly. Its `.task` calls `setScenePhaseActive(true)`, and its `onChange(of: scenePhase)`
  maps background, inactive and active.
- `Sources/DriverAPI/Capabilities/GlucoseSource.swift`: the per-activation stream contract. Read it
  before changing scene-phase behaviour.
- `Sources/DriverAPI/Capabilities/InsulinSource.swift`: `doses(since:)` is the history read used
  in the AC 4 "empty history vs no Driver" test.

### Read algorithm (`port(for:)`)

```text
guard capability.cardinality == .singleInstance  else throw .notSingleInstance(capability)
loop:
  if Task.isCancelled                              throw .cancelled
  guard let holder = slots.holder(of: capability)  else throw .noActiveDriver(capability)
  let state = lifecycles[holder]?.state ?? .notActivated
  guard state == .active || state == .degraded     else throw .holderNotRunning(holder, capability, state)
  guard let driver = drivers[holder]               else throw .noActiveDriver(capability)   // unreachable: slots only name known ids
  let port = await driver.capability(capability)   // suspension point: the actor is reentrant here
  if Task.isCancelled                              throw .cancelled
  if slots.holder(of: capability) != holder or the state left active/degraded: continue loop
  guard let port, port.capability == capability    else throw .portUnavailable(holder, capability)
  return HeldPort(holder: holder, port: port)
```

The re-check after the `await` matters. A serialized swap can complete while this read is
suspended in the old holder's `capability(_:)`, and returning the old holder's port would hand
Home a stream that is about to finish. The loop always terminates, because each pass either throws
or sees a holder that stayed stable across one `await`, and swaps are finite. Do **not** take the
operation gate: a Driver's own activation hook and the AC 4 gate test both read while an operation
holds it.

### HomeModel changes

- **Init:** `init(registry: DriverRegistry, awaitStartup: @escaping @Sendable () async -> DriverStartupOutcome,
  demoIdentifiers:, backend:, clock:, scheduler:, log:, readGap:)`. Keep the defaults on `backend`,
  `clock`, `scheduler`, `log` and `readGap`.
- **Remove:** `driver`, `lifecycle: DriverLifecycle`, `pendingReactivation`, `DriverHostError`,
  `hostError`, `fail(_:)` and every `driver.activate()`/`driver.deactivate()` call.
- **Keep, with new meaning:**
  - `lifecycleState`: the registry's state for the glucose holder, read at connect. The footer
    still derives from it. It is `.notActivated` when there is no holder.
  - `ports`, `latestGlucose`, `latestIOB`, `latestPumpStatus`, `heroState`, `isRefreshing`,
    `refresh()`, `tickInterval`, the ticker, `receive(_:)` and its future-skew guard,
    `glucoseUnit` and `pumpReadGap`.
- **Add:**
  - `public private(set) var source: HomeSource`, the enum from AC 7, `Sendable` and `Equatable`.
  - `public private(set) var slotErrors: [CapabilityReadError]`.
  - `isDemo` becomes `public private(set) var`.
  - `public func displayName(of id: DriverIdentifier) -> String?`, looked up in
    `registry.descriptors`.
- **`connect()`** (private; called from `setScenePhaseActive(true)` when not connected):
  1. Start the ticker and refresh the hero, as `activateIfNeeded()` does today.
  2. `let outcome = await awaitStartup()`.
  3. Read glucose. On `.noActiveDriver`, set `source` to `.startFailed` if
     `outcome.report.failed` holds a glucose-capable Driver, else to `.noActiveDriver`. Set
     `isDemo = false` and return. On `.cancelled`, return with `source` unchanged. On any other
     error, set `.unavailable(error)` and return.
  4. Read insulin and pump status per AC 6.
  5. Set `ports`, `lifecycleState`, `isDemo` and `source = .connected(holder)`.
  6. Run the read sequence once, as today, setting `foregroundReadSatisfied`.
  7. Attach one consumer task per stream. When a loop exits and `Task.isCancelled` is false, call
     a private `streamEnded(generation:)`. If the generation is current, it bumps the generation,
     cancels the other consumers, clears `ports`, and sets `source = .pending`.
- **`setScenePhaseActive(false)`:** cancel the ticker, clear `foregroundReadSatisfied`, bump
  nothing else. No consumer is cancelled.
- **`stop()`:** delete it, or keep it as "cancel consumers and ticker" for `deinit`-style use only
  if a test still needs it. It must never touch the Driver.
- **`statusRow`:** active Drivers are `[holder]` when connected and `[]` otherwise. The connection
  state stays `.disconnected` (SI-6, unchanged reasoning from the status row work).

### Scene phase under the registry: accepted behaviour change

Before: background deactivated the Simulated Driver, and foreground reactivated it, which emitted
a fresh sample immediately. After: the Driver keeps running. A suspended app runs no
`WallClockScheduler` ticks, so after a long background the hero shows the last reading with its
honest age and staleness badge, until the next tick (at most one `tickInterval`). 1.15's
foreground read still runs, but `latestReading()` returns what the Driver already holds. This is
correct for real Drivers: FR-26 wants the selected Driver alive in the background, and a pump
Driver deactivated on every background would drop its Bluetooth link. Record it in the Dev Agent
Record. The PM checks it on the simulator.

### App composition

```swift
init() {
    let validator = AppComposition.makeSafetyValidator()
    let simulated = SimulatedDriver(clock: SystemClock(), scheduler: WallClockScheduler(), validator: validator)
    let store = FileDriverSelectionStore(fileURL: AppComposition.driverSelectionFileURL)
    let registry: DriverRegistry
    do { registry = try DriverRegistry(drivers: [simulated], store: store) }
    catch { preconditionFailure("Driver identifiers in this build must be unique: \(error)") }
    let startup = Task { await DriverStartup.run(registry: registry, store: store, firstLaunchDefault: SimulatedDriver.identifier) }
    _model = State(initialValue: HomeModel(registry: registry, awaitStartup: { await startup.value },
                                          demoIdentifiers: [SimulatedDriver.identifier]))
    // keep startDestination and, if present, the onboarding model
}
```

- `preconditionFailure` follows `makeSafetyValidator()`'s pattern. A duplicate id is a build error,
  not a runtime state.
- `driverSelectionFileURL` is `URL.applicationSupportDirectory` + `DriverSelection/selection.json`.
  The store creates the directory. It is not the App Group container: no extension reads the
  selection.
- `Task { ... }` from the `@MainActor` `init` inherits main-actor isolation. The registry is an
  actor, so the work hops off. That is fine.
- The `SimulatedDriver.identifier` seed stands in for the "first Driver" decision. It goes away when
  onboarding or pairing chooses a Driver.

### DriverHostTests: what moves

Keep the intent of every test that still applies. Change only the construction (through the
helper) and the expectations the new ownership moves.
- **Construction only:** status row (2), refresh and read-sequence tests (`refresh*`,
  `nilGlucoseRead*`, `pumpFailure*`, `refreshBeforeActivation*`, `failedReads*`,
  `tooStaleCachedValue*`, `overlappingRefresh*`), `sceneTransitionsReadExactlyOncePerForeground`,
  `inactiveDuringActivationRead*`, `equalReadingKeepsAgeAndBadge`, hero decay, the future-skew
  tests and `canonicalSafetyValidatorCanBeConstructed`. Replace `activateIfNeeded()` with
  `setScenePhaseActive(true).value`.
- **Rewritten for the registry:**
  - `demoFlagExistsBeforeActivationAndAfterSuccess`: `isDemo` true from `initialSlots` before
    connect, and after.
  - `demoFlagRemainsOnAfterActivationFailure...` becomes "a Driver whose restore throws gives
    `.startFailed(id, .transportUnavailable)`, `isDemo == false`, and Home never shows the hero."
  - `unavailableGlucosePort...` becomes `.unavailable(.portUnavailable(id, .glucoseSource))`.
  - `unavailableInsulinPort...` becomes "glucose shown, `slotErrors` holds the insulin error, no
    IOB."
  - `repeatedActivationDoesNotReactivateHostedDriver` becomes the AC 1 count test.
  - `failedActivationDoesNotPermitRefreshReads`: no read after `.startFailed`.
- **Replaced** (they test Home-owned teardown, which no longer exists):
  `stopCancelsTicksAndAllowsReactivation`, `reactivationDuringStopKeepsTickerAndDecaysReading`,
  `stopDuringActivationDoesNotAttachLateStreams`, `secondBackgroundClearsPendingReactivation`,
  `liveUpdatesResumeAfterStopAndReactivation`, `lateBackgroundRequestActsOnLatestScenePhase`,
  `foregroundDuringBackgroundTeardownReactivates`, `foregroundReadRunsWhileTornDownReadIsStillBlocked`,
  `cancelledActivationReadStillAttachesStreams`. Replace them with:
  - background keeps the consumers attached: a sample yielded while in the background is
    received;
  - background then foreground runs one read and no activation;
  - background stops hero ticks and foreground restarts them;
  - a registry `deactivate` of the holder ends the stream, Home goes `.pending` with `ports == nil`,
    and the next foreground gives `.noActiveDriver`;
  - a glucose-only Driver plus no insulin holder: connected, `latestIOB == nil`, `slotErrors`
    empty;
  - the AC 5 known-limit path gives `.unavailable(.holderNotRunning(id, .glucoseSource, .failed))`;
  - `HomeSourceMessage` for each state: exact strings and identifiers.
- `HostTestDriver` keeps its id `com.glycemicgpt.simulated`, so `demoIdentifiers` works unchanged.
  Its streams must finish on `deactivate()` for the stream-end test. If they do not today, add that
  to the double only.

### Architecture compliance

- **AD-16:** one lifecycle owner. The registry brackets every hook with a legal transition, and
  Home never touches one.
- **AD-13:** every failure is typed and kept: `CapabilityReadError`, `DriverStartupOutcome` and
  `HomeModel.source`. Nothing substitutes an empty value for an unknown one.
- **AD-3:** DomainCore still depends on SafetyCore and DriverAPI only. AppFeature gains the
  DomainCore edge the spine declares. Drivers cannot see either.
- **SI-6:** Home never shows "no readings yet" when nothing is reading, and never shows a Driver as
  connected that did not start.
- **FR-26:** restore starts in `App.init`, so it also runs on a background relaunch. Core Bluetooth
  restoration (AD-11) arrives with the pump Driver work.

### Out of scope (later work; do not build)

- **1.12c, FR-25: deactivation confirmation, plus a Drivers screen.**
  - Decision recorded for 1.12c: a minimal Drivers screen as a **detail route under Settings**
    (`AppRoute.drivers`, next to `AppRoute.licenses`), not more text on the Settings placeholder.
  - Why: FR-166 makes Drivers a Settings section. The confirmation is per Driver, so it needs a
    list of rows (`DriverCatalog.rows(state:)` / `DriverRow` already model them). The
    `NavigationLink(value:)` pattern already exists for Licenses. A detail route can later become
    the real Settings section without moving the confirmation logic.
  - The model gate: deactivation only through a confirm step. Copy: "Deactivate Driver" /
    "Deactivating this Driver may stop glucose monitoring, insulin tracking, or other services it
    provides. Are you sure?" / "Deactivate" / "Cancel". After confirming, Home reconnects through
    this story's stream-end path.
- **1.12c, FR-29:** per-Driver namespaced settings (key regex, per-Driver key-to-type table,
  locked-device access, survives deactivation). It pairs with FR-25's "settings read back unchanged
  after reactivation".
- **1.12c or 1.12d, FR-34:** the bounded best-effort event channel (256 per subscriber,
  drop-oldest, no replay, Driver id on every event, platform-only events not constructible by a
  Driver). There is no publisher or subscriber yet, so it can ship last.
- The Coverage Claim's wording for "no active Driver" (prd §5.4) and the dashboard's no-Driver
  design (§5.3). This story's Home message is the interim honest state.
- Core Bluetooth restoration, pairing and a second real Driver.

### Testing standards

- Swift Testing, `@MainActor` for `HomeModel` tests. No sleeps; synchronize on gates and
  `eventually`, as `DriverHostTests` does.
- AppFeatureTests cannot depend on `SimulatedDriver` or `DomainCoreTests`. Write a small in-memory
  store double inside `AppFeatureTests` rather than importing the DomainCore one.
- `withCheckedContinuation` is not cancellation-aware. Release every gate a test closes.
- Known flake: `WallClockSchedulerTests`. You may re-run once; record it if you do.

### Project structure notes

- New:
  - `Sources/DomainCore/CapabilityRead.swift`
  - `Sources/AppFeature/DriverStartup.swift`
  - optionally `Sources/AppFeature/HomeSource.swift`
  - `Tests/DomainCoreTests/CapabilityReadTests.swift`
  - `Tests/AppFeatureTests/DriverStartupTests.swift`
- Modified:
  - `Package.swift`
  - `Sources/DomainCore/DriverRegistry.swift`
  - `Sources/DomainCore/DriverSelectionStore.swift`
  - `Sources/AppFeature/DriverHost.swift`
  - `Sources/AppFeature/AppShell.swift`
  - `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
  - `Tests/DomainCoreTests/RegistryTestDrivers.swift`
  - `Tests/AppFeatureTests/DriverHostTests.swift`
  - `Tests/SafetyCoreTests/PackageManifestTests.swift`
- Branch from `develop` after #20 merges, for example `feat/registry-composition`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 1.12]
- [Source: prds/prd-ios-unofficial-2026-08-01/prd.md FR-23, FR-25, FR-26, FR-28, FR-29, FR-33
  (:675), FR-34 (:688), FR-166; the §5.2 note on Android's empty-list adapter defect (:780)]
- [Source: ARCHITECTURE-SPINE.md: module graph (AppFeature → DomainCore → DriverAPI, SafetyCore),
  AD-2, AD-3, AD-11, AD-13, AD-16]
- [Source: 1-12a-driver-registry-slot-derivation-and-persisted-selection.md: "Out of scope", the
  Dev Agent Record's known limits, and the PM decisions]
- [Source: android-unofficial/app/src/main/java/com/glycemicgpt/mobile/plugin/PluginRegistry.kt
  (`restoreActivePlugins`, `updateStateFlows`) and the deprecated registry adapters that return an
  empty list with no active Driver, which FR-33 exists to rule out]

## Dev Agent Record

### Agent Model Used

GPT-6 (Amelia), cycles 1–2. Finished outside the sandbox on Claude Opus 5.5 (compile fixes, test tightening, all gates, simulator check).

### Debug Log References

- `swift test --filter CapabilityReadTests` could not compile the manifest because the sandbox denied writes to the Clang module cache outside the worktree.
- `swift test --disable-sandbox --filter CapabilityReadTests` hit the same denial.
- `swiftc -frontend -parse` passed on the changed Swift source and test files; this does not type-check them.
- Cycle 2: `swift build` and `swift test` stopped during manifest compilation because the sandbox denies writes to `~/.cache/clang/ModuleCache`. Redirecting module caches and disabling SwiftPM's sandbox passed that step but then GRDB could not be fetched because `github.com` did not resolve.
- Cycle 2: `bash scripts/guards/safety_guards.sh`, its `--self-test` (75 cases), `bash scripts/guards/driver_guards.sh`, its `--self-test` (68 cases), and `bash scripts/ci-local.sh --self-test` passed.
- Cycle 2: the package `xcodebuild test` command exited 66: CoreSimulatorService was unavailable and the directory was not recognized as a package. The app `xcodebuild build` command exited 74 during package resolution because the module cache was unwritable. The simulator screenshot could not be captured in this sandbox.

- Finishing pass (outside the sandbox): `swift build --build-tests` failed in the two in-memory store doubles (`HostSelectionStore.save`, `StartupStore.load`). `NSLock.withLock` is untyped-rethrows, so a `throw` of `DriverSelectionStoreFailure` inside it surfaced as `any Error`. Fixed by using `lock()`/`defer unlock()`, matching `RecordingSelectionStore`.
- Finishing pass gates, all exit 0: `swift build`; `swift build -c release`; `swift test` twice (398 tests in 48 suites each run, no flake re-run needed); `safety_guards.sh` and `--self-test` (75 cases); `driver_guards.sh` and `--self-test`; `ci-local.sh --self-test`; package `xcodebuild test` on iPhone 17 / iOS 26.5; app Debug `xcodebuild build`; app Release build for the simulator.

### Completion Notes List

- Safety review fixes (PR #23):
  - A transient selection-load failure (`.unavailable`, e.g. a background launch before first unlock) now maps to `HomeSource.selectionDeferred`, shown as "not running, will retry" (`home.source-deferred`), never "No glucose source". The next foreground re-runs restore through `DriverStartup.retryRestore`, which never seeds, and then connects. `connect()` stays single-flight. Test: `transientSelectionLoadFailureShowsWillRetryAndForegroundRestores`.
  - A glucose-holder change clears `latestGlucose`, `latestIOB` and `latestPumpStatus`, which also resets the ordering guard. It recomputes `isDemo` and refreshes the hero. A failed read on the same holder still keeps the cache (AD-13). When a stream ends while the scene is active, Home reconnects at once. Test: `holderChangeClearsPreviousValuesAndDemoLabel`.
  - A failed first-launch seed shows `HomeSource.seedFailed` ("didn't start", `home.source-failed`). `DriverStartupOutcome.seedTarget` names the Driver that was tried. Test: `failedFirstLaunchSeedShowsDidntStart`.
  - `.pending` now shows a neutral "Starting…" message (`home.starting`) instead of the empty dashboard. Tests: `pendingStartupShowsStartingMessage` and `sourceMessagesCoverEveryState`.
  - Dead ports: `DriverRegistry.changes()` yields after every lifecycle transition and selection save. `HomeModel` checks its connection on each change, and once more at the end of `connect()`. It drops the connection (generation bump, consumers cancelled) when the glucose holder is no longer the running slot holder, so a Driver whose streams never finish cannot leave Home `.connected`. Tests: `teardownWithoutStreamEndDropsConnection`, `teardownDuringConnectReadDropsLateWritesAndAttachment` (no late pump write, no glucose read, no attachment), and `changesYieldAfterLifecycleTransitionAndSave`. Stream consumers also stop delivering once their generation is stale.
  - `registryTeardownDropsPortsAndReconnectsToEmptySlot` now expects the immediate reconnect to report `.noActiveDriver`.

- Finishing pass:
  - Fixed the typed-throws compile errors in the two AppFeatureTests store doubles (see Debug Log).
  - `HomeSourceMessage.make` no longer returns `nil` for an unexpected `.unavailable` error. `.unavailable(.noActiveDriver | .notSingleInstance | .cancelled)` now shows "No glucose source" instead of falling through to the dashboard's "--". A glucose read never produces these, but the mapping now fails closed and is exhaustive.
  - `connect()` no longer returns silently (leaving `source == .pending`) if the held glucose port is not a glucose port. It sets `.unavailable(.portUnavailable(holder, .glucoseSource))`. The registry already rules this out; this keeps the state typed if that ever changes.
  - The three Home-state tests now each assert the model state and the user-facing message: `emptySelectionShowsNoGlucoseSource` (`home.no-glucose-source`), `permanentRestoreFailureShowsStartFailed` (`home.source-failed`, "didn't start"), and `transientRestoreFailureShowsNotRunningWillRetry` (renamed from `deferredRestoreDoesNotPermitRefreshReads`; `home.source-deferred`, `isDemo == false`, no port reads). `sourceMessagesCoverEveryState` also pins the fail-closed fallback.
  - Checked that the replaced HomeModel-teardown tests are gone and that their intent is covered through the registry: AC 1 count (`sceneTransitionsDoNotReactivateRegistryDriver`), background delivery (`backgroundKeepsStreamAndForegroundReadsWithoutRestart`), ticker (`backgroundStopsTickerAndForegroundRestartsIt`), registry teardown and reconnect (`registryTeardownDropsPortsAndReconnectsToEmptySlot`), and the known limit (`failedRemovalSaveKeepsFailedHolderVisible`).
  - Simulator (iPhone 17, iOS 26.5, Release build): after a fresh install launched with `-onboardingComplete YES`, Home showed the DEMO DATA banner, a hero of 103 mg/dL "just now" and IOB 4.58u. `Library/Application Support/DriverSelection/selection.json` held `{"activeDriverIDs":["com.glycemicgpt.simulated"],"version":1}`, so first-launch seeding went through the registry. After about 40 s in the background (Settings in front) and a return, the same process (same pid, not relaunched) still showed 103 "just now", which is the correct age for a sample under a minute old. The Driver was not restarted. Screenshots were taken locally and are not stored in the repository.
  - Final diff, reviewable: sources (including `Package.swift` and the app target) +285 / −137 = 422 lines; tests +494 / −238 = 732 lines; 1,154 in total, within the raised ceiling of about 1,400.
  - Accepted behaviour change, as specified: going to the background no longer stops the Simulated Driver. It only cancels the hero ticker.

- Cycle 1 left DomainCore typed slot reads, first-launch startup, app registry composition, and Home registry consumption partially implemented; Home tests and gates remained.
- Cycle 2 completed the Home test migration and added coverage for empty glucose selection, permanent start failure, transient deferred start, a failed removal save, optional slots, background stream delivery, ticker restart, registry teardown, and every Home message. A read test now verifies that another Driver's blocked activation does not block a held port read. The Swift files parse; type checking remains blocked by package resolution.
- Reviewable source and test diff is 1,136 changed lines (429 additions and 376 deletions in tracked code, plus 331 lines in new files), within the PM's raised ceiling of about 1,400. (Superseded by the finishing pass, which ran all gates.) At this point five of nine prescribed gates had passed; four could not run to completion in this sandbox, and no passing build or test suite was claimed.
- Background scene handling now leaves the registry Driver running and keeps Home stream consumers attached. The hero can show the previous sample with its true age until the next Driver tick.
- Invented copy — maintainer review before public TestFlight (final list; the finishing pass added no copy): "No glucose source"; "No active Driver is providing glucose readings, so there is nothing to show here."; "Unable to start data source"; "didn't start. Restart the app to try again."; "isn't providing glucose readings. Restart the app to try again."; "Data source not running"; "isn't running. It will retry when the app starts again."; "Starting…"; "Connecting to your data source."; "Your data source isn't running yet. It will retry when you return to the app." (the last three added by the safety review fixes)
- Reviewable source and test diff reached approximately 996 added/deleted lines before remaining Home tests. The story's budget instruction requires a maintainer decision to raise the budget or split scope. (Superseded by the finishing pass, which ran all gates.) At this point all nine frontmatter gates were still unrun.

- Open question for the PM: rename this file to match its narrowed scope
  (for example `1-12b-registry-composition-and-no-active-driver-error.md`)? It keeps the requested
  name until the launcher stamp is created.

### File List

- `Package.swift`
- `Sources/DomainCore/CapabilityRead.swift`, `DriverRegistry.swift`, `DriverSelectionStore.swift`
- `Sources/AppFeature/DriverStartup.swift`, `DriverHost.swift`, `AppShell.swift`
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
- `Tests/DomainCoreTests/CapabilityReadTests.swift`, `RegistryTestDrivers.swift`
- `Tests/AppFeatureTests/DriverStartupTests.swift`, `DriverHostTests.swift`
- `Tests/SafetyCoreTests/PackageManifestTests.swift`

### PM decisions on drafting open points (2026-11-01)
- **Invented copy is accepted for internal demo builds.** That covers the monitoring-limits warning, the Bluetooth usage string and the Home "no glucose source" / "didn't start" messages. List every invented string in the Dev Agent Record under "Invented copy — maintainer review before public TestFlight".
- **1.12 naming.** The file is named for its actual scope, `1-12b-registry-owns-driver-lifecycle-and-no-active-driver-error`. Deactivation confirmation, per-Driver settings and the event channel go to `1-12c` (and `1-12d` if needed).
- **Demo hero after returning from background.** It is acceptable for the hero to show a reading up to 5 minutes old after the app comes back, provided the age caption and freshness tier show the true age. The foreground read on return reads the latest sample. Never re-timestamp a sample to look fresh.
- **Critical alert option in the notification request.** Requesting `.criticalAlert` before Apple grants the entitlement is accepted. The option has no effect until the entitlement exists. Add a doc comment saying so.

### PM note before dispatch (2026-11-01)
- PR #20 merged with two refinements you must build on:
  - `DriverFailure.isTransient`. On restore, a transient failure keeps the selection, and the Driver appears in `RestoreReport.deferred`.
  - A deferred Driver keeps its slot.
- Home must show a deferred Driver honestly, as "not running, will retry", distinct from "didn't start" (a permanent failure) and from "no glucose source". Add an AC-level test for each of the three states.

### PM decision on the budget escalation (2026-11-01)
- **Raise the budget, don't split.** About 370 of the roughly 1,000 changed lines are deletions or replacements of the old HomeModel driver-ownership tests, so the net new reviewable code is far smaller. Splitting midway through moving lifecycle ownership would leave `develop` in a half-migrated state. That is worse to review than one coherent change. The new ceiling is about 1,400 changed lines, counting additions and deletions together.
- **Finish in this cycle:** migrate the remaining Home tests; add the three Home-state tests (no glucose source / didn't start / not running, will retry); keep every AC; get all nine gates passing. The launcher re-runs the gates outside your sandbox, so finish the code and tests from source.
- Keep the file name as it is. Its scope is unchanged apart from the budget.
- Known pitfalls still apply: `return switch`, `async` on awaiting tests, bind key-path `#expect` to a `let`, `#if os(iOS)` for iOS-only APIs, and no literal that equals a safety constant.
- budget: CONTINUATION_REQUIRED sha256:02d1e82fabf4e3ab597c76be287d133eba2772f824679bb237678c39541ad2b6 cycle 2 2026-11-02T00:18:24Z
