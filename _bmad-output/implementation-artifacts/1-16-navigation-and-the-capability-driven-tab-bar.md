---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-16-navigation-and-the-capability-driven-tab-bar.md.stamp.json
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

# Story 1.16: Navigation and the capability-driven tab bar

Status: done

<!-- Planning note (for the maintainer): depends on 1.13a, 1.13b and 1.14, all merged to develop
(44934d0). Runs in parallel with 1.15 (pull to refresh); see "Interaction with the pull-to-refresh
change" for how the two stay out of each other's way. Estimate: ~400-500 reviewable lines over
5 files (2 new sources, 1 new test file, 2 small edits), about a third of it tests. Inside the
800-line budget, so no split. Route: NOT chosen here; the PM routes via /v1/route. Planning
context: app shell and presentation only. No dosing, alert floor, ingestion mapper,
safety_validation, dependency, CI, DriverAPI, Persistence or SafetyCore change. -->

## Story

As a user,
I want the app to show only what my configuration supports,
so that I am not offered a tab that cannot work.

## Acceptance Criteria

From epics.md Story 1.16 (FR-63), with the PRD's testable consequences that apply today and the
Android client's tab list, order, icons and conditions pinned. AC 5-8 make the epic's three lines
concrete for a build that has no Backend, no onboarding flow and no detail screen yet.

1. **Tab list and order (FR-63).** A pure function maps the Backend configuration to the visible
   tabs, in this order (Android `bottomNavItems`):

   | Tab | Visible when | Label | SF Symbol | Accessibility identifier |
   |---|---|---|---|---|
   | Home | always | "Home" | `house` | `tab.home` |
   | AI Chat | Backend configured only | "AI Chat" | `bubble.left.and.bubble.right` | `tab.aiChat` |
   | Alerts | always | "Alerts" | `bell` | `tab.alerts` |
   | Settings | always | "Settings" | `gearshape` | `tab.settings` |

   `BackendConfiguration.notConfigured` → `[home, alerts, settings]`.
   `BackendConfiguration.configured(_)` → `[home, aiChat, alerts, settings]`.
   In Backend-optional mode the AI Chat tab is **absent**, not present and erroring. Both states
   are unit-tested.

2. **The Backend decision is read live, not captured.** The tab view computes the visible tabs
   from the current `HomeModel.backend` inside `body`, never once at init. If the selected tab
   is no longer visible (AI Chat after the Backend is removed), the effective selection is Home.
   A pure selection function covers this and is unit-tested.

3. **Start destination depends only on onboarding completion (FR-63).** A pure function
   `StartDestination.resolve(onboardingComplete: Bool)` returns `.main` (the tab shell, Home
   selected) for `true` and `.onboarding` for `false`. It takes no session, auth or Backend
   input. Both values are unit-tested. The app resolves it **once**, in `App.init`, and never
   re-reads it while running.

4. **Onboarding completion is a persisted value.** It lives in `UserDefaults` under the key
   `"onboardingComplete"` (the app target passes `.standard`). The read returns the stored Bool
   when one is stored. When nothing is stored it returns `OnboardingCompletion.valueWhenUnset`,
   which is `true` today because no onboarding flow ships yet (see Dev Notes). Nothing in this
   change writes the key at launch. Tests use a throwaway suite and cover stored `true`, stored
   `false` and unset.

5. **The DEMO DATA banner stays at the root and is not dismissable.** `DemoDataBannerRoot` wraps
   the whole shell: the tab view, its tab bar, every tab, every detail screen, and the onboarding
   placeholder. It gains no dismiss control and no state. A test asserts the shell's `body` is a
   `DemoDataBannerRoot` (see Testing).

6. **Detail screens hide the tab bar and show a back affordance (FR-63).** Each tab owns a
   `NavigationStack` with a path of `AppRoute` values. Every pushed `AppRoute` destination applies
   `.toolbar(.hidden, for: .tabBar)` and keeps the system back button (no
   `navigationBarBackButtonHidden`). One real minimal detail route ships: **Open Source
   Licenses**, pushed from the Settings placeholder (FR-63 lists licenses as a detail screen).
   A pure policy `AppRoute.hidesTabBar` is `true` for every case and is unit-tested.

7. **Tabs whose screens don't exist yet get minimal placeholders, honestly labelled.** AI Chat,
   Alerts, Settings and the onboarding destination each render a placeholder with a navigation
   title and plain copy saying what is not in this build. Copy is pinned in Dev Notes. The Alerts
   placeholder must say this build does not alert on glucose (SI-6: never overstate). Home
   renders the existing `HomeScreen()` unchanged.

8. **SF Symbols and identifiers are verified.** A test checks that every `AppTab.systemImage`
   resolves, on UIKit and on AppKit, in the same form as `everyStatusGlyphResolvesToAnSFSymbol`.
   A test checks the four tab identifiers are exactly the table's and are unique. Each tab's
   `tabItem` label carries its identifier.

9. **Gates and a screenshot.** Every frontmatter gate passes. If the sandbox can run the
   Simulator, attach a screenshot of the tab bar (three tabs) with the DEMO DATA banner above,
   and one of the Licenses detail with the tab bar hidden and a back button. If it cannot, say so
   in the Dev Agent Record; the PM captures them.

## Tasks / Subtasks

- [ ] Task 1: navigation model in AppFeature (AC 1, 2, 3, 4, 6)
  - [ ] New `Sources/AppFeature/AppNavigation.swift`, pure values, `Sendable` and `Equatable`
        (and `Hashable` where SwiftUI needs it):
    - `AppTab: String, CaseIterable` with cases `home, aiChat, alerts, settings` (declaration
      order = display order). Properties `title`, `systemImage`, `accessibilityIdentifier`
      from the AC 1 table.
    - `AppTab.visible(backend: BackendConfiguration) -> [AppTab]`.
    - `AppTab.effectiveSelection(_ selected: AppTab, visible: [AppTab]) -> AppTab`: `selected`
      if visible, else `.home`.
    - `StartDestination` enum `main, onboarding` with
      `static func resolve(onboardingComplete: Bool) -> StartDestination`.
    - `OnboardingCompletion` enum (namespace): `static let key = "onboardingComplete"`,
      `static let valueWhenUnset = true`, `static func isComplete(in defaults: UserDefaults) ->
      Bool` (uses `defaults.object(forKey:) as? Bool ?? valueWhenUnset`, so an unset key is
      distinguishable from a stored `false`), and `static func record(_ complete: Bool, in
      defaults: UserDefaults)` for tests and the later onboarding flow.
    - `AppRoute: Hashable` enum with one case `licenses`, `title` ("Open Source Licenses"),
      `hidesTabBar: Bool` (always `true`).
  - [ ] Doc comments say, in plain words: tabs reflect the modes actually available; the start
        destination depends only on onboarding completion so an expired or absent session still
        reaches local data offline; `valueWhenUnset` is `true` only because no onboarding flow
        ships yet and the onboarding flow sets it to `false`.
- [ ] Task 2: expose the Backend configuration (AC 1, 2)
  - [ ] `Sources/AppFeature/DriverHost.swift`: change `private let backend: BackendConfiguration`
        to `public let backend: BackendConfiguration`. **No other change in that file.**
- [ ] Task 3: shell views (AC 1, 2, 5, 6, 7, 8)
  - [ ] New `Sources/AppFeature/AppShell.swift`:
    - `public struct AppShell: View`, `init(startDestination: StartDestination)`. Its `body` is
      exactly `DemoDataBannerRoot { AppRootView(startDestination: startDestination) }`. It must
      **not** read `@Environment` itself, so its `body` can be built in a unit test without a
      `HomeModel` in the environment (`DemoDataBannerRoot.init` evaluates its content closure
      eagerly).
    - `AppRootView` (internal): reads `HomeModel` from the environment. `.onboarding` →
      `OnboardingPlaceholderView` with no tab bar. `.main` → `MainTabView`.
    - `MainTabView` (internal): `@State private var selection: AppTab = .home`. `TabView` with a
      `Binding` whose getter is `AppTab.effectiveSelection(selection, visible:)`.
      `ForEach(AppTab.visible(backend: model.backend))`, each tab wrapped in its own
      `NavigationStack(path:)` (one `[AppRoute]` path per tab, held in `@State`),
      `.tabItem { Label(tab.title, systemImage: tab.systemImage)
      .accessibilityIdentifier(tab.accessibilityIdentifier) }`, `.tag(tab)`. Use the iOS 17
      `.tabItem` API, not the iOS 18 `Tab` type (the floor is iOS 17).
    - Home tab content: if `model.hostError` is non-nil, the "Unable to start data source" view
      that today lives in `GlycemicGPTApp.swift` (moved verbatim: headline text, then
      `activationError.recoverer`, spacing 12, padding 16), otherwise `HomeScreen()`. Hide the
      navigation bar on the Home root (`.toolbar(.hidden, for: .navigationBar)`) so Home's layout
      does not shift.
    - Placeholders for AI Chat, Alerts and Settings, each with `.navigationTitle(tab.title)` and
      the copy in Dev Notes. Settings includes a `NavigationLink(value: AppRoute.licenses)` row.
    - `.navigationDestination(for: AppRoute.self)` on each tab's stack root. The destination
      view applies `.toolbar(.hidden, for: .tabBar)` when `route.hidesTabBar`, and
      `.navigationTitle(route.title)`.
    - `LicensesView`: the one entry in Dev Notes.
- [ ] Task 4: app composition (AC 3, 4, 5)
  - [ ] `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`:
    - Add `private let startDestination: StartDestination`, set in `init()` from
      `StartDestination.resolve(onboardingComplete: OnboardingCompletion.isComplete(in: .standard))`.
    - In `body`, replace the `DemoDataBannerRoot { Group { ... } .task { ... } }` block with
      `AppShell(startDestination: startDestination).task { await model.setScenePhaseActive(true).value }`.
    - Keep `.environment(model)` and the `.onChange(of: scenePhase)` block **exactly** as they are.
- [ ] Task 5: tests (AC 1-8)
  - [ ] New `Tests/AppFeatureTests/AppNavigationTests.swift` (list in Testing below).
- [ ] Task 6: gates, diff size, screenshots (AC 9)

## Dev Notes

### Read first (rules of the road)

- **Swift 6 strict concurrency.** Every target is `.swiftLanguageMode(.v6)`. `HomeModel` is
  `@MainActor @Observable`; keep it so. New value types are `Sendable`. Tests that touch views or
  `HomeModel` are `@MainActor`. `UserDefaults` is passed as a parameter to static functions, not
  stored in a `Sendable` type.
- **Never invent a numeric safety constant inline.** None is needed here.
- **No Bluetooth, no network.** No `CoreBluetooth`, no `URLSession`.
- **No therapeutic write, ever (SI-1).**
- **Do not edit** `Sources/DriverAPI/**`, `Sources/Persistence/**`, `Sources/SafetyCore/**`,
  `Sources/Drivers/**`, `Package.swift`, the Xcode project file, CI files or the guards. If you
  need a shape from one of them, write a NEEDS-HUMAN line in the Dev Agent Record instead.
  New files under `Sources/AppFeature/` are picked up by the package with no manifest change.
- **Do not edit** `Sources/AppFeature/HomeScaffold.swift` (`HomeScreen`, `HomeScaffoldView`,
  `DemoDataBannerRoot`) or `StatusRow*.swift`. `HomeScreen` is only embedded.
- **Code comments and commit messages:** state requirements in plain words. AD-x, SI-x and FR-x
  ids are fine. Never mention stories, epics, AC numbers, agents or cycles.
- **Scratch files only under `.build/` in your worktree. One operation per Bash call.**
- **Diff budget:** reviewable diff under ~800 lines. Report the final size in the Dev Agent Record.
- Your sandbox may not be able to run Swift or the Simulator (see 1.14's record). That is
  expected; the launcher re-runs every gate.

### Existing code to build on (as of develop @ 44934d0)

- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`: `@main struct GlycemicGPTApp: App`. `init()` builds
  the validator, a `SimulatedDriver`, and `HomeModel(driver:demoIdentifiers:)` (backend defaults
  to `.notConfigured`). `body` is `WindowGroup { DemoDataBannerRoot { Group { hostError view or
  HomeScreen() } .task { await model.setScenePhaseActive(true).value } } .environment(model)
  .onChange(of: scenePhase) { ... } }`.
- `Sources/AppFeature/HomeScaffold.swift`:
  - `DemoDataBannerRoot<Content: View>`: reads `HomeModel` from the environment; `VStack(spacing:
    0) { if model.isDemo { orange "DEMO DATA — not your glucose" header }; content }`. It has no
    state and no dismiss path. Its `init` evaluates `content()` eagerly.
  - `HomeScreen` (public) wraps `HomeScaffoldView`, a `ScrollView` with `.padding(.bottom, 88)`.
    The Home footer says "Pair your pump in Settings to start"; leave it.
  - `DemoDataLabel.isVisible(activeGlucoseDriver:demoIdentifiers:)`.
- `Sources/AppFeature/DriverHost.swift`: `HomeModel` holds `private let backend:
  BackendConfiguration` (line ~32), set by `init(driver:demoIdentifiers:backend:clock:scheduler:)`,
  and uses it only for `statusRow`. `hostError: DriverHostError?` with `recoverer`.
- `Sources/AppFeature/StatusRow.swift`: `public enum BackendConfiguration: Sendable, Equatable {
  case notConfigured, configured(BackendStatus) }`. `.configured` is this codebase's "a Backend
  base URL is configured". There is no URL value yet; do not add one.
- `Sources/AppFeature/StatusRowView.swift`: `extension StatusGlyph { var systemName: String }`, the
  pattern for `AppTab.systemImage` (yours can be public or internal; tests use
  `@testable import AppFeature`).
- `Tests/AppFeatureTests/StatusRowTests.swift` lines 90-106: the SF Symbol test to copy, with
  `#if canImport(UIKit) ... UIImage(systemName:) ... #elseif canImport(AppKit) ...
  NSImage(systemSymbolName:accessibilityDescription:) ... #endif`.
- `Tests/AppFeatureTests/DriverHostTests.swift`: `HostTestDriver()` and
  `HomeModel(driver: HostTestDriver(), demoIdentifiers: [], backend: backend)`, reusable if a test
  needs a model.
- There is **no** existing preferences store. `Sources/Persistence` is the GRDB health-data store;
  AppFeature cannot depend on it, and a launch flag does not belong in it. The architecture's
  Config rule is "App Group `UserDefaults` only for non-safety preferences". No App Group
  entitlement exists yet, so the app passes `UserDefaults.standard`; the store functions take the
  `UserDefaults` as a parameter so the suite can change later without touching callers.

### Android reference (copied here; the Android repo is not readable from your sandbox)

`android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/navigation/NavHost.kt`:
- `Screen` (lines 84-102): `Home("home", "Home", Icons.Default.Home)`,
  `AiChat("ai_chat", "AI Chat", Icons.Default.Chat)`,
  `Alerts("alerts", "Alerts", Icons.Default.Notifications)`,
  `Settings("settings", "Settings", Icons.Default.Settings)`. iOS equivalents: `house`,
  `bubble.left.and.bubble.right`, `bell`, `gearshape` (outline forms; the tab bar fills the
  selected one itself).
- `bottomNavItems(backendConfigured)` (lines 109-114): Home; AI Chat only if backend configured;
  Alerts; Settings. Doc comment: "AI Chat is backend-only (there is no on-device model), so in
  BLE-only mode the tab is absent rather than dead-ending on a 'check your server URL' error for
  a server the user deliberately never configured."
- `startDestinationRoute(onboardingComplete)` (lines 122-123): Home if complete, else Onboarding.
  Doc comment: keyed on onboarding completion alone, deliberately independent of session
  validity, because routing an expired session to Onboarding would lock local pump/CGM reads
  behind a login that cannot succeed offline.
- Lines 168-170: `val startDestination = remember { startDestinationRoute(appSettingsStore
  .onboardingComplete) }`, resolved once.
- `spokeRoutes` (lines 140-153) and line 173 `showBottomNav = !isOnboarding && route !in
  spokeRoutes`: detail screens and onboarding hide the bottom bar. Detail screens show their own
  top bar with a back button (`onBack = { navController.popBackStack() }`).
- Lines 194-200: the backend decision is read through `rememberUpdatedState` so it is live, not
  frozen at graph build.
- `backendGatedComposable` / `RedirectToHome` (lines 420-447): a Backend-only destination stays
  registered and redirects to Home when no Backend is configured.

`android-unofficial/app/src/main/java/com/glycemicgpt/mobile/data/local/AppSettingsStore.kt`
lines 85-89 and 393: `onboardingComplete` is a SharedPreferences Boolean, key
`"onboarding_complete"`, default `false`. (iOS uses `"onboardingComplete"`, and `true` when unset
only until the onboarding flow exists; see below.)

Android tests worth mirroring: `app/src/test/.../navigation/StartDestinationTest.kt` and
`DetailRoutesTest.kt`.

### Onboarding completion: why `true` when unset, and what changes later

There is no onboarding UI yet; the onboarding flow (welcome, safety acknowledgement, Backend stage,
permissions) is later work. Until it exists, a user with no stored value must land on the tab
shell, not on a placeholder with no way out. So:
- The start destination depends only on the persisted value (FR-63). It never looks at a session.
- An unset key reads as `OnboardingCompletion.valueWhenUnset`, which is `true` today.
- Nothing writes the key at launch. That matters: when the onboarding flow lands it flips
  `valueWhenUnset` to `false` and writes `true` on completion, and every existing install that
  never completed onboarding is then correctly sent through it, including the safety
  acknowledgement.
- A stored `false` reaches the onboarding placeholder. Nothing in the shipping build writes it, but
  `UserDefaults` reads launch arguments, so `-onboardingComplete NO` in the scheme's run arguments
  shows the placeholder on the Simulator. Mention this in the Dev Agent Record if you use it.
- Name the `valueWhenUnset` test so it is obvious it must change with onboarding, for example
  `unsetReadsAsCompleteUntilOnboardingShips`.

### Placeholder copy (pinned)

Each placeholder: `.navigationTitle(<title>)`, then a `VStack(alignment: .leading, spacing: 8)` of
`Text`, padded 16, top-leading. Plain copy, ASCII full stops:

- AI Chat (`placeholder.aiChat`): "AI Chat isn't available in this build yet."
- Alerts (`placeholder.alerts`): "Alerts aren't available in this build yet." then "This build does
  not alert on glucose. Use your CGM's own app or receiver for alarms."
- Settings (`placeholder.settings`): "Settings aren't available in this build yet." then "Pump
  pairing isn't available in this build yet." then a `NavigationLink(value: AppRoute.licenses)`
  labelled "Open Source Licenses" (`settings.licenses`).
- Onboarding (`placeholder.onboarding`), no navigation title, no tab bar: "Setup isn't available in
  this build yet."
- Licenses detail (`detail.licenses`), title "Open Source Licenses": one entry, "GRDB.swift 7.11.1"
  then "MIT License" then "https://github.com/groue/GRDB.swift". GRDB is the package's only
  dependency (see `Package.swift`). Do not paste licence text you have not read from the package.

The identifiers in brackets go on each placeholder's root view.

### Interaction with the pull-to-refresh change (running in parallel)

The pull-to-refresh work adds `.refreshable` to Home and a foreground re-read. It is likely to
touch `HomeScaffold.swift`, `DriverHost.swift`, and possibly the `scenePhase` handling in
`GlycemicGPTApp.swift`. To keep the merge trivial:
- Do not touch `HomeScaffold.swift`. `HomeScreen()` is embedded unchanged inside the Home tab's
  `NavigationStack`, where `.refreshable` on its `ScrollView` keeps working.
- In `DriverHost.swift` change exactly one token (`private` → `public` on `backend`).
- In `GlycemicGPTApp.swift` change only the `DemoDataBannerRoot { ... }` block and add the
  `startDestination` property and its `init` line. Leave `.environment(model)` and
  `.onChange(of: scenePhase)` byte-for-byte.
- If the other change merges first and conflicts appear, rebase and keep both: its edits win
  inside `HomeModel` and the `scenePhase` block, this change's win in the root view block.

### Architecture compliance

- AppFeature owns presentation and user-facing recovery (spine "Presentation adapters"; 5.9
  Onboarding and settings → `AppFeature`). Its dependencies stay `SafetyCore` and `DriverAPI`.
- Config: `UserDefaults` only for non-safety preferences; no Keychain, no secrets.
- NFR-22: the app registers no custom URL scheme and no share extension. Do not add `onOpenURL`,
  URL types, or any deep-link handling.

### Out of scope (later work; do not build)

- The onboarding flow and writing `onboardingComplete = true` (1.17).
- The session banner ("Not signed in, tap to sign in", expired session) and the insecure-HTTP
  banner: there is no auth and no Backend client yet (Epic 5).
- Backend-only destination redirects for restored paths and internal entry points (widgets,
  complications, notification taps); there are no entry points yet. Only the tab-selection
  fallback in AC 2 is in scope.
- The real AI Chat screen (5.8), Alerts screen and alert history (2.11), Settings composition and
  mode-dependent visibility (6.1), pairing from Settings (1.19).
- Real detail screens (chart, Time in Range, insulin, bolus history, Driver card detail, meals).
- A shared dashboard model across Home, chart detail and bolus history.
- A mutable Backend configuration. `backend` stays a `let`; the tab view already reads it live.
- Pull to refresh and foreground re-read (1.15).
- An App Group entitlement or Xcode project change.

### Testing standards

`Tests/AppFeatureTests/AppNavigationTests.swift`, Swift Testing (`import Testing`,
`@testable import AppFeature`, `import DriverAPI`, plus the UIKit/AppKit conditional imports):

- `visible(backend: .notConfigured)` == `[.home, .alerts, .settings]`.
- `visible(backend: .configured(...))` == `[.home, .aiChat, .alerts, .settings]` (build a
  `BackendStatus` with any sync input and reachability).
- Home, Alerts and Settings are present in both; AI Chat only in the configured one.
- Titles, system images and identifiers equal the AC 1 table; identifiers are unique.
- `effectiveSelection(.aiChat, visible: notConfiguredTabs)` == `.home`;
  `effectiveSelection(.alerts, visible: ...)` == `.alerts`.
- `StartDestination.resolve(onboardingComplete: true)` == `.main`; `false` == `.onboarding`.
- `OnboardingCompletion` with `UserDefaults(suiteName: "AppNavigationTests-\(UUID())")!`
  (remove the persistent domain at the end): stored `true` → `true` → `.main`; stored `false` →
  `false` → `.onboarding`; unset → `valueWhenUnset` → `.main`; `key == "onboardingComplete"`.
- `AppRoute.allCases.allSatisfy(\.hidesTabBar)` (add `CaseIterable` to `AppRoute`), and the
  licenses title.
- `@MainActor` banner-at-root test: `let body = AppShell(startDestination: .main).body`, then
  `#expect(String(describing: type(of: body)).hasPrefix("DemoDataBannerRoot<"))`. Repeat for
  `.onboarding`. This is why `AppShell.body` must not read the environment.
- SF Symbols: `everyTabSymbolResolvesToAnSFSymbol`, in an `#if canImport(UIKit)` /
  `#elseif canImport(AppKit)` pair copied from `StatusRowTests.swift`, over `AppTab.allCases`.
  (Verified on macOS while writing this: all four names resolve.)
- Existing tests must pass unchanged. Nothing in `DriverHostTests` should need editing.

### Project structure notes

- New: `Sources/AppFeature/AppNavigation.swift`, `Sources/AppFeature/AppShell.swift`,
  `Tests/AppFeatureTests/AppNavigationTests.swift`.
- Edited: `Sources/AppFeature/DriverHost.swift` (one token), `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`.
- Expected size: ~90 lines model, ~170 lines views, ~150 lines tests, ~15 lines app edit.

### References

- `_bmad-output/planning-artifacts/epics.md`, Story 1.16 (and 1.15, 1.17, 1.19, 2.11, 5.8, 6.1 for
  scope boundaries).
- PRD `_bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md`: FR-63 (line
  ~1124), PA-18, NFR-22, the AI Chat mode-gate notes near line 1862.
- `_bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md`:
  conventions table (Config row), presentation adapters, 5.9 mapping.

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List

### PM decisions on drafting open points (2026-11-01)
- Treating an unset onboarding flag as complete is accepted for now, because no onboarding UI exists. Leave one doc comment on the key saying that the onboarding flow must set it explicitly, and that existing installs need a migration decision when that flow lands.
- `UserDefaults.standard` is accepted until the App Group identifiers exist. Keep access behind one small type, so moving the store later is a one-line change.
- The Alerts placeholder wording, which says this build does not alert on glucose, is accepted and required. Honesty over polish.

### Agent Model Used

Amelia — Senior Software Engineer

### Debug Log References

- `swift build` and `swift test` could not compile the package manifest: Swift attempted to create a module cache under the restricted `~/.cache/clang/ModuleCache`. A retry with `SWIFTPM_MODULECACHE_OVERRIDE` pointing into `.build/modulecache` was also blocked by the sandbox (`sandbox_apply: Operation not permitted`).
- `xcodebuild test -scheme GlycemicGPT-Package ...` could not locate an Xcode project, workspace, or package at the repository root.
- The app `xcodebuild build` could not resolve SwiftPM dependencies because of the same restricted module cache; CoreSimulator was also unavailable (no simulator runtime/service).
- A direct `swiftc -frontend -parse` check of the new sources, test file, and app entry point completed successfully.

### Completion Notes List

- Added backend-driven tab metadata and visibility, selected-tab fallback, onboarding destination and persisted completion access, and detail route policy.
- Added the root shell, independent navigation paths per tab, honest placeholders, license detail, and the live backend read. Kept Home content and the banner implementation unchanged.
- Moved the existing data-source failure presentation into the Home tab and resolved the start destination once during app initialization.
- Added tests for backend tab modes, metadata and identifiers, selection fallback, onboarding values, detail policy, banner placement, and SF Symbol resolution.
- Gate results: `swift build` blocked by the sandbox module-cache restriction; `swift test` blocked by the same restriction; `bash scripts/guards/safety_guards.sh` passed; its `--self-test` passed (75 cases, 2 documented bypasses, 0 unexpected results); `bash scripts/guards/driver_guards.sh` passed; its `--self-test` passed (68 cases, 3 documented known limits, 0 unexpected results); `bash scripts/ci-local.sh --self-test` passed; the package `xcodebuild test` gate could not locate a project/workspace/package at repository root; the app `xcodebuild build` gate was blocked by package cache restrictions and unavailable Simulator services.
- Simulator screenshots were not captured because CoreSimulator is unavailable in this environment.
- Changed implementation/test files total 326 lines; the complete implementation diff remains below the 800-line budget. No scratch files were added outside `.build/`.

### File List

- `Sources/AppFeature/AppNavigation.swift` (new)
- `Sources/AppFeature/AppShell.swift` (new)
- `Sources/AppFeature/DriverHost.swift` (`backend` visibility only)
- `Apps/GlycemicGPT/App/GlycemicGPTApp.swift`
- `Tests/AppFeatureTests/AppNavigationTests.swift` (new)

### PM note: cycle 1 gate results (launcher re-run outside the sandbox, 2026-11-01)
- Your sandbox can't run SwiftPM or the Simulator. The launcher re-runs the gates outside it.
- `swift build` and `swift test` fail because AppFeature also compiles for **macOS**: CI runs `swift test` on macOS. The errors are:
  - `Sources/AppFeature/AppShell.swift:72:37`: 'navigationBar' is unavailable in macOS
  - `Sources/AppFeature/AppShell.swift:130:37` and `:146:64`: 'tabBar' is unavailable in macOS
- Fix: wrap the iOS-only modifiers (`.toolbar(.hidden, for: .tabBar)`, `.navigationBarTitleDisplayMode`, any `navigationBar` placement) in `#if os(iOS)`, or use a small view-modifier helper that is a no-op on macOS. The tab-bar-hiding test must still assert the intent on iOS, inside the simulator `xcodebuild test` gate. On macOS, test the routing state only, not the modifier.
- The xcodebuild test failure comes from the same compile errors. The app build gate passes.
- Then set `Status: review` and complete the Dev Agent Record.


### Cycle 2 implementation and validation (2026-11-01)

- Fixed the cycle 1 macOS compile findings in `Sources/AppFeature/AppShell.swift`: navigation-bar and tab-bar toolbar placements now compile only on iOS through small platform-aware view helpers. The `AppRoute.hidesTabBar` policy remains testable on every platform.
- Gate results: `swift build` and `swift test` remain blocked before compilation because the sandbox denies SwiftPM's module-cache write under `~/.cache/clang/ModuleCache`; `bash scripts/guards/safety_guards.sh` passed; `bash scripts/guards/safety_guards.sh --self-test` passed (75 cases, 2 documented bypasses, 0 unexpected results); `bash scripts/guards/driver_guards.sh` passed; `bash scripts/guards/driver_guards.sh --self-test` passed (68 cases, 3 documented known limits, 0 unexpected results); `bash scripts/ci-local.sh --self-test` passed; the package `xcodebuild test` gate cannot find a project, workspace, or package at the repository root; the app `xcodebuild build` gate is blocked by the restricted SwiftPM cache and unavailable CoreSimulator service.
- `swiftc -frontend -parse` passed for the navigation model, shell, tests, and app entry point.
- Simulator screenshots were not captured because CoreSimulator is unavailable; the PM can capture them when simulator services are available.
- The five implementation/test files total 632 lines; the implementation remains under the ~800-line diff budget. No scratch files were added outside `.build/`.

### PM decision after review (2026-11-01)
- **Tab accessibility identifiers.** SwiftUI on iOS 26.5 exposes no public API that puts an identifier on the tab bar buttons; only private UIKit classes can do it. Private API is a TestFlight/App Review risk, so it is not acceptable. UI tests match tabs by their stable titles (Home, AI Chat, Alerts, Settings). This amends the identifier requirement for the tab buttons only. Detail screens and placeholders keep their identifiers.
- **Accent colour.** Changed from the template pink (about 2.3:1 on white) to Android's primary `#2563EB`, with a `#60A5FA` dark-mode variant.
- **PM-applied fix.** One compile fix, a `#expect(allSatisfy(\.keyPath))` that the macro treats as throwing, rewritten as a local `let`.
