## 6. Cross-Cutting Non-Functional Requirements

**Scope.** NFR-1 through NFR-34 are system-wide quality attributes: properties every feature section
inherits and none of them owns. Where a feature section already states a number (Freshness Tier
thresholds, queue constants), this section references it and does not restate it — a second copy of a
number is a defect for the same reason SI-4 exists. The **accessibility parity rule** runs the other
way: it is a system-wide target no feature section owns, so **NFR-30 states it once** and 5.9 cites it.

**Measurement honesty.** Under fork-and-build the project produces no binary, holds no signing key and
sees no device. The lead developer has a Mac, an Apple Developer account and a Tandem t:slim X2 but no
iPhone and no Apple Watch, and Core Bluetooth does not exist in the iOS Simulator (decision 10). Every
NFR below is therefore written as either (a) a property a Simulator or a unit test can prove, or (b) a
target with a named measurement protocol and a named owner. No NFR here is a claim about a measurement
the project has not made. This is why the Android public site's `< 5% per day` battery figure is not
inherited (NFR-10).

---

### 6.1 Platform floor, device classes and the shared module

#### NFR-1: One deployment floor — iOS 17.0 and watchOS 10.0

The project publishes exactly one deployment floor, quoted identically in the build settings, the
install runbook (5.12 FR-223), the Apple Watch setup page (5.12 FR-224), the Settings About surface
(5.9 FR-173) and the contributor prerequisites (5.12). It is **iOS 17.0 / watchOS 10.0**. The floor is
**settled, not open**: no section, no assumption and no Open Question may carry the iOS 18 / watchOS 11
figure as a floor.

**Reconciliation of the two figures in the research:**

| Figure | What it actually is | Disposition |
|---|---|---|
| iOS 17 / watchOS 10 | Runtime floor implied by APIs the feature sections require | **Adopted as the deployment target** |
| iOS 18 / watchOS 11 | Simulator runtimes bundled with the Xcode the contributor prerequisites name | Toolchain and CI test-runtime figure. **Not a floor.** Owned by NFR-3 |

**Why iOS 17 / watchOS 10 and not lower:**

| Requirement | Section | Minimum |
|---|---|---|
| Chart pinch-zoom with the current magnification gesture, simultaneous with drag | 5.3 | iOS 17 |
| Watch Smart Stack widgets as a placement path that needs no face configuration | 5.7 (FR-117, FR-119) | watchOS 10 |
| A WidgetKit-only complication story with no legacy complication framework | 5.7 (FR-117) | watchOS 10 |
| Observation-based view state without a back-compatibility shim across four targets | all UI | iOS 17 / watchOS 10 |
| `timeSensitive` interruption level for urgent-low delivery (decision 4) | 5.4 | satisfied well below the floor |
| Core Bluetooth state restoration and background central | 5.1 | satisfied well below the floor |
| Lock Screen and accessory widget families | 5.7 (FR-119) | satisfied below the floor |

**Why not higher:** raising the phone floor to iOS 18 excludes no iPhone that iOS 17 supports, so it
buys nothing. Raising the wrist floor to watchOS 11 drops Apple Watch Series 4, Series 5 and the
first-generation SE for no capability this PRD requires. The floor is therefore set by the Watch, and
the Watch says 10. [ASSUMPTION: iOS 18's supported-iPhone set is identical to iOS 17's, and watchOS 11
drops Series 4, Series 5 and SE 1st generation. Verify against Apple's published support lists before
the floor is written into build settings; if either is wrong the trade-off above changes, not the
requirement to publish one number.]

**Consequences (testable):**
- Every target (app, Watch app, every widget extension, every Driver module, the shared safety module)
  declares the same floor. A target declaring a different minimum fails the `iOS Gate` Required Check —
  5.11 FR-197 fixes the roster of exactly five Required Check names and FR-208 is the job that builds
  every target; this NFR adds no sixth check.
- No API newer than the floor is called without an availability guard, and no availability guard exists
  whose fallback branch changes a safety behaviour — a fallback that alerts differently, classifies a
  Freshness Tier differently or renders a Coverage Claim differently is a defect.
- The floor appears once as a build setting and is read from there by the docs generator; no page hard-codes it.

#### NFR-2: Supported device classes, and what the Simulator can never prove

The app is iPhone-only and the Watch app is Apple Watch-only. No other device class is supported,
tested or offered.

**Consequences (testable):**
- Device family is iPhone only. iPad, Mac (Catalyst or "Designed for iPhone") and visionOS availability
  are explicitly opted out in the build and in App Store Connect, so a Builder's TestFlight never offers
  the app on a device class with no Bluetooth pairing story and no validated layout.
- The supported iPhone set is every iPhone that runs iOS 17.0 or later; the supported Watch set is every
  Apple Watch that runs watchOS 10.0 or later, including SE and Ultra models. [ASSUMPTION: iPhone XS,
  XS Max, XR, SE 2nd generation and later for the phone; Apple Watch Series 4 and later plus SE and
  Ultra for the wrist. Regenerate from Apple's published lists at implementation time.]
- The Watch app requires an iPhone running the app; it does not run independently (5.7 FR-115).
- Performance targets in 6.2 are stated against the **oldest supported device**, not against current
  hardware.

**The Simulator/device split is a first-class NFR, not a testing detail.** The following can only be
validated on hardware and a green Simulator result for any of them is treated as **no result**:

| Property | Why the Simulator cannot prove it |
|---|---|
| Core Bluetooth anything | Core Bluetooth does not exist in the Simulator (decision 10) |
| Keychain accessibility class behaviour while locked | Simulator Keychain is not Secure-Enclave-backed and does not enforce lock state |
| File protection class behaviour on a background write | Not enforced |
| Local Network privacy grant and denial | Not enforced |
| Background execution frequency, wake budgets, thermal state | Not modelled |
| Wrist haptics, and audibility with the ring/silent switch or a Focus enabled | Haptics are a no-op and there is no physical switch. The app never sets a volume and never reads or infers the switch position (5.4 FR-66, PL-24), so the effect on delivery is observable only by a human on hardware |
| Complication reload and metered-transfer budgets | Not enforced |
| Battery cost of any kind | Not measurable |

These populate the device Validation Tier (§9.1 Tier 4) and are validated by DanielDanielson building
from their own fork under their own Apple Developer account (decision 9), or by a community validator.

#### NFR-3: Pinned toolchain, and a floor-runtime test job

The toolchain is pinned, and CI proves the app both builds against the newest pinned runtime and runs
against the floor runtime.

**Consequences (testable):**
- The toolchain minimum is macOS 15+, Xcode 16+ and a Swift 6 toolchain, pinned by exact version in the
  repository per 5.10 FR-193 and enforced by the `iOS Gate` and `Workflow Lint` Required Checks
  (5.11 FR-208, FR-202); the docs prerequisites quote the same pin.
- Builds compile with warnings-as-errors and Swift 6 strict concurrency checking (FR-208); a
  data-race-safety violation is a build failure, not a warning.
- The Simulator test matrix includes at least one destination at the **deployment floor** (iOS 17.0 /
  watchOS 10.0) in addition to the newest pinned runtime, so an unguarded newer API is caught by CI
  rather than by a Builder on an older phone.
- Raising the toolchain pin or the floor is a project-lead decision recorded in the repository (5.10
  FR-193), never a side effect of a dependency bump. It is not a parity item and owes no Parity Ledger
  row.

#### NFR-4: One shared safety module, linked by every target (SI-4)

Exactly one compiled module holds every Safety Constant and every safety decision function, and the app,
the Watch app and every widget extension link it. No target may define, re-derive, mirror or duplicate
any of them.

**Consequences (testable):**
- The three Safety Constants — the Conversion Factor 18.0156, the Glucose Validity Bound 20–500 mg/dL,
  and the Tandem epoch offset 1199145600 — exist exactly once. FR-217's drift guard fails any pull
  request that reintroduces a literal copy anywhere in the repository, including in tests and in a Driver.
- The module also holds the pure decision functions: Freshness Tier classification and its thresholds,
  the relative-age label, the backward-clock guard, the negative-age rule (5.3 FR-49 owns it — a negative
  age classifies as Fresh **for display only** and never arms the Alert Floor, SI-5), Alert Threshold
  sanitization and ordering, glucose banding, the Coverage Claim decay and expiry, the glucose and IOB
  render functions, and the history codec.
- The pinned mg/dL → mmol/L conversion fixture belongs to this module and exists exactly once; 5.3 FR-60
  states the anchor table. No other section, target or test restates the anchors — the phone, the Watch
  app and every widget extension are pinned by that one fixture (SI-4).
- The module has no UI, no transport and no Core Bluetooth dependency, so it is testable with plain
  `swift test` on a Mac with no Xcode, no Simulator and no network (FR-210).
- The module links into every target as a dependency of the target itself, not through a transitive path
  that a build-setting change could sever. A target that builds without it fails the `iOS Gate` Required
  Check (5.11 FR-197, FR-208).
- The Android defect where the Wear module mirrors freshness numbers independently must not be reproduced
  (5.7 FR-116). A CI check asserts the Alert Floor firing path (5.4 FR-71) and the Watch relay path call
  the same function.

**The shared data container (SI-4) — the structural replacement for the Wear Data Layer:**

- One App Group identifier is used by the app, the Watch app and every widget extension, and it is
  derived from the Builder's Team ID rather than committed as a literal (5.10 FR-181). An entitlement
  naming a group outside the signing team's prefix fails signing rather than falling back.
- That identifier resolves to two container instances that no filesystem joins: a phone-side container
  the app writes and the phone widget extensions read, and a Watch-side container the Watch app writes
  and the wrist complications read. The only path between the two devices is WatchConnectivity (5.7).
  No requirement anywhere may assume a write on one device is visible on the other.
- Each container carries a bounded, derived glanceable projection and nothing else: the last Glucose
  Reading, up to 72 Glucose Readings (5.7 FR-122), the last IOB, the display unit, and the current
  Coverage Claim with its expiry and Not-Watching Reason. No credential, no pairing secret, no database
  key, no raw pump frame and no history table is ever written there (NFR-18, NFR-19).
- Exactly one writer per container; every other target that links it is read-only. A reader never
  constructs a Glucose Reading the shared module did not validate, and never derives a Coverage Claim of
  its own (SI-6).
- The container is a cache, never a second store. The encrypted database (NFR-19) stays the only
  authoritative store, nothing in the container is an input to the Alert Floor, and a value read from it
  renders with the same Freshness Tier treatment as a value read from the store.
- A Builder who changes Team ID, or who rebuilds from a fresh fork, gets a different container identifier
  and therefore an empty container. An absent, unreadable or malformed container renders the no-data
  state and re-populates on the next ingest; it is never reported as an error and never renders a stale
  value (5.7 FR-122).
- [ASSUMPTION: the full target topology — how many widget extensions exist, and which target owns each
  writer — is an architecture decision, not a PRD one. This NFR fixes the data contract; the architecture
  addendum fixes the target list.]

---

### 6.2 Performance and responsiveness

[ASSUMPTION: no responsiveness target in this subsection has an Android counterpart to port — the
Android client publishes none. These are new targets, chosen to be provable in the Simulator on the
floor runtime plus one device-tier confirmation. They run as tests inside existing jobs; none of them is
a Required Check, and making one merge-blocking means changing FR-197's five-name roster, which is a
project-lead decision.]

#### NFR-5: Interaction responsiveness

Every user-initiated interaction on every surface completes within one frame budget on the oldest
supported device, or shows a determinate or indeterminate progress state within 100 ms and never
blocks input.

**Consequences (testable):**
- Scrolling Home, Settings, alert history, bolus history and meal history holds the display's frame
  budget with the full data ceilings of NFR-7 loaded.
- Chart pan, pinch-zoom and tap-to-inspect hold frame budget across the full 30-day period with the
  row caps of NFR-7 applied; the binary search for the nearest reading is not permitted to run on the
  main thread for the "All" data sets.
- No screen performs a Keychain read, a database read, a decode, a crypto operation or a file read
  synchronously on the main thread (NFR-8).
- Any operation that can exceed 500 ms has a visible state and a cancel or a bounded timeout; nothing
  can present an indicator that never resolves (this is the general form of 5.5's "Estimating carbs…"
  rule).
- Tests assert on the identifier registry (FR-177), so responsiveness assertions run in the Simulator
  without hardware.

#### NFR-6: Cold start is honest before it is fast

The first frame the user sees is never optimistic. Time-to-first-frame is a target; time-to-first-**honest**-frame
is a requirement.

**Consequences (testable):**
- The Coverage Claim's first-frame value is a pessimistic synchronous seed that assumes no reading age
  and no Backend, so a cold start into an existing outage never renders all-is-well copy (5.4).
- No session prompt, "not signed in" banner or Backend-state copy renders off the pre-validation startup
  state, so nothing flashes at cold start (5.8, 5.3).
- The device-connectivity signal is seeded pessimistically from the current path before the first system
  callback (5.8).
- The Watch app and every widget render real cached data on cold start rather than `--`, because the
  widget reads the shared on-device cache directly and does not require the Watch app process to have
  run first (5.7 FR-116).
- Cold start does no network work and no Bluetooth work before the first honest frame.

#### NFR-7: Data-volume ceilings the UI must hold

Every surface must remain within NFR-5 at the maximum data volume the store can present.

| Surface | Ceiling |
|---|---|
| Chart series (Glucose Reading, IOB, Basal) | 2,000 rows (5.3; enforced by the query layer, 5.8) |
| Chart series (Bolus) | 500 rows (5.3) |
| Analysis card series ("All" variants) | 50,000 rows |
| Outbound queue | **20,000 rows** before oldest-first pruning — the enforced cap is 5.8 FR-142's and this table quotes it |
| Alert history, meal history | one fixed page each, no infinite scroll (5.4, 5.5) |
| Retention | the user's configured retention window, 1–30 days, default 7 — enforced by 5.8 FR-139, set in 5.9 FR-175 |

**Consequences (testable):**
- A performance test loads each ceiling from a seeded store and asserts NFR-5 on the floor runtime.
- Truncation at a ceiling is silent to correctness but never silent to the user where it changes what a
  chart means: the 30-day chart's oldest-end truncation at 2,000 rows is stated in the Parity Ledger as
  inherited Android behaviour, not discovered as a bug.
- No computation over the "All" series runs on the main thread.

#### NFR-8: Main-thread and background-wake work rules

No safety-relevant path may block the main thread, and no background wake may spend its runtime on work
that is not load-bearing.

**Consequences (testable):**
- Keychain reads, database opens, database reads and writes, decodes, and crypto never execute on the
  main thread. Enforced by a lint or a debug-configuration assertion that is not a `precondition`
  (SI-2 — a trap in a monitoring app is unacceptable, see NFR-14).
- A Core Bluetooth state-restoration relaunch gets roughly 10 seconds of runtime, extendable to roughly
  30 seconds. Within that window the work order is fixed and asserted by test: **persist the frame →
  advance the cursor only if it decoded (SI-8) → evaluate the Alert Floor → refresh the Coverage Claim →
  update wrist and widget surfaces → enqueue upload**. Upload is last because it is the only step whose
  failure is recoverable later.
- No background execution waits on a network response before completing its persistence and alerting
  work.
- Uploads are handed to the system as file-backed background transfers, so a push started in the
  foreground finishes without the app being kept alive (5.8).

#### NFR-9: Deterministic behaviour under interruption

Every long-running operation is resumable or idempotent, because iOS may suspend or terminate the app at
any point.

**Consequences (testable):**
- History extraction, queue drain, Backend pull and retention cleanup are each idempotent: running
  the same step twice produces the same store state.
- A process death at any point in a batch leaves the store consistent, the cursor no further advanced
  than the last successfully decoded record (SI-8), and no partially applied migration.
- An in-flight upload interrupted by termination is re-selectable on the next execution opportunity via
  the queue's SQL predicate over stored timestamps, not via an in-memory timer.

---

### 6.3 Battery and background cost

#### NFR-10: No published battery figure without a project measurement

The project publishes no battery-consumption number for iOS until it has measured one, and never carries
the Android figure.

**Consequences (testable):**
- The Android public site's `< 5% per day` figure is an Android measurement of an Android background
  model — a foreground service holding a wake lock with a 3-second loop. It has no iOS meaning and must
  not appear in any iOS documentation page, onboarding screen, Settings copy, release note or README.
  A docs check greps for it and fails.
- In its place, the user-facing statement is qualitative and honest: what the app does in the background,
  what it does not do, and the fact that no per-day figure is published yet.
- A figure may be published only once it has been measured under the protocol below by at least two
  people on at least two device models, and it is published **with** its device model, OS version, mode
  and date attached. A bare percentage with no conditions is not publishable.

**Measurement protocol (owned by the device Validation Tier, §9.1 Tier 4):**
- 24-hour window; screen off for the bulk of it; app backgrounded and not force-quit; Background App
  Refresh on; Low Power Mode off; one paired Pump connected.
- Measured separately in Backend-optional mode and in Backend-connected mode, because the second adds a
  live Backend stream and an upload queue.
- Instrumented from the device's own per-app battery reporting over 24 hours, corroborated by on-device
  energy metrics where the platform reports them.
- Result recorded against device model, OS version, mode and date, in the repository, not only in a chat
  message.

#### NFR-11: Background cost is budgeted as work, not as a percentage

The app requests no background runtime it does not use, and holds no runtime it does not need.

**Consequences (testable):**
- The app schedules no repeating timer that runs while backgrounded. Every background execution is one
  of: a Core Bluetooth event the Pump caused, a system-granted refresh or processing task, an incoming
  wrist transfer, or the user foregrounding the app.
- A granted background execution that finds nothing to do completes and returns immediately rather than
  extending itself.
- The app declares only the background modes it uses. It uses **no** background location, **no**
  significant-location-change, **no** silent-push keep-alive, **no** audio-session keep-alive and **no**
  other technique whose purpose is to buy runtime the platform did not grant. Using one is a defect, and
  the declared background-mode set is asserted by the Entitlements and Plist Guard inside the
  `Static Analysis Gate` Required Check (5.11 FR-204, §10).
- Foreground poll cadence matches Android exactly; background cadence is opportunity-driven and never
  promised to the user (5.8).
- The freshness re-classification ticker (quarter of the source's stale threshold, clamped to 2–30
  seconds) suspends when its view is off screen and resumes with a recomputed age, never a cached tier
  (5.3).
- Metered wrist transfers are spent only on material change — a glucose band crossing, a Freshness Tier
  transition, an alert state change, a Coverage Claim state change — with a floor of at most one per 15
  minutes; all purely time-driven transitions are pre-baked as future timeline entries that cost nothing
  (5.7 FR-122).

#### NFR-12: Low Power Mode and thermal state degrade honestly

When the system takes execution away, the app says so rather than appearing to still be watching.

**Consequences (testable):**
- Low Power Mode removes the opportunistic background refresh path. The app reports this in the Settings
  reliability card and, when it changes what is watching, in the Coverage Claim's Not-Watching Reason
  (SI-6).
- Elevated thermal state may reduce background opportunities; the app reduces non-essential work
  (analysis recomputation, chart pre-rendering, wrist refresh above the material-change floor) before it
  reduces anything on the Alert Floor path. The Alert Floor path is never the first thing shed.
- No degradation path silently lowers a Freshness Tier threshold, widens the Glucose Validity Bound, or
  extends a Coverage Claim expiry to make coverage look better than it is (SI-5, SI-6, SI-11).

---

### 6.4 Reliability and data durability

#### NFR-13: Persist before derive

A datum is durable before any surface, alert or upload depends on it.

**Consequences (testable):**
- On every ingest path the order is persist → derive → alert → present → enqueue upload. A crash between
  any two steps loses no captured data.
- History cursors never advance past a record that was not successfully decoded (SI-8), on every Driver
  and on every Backend pull.
- Only COMPLETED insulin deliveries are ever written as delivered (SI-7).
- No monitoring datum exists only in memory across a suspension boundary.

#### NFR-14: No trap on any ingest, decode, background-wake or render path

A monitoring app that traps is a monitoring app that stopped watching. Rejection is recoverable and
logged; it never crashes the process (SI-2).

**Consequences (testable):**
- Invalid data uses failable or throwing initializers. `precondition`, `assert` in a release
  configuration, `fatalError`, `try!`, `as!`, force-unwrap and unchecked collection indexing are
  prohibited on ingest, decode, background-wake, alerting, persistence and render paths, and a lint gate
  enforces it (5.11).
- Every rejection is recorded with enough context to diagnose it and nothing that violates SI-9
  (NFR-24).
- A malformed Backend response, a malformed pump frame, a corrupt stored row, a clock jump and an
  unexpected enum value each produce a recoverable outcome with a user-visible consequence where the
  user needs one — never a process exit.
- Android's `TimeInRangeData` construction throws on inconsistent aggregate percentages. The iOS port
  renders an empty or degraded card instead; a malformed aggregate must not take down a monitoring app.
  This is the general `require`/`check` → failable-initializer divergence already recorded as PD-25 (§7);
  no second row is owed.

#### NFR-15: Migrations never destroy data as a fallback

Schema evolution is explicit in both directions and has no destructive backstop.

**Consequences (testable):**
- Every schema version hop has an explicit, tested migration. There is no equivalent of Android's
  `fallbackToDestructiveMigration()`, which silently wipes local pump history on an unhandled path or a
  downgrade. Recorded in the Parity Ledger as an intentional divergence.
- An unmigratable store surfaces an explicit, user-visible failure with a stated recovery path; it never
  deletes and never silently starts empty.
- A migration failure leaves the previous store intact and readable by the previous build, because under
  fork-and-build a Builder can and will install an older build (5.10).
- Migration tests run in CI over fixture stores at every prior schema version.

#### NFR-16: Bounded growth everywhere

No store, buffer, queue or cache grows without a bound and a documented eviction rule.

**Consequences (testable):**
- Every table has a retention or cap rule and a test that proves it applies. The Android defect where
  `raw_history_logs` grows without bound in full-stack mode because its cleanup is defined but never
  called must not be reproduced; the iOS port calls it (5.8 FR-139, recorded as PD-20 in §7).
- The outbound queue is bounded, prunes oldest-first at the bound, and the prune is deliberate data loss
  stated to the user rather than discovered. The bound is 5.8 FR-142's **20,000 rows**; this section
  quotes that figure and defines no second one.
- The in-app log buffer is a bounded ring buffer (NFR-33).
- The Watch cache is bounded to what FR-122 defines (72 Glucose Readings, oldest dropped on overflow)
  and is never a second store.

#### NFR-17: Degradation is always announced

Any condition that stops the app from watching, or stops it from watching as well, is surfaced with a
specific cause. Silence is never an acceptable failure mode.

**Consequences (testable):**
- The Coverage Claim carries an explicit expiry, decays without new data, and resolves to not-watching
  **with** a Not-Watching Reason; the Watch renders and decays the phone's claim and never derives one
  (SI-6).
- No surface anywhere renders a value in a way that implies it is current when its Freshness Tier says
  otherwise.
- A failure the app cannot detect while stopped — force-quit, device restart, termination — is detected
  from the data itself on next launch and reported, not resumed quietly (5.8).
- No error state resolves to a blank screen, a spinner that never ends, or a stale value with no age.

---

### 6.5 Security posture

#### NFR-18: Credential custody (SI-10)

Every credential and pairing secret lives in the Keychain, device-only, available after first unlock.

**Consequences (testable):**
- Accessibility class is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for every pump and auth item.
  This is **settled**, not an open question: every FR that touches the class agrees on it. A synchronizing
  class would push pump credentials into iCloud Keychain; `kSecAttrAccessibleWhenUnlocked` would break
  overnight reconnection while locked — the exact window this app exists to cover (UJ-2). Any other class
  fails the Entitlements and Plist Guard inside the `Static Analysis Gate` Required Check (5.11 FR-204).
- No credential, pairing code, pairing secret, database key or token is stored in a settings store, a
  plist, an App Group file, a log, a cache, or a Driver's own storage (5.2).
- Keychain items survive app deletion, so a first run after a fresh install purges the app's own items
  before anything reads them (5.8 FR-136).
- Keychain access group and App Group container are derived from the Builder's Team ID; an entitlement
  naming a group outside the signing team's prefix fails signing rather than falling back (5.10 FR-181).
- The Watch app holds no credential and performs no network request (5.7).

#### NFR-19: At-rest encryption and file protection

All monitoring data is encrypted at rest, in one store, at a protection class that permits background
writes on a locked device.

**Consequences (testable):**
- One encrypted database holds all record kinds. The key is 32 bytes from a cryptographic random source,
  generated once, never regenerated, and held per NFR-18.
- The database file's protection class is complete-until-first-user-authentication (or complete-unless-open),
  never complete — which would fail background writes while locked. A unit test asserts the attribute and
  the Entitlements and Plist Guard inside the `Static Analysis Gate` Required Check enforces the setting
  (5.11 FR-204).
- No health value is written outside that store, with exactly one exception: the bounded, derived
  glanceable projection in the shared App Group container that NFR-4 defines, which is a cache and never
  a source of truth. Nothing else — not `UserDefaults`, not a cache directory, not a temporary file that
  outlives its transfer, not a pasteboard — ever holds a health value.
- The shared container is written at the same protection class as the store, so a locked device can still
  write it from a background wake and a complication can still read it while the Watch is locked, and it
  holds no credential, no key and no raw frame.
- File-backed background upload bodies are written inside the protected container and deleted on
  completion or failure.

#### NFR-20: Transport security — no cleartext to a non-private host, enforced in the app

No request leaves the device in plaintext to any host that is not a literal loopback, private (RFC1918),
carrier-NAT (`100.64.0.0/10`) or link-local address, and the rule is enforced by the app's own code
rather than by platform configuration. This NFR states the system-wide obligation; **5.8 FR-150 and
FR-151 are the single definition** of the cleartext policy and of the private-address classification, and
this section does not restate the accepted-range list.

**Consequences (testable):**
- HTTPS is always permitted. Plaintext HTTP is permitted **only** when the host is a literal private
  address **and** the user has explicitly opted in to insecure LAN HTTP. It is a conjunction, every time.
- The rule is **identical in every build configuration**. No debug, TestFlight or release configuration
  widens it, because a Builder can install a debug configuration through their own TestFlight (FR-150,
  and FR-163 conforms).
- Classification is by **literal address only** and never performs a DNS lookup — resolving a name would
  invite DNS rebinding and would block the caller. The accepted ranges, the strict four-octet base-10
  IPv4 parsing, the rejection of octal, hex and bare-decimal encodings, and the single deliberate
  `.local` name exception are all FR-150's; this section carries no second copy of that list.
- The rule is enforced at **two** independent points: at save/validate time and again on every outbound
  request, so a base URL that became inconsistent with the policy can never actually issue a plaintext
  request to a public host (FR-150).
- **The app's own classifier is the enforcement mechanism; App Transport Security is not.** Under
  fork-and-build the Builder controls their own Info.plist and can weaken it, so no security property in
  this PRD depends on ATS.
- **Architecture to verify, not a settled requirement:** which Info.plist ATS configuration actually
  achieves this baseline on a device is an open architecture decision requiring empirical verification.
  ATS exceptions are per-domain and accept neither IP addresses nor CIDR ranges, and whether
  `NSAllowsLocalNetworking` covers raw private-IP literals — rather than only single-label and `.local`
  names — is unverified. No section may state a plist posture as fact until that verification lands
  (§15 Open Questions). Whatever architecture records as the verified baseline is what the Entitlements
  and Plist Guard then guards against being broadened: any `NSAllowsArbitraryLoads`, any addition to
  `NSExceptionDomains`, or any other ATS exception beyond that baseline fails the `Static Analysis Gate`
  Required Check (5.11 FR-204).
- Recorded in the Parity Ledger (PL-50): Android gets platform help with this property that iOS cannot
  provide, so a policy bug in app code is the only thing between a user and cleartext to a public host.
- TLS uses the platform default trust evaluation with no custom trust callback and no certificate or
  key pinning; a self-hoster's certificate story is theirs. [ASSUMPTION: TLS 1.2 as the negotiated
  minimum, i.e. the platform default with no downgrade. Confirm that no self-hosted Backend deployment
  the project documents requires anything older; if one does, that is a Backend fix, not an app exception.]
- The Backend URL is user-supplied, is not a secret, and is never logged with credentials attached.
- Local Network privacy denial is a distinct, named failure mode with a Settings route, never surfaced
  as an unreachable Backend and never as a generic connection failure (5.8 FR-151, 5.9 FR-162).

#### NFR-21: No therapeutic write surface exists anywhere (SI-1)

The absence of therapeutic writes is a structural property of the whole system, not a feature decision
any section can relax.

**Consequences (testable):**
- No bolus, basal, pump-setting or device-command operation exists in any Capability protocol, in any
  Driver, in the shared safety module, in the Watch app, in a widget extension, behind a build setting or
  behind a runtime flag.
- The Driver protocol public-interface snapshot gate (5.11 FR-205) fails any pull request that adds a
  member whose shape could carry one.
- Every wrist and widget surface states in its own onboarding copy that no interaction on it can deliver
  insulin, change a Pump setting or modify stored data (5.7 FR-115), and that sentence is testable text,
  not marketing.
- Every entry point the app handles performs navigation only; no widget or complication link,
  notification action, Shortcut, widget tap or wrist interaction can reach a write of any kind,
  including to the local store. NFR-22 fixes what an entry point may be.

#### NFR-22: Minimal, declared attack surface

The app asks the platform for the least it can and declares exactly what it uses.

**Consequences (testable):**
- Declared capabilities are exactly: App Groups, Keychain Sharing, Background Modes for Bluetooth
  central, Time Sensitive Notifications, and Push Notifications only if and when the reserved
  device-token path is wired (5.10 FR-182). Nothing else.
- Critical Alerts is structurally unobtainable under fork-and-build (decision 4). Nothing in the build may
  hard-depend on it; the provisioning workflow reports its absence and continues (5.10).
- **The app registers no custom URL scheme that accepts data from another app**, registers no universal
  link, and exposes no share extension or document-provider surface that accepts arbitrary input. That
  prohibition is what "deep links are internal only" means.
- Widget, complication and notification entry points are **not** a third-party input surface and are not
  covered by that prohibition: each travels the system's own widget/complication URL mechanism, whose
  payload only the app's own timeline entries and its own notification content can populate, and no other
  app can reach any of them. FR-63, FR-105 and FR-114 conform on that basis; a prefill carried by one of
  those entry points is app-authored, bounded, and still navigation-only (NFR-21).
- No build-time code execution exists outside the pinned, reviewed pipeline: a newly introduced
  `PBXShellScriptBuildPhase`, `.plugin(` or `binaryTarget(`, absent from the committed CODEOWNERS-owned
  allowlist, fails the build-time-code-execution half of the **Entitlements and Plist Guard**, which runs
  inside the `Static Analysis Gate` Required Check. That is the host FR-197's assignment table fixes, and
  §10.1 states the same placement in words — it is not hosted in `Workflow Lint` (5.11 FR-197, FR-204).
- Every compiled-in Driver shares one sandbox, one entitlement set, one container and one Keychain —
  iOS has no per-module runtime capability restriction. Containment is compile-time only: build-graph
  dependency limits, import lint and CODEOWNERS (5.2). This is stronger than Android for the code it
  covers and covers nothing at runtime; recorded in the Parity Ledger as PL-41.
- Third-party dependency count is minimized as an explicit posture, and every dependency is
  version-pinned to a resolved graph that CI scans (5.11 FR-201) and licenses (5.12 FR-229).

---

### 6.6 Privacy

#### NFR-23: No project telemetry, and network silence with one named exception

No build any Builder produces phones home to the project, under any configuration, and no host carrying
or receiving health data is contacted other than the Backend the user configured.

**Consequences (testable):**
- The no-project-telemetry rule — the DSN empty in every configuration, the build hard-failing on a
  non-empty DSN in CI, and the `Static Analysis Gate` Required Check failing any pull request that
  commits a telemetry credential — has exactly one definition, in 5.10 FR-189. This NFR states the
  system-wide obligation and restates none of the mechanism.
- There is no telemetry opt-out setting, because there is nothing to opt out of.
- No third-party SDK endpoint, no CDN, no font host and no analytics collector is ever contacted, in any
  mode. A test asserts the outbound host set.
- **In Backend-optional mode the app makes no network request to any host carrying or receiving health
  data.** The single permitted exception is the upstream-release check (5.10 FR-188): it is
  user-toggleable, **off by default**, carries and receives no health data, and consumes the response
  only as a release tag string. With that toggle off, a Backend-optional build makes no network request
  at all.
- The outbound-host-set test therefore asserts exactly this set: the user's configured Backend, plus the
  GitHub Releases API host and only while the upstream-release toggle is on. No other host is reachable
  from any code path.
- If a Builder chooses to enable their own crash reporter, it reports to **them**, under the lockdown
  FR-236 documents, and never to the project.

#### NFR-24: Log scrubbing is a system-wide invariant (SI-9)

No health value, raw device payload or credential appears in any log at or above debug level, on any
path, in any target.

**Consequences (testable):**
- Prohibited in logs at or above debug: any Glucose Reading value, IOB value, Bolus or Basal amount,
  carb value, alert threshold value, raw pump frame bytes, pump serial number, Bluetooth device
  identifier, bearer token, refresh token, database key, pairing secret, email address, and Backend URL
  with credentials attached.
- The scrubbing rules themselves, and the iOS unified-logging trap that publishes an interpolated numeric
  value to the system log unless it is explicitly marked private, have exactly one definition. See
  5.8 FR-158; this section restates neither and defines no second set.
- The rules are applied at emission **and** again at export, in every target and on every path, including
  the Watch app and every widget extension (5.8 FR-158).
- All glucose formatting uses a dot decimal separator regardless of device locale, so mmol/L output still
  matches the scrubber — this is why NFR-31's locale-independence rule is a privacy requirement and not
  only a consistency one.
- A diagnostic log of a Backend error body is truncated and carries no health value; if the scrubber
  cannot guarantee that, the log is dropped rather than weakened (5.5).

#### NFR-25: Diagnostic export is scrubbed, bounded and user-initiated

The only data that ever leaves the device for diagnostic purposes is a scrubbed export the user
explicitly produced.

**Consequences (testable):**
- Export is user-initiated, shows the user what it contains before it leaves, and applies the NFR-24
  scrubbing at export time in addition to emission time (5.8 FR-158).
- The export contains no database contents, no Keychain contents, no raw pump frames and no image bytes.
- Every documentation page that asks a user to share output reproduces the redaction guidance: emails,
  bearer and API tokens, auth headers, account IDs, Pump serials and Bluetooth device identifiers are
  replaced with `[REDACTED]` or sent directly to a maintainer (5.12).
- The repository never contains an unredacted user bug report or log (5.12 FR-221).

---

### 6.7 Accessibility

Accessibility is a system-wide floor, not a per-feature nicety. Ownership is fixed and this section
respects it: **NFR-30 owns the accessibility parity rule; 5.9 FR-177 and FR-178 own the identifier
registry, the per-surface porting requirement and the specific per-card phrasing; 5.11 owns the gates
that enforce them; NFR-26 through NFR-29 own only the floor every surface those FRs do not enumerate must
still meet.** Nothing here restates a registry, a phrasing or a check defined there, and nothing there
restates a count defined here.

#### NFR-26: VoiceOver

Every surface is fully operable and fully comprehensible with VoiceOver, and a number can never be heard
without its qualifier.

**Consequences (testable):**
- Every card exposes ONE combined description merging its descendants, so a screen reader cannot separate
  a value from its freshness, its confidence or its safety qualifier. This binds every card, including
  ones added after v1. The ported count of these descriptions is **NFR-30's** and the per-card phrasing is
  **5.9 FR-178's**; neither is restated here.
- Every interactive control has an accessibility label distinct from its accessibility identifier, plus a
  trait that states what it is, plus a value or hint where the label alone is ambiguous.
- Focus order follows visual order on every screen. On Home the glucose hero is the first element after
  the navigation chrome.
- Spoken units are always the full phrase — "milligrams per deciliter", "millimoles per liter" — never
  the abbreviation.
- A rejected Glucose Reading is never announced as a value; the surface announces its absence (SI-2).
- A Coverage Claim resolving to not-watching posts an accessibility announcement carrying the
  Not-Watching Reason; no other state change announces, so the announcement channel is not diluted.
- Decorative elements are hidden from the accessibility tree; no decorative image announces a filename.

#### NFR-27: Dynamic Type

Every surface remains legible and complete at every Dynamic Type size including the accessibility sizes.

**Consequences (testable):**
- No text is clipped, truncated without an accessible full value, or overlapped at the largest
  accessibility size on any screen at the smallest supported device width.
- Where a layout cannot fit, priority is fixed and testable: the glucose value and its trend glyph take
  priority over secondary metrics; a safety qualifier is never the element that drops.
- Fixed-size numerals (the hero, glanceable values) either scale with Dynamic Type or are explicitly
  bounded with a stated rationale; a hard-coded point size with no bound is a defect.
- Sheets and modals scroll their bodies so accessibility text sizes cannot push a confirm or cancel
  button off screen (5.5).
- Snapshot tests at the default size and at the largest accessibility size run in the Simulator for every
  screen in the identifier registry.

#### NFR-28: Non-colour encoding, and legibility in flattened rendering modes

No information is carried by colour alone, anywhere, on any surface.

**Consequences (testable):**
- Severity colour encodes SEVERITY, not direction, project-wide (5.9 FR-178 states the rule and its
  encodings): no requirement anywhere, on any surface, may depend on a user telling low from high by hue.
- Every state that colour carries is also carried by text, glyph, position or length. FR-178 enumerates
  the encodings for the surfaces it covers; the floor is that a surface it does not enumerate may not
  invent a colour-only state.
- The Coverage Claim's watching / not-watching state is never conveyed by colour alone; the
  Not-Watching Reason is always present as text (SI-6).
- **Complications and widgets must remain correct in monochrome, tinted and accented rendering modes,
  which flatten the colour vocabulary entirely, and in the Always-On dimmed state.** FR-178 states the
  tinted and accented case for the surfaces it enumerates; this floor extends it to every widget and
  complication family and to the dimmed state. A complication whose meaning depends on hue is a defect.
  This is why the wrist sparkline ships without the basal, bolus, IOB and activity-mode overlays, whose
  encoding is entirely colour (5.7 FR-117).
- Snapshot tests render every complication and widget family in every rendering mode.

#### NFR-29: Motion, contrast, and input

The app honours the system accessibility settings that change how a surface must be built.

**Consequences (testable):**
- Reduce Motion is honoured; no information is conveyed only by animation, and no alert or state change
  depends on a transition being seen.
- Increase Contrast and Bold Text are honoured without layout breakage.
- Every interactive target meets Apple's 44×44 pt minimum, including chart period chips, badge taps and
  wrist controls.
- Every action reachable by gesture is also reachable without one — the chart's pinch, drag and
  double-tap-to-reset each have a non-gestural equivalent, so the chart is operable under Switch Control
  and VoiceOver.
- Haptic and sound feedback is always accompanied by a visual state, and visual state is always
  accompanied by text.

#### NFR-30: The accessibility parity rule, and the identifier contract as the UI-test substrate

Accessibility identifiers and combined VoiceOver descriptions are a shipping contract, not test
scaffolding. **This NFR is the single site of the system-wide parity rule.**

**Consequences (testable):**
- **The parity target is a generated registry, not a pinned number.** The acceptance criterion is: every
  Compose `testTag` in the Android phone and Wear main source sets has a byte-identical accessibility
  identifier on the corresponding iOS or watchOS surface, and every `contentDescription` has a
  corresponding combined VoiceOver description. The registry is generated from the Android source,
  committed, and diffed by CI — the diff is the gate. **This NFR is the single site of the parity rule;**
  5.9 FR-177 and FR-178 state the per-surface requirements and cite this rule rather than restating it.
  The one Android duplicate (`pairing_fault`) resolves to two distinct strings during the port (FR-177).
- **[NOTE FOR PM] Do not pin a count.** An earlier draft fixed the target at "253 identifiers and 113
  descriptions." Counted directly against the Android source on 2026-08-01, `grep -rn testTag` over
  `app/src/main` + `wear-device/src/main` returns **249** and repo-wide returns **252**;
  `contentDescription` returns **113**. The 253 figure was a grep-token artifact, not a count of distinct
  identifiers, and a line can carry more than one call site. Pinning any of these numbers creates an
  acceptance criterion that was never verifiable and that drifts every time the Android client changes.
  Scale is roughly 250 identifiers and 113 descriptions as of the 2026-08-01 snapshot — stated for
  context only. **The gate is the registry diff.**
- **That registry is the acceptance substrate for every Simulator-runnable gate in this project.**
  With no iPhone, no Apple Watch and no Core Bluetooth in the Simulator (decision 10), XCUITest driven off
  the identifier set plus VoiceOver assertions over the combined descriptions is most of what the project
  can verify at all. A shortfall is a shortfall in the project's only self-serve verification, not a
  cosmetic gap, and it is reported as a registry diff naming the missing surfaces — which is more
  actionable than a count.
- A count is met only by byte-identical ports. The registry itself, the byte-identical-string rule, the
  identifiers-on-states rule and the check's failure conditions are 5.9 FR-177's; 5.11 FR-208 and FR-209
  define the jobs that run the check. This section defines no second registry and no second copy of that
  check.
- The floor this section adds, binding on every surface added after v1: a new user-visible element or
  state ships with a registry identifier in the same pull request that introduces it. An unregistered
  new surface is untestable in the Simulator, which is the project's only self-serve verification.
- **Identifiers are never derived from a display string and are never localized.** This is what keeps
  NFR-31's future localization a mechanical change rather than a test rewrite.
- An identifier is never used as an accessibility label and never announced by VoiceOver; the label
  (NFR-26) and the identifier are always distinct strings.

---

### 6.8 Localization

#### NFR-31: Deliberate English-only v1, with the discipline that makes i18n later mechanical

The app ships English only in v1. This is a stated position, not an omission, and it is not hidden inside
the parity mandate.

**The parity fact.** The Android client ships **no localization at all**: a single `values/` resource
set with no `values-xx` variants, and `strings.xml` is 9 lines carrying **6 strings** — the app name and
five foreground-service notification strings, three of which are the alert-honesty texts. Every other
piece of user-visible copy is inline in Kotlin. There is therefore no localization behaviour to port,
and "full parity" does not silently obligate iOS to internationalize.

**Consequences (testable):**
- The app declares English as its only localization. No additional language is shipped, no translation
  pipeline exists, no contributor is asked to supply translations, and no CI gate checks translation
  coverage.
- The user-facing statement is that the app is English-only, stated once in the docs, not discovered.
- **The discipline is mandatory now even though the translation is not.** All user-visible copy lives in
  a localizable string resource per target, never inline in view code; a new inline user-visible string
  literal fails a lint gate. This is a small improvement over Android, where inline copy makes future
  translation a rewrite rather than a data change.
- Layout never assumes English string length: every screen must survive a pseudo-localized string
  expansion in a snapshot test, even though no expanded locale ships.
- Layout uses leading/trailing rather than left/right throughout, so a future right-to-left locale needs
  no relayout. RTL is not tested in v1 and is not claimed.
- **Formatting is locale-independent by decision, not by accident.** Every number the app displays uses a
  dot decimal separator and half-up rounding regardless of device locale (5.3 FR-60). This is
  simultaneously a cross-surface consistency requirement (the Watch app and the Backend must agree) and a
  privacy requirement (the log scrubber's mmol/L pattern only matches dot-decimal output — NFR-24).
  A future localization may not change it without changing the scrubber and the cross-surface fixture
  together.
- **Safety copy is content, not chrome.** The spoken unit names, the medical disclaimer, the
  never-dose qualifier, the Not-Watching Reasons and the alert-delivery conditions are safety text. Any
  future translation of them is a safety change requiring the same review as a threshold change, and this
  is written down now so nobody treats it as a string swap later.
- Parity Ledger entry: **matched** — neither client is localized. Not a loss.

---

### 6.9 Observability and diagnosability under fork-and-build

#### NFR-32: The project can never see a crash, and the design accepts it

Under fork-and-build the project ships source, publishes no binary and holds no signing key (decision 3).
It therefore never possesses the binary a user is running, receives no crash report, no stack trace and
no device log, and cannot reproduce against a known build. Every diagnosability requirement below exists
because of that.

**Consequences (testable):**
- The project does not build an observability strategy that assumes it will learn about a failure. Every
  failure the app can detect must be legible **to the user, on the device, at the time**.
- Android's model is different in kind: the project builds and publishes the APK a user side-loads and
  can reproduce against it. This is a forced loss owed a Parity Ledger row of its own, with no substitute
  claimed; PL-62 records the gate-coverage half of it, not the crash-report half.
- No requirement anywhere in this PRD may be justified by "we'll see it in crash reports".

#### NFR-33: The on-device diagnostic surface is the only diagnostic channel

What the project cannot observe, the user must be able to hand over.

**Consequences (testable):**
- A bounded in-app log ring buffer exists in every build configuration, not only debug, subject to NFR-24
  scrubbing, exportable by the user (5.8 FR-158).
- **The buffer has honest gaps.** iOS suspends and terminates the app, so a log has no entries for every
  interval the app was not running. The export must state this: an empty interval means "we were not
  running or nothing happened", and the export cannot distinguish them. A reader who assumes silence
  means health will misdiagnose. Owed a Parity Ledger row — Android's foreground service produced a
  continuous process-level record that iOS cannot; PA-15 records the export, not this loss.
- Every build carries provenance — commit, build number, channel, expiry — visible in Settings, so a
  report names a specific commit rather than "the latest" (5.10 FR-187).
- The app surfaces the state a support conversation actually needs without a log: connection state,
  Freshness Tier of each source, Coverage Claim with its Not-Watching Reason, notification authorization,
  Background App Refresh state, Low Power Mode, Local Network grant, Bluetooth authorization, Watch
  install and build match, Backend reachability, and pending queue depth.
- The Trace-Replay Driver is the reproduction substrate: a validator can capture recorded real-Pump
  frames and a maintainer can replay them with no hardware, which is the only way a Pump-specific defect
  becomes reproducible for a developer who has no such Pump.

#### NFR-34: Every device-only NFR has a named owner before v1 ships

An NFR nobody can measure is not a requirement; it is a wish.

**Consequences (testable):**
- Every NFR in this section is tagged in the Validation Tier model (§9) as Simulator-provable,
  unit-test-provable, or device-only.
- Every device-only NFR names who validates it — DanielDanielson from their own fork under their own
  Apple Developer account (decision 9), or a named community validator — and on what hardware.
- A device-only NFR with no named owner at the v1 scope freeze is escalated to §12 MVP Scope as a scope
  decision, not shipped as an unverified claim.
- The Device Verification Matrix (§8) and the Parity Ledger (§7) each carry the resulting honest status;
  "target, not measured" is a permitted and expected value in v1.

---

**Notes:**

- **Settled here, and closed everywhere else — do not reopen either.** The deployment floor is NFR-1's
  **iOS 17.0 / watchOS 10.0**; the iOS 18 / watchOS 11 figure is the pinned Simulator runtime (NFR-3) and
  is never a floor. The Keychain accessibility class is NFR-18's
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, agreed by FR-14, FR-18, FR-29, FR-75, FR-136,
  FR-161, FR-169, FR-181 and FR-204. Both were struck from §15 and the floor's assumption was retired in
  §16; a future draft that reintroduces either as open is regressing, not asking.

- **The one accessibility question this section states but does not own is recorded as OQ-45:** which
  Info.plist App Transport Security configuration actually achieves NFR-20 / FR-150's baseline on a
  device, given that ATS exceptions accept no IP addresses or CIDR ranges and that
  `NSAllowsLocalNetworking`'s coverage of raw private-IP literals is unverified. Architecture owns the
  answer; until it lands, FR-204's guard has only the committed Info.plist as its baseline, and PL-50's
  substitute is the in-app policy plus that unverified plist question — not a settled blanket-cleartext
  posture.

- [NOTE FOR PM] **NFR-10's downstream effect is only half-landed.** §12.2 D-8 correctly defers *any
  published battery-consumption figure* until a measurement exists, so the metric is not claimed. What is
  still absent is the other half: §13 carries no *measurement task with a named owner* for the NFR-10
  protocol, so nothing in the document says who runs it or by when. Either §13 gains that task or the
  open question below is the project's answer.

- **Ownership boundary with 5.9 and 5.11 — settled.** NFR-30 states the accessibility parity rule —
  the identifier count and the combined-VoiceOver-description count — and is the only place either number
  appears; 5.9 FR-177 and FR-178 own the registry, the per-surface porting requirement and the per-card
  phrasing, and cite NFR-30 for the counts; 5.11 owns the jobs. NFR-26 to NFR-29 own only the floor for
  surfaces those FRs do not enumerate. No count, registry or check is defined twice, and none is now
  defined nowhere.

- **Parity Ledger rows this section is owed — all five are written.** NFR-15's deliberate
  non-reproduction of `fallbackToDestructiveMigration()` is **PD-38**; NFR-7's 30-day chart oldest-end
  truncation at 2,000 rows as inherited Android behaviour is **PD-39**; NFR-31's localization **matched**
  row is **PD-40**; NFR-32's loss of any crash report, stack trace or device log is **PL-71**; NFR-33's
  loss of a continuous process-level record is **PL-72**. NFR-14's degrade-instead-of-throw remains
  covered by PD-25 and NFR-16's `raw_history_logs` cleanup by PD-20. One residual, flagged in §7 itself:
  PL-72's honest-gaps statement is mandated only by NFR-33, and FR-158 — which owns the export — does not
  yet carry it, so the disclosure lives only in §6.

- **Open question:** who runs the first NFR-10 battery measurement, on what device, and by when? With
  decision 10 as written, nobody on the project bench can. If the answer is "DanielDanielson, once, on
  one device", NFR-10's two-people-two-models publication rule cannot be met in v1 and the honest
  position is that no figure is published at all in v1 — which is acceptable, but should be decided
  rather than defaulted into.

- **Open question:** is a CI job on the floor Simulator runtime (NFR-3) affordable in wall-clock and
  minutes, or does CI test only the newest pinned runtime with the floor checked by availability lint
  alone? The second is cheaper and materially weaker.

- **Open question:** does the project accept a Builder-enabled crash reporter as a legitimate
  diagnosability path (NFR-32, FR-236), or is the scrubbed export the only channel the project will ever
  discuss in a support conversation? The two imply different documentation and different support
  expectations.

- **Open question:** NFR-2 opts the build out of iPad and Mac availability. Confirm this is right —
  Android ships no tablet variant, so it is parity, but a Builder may reasonably expect their own
  TestFlight build to install on their own iPad, and the refusal will read as a bug unless it is
  documented.
