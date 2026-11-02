---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/1-18-driver-contributed-cards-deterministically-ordered.md.stamp.json
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

# Story 1.18: Driver-contributed cards, deterministically ordered

Status: review

> Depends on PR #23 being merged; dispatch after merge.
> PR #23 (`feat/registry-lifecycle`) moves `HomeModel` onto `DriverRegistry`. Contributed cards
> are gathered through the registry, so this story needs it. Branch from `develop` after it
> lands. This story is independent of 1.12c. If 1.12c merges first, rebase; the two touch
> different parts of `DriverHost.swift`.

<!-- Planning note (for the maintainer): estimate ~620-720 reviewable lines over ~11 files,
about half of it tests. Inside the 800-line budget, so no split. Route: NOT chosen here; the PM
routes via /v1/route. **This story changes DriverAPI.** It adds one read-only member to the
`Driver` protocol, with a default, and new value types. The Capability set, `CapabilityPort`,
the lifecycle and the catalog are untouched. The justification is under "Why DriverAPI changes,
and why that is allowed". The PM may want the reviewer to look at that section first. No dosing,
alert floor, ingestion mapper, safety_validation, dependency, CI or guard change. Suggested
classification: ambiguity medium, blast_radius medium. -->

## Story

As a Builder,
I want Driver-supplied cards to appear in a stable position,
so that the dashboard does not reshuffle between refreshes.

## Acceptance Criteria

From epics.md Story 1.18 (FR-37, FR-38, FR-39; AD-1 as the epic cites it). The epic's AC says
"Android needed an explicit sort because map iteration order shuffled badges" and attributes it
to FR-38. The PRD states the explicit sort in FR-37 and FR-39 (FR-38 is the Nightscout source,
whose card sits at priority 200), so those are the ones cited here.

1. **A Driver contributes cards as data, never as views (AD-1, FR-37).**
   - `DriverAPI` declares `DashboardCardDescriptor`, `CardElement`, `CardColor` and
     `CardLabelStyle` (shapes in Dev Notes). They are plain `Hashable`, `Sendable` value types:
     no closure, no `View`, no `AnyView`, no SwiftUI or UIKit import anywhere in `DriverAPI`.
   - A test scans `Sources/DriverAPI/` with `DriverAPISource` and fails on `import SwiftUI`,
     `import UIKit` or `import AppKit`.
   - The `Driver` protocol gains one requirement, `func dashboardCards() -> [DashboardCardDescriptor]`,
     with a default implementation that returns `[]`. Existing Drivers and test doubles compile
     unchanged.
2. **The element vocabulary is closed, and this story ships part of it.**
   - `CardElement` has exactly two cases now: `label(text:style:)` and `statusBadge(text:color:)`.
   - `CardColor` has all six of FR-37's semantic colours: standard, success, warning, error,
     info, muted.
   - `CardLabelStyle` has all four label styles: title, subtitle, body, caption.
   - The other seven element variants, the 13 icons, detail screens and settings descriptors are
     out of scope (see "Out of scope").
   - The platform's renderer switches over `CardElement` with no `default`, so a new case does not
     compile until it is rendered.
3. **Invalid cards are refused, not repaired (FR-37, FR-28).** The platform validates each card
   before showing it. A card is refused, logged and omitted when:
   - its id or title is empty or whitespace-only
   - its `priority` is below `DashboardCardDescriptor.minimumDriverPriority` (100)
   - it repeats a card id already used by an earlier card from the same Driver (the first one is
     kept)
   Refusing one card keeps the Driver's other cards and keeps the Driver active. Nothing is
   clamped or truncated. The log line names the Driver id, the card id and the rule. It never
   includes card text (SI-9).
4. **One deterministic order (FR-37, FR-39).**
   - Platform cards get priorities from their index in `HomeScaffoldModel.order` (status row 0,
     hero 1, and so on). A test asserts every one is inside `HomeScaffoldModel.platformPriorities`
     (`0...50`).
   - Driver cards sort by priority, lowest first, then by Driver id raw value, then by card id.
     Platform cards always come before Driver cards, and the footer comes last.
   - Tests:
     - every permutation of a fixed input of at least four cards from two Drivers, with equal
       priorities across Drivers and within one Driver, gives the identical output
     - `HomeModel` returns identical `driverCards` across five consecutive `refresh()` calls
       while the Driver returns its cards in a different order each time
   - The existing `cardOrderAndOmission` test passes unmodified.
5. **The platform stamps who contributed each card.** The registry gathers cards only from
   Drivers in `active` or `degraded` state. Each card is wrapped in a `ContributedCard` whose
   Driver id comes from the registry's own key, never from the card. A Driver that is not running
   contributes nothing. After deactivation its cards leave Home on the next registry change.
6. **Home renders the cards in the `driverCards` slot.**
   - Each card shows its title (headline) and its elements in order, in the same card container
     as the existing text cards (16pt padding, `.thinMaterial`, 12pt corner radius, 12pt between
     cards).
   - Identifier: `home.driver-card.<driver raw id>.<card id>`.
   - Coloured text uses the light/dark pairs in Dev Notes, each tested at 4.5:1 or better.
   - A card from a Driver in `demoIdentifiers` also gets a platform-added caption,
     `DemoDataLabel.text`, under its title. The Driver cannot remove it.
   - Every card renders on macOS and iOS.
7. **The Simulated Driver contributes one demo card (FR-35, FR-37).**
   `SimulatedDriver.dashboardCards()` returns exactly one card:
   - id `simulated.status`
   - title "Simulated Driver"
   - priority `DashboardCardDescriptor.minimumDriverPriority`
   - elements: a `statusBadge` "Demo" in `info`, then a `body` label "Synthetic data for trying
     the app. It does not come from a device."
   It carries **no glucose, insulin or other number** (see "Safety notes"). A fresh demo launch
   shows it below Recent Boluses and above the footer, with the platform demo caption.
8. **Gates.** All nine frontmatter gates pass. The Dev Agent Record has one simulator screenshot
   of Home scrolled to the Simulated card, saved under `.build/`. If the sandbox cannot run the
   simulator, record that and the PM takes it.

## Tasks / Subtasks

- [ ] Task 1: card types and the protocol member in DriverAPI (AC 1, 2)
  - [ ] New `Sources/DriverAPI/Presentation/DashboardCard.swift`: the four types and
        `minimumDriverPriority`. Doc comments say: declarative data only; the platform renders,
        validates, orders and labels; a card must not carry a glucose or dose value until the
        platform has a rule for it (FR-46).
  - [ ] `Sources/DriverAPI/Driver.swift`: add the requirement and a `public extension Driver`
        default that returns `[]`. Update the type's "What every Driver implements" doc line.
        **Do not write the text `DriverLifecycle` anywhere in this file.**
        `DriverLifecycleTests.driverProtocolExposesNoLifecycleState` fails on it.
  - [ ] Tests, new `Tests/DriverAPITests/DashboardCardTests.swift`:
    - the case lists of `CardColor` and `CardLabelStyle` (both `CaseIterable`) are exactly the
      six and four names
    - `CardElement` has two cases. Pin that with an exhaustive `switch` in a test helper, with
      no `default`.
    - the no-UI-import scan
    - a stub Driver with no override returns `[]`
- [ ] Task 2: gathering and validation in DomainCore (AC 3, 5)
  - [ ] New `Sources/DomainCore/ContributedCards.swift`:
    - `ContributedCard` (driver id, descriptor, `id` = "\<raw id\>/\<card id\>")
    - `DashboardCardValidation.accepted(_ cards:from:log:)`, which returns the accepted cards and
      reports each refusal
    - `ContributedCard.ordered(_:)`, the AC 4 sort, pure
  - [ ] `DriverRegistry`: add `public func contributedCards() async -> [ContributedCard]`.
    - It walks `descriptors` in order and skips any Driver not in `active` or `degraded`.
    - It awaits `driver.dashboardCards()`, validates, wraps, and returns `ContributedCard.ordered`.
    - It does **not** take the `enter()`/`leave()` operation lock: it is a read, like
      `port(for:)`.
    - After each `await`, re-check that the Driver is still `active` or `degraded`, and drop its
      cards if not. The actor is reentrant, so a deactivation can finish during the call.
  - [ ] Tests, new `Tests/DomainCoreTests/ContributedCardsTests.swift`:
    - each refusal rule, with the other cards kept
    - the permutation test
    - ties across Drivers break by raw id
    - ties within one Driver break by card id
    - only running Drivers contribute
    - a Driver deactivated while its `dashboardCards()` is suspended contributes nothing. Use a
      gate in the test Driver, as `RegistryTestDrivers.swift` does for `activate`.
- [ ] Task 3: Home layout and model in AppFeature (AC 4, 6)
  - [ ] `HomeScaffold.swift`:
    - add `HomeScaffoldModel.platformPriorities: ClosedRange<Int> = 0...50` and
      `priority(of: HomeCard) -> Int?`, which is the index in `order` for platform cards and
      `nil` for `.driverCards` and `.footer`
    - add `enum HomeSlot: Hashable { case platform(HomeCard), driver(ContributedCard), footer }`
      and `static func layout(contributed:) -> [HomeSlot]`. It returns the platform cards in
      priority order, minus `omittedWithoutData`, then the contributed cards in the AC 4 order,
      then `.footer`.
    - `HomeScaffoldView` iterates `layout(contributed: model.driverCards)` instead of `order`.
  - [ ] New `Sources/AppFeature/DriverCardView.swift`: renders one `ContributedCard`. The colour
        and label-style mappings are in Dev Notes. The demo caption is added when
        `model.isDemoDriver(card.driver)`.
  - [ ] `DriverHost.swift` (`HomeModel`):
    - add `public private(set) var driverCards: [ContributedCard] = []`, and
      `isDemoDriver(_:)` using `demoIdentifiers`
    - reload the cards with `registry.contributedCards()` at the end of a successful
      `connectOnce`, at the end of `refresh()`, and on every registry change (the observer that
      calls `validateConnection`)
    - guard every load with the existing `connectionGeneration` pattern, so a late result from an
      old connection is dropped
    - when the connection drops to no source, clear `driverCards`
  - [ ] Tests:
    - `HomeScaffoldTests`: the priorities band; `layout` with zero, one and three contributed
      cards; the footer is last; `recentMeal` is still omitted
    - `DriverHostTests`: the stable order across five refreshes; cards cleared after a registry
      deactivation; no cards from a Driver that is not running
    - new `DriverCardViewTests` (or inside `StatusRowTests`): the light/dark contrast of every
      `CardColor` pair
- [ ] Task 4: the Simulated card (AC 7)
  - [ ] `Sources/Drivers/Simulated/SimulatedDriver.swift`: `public func dashboardCards() ->
        [DashboardCardDescriptor]` inside the actor. It is constant and reads no generator state.
  - [ ] `Tests/SimulatedDriverTests/SimulatedDriverCapabilityTests.swift`: it returns exactly
        the AC 7 card; the platform validation accepts it; no element text contains a digit.
- [ ] Task 5: gates and screenshot (AC 8). Record the final reviewable diff size.

## Dev Notes

### Read first (rules of the road)

- **Swift 6 strict concurrency, typed throws.** `HomeModel` stays `@MainActor @Observable`.
  `DriverRegistry` is an actor and reentrant across `await`.
- **The only DriverAPI edits are** the new `Presentation/DashboardCard.swift` and the one
  requirement plus default in `Driver.swift`. Do not touch `Capability.swift`, `CapabilityPort`,
  `DriverDescriptor`, `DriverCatalog`, `DriverLifecycle.swift`, `Sources/Persistence/**`,
  `Sources/SafetyCore/**`, `Package.swift`, CI files or the guards. If you need more, write a
  NEEDS-HUMAN line in the Dev Agent Record.
- **No therapeutic write, ever (SI-1).** The new protocol member returns data. Name nothing in
  DriverAPI with a command verb (`ReadOnlyPostureTests.commandVerbs`: set, write, update, apply,
  start...). `dashboardCards` is fine.
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

Applied here:
- **Platform priorities come from indices, not typed literals.** Do not hand-number the cards 0,
  10, 20... because `20` is the glucose lower bound and trips the guard. Do not use steps of 18
  either.
- The band ends `0...50` and the floor `100` are fine for the guards. The test fixtures may use
  100, 110 and 200 (Android's demo and Nightscout values). Do not use 55, 58, 70, 180 or 250 as
  test priorities.
- No SF Symbols in this story (icons are out of scope).
- The contrast pairs are in "Colours" below.

### Why DriverAPI changes, and why that is allowed

**Is a change needed? Yes.** Today `DriverAPI` exposes a `Driver` with `descriptor`,
`capability(_:)`, `activate()` and `deactivate()`, the closed `Capability`/`CapabilityPort` set
of six (all reads), `DriverDescriptor`, `DriverCatalog`, `DriverRow`, the models and Safety
Limits. Nothing in it can carry a card. AD-3 lets a Driver depend only on `DriverAPI` and
`SafetyCore`, and AD-1 says every outside interaction crosses a port declared in `DriverAPI`. So
the card types and the member that returns them have to live in `DriverAPI`. `SafetyCore` is the
wrong home: AD-2 gives it the shapes that two rendering units (phone, Watch, widget) must agree
on, and the Watch hosts no Driver cards (FR-37 Out of Scope).

**It is not a Capability, and the closed set stays closed.**
- AD-12 and FR-30 close the *Capability* set at six. `Capability` and `CapabilityPort` are not
  touched, so `CapabilitySetTests` and the exhaustive switches still hold.
- A dashboard card is presentation metadata that every Driver may supply, as `descriptor` already
  is. It is not a device function that a slot holds, so it has no cardinality and no slot.
- Android has the same split: `observeDashboardCards()` is on `Plugin`, not in
  `PluginCapability`.

**It adds no write surface (AD-12, SI-1).**
- The member returns value data from Driver to platform. Nothing flows back, and there is no
  action, callback or closure.
- `CardElement` is an enum of text-only cases. Interactive elements, action routing and settings
  descriptors are exactly what this story leaves out.
- `ReadOnlyPostureTests` and `driver_guards.sh` (symbol scan and rule D) stay unmodified and must
  pass.

**Why a protocol member and not a descriptor field.** `DriverDescriptor` is compile-time
metadata, constant for the Driver's life (`Driver.swift` says so). Card content changes with the
Driver's state; Android re-emits on a flow. A method the platform calls on each refresh fits
that. Static cards would freeze it. A default returning `[]` keeps every existing conformer
compiling. That matters because AD-16 expects five implementers.

Record this reasoning in the doc comment on the new requirement, in plain words. Do not mention
stories.

### Shapes

```swift
// DriverAPI/Presentation/DashboardCard.swift
public struct DashboardCardDescriptor: Hashable, Sendable, Identifiable {
    /// Driver cards sit at or after this priority; the platform's own cards sit before it.
    public static let minimumDriverPriority = 100
    public let id: String
    public let title: String
    public let priority: Int          // lower sorts higher
    public let elements: [CardElement]
    public init(id: String, title: String, priority: Int, elements: [CardElement])
}

public enum CardElement: Hashable, Sendable {
    case label(text: String, style: CardLabelStyle)
    case statusBadge(text: String, color: CardColor)
}

public enum CardColor: String, CaseIterable, Hashable, Sendable {
    case standard, success, warning, error, info, muted   // Android UiColor; DEFAULT renamed
}

public enum CardLabelStyle: String, CaseIterable, Hashable, Sendable {
    case title, subtitle, body, caption
}
```

- The init does **not** validate and does not trap. Validation is the platform's job (AC 3),
  because a Driver bug must degrade to a missing card (FR-28), never to a crash during a
  background wake (AD-13).
- No `hasDetail` yet. Detail screens are out of scope, and a field nothing reads is a claim
  nothing keeps.

```swift
// DomainCore/ContributedCards.swift
public struct ContributedCard: Hashable, Sendable, Identifiable {
    public let driver: DriverIdentifier
    public let card: DashboardCardDescriptor
    public var id: String { "\(driver.rawValue)/\(card.id)" }
    public static func ordered(_ cards: [ContributedCard]) -> [ContributedCard]
}
```

Sort key: `(card.priority, driver.rawValue, card.id)`, compared lexicographically with plain `<`
on `String`, so the result does not depend on locale. Never rely on `Dictionary` or `Set`
iteration order anywhere on this path. That is the Android defect the epic names.

### Colours and label styles

Coloured text must reach 4.5:1. Reuse `StatusRGB` and the existing pairs from `StatusRowView`
where they exist. Add the two that are missing:

| `CardColor` | Light | Dark | Source |
|---|---|---|---|
| standard | `Color.primary` | `Color.primary` | system label |
| muted | `Color.secondary` | `Color.secondary` | as `StatusColor.muted` |
| warning | `#A16207` | `#EAB308` | `StatusColor.caution` |
| error | `#B91C1C` | `#EF4444` | `StatusColor.error` |
| info | `#2563EB` | `#60A5FA` | **new dark value**: `#2563EB` on a dark card is about 4.1:1, under 4.5 |
| success | `#15803D` | `#22C55E` | **new**: Android's `#4CAF50` is about 2.8:1 on white |

Test each fixed pair: light against white `#FFFFFF`, dark against `#1C1C1E` (the dark
`secondarySystemBackground`, a fair stand-in for the material). Reuse the `contrast(_:_:)` helper
in `StatusRowTests` (move it to a shared test file if you need it in two places). The dark
`error` pair is about 4.5:1 against `#1C1C1E`. If the test shows it below 4.5, use `#F87171` for
dark and say so in the record.

Status badge: text in `.caption2.weight(.medium)` (the small-label style 1.14 chose), in the
colour, on a rounded rectangle (4pt radius) filled with the same colour at 12% opacity, with
padding of 8pt horizontal and 4pt vertical. This matches Android's
`PluginDashboardCardRenderer.kt` `StatusBadgeElement`.

Label styles (Android Material → iOS): title `titleMedium` → `.headline`; subtitle `titleSmall` →
`.subheadline.weight(.semibold)`; body `bodyMedium` → `.body`; caption `bodySmall` → `.caption`.

### Existing code to build on (PR #23 tree)

- `Sources/AppFeature/HomeScaffold.swift`:
  - `HomeCard` has ten cases, including `.driverCards` and `.footer`. `HomeScaffoldModel.order`
    is the FR-39 order, and `omittedWithoutData == [.recentMeal]`.
  - `HomeScaffoldView` iterates `order`, filters out omitted cards and renders `.driverCards` as
    `EmptyView()`. `textCard(_:title:body:)` is the container to match.
  - `DemoDataLabel.text` is "DEMO DATA — not your glucose".
- `Sources/AppFeature/DriverHost.swift`:
  - `HomeModel` holds `registry`, `demoIdentifiers`, `connectionGeneration` and
    `refreshGeneration`.
  - The `registryObserver` task calls `validateConnection()` on each `registry.changes()`
    element.
  - `connectOnce()` sets `ports`, `isDemo` and `heroState` on success.
  - `refresh()` runs the read sequence.
  - `dropConnection(keepCache:)` resets state.
- `Sources/DomainCore/DriverRegistry.swift`:
  - `port(for:)` is the pattern for a read: no `enter()`, and the state is re-checked after the
    `await`.
  - `drivers` is `[DriverIdentifier: any Driver]` and `descriptors` is the ordered array. Iterate
    `descriptors`, never `drivers`.
- `Sources/Drivers/Simulated/SimulatedDriver.swift`: `public actor SimulatedDriver: Driver` with
  `nonisolated let descriptor`. Add the method in the actor body.
- `Tests/DomainCoreTests/RegistryTestDrivers.swift`: gated test Drivers to extend with a
  `cards` property and an optional gate.
- `Tests/DriverAPITests/DriverAPISource.swift`: `files()` and `lines()` over DriverAPI source,
  with comments and strings stripped. Use it for the import scan.

### Safety notes

- **No numbers on the Simulated card.** FR-46 and PD-43 allow a Driver card to show a meter
  reading only with its meter name and the word "meter". Nothing else glucose-like may appear
  outside the SafetyCore formatter path. Until the platform has a rule for numeric card content,
  the only shipped card carries none, and AC 7's test pins it ("no digit in any element text").
- The Watch hosts no Driver cards (FR-37 Out of Scope). This story touches no Watch or widget
  surface.
- A card can never move above the hero. The priority floor is enforced by refusal, and platform
  cards come first by construction.

### Release-build lifetime

No new object is held weakly by a system API. `driverCards` lives on `HomeModel`, which the app
holds in `@State`. The card load runs in tasks that `HomeModel` already owns or awaits inline.
Do not start an unowned `Task` per card.

### Out of scope (later work; do not build)

These are still owed to FR-37, and no epic story currently carries them. The PM should plan a
follow-up:
- The remaining seven element variants (large value, progress bar, icon value, sparkline, row,
  column, spacer), the 13 icons, and nesting and size bounds (5 levels, 100 elements).
- Tappable detail screens and their four states.
- Settings descriptors and per-control persistence (pairs with 1.12c's settings store).
- The Nightscout source's card at priority 200 (FR-38, FR-153).

### Testing standards

- Swift Testing. `@MainActor` for `HomeModel` tests. No sleeps; use `eventually` and gates.
  Release every gate a test closes.
- AppFeatureTests cannot import `SimulatedDriver` or DomainCoreTests. Extend the test Driver
  already in `DriverHostTests` with a `cards` array that can be reordered between calls.
- Known flake: `WallClockSchedulerTests`. You may re-run once; record it if you do.

### Project structure notes

- New: `Sources/DriverAPI/Presentation/DashboardCard.swift`,
  `Sources/DomainCore/ContributedCards.swift`, `Sources/AppFeature/DriverCardView.swift`, plus
  tests `Tests/DriverAPITests/DashboardCardTests.swift`,
  `Tests/DomainCoreTests/ContributedCardsTests.swift`.
- Changed: `Sources/DriverAPI/Driver.swift`, `Sources/DomainCore/DriverRegistry.swift` (one
  read method), `Sources/AppFeature/HomeScaffold.swift`, `Sources/AppFeature/DriverHost.swift`,
  `Sources/Drivers/Simulated/SimulatedDriver.swift`, `Tests/AppFeatureTests/HomeScaffoldTests.swift`,
  `Tests/AppFeatureTests/DriverHostTests.swift`,
  `Tests/DomainCoreTests/RegistryTestDrivers.swift`,
  `Tests/SimulatedDriverTests/SimulatedDriverCapabilityTests.swift`.
- `driver_guards.sh`:
  - rule D forbids `as?`, `as!` and `is` against `Driver`, a port, or a Driver-target type
    outside DriverAPI. The renderer switches on `CardElement`; it never casts.
  - the symbol scan covers DriverAPI and `Drivers/*`. Keep the deny-listed words (see the guard)
    out of card text and identifiers there.

### Android reference (copied here; your sandbox cannot read the Android repo)

- `android-unofficial/plugins/pump-driver-api/src/main/java/com/glycemicgpt/mobile/domain/plugin/ui/DashboardCardDescriptor.kt`:
  `data class DashboardCardDescriptor(id, title, priority = 100, elements: List<CardElement>,
  hasDetail = false)`, with `require` checks for a non-blank id and title. iOS validates on the
  platform side instead and does not trap.
- `.../domain/plugin/ui/CardElement.kt`:
  - the sealed class has nine cases: LargeValue, Label, StatusBadge, ProgressBar, IconValue,
    SparkLine, Row, Column, Spacer
  - `enum UiColor { DEFAULT, SUCCESS, WARNING, ERROR, INFO, MUTED }`
  - `enum LabelStyle { TITLE, SUBTITLE, BODY, CAPTION }`
  - `enum PluginIcon` has 13 cases
- `.../domain/plugin/Plugin.kt:42`: `fun observeDashboardCards(): Flow<List<DashboardCardDescriptor>>`.
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/home/HomeViewModel.kt:137-150`:
  it combines every active plugin's flow and calls `.sortedBy { it.card.priority }` with no
  tiebreak. Equal priorities then keep plugin iteration order, which is the instability FR-37's
  Driver-id tiebreak removes.
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/plugin/PluginDashboardCardRenderer.kt`:
  card padding 16dp; label styles at :142-147; status badge at :153-168; colours at :277-283
  (SUCCESS `#4CAF50`, WARNING `#FF9800`, INFO = primary).
- `android-unofficial/plugins/example/src/main/java/com/example/glycemicgpt/plugin/DemoGlucometerPlugin.kt:223-340`:
  the demo plugin's cards at priority 100 and 110.

### References

- [Source: epics.md Story 1.18]
- [Source: prds/prd-ios-unofficial-2026-08-01/prd.md FR-28, FR-35, FR-37 (:727), FR-38 (:746), FR-39 (:812), FR-46, PD-43]
- [Source: architecture ARCHITECTURE-SPINE.md AD-1, AD-2, AD-3, AD-12, AD-13, AD-16]
- [Source: Sources/DriverAPI/Capability.swift and Driver.swift doc comments: the closed set and the downcast seam]

## Dev Agent Record

### Agent Model Used

Amelia / Senior Software Engineer (Codex).

### Debug Log References

- `git diff --check` — passed.
- `bash scripts/guards/safety_guards.sh` — passed.
- `bash scripts/guards/safety_guards.sh --self-test` — passed (75 cases, 2 documented bypasses, no unexpected results).
- `bash scripts/guards/driver_guards.sh` — passed.
- `bash scripts/guards/driver_guards.sh --self-test` — passed (68 cases, 3 documented limits, no unexpected results).
- `bash scripts/ci-local.sh --self-test` — passed (all cases passed).
- `swift build` and `swift test` — blocked before compilation: sandbox denied the default user clang module cache. Retrying with a workspace module cache and `--disable-sandbox` reached dependency resolution but could not resolve `github.com` to fetch GRDB.
- `xcodebuild test -scheme GlycemicGPT-Package ...` — failed because simulator services/runtimes were unavailable and xcodebuild reported no project, workspace, or package at the repository root.
- `xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj ...` — blocked resolving package dependencies by the same module-cache access and unavailable network.
- Simulator screenshot was not captured because CoreSimulatorService was unavailable.

### Completion Notes List

- Added data-only dashboard card types and a default empty Driver method.
- Added card validation, registry-state filtering, attribution from registry keys, and deterministic priority/Driver/card ordering.
- Added Home layout/rendering, demo caption, generation-guarded card refreshes, and the Simulated Driver's text-only demo card.
- Added API, domain, Home layout/refresh/deactivation, simulated-card, and contrast tests.
- Cycle 2 (compiled host):
  - safety_guards.sh failed on `Sources/AppFeature/DriverCardView.swift`: the Dev Notes `success` light value `#15803D` has components `0x15` (21) and `0x3D` (61), inside the drift bands of the glucose lower bound (20) and the alert-floor future skew (60). The cycle-1 record of a passing guard run was wrong. Fix: `success` now reuses the existing Home green (`HeroColor.green.ageCaptionRGB`, light `#167A34`, about 5.4:1 on white; dark `#22C55E`). `warning`, `error` and light `info` now delegate to the `StatusColor` pairs instead of re-spelling them. The only new literal is the dark `info` blue `#60A5FA`. No guard file was touched; `scripts/` has no diff.
  - Dark `error` (`#EF4444`) passes 4.5:1 against `#1C1C1E`, so `#F87171` was not needed.
  - Removed an unused `Color(hex:)` extension.
  - Test compile fix: the WCAG `contrast(_:_:)` helper moved from `StatusRowTests` into shared `Tests/AppFeatureTests/ContrastRatio.swift` (imports Foundation for `pow`), used by both suites.
  - `dashboardCards()` is declared `async` (the spec sketch was synchronous). The Driver is an actor, so the platform awaits it either way, and `async` lets a Driver suspend while building cards; the registry re-checks state after the await.
  - Simulator screenshot not captured, and `xcodebuild test` not run: the simulator was in use by another engineer. The PM takes both. `build-for-testing` compiled the package tests for the simulator destination instead.
- Reviewable diff (Sources + Tests, untracked files included): 17 files, +467 / -19.
- Review fixes (2026-11-01):
  - Card reloads now run in a task owned by `HomeModel`. Each new reload cancels the previous one. The registry change loop and `refresh()` never await Driver card code, so a Driver whose `dashboardCards()` never returns cannot stall deactivation handling or pull-to-refresh.
  - `DriverRegistry.contributedCards(timeout:)` queries Drivers concurrently in unstructured tasks. It drops any Driver that has not answered within `DriverRegistry.dashboardCardsTimeout` (3 s, presentation-only, chosen so it matches no safety constant) and returns at once when cancelled. A task group was not used because it waits for every child.
  - Each reload carries a sequence number, and only the latest reload publishes its results.
  - `ContributedCard.id` is now a structured `ContributedCard.ID` (Driver + card id) instead of a "/"-joined string.
  - New tests: a hung Driver does not block refresh or a later deactivation; a slower, earlier reload cannot replace later cards; a hung Driver does not hold back other Drivers' cards; cancelling a card read returns without waiting; a card id with "/" keeps its parts apart.
- Follow-ups for 1-18b:
  - The ban on glucose and dose lookalikes in card text is enforced only by documentation today. No validation or guard checks it.
  - With first-wins handling of duplicate card ids, which card is kept depends on the order a Driver returns them in. If that order is unstable, the shown card can flicker between reloads.

### File List

- `Sources/DriverAPI/Presentation/DashboardCard.swift` (new)
- `Sources/DriverAPI/Driver.swift`
- `Sources/DomainCore/ContributedCards.swift` (new)
- `Sources/DomainCore/DriverRegistry.swift`
- `Sources/AppFeature/DriverCardView.swift` (new)
- `Sources/AppFeature/HomeScaffold.swift`
- `Sources/AppFeature/DriverHost.swift`
- `Sources/Drivers/Simulated/SimulatedDriver.swift`
- `Tests/DriverAPITests/DashboardCardTests.swift` (new)
- `Tests/DomainCoreTests/ContributedCardsTests.swift` (new)
- `Tests/DomainCoreTests/RegistryTestDrivers.swift`
- `Tests/AppFeatureTests/ContrastRatio.swift` (new)
- `Tests/AppFeatureTests/DriverCardViewTests.swift` (new)
- `Tests/AppFeatureTests/StatusRowTests.swift`
- `Tests/AppFeatureTests/HomeScaffoldTests.swift`
- `Tests/AppFeatureTests/DriverHostTests.swift`
- `Tests/SimulatedDriverTests/SimulatedDriverCapabilityTests.swift`

### PM decisions on drafting open points (2026-11-01)
- **Naming.** 1.12c is named for its real scope. FR-34's event channel moves to 1-12d, which goes into the tracker as backlog.
- **FR-37 remainder.** The other seven card element types, icons, detail screens and settings descriptors become a tracked follow-up, 1-18b, in backlog. This story ships the closed vocabulary subset only.
- **FR citation.** The card sort rule lives in FR-37/FR-39. The epic's FR-38 citation will be corrected in the next docs sync. Implement against FR-37/FR-39.
- **Parallel work.** 1.12c and 1.18 run at the same time and both touch DriverAPI. 1.12c adds a NEW file for the settings protocol. 1.18 adds one requirement with a default in `Driver.swift`. Neither should reformat or reorder the other's area, so the two merge cleanly.
- budget: CONTINUATION_REQUIRED sha256:3459e4029d1641a9ef898d21a735d6b2d71b85fcd90b1527be53dde1f4bc732a cycle 1 2026-11-02T01:39:57Z
