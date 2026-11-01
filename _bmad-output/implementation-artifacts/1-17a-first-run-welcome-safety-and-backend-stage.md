---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-17a-first-run-welcome-safety-and-backend-stage.md.stamp.json
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

# Story 1.17a: First run — welcome, safety, and the Backend stage

Status: review

<!-- Planning note (for the maintainer):
SPLIT. epics.md Story 1.17 is too large for one reviewable PR. Honest estimate for the whole story
was ~950-1,050 reviewable lines (two new view files, a flow model, two live permission adapters,
an Info.plist build-setting change, the warning copy, and tests for all of it). This file is
1.17a ONLY: the five-stage flow, stage gating, the unskippable safety acknowledgement, the Backend
stage with its always-present "Use without a server" escape, the Sign-in stage behind an
injectable Backend port, and the onboarding-completion flag flip. Estimate for 1.17a: ~700-800
reviewable lines over 7 files, about 40% tests.

1.17b (NOT written yet; the PM writes it after 1.17a merges) carries: FR-165 notification and
Bluetooth authorization on both completion paths behind an injected protocol, the
NSBluetoothAlwaysUsageDescription build setting in the Xcode project, and the FR-15/FR-85
restart/force-quit/Low Power Mode warning copy. Proposed copy for 1.17b is recorded under
"Deferred to 1.17b" in Dev Notes so it does not get lost.

The file keeps the path the PM asked for; rename to a 1-17a-* name if the tracker wants the
13a/13b convention.

Route: NOT chosen here; the PM routes via /v1/route. Planning context: presentation and flow
state in AppFeature only. No dosing, alert floor, ingestion mapper, safety_validation, dependency,
CI, DriverAPI, SafetyCore or Persistence change. One cross-cutting behaviour change: an unset
onboarding flag now means "not onboarded" (see AC 9). -->

## Story

As a new user,
I want to get from install to a working monitor without being forced through a server setup I do not want,
so that Backend-optional mode is genuinely reachable.

## Acceptance Criteria

From epics.md Story 1.17 (FR-159, FR-160, FR-161, FR-164), with the PRD's testable consequences
and the Android client's exact strings and `testTag`s pinned. Notification/Bluetooth authorization
(FR-165) and the restart/force-quit warning (FR-15, FR-85) are **1.17b**, not this story.

1. **Five ordered stages (FR-159).** `OnboardingStage` has exactly five cases with raw values
   welcome=0, features=1, safety=2, backend=3, signIn=4. The start stage is `.backend` only when a
   saved Backend URL exists AND onboarding was previously completed; otherwise `.welcome`. There is
   no Backend URL storage yet, so the app always passes `hasSavedBackendURL: false` and always
   starts at Welcome; the pure rule is still implemented and tested.

2. **Controls per stage (FR-159), as a pure function.** Pinned table (Android
   `OnboardingScreen.kt` `OnboardingControls`):

   | Stage | Leading control | Trailing control |
   |---|---|---|
   | welcome (0) | "Skip" `skip_button` | "Next" `next_button`, enabled |
   | features (1) | "Skip" `skip_button` | "Next" `next_button`, enabled |
   | safety (2) | none | "I Understand" `next_button`, enabled |
   | backend (3) | "Back" `back_button` | "Next" `next_button`, enabled only after a connection test succeeded in this session |
   | signIn (4) | "Back" `back_button` | none (Sign In lives in the stage body) |

   "Skip" moves to stage 2 and never lands on 3 or 4. "Back" moves one stage back. Stages 0-2 show
   no back affordance.

3. **Swipe only before the safety stage (FR-159, FR-160).** There is no paging container
   (`TabView(.page)` is forbidden). A horizontal drag on stages 0 and 1 moves forward one stage
   (leftward drag) or back one stage (rightward drag on stage 1). On stages 2, 3 and 4 a drag does
   nothing. The rule lives in the model (`swipe(_:)` is a no-op when `stage.rawValue >= 2`) so it is
   unit-tested, not only enforced by the view.

4. **Unskippable safety acknowledgement (FR-160).** The only call that moves from `.safety` to
   `.backend` is `acknowledgeSafety()`, bound to the "I Understand" button. `next()`, `skip()` and
   `swipe(_:)` never leave `.safety` forward. The model holds `safetyAcknowledged`, false at init
   and set only by `acknowledgeSafety()`; the invariant `stage.rawValue > 2 ⇒ safetyAcknowledged` is
   asserted after every operation in the tests. The stage is never persisted or restored, and there
   is no deep link, so every launch that shows onboarding starts at Welcome and must pass through
   the button. Android has no checkbox, so neither does iOS: the button is enabled and is the single
   explicit action.

5. **Safety stage content (FR-160).** Title "Important Safety Information", then five cards in this
   order with Android's exact copy (see Dev Notes table), then the no-therapeutic-write sentence
   (SI-1) as its own `Text` with identifier `onboarding_no_therapeutic_writes`:
   "GlycemicGPT only reads from your pump. It never delivers a bolus, never changes your basal, and
   never changes a pump setting." `[ASSUMPTION: invented copy and identifier; Android has no such
   sentence. FR-160 requires a distinct, assertable sentence.]`

6. **Welcome and Features copy (FR-159).** Welcome: "GlycemicGPT" / "Your diabetes management
   companion" / "A direct pump monitor on its own — your on-call endo when you connect a server."
   (U+2014 em dash). Features: title "What You Get" and four cards; the AI card uses FR-159's iOS
   copy, the other three use Android's copy verbatim (Dev Notes table).

7. **Backend stage (FR-159, FR-161, FR-164).** Title "Connect a Server (Optional)"; body "A server
   adds AI, meal analysis, and caregiver features. You can skip it and use the app as a direct pump
   monitor." A URL field (`onboarding_server_url`, label "Server URL", placeholder
   "https://your-server.com"), a "Test Connection" button (`onboarding_test_connection`, reading
   "Testing..." while a test runs, disabled while testing or while the field is blank), a result
   line (`onboarding_connection_result`), the label "Don't run a server?" and a button "Use without
   a server" (`onboarding_continue_without_server`).
   - Testing a blank URL yields "Enter a server URL first" and calls the Backend port zero times.
   - The test goes through an injected `OnboardingBackend` port. The production value,
     `UnavailableOnboardingBackend`, always returns a failure; the result line then reads
     "Connection failed: this build can't connect to a server yet" in the error colour.
     `[ASSUMPTION: invented reason text; there is no Backend client in this build.]` Success (only
     reachable with a test double today) reads "Connected successfully" in the primary colour.
   - Editing the URL clears the result line and the success flag.
   - "Use without a server" is **always present and never disabled**, whatever the test state:
     never run, running, failed or succeeded. It is not hidden while a test runs.

8. **"Use without a server" completes onboarding (FR-164).** In this order: cancel any in-flight
   connection test; clear the URL, the result line, the success flag and the testing flag; record
   onboarding complete in `UserDefaults`; set `isFinished`. A test result arriving after
   cancellation changes nothing. A second call after `isFinished` is a no-op. The app then shows
   the main tab view (Home) without a relaunch. Nothing in this path makes a network request. A test
   drives a failing connection test and asserts onboarding still completes (FR-159's escape-hatch
   test).

9. **Unset flag now means "not onboarded".** `OnboardingCompletion.valueWhenUnset` becomes `false`
   and its doc comment says an unset key means the user has never finished onboarding. Effect on
   existing installs: no shipped build ever wrote `onboardingComplete`, so every existing install
   (all internal demo builds) sees onboarding once after upgrading. That is acceptable for internal
   demo builds and is stated here on purpose. The `-onboardingComplete YES` launch argument still
   skips onboarding for simulator runs and screenshots.

10. **Sign-in stage (FR-159, FR-161).** Title "Sign In"; body "Sign in to your GlycemicGPT server
    account to enable AI, meal, and caregiver features."; email field (`onboarding_email`, label
    "Email"), password field (`onboarding_password`, label "Password", secure entry), error line
    (`onboarding_login_error`, error colour), and a "Sign In" button (`onboarding_sign_in`,
    "Signing in..." while running, disabled while running or while either field is blank). In
    production this stage is unreachable because the Backend stage's "Next" needs a successful test;
    it is exercised with test doubles.
    - Blank email or password yields "Email and password are required" and calls the port zero times.
    - Port failure renders the port's message in the error line.
    - The password is cleared from model state on both success and failure.
    - Success records onboarding complete and sets `isFinished`, exactly like AC 8's tail. No
      token or URL is persisted (there is nowhere to persist it yet).

11. **Page indicators (FR-159).** Five dots with identifiers `page_indicator_0` to
    `page_indicator_4`; accessibility label "Page N of 5" (1-based), with ", current" appended on
    the selected one. Generated by a pure function that is unit-tested.

12. **Identifiers are Android `testTag`s, byte for byte (FR-177).** All identifiers come from one
    `OnboardingIdentifier` enum of `static let` strings, pinned by a test. The only iOS-only
    identifier is `onboarding_no_therapeutic_writes` (AC 5). `onboarding_enable_insecure_http` is
    NOT rendered in this story (FR-163 is out of scope).

13. **"Pair your pump": no stage, by design.** Onboarding ends on Home running the Simulated
    Driver under the existing DEMO DATA banner, with the status row showing "No pump" and Settings
    still saying "Pump pairing isn't available in this build yet." Nothing claims a pump is paired.
    Justification: FR-159 fixes exactly five stages and none of them is pairing; UJ-4 and
    epics.md 1.19 put the pairing entry point in Settings; there is no Tandem Driver to pair with.
    The honest "working monitor" today is the labelled Simulated demo.

## Tasks / Subtasks

- [ ] Task 1: flow model, pure helpers and copy (AC 1-4, 7, 8, 10-12)
  - [ ] New `Sources/AppFeature/Onboarding.swift`:
    - `public enum OnboardingStage: Int, CaseIterable, Sendable` with the five cases and
      `static func start(hasSavedBackendURL: Bool, onboardingPreviouslyComplete: Bool) -> Self`.
    - `public enum OnboardingSwipe: Sendable { case forward, backward }`.
    - `OnboardingControls` (pure, `Sendable`, `Equatable`): `leading: Leading?` where
      `Leading` is `.skip` or `.back`, and `trailing: Trailing?` where `Trailing` is
      `.next(enabled: Bool)` or `.understand`. `static func make(stage:connectionSucceeded:)`
      implements the AC 2 table.
    - `OnboardingPageIndicator` (pure): `static func label(index: Int, current: Int, count: Int) -> String`
      and `static func identifier(index: Int) -> String`.
    - `OnboardingCopy`: every user-visible string in this story as `static let`.
    - `OnboardingIdentifier`: every identifier as `static let`.
    - Backend port:
      ```swift
      public enum ConnectionTestOutcome: Sendable, Equatable { case connected, failed(reason: String) }
      public enum SignInOutcome: Sendable, Equatable { case signedIn, failed(message: String) }
      public protocol OnboardingBackend: Sendable {
          func testConnection(to url: String) async -> ConnectionTestOutcome
          func signIn(url: String, email: String, password: String) async -> SignInOutcome
      }
      public struct UnavailableOnboardingBackend: OnboardingBackend { public init() {} ... }
      ```
      `UnavailableOnboardingBackend` returns `.failed(reason: "this build can't connect to a server yet")`
      and `.failed(message: "Sign-in isn't available in this build yet.")`. It makes no request.
    - `@MainActor @Observable public final class OnboardingModel`:
      - `public private(set)`: `stage`, `safetyAcknowledged`, `serverURL`, `isTestingConnection`,
        `connectionResult: ConnectionResultLine?` (text + `isSuccess`), `connectionSucceeded`,
        `email`, `password`, `isSigningIn`, `loginError`, `isFinished`.
      - `init(backend: any OnboardingBackend, defaults: UserDefaults, startStage: OnboardingStage = .welcome)`.
      - `next()`, `back()`, `skip()`, `swipe(_:)`, `acknowledgeSafety()` per AC 2-4.
        `next()` on `.backend` moves only when `connectionSucceeded`; `next()` on `.safety` and
        `.signIn` does nothing.
      - `updateServerURL(_:)`, `updateEmail(_:)`, `updatePassword(_:)`. Editing the URL clears
        result and success. Editing email or password clears `loginError` (Android).
      - `@discardableResult func testConnection() -> Task<Void, Never>?`: blank (after trimming
        whitespace) → result "Enter a server URL first", no task, no port call. Otherwise, if not
        already testing, set testing, clear result, store and return a `Task` that awaits the port,
        then `guard !Task.isCancelled` before applying the outcome.
      - `func continueWithoutServer()`: AC 8 ordering, guarded by `isFinished`.
      - `@discardableResult func signIn() -> Task<Void, Never>?`: AC 10.
      - A private `complete()` that records `OnboardingCompletion.record(true, in: defaults)` then
        sets `isFinished = true`. Both completion paths call it. (1.17b inserts the permission
        requests before the record; keep it a single private method so that is a one-place change.)
- [ ] Task 2: views (AC 2-7, 10, 11)
  - [ ] New `Sources/AppFeature/OnboardingView.swift`: `struct OnboardingFlowView: View` taking
    the model (via `@Bindable` or direct property) and an `onFinished: () -> Void`.
    - Layout: `VStack(spacing: 0)` of a `ScrollView` holding the current stage's content (a
      `switch` on `model.stage`), then the controls area (indicator dots row, then the
      leading/trailing control row). See "Visual design" in Dev Notes.
    - Drag: attach a `DragGesture` to the scroll content; on end, a translation width below
      -80 calls `model.swipe(.forward)`, above 80 calls `model.swipe(.backward)`. The model ignores
      it from stage 2 on.
    - Stage changes animate with `withAnimation`.
    - Text fields bind through `Binding(get: { model.serverURL }, set: { model.updateServerURL($0) })`,
      and likewise for email and password.
    - `.onChange(of: model.isFinished) { _, finished in if finished { onFinished() } }`.
    - Every identifier from `OnboardingIdentifier` is applied with `.accessibilityIdentifier`.
      Indicator dots also get `.accessibilityLabel(OnboardingPageIndicator.label(...))`.
- [ ] Task 3: wiring and the flag flip (AC 8, 9)
  - [ ] `Sources/AppFeature/AppNavigation.swift`: `valueWhenUnset = false`; rewrite its doc
    comment ("An unset key means onboarding was never finished.").
  - [ ] `Sources/AppFeature/AppShell.swift`:
    - `AppShell.init(startDestination: StartDestination, onboarding: OnboardingModel)`. Store the
      model; hold `@State private var destination: StartDestination` initialised from
      `startDestination`.
    - `AppRootView` renders `MainTabView()` for `.main` and
      `OnboardingFlowView(model:onFinished: { destination = .main })` for `.onboarding`.
      Keep `DemoDataBannerRoot` at the root for both destinations (existing test).
    - Delete `OnboardingPlaceholderView` and the `placeholder.onboarding` identifier.
  - [ ] `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: add
    `@State private var onboarding = OnboardingModel(backend: UnavailableOnboardingBackend(), defaults: .standard)`
    (initialise it in `init()` through `_onboarding = State(initialValue: ...)` alongside `_model`),
    and pass it to `AppShell`. The start stage stays `.welcome` (no saved URL exists).
- [ ] Task 4: tests (all ACs)
  - [ ] New `Tests/AppFeatureTests/OnboardingTests.swift` (Swift Testing, `@MainActor` where the
    model is used). Each test uses its own `UserDefaults(suiteName: "OnboardingTests-\(UUID())")`
    and removes the domain in `defer`.
    - Stage raw values and count; `start(...)` for all four input combinations.
    - `OnboardingControls.make` for every stage, both values of `connectionSucceeded` on backend.
    - Navigation walk: next from welcome → features → safety; next on safety stays on safety;
      skip from 0 and 1 lands on safety; skip elsewhere is a no-op; back on 3 → 2, on 4 → 3; back on
      0-2 is a no-op.
    - Swipe: forward on 0 → 1, on 1 → 2; backward on 1 → 0; both directions no-op on 2, 3, 4
      (reach 3 and 4 via acknowledge + a succeeding double).
    - Safety invariant: after every step of the above walks,
      `model.stage.rawValue <= 2 || model.safetyAcknowledged`.
    - Blank URL (empty and whitespace-only): exact message, port call count 0, returned task nil.
    - Unavailable backend: result text exactly
      "Connection failed: this build can't connect to a server yet", `isSuccess == false`,
      `connectionSucceeded == false`, next on backend stays on backend.
    - Succeeding double: "Connected successfully", next moves to signIn.
    - Editing the URL clears result and success.
    - Escape hatch with a failed test: run a failing test, then `continueWithoutServer()` →
      `isFinished`, URL blank, result nil, and `OnboardingCompletion.isComplete(in: defaults)`.
    - Cancellation ordering: a gated double whose `testConnection` suspends until released. Start a
      test, wait until the double reports a pending call, call `continueWithoutServer()`, release the
      double with `.connected`, await the returned task. Assert `connectionSucceeded == false`,
      `connectionResult == nil`, `serverURL == ""`, `isFinished`.
    - `continueWithoutServer()` while never tested, and a second call after finishing (no crash, still
      finished, defaults still true).
    - Sign-in: blank email, blank password → exact message, port count 0. Failure double → its message
      in `loginError`, password "". Success double → password "", `isFinished`, defaults true.
    - Page indicator labels: "Page 1 of 5, current" for index 0 when current is 0, "Page 2 of 5"
      for index 1; identifiers `page_indicator_0`...`page_indicator_4`.
    - Every `OnboardingCopy` and `OnboardingIdentifier` string pinned exactly (one test each).
    - Every SF Symbol used by the onboarding views resolves on UIKit and AppKit (same `#if
      canImport(UIKit)` / `#elseif canImport(AppKit)` shape as `AppNavigationTests`). Keep the
      symbol names in one `OnboardingSymbol` list so the test iterates it.
    - `UnavailableOnboardingBackend` returns the pinned failure for both calls.
  - [ ] `Tests/AppFeatureTests/AppNavigationTests.swift`:
    - `onboardingCompletionPersistsStoredValuesAndDefaultsWhenUnset`: unset now resolves to
      `.onboarding`; assert `valueWhenUnset == false`.
    - `shellKeepsBannerAtRootForBothDestinations`: pass an `OnboardingModel` built with
      `UnavailableOnboardingBackend()` and a throwaway suite.

## Dev Notes

### Known pitfalls

- The worker cannot compile, so write carefully. A `switch` that follows any statement in a function or getter needs `return switch`.
- AppFeature also builds for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs, such as UIKit, `.tabBar` toolbars, `navigationBar*` and permission APIs, in `#if os(iOS)`.
- Every SF Symbol name needs a test that it exists on UIKit and AppKit.
- Small coloured text needs a contrast ratio of at least 4.5:1. Use the existing light/dark palette in `StatusRowView`.
- Never write a numeric safety constant inline, and never disguise one. New constants go in `SafetyConstants` and `CANON_SPEC`.
- Swift 6 strict concurrency.
- Code comments must not mention stories, epics, AC numbers, agents or cycles.
- Do not use private UIKit API.

### Read first (rules of the road)

- **Do not edit** `Sources/DriverAPI/**`, `Sources/Persistence/**`, `Sources/SafetyCore/**`,
  `Sources/Drivers/**`, `Package.swift`, the Xcode project file, CI files or the guards. If you
  need one of them, write a NEEDS-HUMAN line in the Dev Agent Record instead.
- **No `CoreBluetooth`, no `UserNotifications`, no `URLSession`** in this story. Permissions are
  1.17b; there is no Backend client.
- **No wall-clock reads anywhere under `Sources/`.** `safety_guards.sh` rejects `Date()`,
  `Date.now`, `Date.init`, `timeIntervalSinceNow` and friends in every target except
  `SystemClock.swift`. No debounce is needed here because no request is ever issued (FR-161's
  1,000 ms debounce comes with the Backend client). Do not write `1000` or `1_000` anywhere.
- **Safety-guard numeric bands.** Numeric literals under `Sources/` fail in 17.5–18.5, 19–21,
  57–63, 342–378, 475–525, 855–945 and 3420–3780. So no `18`, `20` or `60` in padding, spacing,
  frame sizes or corner radii. The values below (4, 8, 12, 16, 24, 32, 48, 80, 96) are clear.
- **No therapeutic write, ever (SI-1).** This story only renders a sentence saying so.
- **Strings say "server" on purpose.** FR-159/FR-161/FR-164 pin the user-facing word "server"; do
  not re-word to "Backend". Code identifiers and comments use "Backend".
- **Scratch files only under `.build/` in your worktree. One operation per Bash call.**
- **Diff budget:** reviewable diff under ~800 lines. Report the final size in the Dev Agent Record.
- Your sandbox may not be able to run Swift or the Simulator. That is expected; the launcher
  re-runs every gate. Run `swiftc -frontend -parse` on each edited file if you can.

### Existing code to build on (as of develop @ b9f85cd)

- `Sources/AppFeature/AppNavigation.swift`: `StartDestination.resolve(onboardingComplete:)` and
  `OnboardingCompletion` (key `onboardingComplete`, `isComplete(in:)`, `record(_:in:)`). Reading
  uses `defaults.bool(forKey:)`, which also accepts the `"YES"`/`"NO"` strings a launch argument
  produces; keep that.
- `Sources/AppFeature/AppShell.swift`: `AppShell` wraps `AppRootView` in `DemoDataBannerRoot`.
  `AppRootView` switches on a `let startDestination`, so today the destination cannot change
  without a relaunch; this story makes it `@State`. `PlaceholderView` and the private
  `hideTabBarOnIOS` / `hideNavigationBarOnIOS` helpers live here; the onboarding view is not inside
  a `TabView` and needs neither.
- `Sources/AppFeature/DriverHost.swift`: `HomeModel` (`@MainActor @Observable`) is the pattern for
  the new model, including methods that return the `Task` they start so tests can await it
  (`setScenePhaseActive`).
- `Sources/AppFeature/StatusRow.swift` / `StatusRowView.swift`: `BackendConfiguration` is
  `.notConfigured` / `.configured(BackendStatus)`; `HomeModel.backend` is a `let` defaulting to
  `.notConfigured`. This story does NOT change it: finishing either path leaves the app in
  Backend-optional mode because nothing is persisted that would configure a Backend.
  `StatusColor.rgb(dark:)` and `swiftUIColor(_:)` are `internal` in AppFeature: use
  `StatusColor.error.swiftUIColor(colorScheme)` for error text and `.primary` for success text.
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: computes `startDestination` once in `init()` and
  builds `HomeModel` with the Simulated Driver. The `.task` that activates the Driver is on
  `AppShell`, so the Simulated Driver also runs during onboarding. That is fine; leave it.
- `Tests/AppFeatureTests/AppNavigationTests.swift`: SF Symbol test shape and the banner-root test.

### Android reference (copied here; the Android repo is not readable from your sandbox)

Source: `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/onboarding/`
`OnboardingScreen.kt`, `OnboardingViewModel.kt`, `OnboardingPages.kt`.

- Pages: WELCOME=0, FEATURES=1, DISCLAIMER=2, SERVER=3, LOGIN=4, COUNT=5.
- `HorizontalPager(userScrollEnabled = pagerState.currentPage < PAGE_DISCLAIMER)`.
- Skip → `animateScrollToPage(PAGE_DISCLAIMER)`; Back → current − 1; Next → current + 1.
- Disclaimer's button reads "I Understand" with testTag `next_button`. No checkbox.
- Server page "Next" is `enabled = connectionTestSuccess`. Login page shows no Next.
- `getStartPage()`: SERVER only if a saved URL exists AND onboarding was completed before.
- `continueWithoutServer()`: cancel the test job, clear the base URL, set onboarding complete, reset
  URL/test state, then request notification permission (1.17b), then navigate.
- `updateBaseUrl` clears result, success and the insecure opt-in flag. `updateEmail` /
  `updatePassword` clear `loginError`. `login()` clears the password on both outcomes.
- Indicator semantics: `"Page ${index + 1} of $pageCount" + if (selected) ", current" else ""`,
  testTag `page_indicator_$index`.

**Copy table (exact; ASCII "..." where shown, not U+2026):**

| Where | Text | Source |
|---|---|---|
| Welcome title | GlycemicGPT | Android = PRD |
| Welcome subtitle | Your diabetes management companion | Android = PRD |
| Welcome body | A direct pump monitor on its own — your on-call endo when you connect a server. | Android = PRD |
| Features title | What You Get | Android |
| Card 1 title / body | Direct Pump Connection / Connect directly to your Tandem pump via BLE for real-time basal, bolus, IoB, reservoir, and battery data. | Android |
| Card 2 title / body | AI-Powered Analysis / With a connected server, get photo meal analysis, an AI chat, and AI insights delivered as notifications — powered by your choice of AI provider. | PRD FR-159 (overrides Android) |
| Card 3 title / body | Smart Alerts / Configurable glucose alerts, with Telegram delivery and caregiver escalation when you connect a server. | Android |
| Card 4 title / body | Self-Hosted Privacy / Run your own server and your data stays on your infrastructure — no cloud dependency, full control. | Android |
| Safety title | Important Safety Information | Android |
| Safety 1 | Experimental Software / This is alpha software under active development. It is functional but has not been broadly tested. Use at your own risk. | Android |
| Safety 2 | AI Limitations / AI can hallucinate, misinterpret data, and provide outdated or incorrect information. Never rely solely on AI suggestions. | Android = PRD |
| Safety 3 | Photo Carb Estimates Are Guesses / If you use the meal-photo feature, the carb numbers are AI estimates from an image and are frequently wrong, including misidentifying the food entirely. Never use a photo carb estimate to calculate an insulin dose or bolus. Always verify carbs yourself before dosing. | Android (PRD quotes the tail) |
| Safety 4 | Not FDA Approved / This software is not approved by the FDA or any regulatory body for medical use. It is not a medical device. | Android |
| Safety 5 | Consult Your Healthcare Provider / Always consult with your endocrinologist before making changes to your diabetes management. Verify all AI suggestions with your care team. | Android |
| Safety sentence | GlycemicGPT only reads from your pump. It never delivers a bolus, never changes your basal, and never changes a pump setting. | INVENTED (FR-160) |
| Backend title | Connect a Server (Optional) | Android = PRD |
| Backend body | A server adds AI, meal analysis, and caregiver features. You can skip it and use the app as a direct pump monitor. | PRD FR-161 (Android says "direct BLE pump monitor") |
| URL label / placeholder | Server URL / https://your-server.com | Android |
| Test button | Test Connection / Testing... | Android |
| Blank URL | Enter a server URL first | Android = PRD |
| Success | Connected successfully | PRD FR-161 |
| Failure | Connection failed: this build can't connect to a server yet | prefix PRD; reason INVENTED |
| Escape label | Don't run a server? | Android = PRD |
| Escape button | Use without a server | PRD FR-164 (Android appends " (BLE-only)") |
| Sign-in title / body | Sign In / Sign in to your GlycemicGPT server account to enable AI, meal, and caregiver features. | Android |
| Field labels | Email / Password | Android |
| Sign-in button | Sign In / Signing in... | Android |
| Blank credentials | Email and password are required | Android = PRD |
| Sign-in unavailable | Sign-in isn't available in this build yet. | INVENTED |
| Controls | Skip / Back / Next / I Understand | Android |

**Identifiers (FR-177; byte-identical Android testTags unless marked):** `skip_button`,
`back_button`, `next_button`, `page_indicator_0`…`page_indicator_4`, `onboarding_server_url`,
`onboarding_test_connection`, `onboarding_connection_result`,
`onboarding_continue_without_server`, `onboarding_email`, `onboarding_password`,
`onboarding_login_error`, `onboarding_sign_in`; iOS-only: `onboarding_no_therapeutic_writes`.
Do not confuse `onboarding_server_url` with Settings' `server_url_field` (FR-161).

### Visual design `[ASSUMPTION]` — everything here is invented

The PRD has no visual spec for first run (epics.md: "No UX design contract"). Every item below is
an iOS decision that mirrors Android's layout loosely; list any further invention in the Dev Agent
Record.

- SF Symbols (Android Material icon → iOS): Welcome `heart.fill` (Favorite, 96 pt, primary tint);
  Direct Pump Connection `antenna.radiowaves.left.and.right`; AI-Powered Analysis `brain`; Smart
  Alerts `bell`; Self-Hosted Privacy `lock`; Safety header `exclamationmark.triangle.fill` (error
  tint); Experimental `flask`; AI Limitations `brain`; Photo carbs `camera`; Not FDA Approved
  `shield`; Consult provider `cross.case`; Backend header `lock.shield`. Icons are decorative
  (`.accessibilityHidden(true)`); the card title carries the meaning.
- Cards: `HStack(alignment: .top, spacing: 12)` with icon (24 pt safety, 32 pt features), title
  `.subheadline.weight(.semibold)`, body `.subheadline` in `.primary`. Background
  `RoundedRectangle(cornerRadius: 12)` filled with `.fill.tertiary`. Card padding 12 (safety) or
  16 (features), card spacing 8 (safety) or 12 (features). Each card is one accessibility element
  (`.accessibilityElement(children: .combine)`).
- **No `.secondary` for small text** (it is below 4.5:1 on white). Small coloured text uses only
  `StatusColor.error` / `.primary` via `swiftUIColor(colorScheme)`.
- Stage padding 24 horizontal; title `.title2.bold()`; Welcome title `.largeTitle.bold()` in the
  primary colour.
- Indicator dots: 10 pt selected (primary colour), 8 pt otherwise (`Color.gray`), spacing 8.
  Dots are not interactive.
- Buttons: trailing "Next"/"I Understand" `.borderedProminent`; "Skip"/"Back" `.borderless`;
  "Test Connection" `.bordered`, full width; "Use without a server" `.borderless`, centred, below
  "Don't run a server?" (`.subheadline`, `.primary`); "Sign In" `.borderedProminent`, full width.
  While testing, the Test button shows a small `ProgressView` before its label.
- iOS-only text-field modifiers inside `#if os(iOS)`: URL field `.keyboardType(.URL)`,
  `.textInputAutocapitalization(.never)`, `.textContentType(.URL)`; email `.keyboardType(.emailAddress)`,
  `.textInputAutocapitalization(.never)`, `.textContentType(.username)`; password
  `.textContentType(.password)`. `.autocorrectionDisabled()` is cross-platform.
- The DEMO DATA banner stays visible above onboarding (it sits at the root, and the existing test
  pins that).

### Deferred to 1.17b (recorded so the PM does not have to re-derive it)

- FR-165: one notification request with `[.alert, .sound, .badge, .criticalAlert]`, never
  `.provisional`; a Bluetooth authorization request; both on both paths, each resolved before the
  navigation flag flips; behind an injected `OnboardingAuthorizations` protocol so tests use a
  recording double and the Simulator's Bluetooth behaviour never matters to a gate (Core
  Bluetooth reports `.unsupported` in the Simulator and its prompt cannot be asserted). Live
  adapters are `#if os(iOS)`. Needs `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` in all three
  build configurations of the Xcode project, or the first `CBCentralManager` crashes the app.
  1.17b also decides whether the completion flag is written before or after the prompts (Android
  writes it before).
- FR-15 / FR-85 warning. Neither the PRD nor Android has exact copy; FR-85 fixes only the three
  facts. Proposed text, flagged INVENTED, for an extra block on the Safety stage below the
  no-therapeutic-write sentence (FR-159 caps the flow at five stages and FR-160 at five cards, so
  it cannot be a sixth stage or card):
  - Title: "Keep GlycemicGPT running"
  - "If you force-quit GlycemicGPT from the app switcher, it stops monitoring in the background,
    including reconnecting to your pump, until you open it again."
  - "After your phone restarts, nothing runs until you unlock it once."
  - "Low Power Mode removes some of the background time the app uses to stay up to date."
  - Identifier: `onboarding_monitoring_limits` (iOS-only).
- FR-165's "notification denied → Coverage Claim not watching on first dashboard" needs the
  Coverage Claim (Epic 4).

### Architecture compliance

- **AD-1 / AD-3:** the Backend port is defined in AppFeature as a presentation-side seam; the real
  adapter arrives with `BackendClient` and will conform to it (or replace it). AppFeature gains no
  new dependency.
- **AD-13:** "Use without a server" is a supported mode, not an error: no error styling, no
  "limited mode" copy, no nag (FR-164). The failure line from the unavailable Backend uses the error
  colour because it is an actual failed attempt.
- **AD-14:** no wall-clock reads (see guards above).
- **SI-1:** read-only posture stated on the Safety stage.
- **SI-5 / FR-164:** nothing on either path persists a Backend URL, token or Alert Threshold, so a
  departed Backend's values cannot arm anything.
- **SI-6:** onboarding never implies a paired pump or a reachable server.

### Out of scope (later work; do not build)

- FR-165 permissions and the FR-15/FR-85 warning (1.17b, above).
- FR-150 cleartext policy and URL validation, FR-151/FR-162 local-network permission and its
  blocked state, FR-163 insecure LAN HTTP opt-in, dialog and banner (`insecure_http_banner`,
  `onboarding_enable_insecure_http`), FR-161's debounce, URL persistence before the request and
  restore-on-failure, Keychain token storage. All need the Backend client (Epic 5).
- Pairing (1.19), Settings (FR-166), the Coverage Claim.
- XCUITest. There is no UI-test target and adding one changes the Xcode project. Model-level unit
  tests are the acceptance substrate here; the PM checks the rendered flow in the Simulator.

### Simulator check for the PM after the gates pass

1. Fresh install (or launch with `-onboardingComplete NO`): Welcome shows; swipe left reaches
   Features; Skip reaches Safety.
2. On Safety, swiping does nothing; "I Understand" reaches the Backend stage.
3. Type any URL, tap Test Connection: "Connection failed: this build can't connect to a server
   yet" in red; Next stays disabled; "Use without a server" is enabled.
4. Tap "Use without a server": Home appears with DEMO DATA and "No pump". Relaunch: Home again.
5. Check Light and Dark Mode for contrast.

### Testing standards

- Swift Testing, as the existing targets do. No sleeps. To wait for the gated double, loop on
  `await Task.yield()` until it reports a pending call.
- The gated double is an `actor` holding a `CheckedContinuation<ConnectionTestOutcome, Never>?`
  and a call counter; `release(_:)` resumes it once. `withCheckedContinuation` is not cancellation
  aware, so every test that suspends it must release it.
- Counting doubles for the blank-input tests: an `actor` with call counters returning a fixed
  outcome.
- `AppFeatureTests` cannot depend on `SimulatedDriver`; do not change `Package.swift`.
- Known flake: `WallClockSchedulerTests`. You may re-run once; record it if you do.

### Project structure notes

- New:
  - `Sources/AppFeature/Onboarding.swift`
  - `Sources/AppFeature/OnboardingView.swift`
  - `Tests/AppFeatureTests/OnboardingTests.swift`
- Modified:
  - `Sources/AppFeature/AppNavigation.swift` (`valueWhenUnset` and its comment)
  - `Sources/AppFeature/AppShell.swift` (reactive destination, onboarding view, placeholder removed)
  - `Apps/GlycemicGPT/App/GlycemicGPTApp.swift` (create and pass the onboarding model)
  - `Tests/AppFeatureTests/AppNavigationTests.swift`
- Branch from `develop` (for example `feat/first-run-onboarding`).

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 1.17 (:929); 1.19 for the pairing entry]
- [Source: prd.md FR-159 (:2944), FR-160 (:2980), FR-161 (:3001), FR-164 (:3099), FR-165 (:3122),
  FR-15 (:397), FR-85 (:1459), FR-177 (:3513), UJ-3/UJ-4 (:92)]
- [Source: prds/.../review-safety.md F-28 (why the escape lives on the Backend stage)]
- [Source: ARCHITECTURE-SPINE.md: AD-1, AD-3, AD-13, AD-14; 5.9 → AppFeature]
- [Source: android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/onboarding/OnboardingScreen.kt,
  OnboardingViewModel.kt, OnboardingPages.kt]
- [Source: 1-14-the-status-row.md for palette and guard traps]

## Dev Agent Record

### Agent Model Used

Amelia, Senior Software Engineer.

### Debug Log References

### Completion Notes List

- Implemented the five-stage flow model, stage controls, safety gate, backend and sign-in ports, result state, completion persistence, page indicators, and accessibility identifiers.
- Added the SwiftUI onboarding flow and connected it to the root shell so completion changes to Home without relaunching. The simulated driver and root demo banner remain active.
- Changed an unset completion key to mean incomplete. Added “Coming to iOS” to the three feature descriptions for pump connection, AI analysis, and alerts, as required by the maintainer note.
- Added model tests for stage selection, controls, safety acknowledgement, blank and failed/successful connections, escape completion, cancellation, sign-in, visible copy, identifiers, and feature availability.
- Invented copy — maintainer review before public TestFlight: “GlycemicGPT only reads from your pump. It never delivers a bolus, never changes your basal, and never changes a pump setting.”; “this build can't connect to a server yet”; “Sign-in isn't available in this build yet.”; “This preview shows demo data only. Pump connection and server features are coming to iOS.” (Welcome preview notice); “This preview can't connect to a pump or a server yet. Direct pump monitoring is coming to iOS.” (Backend preview notice)
- Verification: `swiftc -frontend -parse` passed for all edited Swift files and `git diff --check` passed. `bash scripts/guards/safety_guards.sh`, `bash scripts/guards/driver_guards.sh`, and `bash scripts/ci-local.sh --self-test` passed. `bash scripts/guards/driver_guards.sh --self-test` passed all 68 cases with no unexpected result. `bash scripts/guards/safety_guards.sh --self-test` was interrupted after the longer test matrix had produced only expected results; it did not report a final summary. `swift build` and `swift test` could not compile the SwiftPM manifest because the sandbox blocks writes to `~/.cache/clang/ModuleCache`. The iOS `xcodebuild test` could not find an Xcode project/package for that scheme, and `xcodebuild build` could not resolve dependencies due to the same cache restriction and unavailable Simulator services.
- Diff budget: approximately 550 reviewable added/changed lines, within the stated budget.
- Review fixes (2026-11-01): Self-Hosted Privacy is now marked Coming to iOS (4 of 4). "Coming to iOS" renders as its own label from `comingToIOS` (id `onboarding_coming_to_ios`), and the card bodies no longer contain it. The swipe is a `.simultaneousGesture` attached only to Welcome and Features. The empty result `Text("")` is gone. `continueWithoutServer()` and `signIn()` do nothing until the stage is at least backend and safety is acknowledged. `startStage >= .backend` implies a previous acknowledgement. A connection result whose URL no longer matches the field is dropped. Added tests for the gate and the stale result. A dedicated `minimumDistance: 20` tripped the safety-constant guard, so the drag uses the default. Simulator check at accessibility-extra-extra-extra-large: Safety scrolls past the last card to the no-therapeutic-writes sentence. Gates: swift build, swift test (339), both guards, xcodebuild test, and the app build all pass.

### File List

- `Sources/AppFeature/Onboarding.swift`
- `Sources/AppFeature/OnboardingView.swift`
- `Sources/AppFeature/AppNavigation.swift`
- `Sources/AppFeature/AppShell.swift`
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
- `Tests/AppFeatureTests/OnboardingTests.swift`
- `Tests/AppFeatureTests/AppNavigationTests.swift`

### PM decisions on drafting open points (2026-11-01)
- **File naming.** This is 1-17a. 1-17b, covering the permission requests (including the Bluetooth plist key) and the restart/force-quit warning, follows separately.
- **Features cards.** Keep Android's feature list, but every feature this build cannot do yet (Tandem pump, Telegram, AI chat, and anything else not working in this build) must carry a visible "Coming to iOS" label. An onboarding screen must never promise a capability the installed build lacks. Test that each unavailable feature is labelled.
- **"Use without a server" copy.** Follow the PRD and drop Android's " (BLE-only)" suffix. The PRD is the iOS source of truth. The control's identifier/testTag stays byte-for-byte Android's (FR-177).
- **Invented copy** (the no-therapeutic-write safety sentence and the connection-failure reason text) is accepted for the demo build. List each invented string in the Dev Agent Record under "Invented copy — maintainer review before public TestFlight".
- budget: CONTINUATION_REQUIRED sha256:4e466dde80b4de822fe16847a93584cd5dbdbbd251d0f23ed67938a7bbb177e0 cycle 1 2026-11-01T19:55:14Z
