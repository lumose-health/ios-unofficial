---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-17b-permissions-and-the-monitoring-limits-warning.md.stamp.json
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

> **Depends on PR #19 being merged; dispatch after merge.** This builds on the onboarding flow
> from PR #19 (`feat/onboarding`): `OnboardingModel`, its private `complete()`, `OnboardingFlowView`
> and the Safety stage. Branch from `develop` after #19 lands.

# Story 1.17b: Permissions on both completion paths, and the monitoring-limits warning

<!-- Planning note (for the maintainer): the second half of epics.md Story 1.17. 1.17a (PR #19)
shipped the five-stage flow, the safety gate and both completion paths. This file adds FR-165
(notification and Bluetooth authorization on both completion paths, behind an injected protocol)
and the FR-15/FR-85 warning that force-quitting, restarting the phone and Low Power Mode stop or
reduce monitoring. Estimate: ~450-550 reviewable lines over ~8 files, about half tests. Inside the
800-line budget, so no split. Touches the Xcode project's build settings (one Info.plist key, three
configurations), which no earlier story has done. No dosing, alert floor, ingestion mapper,
safety_validation, dependency, CI, DriverAPI, SafetyCore or Persistence change. Route: NOT chosen
here; the PM routes via /v1/route. -->

## Story

As a new user,
I want the app to ask for the permissions it needs while I am setting it up, and to tell me what stops it from watching,
so that I am not surprised later by an alarm that never came.

## Acceptance Criteria

From epics.md Story 1.17 (the two bullets 1.17a deferred: FR-165, and the restart/force-quit
disclosure from FR-15 and FR-85), with the PRD's testable consequences.

1. **One injected seam for both permissions (FR-165).** `AppFeature` declares
   `OnboardingAuthorizations: Sendable` with two async, non-throwing requests: notification
   authorization (taking a `NotificationAuthorizationOptions` value) and Bluetooth authorization.
   Each returns a closed outcome enum (see Tasks). `OnboardingModel` receives it through `init`.
   The parameter has **no default value**, so no call site can silently skip the prompts. Tests use
   recording doubles; no test touches `UNUserNotificationCenter` or Core Bluetooth.

2. **Exactly one notification request, full option set, never provisional (FR-165).** The model
   passes `NotificationAuthorizationOptions.onboarding`, which is exactly `[.alert, .sound, .badge,
   .criticalAlert]`. A test asserts the double saw exactly one notification call per completion, that
   the options equal those four, and that they do not contain `.provisional`. The live adapter maps
   the value to `UNAuthorizationOptions` in a single `requestAuthorization(options:)` call. No other
   code in the app requests notification authorization.

3. **Both completion paths request both permissions, resolved before the flag flips (FR-165).**
   "Use without a server" and a successful sign-in each run the same completion sequence:
   1. request notification authorization and await the outcome;
   2. then request Bluetooth authorization and await the outcome (sequential, never two system
      prompts at once);
   3. then record onboarding complete in `UserDefaults`;
   4. then set `isFinished`.

   A gated double proves the order: while either request is suspended, `isFinished` is false and
   `OnboardingCompletion.isComplete(in: defaults)` is false. This is the one place where iOS differs
   from Android, which writes its persistent flag before the prompt (Dev Notes, "Why the flag is
   written after the prompts").

4. **A denial never blocks finishing onboarding.** Every outcome of each request, `granted`,
   `denied` and `failed` for notifications and `allowed`, `denied`, `restricted` and `unsupported`
   for Bluetooth, leads to steps 3 and 4. A test drives all 12 combinations through
   "Use without a server" and asserts `isFinished` and the persisted flag each time. There is no
   retry prompt, no extra screen, no "are you sure" and no nag (FR-164: Backend-optional mode and
   its choices are supported, not errors). The outcomes are kept on the model as
   `authorizationResult` for later surfaces. Nothing about them is persisted (Dev Notes, "What a
   denial does in this build").

5. **Re-entrancy.** While the completion sequence runs (`isCompletingSetup == true`), a second
   `continueWithoutServer()` or `signIn()` returns `nil` and makes no request. The safety gate from
   1.17a still applies: neither path does anything before the Safety stage is acknowledged.
   "Use without a server" stays visible and enabled, as FR-164 requires; the model ignores the
   repeat tap. A failed sign-in requests nothing.

6. **Cancellation ordering from 1.17a still holds.** A connection-test result that arrives after
   "Use without a server" changes nothing, including while the permission requests are suspended.

7. **The Bluetooth usage description is in the app's Info.plist.** The app target's Debug,
   Development and Release build configurations each gain
   `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` with the same string (Dev Notes). Without it,
   the first `CBCentralManager` terminates the app. No other key is needed: notifications need no
   usage string, and `NSBluetoothPeripheralUsageDescription` is obsolete at the iOS 17 deployment
   target. A host-side test reads `project.pbxproj` and asserts the key is present, with the exact
   string, in all three app-target configurations.

8. **The monitoring-limits warning appears during onboarding (FR-15, FR-85, epics.md 1.17).** The
   Safety stage gains one block after the no-therapeutic-write sentence, with identifier
   `onboarding_monitoring_limits`. It is not a sixth safety card (FR-160 fixes five) and not a sixth
   stage (FR-159 fixes five). It holds a title and three statements, with every string in
   `OnboardingCopy` and pinned by a test:
   - Title: "What stops monitoring"
   - "Force-quitting GlycemicGPT from the app switcher stops monitoring, including reconnecting to
     your pump, until you open the app again."
   - "Restarting your phone stops monitoring until you unlock it once."
   - "Low Power Mode cuts some of the background time GlycemicGPT uses to stay up to date."

   The Safety stage is unskippable, so every user on either path sees the block before finishing.
   The copy is invented (Dev Notes) and is listed under "Invented copy — maintainer review before
   public TestFlight" in the Dev Agent Record.

9. **The live adapters live in the app target.** `SystemOnboardingAuthorizations` sits in
   `Apps/GlycemicGPT/App/` and is passed to `OnboardingModel` there. `AppFeature` imports neither
   `UserNotifications` nor `CoreBluetooth`. The Bluetooth adapter's `CBCentralManager` exists only to
   raise the prompt. It has no restoration identifier, is released once the outcome is known, and
   never scans or connects.

10. **Gates.** All nine frontmatter gates pass. The PM runs the simulator check in Dev Notes.

## Tasks / Subtasks

- [ ] Task 1: the seam, options and outcomes (AC 1, 2, 4)
  - [ ] In `Sources/AppFeature/Onboarding.swift` (or a new `Sources/AppFeature/OnboardingAuthorizations.swift`
        if `Onboarding.swift` gets crowded), add:
    ```swift
    public struct NotificationAuthorizationOptions: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let alert = Self(rawValue: 1 << 0)
        public static let sound = Self(rawValue: 1 << 1)
        public static let badge = Self(rawValue: 1 << 2)
        public static let criticalAlert = Self(rawValue: 1 << 3)
        public static let provisional = Self(rawValue: 1 << 4)
        /// The single request made during onboarding. iOS shows the prompt once per install,
        /// so a later request for critical alerts would silently do nothing.
        public static let onboarding: Self = [.alert, .sound, .badge, .criticalAlert]
    }
    public enum NotificationAuthorizationOutcome: Sendable, Equatable { case granted, denied, failed }
    public enum BluetoothAuthorizationOutcome: Sendable, Equatable { case allowed, denied, restricted, unsupported }
    public struct OnboardingAuthorizationResult: Sendable, Equatable {
        public let notification: NotificationAuthorizationOutcome
        public let bluetooth: BluetoothAuthorizationOutcome
    }
    public protocol OnboardingAuthorizations: Sendable {
        func requestNotificationAuthorization(options: NotificationAuthorizationOptions) async -> NotificationAuthorizationOutcome
        func requestBluetoothAuthorization() async -> BluetoothAuthorizationOutcome
    }
    ```
    `1 << 4` and friends are bit positions, not safety values. Keep them as shifts so no bare
    literal lands in a guard band.
- [ ] Task 2: the completion sequence in `OnboardingModel` (AC 3, 4, 5, 6)
  - [ ] `init(backend:authorizations:defaults:startStage:)`, with `authorizations` required.
  - [ ] Add `public private(set) var isCompletingSetup = false` and
        `public private(set) var authorizationResult: OnboardingAuthorizationResult?`.
  - [ ] Replace the private `complete()` with
        `private func complete() -> Task<Void, Never>`. It sets `isCompletingSetup = true` and
        returns a task that awaits the notification request, then the Bluetooth request, stores
        `authorizationResult`, calls `OnboardingCompletion.record(true, in: defaults)`, sets
        `isFinished = true`, then clears `isCompletingSetup`. Capture `authorizations` and
        `defaults` explicitly, and `[weak self]` like the existing tasks.
  - [ ] `continueWithoutServer()` becomes
        `@discardableResult public func continueWithoutServer() -> Task<Void, Never>?`. Guard:
        `pastSafetyGate, !isFinished, !isCompletingSetup`, else return `nil`. Cancel the connection
        test and clear the Backend fields **synchronously** first, exactly as today, then
        `return complete()`.
  - [ ] In `signIn()`'s task, on `.signedIn` await `complete().value` instead of calling the old
        `complete()`. Add `!isCompletingSetup` to its entry guard.
  - [ ] `OnboardingFlowView`: the "Use without a server" button calls
        `_ = model.continueWithoutServer()`. No visual change to it. `onChange(of: model.isFinished)`
        is unchanged.
- [ ] Task 3: the warning block (AC 8)
  - [ ] `OnboardingCopy`: `monitoringLimitsTitle`, and `monitoringLimits: [String]` holding the
        three statements in order. `OnboardingIdentifier.monitoringLimits = "onboarding_monitoring_limits"`.
  - [ ] In the Safety stage view, after the no-therapeutic-write `Text`, add a `VStack(alignment:
        .leading, spacing: 4)` with the title (`.subheadline.weight(.semibold)`) and the three
        statements (`.subheadline`, `.primary`), on the same `.fill.tertiary` rounded background
        and 12pt padding as the safety cards. Make it one accessibility element
        (`.accessibilityElement(children: .combine)`) with the identifier. No icon, so no new
        SF Symbol.
- [ ] Task 4: live adapters in the app target (AC 2, 9)
  - [ ] New `Apps/GlycemicGPT/App/SystemOnboardingAuthorizations.swift` (the app group is
        file-system synchronized, so no project-file entry is needed for the file). See Dev Notes,
        "Live adapters", for the shape.
  - [ ] `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: pass `SystemOnboardingAuthorizations()` to
        `OnboardingModel`.
- [ ] Task 5: Info.plist key (AC 7)
  - [ ] In `Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj`, add
        `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "<string>";` to the three **app target**
        configurations: `A10000000000000000000060` (Debug), `A10000000000000000000061`
        (Development) and `A10000000000000000000062` (Release). Keep the alphabetical position
        before `INFOPLIST_KEY_UILaunchScreen_Generation`. Do **not** touch the project-level
        configurations `...63`, `...64` and `...65`. Change nothing else in the file.
  - [ ] New `Tests/SafetyCoreTests/XcodeProjectSettingsTests.swift`. Read the pbxproj the way
        `PackageManifestTests` reads `Package.swift` (`#filePath` → repository root). For each of
        the three app-target configuration ids, find its line and assert it contains
        `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "` followed by the exact string. Also
        assert the key appears exactly three times in the file.
- [ ] Task 6: tests (`Tests/AppFeatureTests/OnboardingTests.swift`, `AppNavigationTests.swift`)
  - [ ] Add a `RecordingAuthorizations` actor double: it records each call in order (including
        the options), returns configurable outcomes, and can optionally gate each request on a
        continuation released by the test. Add a `makeModel(...)` helper so the 12 existing
        constructions change in one place.
  - [ ] Update the existing tests that call `continueWithoutServer()` and then check `isFinished`
        straight away: await the returned task first. Keep each test's intent.
  - [ ] New tests:
    - options are exactly the four, contain no `.provisional`, and one notification call per
      completion (both paths)
    - call order is notification, then Bluetooth, then the flag, on both paths (gated double: while
      suspended, `isFinished == false` and the flag is unset)
    - all 12 outcome combinations finish onboarding and set the flag; `authorizationResult` holds
      the pair
    - a second `continueWithoutServer()` while completing returns `nil` and the double still saw
      one call of each kind
    - a failed sign-in makes no request
    - neither path requests anything before the safety acknowledgement
    - the gated connection-test cancellation test from 1.17a still passes while the permission
      requests are gated
    - every new `OnboardingCopy` string and the new identifier, pinned exactly
  - [ ] `AppNavigationTests.shellKeepsBannerAtRootForBothDestinations`: pass a double.
- [ ] Task 7: gates, Dev Agent Record and diff size (AC 10)

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

### Read first (rules of the road)

- **Edit only these paths:**
  - `Sources/AppFeature/Onboarding.swift`, `Sources/AppFeature/OnboardingView.swift`, and
    optionally a new `Sources/AppFeature/OnboardingAuthorizations.swift`
  - `Apps/GlycemicGPT/App/GlycemicGPTApp.swift` and the new
    `Apps/GlycemicGPT/App/SystemOnboardingAuthorizations.swift`
  - `Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj`, the three build-setting lines only
  - `Tests/AppFeatureTests/OnboardingTests.swift`, `Tests/AppFeatureTests/AppNavigationTests.swift`
  - the new `Tests/SafetyCoreTests/XcodeProjectSettingsTests.swift`
  - this file's Dev Agent Record

  Do **not** edit `Package.swift`, `Sources/DriverAPI/**`, `Sources/Drivers/**`,
  `Sources/SafetyCore/**`, `Sources/Persistence/**`, CI files or the guards. If you need one of
  them, write a NEEDS-HUMAN line in the Dev Agent Record.
- **No entitlement changes.** Requesting `.criticalAlert` without the Critical Alerts entitlement
  is harmless (FR-165); iOS treats it as a normal alert request. Do not add an entitlements file,
  and do not add `UIBackgroundModes`. Background Bluetooth belongs to the pump Driver work.
- **No wall-clock reads under `Sources/`** (AD-14). The completion sequence needs no time, no
  timeout and no sleep.
- **No therapeutic write (SI-1).** The Bluetooth adapter never scans, connects or writes.
- **Scratch files only under `.build/` in your worktree. One operation per Bash call.** Your
  sandbox likely cannot run SwiftPM or the Simulator; the launcher re-runs every gate. Run
  `swiftc -frontend -parse` on each edited Swift file if you can.

### Existing code to build on (PR #19, `feat/onboarding`)

- `Sources/AppFeature/Onboarding.swift`:
  - `OnboardingModel` is `@MainActor @Observable`, built with
    `init(backend:defaults:startStage:)`. `startStage >= .backend` implies `safetyAcknowledged`.
  - `pastSafetyGate` is true when the stage is `.backend` or later and safety is acknowledged.
  - `continueWithoutServer()` is synchronous today: guard `pastSafetyGate, !isFinished`; cancel
    `connectionTask`; clear URL, result, success and testing; then `complete()`.
  - `signIn()` returns its `Task`. On `.signedIn` it calls `complete()`.
  - `private func complete() { OnboardingCompletion.record(true, in: defaults); isFinished = true }`.
    1.17a kept this as one method so this change happens in one place.
  - `testConnection()`'s task applies its result only if `!Task.isCancelled` and the URL still
    matches. That keeps AC 6 true without extra work, as long as `continueWithoutServer()` still
    cancels and clears synchronously before the permission task starts.
  - `OnboardingCopy`, `OnboardingIdentifier` and `OnboardingSymbol` hold every string, identifier
    and symbol.
- `Sources/AppFeature/OnboardingView.swift`: `OnboardingFlowView`. The Safety stage is the
  `safety` computed view, a `VStack(alignment: .leading, spacing: 8)` ending with the
  no-therapeutic-write `Text`.
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift` builds
  `OnboardingModel(backend: UnavailableOnboardingBackend(), defaults: .standard)` in `init()`.
- `Tests/AppFeatureTests/OnboardingTests.swift` has a gated Backend double (an actor around a
  `CheckedContinuation`) to copy for the gated authorizations double. It builds each model with its
  own `UserDefaults(suiteName:)` and removes the domain afterwards.
- `project.pbxproj`: the app target's three `XCBuildConfiguration` objects are single lines with
  ids `A10000000000000000000060`, `...61` and `...62`. Each already has
  `GENERATE_INFOPLIST_FILE = YES;` and `INFOPLIST_KEY_UILaunchScreen_Generation = YES;`.

### Why the flag is written after the prompts

Android (`OnboardingViewModel.kt`) sets the persistent `onboardingComplete` **before** raising the
notification prompt, and flips only the navigation flag after it. On iOS that order has a hole. If
the app dies while the prompt is up (force-quit, crash, low-memory kill), the next launch skips
onboarding. The prompt was never answered, so notification authorization is still undetermined and
nothing ever asks again. The Backend-optional user then has no alert channel and nothing tells them.
FR-165 calls this path the safety-critical one. Writing the flag after both outcomes are known
means the worst case is seeing onboarding once more. Record this deviation from Android in the
Dev Agent Record.

### What a denial does in this build

| Outcome | Effect now | Where the rest lives |
|---|---|---|
| Notifications denied, or the request throws (`failed`) | Onboarding finishes. Nothing else changes. This build raises no glucose alert at all (the Alerts tab says so), so nothing is being suppressed yet. | FR-165's "first dashboard shows the Coverage Claim as not watching, naming the denied permission" needs the Coverage Claim (Epic 4). That surface reads the **live** setting from `UNUserNotificationCenter.getNotificationSettings()` when it renders, so nothing is persisted here. FR-171's notification status card is Settings work. |
| Bluetooth denied or restricted | Onboarding finishes. There is no pump Driver, so nothing changes. | The pairing wall and Bluetooth state handling (prd §5.1, epics.md 1.19) read `CBManager.authorization` live. |
| Bluetooth unsupported (the Simulator) | Onboarding finishes. | Same. |

`authorizationResult` stays on the model for tests and later surfaces. It is not persisted,
because a stored copy would go stale the moment the user changes it in iOS Settings.

### Live adapters (app target, iOS only)

`Apps/GlycemicGPT/App/SystemOnboardingAuthorizations.swift`:

```swift
import AppFeature
import CoreBluetooth
import UserNotifications

struct SystemOnboardingAuthorizations: OnboardingAuthorizations {
    func requestNotificationAuthorization(options: NotificationAuthorizationOptions) async -> NotificationAuthorizationOutcome {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: Self.map(options))
            return granted ? .granted : .denied
        } catch {
            return .failed
        }
    }
    func requestBluetoothAuthorization() async -> BluetoothAuthorizationOutcome {
        await BluetoothAuthorizationProbe.request()
    }
    // map: .alert → .alert, .sound → .sound, .badge → .badge, .criticalAlert → .criticalAlert,
    // .provisional → .provisional. Exhaustive over the five static members.
}
```

`BluetoothAuthorizationProbe`, in the same file:
- `@MainActor final class BluetoothAuthorizationProbe: NSObject, CBCentralManagerDelegate`.
- `static func request() async -> BluetoothAuthorizationOutcome`:
  - If `CBManager.authorization != .notDetermined`, map it straight away and return, with no manager
    created.
  - Otherwise create one probe, which creates
    `CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])`.
    Creating the manager is what raises the prompt. Await `withCheckedContinuation` until the
    first `centralManagerDidUpdateState`, resume it **once** (state updates can repeat), and drop
    the manager.
- `nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager)`: read
  `central.state` there, then `MainActor.assumeIsolated { ... }` to resume. That is valid because
  `queue: nil` delivers callbacks on the main queue.
- Mapping: `.allowedAlways` → `.allowed`; `.denied` → `.denied`; `.restricted` → `.restricted`;
  still `.notDetermined` → `.unsupported`. If the state is `.unsupported`, return `.unsupported`
  whatever the authorization says. Use `@unknown default` → `.unsupported`.
- **No `CBCentralManagerOptionRestoreIdentifierKey`.** AD-11 makes restoration-identified managers
  a launch-time duty of the paired Driver, derived from its id. A prompt-only manager with a
  restoration identifier would ask iOS to relaunch the app for a manager that no longer exists.
- The project sets `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, and the app target compiles in Swift 6
  mode. Any Sendable or isolation warning fails the app build gate. Keep every Core Bluetooth object
  inside the probe, on the main actor.
- Known risk, accepted: the request waits for Core Bluetooth's first state callback, with no
  timeout. Core Bluetooth always delivers one after creating a manager. A timeout would cut off a
  user who is still reading the prompt.

**Usage-description string** (invented; list it under invented copy):
"GlycemicGPT uses Bluetooth to connect to your insulin pump and read its status. It never sends
commands that change your insulin delivery."
It states the read-only posture (SI-1) and names the purpose, as App Review expects.

### Warning copy: where it comes from

- epics.md 1.17: "the user is told during onboarding that restarting the phone or force-quitting
  the app stops monitoring".
- FR-85 fixes three facts and requires plain words: (a) force-quitting from the app switcher
  disables all background relaunch, including Bluetooth reconnection, until the app is reopened;
  (b) nothing runs after a restart until the phone is unlocked once; (c) Low Power Mode removes the
  opportunistic background refresh path. FR-15 requires the force-quit statement in onboarding
  and forbids implying any mitigation exists.
- §7 PL-13/PL-14 say "verbatim", but the PRD gives no verbatim text. **Android has no source copy**
  (it restarts on boot through `BootCompletedReceiver`, and its only related string is the
  battery-optimisation card in `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/settings/SettingsScreen.kt`,
  around line 2576, which §7 PL-52 says is not ported).
- So the copy in AC 8 is invented. It differs from the draft in 1.17a's Dev Agent Record in two ways:
  - Each sentence uses the epic's words "stops monitoring", so the requirement is visibly met.
  - FR-85(a)'s "any future push" is left out. There is no push channel (FR-157 defers APNs), and
    the copy must not describe one.
- It promises no mitigation (FR-15): no "we'll reconnect", no "turn this off to fix it".

### Architecture compliance

- **AD-1/AD-3:** the seam is declared in `AppFeature`; the platform adapters live in the thin app
  target, whose job `Package.swift` already describes as device composition. `AppFeature` gains no
  framework import.
- **AD-11:** the prompt-only manager carries no restoration identifier.
- **AD-13:** a denial is an outcome, not an error. Nothing substitutes "granted" for an unknown.
- **AD-14:** no time reads.
- **SI-5/SI-6:** both paths ask. The flag waits for the answers. Nothing claims an alert channel
  exists.
- **SI-1:** the adapter only asks for permission; the usage string says the app never changes
  delivery.

### Out of scope (later work; do not build)

- The Coverage Claim and its Not-Watching Reason for denied notifications (Epic 4), FR-171's
  notification status card and FR-166's Reliability card (Settings).
- The force-quit statement in Settings while a pump is paired, and in the pairing documentation
  (FR-15). FR-85's last-ran timestamp, gap detection and lapse notification.
- Bluetooth state handling, scanning, pairing and restoration (prd §5.1, epics.md 1.19).
- Any critical-alert entitlement request.
- XCUITest. There is still no UI-test target.

### Simulator check for the PM after the gates pass

1. Launch with `-onboardingComplete NO` on a fresh simulator. Go through to the Safety stage and
   check the "What stops monitoring" block in Light and Dark Mode, and at the largest accessibility
   text size.
2. Tap "Use without a server". The notification prompt appears first. Deny it. The Bluetooth
   prompt (or nothing, if the Simulator reports Bluetooth unsupported) follows. Home appears either
   way.
3. Reset the simulator, repeat, and allow both. Home appears.
4. Kill the app while the notification prompt is up, then relaunch. Onboarding shows again
   (the flag was not written).

### Testing standards

- Swift Testing, `@MainActor` where the model is used. No sleeps. To wait for a gated double, loop
  on `await Task.yield()` until it reports a pending call, as the 1.17a tests do.
- `withCheckedContinuation` is not cancellation-aware. Every test that gates a request must
  release it.
- `AppFeatureTests` cannot depend on the app target, so the live adapters have no unit tests. The
  simulator check above covers them. Keep them thin enough that this is reasonable.
- Known flake: `WallClockSchedulerTests`. You may re-run once; record it if you do.

### Project structure notes

- New:
  - `Apps/GlycemicGPT/App/SystemOnboardingAuthorizations.swift`
  - `Tests/SafetyCoreTests/XcodeProjectSettingsTests.swift`
  - optionally `Sources/AppFeature/OnboardingAuthorizations.swift`
- Modified:
  - `Sources/AppFeature/Onboarding.swift`
  - `Sources/AppFeature/OnboardingView.swift`
  - `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
  - `Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj` (three lines)
  - `Tests/AppFeatureTests/OnboardingTests.swift`
  - `Tests/AppFeatureTests/AppNavigationTests.swift`
- Branch from `develop` after #19 merges, for example `feat/onboarding-permissions`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 1.17]
- [Source: prds/prd-ios-unofficial-2026-08-01/prd.md FR-15 (:397), FR-85 (:1459), FR-157,
  FR-159, FR-164, FR-165 (:3122), FR-166, FR-171; §7 PL-13, PL-14, PL-52 (:5674)]
- [Source: ARCHITECTURE-SPINE.md: AD-1, AD-3, AD-11 (:127), AD-13, AD-14]
- [Source: 1-17a-first-run-welcome-safety-and-backend-stage.md, "Deferred to 1.17b" and the PM
  decisions]
- [Source: android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/onboarding/OnboardingViewModel.kt
  (`continueWithoutServer`, `login`, `onNotificationPermissionHandled`, around lines 180-250) and
  OnboardingScreen.kt (the permission launcher, around lines 90-105)]

## Dev Agent Record

### Agent Model Used

Codex / Amelia implementation session.

### Debug Log References

- `swiftc -frontend -parse` passed for all edited Swift sources and tests.
- `git diff --check` passed.
- `swift build` and `swift test` were attempted; SwiftPM could not compile its manifest because the sandbox denied writing to `~/.cache/clang/ModuleCache` and the user SwiftPM cache.
- `bash scripts/guards/safety_guards.sh`: passed.
- `bash scripts/guards/safety_guards.sh --self-test`: passed (75 cases, 2 documented known bypasses).
- `bash scripts/guards/driver_guards.sh`: passed.
- `bash scripts/guards/driver_guards.sh --self-test`: passed (68 cases, 3 documented known limits).
- `bash scripts/ci-local.sh --self-test`: passed.
- Required `xcodebuild test` was attempted; this checkout was not recognized as a project/workspace/package by that command, and CoreSimulator services were unavailable.
- Required app `xcodebuild build` was attempted; package resolution was blocked by the same sandbox-denied user cache write and unavailable CoreSimulator services.

### Completion Notes List

- Added a required `OnboardingAuthorizations` dependency and a single sequential notification-then-Bluetooth completion sequence. The onboarding flag is written only after both outcomes return; denials and failures remain non-blocking.
- Added tests for all 12 outcome combinations, exact notification options, sequential gated requests on both completion paths, re-entrancy, failure, safety-gate behavior, and stale connection cancellation while requests are suspended.
- Added the monitoring-limits warning block to the existing Safety stage without adding a card or stage.
- Added the app-target system adapter and the Bluetooth usage description to Debug, Development and Release only.
- The authorization result is held in memory only. No permission result is persisted.
- The flag ordering intentionally differs from Android because termination during a system prompt must leave onboarding available on the next launch.
- **Invented copy — maintainer review before public TestFlight:** monitoring-limits title and three statements; Bluetooth usage description.
- All source/test parsing and repository guards passed. The package and Xcode gates remain unverified because the execution sandbox could not access required user caches/CoreSimulator.

### File List

- `Sources/AppFeature/Onboarding.swift`
- `Sources/AppFeature/OnboardingView.swift`
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
- `Apps/GlycemicGPT/App/SystemOnboardingAuthorizations.swift`
- `Apps/GlycemicGPT/GlycemicGPT.xcodeproj/project.pbxproj`
- `Tests/AppFeatureTests/OnboardingTests.swift`
- `Tests/AppFeatureTests/AppNavigationTests.swift`
- `Tests/SafetyCoreTests/XcodeProjectSettingsTests.swift`

### PM decisions on drafting open points (2026-11-01)
- **Invented copy is accepted for internal demo builds.** That covers the monitoring-limits warning, the Bluetooth usage string and the Home "no glucose source" / "didn't start" messages. List every invented string in the Dev Agent Record under "Invented copy — maintainer review before public TestFlight".
- **1.12 naming.** The file is named for its actual scope, `1-12b-registry-owns-driver-lifecycle-and-no-active-driver-error`. Deactivation confirmation, per-Driver settings and the event channel go to `1-12c` (and `1-12d` if needed).
- **Demo hero after returning from background.** It is acceptable for the hero to show a reading up to 5 minutes old after the app comes back, provided the age caption and freshness tier show the true age. The foreground read on return reads the latest sample. Never re-timestamp a sample to look fresh.
- **Critical alert option in the notification request.** Requesting `.criticalAlert` before Apple grants the entitlement is accepted. The option has no effect until the entitlement exists. Add a doc comment saying so.

### PM note before dispatch (2026-11-01)
- PR #19 merged with two late changes you must build on:
  - The onboarding model init now takes `safetyAcknowledged: Bool = false`. A later start stage without it lands on Safety.
  - `OnboardingPreview.showsNotice` drives an `onboarding_preview_notice` on Welcome and Backend.
- Story 1.12b runs in parallel and moves Driver lifecycle ownership into the registry (`GlycemicGPTApp.swift`, `DriverHost.swift`). Keep your app-target edits to the permission service and its injection point. Don't restructure the app root, so the two changes merge cleanly.

### PM note after review (2026-11-01)
- **Review blocker fixed.** The Bluetooth probe lifetime bug only showed up in optimized builds, where onboarding could hang forever. The probe now retains itself until it resumes. The fix was verified on a Release build in the simulator: Welcome → Safety → "Use without a server" → notification Allow → Home.
- **Validation gap.** The simulator has no Bluetooth, so the Bluetooth permission dialog never appears there. The real-device Bluetooth Allow and Deny paths are owed to community validation on the first internal TestFlight build.
- **Process change.** Every TestFlight candidate now gets a Release-configuration simulator run-through before upload.
- PM-applied fix: removed two copy lines that had been pasted into `OnboardingIdentifier` by mistake (duplicate declaration).
