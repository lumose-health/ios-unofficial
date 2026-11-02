---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-12c-driver-screen-deactivation-confirmation-and-settings.md.stamp.json
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

# Story 1.12c: Drivers screen, deactivation confirmation and per-Driver settings

Status: done

> Depends on PR #23 being merged; dispatch after merge.
> PR #23 (`feat/registry-lifecycle`, head b384d41 at writing, already merged with develop @ bf61006)
> puts `DriverRegistry` in the app, adds `DriverStartup`, and moves `HomeModel` onto the registry.
> Branch from `develop` after it lands.

> **SPLIT. FR-34, the event channel, is NOT in this file. It moves to 1.12d (not written yet).**
> The three remaining pieces of epic Story 1.12 (FR-25, FR-29, FR-34) come to about 1,050-1,150
> reviewable lines together. The Drivers screen with its confirmation (FR-25) and per-Driver
> settings (FR-29) come to about 750-820, which fits the budget. FR-34 has no publisher and no
> subscriber yet (1.12b, "Out of scope"), so it is the piece that can wait. 1.12d carries: a
> per-subscriber bounded buffer of 256 with drop-oldest and no replay, a logged warning on
> overflow that never blocks or fails the publish, the publishing Driver's id on every event, and
> platform-only events whose initializer a Driver target cannot see.

<!-- Planning note (for the maintainer): depends on PR #23. Estimate ~750-820 reviewable lines
over ~12 files, a bit under half of it tests. Route: NOT chosen here; the PM routes via /v1/route.
Touches DriverAPI (one new read-only settings protocol and two value types; no Capability, no
lifecycle, no catalog change) and DomainCore (a new settings store; the registry itself is
unchanged). No dosing, alert floor, ingestion mapper, safety_validation, dependency, CI or guard
change. Suggested classification: ambiguity medium, blast_radius medium. -->

## Story

As a Builder,
I want to turn Drivers on and off from Settings, with a clear warning before one stops,
so that I never stop my glucose source by accident and my Driver's settings are still there when
I turn it back on.

## Acceptance Criteria

From epics.md Story 1.12 (FR-25, FR-29), with the PRD's testable consequences and the Android
copy pinned. FR-34 is split to 1.12d (see the note at the top).

1. **A Drivers screen under Settings.** The Settings tab shows a "Drivers" link above "Open Source
   Licenses" (identifier `settings.drivers`). It opens a new detail route `AppRoute.drivers`,
   titled "Drivers", which hides the tab bar like the Licenses route. The screen lists every
   Driver the registry holds, in `registry.descriptors` order. One row per Driver shows: display
   name, transport (the Protocol column), version, Verification Status verbatim, and the
   lifecycle state as text (table in Dev Notes). Rows are built from `DriverRow`; the view
   derives nothing about a Driver itself. The rows update when the registry changes (its
   `changes()` stream), with no manual refresh. Row identifier: `drivers.row.<raw id>`.
2. **Activate goes through the registry.** A Driver that is not in the persisted selection shows
   an "Activate" button. Tapping it calls `DriverRegistry.activate(_:)` and nothing else. While
   the call runs, that row's button is disabled and shows the state text. A thrown
   `DriverRegistryError` shows as an inline message on that row (wording in Dev Notes). It is not
   an alert and not a crash. Activation needs no confirmation; FR-25 covers deactivation only.
3. **Deactivation always asks first, and names what stops (FR-25).** A Driver in the persisted
   selection shows a "Deactivate" button with the destructive role. Tapping it shows an alert and
   does not touch the registry:
   - title "Deactivate Driver"
   - message: "Deactivating this Driver may stop glucose monitoring, insulin tracking, or other
     services it provides. Are you sure?", then a blank line, then "\<Display name\> provides:
     \<list\>." The list is built from that Driver's declared capabilities in `Capability.allCases`
     order, using the plain names in Dev Notes. Then "Its settings are kept."
   - buttons "Deactivate" (destructive) and "Cancel" (cancel role)
   Cancel leaves the Driver, the selection and the lifecycle exactly as they were. Only
   "Deactivate" calls `DriverRegistry.deactivate(_:)`. **The screen model has no public member
   that deactivates without going through the confirmation**, and a test pins that: requesting
   deactivation alone makes zero registry calls.
4. **Home follows the change, both ways, without a relaunch.** After the Simulated Driver is
   deactivated from this screen, Home shows the existing "No glucose source" message (from PR
   #23) and the DEMO DATA banner goes away. After it is activated again, Home reconnects and
   shows readings, **with no scene-phase change and no relaunch**. Today `HomeModel`'s registry
   observer returns early when `ports == nil`, so a reactivation is not noticed until the next
   foreground. Fix that in `HomeModel` (Dev Notes, "Reconnecting after reactivation").
5. **Per-Driver settings: a namespaced, read-only handle for the Driver (FR-29).**
   - `DriverAPI` declares `DriverSettingKey`, `DriverSettingValue` and a protocol
     `DriverSettings` (shapes in Dev Notes). `DriverSettings` only reads. It has no member that
     takes a Driver id, so a handle can only see the namespace it was made for.
   - `DriverSettingKey` is failable. It accepts exactly `^[a-zA-Z][a-zA-Z0-9_.-]{0,127}$`: 1 to
     128 ASCII characters, the first a letter. It never traps.
   - A typed read of a key stored with another type returns `nil`, never a zero value or `false`.
   - The platform side lives in `DomainCore`: `FileDriverSettingsStore` makes the per-Driver
     handle and is the only thing that writes. A Driver target cannot import `DomainCore` (AD-3),
     so it cannot make a handle for another Driver's namespace.
6. **Settings survive deactivation, reactivation and relaunch (FR-25, FR-29).**
   - A value written for a Driver, then `registry.deactivate`, then `registry.activate`, reads
     back unchanged through that Driver's handle.
   - A value written by one store instance reads back through a new instance on the same
     directory, which stands in for a relaunch or an upgrade.
   - Deactivation deletes nothing in the settings directory.
   - Driver A's handle never sees Driver B's value under the same key.
   - On iOS, files are written atomically with `.completeFileProtectionUntilFirstUserAuthentication`
     (readable during a locked background wake, AD-6). They live in Application Support, so
     deleting the app removes them.
   - No credential, pairing code or secret goes in this store (SI-10). The `DriverSettings` doc
     comment says so.
7. **Gates.** All nine frontmatter gates pass. The Dev Agent Record has two simulator
   screenshots, saved under `.build/`: the Drivers screen with the confirmation alert up, and Home
   after reactivation showing a reading. If the sandbox cannot run the simulator, record that and
   the PM takes them.

## Tasks / Subtasks

- [ ] Task 1: settings types in DriverAPI (AC 5)
  - [ ] New `Sources/DriverAPI/Settings/DriverSettings.swift`: `DriverSettingKey`,
        `DriverSettingValue`, `protocol DriverSettings: Sendable`. Doc comments say: read-only for
        the Driver, the platform writes; namespaced by `DriverIdentifier`; no secrets (SI-10); no
        value here takes part in glucose or dose validation (FR-29).
  - [ ] Tests in `Tests/DriverAPITests/DriverSettingsKeyTests.swift`: valid keys (`a`, `interval`,
        `display.mode`, `x_1-2`, a 128-character key); refused keys (empty, `1abc`, `_a`, `.a`,
        `a b`, `a/b`, `é`, a 129-character key); typed reads return `nil` on a type mismatch.
- [ ] Task 2: `FileDriverSettingsStore` in DomainCore (AC 5, 6)
  - [ ] New `Sources/DomainCore/DriverSettingsStore.swift`. Shape in Dev Notes. Follow
        `FileDriverSelectionStore` for file I/O, the format version and data protection.
  - [ ] New `Tests/DomainCoreTests/DriverSettingsStoreTests.swift`: round trip of all four value
        kinds; namespace isolation; survives a new store instance; a non-finite number is refused
        on save; an unreadable file gives a typed failure on save and `nil` on read, never a
        zero value; `remove` affects only that Driver's key.
  - [ ] Add to `Tests/DomainCoreTests/DriverRegistryTests.swift`: write, deactivate, activate,
        read back unchanged; the settings file still exists after deactivation.
- [ ] Task 3: Drivers screen model in AppFeature (AC 1, 2, 3)
  - [ ] New `Sources/AppFeature/DriversScreen.swift`, model half: `@MainActor @Observable final
        class DriversModel`, built from a `DriverRegistry`. It exposes `rows: [DriverRowState]`
        (the `DriverRow` plus `isSelected`, `isBusy`, `errorMessage`), `pendingDeactivation:
        DeactivationPrompt?`, `activate(_:) async`, `requestDeactivation(_:)`,
        `confirmDeactivation() async` and `cancelDeactivation()`. There is no public
        `deactivate(_:)`. `DeactivationPrompt` holds the id, title, message and button labels, as
        pure data so the copy is unit tested.
  - [ ] It observes `registry.changes()` the way `HomeModel` does (a `Task` held
        `nonisolated(unsafe)` and cancelled in `deinit`, `[weak self]`), and re-reads
        `persistedSelection` and `lifecycleState(of:)` for each Driver.
  - [ ] New `Tests/AppFeatureTests/DriversScreenTests.swift`, using the in-memory selection store
        and test Driver that `DriverHostTests` already has (copy the doubles; AppFeatureTests
        cannot import DomainCoreTests):
    - rows follow descriptor order and carry the verification and state text
    - `requestDeactivation` alone makes zero registry calls and the Driver is still active
    - the prompt copy matches AC 3 exactly, capability list included
    - cancel clears the prompt and nothing changes
    - confirm deactivates; the row then shows "Activate"
    - activate success; activate failure shows the inline message
    - rows update after a registry change made somewhere else
- [ ] Task 4: view and navigation (AC 1, 2, 3)
  - [ ] View half of `DriversScreen.swift`: a `List` of rows, a button per row, and
        `.alert(_:isPresented:presenting:actions:message:)` bound to `pendingDeactivation`.
  - [ ] `AppNavigation.swift`: add `AppRoute.drivers`. `title` becomes a `switch`, and
        `hidesTabBar` stays true for both. Update `detailRoutesHideTabBarAndHaveExpectedTitle`.
  - [ ] `AppShell.swift`: add the `settings.drivers` link before the Licenses link in the
        Settings placeholder, and route `navigationDestination` by case: `.licenses` →
        `LicenseDestination`, `.drivers` → `DriversScreen`. The Drivers screen reads
        `DriversModel` from the environment.
  - [ ] `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: build `DriversModel(registry: registry)` next
        to `HomeModel` and inject it with `.environment(...)`. Nothing else changes there.
- [ ] Task 5: Home reconnects after reactivation (AC 4)
  - [ ] `Sources/AppFeature/DriverHost.swift`, `validateConnection()`: see Dev Notes.
  - [ ] Test in `DriverHostTests`: deactivate through the registry → "No glucose source";
        activate through the registry → connected, with no `setScenePhaseActive` call in between.
        Synchronize with the existing `eventually` helper, not sleeps.
- [ ] Task 6: gates and screenshots (AC 7). Record the final reviewable diff size.

## Dev Notes

### Read first (rules of the road)

- **Swift 6 strict concurrency, typed throws.** `HomeModel` and `DriversModel` are
  `@MainActor @Observable`. New value types are `Sendable` and `Hashable`.
- **Do not edit** `DriverRegistry`'s lifecycle logic, `Sources/DriverAPI/Capability.swift`,
  `DriverLifecycle.swift`, `DriverCatalog.swift`, `Sources/Persistence/**`,
  `Sources/SafetyCore/**`, `Package.swift`, CI files or the guards. The only DriverAPI addition is
  the new `Settings/` file. If you find you need anything else in DriverAPI, write a NEEDS-HUMAN
  line in the Dev Agent Record instead.
- **Do not edit `ReadOnlyPostureTests.commandVerbs`.** The new protocol has only read members
  (see below), so it passes as is.
- **No therapeutic write, ever (SI-1).**
- **Scratch files only under `.build/` in your worktree. One operation per Bash call.**
- Your sandbox may not be able to run Swift or the Simulator. The launcher re-runs every gate.

### Known pitfalls

- The worker cannot compile, so write carefully. A `switch` after any statement in a function or getter needs `return switch`. Test functions that `await` must be `async`. In Swift Testing, `#expect` over a key-path closure such as `allSatisfy(\.x)` is treated as throwing, so bind it to a `let` first. Typed-throws closures can't call `NSLock.withLock` and throw a typed error; use `lock()`/`defer unlock()`. In an init, assign every stored property before reading any `self` property.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs in `#if os(iOS)`.
- Every SF Symbol name needs a test that it exists on UIKit and AppKit.
- Small coloured text needs a contrast ratio of at least 4.5:1. Use the existing light/dark palette in `StatusRowView`.
- Never write a numeric safety constant inline, and never disguise one. Literals equal to safety constants (for example 18, 20, 55, 58, 70, 180, 250) trip the guard.
- Swift 6 strict concurrency; actors are reentrant across `await`.
- Code comments must not mention stories, epics, AC numbers, agents or cycles. No private UIKit API.
- The Release-build lifetime of objects held only weakly by system APIs must be guaranteed explicitly.
- Diff budget: about 800 reviewable lines.

Applied here: the key length limits are 128 and 127 and touch no guard band. Do not write `20`
anywhere as a test key length or count. The screen uses no SF Symbols. If you add one, it needs
the UIKit/AppKit existence test from `AppNavigationTests`. The inline error text uses the
`StatusColor.error` light/dark pair, which already passes 4.5:1.

### Existing code to build on (PR #23 tree)

- `Sources/DomainCore/DriverRegistry.swift`:
  - `descriptors` (nonisolated), `persistedSelection`, `lifecycleState(of:)` and `changes()`
    (an `AsyncStream<Void>`, newest-1 buffered and coalescing, so re-read state on every element).
  - `activate(_:)` returns the evicted ids and throws `DriverRegistryError`.
  - `deactivate(_:)` saves the selection without the id first, then tears down. So FR-25's
    "deactivation never gets stuck, persistence is still updated" already holds:
    `Driver.deactivate()` cannot throw, and the save comes before teardown. Do not change it.
  - The registry never touches settings or the Keychain, which is what "preserves credentials and
    settings" needs. AC 6's registry test pins it.
- `Sources/DriverAPI/Presentation/DriverRow.swift`: `DriverRow(descriptor:state:)` and
  `DriverCatalog.rows(state:)`. Build rows from `registry.descriptors`, not from
  `DriverCatalog.entries`, so tests can inject Drivers. In the app the two lists are the same.
- `Sources/DriverAPI/DriverDescriptor.swift`: `DriverIdentifier`'s doc says the raw value "doubles
  as the Driver's settings-suite name". The settings file name is that raw value, which keeps the
  doc true.
- `Sources/DomainCore/DriverSelectionStore.swift`: `FileDriverSelectionStore` is the pattern to
  copy: a versioned JSON file, `.atomic` plus `.completeFileProtectionUntilFirstUserAuthentication`
  under `#if os(iOS) || os(watchOS)`, a missing file read as empty, and typed failures.
- `Sources/AppFeature/AppShell.swift`: `MainTabView.tabStack` holds the single
  `navigationDestination(for: AppRoute.self)`. The Settings tab is a `PlaceholderView` with an
  `extra` builder that holds the Licenses `NavigationLink(value:)`. Keep its two messages.
- `Sources/AppFeature/AppNavigation.swift`: `AppRoute` is `CaseIterable` with a single case.
  `title` and `hidesTabBar` are constants today.
- `Sources/AppFeature/DriverHost.swift`: `HomeModel.validateConnection()` and `dropConnection`,
  quoted under "Reconnecting after reactivation".
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: builds `registry`, `startup` and `HomeModel`, and
  injects `model` and `onboarding`.

### Settings shapes

```swift
// DriverAPI
public struct DriverSettingKey: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init?(_ rawValue: String)          // ^[a-zA-Z][a-zA-Z0-9_.-]{0,127}$, ASCII only
}

public enum DriverSettingValue: Hashable, Sendable, Codable {
    case bool(Bool), integer(Int), number(Double), text(String)
}

/// One Driver's settings, as that Driver sees them. Read-only: the platform writes.
public protocol DriverSettings: Sendable {
    func value(for key: DriverSettingKey) -> DriverSettingValue?
}
extension DriverSettings {
    public func bool(for key: DriverSettingKey) -> Bool?       // nil unless stored as .bool
    public func integer(for key: DriverSettingKey) -> Int?
    public func number(for key: DriverSettingKey) -> Double?   // .integer is NOT widened
    public func text(for key: DriverSettingKey) -> String?
}
```

```swift
// DomainCore
public enum DriverSettingsStoreFailure: Error, Hashable, Sendable {
    case unreadable(detail: String), unwritable(detail: String), nonFiniteNumber
}

public final class FileDriverSettingsStore: @unchecked Sendable {   // guarded by one NSLock
    public init(directory: URL)
    public func settings(for driver: DriverIdentifier) -> any DriverSettings  // bound handle
    public func save(_ value: DriverSettingValue, for key: DriverSettingKey,
                     driver: DriverIdentifier) throws(DriverSettingsStoreFailure)
    public func removeValue(for key: DriverSettingKey,
                            driver: DriverIdentifier) throws(DriverSettingsStoreFailure)
}
```

- File: `<directory>/<raw id>.json` holding `{ "version": 1, "values": { key: value } }`, with
  sorted keys. `DriverIdentifier` only allows letters, digits, `-` and `.`, so the raw id is a
  safe file name. Still build the URL with `appendingPathComponent`, never by joining strings.
- The handle is a private struct holding the store and the id. Its `value(for:)` reads through
  the store under the lock. Keep a per-Driver cache in the store, filled on first read and
  updated on save. A read of an unreadable or missing file returns `nil`. Nothing traps.
- Inside typed-throws functions use `lock.lock(); defer { lock.unlock() }`, not `withLock`.
- **Why the Driver only reads.** AD-12 says no protocol in `DriverAPI` declares a write member,
  and `ReadOnlyPostureTests` refuses DriverAPI functions named with a command verb (`set`,
  `write`, `update`, `clear`...). A settings writer in DriverAPI would collide with both, and
  getting it past them would take renaming, which would be evasion. FR-37 has the platform write
  per-control values, so the Driver never needs to. The writer lives in DomainCore, where those
  rules do not apply and where AD-3 keeps it out of reach of a Driver.
- No Driver consumes settings yet. Do not inject a handle into `SimulatedDriver` in this story
  (no unused stored property). The first consumer wires it from `GlycemicGPTApp`. FR-29's
  "per-Driver key-to-type table asserted in tests" applies once a Driver declares keys. For now
  the typed-read tests pin the "never a zero value" half.
- App location: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`
  plus `DriverSettings/`, next to the existing `DriverSelection/`. Look at how
  `AppComposition.driverSelectionFileURL` builds its path and add
  `AppComposition.driverSettingsDirectoryURL` beside it. Do not build the store in the app yet;
  with no consumer, nothing writes. If adding the URL helper alone looks like dead code, leave it
  out and say so in the record.

### Lifecycle state text on a row

| `DriverLifecycleState` | Text |
|---|---|
| notActivated | "Inactive" |
| activating | "Starting…" |
| active | "Active" |
| degraded | "Running with problems" |
| deactivating | "Stopping…" |
| failed | "Failed to start" |

Verification Status text, verbatim from the descriptor and never inferred from state:
`unverified` "Unverified", `protocolCompatible` "Protocol-compatible (unverified on hardware)",
`beta` "Beta", `hardwareVerified` "Verified on hardware". Transport: `bluetoothLowEnergy`
"Bluetooth", `network` "Network", `inProcess` "On device". Put each mapping in one `switch` in
the model file and test it.

The button follows **selection**, not lifecycle. Persisted means "Deactivate", otherwise
"Activate". A persisted Driver that is `failed` or deferred still shows "Deactivate", since it
holds its slot (registry `slots` doc), and the user needs a way to clear it.

Inline activation error: "Couldn't activate \<name\>." plus one line by case.
`.activationFailed` → "It didn't start. Try again."; `.persistenceFailed` /
`.persistenceFailedDriverStillLive` / `.selectionUnavailable` → "Your Driver choice couldn't be
saved. Try again."; `.evictionIncomplete` → "Another Driver didn't stop cleanly."; anything else →
"Try again." A deactivation error uses the same pattern with "Couldn't deactivate \<name\>."
Log the full error with `NSLog`, and log no health values.

### Confirmation copy and capability names

Android, `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/settings/SettingsScreen.kt`
lines 431-447 (copied here; your sandbox cannot read the Android repo):

```kotlin
AlertDialog(
    title = { Text("Deactivate Plugin") },
    text = { Text("Deactivating this plugin may stop glucose monitoring, insulin tracking, or other services it provides. Are you sure?") },
    confirmButton = { TextButton(...) { Text("Deactivate", color = MaterialTheme.colorScheme.error) } },
    dismissButton = { TextButton(...) { Text("Cancel") } },
)
```

`SettingsViewModel.kt:565-594`: deactivation is only reachable through `showDeactivateConfirm`,
and the direct `deactivatePlugin` is `@Deprecated` and forwards to it. iOS goes further and does
not have the direct path at all.

iOS copy. "Plugin" becomes "Driver", the PRD's term, which FR-25 states in this exact form:
- Title: `Deactivate Driver`
- Message line 1: `Deactivating this Driver may stop glucose monitoring, insulin tracking, or other services it provides. Are you sure?`
- Line 2, after a blank line: `<Display name> provides: <names joined by ", ">.`
- Line 3: `Its settings are kept.`
- Buttons: `Deactivate` (`.destructive`), `Cancel` (`.cancel`)

Plain capability names, in `Capability.allCases` order:
- glucoseSource → "glucose readings"
- insulinSource → "insulin on board and dose history"
- pumpStatus → "pump status"
- bgmSource → "meter readings"
- dataSync → "data sync"
- doseCategoryProvider → "dose categories"

For the Simulated Driver this reads "Simulated Driver provides: glucose readings, insulin on board
and dose history." Line 2 is iOS-only: Android's dialog is generic. It is what makes the warning
name what stops. Record it as a deliberate addition.

### Reconnecting after reactivation

Today:

```swift
private func validateConnection() async {
    guard let ports else { return }
    ...
}
```

With no ports, a registry change is ignored, so a Driver activated from Settings is not picked up
until the next foreground. Change only the `ports == nil` branch. If `wantsActive` is true, call
`connect()`. That function already folds a concurrent call into `reconnectAfterConnect` through
its `connecting` guard. Use the existing pattern: `if connecting { reconnectAfterConnect = true }
else { await connect() }`.

This cannot loop. Without a holder, `connect()` ends in `.noActiveDriver` and changes nothing in
the registry. A connect that runs while the Driver is still `activating` gets `.holderNotRunning`.
The registry's next change (`active`) triggers another connect, which then succeeds. Check that
the existing `DriverHostTests` still pass unchanged, especially
`registryTeardownDropsPortsAndReconnectsToEmptySlot` and `sceneTransitionsDoNotReactivateRegistryDriver`.

### Release-build lifetime

`DriversModel` is held by `GlycemicGPTApp` in `@State`, as `HomeModel` is, and not by a weak
system reference. Its observer task captures `[weak self]` and the registry strongly, and is
cancelled in `deinit`. The alert is driven by observable state, not by a presenter object.

### Out of scope (later work; do not build)

- **1.12d, FR-34:** the event channel (see the top of this file).
- The full FR-166 Settings composition. This screen is a detail route that the later Settings
  section can host without moving the confirmation logic.
- Settings descriptors and per-control persistence UI (FR-37), and the Simulated Driver consuming
  settings (FR-35).
- Keychain credentials and pairing (FR-14, FR-18). Nothing exists to preserve yet.
- Confirmation on activation-with-eviction (FR-23). Only one Driver ships.
- FR-28's "drop the settings-store entry on initialization failure".

### Testing standards

- Swift Testing, `@MainActor` for model tests. No sleeps; synchronize with `eventually` and gates
  as `DriverHostTests` does. Release every gate a test closes.
- Settings tests use a fresh temp directory per test (`FileManager.default.temporaryDirectory`
  plus a UUID) and delete it afterwards.
- Known flake: `WallClockSchedulerTests`. You may re-run once; record it if you do.

### Project structure notes

- New: `Sources/DriverAPI/Settings/DriverSettings.swift`,
  `Sources/DomainCore/DriverSettingsStore.swift`, `Sources/AppFeature/DriversScreen.swift`, plus
  tests `Tests/DriverAPITests/DriverSettingsKeyTests.swift`,
  `Tests/DomainCoreTests/DriverSettingsStoreTests.swift`,
  `Tests/AppFeatureTests/DriversScreenTests.swift`.
- Changed: `Sources/AppFeature/AppNavigation.swift`, `Sources/AppFeature/AppShell.swift`,
  `Sources/AppFeature/DriverHost.swift` (one branch), `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`,
  `Tests/AppFeatureTests/AppNavigationTests.swift`, `Tests/AppFeatureTests/DriverHostTests.swift`,
  `Tests/DomainCoreTests/DriverRegistryTests.swift`.
- `driver_guards.sh` rule D: no `as?` / `is` on `Driver` or a port anywhere in the new code. A new
  DriverAPI subfolder is fine for rule A and the symbol scan. Run both guards.

### References

- [Source: epics.md Story 1.12 (FR-25, FR-29, FR-34)]
- [Source: prds/prd-ios-unofficial-2026-08-01/prd.md FR-25 (:569), FR-29 (:614), FR-34 (:689), FR-37 (:727) per-control persistence]
- [Source: architecture ARCHITECTURE-SPINE.md AD-1, AD-3, AD-6, AD-12, AD-13]
- [Source: 1-12b-registry-owns-driver-lifecycle-and-no-active-driver-error.md "Out of scope": the Drivers route decision and the confirmation copy]
- [Source: android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/settings/SettingsScreen.kt:431-447; SettingsViewModel.kt:565-594]

## Dev Agent Record

### Agent Model Used

GPT-6.1 Codex, cycle 1 (sandboxed, could not compile). Claude Opus 5.5, cycle 2 (finished, compiled, ran all gates and the simulator check).

### Debug Log References

- `swift build` and `swift test`: SwiftPM cannot write the user module cache in this sandbox. Retrying with a local cache and `--disable-sandbox` reached the GRDB fetch, which failed because `github.com` cannot be resolved here.
- `xcodebuild test`: CoreSimulatorService is unavailable and the package scheme could not be opened from this checkout.
- `xcodebuild build`: CoreSimulatorService is unavailable and package resolution hits the same module-cache permission failure.
- Direct `swiftc` module builds with `-disable-sandbox` succeeded for SafetyCore, DriverAPI, DomainCore, AppFeature and SimulatedDriver. The app entry point and all new and changed test files typechecked with Swift Testing's plugin.

### Completion Notes List

- Added the read-only Driver settings API, strict ASCII key validation, typed reads and a platform-owned, namespaced atomic file store. No app store instance was added because no Driver consumes settings yet; `AppComposition.driverSettingsDirectoryURL` was likewise left out to avoid a dead helper.
- Added the Drivers detail route, registry-backed model, selection-based action buttons, inline errors and deactivation confirmation. The iOS alert names the Driver's declared capabilities; this is a deliberate addition to Android's generic warning.
- Home now reconnects when registry changes arrive after its ports have been cleared, with no scene transition. Added a regression test for deactivation and reactivation with a reading.
- Reviewable source and test diff: about 646 added lines and 4 removed lines, excluding this record and checkpoint files.
- Passed: `bash scripts/guards/safety_guards.sh`, `bash scripts/guards/safety_guards.sh --self-test`, `bash scripts/guards/driver_guards.sh`, `bash scripts/guards/driver_guards.sh --self-test`, and `bash scripts/ci-local.sh --self-test`.
- The simulator could not run in this sandbox, so the two screenshots under `.build/` remain for the PM or next cycle. All nine gates were invoked; the Swift and Xcode gates are blocked as described above.

**Cycle 2 (Claude Opus 5.5):**

- Root cause of the `sceneTransitionsReadExactlyOncePerForeground` failure: the first `connect()` runs `DriverStartup`, which activates the Driver and makes the registry yield changes. The new `ports == nil` branch in `HomeModel.validateConnection()` saw those changes while `connecting` was true and set `reconnectAfterConnect`. `connect()` then looped, and `connectOnce()` ran a second full read sequence, so every foreground read twice.
- Fix (`DriverHost.swift`): the `ports == nil` branch now reconnects only when the glucose slot has a holder that is `active` or `degraded`. While a connect is in flight it sets a separate flag, `connectIfStillUnconnected`, and `connect()` loops on it only when that call ended without ports. A connect that succeeds no longer reads twice. Reactivation from Settings still reconnects without a scene change. No retry loop is possible because the extra pass runs only when a running holder appeared. The test is unchanged.
- `CapabilitySetTests.exactlySixPortsAreDeclared` also failed. It allowlists the protocols DriverAPI may declare outside `Capabilities/`, and this story adds `protocol DriverSettings` as specified. I added `DriverSettings` to `expectedNonPortProtocols`, with a doc comment that explains why: the platform implements it, it is read-only, and it supplies no safety state. **NEEDS-HUMAN (PM ack):** this widens an architecture allowlist, which the story's planning did not anticipate. The port set is unchanged at six.
- Deactivation prompt: when a Driver declares no capabilities, the "<name> provides: …" line is left out, so the prompt never reads "provides: .". This does not affect the Simulated Driver.
- Verified that `DriversModel` has no public deactivate path. `requestDeactivation` only sets the prompt, and `confirmDeactivation` acts only on a pending prompt. `DriverSettings` declares a single read member, and only `FileDriverSettingsStore` in DomainCore writes. The registry test checks that settings survive deactivate and reactivate. The store test checks that they survive a new store instance on the same directory, which stands in for a relaunch.
- Gates, all exit 0: `swift build`; `swift build -c release`; `swift test` twice (434 tests, both runs green, no flake re-run); both guard scripts and their `--self-test`; `ci-local.sh --self-test`; `xcodebuild test` on the package scheme (iPhone 17, iOS 26.5); the Debug app build.
- Simulator check (Release build, uninstalled and reinstalled first, launched with `-onboardingComplete YES`): Settings → Drivers lists Simulated Driver, Active, Deactivate. Tapping Deactivate shows the alert with the exact copy. Confirming switched the row to Inactive and Activate, removed the DEMO DATA banner, and Home read "No glucose source". Tapping Activate brought the banner back, and Home showed a fresh reading (new trend arrow and IOB value) with no relaunch. Screenshots: `.build/drivers-confirmation-alert.png` and `.build/home-after-reactivation.png`.
- Invented copy, beyond what the spec pins: the row labels "Protocol: ", "Version: " and "Verification Status: ", and the "\n" between the inline error's two lines. The capability line in the deactivation alert is an iOS-only addition, as the spec says.
- Final reviewable diff (Sources, Tests and Apps, untracked files included): 663 added and 5 removed, across 14 files.

**Review fixes (Claude Opus 5.5):**

- Home: the `ports == nil` branch of `validateConnection()` now starts `connect()` in a detached task, so the registry observer never parks on a Driver read. `dropConnection` abandons an in-flight connect (token cleared; everything after is generation-guarded, including the previously unguarded `.portUnavailable` path) and starts a fresh one, so a read that never returns cannot block reconnection. `reconnectAfterConnect` is gone. The registry gained `activationEpoch(of:)`; Home records it before reading ports and drops the connection when it moves, so a coalesced deactivate+activate does not keep stale ports. New test `deactivationDuringHeldActivationReadIsFollowed` (fails with the old awaited connect).
- Drivers screen: rows show "Starting…"/"Stopping…" as soon as an operation starts; selected Drivers sharing a single-instance capability with the one being activated show "Stopping…" and cannot be activated or deactivated until the swap ends. Activate is also disabled for rows whose lifecycle is `activating`/`deactivating`.
- Selection unreadable (`.unavailable`): the screen shows "Your driver selection can't be read until the phone is unlocked" and every action is disabled. Registry exposes `selectionLoadFailure`.
- Settings files are named from the lowercased identifier; the registry refuses identifiers that collide case-insensitively (`duplicateIdentifier`).
- Unreadable/corrupt/unsupported-version settings files are logged with `NSLog` (Driver id and failure kind only). **Follow-up:** a repair or quarantine path for such files is not built; the file is left in place and reads return nil.
- Invented copy added: "Starting…" and "Stopping…" as busy labels (same text as the lifecycle labels, new role), and "Your driver selection can't be read until the phone is unlocked".
- Gates, all exit 0: `swift build`, `swift build -c release`, `swift test` twice (439 tests), both guard scripts plus `driver_guards.sh --self-test`, `xcodebuild test` on the package scheme, Debug app build.
- Reviewable diff now 911 added / 17 removed across 15 files (Sources, Tests, Apps), over the 800-line budget; flag for PR sizing.

### File List

- `Sources/DriverAPI/Settings/DriverSettings.swift`
- `Sources/DomainCore/DriverSettingsStore.swift`
- `Sources/AppFeature/DriversScreen.swift`
- `Sources/AppFeature/AppNavigation.swift`
- `Sources/AppFeature/AppShell.swift`
- `Sources/AppFeature/DriverHost.swift`
- `Sources/DomainCore/DriverRegistry.swift`
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
- `Tests/DriverAPITests/DriverSettingsKeyTests.swift`
- `Tests/DomainCoreTests/DriverSettingsStoreTests.swift`
- `Tests/DomainCoreTests/DriverRegistryTests.swift`
- `Tests/AppFeatureTests/DriversScreenTests.swift`
- `Tests/AppFeatureTests/AppNavigationTests.swift`
- `Tests/AppFeatureTests/DriverHostTests.swift`
- `Tests/DriverAPITests/CapabilitySetTests.swift` (allowlist: `DriverSettings`)

### PM decisions on drafting open points (2026-11-01)
- **Naming.** 1.12c is named for its real scope. FR-34's event channel moves to 1-12d, which goes into the tracker as backlog.
- **FR-37 remainder.** The other seven card element types, icons, detail screens and settings descriptors become a tracked follow-up, 1-18b, in backlog. This story ships the closed vocabulary subset only.
- **FR citation.** The card sort rule lives in FR-37/FR-39. The epic's FR-38 citation will be corrected in the next docs sync. Implement against FR-37/FR-39.
- **Parallel work.** 1.12c and 1.18 run at the same time and both touch DriverAPI. 1.12c adds a NEW file for the settings protocol. 1.18 adds one requirement with a default in `Driver.swift`. Neither should reformat or reorder the other's area, so the two merge cleanly.
- budget: CONTINUATION_REQUIRED sha256:b40ec5a7dcd04f2043bb73daacd9b60fb4a94fa73a146c5f1561052e5970a8b9 cycle 1 2026-11-02T01:41:20Z

### PM sign-off (2026-11-01)
- Accepted: `DriverSettings` was added to the DriverAPI protocol allowlist in `CapabilitySetTests.exactlySixPortsAreDeclared`. It is a read-only settings handle and not a capability port. The six capability ports and AD-3's closed capability set are unchanged.

- PM: the size (about 930 changed lines, over the 800 budget) is accepted. The excess is review-driven concurrency fixes and their tests.
