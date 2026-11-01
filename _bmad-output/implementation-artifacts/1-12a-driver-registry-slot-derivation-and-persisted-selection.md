---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-12a-driver-registry-slot-derivation-and-persisted-selection.md.stamp.json
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

Status: review

> **SPLIT. This file is Story 1.12a only: the registry, slot derivation and persistence.**
> The whole of epics.md Story 1.12 is about 1,800 reviewable lines, well over the 800-line
> budget. This file keeps the platform core. A later 1.12b gets the rest: app composition
> (HomeModel and the app consuming the registry), the deactivation confirmation UI (FR-25),
> the FR-33 distinguishable error, per-Driver settings (FR-29) and the event channel (FR-34).
> 1.12b is itself near the budget and may need a 1.12c (see "Out of scope").
> The file keeps the name `1-12-...` because the launcher stamp is keyed to that path.

# Story 1.12a: Driver registry, derived slots and persisted selection

<!-- Planning note (for the maintainer): depends on 1.4 (DriverAPI, catalog, lifecycle) and 1.5
(Simulated Driver), both on develop @ b9f85cd. Estimate: ~800-900 reviewable lines over ~11 files,
about 55% tests, which is at the edge of the budget. If review wants it smaller, the clean cut is
1.12a-i (Capability cardinality + DriverSlots + selection store, ~450) and 1.12a-ii (the registry
actor, ~450). Adds one internal SwiftPM target (`DomainCore`, already in the spine's module graph)
and edits Package.swift for it. No external dependency, no lockfile change, no GRDB schema migration.
Touches DriverAPI with one additive, read-only classification. No dosing, alert floor, ingestion
mapper, safety_validation, auth, CI workflow or CODEOWNERS change. Does NOT touch AppFeature or the
app target, which keeps it clear of the in-flight 1.15 change to HomeModel. Route: not chosen here;
the PM routes via /v1/route. The planning context is platform and safety work, so expect FR-23's
"slot never empty" rule to get reviewer pressure. -->

## Story

As a Builder,
I want my Driver choice to survive relaunch and upgrade,
so that a background wake reconnects without me opening the app.

## Acceptance Criteria

From epics.md Story 1.12 (FR-23, FR-24, FR-25 model half, FR-26, FR-27, FR-28 activation half,
FR-30 derivation) with the PRD's testable consequences. The epic cites AD-2 for "the derived slot
is never empty". In the architecture spine, AD-2 and AD-3 are the module-topology and
dependency-direction rules. They decide **where** this code lives (AC 9). The never-empty rule
itself comes from FR-23 and FR-30.

1. **Every Capability is classified single-instance or multi-instance, exhaustively (FR-30,
   FR-23, FR-24).** `DriverAPI` gains `CapabilityCardinality` (`singleInstance`, `multiInstance`)
   and `Capability.cardinality`, written as an exhaustive `switch` with no `default`. Single-instance
   capabilities are `glucoseSource`, `insulinSource`, `pumpStatus` and `doseCategoryProvider`.
   Multi-instance capabilities are `bgmSource` and `dataSync`. This matches Android's
   `PluginCapability.SINGLE_INSTANCE` / `MULTI_INSTANCE` (Android's calibration member does not
   exist here). A test pins all six.

2. **Slots are derived from the active set, never stored (FR-23, FR-30).** `DriverSlots.derive(
   active:descriptors:)` is a pure, total function:
   - Input: a set of active Driver ids and the descriptors of the Drivers this build contains.
     An active id with no descriptor contributes nothing.
   - For each single-instance Capability, the holder is the qualifying active Driver with the
     **lowest `identifier.rawValue`** under plain `String` `<`. It is `nil` if no active Driver
     qualifies.
   - For each multi-instance Capability, the members are every qualifying active Driver, sorted by
     raw value.
   - `pump` is the lowest-id active **device** Driver declaring `pumpStatus` or `insulinSource`.
     `glucose` is the lowest-id active device Driver declaring `glucoseSource`. A device Driver is
     one whose transport is not `.network`. A network-transport Driver never occupies either
     device slot.
   - No slot table exists anywhere. Nothing stores a slot; every slot read derives.
   - Determinism: the same active set derived repeatedly, with the descriptor array given in
     several different orders, yields an identical `DriverSlots` every time.

3. **Activation runs the incoming hook first, then persists, then evicts (FR-23).**
   `DriverRegistry.activate(_:)`:
   - Unknown id → throws `DriverRegistryError.unknownDriver(id)`. No hook runs and nothing is
     written.
   - Already running (lifecycle `active` or `degraded`) → returns with no hook call and no write.
     This makes it idempotent.
   - Otherwise, in this order: compute the conflicts from the **persisted** set (every other known,
     persisted Driver that shares one of the incoming Driver's single-instance capabilities); move
     the lifecycle to `activating`; call `activate()`; move to `active`; add the id to the
     persisted set and save it durably; then, for each conflict in raw-id order, remove it from the
     persisted set, save, and tear it down.
   - The derived single-instance slot is **never empty** across a swap. A test records the derived
     slots at every saved set and from inside the incoming Driver's activation hook, and asserts
     the contested slot is non-nil at every observation.
   - Activating a Driver that claims several single-instance capabilities evicts every previous
     holder in one call. A three-capability Driver replaces a Driver holding glucose, insulin and
     pump status, and it also replaces two different Drivers that each hold one of them.
   - A throwing hook → throws `.activationFailed(id, failure)`. The lifecycle ends `failed`, no
     conflict is evicted, and no write happens, except that a stale persisted entry for that id is
     removed (FR-28).
   - If the save after a successful hook fails, the registry tears the incoming Driver back down
     and throws `.persistenceFailed`. The persisted set is unchanged.
   - Returns the evicted ids (`@discardableResult`).

4. **Multi-instance capabilities coexist (FR-24).** Activating two BGM-source Drivers and a
   data-sync Driver while a pump Driver is active evicts nothing. The single-instance slots and
   the `pump` and `glucose` slots stay unchanged, and both BGM Drivers appear in the BGM members.
   Deactivating one multi-instance member leaves the others in place.

5. **Deactivation removes the id durably, then tears down, and never clobbers a newer claim
   (FR-25, model half).** `DriverRegistry.deactivate(_:)`:
   - Unknown id → `.unknownDriver(id)`.
   - Not persisted and not running → returns with no hook call and no write. This makes it
     idempotent.
   - Otherwise it removes the id from the persisted set and saves. Only then, if the lifecycle is
     `activating`, `active`, `degraded` or `failed`, it moves the lifecycle to `deactivating`,
     calls `deactivate()`, and moves to `notActivated`.
   - The registry stores nothing but the id set, so deactivation cannot touch credentials or
     per-Driver settings. A test reads the selection file after deactivation and sees only ids.
   - Race: `activate(B)` (conflicting with A, with B's hook held on a gate) runs concurrently with
     `deactivate(A)`. When both finish, the persisted set is exactly `{B}`.
   - The user-facing confirmation is **not** built here. It goes to 1.12b (see Dev Notes).

6. **Operations are serialized (FR-23).** No two `activate`, `deactivate` or `restore` calls
   interleave. A test holds Driver A's activation hook on a gate, starts a second activation, and
   asserts that the second Driver's hook has not been called until the gate opens. Reads such as
   `slots` and `lifecycleState(of:)` are not blocked by the serializer.

7. **The selection persists durably in a small protected file (FR-26).** `FileDriverSelectionStore`
   behind the `DriverSelectionStore` protocol:
   - `load()` and `save(_:)` are **synchronous** and use typed throws. `DriverRegistry.init` loads
     the set synchronously, so slots can be derived before any activation hook runs.
   - A missing file reads as the empty set (first launch). An unreadable file, or one with an
     unknown format version, is a typed failure. It is **never** read as the empty set.
   - `save` writes JSON `{"activeDriverIDs":[…sorted…],"version":1}` with sorted keys, atomically
     (`Data.WritingOptions.atomic`). On iOS and watchOS it also writes with
     `.completeFileProtectionUntilFirstUserAuthentication`, the same Data Protection class AD-6
     gives the database, so a locked-device background wake can read it.
   - It creates its parent directory if that is missing.
   - Durability: after `activate` or `deactivate` returns, a **new** store instance at the same
     URL loads the new set.
   - If the initial load failed, every `activate` and `deactivate` throws
     `.selectionUnavailable(...)`, `restore` reports the failure, and the file stays byte-for-byte
     unchanged. A failed read is never followed by a write that would erase the Builder's choice.

8. **Restore at launch (FR-26, FR-27, FR-28).** `DriverRegistry.restore() async -> RestoreReport`:
   - For each persisted id in raw-value order:
     - If this build has no Driver with that id, it is reported as `absentFromBuild` and left in
       the persisted set **untouched**. It survives every later `save` the registry makes, so
       re-enabling the Driver in a later build restores the choice.
     - If the Driver's activation hook throws, the id is reported as `failed` with its
       `DriverFailure`, its lifecycle is `failed`, and the id is removed from the persisted set.
       The registry reports this and does not retry.
     - Otherwise the id is reported as `restored`.
   - A second `restore()` call does not call any hook a second time.
   - The restore path has no Backend, session or network input. `DomainCore` cannot depend on
     anything that has one (AC 9), and the tests run it with nothing but a temp-directory store.
   - A test simulates a relaunch: registry 1 activates and is dropped; registry 2 is built with
     **new** Driver instances and a new store at the same URL; `restore()` brings the same set back
     up.

9. **Placement: a new `DomainCore` target, as the spine's graph declares it (AD-1, AD-2, AD-3,
   AD-4, AD-13, AD-16).**
   - `Sources/DomainCore/` depends on exactly `["SafetyCore", "DriverAPI"]`.
   - `DomainCoreTests` depends on `["DomainCore", "DriverAPI", "SafetyCore"]`.
   - A `DomainCore` library product is added.
   - No Driver target depends on `DomainCore`.
   - `AppFeature`, the app target and `Persistence` are not changed.
   - `PackageManifestTests` is updated: the Sources directory list, the target enumeration, and a
     new exact-dependency test for `DomainCore`.
   - The registry is an `actor`. It is the only owner of these Drivers' lifecycles, through
     `@_spi(DriverPlatform) import DriverAPI`.

10. **Gates and budget.** Every gate in the frontmatter passes. Report the reviewable diff size in
    the Dev Agent Record. If it is past ~900 lines, write a NEEDS-HUMAN line rather than trimming
    tests.

## Tasks / Subtasks

- [ ] Task 1: Capability cardinality in DriverAPI (AC 1)
  - [ ] In `Sources/DriverAPI/Capability.swift`, add
        `public enum CapabilityCardinality: String, CaseIterable, Hashable, Sendable { case singleInstance, multiInstance }`
        and `public var cardinality: CapabilityCardinality` on `Capability`, as an exhaustive
        switch with no `default`. Use one or two lines of doc comment.
  - [ ] In `Tests/DriverAPITests/CapabilitySetTests.swift`, add one test that pins all six
        classifications (the four single-instance and the two multi-instance).
- [ ] Task 2: package wiring (AC 9)
  - [ ] In `Package.swift`, add the `DomainCore` product, target and test target as in AC 9, each
        with `swiftSettings: [.swiftLanguageMode(.v6)]` like its neighbours. Update the header
        comment, which today says DomainCore "arrive[s] with [its] own work". Do not touch
        `dependencies:` or any other target.
  - [ ] In `Tests/SafetyCoreTests/PackageManifestTests.swift`:
    - add `"DomainCore"` to the Sources list (sorted)
    - add `"DomainCore", "DomainCoreTests"` to the enumeration superset
    - add `@Test("DomainCore depends on exactly SafetyCore and DriverAPI")`, modelled on
      `appFeatureDependencies`, asserting
      `arguments.contains("dependencies:[\"SafetyCore\",\"DriverAPI\"]")`
- [ ] Task 3: `DriverSlots` derivation (AC 2)
  - [ ] Create `Sources/DomainCore/DriverSlots.swift`. A `public struct DriverSlots: Equatable,
        Sendable` holds:
        - `singleInstance: [Capability: DriverIdentifier]`, with entries only for held capabilities
        - `multiInstance: [Capability: [DriverIdentifier]]`, sorted, with entries only for
          non-empty capabilities
        - `pump: DriverIdentifier?` and `glucose: DriverIdentifier?`
        - `holder(of:) -> DriverIdentifier?` and `members(of:) -> [DriverIdentifier]` helpers
        - `public static func derive(active: Set<DriverIdentifier>, descriptors: [DriverDescriptor]) -> DriverSlots`

        In `derive`, filter the descriptors to the active ids, sort by `identifier.rawValue`, then
        take the first qualifying descriptor for each single-instance slot. "Device" is an
        exhaustive switch over `DriverTransport` (`.bluetoothLowEnergy, .inProcess` → true,
        `.network` → false), not `!= .network`, so a new transport fails to compile until someone
        classifies it.
  - [ ] Create `Tests/DomainCoreTests/DriverSlotsTests.swift`:
    - empty set → every slot is nil or empty
    - lowest raw id wins a contested single-instance capability
    - multi-instance members are sorted
    - a network Driver declaring `glucoseSource` gets no `glucose`/`pump` slot
    - an active id with no descriptor contributes nothing
    - determinism: the same input with the descriptor array forward, reversed and rotated gives
      an equal result each time, checked over a loop of repetitions
- [ ] Task 4: selection store (AC 7)
  - [ ] Create `Sources/DomainCore/DriverSelectionStore.swift`:
    - the protocol `DriverSelectionStore: Sendable` with
      `func load() throws(DriverSelectionStoreFailure) -> Set<String>` and
      `func save(_ ids: Set<String>) throws(DriverSelectionStoreFailure)`. The ids are **raw
      strings**, so an id that this build does not know (or that no longer parses) round-trips
      untouched.
    - `public enum DriverSelectionStoreFailure: Error, Hashable, Sendable` with cases
      `unreadable(detail: String)`, `unwritable(detail: String)` and
      `unsupportedVersion(Int)`
    - `public struct FileDriverSelectionStore: DriverSelectionStore` with `init(fileURL: URL)`
      and `static let formatVersion = 1`. It uses a private `Codable` struct for the file.
  - [ ] Create `Tests/DomainCoreTests/FileDriverSelectionStoreTests.swift`. Use a unique temp
        directory per test and remove it afterwards:
    - a missing file loads as empty
    - save then load with a new instance round-trips
    - the written JSON has sorted ids
    - garbage bytes → `unreadable`
    - version 2 → `unsupportedVersion(2)`
    - a missing parent directory is created
- [ ] Task 5: the registry (AC 3, 4, 5, 6, 8)
  - [ ] Create `Sources/DomainCore/DriverRegistry.swift` with
        `@_spi(DriverPlatform) import DriverAPI`. It declares:
    - `public enum DriverRegistryError: Error, Hashable, Sendable` with cases
      `duplicateIdentifier(DriverIdentifier)`, `unknownDriver(DriverIdentifier)`,
      `activationFailed(DriverIdentifier, DriverFailure)`,
      `selectionUnavailable(DriverSelectionStoreFailure)`,
      `persistenceFailed(DriverSelectionStoreFailure)` and `lifecycle(DriverFailure)`
    - `public struct RestoreReport: Equatable, Sendable` with:
      - `restored: [DriverIdentifier]`
      - `absentFromBuild: [String]`
      - `failed: [RestoreFailure]`, where `RestoreFailure` is a struct of id and `DriverFailure`
      - `selectionFailure: DriverSelectionStoreFailure?`

      Every list is sorted by raw id.
    - `public actor DriverRegistry` with:
      - `public init(drivers: [any Driver], store: any DriverSelectionStore) throws(DriverRegistryError)`.
        It throws on a duplicate id, loads the set synchronously, and records a load failure
        instead of throwing it.
      - `public var slots: DriverSlots`, derived from `persisted ∩ known ids` on every read
      - `public func lifecycleState(of: DriverIdentifier) -> DriverLifecycleState?`
      - `public var persistedSelection: Set<String>`, for tests and the later UI
      - `@discardableResult public func activate(_: DriverIdentifier) async throws(DriverRegistryError) -> [DriverIdentifier]`
      - `public func deactivate(_: DriverIdentifier) async throws(DriverRegistryError)`
      - `public func restore() async -> RestoreReport`
  - [ ] Serialize the three mutating operations with the gate in Dev Notes.
  - [ ] Never call a Driver hook without a legal lifecycle transition around it. If `advance`
        throws, surface `.lifecycle(failure)`. Never trap.
- [ ] Task 6: registry tests (AC 3, 4, 5, 6, 7, 8)
  - [ ] Create `Tests/DomainCoreTests/RegistryTestDrivers.swift` with the test-only doubles: a
        configurable `actor TestDriver: Driver`, an in-memory `RecordingSelectionStore`, and a
        `Gate` actor. See Dev Notes. These live **only** in the test target and are never added
        to `DriverCatalog` or `Sources/`.
  - [ ] Create `Tests/DomainCoreTests/DriverRegistryTests.swift`, with one test for each bullet
        under AC 3, 4, 5, 6 and 8 and the durability and refusal bullets of AC 7. The minimum list
        is in Dev Notes under "Test list".
- [ ] Task 7: run every gate, record results and diff size (AC 10)

## Dev Notes

### Known pitfalls

- The worker cannot compile, so write carefully. A `switch` that follows any statement in a function or getter needs `return switch`.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs in `#if os(iOS)`.
- Every SF Symbol name needs a test that it exists on UIKit and AppKit.
- Small coloured text needs a contrast ratio of at least 4.5:1. Use the existing light/dark palette in `StatusRowView`.
- Never write a numeric safety constant inline, and never disguise one (for example `29 * 2`). New constants go in `SafetyConstants` and `CANON_SPEC`.
- Swift 6 strict concurrency. Use typed throws where the module already does.
- Code comments must not mention stories, epics, AC numbers, agents or cycles.

This change has no UI, so the SF Symbol and contrast items do not apply. The macOS item does
apply: `.completeFileProtectionUntilFirstUserAuthentication` must sit inside
`#if os(iOS) || os(watchOS)`, and macOS writes `.atomic` only.

### Read first (rules of the road)

- **Edit only these paths:**
  - `Package.swift`
  - `Sources/DriverAPI/Capability.swift`
  - `Sources/DomainCore/**` (new)
  - `Tests/DomainCoreTests/**` (new)
  - `Tests/DriverAPITests/CapabilitySetTests.swift`
  - `Tests/SafetyCoreTests/PackageManifestTests.swift`
  - this story file's Dev Agent Record

  Do **not** edit:
  - `Sources/AppFeature/**`
  - `Apps/**`
  - `Sources/Persistence/**`
  - `Sources/Drivers/**`
  - `Sources/SafetyCore/**`
  - `DriverCatalog.swift`
  - guards, CI files or `Package.resolved`

  If you need something outside this list, write a NEEDS-HUMAN line in the Dev Agent Record.
- **No therapeutic write, ever (SI-1).** The registry starts and stops Drivers. It reads nothing
  from a device and writes nothing to one.
- **Comments are brief.** One to three lines per declaration. This change is at the edge of the
  diff budget, and long doc essays are what push it over. AD-x, SI-x and FR-x ids are fine in
  comments.
- **Scratch files only under `.build/` in your worktree. One operation per Bash call.** Your
  sandbox likely cannot run Swift or the Simulator. That is expected; the launcher re-runs every
  gate. `swiftc -frontend -parse <file>` is a useful syntax check if it runs.

### Where the registry lives, and why (AD-1/2/3/4/13/16)

- **Not DriverAPI.** Every Driver imports DriverAPI. A file-writing selection store there hands
  every Driver its own storage path, which AD-3 exists to prevent. The lifecycle-driving code
  would also sit in the module whose SPI exists to keep Drivers away from it. On top of that,
  `driver_guards.sh` symbol-scans DriverAPI for `resume` and `suspend`, and the serializer below
  calls `continuation.resume()`. DomainCore is outside `SCAN_DIRS`, so the call is legal there.
- **Not AppFeature.** AppFeature is the `@MainActor` presentation adapter. FR-26's restore runs
  on a background Bluetooth relaunch with no scene. AD-13 names `DomainCore` as the owner of
  recovery for Driver failures. AppFeature is also being changed by the in-flight 1.15 work.
- **`DomainCore`, a new target.** The spine's graph already declares `DomainCore → DriverAPI,
  SafetyCore` and `AppFeature → DomainCore`, and AD-4 binds DomainCore to actor isolation. No
  Driver may depend on it (AD-3), so no Driver can reach the registry or the selection file. The
  `AppFeature → DomainCore` edge is added in 1.12b, when the app starts using it.
- **SPI import is allowed here.** The driver guard forbids `@_spi` only under `Sources/Drivers/`.
- **Rule D (consumer casts) applies to DomainCore.** Do not write `as?`, `as!` or `is` against
  `Driver`, `CapabilityPort` or any Capability port anywhere under `Sources/DomainCore/`. Nothing
  here needs a cast, because the registry reads `descriptor` and calls `activate`/`deactivate`.

### Where the selection is stored, and why (FR-26, AD-6, AD-9)

The store is a small atomic JSON file with Data Protection `CompleteUntilFirstUserAuthentication`.
It is **not** the GRDB `LocalStore` from the encrypted local store work
(`Sources/Persistence/LocalStore.swift`):
- `LocalStore.open` is `async` and opens a `DatabasePool`. FR-26 wants the selection read
  synchronously during launch.
- A new table would be a schema migration. Migrations are a protected path that needs the
  maintainer's sign-off, and storing six short strings does not justify one.
- At-rest protection is the same either way. AD-6 gets the database's protection from iOS Data
  Protection at this exact class, not from SQLCipher.

It is not `UserDefaults` either: that gives no control over the protection class and no
durable-before-return write. FR-21 also hints that per-Driver *settings* suites will use
`UserDefaults` (FR-29, later work), and the selection should not share that mechanism. It is not
the Keychain: Keychain items survive app deletion, and selection is ordinary app state.

The registry does not choose the file URL. 1.12b's app composition will pass one in Application
Support. It is not the App Group, because no extension reads the selection.

### The serializer (AC 6)

Actor reentrancy means two `activate` calls interleave at every `await`. Use a FIFO gate inside the
actor:

```swift
private var isBusy = false
private var waiters: [CheckedContinuation<Void, Never>] = []

private func enter() async {
    if !isBusy { isBusy = true; return }
    await withCheckedContinuation { waiters.append($0) }
}

private func leave() {
    if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
}
```

Each mutating operation starts with `await enter()` followed by `defer { leave() }`. When `leave()`
hands off to a waiter, `isBusy` stays `true`; that is deliberate. `slots`, `lifecycleState(of:)`
and `persistedSelection` do **not** take the gate, so a Driver's activation hook can read
`await registry.slots` without deadlocking. The "never empty" test relies on that.

### Activation algorithm, step by step (AC 3)

1. `await enter()`, then `defer { leave() }`.
2. `guard let driver = drivers[id] else { throw .unknownDriver(id) }`.
3. If the initial load failed, throw `.selectionUnavailable(failure)`.
4. If `lifecycle[id]?.state` is `.active` or `.degraded`, return `[]`.
5. Conflicts: the known ids in `persisted` (excluding `id`) whose descriptor shares any capability
   in `driver.descriptor.capabilities` with `cardinality == .singleInstance`. Sort them by raw
   value.
6. Advance to `.activating`, then `try await driver.activate()`.
   - On `catch` (the error is `DriverFailure`): advance to `.failed`. If `persisted` contains
     `id.rawValue`, save `persisted − {id}`; if that save fails, still throw the activation error.
     Then throw `.activationFailed(id, failure)`.
7. Advance to `.active`.
8. If `persisted` lacks the id, save `persisted ∪ {id}`. On failure: advance to `.deactivating`,
   `await driver.deactivate()`, advance to `.notActivated`, and throw `.persistenceFailed`.
   Assign `persisted` only after the save succeeds.
9. For each conflict `c`: save `persisted − {c}`. On failure, throw `.persistenceFailed`. Both
   Drivers are then persisted and running, and derivation still picks one deterministically.
   Then assign `persisted`, and tear `c` down **only if** its lifecycle state is one that permits
   `.deactivating`. A persisted Driver that `restore()` has not yet started is `.notActivated`,
   and the table refuses `notActivated → deactivating`.
10. Return the evicted ids.

**Absent ids are never conflicts.** The registry has no descriptor for a Driver this build
excludes, so it cannot know what that Driver claims. Those ids stay in the persisted set
(FR-27). Every `save` is built from `persisted` with set arithmetic, never rebuilt from the
known Drivers, so they survive it.

### Restore (AC 8)

Walk `persisted.sorted()`. Skip ids already running. Collect the failures and remove them with
**one** save at the end. If that save fails, set `selectionFailure` in the report. When the
initial load had failed, return a report carrying `selectionFailure` straight away, with no hooks
and no writes.

Restore does not evict anything. After a crash in the middle of a swap, or after a gated Driver
returns in a later build, two present Drivers may both be persisted and claim the same slot.
Derivation then picks the lowest id deterministically, and both run. Do not add eviction to
restore; this is an open question for the maintainer (below).

### Test doubles (test target only)

`Tests/DomainCoreTests/RegistryTestDrivers.swift`:

- `actor TestDriver: Driver`:
  - `init(id: String, capabilities: Set<Capability>, transport: DriverTransport = .inProcess)`.
    Build the descriptor with `DriverIdentifier(id)!`, `targetName: "TestDriver"`,
    `displayName: id`, `version: "1.0.0"` and `verification: .unverified`.
  - `var activationFailure: DriverFailure?`. When set, `activate()` throws it.
  - `var onActivate: (@Sendable () async -> Void)?`, awaited inside `activate()`, plus setters
    for both of these.
  - `activateCount` and `deactivateCount`.
  - `capability(_:)` returns `nil`. The registry never asks for a port, and returning `nil`
    avoids writing six stubs.
- `final class RecordingSelectionStore: DriverSelectionStore, @unchecked Sendable`. Guard its
  state with an `NSLock`. It holds the current set, `savedSets: [Set<String>]`, and optional
  injected `loadFailure` and `saveFailure`.
- `actor Gate` with `wait()` and `open()`, using the same continuation pattern as the serializer.
  `Tests/AppFeatureTests/DriverHostTests.swift` has `HostDeactivationGate` as a model.
- **Ids need at least two dot-separated labels** (`DriverIdentifier` rejects `"alpha"`). Use, for
  example:
  - `test.pump.alpha` and `test.pump.bravo`, each with glucose, insulin and pump status
  - `test.cgm.charlie`, glucose only
  - `test.status.delta`, pump status only
  - `test.bgm.one` and `test.bgm.two`
  - `test.sync.one`
  - `test.net.glucose`, network transport with glucose source
- Multi-Driver behaviour is tested only with these doubles. The shipped build still contains only
  the Simulated Driver. Do not add a Driver to `DriverCatalog` or under `Sources/Drivers/`.

### Test list (minimum)

**Registry, `DriverRegistryTests`:**
- **Swap, never empty:**
  - Activate alpha, then activate bravo while recording `slots.holder(of: .glucoseSource)` from
    bravo's `onActivate` hook (expect alpha).
  - Derive slots for each set in `savedSets` (expect non-nil at every step).
  - At the end: holder is bravo; alpha's `deactivateCount == 1`; `persistedSelection ==
    ["test.pump.bravo"]`.
- **Multi-holder eviction:** with charlie and delta active, activating alpha evicts both in one
  call and returns `[charlie, delta]`.
- **Idempotent activate:** a second `activate(alpha)` leaves `activateCount == 1` and `savedSets`
  unchanged.
- **Unknown id:** throws `.unknownDriver`; nothing is saved.
- **Failing hook:**
  - It throws `.activationFailed(id, .transportUnavailable)`.
  - The lifecycle is `.failed`.
  - Nothing is saved, and the incumbent is not evicted.
- **Save failure after the hook:**
  - It throws `.persistenceFailed`.
  - The incoming Driver's `deactivateCount == 1` and its lifecycle is `.notActivated`.
  - The incumbent is still the holder.
- **Multi-instance:** pump alpha active, then bgm one and two and sync one; nothing is evicted,
  the pump and glucose slots are unchanged, and the BGM members are both, sorted. Deactivating
  bgm one leaves bgm two.
- **Deactivate:**
  - The id is removed from the store before the hook runs: assert from a recording store that
    the save happened while `deactivateCount` was still 0, or check the order of a combined
    event log.
  - A second deactivate is a no-op.
  - The file contents are ids only.
- **Race:** bravo's activation is held on a gate, `deactivate(alpha)` runs concurrently, then the
  gate opens; the result is `persistedSelection == ["test.pump.bravo"]`.
- **Serialization:** while alpha is held on a gate, charlie's `activateCount` stays 0 until the
  gate opens.

**Restore, using `FileDriverSelectionStore` in a temp directory:**
- Relaunch with new instances restores the same set.
- Durability: a new store instance sees the change right after `activate` returns.
- An absent id is left in the file after restore **and** after a later activate and deactivate.
- A failing restore reports the failure, clears the id from the file, sets the lifecycle to
  `.failed`, and leaves the slot nil.
- A second `restore()` does not call any hook again.
- An unreadable file (and a newer-version file) gives a report with `selectionFailure`;
  `activate` throws `.selectionUnavailable`; the file bytes are identical before and after.

**Init:** a duplicate id throws `.duplicateIdentifier`. Slots derive from the loaded set before
`restore()` runs.

Use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), as every existing target
does. Write `@testable import DomainCore` only if you need internals, and
`@_spi(DriverPlatform) import DriverAPI` to read `DriverLifecycleState`. That enum is public
anyway, so a plain import works for it. No sleeps: synchronize on gates.

### Safety-guard traps

- **Numeric literals under `Sources/`** that fall in a canonical band fail `safety_guards.sh`,
  however they are spelled: 17.5-18.5, 19-21, 475-525, 342-378, 855-945, 3420-3780, 57-63, and
  1,000,000,000-1,400,000,000. This code needs no number except `formatVersion = 1`. Tests are
  not scanned, but keep them clean anyway.
- **No `Date()`, `Date.now` or `Date.init` under `Sources/`** (AD-14). The registry needs no time.
- **The driver guards' deny-list** (`bolus`, `deliver`, `suspend`, `resume`, `prime`, `inject`,
  ...) scans only `Sources/DriverAPI` and `Sources/Drivers`. Your DriverAPI edit (Task 1) must use
  none of those words, including in identifiers. `cardinality`, `singleInstance` and
  `multiInstance` are clean.
- **`ReadOnlyPostureTests`** rejects any DriverAPI **function** whose name starts with `set`,
  `start`, `stop`, `update`, `clear`, `enable` and similar verbs. `cardinality` is a computed
  property, so it is fine. Do not add functions to DriverAPI.
- **Logging:** the repo has no logger yet, and SI-9 forbids health values in logs. Do not add
  one. FR-25 and FR-28 ask for failures to be "logged". Here they are **reported** through typed
  errors and `RestoreReport`, which a later change can log.

### Existing code to build on (develop @ b9f85cd)

- `Sources/DriverAPI/Driver.swift`: `protocol Driver: Actor` with a `nonisolated descriptor`,
  `activate() async throws(DriverFailure)` (repeatable), and `deactivate() async` (idempotent,
  non-throwing). So FR-25's "a deactivation hook that throws" cannot happen here.
- `Sources/DriverAPI/DriverLifecycle.swift`:
  - `DriverLifecycleState` and its transition table: `notActivated → activating`;
    `activating/active/degraded → active/degraded/deactivating/failed`;
    `deactivating → notActivated`; `failed → activating/deactivating`.
  - The SPI type `DriverLifecycle` with `advance(to:) throws(DriverFailure)`.
- `Sources/DriverAPI/DriverDescriptor.swift`: `DriverIdentifier` (Hashable, `rawValue`, at least
  two dot labels) and `DriverTransport` (`bluetoothLowEnergy`, `network`, `inProcess`).
- `Sources/DriverAPI/DriverCatalog.swift`: a static list with one entry,
  `com.glycemicgpt.simulated`, which declares glucose and insulin source. Unchanged here.
- `Sources/AppFeature/DriverHost.swift`: `HomeModel` hosts one Driver and drives its lifecycle on
  scene phase. It is **untouched** here. Moving lifecycle ownership from `HomeModel` to the
  registry is 1.12b's job. Until then, nothing constructs a `DriverRegistry` in the app, so no
  Driver has two lifecycle owners.

### Android reference (copied here; the Android repo is not readable from your sandbox)

`android-unofficial/app/src/main/java/com/glycemicgpt/mobile/plugin/PluginRegistry.kt`:
- `activatePlugin`, under `synchronized(activationLock)`:
  - unknown id → failure "Unknown plugin: <id>"
  - already active → success with no hook
  - collect the conflicting ids from the persisted per-capability slot
  - `plugin.onActivated()` **first** ("so the capability slot is never empty"); if it throws,
    return failure with nothing persisted
  - persist: `setActivePluginId` for single-instance capabilities, `addActivePluginId` for
    multi-instance ones
  - then `deactivatePluginInternal(conflictId)` for each conflict
- `deactivatePluginInternal`:
  - `onDeactivated()`; if it throws, Android logs "threw during onDeactivated, continuing cleanup"
  - then clear each single-instance preference **only if it still equals this id**, and remove
    the id from each multi-instance set
  - Here the order is reversed (persist, then hook) so that a crash mid-hook cannot resurrect
    the Driver. Derivation from a set makes the "only if still equal" check automatic.
- `restoreActivePlugins`:
  - for each persisted id: `plugins[pluginId] ?: continue` leaves absent ids untouched
  - an `onActivated()` that throws → "Failed to restore plugin %s for %s, clearing preference"
    and the preference is cleared
- `updateStateFlows`: the pump slot is the first active plugin with `PUMP_STATUS` or
  `INSULIN_SOURCE`, and the glucose slot is the first with `GLUCOSE_SOURCE`. Android uses
  iteration order; here it is the lowest raw id (FR-30).

`android-unofficial/plugins/pump-driver-api/src/main/java/com/glycemicgpt/mobile/domain/plugin/PluginCapability.kt`:
`SINGLE_INSTANCE = {GLUCOSE_SOURCE, INSULIN_SOURCE, PUMP_STATUS, CALIBRATION_TARGET,
BOLUS_CATEGORY_PROVIDER}` and `MULTI_INSTANCE = {BGM_SOURCE, DATA_SYNC}`, with an init-time
exhaustiveness check. iOS has no calibration member, and its dose-category provider corresponds
to the bolus-category provider.

`android-unofficial/app/src/main/java/com/glycemicgpt/mobile/plugin/PluginPreferences.kt`: a
SharedPreferences file named `plugin_prefs`, with one key per single-instance capability and a
string set per multi-instance capability. iOS persists one set of ids instead (FR-23).

**For 1.12b, not this change:** the confirmation copy, from
`android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/settings/SettingsScreen.kt`
(around line 432):
- title `"Deactivate Plugin"`
- body `"Deactivating this plugin may stop glucose monitoring, insulin tracking, or other services it provides. Are you sure?"`
- confirm `"Deactivate"` (error colour) and dismiss `"Cancel"`

`SettingsViewModel.kt` gates deactivation behind `showDeactivateConfirm(pluginId)` →
`confirmDeactivatePlugin()` and deprecates the direct `deactivatePlugin`. The PRD's FR-25 wording
says "Driver" where Android says "plugin". The iOS copy is "Deactivate Driver" and "Deactivating
this Driver may stop glucose monitoring, insulin tracking, or other services it provides. Are you
sure?"

### Architecture compliance

- **FR-23 / FR-30:** one model, persisted ids, with slots derived by a total function and a
  stable tiebreak. No slot table.
- **AD-3:** DomainCore depends on SafetyCore and DriverAPI only, and no Driver depends on it.
  The manifest test pins both.
- **AD-13:** every fallible path returns a typed error or a report entry. Nothing substitutes an
  empty set for an unreadable one.
- **AD-16:** the platform owns transitions. Every hook call is bracketed by a legal `advance`.
- **SI-6:** a Driver that failed to restore is reported and its slot is empty. Nothing claims it
  is running.

### Out of scope (later work; do not build)

- **1.12b:**
  - app composition: construct the registry and call `restore()` at launch before anything else
    (FR-26); make `HomeModel` read the glucose slot from the registry instead of owning one
    Driver; reconcile with 1.15's scene-phase behaviour; add the `AppFeature → DomainCore` edge
  - the deactivation confirmation UI and its model gate, so that no UI path deactivates without
    confirmation (FR-25)
  - the Drivers list in Settings
  - the FR-33 typed "no active Driver for this Capability" read error, which needs a
    `DriverFailure` case or a DomainCore read API
- **1.12b or 1.12c:**
  - FR-29 per-Driver namespaced settings
  - FR-34 bounded best-effort event channel (256 per subscriber, drop-oldest, Driver id on every
    event; 256 belongs in `SafetyConstants`/`CANON_SPEC` only if it is classed as a safety
    constant)
  - logging of registry failures
- **Elsewhere:**
  - FR-27's compile-time gate mechanism (FR-189)
  - Keychain credentials (5.1)

### Project structure notes

- New:
  - `Sources/DomainCore/DriverSlots.swift`
  - `Sources/DomainCore/DriverSelectionStore.swift`
  - `Sources/DomainCore/DriverRegistry.swift`
  - `Tests/DomainCoreTests/DriverSlotsTests.swift`
  - `Tests/DomainCoreTests/FileDriverSelectionStoreTests.swift`
  - `Tests/DomainCoreTests/RegistryTestDrivers.swift`
  - `Tests/DomainCoreTests/DriverRegistryTests.swift`
- Modified:
  - `Package.swift`
  - `Sources/DriverAPI/Capability.swift`
  - `Tests/DriverAPITests/CapabilitySetTests.swift`
  - `Tests/SafetyCoreTests/PackageManifestTests.swift`
- Branch from `develop`, named for example `feat/driver-registry`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 1.12]
- [Source: prd.md §5.2 description; FR-23, FR-24, FR-25, FR-26, FR-27, FR-28, FR-29, FR-30, FR-33,
  FR-34]
- [Source: ARCHITECTURE-SPINE.md: module graph, AD-1, AD-2, AD-3, AD-4, AD-6, AD-9, AD-13, AD-16]
- [Source: scripts/guards/driver_guards.sh: SCAN_DIRS, deny-list, rule D, SPI rule]
- [Source: android-unofficial PluginRegistry.kt, PluginPreferences.kt, PluginCapability.kt,
  SettingsScreen.kt, SettingsViewModel.kt, as cited above]

## Dev Agent Record

### Agent Model Used

Codex (GPT-6), cycle 1.

### Debug Log References

- `swiftc -module-cache-path .build/clang-cache -swift-version 6 -emit-module` compiled SafetyCore, DriverAPI and DomainCore in dependency order; DomainCoreTests typechecked with the Xcode Swift Testing framework.
- `swift build` and `swift test`: exit 1 before compilation. The sandbox denies `~/.cache/clang/ModuleCache`; pointing the cache inside `.build` then encounters `sandbox-exec: sandbox_apply: Operation not permitted`.
- `bash scripts/guards/safety_guards.sh`: pass.
- `bash scripts/guards/safety_guards.sh --self-test`: pass, 75 cases and two documented known bypasses.
- `bash scripts/guards/driver_guards.sh`: pass.
- `bash scripts/guards/driver_guards.sh --self-test`: pass, 68 cases and three documented known limits.
- `bash scripts/ci-local.sh --self-test`: pass.
- `xcodebuild test -scheme GlycemicGPT-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd`: exit 66; CoreSimulatorService unavailable and Xcode reports no package/project at the directory.
- `xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj -scheme GlycemicGPT -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath .build/xcode-dd CODE_SIGNING_ALLOWED=NO`: exit 74 during package resolution; module cache access denied and CoreSimulatorService unavailable.

### Completion Notes List

- Implemented AC 1–9: capability cardinality, package topology, derived slots, protected atomic selection file, serialized registry operations, restore and test coverage. The later PM decision on competing persisted claims is applied during restore: the lower raw id remains and the removed id and capability are logged.
- Reviewable diff: 814 added or changed lines across 11 source, test and manifest files, excluding this record and checkpoint artifacts.
- The required gates have been attempted, but AC 10 is not verified because SwiftPM and Xcode cannot run through this sandbox. Independent gate re-run remains necessary.

- Safety review fixes (2026-11-01):
  - **Accepted deviation (PM):** a swap writes the persisted set once, `persisted ∪ {id} − conflicts`, after the incoming hook succeeds and before any conflict is torn down; this replaces activation steps 8–9's per-conflict saves. A failed write deactivates the incoming Driver and leaves the selection unchanged. A conflict whose teardown throws does not stop the others; `activate` then throws `.evictionIncomplete(evicted:failedToDeactivate:)` naming it.
  - Restore no longer starts a losing claimant: in raw-id order, an id whose single-instance capability is held by a running or lower restored Driver is skipped and dropped from the selection. If the winner fails, the next claimant takes over. Failed and skipped ids leave in one save; a failed save is reported via `selectionFailure` and `unremoved`.
  - The store distinguishes `.unavailable` (file present but unreadable now, e.g. before first unlock) from `.unreadable` (corrupt). `restore()` retries the load only for `.unavailable`; other failures are never retried, read as empty, or overwritten.
  - `operationsAreSerializedAndNewClaimSurvives` uses an internal enqueue hook to prove the deactivation is queued before the release. Teardown failure is injected through an internal transition-fault seam (`@testable import`).

### File List

- `Package.swift`
- `Sources/DriverAPI/Capability.swift`
- `Sources/DomainCore/DriverSlots.swift`
- `Sources/DomainCore/DriverSelectionStore.swift`
- `Sources/DomainCore/DriverRegistry.swift`
- `Tests/DriverAPITests/CapabilitySetTests.swift`
- `Tests/SafetyCoreTests/PackageManifestTests.swift`
- `Tests/DomainCoreTests/DriverSlotsTests.swift`
- `Tests/DomainCoreTests/FileDriverSelectionStoreTests.swift`
- `Tests/DomainCoreTests/RegistryTestDrivers.swift`
- `Tests/DomainCoreTests/DriverRegistryTests.swift`

### PM decisions on drafting open points (2026-11-01)
- **File naming:** this is 1-12a. The 1-12b story covers the deactivation-confirmation UI, the FR-33 distinguishable no-active-Driver error, FR-29 per-Driver namespaced settings and FR-34 bounded best-effort event delivery.
- **Two active Drivers in one single-instance slot at restore.** This can only come from corruption or a build change. The derivation function picks the deterministic winner (lowest id). Every other Driver claiming that slot is removed from the persisted active set, and the change is logged by Driver id and slot only, with no health data. The persisted set must never stay in a state that is invalid by construction. Test it.
- **"Reinstall" in FR-26:** the selection survives relaunch, background relaunch and app upgrade. It does NOT have to survive deleting the app; iOS removes the container. Document this in a doc comment on the store.
- **Budget:** 800–900 lines at the edge is accepted, because over half is tests. If the implementation goes over about 1,000 reviewable lines, stop and report it, and don't ship the blob.
- budget: CONTINUATION_REQUIRED sha256:f7436c28830076ec00791e61a6dfd2b49bce0f2666790ea76f4f0dd2a7c25ca3 cycle 1 2026-11-01T20:01:03Z
