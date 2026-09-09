---
title: GlycemicGPT for iOS and Apple Watch
status: final
created: 2026-08-01
updated: 2026-08-10
---

# PRD: GlycemicGPT for iOS and Apple Watch

*Repository: `lumose-health/ios-unofficial`. Working title — confirm.*

## 0. Document Purpose

This PRD specifies the iPhone and Apple Watch port of GlycemicGPT's mobile client, currently shipping for Android and Wear OS in [`lumose-health/android-unofficial`](https://github.com/lumose-health/android-unofficial). It is written for the maintainers who will build it, the contributors who will extend it, and the downstream UX, architecture, and epic-planning work that follows.

The mandate is **full parity**: the iOS app must do everything the Android app does today — every supported pump, every feature, the same safety posture, the same engineering rigor. This document exists because parity is not achievable by transcription. iOS forbids things Android permits, and permits nothing that substitutes cleanly for several of them. Where a capability cannot cross the platform boundary, this PRD names the loss explicitly rather than letting it disappear into an implementation detail.

It is structured as follows. §1–§3 establish what this is and the vocabulary the rest of the document uses. **§4 is the Safety Invariant Register** — the properties that must survive the port intact, stated before any feature, because every feature is subordinate to them. §5 groups behavior into features with globally numbered functional requirements (`FR-N`). §6 covers cross-cutting non-functional requirements. **§7 is the Parity Ledger** — every divergence from the Android product, sorted into forced losses, deliberate divergences, and additive substitutes. §8–§10 carry the three artifacts this product needs that a generic PRD would not produce: a per-device verification matrix, a validation tier model, and a security-gate substitution table. §11–§16 close with non-goals, scope, metrics, risks, and open items.

**Vocabulary is binding.** §3 defines every domain noun. Functional requirements, user journeys, and success metrics use those terms verbatim. Introducing a synonym anywhere in this document is a defect.

**Source of record.** This PRD is grounded in a subsystem-by-subsystem analysis of the Android repository — 14 subsystems, 543 catalogued capabilities, 205 safety-critical behaviors — with a per-capability iOS portability verdict. Those working artifacts live in `research/` alongside this document and are the evidence behind every claim of *"Android does X"* and every *"Apple forbids Y."*

**Not in this document.** Technology selection, module topology, target layout, and mechanism choices belong to architecture and are captured in `addendum.md`. This PRD states capabilities and constraints, not implementations.

### 0.1 Settled decisions

Ten product decisions were taken during discovery and are treated as settled throughout. Requirements cite them as *"decision N"*. They are recorded here because several are load-bearing — a downstream reader who reverses one silently invalidates whole sections.

| # | Decision | Why it is settled | Where it bites |
|---|---|---|---|
| **1** | Pump **Drivers** are compile-time-linked Swift modules, not runtime-loaded plugins. | iOS forbids loading code that was not signed into the build. | Community contribution becomes a pull request and a release, not a drop-in plugin (§5.2). |
| **2** | Monitoring only. Read-only. **No therapeutic write, ever** — no bolus, no basal, no pump-setting, no device command. | Architectural commitment inherited from the Android product, not a v1 cut. | SI-1. Removing the calibration Capability (§7) follows from it. |
| **3** | Distribution is **fork-and-build**: the project ships source, publishes no binary, holds no signing key. Each **Builder** signs with their own Apple Developer account into their own TestFlight. | The GPL-3.0-only licence conflicts with Apple's Developer Program License Agreement, which governs TestFlight as well as the App Store. The project conveys nothing and accepts no terms on anyone's behalf. This is the Loop / xDrip4iOS model. | §5.10 in full, NG-3, NG-4, and the reason §8 and §9 look the way they do. |
| **4** | Urgent-low alerts ship on `.timeSensitive`, upgrading to `.critical` at runtime if the entitlement is ever present. | Critical Alerts is granted per Team ID on individual Apple review; under decision 3 every user signs with their own personal team, so it is structurally unobtainable. Blocking on it blocks forever; asking every Builder to request it splits the userbase into two silent alarm behaviours. | §5.4, R-4, PL-23, PL-24. **The alarm can be silenced by the ring/silent switch and the app cannot detect it.** |
| **5** | Medtronic ships present-but-gated at **Beta**, matching Android's own label, with its transport spike split in two. | Part (a) — whether Core Bluetooth returns a `CBPeripheral` for a central that connected to our `CBPeripheralManager` — is answerable **without a pump** and comes first, because a negative answer invalidates the driver architecture. Part (b) needs hardware nobody on the team has. | §8, R-1, and the Medtronic sequencing in §12.3. |
| **6** | The fork's build-and-sign pipeline is a **supported product surface** — CODEOWNERS-gated, SHA-pinned, inside the security-response scope. | Builders load their own App Store Connect key into a run executing project workflow code. Disclaiming support would not reduce the risk, only relocate the blame. | §5.10. Key custody, account state, certificate lifecycle and the 90-day rebuild remain the Builder's. |
| **7** | APNs is **deferred for v1**: SSE while the process is alive, plus the on-device **Alert Floor**, plus opportunistic pulls. The device-token path is reserved but unwired. | Per-deployment APNs is the right eventual design but is work in the platform repository, which this PRD cannot discharge. The safety-critical alerts are local and need no push. | Backend-generated alerts do not reach a suspended or terminated app; caregiver alerting is degraded versus Android (§7, D-2). |
| **8** | Nightscout is **Backend-mediated**, not a direct client. | Verified in the Android source: the app reads Nightscout-sourced data from the **Backend** and holds no Nightscout URL or API secret. | §5.8. No Nightscout networking exists in the app. |
| **9** | Maintainer **DanielDanielson** validates by building from their own fork under their own Apple Developer account — never as a tester on a project-held TestFlight. | Adding a tester would make the project convey a binary and reopen the conflict decision 3 exists to avoid. | §9 Tier 4, R-5. |
| **10** | The lead developer works from a Mac with an Apple Developer account and a Tandem t:slim X2, but **no iPhone and no Apple Watch**, so the daily loop is the Simulator. | **Core Bluetooth does not exist in the iOS Simulator** — `CBCentralManager` reports `.unsupported`. The watchOS Simulator does pair with the iOS Simulator, so WatchConnectivity is exercisable. | The entire §9 Validation Tier model, and why the **Simulated Driver** and **Trace-Replay Driver** are shipped targets rather than test fixtures. |

## 1. Vision

People with diabetes who use an insulin pump live inside a number that changes every five minutes. GlycemicGPT exists so that number — and the insulin, meals, and trends around it — is legible, on your own terms, on hardware you already own, running against a Backend you control. It reads your Pump directly over Bluetooth, keeps the history on your device, and pairs with a self-hosted Backend for AI analysis and alerting when you want one. It never tells your pump what to do.

Today that product exists only on Android. **This is the iPhone and Apple Watch half.** Not a companion, not a viewer — the same product, on the platform most people actually carry, with the same direct pump connection, the same local-first data, and the same refusal to put anything therapeutic behind an AI suggestion.

Getting there means accepting that Apple's platform is not Android's. iOS gives no guaranteed background execution, no foreground service to hold a Bluetooth link open forever, no way for an ordinary user to obtain the entitlement that makes an alarm unsilenceable, and no custom watch faces. Android's answer to "am I being watched right now?" is a permanent, undismissable notification. iOS has no such thing, at any price. **The product response is not to pretend otherwise.** Where iOS delivers less, the app says so — on the surface where the user would otherwise assume coverage, in the words they need to act on it. An honest monitor that admits its gaps is safer than a confident one that has them anyway.

It ships the way open-source diabetes software on iOS has always shipped: as source. Each user builds the app themselves, signs it with their own Apple Developer account, and installs it through their own TestFlight. The project publishes no binary and holds no signing key — which is what keeps a GPL-3.0-only medical monitoring tool distributable on a platform whose terms would otherwise forbid it.

## 2. Target User

### 2.1 Jobs To Be Done

- **See my glucose and insulin without asking anyone's permission.** Read it off my own pump, over Bluetooth, on my own phone, with no vendor cloud in the path and no subscription.
- **Know, at a glance, whether the number I'm looking at is still true.** A stale reading presented confidently is worse than no reading.
- **Know whether anything is actually watching for a low right now** — and if not, why not, and what I can do about it.
- **Get a low alarm that reaches me,** including overnight, including on my wrist, within whatever the platform genuinely allows.
- **Keep my data on my device and on my own Backend.** Run the whole thing in Backend-optional mode if that's what I want.
- **Understand my own patterns** — time in range, variability, insulin split, what a meal did — without exporting to someone else's product.
- **Ask questions about my own data** and get an answer that is explicitly advisory and never a dose.
- *(Maintainer)* **Add support for my pump** without waiting for a vendor, and have the project's tests and gates tell me whether I got it right.
- *(Maintainer)* **Ship this to iPhone users** without the project taking custody of anyone's signing credentials or accepting terms on their behalf.

### 2.2 Non-Users (v1)

- **Anyone seeking a closed-loop or dosing system.** This app has no therapeutic write surface and never will. Loop, Trio, and iAPS serve that need; this does not, and the boundary is architectural, not a roadmap item.
- **Anyone who wants an App Store download.** There is no listing and there will not be one. Every user builds and signs their own copy.
- **Anyone who needs a guaranteed, unsilenceable alarm as their primary low-glucose safety net.** iOS cannot provide this to a self-signed build. See FR-66 and §7.
- **Clinicians provisioning devices for patients,** and anyone needing FDA-cleared software. This is unapproved, experimental, community-maintained software.
- **Users without a supported pump.** Backend-mediated data sources exist, but the product is built around a direct pump link.

### 2.3 Key User Journeys

> `[ASSUMPTION]` The journeys below are authored from the Android product's behavior and the constraints of the target platform, not from user interviews. They are the highest-value candidates for review — each one encodes screen order, entry state, and what tells the user value landed. Correct or replace any that don't match your intent.

- **UJ-1. Sam checks whether the number on their wrist can be trusted.**
  Sam, 34, type 1 for two decades, wearing a Tandem t:slim X2 and an Apple Watch. Mid-meeting, they turn their wrist. The complication reads **112** with a flat trend arrow, plain — no strikethrough, no dimming — which is how they know the reading is under five minutes old and the phone in their pocket is currently watching. They put their arm down without opening anything. **Climax:** the entire interaction is one glance and costs nothing. **Resolution:** nothing to do. **Edge case:** had the value been struck through, that means the reading has aged past the trust boundary — the number shown is the last one received, not the current one, and Sam knows to open the phone rather than act on it.

- **UJ-2. Priya is woken by a low at 3 a.m. — and the app is honest about how close it came to missing it.**
  Priya, 41, sleeps with her iPhone charging across the room and Sleep Focus on. Her glucose crosses 68 mg/dL. The phone alarms and her watch buzzes; the notification breaks through Sleep Focus and reads **Low — 68 mg/dL, 2 min ago**. She acknowledges from the watch, gets up, treats. **Climax:** the alert arrived and the acknowledgement stuck without her touching the phone. **Resolution:** the re-alarm is cancelled; the alert appears in Alerts history. **Edge case — and this one is a product requirement, not a footnote:** had Priya's phone been on silent, this alarm would have been inaudible, and the app has no way to detect that. Onboarding told her so and the docs say it plainly. See FR-66, FR-71, and §7.

- **UJ-3. Marcus builds his own copy of the app, having never opened App Store Connect.**
  Marcus, 52, comfortable with a phone and not much else, wants this on his iPhone. He follows one documented page: fork the repository, create an App Store Connect API key, paste the documented secret set into his fork, run one workflow. Twenty minutes later TestFlight on his phone offers a build. **Climax:** the app opens on his own device, signed by him, with no binary having come from the project. **Resolution:** he pairs his pump. In Settings he can see the commit his build came from and the date it expires. **Edge case:** ninety days later that build stops launching — a total loss of monitoring, silently, unless he rebuilds. The app warns him ahead of time and a scheduled workflow can rebuild for him. See FR-179 through FR-196, and FR-186 in particular.

- **UJ-4. Dana pairs a t:slim X2 for the first time and hits a wall the app explains.**
  Dana opens Settings → Pump, taps Pair, and sees a live list of nearby pumps by name and model. They select theirs and enter the pairing code from the pump's Bluetooth settings screen. iOS raises its own Bluetooth pairing prompt; the app has already told them it's coming and why. Handshake completes; the status row goes blue. **Climax:** the dashboard fills with real data — glucose, trend, insulin on board, basal. **Resolution:** from here the app reconnects on its own, indefinitely, whenever the pump is in range. **Edge case:** if the pump has forgotten this phone, the app does not present that as an ordinary disconnect — it says the pairing is broken and walks Dana through forgetting the device in iOS Settings first, because iOS gives the app no way to clear that bond itself.

- **UJ-5. Ren photographs lunch and gets a range, never a dose.**
  Ren, 29, running a Backend with meal intelligence enabled, taps the camera button on Home and photographs a plate. The app shows *"Estimating carbs…"*, then a range — **45–60 g**, medium confidence, with the words *"Rough estimate — an AI guess. Never dose from this."* on the same screen as the number. Ren corrects the range to 50–65 and saves it as a common food. **Climax:** the estimate lands with its uncertainty attached, not as a bare number. **Resolution:** the meal appears on Home with its range and timestamp. **Edge case:** with the Backend unreachable, meal logging is unavailable rather than degraded — and says so, because a stale carb estimate is worse than none.

- **UJ-6. Alex contributes a driver for a pump the project doesn't support.**
  Alex owns a pump nobody on the project has. They add one Swift package implementing the Driver protocols, register it in the Driver Catalog, and open a pull request. CI builds it, runs its protocol tests against recorded frames, and fails if the Catalog registration is missing. **Climax:** the review conversation is about protocol correctness, not build plumbing. **Resolution:** the Driver ships in the next release, listed in the device matrix at **Protocol-Implemented** until someone with hardware raises it to **Verified**. **Edge case:** unlike Android, Alex cannot install this as a runtime plugin to try it — iOS forbids loading code that was not signed into the build. The contribution path is a pull request and a rebuild, and the docs say so up front.

- **UJ-7. Jordan works out why yesterday went sideways.**
  Jordan, 26, two years post-diagnosis, had a bad afternoon and wants to know what happened. They open the app, scroll past the hero to the insulin summary, and switch the period to yesterday: total daily dose, the basal/bolus split, and the food-versus-correction breakdown. Below it, Recent Boluses lists the five most recent with time, units, a type badge, and — cross-referenced within five minutes — what their glucose and insulin on board were at the moment of each. The 4 p.m. correction sat on top of insulin that was still working. **Climax:** the picture assembles from data already on the device, with no export and no upload. **Resolution:** Jordan has something concrete to raise with their care team. **Edge case:** a bolus whose requested meal and correction portions don't sum to what was delivered is never rendered as though they do — the app shows what the **Pump** actually delivered and does not present a layout that reads as an equation.

- **UJ-8. Sam asks a question about their own data at 11 p.m.**
  Sam, from UJ-1, running a **Backend** with an AI provider configured. Something about the last week looks off and their clinic is closed. They open the AI Chat tab — present only because a **Backend** is configured — and type a question. Four starter suggestions were on screen before they typed; the answer comes back as sanitized markdown with no images. **Climax:** they get a useful read on their own trend without waiting three weeks for an appointment. **Resolution:** the transcript is in memory only and is gone on relaunch, which the app does not pretend otherwise about. **Edge case:** if they background the app mid-request, the app says the request was interrupted rather than silently dropping it — and no answer, at any point, is a dose.

## 3. Glossary

Downstream workflows and readers must use these terms exactly. FRs, journeys, and metrics use them verbatim.

**Platform and product**

- **GlycemicGPT** — the overall open-source diabetes platform: backend, web dashboard, AI sidecar, and mobile clients. Lives at `lumose-health/GlycemicGPT`.
- **The app** — the iPhone application specified by this PRD. Where the Apple Watch application is meant specifically, this document says **the Watch app**.
- **Backend** — a self-hosted GlycemicGPT server instance. Always the user's own; the project operates none.
- **Backend-optional mode** — the app running with no Backend configured: direct pump monitoring, local storage, and on-device alerting only. A first-class supported mode, not a degraded state.
- **Builder** — a user who forks the repository, supplies their own Apple credentials, and produces their own signed build. Under fork-and-build every user is a Builder.
- **Fork-and-build** — the distribution model: the project publishes source only; each Builder compiles, signs with their own Apple Developer account, and installs through their own TestFlight.

**Devices and drivers**

- **Pump** — an insulin pump the app reads from. Never written to.
- **Driver** — a compile-time-linked Swift module implementing one device's protocol. Replaces Android's runtime-loaded plugin. Drivers are read-only by construction.
- **Driver Catalog** — the explicit, compile-time registry of every Driver in a build. A Driver not in the Catalog fails CI.
- **Capability** — a protocol a Driver conforms to, declaring what it provides. The set is exactly **six** and is closed: glucose source, insulin source, pump status, BGM source, data sync, bolus-category provider. Some are single-instance, some multi-instance. Android's seventh Capability, calibration target, is deliberately **not** carried to iOS — it was the only member requiring a write to a device, and removing it lets SI-1 stand without a carve-out. See §7 and FR-30.
- **Simulated Driver** — a shipped Driver producing realistic synthetic data with no Bluetooth. The basis of all Simulator-tier validation.
- **Trace-Replay Driver** — a shipped Driver replaying recorded real-pump frames, so protocol parsing is testable without hardware.
- **Verification Status** — a Driver's evidence level against physical hardware: **Verified**, **Protocol-Implemented** (unverified on hardware), or **Beta** (unproven transport). Defined in §8.

**Glucose and insulin data**

- **Glucose Reading** — one CGM value with its own sensor timestamp. Stored in mg/dL.
- **Glucose Validity Bound** — **20–500 mg/dL**. Values outside it are **rejected, never clamped**. One definition, project-wide.
- **Conversion Factor** — **18.0156**, the sole mg/dL ↔ mmol/L constant. Display-only; mmol/L never reaches storage, transport, comparison, or alerting.
- **IOB** — insulin on board, as reported by the Pump. Never computed by the app.
- **Bolus** / **Basal** — delivered insulin events read from the Pump. Only completed deliveries count.
- **Safety Limits** — Backend-supplied bounds that may only ever *narrow* the Glucose Validity Bound, never widen it.
- **Alert Threshold** — one of four user or Backend configured values that decide **when the app alarms**: urgent low, low, high, urgent high. Ordering is enforced: `20 ≤ urgent low ≤ low < high ≤ urgent high ≤ 500`. Consumed by the Alert Floor and by nothing that renders a number.
- **Target Range** — a **separate** four-value set that decides **how glucose is displayed and analysed**: hero and wrist colour banding, chart target band and grid lines, and Time-in-Range bucketing. Same ordering rule, same bounds, same units, **different values and a different store.**

  > These two are distinct in the Android client — `GlucoseRangeStore` feeds `GlucoseHero` and the dashboard, `AlertThresholdStore` feeds `AlertFloor` — and they must stay distinct here. Collapsing them makes Time in Range compute off alarm thresholds, so iOS would report a different TIR percentage than Android for any user whose two sets differ. TIR is a number people take to their care team. Never substitute one for the other; where a requirement means "the alarm fires at," it says **Alert Threshold**, and where it means "the chart is green between," it says **Target Range**.

**Freshness, alerting, and honesty**

- **Freshness Tier** — the age classification of a Glucose Reading against its own sensor timestamp: **Fresh**, **Stale**, or **Too Stale**. Half-open boundaries.
- **Alert Floor** — on-device alerting computed locally from pump data, functioning with no Backend. The app's irreducible safety net.
- **Coverage Claim** — the app's statement about whether anything is currently watching for a low. Carries an explicit expiry, decays on its own without new data, and degrades to *not watching* with a specific reason rather than going quiet.
- **Not-Watching Reason** — the specific, user-actionable cause behind a negative Coverage Claim.

**Engineering artifacts**

- **Contract Pin** — the byte-for-byte vendored copy of the Backend's OpenAPI document, plus its **CONTRACT_VERSION**, that the app's request and response surface is tested against.
- **Safety Constant** — one of three values duplicated across repositories and guarded against drift: the Conversion Factor, the Glucose Validity Bound, and the Tandem epoch offset (`1199145600`).
- **Parity Ledger** — §7. The complete, enumerated record of every divergence from the Android product.
- **Validation Tier** — one of four evidence levels a behavior can be validated at, from Simulator to physical hardware. Defined in §9.
- **Required Check** — a named CI status check that must pass before merge to `develop`.

## 4. Safety Invariant Register

These properties must survive the port intact. Every requirement in §5 is subordinate to them. Each carries its enforcement mechanism, because an invariant with no mechanism is a wish.

| # | Invariant | Android enforcement | iOS enforcement | If violated |
|---|---|---|---|---|
| **SI-1** | **No therapeutic write exists anywhere.** No bolus delivery, no basal change, no pump-setting modification, no device command — not in the Driver protocols, not in any Driver, not behind a flag. | Absent by construction; CodeRabbit medical-safety review | Driver protocols expose no write member; CI rejects any write-shaped symbol in Driver modules; project lead review required | Patient harm. Also voids the entire product framing and the security policy's stated non-accepted-report class. |
| **SI-2** | **Glucose outside 20–500 mg/dL is rejected, never clamped.** Rejection is recoverable and logged with the violated bound; it never crashes the process and never silently corrects a value. | `require` in model constructors; `SafetyConstantDriftGuardTest` | Failable/throwing initializers — **never `precondition`**, which would trap a monitoring app mid-background-wake; CI drift guard over every definition site | A clamped value is a plausible wrong number. Worse than no number. |
| **SI-3** | **mg/dL is canonical everywhere.** Storage, transport, threshold comparison, alerting, chart geometry, and statistics are mg/dL. mmol/L exists only at the display boundary, converted once via 18.0156, rounded last. | Convention plus drift guard | A glucose type whose stored value is mg/dL by construction, with conversion only at formatting; CI fails a hardcoded factor outside the single definition | Unit confusion in a dosing-adjacent context. |
| **SI-4** | **One definition of each Safety Constant, shared by phone and Watch.** The Conversion Factor, the Glucose Validity Bound, and the Tandem epoch offset are defined once in a module both targets link. | ~19 enumerated duplication sites held equal by a drift-guard test | A single shared module; CI fails any literal reintroduction | Phone and wrist disagree about the same reading. |
| **SI-5** | **The Alert Floor never fires from stale data or from unconfirmed thresholds.** It arms only on a Glucose Reading fresh by its own sensor timestamp, and only against thresholds the user or their Backend actually set — never defaults. | Freshness gate plus threshold provenance check | Same gates, enforced in shared code covered by tests at both targets | An alarm from an hour-old reading trains users to ignore alarms. |
| **SI-6** | **The Coverage Claim never overstates.** It carries an explicit expiry, decays without new data, and resolves to *not watching* with a specific reason rather than silence. The Watch never derives its own claim — it renders and decays the phone's. | Permanent foreground-service notification | Composite of Live Activity, complication, and in-app banner — **none permanent**; the honesty requirement moves into the copy and the expiry | A silent app that looks like a watching app is the most dangerous failure mode in this product. |
| **SI-7** | **Only completed insulin deliveries are reported as delivered.** Started, cancelled, and in-progress boluses are never counted. SmartGuard auto-basal micro-boluses stay excluded from bolus totals. | Driver-level filtering | Same, with protocol tests over recorded frames | Overstated insulin on board leads to under-treatment of a low. |
| **SI-8** | **History cursors never advance past a record that was not successfully decoded.** An undecodable frame stops the cursor; it is never skipped. | Per-driver cursor discipline | Same, plus persisted cursors — iOS termination makes process-local cursors lose data | Silently lost insulin records. |
| **SI-9** | **No health value, raw device payload, or credential appears in any log at or above debug level.** Raw packet capture exists in debug builds only, in memory only. | CodeRabbit BLE-protocol check | Same policy; CI rejects logging of health-typed values; diagnostic export is scrubbed | PHI disclosure. |
| **SI-10** | **Credentials and pairing secrets live in the Keychain**, device-only, readable after first unlock so overnight reconnection works while the device is locked. | `EncryptedSharedPreferences` + SQLCipher | Keychain with a device-only after-first-unlock class; encrypted local store | Credential theft; or an app that cannot reconnect overnight. |
| **SI-11** | **Backend-supplied Safety Limits may only narrow, never widen,** the Glucose Validity Bound. A response that would widen it is rejected atomically. | Validation on ingest | Same, with contract tests | A compromised or misconfigured Backend could otherwise disable the safety bound. |
| **SI-12** | **Unknown fields in a Backend response are tolerated; a missing consumed field fails loudly.** The tolerant-reader direction is asymmetric and deliberate. | Moshi tolerant reader; `ContractSmokeTest` | Explicitly configured decoding — **Swift's synthesized `Codable` breaks this by default** and must be overridden; contract tests assert both directions | A newer Backend silently breaks an older client, or a renamed field silently becomes `nil`. |

> `[NOTE FOR PM]` SI-2 and SI-12 are the two invariants most likely to be violated by an idiomatic Swift translation rather than by a design decision. Both warrant an explicit architecture note and a lint rule, not just a test.


## 5. Features

*Each subsection is a coherent feature: behavioral description first, functional requirements nested under it. FRs are numbered globally (FR-1 through FR-237) so downstream artifacts have stable references even if features are reorganized. Journeys are referenced by ID inline; safety invariants by SI-N.*



### 5.1 Pump Connection and Pairing

**Description:**

Pairing is the only place in the app where the user does BLE work by hand, and on iOS it is the subsystem that diverges most from Android. It is reached from Settings, never from onboarding: a Pump card appears whenever a Driver declaring a pump-status or insulin-source Capability is selected, showing "Paired" or "Not paired" and offering **Pair Pump** when unpaired or **Re-pair** when paired. The pairing flow returns the user to Settings automatically the moment the connection reaches Connected. If no Driver is selected there is no Pump card and therefore no route to pairing at all — the app must say so and point at the Driver picker rather than presenting a blank Settings pane.

The active Driver decides the whole shape of the flow. Two shapes exist and only two. **Phone-scans-and-connects** (Tandem t:slim X2 and Tandem Mobi): the app scans for the Pump's service, lists what it finds, the user taps a Pump and types the pairing code off the Pump. **Phone-advertises-and-waits** (Medtronic MiniMed 680G/770G/780G): the app makes the phone discoverable under a fixed name, the user selects that name on the Pump itself, and there is no scan, no list and no code. Every string on the pairing screen — the blurb, the code instructions, the discoverable-as copy — is supplied by the Driver. Android hard-coded Tandem copy into the central-scan branch, which would mislabel any future contributed Driver; that defect is not ported (Realizes UJ-6).

Bluetooth permission works differently enough to change the UI. iOS has exactly one Bluetooth permission covering both the central and peripheral roles, it is prompted implicitly by the first Bluetooth operation, and **iOS never re-prompts after a denial**. Android's "tap Scan again to re-request" is dead code here. So the app explains why Bluetooth is needed *before* the first Bluetooth operation runs, and on denial replaces the retry loop with a single card carrying an Open Settings action that re-evaluates itself when the user comes back.

The seven connection states — Disconnected, Scanning, Connecting, Authenticating, Auth Failed, Connected, Reconnecting — are kept verbatim from Android because every other section consumes them. What changes is that Disconnected must carry a reason: iOS can be powered off, unauthorized, unsupported (the Simulator), or resetting, and rendering any of those as a bare "pump not connected" tells the user a lie about which thing is broken.

Connecting and authenticating are where Android's UI is unsafe to copy. Android has no cancel affordance and no UI timeout; on Android the OS GATT connect eventually errors out, but on iOS a pending connection **never** times out by design. Shipping Android's screen would produce an unrecoverable spinner whose only escape is force-quitting — which additionally kills background monitoring. So the app adds a Cancel and a 45 s watchdog, deliberately longer than the Driver's own 30 s authentication timeout so the Driver's real transition always wins when it fires.

Failures must be told apart. Android collapses a mistyped code, a lost bond, stale encryption keys and a Pump that ignores requests into one string, "The pump rejected the pairing attempt." That is a patient-safety communication defect: the user is left with no data and no actionable step. iOS gets one signal Android never had — the system reports when the peripheral has removed its pairing information for this phone — and one capability Android had that iOS does not: **the app cannot remove a Bluetooth bond.** There is no public or private API; bond removal is exclusively a user action in Settings → Bluetooth → ⓘ → Forget This Device. Three Tandem recovery paths and both Drivers' unpair paths depended on programmatic bond removal. All of them become guided user procedures. That is the broken-pairing wall Dana hits (Realizes UJ-4): the app detects the condition, states plainly that the pump no longer trusts this phone, gives numbered steps with a one-tap route into Settings, and then verifies recovery by attempting a fresh connection.

Because the automatic remedy is gone, the Android *restraint* rule matters more on iOS than it did on Android, not less. Android deliberately never removes the bond once a successful authenticated session has happened, tolerating up to 20 consecutive encryption failures first, because sleep/wake renegotiation resolves itself. An over-eager iOS classifier does not cost a silent re-bond; it strands a user in front of a Settings procedure they may never complete. The counters and the restraint port exactly.

Reconnection is indefinite and has no give-up condition. While a pairing exists the app keeps trying. On Android that meant a fast exponential ladder for ~5 minutes then a 120 s slow phase forever. iOS provides the better primitive natively: a connection request with no timeout, serviced by the system, surviving backgrounding, system eviction and reboot. The app keeps the Android ladder in the foreground so user-visible behaviour matches, and hands off to the indefinite pending connection whenever the app leaves the foreground. Backoff *intervals* are bounded; the loop is not. Counters are retained for diagnostics only, exactly as Android caps `consecutiveReconnectFailures` at 100 and never lets it stop the loop. The only things that stop it are the user unpairing and one positive determination that the pairing is no longer valid — the latched Auth Failed state, which is reached from a rejected or expired handshake and cleared by user action, never from an attempt count. FR-13 owns that rule and every other requirement in this section conforms to it. Reconnection must work while the device is locked, which makes the Keychain accessibility class a safety decision rather than a formality: device-only, readable after first unlock, fixed by SI-10 — anything stricter and overnight reconnection silently fails in precisely the window this app exists to cover (Realizes UJ-2).

Two iOS-only losses have to be stated in product, not buried. First, **force-quitting the app from the App Switcher permanently suppresses system relaunch for Bluetooth events until the user manually opens the app again** — no entitlement, background mode or API changes this, and the failure is invisible: no badge, no notification, no system indication. Second, an app advertising from the background has its local name stripped and its service UUIDs moved to an area only other Apple devices can read, so a Pump scanning for a name or a service UUID cannot discover a backgrounded iPhone. That makes advertise-and-wait pairing **and** advertise-and-wait reconnection foreground-only. The Android documentation's promise that a Medtronic Pump "is remembered — GlycemicGPT reconnects on its own" is false on iOS and the in-app copy must say so.

Unpair is reconciled to one operation. Android had two entry points with materially different effects: the pairing screen tore everything down without asking, while Settings asked for confirmation and then only cleared credentials, leaving a live session, a running service and a stale bond. Ported as-is, the weaker path would leave an orphaned pending connection registered with the system and a bond the app can never remove, while the user believes the Pump is disconnected. One canonical unpair, invoked from both entry points, always confirmed, always followed by the Forget This Device instruction.

Two smaller corrections carry through. Android displayed the Pump's raw MAC address as its subtitle in both the pairing screen and the Settings card; iOS has no address to show and would otherwise show an opaque per-install UUID, which is worse than useless to a user and is a device identifier that must not appear in logs at or above debug level. The app identifies a Pump by name and detected model, and states the one consequence that substitution carries — that a reinstall or a device restore can leave the saved Pump unrecognised. And Android's single shared credential store meant pairing a second Driver overwrote the first Driver's record; credentials are namespaced per Driver here.

Everything in this section must be exercisable without hardware. The lead developer has no iPhone and no Apple Watch, and Core Bluetooth does not exist in the iOS Simulator, so every pairing state, every failure category and the full reconnection lifecycle must be reachable through the Simulated Driver and the Trace-Replay Driver.

**Functional Requirements:**

#### FR-1: Reaching pairing from Settings

The user can reach a dedicated pairing flow from a Settings Pump card that shows current pairing status, offering **Pair Pump** when unpaired and **Re-pair** when paired, and is returned to Settings automatically once the Pump reaches Connected. Realizes UJ-4.

**Consequences (testable):**
- The Pump card renders whenever the selected Driver declares the pump status or insulin source Capability, resolved generically from the Driver Catalog with no vendor name hard-coded in the card.
- Card subtitle is "Paired" with the Pump's name and detected model, or "Not paired"; it is never the raw device identifier.
- Reaching Connected pops the pairing flow back to Settings even when the pairing flow is not the frontmost view.
- Auth Failed never navigates away on its own.
- Settings re-reads pairing status when it becomes active again, so a pairing completed elsewhere is reflected without a manual refresh.
- With no Driver selected, no Pump card renders; the app instead shows a one-tap route to the Driver picker and states that a Driver must be selected before a Pump can be paired. Android leaves this a dead end.

#### FR-2: Driver-determined pairing shape and Driver-supplied copy

The user is presented the pairing flow declared by the active Driver — phone-scans-and-connects or phone-advertises-and-waits — and the flow changes live when a different Driver is selected in Settings. Realizes UJ-6.

**Consequences (testable):**
- Exactly two pairing shapes exist. A Driver declaring neither is a Driver Catalog failure, not a runtime fallback.
- All user-visible pairing copy — scan blurb, per-model code instructions, discoverable-as text, fault remediation — is supplied by the active Driver. No vendor-specific string is compiled into the shared pairing views; a test asserts the shared views contain no occurrence of "Tandem", "t:slim", "Mobi", "Medtronic" or "MiniMed".
- Switching the selected Driver while the pairing flow is open re-renders it into the other shape without restarting the app.
- The pairing header and the paired-status card render above the shape-specific content in both shapes.
- The connection the flow establishes is read-only: no pairing or connection path exposes a bolus, basal, pump-setting or device command. Upholds SI-1.

#### FR-3: Bluetooth pre-explanation, the system prompt, and denial recovery

The user is told why the app needs Bluetooth before the system Bluetooth prompt appears, and on denial is given a one-tap route into the app's iOS Settings pane whose state clears automatically on return. Realizes UJ-4.

**Consequences (testable):**
- No Bluetooth operation runs — and therefore no system prompt appears — until the user taps Scan or Start Pairing and dismisses the in-app explanation.
- One denial surface, not two. Title "Bluetooth permission required"; body names both roles: "GlycemicGPT needs Bluetooth to find your pump and to let your pump find this phone."
- The denial card carries an Open Settings action. It does not carry a retry that re-requests permission, because iOS never re-prompts after a denial.
- Authorization is re-evaluated whenever the app becomes active; the denial card clears itself when the user returns having granted permission.
- Restricted and denied are distinguished from not-determined in the state the card renders from.
- On first connection to a Tandem Pump the app warns in advance that an iOS pairing dialog will appear and must be accepted, because that dialog cannot be triggered or observed programmatically.

#### FR-4: Scanning and the discovered-Pump list

The user can scan for nearby Pumps, see each one identified by name and detected model with a live-updating signal strength, and stop the scan at any time. Realizes UJ-4.

**Consequences (testable):**
- The scan filters on the Driver's declared service; for Tandem that is `0000fdfb-0000-1000-8000-00805f9b34fb`. Nothing outside the filter is listed.
- Signal strength updates live while the entry is visible. Android froze RSSI at first sighting; that is not ported.
- Entries are ordered strongest-first with a stable tiebreak on first-seen, and are removed after 10 s without a sighting. [ASSUMPTION: the 10 s age-out is an iOS-side choice; Android never aged entries out and has no corresponding number.]
- The secondary line is the detected model, derived from the advertised local name: leading "tslim X2" or "t:slim X2" (case-insensitive, whitespace-collapsed) is t:slim X2; leading "Tandem Mobi" is Mobi; anything else is Unknown. It is never a device identifier.
- Empty state while not scanning: "No pumps found. Tap Scan to search." Scan button toggles "Scan for Pumps" / "Stop Scan"; while scanning the list is preceded by a progress indicator and "Scanning...".
- The scan stops automatically after 2 minutes of no user interaction so the radio is not left running on an abandoned screen. [ASSUMPTION: Android has no scan timeout at any layer; the 2-minute bound is introduced for iOS and matches the Pump-side pairing-code timeout documented as "a couple of minutes".]
- When a scan cannot start, the user is told which condition prevents it — Bluetooth turned off, Bluetooth permission denied, Bluetooth unavailable on this device — rather than the scan silently ending. Android swallowed the scan-failure exception and just stopped saying "Scanning…".
- Selecting a Pump stops the scan.

#### FR-5: Pairing-code entry

The user can enter a pairing code of 6 to 16 characters for a selected Pump, guided by instructions specific to the detected model, and can edit and resubmit it after a rejection without re-selecting the Pump. Realizes UJ-4.

**Consequences (testable):**
- Pair is enabled only at 6 or more characters; input is truncated to 16; empty submission is a no-op.
- No character-class filtering, no trimming, no case normalisation, no client-side verification of the code. A numeric-only keyboard is forbidden: 11–16-character codes route to the legacy handshake and are not numeric.
- Autocorrection and autocapitalisation are disabled — behaviour Android received from the platform and iOS does not.
- Handshake selection is by code length and never asked of the user: 10 characters or fewer selects the modern handshake, 11 or more selects the legacy handshake.
- Model-specific instruction text, supplied by the Driver:
  - has a screen — "Check your pump screen for the pairing code. You must confirm pairing on the pump."
  - has no screen — "Put your Mobi on the charging pad and double-press the pump button to enter pairing mode. Then enter the 6-digit PIN printed behind the cartridge well on your pump body."
  - unknown — "Enter the pairing code from your pump. Check your pump screen or documentation for the code."
- Cancel clears both the selection and the code and returns to the scan list; a rejection retains the code so the user can correct one character.

#### FR-6: Advertise-and-wait pairing

The user can make the phone discoverable to a Pump that initiates its own connection, select the phone's advertised name on the Pump, and watch the flow move from waiting to connecting to connected, entering no code. Realizes UJ-4.

**Consequences (testable):**
- Before starting, an unconditional "Before you start" card states: "A pump pairs with only one phone at a time. If this pump is currently paired with the manufacturer's official app, remove it there first or it will not connect here."
- The waiting card shows a progress indicator, "Waiting for your pump", and name-specific copy: `Your phone is now discoverable as "Mobile 000001". On your pump, open the pairing menu (Add/Pair new device) and select "Mobile 000001" to connect.` The advertised name must be the name iOS actually broadcasts and must satisfy the Pump's matcher `Mobile .{0,7}`.
- First-pair advertising surfaces "No pump has connected yet. If this pump is still paired with the manufacturer's official app, remove it there first." after 60 s while continuing to advertise and continuing to show Cancel. Reconnect-mode advertising waits indefinitely.
- The waiting card states that the app must remain open and on screen: "Keep this screen open while your pump connects — iPhone can only be discovered by your pump while the app is on screen." Advertising starts only from the visible pairing screen.
- The secure handshake is bounded at 30 s; expiry latches Auth Failed and stops advertising. The latch is the positive invalid-pairing determination FR-13 admits — a state the user clears — not an attempt cap and not a give-up condition; the reconnection rule is FR-13's.
- Phase is driven off connection state, not off whether advertising is live: Connecting or Authenticating renders the connecting card; Scanning, or advertising with no terminal fault while Disconnected, renders the waiting card; anything else renders the idle card with the fault and Try Again. A terminal fault is any fault other than the still-waiting one.
- Re-pair for an already-paired Pump can force first-pair advertising from the Re-pair entry point. Android defines this switch but leaves it unreachable from the UI.
- Cancel stops advertising and returns to idle.

#### FR-7: One-phone-at-a-time warning

The user is warned, before pairing and again in Settings, that a Pump connects to only one phone at a time and must be removed from the manufacturer's official app first. Realizes UJ-4.

**Consequences (testable):**
- The warning renders on the pairing screen for both pairing shapes and as a Driver-contributed note on the Settings Pump card.
- Medtronic's Settings note reads: "A MiniMed pump pairs with only one phone at a time. Remove the pump from the official Medtronic app before pairing it here."
- Driver-contributed notes on the Pump card are informational only; no interactive Driver setting renders there.
- A Pump that is connectable but never completes a session, or immediately disconnects, produces the specific message "Another app or device is connected to your pump" rather than a generic pairing failure. This is the symptom of the vendor's own app holding the Pump's single connection.

#### FR-8: The connection state model

The app exposes one connection state with seven values — Disconnected, Scanning, Connecting, Authenticating, Auth Failed, Connected, Reconnecting — consumed identically by the pairing flow, the dashboard status row, the diagnostics view, the polling gate and the Watch forwarding path. Upholds SI-1.

**Consequences (testable):**
- The seven names and their transitions are the Android set. Auth Failed is latched; nothing clears it but a new user-initiated connect, a new pair, an unpair or a Driver swap. It is the single positive invalid-pairing determination FR-13 admits, always user-clearable, and it is never reached from a failure count, an elapsed duration or a backoff ceiling.
- Disconnected always carries a reason, and the reason distinguishes at minimum: Bluetooth powered off, Bluetooth permission denied, Bluetooth unavailable on this device, radio resetting, and ordinary link loss. Rendering all five as a bare "not connected" is a defect.
- Authenticating is promoted to Connected only after a 500 ms settle and only if the state is still Authenticating.
- Deselecting the Driver collapses the state to Disconnected regardless of radio state.
- A status read is rejected unless the state is Connected.
- Every one of the seven states, plus every Disconnected reason, is reachable in the iOS Simulator through the Simulated Driver with no Bluetooth hardware.

#### FR-9: Cancelling a connection attempt

The user can cancel while the app is connecting or authenticating and return to the previous step, and is offered a retry path if the attempt has not resolved within a bounded time. Realizes UJ-4.

**Consequences (testable):**
- The connecting card carries a Cancel. Cancelling actually cancels the pending connection; it must not leave a pending connect alive in the system.
- A 45 s UI watchdog surfaces a retry. The value is deliberately above the Driver's 30 s authentication timeout so the Driver's own transition wins whenever it fires.
- Card text is unchanged from Android: Connecting → "Connecting to pump...", Authenticating → "Authenticating...", any other state → "Working...".
- After cancel, the central-scan shape returns to the scan list and the advertise-and-wait shape returns to idle.

#### FR-10: Distinct pairing-failure categories

The user is shown which category of failure occurred, with its own copy and its own remediation, rather than one generic failure message. Realizes UJ-4.

**Consequences (testable):**
- The following categories are distinct and separately reachable in the Simulated Driver:
  - code rejected — "Pairing failed" / "The pump rejected the pairing attempt. Please verify the code and try again.", rendered above a live code field pre-filled with the previous code.
  - the Pump no longer recognises this phone — see FR-11.
  - secure handshake timed out — "The pump connected but the secure handshake timed out. Try again."
  - the Pump rejected the secure handshake — "The pump rejected the secure handshake. Try again."
  - no Pump has connected yet — "No pump has connected yet. If this pump is still paired with the manufacturer's official app, remove it there first."
  - could not start advertising — "Couldn't start Bluetooth advertising. Close other Bluetooth apps and try again."
  - this phone cannot act as a Bluetooth accessory — "This phone can't act as a Bluetooth accessory, so it can't pair with this pump." On iOS this is reachable only from the Simulator or an unsupported/unauthorized radio state, not from a hardware limitation.
  - Bluetooth unavailable — carries the specific radio reason.
  - another app or device is connected to your pump — see FR-7.
- Each category renders a Try Again action; the fault persists until the next attempt clears it.
- A failure category is never inferred from a raw link-layer status byte, because iOS does not expose them. Classification is behavioural — time to disconnect, whether authentication completed, whether any notification ever arrived — refined by the system's reported error.

#### FR-11: The broken-pairing wall

The user is walked through forgetting the device in iOS Settings when the app determines the Pump no longer trusts this phone, and the app verifies recovery afterwards. Realizes UJ-4.

**Consequences (testable):**
- The app cannot remove an iOS Bluetooth bond and must never imply that it can. Every remediation is a user procedure.
- The wall presents numbered steps — Settings → Bluetooth → ⓘ next to the Pump → Forget This Device → return here and pair again — with a one-tap route into Settings, and a Retry Pairing action that attempts a fresh connection and reports whether recovery worked.
- Copy: "Your pump no longer recognises this phone. Open iOS Settings → Bluetooth, tap the ⓘ next to your pump, choose Forget This Device, then pair again here."
- The wall is reachable from three conditions: the system reporting that the peripheral removed its pairing information; three consecutive rapid disconnects before ever reaching Connected; and three consecutive connections that reach Connected and receive zero notifications. The last condition is the only available detector for a stale service cache, because iOS provides no way to invalidate one.
- For a Tandem Pump the steps also state that the Pump must be put back into pairing mode, because the modern handshake falls back to a full bootstrap once the saved secret is discarded.
- The wall is not a toast or a banner; it blocks the pairing flow until dismissed or resolved.

#### FR-12: Restraint before declaring a pairing broken

The app never presents the broken-pairing wall, and never treats a disconnection as a trust failure, when a successful authenticated session has previously been established with that Pump and the user has not unpaired. Upholds SI-1.

**Consequences (testable):**
- "Had a successful session" is reset only by a user-initiated disconnect or unpair. It deliberately survives every reconnect cycle, app relaunch and system restoration.
- Up to 20 consecutive encryption failures are tolerated after a successful session before any failure is reported, and the app never routes to the wall on that path. Sleep/wake renegotiation failures self-resolve.
- Rapid pre-Connected disconnects trip at 3 only when no successful session has ever occurred; with a prior successful session they are treated as the Pump's own idle timeout and reconnection continues.
- A test asserts that a sequence of 19 encryption failures following a successful session produces no user-visible trust failure and no interruption of the reconnect loop.
- On iOS this restraint is stricter than on Android in consequence, not in rule: a false positive costs the user a manual Settings procedure plus physical access to the Pump's pairing menu, with no automatic recovery available.

#### FR-13: Indefinite reconnection

The app reconnects to a paired Pump indefinitely, with no attempt limit and no give-up condition, until the user explicitly unpairs or the app positively determines the pairing is no longer valid. This FR is the single definition of the reconnection rule; every other requirement in this PRD that describes reconnect behaviour conforms to it. Realizes UJ-2. Upholds SI-1.

**Consequences (testable):**
- No attempt cap, no maximum-failures abort, no elapsed-time abort, no backoff ceiling that terminates the loop. The Pump is a medical device; while a pairing exists the app keeps trying.
- Backoff *intervals* are bounded and are permitted; a terminal state at the end of the ladder is not. The ladder's last rung repeats forever.
- Exactly two conditions stop the loop, and neither is derived from a failure count or an elapsed duration: (a) the user unpairs (FR-17) or deselects the Driver; (b) the app positively determines the pairing is no longer valid — the latched Auth Failed state (FR-8), entered only from a rejected or expired secure handshake (FR-6), which routes to the broken-pairing wall (FR-11) and is cleared by a new user-initiated connect, a new pair, an unpair or a Driver swap.
- In the foreground, the retry ladder matches Android: attempt count saturating at 10, delay `min(1000 × 2^min(attempt,5), 32000)` ms — 1 s, 2 s, 4 s, 8 s, 16 s, 32 s, then 32 s flat — then a 120 000 ms interval thereafter, repeated without end.
- On leaving the foreground the app cancels its timers and leaves a single pending connection outstanding with no timeout, re-armed on every disconnect and whenever the radio powers back on. Ladder position is retained and resumes on foregrounding.
- Consecutive-failure counters are retained for diagnostics only, capped at 100 as on Android, and never influence whether the loop continues. Reaching the cap changes nothing a user can observe.
- A test drives 1,000 consecutive failed attempts against an intact pairing and asserts the loop is still running, the state is still Reconnecting, and no terminal state was entered.
- Reconnecting is the reported state whenever a pending connection is outstanding and the app is not connected, and it is visible on the pairing screen. Android renders Reconnecting as the plain scan UI with no indication at all; that is not ported.
- A project-lead review rule under FR-212 forbids attempt caps, give-up conditions and app-scheduled reconnect timers in the connection layer. The trees the rule reaches are exactly those on FR-212's CODEOWNERS roster, which is the single definition; this FR restates no path of its own, and a Driver tree absent from that roster is outside the rule. It is a review requirement, not a Required Check, and it is not one of the five names in FR-197.

#### FR-14: Reconnection while backgrounded, locked, evicted and after reboot

The app maintains and re-establishes the Pump connection while backgrounded and while the device is locked, and resumes automatically after system eviction and after the device reboots and is first unlocked. Realizes UJ-2. Upholds SI-10.

**Consequences (testable):**
- Pairing credentials are readable after first unlock while the device remains locked, so an overnight reconnection authenticates without the user touching the phone. A test asserts the accessibility attribute on every stored pairing item; a hardware step locks the device, drops the link and verifies reconnection while locked.
- Credentials are device-only: they never sync to iCloud Keychain and never restore onto another device, where they would be useless and a liability.
- Both the central and peripheral roles are configured for system restoration, and a restored launch re-adopts restored peripherals and re-arms the pending connection.
- Every restored or reconnected session re-runs authentication from scratch. No handshake state, session cipher state, in-flight request or assembler buffer is assumed to survive termination. This matches Android, which already re-authenticates on every reconnect.
- Reconnection after a drop does not require the Pump to re-enter pairing mode and does not require the user to re-enter the pairing code, for as long as the pairing is intact.
- Background freshness is best-effort and is not promised at Android's cadence; the loss is §7 PL-12 and the Coverage Claim states it (FR-83). Foreground behaviour matches Android.

#### FR-15: Force-quit disclosure and detection

The user is told, permanently and in-product, that force-quitting the app from the App Switcher stops background Pump monitoring until the app is opened again, and is notified when a prolonged gap in background activity is detected. Realizes UJ-2. Upholds SI-6.

**Consequences (testable):**
- The statement appears in onboarding, in Settings while a Pump is paired, and in the shipped pairing documentation. It is not dismissible-and-forgotten.
- There is no programmatic mitigation and the app must not imply one exists. iOS suppresses Bluetooth relaunch for a force-quit app until the user manually reopens it, and no entitlement or background mode changes that.
- The connection layer records a wake on every Core Bluetooth event so the gap detector has an input. The last-ran timestamp, the gap detection and the notification that reports it are FR-85's.
- The Settings surface that reports the conditions degrading background monitoring is FR-166's Reliability card; the notification-suppression conditions are FR-171's. See FR-166 and FR-171. Android's battery-optimization guidance is not ported (§7 PL-52).

#### FR-16: Foreground-only discoverability for advertise-and-wait Drivers

The user of an advertise-and-wait Driver is told that both first pairing and every reconnection after a drop require the app to be open and on screen. Upholds SI-6.

**Consequences (testable):**
- An app advertising from the background has its local name removed and its service UUIDs relocated where only other Apple devices can read them, so a Pump cannot discover a backgrounded iPhone. Advertising is therefore started only from the visible pairing screen.
- The in-app copy and the shipped documentation state that the Pump does not reconnect on its own for this Driver. Android's "Once paired, the pump is remembered — GlycemicGPT reconnects on its own" is false on iOS and must not be carried over.
- When a paired advertise-and-wait Pump has been disconnected past a threshold, the user is prompted to open the app; the notification delivery contract is FR-85's. The reconnect loop itself keeps running and gives up on nothing (FR-13) — what is foreground-only is discoverability, not the attempt.
- An already-established link does survive backgrounding; the degradation is specifically at re-establishment.
- The Driver ships at Beta Verification Status and its documentation states it is not suitable as a sole monitoring path on iOS.

#### FR-17: One canonical unpair, always confirmed

The user can unpair a Pump from either entry point and gets exactly the same effect, after an explicit confirmation, followed by the instruction to complete removal in iOS Settings. Realizes UJ-4.

**Consequences (testable):**
- Confirmation copy: title "Unpair Pump", body "Are you sure you want to unpair this pump? You will need to re-pair to resume data collection.", confirm "Unpair", dismiss "Cancel". Both entry points confirm. Android's pairing-screen unpair acted immediately on a mis-tap.
- The single unpair operation: cancel the pending connection, cancel the peripheral connection, stop advertising, cancel authentication/settle/reconnect work, clear the operation queue and pending requests, clear that Driver's stored credentials, end any out-of-app status surface, reset the had-a-successful-session flag, and set Disconnected.
- After unpair, a test asserts there is no pending connection, no advertising, no stored credentials for that Driver and no active out-of-app status surface.
- The follow-through instruction to forget the device in iOS Settings is prominent and carries a route into Settings. It does not block, but it is not a toast.
- Deselecting a Driver disconnects it and preserves its pairing, so reselecting reconnects without re-pairing. Only unpair clears credentials.

#### FR-18: Per-Driver credential isolation

Credentials for one Driver are isolated from every other Driver, so selecting or pairing a different Driver never overwrites, reads or exposes another Driver's pairing. Upholds SI-10.

**Consequences (testable):**
- Every stored pairing item is namespaced by Driver id. Pairing a second Driver leaves the first Driver's record intact and re-selecting the first Driver reconnects without re-pairing. Android shared one store and clobbered it.
- Clearing a Driver's pairing clears only that Driver's namespace.
- The modern-handshake material can be cleared independently of the pairing record, so a rejected confirmation falls back to a full bootstrap without discarding the pairing itself.
- Advertise-and-wait Drivers have no pairing code; the code slot holds the advertised identity string and this is documented at the storage boundary.
- Storage mechanics beyond these requirements belong to FR-135 and FR-136; the accessibility class every pairing item uses is SI-10's, fixed at device-only, after-first-unlock.

#### FR-19: Pump identity is a name and a model, never a raw identifier

The user never sees a raw device identifier as the name of a Pump, and the app can recover a paired Pump whose opaque identifier has changed. Upholds SI-9.

**Consequences (testable):**
- No pairing surface, Settings surface or out-of-app surface renders a device identifier. Android displayed the raw MAC address unmasked in two places.
- No log line at or above debug level contains a peer device identifier, a raw device payload or a credential.
- The stored pairing record carries an opaque per-installation identifier as its primary key plus a durable fingerprint — the last advertised local name and, once read, the Pump's serial number — as the recovery path.
- When the primary identifier no longer resolves, the app re-binds the existing pairing record by matching the fingerprint against a service-filtered scan rather than presenting the Pump as unpaired.
- When re-binding does not recover the Pump, the app states the consequence in words rather than presenting an ordinary "Not paired": that iOS gives the app no stable device address, that a reinstall or a device restore can therefore leave a saved Pump unrecognised, and that the remedy is to pair again. The same statement appears on the pairing-troubleshooting page required by FR-237, whose wording is fixed against this one and tested against it rather than maintained separately. This is the user-facing disclosure §7 PL-8 requires.
- A hardware step validates identifier stability across an app reinstall and a device restore. This matters more under fork-and-build than in a normal app: Builders reinstall frequently and their TestFlight builds expire every 90 days.

#### FR-20: Connection status outside the pairing flow

The user can see current Pump connection status while paired without opening the app, and a failed reconnection or authentication that happens while the user is not on the pairing screen is surfaced rather than silently absorbed. Upholds SI-6.

**Consequences (testable):**
- The out-of-app glanceable surface itself — Lock Screen, Dynamic Island and Watch Smart Stack — is defined by FR-119. See FR-119. This section requires only that Pump connection state is one of the values that surface carries, and that it is never rendered healthier than the true state: a stale surface degrades to an explicit unknown, never to a reassuring default (SI-6).
- A trust failure or an authentication failure occurring with no Pump selected in the pairing flow still produces a user-visible signal. Android renders nothing at all in that case.
- The dashboard connection status is tappable when pairing has failed and takes the user directly to the pairing flow. Android's status row is a non-tappable dead end. The indicator's own states and treatment are FR-43's.
- The out-of-app surface is dismissible and time-limited by the platform, which is why the Coverage Claim and the Alert Floor honesty text may not depend on it alone. The Coverage Claim contract is FR-83 and its expiry and decay FR-84; the Watch renders and decays the phone's claim and derives none of its own, which is FR-126.

**Out of Scope:**
- Rendering of connection status inside the dashboard (FR-43), the Coverage Claim and Not-Watching Reason contracts (FR-83, FR-84) and all alert delivery (FR-65, FR-85), every out-of-app and Watch surface (FR-119, FR-126), Keychain and database mechanics beyond the pairing-secret requirements above (FR-135, FR-136), and the Settings surfaces that report background-monitoring and notification health (FR-166, FR-171).

**Feature-specific NFRs:**

- **Simulator reachability.** Every connection state, every Disconnected reason, every pairing-failure category, the broken-pairing wall, the restraint counters and the full reconnection lifecycle are reachable in the iOS Simulator through the Simulated Driver, with no Bluetooth hardware and no Pump. This is not test scaffolding: Core Bluetooth does not exist in the Simulator and the lead developer has no iPhone. It is exercised in CI by FR-207 and enforced by the `iOS Gate` Required Check (FR-197); this section names no gate of its own.
- **Hardware sign-off items.** Any pairing or connection path reachable only through real Core Bluetooth objects carries an explicit item on the project's single hardware-validation checklist — the one FR-207 routes to and §8.2 keys Verification Status on. This section does not define a second list; it contributes these items to that one: reconnection while the device is locked; reconnection after reboot; system-restoration relaunch; identifier stability across reinstall and restore; and every path that can reach the broken-pairing wall. Completion of that checklist is a documented release gate, explicitly **not** a Required Check and not one of the five names in FR-197.
- **No link-parameter assumptions.** The app cannot request a connection interval or an MTU. It asserts the negotiated write length meets the protocol minimum after connection and fails loudly with a diagnostic rather than proceeding, and logs negotiated link parameters in the diagnostics view so a hardware validator can report them.

**Notes:**

*Parity Ledger rows this section feeds. §7 owns the rows and their full statements; the ids below are the assignment §7 made, and this list is a traceability map, not a second definition:*
- **PL-1** Programmatic Bluetooth bond removal. Three Tandem trust-recovery paths and both Drivers' unpair paths become manual user procedures in iOS Settings.
- **PL-2** GATT service-cache invalidation on every connect. Stale-cache silent notification loss is detected after the fact (three zero-response connections) instead of pre-empted.
- **PL-3** Link-layer disconnect status bytes (0x05, 0x08, 0x13) are not exposed; failure classification is behavioural plus a coarser system error vocabulary.
- **PL-4** Manufacturer-specific advertisement data (company id `0x01F9`). The advertise-and-wait identity can only be carried as the standard local name.
- **PL-5** Advertising interval, TX power, timeout and connectability control. The reconnect-vs-first-pair advertising-mode distinction, which exists because a paired Pump scans infrequently, becomes unmitigable.
- **PL-6** Background discoverability to a non-Apple central. Advertise-and-wait pairing **and** reconnection are foreground-only; the Android promise of unattended reconnection is false on iOS for that Driver.
- **PL-7** Connection-interval and MTU requests (`CONNECTION_PRIORITY_HIGH`, MTU 185).
- **PL-8** A raw device address as a stable pairing key. Identity is an opaque per-installation identifier that can break across reinstall or restore. FR-19 carries the in-app statement of that consequence and FR-237's pairing-troubleshooting page carries the published one, and the two are tested against each other; PL-8's disclosure obligation is closed.
- **PL-13** Guaranteed background reconnection after force-quit. iOS suppresses Bluetooth relaunch until the user manually reopens the app; no mitigation exists.
- **PL-15** An undismissable, permanent out-of-app status surface. The iOS equivalent is dismissible and expires.

*Open questions:*
- Spike (b) — whether a 780G's discovery filter accepts an iOS advertisement carrying the identity as a standard local name rather than as manufacturer data — needs a physical Pump. Neither the lead developer nor DanielDanielson has one. Who validates, and does FR-6 ship gated behind an unvalidated label until they do?
- Whether an already-bonded Pump reconnects to a backgrounded iPhone by stored peer identity rather than by name. If it does, FR-16's degradation is narrower than stated; it cannot be assumed and cannot be tested without hardware.
- The 2-minute scan auto-stop and the 10 s device age-out have no Android counterpart. Confirm both, or accept them as introduced.
- Should the 45 s connect watchdog be user-visible as a countdown, or silent until it fires?

*Deliberate divergences from Android already recorded in §7:* PD-1 (one canonical unpair, FR-17), PD-2 (Driver-supplied pairing copy, FR-2), PD-3 (live RSSI, FR-4), PD-4 (Reconnecting is an explicit state, FR-8/FR-13), PD-5 (Cancel plus the 45 s watchdog, FR-9), PD-6 (force-first-pair reachable from Re-pair, FR-6), PD-7 (no silent pairing failure and a tappable status row, FR-20), PD-24 (per-Driver namespaced credentials, FR-18), PD-37 (no surface renders a device identifier; the Pump is a name and a model, FR-19, SI-9).

*[NOTE FOR PM]* Tandem Pumps accept exactly one BLE connection at a time. This collides with the vendor's own iOS app, with any macOS validation bench, and with any Watch-side experiment. FR-7's "another app or device is connected to your pump" message is the only diagnostic that distinguishes it from a broken pairing, and it will be a recurring support case for Builders who keep t:connect installed.


### 5.2 Drivers and the Device Catalog

**Description:**

A Driver is a compile-time-linked Swift module implementing one device's protocol, read-only by construction. On Android a Driver is one of two things: a Gradle module wired in through a Hilt `@Binds @IntoSet` multibinding, or a DEX JAR the user sideloads into `filesDir/plugins/` at runtime. On iOS only the first survives. Apple forbids executing code that was not signed into the bundle at build time, so the entire runtime half — `DexPluginLoader`, `PluginFileManager` (50 MB cap, `PK\x03\x04` magic check, canonical-path containment, `setReadOnly()`), `PluginManifest` (`META-INF/plugin.json`), the Storage Access Framework picker, the Custom Plugins card and its "not verified by GlycemicGPT" trust warning, and the `RestrictedContext` sandbox that blocked ~30 `Context` operations behind a seven-service allowlist — is deleted rather than ported. What replaces it is the Driver Catalog: an explicit, hand-maintained, CODEOWNERS-gated registry of every Driver compiled into this build. Because Swift cannot enumerate protocol conformances at runtime, Hilt's "it compiles, therefore it registered" guarantee is gone; a Driver that builds but is missing from the Catalog would be silently absent from the running app. That failure mode is closed by the `iOS Gate` Required Check (FR-197), not by hope.

The Driver list is where a Builder sees what their build actually contains. Each row carries name, `protocolName` + `version` rendered as "Tandem v1.0.0", the Capability slots the Driver claims, and its Verification Status (Verified / Protocol-Implemented / Beta) — the last of these being net-new metadata iOS adds, because under fork-and-build nobody else vouches for a build but the Builder. Activation is the same algorithm Android runs and it is deliberately ordered: `onActivated()` fires on the incoming Driver *before* the conflicting one is deactivated, so a single-instance Capability slot is never momentarily empty. The cost is a brief window where two Drivers hold the same slot and both may publish; events carry the publishing Driver's id so the overlap is detectable. Deactivation is never a bare button — it takes an explicit confirmation naming what stops ("may stop glucose monitoring, insulin tracking, or other services it provides"), and it keeps credentials and per-Driver settings so reactivation is not a re-pair. Realizes UJ-4 in its recovery half: Dana's t:slim X2 Driver stays selected and stays paired across everything short of an explicit unpair.

Selection has to survive more than a relaunch. The app can be relaunched straight into the background by a Bluetooth event, with no UI, no scene, and no network. The Catalog must be constructed and Drivers restored on that path, synchronously, before any Bluetooth manager exists — which means restoration cannot depend on an authenticated Backend session and must work identically in Backend-optional mode. Two restore subtleties from Android are load-bearing and are kept: a Driver that is absent (because a compile-time exclusion kept it out of this binary — FR-27, FR-189) leaves its persisted selection **untouched**, so re-enabling it in a later build restores the Builder's prior choice; but a Driver whose activation *throws* has its selection **cleared**, because a slot pointing at something that cannot start is worse than an empty slot.

Two Drivers ship purely to make the project developable and reviewable. The Simulated Driver produces realistic synthetic data with no Bluetooth; the Trace-Replay Driver plays recorded real-pump frames through the real parsers. On Android the analogous artifact is `plugins/example`, which is **not in `settings.gradle.kts`** — it is a standalone JVM project that produces a sideloadable JAR, not a built module of the app. So these are net-new work, not a port, and they are load-bearing here in a way they never were on Android: Core Bluetooth does not exist in the iOS Simulator and the lead developer has no iPhone and no Apple Watch. Every non-hardware validation of the Driver lifecycle, Safety Limits filtering, card rendering, settings persistence and parser correctness runs through these two. Both ship in every configuration including release, governed by the same compile-time exclusion as any other Driver rather than by `#if DEBUG` (FR-189).

Drivers contribute UI as data, never as views: a fixed set of declarative card and detail elements the platform renders. Ordering is deterministic — platform cards occupy priority 0–50, Driver cards 100+, lower sorts higher, ties broken by Driver id — because Android had to add an explicit sort to stop its `ConcurrentHashMap` iteration order from shuffling dashboard brand badges between emissions. Safety enforcement never lives in the UI layer: it lives in the closed Capability set (no therapeutic write exists to call), in the Glucose Validity Bound, and in Backend-supplied Safety Limits that a Driver must re-read on every validation pass and that may only ever narrow.

There are two glucose validation gates in this product and their bounds differ **by design**. The Driver-level gate (FR-32) runs against the **current**, Backend-narrowable Safety Limits at every validation pass, because a value the user's own configuration excludes should never enter the app. The storage-layer gate (FR-138, 5.8) runs against the **absolute** Glucose Validity Bound of 20–500 mg/dL, because a row already written must survive a later Safety Limits change without being retroactively invalidated. The asymmetry is deliberate and is stated in both places so a reader does not read it as a defect.

The Capability set contains no calibration member. No shipped Driver implements calibration, it is the only capability that would require writing to a device, and keeping it would force SI-1 — the strongest safety claim in this product — to carry a carve-out. A future CGM Driver that needs calibration is a PRD change with its own safety review, not a slot left open (§11 Non-Goals).

The Nightscout data source is Driver-shaped but is not a device Driver. It declares data sync only — a multi-instance Capability — so enabling it can never evict a Pump's glucose, insulin or pump-status slot. Everything else about it — what it reads, from where, its states, its controls — belongs to 5.8. See FR-153.

**Functional Requirements:**

#### FR-21: Driver Catalog as the sole registration path

The project compiles every supported Driver into the signed binary and registers each one in an explicit Driver Catalog; the app offers no way to add, install or load a Driver at runtime. Realizes UJ-6. Upholds SI-1.

**Consequences (testable):**
- No code path in the app reads an executable artifact from disk, from the network, or from a document picker; there is no analogue of `filesDir/plugins/*.jar`, of `META-INF/plugin.json` parsing, or of reflective instantiation from a class-name string.
- A Driver target that builds but is not present in the Driver Catalog fails the `iOS Gate` Required Check (FR-197); the check asserts the Catalog's exact expected set of Driver ids, so adding, renaming or gating a Driver is a deliberate edit.
- Every Driver id matches `^[a-zA-Z][a-zA-Z0-9._-]{1,127}$` (2–128 characters, first character a letter), enforced at build time, because the id is also a settings-suite name and a Keychain service name.
- Every Driver's declared API version equals the project's Driver API version constant, asserted at build time rather than checked at runtime; a mismatch fails the `iOS Gate` Required Check (FR-197) instead of making the Driver silently vanish from the list.
- Each Driver's id is reserved in the Catalog before that Driver is constructed, so a transient initialization failure cannot leave the id claimable.
- A Driver's metadata is readable without constructing the Driver, so the Driver list renders without instantiating anything.

**Out of Scope:**
- The CI job definitions and CODEOWNERS wiring themselves (5.11); the contributor-facing documentation (5.12).

#### FR-22: Viewing the Drivers this build contains

A Builder can view every Driver compiled into their build, showing name, version, protocol, the Capability slots it claims, and its Verification Status, without installing anything. Realizes UJ-6.

**Consequences (testable):**
- Each row shows `name` and `v<version>`; where a Driver declares a protocol name, the pairing surface renders it as `<protocolName> v<version>` (e.g. "Tandem v1.0.0").
- Each row shows Verification Status as exactly one of Verified, Protocol-Implemented, or Beta. Medtronic renders Beta. [ASSUMPTION: Verification Status is static metadata declared by the Driver and cross-checked in CI against the Device Verification Matrix; Android carries no equivalent field and this is net-new.]
- Each row shows an Activate control when the Driver is inactive and a Deactivate control when active.
- A Driver excluded from this binary by a compile-time exclusion does not appear in the list at all (FR-27), and the list therefore doubles as the answer to "what does this build contain".
- The list renders identically with no Backend configured, except that a data-sync Driver requiring a Backend hides its Activate control (FR-153).

#### FR-23: Activating a Driver and swapping a single-instance Capability

A Builder can activate any listed Driver; activating a Driver that claims a single-instance Capability automatically deactivates the Driver previously holding that Capability, and the slot is never empty during the swap.

**Consequences (testable):**
- The four single-instance Capabilities are glucose source, insulin source, pump status and bolus-category provider. Activating a Driver claiming several of them evicts the previous holder of each simultaneously — activating Medtronic while Tandem is active evicts Tandem from glucose source, insulin source and pump status in one operation.
- **One model, stated once (see also FR-30): what persists is the SET OF ACTIVE DRIVER IDS. Capability slots are DERIVED from that set and are never stored.** There is no slot table, so a slot assignment and the active set cannot diverge and there is nothing to reconcile.
- Activation calls the incoming Driver's activation hook first, then ADDS it to the persisted active set, then removes the conflicting Driver, then republishes. Because the slot is derived, it is occupied continuously across that mutation — a test observes the derived slot at every step and asserts it is never empty.
- Conflict detection reads the persisted active set. The in-memory active set is a projection of it, not a second source of truth, so the divergence an earlier draft resolved by precedence cannot occur.
- Activating a Driver already active is idempotent: it succeeds without invoking any lifecycle hook and without rewriting persistence.
- Activating an unknown Driver id returns a typed error naming the id.
- Activation is serialized; no two activation or deactivation operations interleave, and the two-Drivers-hold-one-slot window is bounded to the duration of the activation hook rather than an unbounded suspension.
- Every event carries the publishing Driver's id, so readings arriving from both holders during the overlap window are attributable.

#### FR-24: Multi-instance Capabilities

A Builder can have several Drivers claiming a multi-instance Capability active at the same time, and activating one never evicts a Driver holding a single-instance Capability.

**Consequences (testable):**
- The two multi-instance Capabilities are BGM source and data sync. Any number of each may be active concurrently.
- Activating a data-sync Driver leaves the active glucose source, insulin source and pump status slots unchanged.
- Two BGM sources active at once produce readings distinguished by the meter name on the reading and the Driver id on the event; neither conflicts with a Pump's glucose source.
- Multi-instance slot membership persists as a set; deactivating one member does not disturb the others.

#### FR-25: Deactivating a Driver

A Builder can deactivate any active Driver, and must confirm an explicit warning naming the consequences before deactivation proceeds; deactivation stops the Driver's work while preserving its credentials and its per-Driver settings.

**Consequences (testable):**
- The confirmation names the consequences in the form "Deactivating this Driver may stop glucose monitoring, insulin tracking, or other services it provides"; there is no path that deactivates without it.
- After deactivation and reactivation with no intervening pairing, the Driver reports itself paired and reconnects without the Builder re-entering a pairing code.
- Per-Driver settings written before deactivation read back unchanged after reactivation.
- A Driver whose deactivation hook throws is still removed from the active set, the failure is logged, and persistence is still updated — deactivation never gets stuck.
- Clearing a single-instance slot only clears it if the stored id still equals the Driver being deactivated, so a deactivation that races a swap cannot clobber the incoming Driver's claim.

#### FR-26: Selection surviving relaunch, restart, upgrade and background launch

A Builder's Driver selection survives app relaunch, device restart, app upgrade and reinstall-from-the-same-fork, and is restored automatically at launch — including a launch the system triggers in the background because of a Bluetooth event, with no user interface and no network.

**Consequences (testable):**
- The Driver Catalog is constructed and selections restored synchronously during launch, before any Bluetooth manager is created, so a restored connection callback finds a live Driver.
- Restoration succeeds with no Backend configured and with no authenticated session; nothing in the restore path performs a network call.
- The activation change is durably written before activate or deactivate reports success, so a process kill immediately afterwards does not lose the selection.
- A persisted selection naming a Driver that is not present in this build is left **untouched** (FR-27).
- A persisted selection whose Driver fails to activate is **cleared**, and the resulting empty slot is reported rather than silently retried.
- Initializing the Driver Catalog twice in one process is a programmer error and fails loudly in debug; it is not a recoverable runtime condition.

#### FR-27: Compile-time kill switch making a Driver wholly absent

A maintainer can disable a named Driver at build time such that it is excluded from the shipped binary by a compilation condition and is therefore never constructed, never listed, never pairable and never polled, while the Builder's prior selection is preserved for a later build that re-enables it.

**Consequences (testable):**
- Disabling a Driver is a **compilation condition**, not a runtime flag. The Driver's code is not compiled into the shipped binary, so there is no inert-but-present module a defect could reach. The build-composition mechanism and its default-enabled build setting are FR-189 (5.10); this FR owns what the Builder sees.
- Because gated code is otherwise uncompiled and untested, CI builds a configuration with **every** Driver's gate enabled, so every gated Driver stays compiled and test-covered (FR-208, 5.11). Both halves are required: a compilation condition alone loses coverage, an all-Drivers CI build alone is not a kill switch.
- A gated-off Driver has no entry in the Driver list, no pairing entry, no settings surface, and produces no events. Building with the Medtronic gate off produces a build in which the Driver list contains no Medtronic row at all; the default is on.
- The gate is keyed off each Driver's own canonical id constant, so a renamed Driver cannot leave the switch pointing at a nonexistent id (which would silently leave it always-enabled).
- Gating a Driver off leaves its persisted single-instance and multi-instance slot entries intact; re-enabling it in a later build restores the prior selection with no user action.
- If the gated-off Driver held the glucose source slot, that slot is empty and the app reports it as empty with a reason rather than presenting the dashboard as if a source were present.

#### FR-28: A failing Driver is skipped without affecting the others

A Driver that fails to initialize is skipped entirely and no other Driver is affected; a Driver that fails while being activated is not recorded as active. Upholds SI-2.

**Consequences (testable):**
- An initialization failure logs, drops that Driver's settings-store entry, removes it from the Driver list, and leaves every other Driver constructed and listed. The app does not crash.
- An activation failure returns a typed error, leaves the Driver inactive, writes no slot persistence, and (on the restore path) clears any stale persisted selection for it.
- No invariant violation in this subsystem terminates the process. Rejections and failures are recoverable and logged; validation uses failable or throwing construction, never a trap that would kill a background Bluetooth wake.
- A Driver whose settings or card descriptor computation fails degrades to omitting that descriptor rather than removing the Driver from the list or taking down the settings screen.

#### FR-29: Per-Driver namespaced settings that survive deactivation

Each Driver has private, namespaced settings storage that survives deactivation and reactivation, app upgrade, and background operation while the device is locked. Upholds SI-10.

**Consequences (testable):**
- Settings are namespaced by Driver id; one Driver cannot read or write another's keys.
- Settings survive deactivation, reactivation and app upgrade, and are removed when the app is deleted.
- Settings are writable and readable during a background Bluetooth wake on a locked device.
- Every settings key matches `^[a-zA-Z][a-zA-Z0-9_.-]{0,127}$` (1–128 characters, first character a letter), enforced at build time, because keys are also persistence keys.
- No credential, pairing code or pairing secret is stored in the settings store; those go to the Keychain, device-only, after-first-unlock (SI-10).
- Reading a settings key with the wrong type is caught by a per-Driver key-to-type table asserted in tests, because the platform returns a zero value rather than failing loudly. No Driver-owned settings value participates in glucose or dose validation.

**Out of Scope:**
- The Keychain credential lifecycle and orphan purge on reinstall (5.1).

#### FR-30: The closed Capability set and its cardinality rules

Every Driver declares which of the six Capabilities it provides, and the platform resolves each Capability slot from the declarations of the active Drivers. Upholds SI-1.

**Consequences (testable):**
- The Capability set is exactly six and is closed — glucose source, insulin source, pump status, BGM source, data sync, bolus-category provider — with no string-keyed or open construction. A Capability outside the set is a compile error, not a runtime rejection.
- There is no calibration-target Capability. No Capability case, no protocol, no slot and no slot-resolution branch for calibration exists; a Driver cannot declare it and the platform cannot resolve it. This is what lets SI-1 read without a carve-out: every remaining Capability is read-only, so "no device command exists in any Capability protocol" is true unconditionally. Adding calibration back is a PRD change with its own safety review (§11 Non-Goals), not an implementation choice.
- Every Capability is classified single-instance or multi-instance exhaustively; adding a Capability without classifying it fails to compile.
- Data sync has no Capability protocol: it is a pure activation and mutual-exclusion tag, and a Driver declaring it returns nothing when asked for an implementation.
- Capability lookup is compile-time typed; a Driver may declare a Capability and provide no implementation, and requesting it returns nothing rather than failing.
- The pump slot resolves to the first active Driver declaring pump status **or** insulin source that is also a device Driver; the glucose slot to the first active device Driver declaring glucose source. There are exactly these two device-typed slots. A non-device Driver declaring glucose source is excluded from them by construction, which is what keeps a Backend-mediated source out of the pump slot.
- **Derivation is a total, deterministic function of the persisted active set (FR-23) — never of iteration order.** "First" means lowest Driver id under a stable ordering, not first-encountered: Android had to add an explicit sort because `ConcurrentHashMap` iteration order shuffled dashboard badges between emissions, and a slot that shuffles is worse than a badge that does. A test resolves the same active set repeatedly and asserts an identical slot map every time.
- Slot resolution iterates an order-stable collection, so the resolved Driver is deterministic when more than one qualifies.

#### FR-31: Read-only by construction — no therapeutic write exists

The Driver protocol surface contains no bolus, basal, pump-setting or device-command write, in any Capability, in any Driver, behind any flag. Upholds SI-1.

**Consequences (testable):**
- No protocol in the Driver API declares a method that delivers insulin, changes a basal rate, writes a pump setting, or calibrates a sensor. Connect, disconnect, unpair and reconnect are the only device-touching operations and are classified as session and lifecycle, not therapy.
- No Capability protocol contains a write of any kind, because the Capability set contains no member that writes to a device (FR-30). SI-1 therefore needs no exception clause, and the Driver protocol snapshot gate (FR-205 — hosted in `Build & Test` and reaching merge gating through the `iOS Gate` Required Check, per FR-197's host assignment) can treat *any* newly added write-shaped member as a failure rather than having to distinguish a permitted one.
- The `Static Analysis Gate` Required Check (FR-197) fails the build if any Driver target writes to a known therapy control-point characteristic or exposes a symbol matching a delivery-verb denylist.
- The `iOS Gate` Required Check (FR-197) fails the build if a Driver target imports anything beyond the shared safety module, the Driver API and the Bluetooth framework — importing the app target, networking or UI frameworks is a build error, which is the compile-time replacement for Android's runtime `RestrictedContext` sandbox.
- Driver targets are CODEOWNERS-gated for review.

#### FR-32: Safety Limits read fresh at every validation pass, narrowing only

Every Driver applies its device's own validity gates first, then reads the **current** Safety Limits at every validation pass and drops values outside them rather than clamping them; Backend-supplied Safety Limits may only narrow the Glucose Validity Bound. Upholds SI-2, SI-3, SI-4, SI-11.

**Consequences (testable):**
- **Medtronic decode gates, all three, ported explicitly (SI-2, SI-7).** (a) `SG_SENTINELS = {0x0301, 0x0303, 0x030D}` dropped in the history path; (b) IEEE-11073 reserved-code rejection via `isFinite()` in the live path, applied to insulin totals and basal rates as well as glucose — a reserved SFLOAT decoded as a number is a fabricated dose; (c) the annunciation byte, which is a genuine TODO in the Android source and stays one here, named rather than silently omitted.
- **Medtronic history timestamps resolve relative offsets against a naive local wall-clock reference record.** Getting the reference wrong shifts every timestamp by the device's UTC offset — which silently mis-sequences insulin against glucose without any value looking wrong. A test resolves a known trace under a non-UTC timezone and asserts absolute timestamps.
- **The E2E-CRC requirement is read from the per-pump feature bit, never hardcoded to a model.** Hardcoding "780G" makes the Driver wrong on any pump whose feature set differs, in a direction that fails open.
- **The Driver gate and the storage gate use different bounds, by design, and neither is unified into the other.** This gate runs against the **current**, Backend-narrowable Safety Limits at every validation pass, so a value the user's own configuration excludes never enters the app. The storage-layer gate (FR-138, 5.8) runs against the **absolute** Glucose Validity Bound of 20–500 mg/dL, so a row already written survives a later Safety Limits change without being retroactively invalidated. A test narrows the Safety Limits after ingestion and asserts that already-stored rows still read back while newly offered Driver values in the same range are dropped. The asymmetry is stated in both FRs so a reader does not read it as a bug.
- Safety Limits are exposed to Drivers as a live value that always has a current reading; narrowing the limits mid-stream changes which readings are accepted without restarting the Driver, proven by a test that narrows and then re-feeds the same stream.
- **Backend-supplied Safety Limits are validated and rejected atomically — never clamped.** This upholds SI-11 and SI-2, and matches FR-155 (5.8), which owns the Backend-response validation rules. A payload is accepted only if every field passes: minimum in 20…499, maximum in 21…500, minimum < maximum, maximum basal in 1…15,000 mU/hr, maximum bolus in 1…25,000 mU, and the resulting window no wider than the absolute Glucose Validity Bound. If any field fails, the **entire record is dropped** and the last known-good Safety Limits stay in force. A configuration of (minimum 450, maximum 300) is rejected outright; it is never resolved to (450, 451). A maximum bolus of 0 is rejected; it is never resolved to 1.
- **There is no clamping path anywhere on this surface.** A clamp would silently transform a malformed or hostile Safety Limits payload into a plausible-looking one — precisely the failure SI-2 exists to prevent. A test feeds each malformed configuration above and asserts the previous limits are still in force and unchanged.
- Every rejection is logged with the field and bound that failed, and is surfaced to the user as a configuration fault naming the offending value, so the app never appears to have lost the Pump with no explanation. Rejection is recoverable: a subsequent valid sync replaces the limits normally.
- Safety Limits are persisted as one atomic record, are accepted only from Backend sync, and no local override exists anywhere in the app.
- The age of the last Safety Limits sync is exposed; a never-synced install reads as stale, with a staleness threshold of 3,600,000 ms (1 hour). Staleness is a surfaced signal; it does not by itself block readings.
- Every history-extraction and bolus-history path **drops** out-of-range records; tests prove a 900 mg/dL record and a 40 U bolus are absent from the result rather than coerced to 500 and 25.
- Two bolus caps are honoured independently: the type-level 25 U on the bolus model and the narrowable Safety Limit expressed in milliunits (default and absolute 25,000 mU). The ×1000 scale difference between milliunit limits and float-unit models is asserted in tests.
- No signature in the Driver API defaults its Safety Limits parameter; the caller must pass the configured limits explicitly.
- The Glucose Validity Bound (20–500 mg/dL) is defined exactly once, in a module both the app and the Watch app link, and every reading model, limit type and event validator references that single definition.
- **Device-reported validity gates run before any bound check and are independent of both bounds.** A Driver drops a reading its own device has marked unusable even when the value is numerically in range, because the device's status field is the sensor's own claim about whether the number means anything. For the Tandem Driver this is the `egvStatusId` byte of the CGM EGV response (cargo byte 6): the reading is accepted only when `egvStatusId` is in 1…3 (1 = VALID, 2 = LOW, 3 = HIGH — all three carry a real glucose value) and is **discarded** for 0 (INVALID) and for 4 and above (UNAVAILABLE and any future value). Tests pin all five cases. Without this gate a warm-up or error sentinel arrives as a real, in-range, alertable Glucose Reading; the drop is logged with the status value and never crashes the process (SI-2).
- **Where a device reports more than one insulin-on-board figure, the Driver selects the live one from the device's own selector field and never picks a default.** For the Tandem Driver the 17-byte `ControlIQIOBResponse` (opcode 109) cargo carries both a Mudaliar IOB (bytes 0–3, milliunits) and a Swan-6hr IOB (bytes 12–15, milliunits), with a selector byte at cargo byte 16: `0` = Control-IQ off, use the Mudaliar value; `1` = Control-IQ on, use the Swan-6hr value; any other value falls back to the Mudaliar value. Tests pin `0`, `1` and an unknown selector against a cargo whose two IOB fields differ. This is the value FR-46 and FR-121 render as "IOB as reported by the Pump" — both candidates sit inside every bound this PRD enforces, so selecting the wrong one produces a plausible, wrong, dosing-relevant number that no other check catches.

#### FR-33: No active Driver is a distinguishable error, never an empty result

Any read of Pump history, status, glucose or insulin data while no Driver holds the relevant Capability returns a typed error the caller can distinguish from a genuine empty result. Upholds SI-6.

**Consequences (testable):**
- Every Capability read returns a typed "no active Driver for this Capability" error naming the Capability; none returns an empty collection, a zero value, or a default-constructed Safety Limits.
- A history-extraction call with no active Pump Driver is distinguishable in a test from a call that legitimately found no records.
- The call site names which Capability slot it is reading, so a CGM-only Driver active alongside a Pump cannot silently satisfy a pump-slot read.
- Cancellation propagates as cancellation and is never converted into a failure result.

**Out of Scope:**
- What the dashboard renders in the no-Driver case (5.3); what the Coverage Claim says about it (5.4).

#### FR-34: Best-effort bounded event delivery

Drivers publish events to the platform over an explicitly best-effort, bounded-buffer channel, and no user-facing alerting depends on it for delivery. Upholds SI-5, SI-6.

**Consequences (testable):**
- Each subscriber has its own bounded buffer of 256 events with drop-oldest overflow and no replay; a late subscriber sees no history, and a slow subscriber's drops do not starve other subscribers.
- Buffer overflow drops the oldest event and logs a warning; it never blocks the publisher and never fails the publish.
- The Alert Floor does not read its inputs from this channel; it reads from persisted Pump data, so a dropped event cannot suppress an alert.
- Platform-only events cannot be constructed by a Driver target at all — the initializer is not visible outside the platform module, so a forged Safety-Limits-changed event is a compile error rather than a silently swallowed publish.
- Every event carries the publishing Driver's id.

#### FR-35: The Simulated Driver as a shipped first-class Driver

The project ships a Simulated Driver that produces realistic synthetic data with no Bluetooth, exercises the full Driver lifecycle, and runs in the iOS Simulator and in CI. Realizes UJ-6. Upholds SI-2.

**Consequences (testable):**
- The Simulated Driver appears in the Driver Catalog and in the Driver list like any other Driver, is subject to the same compile-time exclusion (FR-27), and carries Verification Status Beta. It ships in every configuration including release (FR-189). [ASSUMPTION: it uses a project reverse-domain id; Android's analogue is a standalone JVM project outside `settings.gradle.kts`, so this is net-new work rather than a port.]
- It declares BGM source and data sync — both multi-instance — so activating it never evicts a Pump's glucose, insulin or pump-status slot.
- Its generator reproduces the Android reference math: base = 130 + 50·sin(phase), jitter uniform in ±10, phase advanced by 2π/12 so a full cycle spans 12 readings, result rounded and bounded to 20…500; history retained is the most recent 12 readings; the default interval is 30 s, adjustable 5–300 s in steps of 5.
- It re-reads the current Safety Limits inside the generation loop, once per iteration, and **drops** an out-of-range value with a logged reason naming the violated limit rather than clamping it — this is the reference behaviour every real Driver copies.
- The generation delay runs whether or not a value was dropped, so filtering does not change cadence.
- It exercises every card element variant, every settings descriptor variant, detail screens with interactive elements and action routing, and per-Driver settings persistence — the full non-Bluetooth Driver surface, in the Simulator.
- Its manual-entry path validates against the **current** Safety Limits, not against the absolute bound, and shows an inline error on invalid input rather than silently doing nothing (both are Android defects corrected in the port).
- It logs no health value and no payload at or above debug level (SI-9).

#### FR-36: The Trace-Replay Driver as a shipped first-class Driver

The project ships a Trace-Replay Driver that replays recorded real-pump frames through the production parsers, so parser correctness and safety filtering can be validated in the Simulator and in CI without a physical Pump. Upholds SI-2, SI-8.

**Consequences (testable):**
- It appears in the Driver Catalog and Driver list, is subject to the same compile-time exclusion (FR-27), and carries Verification Status Beta.
- Recorded traces cover at minimum Tandem and, once available, Medtronic frames, and are committed as CI fixtures. [ASSUMPTION: traces are de-identified before commit — glucose values, insulin doses and device serial numbers are synthesized or offset — because a raw capture would put health data in the repository, and a fork-and-build repo is public.]
- Replaying a trace containing an out-of-range value proves the value is dropped, not clamped, and that the drop is logged with the violated limit.
- Trace fixtures cover the device-reported validity and selector gates of FR-32: a Tandem EGV frame with `egvStatusId` 0 and one with 4 prove the reading is discarded even though its glucose value is in range, and a `ControlIQIOBResponse` fixture whose Mudaliar and Swan-6hr fields differ, replayed with selector byte 0, 1 and an unknown value, proves the selected IOB.
- Replaying a trace containing a record that fails to decode proves the history cursor does not advance past it (SI-8).
- Replay is deterministic: the same trace produces the same extracted readings, boluses and basal records on every run.
- Trace fixtures are versioned alongside the parsers, so a parser change that alters extraction from a fixed trace shows up as a CI diff.

#### FR-37: Driver-contributed dashboard cards and detail screens

A Driver can contribute dashboard cards and one tappable detail screen per card, built entirely from a fixed set of declarative elements the platform renders; no Driver supplies view code, and ordering is deterministic across refreshes.

**Consequences (testable):**
- The element vocabulary is fixed and closed: 9 card element variants, 6 semantic colours, 4 label styles, 13 icons, and 6 settings descriptor variants. A Driver cannot introduce a new element.
- Ordering: platform cards occupy priority 0–50, Driver cards 100+, lower priority sorts higher, and ties are broken by Driver id so ordering is stable across refreshes. A test asserts identical ordering across repeated emissions.
- A card declaring a detail screen renders a tap affordance; a card that does not, does not, and its detail screen is never requested.
- Structural bounds are enforced and are refusals, not truncations with an indicator: nesting deeper than 5 levels is not rendered, and a detail screen is limited to 100 elements — exactly 100 is accepted, 101 is refused.
- Descriptor validation rejects a blank card id or title, an empty row, column or sparkline, a non-finite progress or sparkline value, a progress value outside 0…max, a max of 0 or less, a negative spacer height, a slider whose minimum is not less than its maximum or whose step is not positive and not at most (max − min), an empty dropdown option list, a blank dropdown value, a blank section header, and duplicate keys among interactive elements or across all settings sections.
- Descriptor validation failures are recoverable: an invalid settings descriptor drops only the informational notes and keeps the Driver's card; only losing the Driver's metadata drops the card. Neither takes down the settings screen.
- Per-control persistence: toggles and dropdowns write immediately; sliders write when editing ends, coerced into range; text inputs persist on focus loss **and** on leaving the screen (closing the Android defect where navigating away without blurring lost the edit).
- Interactive elements render only when the Driver has a settings store; informational text and action buttons always render, which is how a Driver's notes appear on the pairing card with no store.
- The detail surface reports exactly these states: Driver not found; no detail available for this card; the Driver encountered an error loading detail content; the action could not be completed. Loading is keyed on both Driver id and card id, so changing Driver while keeping the card id reloads.
- Cards and detail screens render fully in the iOS Simulator, driven by the Simulated Driver.

**Out of Scope:**
- What a specific card's content means clinically (5.3); the Watch surface, which hosts no Driver cards at all (5.7).

#### FR-38: The Backend-mediated Nightscout data source as a Driver-shaped Capability

The Nightscout data source participates in Driver activation as a data-sync Capability so that it can never evict a Pump Driver from a device-typed slot. The source itself is specified by FR-153 (5.8).

**Consequences (testable):**
- It declares data sync only — multi-instance — and provides no Capability implementation. Activating it leaves the glucose source, insulin source and pump status slots unchanged, and deactivating it disturbs no other multi-instance member (FR-24).
- It is not a device Driver, so it can never resolve into the pump slot or the glucose source slot (FR-30).
- It lives in the app module, not a Driver target, because it needs the app's networking and persistence stack that a Driver target is forbidden to import (FR-31) — the same reason Android places it in `:app`.
- Its card registers in the Driver card band at priority 200 with a detail screen and is ordered by FR-37 like any other Driver card.
- Everything else about the source — that it is off by default, that no Nightscout URL or API secret exists anywhere in the app, that the activation control is hidden when no Backend is configured unless the source is already active, the five sync states, the last-successful-sync time staying visible during an error, and the one-versus-many connection picker — is defined once in FR-153 and is not restated here. See FR-153.

**Out of Scope:**
- The source's behaviour, states and controls (FR-153); the sync engine, its cursors, paging and background scheduling (5.8); how Nightscout-sourced readings merge with Pump-sourced readings (5.8).

**Feature-specific NFRs:**

- Driver Catalog construction and selection restoration must complete synchronously during launch, before any Bluetooth manager is created, and must not perform network I/O — the whole path has to work on a background Bluetooth relaunch with no scene and no Backend.
- Driver targets depend only on the shared safety module, the Driver API and the Bluetooth framework. This is enforced by build-graph dependency, not convention.
- Every value in this subsystem that can originate from a device, the Backend or a Driver validates through failable or throwing construction. No trapping assertion is used for such a value; trapping is reserved for genuine programmer errors (double-initializing the Driver Catalog is the only one).

**Notes:**

*For the Parity Ledger (capabilities Android has that iOS cannot):*
- **Runtime Driver installation is gone.** Android lets a user sideload a DEX JAR into `filesDir/plugins/` and run a community Driver with no repo change. iOS forbids executing unsigned code (App Store Review Guideline 2.5.2 plus OS-level code signing; TestFlight is not a carve-out). The Custom Plugins card, the "Add Plugin" picker, the 50 MB / ZIP-magic / path-traversal install pipeline and the "not verified by GlycemicGPT" trust warning are all deleted. Trying an unmerged Driver now requires forking, opening Xcode and signing with your own Apple credentials — a materially higher bar than `adb push`.
- **Runtime per-Driver containment is gone.** Android's `RestrictedContext` blocks ~30 `Context` operations and allowlists seven system services; `ScopedCredentialProvider` namespaces runtime-plugin credentials. iOS has no per-module runtime capability restriction — every compiled-in Driver shares one sandbox, one entitlement set, one container and one Keychain. Replaced by compile-time containment (build-graph dependency limits, CI import lint, CODEOWNERS), which is stronger for the code it covers but covers nothing at runtime.
- **Registration is no longer guaranteed by compilation.** Hilt's `@Binds @IntoSet` means an Android Driver that compiles is registered. Swift cannot enumerate protocol conformances, so a compiled-but-unregistered Driver would be silently absent. Closed by the `iOS Gate` Required Check, but the failure mode is net-new to iOS.
- **Runtime API-version rejection becomes build-time assertion.** Android rejects a mismatched Driver at load; with compile-time linking that check is unreachable. Not a functional loss, but the enforcement moment moves.

*For the Parity Ledger (deliberate divergences this section introduces):*
- **The calibration-target Capability is removed; the Capability set is six, not Android's seven.** No shipped Driver implements it, it is the only member that would require writing to a device, and its presence forced SI-1 to carry a carve-out for a permitted `calibrate` device command. Removed from the Capability set, from slot resolution, from the Driver protocol surface and from the published contribution contract. Nothing user-visible is lost — no calibration surface ever existed on either platform — but the published capability list narrows, and a future CGM Driver needing calibration is a PRD change with its own safety review rather than a slot already open. Deliberate divergence, not a forced loss (FR-30, FR-31, §11 Non-Goals).
- **Two Tandem decode gates are stated as requirements where Android carried them only as parser code.** The `egvStatusId` 1…3 sensor-validity gate and the `ControlIQIOBResponse` selector byte are FR-32 consequences with pinned tests — all five `egvStatusId` values, and selector byte `0`, `1` and an unknown value against a cargo whose two IOB fields differ — plus Trace-Replay fixtures (FR-36). Parity is *matched*, not diverged; it is recorded here so the port cannot drop either gate silently, since both failures produce a plausible, in-range, dosing-relevant number that no other check in this PRD catches.

*[NOTE FOR PM]*
- `plugins/example` is **not** listed in Android's `settings.gradle.kts` — it is a standalone JVM project producing a sideloadable JAR, not a built module. FR-35 and FR-36 are therefore net-new engineering, not a port, and they are on the critical path: with no Core Bluetooth in the Simulator and no iPhone for the lead developer, they are the only executable Drivers during most development.
- The Android source carries a three-way API-version drift: code says 5, `docs/dev/plugin-architecture.md` says 2, and the example plugin's manifest and README say 1 — meaning the shipped example JAR would be rejected by Android's own loader today. The Android docs also omit the bolus-category provider Capability entirely and reference Safety Limits property names that do not exist. Port from the Kotlin source, never from the Android documentation.
- Android's four deprecated pump interfaces and their four registry adapters are deliberately **not** ported. Two of them carry live defects: the history-log adapter returns an empty list when no Driver is active (indistinguishable from "the patient had no boluses"), and the deprecated signatures default their Safety Limits parameter to the absolute bounds whenever a caller forgets to pass the user's narrowed configuration. FR-33 and FR-32 exist to make both impossible.
- FR-32's two Tandem decode gates are Driver-specific but are stated in a Driver-general FR because no per-Driver FR range exists. Medtronic ships **two** sensor-validity gates of its own, and both must be ported: `SG_SENTINELS = {0x0301, 0x0303, 0x030D}` in the history path (`MedtronicHistoryParser.kt:197`, applied at :511), and IEEE-11073 reserved-code rejection via `isFinite()` in the live path (:560, :616), which also guards insulin totals and basal rates. Only the annunciation byte is a genuine TODO in the Android source.

*Open questions specific to this section:*
- Does the iOS Driver API version constant reset to 1 for the new SDK, or inherit Android's 5 to keep cross-repo changelogs aligned?
- Data sync has no Capability protocol on Android — it is a pure activation tag. Keep it that way, or give it a protocol now that a Backend-mediated source is a first-class shipped source?
- Verification Status is net-new metadata with no Android equivalent. Who assigns it, and does a change to a Driver's protocol code automatically demote it from Verified pending re-validation on DanielDanielson's hardware?


### 5.3 Glucose Monitoring and the Dashboard

**Description:**

Home is one vertically scrolling screen with a fixed card order identical to Android. Sam opens it and, within one glance, learns three things in this order: whether the Pump link is up, what the number is, and whether the number can still be trusted (UJ-1). Nothing on this screen is hidden for lack of data — every card is always present and renders its own empty-state line, so an empty dashboard reads as "nothing recorded yet", never as "this feature is missing".

The screen's honesty contract is the Freshness Tier. A Glucose Reading is classified against its OWN sensor timestamp, not against when the app happened to poll it: Fresh below 6 minutes, Stale below 15, Too Stale at 15 and beyond; Pump-sourced metrics (IOB, Basal rate, battery, reservoir) use 15 and 60. Boundaries are half-open, so a reading exactly at a boundary has already crossed into the worse tier. Classification re-runs on a wall-clock timer at one quarter of the source's stale threshold (clamped to 2–30 seconds) so the badge appears and the age caption grows while the app sits open and nothing new arrives. This is the single most load-bearing behaviour in the section: a port that recomputed only on data arrival would leave a dead sensor showing a confident, green, hours-old number forever.

This matters far more on iOS than it did on Android. Android kept a foreground service polling the Pump every 15 seconds; iOS suspends the app within seconds of backgrounding and offers no guaranteed periodic execution. The dashboard therefore treats "the app was suspended" as a first-class state: on every return to the foreground the app immediately re-runs the Pump read sequence, and whatever gap remains is rendered as the tier the data actually earned. If the value is 40 minutes old because iOS suspended the app, the hero is grey and badged "Too old". iOS trades guaranteed cadence for guaranteed honesty; the display layer must never paper over the gap.

Severity colour is a pure function of the stored mg/dL value with no unit parameter, so choosing mmol/L can never change the colour a user sees (SI-3). The colour encodes severity, not direction — low and high share one amber, urgent low and urgent high share one red. At Too Stale the hero value and its trend glyph lose severity colour entirely and render de-emphasised grey.

The status row carries a Pump-link indicator in every mode with six states. The sync and Backend-reachability indicators are hidden entirely in Backend-optional mode — claiming "pending sync" or "reachable" about a Backend that does not exist is a lie the app refuses to tell. How the reachability state is derived is owned by 5.8 (FR-152); this section owns only how that state renders. iOS adds one state Android never needed — local-network permission denied — which must be distinguishable from "Backend unreachable" and actionable, because a self-hosted Backend on a LAN address requires a user grant the app cannot recover from in-app. [ASSUMPTION: the denied-permission state is surfaced in the status row itself rather than only inside Settings.]

The chart is deliberately bespoke: a 40–300 mg/dL default Y axis so the same glucose value normally sits at the same height across sessions, dashed grid lines and labels only at the low, high and urgent-high Alert Threshold values, a translucent target band, and unconnected dots drawn last so no overlay can obscure a reading. The axis is a default, not a clamp: a reading outside 40–300 EXPANDS the axis to include it, and no reading is ever pinned to a boundary. Pinning draws a valid, in-bound reading at a false height — the Android display defect this port closes — so a 35 mg/dL reading is plotted below the 40 line, not on it. This one axis rule covers every graph surface on the phone and the Watch app (FR-52; FR-133 cross-references it and defines no second clamp). From Home the chart expands into a landscape detail view with pinch-zoom, pan, double-tap reset and tap-to-inspect. Period selection is shared between the card and the detail view; the dashboard maintains five independent period selections in total, each filtered by the user's retention setting.

Time in Range is computed by a database aggregate over the Glucose Validity Bound, not in application code, so a 30-day bar does not require loading 30 days of rows. CGM statistics use the sample standard deviation (n−1), and GMI and CV% are derived from the raw mg/dL mean and never unit-converted.

Navigation is capability-driven: the AI Chat tab is absent in Backend-optional mode rather than dead-ending on a Backend error, but its destination stays registered so a restored navigation path or an internal entry point — a widget, complication or notification tap — redirects to Home instead of blanking. Those entry points travel the system's own widget/complication URL mechanism; the app registers no custom URL scheme that accepts data from another app (NFR-22). The start destination depends only on onboarding completion and never on session validity — routing an expired session to onboarding would lock locally stored Glucose Readings behind a login that cannot succeed offline. A session banner covers the gap instead.

**Functional Requirements:**

#### FR-39: Home dashboard composition and fixed card order

Any user can view a single scrolling Home dashboard whose card order is fixed and identical to Android, in every mode including Backend-optional mode. Realizes UJ-1.

**Consequences (testable):**
- Card order top to bottom: status row, glucose hero, recent-meal glance (present only when a recent meal exists — content owned by 5.5), trend chart, Time in Range, CGM Stats, Insulin Summary, Recent Boluses, then Driver-contributed cards in ascending `priority` order (lower value = higher on screen), in that exact sequence.
- Content insets 16pt leading/trailing/top and 88pt bottom; 12pt separation between adjacent cards; a 24pt gap before the footer line.
- Every card renders with no data present, each showing its own empty-state string; no card is hidden for lack of data. Zero cards may be conditionally omitted except the recent-meal glance.
- A single footer line renders one of two verbatim Android strings: "Pair your pump in Settings to start" when the Pump link is disconnected; else "Loading pump data..." when the Pump link is connected with no Glucose Reading; else nothing. (Both strings are shipped user-facing copy and are kept character-for-character, including the lowercase "pump"; the requirement prose around them uses the Glossary term Pump.)
- Driver-contributed cards are ordered by an explicit sort even though the Driver Catalog is a compile-time-linked list, so ordering is identical across the app and the Watch app.
- A blood-glucose-meter reading produced by a BGM-source Driver (5.2 FR-24) renders only inside that Driver's own contributed card, in the Driver-contributed card region of this order; its content is owned by 5.2 FR-37. It never occupies the glucose hero and never joins a shared glucose surface — the full BGM-versus-CGM rule is in FR-46.

**Out of Scope:**
- Recent-meal glance and meal-logging affordance content and gating (5.5).
- Insulin Summary and Recent Boluses card content (5.5).

#### FR-40: Pull-to-refresh forced read

Any user can pull down on Home to force an immediate re-read of Pump values and a reconciliation of Backend-supplied settings. Realizes UJ-1.

**Consequences (testable):**
- Pump reads execute sequentially in the order IOB, basal rate, battery status, reservoir level, glucose, with a 500 ms gap between reads.
- The glucose result is routed through the same path the background poller uses, so a low fetched by a manual refresh during an outage reaches the Alert Floor immediately rather than waiting for the next poll.
- A refresh requested while one is in flight is dropped, not queued — the guard is a compare-and-set on a single in-flight flag, and the flag is cleared on every exit path including thrown errors.
- When a Backend is configured, the refresh concurrently reconciles glucose range, glucose unit, meal-intelligence config, analytics settings, Pump profile, Safety Limits and Alert Thresholds. In Backend-optional mode none of these are attempted.
- "Analytics settings" is exactly two objects and nothing else: the analysis day-boundary hour consumed by FR-57 and 5.5 FR-89, and the bolus-category label override map whose resolution, caching and clearing rules are owned by 5.5 FR-89. This FR is the reconcile pass only; it defines neither object.
- The glucose unit reconcile runs on every dashboard load unconditionally and is never gated behind another setting's staleness clock.

#### FR-41: Foreground re-read on activation

The app re-runs the full Pump read sequence every time it returns to the foreground, because iOS suspends it in the background and the last value may be arbitrarily old. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Every transition to the active scene phase triggers the FR-40 read sequence, sharing the same in-flight guard.
- The first activation after launch does not double-fire when the model already fetched during initialization.
- The re-read never rewrites or back-dates a Glucose Reading's sensor timestamp; a re-read that returns the same reading leaves its age, and therefore its Freshness Tier, unchanged.
- If the re-read fails or returns nothing, the hero continues to display the cached value at whatever Freshness Tier its own timestamp earns — including Too Stale.

#### FR-42: Refresh failures preserve cached values

Any reconciliation or read failure leaves every previously displayed value intact. Upholds SI-6, SI-11.

**Consequences (testable):**
- A failed refresh logs at warn and blanks, resets or zeroes no displayed value on any card.
- A failed Safety Limits fetch falls back to last-known-good; it never widens the Glucose Validity Bound (SI-11).
- A non-2xx response or thrown error during glucose-range reconciliation leaves the cached Alert Threshold set untouched.
- No log line emitted by a failed refresh contains a health value, raw device payload or credential at or above debug level (SI-9).

#### FR-43: Pump-link indicator

Any user sees a Pump-link indicator in the status row in every mode, including Backend-optional mode, with six distinct states. Realizes UJ-4.

**Consequences (testable):**
- The six states and their treatment: connected — primary blue, no accompanying text; connecting or authenticating — tertiary amber, text "Connecting..."; reconnecting — tertiary amber, text "Reconnecting..."; scanning — tertiary amber, text "Scanning..."; pairing failed — error red, text "Pairing failed"; disconnected — error red, no accompanying text.
- The crossed-out disconnected glyph is presented as a resting state (no Pump paired, idle, or out of range), not as an error condition, in copy and in any explanatory help text.
- Icons are 16pt; icon-to-text gap 4pt; accompanying text uses the small label style in the same colour as the icon.
- The indicator renders identically whether or not a Backend is configured.

#### FR-44: Sync and Backend reachability indicators

A user with a Backend configured sees a sync indicator and a Backend-reachability indicator; a user in Backend-optional mode sees neither. Upholds SI-6.

**Consequences (testable):**
- In Backend-optional mode the sync and reachability indicators render zero elements — not a greyed-out or "unknown" state.
- Sync states resolve in first-match order: error → cloud-slash, error red; pending count > 0 → sync-in-progress glyph, tertiary amber, accessible label "\<n\> readings pending sync"; last sync timestamp present → an up/down transfer glyph, primary blue; else cloud-slash, muted. The sync indicator never shows accompanying text.
- The healthy sync glyph and the healthy reachability glyph are visually distinct glyph families (transfer arrows vs. cloud-with-check), so "my data is uploaded" is never confusable with "my Backend answers right now".
- Reachability states: reachable — cloud-with-check, primary blue, no text; Backend unreachable — cloud-slash, error red, text "Backend unreachable"; device offline — cloud-slash, error red, text "Offline"; local-network permission denied — a distinct state with its own text and a tap target that opens the system Settings page for the app. ("cloud-slash" and "cloud-with-check" name system symbols, not a product concept; the destination is always called the Backend in copy.)
- The connectivity states this row renders, and every rule for deriving them — traffic-only derivation, HTTP-response-proves-reachable, the two-consecutive-transport-failure flip, no health-check endpoint, LAN-only counts as online, device-offline precedence — are defined once. See FR-152. This FR renders that state and adds no second derivation.

**Out of Scope:**
- Derivation of the three connectivity states (5.8 FR-152).
- The sync queue itself, retry policy and pending-count semantics (5.8).
- App Transport Security posture and the local-network purpose string (5.8).

#### FR-45: Driver brand marks

Any user sees a brand mark for each active Driver that ships one, rendered untinted, immediately after the status indicators. Upholds SI-6.

**Consequences (testable):**
- Marks render at their per-brand normalized heights (Tandem 16pt, Medtronic 12pt, Nightscout-sourced 16pt) so optical weight matches in a ~16pt row.
- Marks render untinted, preserving brand colour, in both Light and Dark themes.
- The mark strip is horizontally scrollable and yields layout priority to the status indicators, so no badge set can push the Pump-link indicator off a narrow screen.
- A Driver with no bundled mark stays active and displays nothing.
- At most one Pump brand mark can appear, because only one Pump Driver is active at a time.
- Marks appear in every mode including Backend-optional mode, and are sourced through a single asset lookup so the entire set can be disabled with one change.

#### FR-46: Glucose hero

Any user sees the current Glucose Reading at hero scale with its trend glyph, unit label, relative-age caption and available Pump secondary metrics. Realizes UJ-1. Upholds SI-3.

**Consequences (testable):**
- Value renders at 64pt bold; the trend glyph at 40pt bold, bottom-aligned to the value with 8pt bottom and 4pt leading offsets; both render in the same colour whenever the glyph's own source is at least as fresh as the value (see the trend-provenance rules below).
- Trend glyphs are exactly: double-up ⇈ (U+21C8), single-up ↑, forty-five-up ↗, flat →, forty-five-down ↘, single-down ↓, double-down ⇊ (U+21CA), unknown "?" — rendered at hero style and coloured by the provenance rules below. An unparseable persisted trend name resolves to unknown rather than throwing.
- The trend glyph and the glucose value are SEPARATE Pump transactions and can disagree and age independently: on Tandem the trend icon id (`cgmTrendIconId`) is read from the HomeScreenMirror response, opcodes 56/57, not from the EGV response that carries the value. On iOS the two reads can land in different foreground activations, so the coupling is strictly weaker than on Android, where a 15-second foreground poll kept them close.
- The trend glyph therefore carries its OWN source timestamp and is classified under the CGM policy (FR-49) against that timestamp. The glyph renders at the WORSE of its own Freshness Tier and the value's, never a better one: the dashboard never presents a trend glyph as fresher than its own source.
- A glyph whose own source is Too Stale, or absent entirely, renders as the unknown "?" glyph in the de-emphasised colour beside a value that may still be Fresh; the value's own tier, caption and severity colour are unaffected by the glyph's age.
- **This FR owns the trend-glyph provenance rule for every surface in the product that renders a trend glyph** — the hero, the wrist complications and the Watch app (5.7 FR-120), the iPhone Lock Screen, Dynamic Island and Watch Smart Stack surface (5.7 FR-119) and the iPhone widgets. Those sections cross-reference this rule and state no second one. A surface that classified the glyph at the value's tier alone would render a confident arrow off a source the hero shows as "?", which is the failure this rule exists to close.
- Pinned pair: a 4-minute-old value beside a 16-minute-old glyph source renders the value Fresh, in severity colour, next to a "?" glyph; a 16-minute-old value beside a 1-minute-old glyph source keeps the glyph's direction but renders the whole pair de-emphasised at Too Stale (FR-48), because the glyph takes the worse of the two tiers and "?" is reserved for a glyph whose OWN source is Too Stale, absent or unparseable.
- The unit label ("mg/dL" or "mmol/L") renders below the value.
- The relative-age caption is coloured by Freshness Tier (Fresh green, Stale amber, Too Stale grey) and reads "just now" under 60 s, "\<n\>m ago" under 3600 s, "\<n\>h ago" under 86400 s, "\<n\>d ago" beyond. Negative ages are handled by FR-49.
- A secondary metrics row renders only when at least one of IOB, basal rate, battery or reservoir is present: IOB as `%.2fu`; basal rate as `%.2f u/hr` plus a mode suffix of " Sleep", " Exercise", " Automated" (when automated) or nothing; battery as `<pct>%`; reservoir as `%.0fu`. Each metric value is de-emphasised and badged when its own Freshness Tier is not Fresh.
- All four Pump secondary metrics classify against the Pump policy; the glucose value classifies against the CGM policy.
- With no Glucose Reading: "--" at 64pt in the de-emphasised colour plus the unit label only — no age caption, no staleness badge, no secondary metrics row.
- IOB is displayed exactly as reported by the Pump and is never computed, interpolated or extrapolated by the app.
- The hero renders a CGM Glucose Reading only. A blood-glucose-meter reading from a BGM-source Driver is a distinct record type carrying its meter name and Driver id (5.2 FR-24), and its only consuming surface is the contributing Driver's own dashboard card (5.2 FR-37, positioned by FR-39). It is always labelled with its meter name and the word "meter" so it can never be read as a CGM value.
- A blood-glucose-meter reading never enters the hero, the chart glucose series (FR-52), Time in Range (FR-58), CGM statistics (FR-59) or the Alert Floor (5.4 FR-71), and never sets, resets or refreshes a Glucose Reading's Freshness Tier. With no CGM Glucose Reading present the hero still shows "--" even when a recent meter reading exists.

#### FR-47: Severity colour from stored mg/dL alone

The app colours a Glucose Reading by severity as a pure function of its stored mg/dL value, with no unit input. Realizes UJ-1. Upholds SI-3.

**Consequences (testable):**
- Banding: value ≤ urgent low → urgent-low colour; ≤ low → low colour; < high → in-range colour; < urgent high → high colour; else urgent-high colour, against the Target Range set. **Banding is computed from the Target Range, never from Alert Thresholds** — the colour a number is drawn in and the value that makes the phone alarm are separate settings with separate stores (see Glossary).
- Pinned boundaries at the default Target Range set (urgent low 55, low 70, high 180, urgent high 250): 55 → urgent low, 56 → low, 70 → low, 71 → in-range, 179 → in-range, 180 → high, 249 → high, 250 → urgent high.
- Colour encodes severity, not direction: low and high are both #EAB308; urgent low and urgent high are both #EF4444; in-range is #22C55E. These three values are identical in the Light and Dark themes.
- Switching the display unit to mmol/L changes no pixel of colour anywhere on the dashboard.
- The colour function accepts no unit parameter, making a unit-dependent severity a compile-time impossibility.
- The banding comparison at exactly `low` and exactly `high` deliberately differs from the Time in Range bucket comparison (FR-58); both behaviours are pinned by test and the divergence is recorded, not silently reconciled.

#### FR-48: Too Stale de-emphasis of the hero

When the current Glucose Reading is Too Stale, the app removes its severity colour so a stale number cannot be mistaken for a live one. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- At Too Stale, both the value and the trend glyph render in the de-emphasised secondary colour, not in any severity colour.
- At Too Stale a "Too old" badge is present alongside the age caption.
- The transition happens on the freshness ticker (FR-50) with no new Glucose Reading arriving.
- The de-emphasis is driven by the Glucose Reading's own sensor timestamp, never by when the app received or polled it.
- A Too Stale reading is still displayed — it is de-emphasised, never blanked, and never replaced by "--" while it exists.

#### FR-49: Freshness Tier classification

The app classifies every displayed value into a Freshness Tier of Fresh, Stale or Too Stale against that value's own timestamp, using one shared definition. Realizes UJ-1. Upholds SI-4, SI-5, SI-6.

**Consequences (testable):**
- Boundaries are half-open: age < staleAfter → Fresh; age < tooStaleAfter → Stale; else Too Stale. Exactly at staleAfter is Stale; exactly at tooStaleAfter is Too Stale.
- CGM policy: Stale at 6 minutes (360,000 ms), Too Stale at 15 minutes (900,000 ms). Pump policy: Stale at 15 minutes, Too Stale at 60 minutes (3,600,000 ms).
- **This FR is the single definition of negative-age handling in this document.** A negative age — clock skew, a future-dated sensor timestamp — classifies as **Fresh FOR DISPLAY ONLY**, at every magnitude, identically on the phone and on the Watch, and its relative-age label reads "just now". There is no second negative-age classification bound anywhere in this document and no display tier that fails closed on a backward clock. The one label exception is stated below and changes no tier.
- A negative age NEVER arms the Alert Floor. Alertability is a separate, stricter predicate owned by 5.4 FR-72 — forward-skew tolerance exactly 60,000 ms, plus the backward-clock high-water-mark suppression — and this display classifier must never be substituted for it (SI-5). Pinned pair: age −120,000 ms displays Fresh on both targets and is not alertable on either.
- Every other section conforms to the two rules above by cross-reference to this FR and states no classification threshold of its own.
- Exactly one adjacent bound survives elsewhere and it classifies nothing: the Watch's own clock-trust guard (5.7 FR-123). A Watch clock that has run backward by more than 60,000 ms — the same skew tolerance 5.4 FR-72 already uses, not a second number — is untrustworthy, so the wrist replaces the relative-age LABEL with "unknown time" and resolves the Coverage Claim to not-reported-recently. That guard is a statement about the WATCH's clock, not about the reading: it changes no Freshness Tier (the reading is still Fresh at every magnitude), withholds no value, and arms nothing. This label carve-out is the only exception to the "just now" rule above and exists nowhere else.
- Threshold construction validates `1 ≤ staleAfter < tooStaleAfter` via a throwing or failable initializer and never a `precondition`, so an invalid configuration cannot trap the process during a background wake (SI-2).
- The classifier, its thresholds and the relative-age label live in the one shared safety module that BOTH the app and the Watch app link (NFR-4), so no second definition can exist (SI-4).
- A debug-only compressed policy (Stale at 20 s, Too Stale at 45 s) exists behind a toggle hard-gated so it is unreachable in a TestFlight or Release build.

#### FR-50: Wall-clock freshness re-evaluation

The app re-evaluates Freshness Tier on a wall-clock timer independent of any new data arriving, so a dead sensor degrades on screen on its own. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Tick interval = staleAfter ÷ 4, clamped to [2,000 ms, 30,000 ms]. CGM policy → 30 s; Pump policy → 30 s; debug-fast policy → 5 s.
- With the app open and no new Glucose Reading, a Fresh hero becomes Stale within one tick of the 6-minute boundary and Too Stale within one tick of the 15-minute boundary.
- The age caption grows monotonically with no new data.
- The first tick fires after the interval, so the initial render uses the composition-time clock; a new timestamp restarts the ticker's phase.
- The ticker suspends while the view is off screen and resumes with a recomputed age on return — it never resumes with a cached tier.

#### FR-51: Staleness badge

The app renders a staleness badge next to any value whose Freshness Tier is not Fresh. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Fresh renders nothing at all — a fully Fresh screen contains zero staleness-badge elements, and this is an assertable test invariant.
- Stale renders the text "Stale" in amber; Too Stale renders the text "Too old" in grey. Copy is verbatim.
- The badge background is its own colour at 0.15 opacity with a 4pt corner radius and 6pt horizontal / 2pt vertical padding.
- Badges attach independently to the hero glucose value and to each of the four Pump secondary metrics, each reflecting its own tier.

#### FR-52: Trend chart base rendering

Any user sees a trend chart on Home rendering Glucose Readings on a Y axis that defaults to 40–300 mg/dL and expands to include every reading it draws. Realizes UJ-1. Upholds SI-2, SI-3.

**Consequences (testable):**
- **This FR owns the Y-axis rule for every graph surface in the product** — the Home card, the chart detail view, the wrist sparkline, the full-screen Watch app graph and the iPhone widgets. FR-133 cross-references this rule and defines no second clamp.
- The axis DEFAULTS to 40–300 mg/dL and EXPANDS, never pins: the rendered lower bound is `min(40, lowest value in the visible window)` and the upper bound is `max(300, highest value in the visible window)`, each further expanded to include any Alert Threshold the chart draws a grid line for, so no grid line falls outside the plot. Because every stored value is inside the Glucose Validity Bound (SI-2), the resolved axis can never exceed 20–500.
- No reading is ever pinned to an axis boundary. Every dot's y position is computed from its true value against the resolved axis: a 35 mg/dL reading draws below the 40 line, not on it. Pinning would place a valid, in-bound reading at a false height — the Android display defect this rule closes — and is a defect here.
- Cases pinned by test: a window whose values all lie in 40–300 resolves to exactly 40–300; a window containing 35 resolves to 35–300; a window containing 420 resolves to 40–420; a window containing both resolves to 35–420; an urgent high of 400 with no reading above 300 resolves to 40–400. The axis is recomputed from the VISIBLE window, so a zoom or pan in the detail view (FR-55) re-resolves it.
- Chart geometry is always computed in mg/dL; only the rendered label strings convert.
- A translucent in-range band spans y(high) to y(low) at 0.08 opacity across the full plot width.
- Dashed grid lines (8/8 dash) at the low, high and urgent-high Target Range values at 0.3 opacity; Y-axis labels only at those same three values, converted to the display unit, right-aligned 3pt left of the plot area. There are no axis end labels at the resolved bounds.
- Glucose is drawn as unconnected filled dots of 3pt radius, coloured from the raw stored mg/dL value (FR-47).
- Plot insets: 36pt leading; 32pt trailing when any IOB series is loaded, else 8pt; 8pt top; 24pt bottom. Home renders in a card at a fixed 280pt plot height; detail mode fills available height.
- Drawing aborts safely when the visible span is zero or the plot area has a non-positive width or height — no division by zero, no crash.
- With no Glucose Readings the chart renders a centred "No glucose readings yet" line in a container of the same height.
- Home mode shows a header row with the title "Glucose Trend" and a 48pt expand control.

#### FR-53: Chart draw order, overlays and legend

The app draws chart layers in a fixed back-to-front order so no overlay can obscure a Glucose Reading. Realizes UJ-1.

**Consequences (testable):**
- Draw order, back to front: (1) target-range band, (2) threshold grid lines, (3) Y-axis labels, (4) time-axis labels, (5) sleep/exercise mode bands, (6) stepped basal area, (7) IOB area and line, (8) bolus markers, (9) glucose dots. Glucose dots are always last.
- Mode bands render full plot height at 0.06 opacity, only for basal segments whose activity mode is sleep or exercise.
- The basal stepped area occupies the bottom 25% of plot height, anchored at the plot bottom, with the rate scale maximum clamped to [0.1, 15.0] U/hr; each segment runs to the next reading's timestamp or to the window end; fills at 0.15 opacity, top edges at 0.6, vertical step lines at 0.4.
- The IOB overlay requires at least 2 IOB points and renders on an independent full-height secondary scale whose maximum is floored at 1 U; area at 0.06 opacity, line at 0.4, with right-hand labels showing the maximum as `%.1fu` and `0u`.
- Bolus markers render as diamonds of 4pt radius with a dashed (4/4) leader line to the plot bottom; markers closer than 20pt stagger downward in 18pt steps from a 16pt base offset, capped at `floor((0.25 × plotHeight) / 18)` levels (minimum 1) so clustered markers can never overflow into the glucose area. Marker labels clamp to a non-negative y.
- The legend lists only series actually present in the loaded data; a chart with no basal data shows no basal legend entries, and a chart with no IOB data shows no IOB entry.
- Only completed deliveries are drawn as bolus markers; automated micro-boluses excluded from bolus totals are likewise excluded from marker totals (SI-7).

**Out of Scope:**
- Bolus category derivation, category labels and the Bolus-category provider Capability (5.5).

#### FR-54: Chart time-axis labels and tick counts

The app selects the time-axis label format and tick count from the visible span. Realizes UJ-1.

**Consequences (testable):**
- Label format by visible hours: ≤ 6 → "h:mm"; ≤ 48 → "ha"; ≤ 168 → "EEE"; else "M/d", all in the device's current time zone.
- Tick count by visible hours: ≤ 3 → 3; ≤ 6 → 3; ≤ 12 → 4; ≤ 24 → 4; ≤ 72 → 3; ≤ 168 → 7; ≤ 336 → 7; else 6. Ticks are drawn inclusively from 0 through the tick count, yielding tickCount + 1 labels evenly spaced and centred under their x position, 4pt below the plot area.
- Label formats respond to zoom in the detail view, because the format is chosen from the visible span rather than the selected period.

#### FR-55: Chart detail interaction

Any user can expand the chart from Home into a detail view supporting pinch-zoom, pan, double-tap reset and tap-to-inspect. Realizes UJ-1.

**Consequences (testable):**
- Zoom clamps the visible span to [15 minutes, the full selected period] — the user can never see less than 15 minutes nor more than the selected period.
- Pan clamps the viewport centre so the window cannot extend before the period start or past "now". A zero-width plot aborts the pan rather than dividing by zero.
- Double-tap resets the viewport to the full period and dismisses the tooltip.
- A single tap selects the nearest Glucose Reading by timestamp, accepted only when the reading is within 3% of the visible span of the tap, clamped to [60 s, 300 s]; otherwise the tooltip is dismissed.
- The tooltip shows the value with its unit label, coloured by severity, and the local time in "h:mm a"; its position is clamped to remain inside the plot area.
- Any zoom, pan or drag gesture dismisses an open tooltip first.
- Home mode attaches no gesture recognisers and always draws the full [now − period, now] window.

#### FR-56: Chart detail landscape presentation

The chart detail view presents in landscape and restores the previous orientation posture on exit. Realizes UJ-1.

**Consequences (testable):**
- Entering the detail view requests landscape; leaving it restores the prior supported-orientation mask on every exit path, including a back swipe and an app backgrounding while the view is presented.
- If the window scene is unavailable, the app logs and continues in the current orientation rather than crashing or blocking presentation.
- The chart remains fully usable (all gestures, tooltip, period chips) if the orientation request is not honoured.
- [ASSUMPTION: this behaviour targets iPhone; on iPad the orientation request is not honoured the same way and the detail chart simply renders in the window's current orientation.]

#### FR-57: Five independent period selections

Any user can select an analysis period independently on the chart, Time in Range, CGM Stats, Insulin Summary and Recent Boluses, with the choice shared between a card and its detail screen. Realizes UJ-1.

**Consequences (testable):**
- Five independent selections exist. Chart default is 3H; the other four default to 24H.
- The Home chart card offers 3H, 6H, 12H, 24H; the chart detail view offers the full set 3H, 6H, 12H, 24H, 3D, 7D, 14D, 30D. The chart selection is one value shared between the two, so a period chosen in the detail view persists back on Home.
- Time in Range and CGM Stats use rolling now-minus-N-hours windows. Insulin Summary and Recent Boluses use day-boundary-aligned windows anchored on a configurable day-boundary hour validated to 0–23, rolling back one day when "now" precedes today's boundary. The same "24H" label therefore covers different spans on different cards; this is preserved deliberately.
- Available periods are filtered by the user's local retention setting; a selection outside the available set falls back to the first available period.
- The CGM Stats card additionally pushes its corrected selection back into shared state; the other cards fall back for display only without mutating shared state.
- The window's start instant is captured on (re)subscription rather than continuously, and re-anchors after the observation teardown grace elapses and the screen is revisited.

**Out of Scope:**
- Retention enforcement, row caps and observation lifetime mechanics (5.8).
- Insulin Summary and Recent Boluses card content (5.5).

#### FR-58: Time in Range

Any user sees the distribution of their Glucose Readings across five clinical buckets for the selected period. Realizes UJ-1. Upholds SI-2, SI-11.

**Consequences (testable):**
- **Time in Range buckets on the Target Range, not on Alert Thresholds.** These are separate four-value sets with separate stores (Glossary). Bucketing on the alarm set makes iOS report a different TIR percentage than Android for any user whose two sets differ — and TIR is a number people take to their care team. A test configures the two sets to different values and asserts TIR follows the Target Range.
- Bucket counts are computed by a database aggregate, not in application code, over rows filtered to the Glucose Validity Bound of 20–500 mg/dL. A Backend-supplied Safety Limit may narrow that filter but never widen it (SI-11).
- Bucket comparisons: `< urgent low`; `≥ urgent low AND < low`; `≥ low AND ≤ high`; `> high AND ≤ urgent high`; `> urgent high`. A value exactly at `low` or `high` counts in-range, which deliberately differs from the severity banding in FR-47.
- Percentages are count × 100 ÷ total, all zero when total is zero.
- The bar is a 24pt-tall five-segment stack clipped to a 12pt corner radius over #334155, in bucket order urgent low / low / in range / high / urgent high. The last non-zero segment absorbs all rounding so the segments always fill the bar exactly. Zero-percent buckets draw nothing.
- Percent formatting: ≤ 0 → "0%"; < 0.5 → "<1%"; ≥ 99.5 and < 100 → ">99%"; else zero decimals.
- A quality label renders only when data exists: ≥ 70% in range → "Excellent" green; ≥ 50% → "Good" yellow; else "Needs Improvement" red.
- The two-row legend labels bucket boundaries in the display unit; the footer reads "Target: \<low\>-\<high\> \<unit label\>" in the display unit.
- Empty state: "No glucose readings for this period".
- An internally inconsistent aggregate (percentages outside 0–100, or a sum more than 0.5 away from 100 when not all-zero) is rejected via a failable initializer, logged, and rendered as the empty state — it never traps the process (SI-2).

#### FR-59: CGM statistics

Any user sees mean, variability and coverage statistics for their Glucose Readings over the selected period. Realizes UJ-1. Upholds SI-3.

**Consequences (testable):**
- Input is filtered to the Glucose Validity Bound of 20–500 mg/dL; with nothing valid remaining the card renders "No glucose readings for this period".
- Standard deviation uses the SAMPLE denominator: n−1 when n > 1, else 1.
- CV% = (standard deviation ÷ mean) × 100, or 0 when the mean is ≤ 0.
- GMI = 3.31 + 0.02392 × mean, computed from the RAW mg/dL mean and never unit-converted, in either display unit. CV% is likewise never converted.
- CGM-active percentage = valid readings × 100 ÷ (period hours × 12), clamped to 0–100, and 100 when period hours ≤ 0.
- Six statistics render in two rows of three: Mean Glucose (converted to the display unit, with the unit label), Std Dev (converted through the spread path, with the unit label as subtitle), CV% (≤ 36 "Stable" green, ≤ 50 "Moderate" yellow, else "High" red), GMI (subtitle "est. A1C"), CGM Active (≥ 70 "Good" green, ≥ 50 "Fair" yellow, else "Low" red), and the valid reading count.
- Available periods on this card are restricted to 24H, 3D and 7D, further filtered by retention; 14D and 30D are unreachable here even at 30-day retention.

**Out of Scope:**
- Deriving the expected reading cadence from the Driver rather than assuming 12 per hour (see Notes).

#### FR-60: Display-boundary unit rendering and numeric formatting

The app renders glucose values in the user's chosen display unit at the display boundary only, and formats every number on the dashboard identically regardless of device locale. Upholds SI-3, SI-4.

**Consequences (testable):**
- The complete set of dashboard surfaces that convert: hero value and unit label, chart Y-axis labels, chart tooltip value, Time in Range bucket-boundary labels and target caption, and CGM-stats mean and standard deviation. Nothing else on the dashboard converts.
- Never converted: Target Range values in storage or on the wire, all threshold comparisons, chart geometry, Time in Range bucket counts, CV%, GMI, and insulin units.
- Conversion uses the Conversion Factor 18.0156 exactly once, from the most precise mg/dL source, rounded last to one decimal for mmol/L. No second constant exists anywhere in the repository (SI-4).
- **This FR owns the pinned mg/dL→mmol/L anchor table**, held once as a test fixture in the shared safety module (NFR-4) and shared with the Watch app and the Backend: 20→1.1, 54→3.0, 70→3.9, 99→5.5, 100→5.6, 120→6.7, 180→10.0, 250→13.9, 400→22.2, 500→27.8. The Glucose Validity Bound anchors 20→1.1 and 500→27.8 are part of the table, not optional. Every other surface — the wrist and widget fixture in 5.7 FR-116, the Units control in 5.9 FR-175 — cites this table and restates no subset of it; a second, shorter copy is exactly the drift SI-4 exists to prevent.
- Spreads (standard deviations, differences) convert through a distinct offset-free path and always render with one decimal in either unit; the value converter is never used for a spread.
- Every number the dashboard displays uses a dot decimal separator and half-up rounding regardless of device locale, so no screen mixes separators. Pinned ties: 12.5% → "13%", a mean of 100.5 → "101", 0.125 U → "0.13". This is a deliberate divergence from Android, which forces US formatting for glucose but device-locale formatting for IOB, basal, battery, reservoir, TIR percentages, CV% and GMI.
- The app and the Watch app produce byte-identical strings for the same stored mg/dL value, enforced by linking the same formatting module rather than by a test convention.

**Out of Scope:**
- The unit setting itself, its persistence and its propagation to the Watch app and widgets (5.8, 5.9).

#### FR-61: Single injectable time source

Every "now" the dashboard consumes comes from one injectable clock rather than a direct system-time read. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Freshness classification, the freshness ticker's sampling, chart window boundaries, the chart's frozen render-time "now", day-boundary alignment, the basal integral's final-segment extension and the total-daily-dose denominator all read the same injected clock.
- No dashboard code path calls a system time function directly; this is enforced by a lint or grep rule that runs inside the `Static Analysis Gate` Required Check (FR-197), not as a new gate.
- The entire time-dependent surface — every Freshness Tier transition, every period boundary, every day-boundary roll-back — is exercisable deterministically in unit and UI tests without changing the host clock, because the iOS Simulator cannot have its clock changed independently of the host Mac.
- A Simulated Driver can drive stale, future-dated and clock-rewound values through the same clock so every dashboard state is reachable without a Pump.

#### FR-62: Theme selection

Appearance selection — System / Dark / Light, applied live without a restart, persisted with a fallback to System on an unparseable value, over a fixed palette with no dynamic or system-derived colour, and the calm-amber caution treatment resolving against the forced appearance — is defined once. See FR-175.

**Consequences (testable):**
- The dashboard consumes the resolved appearance and defines nothing of its own. Glucose severity colours do not vary by appearance (FR-47); meal-confidence colours are owned by 5.5 FR-97.

#### FR-63: Navigation, capability-driven tab bar and session banner

Any user navigates through a tab bar whose contents reflect the modes actually available, with detail screens presented as spokes. Realizes UJ-1.

**Consequences (testable):**
- Tabs: Home, Alerts and Settings always; AI Chat only when a Backend is configured. In Backend-optional mode the AI Chat tab is absent rather than present-and-erroring.
- Backend-only destinations remain registered so a restored navigation path or an INTERNAL entry point resolves; when no Backend is configured their bodies redirect to Home rather than presenting an empty guard frame, and the redirect is never left on the back stack.
- Every entry point that routes into the app is internal: a widget, complication or notification tap, travelling the system's own widget/complication URL mechanism, which is not a third-party input surface. The app registers no custom URL scheme that accepts data from another app and exposes no share extension (NFR-22). No routing target accepts a payload from outside the app's own extensions.
- The Backend-configured decision is evaluated live inside each destination body, not captured when the navigation graph is built, so adding or removing a Backend mid-session takes effect immediately.
- Detail screens (chart detail, Time in Range detail, insulin detail, alert history, bolus history, Driver card detail, pairing, meal surfaces, licenses) hide the tab bar and provide a back affordance.
- The start destination depends only on onboarding completion and never on session validity, so an expired or absent session still reaches locally stored Glucose Readings and Pump data offline. It is resolved once, not reactively.
- Session banner: an expired session shows its banner unconditionally; an unauthenticated state shows "Not signed in, tap to sign in" only when a Backend is configured; an initializing, refreshing or authenticated state shows nothing, so no "not signed in" flash occurs at cold start. The banner is tappable and navigates to Settings.
- The session banner is hidden during onboarding; the insecure-HTTP warning banner is not, and renders above all content including onboarding.
- Home, chart detail and bolus history share one dashboard model, so period selections, Target Range and display unit are one state across all three.

#### FR-64: Dashboard legibility under Dynamic Type

Any user can read every dashboard surface at any Dynamic Type size including the accessibility sizes. Realizes UJ-1.

**Consequences (testable):**
- The hero value and its trend glyph remain on one line and are never truncated or clipped at any Dynamic Type size; if the value must be capped to fit, the cap is applied to the numeral scale and the glyph scales with it so both stay visually paired.
- No card's empty-state line, staleness badge, age caption, statistic label or Time in Range legend entry truncates or overlaps at the largest accessibility size; entries reflow rather than clip.
- In-chart labels (axis, tick, marker, tooltip) scale with Dynamic Type up to a bounded maximum, and the chart remains legible with a horizontally scrollable or reflowed legend rather than an overlapping one.
- The five-segment Time in Range bar and the basal/bolus stacked bar keep their fixed heights; only their labels scale.
- Every dashboard screen is verified at the default size, the largest non-accessibility size and the largest accessibility size.

**Out of Scope:**
- VoiceOver descriptions, spoken unit names and accessibility identifiers (5.9).

---

**Feature-specific NFRs:**

- The freshness ticker must not prevent the app from being suspended or measurably affect battery: it suspends when its view is off screen and resumes with a recomputed age, never a cached tier.
- Chart rendering at the 30-day period must remain smooth under pinch-zoom and pan with the maximum retained row count; the chart series row caps (2,000 glucose/IOB/basal points, 500 bolus events) are the performance contract and are enforced by the query layer (5.8).
- Every displayed number routes through one formatting helper; a second formatting path anywhere on the dashboard is a defect.
- Rendering an out-of-bound Glucose Reading is impossible by construction: rows outside the Glucose Validity Bound are dropped at the model boundary and the dashboard falls back to the next valid reading or the no-data state (SI-2). A dropped row is never surfaced as an error row.

**Notes:**

- [NOTE FOR PM] **Parity loss — guaranteed refresh cadence.** Android's foreground service polled the Pump every 15 seconds, which also served as the BLE keep-alive against a ~30 s idle drop. iOS provides no periodic background execution: `BGAppRefreshTask` is opportunistic and budgeted, and Core Bluetooth wakes the app on connect/disconnect and characteristic notifications only, never on a timer. The dashboard therefore cannot guarantee current data while the app is not in the foreground. FR-41 (foreground re-read) plus FR-48/FR-49/FR-50 (honest degradation) are the substitute. Recorded in the Parity Ledger as PL-12.
- [NOTE FOR PM] **Parity loss — chart detail orientation.** iOS has no "sensor landscape" concept and no per-screen orientation property; the geometry request is honoured on iPhone but not on iPad, and the interaction with the user's rotation lock differs from Android's. Recorded in the Parity Ledger as PL-44, whose disclosure need depends on the iPad open question (OQ-22).
- [NOTE FOR PM] **Parity loss — Bluetooth glyph.** There is no system Bluetooth symbol on iOS, and the Bluetooth word and figure marks are Bluetooth SIG trademarks tied to membership and a Declaration ID. A custom glyph set for the six Pump-link states must be shipped. If the marks cannot be used, the status-row glyph vocabulary diverges from the published Android status-icons documentation. Recorded in the Parity Ledger as PL-10, whose disclosure surface is the iOS status-icons page (5.12 FR-237).
- [NOTE FOR PM] **Deliberate divergence — numeric formatting.** FR-60 requires dot-decimal and half-up rounding for EVERY dashboard number. Android forces US formatting only inside its glucose formatter and uses the device locale for IOB, basal, battery, reservoir, TIR percentages, CV% and GMI, so a comma-decimal device today shows "6.7 mmol/L" next to "1,23u". Additionally, Java's `%f` rounds half-up while Foundation's `String(format:)` rounds half-to-even, so a naive port renders 12.5% as "12%" and a mean of 100.5 as "100". This is an intentional improvement over Android, not a defect port. Recorded in the Parity Ledger as PD-12, an intentional divergence.
- [NOTE FOR PM] **Deliberate divergence — one expanding Y axis everywhere.** Android ran two clamps (20/500 on the Wear sparkline, 40/400 on the phone detail view) and pinned out-of-axis readings to the boundary, drawing a valid in-bound reading at a false height. FR-52 replaces both with one rule for every graph surface on the phone and the Watch app: default 40–300, expand to include any reading or drawn threshold, never pin. §7's PD-16 now records the closed defect in those terms, owned by FR-52 and cross-referenced by FR-133, and reaches the phone chart as well as the wrist. Nothing further is owed here.
- [NOTE FOR PM] **Trend-arrow provenance is now owned.** FR-46 states that `cgmTrendIconId` arrives on the HomeScreenMirror response (opcodes 56/57) rather than on the EGV response, that the glyph carries its own timestamp and Freshness Tier, that it renders at the worse of the two tiers, and that every other surface that draws a glyph — including the wrist (5.7 FR-120) — cross-references this FR. §15's OQ-7 records the provenance item as closed and §7 records the divergence as PD-42: Android's 15-second foreground poll kept the two transactions close and iOS cannot, so the glyph can legitimately be older than the value it sits beside. Nothing further is owed here.
- [NOTE FOR PM] **BGM source now has a consuming surface.** FR-39 and FR-46 place a blood-glucose-meter reading on the contributing Driver's own card only, labelled with its meter name, and exclude it from the hero, the chart glucose series, Time in Range, CGM statistics and the Alert Floor. This matches Android, where the only BGM consumer was the demo runtime plugin's own card (Android's term for what this product calls a Driver). §7 records it as PD-43 — parity, not an addition. Nothing further is owed here.
- [NOTE FOR PM] **Preserved inconsistency.** The severity banding (FR-47) treats a value exactly at `low` as Low and exactly at `high` as High, while the Time in Range aggregate (FR-58) counts both as in-range. Both are pinned by test. This is a genuine inconsistency in Android; it is preserved for parity and recorded as §7's PD-14 rather than reconciled silently.
- [NOTE FOR PM] **Light-theme contrast.** Green #22C55E and Yellow #EAB308 on a white surface fall short of WCAG AA for small text, affecting the Time in Range legend entries, the CGM-stats assessment subtitles and the age caption. The hues are a cross-surface semantic contract with the Watch app and the Backend and must not change (FR-47); within the appearance owned by FR-175, darken only the TEXT variants in the Light appearance, never a fill, dot or badge.
- [NOTE FOR PM] **Glyph coverage risk.** U+21C8 and U+21CA (the double arrows) may not be covered by the system font at 40pt bold, silently falling back to a different face on the single most-read element in the app. If the fallback is visible, ship a custom glyph pair while keeping the Unicode string as the data contract so the app and the Watch app remain string-identical.
- [NOTE FOR PM] **App Review sensitivity.** Shipping Tandem, Medtronic and Nightscout brand marks (FR-45) is a nominative-use decision inherited from Android; Apple reviews third-party trademarks less predictably than Google Play. Keeping all marks behind one asset lookup means the whole set can be disabled with a single change if review demands it.
- [NOTE FOR PM] **The dashboard cannot substitute for a sensor-validity gate, and no longer has to.** Tandem's `egvStatusId` (usable only in 1..3; 0 invalid, 4 and above unavailable) is the sensor's own claim that a value is real, and it is independent of the Glucose Validity Bound. A warm-up or error sentinel that lands inside 20–500 is indistinguishable from a real reading at the display layer: it would render at hero scale, in a severity colour, Fresh, and it would be plotted. No display rule in this section can recover from its absence. The gate belongs at Driver decode time and 5.2 FR-32 now requires it, with all five status cases pinned by test and Trace-Replay fixtures (5.2 FR-36). This section remains a consumer of that decision, not its owner, and adds no display-layer substitute.
- **Open question (OQ-19) — CGM-active cadence.** FR-59 assumes exactly 12 Glucose Readings per hour, as Android does. A source with a different cadence misreports coverage. Should the expected cadence be declared by the Driver's glucose-source Capability instead of hard-coded?
- **Open question (OQ-20) — display banding from defaults.** SI-5 forbids the Alert Floor from firing on thresholds neither the user nor their Backend set. FR-47's severity banding currently colours from the default Alert Threshold set (55/70/180/250) when nothing has been set. Confirm that colouring from defaults is acceptable while alerting from them is not, and that the two are visibly distinguishable to the user.
- **Open question (OQ-21) — Dynamic Type and the 64pt hero.** Android has no equivalent, so there is no reference behaviour. Does the hero numeral scale with Dynamic Type at all, or stay fixed while only the surrounding text scales?
- **Open question (OQ-22) — iPad.** FR-56 assumes iPhone. Is iPad a supported target for this release at all, and if so what is the expected chart-detail behaviour?


### 5.4 Alerting and the Coverage Contract

**Description:**

There are exactly two sources of alerts, and they are mutually exclusive by construction. The Backend is one: it evaluates trajectory, prediction horizons and IOB, and pushes alerts to the app while the app is running. The Alert Floor is the other: threshold-only, computed on the iPhone from the most recent Glucose Reading the Pump gave us, armed only while Backend alerting is degraded, and — critically — the whole of alerting in Backend-optional mode. The Alert Floor is the irreducible safety net; it is not a fallback bolted onto a Backend-dependent product, it is the product for any user who never stands up a Backend.

The Android app hosts this in a foreground service that polls every 15 seconds forever, holds an SSE stream open indefinitely, mutates an ongoing notification with the coverage text, and bypasses Do Not Disturb by declaring a normal install-time permission. iOS grants none of that. Four things are lost outright and are stated here rather than hidden:

1. **Audibility cannot be guaranteed.** Do Not Disturb / Focus / silent-switch override on iOS requires the Critical Alerts entitlement, which Apple grants per Team ID after manual review — structurally unobtainable under fork-and-build, where every Builder has their own Team ID. Urgent lows therefore ship on `.timeSensitive`, which breaks through Focus when the user permits it and escapes the Notification Summary, but does **not** override the ring/silent switch and does **not** raise the volume. Worse, no public API reports the switch position or the ringer volume, so the app cannot even detect that it was silenced. Android's alarm-volume boost-and-restore (`STREAM_ALARM` to max on a low, restored on acknowledge) has no analog and is deleted, not ported.
2. **Backend-generated alerts do not reach a suspended or terminated app.** APNs is deferred (FR-157, 5.8). While the app is not running, the Backend's stream is not connected, the Coverage Claim degrades, and the Alert Floor is the only thing that can alarm.
3. **Nothing runs after a reboot until the user unlocks the phone once, and a force-quit from the app switcher disables all background relaunch** — including Core Bluetooth state restoration — until the user manually reopens the app. Both are invisible to the app while they are happening. This is the single most common way an iOS diabetes client goes silent, and it gets explicit product copy.
4. **There is no ongoing, non-dismissible notification whose existence proves the monitor is alive.** Android's pump foreground notification is exactly that surface; iOS has no equivalent.

What replaces (4) is the heart of this section: the **Coverage Claim** becomes *declarative*. Every claim the app emits carries an explicit expiry instant, and every surface that renders it decays it at that instant **with no code running** — a widget timeline entry scheduled at the expiry, a Live Activity `staleDate`, the Watch app's own local decay, and a scheduled proactive notification that fires if the app has not run by then. Silence itself becomes the alarm. There is exactly one selector producing the claim and exactly one expiry number feeding all four decay mechanisms; forking that pipeline per surface is the fastest route back to the lethal lie SI-6 exists to prevent.

Everything that is a *decision* in the Android Alert Floor ports byte-identically: the four arming gates and their order, urgent-band-first classification with inclusive boundaries, the 6-minute Fresh window measured against the reading's **own sensor timestamp**, the 60-second wall-clock rewind guard and the symmetric 60-second forward-skew tolerance, the 30-minute cooldown, the ack-gated episode guard against Backend alert history with its fail-toward-alerting exception handling, the never-alarm-from-defaults gate, and the never-persist rule for on-device alarms. What changes is only the execution model: the Alert Floor evaluates when Core Bluetooth wakes the app, not on a 15-second timer. Because the Fresh window is 6 minutes, a connect → poll → idle-disconnect → reconnect cycle stays comfortably inside it — but that is a measurement, not an assumption, and if the achievable background cadence approaches 6 minutes that is a coverage fact to surface, not a constant to widen.

Sam (UJ-1) reads a Coverage Claim on the wrist that the phone computed and the Watch merely decays. Priya (UJ-2) is woken at 03:10 by an urgent low that repeats on a bounded ladder until she acknowledges it from the wrist notification the Watch itself scheduled (FR-128) — and that acknowledgement silences the phone, marks locally first, and survives the Backend being unreachable. Dana (UJ-4), whose t:slim X2 pairing broke, does not get a quiet screen: she gets `PUMP_DISCONNECTED` as the Not-Watching Reason, in plain words, on every surface.

Alert Thresholds have provenance. In Backend-optional mode the user sets all four on-device and they are the device's, surviving sign-out. When a Backend is configured the four are read-only in the app, edited in the web app, and adopted within the hour whenever the app gets any opportunity to run; an invalid Backend response is dropped whole and silently, never clamped, leaving the last good set standing. Built-in defaults (55/70/180/250 mg/dL) exist only so the classifier has values to compute the Watch relay's state with — they were chosen by no user and can never arm an alarm (SI-5).

**Functional Requirements:**

#### FR-65: Alert type vocabulary and delivery tiering

The app can deliver an audible alert for urgent low, low, high, urgent high and IOB conditions using the exact Backend wire vocabulary, tolerating alert types it does not recognize by delivering them at the informational tier rather than dropping them. Realizes UJ-2. Upholds SI-12.

**Consequences (testable):**
- The recognized alert-type strings are exactly `low_urgent`, `low_warning`, `high_warning`, `high_urgent`, `iob_warning`; the recognized severities are exactly `warning`, `urgent`, `emergency`. `no_data` is a Backend-originated caregiver type that is not in the low or high sets.
- The low set is exactly {`low_urgent`, `low_warning`} and the high set exactly {`high_warning`, `high_urgent`}; both sets have one definition shared by delivery tiering, the Alert Floor classifier and the Watch relay.
- The alert type is decoded as an open string type, never a closed enum: an unrecognized type decodes successfully and is delivered at the informational tier. A missing consumed field (`alert_type`, `severity`, `message`, `current_value`, `timestamp`) fails the decode loudly (SI-12).
- Low-set and high-set alerts are delivered at the interrupting tier (FR-66); `iob_warning`, `no_data` and every unrecognized type are delivered at the informational tier (`.active`, default sound, no Focus break-through).
- A test pins that the Backend alert vocabulary and the Watch alert vocabulary (`urgent_low` / `low` / `high` / `urgent_high`) are distinct types that cannot be assigned to one another, and that classification never emits the Watch vocabulary.

**Out of Scope:**
- The transport that carries Backend alerts to the app (FR-157, 5.8).

#### FR-66: Interruption level and the audibility honesty statement

The app can deliver urgent low, low, high and urgent high alerts at `UNNotificationInterruptionLevel.timeSensitive`, auto-upgrading to `.critical` at runtime whenever the Critical Alerts entitlement and user authorization are both present, and states plainly wherever it makes a coverage promise that it cannot guarantee the alarm is audible. Realizes UJ-2. Upholds SI-6.

**Consequences (testable):**
- Interruption level is resolved at post time from `UNNotificationSettings.criticalAlertSetting`: `.enabled` → `.critical`; anything else → `.timeSensitive`. No build flag, no rebuild, no code path difference beyond that one read.
- The app never requests provisional authorization; provisional delivery is quiet and would silently disable every alarm.
- Full notification settings (`authorizationStatus`, `alertSetting`, `soundSetting`, `lockScreenSetting`, `criticalAlertSetting`, `timeSensitiveSetting`, `scheduledDeliverySetting`) are re-read on every foreground and cached; the cached value feeds the Coverage Claim (FR-83).
- The app ships copy, in-app and in the Coverage Claim detail, stating that without Critical Alerts an alarm can be silenced by the ring/silent switch and that the app cannot detect this. That copy is present in the default (`.timeSensitive`) configuration and suppressed only when `.critical` is active.
- No code attempts to set output, ringer or alarm volume, and no code reads or infers the silent-switch position.

**Out of Scope:**
- Requesting notification authorization (FR-165) and the Settings card that reports every suppressing condition (FR-171).
- Custom vibration waveforms — no public API attaches one to a delivered notification on iOS or watchOS.

#### FR-67: Per-severity alert sound selection

The user can choose a distinct alert sound per severity tier from a curated set bundled in the app, and select silence for the informational tier only. Realizes UJ-2.

**Consequences (testable):**
- Three independently configurable tiers: low, high, informational. Each stores a sound selection and a display name. This FR is the single definition of the sound model; the picker surface that exposes it — its rows, labels, accessibility identifiers and in-place preview — is FR-170.
- Every selectable sound is a file shipped inside the app bundle, ≤ 30 s, in a format iOS accepts for a notification sound. The set is closed at build time: no system ringtone, no system sound library, no user content URI and no arbitrary file path is selectable. This is a **forced loss**, not a preference — Android uses the system `RingtoneManager` picker over the whole system sound library, and iOS exposes no API to enumerate, preview or select from it (§7).
- A bundled set plus "Default" is offered for every tier. "Silent" is offered for the informational tier only and for no other; selecting nothing for the low or high tier resets that tier to its default rather than silencing it. The explicit Silent option is real Android parity, not an iOS invention.
- The low-tier set is deliberately alarm-like and distinct from the notification-like high and informational sets.
- The informational tier's sound selection is hidden entirely in Backend-optional mode (that tier can never fire without a Backend).
- The sound is a per-notification property resolved at post time. There is no channel to delete and recreate and no version suffix in any identifier.
- No sound selection, and no other code path, sets output, ringer or alarm volume, or reads or infers the silent-switch position (FR-66).
- Settings copy states that the chosen sound is an iPhone-only feature: the wrist alert is scheduled on the Watch (FR-128) and plays watchOS's own alert sound and haptic, which the app cannot override.

**Out of Scope:**
- **User-imported alert audio and any transcode-to-CAF import path — deferred, not deleted-by-oversight.** An import adds a transcode failure mode to an alarm path whose failure mode is silence. **Revisit condition:** the bundled set has shipped through one tagged release AND the import path can be validated end to end — import, transcode, delivery of a real low alarm — at Validation Tier 4, on-device hardware (§9), so a failed transcode can never silently substitute the system default on a low.

#### FR-68: Foreground presentation

The app presents an alert visibly and audibly while it is in the foreground; a foreground app never silently swallows an urgent low. Upholds SI-6.

**Consequences (testable):**
- The notification-center delegate's will-present handler returns banner, sound and list presentation options for every low-set and high-set alert, regardless of which screen is showing.
- Informational-tier alerts also present in the foreground, using their configured sound (which may be Silent).
- A test asserts that no code path returns an empty presentation option set for a low-set alert type.

#### FR-69: Alert content, title format, and caregiver rendering

The app renders an alert title and body from the alert's severity, type, value, and optional patient name, in the user's display unit, and never renders a glucose value in the title of a data-gap alert. Realizes UJ-1. Upholds SI-3.

**Consequences (testable):**
- Title prefix by severity: `emergency` → "EMERGENCY", `urgent` → "URGENT", `warning` → "Warning", anything else → "Info".
- When a patient name is present the title carries the suffix `" - <patientName>"`; the alert list row shows the patient name before the timestamp.
- For alert type `no_data` the title is exactly `"<prefix>: No CGM data<suffix>"` — the value is never rendered, because a data-gap alert's value is only a last-known reading and would fake a live glucose during the very blackout being reported. The gap age and last-known value stay in the Backend-authored body.
- For every other type the title is `"<prefix>: <value with unit label><suffix>"`, e.g. `EMERGENCY: 320 mg/dL - Alice` or `EMERGENCY: 17.8 mmol/L`.
- The value is stored and transmitted as canonical mg/dL and converted to mmol/L exactly once at the display boundary using the Conversion Factor 18.0156, rounded last (SI-3).
- The body is the alert message verbatim; the notification's thread identifier groups all alerts together.
- No client-side caregiver escalation, fan-out or third-party messaging exists. Onboarding and Coverage Claim copy attribute caregiver escalation to the Backend.

#### FR-70: Notification slot identity and duplicate suppression

The app replaces rather than stacks alerts of the same type for the same patient, and suppresses a repeat notification for an alert identity it has already delivered. Upholds SI-6.

**Consequences (testable):**
- The notification request identifier is exactly the string `"<alertType>|<patientName or empty>"`. No hashing is used — Swift's `hashValue` is per-launch seeded and unstable across runs.
- Re-posting the same identifier replaces the delivered notification. A Backend re-delivery therefore replaces an on-device Alert Floor notification of the same type rather than duplicating it.
- Two patients with the same alert type occupy distinct identifiers and do not replace each other.
- A separate suppression record keyed on the Backend-assigned alert identifier admits each identifier exactly once; the record is capped at 200 entries with oldest-first eviction, and an acknowledgement removes that identifier so a later re-issue can notify again.
- On launch, the suppression record is seeded from the currently delivered notifications so a process restart does not re-notify an alert that is still posted on screen.

#### FR-71: The Alert Floor — on-device alarming with no Backend

The app raises audible low and high alarms computed on the iPhone from the most recent Glucose Reading, with no Backend configured at all, threshold-only, and states that provenance in the alert body. Realizes UJ-2. Upholds SI-5, SI-1.

**Consequences (testable):**
- The Alert Floor performs no trajectory projection, no prediction horizon and no IOB escalation. It never produces an `iob_warning` or `no_data` alert and never produces a caregiver alert (patient name is always absent).
- Classification checks urgent bands first: value ≤ urgent low → `low_urgent`; value ≥ urgent high → `high_urgent`; value ≤ low → `low_warning`; value ≥ high → `high_warning`; otherwise no alert. Boundaries are inclusive at both urgent and warning edges. With thresholds 55/70/180/250: 55 → `low_urgent`, 56 → `low_warning`, 70 → `low_warning`, 71 → none, 179 → none, 180 → `high_warning`, 249 → `high_warning`, 250 → `high_urgent`.
- Gate order is fixed and tested: (1) wall-clock rewind (FR-72) — suppress evaluation entirely, including episode recovery; (2) episode re-arm for acknowledged types other than the current one; (3) no classification → return; (4) Backend alerting is not degraded — by the evidence-based definition in FR-83, which requires Backend-side glucose recency and not merely a connected stream → return; (5) the shared data-trust bound (FR-72, FR-73); (6) notification capability, checked **before** the cooldown is stamped so a capability granted a minute later still gets its alarm; (7) per-type cooldown (FR-74); (8) episode guard against Backend history (FR-75); (9) fire.
- **"Backend alerting is degraded" requires positive evidence that the Backend can actually alarm for this user, not merely that a socket is open.** It is degraded when ANY of: network is not reachable; the **Backend** alert stream is not connected; OR **the Backend has not confirmed a Glucose Reading for this account newer than the Fresh boundary.** Deliberately pessimistic on disagreement, and pessimistic when the third input is unavailable — an app that cannot determine Backend-side data recency treats alerting as degraded and stays armed.
- **Why the third input exists (SI-5, SI-6).** The app never uploads Glucose Readings (FR-140), so the **Backend** only holds glucose if a Backend-side source supplies it. A user who configures a **Backend** for AI Chat, or who leaves the Nightscout source off (FR-153 defaults it off), has a healthy alert stream over an account with no glucose in it. Without this input the app would stand its own **Alert Floor** down and report **Backend Active** while nothing anywhere was watching — a silent missed urgent low with every subsystem behaving exactly as specified. A test pins that scenario: **Backend** reachable, stream connected, no Backend-side glucose source → claim is **Floor Watching**, the Alert Floor is armed, and an urgent low alarms locally.
- In Backend-optional mode degradation is permanently true, so the Alert Floor is permanently armed.
- The alert body is exactly `"<headline> <value with unit> — computed on your phone from your last sensor reading. Threshold-only, no prediction. Not a replacement for your CGM app."` with headline ∈ {"Urgent low glucose", "Low glucose", "High glucose", "Urgent high glucose"}, fallback "Glucose alert". (The literal string says "sensor reading" deliberately: that is the plain-language wording the product shows people for the Glucose Reading. The string is pinned by test and is not to be re-worded to the Glossary term.)
- Alert Floor alerts are never written to the Backend alert history store (FR-87). Their synthetic identifier is `"local-floor:<alertType>:<sensor timestamp in ms>"` and it is never sent to a Backend acknowledge endpoint.
- No Alert Floor code path issues any device command, in any Driver, behind any flag (SI-1).

#### FR-72: Freshness and clock-trust gate

The app never alarms from a Glucose Reading that is not Fresh against its **own sensor timestamp**, never from a reading dated more than 60 seconds in the future, and suppresses all on-device alarming while the device wall clock runs behind the highest time the app has observed. Upholds SI-5, SI-4.

**Consequences (testable):**
- Age is `now − the reading's sensor timestamp`, never poll wall-clock time. A warmup or signal-loss poll can succeed repeatedly while returning the same aged Glucose Reading; that reading must not alarm.
- The Alert Floor requires the strictly Fresh tier. Stale and Too Stale both suppress alarming. The Freshness Tier boundaries themselves, their half-open semantics and the debug-compressed policy are specified once, in FR-49; this FR states no threshold of its own.
- **Alertability is a separate, stricter predicate than display classification, and this FR owns it.** Forward-skew tolerance is exactly 60,000 ms: alertable iff `age ≥ −60,000 && classify(max(age, 0)) == Fresh`. Pinned pairs: age 359,999 ms alertable, 360,000 ms not; age −60,000 ms alertable, −60,001 ms not; under the debug policy 19,999 ms alertable, 20,000 ms not.
- A negative age displays as Fresh at every magnitude (FR-49) and **never** arms the Alert Floor beyond the 60,000 ms forward-skew tolerance above. The display classifier is never substituted for this predicate (SI-5). Pinned pair: age −120,000 ms displays Fresh and is not alertable.
- A monotonic high-water mark of every observed wall-clock time is kept and advanced by every Alert Floor evaluation, every data-trust-bound check and every Coverage Claim recomputation. While `now + 60,000 ms < highWaterMark`, the Alert Floor suppresses evaluation **and** the Coverage Claim reports Not Watching `CLOCK_UNTRUSTED` — never `NO_FRESH_READING`, because the readings are fine and the clock is not.
- **The mark is process-local, is never persisted across launches, and cannot latch.** A forward movement larger than 60,000 ms is treated as a clock CORRECTION — a timezone change, a manual set, an NTP step — and RESETS the mark to the newly observed time rather than raising it beyond reach. Only backward movement suppresses, and suppression clears the moment observed time catches the mark. **Suppression is additionally bounded at 300,000 ms (5 minutes);** past that the mark is reset unconditionally and the app resumes evaluating, because a monitor that has stopped watching indefinitely is a worse outcome than one that trusts a possibly-wrong clock and says so.
- Rationale (SI-5): without a reset path a single forward jump makes every subsequent real time read as a rewind, suppressing the **Alert Floor** for the life of the install while reporting a reason that points the user at their sensor. A test performs a +6-hour jump, then a normal reading, and asserts the Alert Floor evaluates and an urgent low alarms.
- A continuous, sleep-surviving clock reading is paired with each observed wall-clock time as a second rewind detector; disagreement beyond 60,000 ms is a rewind. The residual — a rewind occurring while the process is dead leaves no mark — is documented and fails toward alarming, never toward silence.
- Exactly one implementation of the data-trust bound (rewind check → mark advance → thresholds configured → freshness) exists, in a module both the app and the Watch app link (SI-4). A unit test in `Build & Test` fails if the Alert Floor firing path and the Watch relay path do not call the same function; it is aggregated by the `iOS Gate` Required Check (FR-197, FR-208).
- The Pump-data Freshness Tier policy (IOB, basal, battery, reservoir) is likewise FR-49's, not this FR's. It gates no alarm: the Alert Floor is CGM-only and never alarms from Pump-status age.

#### FR-73: Never alarm from unconfirmed Alert Thresholds

The app never raises an on-device alarm from Alert Thresholds that neither the user nor their Backend explicitly set. Upholds SI-5.

**Consequences (testable):**
- Threshold provenance is one of three states: none (never configured), backend (synced from the Backend), local (set on-device in Backend-optional mode). The Alert Floor is armed only when provenance is backend or local.
- The built-in values 55 / 70 / 180 / 250 mg/dL exist only so the classifier and the Watch relay have values to compute a display state with. With provenance `none`, no alarm fires at any glucose value.
- With provenance `none`, the Coverage Claim resolves to Not Watching with reason `THRESHOLDS_NOT_SYNCED` when a Backend is configured and `THRESHOLDS_NOT_CONFIGURED` otherwise (FR-83).
- For installs that predate an explicit provenance record, absent provenance resolves to backend when a last-sync timestamp is non-zero and to none otherwise, so an upgrading user is never silently disarmed.
- Provenance changes are observed reactively: saving thresholds arms the claim immediately and signing out disarms it immediately, with no polling delay.

#### FR-74: Re-alarm cooldown and episode semantics

The app re-alarms an unacknowledged on-device condition at most once per 30 minutes, re-alarms exactly 30 minutes after an acknowledgement if the condition persists, and alarms immediately as a new episode if the value recovers and re-crosses. Realizes UJ-2. Upholds SI-5.

**Consequences (testable):**
- The cooldown is exactly 1,800,000 ms (30 minutes) per alert type, mirroring the Backend's own 30-minute dedup window.
- Acknowledging an on-device alarm sets that type's last-fired time to the acknowledgement instant and marks the type acknowledged. An acknowledgement means "seen", never "snooze forever" and never "re-alarm on every evaluation".
- A sustained condition that never recovers re-alarms exactly 1,800,000 ms after the acknowledgement. The Alert Floor can never go permanently silent on an ongoing emergency.
- Any subsequently evaluated reading that no longer classifies as an acknowledged type fully re-arms that type (last-fired and acknowledged state both cleared), so a re-cross alarms immediately as a distinct episode even well inside the raw 30-minute window.
- An **unacknowledged** cooldown deliberately does not re-arm on recovery: a glucose hovering across a boundary must not re-alarm while its notification is still on screen.
- Acknowledging one type never clears another type's cooldown.
- Per-type last-fired times and acknowledged types are persisted to storage shared by the app and the Watch app, so a background relaunch after process termination does not re-alarm a low the user already acknowledged.
- This is a recorded, deliberate divergence from the Backend, which re-alerts an acknowledged sustained low on its own evaluation cadence; re-alarming on every evaluation is alarm-spam that trains users to disable notifications.

#### FR-75: Episode guard against Backend alert history

The app does not raise an on-device alarm for a condition the Backend already announced and the user has not yet acknowledged, seeding the suppression window from the Backend alert history. Upholds SI-5.

**Consequences (testable):**
- Before firing, the app queries for the most recent unacknowledged Backend alert of the same type within the last 1,800,000 ms. If one exists, the type's last-fired time is seeded to `min(that alert's timestamp, now)` and no alarm fires.
- The `min(..., now)` clamp is required so a Backend clock running ahead of the phone cannot stretch the silence window beyond 30 minutes.
- A storage error during this query is caught and treated as "no recent Backend alert" — the guard fails **toward** alerting. A broken lookup may cost one duplicate alarm; it may never cost a missed one.
- The alert history store is readable while the device is locked after first unlock, so this query and the acknowledge write in FR-78 succeed on a locked phone (SI-10). A test asserts the store's file protection level is not raised above after-first-unlock.

#### FR-76: Bounded finite re-alarm ladder

The app repeats an unacknowledged urgent alert on a bounded, finite schedule until the user acknowledges it, and stops repeating the instant they do. Realizes UJ-2.

**Consequences (testable):**
- Repeats apply to the urgent tiers (`low_urgent`, `high_urgent`) only. Non-urgent low and high alerts alert once and then update silently; low-set alerts always re-sound on a value update, high-set and informational alerts update at `.passive` with no sound.
- The ladder is exactly 5 repeats at 120-second intervals, ending 10 minutes after the initial alarm. After the ladder ends, only the 30-minute cooldown (FR-74) can produce another alarm. [ASSUMPTION: Android encodes urgency in a custom vibration waveform and an alarm-volume boost, neither of which exists on iOS; a 2-minute × 5 ladder is the chosen temporal substitute and is a tuning parameter, not a ported constant.]
- The total number of scheduled pending notification requests from the ladder never approaches the iOS 64-request limit; a test asserts the cap.
- Acknowledgement cancels every pending ladder request for that alert unconditionally and before any network call (FR-77).
- The ladder is cancelled and re-scheduled, never duplicated, if the same alert type re-fires.
- **This is the iPhone ladder only.** The wrist ladder is a separate, Watch-scheduled 1,800,000 ms (30-minute) ladder owned by FR-129, because the wrist copy must keep repeating with the app force-quit or Bluetooth lost. The two run on different surfaces at different cadences by design; what the user experiences is at most one phone ladder and at most one wrist ladder per episode, and an acknowledgement on **either** surface cancels **both** (FR-77, FR-131).

#### FR-77: Acknowledge from the notification

The user can acknowledge an alert directly from the notification on iPhone or on Apple Watch without opening the app, and every local silencing effect takes place regardless of whether the Backend is reachable. Realizes UJ-2. Upholds SI-6.

**Consequences (testable):**
- Every alert notification carries a "Got It" action. The action is non-foreground, so acknowledging launches the app in the background to handle it rather than opening it.
- The wrist acknowledge path is the **Watch-scheduled** notification (FR-128) and the wrist dismissal it carries (FR-131); that is the primary wrist transport. iPhone notification mirroring is the **fallback**, never the mechanism, because a mirrored notification does not fire while the phone is unlocked and in use — a common daytime state, which would leave the wrist silent exactly when the user is awake.
- Acknowledging on Apple Watch, by either path, routes the action back to the app carrying **that specific alert's** identifier — never a most-recent-alert assumption — and cancels both the iPhone ladder (FR-76) and the Watch ladder (FR-129). It can therefore silence an Alert Floor alarm, which the Android wrist dismiss provably cannot.
- The handler executes in this pinned order, all steps unconditional and network-independent: (1) mark the alert acknowledged in local storage; (2) remove the delivered notification; (3) cancel the re-alarm ladder; (4) clear the duplicate-suppression identifier; then (5) if the identifier begins with `local-floor:`, parse the type and apply the Alert Floor acknowledgement (FR-74) and **return without any network call**; otherwise (6) send the acknowledgement to the Backend, whose failure is logged only and whose durability is FR-78.
- The identifier parse is exact: `local-floor:low_urgent:175000` → `low_urgent`; `local-floor:` → no type; `local-floor:oops` → no type. A malformed identifier never reaches the Backend endpoint.
- The whole handler runs inside a background task assertion and completes the delivery callback in all paths, including thrown errors.
- A test pins the ordering and asserts that an unreachable or hung Backend can never leave the alarm sounding, the ladder pending, or the notification on screen.
- Tapping the notification body (rather than the action) opens the app to the alert history screen.

#### FR-78: Offline acknowledgement durability and reconciliation

An acknowledgement made while offline is never reversed by a later Backend delivery of the same alert, and syncs automatically when connectivity returns without the user retrying. Realizes UJ-2. Upholds SI-6.

**Consequences (testable):**
- Alert ingestion merges rather than overwrites: if a stored alert is locally acknowledged and an incoming copy of the same Backend-assigned alert identifier is not, the merge keeps `acknowledged = true` and preserves the existing sync flag. Callers branch on the **merged** result, never on the raw incoming payload, so a re-delivery cannot re-alarm an already-acknowledged alert.
- Acknowledgement outcomes are classified: 2xx → synced; 403, 404 and 422 → terminal (marked synced to stop retrying forever, and surfaced as an error); everything else, including 401 and any transport failure → transient (left pending, retried).
- A reconciliation pass drains pending acknowledgements oldest-first, is serialized so two passes never overlap, never throws, and is safe to call opportunistically. A transport failure aborts the whole pass (the Backend is still unreachable); any other unexpected error logs and continues to the next row.
- Reconciliation is triggered on network reachability becoming satisfied — including the initial value on cold start, which is what drains acknowledgements pending across process death — on Backend stream open, at the head of every history pull, on every foreground, and on every Core Bluetooth background wake.
- User-facing copy distinguishes deferral from failure: transient or transport → "Acknowledged locally — will sync when reconnected."; terminal → "Couldn't sync this acknowledgment to the server."; anything else → "Couldn't acknowledge the alert. Try again." (The literal string says "server" deliberately — that is the word the product shows people for their Backend. The string is pinned by test and is not to be re-worded.) In Backend-optional mode an acknowledge failure is silent — there is no Backend to nag about.

#### FR-79: On-device Alert Threshold editor (Backend-optional mode)

The user can set all four Alert Thresholds on the device when no Backend is configured, and doing so is what arms the Alert Floor at levels a user actually chose. Upholds SI-2, SI-3, SI-5.

**Consequences (testable):**
- The editor itself — its four decimal fields, its seeding and re-seeding on unit change, its locale-aware parsing, the mmol/L multiply-then-round rule, the reject-never-clamp validation against the Glucose Validity Bound, the ordering rule, the derived mmol/L bounds label (1.1 / 27.7) and its status-line copy — is specified once. See FR-169.
- The alerting consequence is owned here: a successful save sets threshold provenance to local and clears the last-sync timestamp to zero. That provenance change, and nothing else, is what arms the Alert Floor (FR-73).
- Provenance is observed reactively, so a save flips the Coverage Claim from Not Watching to Floor Watching with no polling delay (FR-83).
- The editor is offered only while no Backend is configured (FR-80, FR-143).

#### FR-80: Backend-supplied Alert Thresholds are read-only and adopted within the hour

When a Backend is configured, the app treats Alert Thresholds as read-only and adopts a Backend-side change within one hour whenever it has any opportunity to run. Upholds SI-11.

**Consequences (testable):**
- The read-only rendering — the values line, the never-synced empty state and the note pointing at the web app — is specified once. See FR-168. This FR owns the sync and staleness contract behind it.
- With a Backend configured, no editable field and no save control exists in the app; the four values are the Backend's.
- Thresholds are considered stale when `now − last sync > 3,600,000 ms`. A never-synced store is always stale.
- A refresh-if-stale is attempted after successful sign-in, on settings open, on dashboard open, on every Backend stream heartbeat and stream open, on every app foreground, and on every Core Bluetooth background wake. The 1-hour staleness window throttles this to at most one request per hour.
- A successful Backend fetch overwrites local provenance thresholds and records an audit line noting the takeover; the Backend is master while it exists.
- Backend-supplied Safety Limits may only narrow the Glucose Validity Bound, never widen it (SI-11).

#### FR-81: Invalid Backend threshold responses are discarded whole

The app silently discards a Backend threshold response that fails validation, keeps the last known good set, and never clamps an out-of-range or misordered value into range. Upholds SI-2, SI-5.

**Consequences (testable):**
- Validation runs in two stages: ordering is checked on the **raw** decimal values with all-strict comparisons (`urgent low < low < high < urgent high`) **before** rounding, because rounding two Backend-legal values less than 1 mg/dL apart could collapse them to equal integers and permanently disarm the Alert Floor; then values are rounded and range-checked within 20–500 mg/dL.
- On either failure the entire response is dropped and logged (no health value at or above debug level, SI-9). Nothing is written; the previous values and provenance stand. If nothing was ever synced, the store stays in the disarmed `none` state.
- A non-2xx response causes no state change. Any error other than task cancellation is caught and logged; cancellation is rethrown.
- Rounded ties at the urgent boundaries (69.8 / 70.2 → 70 / 70) are legal and safe because classification checks urgent bands first (FR-71).
- An optional `iob_warning` threshold in the response is ignored by the app — IOB alerting is Backend-side only.

#### FR-82: Alert Threshold provenance across sign-out

The app preserves device-set Alert Thresholds across sign-out and discards Backend-set ones on sign-out or when the Backend URL is removed. Upholds SI-5.

**Consequences (testable):**
- The clearing rule itself — clear Backend-provenance thresholds on sign-out and on Backend URL removal, preserve local-provenance ones — is specified once. See FR-143.
- The alerting consequences are owned here. With provenance local, sign-out leaves the Alert Floor armed at the user's own levels; a user who signs out is never left silently disarmed with nothing to restore from (SI-5).
- After a sign-out or URL removal that cleared Backend-provenance thresholds, the Coverage Claim immediately resolves to Not Watching with reason `THRESHOLDS_NOT_CONFIGURED` — no Backend is configured any more — and the on-device editor (FR-79) becomes available.
- The Alert Floor must never fire off another account's levels: a cleared Backend-provenance store returns provenance to `none`, which disarms it (FR-73).

#### FR-83: The Coverage Claim

The app tells the user, on every surface it offers, whether anything is currently watching for lows and highs, and never claims coverage it cannot deliver. Realizes UJ-1, UJ-4. Upholds SI-6.

**Consequences (testable):**
- The claim resolves to exactly one of: **Backend Active**, **Floor Watching**, or **Not Watching** with a Not-Watching Reason. These three state names are the Glossary-conformant vocabulary and are pinned by test; "Server Active" is not a state name anywhere in code, wire payload or documentation.
- One pure selector produces it, evaluated strictly in this order: **(1) the app cannot post alert notifications → Not Watching `NOTIFICATIONS_DENIED`**; (2) the clock is untrusted (FR-72) → `CLOCK_UNTRUSTED`; (3) Backend alerting is not degraded, by the evidence-based definition below → **Backend Active**; (4) Alert Thresholds not configured → `THRESHOLDS_NOT_SYNCED` if a **Backend** is configured else `THRESHOLDS_NOT_CONFIGURED`; (5) the accept window admits no readings → `SAFETY_LIMITS_TOO_NARROW`; (6) **Pump** not connected → `PUMP_DISCONNECTED`; (7) the reading age is known and Fresh → **Floor Watching**; (8) otherwise → `NO_FRESH_READING`.
- **Notification capability is checked FIRST, before any Backend branch.** If the app cannot present a notification, nothing is watching no matter how healthy the **Backend** is — a claim of **Backend Active** on a phone that cannot show an alert is an SI-6 violation by ordering rather than by intent. A test pins: **Backend** healthy with recent glucose, notifications denied → Not Watching `NOTIFICATIONS_DENIED`.
- The Not-Watching Reasons are `NOTIFICATIONS_DENIED`, `THRESHOLDS_NOT_SYNCED`, `THRESHOLDS_NOT_CONFIGURED`, `PUMP_DISCONNECTED`, `NO_FRESH_READING`, `BACKEND_HAS_NO_DATA`, `SAFETY_LIMITS_TOO_NARROW` and `CLOCK_UNTRUSTED`, ordered by how actionable they are; when several apply the most actionable wins.
- **The reason set is open, and a new failure mode gets a new reason rather than collapsing into an existing one.** A reason that is true-sounding and wrong is worse than no reason: it sends the user to fix the wrong thing. `NO_FRESH_READING` in particular must never be reported when the app is discarding readings that arrived (`SAFETY_LIMITS_TOO_NARROW`), when the **Backend** holds no data (`BACKEND_HAS_NO_DATA`), or when evaluation is suppressed for clock distrust (`CLOCK_UNTRUSTED`). A test pins one distinct reason per cause.
- Whether a Backend is configured only ever selects **which** missing-thresholds reason is reported. It never widens or narrows the claim itself. A test grid pins this across every input combination.
- Every input the Alert Floor's firing path gates on is mirrored in the selector, plus Pump connection state (the Alert Floor's implicit fifth gate: evaluation only happens on a newly obtained reading).
- Exactly one pipeline produces the claim for all consumers — in-app banner, glanceable surfaces, and the Watch app. Forking it per surface is prohibited by a test in `Build & Test`, aggregated by the `iOS Gate` Required Check (FR-197, FR-208).
- The claim is recomputed on a ticker whose period is `Fresh boundary ÷ 4` clamped to [2,000 ms, 30,000 ms] — 30,000 ms under the real policy, 5,000 ms under the debug policy — because the decisive input (reading age) grows with no new events.
- On any pipeline error the claim emits a pessimistic snapshot and retries after 5,000 ms; it never freezes and never goes quiet. The synchronous first-frame seed uses no reading age and assumes no Backend, so a cold start into an existing outage never renders all-is-well copy.
- Copy: Floor Watching with a Backend → "Server alerts paused — this phone is watching your latest sensor reading and will alarm for lows and highs. Threshold-only, no prediction. Alerts below are from before the disconnect."; Floor Watching in Backend-optional mode → "This phone is watching your latest sensor reading and will alarm for lows and highs. Threshold-only, no prediction."; every Not Watching variant begins "Monitoring degraded — this phone is NOT watching for lows or highs: " followed by the reason tail, with the suffix " No new alerts will arrive until the connection is restored." appended only when a Backend is configured. **Backend Active** shows no banner. (These literal strings say "Server alerts" and "sensor reading" deliberately — they are the words the product shows people for the Backend and the Glucose Reading. They are pinned by test and are not to be re-worded to the Glossary terms; the state name behind the first variant is nonetheless **Backend Active**.)
- Tests pin that no Backend-optional copy variant mentions a server or a restorable connection, and that every Not Watching variant literally contains "NOT watching" and never claims coverage.

#### FR-84: Coverage Claim expiry and decay

Every Coverage Claim carries an explicit expiry instant and degrades to Not Watching at that instant with no application code running. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Each emitted claim carries a `validUntil` timestamp. For Floor Watching it is the Glucose Reading's own sensor timestamp plus the Fresh boundary (360,000 ms; 20,000 ms under the debug policy). For Backend Active it is now plus the same window, because the Backend stream's liveness is only known while the process runs. For Not Watching it is now — an expired claim by construction. [ASSUMPTION: the Backend Active expiry window is not present in Android, which never needed one; reusing the Fresh boundary keeps a single number driving all four decay mechanisms.]
- All decay mechanisms derive from that one number: the widget timeline's pre-computed future entry is scheduled at `validUntil`, the Live Activity's stale date is set to `validUntil`, the proactive lapse notification (FR-85) is scheduled for `validUntil`, and the Watch app decays the phone's claim against its own clock after the advertised window.
- The claim is never persisted as authoritative across a process restart: on relaunch, coverage is recomputed from live inputs, and until it is, the pessimistic seed applies.
- A test asserts that no surface can render Watching from a claim whose `validUntil` is in the past.
- The Watch app never derives a claim of its own; it renders and decays the phone's (SI-6). Watch rendering and the Watch-side clamp on the advertised window are specified in FR-126; the wrist reason copy is FR-127.

#### FR-85: Proactive coverage-lapse notification, force-quit and reboot warnings

The app proactively notifies the user when it has stopped watching for longer than the coverage window, even though no application code is executing at that moment, and warns them about the two conditions that silently disable all background alerting. Realizes UJ-1, UJ-2. Upholds SI-6.

**Consequences (testable):**
- On every wake — foreground, Core Bluetooth background wake, or background refresh — the app cancels and re-schedules a single local notification for the current claim's `validUntil`. If the app runs again before then, that notification never fires; if the app dies, it fires. Silence becomes the alarm.
- The lapse notification is delivered at `.timeSensitive` and states that the app has stopped watching and what to do about it. It is not a glucose alert and never renders a glucose value.
- A last-ran timestamp is written on every wake. On next launch, a gap longer than the coverage window is detected and reported prominently: "GlycemicGPT has not run since <time>. Nothing was watching for lows during that period."
- Onboarding and Settings both carry copy stating, in plain words, that (a) force-quitting the app from the app switcher disables all background relaunch — including Bluetooth reconnection and any future push — until the app is manually reopened; (b) nothing runs after a device restart until the phone is unlocked at least once; (c) Low Power Mode removes the opportunistic background refresh path.
- Because APNs is deferred (FR-157), Backend-generated alerts do not reach a suspended or terminated app. The Coverage Claim copy says so rather than implying continuous Backend coverage.

#### FR-86: Automatic resume after background termination

The app resumes alerting automatically after a background termination when the paired Pump produces a Bluetooth event, without any user action. Realizes UJ-2, UJ-4. Upholds SI-5.

**Consequences (testable):**
- A pending connection to the paired Pump is kept outstanding at all times, so the system relaunches the app into the background on the next matching Bluetooth event.
- On such a relaunch the app restores the Alert Floor's persisted per-type cooldowns and acknowledged types (FR-74), recomputes the Coverage Claim from the pessimistic seed, re-schedules the lapse notification (FR-85), and evaluates the Alert Floor on the first Glucose Reading obtained — with no user interaction and no foreground transition.
- The Pump's idle disconnect is itself a background wake, so a connect → poll → idle-disconnect → reconnect cycle is the de-facto background evaluation cadence. No background timer is required or used.
- An acknowledgement handled during a background relaunch (FR-77) completes fully, including the local mark and the ladder cancellation, before the app is re-suspended.
- The measured background evaluation cadence on a real device is a release-checklist item at Validation Tier 4, on-device hardware (§9), explicitly **not** a CI Required Check — no CI job can measure it. If it approaches the 360,000 ms Fresh boundary, that is reported as a coverage fact in the Coverage Claim copy, never resolved by widening the Fresh boundary.
- A resume is impossible after a force-quit; FR-85's warnings are the product answer.

#### FR-87: Backend alert history

The user can review recent Backend alerts, refresh them on demand when a Backend is configured, and understand in Backend-optional mode why on-device alarms do not appear in the list.

**Consequences (testable):**
- The list shows the most recent 100 Backend alerts ordered newest first, keyed by the Backend-assigned alert identifier.
- Alert history retention is **not** specified here and is **not** a fixed 7 days: it follows the user's chosen retention window and is pruned by the scheduled retention pass, not on history-screen open. See FR-139. Correcting the Android behaviour — retention pinned at 7 days with cleanup running only when the alerts screen was opened — is a recorded deliberate divergence (§7).
- Pull-to-refresh is offered **only** when a Backend is configured; in Backend-optional mode there is no pull affordance at all, because a refresh would stand down and the gesture would be dead.
- Empty states are selected as a title/subtitle pair so they cannot drift: with a Backend → ("No alerts", "Pull down to refresh"); in Backend-optional mode → ("No alert history", "On-device alarms appear as notifications, not in this list."). In Backend-optional mode the loading flag is ignored when choosing the empty state.
- Each row shows severity, the value in the display unit, the message (3 lines maximum, ellipsized), the patient name when present, and a relative timestamp: "Just now" under 1 minute, "Xm ago" under 60 minutes, "Xh ago" under 24 hours, otherwise an absolute date and time.
- An unacknowledged row offers an acknowledge control that runs the same pinned sequence as FR-77.
- Refresh errors use user-facing copy, never a raw error message: unreachable → "Can't reach your server — alerts may be out of date."; otherwise → "Couldn't refresh alerts. Try again." (The literal string says "server" deliberately — that is the word the product shows people for their Backend. Pinned by test; not to be re-worded.) In Backend-optional mode a refresh returns silently with no error.
- Cached alerts remain visible while Backend alerting is degraded; the Coverage Claim banner sits above the list.
- Alert Floor alerts never appear in this list (FR-71).

#### FR-88: Developer fault-injection surface

A developer building from their fork can exercise every alerting path in the iOS Simulator without a physical Pump or a live Backend. Realizes UJ-6.

**Consequences (testable):**
- The fault-injection surface itself — the Developer section, the debug console, the release-build hard gate, "Simulate Backend Unreachable", the compressed 20,000 ms / 45,000 ms Freshness Tier policy, synthetic Glucose Reading injection and the fresh-low-fires / stale-low-suppressed pair — is specified once. See FR-176.
- Two injections are owed to alerting specifically and are stated here: force-fire each alert type at each severity, and expire the Coverage Claim immediately.
- The compressed Freshness Tier policy (FR-176) is substituted at exactly one swap point and applies simultaneously to the Alert Floor gate (FR-72), the Coverage Claim pipeline, the claim's ticker period, and the claim's advertised expiry (FR-83, FR-84) — so Fresh → Stale → Too Stale transitions are observable in seconds.
- With those injections plus a Simulated Driver, the following are exercisable with no hardware: Alert Floor arming, firing, cooldown, episode re-arm, episode guard, acknowledgement ordering, Coverage Claim decay, and coverage-lapse notification.
- Simulator results are treated as logic tests only. Alert audibility, entitlement behavior, locked-device delivery, Focus behavior, force-quit recovery, post-reboot behavior and background Bluetooth cadence are Validation Tier 4 on-device checks (§9), not CI Required Checks.

**Feature-specific NFRs:**

- The Coverage Claim pipeline must survive an error in any input without freezing: on failure it emits a pessimistic snapshot within 5,000 ms and resubscribes.
- The alert history store must be readable and writable while the device is locked after first unlock (SI-10); raising its file protection above that level is a release-blocking defect because it fails only on a locked device, which the Simulator does not faithfully reproduce.
- Alert logging must never emit a glucose value, a threshold value, a raw device payload, or a credential at or above debug level (SI-9). Alert Floor suppression logs must identify *which gate* failed without quoting the reading.
- The Freshness Tier constants, the Glucose Validity Bound, the Conversion Factor, the 30-minute cooldown, the 60,000 ms skew tolerance, the coverage expiry window, and the alert-type vocabulary must have exactly one definition each, in a module both the app and the Watch app link (SI-4). The Android risk that the Wear module mirrors freshness numbers independently must not be reproduced.

**Notes:**

*For the Parity Ledger (capabilities Android has that iOS cannot), originating in this section (§7):*
1. **Do Not Disturb / silent-switch override.** Android gets it from a normal install-time permission. iOS requires the Critical Alerts entitlement, granted per Team ID, structurally unobtainable under fork-and-build. Urgent lows ship `.timeSensitive`; the ring/silent switch can silence them and the app cannot detect it. Runtime auto-upgrade to `.critical` is wired but will not activate for the typical Builder.
2. **Alarm volume boost and restore.** Deleted, not ported. iOS exposes no API to set output or ringer volume and none to read the silent-switch position.
3. **Custom vibration waveforms.** Android's low-alert pattern `[0, 500, 200, 500, 200, 500]` has no iOS analog. Severity is encoded in the sound and in the FR-76 repeat ladder instead.
4. **Permanently visible "we are watching" indicator.** Android's ongoing foreground-service notification proves a process is alive. iOS has nothing equivalent; the composite of expiring claim + widget timeline + lapse notification is honest but not always-visible.
5. **Backend alert delivery to a suspended or terminated app.** Zero in v1 (APNs deferred, decision 7). Android's foreground SSE service delivers continuously.
6. **Launch on boot.** No analog. Nothing runs after a restart until the user unlocks the phone once; force-quit disables all background relaunch until manual reopen.
7. **Background evaluation cadence.** Android polls every 15 s under a wake lock. iOS cadence is whatever Core Bluetooth wakes produce; the 360,000 ms Fresh window is the tolerance budget.
8. **Custom notification sounds on the wrist.** The wrist alert is scheduled on the Watch (FR-128) and plays watchOS's own alert sound and haptic; the per-severity sound choice (FR-67) is iPhone-only.
9. **Choosing an arbitrary system sound as an alert tone.** Android uses the system `RingtoneManager` picker over the entire system sound library and ships no bundled sound assets at all. iOS exposes no API to enumerate, preview or select from the system sound library, and a notification sound may only reference a bundle or container file. The curated bundled set in FR-67 is a **forced substitute for a capability iOS removes**, not a design preference. The explicit "Silent" option is retained because it is real Android parity.
10. **Silencing a device-computed alarm from the wrist.** This is a parity **gain**: the wrist notification action targets the specific alert and can silence an Alert Floor alarm, which the Android wrist dismiss provably cannot.

*For the Parity Ledger (deliberate divergence this section contributes):*
- **Alert history retention.** FR-87 does not prune at a fixed 7 days on history-screen open. Retention follows the user's 1–30 day window and runs on the scheduled retention pass (FR-139, which owns the rule). This corrects a real Android defect — cleanup ran only when the alerts screen was opened, so a user who never opened it kept alert rows forever.

*Open questions this section raises, carried in §15:*
- **(OQ-24, product ruling needed)** When the app cannot verify that an alarm will be audible — the normal case without Critical Alerts — does the Coverage Claim say "watching" or "watching, but you may not hear it"? The strict reading of SI-6 argues for the caveat, but it would appear for nearly every Builder nearly all the time, which risks training people to ignore the one surface whose entire purpose is to be believed. Android never faced this. FR-66 currently places the caveat in claim *detail* copy rather than in the claim *state*.
- **(OQ-25)** FR-76's iPhone ladder (5 repeats at 120 s) is invented, not ported. It substitutes for two Android mechanisms that do not exist on iOS. It needs a real-user tuning pass before the first tagged release, together with FR-129's 30-minute wrist ladder, since the two are what the user actually experiences side by side.
- **(OQ-26)** The Alert Floor's background evaluation cadence cannot be measured without an iPhone and a Pump. The lead developer has neither an iPhone nor an Apple Watch (decision 10), so FR-86's cadence check lands on DanielDanielson's own fork build against their t:slim X2 (decision 9). Sequence that validation early — if the achievable cadence approaches 6 minutes, the honest response is a coverage-copy change, and that is a product decision, not a constant to retune.

**User-imported alert audio** is deferred, not deleted by oversight: FR-67's Out of Scope carries the named revisit condition, and §12.2 D-9 carries the deferral with the same condition. v1's selectable set is the bundled curated sounds plus "Default" for every tier and "Silent" for the informational tier, and nothing else.


### 5.5 Insulin, Meals and Analysis

**Description:**

This section owns two surfaces that share one posture: *the app reports what happened, it never suggests what to do.*

**Insulin.** The Insulin Summary card answers "how much insulin, split how?" over a day-boundary-aligned window. It reports a total daily dose, a basal/bolus split as a stacked bar with a legend, food and correction portions per day, and a per-category breakdown in a fixed order. Every number is derived from Pump-reported records: IOB is never computed by the app, Basal is integrated from the reported rate segments, and only completed Bolus deliveries count. The single most load-bearing honesty rule lives here: a Pump reports the *requested* meal and correction portions of a bolus, and those portions legitimately do not sum to the delivered units — partial delivery, user cancellation, an occlusion, a status frame that carries no breakdown, and automated boluses with a zero meal portion all break the identity. The app must never lay the two portions next to the delivered total in a way that implies arithmetic. SmartGuard auto-basal micro-boluses stay out of bolus totals entirely (SI-7).

Recent Boluses is the event view: the five most recent completed deliveries, newest first, each with time, units, a type badge and a plain-language reason, expanding to a full Bolus History for the period. Each row cross-references the nearest Glucose Reading and the nearest IOB value within ±5 minutes of the delivery, showing `--` rather than a guess when nothing falls in that window. Android prints that Glucose Reading column as a raw mg/dL integer with no unit label even for mmol/L users — the one glucose surface on the Android dashboard that ignores the display preference. (The column header itself reads "BG" in both apps; that is deliberate user-facing copy, not the requirement's term.) iOS corrects this: the column renders in the user's display unit, converted once through the Conversion Factor and rounded last (SI-3). That is a deliberate divergence, recorded in the Parity Ledger as an improvement rather than a loss.

Bolus *categories* and bolus *category labels* are two different things and have two different owners. Which category a delivery belongs to is decided by the active Driver's bolus-category-provider Capability, or by the flag ladder when no Driver provides one. What that category is *called* on screen can be overridden per account by the Backend, which ships a display-label list as part of its analytics settings alongside the day-boundary hour. The label map is presentation only: it never moves a delivery between categories, never reorders the breakdown and never changes a total, and it is cleared on sign-out so one account's vocabulary cannot render over another's data.

**Meals.** Meal intelligence is a Backend feature. It is reachable only when a Backend is configured *and* meal intelligence is enabled for the account; in Backend-optional mode the meal surfaces and the Home entry point are simply not there. Realizes UJ-5: Ren photographs lunch, waits through an "Estimating carbs…" indicator that is engineered so it can never stick, and gets back a *range* with a confidence signal — never a bare number, and never anything expressed in insulin units. The never-dose qualifier ("Rough estimate — an AI guess that's often wrong. Never use it to calculate an insulin dose or bolus.") appears on the same screen as every carb estimate, in a calm amber treatment that is deliberately never the error red, so a standing safety note is not mistaken for an alarm. VoiceOver reads the number, the confidence and the qualifier as one element, so the number cannot be heard without it. Throughout the meal surfaces the user-facing copy says "server" where this PRD says **Backend** — that is deliberate product copy, is quoted verbatim in the requirements below, and must not be rewritten to match the Glossary; the requirement prose around each quotation uses the Glossary term.

The estimate is honest about its own uncertainty in three separate ways. Confidence is conveyed by bar length *as well as* colour, because Medium and Low share one amber hue by design. When multiple reads of the photo disagreed on the amount or on what the food even was, the Backend's uncertainty note is elevated to the caution treatment; when they agreed, the note still renders quietly, because consistency is not correctness. And "How was this estimated?" opens a provenance trail: how many times the photo was read, what each read returned, and whether the result was grounded against an external nutrition source or is vision-only.

Correcting the food's *identity* is a separate action from correcting the *range* — grounding against real nutrition data only runs once the identity is confirmed, because a confident misidentification is not certified by grounding it. Correcting the range rejects bad input with a specific message and never silently clamps it, mirroring the Backend's own reject-not-clamp posture. Nutrition text that the Backend returns is rendered verbatim, in the Backend's own words, with malformed numbers dropped rather than displayed; the heart and blood-pressure block appears only for a confirmed, grounded record and is framed as awareness, never a directive.

Two iOS realities change the shape of the photo path. The Simulator has no camera, so the library path and a debug-only bundled-sample injector carry development; camera validation is a device-only pass. And iOS has no catchable out-of-memory condition — Android's `OutOfMemoryError` catch that produced "That photo is too large to process. Try a smaller one." has no counterpart, so the same user-facing state is reached by prevention (header-only dimension pre-check, thumbnail downsampling that never decodes the full-resolution image) plus a launch-time recovery marker, so a jetsam mid-upload can never leave a stuck medical spinner behind.

**Functional Requirements:**

#### FR-89: Insulin Summary

The user can see, for a selected period, their total daily dose, the basal/bolus split, food and correction portions per day, and a per-category bolus breakdown, computed entirely from Pump-reported Basal and Bolus records. Upholds SI-7.

**Consequences (testable):**
- Period choices are 24H / 3D / 7D, filtered by the local retention setting; a selection outside the available set falls back to the first available. The window is day-boundary-aligned: `periodStart(daysBack, boundaryHour, zone)` takes today's local date at the boundary hour, rolls back one day if now precedes it, then subtracts `daysBack` (24H→0, 3D→2, 7D→6). `boundaryHour` is required to be in 0…23 and defaults to 0.
- Basal is a segment integral: each segment runs from its own timestamp to the next reading's timestamp, capped at 2.0 hours and floored at 0; the final segment extends to now. A long Pump disconnect therefore under-reports rather than extrapolates.
- The days denominator is `dataSpanHours / 24` clamped into `[1, periodHours/24]`, measured from now rather than from the newest event, so numerator and denominator share one clock. At 24H the denominator is exactly 1, making total daily dose equal the raw total.
- The card renders nothing computed when `periodHours <= 0` or when `totalBasal + totalBolus <= 0`; the empty state reads "No insulin data for this period".
- Portion accumulation uses four mutually exclusive branches, in order: automated → the whole delivery is correction (`correctionUnits` when > 0, else `units`); else declared portions when `mealUnits > 0 || correctionUnits > 0`; else correction when flagged as a correction; else food.
- `basalPercent = basalPerDay / tdd * 100`, `bolusPercent = 100 - basalPercent`, both 0 when `tdd <= 0`. The stacked bar draws basal then bolus with bolus absorbing all rounding remainder, and draws nothing when the sum is ≤ 0.
- Category assignment prefers the active Driver's bolus-category provider Capability (FR-30); an unrecognised platform category name resolves to Other, and with no provider the flag ladder applies (automated → Auto Corr; meal and correction both present → Meal+Corr; correction → Correction; otherwise Meal). The breakdown lists only categories present in the data, in the fixed order Meal+Corr, Correction, Meal, Auto Corr, Override, AI Suggested, Other.
- Category *labels* are resolved separately from category assignment, and this FR owns that rule for every surface in this section. The Backend's analytics settings carry a bolus-category label override map — a display-label list keyed by computation role — reconciled together with the day-boundary hour on every Backend reconcile pass (FR-40) and cached locally. Resolution is: the Backend label for that category when present and non-blank, else the app's own category vocabulary (Meal+Corr, Correction, Meal, Auto Corr, Override, AI Suggested, Other). A response whose display-label list is absent leaves the cached map untouched; a response carrying an explicit empty list clears it; a label entry with no computation role is dropped rather than applied to an arbitrary category.
- In Backend-optional mode no label map exists and the app's own vocabulary is always used. The map is cleared on sign-out (FR-167) together with the rest of the analytics settings, so a departing account's labels can never render over the next account's data, and a category renders under its own vocabulary until the next reconcile lands.
- The label map is presentation only: a test asserts that changing it moves no delivery between categories, changes no fixed-order position, and changes no total, count or percentage. Rendering it is not a fallback for a missing Driver category — the two mechanisms are independent.
- The card exposes one combined VoiceOver description naming total daily dose, basal units and percent, bolus units and percent, food and correction units per day, and the total bolus count.
- Every displayed number uses a dot decimal separator and half-up rounding regardless of device locale.

**Out of Scope:**
- The chart's bolus markers and basal overlay (5.3).
- An Insulin Summary detail screen; it remains a registered destination rendering a placeholder line.

#### FR-90: Delivered-insulin honesty

The app reports only completed insulin deliveries, never presents a bolus's requested meal and correction portions as if they summed to the delivered units, and rejects bolus records whose units fall outside 0–25 U. Upholds SI-7, SI-1.

**Consequences (testable):**
- `units`, `correctionUnits` and `mealUnits` are each required to be ≥ 0 and ≤ 25 U at the model boundary. Construction from an out-of-bound record fails recoverably (failable or throwing initialiser — never a `precondition`, which would trap the process during a background wake) and is logged without the offending health value (SI-9).
- A stored record that violates the bound is skipped when read back from local storage and never rendered as an error row; the surface falls back to the next valid record or to its empty state.
- SmartGuard auto-basal micro-boluses are excluded from bolus totals, bolus counts and the category breakdown. [ASSUMPTION: the exclusion happens inside the Medtronic Driver, at the point the frame is decoded, so no downstream surface applies a second filter — the Insulin Summary and Recent Boluses consume whatever the Driver reports as a completed Bolus.]
- No layout places `mealUnits`, `correctionUnits` and delivered `units` in a way that reads as an equation: the meal and correction portions are labelled as the requested breakdown, and the delivered total is presented separately. A test asserts that no surface renders the three values in a single additive row or with a sum/`=` affordance.
- In-progress, cancelled and partially delivered boluses never appear as delivered. Where a Pump status frame carries no portion breakdown, the portions are absent, not zero.
- No screen in this section renders a suggested, recommended or calculated dose, and no control anywhere in the meal or insulin surfaces initiates a delivery (SI-1).

#### FR-91: Recent Boluses and Bolus History

The user can see their five most recent completed boluses on Home, newest first, and can expand to a full Bolus History listing every completed bolus in the selected period. Upholds SI-7.

**Consequences (testable):**
- The Home card shows at most 5 rows sorted by timestamp descending; when more exist for the period it offers "View all &lt;n&gt; boluses".
- Each row shows: local time as `M/d h:mm a`; units as `%.2fU`; a type badge; the nearest Glucose Reading at the event (column headed "BG" — deliberate user-facing copy); the IOB at the event — with a derived reason line beneath.
- Type resolution: automated **and** correction → Auto Corr; meal and correction portions both > 0 → Meal+Corr; correction and not automated → Correction; automated → Auto; otherwise Meal. Category labels resolve through FR-89 (the active Driver's category, rendered under the Backend's label override map when one is present, else the app's own vocabulary) and override the first four badge labels; the Auto badge always uses the static label "Auto" so no Driver-supplied or Backend-supplied label can conflate it with Auto Corr.
- Reason strings are vendor-neutral: "Auto correction bolus", "BG correction bolus", "Food bolus", "Meal %.1fU + correction %.1fU" (falling back to "Meal bolus with correction" when either portion is 0), "Automated bolus". These are literal user-facing strings and are kept verbatim — "BG" is the word the product shows for a Glucose Reading in this copy. A test asserts no reason string contains a manufacturer name.
- The Bolus History screen offers the full period set filtered by retention and shares one period selection with the Home card, so a change in either is reflected in the other.
- Empty state on both surfaces: "No boluses for this period".
- The Home card exposes a combined VoiceOver description of the form "Recent boluses: &lt;n&gt; events in the last &lt;period label&gt;".

#### FR-92: Glucose-Reading-at-event and IOB-at-event cross-referencing

The user can see the Glucose Reading and the IOB value nearest each bolus, and can tell when no such value exists. Upholds SI-2, SI-3, SI-4.

**Consequences (testable):**
- A Glucose Reading or IOB value is matched to a bolus only when `|reading.timestamp - bolus.timestamp| <= 5 minutes` (300 000 ms), measured against each reading's own sensor timestamp. Outside that window the cell renders `--`, never the nearest-available value.
- Two boluses at the identical timestamp cross-reference to the same nearest reading.
- The nearest reading is selected on timestamp alone, without regard to which Capability produced it: a reading from a BGM source (FR-24) competes with a CGM glucose-source reading on proximity only, and where the winning reading came from a BGM source the row names that meter, because two BGM sources may be active concurrently. Source has no effect on the ±5-minute window or on rounding.
- The Glucose Reading at the event is required to fall inside the Glucose Validity Bound (20–500 mg/dL); an out-of-bound value is REJECTED at the model boundary, never clamped, and the row renders `--` for that cell. This is the ABSOLUTE bound the storage layer enforces (FR-138), not the current, Backend-narrowable Safety Limits a Driver validates against at every validation pass (FR-32); the asymmetry is deliberate, so a stored row already inside the absolute bound is never retroactively invalidated by a Safety Limits change.
- The glucose-at-event column renders in the user's display unit **with** its unit label, converted once from the canonical stored mg/dL through the single Conversion Factor and rounded last — one decimal for mmol/L, integer for mg/dL. This is a deliberate correction of Android, which prints the raw mg/dL integer to mmol/L users; it is recorded in the Parity Ledger as an intentional divergence (PD-13).
- The Conversion Factor used here is the same Safety Constant the Watch app links; no second copy exists in this feature (SI-4).
- IOB at event renders as `%.1fU` or `--`. It is always the Pump-reported value; the app never derives it.

#### FR-93: Meal availability gate, Home glance and entry point

The user can reach meal logging only when a Backend is configured and meal intelligence is enabled for their account, and sees the most recent meal on Home when one exists. Realizes UJ-5.

**Consequences (testable):**
- When the locally cached meal-intelligence flag is off, the meal screen shows its disabled state immediately with **no** network request to the Backend: "Meal logging isn't turned on" / "Meal intelligence is turned off for this server. Ask your server admin to enable it to estimate carbs from a photo." (The copy says "server" deliberately — it is the word the product shows people for the **Backend** — and is shipped verbatim.)
- Otherwise the screen probes the Backend by requesting one food record; success → ready, a feature-disabled response → disabled, anything else → "Can't reach your server — meal logging isn't available right now." with a Retry control. A spinner is never a terminal state.
- A feature-disabled response discovered mid-upload moves the screen to the disabled state.
- All three meal destinations stay registered in Backend-optional mode and redirect to Home rather than blanking, and the Backend-configured decision is read from live state at render time, not captured when the navigation graph is built.
- The Home entry point to meal logging is absent when no Backend is configured and absent when meal intelligence is locally off. A transient or offline probe failure keeps it visible, so the meal screen can present its own degraded state; only an explicit feature-disabled result hides it. The local flag is re-checked on both the success and failure paths so a toggle flipped mid-flight cannot re-expose it.
- The Home recent-meal card renders only when a recent meal exists and shows: a "Recent meal" header with a "View all" affordance; a neutral placeholder thumbnail (the Backend returns no image); the food description; the carb range; "&lt;timestamp&gt; · &lt;confidence label lowercased&gt;"; and the never-dose qualifier.
- Home content retains a bottom inset large enough that the entry point never overlaps the last card.

**Out of Scope:**
- Android's draggable, position-persisting meal FAB and its "Reset position to default" VoiceOver action. iOS ships a fixed entry point above the tab bar safe area plus a redundant "Log a meal" row; drag is dropped. Recorded in the Parity Ledger.

#### FR-94: Meal photo capture and preparation

The user can supply a meal photo by taking one or choosing one from their library, and the app prepares it for upload without leaking location data. Realizes UJ-5.

**Consequences (testable):**
- The idle screen offers, in order: the explanatory line "Snap a photo of your meal to get an estimated carb range you can correct and save."; a filled "Take photo" action; an outlined "Choose from gallery" action; the permission line when applicable; then secondary actions for re-logging a common food, meal history and common foods.
- Library selection requires no photo-library permission and yields an image carrying no location metadata.
- Camera access is requested with a purpose string. Denial is non-fatal: the library path stays available and an inline error-styled line reads "Camera permission is needed to take a photo. You can still choose one from your gallery.", accompanied by a link into the system Settings for this app — because iOS never re-prompts after a denial.
- The image is downscaled so its longest edge is at most 1280 px, with no upscaling and aspect ratio preserved; EXIF orientation is applied to the pixels so the uploaded image is upright.
- The image is re-encoded as JPEG starting at quality 90 and stepping down by 10 while over 5 MiB (5 × 1024 × 1024) until quality 40; still over the cap → the operation fails with "Image is too large to upload after compression". The client cap must remain ≤ the Backend's own 5 MiB cap.
- The uploaded bytes contain no EXIF, GPS or other metadata. An automated test asserts the absence of a GPS IFD in the produced bytes.
- Preparation never decodes the source at full resolution; source dimensions are read from headers only and an absurd image is refused up front with "That photo is too large to process. Try a smaller one."
- Debug builds only: a bundled-sample-photo action feeds the same preparation and upload path, including deliberately oversized and non-upright samples, because the Simulator has no camera.

#### FR-95: Upload lifecycle and the non-sticking estimate indicator

The user always leaves the estimate flow in a stated outcome — an estimate, a named failure, or a dead-end state with a way back — and never in a spinner. Realizes UJ-5. Upholds SI-9.

**Consequences (testable):**
- Picking a new photo cancels any in-flight upload **first**, so a previous capture's temporary file can never be deleted out from under an active read.
- Temporary capture files are deleted after upload, on cancellation, and when a new capture supersedes an old one. Deletion is scoped to a single file; a full sweep of the capture directory runs only when the meal screen resets. The current photo is retained so the result can show its thumbnail.
- While uploading, the screen shows a centred indicator with the copy "Estimating carbs…". Every failure path clears it. Failure copy: "That photo is too large to process. Try a smaller one." (oversized source) and "Couldn't read that photo. Try another one." (unreadable or undecodable source).
- A marker is written before preparation begins and cleared on any terminal outcome; if the app is terminated mid-upload, the next launch clears the marker and shows an honest failure state rather than resuming into an indicator. [ASSUMPTION: the marker is a small on-device flag, not a persisted copy of the photo or of any estimate.]
- A request interrupted because the app left the foreground surfaces as an honest failure inviting a re-send, not a stalled indicator. [ASSUMPTION: the upload uses the same 90-second request budget Android's vision client uses, and is not moved to a background session in v1.]
- Vision-unavailable and no-AI-provider results are dead-end states with a Back action that resets the screen — not retryable errors.
- Backend error responses map to fixed user copy per status; a raw error message is never surfaced. Any diagnostic logging of an error body is truncated (200 characters) and carries no food identity, carb value, image bytes or credential at or above debug level (SI-9).

#### FR-96: The never-dose qualifier on every carb-estimate surface

Every surface that displays a carb estimate displays, at the same time and on the same screen, the never-dose qualifier. Realizes UJ-5. Upholds SI-1.

**Consequences (testable):**
- The qualifier text is exactly: "Rough estimate — an AI guess that's often wrong. Never use it to calculate an insulin dose or bolus." It exists as one constant reused by every surface.
- It appears on all six surfaces: the meal result screen (pinned above the scroll region so it cannot scroll out of view regardless of content length), the meal history list, the common foods list, the re-log sheet, the common-food edit sheet, and the Home recent-meal card. Sheets embed their own copy because a presented sheet dims the screen-level one.
- The treatment is a calm amber palette (light: background #FFF8E1, foreground #5D4200, icon #B26A00; dark: background #3A2E07, foreground #FCEFC7, icon #F2C14E) and is **never** the semantic error/alarm colour. The palette resolves against the effective appearance, so a forced Light or Dark selection is respected.
- VoiceOver reads the carb value, the confidence and the qualifier as a single element: "Estimated &lt;low&gt; to &lt;high&gt; grams of carbs, &lt;confidence label lowercased&gt;. &lt;qualifier&gt;.&lt;dispersion note&gt;" — a test asserts the number cannot be focused independently of the qualifier. That assertion needs a running screen, so it lives in `UI Tests (Simulator)`, which FR-197 lists as explicitly **non-required**; the merged accessibility string is additionally asserted at the view-model level in `Build & Test`, which the `iOS Gate` Required Check aggregates.
- Nothing in the meal feature presents insulin, insulin units, or a bolus (SI-1).
- A UI test in `UI Tests (Simulator)` — a non-required job per FR-197 — asserts that a screen rendering a carb estimate with zero qualifier elements is impossible, for each of the six surfaces. Because that job cannot block merge, the same six surfaces are also covered by a `Build & Test` unit test asserting every carb-rendering view model emits a non-empty qualifier constant, so this SI-1 guarantee is carried by the `iOS Gate` Required Check and not only by the non-required lane.

#### FR-97: Carb range and confidence presentation

The user always sees carbs as a low-to-high range with a confidence signal, never as a bare number. Realizes UJ-5.

**Consequences (testable):**
- The range renders as "≈ 40–55 g carbs", collapsing to "≈ 50 g carbs" when the low and high are equal — a single-point estimate still carries its units and the "≈" marker. Grams render as an integer when the value has no fractional part and to one decimal otherwise, with a dot separator regardless of device locale.
- A confidence label accompanies every range: "Low confidence" / "Medium confidence" / "High confidence" / "Confidence unavailable".
- The confidence bar is a 120 × 6 rounded track with fill fractions High 1.0 (green #22C55E), Medium 0.6 (amber #EAB308), Low 0.3 (amber #EAB308). Medium and Low deliberately share one hue and are distinguished by **length**; a test asserts the two are distinguishable with colour perception removed. Unknown confidence renders no bar at all.
- A corrected estimate shows the original alongside it: "You corrected this. AI estimated ≈ X–Y g carbs."
- The timestamp renders in the system time zone at medium date+time style, or "Unknown time" when absent.
- No carb estimate is ever rendered as an unqualified integer anywhere in the app.

#### FR-98: Multi-read disagreement disclosure

When the Backend produced the estimate from multiple reads of the photo, the user is told how much those reads disagreed and whether they agreed on what the food was. Realizes UJ-5.

**Consequences (testable):**
- The uncertainty note is rendered verbatim from the Backend. A blank note renders nothing.
- When the reads spread widely **or** disagreed on the food's identity, the note renders in the caution treatment (the same calm amber palette as the qualifier, never error red). When neither flag is set, the note still renders as a quiet secondary line — consistency is not correctness, and the quiet form must not read as "safe to dose".
- The note is appended to the merged VoiceOver phrase so a screen reader hears the uncertainty alongside the number.
- Uncertainty information exists only on a newly created record and is absent from history reads by contract; it is never fabricated, inferred or cached for a history row.
- The two flags default to *not wide spread* and *identity agreed* when absent, so a missing field can never fabricate a caution. [ASSUMPTION: these two fields are marked optional-with-default in the Contract Pin, making them an explicit carve-out from SI-12's fail-loudly rule for missing consumed fields; every other consumed field in the meal payloads remains required.]

#### FR-99: Food identity confirmation

The user can confirm or correct what the food is, as an action separate from correcting the carbs. Realizes UJ-5.

**Consequences (testable):**
- The displayed identity is the confirmed name when non-blank, otherwise the Backend's description, falling back to "Unidentified food".
- Unconfirmed records show one of three prompts, in priority order: when the reads disagreed on identity, "The AI wasn't sure what this is. Confirm it so we can look up its nutrition." in error styling; else when a saved food was suggested, "Looks like your saved \"&lt;X&gt;\" -- confirm?"; else "Confirm what this food is so we can ground it against real nutrition data."
- Confirm and Correct are separate actions. The submitted candidate is one normalised value (the suggestion when present, else the displayed identity, trimmed) used both for the submission and for the enabled check, so a valid suggestion can never leave Confirm disabled. An empty submission is refused with "Tell us what this food is." and no request.
- A confirmed record shows "✓ You confirmed this food." with a "Change what this is" affordance. The editor is titled "What is this food?" with a single-line "Food name" field, Cancel and Confirm, Confirm enabled only on non-blank trimmed input.
- The record id is captured before the request; a response that arrives after the user moved to a different record is discarded entirely rather than written to state.
- On success the record is replaced **and** any loaded provenance is discarded, because grounding and precedence have changed.
- Grounding against an external nutrition source runs only after identity is confirmed; a confident misidentification is never presented as grounded.

#### FR-100: Carb range correction — reject, never clamp

The user can correct the carb range, and invalid input is rejected with a specific message rather than silently adjusted. Realizes UJ-5. Upholds SI-2's reject-not-clamp posture.

**Consequences (testable):**
- Bounds are 0–1000 g. Validation runs in this order with these messages: non-numeric → "Enter a number of carbs in grams."; negative → "Carbs can't be negative."; above 1000 → "Carbs can't exceed 1000 g."; low above high → "The low value must not exceed the high value."; a missing or unparseable field → "Enter both carb values in grams."
- No value is ever clamped into range, and no invalid value ever reaches the Backend.
- The same validation implementation and the same copy are shared with the common-food editor, so the two cannot drift.
- The editor is titled "Correct the carb estimate (grams)" with decimal-keyboard "Low (g)" and "High (g)" fields seeded from the currently displayed range at the same rounding precision used for display, an inline error line, and Cancel / Save.
- The record always preserves the original estimate alongside the correction; the displayed range is the correction when present, else the estimate. A response carrying only one corrected bound is treated as **uncorrected**.
- Starting a correction clears any stale "saved to your common foods" confirmation, because that confirmation referred to the pre-correction baseline.

#### FR-101: Estimate provenance — "How was this estimated?"

The user can ask how an estimate was reached and see the reads behind it and whether it was grounded. Realizes UJ-5.

**Consequences (testable):**
- The affordance reads "How was this estimated?" and loads **on demand only**, never eagerly; the label reflects loading, and a load failure renders inline in error styling.
- The expanded card is titled "How this estimate was reached" and shows: "Read the photo &lt;n&gt; time(s); the range reflects how much those reads disagreed." (or "Estimated from multiple reads of the photo." when the count is unknown); one bullet per read as "• &lt;identity or 'unnamed'&gt;: &lt;low&gt;–&lt;high&gt; g" (an em dash when carbs are absent); then a precedence line — "Grounded against &lt;source&gt;" (with " (as \"&lt;identity used&gt;\")" when present) or "Vision-only -- not grounded against an external source." — then a Hide action that clears the loaded provenance.
- Grounded is derived from the Backend's precedence outcome; the app never infers it from the presence of nutrition data.
- The model's self-reported confidence is not part of this contract and is never displayed; the confidence shown is the empirical dispersion band.
- Provenance is not available until the Backend has produced one; that condition renders as an absence, not an error.

#### FR-102: Backend-authored nutrition, rendered verbatim

The user sees the Backend's nutrition text in the Backend's own words, and the heart and blood-pressure block only for a confirmed, grounded record. Realizes UJ-5.

**Consequences (testable):**
- All nutrition copy is rendered verbatim; the app authors none of it and rewrites none of it.
- Render order below the estimate: (1) the assumed-portion card labelled "ASSUMED PORTION" with the portion text and the prompt "Portion size is the biggest source of error in a photo estimate — does this match what you ate?"; (2) "Estimated nutrition" with one row per macro showing the label, the value in **whole** units ("&lt;rounded&gt; &lt;unit&gt;" — no false precision on an estimate) and the macro's glucose note; (3) a net-carbs row formatted "≈ 34–49 g", collapsing when the rounded endpoints meet, followed by the Backend's caveat on the calm-caution strip; (4) the section disclaimer, rendered by the content view rather than the card so a portion-only payload still shows it.
- Defensive decoding: a macro whose value is non-finite is dropped; net carbs are skipped when either bound is non-finite or the low exceeds the high; blank portion and note strings map to absent. A malformed response can never render a NaN or infinity on a medical surface.
- Net carbs appear only behind their caveat, clearly secondary to the total carb range, and are never presented as a dosing input.
- The heart and blood-pressure block is grounding-only and identity-gated: it renders only for a confirmed, grounded record and is never derived from the photo. It is titled "Heart & blood-pressure awareness", shows one row per fact with its note, then the sugar note, then attribution "From &lt;source&gt; (&lt;trust tier lowercased&gt;)", then its disclaimer.
- Facts with non-finite or negative values are dropped; if no fact survives, the entire block is omitted rather than rendered empty. The sugar note is kept only when a surviving fact key is `sugars_grams` or `added_sugars_grams`, so a dropped sugars value cannot leave an orphaned caveat.
- The block is framed as awareness, never as a directive, and is attributed to a source distinct from the vision estimate.
- Unknown fields in these payloads are tolerated; a missing consumed field fails loudly rather than defaulting (SI-12). [ASSUMPTION: the nutrition, comorbidity, provenance and dispersion payload shapes are unchanged from the Android contract and are covered byte-for-byte by the Contract Pin.]

#### FR-103: Meal history and record deletion

The user can review their logged meals and delete any of them with immediate effect. Realizes UJ-5.

**Consequences (testable):**
- The list loads a fixed page of 50 records with no pagination and no infinite scroll. There is no local cache: history is Backend-only.
- Render priority is disabled → loading → terminal error → content. When the Backend is unreachable and the list is empty, the screen shows "Can't reach your server — your meal history isn't available right now." with a Retry control — it must **never** show "No meals logged yet.", which would imply the user has logged nothing.
- "No meals logged yet." appears only on a successful load that returned zero records.
- When records are already loaded and a refresh fails, the failure renders as a small inline notice above the existing list, never as a full-screen takeover.
- A superseded load never writes state: the previous load is cancelled and cancellation is re-checked after the request completes, because a repository that maps errors into a result type can swallow the cancellation.
- Each row shows the food description (when non-blank), the carb range with its correction note, the timestamp, and a Delete action labelled "Delete meal".
- Delete takes effect immediately with **no** confirmation dialog: the row is removed optimistically and a failure is surfaced as a transient bottom message. (Pump unpairing per FR-17 and Driver deactivation per FR-25 keep their confirmations; a meal record is not a device state and is not held to that bar.)
- Feature-disabled renders "Meal intelligence is turned off for this server."; a retry after that state resets the disabled flag so an offline retry shows the honest offline state rather than a stale disabled one.

#### FR-104: Common foods — save, edit, read-only re-log, delete

The user can save a meal's estimate as a named common food and later view, edit, re-log or delete it. Realizes UJ-5.

**Consequences (testable):**
- Saving opens a sheet with a single "Name" field; an empty trimmed name is refused with "Give this food a name first." and no request. Success renders "Saved \"&lt;name&gt;\" to your common foods." echoing the **Backend-returned** name, not the typed one. A name conflict renders "A common food with that name already exists."
- The list loads a fixed page of 50 with no pagination. Unreachable renders "Can't reach your server — your common foods aren't available right now." with Retry; a successful empty load renders "No common foods yet. Save a meal as a common food to build your list."
- Each row shows the name, the saved carb range, and Re-log, Edit and Delete actions with per-item accessibility labels naming the food.
- Re-log opens a **read-only** sheet titled with the food name, containing the never-dose qualifier, the saved carb range rendered with unknown confidence (so no confidence bar appears), the copy "Your saved estimate for this food. Use it to verify before dosing — no new photo needed.", and a single Close action. Re-log does **not** create a new record — the Backend has no create-record-from-common-food path, and the seam is left in place for when it does.
- The edit sheet embeds the never-dose qualifier, offers a Name field and decimal "Low (g)" / "High (g)" fields, and scrolls its body so accessibility text sizes cannot clip its buttons. An empty trimmed name is refused with "Name can't be empty."; carb values run through the same shared validation and copy as FR-100 and are rejected, never clamped. On success the row is replaced in place.
- Delete takes effect immediately with no confirmation; the row is removed optimistically and a failure is surfaced as a transient message ("Couldn't delete that common food." / "Check your connection and try again.").

**Feature-specific NFRs:**
- Meal photo preparation must not hold a full-resolution decoded image in memory at any point; downsampling and orientation are applied in one pass from the encoded source.
- The vision request budget is 90 seconds, isolated from the general request budget so a slow inference is not counted as evidence the Backend is unreachable.
- Every number rendered in this section uses a dot decimal separator and explicit half-up rounding, matching the Android string byte-for-byte for the same input.
- Every test this section names runs in `Build & Test` and reaches merge gating through the `iOS Gate` Required Check (FR-197), except the two assertions in FR-96 that require a running screen, which run in `UI Tests (Simulator)` — a job FR-197 lists as explicitly non-required. This section names no Required Check of its own and introduces no new gate name. No safety assertion here rests solely on a non-required job: each FR-96 UI assertion has a stated `Build & Test` counterpart.

**Notes:**
- [NOTE FOR PM] Parity Ledger entries owned by this section: (1) the draggable meal entry button with its per-device saved position and "Reset position to default" VoiceOver action is dropped for a fixed entry point plus a Home list row; (2) Android catches an out-of-memory condition and shows a specific message — iOS has no catchable equivalent, so the same state is reached by prevention plus a launch-time recovery marker, and a jetsam mid-upload is recovered on next launch rather than in-process; (3) after a camera-permission denial iOS never re-prompts, so the app can only deep-link to Settings where Android can re-ask.
- [NOTE FOR PM] One deliberate *improvement* over Android is already in the Parity Ledger as PD-13: the Recent Boluses / Bolus History glucose-at-event column renders the Glucose Reading in the user's display unit with a label, where Android prints the raw mg/dL integer. Please confirm this divergence is wanted before it is pinned by tests.
- *For the Parity Ledger (parity this section contributes):* **the Backend-synced bolus-category label override map.** FR-89 owns it end to end — the cache, the fall-back to the app's own category vocabulary, the presentation-only guarantee, and the clear-on-sign-out via FR-167. It is a straight port of Android's `AnalyticsSettingsStore` display-label map, including the clear-on-sign-out behaviour, so it is parity rather than a loss or an improvement.
- [NOTE FOR PM] SI-12 carve-out requested: the dispersion flags (`wideSpread`, `identityAgreement`) must default to false/true when absent, because Android relies on that so a missing field never fabricates a caution. That conflicts with SI-12's fail-loudly rule unless the Contract Pin marks them optional. Recorded as A-16 in §16 and as OQ-36 in §15, where it is marked blocking; it still needs an explicit ruling.
- [NOTE FOR PM] This section has no dedicated user journey for the insulin surfaces — UJ-5 covers meals only. FR-89 through FR-92 are journey-orphaned. Consider adding a journey for "reviewing what insulin was actually delivered" so the honesty rule in FR-90 has a narrative anchor.
- The 5xx meal diagnostic log Android keeps (200-char body excerpt) exists because release builds ship no crash reporter. Carried forward only under SI-9 scrubbing; if the scrubber cannot guarantee that a Backend error body carries no food identity or carb value, the log must be dropped rather than weakened.


### 5.6 AI Chat

**Description:**

AI Chat is the one feature in the app that is Backend-only by construction. A user running in
Backend-optional mode never sees the tab at all — it is not disabled, not greyed, not present. Everything
else in this PRD works with no Backend; this does not, and the app says so plainly rather than presenting
a dead surface. There is no dedicated journey for AI Chat in S2; its safety posture is the same
never-a-dose posture UJ-5 establishes for meal carb estimates, and it is enforced here by two standing
disclaimers plus a suffix welded onto every spoken answer.

The experience is deliberately small. When the tab is opened the app probes the Backend's AI provider
exactly once and lands in one of three terminal states — Ready, "No AI Provider Configured", or "Unable to
Connect". There is no polling, no backoff, no automatic re-probe, and no state where a spinner is the
final answer. A 404 from the provider endpoint is the *only* route to "No AI Provider Configured"; a 500,
a TLS failure and a timeout all land in "Unable to Connect", which is the only one of the three that
offers a Retry. A provider removed on the Backend after a successful probe therefore surfaces as a send
failure, not as a state change — that is the Android behaviour and it is kept.

Conversations are ephemeral on purpose. The transcript lives in memory, capped at the most recent 100
messages, and is gone on relaunch. Nothing is written to disk. This is not a v1 shortcut: persisting it
would create a durable store of health-related conversation content that the Android client deliberately
does not have. Messages are capped at 2000 characters inclusive, refused locally above that with no
Backend request. Every failure class has curated copy; a raw error string, status line or response body
never reaches the screen.

Two things iOS cannot do the way Android does. First, the 90-second AI request does not survive app
suspension. On Android the process typically outlives a backgrounded LLM call, so a user can ask, switch
apps, and come back to an answer. On iOS the app is suspended within seconds of backgrounding and the
in-flight request dies. Rather than introduce chat persistence to paper over it, the app cancels the
request on backgrounding and says so honestly on return. That is a recorded parity loss. Second, watchOS
has no third-party watch faces, so Android's guaranteed chat slot on the project's own face becomes a
WidgetKit accessory complication and a Smart Stack widget that the *user* places, and which may simply be
absent. The wrist chat experience itself survives intact: one question, one answer, no transcript, three
one-tap prompts, and system dictation / Scribble / keyboard input — which needs no microphone or
speech-recognition permission because the input control runs out of process.

On the wrist the Android implementation had a real defect this port fixes: a 30-second watch watchdog
against a 90-second phone-side call, so a slow-but-successful answer could surface as a wrist timeout
while the phone completed anyway. iOS uses one shared AI request timeout across both surfaces.

Spoken responses are one setting shared by the app and the Watch app: an on/off flag defaulting off, and
a chosen voice defaulting to the system voice. Speech ducks other audio rather than interrupting it, and
stops on toggle-off, on clearing the chat, and on leaving the screen. Whatever is spoken always ends with
". This is not medical advice." — the disclaimer is inseparable from the spoken answer, exactly as on
Android. iOS cannot reproduce Android's "Online" voice label (there is no network-required flag on an
`AVSpeechSynthesisVoice`), so that indicator is dropped rather than faked.

There is no AI daily-brief screen, and adding one would be new work rather than a port. The Backend
exposes brief endpoints; the Android client never declares or calls them. AI insights and briefs reach
the user in exactly one place: a Backend-pushed alert, delivered at the informational tier (FR-65), with
the informational-tier sound (FR-67) and its Settings row (FR-170). There is no screen to open, and any
copy elsewhere in the product that promises briefs is describing those alerts. That absence is preserved
deliberately.

**Functional Requirements:**

#### FR-105: AI Chat tab availability

The app presents an AI Chat tab only when a Backend is configured; in Backend-optional mode the tab is
absent and no chat surface is reachable.

**Consequences (testable):**
- The Chat tab is absent from the tab bar whenever no Backend base URL is configured, and appears without
  requiring a relaunch once one is configured.
- Chat entry points are internal only. The app registers no custom URL scheme that accepts data from
  another app (NFR-22); the widget, complication and notification entry points that reach chat use the
  system's own widget/complication URL mechanism, which only the app's own extensions can populate, so
  none of them is a third-party input surface.
- An internal entry point targeting chat — a widget or complication link, a notification action, or a
  restored navigation path — returns the user to Home while in Backend-optional mode; it never renders a
  blank screen and never renders a chat surface. The destination itself stays registered (FR-63).
- The mode gate reads live state, so flipping to Backend-optional mode while the chat surface is on the
  navigation stack pops it to Home rather than leaving a stale screen behind.
- No chat request is issued in Backend-optional mode from any entry point.

**Out of Scope:**
- An AI daily-brief screen. The app ships no brief view, no brief view model and no brief endpoint call.
  AI insights and briefs surface in exactly one place: a Backend-pushed alert. Its delivery tier is the
  informational tier (FR-65), its sound is the informational-tier selection (FR-67) and the Settings row
  that chooses that sound is FR-170. There is nothing to open and nothing to navigate to, so onboarding
  and Settings copy must describe that alert rather than a screen (FR-159, FR-170). If a brief surface is
  ever wanted, it is new product work, not a port.
- Choosing or configuring the AI provider. That is done in the Backend's own web interface; the app only
  reports whether one exists.

#### FR-106: One-time AI provider probe and its three landing states

The app probes the Backend's AI provider exactly once when the chat surface first appears, and again only
when the user taps Retry, resolving to exactly one of three terminal states.

**Consequences (testable):**
- A 2xx response lands in Ready.
- An HTTP 404 — and only a 404 — lands in "No AI Provider Configured", with the guidance "Configure an AI
  provider in the web app Settings to use AI Chat." and **no** action control. The state is terminal.
- Any other status code, and any transport failure or timeout, lands in "Unable to Connect" with "Check
  your connection and server URL in Settings." and a Retry control. The requirement term for that field is
  the Backend URL; the copy string keeps "server" verbatim from Android because that is the word the
  product shows people, and it is a deliberate copy choice rather than a second name for the Backend.
- The app does not poll, does not retry automatically, applies no backoff, and does not re-probe after a
  successful send. The landed state persists until the user taps Retry or the surface is recreated.
- The loading indicator is never terminal: every probe outcome resolves to one of the three states,
  including on an unclassified error.
- The probe uses the general Backend request timeout, not the longer AI request timeout (this section's
  Feature-specific NFRs).

#### FR-107: Sending a message and the 2000-character limit

A user can send a chat message of up to 2000 characters inclusive; longer input is refused on device with
no Backend request.

**Consequences (testable):**
- A message of exactly 2000 characters after trimming is sent.
- A message of 2001 characters or more sets the error "Message is too long (max 2000 characters)" and
  issues no Backend request.
- Input that is empty or whitespace-only after trimming is not sent and produces no error.
- While a request is in flight the send control and the input field are both disabled, so a second send
  cannot be issued from the UI; a programmatic second send is additionally refused by the in-flight guard.
- The send control is enabled only when the trimmed input is non-empty and no request is in flight.
- While a request is in flight the app shows an in-flight indicator with the copy "AI is thinking..." and
  the message list scrolls to the newest item.

#### FR-108: Ephemeral in-memory transcript

The app keeps the chat transcript in memory only, capped at the most recent 100 messages, and offers a
Clear control. Upholds SI-9.

**Consequences (testable):**
- No chat message — user or assistant — is written to disk, to a database, or to any backup-eligible
  store. A relaunch or process termination leaves the transcript empty.
- The transcript is truncated to the most recent 100 messages on **every** append, both when the user
  message is added and when the assistant reply is added.
- A Clear control is shown only when the transcript is non-empty; activating it empties the transcript,
  clears any displayed error, and stops any speech in progress.
- No chat message content, and no Backend response body, appears in any log at or above debug level
  (SI-9).

#### FR-109: Curated failure copy for every failure class

The app presents fixed, curated copy for every chat failure and never surfaces a raw error.

**Consequences (testable):**
- Request timeout renders "AI response took too long. Please try again".
- A connectivity failure (not connected, host unresolvable, connection lost) renders "Check your internet
  connection and try again".
- HTTP 401 renders "Session expired. Please sign in again".
- HTTP 500 through 599 renders "Server error. Please try again later".
- Any unclassified failure renders "Couldn't get a response. Please try again".
- No exception description, status line, response body, URL or header value is ever rendered to the user
  or written to a log at or above debug level (SI-9).
- The error renders as a dismissible inline row at the **bottom of the message list**, not as a modal
  alert or dialog.
- Every failure path clears the in-flight indicator; a spinner can never be left running after a failure.
- A successful send after a failure clears the previously displayed error.

#### FR-110: Honest disclosure of an interrupted request

When a chat request is cancelled because the app left the foreground, the app tells the user on return
and invites a resend rather than showing a stalled request.

**Consequences (testable):**
- An in-flight chat request is cancelled when the app leaves the foreground; no partial or late response
  is applied to the transcript afterwards.
- On return to the foreground the app renders "Your question was interrupted. Send it again." in the same
  inline dismissible row used by FR-109, with the in-flight indicator cleared.
- The user's own message remains in the transcript so it can be copied or retyped; the app does not resend
  automatically.
- This path is never entered while the app remains in the foreground — a foreground request that exceeds
  the AI request timeout is reported as a timeout (FR-109), not as an interruption.

#### FR-111: Starter suggestions and the standing safety disclaimers

The app offers four one-tap starter suggestions on an empty transcript and shows the never-a-dose
disclaimers on every reply. Upholds SI-1, SI-12.

**Consequences (testable):**
- With an empty transcript and no request in flight, the app shows "Ask me about your glucose data" and
  exactly four tappable suggestions: "How am I doing today?", "Why do I spike after breakfast?", "What are
  my patterns this week?", "How is my time in range?".
- Tapping a suggestion only populates the input field; it never sends. The user can edit it before
  sending.
- A permanent footer sits above the input at all times, in every state including empty and error:
  "AI responses are informational only. Always consult your healthcare provider."
- Every assistant reply renders the Backend-supplied disclaimer beneath it.
- The disclaimer is a consumed field: a chat response missing `disclaimer`, or missing the answer body,
  fails loudly as a decode error rather than rendering a reply with a silently absent disclaimer
  (SI-12).
- No chat response, and no suggestion, can initiate a device command, a bolus, a basal change or any other
  therapeutic action — no such path exists to be reached (SI-1).

#### FR-112: Assistant markdown sanitization

The app strips image markdown and HTML image tags from assistant content before rendering, and opens only
http and https links.

**Consequences (testable):**
- `![...](...)`, `![...][...]` and `<img ...>` (case-insensitive, with or without attributes) are removed
  before rendering, so assistant content can never cause an outbound network fetch.
- Rendering an assistant reply issues zero network requests, verified for content containing remote image
  references.
- A link is opened only when its scheme, lowercased, is `http` or `https`; every other scheme is silently
  ignored with no error, no alert and no navigation.
- A failure to open a link is handled without crashing and without surfacing a raw error.
- Blank assistant content renders nothing at all rather than an empty bubble.
- The Watch app renders answers as plain text with markdown removed, so no image reference can be fetched
  there by construction.

*No Safety Invariant covers outbound-fetch suppression; it is a privacy control carried over verbatim
from Android, where it is documented as mirroring the web client.*

#### FR-113: Spoken responses, voice choice and audio ducking

A user can turn spoken responses on or off and choose a voice; spoken output always carries the
not-medical-advice statement. Upholds SI-1.

**Consequences (testable):**
- Spoken responses default to off and the chosen voice defaults to the system voice; both persist across
  relaunch.
- Activating the control while spoken responses are off turns them on immediately. Activating it while on
  opens a menu whose first item is "Disable TTS", followed by a separator, followed by every available
  voice with a checkmark on the selected one. [ASSUMPTION: the menu item copy "Disable TTS" is retained
  verbatim from Android even though this section otherwise calls the feature spoken responses; no
  evidence proposes replacement copy.]
- The voice list is filtered to the device's current language and sorted deterministically. [ASSUMPTION:
  voices are sorted by quality descending, then region, then name, and labelled `<region> - <voice name>`
  with an `(HD)` suffix for enhanced or premium voices; Android's variant-token derivation produces
  nonsense against iOS voice identifiers and no iOS copy exists.]
- Selecting a voice that is not in the available list is ignored. A persisted voice that is no longer
  installed falls back to the system voice for the device language rather than failing or going silent.
- The spoken string is always the assistant's reply with ". This is not medical advice." appended (SI-1);
  markdown is removed before speaking, with fenced code removed before inline code and table rows
  flattened to comma-separated cells. If the stripped text is blank, nothing is spoken.
- Speech **ducks** other audio rather than interrupting or stopping it, and other audio is restored when
  speech ends.
- Speech stops immediately when the user turns spoken responses off, clears the chat, or leaves the chat
  surface.
- Starting a new spoken reply replaces any speech still in progress rather than queueing behind it.
- The on/off flag and the chosen voice are one shared setting used by both the app and the Watch app;
  changing either on the chat surface syncs the new value to the Watch app, read from the canonical
  setting store rather than from any cached configuration copy. Both controls live on the chat surface,
  not in Settings > Watch, whose offered preference set is FR-134's and is unchanged by this section.
- Android's "Online" voice indicator is not reproduced; no label claims a voice requires network when the
  platform provides no such signal.

#### FR-114: AI Chat on the Watch

A user can ask the AI a question from their wrist and hear or read the answer there, reaching chat from a
complication or a Smart Stack widget. Upholds SI-1, SI-12.

**Consequences (testable):**
- The Watch app accepts a question via the system text input control — dictation, Scribble, and the
  keyboard where the hardware supports it — and requires no microphone or speech-recognition permission
  prompt from the app.
- Three one-tap prompts are offered verbatim: "How am I doing?", "Breakfast advice", "Why is my BG high?".
- Input is truncated to 500 characters. Input that is blank after trimming shows "Please enter a question"
  and issues no request. A relayed question exceeding 500 characters is refused with "Message too long
  (max 500 chars)".
- The Watch app holds no transcript: one question, one answer, then idle. Leaving the screen while a
  request is in flight clears the chat state.
- The answer renders as plain text with markdown removed, with the Backend-supplied disclaimer beneath it,
  defaulting to "Not medical advice. Consult your doctor." when the disclaimer is blank.
- When spoken responses are enabled, the Watch app speaks the answer plus ". This is not medical advice."
  (SI-1) and never speaks the same answer twice.
- Failure copy is per condition and never raw: "Request timed out. Try again later." / "No internet
  connection." / "Session expired. Open phone app to sign in." / "Server error. Try again later." /
  "Something went wrong. Try again later." Any relayed error string is truncated to 200 characters so no
  stack trace can render. [ASSUMPTION: Android's watchdog copy "Request timed out. Check phone
  connection." is replaced by "Request timed out. Try again later." because the Watch app's AI request no
  longer necessarily depends on the phone; no evidence fixes the replacement wording.]
- A response whose answer body is blank renders "Empty response from AI"; an unparseable response renders
  "Failed to parse response" (SI-12).
- The Watch app's in-flight watchdog and the AI request share **one** timeout value; the Watch can never
  report a timeout while the request is still running and can never be superseded by a late success.
- In Backend-optional mode the Watch app renders the terminal message "AI chat needs a GlycemicGPT server
  — none is set up on your phone." **before** any loading state is shown, with no retry control, because
  retrying cannot succeed. The copy is retained verbatim from Android's relay message and deliberately
  keeps the user-facing word "server"; the requirement term is Backend, and the condition is
  Backend-optional mode. [ASSUMPTION: the Watch chat entry points stay visible in Backend-optional mode
  rather than being hidden, matching Android's ungated chat complication; the terminal message carries the
  honesty instead.]
- The app's own chat complication placed on the user's watch face, and its own chat widget in the Smart
  Stack, both open the Watch chat screen; the widget kinds themselves are FR-117's. Both entry points use
  the system's own widget/complication URL mechanism, which only the app's own extensions can populate, so
  neither is an input surface another app can reach. The Watch app registers no custom URL scheme that
  accepts data from another app (NFR-22).
- A prefill carried by one of those entry points is truncated to 500 characters and lands in the idle
  state with a send control, not auto-sent. No prefill originates outside the app's own targets: no chat
  text is accepted from any other app on either surface. [ASSUMPTION: the Smart Stack chat widget carries
  no prefill, since Android has no Smart Stack analogue to port; only the app's own complication may
  prefill.]
- The chat glyph is identifiable without colour, because accessory rendering flattens the tint Android
  encodes as blue.

**Out of Scope:**
- Whether the Watch app calls the Backend directly or relays the request through the app. No FR fixes it:
  it is an architecture decision bounded by the Backend contract 5.8 owns and by 5.7's open question on
  giving the Watch app an independent Backend data path. This section fixes the behaviour contract, which
  must hold identically either way.
- Watch-side transcript history, and any persistence of a Watch question or answer.

**Feature-specific NFRs:**

- **One AI request timeout.** A single timeout value governs both the app's Backend AI call and the Watch
  app's in-flight watchdog. [ASSUMPTION: the value is 90 seconds, adopting Android's phone-side figure —
  its code documents LLM inference at 20–60 s — because the Backend's own inference ceiling is
  unverified.] The AI-provider probe deliberately uses the shorter general Backend request timeout
  instead; a slow inference is not evidence that the Backend is unreachable, and must not count toward any
  Backend-health signal.
- **No durable chat content.** Neither the app nor the Watch app writes any chat message, question,
  answer, disclaimer or AI response body to disk, and none appears in any log at or above debug level
  (SI-9).
- **Rendering issues no network requests.** Displaying an assistant reply on either surface performs zero
  outbound requests.

**Notes:**

[NOTE FOR PM] S2 defines no user journey for AI Chat. UJ-1 through UJ-6 cover glanceability, overnight
lows, building, pairing, meals and contribution — none touches chat. Either the section stays journey-less
(defensible: it is the only Backend-only feature and the smallest surface here) or S2 gains a seventh
journey. Flagging rather than inventing one.

The Android client promises daily briefs in its onboarding copy while shipping no brief surface. This
section ships no brief surface and will not gain one, so the two iOS surfaces that would otherwise carry
that promise forward — 5.9's FR-159 Features card and FR-170's AI-sound row description — describe the
Backend-pushed alert that actually exists rather than a screen. FR-105's Out of Scope names exactly where
AI insights arrive (FR-65 delivery tier, FR-67 sound, FR-170 row) so that copy has a target to describe.
The dropped "daily briefs, meal analysis, and pattern recognition" wording is a deliberate divergence 5.9
owns and records.

Parity Ledger candidates originating in this section:

1. **Backgrounded chat request is lost.** Android's process typically survives a backgrounded 90-second
   LLM call, so a user can ask, switch apps and return to an answer. iOS suspends the app within seconds
   and the request dies. The app cancels on background and discloses it (FR-110). Not fixable without
   introducing chat persistence, which would create a durable store of health-related conversation content
   that Android deliberately does not have.
2. **Chat entry point on the wrist is user-placed and may be absent.** Android ships its own watch face
   with a guaranteed AI Chat slot. watchOS permits no third-party faces, so the chat complication is a
   WidgetKit accessory widget the user must add manually, plus a Smart Stack widget. A user who adds
   neither has no wrist entry point at all.
3. **Chat glyph colour is not guaranteed.** Android tints the chat complication blue (0xFF3B82F6);
   watchOS accessory rendering applies the face's tint, so the glyph must read in monochrome.
4. **"Online" voice indicator dropped.** Android labels voices that require network. iOS exposes no
   equivalent flag, so the label is removed rather than guessed.
5. **Persisted voice identifiers do not migrate.** An Android `ai_tts_voice` value never resolves on iOS.
   There is no cross-platform settings migration path and none should be built; the unknown-voice fallback
   to the system voice covers it.
6. **Watch dictation is not testable in the developer loop.** watchOS dictation does not function in the
   Simulator, and the lead developer has no Apple Watch. The three one-tap prompts and the widget prefill
   are the Simulator-testable paths covering the same downstream state machine; truncation and blank
   handling are unit-testable on the plain string. A device pass by the maintainer is required before
   release.

All six are already carried in §7 — PL-21, PL-37, PL-38, PL-48, PL-49 and PL-39 respectively — so this
section owes no new row. Nor does the chat entry-point surface: the wrist complication and Smart Stack
widget are the additive substitute PA-2 already records, and under NFR-22 they are internal navigation
through the system's own widget/complication URL mechanism rather than a third-party input surface, so no
separate deep-link row is owed.

Defect fixed in the port, not carried: Android's Watch chat watchdog (30 s) is shorter than its phone-side
AI call (90 s), so a slow-but-successful answer can surface as a wrist timeout while the phone completes
and pushes a response that then replaces the error. FR-114 mandates one shared timeout, which removes the
window.

Open questions:

1. Confirm the Backend's actual AI inference ceiling so the single AI request timeout is set from evidence
   rather than inherited from Android's 90 s.
2. Confirm that `GET /api/ai/provider` returning exactly 404 for "no provider configured" is pinned by the
   Contract Pin, since it is the sole discriminator between a terminal no-provider state and a retryable
   offline state.
3. Should the "Disable TTS" menu copy be renamed to match the "spoken responses" vocabulary used
   everywhere else in this section, accepting a deliberate copy divergence from Android?


### 5.7 Apple Watch and Glanceable Surfaces

**Description:**

The Watch app ships inside the same bundle as the app. A Builder who forks, builds and installs their own signed copy (UJ-3) gets the Watch app as a counterpart install — no second artifact, no sideload, no ADB, no self-update channel. This deletes what the Android documentation calls "genuinely the most complicated step in setting up GlycemicGPT" and it deletes the entire Android watch-APK self-update subsystem with it. No Driver runs on the Watch; the Watch never opens a Bluetooth link to a Pump and holds no Pump credential. Everything on the wrist is a rendering of state the app forwarded, aged on the Watch's own clock.

**watchOS has no third-party watch face API, and never has.** The Android `:watchface` module — two Watch Face Format v2 faces (DIGITAL_FULL and ANALOG_MECHANICAL), 450x450 circular scenes, five and three complication slots bound to our own providers by `DefaultProviderPolicy`, a phone-side push channel with SHA-256 asset verification, and a phone-triggered "set as active" — has **no equivalent on watchOS and no partial substitute**. Apple owns face layout, clock rendering, ambient behaviour and tint; no app can install, draw, brand or activate a face. That is a hard parity loss, recorded in the Parity Ledger, not a scope cut. What replaces it: WidgetKit accessory complications the **user** places on the face **they** chose, the same widgets appearing in the Watch Smart Stack, and iPhone Lock Screen widgets plus a Dynamic Island surface. The Android guarantee that the Glucose Reading, IOB, graph, alerts and chat are all visible together on one screen does not survive; placement is the user's, so the app must instead *teach* placement and must *detect and say* when none of our complications is on the active face.

The second consequence of Apple owning the face is that complications render in an accented/tinted mode: hue is the face's, not ours. The Android alerts bell encodes its entire six-branch coverage-honesty decision in colour (quiet grey = something is watching; amber = coverage degraded or unknown; red = urgent alert). A literal port makes "everything is fine" and "your phone is dead and nothing is watching" pixel-identical. Every wrist state that matters is therefore re-encoded on **symbol, shape and text**, with hue as reinforcement only where the OS grants full colour (inside the Watch app, and on iPhone widgets). The accessibility labels carry the full state verbatim — screen-reader output is the one channel where the exact Android copy survives unchanged, and for this product it is arguably the most important one.

The two honesty axes from the Android design port intact and are the reason the wrist is trustworthy at all. Axis (b): every pushed value is aged on the **Watch's own clock**, against the reading's own sensor timestamp, so an app that dies, is force-quit, or loses Bluetooth causes the wrist to decay to "no recent data" on schedule instead of freezing on its last reassuring number (UJ-1). Axis (a): the Coverage Claim is the app's, mirrored and decayed by the Watch, **never derived** on the Watch (SI-6). The axes are deliberately decoupled — a Glucose Reading greys at Stale even while the mirrored Coverage Claim still says something is watching.

Where iOS forces a redesign, it forces it in three places. First, there is no guaranteed periodic wake, so Android's 3-minute coverage heartbeat cannot exist; the Coverage Claim gains an **absolute expiry** the app computes, and the Watch decays against that deadline rather than against arrival cadence. Second, wrist refresh is **metered** — high-priority complication transfers draw on an OS daily allowance and 288 readings a day cannot each buy one — so every time-driven transition is pre-baked as a future timeline entry that costs nothing, and metered spend is reserved for material change. Third, watchOS cannot vibrate the wrist from the background, and an iPhone notification mirrors to the Watch **only while the iPhone is locked** — so mirroring is silent in exactly the state a person is in for most of the day, phone unlocked and in hand. The wrist alarm is therefore a notification **scheduled on the Watch itself** (FR-128), with mirroring kept only as the fallback for when that path is unavailable; that is the only way Priya feels an urgent low while her iPhone happens to be unlocked in front of her (UJ-2). It also lets the 30-minute re-alarm ladder keep running on the wrist after the app stops — something Android cannot do.

The whole wrist experience works in Backend-optional mode: the Alert Floor and the Coverage Claim are on-device, and the Watch renders them with no Backend anywhere.

**Functional Requirements:**

#### FR-115: Single-bundle Watch app delivery and read-only wrist posture

A Builder can install the Watch app as a counterpart of the app they built, with no separate artifact, no sideload and no developer-grade device workflow, and can rely on the wrist being read-only. Realizes UJ-3. Upholds SI-1.

**Consequences (testable):**
- Installing or updating the app installs or updates the Watch app; there is no second downloadable artifact, no in-app APK/IPA download path, and no in-app installer.
- The Watch app declares that it does not run independently of the app: with no app present it renders its cached state, ages it, and never claims coverage.
- No Driver, no Bluetooth central, and no Pump credential exists in the Watch app or its widget extension. No wrist interaction can deliver insulin, change a Pump setting, or modify stored data; this sentence appears verbatim in the Watch onboarding and in the user documentation.
- When the installed Watch app's build identifier does not match the app's, the app shows a build-mismatch banner naming both builds and linking to the system Watch app's install flow; the app never attempts to update the Watch app itself.
- The app surfaces the case where the Watch app is not installed because "Automatic App Install" is off, with the exact step to install it.
- This FR is the single definition of the Watch app's install path, and there is exactly one remedy per condition: **not installed** → install it from the system Watch app (Automatic App Install, or the manual Install control there); **version mismatch** → update the app itself from TestFlight, which carries the Watch app with it. No surface anywhere offers a TestFlight download of the Watch app as a separate artifact, because none exists. FR-172, FR-173 and FR-224 cross-reference this FR and state no other remedy.

**Out of Scope:**
- Signing, provisioning and CI for the Watch target (5.10).

#### FR-116: One shared safety module behind every wrist surface, demonstrable in the Simulator

The app, the Watch app and both widget extensions can only obtain safety-relevant constants and decisions from one compiled module they all link, and a developer without an iPhone or Apple Watch can exercise every wrist surface end to end in the Simulator. Realizes UJ-1. Upholds SI-4, SI-2, SI-3.

**Consequences (testable):**
- Wrist colour banding is computed from the **Target Range**, never from **Alert Thresholds** — they are separate sets with separate stores (Glossary). The wrist and the phone hero must band identically for the same stored value.
- The Conversion Factor (18.0156) and the Glucose Validity Bound (20-500 mg/dL) exist exactly once and are linked by all four targets; a second literal anywhere fails the Safety Constant guard.
- The module holds the pure decision functions with no UI or transport dependency: Freshness Tier classification, the backward-clock guard, Alert Threshold sanitization, glucose banding, the trend-glyph provenance resolution (5.3 FR-46 — worse-of-two tiers, `?` when the glyph's own source is Too Stale), the Coverage Claim decay, the glucose/IOB render functions, and the history codec.
- Unit tests pin every boundary pair: CGM 6min-1ms Fresh / 6min Stale, 15min-1ms Stale / 15min Too Stale; Pump 15min-1ms Fresh / 15min Stale, 60min-1ms Stale / 60min Too Stale; Coverage Claim age `timeout-1` Watching / `timeout` not-watching-recently, received-at `now+60,000 ms` accepted / `now+60,001 ms` rejected.
- The provenance pairs are pinned in the same suite and against the same function the app calls, so the wrist and the hero cannot disagree about which tier either element is in: value 4 min / glyph source 8 min resolves to a Fresh value with a Stale glyph; value 4 min / glyph source 16 min resolves to a Fresh value with the unknown glyph; a 16-minute-old value resolves to Too Stale regardless of the glyph's age. The shared function returns the tiers; what each target does with a Too Stale value stays its own rule — the hero de-emphasises and keeps the number (5.3 FR-48), the wrist withholds it and shows `--` (FR-120).
- Negative age has exactly one rule and it is FR-49's: it classifies as Fresh **for display only** and never arms the Alert Floor (SI-5). The pinned pair is therefore age -60,000 ms Fresh and age -60,001 ms Fresh, with -60,001 ms additionally failing the Watch clock-trust guard (FR-123) so the age label reads "unknown time" and the Coverage Claim axis resolves to not-reported-recently.
- The mg/dL -> mmol/L pinned fixture is not restated here. See FR-60; the Watch app links the same formatting module and is pinned by that same fixture (SI-4).
- Every wrist surface renders correctly in the watchOS Simulator driven by the Simulated Driver, including scripted scenarios for a low crossing, a sustained urgent low, a CGM dropout landing exactly on the 6-minute and 15-minute boundaries, an app-death simulation, and a backward clock jump.
- Because the widget extension reads the shared on-device cache directly, no widget surface depends on the Watch app process having run first — the Android cold-start defect where IOB alone rendered "--" cannot recur.

#### FR-117: The wrist complication set, and the absence of custom watch faces

The user can place GlycemicGPT complications on the Apple Watch face they chose and see current glucose with trend, IOB, a recent-glucose sparkline, and the Coverage Claim indicator without opening any app. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Distinct widget kinds are provided so each can be placed independently: glucose, IOB, glucose sparkline, coverage/alert indicator, and an AI Chat entry point.
- Each kind supports the accessory families it can render honestly, and the same widgets appear in the Watch Smart Stack.
- The glucose complication is gated by no user preference; the IOB and sparkline complications honour their display preferences from the set FR-134 defines.
- The sparkline complication ships **without** the basal, bolus, IOB and activity-mode overlays: on an accessory strip they are unreadable and their encoding is entirely colour, which the accented rendering mode flattens. The full multi-layer overlay rendering lives only where full colour is real — inside the Watch app (FR-133) and on the phone chart (FR-53).
- The app ships no watch face, no face-configuration push, and no way to set the active face. Any UI implying otherwise is a defect.
- Every complication exposes a full accessibility label carrying the complete state, including the "data stale", "not watching" and "no recent data" phrasings.

**Out of Scope:**
- The behaviour of AI Chat itself once opened (5.6).

#### FR-118: Guided complication setup and active-face detection

The user can follow an in-app guide that names every complication we provide, says what each shows, and walks through adding it to their face; and the app tells them when none of ours is on the active face. Realizes UJ-1.

**Consequences (testable):**
- The guide enumerates each widget kind, the families it supports, and the exact steps to add it, and is reachable from onboarding and from Settings > Watch.
- The app detects whether any of our complications is currently enabled on the active face and, when none is, states plainly that nothing of ours is on the wrist and that wrist glances and wrist decay will not be visible.
- The guide states that placement, layout and face tint belong to the user and to watchOS, and that the app cannot place a complication for them.
- If a shareable watch-face configuration is offered, it is presented as a suggestion the user must confirm, never as an install. [ASSUMPTION: shipping a shareable `.watchface` configuration is optional for v1; it is device-only and cannot be validated in the Simulator, so it is not on the critical path.]

#### FR-119: Glanceable surfaces on the iPhone Lock Screen, Dynamic Island and Watch Smart Stack

The user can see current glucose, trend, IOB, the Pump-link state and the Coverage Claim on the iPhone Lock Screen and in the Dynamic Island, and the same surface reaches the Watch Smart Stack, with no configuration. Realizes UJ-1. Upholds SI-6.

This FR is the single definition of the out-of-app glanceable surface; every other section that needs something on the Lock Screen or in the Dynamic Island (FR-20) cross-references it rather than specifying a second surface.

**Consequences (testable):**
- iPhone Lock Screen accessory widgets render the same values, the same Freshness Tier treatment and the same Coverage Claim states as the wrist complications, from the same render functions.
- A live monitoring surface drives the Dynamic Island and is forwarded to the Watch Smart Stack; it carries glucose, trend, Freshness Tier, the Pump-link state and the Coverage Claim state. The trend it carries is the glyph resolved by the provenance rule (5.3 FR-46, rendered per FR-120), never the raw last-known arrow: no glanceable surface presents a trend glyph as fresher than its own source.
- The Pump-link state rendered here is the connection state model of FR-8, unmodified: the surface never states or implies a healthier link state than the true one, and a surface whose backing state has aged out degrades to an explicit unknown rather than to a reassuring default.
- Full-colour glucose banding is used on these surfaces because the OS permits full colour there; the state remains legible with hue removed.
- The live surface has a bounded lifetime imposed by the OS, is user-dismissible, and ends automatically; when it ends, the app does not leave a stale reading on screen, and the app restarts it at the next foreground or next Glucose Reading. [ASSUMPTION: the OS bound is 8 hours active with up to 12 hours of residual Lock Screen presence; the exact figures must be re-verified against the shipping OS and the surface must never present a value older than its Freshness Tier permits regardless.]
- Because that lifetime is bounded and the user can dismiss it, this surface may never be the sole carrier of the Coverage Claim, and no honesty copy in the app may depend on it being present (SI-6).

#### FR-120: Glucose Reading on the wrist with the Freshness Tier treatment

The user can read current glucose on the wrist and always know whether it can be trusted, at every Freshness Tier and with no value ever shown outside the Glucose Validity Bound. Realizes UJ-1. Upholds SI-2, SI-3.

**Consequences (testable):**
- Fresh (age < 6 min / 360,000 ms): the value with its trend glyph, e.g. `120 ->`; accessibility label "Blood Glucose: 120 mg/dL" (verbatim spoken copy carried from Android — the wording the user hears is deliberate and is not the Glossary noun).
- Stale (6 min <= age < 15 min / 900,000 ms): the value with an explicit stale marker, e.g. `120? ->`; accessibility label ends "(stale)".
- Too Stale (age >= 15 min): no value at all — `--` — while the age keeps counting; accessibility label "No recent data".
- **The trend glyph is aged separately from the value, and the rule is 5.3 FR-46's — this section states no second one.** The glyph is a distinct Pump transaction carrying its OWN source timestamp, classified under the same CGM policy against that timestamp, and every wrist surface renders it at the WORSE of its own Freshness Tier and the value's, never a better one. The wrist must not present a trend glyph as fresher than its own source.
- The marker convention above extends to the glyph, and only when the glyph's own tier is WORSE than the value's — when the two tiers are equal the value-level treatment already carries the tier and the glyph is not separately marked, so every example above is unchanged. Glyph at Stale beside a Fresh value: the stale marker trails the glyph, `120 ->?`. Glyph at Too Stale, absent, or unparseable beside a Fresh value: the glyph is replaced by `?`, `120 ?`, while the value keeps its own tier, marker and colour. A marked glyph always keeps its direction character, so `120 ->?` (flat, stale) and `120 ?` (unknown) are never confusable. At a Too Stale value the surface shows `--` regardless of the glyph's tier.
- When the glyph is marked or replaced, the accessibility label states the trend's own state — "trend stale" or "trend unknown" — so a screen-reader user is never told a direction the arrow no longer supports.
- A Glucose Reading outside 20-500 mg/dL renders `--` regardless of age, is REJECTED not clamped, is logged without the value at debug level or above, and never crashes the surface — including a value restored from the on-device cache after a restart.
- The relative age is rendered by the system from the reading's own sensor timestamp so it keeps counting up without waking the extension; when no reading exists at all, no age is shown.
- Trend glyphs are the exact code points: double-up U+21C8, single-up U+2191, forty-five-up U+2197, flat U+2192, forty-five-down U+2198, single-down U+2193, double-down U+21CA, anything else `?` — including a glyph whose own source is Too Stale or absent (FR-46).
- Half-open boundaries, with the glyph source at least as fresh as the value: 6min-1ms shows `120 ->`, 6min shows `120? ->`, 15min-1ms shows `120? ->`, 15min shows `--`.
- Pinned provenance pairs: a value 4 min old with a glyph source 8 min old shows `120 ->?`; a value 4 min old with a glyph source 16 min old shows `120 ?` with the value still in its Fresh treatment; a value 16 min old with a glyph source 1 min old shows `--`.

#### FR-121: IOB on the wrist with the Freshness Tier treatment

The user can read IOB on the wrist under the Pump Freshness Tier policy, never presented as current when it is not. Realizes UJ-1. Upholds SI-7.

**Consequences (testable):**
- Fresh (age < 15 min / 900,000 ms): two decimal places, e.g. `2.45`; accessibility label "Insulin on Board: 2.45 units".
- Stale (15 min <= age < 60 min / 3,600,000 ms): `2.45?`; accessibility label ends "(stale)".
- Too Stale (age >= 60 min): `--`; accessibility label "No recent data". An hour-old IOB presented as current is dosing-relevant misinformation and is never rendered.
- IOB is the value the Pump reported; the Watch never computes, extrapolates or decays an IOB number toward zero.
- The IOB complication honours the Show IOB preference (FR-134); when it is off the complication renders an explicit off state rather than a stale number.
- Two-decimal formatting uses a fixed POSIX locale so a comma-decimal device locale cannot produce `2,45`.

#### FR-122: Wrist decay on the Watch's own clock, within the OS refresh budget

The Watch app can degrade every wrist surface on schedule using only its own clock, with no message from the app, and without exhausting the OS's daily wrist-refresh allowance. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Every time-driven transition is pre-baked as a future timeline entry at the moment data arrives: for a Glucose Reading, entries at now, sensor timestamp + 6 min and + 15 min; for IOB, at now, timestamp + 15 min and + 60 min; for a Coverage Claim, at its expiry.
- With the app force-quit, powered off, or out of Bluetooth range, the wrist still transitions Fresh -> Stale -> `--` and the Coverage Claim still expires, with zero further messages and zero refresh budget spent.
- Metered high-priority wrist transfers are spent only on material change: a glucose band crossing, a Freshness Tier transition, an alert state change, a Coverage Claim state change, or a floor of at most one per 15 minutes.
- The remaining daily metered allowance is read at runtime, never hardcoded, and when it is exhausted the app degrades to unmetered delivery rather than dropping data. [ASSUMPTION: the allowance is a system value in the tens per day; the design must not depend on a specific number.]
- The Watch caches the last Glucose Reading, up to 72 Glucose Readings (6 hours at 5-minute intervals), the last IOB and the display unit, in storage readable while the Watch is locked, so a complication renders real data immediately on cold start rather than `--`.
- A newly arrived Glucose Reading whose timestamp is within 30,000 ms of any cached entry is dropped as a duplicate; overflow past 72 entries drops the oldest.
- A malformed cache record is dropped; an unreadable cache is discarded wholesale and the surface renders "no recent data" rather than partial garbage.

#### FR-123: Backward clock-jump guard

The Watch app can treat its own clock as untrustworthy when it jumps backward, and says so instead of implying freshness. Realizes UJ-1. Upholds SI-5, SI-6.

**Consequences (testable):**
- Negative-age **classification** is not defined here. FR-49 owns the single rule the app and the Watch app both link: a negative age (clock skew, future-dated timestamp) classifies as Fresh **for display only** and never arms the Alert Floor (SI-5). This section defines no second classification and the Watch never reclassifies a negative age to Too Stale.
- What the guard changes is the honesty the Watch owns about **its own clock**: an age more negative than -60,000 ms means the Watch's clock has run backward past the tolerated skew, which marks the clock untrustworthy, so the Coverage Claim resolves to not-reported-recently and no wrist alert is scheduled or re-alarmed from that reading (SI-5).
- That -60,000 ms is a clock-trust bound, not a display tier and not a second negative-age classification. It is the same 60,000 ms skew tolerance FR-49 and 5.4 FR-72 already use, applied to the Watch's own clock rather than to the reading; it withholds no value, changes no Freshness Tier, and the reading stays Fresh at every magnitude.
- The age label under an untrusted clock reads "unknown time", never "just now" and never the incoherent "as of just now - data stale". FR-49 carves this label case out by name as its only exception, so there is one label rule and one exception to it, both stated in FR-49.
- Small negative ages are routine sampling skew and are tolerated without any label change: age -5 s renders Fresh with a normal relative age, and a Coverage Claim received up to 60,000 ms in the future is accepted.
- Pinned pairs: age -60,000 ms renders Fresh with a normal age label; age -60,001 ms renders Fresh (FR-49) but with the "unknown time" label, no alert armed, and coverage not-reported-recently. Coverage Claim received at `now + 60,000 ms` accepted, `now + 60,001 ms` rejected.

#### FR-124: Display-only mmol/L conversion and glucose banding on the wrist

The user can see wrist values in mmol/L without the display unit ever reaching a safety decision, and can read the glucose band with or without colour. Realizes UJ-1. Upholds SI-3.

**Consequences (testable):**
- mg/dL is what is stored, transported, compared and plotted on every wrist surface; conversion happens once at the display boundary using the Conversion Factor 18.0156, dividing once and rounding last, to one decimal place.
- Formatting uses a fixed POSIX locale so the decimal separator is a dot on every device locale; the acceptance test is the pinned cross-surface fixture in FR-60, which the Watch app is held to by linking the same formatting module (SI-4).
- The banding function takes no unit parameter, so the user's mmol/L preference structurally cannot reach it.
- Banding, on mg/dL only: at or below urgent low, or at or above urgent high -> urgent band; at or below low, or at or above high -> warning band; otherwise in-range band. Warning boundaries are inclusive: exactly `low` and exactly `high` band as warning, not in-range.
- Full colour (urgent red, warning amber, in-range green) is used on every surface where the OS permits it — the Watch app's own screens, the iPhone Lock Screen and Home Screen widgets, the Dynamic Island.
- On every surface where the OS flattens colour, the same band is conveyed without hue — by symbol, shape or text — and the greyscale rendering of each band is distinguishable by a reviewer who has not read the code.
- The converted string is never fed back into validation, banding, threshold comparison, or plotting geometry.

#### FR-125: Alert Threshold sanitization on the wrist

The Watch app can accept Alert Thresholds from the app, including a corrupt or hostile payload, and still band every reading against an ordered, in-bound set. Realizes UJ-1. Upholds SI-2, SI-5, SI-11.

**Consequences (testable):**
- Sanitization runs in this dependent order, each clamp depending on the previous: low clamped to 40-200; high clamped to max(low+1, 100)-400; urgent low clamped to 20-low; urgent high clamped to high-500.
- For any input whatsoever the result satisfies 20 <= urgent low <= low < high <= urgent high <= 500.
- When threshold keys are absent, the wrist falls back to low 70, high 180, urgent low 55, urgent high 250 **for display banding only**; these fallbacks never cause a wrist alert, and no wrist alert is ever scheduled from a threshold the user or their Backend did not set.
- Sanitization can only narrow within the Glucose Validity Bound; no sanitized threshold can fall below 20 or above 500.

#### FR-126: The wrist Coverage Claim — rendered and decayed, never derived

The user can tell at a glance whether anything is currently watching for a low, in three unambiguous states, on a wrist surface that never invents the claim and never overstates it. Realizes UJ-1, UJ-2. Upholds SI-6.

**Consequences (testable):**
- Exactly three states are rendered: something is currently watching; the app reported that nothing is watching, with the specific Not-Watching Reason; the app has not reported recently.
- The quiet "all clear" presentation is reserved exclusively for the first state. The other two are always visibly degraded, even with zero active alerts.
- The Watch never computes a Coverage Claim from data freshness, connectivity, or anything else; it renders and decays what the app sent (SI-6).
- The app advertises an absolute expiry with every Coverage Claim, so an irregular delivery cadence cannot produce a false "no recent data" on a healthy phone. The claim rides along on every state write, which is the same event stream that proves the app is alive.
- The Watch clamps the advertised validity window to 10,000 ms - 1,800,000 ms: a corrupt or hostile payload can neither make a dead phone look covered for more than 30 minutes nor force decay in under 10 seconds. The default when the window is absent is 360,000 ms.
- An unrecognised coverage state string fails closed to "has not reported recently".
- The Coverage Claim is **not persisted**: after a Watch app restart, coverage reads as unknown until the app reports again, because coverage after a restart is genuinely unknown.
- The claim's state is encoded on symbol and text, not hue: the three claim states above and the urgent-alert presentation are all distinguishable from one another in a greyscale screenshot, and a merge gate requires that greyscale review.
- The urgent-alert, degraded-coverage and stale-alert states each carry the full descriptive accessibility label; the "quiet" presentation is only reachable while the claim says something is watching.

#### FR-127: Not-Watching Reason copy on the wrist

The user can read the specific, user-actionable cause when nothing is watching, in distinct copy per reason. Realizes UJ-1, UJ-2. Upholds SI-6.

**Consequences (testable):**
- Five reasons, each with its own distinct line, pinned by test so a dropped or renamed arm fails CI rather than silently degrading to the generic copy. The quoted strings are verbatim user-facing copy and are deliberately left in ordinary sentence case rather than restyled to Glossary capitalisation:
  - notifications denied -> "Monitoring degraded - allow notifications on your phone."
  - thresholds not synced -> "Monitoring degraded - alert thresholds haven't synced yet."
  - thresholds not configured -> "Alerts off - set alert thresholds in the phone's Settings."
  - Pump disconnected -> "Monitoring degraded - pump is disconnected."
  - no fresh reading -> "Monitoring degraded - no fresh glucose readings."
- An unrecognised or absent reason renders a distinguishable generic line: "Monitoring degraded - nothing is watching for lows or highs."
- The reason vocabulary is a pinned contract shared with the app; a rename on either side fails the contract test.
- When the reason indicates the Backend-mediated path is down, the wrist additionally states that caregiver and AI alerts are paused because they need the Backend — without implying the on-device Alert Floor is also down when it is not.

#### FR-128: Watch-scheduled wrist alert delivery

Priya can be woken on the wrist by an urgent low whether or not her iPhone is locked, and a single fresh low produces exactly one wrist experience. Realizes UJ-2. Upholds SI-5.

This FR owns the wrist alert transport for the whole PRD. 5.4 and 5.8 conform to it and specify no competing wrist path.

**Consequences (testable):**
- **The Watch-scheduled notification is the primary wrist alert path.** The wrist alert notification is scheduled on the Watch itself, triggered by a guaranteed delivery from the app that wakes the Watch app in the background even when suspended; wrist delivery does not depend on iPhone lock state, on the iPhone being asleep, or on notification mirroring.
- **iPhone notification mirroring is the fallback, never the mechanism, and the reason is stated in the requirement:** iOS mirrors a notification to the Watch only while the iPhone is locked, so a mirroring-only design is silent whenever the phone is unlocked and in use — a common daytime state and the single most likely time a low is missed. Mirroring therefore carries the wrist only when the Watch-scheduled path is unavailable (no Watch app installed, or the Watch app cannot be woken), and that fallback state is reported as degraded coverage rather than treated as normal.
- One fresh low produces one wrist haptic and one wrist notification. The wrist notification identifier is derived from the alert's identity, so a re-delivery, a mirrored copy, or a refresh **replaces** the existing wrist notification rather than stacking a second one. A test asserts that a Watch-scheduled alert and its mirrored copy of the same alert never coexist on the wrist.
- Interruption level follows FR-66 and is not restated here: time-sensitive, auto-upgraded at runtime to critical whenever the Critical Alerts entitlement and authorization are both present. The urgent-vs-warning distinction is carried by interruption level and sound, not by a custom haptic waveform.
- The alerting layer exposes interruption level as a single configuration point, so a change from time-sensitive to critical requires no restructuring.
- The Watch alert screen re-evaluates on a 15-second tick so both honesty axes keep decaying while the screen is open, with no new data required.
- The alert screen shows the glucose value **only** when the raw mg/dL is within 20-500; otherwise it shows the alert type and age with no number.
- The age line is always visible. Past 15 minutes it reads "as of <age> - data stale" and the alert is visibly de-emphasised — never silently retracted to "All clear".
- When the alert is stale **and** coverage is not "watching", the alert screen adds an explicit line: "Not watching - check your phone."
- The app's own Alert Floor notification is not additionally mirrored to the wrist when the Watch app scheduled the wrist copy; mirroring reaches the wrist only on the fallback path above.

#### FR-129: Locally scheduled 30-minute wrist re-alarm ladder

The user can keep being alarmed on the wrist for a sustained alert every 30 minutes, and that ladder terminates honestly rather than alarming forever off a frozen snapshot. Realizes UJ-2. Upholds SI-5, SI-6.

**Consequences (testable):**
- The re-alarm is scheduled locally on the Watch at a 1,800,000 ms (30-minute) cadence, so it continues even if the app stops responding, is force-quit, or loses Bluetooth.
- The ladder terminates once the underlying Glucose Reading ages past Too Stale (>= 15 min / 900,000 ms). The terminating notification says the data is stale and that nothing is currently watching; it does not re-assert the alert value.
- Dismissing the alert (FR-131) cancels the whole scheduled ladder on the Watch.
- A recovery from the app cancels the ladder; a Coverage Claim expiry does not silently cancel it — the ladder terminates only via the stale rule or an explicit dismissal.
- Re-alarm defaults to on when the app's payload omits the flag, so an older app build still re-alarms.
- This ladder is the **only** cadence that re-buzzes the wrist. The phone's bounded finite ladder (FR-76) governs the phone; each of its repeats updates the existing wrist notification in place under the identity-derived identifier (FR-128) and adds no wrist haptic, so the user is never alarmed on two cadences at once. A test pins the wrist haptic count for a sustained urgent low: one at onset, then one per 30 minutes, regardless of how many phone-side repeats fired.

#### FR-130: Live-alert refresh, and never retracting on data we cannot vouch for

The user can trust that a still-live alert on the wrist stays presented as live, and that an alert is never retracted on the strength of a reading nothing can vouch for. Realizes UJ-2. Upholds SI-5, SI-6.

**Consequences (testable):**
- While an alert is ongoing, the app silently refreshes the wrist copy at least every 300,000 ms (5 minutes), keeping the shown alert inside the 6-minute Stale band so a still-true alert is never greyed as "data stale". On iOS this rides the natural ~5-minute Glucose Reading cadence.
- When a Glucose Reading is not alertable — clock rewound (FR-123), Alert Thresholds not configured, or the reading not strictly Fresh — the wrist relay takes **no action at all**: nothing is sent, nothing is cleared, no latch changes. The wrist copy ages out on the Watch's own clock instead.
- A recovery that clears the wrist alert is keyed on the alert classification being in-range, not on a wrist-type mapping being absent: a mapping gap costs a wrist push, never produces a reassuring "All clear".
- No wrist surface transitions from an active alert to the quiet "all clear" presentation unless coverage currently says something is watching.

#### FR-131: Wrist alert dismissal

Priya can dismiss an alert from the wrist — from the alert screen and from the notification itself — and that dismissal is truthful even with no Backend reachable. Realizes UJ-2. Upholds SI-6.

**Consequences (testable):**
- Dismissal is available both as a button on the Watch alert screen and as an action on the wrist notification, without opening the Watch app.
- The dismiss payload carries the identifier of the specific alert being dismissed; the most-recent-alert assumption is not used, so two alerts arriving in quick succession cannot cross-dismiss.
- The app marks the alert acknowledged **locally before** any Backend call, so the dismissal is truthful with no Backend reachable and the alert cannot re-fire; the Backend sync is deferred to reconciliation.
- The app clears its own ongoing-alert latch on dismissal, so the same episode does not immediately re-alarm the wrist.
- The Watch clears its local alert optimistically and cancels the re-alarm ladder even when the app is unreachable; if the app still holds the alert, it re-pushes on the next refresh and the wrist shows it again rather than staying falsely quiet.
- The dismiss button is single-shot: it disables itself and shows an in-progress label while the dismissal is in flight.

#### FR-132: Six-hour basal, Bolus and IOB history on the Watch

The user can see basal, Bolus and IOB overlays on the wrist graph for the last 6 hours, with every record bounded at receipt and a truncated payload producing no overlay rather than garbage. Realizes UJ-1. Upholds SI-7, SI-8.

**Consequences (testable):**
- The app forwards the last 6 hours of basal, Bolus and IOB history, capped at 500 records per type, in a fixed-size binary encoding: basal 13 bytes per record, Bolus 21 bytes, IOB 12 bytes (approximately 6.5 kB / 10.5 kB / 6 kB at the cap).
- At receipt the Watch rejects any record with a basal rate outside 0-15 U/hr, any Bolus component (total, correction or meal units) outside 0-25 U, a negative IOB, or a non-positive timestamp; the record count must be 0-500.
- Only completed deliveries are represented; auto-basal micro-boluses are excluded from Bolus totals before forwarding.
- A truncated or undersized payload yields an empty overlay, not a partial decode: the required-byte computation is overflow-safe and returns empty rather than trapping.
- No partially decoded batch is committed: either the batch decodes and the filtered records are stored, or the previous overlay state is left untouched.
- Byte order and field order are pinned by a codec test shared with the app so the encoding stays byte-identical on both sides.

#### FR-133: Full-screen Watch glucose graph and the shared Y-axis rule

The user can open a full-screen glucose graph on the Watch, pan back in time, tap any point for its value, and see the same reading on every graph surface. Realizes UJ-1. Upholds SI-2, SI-3.

**Consequences (testable):**
- The graph renders in full colour inside the Watch app: activity-mode bands, target-range band, dashed threshold lines with numeric axis labels, basal stepped area, IOB area, Bolus markers, and per-segment glucose colouring by band.
- It honours the four overlay preferences and the Graph Range preference of 1, 3 or 6 hours (default 3), all as defined in FR-134.
- Below 3 Glucose Readings in the window the graph renders an explicit "not enough data" state, not an empty chart.
- Panning drags backward in time only, clamped to the extent of available history; the viewport never advances past now.
- Tapping within a 50-pixel radius (squared distance 2500) of a reading shows a tooltip with the value in the user's display unit and its local time; a tap outside that radius shows nothing.
- Time-axis ticks align to clean local-minute boundaries at 15-minute marks for a viewport <= 1 h, 1-hour marks for <= 3 h, and 2-hour marks beyond.
- **The Y axis is not defined here.** Every graph surface on phone and wrist — the wrist sparkline, the full-screen Watch graph, the phone chart and the iPhone widgets — uses the single rule in FR-52. This section states no second axis rule and no wrist-specific clamp. The consequence it depends on: no reading inside the Glucose Validity Bound is drawn on one surface and missing from another, and no reading is ever drawn at a boundary position it does not hold.
- Axis geometry stays in mg/dL; only the printed axis label and the tooltip convert to the display unit.
- Both graph surfaces carry the Freshness Tier treatment: once the newest Glucose Reading in the window is Stale the trace is de-emphasised and the window is explicitly labelled as such; once it is Too Stale the trace is withheld and the surface says so. A three-hour-old chart never renders identically to a live one.

#### FR-134: iPhone Settings > Watch — preference sync and the true wrist-link state

The user can see, in the app's settings, the real state of the wrist link and can change the wrist preferences that actually change wrist behaviour. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Preferences are pushed to the Watch on every change and re-pushed on every reconnection; the push carries a monotonic sequence value so an unchanged payload is still delivered.
- This FR is the single definition of **what** the Watch consumes. The offered preferences are exactly, and only: Show IOB; Show Glucose Graph; Wrist Alerts; Graph Range (1H / 3H / 6H, any other value falling back to 3H); and — only while Show Glucose Graph is on — the four graph overlays Show Basal Rate Area, Show Bolus Markers, Show IOB Overlay and Show Activity Mode Bands. Eight preferences, these names. FR-172 defines only **where** the controls live and mirrors this set by cross-reference; it introduces no preference of its own and renames none of these.
- No preference is offered that nothing consumes. There is no watch-face theme control, no appearance or high-contrast preference for the Watch, and no "show seconds" control. Complications render in a system-controlled tint the app cannot override, so a per-app appearance preference could not affect them — it would be a control that does nothing. The Android watch-face theme is a forced loss recorded in the Parity Ledger, not a rebound feature, and no substitute for it is offered.
- The Wrist Alerts setting states its consequence in plain words: turning it off disables all wrist alerting for lows and highs. It also states that watchOS and the system Watch app give the user independent notification controls the app cannot override or detect.
- Settings > Watch shows the true link state: whether a Watch is paired, whether our Watch app is installed, whether any of our complications is on the active face, whether the Watch is currently reachable, the session activation state, the last Glucose Reading and last IOB the Watch **actually holds** with their timestamps, and how much of today's metered wrist-refresh allowance remains.
- Values read back from the Watch are re-checked against the Glucose Validity Bound before display; an out-of-bound cached value shows as absent, not as a number.
- Every "synced to watch" style claim in the app derives from an acknowledged delivery or a read-back of what the Watch holds — never from "we called the API". A merely-enqueued transfer is never reported as delivered.
- A failed link surfaces as a specific state ("Watch app installed but not reachable", "session not activated") rather than a generic error.

**Feature-specific NFRs:**
- Greyscale gate: a reviewer who has not read the code must be able to distinguish all coverage/alert complication states, and all three glucose bands, from greyscale screenshots. This is a merge-blocking human review, not a style note — and not a sixth Required Check: no CI job executes it, and the roster stays closed at five (FR-197).
- On-device acceptance items (unverifiable in the Simulator, so they must be budgeted as device time from the start): a felt haptic for each alert tier; wrist breakthrough with Sleep Focus enabled; wrist delivery with the iPhone **unlocked and in use**, which is the state mirroring does not cover (FR-128); complications still updating after 18 hours of continuous use; a complication rendering real data after a wrist-off/lock cycle; the wrist re-alarm ladder firing with the app force-quit; and a full overnight soak with the iPhone in Low Power Mode. These are contributed to the one written hardware-validation checklist that §9.1 Tier 4 and FR-207 route to; this section maintains no second list.
- Wrist cache storage must be readable while the Watch is locked (after-first-unlock class, never when-unlocked), or the complication renders `--` after every lock cycle. No health value is written to any log at or above debug level (SI-9).

**Notes:**

[NOTE FOR PM] Parity Ledger entries for this section, all now written — the ID follows each so a reader can check the row rather than take this list's word for it:
1. **No custom watch faces (PL-31).** The `:watchface` module (DIGITAL_FULL and ANALOG_MECHANICAL, WFF v2, 450x450, guaranteed five-slot / three-slot layouts, branding) has no watchOS equivalent. The user places complications themselves; the app cannot guarantee that glucose, IOB, graph and coverage are visible together.
2. **No Watch Face Push and no phone-set active face (PL-32).** Neither the transport nor the concept exists on watchOS, and pushing an executable artifact to a paired device is separately prohibited by App Review.
3. **No phone-controlled face theme or seconds display — a forced loss with no substitute (PL-33).** Apple owns face colour and time rendering, and complications render in a system-controlled tint the app cannot override, so there is nothing for a per-app appearance preference to affect. PL-33 records this as a loss with **no control offered and no rebinding**; the earlier "rebound to a high-contrast appearance preference" substitute, its Assumption entry and the §15 question that asked whether to accept the rebinding are all retired. (Both settings were already inert on Android.) Legibility is carried instead by the unconditional symbol-and-text encoding and the merge-blocking greyscale review.
4. **No custom background haptic waveform (PL-26).** The Android urgent double-buzz (0/500/200/500 ms) versus one-shot 300 ms distinction cannot be reproduced; urgency is carried by interruption level and sound instead. Combined with binding decision 4, the wrist alarm can be silenced by the ring/silent switch and the app cannot detect that.
5. **Complication colour is not ours (PL-34).** The Android bell's six-branch hue encoding and the sparkline's four colour-encoded overlay layers do not survive the accented rendering mode; both are re-encoded, and the multi-overlay graph exists only inside the Watch app and on the phone chart.
6. **No guaranteed periodic heartbeat (PL-16).** Android's 3-minute coverage heartbeat is replaced by an absolute expiry piggybacked on Bluetooth-driven writes. A force-quit app is never relaunched by Core Bluetooth; the wrist's decay to "no recent data" is the only signal the user gets, and that is by design.
7. **Metered wrist refresh (PL-35).** High-priority wrist refreshes draw on an OS daily allowance; Android has no such cap. Pre-baked timelines make decay free, but a data-driven refresh is not guaranteed per reading.
8. **No watch-side self-update (PL-36).** Removed entirely (the Watch app ships in the bundle) — an improvement, but the Android capability "update the watch app from the phone" no longer exists and neither does the ADB install path.

[NOTE FOR PM] Two Android defects are fixed rather than ported, and both cost nothing now and a regression later: the alert dismiss carries the alert identifier instead of an empty payload (Android can dismiss the wrong alert when two arrive together), and both graph surfaces get freshness de-emphasis plus the one shared axis rule of FR-52 — a single default range that expands rather than pins, so Android's split of a 20/500 sparkline against a 40/400 detail view, and its pinning of an out-of-axis reading to the boundary, both disappear. PD-16 and PD-17 now record both in those terms; the Assumption entry and the §15 question that asked whether to confirm a 20/500 wrist clamp are retired, and FR-133 states no axis rule of its own. Nothing further is owed here.

[NOTE FOR PM] The wrist alert transport is settled and the ledger already reflects it: FR-128 makes the Watch-scheduled notification primary and mirroring the fallback, because mirroring does not fire while the iPhone is unlocked and in use. PL-30 and PL-27 are restated on that basis and the §15 wrist-alert-transport question is struck as answered. Nothing further is owed here.

[NOTE FOR PM] Recorded in §15 as OQ-32 and owned by 5.8: should the Watch app be given an independent data path to the Backend in Backend-connected mode (its own background fetch), so the wrist has data when the iPhone is dead? It is the honest answer to "the phone died", but it puts a Backend credential in the Watch Keychain and creates a second data path with its own freshness semantics. Section 5.8 owns the Backend contract; this section only needs to know whether the wrist ever sources data from anywhere but the app.

[NOTE FOR PM] **PD-42's conforming edit is made.** §7's PD-42 records trend-glyph provenance as owned by 5.3 FR-46 for the whole PRD and asks this section to carry it; FR-120 now does — the glyph is a separate Pump transaction, aged on its own timestamp, rendered at the worse of the two tiers, marked when its own tier is worse than the value's and replaced by `?` when its own source is Too Stale or absent — with the resolution and its pinned pairs in the shared module (FR-116) and the same glyph on the glanceable surfaces (FR-119). On Android a 15-second foreground poll kept the two transactions close and the wrist never had to show a marked or unknown arrow beside a good number; on iOS it will, which is the behaviour PD-42 exists to disclose. Nothing further is owed here.


### 5.8 Data, Storage, Sync and Backend Integration

**Description:**

The local store is the product. Every Glucose Reading, Bolus, Basal, IOB value, battery and reservoir sample, alert row, raw pump-history frame and outbound-queue row lives in one encrypted database on the iPhone, and every surface — dashboard, Alert Floor, Watch app, analysis, upload — reads from it. The Backend is a consumer of that store, never its source of truth. Backend-optional mode is therefore not a degraded path: it is the same store with the upload half switched off.

Android kept that store fed and drained with a foreground service holding a wake lock and a coroutine loop that woke every 3 seconds forever. iOS has no foreground service, no wake lock, and suspends the app within seconds of backgrounding. The single most fortunate property of the existing design is that outbound-queue eligibility was already a SQL predicate over stored timestamps rather than an in-memory timer — sparse execution windows therefore delay delivery without corrupting state. So the drain loop survives verbatim in the foreground and becomes opportunity-driven in the background: the app does its housekeeping (queue drain, retention, Alert Threshold refresh, Backend-mediated Nightscout sync, token refresh) at every execution opportunity the system grants it, and never on a promised cadence. Uploads are handed to the system as file-backed background transfers so a push started in the foreground finishes after the user leaves.

Honesty is the load-bearing constraint. Freshness is always derived from a reading's own capture timestamp, never from when the app fetched it, so a frozen Backend-mediated feed ages out exactly like a frozen Bluetooth feed (UJ-1). When the iPhone is restarted or the app is force-quit, nothing runs — no capture, no upload, no alerting — and the app cannot detect it while stopped; on the next launch it must detect the gap from the data itself and report it rather than resuming quietly. This is the honest ceiling of iOS background monitoring and it is a recorded parity loss, not a bug to be engineered around.

Two iOS-only hazards get first-class treatment. Keychain items survive app deletion, so a fresh install would otherwise inherit a previous install's database key, tokens and pairing secrets against a database file that no longer exists — the app purges its own Keychain items on first run after install. And any connection to a local-network address requires the Local Network privacy grant; a denial produces connection failures that look like a dead Backend, so the app must name it as a permission problem with a route to Settings (UJ-3, where Marcus points a freshly built copy at his own Backend).

Cleartext transport policy is a product requirement enforced by the app's own code, at save time and again on every request, identically in every build configuration: no plaintext request leaves the device for any host that is not a literal loopback, private (RFC1918), carrier-NAT (100.64.0.0/10) or link-local address, or a `.local` name. Host classification is by literal IP address only and never performs a DNS lookup. The Info.plist App Transport Security configuration that *achieves* that baseline is an architecture decision requiring empirical verification — ATS exceptions are per-domain and accept neither IP addresses nor CIDR ranges, and whether `NSAllowsLocalNetworking` covers raw private-IP literals is genuinely unsettled — so this section fixes the in-app policy and does not assert a plist posture as settled fact (§15). Under fork-and-build a Builder controls their own Info.plist, so no security property may rest on ATS at all.

The Nightscout source is Backend-mediated: the app pulls the user's Nightscout-derived data from the Backend into the same tables the Bluetooth Drivers write into. No Nightscout URL and no API secret ever exists in the app.

Backend-generated alerts reach the app only while it is alive. APNs is deferred for v1; the device-token field stays in the registration payload, reserved and unwired.

**Functional Requirements:**

#### FR-135: Encrypted local store for all monitoring data

The app stores all pump, Glucose Reading, Bolus, Basal, battery, reservoir, alert, raw pump-history and outbound-queue data in a single encrypted local database that remains readable while the device is locked. Realizes UJ-1, UJ-2. Upholds SI-9, SI-10.

**Consequences (testable):**
- One database holds all nine record kinds; no monitoring data is persisted outside it except settings covered by FR-136 and the Keychain items it names.
- The database file is protected at a level equivalent to complete-until-first-user-authentication, so a background write on a locked device succeeds after the device has been unlocked once since boot; a write during a background wake on a locked device is verified on physical hardware, not in the Simulator.
- Reads and writes issued from a background wake while the screen is off succeed for every record kind.
- No health value, raw device payload, or credential appears in any log emitted at or above debug level from any storage path (SI-9).
- The Watch app never holds its own copy of this store, holds no Backend credential, and issues no Backend request of its own; it renders and decays what the app sends (FR-115, FR-126). There is no independent wrist fetch path in any mode.

#### FR-136: Database key generated once, device-only, never inherited

The app generates the database key exactly once on first run, stores it so only this app on this device can read it, refuses to open the database rather than minting a second key, and purges keys, tokens and pairing secrets left behind by a previous installation before anything reads them. Realizes UJ-3. Upholds SI-10.

**Consequences (testable):**
- The key is 32 bytes from a cryptographic random source, hex-encoded to a 64-character lowercase string.
- The key item is device-only and available after first unlock, never only-when-unlocked and never synchronized to iCloud; a background wake on a locked device can open the database.
- If persisting the key fails, the app surfaces an error and refuses to open the database; it never generates a replacement key, which would orphan existing data.
- On first launch after a fresh install — detected by the absence of a sentinel in storage that app deletion does wipe — the app clears its own database key, auth tokens and pump pairing secrets from the Keychain before any component reads them, then proceeds as a clean install.
- Auth credentials and pump pairing secrets are stored in the Keychain with the same device-only, after-first-unlock accessibility (SI-10). The Backend URL is not a secret and is not stored there.

#### FR-137: Write-time deduplication and cross-source collision resolution

The store rejects duplicate records at write time and resolves same-timestamp collisions between a Backend-mediated record and a Pump-sourced record deterministically and identically to Android. Upholds SI-7.

**Consequences (testable):**
- At most one Glucose Reading per timestamp, one Basal reading per timestamp, one Bolus per (units, timestamp) pair, one raw-history record per pump sequence number, and one alert row per Backend alert identifier.
- Batch writes of Glucose Readings and Basal readings keep the FIRST writer on collision; Bolus writes keep the LAST writer. Both winners are documented in the Parity Ledger's data-provenance note and asserted by test.
- Two genuinely distinct Boluses with identical units at the identical millisecond collapse to one row — a known, accepted consequence of the dedup key, and it is stated rather than silently absorbed.
- Every row carries its source, so a Nightscout-sourced row is distinguishable from a Driver-sourced row after the fact.
- A Glucose Reading from a BGM source Capability (FR-24) is stored in this same table under these same dedup and validity rules, carries the meter name on the row, and is marked BGM-sourced so it is distinguishable after the fact. It never satisfies the fresh-CGM input the Alert Floor gates on (SI-5). Which surfaces render it and whether it participates in analysis are out of scope here (5.3, 5.5).
- Duplicate rejection never raises an error to the caller and never aborts a batch: a colliding row is skipped and the rest of the batch lands.

#### FR-138: Canonical mg/dL storage and rejection of invariant-violating rows

The store keeps every glucose value in mg/dL, converts to mmol/L only at the display boundary, and rejects any row that violates the ABSOLUTE Glucose Validity Bound or the absolute insulin bounds, at write and again at read. Upholds SI-2, SI-3, SI-4, SI-11.

**Consequences (testable):**
- Glucose is stored, transported, compared and threshold-tested in mg/dL. mmol/L exists only as a display conversion, produced from the most precise mg/dL value, converted once with the Conversion Factor 18.0156, and rounded to one decimal last, with a dot decimal separator regardless of the device's locale.
- A value outside the absolute Glucose Validity Bound of 20–500 mg/dL is REJECTED, never clamped, at every storage entry point: reading construction, Backend-mediated ingestion, history extraction and read-back from the store (SI-2).
- Rejection is expressed as a failable or throwing initializer, never a `precondition`; rejection is recoverable, is logged with the bound that was violated, and never terminates the process (SI-2).
- **Two validation gates, different bounds, by design.** Driver-level validation (FR-32) runs against the CURRENT, Backend-narrowable Safety Limits at every validation pass, so a narrowing changes which live readings a Driver accepts without a restart. Storage-layer rejection — this FR — runs against the ABSOLUTE Glucose Validity Bound of 20–500 and never against the narrowed Safety Limits. The asymmetry is deliberate, not a defect: stored rows must survive a Safety Limits change without being retroactively invalidated. Both bounds are asserted by their own tests, and the tests name the asymmetry so a future reader does not "fix" one into the other.
- A Safety Limits change never rewrites, deletes, hides or retroactively invalidates a stored row. A row written before a narrowing is still read back, displayed, uploaded and counted. It is not repaired and not silently corrected.
- The visible consequence is stated rather than inferred: a narrowing changes which NEW Driver-sourced readings enter Time in Range, GMI, CV, the chart and the Alert Floor's input set, and leaves already-stored readings in all of them. Backend-mediated rows (FR-153) never pass a Driver validation pass at all, so they are only ever bounded by the absolute 20–500.
- Bolus rows outside the absolute 0–25 U and ingested Basal rows outside the absolute 0–15 U/hr are rejected by the same rule, with an explicit finiteness check that rejects NaN and infinity.
- Backend-supplied Safety Limits may only NARROW the Glucose Validity Bound and may never widen it; the clamp-on-write, clamp-on-read ordering that enforces this is owned by FR-32 and is not restated here (SI-11).
- The Conversion Factor, the Glucose Validity Bound and the Tandem epoch offset 1199145600 each have exactly one definition, in a module that both the app and the Watch app link (SI-4).

#### FR-139: Retention window bounding every table

The user can choose a data-retention window between 1 and 30 days, defaulting to 7, and the app enforces it across every growing table without the user opening any particular screen. Upholds SI-9.

**Consequences (testable):**
- The setting accepts 1–30 days, defaults to 7, and coerces any out-of-range value into the range.
- One transaction deletes rows older than the cutoff across all six pump-data tables and reports the number deleted.
- The same window bounds the alert history and the raw pump-history table. Alert history follows the user's chosen retention window — 1–30 days, default 7 — and is pruned by the scheduled retention pass, NEVER only when the alerts screen is opened. This FR is the single definition of alert-history retention; FR-87 defers to it by cross-reference and does not restate a fixed 7-day rule.
- The alert-history change is recorded in the Parity Ledger as a deliberate divergence (PD-19): Android pinned alert history at a fixed 7 days and ran its cleanup only on screen open, so a user who never opened the alerts screen was never pruned at all.
- The raw pump-history table is pruned of already-uploaded rows older than the cutoff, and the single highest-sequence row is always retained as the history resume anchor even when it is older than the cutoff. [NOTE: Android defined this cleanup but never called it, so that table grew without bound in full-stack mode.]
- Outbound-queue rows are removed when their retry budget is exhausted OR when they are older than the retention cutoff.
- Retention runs on every execution opportunity subject to a once-per-hour guard, so a user who never opens a particular screen still gets it.
- No table can grow without limit under any mode, including Backend-optional mode.

#### FR-140: Durable local record before any upload, surviving suspension

Every uploadable pump event is durably recorded locally before any upload is attempted, and an upload begun in the foreground completes after the user backgrounds the app without the app continuing to run. Upholds SI-1, SI-7.

**Consequences (testable):**
- The local write happens first and unconditionally; enqueueing for upload is a separate, second step. A failure to enqueue never prevents the local write, and never propagates an error into the poll loop that produced the event — an enqueue failure is logged and swallowed, because a dropped upload row is harmless and a dead poll loop starves the dashboard and the Alert Floor.
- Enqueued events survive app suspension, app termination and device restart until the Backend accepts them or retention drops them.
- The Backend-configured check that gates enqueueing is read once per call, not once per event, so a history backfill batch does not re-read secure storage thousands of times.
- A batch handed to the system for deferred upload is serialized to a file first, so the transfer survives suspension and termination and can relaunch the app on completion.
- Only COMPLETED insulin deliveries are enqueued; SmartGuard auto-basal micro-boluses are excluded from bolus totals at the point of extraction, not filtered later (SI-7).
- Nothing in the outbound payload is a command: the upload protocol carries observations only, with no bolus, basal, pump-setting or device-command field anywhere in it (SI-1).
- The wire quirks are preserved: IOB uploads under the `bg_reading` event type carrying `iob_at_event`; Basal duplicates `pump_activity_mode` into `control_iq_mode` for tolerant older Backends; Glucose Readings are never enqueued.

#### FR-141: Upload failure classification and the retry budget

The app classifies upload failures so that a Backend outage never discards queued events, while a permanently rejected batch is eventually dropped instead of blocking every newer event behind it.

**Consequences (testable):**
- A transport failure, or an HTTP 408, 429, 502, 503 or 504, marks the batch failed and stamps its attempt time but does NOT increment its retry count.
- Any other non-2xx response increments the retry count. At 5 retries the row becomes ineligible and is removed by the next cleanup pass.
- This retry budget bounds an outbound upload batch and nothing else. It is not a connection policy: Pump reconnection has no attempt cap, no maximum-failures abort and no give-up condition (FR-13), and no backoff ladder in this section may be read as introducing one.
- Retry eligibility is computed from stored timestamps: a failed row becomes selectable again after 2000 ms × 2^retryCount, giving 2s, 4s, 8s, 16s and 32s.
- A row left in the in-flight state by a process death returns to pending after a stale timeout. [ASSUMPTION: the reclaim window is 15 minutes on iOS, not Android's 60 seconds, because a system-deferred background upload legitimately takes longer than a minute; a shorter window would re-send batches the system is still holding.]
- Only the network call is inside the failure-classification boundary; a local storage failure after the Backend accepted the batch is never mislabeled as an upload failure.
- On acceptance the app records the accepted, duplicate, raw-accepted and raw-duplicate counts the Backend reports, and clears the last-error state.
- A batch that runs twice because the system retried a deferred transfer is absorbed by Backend-side deduplication; the app does not attempt to prevent it.

#### FR-142: Bounded outbound queue and its user-visible state

The outbound queue is bounded, evicts oldest-first at the bound, and the user can see how many events are waiting and when the last successful upload happened.

**Consequences (testable):**
- When the queue exceeds its bound, the OLDEST undelivered rows are dropped until it is back under. In-flight rows are never evicted. Retryable failed rows ARE eligible for eviction, because during an outage the whole backlog dwells in that state and a narrower rule would let the queue exceed its cap.
- The bound is **20,000 rows**, raised from Android's 5,000, sized so that a full day with no successful upload discards nothing: at the 15-second fast cadence the enqueue rate is roughly 8 rows per minute, so 5,000 rows is about 10 hours, and an iPhone suspended overnight exceeds that and would silently discard the oldest Pump history. This figure is the enforced cap; every other section that quotes a queue capacity quotes this one (NFR-7, NFR-16, PD-23).
- Data loss at the cap is the intended policy and is stated to the user in the sync surface, not discovered.
- The pending count and the last-successful-upload time are observable and update as the queue changes.
- The pending count excludes rows currently in flight, and the surface labels it so a dip during an in-flight push does not read as data disappearing.
- The last-error string, when present, is shown alongside the last-success time rather than replacing it.

#### FR-143: Backend-optional transitions

Removing the Backend URL leaves a fully functional local monitor; adding one resumes syncing without an app restart; signing out preserves both. Realizes UJ-2. Upholds SI-5.

**Consequences (testable):**
- A non-blank stored Backend URL is the single canonical signal for whether a Backend is configured. Every dependent behavior observes that one signal rather than re-deriving it from ad-hoc checks.
- With no Backend URL: no outbound row is ever created, no Backend request is attempted (the request fails at configuration resolution, before touching the network), the outbound queue is purged, and all raw pump-history rows except the highest-sequence anchor are deleted. The purge sweep repeats on subsequent opportunities, because a Driver keeps producing raw rows and an enqueue can race the mode change.
- Backend-optional mode makes NO network request to any host that carries or receives health data. There is exactly one permitted exception — the upstream-release check (FR-188), which contacts only the upstream release API, carries and receives no health data, is user-toggleable and is OFF by default. NFR-23's "no network requests at all" is read against this exception, not around it.
- In Backend-optional mode the user can set Alert Thresholds locally on the device, and those thresholds arm the Alert Floor. A valid Backend fetch later replaces them and records an audit line; the local editor is offered only while no Backend is configured (SI-5).
- Removing the Backend URL also clears Backend-provenance Alert Thresholds, so the Alert Floor can never keep firing values a now-Backend-less user never chose. Thresholds the user set on this device survive.
- Adding a Backend URL starts syncing without an app restart or a re-launch.
- Signing out is NOT this path: it preserves the Backend URL and the queued events, which drain on the next successful sign-in. It clears Backend-provenance Alert Thresholds, Safety Limits and per-account settings, and leaves Alert Thresholds the user set on this device intact. This bullet and the one above are the single definition of threshold clearing across sign-out and mode change; FR-82 and FR-167 defer to them by cross-reference and do not restate the rule.
- Transitioning from full-stack to Backend-optional mode deletes undelivered queued events; the user is warned before the transition, not after.

#### FR-144: Opportunity-driven background work

The app attempts queue drain, retention, Alert Threshold refresh and Backend-mediated Nightscout sync (FR-154) at every execution opportunity the system grants it, rather than on a fixed interval. Realizes UJ-2.

**Consequences (testable):**
- The recognized opportunities are: app activation or scene foregrounding, every Bluetooth wake, a system-scheduled background refresh, a system-scheduled background processing window, and completion of a deferred upload.
- While the app is foregrounded and a Backend is configured, the drain runs on a 3-second tick with immediate wake on an explicit trigger, identical to Android. Many rapid triggers collapse into one wake.
- Local hygiene — stale-in-flight reclaim, queue pruning, retention cleanup — runs even when the queue cannot be drained, throttled to at most once per 60 seconds rather than on every tick.
- Alert Threshold refresh runs at every opportunity but is throttled by a 1-hour staleness check, so Backend-side threshold edits reach the Alert Floor within the hour at a cost of at most one request per hour (SI-5).
- Every background handler completes or aborts cleanly within the window the system granted and always reports completion, so repeated expiry does not cause the system to throttle future scheduling.
- No path assumes an opportunity will arrive. Missing opportunities delay delivery; they never lose or corrupt an event.

#### FR-145: Capture-time freshness and detected collection gaps

The data layer derives freshness from each record's own capture timestamp and detects and reports a gap in collection when the app resumes after not running. Realizes UJ-1. Upholds SI-6.

**Consequences (testable):**
- Freshness Tier for any record is computed against that record's own sensor or pump timestamp, never against the time the app fetched, ingested or stored it. A frozen Nightscout feed ages out exactly like a frozen Bluetooth feed.
- Every value the data layer hands to the Coverage Claim carries its capture timestamp, so the claim can decay without new data (SI-6).
- On launch, the app compares the newest stored Glucose Reading's capture timestamp against the current time and, when the gap exceeds the Too Stale bound, records and surfaces a collection gap with its duration.
- The data layer supplies the Not-Watching Reason inputs it owns — no Backend configured, no recent stored reading, Local Network access denied, upload failing — to the Coverage Claim; it never composes the claim itself (that belongs to 5.4).
- A backward wall-clock movement suppresses freshness claims rather than making stale data look recent.
- The app never presents a fetch time as a capture time on any surface.

**Out of Scope:**
- The wording, decay policy and expiry semantics of the Coverage Claim (5.4).
- Onboarding copy about restart and force-quit consequences (5.9).

#### FR-146: Resumable, cancellable initial history download

After a Pump is paired, the app downloads the pump's multi-month history as a user-visible, cancellable, resumable foreground task with accurate progress, and never advances its cursor past a record it did not decode. Realizes UJ-4. Upholds SI-8.

**Consequences (testable):**
- The download runs in the foreground with the screen kept awake and a progress indication, not as unattended background work, because it can take up to 20 minutes and no iOS background window is that long.
- Resume is anchored on the highest stored raw-history sequence number. A resumed download starts from that anchor and does not restart; an absent anchor (fresh install, or a purged raw-history table) triggers the full download.
- The cursor advances only past records that were successfully decoded. A decode failure stops the advance at the last good record (SI-8).
- If a batch's maximum sequence number does not exceed the current anchor, the download stops with a non-advancing-history diagnostic rather than looping.
- Batches are staggered 1 second apart so the live poll loop gets a window, and each batch is persisted and uploaded incrementally rather than at the end, so a cancellation keeps everything already downloaded.
- Cancelling is immediate and leaves the anchor at the last completed batch; resuming continues from there.
- Incremental (non-initial) history catch-up is bounded at 2 minutes; the initial full download is bounded at 20 minutes.
- Records extracted from history are subject to the same rejection rule as live data: out-of-bound values are dropped, never clamped (SI-2).

#### FR-147: Staying signed in with proactive token refresh

The user stays signed in across app restarts, and the access token is refreshed before it expires whenever the app has execution time — and specifically before any upload is handed to the system for deferred delivery.

**Consequences (testable):**
- The app checks whether the access token expires within 5 minutes at app activation, at every background execution opportunity, and as a precondition of handing an upload to the system.
- A deferred upload is never handed to the system carrying a token that will have expired by the time the system is likely to run it.
- A foreground timer scheduled 5 minutes before expiry is an optimization only; correctness never depends on it firing.
- Startup validation resolves to exactly one of: unauthenticated (no refresh token), expired (refresh token expired), authenticated (valid access token), or refreshing.
- Refresh retries at most 3 times with 1s then 2s backoff; a transient failure reschedules no sooner than 60 seconds later, so an outage does not produce back-to-back attempts.
- A transient failure that leaves a stored access token keeps the session authenticated rather than showing a false session-expired state.
- The refresh request uses its own short-timeout transport (10 seconds connect, read and write) that carries no auth and cannot itself trigger a refresh.

#### FR-148: Exactly one serialized refresh per 401, and sign-out always wins

A 401 triggers exactly one serialized refresh-and-retry shared across all concurrent requests, and signing out always beats an in-flight refresh.

**Consequences (testable):**
- Concurrent requests that all receive 401 produce exactly ONE refresh call; the others await its result. A refresh token is never rotated twice concurrently, which the Backend's replay detector would reject.
- The proactive path and the reactive 401 path share the same serialization primitive; there is no second refresh path.
- The fast path returns the stored token only if it differs from the token the failing request actually carried, which is null when the header was omitted because the stored token had already expired. This both fixes the omitted-header case and prevents an infinite refresh loop when the Backend 401s a fresh token for an unrelated reason.
- A refresh attempt against the refresh endpoint itself is never made.
- Sign-out increments a session generation before clearing stored credentials; any refresh in flight snapshots the generation on entry and discards its result on mismatch. A refresh that completes after sign-out never restores a session and never re-persists a token.
- A late 401 or a late refresh failure cannot overwrite a deliberate sign-out with a session-expired state.
- The five refresh outcomes are distinguished and handled distinctly: local precondition failure preserves the store; a 401/403 from the Backend clears the token; a sign-out mid-flight touches nothing; a 5xx or unparseable body preserves tokens; a transport failure preserves tokens.

#### FR-149: Offline session expiry without data loss

A session that expires while the device is offline tells the user plainly to sign in again, without erasing the Backend URL, the user's email address, or any local data, and without blocking local monitoring. Realizes UJ-2. Upholds SI-5.

**Consequences (testable):**
- The message is a session-expired prompt, not a re-onboarding flow.
- The Backend URL, the user's email address and the entire local store survive; the queued events survive and drain after the next successful sign-in.
- Start-of-app routing keys on onboarding completion alone, never on whether a session is active, so an expired refresh token cannot route an offline user to onboarding and lock local data behind a sign-in that cannot succeed.
- Local Glucose Readings, history and analysis remain viewable, and the Alert Floor remains armed if its thresholds were configured (SI-5).
- The app does not render any session prompt off its pre-validation startup state, so a prompt never flashes at cold start.

#### FR-150: Cleartext transport policy

The app refuses plaintext HTTP to any host that is not a literal loopback, private, carrier-NAT or link-local address or a `.local` name, enforced both when the URL is saved and again on every request, classifying by literal address only and never by DNS resolution. This FR and FR-151 are the single definition of the cleartext policy and of the private-address classification; FR-163 and NFR-20 defer to them by cross-reference and do not restate the range list.

**Consequences (testable):**
- `https` is always permitted. `http` is permitted only when the host classifies as private AND the user has explicitly opted in (FR-151). Any other scheme is refused. The rule is a conjunction, never a disjunction.
- The rule is IDENTICAL in every build configuration. No debug, TestFlight or release configuration widens it, because under fork-and-build a Builder can install a debug configuration through their own TestFlight and a configuration-dependent exemption would ship to a real user's phone.
- Accepted private ranges: IPv4 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 and 169.254.0.0/16; IPv6 `::1`, `fe80::/10` and `fc00::/7`; IPv4-mapped `::ffff:a.b.c.d` classified by the embedded IPv4; and host names ending in `.local`, the one deliberate name-based exception, with a bare `.local` rejected.
- IPv4 parsing is strict: exactly four dot-separated base-10 octets, 1–3 digits each, no leading zeros, each ≤ 255. Octal (`012.0.0.1`), hex (`0x0a000001`) and bare-decimal (`2130706433`) encodings are rejected.
- The classifier NEVER performs a DNS lookup — a name-to-address resolution would invite DNS rebinding and block the calling thread.
- The policy is enforced at save time and independently at request time, so a URL saved while the opt-in was on can never issue a cleartext request after the opt-in is turned off.
- The two refusal messages are distinct and actionable: "Insecure LAN HTTP is off. Enable it in Settings, or use https://." for a private host pending opt-in, and "Refusing cleartext HTTP to a non-private host. Use https:// or a private/LAN address." otherwise.
- The in-code classifier is authoritative and is the sole enforcement mechanism. Because a Builder controls their own Info.plist, no security property in this PRD depends on App Transport Security at all.
- **Architecture to verify, not a settled requirement:** which Info.plist ATS configuration achieves this baseline is an open architecture decision requiring empirical verification on a device. ATS exceptions are per-domain and accept neither IP addresses nor CIDR ranges, and whether `NSAllowsLocalNetworking` covers raw private-IP literals rather than only single-label and `.local` names is unverified. No section may state a plist posture as fact until that verification lands (§15). Whatever architecture records as the verified baseline is what the Entitlements and Plist Guard (5.11 FR-204) then guards against being broadened.
- A Backend URL carrying a path, query or fragment is rejected at save time with a specific message. [ASSUMPTION: this deliberately diverges from Android, which silently ignored a path prefix and then requested a different URL than the user typed.]

#### FR-151: Local network reachability — permission, denial copy, and the insecure-HTTP opt-in

The app requests Local Network access before contacting a Backend on the local network, reports a denial as a permission problem, and lets the user explicitly opt in to insecure LAN HTTP with a persistent indicator while it is in effect. Realizes UJ-3.

**Consequences (testable):**
- The app declares a Local Network usage purpose string that names why it needs the local network (reaching the user's self-hosted Backend).
- A denied Local Network grant is surfaced as "Local Network access is off for this app" with a route to Settings — never as a generic connection failure, a timeout, or an unreachable Backend.
- Local Network reachability is verified on physical hardware before release; a Simulator result is treated as no result, because the Simulator uses the Mac's network stack and never shows the prompt.
- The insecure-LAN-HTTP opt-in defaults OFF, is per-device, and is NOT reset on sign-out — the LAN box is the same box across sign-ins.
- When a private-host `http://` URL is entered while the opt-in is off, the app offers a one-tap opt-in rather than a dead-end error.
- A persistent indicator is shown whenever cleartext traffic is actually in effect — that is, when the scheme is `http` AND the policy permits it — not merely because the stored URL begins with `http://`.
- The setup documentation names https with a privately trusted certificate authority as the preferred alternative, since iOS trusts user-installed CA certificates by default and this avoids cleartext entirely.

#### FR-152: Three connectivity states

The app reports exactly three connectivity states — device offline, Backend unreachable, reachable — with device-offline taking precedence. This FR is the single definition of how reachability is derived; FR-44 owns only the rendering of the indicators and defers here for the derivation.

**Consequences (testable):**
- Device offline wins: with no network the app cannot distinguish a Backend outage from a missing radio, so it reports offline rather than misattributing.
- A local-network-only connection with no internet route counts as ONLINE, because a self-hosted Backend on the LAN is exactly that case.
- The device signal is seeded pessimistically from the current path before the first update, so a cold start on an offline device reports offline immediately rather than optimistically.
- Backend reachability is derived entirely from traffic the app already makes; there is no dedicated health-probe loop and no health-check endpoint exists.
- Any HTTP response, including 4xx and 5xx, records a success and resets the failure counter. Only a transport failure records a failure, and only when the request was not cancelled.
- The state flips to Backend-unreachable only after 2 consecutive transport failures with no intervening success.
- Long-running AI inference requests are excluded from the reachability signal: a 90-second inference timing out is not evidence the Backend is down.
- A transition to reachable triggers reconciliation of any pending offline alert acknowledgements.

#### FR-153: Backend-mediated Nightscout source

The user can enable a Nightscout data source that pulls their Nightscout-derived Glucose Readings, Bolus and Basal data from their own Backend account into the same local store the Drivers write into, with no Nightscout client, URL or API secret in the app. This FR is the single definition of the source's behavior; FR-38 keeps only its Capability declaration and defers here.

**Consequences (testable):**
- The app never contacts a Nightscout instance directly. It reads Nightscout-sourced data only from the Backend. No Nightscout URL and no Nightscout API secret is ever stored, entered, or transmitted by the app.
- The source is OFF by default, and disabling it retains already-synced data rather than deleting it.
- The activation control is not offered when no Backend is configured — unless the source is already active, in which case turning it off stays reachable.
- The surface shows the last successful sync time and a distinct state for each of: never synced, healthy, no Nightscout connection configured, re-authentication required, and sync error that will be retried. The last successful sync time stays visible while an error state is shown.
- The user can trigger an immediate sync and see the state update in place without leaving the screen.
- When the account has more than one active Nightscout connection the user chooses which one syncs; when exactly one exists no choice is presented.
- An explicit connection choice is honored only while that connection is still active. A deleted or deactivated choice reports "no Nightscout connection" rather than silently syncing a different connection into the same tables.
- Ingested rows are validated and dropped at the boundary, never clamped and never thrown: Glucose Readings outside the ABSOLUTE Glucose Validity Bound of 20–500 mg/dL are dropped (SI-2); Bolus rows are accepted only for event types `bolus` and `correction` with units in 0–25 U; `combo_bolus` is deliberately EXCLUDED because it can carry an extended temp-basal portion that would inflate Bolus totals and IOB (SI-7); Basal rows require units in 0–15 U/hr with an explicit finiteness check.
- The bound applied here is the absolute one, deliberately NOT the Backend-narrowable Safety Limits. Backend-mediated rows enter the store directly and never pass a Driver's FR-32 validation pass, so the storage-layer gate of FR-138 is the only gate they cross. This is the same deliberate asymmetry FR-138 states, seen from the ingest side; it is not an oversight and must not be unified with FR-32.
- A `correction` row is marked automated regardless of the upload's own flag; user doses arrive as `bolus`.
- Every ingested row carries the source marker `nightscout-source`, and Basal activity mode is left empty because Nightscout carries none.
- Logging records row counts and HTTP status only, never glucose values, insulin doses, or connection credentials (SI-9).

#### FR-154: Nightscout sync execution — cursor, paging and clean abort

Nightscout sync is best-effort background work that never implies freshness the platform did not deliver, aborts cleanly within its window, and persists its cursor so the next run resumes from the same point.

**Consequences (testable):**
- Each run pages 500 records per array from a per-connection cursor. The cursor is inclusive, and boundary duplicates are absorbed by the write-time dedup of FR-137; there is no separate deduplication pass.
- Cursor advance rule: if neither array came back full, advance to the overall maximum and stop; if at least one came back full, advance only as far as the MINIMUM of the full streams' maxima, so a lagging stream's un-fetched tail is never skipped.
- If the computed next cursor would not advance — a page saturated by more than 500 records sharing one millisecond — the run persists its progress and reports a transient error rather than a false success that would drop the tail.
- The cursor is persisted after EVERY successful page, not once at the end, so a background window that expires mid-run loses nothing. [NOTE: Android persisted only on loop exit; a 30-second window makes per-page persistence mandatory.]
- Each background run is bounded by both a wall-clock deadline of roughly 20 seconds and an iteration cap, and cancels cooperatively when the system signals expiry. Cancellation is never swallowed into a retry.
- A first-time full backfill is never attempted inside a short background window; it runs in the foreground or in a long-form processing window.
- Outcome classification: disabled, no Backend, no connection, success and re-authentication-required are all TERMINAL for the run — retrying cannot help until the user or the environment changes. Only a transient outcome requests a sooner retry. HTTP 401, 403 and 404 map to re-authentication-required and do NOT retry.
- The app requests a background refresh opportunity roughly every 15 minutes and reschedules at the START of every handler run, and additionally syncs at app activation and on every Bluetooth wake. Delivery cadence is never promised in the UI; the last-sync time and the readings' own capture timestamps are the only freshness statements (SI-6).
- When no Backend is configured the sync stands down, cancels any orphaned schedule, and retains its activation flag so sync resumes if a Backend reappears. A run that races the mode change terminates as no-Backend rather than retrying forever on a condition only the user can resolve.

#### FR-155: Tolerant reader with loud failure on missing consumed fields

The app tolerates unknown fields in every Backend response, applies the documented default for every absent optional field, and fails loudly when a field it actually consumes is missing. Upholds SI-12.

**Consequences (testable):**
- An unrecognized field in any Backend response is ignored; the response still decodes (SI-12).
- A renamed, removed or type-changed field that the app CONSUMES fails to decode loudly rather than defaulting silently (SI-12).
- Every field that carries a documented default — including `is_automated` (false), `acknowledged` (false), `raw_accepted` (0), `raw_duplicates` (0) and `source` ("mobile") — decodes correctly when the key is ABSENT. Swift's synthesized decoding does not apply property defaults for absent keys and must be overridden field by field (SI-12).
- Backend timestamps are accepted with or without fractional seconds.
- A Backend response carrying Alert Thresholds, a target glucose range, or Safety Limits that fails validation is DROPPED, never clamped, leaving last-known-good values in place. Ordering is validated on the RAW Backend values before any rounding, because rounding two Backend-legal values less than 1 mg/dL apart can collapse them to equal integers and permanently disarm the Alert Floor (SI-5, SI-11).
- Validation rules preserved exactly: target range requires all four values in 20–500 after rounding and strict ordering urgent-low < low < high < urgent-high; Alert Thresholds require strict ordering on the raw floats and all four rounded values in 20–500; Safety Limits reject min ≥ max, min outside 20–499, max outside 21–500, basal outside 1–15000 milliunits/hr, or bolus outside 1–25000 milliunits.
- **Safety Limits must additionally admit a usable accept window, and are rejected atomically when they do not (SI-11, SI-5).** A payload is rejected if `max - min < 100` mg/dL, or if the window does not contain all four currently configured **Alert Thresholds**. Without this, `min=100, max=101` passes every ordering and bounds check, FR-32's live Driver gate then discards every reading the **Pump** produces, and the app reports Not Watching — a silent, unbounded monitoring kill switch reachable from a **Backend** misconfiguration, in the direction SI-11 explicitly permits (narrowing). The user's most likely reading of that state is a failed sensor, so they replace hardware that is working. A test supplies a 1 mg/dL window and asserts the payload is rejected, the previous limits stay in force, and monitoring continues.
- When the accept window admits no readings for longer than one Fresh boundary, the Coverage Claim reports `SAFETY_LIMITS_TOO_NARROW` — never `NO_FRESH_READING` — because readings are arriving and the app is discarding them (FR-83).
- A 401 or 403 on the meal-intelligence setting fails CLOSED to disabled, so a cached or default-on value cannot leave meal surfaces visible for an account the Backend rejects.

**Out of Scope:**
- The Contract Pin itself and the CI checks that guard it (5.11).

#### FR-156: Device registration as an iOS device

The app registers itself with the Backend as an iOS device using a stable per-installation identifier and deregisters on sign-out; a registration failure never blocks use of the app.

**Consequences (testable):**
- Registration sends platform `ios` and a build type of `debug` or `release`, both already present in the pinned contract's enumerations.
- The per-installation identifier is generated once, stored locally, and reused for the life of the installation; it is cleared by the fresh-install purge of FR-136.
- The device fingerprint is a SHA-256 of the vendor identifier combined with the bundle identifier. The Android signing-certificate component is dropped; it has no iOS equivalent under fork-and-build, where every Builder signs with their own certificate.
- The device name is the device model plus a short install-scoped suffix, so two iPhones are distinguishable in the Backend's device list. The user-assigned device name is not used; it requires an entitlement the project does not hold.
- The Watch app does not register separately; it has no independent Backend-alert delivery path and no Backend credential of its own. Its wrist alerts come from the app's payload, not from the Backend (FR-128).
- Registration runs on a task tied to the app, not to the sign-in screen, so backgrounding that screen mid-flight does not cancel it. [NOTE: this fixes an Android defect where six post-login fetches ran on the screen's scope.]
- A registration failure is logged and the app continues to function; nothing is blocked.
- Deregistration on sign-out is best-effort and clears the local identifier regardless of the response.

#### FR-157: Backend-alert transport posture — SSE while alive, APNs reserved

Backend-generated alerts reach the app over a live event stream only while the app is running; APNs is deferred for v1 and the device-token path is reserved but unwired. Upholds SI-6.

**Consequences (testable):**
- The event stream runs only while the app is alive and is torn down at suspension. It is never claimed to run in the background.
- Stream transport parameters are preserved: 30-second connect and 75-second read timeout, sized at 2.5 times the Backend's 30-second heartbeat so one fully missed heartbeat is tolerated while a silently dead stream is detected promptly.
- Pending Backend alerts are pulled at every execution opportunity as a supplement to the stream, and deferred acknowledgements are pushed BEFORE any pull so a pull cannot resurrect an alert the user already acknowledged offline.
- The device-token field remains in the registration payload but is not populated from APNs, no push entitlement is requested, and no push registration is performed in v1.
- The app does not present itself as receiving Backend alerts while suspended or terminated. Coverage while the app is not running is the Alert Floor only, and the Coverage Claim says so (SI-6).
- This posture governs Backend-generated alerts only. Wrist delivery of an Alert Floor alert is a separate mechanism and is NOT this path: the wrist notification is scheduled on the Watch itself (FR-128, FR-129). iPhone notification mirroring is the fallback, never the mechanism, because mirroring does not fire while the iPhone is unlocked and in use — a common daytime state that would otherwise produce a silent wrist.
- Adding APNs later requires no contract change to the registration payload.

**Out of Scope:**
- Alert semantics, deduplication, acknowledgement UX and the Coverage Claim's wording (5.4).

#### FR-158: Scrubbed diagnostic log export

The app keeps a bounded in-app log buffer and lets the user export it, scrubbed of tokens, email addresses and health values, and states on the exported artifact that the buffer has gaps for every interval the app was not running. Realizes UJ-3. Upholds SI-9.

**Consequences (testable):**
- Release builds emit at warning level and above only; no health value, raw device payload or credential appears in any log at or above debug level (SI-9).
- Four scrubbing rules are applied before emission and again before export: JWT-shaped tokens → `[TOKEN]`; email addresses → `[EMAIL]`; a 2-to-3-digit value followed by `mg/dL` → `[BG]`; a 1-to-2-digit value with one decimal followed by `mmol/L` → `[BG]`. (`[TOKEN]`, `[EMAIL]` and `[BG]` are literal replacement tokens, not vocabulary.) These four rules have exactly one definition, here; NFR-24 states the system-wide obligation and defers to this FR for the rules themselves.
- **iOS-specific trap, stated because a naive port hits it:** the unified logging system treats interpolated numeric values as public by default while redacting dynamic strings, so a health value interpolated into a log line is published to the system log even though the scrubber never saw it. Every interpolation of a health value, identifier or secret is explicitly marked private or omitted, and a lint gate checks it (SI-9).
- All glucose formatting uses a dot decimal separator regardless of device locale, so mmol/L output still matches the scrubber (SI-3).
- The buffer is bounded and in memory; raw device packet traces exist only in non-release builds and are never written to disk unencrypted.
- The export is user-initiated, produces a shareable text artifact, and shows the user what it contains before sharing.
- **The export states its own gaps, on the artifact.** iOS suspends and terminates the app, so the buffer holds no entry for any interval in which no code ran. The exported artifact carries that statement in plain words — an empty interval means "the app was not running **or** nothing happened", and the export cannot distinguish the two — because a reader who takes silence for health will misdiagnose. A test asserts the statement is present in every export, and it is shown in the pre-share preview along with the rest of the contents. This FR carries the disclosure on the artifact; NFR-33 states the system-wide obligation and §7 PL-72 records the parity loss (Android's foreground service produced a continuous process-level record that iOS cannot).
- The export exists because iOS gives users no way to read an app's system log — a Builder or TestFlight tester reporting a bug otherwise has nothing to send (UJ-3).

**Feature-specific NFRs:**
- Every storage and transport behavior that depends on device-lock state or Local Network privacy MUST be verified on physical hardware. A Simulator result for file protection, Keychain accessibility, Local Network permission, background task scheduling, deferred upload survival or low-power mode is treated as NO result.
- Every background path — queue drain, retention, Alert Threshold refresh, Nightscout sync, token refresh, deferred-upload completion — MUST be independently invokable from a debug surface so its logic is testable in the Simulator without waiting for the system to schedule it.
- Persistence, dedup, retry classification, Backend-optional mode transitions and the collection-gap detector MUST all be exercisable end to end against the Simulated Driver and the Trace-Replay Driver, with no physical Pump present. This is a hard requirement, not a convenience: Core Bluetooth does not exist in the iOS Simulator and the lead developer has no iPhone.
- The fault-injection surface (FR-176, which owns it) MUST be able to force the Backend unreachable and accelerate staleness, so the three connectivity states, the retry classification and the freshness paths are reachable without a real outage.

**Notes:**

[NOTE FOR PM] Parity losses this section produces, for the Parity Ledger:
1. There is no guaranteed periodic background execution. Android's retention worker (guaranteed daily) and Nightscout periodic sync (guaranteed 15-minute floor) become opportunistic on iOS and may not run for days on a rarely opened app.
2. The outbound queue does not drain continuously in the background. Android's foreground service drained every 3 seconds forever; iOS drains in the foreground and in system-granted windows only, so upload latency is materially worse and has no upper bound.
3. After an iPhone restart or a force-quit, no data is captured, no upload occurs, and no alerting happens until the user opens the app. Android's boot receiver has no substitute and no code can run to detect the condition while it holds.
4. Backend-generated alerts do not reach a suspended or terminated app (per settled decision 7, APNs deferred). The event stream is foreground-only and background pulls are opportunistic.
5. Deferred uploads may be marked discretionary by the system and held for an unbounded time; the app cannot force delivery.
6. Local Network access is an additional gate with no Android analog: a user can deny it and thereby break a LAN Backend in a way that presents as a dead Backend unless the app names it.

[NOTE FOR PM] Android defects closed by this port rather than reproduced: the raw pump-history cleanup that had zero production callers (FR-139); alert retention that ran only when the alerts screen was opened (FR-139); post-login fetches running on the sign-in screen's scope (FR-156); and a Backend URL's path prefix being silently dropped (FR-150).

*For the Parity Ledger (deliberate divergences this section contributes):*
- **Two Android constants are deliberately changed for iOS**, both because iOS defers work Android performed immediately and Android's values would discard Pump history during a normal overnight suspension. The outbound queue bound (5,000 → 20,000 rows) is **settled by product ruling** and is no longer an assumption; FR-142 is the enforced cap. The stale-in-flight reclaim window (60 seconds → 15 minutes) remains an assumption needing sign-off (A-30).
- **Alert-history retention is likewise settled by product ruling**: alert history follows the user's 1–30 day window (default 7) and is pruned on the scheduled retention pass, never on alerts-screen open. FR-139 is the single definition and FR-87 defers to it.
- **The two-gate glucose validation asymmetry.** The Driver gate (FR-32) runs against the current, Backend-narrowable Safety Limits; the storage gate (FR-138) runs against the absolute 20–500 mg/dL. Android carried three inconsistent regimes; iOS carries two, deliberately. Both FRs state the asymmetry in their own words so a future reader does not collapse one into the other.

**Open questions:**
- What is the real per-Driver enqueue rate? The 20,000-row bound is fixed, but it is sized from Tandem's 15-second fast cadence; a Driver with a materially different cadence changes the day-without-upload arithmetic and would be evidence for revisiting the figure in a later release.
- Which Info.plist App Transport Security configuration actually achieves FR-150's baseline on a device? ATS exceptions are per-domain and accept neither IP addresses nor CIDR ranges, and whether `NSAllowsLocalNetworking` covers raw private-IP literals — rather than only single-label and `.local` names — is unverified. Architecture owns the answer and it must be verified empirically before any section states a plist posture as fact; until then FR-204's guard has no baseline to guard.
- Under fork-and-build, is a Builder who edits ATS values in their own fork still inside the supported build surface (5.10)?


### 5.9 Onboarding, Settings and Accessibility

**Description:**

Onboarding is the app's consent gate and its mode-selection fork, and on iOS it is also where three
one-shot platform decisions are spent: notification authorization, Bluetooth authorization, and Local
Network permission. All three prompt once per install and none can be re-asked from inside the app.
That makes onboarding safety-critical rather than decorative.

The flow is five stages — Welcome, Features, Safety Acknowledgement, Backend setup, Sign-in. Swiping is
disabled from the Safety Acknowledgement stage onward; only the explicit "I Understand" button advances
it, and Skip on the first two stages jumps *to* that stage, never past it. The acknowledgement carries
five cards, one of which names the prohibited action for the only AI-vision feature verbatim: never use
a photo carb estimate to calculate an insulin dose or bolus. Marcus (UJ-3), who has never opened App
Store Connect, meets this before he meets anything else.

The Backend stage is optional and says so. A Builder can type a URL and test it before signing in; the
test persists the typed URL first so the request layer routes to it, and restores the previous
known-good value if the test fails. Two iOS-only failure modes sit under that test. First, App Transport
Security rejects cleartext before the app's own policy runs, so the insecure LAN HTTP opt-in depends on
an Info.plist posture. That posture is an architecture decision, not a product requirement, and it is
not settled here. The product requirement is FR-150 / NFR-20: no cleartext to any host that is not
loopback, private (RFC1918), carrier-NAT (100.64.0.0/10) or link-local, enforced in-app by strict
literal-address classification and never by a DNS lookup. Whether `NSAllowsLocalNetworking` covers raw
private-IP literals is genuinely unsettled and must be verified empirically; architecture records the
verified baseline, and 5.11's Entitlements and Plist Guard (FR-204) then guards against broadening
beyond it. Second — and this is the one that will burn every self-hoster — iOS 14+ Local Network
Privacy blocks any connection to an RFC1918
address, a `.local` name, or the link-local range until the user grants permission, denial is permanent
until they visit Settings, and **the Simulator neither presents nor enforces the prompt**. With the lead
developer having no iPhone (decision 10), the entire Simulator loop will show a working LAN connection
while every real device fails opaquely. The app must therefore name that condition specifically and
distinguishably, never as a generic "Connection failed".

Finishing without a Backend is a first-class path, not a fallback: it puts the app in Backend-optional
mode as a direct pump monitor. Taking it cancels any in-flight connection test *before* clearing the
saved URL (the test persists a URL before it resolves and its failure branch can restore one), and
clears Backend-supplied Alert Thresholds so a departed Backend's values are never left arming the Alert
Floor. Both completion paths then request notification and Bluetooth authorization and resolve them
before navigating away — because the Alert Floor is silently suppressed without notification permission,
and a user in Backend-optional mode with no permission would believe they are monitored when they are
not.

Settings is a single scrolling screen that refreshes on every appearance. Backend-optional mode hides
what would be a claim about a Backend that does not exist — the Backend sync control, the whole Meal
Intelligence section, the AI notification sound row — and flips the Alert Thresholds editor from
read-only to editable. Thresholds are the sharpest surface here: with a Backend the Backend is master
and the app shows four values it cannot edit; in Backend-optional mode the user sets all four in their
chosen unit, stored canonically in mg/dL, rejected never clamped when out of the Glucose Validity Bound
or out of order, and written durably before the save reports success. Until all four exist from a real
source, Settings says in error styling that on-device alarms are off — the Alert Floor never fires from
defaults (SI-5). Priya (UJ-2) depends on every one of those properties holding overnight while the phone
is locked.

The notification status card is the honest-degradation surface for this section. Android had one axis:
permission granted or not. iOS has many that can each silently mute an alarm — authorization, alert,
sound, critical alerts, Time Sensitive, lock screen, Notification Center, and Scheduled Summary, which
can delay a non-time-sensitive notification by hours. A binary "Enabled/Disabled" card would report
Enabled while the alarm is summarized into oblivion. The card reports each condition separately with its
own Settings link, and its conditions are the same vocabulary the Coverage Claim uses for its
Not-Watching Reason (SI-6).

Several Android capabilities have no iOS shape at all and are written here for what iOS *can* do: there
is no system sound picker (a curated bundled set with in-place preview is the forced substitute, FR-67),
no notification channel model (per-category preference lives in the app; muting the app in iOS Settings
mutes everything at once), no way to raise system volume and therefore no volume control anywhere
(FR-66), no watch-face gallery, face push or face theme, and no in-app self-update or watch-app push.
Each is a recorded Parity Ledger entry, not a v1 cut.

Accessibility is a contract, not polish. Every element that carries a Compose `testTag` on Android
carries the identical string as an accessibility identifier on iOS. That identifier set and the combined
VoiceOver descriptions are the acceptance substrate for every Simulator-runnable gate in this project;
the parity RULE — a generated registry diffed against the Android source, with no pinned count — is stated once in NFR-30 and is cited, never restated, here. With no iPhone, no
Apple Watch and no Core Bluetooth in the Simulator, XCUITest driven off those identifiers is
most of what the lead developer can actually verify. Sam (UJ-1) additionally depends on every state that
colour carries also being carried by text, shape or position, because watchOS tinted and accented
complication rendering flattens the colour vocabulary entirely.

[ASSUMPTION: the app's display name in permission-fallback copy is "GlycemicGPT", matching Android's
strings; the fork's bundle display name is a Builder-controlled value and the copy reads from it.]

**Functional Requirements:**

#### FR-159: First-run onboarding flow and stage gating

A first-run user can move through five ordered onboarding stages — Welcome, Features, Safety
Acknowledgement, Backend setup, Sign-in — with forward movement gated per stage. Realizes UJ-3. Upholds
SI-6.

**Consequences (testable):**
- Exactly 5 stages exist, indexed Welcome=0, Features=1, Safety Acknowledgement=2, Backend=3, Sign-in=4.
- Interactive swipe between stages is enabled only while the current stage index is < 2; from the Safety
  Acknowledgement stage onward the only forward affordance is a button.
- "Skip" appears on stages 0 and 1 only and animates to stage 2; it never lands on 3 or 4.
- **The Backend stage carries its own always-available escape: a "Use without a server" control that completes onboarding into Backend-optional mode.** It is present regardless of whether a connection test has been run, has failed, or is impossible, and it is never disabled. This is separate from "Next", which means *continue with this Backend* and stays gated on a successful test.
- **Why this is a requirement and not a nicety.** Without it the stage is a trap: "Next" is disabled until a test succeeds, "Skip" does not reach this stage, and FR-164's "Use without a server" lives on the following stage — so a user whose Local Network Privacy grant is denied (the exact case FR-162 predicts) can never leave stage 3. Backend-optional mode is a first-class supported mode and the product's headline claim; it must be reachable from the stage where the Backend attempt fails. A test drives a failing connection test and asserts onboarding can still be completed into Backend-optional mode.
- "Back" appears on stages 3 and 4 only; stages 0-2 show no back affordance.
- The Backend stage's "Next" is disabled until a connection test has succeeded in this session.
- The Sign-in stage shows no "Next"; the Sign In action lives in the stage body.
- Five page indicators are rendered, each with an accessibility label of the form "Page N of 5" with
  ", current" appended for the selected one, and identifiers `page_indicator_0`..`page_indicator_4`.
- The start stage is the Backend stage only when a saved Backend URL exists AND onboarding was
  previously completed; in every other case it is Welcome (so a returning user who never finished still
  sees the Safety Acknowledgement).
- Welcome copy is "GlycemicGPT" / "Your diabetes management companion" / "A direct pump monitor on its
  own — your on-call endo when you connect a server."
- Features shows four cards: Direct Pump Connection; AI-Powered Analysis ("With a connected server, get
  photo meal analysis, an AI chat, and AI insights delivered as notifications — powered by your choice
  of AI provider."); Smart Alerts; Self-Hosted Privacy.
- That copy names only surfaces that ship: the meal capture and estimate flow (5.5), the AI Chat tab
  (FR-105), and the Backend-pushed insight delivered at the informational tier (FR-65). It promises no
  daily brief and no pattern-recognition screen, because the app ships no brief view, no brief view model
  and no brief endpoint call (FR-105 Out of Scope). Porting Android's "daily briefs, meal analysis, and
  pattern recognition" wording would promise a surface that does not exist; the divergence is recorded in
  §7.
- The literal onboarding strings above say "server" deliberately — that is the word the product shows
  people for their **Backend**. The strings are pinned by test and are not to be re-worded; the
  requirement prose uses the Glossary term.

#### FR-160: Unskippable safety acknowledgement

A first-run user must take one explicit action to acknowledge the safety disclaimer before any further
stage is reachable. Realizes UJ-3, UJ-5. Upholds SI-1.

**Consequences (testable):**
- The stage's primary button reads "I Understand", not "Next", and is the only control that advances.
- No gesture, deep link, or restored navigation state advances past this stage without that button
  having been pressed in this run.
- Five acknowledgement cards render, in order: Experimental Software (alpha, use at your own risk); AI
  Limitations ("AI can hallucinate, misinterpret data, and provide outdated or incorrect information.
  Never rely solely on AI suggestions."); Photo Carb Estimates Are Guesses ("the carb numbers are AI
  estimates from an image and are frequently wrong, including misidentifying the food entirely. Never
  use a photo carb estimate to calculate an insulin dose or bolus. Always verify carbs yourself before
  dosing."); Not FDA Approved; Consult Your Healthcare Provider.
- The stage states that the app performs no therapeutic writes — no bolus, no basal, no pump setting
  (SI-1) — as a distinct sentence a UI test can assert.

**Out of Scope:**
- The wording and hosting of MEDICAL-DISCLAIMER.md and the README device table (5.12).

#### FR-161: Optional Backend setup, connection test and sign-in

A user can enter a Backend URL, test it before signing in, and sign in, with the typed URL restored to
the last known-good value if the test fails. Realizes UJ-3. Upholds SI-10.

**Consequences (testable):**
- The stage is labelled optional: "Connect a Server (Optional)" with the copy "A server adds AI, meal
  analysis, and caregiver features. You can skip it and use the app as a direct pump monitor."
- A blank URL on test yields "Enter a server URL first" and issues no request.
- A URL the security policy rejects yields "Invalid server URL. Use https://, or enable insecure LAN
  HTTP to reach a private/LAN address over http://." and issues no request.
- After validation, a second test within 1000 ms of the previous one is ignored silently; a
  confirmation-driven re-test bypasses the debounce.
- The typed URL is persisted before the request is issued; on failure the previous value is restored.
- Success renders "Connected successfully"; failure renders "Connection failed: <reason>".
- Editing the URL clears the result line and hides the insecure LAN HTTP opt-in affordance.
- Sign-in with a blank email or password yields "Email and password are required" and issues no request;
  HTTP 401 yields "Invalid email or password"; any other non-2xx yields "Login failed: HTTP <code>"; a
  transport error yields "Network error: <message>"; an empty body yields "Login failed: empty response
  from server".
- The password is cleared from in-memory state on both success and failure.
- Every literal string quoted above says "server" deliberately — that is the word the product shows
  people for their **Backend** — and the identifiers `onboarding_server_url` and
  `onboarding_continue_without_server` are byte-identical ports of Android `testTag` values under FR-177,
  so neither the copy nor the identifiers may be re-worded. This stage's URL field is
  `onboarding_server_url`; `server_url_field` is a different element — the Settings Account section's URL
  field (FR-167) — and the two are never interchanged. The requirement prose uses **Backend** and
  **Backend-optional mode**.
- Access token, expiry and refresh token are stored in the Keychain with an after-first-unlock,
  device-only accessibility class (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), so overnight
  refresh works while the device is locked (SI-10, FR-204). This class is settled project-wide and is not
  an open question.
- The app's start destination is chosen from onboarding completion alone, independent of session
  validity, so an expired session never re-onboards a user nor locks locally cached pump data behind an
  impossible sign-in.
- Identifiers: `onboarding_server_url`, `onboarding_test_connection`, `onboarding_connection_result`,
  `onboarding_email`, `onboarding_password`, `onboarding_login_error`, `onboarding_sign_in`.

#### FR-162: Local-network-blocked state and Settings deep link

A user whose Backend is on the local network can see that iOS is blocking the connection, distinguished
from every other failure, with a direct link to the setting that fixes it. Realizes UJ-3.

**Consequences (testable):**
- The app declares a local-network usage description; the permission is driven deliberately during the
  first connection test rather than incidentally later.
- When local network access is denied, the result line reads "iOS is blocking access to devices on your
  local network. Turn on Local Network for GlycemicGPT in Settings." and renders a control that opens
  the app's iOS Settings page.
- This state is visibly and programmatically distinct from: an invalid/unsupported URL, an unreachable
  or non-responding Backend, and an insecure-scheme rejection. Four distinct identifiers, four distinct
  strings.
- Settings surfaces the same condition in its Network section whenever it is active, so a user who
  denied the prompt during onboarding can discover the cause later.
- Because the Simulator neither presents nor enforces the prompt, the acceptance evidence for this FR is
  device-only and is recorded as such in the Validation Tier for onboarding.

#### FR-163: Insecure LAN HTTP opt-in and the persistent insecure-transport banner

A user can opt in to reaching a self-hosted Backend over unencrypted http on a private or LAN address,
only after acknowledging the risk, and only for addresses the app classifies as private. Realizes UJ-3.

**Consequences (testable):**
- The opt-in is reachable inline during onboarding (a fresh install cannot reach Settings before signing
  in) and from the Settings Network section; both use the same acknowledgement dialog.
- The dialog is titled "Allow insecure LAN HTTP?" with the body, verbatim: "This lets the app talk to
  your server over plain http://, which is unencrypted -- anyone on the same network could read your
  data and sign-in token. It is allowed only for private/LAN addresses (for example 10.x, 192.168.x, or
  a .local name); public addresses always require https://. Only enable this on a network you trust."
  The confirm button reads "Enable" and is rendered in the error colour.
- Enabling requires the dialog; toggling the switch alone never persists it. Disabling is immediate and
  needs no dialog.
- Confirming during onboarding immediately re-runs the connection test with the debounce forced, so the
  flow proceeds without a second tap.
- The setting is per-device and is NOT cleared on sign-out (FR-151).
- The cleartext rule and the private-address classifier it depends on — the accepted IPv4 and IPv6
  ranges, the strict-octet parsing, the octal/hexadecimal/bare-decimal rejections, the `.local` exception
  and the never-perform-a-DNS-lookup rule — are specified once. See FR-150. This FR states no second
  range list and no second classifier.
- **There is one cleartext rule in every configuration.** https is always allowed; http is allowed only
  when the opt-in is on AND the host classifies as private, and everything else is refused before a
  request is issued. A debug build gets no wider exemption than a release build; the build configuration
  is not an input to the decision.
- A persistent banner reading "Insecure LAN HTTP is on -- traffic to your server is unencrypted."
  renders above every screen including onboarding, identifier `insecure_http_banner`, and lights only
  when cleartext would genuinely be sent — never for a public http URL the request layer refuses.
- The banner tracks both the opt-in flag and the Backend URL reactively; changing either updates it
  without a screen change.
- The dialog body and the banner say "server" deliberately, for the reason FR-161 records; both strings
  are pinned by test and are not to be re-worded.

**Out of Scope:**
- The request layer's transport implementation and its interceptor ordering (5.8).
- The App Transport Security configuration that lets the in-app policy above actually run. That is an
  architecture decision requiring empirical verification, not a product requirement, and this FR asserts
  no Info.plist shape. FR-204's Entitlements and Plist Guard guards against broadening beyond whatever
  architecture records as the verified baseline (§15).

#### FR-164: Finishing onboarding without a Backend

A user can finish onboarding without a Backend and use the app as a direct pump monitor in
Backend-optional mode. Realizes UJ-3, UJ-4. Upholds SI-5.

**Consequences (testable):**
- The Sign-in stage carries the label "Don't run a server?" and a control reading "Use without a server"
  (identifier `onboarding_continue_without_server`). Both strings say "server" deliberately, for the
  reason FR-161 records, and the identifier is a byte-identical Android `testTag` port.
- Taking the path cancels any in-flight connection test BEFORE clearing the saved Backend URL; the
  ordering is load-bearing because the test persists a URL before it resolves and its failure branch can
  restore a previous one.
- Clearing the Backend URL clears Backend-provenance Alert Thresholds and preserves any the user set on
  this device, so a departed Backend's values never arm the Alert Floor. That rule is specified once —
  see FR-143 (SI-5).
- It marks onboarding complete and blanks the URL and test state.
- Backend-optional mode is presented as supported, not degraded: no error styling, no "limited mode"
  copy, no nag to connect a Backend.
- After completion the app is fully usable against a paired Pump with no network at all: dashboard,
  Alert Floor, Watch app and Settings all function. In Backend-optional mode the app makes no network
  request to any host carrying or receiving health data; the single permitted exception is the
  user-toggleable upstream-release check, which is OFF by default (FR-188, FR-173, NFR-23).

#### FR-165: Notification and Bluetooth authorization on both completion paths

The app requests notification and Bluetooth authorization on both onboarding completion paths and
resolves them before navigating away. Realizes UJ-2, UJ-4. Upholds SI-5, SI-6.

**Consequences (testable):**
- Notification authorization is requested in exactly ONE call carrying the full option set — alert,
  sound, badge, and critical alert — because iOS prompts once per install and a later critical-alert
  request silently no-ops. Requesting critical alert without the entitlement is harmless.
- Provisional authorization is never requested; provisional delivery is quiet, which would silently
  disable every alarm.
- The request fires on BOTH paths: after a successful sign-in, and after "Use without a server". The
  Backend-optional path is the safety-critical one — without notification permission the Alert Floor is
  suppressed with no user-visible signal.
- Bluetooth authorization is requested on both paths as well, so a Builder meets the prompt during
  onboarding rather than mid-pairing.
- Each permission result is resolved before the navigation flag flips, so no prompt races the navigation
  transition.
- If notification authorization is denied, the app does not proceed silently: the first dashboard
  presentation shows the Coverage Claim resolved to not-watching with the Not-Watching Reason naming the
  denied permission (SI-6).

**Out of Scope:**
- Bluetooth state handling, scanning and the pairing wall itself (5.1).
- Alert construction, interruption level and delivery (5.4).

#### FR-166: Settings composition, ordering and mode-dependent visibility

A user can reach every setting from one screen whose sections appear in a fixed order and whose state
refreshes on every appearance, with Backend-dependent surfaces hidden in Backend-optional mode. Realizes
UJ-1, UJ-3.

**Consequences (testable):**
- Sections render in this order: Account, Network, Drivers, Sync, Meal Intelligence, Notifications,
  Watch, Appearance, Units, Retention, Licenses, About, Developer.
- The Developer section renders only in a debug build; its entry point is absent from release routing
  entirely, not merely hidden.
- A Reliability card renders between Drivers and Sync only when a Pump is paired AND at least one
  condition would degrade background monitoring: background app refresh denied or restricted, Low Power
  Mode on, or the app having been force-quit from the app switcher (which stops Core Bluetooth state
  restoration from relaunching it). Copy names the specific condition and links to the relevant setting.
- The screen re-reads all of its state on every appearance, including pairing state, Driver Catalog
  state and the reliability conditions.
- This FR is the single Settings-side definition of background-health reporting: the Reliability card
  above reports the conditions that degrade background Pump monitoring, and FR-171's notification status
  card reports the conditions that suppress an alert. FR-15's force-quit disclosure and FR-85's gap
  notification feed the Reliability card and define nothing of their own here.
- In Backend-optional mode the following are hidden entirely: the Backend sync control, the Meal
  Intelligence section (header, card and spacing), and the AI notification sound row.
- In Backend-optional mode the following remain: Retention, low and high alert sounds, the notification
  status card, Watch, Appearance, Units, Licenses, About, Drivers — and the Alert Thresholds editor
  switches from read-only to editable.
- Every section header and every card carries a stable accessibility identifier (FR-177).

[ASSUMPTION: this order promotes Android's Glucose Units card, Data Retention card and Open Source
Licenses row to their own sections. If the PM prefers Android's nesting, the equivalent order is
Account, Network, Drivers, Sync (containing Retention), Meal Intelligence, Notifications, Watch,
Appearance (containing Units), About (containing Licenses), Developer — the surfaces and their
identifiers are identical either way.]

#### FR-167: Account section and sign-out

A user can see or change their Backend connection, sign in, and sign out. Realizes UJ-3. Upholds SI-5,
SI-10.

**Consequences (testable):**
- Signed in: the Backend URL (single line, truncated), the account email or "Signed in", an
  "Authenticated" confirmation line, and a "Sign Out" control in the error colour.
- Signed out: a Backend URL field (`server_url_field`), a "Test Connection" control
  (`test_connection_button`) that saves the URL then tests it, a result line, email
  (`email_field`) and password (`password_field`) fields that clear the login error on every keystroke,
  and a "Sign In" control (`sign_in_button`) enabled only when both fields are non-blank.
- Saving an empty URL clears the field and result without persisting; saving an invalid URL shows the
  invalid-URL message without persisting.
- Saving a valid Backend URL recomputes Backend-configured state in the same interaction, so the Alert
  Thresholds editor becomes read-only in the same frame.
- Sign-out is confirmed by a dialog: "Are you sure you want to sign out? Pump data sync will pause until
  you sign in again."
- What sign-out clears and what it preserves — Backend-provenance Alert Thresholds, Safety Limits and
  per-account settings cleared; Alert Thresholds the user set on this device, the Backend URL and the
  queued events preserved — is specified once. See FR-143 (SI-5).
- This section's own surfaces reset with it: pump profile and analytics settings are dropped, and the
  per-account preferences this FR renders (display unit to mg/dL, meal intelligence to its default) are
  reset, so a stale value cannot carry into the next account before its reconcile lands.
- Sign-out never clears the insecure LAN HTTP opt-in, which is per-device (FR-151).
- Credentials are removed from the Keychain on sign-out.

#### FR-168: Alert Thresholds are read-only whenever a Backend is configured

A user with a Backend can see their four Alert Thresholds in Settings but cannot edit them there,
because the Backend is master. Realizes UJ-2. Upholds SI-5, SI-11.

**Consequences (testable):**
- This FR owns the read-only RENDERING. The sync and staleness contract behind it — the refresh triggers,
  the staleness window, the Backend-master takeover and the audit line — is specified once.
  See FR-80. The drop-never-clamp handling of an invalid Backend threshold payload is specified once in
  FR-81.
- The card subtitle reads "Managed on your server".
- The values render as one line, identifier `alert_thresholds_readonly`: "Urgent low <v> · Low <v> ·
  High <v> · Urgent high <v> <unit label>", in the user's chosen display unit.
- When no sync has ever landed the line reads "Waiting for the first sync from your server." and no
  values are shown.
- A note reads "Edit alert thresholds in the GlycemicGPT web app; they sync to this phone automatically."
  (These three strings say "server" deliberately, for the reason FR-161 records.)
- No editable field is present and no save control exists in this state.
- Any save attempt re-checks the live Backend-configured state, not a cached flag, and aborts if a
  Backend exists.
- The Backend-is-master posture this card renders is the same one that lets Backend-supplied Safety
  Limits narrow but never widen the Glucose Validity Bound (SI-11); the narrowing rule itself is FR-32's.

#### FR-169: Alert Thresholds are editable in Backend-optional mode with dependent validation

A user in Backend-optional mode can set all four Alert Thresholds in their chosen display unit, with
out-of-range and out-of-order values rejected rather than clamped, and the result written durably before
the save reports success. Realizes UJ-2. Upholds SI-2, SI-3, SI-5, SI-10.

**Consequences (testable):**
- A status line (`alert_thresholds_status`) reads "On-device alarms are armed at these levels." once all
  four are set from a real source, or "On-device alarms are OFF until you set all four thresholds." in
  ERROR styling until then.
- Four decimal-entry fields render — `alert_threshold_urgent_low`, `alert_threshold_low`,
  `alert_threshold_high`, `alert_threshold_urgent_high` — each re-seeded when its mg/dL value or the
  display unit changes. Editing any field clears the inline error (`alert_threshold_error`).
- Parsing trims, accepts `,` as a decimal separator, and rejects non-finite values. In mg/dL the value
  is rounded to the nearest integer; in mmol/L it is multiplied by the Conversion Factor — read from the
  shared safety module, never re-typed (SI-4, NFR-4) — and then rounded. Storage is ALWAYS canonical
  mg/dL (SI-3).
- Any unparseable field yields "Enter a number for all four thresholds." and no write occurs.
- All four must lie within the Glucose Validity Bound (20-500 mg/dL) or the save is rejected with
  "Thresholds must be between <bounds label>." — never clamped (SI-2).
- The bound checked here is the ABSOLUTE Glucose Validity Bound, not the Backend-narrowable Safety
  Limits, for the same reason FR-138 rejects stored rows against the absolute bound: a threshold the user
  set must survive a later Safety Limits change without being retroactively invalidated. This differs by
  design from the Driver-level validation gate of FR-32, which runs against the current, narrowable
  Safety Limits at every validation pass.
- The mmol/L bounds label quotes 1.1 and 27.7, computed so the quoted values themselves round back
  INTO 20-500 mg/dL. The naive conversion of 500 (27.8) rounds back to 501 and would be rejected by the
  very message quoting it.
- Ordering must satisfy urgent low ≤ low < high ≤ urgent high, or the save is rejected with "Thresholds
  must increase: urgent low ≤ low < high ≤ urgent high."
- A successful save persists synchronously and is confirmed to the user only after the write is durable;
  the persisted record is marked as a local source and its Backend fetch timestamp is reset.
- The persistence layer re-validates the same bound and ordering as defense in depth and refuses an
  invalid write even if the UI let one through.
- Persisted thresholds are readable by the alerting path while the device is locked (after first
  unlock), so the Alert Floor works overnight (SI-10).
- The stored defaults 55 / 70 / 180 / 250 are never used to arm any alarm on any surface (SI-5) and are NEVER a source
  the Alert Floor fires from; until a real source exists the thresholds are reported as unconfigured
  (SI-5).

#### FR-170: Per-severity alert sound picker

A user can choose a sound for low alerts, high alerts and AI notifications from the curated set bundled
in the app, preview each one in place, and choose Silent for AI notifications. Realizes UJ-2.

**Consequences (testable):**
- The sound MODEL is specified once. See FR-67: the three tiers, the closed bundled set with no system
  ringtone, no system sound library, no user content URI and no user-imported audio, the ≤ 30 s
  constraint, the per-tier "Default", the alarm-like low set, and Silent on the informational tier only.
  This FR owns only the picker SURFACE — its rows, labels, identifiers and in-place preview — and
  introduces no sound the model does not offer.
- Three rows render with these labels and descriptions: "Low Glucose Alert" / "Life-threatening --
  aggressive alarm" (`low_alert_sound`); "High Glucose Alert" / "High glucose and insulin warnings"
  (`high_alert_sound`); "AI Notification" / "AI insights your server sends as notifications"
  (`ai_notification_sound`). The third description says "server" deliberately, for the reason FR-161
  records.
- The AI row description names a NOTIFICATION, not a screen. The app ships no daily-brief view, no brief
  view model and no brief endpoint call (FR-105 Out of Scope); AI insights arrive in exactly one place, a
  Backend-pushed alert at the informational tier (FR-65). Android's "AI analysis insights and daily
  briefs" wording is not ported, because it names a surface that does not exist.
- The AI notification row is hidden entirely in Backend-optional mode, because AI notifications are
  Backend-generated and the row would be a picker for a sound that can never play (FR-67).
- Each row's choices are previewable in place with a single tap, and the preview plays the same file the
  delivered notification will carry.
- Selecting nothing for low or high resets that category to its default rather than silencing it; Silent
  is offered for AI notifications only (FR-67).
- **No volume control exists in this section or anywhere in the app.** No code sets output, ringer or
  alarm volume, and no code reads or infers the ring/silent switch position (FR-66, §7). The audibility
  honesty statement — that without the Critical Alerts entitlement the ring/silent switch can silence the
  alarm and the app cannot detect it — is FR-66's copy, and this section renders it beside the low-alert
  row. It is a disclosure, not a control.
- The chosen sound is a per-notification property; there is no channel to delete and recreate, and no
  version suffix in any identifier.

**Out of Scope:**
- Interruption level selection, Focus bypass, and re-alert cadence (5.4).
- User-imported alert audio and any transcode-to-CAF import path — deferred with a named revisit
  condition, not silently dropped. See FR-67.

#### FR-171: Notification status card reporting every suppressing condition

A user can see, in one card, every condition that would stop an alert reaching them, each with a link to
the setting that fixes it. Realizes UJ-2. Upholds SI-6.

**Consequences (testable):**
- The card renders one prominent verdict line in error styling whenever ANY condition would suppress a
  low alarm; the denied case reads "Disabled -- alerts will not appear on your phone".
- Below the verdict it itemizes each active condition separately: authorization denied; alerts not
  permitted; sound off; critical alerts not permitted; Time Sensitive not permitted; lock screen
  delivery off; Notification Center delivery off; Scheduled Summary enabled.
- Each itemized condition carries its own control that opens the relevant iOS setting.
- Every listed condition maps one-to-one onto a Not-Watching Reason the Coverage Claim can surface
  (SI-6); a condition the card can report but the Coverage Claim cannot name is a defect.
- The card re-evaluates on every return to the foreground, so coming back from iOS Settings updates it
  without further action.
- The enable control opens the app's notification settings page where available and falls back to the
  app's Settings page otherwise; if neither can be opened it shows "Please enable notifications for
  GlycemicGPT in your phone's Settings".
- When nothing would suppress an alert, the card reads "Enabled" in the primary colour and lists no
  conditions.

#### FR-172: Watch section — pairing state, what the Watch surfaces show, and telemetry

A user can see whether a Watch is paired, whether the Watch app is installed, and whether it is
reachable, configure what the Watch app and its complications show, and inspect the last values sent.
Realizes UJ-1. Upholds SI-2, SI-3, SI-6.

**Consequences (testable):**
- Status resolves to exactly one of: "Status unknown"; "Connected -- streaming glucose, IOB and alerts";
  "Installed (not nearby)"; "Not installed". A check control re-queries on demand.
- Installed-ness is derived only from a signal that proves the Watch app is present; mere Watch
  connectivity never sets it.
- When no Watch app is detected the section shows one of two hint cards instead of the configuration
  controls: installed-but-not-nearby, or not-installed. The not-installed remedy is the one FR-115
  defines — install it from the system Watch app — and this section states no other. It never offers a
  TestFlight download of the Watch app, because there is no second artifact to download. See FR-115.
- **The set of preferences the controls expose is exactly the set FR-134 defines, and no other.** This FR
  defines only WHERE the controls live; it renames none of them, adds none, and restates none. See
  FR-134. Every change made here is pushed and applied on the Watch without further user action.
- No watch-face theme, appearance or high-contrast preference is offered. Complications render in a
  system-controlled tint the app cannot override, so a per-app appearance preference could not affect
  them — it would be a control that does nothing. Android's watch-face theme is a forced loss recorded in
  §7, not a rebound feature (FR-134).
- Because watchOS has no third-party watch faces, the section explains how to add the app's
  complications to an Apple face and its widget to Smart Stack. It offers no face gallery, no face push,
  and no face-level options such as showing seconds.
- Telemetry shows "Last glucose sent (wire, mg/dL)" and "Last IOB sent" formatted to two decimals, each
  with a relative age. The label states the wire unit explicitly because the Watch always receives
  canonical mg/dL regardless of display unit (SI-3).
- A last-sent Glucose Reading outside the Glucose Validity Bound is shown as unavailable, never rendered
  (SI-2).
- A telemetry read that fails or times out shows "Could not read watch data" rather than a stale or
  blank value.
- The section never presents a Coverage Claim of its own; it reports transport state only (SI-6).
- The section describes the wrist alert path as FR-128 defines it: the alert the wrist raises is
  scheduled on the Watch itself, and iPhone notification mirroring is the fallback, because mirroring
  does not fire while the iPhone is unlocked and in use. No copy here implies mirroring is the mechanism.

**Out of Scope:**
- What the Watch app and its complications actually render, and how the Coverage Claim decays there
  (5.7).
- What the Watch consumes — the preference set itself (FR-134) — and the Watch app install path
  (FR-115).

#### FR-173: About — versions, build mismatch, TestFlight, and the licenses entry

A user can see the installed app and Watch app versions, be warned when they disagree, be directed to
TestFlight to update, and reach the license viewer. Realizes UJ-3.

**Consequences (testable):**
- Rows render for: app version; build configuration; active Driver protocol as "<protocol name>
  v<version>", or "None" when no Driver is active.
- The installed Watch app version renders alongside the phone version whenever it can be read.
- When the two versions differ, a warning states the mismatch explicitly and applies the one remedy
  FR-115 defines for that condition — update the app itself from TestFlight, which carries the Watch app
  with it. This FR states no other remedy and never presents the Watch app as a separate download. See
  FR-115.
- The app never downloads or installs any build, for itself or for the Watch. There is no download
  progress, no size figure to verify, and no install action beyond opening TestFlight.
- The About section renders the upstream-release check's toggle and its result. The check itself — that
  it is user-toggleable and OFF by default, the single permitted exception to Backend-optional network
  silence, the host it contacts, the tag comparison and its fail-silent behaviour — is specified once.
  See FR-188 (NFR-23). This FR adds no state, no error copy and no host of its own.
- The only action offered when a newer upstream release exists is opening TestFlight.
- An "Open Source Licenses" row (`open_source_licenses_button`) navigates to the license viewer (FR-174).
- The section states that TestFlight builds expire and must be rebuilt every 90 days, and that key
  custody, Apple account state and certificate lifecycle are the Builder's.

**Out of Scope:**
- The build-and-sign pipeline and the 90-day rebuild workflow itself (5.10).

#### FR-174: Settings entry point to the offline license viewer

A user can reach the app's license documents from Settings, in any configuration and with no
connectivity. Realizes UJ-3, UJ-6.

**Consequences (testable):**
- The viewer itself is specified once. See FR-227: its three states, the "License text could not be read
  from this build." copy, plain-text-never-markdown rendering, the fixed content order, one row per
  paragraph, repository-relative link reduction with `mailto:` preserved, whole-document text selection,
  scroll-position restoration and the offline requirement. This FR states none of them again.
- The About section's "Open Source Licenses" row (`open_source_licenses_button`, FR-173) is the single
  entry point; its destination is registered in the app's navigation.
- The entry point is present in every configuration — including Backend-optional mode and with the device
  in airplane mode — and never depends on a reachability check, a sign-in state or a Backend.
- The row carries an accessibility identifier and an accessibility label distinct from it (FR-177), and
  is reachable at the largest accessibility text size without truncation (NFR-27).

**Out of Scope:**
- The viewer screen itself (FR-227), and generating the bundled documents, the attribution generator and
  the build failure on a missing or empty source document (5.12).

#### FR-175: Appearance, Units, Meal Intelligence and Retention

A user can choose appearance and display unit per device, enable or disable meal intelligence for their
account, and set local data retention. Realizes UJ-1, UJ-5. Upholds SI-3, SI-4.

**Consequences (testable):**
- Appearance offers System, Dark and Light (`theme_system`, `theme_dark`, `theme_light`), is per device,
  and applies live across the app without a restart. A corrupt persisted value falls back to System.
- The palette is fixed; there is no dynamic or system-derived colour scheme.
- The calm-caution treatment used by standing safety notes (soft amber, never the error colour) tracks
  the FORCED appearance choice, not the system appearance, so a user on Light with the system in Dark
  still gets the light variant.
- Units offers mg/dL and mmol/L (`glucose_unit_mgdl`, `glucose_unit_mmol`). The choice affects display
  and speech ONLY: storage, transport, every threshold comparison, Alert Floor evaluation, Watch
  payloads and the Glucose Validity Bound all remain mg/dL (SI-3).
- Conversion uses the Conversion Factor 18.0156 as the single Safety Constant, defined once in the shared
  safety module both the app and the Watch app link (SI-4, NFR-4), converting once from the most precise
  mg/dL source and rounding last. The pinned mg/dL→mmol/L anchor fixture lives with that module and is
  not restated here; this section cites it (NFR-4) rather than carrying a second copy, which is the drift
  SI-4 exists to prevent.
- A spread or standard deviation converts without the value offset; reusing the value converter for a
  spread is a defect.
- When the unit was picked automatically, a one-time dismissible notice (`glucose_unit_seed_notice`)
  appears ABOVE the selector reading "We set this to <unit> based on your region or your Nightscout-
  sourced data. Change it anytime below." with a "Got it" control. It never blocks the UI, and
  dismissing it records the acknowledgement so it does not recur.
- With a Backend, unit and meal intelligence write locally first (immediate effect) then sync; a failed
  sync keeps the local value and shows "Saved on this device. Couldn't sync to your account." and does
  not imply a retry. In Backend-optional mode the local write is the entire save with no error surfaced.
- Rapid toggling of meal intelligence can never let a stale response overwrite a newer choice; an
  account the Backend rejects (401/403) fails CLOSED to disabled.
- Meal intelligence enabled shows a "Log a meal" entry point and the line "Estimates are a guess to
  verify before dosing."
- Retention is settable from 1 to 30 days in whole-day steps, defaults to 7, commits on release rather
  than continuously, and is coerced into 1-30 at both the setter and the persistence layer.
- This FR owns the CONTROL. What the chosen window bounds and when the sweep runs — every growing table,
  the raw pump-history table and the alert history, pruned by a scheduled pass rather than on screen open
  — is specified once. See FR-139. Settings copy states that alert history follows this same window and
  names no separate, fixed retention for it.
- The retention value bounds the analysis windows offered elsewhere in the app.

**Out of Scope:**
- The meal capture, estimate and correction flows (5.5).

#### FR-176: Developer section and debug console

A developer using a debug build can reach a Driver debug console and the fault-injection toggles that are
compiled out of release. Realizes UJ-6. Upholds SI-5, SI-6, SI-9.

**Consequences (testable):**
- **Fault injection is gated on a dedicated compile-time flag that is OFF in every build the pipeline produces — both channels.** A debug configuration alone does not enable it. The flag is set only for a local Xcode build a maintainer runs on their own machine.
- **Why not gate on "not TestFlight":** under the verified Loop model the `develop` channel is delivered through TestFlight too (FR-182), so a TestFlight test would disable fault injection for the development channel while still leaving it reachable for anyone who dispatched a debug build. The compile-time flag is the only gate that holds for both channels.
- The consequence being prevented is specific: simulate-backend-unreachable, compressed staleness and synthetic Glucose Reading injection on a phone somebody is relying on to catch a low. A test asserts the Developer section is absent from a pipeline-produced build of either channel.
- This FR is the single definition of the developer fault-injection surface. FR-88 cross-references it
  for the alerting consequences of each injection and defines no toggle of its own.
- The section renders only in a debug build; the console's route is absent from release routing.
- Toggles: "Show Pump Labels" (Pump-native category names beside display labels); "Simulate Backend
  Unreachable" (fail all Backend requests before the network on both the general and the alert-stream
  sessions, accounted for exactly like a real transport failure, so the app shows Backend-unreachable
  while cached data stays on screen, and cancel any live Backend stream immediately rather than waiting
  out the read timeout); "Fast Staleness" (compress the CGM Freshness Tier to Stale after 20,000 ms and
  Too Stale after 45,000 ms, substituted at exactly one swap point so the Alert Floor gate, the Coverage
  Claim pipeline, its ticker period and its advertised expiry all move together and the transitions are
  observable in seconds).
- Both fault toggles are hard-gated: their readers return false and their writers are no-ops in a
  release build, so a Builder shipping a release configuration can never trigger them.
- The console renders TX/RX frames newest-first from an in-memory circular buffer of capacity 100, each
  entry showing direction, opcode name, opcode as `(0x<2-digit hex>)`, an `HH:mm:ss.SSS` timestamp,
  transaction id and cargo length, the cargo as monospaced hex, and either a parsed value or an error.
- Console entries carry no health value and no credential; raw device payload appears only here, in a
  debug build, and is never written to any log at or above debug level (SI-9).
- Injection actions exist for: a normal Glucose Reading at 120 mg/dL; a fresh low at 54 mg/dL; a stale
  low at 54 mg/dL aged 60 seconds (past the compressed Too Stale bound); a synthetic Glucose Reading at a
  chosen value and sensor timestamp; force-firing each alert type at each severity; expiring the Coverage
  Claim immediately; and seeding 20 sync-queue events.
- Injected readings travel the SAME production path a polled reading takes, so the Alert Floor, the
  Watch relay and the Coverage Claim see them identically.
- With these toggles plus a Simulated Driver the following are exercisable with no hardware: Alert Floor
  arming, firing, cooldown, episode re-arm, episode guard, acknowledgement ordering, Coverage Claim decay
  and the coverage-lapse notification. Results are logic evidence only; audibility, entitlement
  behaviour, locked-device delivery, Focus behaviour, force-quit recovery, post-reboot behaviour and
  background Bluetooth cadence are device-tier checks (see the Feature-specific NFRs below and §9).
- The fresh low MUST fire the Alert Floor; the stale low MUST be suppressed by it and MUST resolve the
  Coverage Claim to not-watching with a Not-Watching Reason naming staleness (SI-5, SI-6). This pair is
  the only way to exercise the fire-versus-suppress behaviour without pump hardware, which matters
  because Core Bluetooth does not exist in the Simulator.
- Injection is additionally guarded by an explicit release-build early return as defense in depth,
  because it writes to the same store that drives the real dashboard and can fire a real alarm.

#### FR-177: Accessibility identifier parity as the acceptance substrate

Every element that carries a Compose `testTag` in the Android client carries the identical string as an
accessibility identifier in the app and the Watch app. Realizes UJ-1, UJ-6.

**Consequences (testable):**
- Every ported identifier string is byte-identical to the Android `testTag`; a renamed, prefixed or
  camel-cased identifier is a defect. **This FR states the per-surface requirement** — which elements
  carry an identifier and what each one must be — and cites **NFR-30** for the two system-wide parity
  counts and for the rules that apply to every surface: identifiers on states as well as controls, never
  derived from a display string, never localized, never used as an accessibility label. Neither count is
  restated here.
- The set of identifiers is enumerated in a single registry that is the source of truth for the app, the
  Watch app and their UI tests. The registry is complete only when it reaches NFR-30's identifier count.
- Enforcement runs in two named places and neither invents a sixth **Required Check**. The source-side
  half — the registry is present, well-formed, declares no identifier twice, every enumerated identifier
  occurs in the source's identifier set, and the source declares none the registry omits — runs in
  `Build & Test` and reaches merge gating through the `iOS Gate` Required Check, which is where FR-197's
  host-assignment table places it and where FR-208 defines the step. The built-UI half — a registry
  identifier absent from the built UI, or an identifier appearing twice on one rendered screen — runs
  inside `UI Tests (Simulator)`, which FR-209 states explicitly is **not** a Required Check while it
  stabilizes. A failure of the second half is a release-blocking defect by policy, not by branch
  protection.
- The known duplicate `pairing_fault` identifier in the Android client is resolved during the port to
  two distinct identifiers, and the resolution is recorded in the registry.
- Because Core Bluetooth does not exist in the Simulator and the lead developer has no iPhone (decision
  10), the Simulator-runnable gates for sections 5.3, 5.4, 5.5, 5.9 and 5.10 are written against this
  identifier set; a gap in it is a gap in the project's only self-serve verification.

#### FR-178: VoiceOver, non-colour encoding and Dynamic Type

Every card exposes one combined VoiceOver description matching the Android phrasing, every state that
colour carries is also carried without colour, and hero numerals stay legible at accessibility text
sizes. Realizes UJ-1, UJ-2. Upholds SI-2, SI-6.

**Consequences (testable):**
- The system-wide accessibility rules are stated once and are not restated here: VoiceOver (NFR-26),
  Dynamic Type (NFR-27), non-colour encoding and legibility in flattened rendering modes (NFR-28),
  motion, contrast and input (NFR-29). The combined-description parity rule is **NFR-30's**, stated
  there alongside the identifier count and cited here rather than restated. This FR owns only the
  PER-CARD phrasing those rules do not enumerate.
- Each card merges its descendants into ONE description so a screen reader cannot separate a number from
  its qualifier — most critically the glucose hero, the Time-in-Range bar, the CGM stats card, the
  insulin summary card, and the carb estimate, whose description always carries the never-dose qualifier
  in the same utterance as the number.
- The glucose hero description is "Glucose <value> <spoken unit>, <trend spoken>", with ", reading is
  stale, last updated <age>" inserted BEFORE the metrics only when the Freshness Tier is Too Stale, then
  IOB, basal, battery and reservoir clauses for each present metric. With no reading it is "No glucose
  data available".
- Spoken unit is "milligrams per deciliter" or "millimoles per liter", never the abbreviation (NFR-26).
- The specific per-card non-colour encodings this section's surfaces carry, under NFR-28's rule: the
  Freshness Tier carries the text badges "Stale" and "Too old" and renders no badge when Fresh;
  confidence is encoded by bar LENGTH as well as hue, so Medium and Low (which share a hue) remain
  distinguishable; and the Time-in-Range bar distinguishes low from high by POSITION.
- The Coverage Claim's watching / not-watching state is never conveyed by colour alone; the
  Not-Watching Reason is always present as text (SI-6, NFR-28).
- Hero numerals and the glucose value on every glanceable surface remain legible and untruncated at the
  largest accessibility text size: the value and the trend glyph must not clip, overlap, or drop the
  unit label. Where the full layout cannot fit, the value and trend take priority over secondary metrics
  (NFR-27).
- A rejected Glucose Reading (outside the Glucose Validity Bound) is never announced as a value (SI-2);
  the surface announces its absence.

**Feature-specific NFRs:**
- Every acceptance criterion in this section that depends on lock state, Focus, the ring/silent switch,
  Local Network Privacy, or Keychain/file protection classes is DEVICE-ONLY. The Simulator does not
  enforce any of them and will pass while a real phone fails. These belong in the device Validation Tier
  and are validated by DanielDanielson building from their own fork under their own Apple Developer
  account (decision 9).
- Settings must render its full section list within one frame budget on the oldest supported device even
  when a Driver's metadata read throws; a failure reading one Driver's metadata may drop that Driver's
  card but must not blank the section or the screen.
- All display formatting in this section uses a fixed decimal separator for cross-surface consistency
  with the Watch app and the Backend, independent of device locale.

**Notes:**

- [NOTE FOR PM] **Parity Ledger entries owned by this section:**
  1. **No system sound picker — a FORCED LOSS, not a design preference.** Android uses the system
     `RingtoneManager` picker over the whole system sound library and ships no bundled sound set at all.
     iOS exposes no API to enumerate, preview or select from that library, and a notification sound may
     only reference a file in the app bundle or container. The curated bundled set (FR-67, picker FR-170)
     is the forced substitute for a capability iOS removes. The explicit "Silent" option is real Android
     parity, not an iOS invention. User-imported audio is DEFERRED with the revisit condition FR-67
     names, not cut by oversight.
  2. **No notification channels.** iOS has no per-category OS notification settings. A user who mutes
     the app in iOS Settings mutes low alerts, high alerts and AI notifications together. This is the
     reason FR-171 must itemize every suppressing condition.
  3. **No system-volume boost, and no volume control anywhere.** "Boost Volume for Lows" as Android
     implements it cannot exist. Loudness over the ring/silent switch requires Critical Alerts, which is
     structurally unobtainable under fork-and-build (decision 4). Nothing substitutes for it: FR-170
     offers no volume control, and no code sets output, ringer or alarm volume or reads the silent-switch
     position (FR-66). What FR-170 renders beside the low-alert row is FR-66's honesty copy — a
     disclosure, not a control. PL-24 is already stated on that basis: FR-66 owns the audibility honesty
     statement and the no-volume-control rule, and no ledger row cites "FR-170 volume-control copy".
  4. **No watch-face gallery, no face push, no face-level options, and no face theme.** watchOS has no
     third-party watch faces. The Digital Full and Analog Mechanical designs with their four graph
     overlays are lost; complications and Smart Stack widgets are the substitutes, and they are not
     equivalent. Android's watch-face theme is a **forced loss with no substitute**: complications render
     in a system-controlled tint the app cannot override, so a per-app appearance or high-contrast
     preference could not affect them and none is offered (FR-134, FR-172).
  5. **No in-app self-update and no watch-app push.** The download → verify → install state machine and
     the watch APK push are both impossible. TestFlight is the only channel for the app, the Watch app
     ships inside the same bundle and is installed from the system Watch app (FR-115), and the Builder
     owns the 90-day rebuild.
  6. **No runtime Driver install.** The "Custom Plugins" card, Add Plugin from a user-supplied archive,
     per-Driver Remove, and the untrusted-source warning all disappear; the Driver Catalog is
     compile-time (decision 1). Verification Status replaces the install-time trust warning.
  7. **No battery-optimization exemption.** Android's `isIgnoringBatteryOptimizations` card has no iOS
     equivalent; FR-166's Reliability card substitutes background-refresh status, Low Power Mode, and
     the force-quit condition (which is the true analogue: force-quitting stops Core Bluetooth state
     restoration).
  8. **ATS cannot be scoped to private address ranges.** ATS exceptions are per-domain and accept
     neither IP addresses nor CIDR ranges, so ATS cannot express "private ranges only" and the app's own
     literal-address policy is the sole guard against cleartext to a public host — something Android
     achieves with platform help. Whether `NSAllowsLocalNetworking` covers raw private-IP literals is
     **unsettled** and is NOT asserted by this ledger row; the Info.plist shape is an architecture
     decision pending empirical verification (see the open question below and §15).
  9. **Local Network Privacy is a new failure mode with no Android counterpart.** Denial is permanent
     until the user visits iOS Settings and cannot be re-prompted in-app.
  10. **Onboarding no longer promises daily briefs or pattern recognition.**
     Android's Features copy names both while the client ships neither. The iOS copy (FR-159) and the AI
     sound row description (FR-170) describe only the Backend-pushed notification that actually exists
     (FR-105, FR-65). A deliberate divergence — the honest copy is not the ported copy. Recorded in §7 as
     **PD-45**; FR-159's cross-reference resolves there.

- **ATS is unresolved and is recorded as OQ-45 in §15, not settled here.** The research recommends "a
  scoped ATS exception via `NSExceptionDomains`" in one place, states elsewhere
  that exception domains cannot express IP ranges, and states that the presence of
  `NSAllowsLocalNetworking` causes `NSAllowsArbitraryLoads` to be ignored. Whether
  `NSAllowsLocalNetworking` covers raw private-IP literals — the case that matters for a self-hoster at
  `http://192.168.1.10:3000` — is genuinely unsettled and cannot be asserted from documentation. The
  PRODUCT requirement is fixed and is not waiting on this: FR-150 / NFR-20, no cleartext to any host that
  is not loopback, private, carrier-NAT or link-local, classified in-app from the literal address, never
  by DNS. The Info.plist configuration that ACHIEVES it is an architecture decision requiring empirical
  verification on a device; architecture records the verified baseline, and FR-204's Entitlements and
  Plist Guard then fails any pull request that broadens beyond it.

- [NOTE FOR PM] The seed-notice copy currently names Nightscout. Under decision 8 the app is not a
  Nightscout client — Nightscout-sourced data reaches it through the Backend. FR-175 reads
  "Nightscout-sourced data" for that reason. Confirm the wording.

- **FR-177's identifier registry is owned here; its enforcement is owned by CI in 5.11**, mapped onto the
  fixed roster rather than asserting a sixth gate. Both placements are confirmed against FR-197's
  host-assignment table: the source-side registry check runs in `Build & Test` and reaches merge gating
  through the `iOS Gate` **Required Check** (defined in FR-208), and the built-UI assertions run inside
  `UI Tests (Simulator)` (explicitly not required, FR-209). The parity rule those checks enforce
  against are NFR-30's.

- **Open question:** should the Settings Network section carry its own persistent "Local Network access
  denied" banner alongside the insecure-transport banner, or is the in-section card of FR-162 enough?
  The condition is invisible in the Simulator and will otherwise be misdiagnosed as a Backend fault.

- **Open question:** FR-176 gates the Developer section on a debug build. Under fork-and-build a Builder
  could build the debug configuration and install it via their own TestFlight. Confirm whether that is
  acceptable (fault injection reaching a real user's phone) or whether the gate should additionally
  require a non-TestFlight install. Note that this no longer touches transport security: FR-163 gives a
  debug build no wider cleartext exemption than a release build.


### 5.10 Build, Sign, Install and Update

**Description:**

On Android the project is the publisher: CI builds four APKs, signs them with one project-held keystore materialized from one 1Password item, asserts the signer fingerprint equals the hardcoded `RELEASE_SIGNER_SHA256=55f0d0cdabf20b398ad30a0ce3e998e3192666e5c15e6d378b86e1c8de342990`, uploads them to GitHub Releases, and an in-app updater downloads and hands the APK to the package installer. Every part of that chain is unavailable on iOS. There is no sideload path for a normal Apple Developer Program account; `itms-services://` over-the-air install requires an Enterprise membership whose terms forbid distribution outside the member organization; ad-hoc distribution caps at 100 devices per class per team per year; and App Store review guideline 2.5.2 independently forbids an app downloading and executing code. So the publisher role moves to the user. Under fork-and-build the project ships source, holds no signing key, and each Builder forks, supplies their own Apple Developer credentials, and produces a signed build in their OWN TestFlight. Realizes UJ-3.

This inverts the trust topology rather than merely relocating it. Android had one keystore under one person's control; iOS has N Apple Developer identities, one per Builder, and every merged upstream commit becomes code that will execute inside a build with a Builder's App Store Connect private key in scope on their next run. That is why the fork's build-and-sign pipeline is a supported product surface and not published reference configuration: CODEOWNERS-gated, SHA-pinned throughout, and inside SECURITY.md response scope. What stays with the Builder is the part the project structurally cannot hold — key custody, Apple account state, certificate and profile lifecycle, and rebuild cadence. Maintainer DanielDanielson validates by building from their own fork under their own Apple Developer account for exactly this reason; the project never conveys a binary, not even to a hardware validator.

Apple's App ID namespace is globally unique across every developer account, so two Builders cannot both own `com.glycemicgpt.mobile`. Nothing in the Android repo prepares for this and it is the single largest new setup burden: every bundle identifier, App Group container and keychain access group must be templated on the Builder Team ID, and every App ID must be registered with Apple, with exactly the capabilities the app uses, before a profile can be issued. One capability cannot be self-registered at all — `com.apple.developer.usernotifications.critical-alerts` is granted per Team ID by Apple on application and is not obtainable by an individual Builder. The provisioning workflow must therefore report its absence and continue, never fail; nothing in the build may hard-depend on an entitlement a Builder cannot get. (The alerting consequence of that is 5.4's; the provisioning consequence is here.)

The other structural change is that an installed build now expires. A TestFlight build stops launching 90 days after upload, and for a glucose monitor that is a silent loss of monitoring, not a cosmetic lapse. The honest replacement for the entire `AppUpdateChecker` / `dev-latest` / APK-download apparatus is therefore two things: the Builder's own CI rebuilding on demand and on a schedule so the installed build never lapses, and the app telling the truth about its own shelf life — build date, source tag and short commit, channel, and days remaining, with escalating prominence. This is not decoration; a GitHub-hosted scheduled workflow is disabled after 60 days of repository inactivity, which lands 30 days BEFORE the build expires, so a quiet fork can lose its automatic rebuild while the Builder still believes it is armed. The in-app countdown is the backstop for that failure and it must never overstate remaining coverage.

Signing correctness keeps the Android hazard in a new shape. There, both release buildTypes silently fell back to `signingConfigs.getByName("debug")` when `RELEASE_KEYSTORE_FILE` was unset, and the only thing preventing a debug-signed "release" reaching patients was a post-build `apksigner` fingerprint assertion. The iOS analogue is Xcode automatic signing quietly selecting a Development identity or a wildcard profile. The fingerprint equality check cannot survive — every Builder signs with a different certificate — so it becomes a property assertion on the archive: Apple Distribution identity, `get-task-allow == false`, `TeamIdentifier` equal to the configured team, profile not expired. It stays a hard fail, never a warning, and it runs before upload so a wrongly signed archive never consumes a build number. Signing is manual, pinned in a committed xcconfig, precisely because automatic signing is the ambiguity that produced the Android bug.

Everything above the build lane — the promotion topology, conventional-commit versioning, the changelog taxonomy and cutoff marker, the sync-back cherry-pick, the DCO posture, Renovate policy and the auto-merge scope guard — is repository machinery that is platform-independent and ports largely intact, with three exceptions worth naming. `versionCode = major*1_000_000 + minor*10_000 + patch` is deliberately NOT reproduced: it collides silently at patch > 9999 or minor > 99, and reproducing it would import a bug that made the Android updater report "up to date" forever. `DEV_RUN_NUMBER_OFFSET = 500` has nothing to attach to, but its real content — a one-way ratchet on a number that must never decrease — is stronger on iOS, because App Store Connect permanently rejects a build number less than or equal to one already uploaded. And SwiftPM's default behavior when `Package.resolved` disagrees with the manifests is to quietly re-resolve and succeed, which would silently defeat pinning and let a dependency scan pass against versions that were never scanned; resolution enforcement is mandatory, not advisory.

Upstream CI still runs, and still gates, but it produces no installable artifact. What it produces is tags, release notes, and unsigned iOS Simulator and watchOS Simulator application bundles — the only artifact the lead developer, who has a Mac and a Tandem t:slim X2 but no iPhone and no Apple Watch, can actually run. Core Bluetooth does not exist in the iOS Simulator, so those bundles exercise the app through the Simulated Driver and the Trace-Replay Driver, never a radio.

**Functional Requirements:**

#### FR-179: Fork-and-build with no project-held signing material

The project publishes source and holds no signing key, certificate, provisioning profile, or Apple credential belonging to itself or to any Builder; upstream CI produces tags, release notes and unsigned Simulator bundles, never an installable signed binary. Realizes UJ-3.

**Consequences (testable):**
- No upstream repository, workflow, environment or secret store contains an Apple Distribution certificate, a `.p12`, a `.mobileprovision`, an App Store Connect API key, or an Apple ID credential.
- Committed signing material and a `DEVELOPMENT_TEAM` identifier in a build settings file are rejected by the Entitlements and Plist Guard inside the `Static Analysis Gate` Required Check. See FR-204.
- A leaked upstream secret cannot sign or upload a build to any Builder's App Store Connect account, because upstream holds no credential that App Store Connect will accept for any team.
- The upstream release job produces: the `vX.Y.Z` tag, the GitHub Release with notes, and unsigned `.app` bundles built with `-sdk iphonesimulator` and `-sdk watchsimulator`, attached as release assets and as workflow artifacts with 90-day retention.
- Simulator bundles install with `xcrun simctl install` into a paired iPhone + Apple Watch simulator and launch without any Apple Developer credential.
- The Android release path's artifact contract — `GlycemicGPT-<VERSION>-release.apk`, the Wear and two WatchFace APKs, `find`+`head -1` renaming, `gh release upload --clobber` of installable binaries — has no successor and is absent from the repository.
- A doc-only promotion (README, GOVERNANCE, CLAUDE.md, docs/) produces no versioned release and no build, preserving the Android deployable-change rule with the path regex remapped to `^(App/|Sources/|WatchApp/|Widgets/|Tests/|Package\.swift|Package\.resolved|Config/|.*\.xcconfig|.*\.xcodeproj/|project\.yml|fastlane/|Gemfile\.lock)`.

**Out of Scope:**
- Any project-operated build, signing or distribution service on a Builder's behalf.
- Adding a person as an internal TestFlight tester on a maintainer's team; hardware validators build from their own fork (settled).

#### FR-180: The documented fixed secret set and isolated credential validation

A Builder can produce a build by adding a documented, fixed set of repository secrets to their fork without editing any source file, and can validate those credentials in isolation — before any build — without any secret value appearing in a log. Realizes UJ-3. Upholds SI-9.

**Consequences (testable):**
- The secret set is fixed, named in one place, and identical for every **Builder**: `TEAMID`, `FASTLANE_ISSUER_ID`, `FASTLANE_KEY_ID`, `FASTLANE_KEY`, `MATCH_PASSWORD`, `GH_PAT` — six items. **Verified against the Loop browser-build documentation, not inferred:** this is the same six-secret set LoopWorkspace requires, and mirroring it exactly means a **Builder** who has already set up Loop, Trio or iAPS reuses what they have rather than learning a second scheme. `GH_PAT` must carry the `workflow` scope, because without it the scheduled rebuild in FR-186 cannot fire.
- Signing material is managed by `fastlane match` against a **private `Match-Secrets` repository in the Builder's own account**, encrypted with `MATCH_PASSWORD`. The project never sees it. This is the Loop pattern and it is what makes "the project holds no signing key" true rather than aspirational.
- A **Builder** who builds more than one app is directed to hold the six secrets at a free GitHub **organization** rather than per-repository, so they are entered once. This is the documented Loop guidance and it removes the most common setup error — re-entering six secrets correctly a second time.
- Producing a build requires zero source edits: no bundle identifier, team id, or path is typed into a tracked file by the Builder.
- A `Validate Secrets` workflow is `workflow_dispatch` only and is explicitly a non-required job — it is not one of the five Required Checks of FR-197, because it runs in a Builder's fork against their own credentials and cannot run on an upstream pull request. It declares `permissions: contents: read`, and asserts in order: every required secret is present and non-empty; the App Store Connect API key authenticates with a read-only call that resolves the team and lists its app records; the private certificate repository clones and decrypts.
- Output is pass/fail plus non-sensitive identifiers only. No key bytes, no issuer id, no passphrase, and no certificate material reaches the log, the summary, or an artifact — asserted by a test that greps the run log for each secret's value.
- Every failure emits a specific, greppable message naming the exact secret or account setting at fault, so a Builder debugging alone has something to search for.
- Validation is the documented first step after forking and is re-run after any credential rotation, carrying the Android `Secrets Plumbing Check` guidance forward.
- A Builder holding only a free Apple account fails validation with that exact message, because a free account cannot use TestFlight and receives 7-day sideload profiles instead. Paid Apple Developer Program membership is a stated prerequisite, not a discovered one.

#### FR-181: Identifiers derived from the Builder Team ID

Every bundle identifier, App Group container and keychain access group in the build is derived from the building Builder's Apple Team ID, so two independent Builders never collide in Apple's globally unique App ID namespace. Realizes UJ-3. Upholds SI-10.

**Consequences (testable):**
- Every identifier is templated on `$(DEVELOPMENT_TEAM)` (or an equivalent `$(TEAMID)` xcconfig variable); no literal team-qualified identifier is committed.
- The app, the Watch app and every extension resolve to distinct App IDs under one Builder prefix, and two forks built by different Builders produce non-colliding identifiers with no source edit in either.
- The App Group container shared by the app and the Watch app, and the keychain access group holding pairing secrets and credentials, are both Team-ID-derived; a build whose entitlements name a group outside the signing team's prefix fails signing rather than silently falling back.
- Keychain items written by the pipeline-produced build carry a device-only, after-first-unlock accessibility class (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) so overnight reconnection works while locked and nothing syncs to iCloud Keychain. Enforced by the Entitlements and Plist Guard inside the `Static Analysis Gate` Required Check. See FR-204.
- `CODE_SIGN_STYLE = Manual` with the provisioning profile specifier pinned in a committed xcconfig; automatic signing is not used in any pipeline configuration.

#### FR-182: One-time identifier and capability registration

A Builder can run a one-time setup workflow that registers with Apple every App ID the build needs, enabling exactly the capabilities the app uses, and that reports which entitlements Apple grants only by individual application rather than failing on them. Realizes UJ-3. Upholds SI-10.

**Consequences (testable):**
- **One App ID set per Builder, registered once.** The identifier-registration workflow runs a single time per fork and claims one set of bundle identifiers for the app, the **Watch app** and every extension. This is the verified Loop model: a second concurrently-installed app would need a second, distinct identifier set, which is how LoopCaregiver ships alongside Loop.
- **The channel is a build-time choice, not a second app.** A **Builder** selects the branch when they dispatch the build — `develop` produces a development build, `main` produces a production build — and the new build **replaces** the installed one. Stable and development do not sit side by side on one iPhone, because they share bundle identifiers.
- **Rationale.** Side-by-side installation would double the identifier registration and the setup a non-technical **Builder** must get right, to serve a case a maintainer can already handle by registering a second identifier set themselves. Documented as an advanced path, not the default one.
- The workflow creates App IDs for the host app, the Watch app, and each widget/complication extension, plus the App Group container, all Team-ID-templated, and is idempotent — a second run on an already-provisioned account succeeds without duplicating records.
- It enables exactly the capabilities the app uses and no others: App Groups, Keychain Sharing, Background Modes for Bluetooth central, Time Sensitive Notifications, and Push Notifications only if and when the reserved device-token path is wired.
- `com.apple.developer.usernotifications.critical-alerts` is not present in any committed entitlements file. The workflow reports it as unobtainable-by-application with a one-line explanation and exits successfully; no build step, signing step, or runtime path fails because it is absent.
- Any entitlement Apple grants only out-of-band is rejected by the Entitlements and Plist Guard inside the `Static Analysis Gate` Required Check if it is added to a committed entitlements file (FR-204), because such an entitlement would make every Builder's build fail to sign.
- The workflow reports days-to-expiry for the distribution certificate, the provisioning profile, and the Apple Developer Program membership, and warns below a threshold, because all three lapse on a one-year cycle with no upstream visibility.
- The workflow's failures name the specific missing capability or account state, never "provisioning failed".

#### FR-183: Building, signing and uploading from the Builder's own fork

A Builder can run one workflow in their own fork that preflights their credentials, archives the app, signs it with their own Apple Distribution identity, and uploads it to their own TestFlight, choosing at run time whether to build the stable or the development channel. Realizes UJ-3.

**Consequences (testable):**
- The workflow takes a branch input with exactly two documented values — `main` (stable) and `develop` (development) — and defaults to `main`.
- Preflight runs before any archive step and fails closed: a missing or non-authenticating credential aborts the run before compilation, so a build can never proceed unsigned or wrongly signed. This preserves the Android `dev-pre-release.yml` property that an unset credential fails before any build rather than publishing an improperly signed artifact.
- The workflow uses only the fork's own repository secrets and the default `GITHUB_TOKEN`. It mints no upstream GitHub App token and reads no upstream secret store; upstream is not in the Builder's trust boundary.
- Every third-party action referenced in the build lane is pinned to a full 40-character commit SHA; the `Workflow Lint` Required Check's SHA-pin guard covers this workflow with no exception (FR-202). Signing secrets are scoped to the narrowest job that needs them and are never available to a `pull_request`-triggered job.
- On success the run reports the uploaded marketing version, build number, source branch and short commit; on App Store Connect rejection it surfaces Apple's rejection message verbatim rather than a generic failure.
- The archive is a single `.ipa` containing the Watch app and every extension; there is no separate watch artifact to build, sign, name or upload.

**Out of Scope:**
- Xcode Cloud as the supported path: its workflows live in App Store Connect against one team's app record, not in the repository, so a fork inherits `ci_scripts/` but not a working pipeline.
- A second App ID, provisioning profile and App Store Connect record enabling stable and development side by side on one iPhone (see Notes).

#### FR-184: Distribution-signing assertion, hard fail

The pipeline verifies before upload that the archive is signed by an Apple Distribution identity for the configured team, that the embedded profile does not permit debugging, and that the profile is unexpired, and fails the run on any violation. Realizes UJ-3.

**Consequences (testable):**
- Four assertions, all required, all evaluated on the built archive: the code signature names an `Apple Distribution` identity; the embedded provisioning profile has `get-task-allow == false`; its `TeamIdentifier` equals the configured `DEVELOPMENT_TEAM`; its `ExpirationDate` is in the future.
- Any failure exits non-zero. There is no warning path, no `continue-on-error`, and no environment variable that downgrades the check — mirroring the Android rule that a build failure tolerated at build time is still fatal at the certificate-verification step.
- The check runs before the App Store Connect upload, so a development-signed or expired-profile archive never consumes a build number and never produces a late, opaque upload rejection.
- `get-task-allow == false` is the specific iOS equivalent of "this is not a debug-signed build" and is asserted by name, replacing the Android fixed-fingerprint equality that has no per-Builder analogue.
- The check's rationale and provenance are recorded in-repository. (The Android side referenced `docs/dev/parity-gate-runbook.md` three times; that file does not exist, leaving its fingerprint with no provenance record. That defect is not ported.)

#### FR-185: Custody of signing material within a run

Signing material materialized during a build is created with restrictive permissions, removed if the operation fails midway, never written to a log, and explicitly destroyed by the calling job regardless of build outcome. Upholds SI-9.

**Consequences (testable):**
- The certificate and profile are imported into an ephemeral macOS keychain created with a random password for that run only; nothing is written into the login keychain or any persistent store.
- `umask 077` precedes any write; the destination is deleted before it is created; an `ERR` trap removes a partially written file; materialized files end at mode `0600`.
- Only paths and non-sensitive identifiers are printed. A test asserts no keychain byte, passphrase, `.p8` content, or certificate body appears in the run log or any uploaded artifact.
- The calling job runs an `if: always()` teardown that deletes the ephemeral keychain and removes installed profiles, because a composite action cannot register a post-job step — the same constraint, and the same caller-side remedy, as the Android `op-load-signing-secrets` action.
- A `Signing Smoke` workflow, `workflow_dispatch` only and explicitly a non-required job (it is not one of the five Required Checks of FR-197), asserts that a signing identity and a matching profile resolve for the configured bundle identifier without printing either, and additionally fails if the resolved entitlements request a capability not enabled on the signing team.

#### FR-186: On-demand and scheduled rebuild so an installed build never lapses

A Builder can re-run their build on demand and on a recurring schedule, so the build installed on their iPhone never passes Apple's 90-day TestFlight expiry. Realizes UJ-3. Upholds SI-6.

**Consequences (testable):**
- The scheduled rebuild workflow ships in the repository enabled by default, so it exists in every fork from the first sync without the Builder authoring anything.
- The schedule mirrors the verified Loop pattern: a **weekly check** that rebuilds when the tracked branch has changed, plus a **monthly build regardless of changes**, so a quiet upstream cannot let a build lapse. Both fire well inside Apple's 90-day TestFlight expiry with margin for two consecutive failures.
- The known failure mode is documented explicitly, because Loop's users hit it: **a fork whose tracked branch sees no change for 90 days can still expire** if only the change-triggered job is enabled. The monthly unconditional build exists precisely to close that, and disabling it is called out as the thing not to disable.
- A `workflow_dispatch` trigger allows an immediate rebuild, and the in-app expiry surface (FR-187) deep-links to it.
- A failed scheduled rebuild notifies the Builder rather than failing silently, and the failure message names the specific credential or account state at fault (FR-180).
- Documented hazard, surfaced not hidden: GitHub disables scheduled workflows in a repository with 60 days of inactivity — 30 days before the build expires. Any repository activity, including the upstream sync of FR-195, re-arms it. The setup documentation states this on the build page, not in troubleshooting, and the in-app countdown of FR-187 is the backstop.
- Rebuilding is documented as the only mechanism that extends a build's life; the app never claims an installed build can be renewed from the device.

#### FR-187: In-app build provenance, channel and expiry

The app shows the version and commit it was built from, its channel, its build date, and the number of days until it expires, with escalating prominence as expiry approaches, and tells the Builder the exact action that refreshes it. Realizes UJ-3. Upholds SI-6.

**Consequences (testable):**
- The surface shows, all of them: marketing version, build number, source tag, 7-character source commit SHA, channel (`stable` or `development`), build/upload date, computed expiry date, and integer days remaining.
- Values are injected at archive time and are read-only at runtime; the app never queries App Store Connect. [ASSUMPTION: expiry is computed as the recorded upload timestamp plus 90 days, since no on-device API reports a TestFlight build's expiry.]
- Prominence escalates as expiry nears. [ASSUMPTION: a passive Settings row until 30 days remain, a persistent non-blocking banner at 14, and a local notification at 7, 3 and 1 — the Android repo has no expiry surface to derive thresholds from.]
- Where the pipeline recorded them, the surface also shows days-to-expiry for the signing certificate, the provisioning profile and the Apple Developer Program membership.
- The refresh affordance names the exact action ("re-run your build workflow") and links to the Builder's own workflow, never to an upstream artifact.
- No surface anywhere states or implies that monitoring, the Alert Floor, or the Coverage Claim continues past expiry. An expired build does not launch, and the app must never have promised otherwise.

#### FR-188: Upstream release notice and TestFlight deep link

The app can tell the Builder that a newer upstream release exists than the one it was built from and deep-link to TestFlight, and never downloads, stores or executes code obtained at runtime. Realizes UJ-3. Upholds SI-6.

**Consequences (testable):**
- The check is the single permitted exception to Backend-optional network silence (NFR-23). It is user-toggleable and **off by default**, so a Builder who has enabled nothing makes no request to `github.com` at all. It carries and receives no health data: the request is an unauthenticated read of the upstream releases list and the response is consumed only as a tag string. It is the only host outside the user's configured Backend the app ever contacts, and the outbound-host-set test asserts exactly that set: the Backend, plus the GitHub Releases API host and only while the toggle is on. `objects.githubusercontent.com` is never contacted, because nothing is downloaded.
- The check reads the upstream GitHub Releases API and compares the newest release tag against the exact tag the running build was made from; the notice states both versions explicitly, so there is no ambiguous match. This preserves the Android selector's anchored, single-match discipline in the only form iOS leaves for it.
- The notice is non-blocking and its action is a `itms-beta://` deep link to TestFlight plus a pointer to re-run the build workflow.
- The check fails silent, never fails wrong: an unreachable API, an HTTP 403 rate limit, or an unparseable response leaves the notice absent rather than showing an error state or a wrong comparison.
- No code path in the app downloads an executable, a package, a bundle, or a script; there is no analogue of the APK download path, its `github.com`/`objects.githubusercontent.com` host allowlist, its filename sanitization, its expected-size check, its `apk_updates` cache, or its 100 MB cap, because there is nothing to download.
- The Watch app derives no update state of its own; it ships inside the same `.ipa` and is installed and updated by the system with the app.

#### FR-189: Build-time composition of what ships

Compile-time inclusion of an individual Driver is controlled by an in-repository build setting that excludes the Driver from the shipped binary by a compilation condition, and no build a Builder runs contains a project-owned telemetry or analytics credential. Realizes UJ-6. Upholds SI-1. Upholds SI-9.

**Consequences (testable):**
- Each gateable Driver has a build setting defaulting to enabled (the Android `MEDTRONIC_DRIVER_ENABLED` analogue). Disabling it is a **compilation condition**, not a runtime flag: the Driver module is not compiled into the shipped binary and is absent from the Driver Catalog, so there is no inert-but-present module a defect could reach. This matches Android's build-time intent and goes further than Android's mechanism, which compiled the plugin in and left it inert at runtime. What the Builder sees is FR-27 (5.2); the composition mechanism is here.
- Both halves are required and neither substitutes for the other. Because a compilation condition leaves gated code uncompiled and therefore untested in the shipping configuration, CI additionally builds a configuration with **every** Driver's gate enabled so no gated Driver loses compilation or test coverage (FR-208, 5.11). A compilation condition without that CI configuration is untested code; that CI configuration without the compilation condition is not a kill switch.
- The Simulated Driver and the Trace-Replay Driver are governed by the same mechanism as any other Driver, not by `#if DEBUG`, so a shipped configuration cannot silently lose the only Drivers that are testable without hardware.
- No build setting, compilation condition, scheme, or configuration anywhere in the repository enables a therapeutic write. The only Driver-affecting setting is subtractive — it can remove a Driver, never add a Capability.
- This FR is the single definition of the no-project-telemetry rule; NFR-23 (§6), FR-236 (5.12) and NG-6 (§11) defer to it and restate nothing.
- The crash/error-monitoring DSN defaults to empty in every configuration, is sourced only from the building Builder's own secret, and is never committed.
- The build hard-fails when a non-empty DSN is present while the build is running in CI, preserving the Android `GradleException` guard: an upstream-owned telemetry credential in a build users install would route patients' crash and breadcrumb data to the project. String values are escaped on the way into the generated configuration so an unusual value cannot break the literal.
- The `Static Analysis Gate` Required Check fails any pull request that commits a DSN, an analytics key, or any other project-owned telemetry credential; its secret-scanning steps (Semgrep `p/secrets`, gitleaks) are the mechanism (FR-200).

#### FR-190: One version source of truth

The repository has exactly one version source of truth, bumped automatically from conventional commits, and the app, the Watch app and every extension always report the identical marketing version.

**Consequences (testable):**
- One `Config/Version.xcconfig` carries `MARKETING_VERSION = X.Y.Z // x-release-please-version`; every target consumes that variable and no target hardcodes a version.
- release-please configuration carries over unchanged: release-type `simple`, `include-v-in-tag: true` (tags are `vX.Y.Z`), `bump-minor-pre-major: true`, `include-component-in-tag: false`, draft and prerelease false, PR title pattern `chore: release ${version}`, single package `.`, manifest baseline `{".": "0.14.0"}`. `extra-files` names the one xcconfig in place of the three `build.gradle.kts` files.
- CHANGELOG section visibility carries over: `feat`, `fix`, `perf`, `docs`, `refactor`, `ci` visible; `chore`, `test` hidden. release-type `simple` keeps release-please the owner of CHANGELOG.md.
- A build in which the Watch app's `CFBundleShortVersionString` differs from the host app's fails, because Apple requires equality and single-sourcing it is mandatory rather than tidy.
- A version hardcoded in any target-level setting rather than read from `Config/Version.xcconfig` fails a build-settings check that runs in `Build & Test` and reaches merge gating through the `iOS Gate` Required Check. FR-197 assigns that host; this FR is the check's single definition and 5.11 carries no second one.

#### FR-191: Monotonic build numbers

Every build uploaded to App Store Connect carries a build number strictly greater than any previously uploaded for that Apple account, derived so that it cannot regress when a fork is recreated, a run counter resets, or a maintainer archives locally before archiving in CI.

**Consequences (testable):**
- `CFBundleVersion` is derived from a monotonic UTC clock value plus a `BUILD_NUMBER_OFFSET` repository variable defaulting to `0`. [ASSUMPTION: minutes since a fixed epoch; the exact unit is an implementation choice, the monotonicity property is the requirement.]
- The build number is never derived from a GitHub Actions run number: a run counter regresses when a Builder recreates their fork or resets workflows, and App Store Connect then permanently rejects uploads for that marketing version.
- `BUILD_NUMBER_OFFSET` may only increase. It carries the same do-not-remove framing as Android's permanent `DEV_RUN_NUMBER_OFFSET = 500`: lowering it strands the Builder's ability to upload, exactly as lowering +500 would have stranded dev-channel users forever.
- The Android packed formula `major*1_000_000 + minor*10_000 + patch` is not reproduced anywhere. It collides silently at patch > 9999 or minor > 99, and on Android a collision made the updater report "up to date" forever — a state in which a safety fix never reaches a patient.
- A rejected upload surfaces App Store Connect's message verbatim, and the documentation names the offset variable as the remedy.

#### FR-192: develop-to-main promotion

A maintainer can promote develop to main with a single command, and that one push fans out to version bumping, changelog PR creation and cherry-pick sync-back, with message-string trigger predicates that prevent any loop.

**Consequences (testable):**
- Two long-lived branches. Contributor pull requests target `develop` and are squash-merged; `main` is release-only. Promotion is `gh pr create --base main --head develop --title "chore: promote develop to main"` merged as a real merge commit, not a squash, to preserve ancestry.
- The three trigger predicates are preserved verbatim: the changelog workflow fires on `promote develop to main` and NOT on `[Changelog]` or `chore: release`; the sync-back workflow fires ONLY on `chore: release` or `[Changelog] Update CHANGELOG.md`. The promotion commit therefore never re-triggers sync and no bot commit re-triggers the changelog.
- A promotion whose commits are all chore/ci/docs/test but which changed deployable code cuts a fallback patch release: the current version is read from the immutable triggering SHA (`git show <github.sha>:.release-please-manifest.json`) so a rerun cannot compute a different version, the patch is incremented, an existing tag short-circuits the bump, the rewrite is grep-verified or hard-fails, and branch and tag land together via `git push --atomic origin main refs/tags/$TAG`.
- The changelog window's lower bound comes from `<!-- changelog-cutoff:<ISO8601> -->` validated against `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[Z+]` with a hard fail on mismatch (anti-injection), falling back to the last dated header plus one day, then to `2025-01-01T00:00:00Z`. The changelog PR title is exactly `[Changelog] Update CHANGELOG.md`.
- Sync-back cherry-picks onto `sync/main-to-develop-<7-char sha>` and force-resolves conflicts to main's version for exactly three files — `.release-please-manifest.json`, `Config/Version.xcconfig`, `CHANGELOG.md` — down from Android's five. Anything else unresolved aborts the cherry-pick, pushes nothing, and requires a manual sync. The phantom sixth allowlist entry Android tolerates but never produces is dropped.
- Every admin-merge re-validates author, exact title, and the complete changed-file list before bypassing, for the release, changelog and sync pull requests alike.
- Every bot commit is DCO signed off (`git commit -s` / `--signoff`), with no maintainer exemption tier.

#### FR-193: Pinned build inputs

The Xcode version, the Swift package graph, the Ruby release toolchain and every CLI tool used by the pipeline are pinned in the repository, are the same on a maintainer's machine as in CI, and a mismatch fails the build.

**Consequences (testable):**
- A committed `.xcode-version` is the single toolchain pin, and a maintainer's machine and CI select the same value from it; the build asserts at start that the selected toolchain matches the pin. An unpinned Xcode bump can silently change signing behavior, entitlement defaults and package resolution, so it is treated as a build-toolchain change requiring lead review. CI's selection step is FR-208.
- The Swift package graph is pinned by a committed `Package.resolved`, automatic resolution is disabled, resolution drift is a hard failure, and cryptography- and Bluetooth-adjacent packages are declared `.exact` or `.upToNextMinor`. See FR-201.
- `Gemfile.lock` is committed and every fastlane invocation runs through `bundle exec`. The Ruby toolchain is the second real lockfile in an iOS repository and is not optional; it is pinned here because the build-and-sign lane is the only lane that runs fastlane, and nothing in 5.11 covers it.
- Pinned CLI tools install as version-pinned, SHA-256-verified release binaries rather than unpinned marketplace actions. See FR-202.
- Every third-party GitHub Action is pinned to a full 40-hex commit SHA across workflow files and composite action definitions, including the fork-facing build-and-sign workflow. See FR-202.
- Recorded honestly: nothing in the iOS toolchain corresponds to Gradle wrapper checksum verification. Toolchain trust reduces to the GitHub-hosted runner image plus the Xcode pin, and that gap is stated rather than papered over.

**Out of Scope:**
- The gate job definitions that enforce these pins, and the pin values themselves (5.11: FR-201, FR-202, FR-208).

#### FR-194: Bot dependency pull requests and the auto-merge scope guard

A bot dependency pull request that changes package manifests has its resolved lockfile regenerated automatically on an Apple toolchain and pushed back to the same pull request or fails visibly, and no bot pull request can auto-merge if it touches a file outside what the build and dependency gates actually cover. Realizes UJ-6.

**Consequences (testable):**
- Regeneration is required because the bot's container has no Swift toolchain and its Swift manager edits `Package.swift` without touching `Package.resolved` at all — a stale lockfile would otherwise merge.
- Two-job privilege split, ported verbatim in shape. The `regenerate` job runs on a macOS runner, checks out the pull-request head with no credential, records the exact SHA, resolves packages, counts changed lockfiles, and uploads them with `if-no-files-found: error` and 1-day retention. It holds no token.
- The `push` job runs only when something changed, checks out the exact SHA the lockfile was built from with `persist-credentials: false`, downloads the artifact over the tree, mints a token scoped to contents-write only, sets `git config core.hooksPath /dev/null` so no pull-request-authored hook runs, commits with `--signoff`, and does a non-force push to the pinned head ref so a branch that advanced meanwhile is rejected as non-fast-forward. This job never executes pull-request code.
- The scope guard is explicitly a **non-required job** — it is not one of the five Required Checks of FR-197, because its function is to withhold auto-merge rather than to block merge, and branch protection keys only on those five literal names. It runs on `pull_request_target` with `permissions: pull-requests: read`, no checkout, and the changed-file list read via the API — deliberately, so the gate evaluates trusted base-branch logic rather than a version the pull request could have edited. It is a no-op pass unless the author is the dependency bot AND the `automerge` label is present; a non-pass leaves the pull request to ordinary human review rather than blocking it.
- Each changed file must match both an allowlist regex (`Package.swift`, `Package.resolved`, `Gemfile`, `Gemfile.lock`, workflow files, `Brewfile`, `mise.toml`, `.xcode-version`) AND the union of the `iOS Gate` and `Dependency Scan Gate` paths-filters (FR-201, FR-208). A file that is allowlisted but outside gate coverage fails, because it would otherwise auto-merge unbuilt and unscanned.
- Top-level `automerge: false` is retained as a load-bearing guard: platform auto-merge defaults on, so any rule setting `automerge: true` would enqueue native auto-merge at pull-request creation and bypass the file allowlist entirely.
- Nothing touching cryptography, secure storage, database encryption, the build toolchain, CI action pins, prerelease packages, or any major version can auto-merge; all route to lead review. `minimumReleaseAge: "7 days"` with strict internal checks keeps the soak as the primary supply-chain defense, with `prHourlyLimit: 3` and `prConcurrentLimit: 6`.
- The label relay that converts an eligible label set into native auto-merge is authored in this repository rather than inherited: the Android repo documents and allowlists `auto-merge-renovate.yml` by name and the file does not exist. Either it is written here or every reference to it, including its workflow-security allowlist entry, is removed.

#### FR-195: Syncing a fork with upstream

A Builder can pull upstream changes into their fork and rebuild without manual merge work, and can see what changed before that code runs with their signing credentials. Realizes UJ-3.

**Consequences (testable):**
- A documented one-command sync (`gh repo sync`, or a scheduled sync workflow shipped in the template) fast-forwards the fork's `main` and `develop` from upstream without the Builder resolving anything, as long as they have not modified tracked files.
- A sync that cannot fast-forward fails visibly with the diverging paths named, rather than silently leaving the fork behind or silently merging.
- The Builder can see, before rebuilding, the upstream release they are currently behind and the diff since their current build's commit; the app's own upstream notice (FR-188) is the passive half of the same signal.
- Syncing counts as repository activity and re-arms a scheduled rebuild that GitHub disabled after 60 days of inactivity (FR-186).
- The documentation states plainly that syncing upstream pulls new workflow code that will execute with the Builder's Apple signing credentials, and that reading the workflow diff is a reasonable precaution.
- A Builder who has modified their fork keeps their modifications; sync never force-overwrites local commits.

#### FR-196: The pipeline as a supported surface, and the Builder boundary

The fork's build-and-sign pipeline is maintained as a supported product surface — CODEOWNERS-gated, SHA-pinned, and inside SECURITY.md response scope — while key custody, Apple account state, certificate lifecycle and rebuild cadence remain the Builder's. Realizes UJ-3. Realizes UJ-6.

**Consequences (testable):**
- **Privileged upstream jobs run behind a `release-gated` environment requiring a named reviewer.** Android gates seven jobs this way. Without it, "supported product surface" is a claim with no access control behind it.
- **Upstream automation uses a least-privilege split across separate GitHub Apps rather than one broadly-scoped token** — Android splits four ways (release, merge, CI dispatch, docs). A single token with union scope is the failure mode this prevents.
- These two controls are what make the decision-6 argument hold: **Builders** load their own App Store Connect key into a run executing project workflow code, so the project owes them a reviewed, least-privilege pipeline rather than a disclaimer.
- Every build-lane, signing-configuration and release-configuration file specified in this section is CODEOWNERS-routed to the project lead. The roster itself is defined once, in 5.11; this section adds no CODEOWNERS entries of its own and states none. See FR-212.
- The build lane is treated as the highest-trust file in the repository: minimal action set, plain `run:` steps preferred over marketplace actions, every reference SHA-pinned with no exception, and any change to it reviewed as security-critical.
- SECURITY.md states explicitly that building from a fork executes upstream code with the Builder's Apple signing credentials, and places the build-and-sign pipeline inside the project's security response scope with the same private reporting channels as the app.
- The documentation states, in the setup path and not in troubleshooting, that the Builder owns: custody of their App Store Connect key and certificate store passphrase; the state of their Apple Developer Program membership; the annual certificate and provisioning profile lifecycle; and the cadence at which they rebuild before the 90-day expiry.
- The project makes no claim about what any installed build contains. Because every Builder compiles and signs their own binary, every architectural claim in the project's published documents is a claim about the source at a stated tag, not about the binary anyone is running — and that boundary is stated in writing.
- A Driver contribution reaching the Driver trees or the build lane cannot auto-merge and requires lead review (FR-212 for the routing, FR-194 for the auto-merge scope guard).

**Feature-specific NFRs:**

- Preflight failures are cheap and fast: a missing or non-authenticating credential aborts before compilation, so a misconfigured fork costs seconds of macOS runner time, not a full archive.
- macOS runner minutes carry roughly a 10x multiplier on private repositories. The upstream repository stays public so standard runners remain free; platform-independent Driver, domain and unit-conversion modules are tested with `swift test` on Linux runners; documentation-only changes do not trigger a build. Builders are advised to keep their forks public for the same reason — a private fork can exhaust a free allowance in a handful of iOS-plus-watchOS builds and lose the ability to rebuild before expiry.
- Every job in the build lane declares an explicit `timeout-minutes`, closing the Android gap where the dependency-scan and build jobs have none. The lockfile-regeneration job's Android 15-minute timeout is raised: a cold SwiftPM resolve on a macOS runner is slower than a Gradle resolve.
- The full promotion, changelog and sync-back cycle is exercised on a throwaway repository before the first release. The Android pipeline is documented as "built, unit-proven in parts, never exercised end to end" and its lockfile-regeneration path as an "UNPROVEN PATH"; porting it wholesale ports unvalidated behavior into a repository whose first real release would otherwise be its first live test.

**Notes:**

Parity Ledger entries originating in this section — 1 through 10 are forced losses, 11 is a deliberate divergence:

1. **No project-published installable binary and no in-app self-update.** The entire `AppUpdateChecker` / `WearAppUpdateChecker` / `dev-latest` install channel, and the APK download hardening around it, have no iOS target. Replaced by TestFlight plus a read-only upstream notice (FR-188).
2. **An installed build expires after 90 days and stops launching.** An Android APK runs indefinitely. For a glucose monitor this is a silent loss of monitoring, mitigated but not eliminated by FR-186 and FR-187.
3. **Scheduled rebuilds are disabled by GitHub after 60 days of fork inactivity** — 30 days before expiry. No Android analogue.
4. **The fixed release-signer fingerprint equality check cannot exist.** Replaced by a property assertion (FR-184); nothing structurally ties a build to a project-known identity.
5. **No Gradle-wrapper-checksum equivalent for the Xcode toolchain.** Toolchain trust reduces to the runner image plus a version pin (FR-193).
6. **Every Builder must hold and annually renew a paid Apple Developer Program membership**, and their certificate and provisioning profile expire on a one-year cycle. Android required no account and no renewal.
7. **Per-Builder App ID registration is mandatory** because Apple's App ID namespace is globally unique; an Android `applicationId` is just a string. This is the largest new setup burden and has no Android counterpart.
8. **Side-by-side stable and development installs are not free.** Android got them from an `applicationIdSuffix ".debug"`; iOS needs a second App ID, profile and App Store Connect record per Builder. Not provided in v1 (FR-183).
9. **Watch-face artifacts disappear entirely** — no `GlycemicGPT-WatchFace-Digital/Analog` builds to produce, sign, publish or carve out of the certificate assertion. Strictly better on the signing axis (the Android watch-face APKs were debug-signed), but a lost capability.
10. **Upstream cannot verify what any installed build contains.** Every published claim is a claim about source at a tag.
11. **The upstream release notice is off by default and user-toggleable**, where Android's update check ran automatically. A deliberate divergence rather than a forced loss: it is the single permitted exception to Backend-optional network silence (NFR-23, FR-188), and an exception that is on by default is not an exception the Builder chose.

[NOTE FOR PM] Open, and mine to flag rather than settle: must a Builder be able to run the stable build and the development build on the same iPhone simultaneously? On Android this was free. On iOS it costs every single Builder a second globally-unique App ID, a second provisioning profile, a second App Store Connect record and a second TestFlight setup — roughly doubling onboarding. FR-183 assumes one identifier with a branch-selectable channel. If side-by-side is a real product requirement it needs to be stated before the provisioning workflow of FR-182 is built, because it changes what that workflow registers. Registered as §15 OQ-50.

[NOTE FOR PM] The build number derivation (FR-191) is a clock-derived value plus a never-decreasing offset. This is a decision, not a port — Android's packed `versionCode` formula is deliberately abandoned. If a Builder has already uploaded a higher build number by archiving locally in Xcode before using the pipeline, the `BUILD_NUMBER_OFFSET` escape hatch is the documented remedy; that path should be exercised once before the first release.

[NOTE FOR PM] Upstream may still want a 1Password-backed local convenience path for the lead's own maintainer builds. It must never become a project-held signing identity and must not be referenced from any fork-facing workflow. Flagging so it is a deliberate choice rather than a leftover. Registered as §15 OQ-61.

[NOTE FOR PM] The legal framing of a Builder as builder, signer and installer-to-self — whether "users become the manufacturer of their own personal medical device" now describes every user rather than only fork users — affects the wording of the build-and-install documentation. That determination belongs to 5.12 and to counsel; this section states the builder relationship factually and asserts no legal conclusion. Registered as §15 OQ-56.


### 5.11 Engineering Gates and Contract Guards

**Description:**

This section is the engineering system itself, so it names concrete tools, gate names, files and workflows — that naming *is* the requirement. Everything else in this PRD is a claim about what the app does; this section is the machinery that makes those claims survive contact with a second contributor.

The shape is inherited from the Android repository and is deliberately conservative. Merge to `develop` is gated by exactly five **Required Checks**, matched by GitHub on the *job* `name:`, not the workflow `name:`: `Static Analysis Gate`, `Dependency Scan Gate`, `Workflow Lint`, `Workflow Security`, `iOS Gate`. Branch protection keys on those five literal strings, so renaming a job silently removes a gate — the names are part of the contract, not cosmetics. That roster is closed, and FR-197 owns it: every mechanical gate this PRD names anywhere is a step or a test inside one of those five, or is explicitly a non-required job. A requirement elsewhere that says "a Required Check fails…" without naming one of the five names a gate that does not exist. The single most load-bearing structural rule carried over is the *always-report* pattern: a Required Check that is paths-filtered at the workflow level is never created at all, leaves the pull request permanently "pending", and wedges the merge. Two solutions coexist, both preserved verbatim. `Static Analysis Gate`, `Workflow Lint` and `Workflow Security` run unconditionally on every pull request with no paths filter. `iOS Gate` and `Dependency Scan Gate` are `if: always()` aggregation jobs that read `needs.*.result` through `env:` (never shell-interpolated — the template-injection-safe pattern zizmor enforces) and fail closed on anything that is not an explicit pass.

The second structural rule: every Required Check must complete on a pull request opened from a fork, with a read-only token and no repository or organization secret. This is not hygiene, it is the precondition for UJ-6 — Alex contributes a Driver from a fork and gets the same verdict the lead developer gets. It forces two concrete choices: pull-request builds are unsigned Simulator builds, and static-analysis results are evaluated from a local SARIF file with `jq` rather than uploaded to code scanning, because `security-events: write` is not granted to fork pull requests and an upload-based gate would fail for every external contributor.

The analyzer is where honest divergence begins. Android's `Security Scan Gate` runs Semgrep with `p/kotlin`, `p/java` and `p/secrets`. Two of those three packs match Kotlin and Java syntax and produce **exactly zero findings on Swift**. A name-only port — same workflow, same tool, same required-check name — would yield a permanently green check that tests nothing, and would look like parity while being an absence. So the gate survives, the name changes to `Static Analysis Gate`, and the analyzer is replaced: CodeQL with language `swift` and the `security-extended` query suite as the primary taint and dataflow analysis, plus Semgrep `p/secrets` retained unchanged (regex and entropy matching, language-agnostic) and `gitleaks` promoted to a first-class failing step. The query pack is pinned by version, which actually *improves* on Android, where the CLI was pinned to 1.169.0 but the registry rule packs were fetched at scan time and could turn a previously-green commit red with no repository change. The coverage delta is real and is a recorded parity loss: CodeQL's Swift suite is not `p/kotlin` + `p/java`, and a green `Static Analysis Gate` here carries less assurance than the same-named gate did on Android. The mitigation is to move invariants *out* of static analysis and into the type system and into tests — which is what most of the rest of this section does.

Failing closed is implemented in exactly two places and both are preserved. First, the analyzer's own exit status: an unset or missing exit code defaults to fail (`${EXIT:-2}`), a scanner error fails the gate, and a missing or empty results file makes the `jq` step error out, which is also a fail. Second, the aggregation jobs' non-success branches. Added on top, because Swift makes it necessary: the gate fails if the analyzer reports **zero analyzed files**. Semgrep records unparseable files in `.errors[]` without changing its exit code, and CodeQL's Swift extractor reports files it could not compile as database diagnostics rather than analysis failures — in both cases a whole target contributes zero findings and the gate stays green. On Swift this is a recurring case (macro expansion, mixed Objective-C bridging headers), so unprocessable files are surfaced as a non-blocking `::warning::` with the file list, and a run that analyzed nothing at all is a hard failure.

Android compensated for its lack of artifact-level scanning with Android Lint, which covers manifest and network-security posture. Apple ships nothing comparable: `xcodebuild analyze` runs the Clang analyzer over C and Objective-C, not Swift, and inspects neither `Info.plist` nor entitlements. MobSF is declined for the same reasons Android declined it, with the same revisit trigger carried verbatim. In its place sits a purpose-built, deterministic **Entitlements and Plist Guard** with no suppression baseline to maintain and no false-positive tax. Its App Transport Security half is a *no-broadening* guard, not a plist design: the product requirement is the app's own private-address-only cleartext policy (FR-150, NFR-20), enforced in-app by strict literal-address classification and never by DNS lookup or by the platform layer, and the Info.plist configuration that achieves it is an architecture decision awaiting empirical verification (§15 Open Questions). This section does not state a plist shape as settled; the guard fails any broadening past whatever baseline architecture records as verified. Beyond that sits, because of fork-and-build, an entire guard class Android never needed: `Package.swift` is executable Swift evaluated at resolve time, SPM plugins run during build, and Xcode Run Script phases run on every build. Under fork-and-build all three execute inside a build that has *a user's* Apple signing credentials in its environment. Android had one project-held keystore under one person's control; here the blast radius is every Builder's developer account.

The Contract Pin guards and the Safety Constant drift guard are plain host-macOS SwiftPM tests: seconds, no Simulator, no network, unrestricted filesystem access to repository sources. Repository-root resolution is anchored on `#filePath` (baked at compile time) walking up to `Package.swift`, so the guards behave identically under `swift test` and `xcodebuild test` and never depend on the runner's working directory. The Safety Constant guard changes character from Android's: with one canonical definition of each **Safety Constant**, Android's 19-entry count-equality enumeration collapses to roughly the Tandem epoch offset alone, and the third layer inverts — instead of asserting that each known duplication site still has its expected occurrence count, CI asserts that **no** bare `20`, `500`, `18.0156` or `1199145600` appears in a glucose or **Pump**-time context outside the canonical definitions. The inverse scan is self-maintaining: a new duplication site fails without anyone remembering to update a list.

Two known Android weaknesses are deliberately not inherited. CodeRabbit's `fail_commit_status: false` makes even its `mode: error` custom checks advisory with respect to merge blocking, which means medical unit correctness and BLE protocol safety are enforced on Android by a reviewer whose verdict does not block anything. Here those invariants are load-bearing enough to be mechanical: the **Glucose Validity Bound** is a type invariant, the read-only Driver posture is an API-surface snapshot gate, and protocol framing is a replay test. CodeRabbit stays as defence in depth. And the contributor documentation is not copied: the Android repository carries at least six documented drifts between what CONTRIBUTING.md says and what CI does, so the Required Check list is verified against the configured ruleset in CI rather than transcribed.

[ASSUMPTION: exact `timeout-minutes` values for the macOS-hosted `Static Analysis Gate`, `iOS Gate` and `UI Tests (Simulator)` jobs are set at implementation time; only the requirement that every job declares one is fixed here. Android's dependency-scan and build jobs have none, and that gap is closed rather than ported.]

**Functional Requirements:**

#### FR-197: Fixed Required Check roster and branch protection

The project lead can gate merge to `develop` on exactly five **Required Checks**, named and enforced by job name, with the documented roster verified against the configured ruleset by CI. Realizes UJ-6.

**Consequences (testable):**
- The `Protect develop` ruleset requires exactly these five check names, matched against the job `name:` and not the workflow `name:`: `Static Analysis Gate`, `Dependency Scan Gate`, `Workflow Lint`, `Workflow Security`, `iOS Gate`.
- No Required Check job uses `continue-on-error`.
- Bypass actors may skip CODEOWNERS approval but never skip the five Required Checks.
- A CI step compares the check list published in CONTRIBUTING.md against the configured branch-protection ruleset and fails on any difference, so contributor documentation cannot drift from enforcement.
- Renaming a Required Check job without updating the ruleset fails that comparison step.
- **The roster is closed at five.** No sixth Required Check is created. Every mechanical gate this PRD names, in any section, is a step or a test inside one of the five, or is explicitly a non-required job; a requirement that says "a Required Check fails…" must name its host by one of the five exact strings. The published host assignment is:
  - `Static Analysis Gate` — the analyzers (FR-200); the Entitlements, Plist, signing-material and build-script guard (FR-204); the License Header Gate (FR-211); the committed-telemetry-credential check (FR-189); the **Driver** delivery-verb and therapy-characteristic scan (FR-31); the direct-system-time lint (FR-61); the documentation publication and in-repo internal-link gates (FR-219, whose four checks are the ones hosted here). FR-220 defines the documentation SET rather than a check, so it contributes no step; its pages are gated by FR-219's four checks like every other page. These steps add no macOS job — the gate is already macOS-bound for CodeQL — and they run unconditionally, which is what a documentation-only or entitlements-only pull request needs.
  - `iOS Gate`, aggregating `Build & Test` — the **Driver Catalog** registration and Driver-API-version checks (FR-21); the Driver import restriction (FR-31); the Driver protocol snapshot gate (FR-205); the replay tests (FR-206); the **Simulated Driver** exercise (FR-207); build and unit test (FR-208); the host-macOS guard target (FR-210); the **Contract Pin** guards (FR-214); the decoder guards (FR-215); the **Safety Constant** drift guard (FR-217); the static half of the accessibility identifier registry check (FR-177, defined here in FR-208); the dependency license allowlist and bundled-attribution drift checks (FR-229, enforced by FR-211); the deployment-floor and shared-safety-module checks (NFR-1, NFR-4); the version-source check, which FR-190 defines; the `Resolution Drift` step (FR-201).
  - `Dependency Scan Gate` — FR-201's vulnerability scan over the committed resolved graph. Its `Resolution Drift` step is the one part of FR-201 hosted in `iOS Gate` above, because drift is a build input rather than an advisory match. `Workflow Lint` — FR-202. `Workflow Security` — FR-203.
- A gate that must evaluate trusted base-branch logic on `pull_request_target` — the auto-merge scope guard (FR-194) and `Attribution Check` (FR-218) — can never be one of the five, because the five must complete on a fork pull request with a read-only token and no privileged context (FR-199). Both are non-required jobs; their enforcement is the job's own action, not a merge block.
- Completion of the written hardware-validation checklist (FR-207) is a documented release gate and is explicitly not a Required Check: no CI job can execute it.
- Additional jobs report their own status without being required: `Detect Dependency Changes`, `OSV-Scanner`, `Detect iOS-Relevant Changes`, `Build & Test`, `UI Tests (Simulator)`, `App Token Auth Check`, `Attribution Check`. `Build & Test`'s verdict reaches merge gating only through `iOS Gate`.
- Every job in every workflow declares an explicit `timeout-minutes`; `Workflow Lint` and `Workflow Security` use 5.
- Every workflow declares `concurrency: <name>-${{ github.ref }}` with `cancel-in-progress: true`.

#### FR-198: Always-reporting gate shape and fail-closed aggregation

Any contributor can rely on all five Required Checks being *created* on every pull request, either unconditionally or through an always-running aggregation gate that fails closed.

**Consequences (testable):**
- `Static Analysis Gate`, `Workflow Lint` and `Workflow Security` have no `paths:` filter on the `pull_request` trigger and run on every pull request.
- `iOS Gate` and `Dependency Scan Gate` are `if: always()` jobs with `needs: [detect-changes, <work job>]`.
- Each aggregation job implements the same five-branch decision: detect-changes result not `success` → exit 1; event is `schedule` or `workflow_dispatch` → require the work job to have succeeded, else exit 1; push or pull request with `should_*` not `'true'` → print the skip reason and exit 0; work job `success` → exit 0; any other result including `failure` and `cancelled` → exit 1.
- A `skipped` work job on a push or pull request where nothing relevant changed resolves to a pass.
- `needs.*.result` values reach the shell through `env:` and are never interpolated into a `run:` block.
- Introducing a workflow-level `paths:` filter on any Required Check fails `Workflow Lint`'s policy step.

#### FR-199: Every Required Check passes on a fork pull request

An external contributor can open a pull request from a fork and have all five Required Checks run to completion with a read-only token, no repository or organization secret, and no privileged context. Realizes UJ-6.

**Consequences (testable):**
- All five Required Checks trigger on plain `pull_request`; none requires a secret.
- Workflow-level permissions are `contents: read`; `Dependency Scan Gate` and `iOS Gate` add `pull-requests: read` only for the paths filter.
- Every checkout in a Required Check sets `persist-credentials: false`.
- Pull-request builds are unsigned Simulator builds (`-sdk iphonesimulator`, `CODE_SIGNING_ALLOWED=NO`); no signing identity, certificate, provisioning profile or App Store Connect key is referenced by any pull-request-triggered job.
- Static-analysis results are evaluated from the local SARIF file; upload to code scanning happens only on push to `develop` or `main`, because fork pull requests are not granted `security-events: write`.
- Jobs that mint an App token guard both the mint and the verify step with `github.event_name != 'pull_request' || github.event.pull_request.head.repo.fork != true`.
- Workflows requiring write access run on `pull_request_target` in base-repository context and never check out pull-request-supplied code.

#### FR-200: Swift static security analysis with a pinned query set, failing closed

A contributor can have every pull request analyzed by a Swift-capable static security analyzer whose rule set is pinned in the repository and whose gate fails closed on scanner error, on a missing results file, and on a run that analyzed nothing. Upholds SI-9.

**Consequences (testable):**
- `Static Analysis Gate` runs CodeQL with language `swift` and the `security-extended` query suite, plus Semgrep `p/secrets` and `gitleaks` in the same job, on `macos-latest`.
- The CodeQL query pack is pinned to an exact version (`packs: codeql/swift-queries@<x.y.z>`); no rule content is fetched unpinned at scan time. Semgrep is pinned by CLI version.
- Documentation states plainly that Semgrep `p/kotlin` and `p/java` produce zero findings on Swift, and that porting those packs by name would produce a permanently green check that tests nothing.
- Scope is derived from the build graph via CodeQL autobuild over a scheme that compiles every shipping target — the app, the **Watch app**, the widget extension, every **Driver** in the **Driver Catalog**, and any research spike — so adding a module cannot silently fall outside scan scope.
- Blocking threshold: any result with `properties.security-severity >= 7.0` or `level == "error"` fails the gate, printing each as a one-line finding. `warning` results are counted and printed non-blocking. `note` results are neither counted nor blocking.
- Scanner-error fail-closed: an exit status of 2 or greater fails the gate, and an unset exit variable defaults to 2 (`${EXIT:-2}`) so a missing value also fails.
- A missing or empty SARIF file makes the gate step error out, which is a failure, not a pass.
- The gate fails if the analyzer reports zero analyzed files.
- Files the extractor could not process are surfaced as a non-blocking `::warning::` listing each affected path, so a target contributing zero findings because it failed to compile is never mistaken for a clean target.
- Results are uploaded as an artifact with `if: always()`, `if-no-files-found: warn`, 30-day retention.
- No suppression baseline exists for this gate; the only escape hatch is an inline suppression comment or a full-path exclusion carrying a written reason. A basename-scoped exclusion pattern is not permitted.

#### FR-201: Dependency vulnerability scanning over the committed resolved graph

A maintainer can have every resolved third-party dependency scanned for known vulnerabilities on any change to the dependency graph, weekly, and on demand, with CI failing if the committed resolved graph does not match what resolution produces. Realizes UJ-6.

**Consequences (testable):**
- This FR and FR-208 are the single definition of the project's pinned build inputs; 5.10 FR-193 defers here and does not restate them.
- `Package.resolved` is committed at the workspace path and pins both an exact version and a git revision for every dependency. Every dependency is declared with `.exact(...)` or `.upToNextMinor(...)`; `branch:` and unbounded `.upToNextMajor(...)` are rejected for any cryptography- or Bluetooth-adjacent package.
- A `Resolution Drift` step inside `iOS Gate` resolves packages from the committed manifests and fails on any diff to `Package.resolved`; every CI lane builds with automatic package resolution disabled and resolved-file-only enforcement, so a stale lockfile is a hard failure rather than a silent re-resolve.
- OSV-Scanner v2.3.3 runs `--recursive --no-ignore --config=osv-scanner.toml .` over the committed resolved graph; any known vulnerability fails the gate, with no severity floor.
- The `deps` paths filter matches `Package.swift`, `Package.resolved`, `**/Podfile.lock`, `*.xcodeproj/project.pbxproj`, `osv-scanner.toml`, and the dependency-scan workflow file itself.
- The scan additionally runs on `schedule: cron '0 6 * * 1'` (Monday 06:00 UTC) and on `workflow_dispatch`; on those events the aggregation gate requires a successful scan and never treats a skip as a pass.
- `osv-scanner.toml` ships with zero active `[[IgnoredVulns]]` entries and records the first-scan triage result and resolved package count in its header.
- Every suppression lives in that single file, carries a written `reason`, and carries an `ignoreUntil` date that forces re-evaluation. Suppressions are reviewed quarterly.
- No gate is ever weakened by lowering a severity threshold; suppression is one finding at a time.
- Documentation states that SwiftPM advisory coverage in OSV and the GitHub Advisory Database is materially thinner than Maven's, that a green gate therefore carries less assurance than the Android equivalent, and that dependency minimalism is the primary control with OSV as the secondary.

#### FR-202: Workflow lint, SHA-pin enforcement and the composite-action secrets guard

A contributor can have every workflow and composite action linted for syntax, expression, context and embedded-shell defects, and blocked on any unpinned action reference or any `secrets` context use inside a composite action. Realizes UJ-6.

**Consequences (testable):**
- `Workflow Lint` runs on `ubuntu-latest` with `timeout-minutes: 5`. Both analysis tools install as version-pinned release tarballs verified with `sha256sum -c -`, not as third-party actions, so the gate has no unpinned dependency of its own.
- Pins: shellcheck 0.10.0, sha256 `6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87`; actionlint 1.7.7, sha256 `023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757`. A tampered or re-cut upstream tarball fails the checksum and hard-fails the gate.
- Guard 1: `actionlint -oneline -shellcheck=<pinned shellcheck>` with no file arguments, auto-discovering `.github/workflows/`.
- Guard 2 (SHA-pin): every `uses:` reference across `.github/workflows/**` and `.github/actions/**` must pin a full 40-character commit SHA containing only `0-9a-f`. Local `./*` and `docker://*` references are skipped; a reference with no `@` fails as "not pinned"; all offenders are listed before the step exits 1.
- Guard 3 (composite-action secrets): any `${{ secrets.* }}` reference inside `.github/actions/**` fails the gate, excluding lines whose first non-space character is `#`. The prescribed alternative is inheriting the value through the calling job's `env:`.
- Guard 3 exists because actionlint parses `action.yml` as a malformed workflow and cannot lint composite action definitions, and because a `secrets` reference inside a composite action resolves to empty at runtime rather than erroring.
- Guards 2 and 3 also cover any reusable workflow shipped for Builders to run in their own fork.

#### FR-203: Workflow security auditing at medium-or-higher, with a fork-reachable-checkout backstop

A maintainer can have workflow security posture audited on every pull request, failing on any medium-or-higher finding that is not individually allowlisted with a written rationale.

**Consequences (testable):**
- `Workflow Security` runs on `ubuntu-latest` with `timeout-minutes: 5`, zizmor 1.5.2 and PyYAML 6.0.2 pinned, Python 3.12.
- Invocation is `zizmor --config zizmor.yml --min-severity=medium .github/workflows/ .github/actions/`, with `GH_TOKEN: ${{ github.token }}` at `contents: read` so online audits such as known-vulnerable-actions can query the advisory database.
- Any non-allowlisted finding at medium severity or above fails the check. Informational findings are logged only.
- The `pull_request` trigger deliberately carries no `paths:` filter, so the Required Check is always created; push triggers may be paths-filtered to `.github/workflows/**`, `.github/actions/**`, `zizmor.yml`.
- An independent backstop step parses every workflow and fails any workflow that combines a fork-reachable trigger (`pull_request_target`) with a checkout whose `with.ref` or `with.repository` contains `github.event.pull_request.head`. Trigger-key parsing handles YAML 1.1 reading a bare `on:` as boolean `true`.
- The backstop exists because zizmor attributes the finding to the trigger itself, so allowlisting a legitimate `pull_request_target` workflow would also mask a genuine pull-request-head checkout.
- The backstop is documented as not airtight: laundering the head ref through a prior step's output, or fetching the head manually in a `run:` block, evades it. It is layered with zizmor and CODEOWNERS review, never the sole control.
- `zizmor.yml` allowlists one audit id per entry with a written rationale; whole-file versus line-scoped scope is justified per entry. Lowering `--min-severity` is never an accepted remedy.

#### FR-204: Entitlements, Plist, signing-material and build-script guard

A contributor can have any change that broadens the app's platform trust boundary blocked deterministically — a widened App Transport Security posture, debug entitlements in release, committed signing material, credentials stored outside the **Keychain**, non-grantable entitlements, and newly introduced build-time code execution. Realizes UJ-3. Upholds SI-9, SI-10.

**Consequences (testable):**
- The guard runs as a deterministic step inside the `Static Analysis Gate` Required Check (FR-197). It is the single definition of the committed-signing-material check and of the Keychain accessibility-class check; 5.10 FR-179 and FR-189 defer here.
- ATS: the guard is a *no-broadening* guard against a recorded baseline, not a statement of what the Info.plist should contain. It fails any pull request that widens the App Transport Security configuration past the baseline the architecture addendum records as empirically verified — a new or widened `NSExceptionDomains` entry, a new exception key, or any change to `NSAllowsArbitraryLoads` or `NSAllowsLocalNetworking` away from that baseline.
- The product requirement the guard backstops is FR-150 and NFR-20: no cleartext to any host that is not literal loopback, private (RFC1918), carrier-NAT (100.64.0.0/10) or link-local, classified in-app from the literal address and never by DNS lookup. That policy is the enforcement mechanism; ATS is a second gate and never the guard of record, because under **fork-and-build** a Builder controls their own Info.plist.
- Whether `NSAllowsLocalNetworking` covers raw private-IP literals rather than only single-label and `.local` names is unverified, and no section of this PRD may state a plist posture as settled fact until that verification lands; it is carried in §15 Open Questions. Until architecture records a verified baseline, the guard's baseline is the Info.plist as committed, and any diff to its ATS keys fails.
- `get-task-allow` being true in any Release configuration fails the gate.
- `UIBackgroundModes` must match exactly the committed declared set; adding a mode fails until the declaration is updated in the same pull request.
- Every required usage-description string must be present and non-placeholder, including `NSBluetoothAlwaysUsageDescription`.
- Non-grantable entitlements fail the gate: `com.apple.developer.usernotifications.critical-alerts` must never appear in a committed `.entitlements` file, because Apple grants it per Team ID and under **fork-and-build** no Builder's build could sign with it. Runtime detection and upgrade of the interruption level is the app's concern, not the entitlements file's.
- Signing material: any committed `.p12`, `.cer`, `.mobileprovision`, `AuthKey_*.p8`, or a `DEVELOPMENT_TEAM` identifier in an `.xcconfig` or `ExportOptions.plist`, fails the gate.
- Credential location: any credential or pairing secret stored outside the Keychain fails the gate, as does any Keychain item for **Pump** or auth material declared with an accessibility class other than `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — a synchronizing class would push **Pump** credentials into iCloud Keychain, and `kSecAttrAccessibleWhenUnlocked` would break overnight reconnection while locked.
- Data protection: the local database must be configured `CompleteUntilFirstUserAuthentication` (or `CompleteUnlessOpen`), never `NSFileProtectionComplete`, which would fail background writes while the device is locked. A unit test asserts the file protection attribute.
- Build-time code execution: any `PBXShellScriptBuildPhase` in `project.pbxproj`, any `.plugin(` or `binaryTarget(` in `Package.swift`, fails unless present in a committed, CODEOWNERS-owned allowlist. Any accepted `binaryTarget` must be `checksum:`-pinned.
- Remote `binaryTarget` dependencies are forbidden by default; documentation records that a checksummed binary zip has no resolvable package identity and is therefore invisible to dependency scanning — an accepted residual gap stated plainly rather than left implicit.

#### FR-205: Driver protocol public-interface snapshot gate

A reviewer can rely on CI failing any change to the **Driver** protocol module's public interface that is not accompanied by a reviewed snapshot update, making the read-only posture mechanical rather than a review rule. Realizes UJ-6. Upholds SI-1.

**Consequences (testable):**
- The public API surface of the Driver protocol module is snapshotted into a committed file (via `swift-api-digester` or an equivalent interface dump).
- The guard runs in `Build & Test` and reaches merge gating through the `iOS Gate` Required Check (FR-197). It regenerates the snapshot and fails on any diff, naming both the guard and the snapshot file in the failure message.
- Updating the snapshot requires project-lead review (FR-212).
- Adding any therapeutic write primitive — bolus, basal, pump-setting, or any device command — to any **Capability** protocol produces a snapshot diff and therefore a failing check, whether or not it is behind a flag.
- The gate carries no permitted-write carve-out. Because no member of the closed **Capability** set writes to a device (FR-30), *any* newly added write-shaped member is a failure and the gate never has to distinguish a permitted write from a forbidden one — which is exactly what makes SI-1 mechanically checkable.
- The gate also fails if the Driver protocol module acquires an app-layer import.
- A **Driver** absent from the **Driver Catalog** fails the `iOS Gate` Required Check (FR-21) independently of this gate.

#### FR-206: Per-Driver protocol tests over recorded frames

A **Driver** author can have their protocol implementation exercised in CI against recorded real-**Pump** byte traces, with no Bluetooth radio and no **Pump**. Realizes UJ-4, UJ-6. Upholds SI-2, SI-7, SI-8.

**Consequences (testable):**
- The tests run in `Build & Test` and reach merge gating through the `iOS Gate` Required Check (FR-197); this FR introduces no gate name of its own.
- Every **Driver** in the **Driver Catalog** ships trace fixtures and tests that exercise, at minimum: frame framing, byte order (little-endian for the Tandem protocol), event-type ID mapping, multi-packet reassembly including the documented idle timeout, and the connection state machine.
- Tests run under plain `swift test` behind a transport seam, so no Core Bluetooth API is reached.
- Timestamp decoding is tested against the **Safety Constant** Tandem epoch offset `1199145600`, including non-UTC time zones in both hemispheres and a DST spring-forward gap.
- A frame that fails to decode must leave the history cursor unadvanced, asserted by test.
- A glucose value outside the **Glucose Validity Bound** in a recorded frame must be rejected and logged, never clamped, and must not terminate the test process.
- Malformed cargo returns `nil` rather than throwing at parser level; no parser path calls `precondition` or `fatalError`.
- A **Driver** introducing a new pairing or authentication flow must add coverage in its own test suite; there is no shared auth-flow harness.

#### FR-207: Buildability and full behavioral exercise against the Simulated Driver

The lead developer, who has no iPhone and no Apple Watch, can build and drive the entire app and **Watch app** end to end against the **Simulated Driver** in the iOS and watchOS Simulators, with no **Pump** and no Bluetooth radio. Realizes UJ-1, UJ-5.

**Consequences (testable):**
- The **Simulated Driver** is a shipped, compile-time-linked module in the **Driver Catalog**, not test-only code, and links against the same shared **Safety Constant** definitions as every real **Driver**.
- CI exercises, against the **Simulated Driver**, the full path from reading ingestion through **Freshness Tier** classification, **Alert Floor** evaluation, **Coverage Claim** derivation and decay, and phone-to-Watch rendering.
- The **Simulated Driver** is subject to every gate in this section; it carries no exclusion from the Safety Constant drift guard.
- Documentation states explicitly which behaviors cannot be exercised this way — anything requiring a Bluetooth radio, background BLE relaunch, notification audibility, or always-on-display legibility — and routes them to the written hardware-validation checklist required below.
- **The hardware-validation checklist exists as a written, committed document.** There is exactly one such checklist in the repository; it is CODEOWNERS-owned (FR-212), versioned with the code, and written so that any Builder holding the hardware can execute it without tacit knowledge. Every property §9.1 Tier 4 enumerates appears on it as a line item, and sections contributing items (5.1, 5.4, 5.7) contribute to this one list and maintain no second list. A pull request that adds a behavior reachable only on hardware adds its checklist item in the same pull request.
- **Its completion is recorded against a Verification Status change.** A **Driver**'s Verification Status may be raised to Verified only when a completed run of that checklist is committed alongside the device table (§8.3), recording validator name, date, Pump model, iPhone and Apple Watch models, iOS and watchOS versions, and the build identifier. An unrecorded or partial run is not evidence and the status does not move; a stale run is visible as an ageing date rather than as silence.
- Checklist completion is a documented release gate and is explicitly **not** a Required Check and not one of the five names in FR-197 — no CI job can execute it, which is precisely why it is written down.

#### FR-208: iOS Gate — build and unit test of phone, Watch and widget extension

A contributor can have the app, the **Watch app** and the widget extension built and unit-tested on every relevant pull request, with warnings and data-race violations treated as errors. Realizes UJ-6.

**Consequences (testable):**
- `Build & Test` builds and unit-tests all three targets plus every **Driver** module; `iOS Gate` aggregates it per FR-198.
- Builds use `-warnings-as-errors` and Swift 6 strict concurrency checking; a data-race-safety violation fails the build.
- Lint runs SwiftLint `--strict` plus `swift-format lint`.
- No signing occurs; builds are unsigned Simulator builds.
- **CI builds a configuration with every Driver's compilation condition enabled.** Because a disabled **Driver** is excluded from the binary by a compilation condition rather than skipped at runtime (5.10 FR-189 owns the build-composition statement; 5.2 owns its user-visible absence from the Driver list), gated code is invisible to the compiler in the shipped configuration. `Build & Test` therefore builds and unit-tests an all-Drivers-enabled configuration in addition to the default one, so every gated **Driver** stays compiled, type-checked, warning-clean under `-warnings-as-errors` and covered by its own tests. A Driver that no longer compiles with its condition enabled fails `iOS Gate` even when the default configuration excludes it.
- The Xcode version is pinned by a committed `.xcode-version` file, selected explicitly with `xcode-select` rather than accepting the runner image default, and asserted at build start to equal the pin; it is tracked as a reviewed dependency alongside the pinned analysis tools, and a bump is a build-toolchain change requiring lead review.
- A build-settings check fails when any target — the app, the **Watch app**, every widget and complication extension, every **Driver** module, the shared safety module — declares a deployment target other than the single floor NFR-1 fixes, or does not take a direct dependency on the shared safety module (NFR-4). The floor is read from the one build setting; no check hardcodes a second copy of it.
- **The accessibility identifier registry check is defined here.** Its static half runs in `Build & Test` and fails when an identifier enumerated in the registry (FR-177 owns the registry's contents and the per-surface requirement; the system-wide parity RULE — a generated registry diffed against the Android source, with no pinned count — is NFR-30's and is referenced here, not defined here) has no occurrence in the source's identifier set, or when the source declares an identifier absent from the registry. The rendered half — the identifier reaching the built UI and appearing at most once on a rendered screen — requires a running screen and therefore runs in `UI Tests (Simulator)` (FR-209), a non-required job; the guarantee that reaches merge gating is the static half. No third document defines this check.
- The `ios` paths filter matches `Sources/**`, `Apps/**`, `Tests/**`, `Package.swift`, `Package.resolved`, `.xcode-version`, `Contract/**`, `*.xcodeproj/**`, `*.xcconfig`, `*.entitlements`, `Info.plist`, `Resources/**`, the workflow file itself, and the bundled attribution texts `README.md`, `LICENSE`, `docs/THIRD_PARTY_LICENSES.md`, `docs/licenses/**`.
- Documentation- and governance-only pull requests skip the build and pass through the aggregation gate; the gates those pull requests do need — the License Header Gate and the documentation publication gates — run unconditionally inside `Static Analysis Gate` (FR-197).
- SwiftLint carries project-specific custom rules that no generic pack contains: no bare **Glucose Validity Bound** or **Conversion Factor** literal outside the canonical definitions; no `precondition` or `fatalError` on any value originating from Bluetooth, the **Backend**, or persistence; no raw-value enum decoded from a Backend-supplied field; no `.formatted()` or unpinned `NumberFormatter` on a glucose value; no `privacy: .public` interpolation of **Pump** identifiers in logging.

#### FR-209: UI tests on both Simulator destinations with a published result bundle

A contributor can see UI test results for both the iOS and watchOS Simulator destinations on every relevant pull request, published as a downloadable result bundle, without a flaky simulator being able to wedge unrelated pull requests.

**Consequences (testable):**
- `UI Tests (Simulator)` runs XCUITest against an iOS Simulator destination and a watchOS Simulator destination.
- `-resultBundlePath` output is uploaded as an artifact with `if: ${{ !cancelled() }}`, `if-no-files-found: ignore`, 14-day retention.
- The job is gated by the same paths filter as `Build & Test` and declares an explicit `timeout-minutes`.
- The job is deliberately **not** a Required Check and is **not** in `needs:` of `iOS Gate` while it stabilizes; promotion to required is a branch-protection change made once it proves stable. Every other section citing an assertion that runs here must name it as a non-required job (FR-197).
- The rendered half of the accessibility identifier check (FR-208) runs here — identifier present on the rendered screen, and at most one occurrence per screen — and is therefore non-required; the registry's merge-blocking guarantee is FR-208's static half.
- No automatic retry is configured. A red result is re-run as a single job, never disabled.
- Documentation records the coverage delta honestly: database migration and UI behavior port from Android's emulator lane, but nothing Bluetooth-related runs here.

#### FR-210: Platform-independent code testable without Xcode

A contributor can run the **Driver**, domain, unit-conversion and contract-guard tests with plain `swift test` on a Mac in seconds, without Xcode, a Simulator, an App Store Connect account, or a network connection. Realizes UJ-6. Upholds SI-4.

**Consequences (testable):**
- Driver, domain, unit-conversion and **Safety Constant** modules are platform-independent SwiftPM targets with no UIKit, SwiftUI or app-layer imports; acquiring one is a build failure, which is the executable form of Android's review-only "no app imports" rule.
- The **Contract Pin** guards and the Safety Constant drift guard run as a host-macOS test target with no Simulator destination, inside `Build & Test`, and reach merge gating through the `iOS Gate` Required Check (FR-197).
- Repository-root resolution is anchored on `#filePath` walking up to the directory containing `Package.swift`; the guards never depend on the runner's working directory. If the anchor file moves, the failure message instructs the developer to update both the guard and the safety-constants source-of-truth document.
- The **Contract Pin** is parsed once per test process into a cached root rather than re-parsed per call.

#### FR-211: License Header Gate and dependency license allowlist

A contributor can have every shipped source file checked for the correct SPDX header, every ported third-party file checked for its upstream identifier, every dependency checked against a license allowlist, and every bundled attribution text checked for drift.

**Consequences (testable):**
- **The SPDX header policy — the identifier string, the copyright holder, the marker and placement rules, the in-scope and never-stamp lists, the `Package.swift` line-ordering rule, the copied-or-ported versus studied test, and the EC-JPAKE Apache-2.0 exception — is defined once in FR-231.** This FR defines only the gate that enforces it and restates none of it; where the gate and the policy appear to disagree, FR-231 is authoritative and the gate is the defect.
- The License Header Gate runs as a step inside the `Static Analysis Gate` Required Check (FR-197), unconditionally on every pull request, so a documentation- or workflow-only change is still stamped-checked. It is judged by command *output* rather than exit status (a `grep -L`/`-l` that matches nothing exits non-zero, which is the passing case).
- Seven checks, each failing the gate independently and each naming the offending paths: (1) no in-scope Swift file lacks the project identifier, with the excluded upstream tree filtered out; (2) no listed non-Swift in-scope file lacks it; (3) no excluded or ported tree contains it; (4) the EC-JPAKE implementation positively contains the upstream identifier and notice FR-231 fixes; (5) `LICENSE` is unmodified by the pull request; (6) the repository license API reports exactly one license, GPL-3.0; (7) the `Package.swift` line-ordering rule of FR-231.
- The gate reads its in-scope globs and its never-stamp list from the single lists FR-231 defines rather than from a copy held in the workflow, so the two cannot drift; a pull request that edits one and not the other fails.
- EC-JPAKE lives in its own SPM target so the project-identifier sweep never touches it and the license boundary is structural rather than a per-file exception.
- **The dependency license allowlist itself is defined in FR-229.** This FR requires only that its enforcement is mechanical: the allowlist check runs in `Build & Test` and reaches merge gating through the `iOS Gate` Required Check (FR-197), fails closed, and names the offending package identity. It defines no allowlist contents, no exception mechanism and no arbitration rule.
- A `LicenseResourcesTest` fails if any bundled attribution text is missing, empty, or drifted from its source document; edits to those documents re-run the build gate through the `ios` paths filter.

#### FR-212: CODEOWNERS tags trust-boundary files for review request

The project lead and the maintainer team are auto-requested for review on every file that carries arbitrary-code execution, secret access, signing configuration, or a safety invariant — **as a tagging mechanism, not a merge gate.** Realizes UJ-6.

**Deliberate policy, confirmed by the project lead (2026-08-10):** `develop` requires **0 reviews and no code-owner review**, so maintainers self-merge their own pull requests. This is intentional — it lets other maintainers build freely. CODEOWNERS exists to put the right eyes on the right diff, not to block. The five Required Checks (FR-197) are the merge gate; ownership is the review-request layer above them.

**Consequences (testable):**
- This FR is the single definition of the CODEOWNERS roster; 5.10 FR-196 defers here and does not carry a second list.
- The live roster (`.github/CODEOWNERS`, in the repository as of `f1190fe`) is: default `*` → `@lumose-health/web` and `@jlengelbrecht`; governance and project-policy files (`CODEOWNERS`, `GOVERNANCE.md`, `CONTRIBUTING.md`, `LICENSE`, `CODE_OF_CONDUCT.md`, `SECURITY.md`) → lead only; `/.github/workflows/` → lead only.
- **iOS additions to the roster** as those trees appear: `/.github/actions/`, `zizmor.yml`, the workflow-security allowlist, the dependency license allowlist (FR-229), `Package.swift`, the Xcode project file, the Safety Constant guard, and the **parent** Driver tree `/Sources/Drivers/`.
- **The Driver entry is the parent tree `/Sources/Drivers/`, never a per-Driver list.** A roster naming only the Drivers shipped today would leave a newly contributed Driver tree unowned from its first commit.
- Rules are written later-wins and explicit, so a more specific entry cannot be shadowed by an earlier broad one.
- The rationale is recorded per entry: workflow files run with secret access; the workflow-security allowlist can silently widen what the audit ignores; `Package.swift` and the Xcode project file can introduce arbitrary build-time execution.
- **No requirement here asserts that review blocks merge.** A story or gate that configures branch protection to require code-owner approval on `develop` contradicts this FR and the project's stated policy. Promotion to `main` is separately restricted by the org-level main update lock.

#### FR-213: Local reproduction of every gate from one committed script

Any developer can reproduce every CI gate on their own machine by running one committed script, which CI itself invokes so the two cannot diverge. Realizes UJ-6.

**Consequences (testable):**
- A single committed script (`scripts/ci-local.sh`) is the only definition of each gate's invocation; CI calls the script rather than duplicating the commands inline.
- The script covers: static analysis with the pinned query pack, Semgrep `p/secrets` and gitleaks; the dependency scan with the exact CI flags including `--no-ignore`; workflow lint including the SHA-pin and composite-action secrets guards; workflow security (`zizmor --config zizmor.yml --min-severity=medium .github/workflows/ .github/actions/`); resolution drift; the **Contract Pin** guards; the Safety Constant drift guard; the License Header Gate; the documentation publication and in-repo internal-link gates (FR-219); and the Entitlements/Plist/signing/build-script guard. 
- The script documents which gates cannot be reproduced on a machine without Xcode, and exits with a named message rather than a partial pass on such a machine.
- No documented local command scans less than CI does; the Android repository's three divergences (SAST repro omitting a scan root, dependency repro omitting `--no-ignore`, no documented workflow-security repro) are structurally impossible here because there is only one definition.

#### FR-214: Contract Pin guards — version agreement, endpoint presence, field presence

A maintainer can refresh the **Contract Pin** in one pull request and have CI fail loudly if the version, the endpoint surface, or any safety-critical consumed field has drifted. Upholds SI-11, SI-12.

**Consequences (testable):**
- The guards run in `Build & Test` and reach merge gating through the `iOS Gate` Required Check (FR-197); `Contract/**` is in the `ios` paths filter (FR-208) so a pin refresh cannot skip them.
- `Contract/openapi.json` is a byte-for-byte vendored copy of the Backend's spec (748,299 bytes today; `openapi: "3.1.0"`; 164 paths; 274 component schemas; no `servers` block and no top-level `security` block, so no host or auth scheme can be derived from it). It is never hand-edited; refresh means copying the whole file.
- `Contract/CONTRACT_VERSION` is a 2-byte file containing `1` and a newline. CI fails if its trimmed contents do not string-equal `info.x-contract-version` in the pin, which is a JSON *string*, with the message telling the developer to refresh the pin and its version together.
- The networking layer exposes its complete endpoint list to the test as a `CaseIterable` table of (method, path template); no `URLRequest` is constructed outside the routing layer, enforced by lint.
- CI fails if any endpoint or HTTP method the app calls is absent from the pin, naming `Contract/openapi.json` in the failure. Path normalization replaces `\{[^}]+\}` with `{}` so a client `{deviceToken}` matches a spec `{device_token}`. All 34 covered operations must resolve.
- CI fails if the pin stops declaring a field the app consumes on a safety-critical response: `GET /api/settings/safety-limits` → `min_glucose_mgdl`, `max_glucose_mgdl`; `GET /api/settings/alert-thresholds` → `urgent_low`, `low_warning`, `high_warning`, `urgent_high`; `POST /api/auth/mobile/login` → `access_token`, `refresh_token`, `expires_in`, `user`; and the Nightscout data array items `pump_events[units, event_type]` and `glucose_readings[value]`.
- Schema resolution follows a top-level `$ref` into `components.schemas` and additionally resolves one level of `allOf`/`oneOf`/`anyOf`; a missing spec path produces a readable test failure rather than an exception.
- The nullable-consumed-field rule is a standing, enforced obligation: any newly consumed optional field whose absence would silently degrade a safety surface must be added to the field-presence list in the same pull request rather than left to round-trip tests. `pump_events[].units` is the canonical case — it is optional, the persistence mapper drops any event with a nil value, and a silent Backend rename would delete every Nightscout **Bolus** and **Basal** row and understate **IOB** with no parse error.
- Documented blind spots are carried over unchanged and stated in the contract README: this is not a structural diff, and it does not catch removal of an optional or defaulted consumed field, type changes on unexercised surfaces, path-parameter renames, request-body drift, or enum-member and nullability changes.

#### FR-215: One shared decoder configuration and tolerant-reader guards in both directions

A maintainer can rely on the app decoding every **Backend** response through exactly one decoder configuration that the contract tests also exercise, tolerating additive drift in both directions while failing loudly on a missing consumed field. Upholds SI-12.

**Consequences (testable):**
- These guards run in `Build & Test` and reach merge gating through the `iOS Gate` Required Check (FR-197).
- Exactly one shared decoder object is used by both the production networking layer and the contract tests, so the Android hazard — hand-copying the network module's decoder configuration into the test and letting it drift — is impossible by construction.
- Dates decode through a custom strategy accepting ISO-8601 with and without fractional seconds, throwing `DecodingError.dataCorrupted` on failure rather than escaping as a foreign exception type.
- Field names use explicit coding keys per field rather than automatic snake-case conversion, mirroring the Android explicit-name posture.
- Newer-Backend tolerance: unknown extra fields, including unknown nested objects, decode successfully.
- Older-Backend tolerance: any field the app treats as optional or defaulted decodes successfully when omitted. Because Swift's synthesized `Codable` throws `.keyNotFound` for a non-optional property even when it has a default value, every such field is handled explicitly, and a test enumerates every field carrying a default and asserts that omitting its key still decodes.
- CI flags any non-optional `Codable` property declared with a default value.
- Loud failure: a renamed consumed key, a missing nested required field, and a wrong scalar type each fail with the expected `DecodingError` case (`.keyNotFound`, `.keyNotFound`, `.typeMismatch`). A JSON string is never coerced into a numeric field.
- No Backend-supplied enumerated value is modeled as a strict raw-value enum; any unrecognised member decodes to a well-defined unknown case rather than failing the whole response. CI fails any raw-value enum decoded directly from a Backend field.
- Golden round-trip fixtures are retained: health `{"status":"ok"}`; login with `expires_in` 3600; alert thresholds 55 / 70 / 180 / 250 with `iob_warning` absent decoding to nil; safety limits 20 / 500 / 3000 / 25000.

#### FR-216: Contract-version signalling and older-Backend behavior

A Builder running an app newer than their self-hosted **Backend** can be told so once, clearly, and keep monitoring. Upholds SI-11.

**Consequences (testable):**
- The app reads a Backend contract-version signal where one is offered, parses it as a monotonically increasing integer starting at 1, and compares numerically — never as semver, never as an opaque string.
- A missing or unparseable signal is treated as *absent*, routed to the older-or-unknown branch, never silently as compatible.
- Three states on first contact: signal present and the app's required version is at most the Backend's → proceed normally; signal present and the Backend is older → proceed on all read and monitoring paths with a one-time dismissible warning; signal absent or unparseable → the same warning branch.
- A fourth state exists for **Backend-optional mode**: with no Backend configured, no warning is shown at all.
- The app never hard-refuses to run because of an unknown Backend; individual failing calls are handled per call.
- The scope limit is architecturally guaranteed rather than policy: because no therapeutic write exists anywhere, the clause requiring a safety-critical write to be refused under unknown compatibility is unreachable by construction.
- The app shows, on a screen reachable with no Backend connection, the upstream commit it was built from, the CONTRACT_VERSION it was validated against, and which Backend it is paired with.
- Documentation states that under **fork-and-build** the newer-app-to-older-Backend direction is the *normal* case and is handled defensively rather than proven compatible.

#### FR-217: Safety Constant drift guard — exactly one definition, and no reintroduced literal

A reviewer can rely on there being exactly one definition of each **Safety Constant** in the codebase, and on CI failing any pull request that reintroduces a hardcoded copy. Realizes UJ-1, UJ-2. Upholds SI-2, SI-3, SI-4.

**Consequences (testable):**
- The guard runs in `Build & Test` and reaches merge gating through the `iOS Gate` Required Check (FR-197); its SwiftLint half runs in the same job (FR-208).
- Exactly one definition of the **Conversion Factor** `18.0156`, exactly one definition of the **Glucose Validity Bound** `20...500` (inclusive at both ends), and exactly one definition of the Tandem epoch offset `1199145600`, all in a shared platform-independent module that the app, the **Watch app**, every widget and complication extension, and every **Driver** link.
- Layer 1 — direct reads: the guard asserts the Conversion Factor equals `18.0156` with zero tolerance and that every importable bound constant equals 20 and 500.
- Layer 2 — behavioral boundaries: each domain type that validates glucose is exercised at min, max, min−1 and max+1. Construction with an out-of-range value throws (or returns nil on parser paths); it never traps. `precondition` and `fatalError` are banned on any value originating from Bluetooth, the Backend, or persistence, because a trap inside a Core Bluetooth callback during a background relaunch kills the process invisibly and repeated background crashes get the app deprioritised for future relaunch.
- Layer 3 — inverse scan: CI fails if a bare `20`, `500`, `18.0156` or `1199145600` appears in a glucose or **Pump**-time context anywhere outside the canonical definitions. The scan operates over parsed Swift tokens in code position, so nested block comments and literals inside strings cannot confuse it, and underscore grouping is normalized so `1_199_145_600` and `1199145600` are the same token.
- Boundary semantics are preserved so widening cannot slip past: a following digit, `.`, `_`, `e` or `E` must not match, so `500` → `5000` and `18.0156` → `18.01565` stop matching and fail.
- The remaining enumerated site is effectively the Tandem epoch offset alone; the collapse from Android's 19 sites is documented in the safety-constants source-of-truth document so a reader is not confused by the count difference.
- Display-only re-expressions that never validate or gate data — chart axis clamps, unit-label bounds math — remain excluded, with an explicit revisit trigger: if any ever feeds a validation or alerting path, it becomes a scan site.
- The **Simulated Driver** carries no exclusion; it references the shared constants like every other **Driver**.
- The failure message names both the guard and the safety-constants document, and any legitimate change must update both in the same pull request and land in both repositories in the same coordinated release.

#### FR-218: AI-attribution and sign-off enforcement

A contributor can have AI-tool attribution caught before it becomes a permanent part of the repository history, with a local hook as the first line and CI as the backstop. Realizes UJ-6.

**Consequences (testable):**
- Policy: using AI tools to write code is fine; leaving AI attribution in the repository is not.
- A committed `commit-msg` hook holds both commit-message policies in one file (git runs only one such hook). It strips `Co-Authored-By:` lines matching the AI-tool list, strips `Authored-By:`, `Generated-By:` and `AI-Generated-By:` lines, strips any `[bot]` or `noreply@` co-author, collapses trailing blank lines, warns non-blocking on a missing `^Signed-off-by: .+ <.+@.+>$` trailer, and always exits 0. Installation is opt-in (`git config core.hooksPath .githooks`).
- The `Attribution Check` workflow runs on `pull_request_target` for `[main, develop]`, types `[opened, synchronize, reopened, edited]`, with workflow permissions `contents: read` and job-level `pull-requests: write`. It is explicitly a non-required job (FR-197) and can never be one of the five, because it needs write access in base-repository context, which FR-199 forbids the five from requiring; its enforcement is the auto-close below, not a merge block.
- Hardening: the checkout specifies no `ref` (base tree, `persist-credentials: false`, `fetch-depth: 0`); pull-request commits are fetched into a remote-only ref with `--no-tags` and no depth cap; only text inspection runs. No dependency install and no execution of pull-request code — which matters more here than on Android, where a malicious pull request could otherwise land a `Package.swift` build-tool plugin that executes at resolve time.
- Layer 1 (commit trailers): a `Co-Authored-By:` naming a `[bot]` not in the allowlist is CRITICAL; one naming an AI tool is HIGH; any `Authored-By:`, `Generated-By:` or `AI-Generated-By:` is HIGH.
- Layer 2 (code comments): added lines only (`^+`, not `^+++`) across `*.swift *.sh *.rb *.yml *.py`, matching attribution phrasing against the AI-tool list, is MEDIUM; the first five are shown in the log.
- Layer 3 (pull-request description): AI-branding phrases are HIGH, after stripping the CodeRabbit auto-generated footer only when it is a properly bracketed trailing block (open marker found, close marker found after it, nothing but whitespace after the close), so a pasted marker cannot bypass the scan.
- Precedence is CRITICAL > HIGH > MEDIUM > NONE; the step exits 1 for anything but NONE.
- The bot allowlist regex is anchored to the start of the co-author *name* so a crafted trailer cannot substring-match a legitimate entry, and is kept in sync with the CONTRIBUTING bot whitelist.
- A bare `noreply@` is deliberately not CRITICAL, so a human co-author's GitHub noreply address does not auto-close their pull request.
- Reporting upserts a sticky comment keyed on an HTML marker, paginating existing comments so a pull request with more than 100 comments does not get duplicates, and runs `if: always() && severity != ''` so an early crash never posts a misleading pass.
- CRITICAL auto-closes the pull request, except when the head branch is `develop` in the same repository, and instructs the contributor to branch fresh from `develop`, cherry-pick without the trailers, and open a new pull request — because a co-author is a permanent participant.
- The pull-request body is passed through `env:` and finding text is sanitized (backslash, pipe, backtick, CR, LF stripped) before embedding in the comment table.
- A Developer Certificate of Origin check enforces the `Signed-off-by` trailer on every commit; the local hook's warning is the non-blocking early signal, not the enforcement point. [ASSUMPTION: the Android repository's lead-owned `.github/dco.yml` indicates the DCO app is the enforcement mechanism; sign-off is warned about but not blocked by the hook itself.]

**Out of Scope:**
- The fork's build-and-sign pipeline, its secrets preflight, and its signing smoke (5.10).
- The build-time composition of what ships — which **Driver** is compiled into the binary and which build setting removes it (5.10 FR-189) — and its user-visible consequence in the Driver list (5.2). This section owns only the CI requirement that an all-Drivers-enabled configuration is built and tested (FR-208).
- The SPDX header policy (5.12 FR-231) and the dependency license allowlist and its exception rules (5.12 FR-229). This section defines only the gates that enforce them (FR-211).
- The content of SECURITY.md, CONTRIBUTING.md, the licensing narrative, and the third-party attribution document (5.12).
- Which Info.plist ATS configuration is correct. The in-app cleartext policy is FR-150 and NFR-20; the plist baseline is an architecture decision pending empirical verification, and this section guards only against broadening past it (FR-204).
- Runtime app behavior of any kind.

---

**Feature-specific NFRs:**

- Required Checks must not require macOS runners where they do not need Xcode: `Workflow Lint` and `Workflow Security` stay on `ubuntu-latest`, and platform-independent modules run under `swift test`, so most feedback does not cost macOS minutes. Text-only checks that must run unconditionally — the License Header Gate and the documentation publication gates — ride as steps inside `Static Analysis Gate`, which is macOS-bound for CodeQL regardless, rather than justifying a second macOS job or a sixth check name.
- Automated dependency updates must cover GitHub Actions pins, Swift package versions, the pinned analysis-tool versions (actionlint, shellcheck, zizmor, OSV-Scanner, the CodeQL query pack) and the pinned Xcode version. The Android repository's pip/go/tarball tool pins sit under no manager and are documented as silently rotting; that gap is closed here with custom-manager coverage.
- All GitHub Actions updates, all majors, and every cryptography-, cipher- or Keychain-adjacent package update route to manual project-lead review with no auto-merge, because a bot-authored bump that lands upstream propagates to every Builder's credentialed build and receives no automated safety review (CodeRabbit skips bot-authored pull requests).
- `Package.resolved` regeneration on dependency-update pull requests requires a job with a Swift toolchain; the update bot's container has none.

**Notes:**

*For the Parity Ledger (capabilities Android has that iOS cannot match here):*
- **SAST depth.** Semgrep `p/kotlin` + `p/java` has no Swift equivalent of comparable breadth from any vendor. CodeQL `swift` + `security-extended`, Semgrep `p/secrets`, gitleaks and project-specific SwiftLint rules are the honest replacement; a green `Static Analysis Gate` carries measurably less assurance than the Android gate of the same shape.
- **Manifest and network-security linting.** Android Lint is named in the Android security matrix as the verifier for HTTPS enforcement and as the compensating control for the declined MobSF decision. Apple ships nothing comparable. The Entitlements and Plist Guard covers the specific posture class deterministically but is narrower.
- **Artifact-level scanning.** Upstream CI cannot produce a signed device build under **fork-and-build**, so the iOS analogue of APK-artifact SAST is unreachable upstream even in principle. The accepted residual gap — secrets or material present only in the built artifact — persists and widens slightly.
- **Dependency advisory coverage.** SwiftPM advisories in OSV and the GitHub Advisory Database are materially sparser than Maven's, and remote `binaryTarget` dependencies have no resolvable package identity at all, so they cannot be CVE-scanned.
- **Simulator-level BLE smoke.** Core Bluetooth does not exist in the iOS Simulator; `CBCentralManager` never reaches `poweredOn`. Android's emulator at least presented a (non-functional) Bluetooth stack. Neither CI tested BLE against hardware, so release-gate parity is preserved; what is lost is Simulator-level smoke coverage, replaced by trace-replay tests and the **Simulated Driver**.

*[NOTE FOR PM]* CodeRabbit's Android configuration sets `fail_commit_status: false`, which makes even its `mode: error` custom checks — including Medical Safety Review and BLE Protocol Safety — advisory with respect to merge blocking. Inheriting that value by default would import a known-weak control into a fresh repository. This section moves those invariants into the type system, the API-surface snapshot and replay tests, so the review layer is defence in depth; whether to also flip the commit status to failing is a deliberate decision, not a default.

*[NOTE FOR PM]* `UI Tests (Simulator)` is non-required while it stabilizes, matching Android's posture for its emulator lane. Android has carried that "while it beds in" state indefinitely with no promotion criterion. A stated trigger — for example, N consecutive green runs — would prevent the same drift here.

*[NOTE FOR PM]* The dependency license allowlist gate has no Android analogue in the evidence. The allowlist itself is FR-229's (5.12) — its initial contents, its exception mechanism and the GPL-3.0-only interaction with any MIT/Apache-2.0 dependency (notably the EC-JPAKE implementation) are licensing judgments that belong there. This section requires only that the check is mechanical, fails closed, and reaches merge through `iOS Gate`.

*[NOTE FOR PM]* **The ATS half of FR-204 is now a no-broadening guard, deliberately.** It can only be as strong as the baseline architecture records, and until that verification lands the baseline is "the Info.plist as committed" — which blocks drift but proves nothing about whether the committed shape is correct. The open question (whether `NSAllowsLocalNetworking` covers raw private-IP literals) must be answered on a device before the first tagged release, or the guard is protecting an unverified artifact. The product-level guarantee does not depend on it: FR-150's in-app classifier is the enforcement mechanism.

*[NOTE FOR PM]* **The all-Drivers-enabled CI configuration (FR-208) is what makes the compile-time kill switch safe.** Compile-time exclusion is a stronger kill switch than Android's runtime flag, but it also means excluded code stops being compiled — which is how gated code rots and how a disabled **Driver** becomes unshippable without anyone noticing. The second configuration doubles part of the build cost, and that cost is the price of the stronger switch, not an optimization target.


### 5.12 Documentation, Licensing and Policy Surface

**Description:**

Under fork-and-build the documentation stops being support material and becomes the delivery mechanism. There is no binary to download; a user who cannot follow the install runbook has no product at all. Marcus, who has never opened App Store Connect, gets from a fresh fork to a working app on his own iPhone using one published page (UJ-3). That page is the highest-consequence prose in the repository after the medical disclaimer.

Two more pages are load-bearing in the same way. The Parity Ledger names the pairing-troubleshooting page and the iOS status-icons page as the user-disclosure surface for five forced losses — PL-1, PL-2, PL-8, PL-10 and PL-52 — and §7's own rule is that a forced loss with no disclosure surface is a defect. Their existence and their contents are therefore a requirement (FR-237), not an editorial choice, and they are gated exactly like every other page.

The docs tree keeps one `_meta.json` per section directory, schema `{"title": string, "pages": [string]}`, entries as basenames without extension resolving to `.md` or `.mdx`, and the `pages` array as the curated rendered nav order rather than an alphabetical listing of the directory. Android enforced none of it: a page could be added and silently never publish, and no link checker existed anywhere. Both gaps close here — a docs pull request fails on missing frontmatter, on a file present on disk but absent from its section's `pages` array, on a `pages` entry with no file behind it, and on an internal link that resolves to nothing when resolved the way the reader will meet it, on the website.

Publication is somebody else's job. Every repository in the org keeps a `docs/` folder of public-facing pages — the platform repo, `android-unofficial`, and `.github` all do — and the `website` repository pulls them in when it builds glycemicgpt.org. This repository's obligation ends at the folder: write the pages, keep the section contract, and the site takes care of the rest. Nothing about how the website ingests, orders or routes those pages is a requirement of this PRD.

`docs/` in this repository is empty today. Every page is authored fresh. Nothing is gathered, migrated, mirrored or duplicated from the platform repository, the org repository or `android-unofficial`; cross-references to platform or org documentation are links to the published site, never copies. Two reasons, both hard: a copy drifts from its source with nothing anywhere to detect the drift, and there is nowhere for a copy to live in any case, because the sync deletes and replaces this namespace on every build. Everything under `docs/` is public-facing documentation specific to the iPhone and Apple Watch apps. Nothing else belongs there.

A related honesty point has to be stated in the repository itself, because the `pages` array invites the wrong reading: **this repository is PUBLIC.** "Not public facing" can only mean "not rendered on the website". Anything committed under `docs/` is readable on GitHub by anyone, forever, whether or not it appears in a `pages` array — and the sync copies the whole of `docs/` into the published namespace regardless, so a `pages` array controls nav, not distribution. Two document classes are deliberately unrendered — the third-party source-lineage document and the port provenance record — and both are still world-readable and written for that audience. Genuinely internal material does not belong in this repository at all.

The license pipeline is the strongest engineering constraint in this section and it must be rebuilt, not swapped. Android's guarantee is that the shipped license screen reads GENERATED assets derived from the resolved release dependency graph of every module that ships a binary, and that five conditions break the build rather than degrading the output. Off-the-shelf Swift tooling generates files but warns where Android fails, which would silently convert five build-breaking guarantees into zero. The generator is therefore in-repo, fail-closed, and covers the app, the Watch app, any widget extension and every Driver target — the Android lesson being that five of six reproduced NOTICE files were reachable only through the watch module.

The disclaimer surface gets stricter, not looser. Android's alert-delivery warning names four dependencies; iOS is materially weaker on every one of them and adds several Android has no concept of. Urgent-low alerts ship on `.timeSensitive` with runtime auto-upgrade to `.critical` if the entitlement is ever present, and Critical Alerts is structurally unobtainable under fork-and-build because Apple grants it per Team ID — so the alarm can be silenced by the ring/silent switch and the app cannot detect that. APNs is deferred for v1, so Backend-generated alerts do not reach a suspended or terminated app. Both are forced parity losses and both must appear in the published warning. No surface anywhere — app copy, README, install page, screenshot — may claim alerts are guaranteed, undismissable, or able to override the silent switch.

The acknowledgments page keeps Android's load-bearing distinction between studied and ported. Tandem is architectural reference only: jwoglom/pumpX2 and jwoglom/controlX2 (MIT, James Woglom) were studied, the Swift Driver is an independent port, no code was imported, and pumpX2 test vectors validate parser correctness only. Medtronic is the exception — a direct port of OpenMinimed work, GPL-3.0, relied on under explicit relicensing permission from palmarci (Pál Marci). That fact constrains any future project-published binary: the project does not own that copyright, so it could not relicense it, and App Store terms conflict with GPL-3.0-only regardless. The fork-and-build model is what keeps this lawful, and it is strictly stronger for GPL compliance than Android's — every Builder provably holds the corresponding source and their own signing identity.

**Functional Requirements:**

#### FR-219: Section directory contract and the page publication gate

A documentation author can add a page to a publishing namespace by satisfying exactly two conditions, and CI fails the pull request when either is unmet or when any internal link is dead. This FR governs the tree's structural contract; FR-220 governs which pages must exist in it.

**Consequences (testable):**
- Each section directory under `docs/` contains exactly one `_meta.json` with the schema `{"title": string, "pages": [string]}`. `pages` entries are basenames without extension and resolve to `.md` or `.mdx`.
- The `pages` array IS the rendered nav order — curated, not alphabetical, and not a filter derived from the directory listing.
- Section ordering inside this repository's `docs/` tree is this repository's to set. Where the tree lands in the site's global navigation is the website repository's concern and is not specified here.
- Condition 1: YAML frontmatter delimited by `---` carrying `title:` and `description:`. A title containing a colon is quoted. `description:` is one sentence and is used as the page subtitle and meta description.
- Condition 2: the page's basename appears in its owning section's `pages` array.
- CI fails a pull request when: a `.md`/`.mdx` file inside a section directory lacks `title:` or `description:`; a file exists on disk but is absent from its section's `pages` array; or a `pages` entry has no file behind it. Android enforced none of these three.
- CI fails a pull request containing an internal link that resolves to nothing. Relative links are used within this repository's `docs/` tree and are checked against it.
- **Every link that leaves this `docs/` tree is written as an absolute URL** — to a published page on glycemicgpt.org for platform or org documentation, or to a `https://github.com/lumose-health/ios-unofficial/blob/main/...` URL for a repository-root file such as `LICENSE` or `MEDICAL-DISCLAIMER.md`. No relative path escapes `docs/`. This is a single in-repo rule that holds however the site chooses to route the tree, and it removes any dependency on website-side link rewriting.
- Extension-tolerant resolution holds: a link to `./status-icons.md` resolves to `status-icons.mdx`.
- Files at the ROOT of `docs/` are outside every section directory and are exempt from both conditions. That is where the two deliberately unrendered documents live (FR-221). The exemption is a location rule, not an access-control mechanism, and carries no claim that those files are absent from the site.
- This FR's four checks — frontmatter, `pages` membership, a file behind every `pages` entry, and link resolution — run as steps inside the Required Check `Static Analysis Gate` (FR-197), which has no `paths:` filter and runs on every pull request, so a documentation-only pull request is still gated and no sixth Required Check is added. Their workflow mechanics belong to 5.11.

**Out of Scope:**
- Everything the `website` repository does: how it discovers this tree, how it renders it, where it sits in the global nav, and how it deploys. Not this PRD's concern.

#### FR-220: The published documentation set for the iPhone and Apple Watch apps

A person who wants to use the iOS or Apple Watch app finds everything they need under `docs/`, written for them, on the website. Realizes UJ-3, UJ-4. Upholds SI-6.

`docs/` in this repository is empty today; every page is authored fresh. It carries public-facing documentation for the iPhone and Apple Watch apps and nothing else. Nothing is gathered, migrated, mirrored or duplicated from the platform repository, the org repository or `android-unofficial` — a copy drifts from its source with nothing anywhere to detect the drift. Cross-references to platform or org documentation are links to their published pages.

**Consequences (testable):**
- The tree carries at minimum these sections, each with the `_meta.json` contract of FR-219:

  | Section | Purpose | Pages required by |
  |---|---|---|
  | *(root)* `index` | What these apps are, what they require, and where to start | this FR |
  | `install/` | Getting a working app onto a phone, end to end | FR-223 |
  | `daily-use/` | Pairing a **Pump**, reading the dashboard, what alerts can and cannot do | this FR |
  | `apple-watch/` | Watch app and complication setup | FR-224 |
  | `troubleshooting/` | Pairing failures, a connected **Pump** sending nothing, alerts not arriving, an expired build | FR-237 |
  | `reference/` | Status icons, supported devices and their **Verification Status** | FR-237, FR-234 |
  | `concepts/` | Acknowledgments and upstream provenance | FR-232 |
  | `dev/` | Contributing, the **Driver** contribution guide, security testing | FR-225, FR-237 |

- The index page states in its first screen: that these apps read a **Pump** and never write to one (SI-1); that a **Backend** is optional and what is lost without one; that the app is built and installed by the user rather than downloaded; and that alert delivery has limits, linking to FR-234's warning. A reader who goes no further still learns those four things.
- `daily-use/` covers, at minimum: pairing a **Pump** and what each connection state means; reading the dashboard, including what a struck-through or dimmed value means and why (**Freshness Tier**); what the **Coverage Claim** says and what each **Not-Watching Reason** means in practice; and setting **Alert Thresholds**, including that they are read-only whenever a **Backend** supplies them.
- Every page is written for a reader on glycemicgpt.org, not for a reader browsing GitHub. Prose does not refer to "this repository", to file paths, or to the reader's clone.
- Pages assume no Android knowledge and do not tell an iOS reader to consult Android documentation for anything.
- Every published number that also exists in code or CI has exactly one authoritative site and the page quotes it rather than restating it — the deployment floor (NFR-1), the 90-day expiry, the **Freshness Tier** boundaries, the **Conversion Factor** and the **Glucose Validity Bound** (SI-4).
- No page claims alerts are guaranteed, undismissable, or able to override the ring/silent switch (FR-235).

**Out of Scope:**
- How the website discovers, renders, orders or deploys this tree. The `website` repository owns all of it.
- Documentation for the platform, the **Backend**, or the Android apps. Those live in their own repositories.

#### FR-221: Public repository — rendered is not the same as private

Every contributor and maintainer treats each file committed under `docs/` as published to the world at commit time, regardless of whether it renders on the website.

**Consequences (testable):**
- The repository's documentation policy states in writing: this repository is PUBLIC; the `pages` array controls rendering and nav order only; a file absent from every `pages` array is still readable on GitHub by anyone.
- No document, comment, or review may describe the `pages` array, missing frontmatter, or a root-level `docs/` location as an access-control mechanism.
- The two deliberately unrendered document classes — the third-party source-lineage document `docs/THIRD_PARTY_LICENSES.md` (generated-from and tested by FR-228 and FR-230, authoritative for FR-231's never-stamp list) and the port provenance record (FR-233) — sit at the root of `docs/`, are frontmatter-less and unlisted, are still world-readable, and are written for a public audience. The acknowledgments page (FR-232) is NOT in this class: it is a rendered website page.
- Named material that must NOT be committed anywhere in this repository, including under `docs/`: any credential or Apple signing material; an unredacted user bug report or log; pre-disclosure detail on an unfixed parsing defect or an embargoed vulnerability; any personal information about a Builder, tester or maintainer. These live in the private advisory channel (FR-226) or outside the repository entirely.
- Log-redaction guidance is reproduced in every troubleshooting page that asks a user to share output: emails, bearer/API tokens, auth headers, account IDs, Pump serials and Bluetooth device identifiers are replaced with `[REDACTED]` or sent directly to a maintainer. Upholds SI-9.

#### FR-222: Docs publication dispatch to the website repository

A push to `main` touching `docs/**` dispatches a `docs-updated` repository event to the website repository, and a maintainer can force a re-dispatch after a failed website build.

**Consequences (testable):**
- Trigger: push to `main` touching `docs/**` or the dispatching workflow itself, plus manual `workflow_dispatch` documented as the way to force a rebuild.
- The workflow declares `permissions: {}` at both top level and job level — no `GITHUB_TOKEN` scopes at all.
- The cross-repository token is minted by `actions/create-github-app-token` pinned to SHA `1b10c78c7865c340bc4f6099eb2f838309f1e8c3`, with `app-id`/`private-key` from `CI_APP_ID`/`CI_APP_PRIVATE_KEY`, `owner: github.repository_owner` (dynamic, so an org rename does not break the App installation lookup, which does not follow rename redirects), and `repositories: website`.
- The dispatch sends `event_type=docs-updated` with `client_payload[source]` and `client_payload[sha]`.
- Semantics are fire-and-forget: a failed website build is not surfaced here, and nothing validates docs content at dispatch time — content validation is FR-219's job, on the pull request.
- The workflow's job ends at the dispatch. What the website does with it — when it re-syncs, what it rebuilds, how it deploys — is the `website` repository's concern.
- Docs merged to `develop` are not published until promotion to `main`.

#### FR-223: Fork-to-working-app install runbook and the 90-day rebuild

A user with no prior Apple developer experience can go from a fresh fork to a working app on their own iPhone using only this page. Realizes UJ-3.

**Consequences (testable):**
- The page opens with a prerequisites gate the user reads before investing effort: Apple Developer Program membership (a paid annual enrollment), an App Store Connect API key, a GitHub account, and iPhone plus Apple Watch hardware meeting the deployment floor.
- The deployment floor is **iOS 17.0 / watchOS 10.0**, fixed by NFR-1. The page renders it from the single build-setting source through the docs generator and hard-codes no figure of its own; the iOS 18 / watchOS 11 figure is the pinned Simulator runtime (NFR-3) and never appears as a user prerequisite.
- The same gate states the CI-minutes cost, because it is the one prerequisite a Builder otherwise discovers only by exhausting it: GitHub-hosted **macOS runner minutes carry roughly a 10x multiplier on private repositories**, and a fork kept private can exhaust the free monthly allowance in a handful of iOS-plus-watchOS builds. The page states the consequence in the same breath as the 90-day expiry rather than in a separate performance note: a Builder with no minutes left cannot re-run the build-and-upload workflow, and an expired build does not launch, does not monitor and does not alert. Exactly two remedies are documented: keep the fork public, or budget paid minutes. This is §7 PL-63's disclosure surface, and it is where PL-63 meets PL-54.
- Steps appear in executable order: fork the repository; create an app record and choose a bundle-ID prefix; add the documented repository secrets (Issuer ID, Key ID, base64-encoded `.p8` contents, Team ID, bundle-ID prefix, app name); run the build-and-upload workflow; accept the TestFlight invite on the iPhone.
- The page states plainly that the project holds no signing key, publishes no binary, and never requests or receives any Builder's Apple credentials; a leaked App Store Connect key compromises only that Builder's own Apple account, and rotation is a one-secret change in their own fork.
- The 90-day TestFlight build expiry is documented in the body of the page, not a footnote, with the exact remedy: re-run the fork's build-and-upload workflow before the expiry date and reinstall from TestFlight. The page states that an expired build does not launch, and therefore does not monitor and does not alert.
- Internal TestFlight distribution is documented as up to 100 internal testers with no Beta App Review; the maintainer validating on their own hardware does so from THEIR OWN fork under THEIR OWN Apple Developer account, never as a tester on a project-held TestFlight.
- After install, the page covers onboarding (Backend URL then sign-in) and then Pump pairing.
- Backend-optional mode is documented as a first-class supported path: a user can reach a fully working app with no Backend configured at all, and the page says so rather than presenting a Backend URL as a prerequisite.
- Three facts that are platform-independent are restated on this freshly authored page — restated, not carried over as text, since nothing here is copied from another repository: the reachable Backend URL forms (`http://<lan-ip>:3000` local, `https://domain` remote); the Tandem one-Bluetooth-connection-at-a-time rule and unpair t:connect first (UJ-4); and the "if the dashboard is still empty after 5 minutes" troubleshooting threshold.
- Content that must NOT be inherited: the `<5%/day` battery figure (an Android measurement of an Android background model), the no-auto-update/stale-version-banner claim (false — TestFlight updates automatically), and any sideload, `adb`, or "allow from this source" instruction.
- A contributor path is documented separately from the user path: build and run from Xcode against a connected iPhone via Devices and Simulators. It is in the developer section, not on the user-facing install page.
- [ASSUMPTION: the page states the builder relationship factually — the user forks, signs and installs their own build — and asserts no legal conclusion about manufacturer status in either direction, pending the counsel review named in Notes.]

#### FR-224: Apple Watch setup page

A user can put glucose on their wrist from this page alone, and the page states honestly what watchOS does not allow. Realizes UJ-1.

**Consequences (testable):**
- The page documents the Watch app install path and states no remedy of its own. See FR-115. It records that the single-bundle path removes the single hardest documented step in the Android product, and it offers no TestFlight download of the Watch app as a separate artifact, because none exists.
- The page states that watchOS has no third-party watch faces and no counterpart to pushing a face from the phone; the user manually adds a GlycemicGPT complication to an Apple-provided face (long-press the face, Edit, tap a complication slot, choose GlycemicGPT), matching the in-app guided setup in FR-118 step for step.
- The complication kinds, the accessory families each supports, and the Smart Stack as a second placement path are quoted from FR-117 and FR-119. The page enumerates no set of its own, so a change to the shipped complication set cannot leave the page stating a set that no longer exists.
- Rendered elements are named: glucose, trend arrow (up/down/flat), IOB, and the reading's age. Every wrist surface is explicitly read-only (FR-115).
- New values arrive on the ~5-minute Glucose Reading cadence, and the page states that complication timeline reloads are system-budgeted so no refresh cadence is guaranteed. Freshness Tier presentation on the wrist — plain, marked stale, then `--` — is quoted from FR-120 for glucose and FR-121 for IOB; the page states no age threshold of its own.
- Three losses are stated rather than implied away: no control of the face surface, no guarantee of placement (the user chooses the face and the slot), and no guaranteed refresh cadence.
- The page states that phone-to-watch delivery is best-effort, so the Watch app can be staler than the app — and that the Watch app renders and decays the phone's Coverage Claim rather than deriving one of its own (FR-126). Upholds SI-6.
- The page states that a wrist alert is scheduled on the Watch itself and that iPhone notification mirroring is only the fallback, because mirroring does not fire while the phone is unlocked and in use. See FR-128 and FR-129; the page restates neither mechanism.

#### FR-225: Contributor documentation, the Driver contribution guide, and the code of conduct

A contributor can reproduce every gate locally, contribute a Driver for an unsupported Pump, and know where to report conduct problems. Realizes UJ-6.

**Consequences (testable):**
- Prerequisites are published, and for reproducing the CI gates locally the guide points at the single committed local-reproduction script rather than listing commands of its own. See FR-213. Branching (`develop` and `main`, all contributor PRs target `develop`, never `main`), branch prefixes (`feat/`, `fix/`, `docs/`, `refactor/`, `ci/`), Conventional Commits and the pre-submit checklist carry over from Android unchanged.
- The DCO requirement is stated: every commit carries a `Signed-off-by: Name <email>` trailer using a real name and reachable email; DCO grants no relicensing rights and there is no CLA; enforcement runs on the repository as a pull-request status check rather than as a local hook, with no exemption tier and a one-remediation-commit allowance.
- The Driver contribution path is: pick an unsupported Pump; open an issue naming device, protocol and data surfaced; open a pull request adding a compile-time-linked Swift Driver target registered in the Driver Catalog; include unit tests, especially parsing and Safety Limits validation.
- The guide publishes the closed Capability set as exactly SIX, matching FR-30 verbatim: glucose source, insulin source, pump status, BGM source, data sync, bolus-category provider. Nothing else is declarable, and the guide states that there is no calibration-target Capability — every member of the set is read-only, which is what lets SI-1 read without a carve-out. A Driver needing to write to a device is a PRD change with its own safety review, not a contribution. Upholds SI-1.
- The guide states the hard rejection rule verbatim: a reading outside the Glucose Validity Bound or Safety Limits must be REJECTED — not returned, not emitted, not persisted — and the rejection logged with the violated limit, without crashing. Upholds SI-2.
- The guide states that pull requests introducing a therapeutic write primitive will not be merged, and that contributions whose intent is to enable a device-control fork are refused. Upholds SI-1.
- Two steps Android had no need for are mandatory: a Driver pull request must name who will validate it on physical hardware and on which device; and any Bluetooth-touching pull request must state whether it was validated on hardware or against the Simulated Driver or Trace-Replay Driver, because Core Bluetooth does not exist in the iOS Simulator.
- Android's runtime-loaded plugin path is DELETED from the guide rather than adapted, with the tradeoff stated: adding a Pump on iOS requires a source change, a merged pull request and a rebuild by each Builder — mitigated by the fact that a Builder wanting an unmerged Driver can already build their own fork with it.
- A pull-request template and issue forms ship in the first commit, including a hardware-validation field. The Android repository instructs contributors to fill a template that does not exist; that defect is not inherited.
- `CODE_OF_CONDUCT.md` is Contributor Covenant v2.1 verbatim, retaining the project-specific Pledge paragraph about being especially patient with people who are stressed, tired, or scared because of their own or a loved one's diabetes, and the four-rung ladder (Correction, Warning, Temporary Ban, Permanent Ban).
- Conduct reports go to `info@glycemicgpt.org`, deliberately distinct from the security address in FR-226. Both addresses appear in the documents that own them and are never swapped.

#### FR-226: Security disclosure policy and the pre-declined report class

A reporter has two private channels and no public issue path, and the policy states in advance which class of report will be declined.

**Consequences (testable):**
- Two private channels, both reaching the project lead: GitHub private vulnerability reporting at `../../security/advisories/new`, and `security@glycemicgpt.org`. The policy says "do not open a public issue" and provides no public reporting path.
- First-response expectation is "within a few days", with escalation via the platform repository's README channels; no other SLA is committed.
- Required report contents: description and potential impact; reproduction steps or proof of concept; the source tag and build number tested; and whether the issue requires physical proximity to a Bluetooth device.
- Scope covers the app, the Watch app, the Swift Drivers, AND the fork's build-and-sign pipeline, which is a supported product surface. Backend, web and sidecar route to the platform repository's policy.
- Supported versions: fixes land on `develop` and ship via the `develop`→`main` promotion; only the latest tagged source revision is supported, since the project publishes no binary to be "on".
- In-scope classes are enumerated, and class 1 is stated as a safety issue rather than a classic security bug: incorrect Bluetooth parsing producing a wrong Glucose Reading, IOB, or dosing-history value is reportable through this channel. Upholds SI-2, SI-7, SI-8.
- Remaining classes: health data escaping the encrypted store or credentials escaping the Keychain (SI-10); Pump serials, auth material or raw device payloads in logs (SI-9); any code path that could introduce a therapeutic write primitive onto a Capability, even unintentionally (SI-1); and standard app issues. iOS-specific classes are added: an over-permissive Keychain accessibility class, health data written outside an adequate file-protection class, App Group container leakage, and anything reachable from a Core Bluetooth state-restoration relaunch.
- The policy PRE-DECLINES, in writing, any report proposing that the absent therapeutic-write capability is a bug to be fixed: monitoring-only is a deliberate safety and legal boundary, not an implementation gap, and such a report is declined as a feature request for a different, unendorsed kind of project. Upholds SI-1.

#### FR-227: In-app license viewer

A user can read the complete licensing of their build inside the app, offline, with text selection, from a Settings entry point. Realizes UJ-3.

**Consequences (testable):**
- Three states: Loading, Loaded, and Unavailable. Unavailable shows "License text could not be read from this build." in the error colour and is documented as a packaging failure, not a user state — it is reachable only by a read failure and is logged.
- Loaded renders, in this exact order: the project license notice; the third-party source-lineage document; one section per redistributed-component license family; one item per bundled license-text paragraph; one item per GPL-3.0 paragraph.
- License texts and the GPL are rendered as PLAIN TEXT, never markdown — numbered clauses parse as list markers and indented lines parse as code blocks.
- Repository-relative links in any displayed document are reduced to their label text, because such a path addresses a file that does not exist on the device. Targets carrying a URI scheme, including `mailto:`, are left intact even when the renderer declines to open them. Only `http` and `https` targets are openable.
- Automatic link detection and data detectors are OFF for these documents, so a filename such as `some-file.md` is not turned into a dead link. Image syntax is stripped so no outbound image fetch can occur.
- The whole document is text-selectable.
- The list is built one row per paragraph so layout measures only on-screen content rather than the ~670 lines of the GPL.
- Scroll position is preserved across rotation and scene restoration; a reader returns to their position rather than the top of a ~35 KB document.
- Documents are read from the app bundle off the main actor. The screen requires no network connectivity and works in Backend-optional mode.
- Content splits at `## ` boundaries with the heading kept in its section and the preamble as section 0.
- This FR is the single definition of the viewer's states, ordering, rendering and restoration behaviour. FR-174 (5.9) cross-references it and owns only where the entry point sits in Settings.

**Out of Scope:**
- The Settings entry point's placement and the App Info card (FR-174, 5.9).

#### FR-228: License assets generated from the resolved dependency graph on every build

The five shipped license assets are regenerated from the resolved dependency graph on every build, so the documents in the repository remain the single source of truth.

**Consequences (testable):**
- Exactly five assets, with these exact names: `project_license_notice.md` (the README `## License` section including its heading, verbatim, up to the next `## `), `third_party_licenses.md` (`docs/THIRD_PARTY_LICENSES.md` whole), `gpl-3.0.txt` (repo-root `LICENSE` whole), `runtime_dependencies.md`, `runtime_dependency_licenses.txt`.
- Generation covers EVERY target that ships in a binary — the app, the Watch app, any widget/complication extension, and every Driver target — not the app alone.
- Nothing is rewritten for display; normalisation belongs to the UI. Each asset stays an exact substring of its source so the drift test in FR-230 is a plain equality check.
- Pre-generated assets committed to the repository are NOT accepted: committing them breaks single-source-of-truth, lets them go stale between dependency bumps, and turns the drift test into a tautology.
- `runtime_dependencies.md` format: `# Redistributed Components`, three fixed preamble paragraphs, `Components: <N>.`, then one `## <heading>` per license family sorted alphabetically, where the heading is the component's FIRST license identifier or the literal `License terms available elsewhere`. Each entry is `- \`identity\` -- <name> -- carries a NOTICE` (name omitted when blank or equal to the identity; the NOTICE suffix only when that component contributed one), then an indented scm URL line, then `Also licensed under: X, Y`, then `Terms: <note>`.
- `runtime_dependency_licenses.txt` format: header `LICENSE TEXTS AND UPSTREAM NOTICES`; per identifier a 64-character `=` separator line, the identifier, another separator, then the bundled text; then a final `UPSTREAM NOTICES` block of `--- identity ---` sections.
- Components are keyed by package identity so multi-target and multi-platform resolution de-duplicates.
- Canonical license texts live one per identifier at `docs/licenses/<identifier>.txt`, and the filename minus extension IS the lookup key. GPL-3.0 is NOT in that directory — the repo-root `LICENSE` is the GPL source and ships as its own asset. Non-SPDX families keep the bundled-by-name convention for packages whose metadata declares no identifier.
- NOTICE harvesting matches a NOTICE file only at the ROOT of each package checkout. A nested NOTICE belongs to a vendored dependency inside that checkout and is that dependency's obligation, not this project's; a recursive search would over-attribute. A declared per-package extra-path allowlist is the only escape hatch and each entry carries a written reason.
- Multiple notices within one package are sorted by path and joined with a blank line; empty or whitespace-only notices are dropped; the notices map is sorted by package identity.
- Classification fallback order is exactly: declared SPDX identifier → unmapped override → external-terms note → build failure. The override is consulted ONLY when nothing was declared; a declared identifier always wins.

#### FR-229: Fail-closed license policy gate with version-pinned exceptions

The build FAILS — never warns — on any unresolved licensing condition, and every exception is pinned to an exact version with a written reason.

**Consequences (testable):**
- The build fails when the resolved component list is EMPTY, with the reason stated: an empty list "would ship empty, which reads as 'this app redistributes nothing'".
- The build fails when a component has no detectable SPDX identifier and no entry in the unmapped or unreproduced maps, naming the offending package identity. It is never papered over with an "undeclared" placeholder.
- The build fails when a license family has no `docs/licenses/<identifier>.txt`, listing every missing family.
- The build fails when a whole-file source document is blank — "refusing to ship a build whose licence screen would show a blank section in its place" — and when `README.md` has no `## License` heading, naming the heading.
- The build fails when a package checkout cannot be read. Resolution is strict, never lenient: a failure breaks the build rather than silently dropping a NOTICE.
- The build fails when a dependency's license is not on the checked-in allowlist. One CODEOWNERS-owned policy file at the repository root, so the app, the Watch app and the Driver targets cannot disagree. This FR is the single definition of the allowlist and of every fail-closed condition above; FR-211 (5.11) owns the gate that runs them and states no policy of its own.
- In CI these failures surface through the `iOS Gate` Required Check (FR-197), which builds every shipping target. No sixth Required Check is added for licensing.
- EPL-1.0 is NOT on the allowlist and must not be added: the FSF considers it incompatible with GPLv3 for a combined distributed work. An EPL-licensed transitive is excluded AT THE DEPENDENCY with a test proving the affected feature still works without it — never allowlisted, never handled by lowering a threshold.
- The project's own license URL (`https://www.gnu.org/licenses/gpl-3.0.txt`) is allowed explicitly, as GPL-3.0-only is the licence this application ships under.
- Every per-package exception is pinned to an exact version and carries a written `because` reason, so a version bump re-raises the judgement rather than inheriting it.
- The per-configuration check covering Debug, Release and every fork's signing configuration replaces Android's per-variant null check, so no build path can ship a blank license screen.
- Off-the-shelf tools that warn where these conditions require failure are rejected: the fail-closed behaviour IS the requirement, not the file generation.

#### FR-230: License asset drift test and license-document build inputs

An automated test proves each shipped asset is byte-for-byte its on-disk source, and editing a license document invalidates a cached green result.

**Consequences (testable):**
- Shipped GPL text equals the repo-root `LICENSE` verbatim, exceeds 30,000 characters, and contains both `GNU GENERAL PUBLIC LICENSE` and `Version 3, 29 June 2007`.
- Shipped third-party document equals `docs/THIRD_PARTY_LICENSES.md` verbatim, exceeds 10,000 characters, and starts with `# Third-Party Licenses`.
- Project notice exceeds 200 characters, starts with `## License`, is a verbatim substring of `README.md`, contains no later `\n## ` (the over-capture guard), and contains both `Copyright (C) 2026 Josh Engelbrecht` and `GPL-3.0-only`.
- Component document starts with `# Redistributed Components` and names a fixed witness set including at least one package reachable only through the Watch app target.
- Every heading in the component document falls inside the declared SPDX heading set or the declared non-SPDX heading set (which includes the literal `License terms available elsewhere`); any heading outside both sets fails the test.
- Section-split count equals the number of `## ` lines plus one.
- The `UPSTREAM NOTICES` block is non-blank, contains `\n--- `, and names a stable witness package, so a silent regression to zero harvested notices is impossible.
- `README.md`, `LICENSE`, `docs/THIRD_PARTY_LICENSES.md` and `docs/licenses/**` are registered as declared inputs to the license test target, so editing one invalidates a cached green result.
- Those same four paths are members of the `ios` paths filter (FR-208), so a change to one of them runs the `iOS Gate` Required Check — it is an app change even though it is a document. Every other `docs/**` change matches no `ios` path and passes through the aggregation gate without a build.

#### FR-231: SPDX headers, never-stamp trees, and the EC-JPAKE notice

Every in-scope source file carries the project's SPDX header, ported upstream trees are excluded and carry their own upstream notice instead, and the objective test for which is which is written down.

**Consequences (testable):**
- The identifier is `GPL-3.0-only` — explicitly not `GPL-3.0-or-later` and not the deprecated bare `GPL-3.0`.
- The copyright holder is the individual: `Copyright (C) 2026 Josh Engelbrecht`. "Lumose Health" and "GlycemicGPT" are org and project names, not legal entities, and must never appear as the holder.
- The canonical two-line block appears verbatim, with `//` for Swift (above the first `import`) and `#` for shell (after the shebang) and YAML (top). An existing descriptive block comment is kept, with the SPDX lines above it.
- In-scope globs are enumerated explicitly, with each `Package.swift` listed individually rather than reached by a recursive glob. Anything unmatched is not stamped, and exclusion beats inclusion where both match.
- Out of scope by design: `Info.plist`, `.entitlements`, `.xcconfig`, asset catalogs, `.xcodeproj`/`.xcworkspace` internals, `Package.resolved`, lockfiles, the pinned OpenAPI document, build output, binaries, and ALL Markdown — prose carries its license via the repo `LICENSE`.
- `LICENSE` is never edited; a diff over any stamping sweep shows no change to it.
- The never-stamp list is normative and its test is objective: a file is EXCLUDED if upstream code was COPIED OR PORTED into it, and IN SCOPE if upstream work was only STUDIED and reimplemented. When the test and the list disagree, treat the file as excluded and fix the list in the same pull request. `docs/THIRD_PARTY_LICENSES.md` is authoritative on conflict.
- The Swift Medtronic Driver target is the excluded tree, stated at directory level deliberately even where some files inside it are original, because file-by-file lines invite misattribution.
- Swift files that merely CITE pumpX2 (protocol, JPAKE, HKDF, HMAC, status parsing) stay IN scope and carry the project header.
- The Android open gap is CLOSED on port, not carried: the Swift EC-JPAKE source is a port of Particle's implementation and ships `// SPDX-License-Identifier: Apache-2.0` and `// Copyright 2022 Particle Industries, Inc.` in-file, because Apache-2.0 requires the notice travel with the file. It is the one file that carries a non-GPL header.
- A pull request that adds an upstream-derived file adds it to the never-stamp list in the same pull request.
- This FR is the single definition of the header policy — the identifier, the holder, the marker and ordering rules, the in-scope and out-of-scope globs, the never-stamp list and its objective test, and the EC-JPAKE exception. FR-211 (5.11) owns the License Header Gate that enforces it, including which Required Check carries the gate, and restates no rule from this list.

#### FR-232: Acknowledgments page — studied versus ported, per upstream project

The published acknowledgments page states, per upstream project, whether its code was studied and reimplemented or copied and ported, names the license and any relicensing permission relied on, and records what that constrains.

**Consequences (testable):**
- Tandem is stated as ARCHITECTURAL REFERENCE ONLY: `jwoglom/pumpX2` (MIT, James Woglom) and `jwoglom/controlX2` (MIT) were studied; the Swift Driver is an independent port; no code was imported; pumpX2 test vectors are used only to validate parser correctness. In-source citations appear in the corresponding Swift protocol, JPAKE, HKDF and status-parsing files.
- Medtronic is stated as the DIRECT PORT and the one place this project departs from its Tandem posture: OpenMinimed work is GPL-3.0 and is relied on under explicit relicensing permission from palmarci (Pál Marci), who is named. The four upstream repositories are mapped to their roles, and the note that firmware-derived SAKE key material ships under GPL-3.0 and introduces no new secret is retained.
- EC-JPAKE lineage names `particle-iot/ecjpake-java`, Apache-2.0, Copyright 2022 Particle Industries, Inc.
- The page records the constraint this creates: because the project does not own the OpenMinimed-derived copyright and it is GPL-3.0-only, the project could not relicense it, and App Store terms conflict with GPL-3.0-only regardless — so any future project-published binary is foreclosed by these facts and not merely by preference. fork-and-build is what keeps this lawful, and it is strictly stronger for GPL compliance because every Builder provably holds the corresponding source and their own signing identity.
- Individual credits carry over: drfubar, Morten Fyhn Amundsen, Stenium, @planiitis. The diabetes open-source movement is credited — Nightscout, OpenAPS/Dana Lewis, Loop/LoopKit/Pete Schwamb, AndroidAPS, xDrip+, Tidepool — alongside the statement that GlycemicGPT does not do closed-loop and never will.
- Any Swift-ecosystem lineage actually consumed is added with the same studied-versus-ported labelling; nothing is credited that was not actually used.
- The page invites correction issues explicitly, retaining "correctness matters more than concision".
- The page is RENDERED: it lives in the `concepts` section, carries frontmatter and appears in its section's `pages` array (FR-219), and reaches the public site through FR-220's registry entry like every other page here. Its basename is chosen for readability and is under no cross-repository constraint. It is not one of FR-221's two unrendered documents, and it is not the third-party source-lineage document `docs/THIRD_PARTY_LICENSES.md`, which is a root-of-`docs/` document generated into a shipped asset by FR-228.

#### FR-233: Repo-internal, unpublished provenance record

A repo-internal record maps every Swift module to its Android origin, so the never-stamp test in FR-231 and the lineage document in FR-232 have an auditable input.

**Consequences (testable):**
- The record states, per Swift module, which `android-unofficial` file and commit SHA it derives from, and whether it was PORTED (copied and translated) or REIMPLEMENTED from protocol documentation only. That distinction is exactly the objective test FR-231 depends on.
- It carries no frontmatter and appears in no `pages` array, so it appears in no website nav — and per FR-221 it is nevertheless world-readable, is copied into the published namespace by the sync like every other file under `docs/`, and is written for that audience. "Unpublished" here means "not a nav entry", never "not distributed".
- Deliberate exclusions and post-merge fixups are recorded.
- A secret scan runs over ALL refs before the first push, as the Android extraction did (233 commits, ~5.9 MB, no leaks found), and its result is recorded here.
- The record replaces `docs/dev/monorepo-port-ledger.md`, which `android-unofficial`'s CONTRIBUTING references and which does not exist; that dangling reference is not inherited.

#### FR-234: Medical disclaimer, the alert-delivery conditions, and the per-device verification table

The published medical disclaimer states that no therapeutic write surface exists, enumerates every iOS-specific condition under which alert delivery can fail, and defers to a README verification table that is iOS-specific and never inherited. Realizes UJ-2, UJ-4. Upholds SI-1, SI-5, SI-6.

**Consequences (testable):**
- The disclaimer states the regulatory position: not cleared, approved or certified by the FDA, EU Notified Bodies (no CE marking under MDR 2017/745), Health Canada, the TGA, or any equivalent; "NOT a medical device"; no person or entity is the "manufacturer" under any framework.
- No Therapeutic Write Surface is stated as architectural: Drivers READ glucose, IOB, Basal, Bolus history and Pump hardware status and issue no therapeutic writes — no bolus dosing, no basal changes, no pump-setting modification — and no Capability exposes an insulin-delivery primitive, not even behind a flag. Upholds SI-1.
- Permitted non-therapeutic device-management operations are enumerated as exactly two: Bluetooth pair and unpair, and connect, reconnect and disconnect — session and lifecycle operations, not therapy. The disclaimer publishes no calibration operation, because no calibration-target Capability exists (FR-30) and no Driver can write to a device at all. The published statement is therefore unconditional: every Capability in the closed six-member set is read-only.
- The alert-delivery warning enumerates every iOS condition and is strictly MORE conservative than Android's four-item list, and may never be weakened: the Bluetooth link to the Pump holding; iOS not having suspended or terminated the app; Core Bluetooth state restoration successfully relaunching it; Background App Refresh enabled; Low Power Mode off; the app not swiped away in the app switcher; the user's Focus, Do Not Disturb, notification-summary and per-app notification settings; the Apple Watch being in range; the iPhone being powered on and not restarted since the app last ran; and the TestFlight build not having expired.
- The warning states the two forced parity losses explicitly: urgent-low alerts ship at `.timeSensitive` interruption level and can therefore be silenced by the ring/silent switch, and the app cannot detect that this has happened; and Critical Alerts is structurally unobtainable under fork-and-build because Apple grants the entitlement per Team ID, with runtime auto-upgrade to `.critical` only if the entitlement is ever present.
- The warning states that Backend-generated alerts do not reach a suspended or terminated app in v1, so caregiver alerting is degraded, and that the on-device Alert Floor is the irreducible safety net that continues to work with no Backend. Upholds SI-5.
- The supplement-not-replacement claim and the instruction to keep the Pump's and CGM's own alerts enabled are stated verbatim and are identified as the actual safety mechanism.
- The untested-device clause is retained: protocol compatibility does not guarantee correct operation, and safety-critical values (IOB, glucose, Basal) must always be verified against the manufacturer's official app.
- The README carries an iOS-specific per-device verification table using the project's Verification Status vocabulary — Verified, Protocol-Implemented, Beta — with a column Android's table lacks: validated on iOS hardware by / on date. A named validator and a date are a precondition for any status better than unverified.
- No device status is inherited from the Android table at any point. An inherited "Verified" would be a false safety claim about software nobody has run, because the iOS Bluetooth stack is a different code path.
- Expected v1 table state: Tandem t:slim X2 — Verified, validated on iOS hardware by DanielDanielson on a stated date, from their own fork under their own Apple Developer account; Tandem Mobi — Protocol-Implemented, unverified on hardware, no validator; Medtronic MiniMed 680G/770G/780G — Beta, read-only, unverified on hardware, no validator.
- The README also carries the pre-Overview IMPORTANT SAFETY WARNING blockquote, the `## Disclaimer` section, and the `## License` section — which remains the ONLY README section packaged into the app, so its no-later-`## `-heading constraint and its exact content (project name and description, `Copyright (C) 2026 Josh Engelbrecht`, GPL-3.0 with SPDX `GPL-3.0-only` and no or-later, pointers to `LICENSE` and the SPDX header policy, inbound = outbound, and the GPL no-warranty paragraph) stay test-enforced by FR-230.
- The stricter-of-the-two conflict rule against the platform disclaimer is retained: where a statement about this app or its device handling appears in both, the STRICTER applies, and nothing in the platform disclaimer relaxes device-level limits.
- Liability is stated in caps and re-grounded in GPL-3.0 Sections 15, 16 and 17, with the jurisdictional note about EU consumer protection, UK consumer rights and Australian consumer law, and the statement that the PRIMARY risk mitigation is the monitoring-only design rather than the disclaimer.
- The disclaimer states that these claims describe the SOURCE at a given tag; a Builder's own build is their own.

**Out of Scope:**
- The in-app onboarding acknowledgement flow that presents these warnings (5.9).
- The Device Verification Matrix as a PRD artifact (S8); this FR governs the published README table.

#### FR-235: Prohibition on guaranteed-alert claims on any surface

No surface produced by this project may claim that alerts are guaranteed, undismissable, or able to override the user's own notification, Focus, mute, or ring/silent settings. Upholds SI-5, SI-6.

**Consequences (testable):**
- The prohibition binds every surface: app copy, notification text, the Watch app, README, install runbook, troubleshooting pages, release notes, and any screenshot or promotional text.
- Banned claim shapes are enumerated so a reviewer can match them: "you will always be woken", "alerts cannot be missed", "works even when your phone is silenced", "guaranteed", "undismissable", "overrides Do Not Disturb", "reliable alarm", and any phrasing implying the app can substitute for the Pump's or CGM's own alarms.
- Permitted phrasing is bounded by what the Coverage Claim can honestly assert: what is being watched, until when, and — when nothing is watching — the specific Not-Watching Reason. Upholds SI-6.
- A review checklist item — explicitly a human review step and NOT a Required Check, because the judgement is editorial — flags any diff that weakens alerting language in the medical disclaimer, the README, the install runbook, or in-app alert copy, so the strengthening is one-directional.
- The alerting-language rules are written down once and referenced by every document that describes alerts, so the app and the docs cannot drift apart.

#### FR-236: Privacy document and the crash-reporting posture under fork-and-build

The published privacy document enumerates every outbound connection by name, states that each is user-chosen, and states the crash-reporting posture in a world where every build is a Builder's build. Upholds SI-9, SI-10.

**Consequences (testable):**
- The document enumerates exactly five outbound connections and states which are optional: (1) the Pump over Bluetooth, direct and local; (2) the user's Backend if configured; (3) the Watch app over the phone-to-watch link, carrying glucose, trend, IOB and alerts only, never credentials; (4) Apple and TestFlight, which see the Builder's own Apple ID and install metadata under the Builder's OWN Apple Developer account; (5) the upstream-release check (FR-188) — a comparison against the upstream repository's latest release tag that downloads nothing, carries and receives no health data, is user-toggleable and is OFF by default.
- Connection 3 is stated as involving no third-party services transport, unlike Wear OS's Data Layer, which routed through Google Play Services — a privacy improvement over Android, recorded as such.
- The document states the Backend-optional network rule exactly as NFR-23 states it, with its one exception named rather than omitted: in Backend-optional mode the app makes NO network request to any host carrying or receiving health data — local Bluetooth monitoring, on-device storage and on-device Alert Floor alerting only — and the single permitted exception is the upstream-release check (FR-188), which is user-toggleable and off by default, so a user who has enabled nothing makes no request at all. Backend-optional mode is described as first-class, not degraded.
- Storage claims: credentials and pairing secrets in the Keychain, device-only, after-first-unlock so overnight reconnection works while locked (SI-10); health data under a file-protection class no weaker than complete-until-first-user-authentication; the Watch app holds only a small rolling render cache in app-private storage, stores no credentials, and makes no network requests.
- The document states there is no telemetry and no analytics, and that no health value, raw device payload or credential appears in any log at or above debug level (SI-9).
- Crash-reporting posture: the document cites the build-composition rule rather than restating it. See FR-189. What the document adds is the reader-facing consequence of fork-and-build: the only way a DSN enters a build is a Builder supplying it to their own fork, and reports then go to that Builder's own account, never to the project's.
- If a Builder enables it, the lockdown is stated: error events only, no performance traces, no profiling, no session or release-health telemetry, no session replay, no screenshots or view-hierarchy capture, no user-interaction tracking, automatic HTTP/navigation/UI/network breadcrumbs dropped wholesale, default PII off, reporting IP replaced with a non-routable placeholder, and a glucose/token/email scrubber over every surviving string field.
- The never-transmit list is reproduced verbatim: glucose or health data, user identifiers, names or contacts, keys, tokens or credentials, device serials or Pump pairing IDs, database contents or query parameters, local variables, HTTP bodies, and health data interpolated into exception or log messages.
- "Default — nothing to opt out of" still holds: there is no project telemetry toggle, because no pipeline-produced build carries a DSN (FR-189).
- The document names the honest boundary: every claim here describes the SOURCE at a given tag, not the binary any particular person is running; the project cannot verify what a Builder compiled. It publishes which claims are architecturally enforced (no therapeutic write surface, no DSN in CI builds, Keychain accessibility class) versus which are prose.
- The platform repository's privacy page remains canonical and wins on conflict. Privacy concerns are reported through the security channels in FR-226.

#### FR-237: The troubleshooting and status-icon pages, and the forced-loss disclosures they carry

A user hitting a pairing failure, a silent Pump connection, an unrecognised Pump after a restore, an unfamiliar status glyph, or degraded background monitoring finds the explanation on a published page, because §7 names those pages as the disclosure surface for five forced parity losses. Realizes UJ-4. Upholds SI-6.

**Consequences (testable):**
- Two pages exist and render: a pairing-troubleshooting page and an iOS status-icons page. Each is authored fresh in this repository — neither is copied or adapted from `android-unofficial`, whose statements describe a different Bluetooth stack — and each satisfies FR-219's two publication conditions and publishes through FR-220's contract. Basenames are chosen for readability under no cross-repository constraint. A pull request that deletes either, or drops it from its section's `pages` array, fails the same gate as any other page.
- The pairing-troubleshooting page states, without implying the app can do it itself, that iOS exposes no API to enumerate, inspect or delete a Bluetooth pairing, so bond removal is a user procedure: Settings → Bluetooth → ⓘ next to the Pump → Forget This Device, then pair again. Wording matches the in-app wall in FR-11. This is §7 PL-1's disclosure surface.
- The same page states the stale-service-cache consequence: a Pump can be connected and deliver nothing, iOS gives no way to flush a bonded peripheral's cached service database, the app detects the symptom after the fact from three consecutive zero-notification connections (FR-11), and the remedy is the same forget-and-re-pair procedure. This is §7 PL-2's disclosure surface.
- The same page states the pairing-identity consequence: iOS never exposes a stable device address, so a reinstall or a device restore can leave a saved Pump unrecognised, and the remedy is to pair again. The wording is identical to FR-19's in-app statement and the two are tested against each other rather than maintained separately. This is §7 PL-8's disclosure surface.
- The same page documents the pairing-recovery flow end to end: what the app retries on its own — indefinitely, with no attempt cap and no give-up condition while a pairing exists (FR-13) — what only the user can do in iOS Settings, and how Retry Pairing verifies recovery (FR-11). No page describes a terminal give-up state, because none exists.
- The iOS status-icons page documents the iOS glyph set on its own terms, states that every Pump-link state is carried by text and colour as well as by a glyph so no state depends on glyph recognition (FR-43), and does not present the Android glyph vocabulary as if it were shared. This is §7 PL-10's disclosure surface.
- The troubleshooting section carries the reliability statement: iOS has no battery-optimization exemption, no sleeping-apps list, and no setting that grants durable background execution; the only conditions a user can act on are Background App Refresh, Low Power Mode and force-quit, as surfaced by the Reliability card in FR-166. The Android `<5%/day` battery figure does not appear on any page (FR-223). This is §7 PL-52's disclosure surface.
- **A third page exists and renders: the iOS security-testing page**, the counterpart to Android's `docs/dev/security-testing.md` — a counterpart in role, not a copy: it is written fresh against the iOS gate set and inherits no text. It satisfies FR-219's publication conditions and publishes through FR-220's contract. It documents the five Required Checks by their exact names (FR-197), what each tool is and its pinned version, each gate's pass/fail threshold and fail-closed behaviour, what is excluded and why, and how to reproduce each gate locally. It states plainly the three coverage differences the port forces, each of which §7 names it as the disclosure surface for: that Semgrep's `p/kotlin` and `p/java` packs produce zero findings on Swift and CodeQL `swift` with `security-extended` is the substitute (**PL-64**); that Xcode has no Gradle-wrapper-checksum equivalent, so toolchain trust reduces to the runner image plus an in-repo version pin (**PL-57**); and that upstream holds no signing identity, so artifact-level scanning of a signed device build is unreachable upstream even in principle, leaving source-level `Info.plist` and entitlements linting as the substitute (**PL-66**). It carries Android's two documented declines — MobSF and a dedicated secret-scanning gate — with their revisit triggers restated for a world where builds go through App Store Connect rather than being sideloaded.
- All three pages reproduce the log-redaction guidance from FR-221 wherever they ask a user to share output. Upholds SI-9.
- No page of the three claims that alerts are guaranteed, undismissable or able to override the ring/silent switch (FR-235).
- Every link on these pages that leaves the `docs/` tree is an absolute URL (FR-219), including references to `SECURITY.md` and `MEDICAL-DISCLAIMER.md` at the repository root.
- §7 cites this FR — not FR-220 — as the disclosure surface for PL-1, PL-2, PL-8, PL-10 and PL-52. A forced loss whose disclosure surface is a documentation page cites an FR that requires that page to exist and to carry the statement.

**Feature-specific NFRs:**
- Every published number that also appears in code or CI — the deployment floor (NFR-1), the 90-day expiry, the 5-minute empty-dashboard threshold, the Freshness Tier boundaries behind the `--` treatment (FR-120, FR-121), the Conversion Factor and the Glucose Validity Bound (SI-4, one shared definition) — MUST have exactly one authoritative site, and the docs MUST quote it rather than restate it. Android's six inconsistent repository slugs are the cautionary case.
- The install runbook MUST be validated end to end by someone who did not write it, from a clean GitHub account and a clean Apple Developer account, before the repository is announced. It is the only product surface with no fallback if it is wrong.
- Documentation-only pull requests MUST receive the `docs` label and a Documentation changelog section without triggering an `iOS Gate` build, except when they touch `README.md`, `LICENSE`, `docs/THIRD_PARTY_LICENSES.md` or `docs/licenses/**`, which are members of the `ios` paths filter (FR-208). They are still gated: `Static Analysis Gate` runs unconditionally and carries FR-219's four docs checks plus FR-220's `externalLinks` check.
- Publication MUST be spot-checked once before announcement: fetch a page of this tree from glycemicgpt.org and confirm it renders with its frontmatter title and working links.
- The license generator's five failure modes MUST be tested as behaviours of the generator itself, before the first TestFlight build exists, and the drift test MUST exist on day one — otherwise a build path can ship a blank or stale license screen and nothing will notice.

**Notes:**

*Parity Ledger rows this section feeds. §7 owns the rows and their full statements; the ids below are the assignment §7 made, and this list is a traceability map, not a second definition:*
- **PL-53**, **PL-58** No project-published binary, no "download the topmost release" path, and no in-app "Check for updates" that downloads and installs. The install runbook gates on paid Apple Developer Program membership before any use (FR-223) — a hard access barrier Android did not have — and the documented update mechanism is TestFlight plus re-running the fork's workflow; the app can at most compare tags and show a non-actionable banner (FR-188).
- **PL-54** TestFlight builds expire after 90 days. A Builder who stops rebuilding loses a working glucose monitor; a sideloaded APK simply kept running. FR-223 documents it in the body of the install page, not a footnote.
- **PL-63** macOS runner minutes carry roughly a 10x multiplier on private forks. FR-223's prerequisites gate is the disclosure surface, stated before the Builder starts and bound to PL-54, because a Builder out of minutes cannot rebuild before expiry.
- **PL-31**, **PL-61** There is no custom watch face. FR-224 documents complications the user places manually, with no guarantee of placement and no guaranteed refresh cadence.
- **PL-17**, **PL-23** The published alert-delivery warning is strictly longer and more pessimistic than Android's, because the ring/silent switch can silence a `.timeSensitive` alert undetectably and Backend-generated alerts do not reach a suspended or terminated app in v1. FR-234 carries the warning; FR-235 forbids any surface weakening it.
- **PL-52** The battery-optimization exemption documented as a prerequisite on two Android pages has no iOS counterpart, and the `<5%/day` battery figure is deliberately dropped rather than inherited (FR-223, FR-237).
- **PL-69** The device verification table starts almost empty: only Tandem t:slim X2 can reach Verified in v1, and only after DanielDanielson validates on their own hardware (FR-234's README table, §8).
- **PL-40** Android's runtime-loaded plugin contribution path is deleted from the contributor guide rather than adapted, with the tradeoff stated (FR-225).
- **PL-70** RETIRED by §7, not repurposed. It asserted a forced loss that does not exist. What remains true, and is stated in FR-219, is that a link leaving this `docs/` tree is written as an absolute URL rather than a relative path.

[NOTE FOR PM] Settled by ruling and recorded so a later reader does not reopen them. None of these is an outstanding instruction to another section:
1. **FR-237 stands, and this section's allocated range is FR-219 – FR-237.** It was written to close a real defect: five §7 forced-loss rows named a disclosure surface that no FR required to exist. §7 has re-pointed PL-1, PL-2, PL-8, PL-10 and PL-52 from FR-220 to FR-237, and FR-19 (5.1) now cites FR-237 for the pairing-identity statement. Nothing was renumbered and FR-237 was not folded into another FR.
2. **The published Capability contract is six, not seven.** FR-225's contribution guide and FR-234's disclaimer publish no calibration target and no CGM-calibration operation; the permitted non-therapeutic operations are exactly pair/unpair and connect/reconnect/disconnect. §7 PD-36 records the removal and §11 NG-17 states the closure.
3. **The deployment floor is closed** by NFR-1 at iOS 17.0 / watchOS 10.0. §15's question is struck and §16 retired A-45.
4. **The docs checks are hosted in `Static Analysis Gate`.** FR-219's four checks — frontmatter, `pages` membership, a file behind every `pages` entry, and link resolution — run as steps in that Required Check (FR-197). No sixth Required Check is added.
5. **FR-220 was repurposed in place, not renumbered.** It previously described website-side publication plumbing. It now specifies the documentation set this repository must publish for the iPhone and Apple Watch apps. How the site ingests that tree is out of scope.

[NOTE FOR PM] Still outstanding, and not editable from this file:
- §12's preamble, §12.1's section-range row for 5.12, and §16's A-47 still publish the scope as "FR-1 through FR-236" and give this section the range FR-219 – FR-236. Per the ruling above all three read **FR-1 through FR-237** and **FR-219 – FR-237**. FR-237 also appears in no §8 or §10 traceability surface.
- §7's PL-63 row still carries a `[NOTE FOR PM]` placeholder in its disclosure column reading "No disclosure surface currently exists." The surface now exists: FR-223's prerequisites gate states the 10x macOS-minutes multiplier on private forks before the Builder starts. That row should cite **FR-223**, and §7.4's note naming PL-63 as the only forced loss whose disclosure surface does not exist at all should be struck.
- FR-197's host list (5.11) names FR-219's documentation checks as steps inside `Static Analysis Gate`. Conformed; no edit outstanding.
- Nothing outside this file has been told that `docs/` is greenfield. Any surface stating or implying that iOS documentation is migrated, mirrored or adapted from `android-unofficial` contradicts the settled product model and should be corrected on sight.

[NOTE FOR PM] Android defects closed here rather than reproduced: no CI validation of frontmatter or `pages`-array membership (a new page silently failed to publish); no link checker anywhere; the pull-request template CONTRIBUTING tells contributors to fill out but which does not exist; the dangling `docs/dev/monorepo-port-ledger.md` reference; six inconsistent repository slugs across policy documents; and the EC-JPAKE file carrying a prose port note but no Apache-2.0 identifier and no Particle Industries copyright, which Apache-2.0 requires travel with the file.

[NOTE FOR PM] The highest-severity risk in this section is not technical. A naive swap to an off-the-shelf Swift license tool converts five build-breaking guarantees into zero warnings, and nobody notices until a user reads a blank license screen. The generator must be written in-repo and fail-closed.

**Open questions:**
- Counsel review of the manufacturer framing. Android reserves "users become the manufacturer of their own personal medical device" (citing the Loop/AndroidAPS precedent) for third-party forks that add device control. Under fork-and-build that description arguably fits EVERY user. Does the iOS disclaimer need counsel review before the install runbook is published — and if counsel says the framing applies, does that change whether fork-and-build instructions are published publicly, or only how the disclaimer is worded? This gates the two highest-traffic published pages and cannot be decided from the Android repository, Apple's rules, or the stated product context.
- Does the website's `ensureDefaultOpen` step require a root `docs/_meta.json` at `docsPath` root to have something to inject into? `android-unofficial` ships none, and it is not synced, so this is untested. If one is required, this repository authors it — the sync wipes the target path, so the website cannot supply one — and it is authored without a `defaultOpen` key.
- Should the fork template ship a scheduled workflow that rebuilds automatically before the 90-day expiry, or is an automatic rebuild that a Builder never sees a worse failure mode than a build that visibly lapses?
- Is a Builder who edits the disclaimer, adds a DSN, or changes an Alert Threshold default in their own fork still described as running "GlycemicGPT" in these documents, and does the privacy document need to say so explicitly?


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


## 7. Parity Ledger

The enumerated record of every divergence from the Android/Wear OS product. Three tables, one ID space each:

- **PL-n — Forced losses.** Android capabilities iOS cannot deliver. Every row names the surface where the product tells the user. A forced loss with no disclosure surface is a defect, flagged inline with `[NOTE FOR PM]`. Where the disclosure lives on a published documentation page, the row cites the FR that requires that page to exist and to carry the statement — never a page by name alone.
- **PD-n — Deliberate divergences.** Behaviour changed on purpose, including Android defects fixed rather than ported. A row marked **—** records behaviour that is deliberately unchanged, so nobody later "fixes" it on one platform alone.
- **PA-n — Additive substitutes.** Net-new iOS work with no Android counterpart.

Rows reference the FR that owns the behaviour, the SI it is subordinate to, and the UJ it touches. This ledger is the record §6 defers to whenever an NFR says "recorded in the Parity Ledger". §8 owns the Device Verification Matrix, §9 the Validation Tier Model and §10 the Security Gate Substitution Table; rows here name losses, not the substitution mechanics.

---

### 7.1 Forced losses (PL)

#### A. Bluetooth transport and pairing

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-1 | Programmatic bond removal (`BluetoothDevice.removeBond` via reflection) | iOS exposes no public or private API to enumerate, inspect or delete a Bluetooth pairing; bond removal is exclusively a user action. Private-API use would additionally be caught on TestFlight upload, breaking **fork-and-build** | Detect the same conditions with the same counters, then present a guided remediation: Settings → Bluetooth → ⓘ → Forget This Device, a one-tap route into Settings, and a Retry Pairing that verifies recovery | Three Tandem trust-recovery paths (status `0x05` before connect, status `0x08` with no prior session, 3 zero-response connections) and both **Drivers'** unpair paths become manual user procedures | FR-11 broken-pairing wall (blocking, verbatim copy); FR-17 unpair confirmation; the pairing-troubleshooting page required by FR-237, which fixes its wording against the in-app wall |
| PL-2 | GATT service-cache invalidation on every connect (`BluetoothGatt.refresh` via reflection) | Core Bluetooth provides no way to flush a bonded peripheral's cached service database. The only invalidation paths are a GATT Service Changed indication (`0x2A05`) from the peripheral, or the user forgetting the device | Handle `didModifyServices` and re-discover on every fresh connection, never cache characteristic handles across sessions, then detect the symptom via the existing `MAX_ZERO_RESPONSE_CONNECTIONS = 3` heuristic | Stale-cache silent notification loss — a connected **Pump** delivering no data — is detected after the fact rather than pre-empted on every connect | FR-11 (the 3-zero-response condition routes to the wall, which is the disclosure); the pairing-troubleshooting page states the symptom and the forget-and-re-pair remedy (FR-237) |
| PL-3 | Link-layer disconnect status bytes (`0x05` INSUFFICIENT_AUTHENTICATION, `0x08` INSUFFICIENT_ENCRYPTION, `0x13` CONN_TERMINATE_PEER_USER) | Core Bluetooth does not expose HCI status codes; the central sees a coarser system error vocabulary | Behavioural classification: rapid-disconnect timing, whether authentication completed, whether any notification arrived, refined by the system error where one is available | Failure categorisation is less precise; a mis-classified failure can send the user to the wrong remedy | FR-10 failure categories, FR-11 restraint rule (FR-12). `[NOTE FOR PM]` No direct user-facing statement is owed here — impact is internal accuracy. Confirm. |
| PL-4 | Manufacturer-specific advertisement data (company id `0x01F9`, payload `0x00 \|\| ASCII(localName) \|\| 0x00`) | `CBPeripheralManager.startAdvertising` accepts exactly two keys — local name and service UUIDs. No API emits manufacturer data from the peripheral role, on any iOS version, with or without an entitlement | Carry the identity as the standard GAP local name alongside the mode-appropriate service UUID (`0xFE82` first-pair / `0xFE81` reconnect) and rely on the **Pump's** `Mobile .{0,7}` matcher | The Medtronic advertise-and-wait identity may not be recognised at all. Unproven without hardware | FR-6 advertise-and-wait copy; **Verification Status** Beta on the **Driver** (FR-22); §8; the medical disclaimer's per-device table (FR-234) |
| PL-5 | Advertising interval, TX power, timeout and connectable-flag control (`ADVERTISE_MODE_LOW_LATENCY` for reconnect vs `ADVERTISE_MODE_BALANCED` for first pair, `ADVERTISE_TX_POWER_MEDIUM`, `timeout=0`) | Core Bluetooth exposes no advertising interval, PHY, TX power, duty cycle, timeout or connectability parameter. iOS chooses the interval itself and varies it with app and radio state | Reduce the mode selection to the advertised service UUID only | The reconnect-vs-first-pair distinction, which exists because a paired MiniMed **Pump** scans infrequently, becomes unmitigable rather than tunable: reconnection may simply take longer or fail | FR-6 and FR-16 copy; **Driver** documentation states it is not suitable as a sole monitoring path on iOS |
| PL-6 | Background discoverability to a non-Apple central | A backgrounded iOS app has its advertised local name stripped entirely and its service UUIDs relocated to an Apple-only overflow area. A **Pump** scanning for a name or for `0xFE82` cannot discover a backgrounded iPhone | Advertising starts only from the visible pairing screen; an already-established link does survive backgrounding | Advertise-and-wait pairing **and** reconnection are foreground-only. Android's shipped promise that a paired Medtronic **Pump** "is remembered — GlycemicGPT reconnects on its own" is **false on iOS** and must not be carried over | FR-16 (in-app copy and the shipped documentation); the prompt to open the app after a threshold disconnect (FR-16, delivery per 5.4) |
| PL-7 | Connection-parameter and MTU requests (`requestConnectionPriority(CONNECTION_PRIORITY_HIGH)` for a 7.5–15 ms interval; `requestMtu(185)` treated as fatal on failure) | Core Bluetooth gives the central no control over connection interval, latency, supervision timeout or ATT MTU; only the peripheral may request parameters | Assert the negotiated write length after connection and fail loudly with a diagnostic; log negotiated link parameters for a hardware validator. iOS requests an ATT MTU of 185 automatically | Link stability under an unfavourable negotiated interval is unmitigable; it presents as ordinary connection failures | FR-10 failure categories; the diagnostics surface (FR-158) and the hardware sign-off list (§9). `[NOTE FOR PM]` No end-user copy is owed; confirm. |
| PL-8 | A raw device address as a stable pairing key | Core Bluetooth never exposes a Bluetooth address. Identity is an opaque per-installation UUID, not stable across reinstall, device restore, or an unbonded peripheral rotating its private address | A name/serial fingerprint recovery path in addition to the opaque identifier: when the primary identifier stops resolving, the app re-binds the existing pairing record by matching the fingerprint against a service-filtered scan rather than presenting the **Pump** as unpaired | After a reinstall or a restore the saved **Pump** may not be recognised and pairing may have to be redone | FR-19 — when re-binding does not recover the **Pump**, the copy states in words that iOS gives the app no stable device address, that a reinstall or restore can therefore leave a saved **Pump** unrecognised, and that the remedy is to pair again; the same statement appears on the pairing-troubleshooting page and the two are tested against each other (FR-237) |
| PL-9 | Re-prompting for Bluetooth permission ("tap Scan again to re-request") | iOS never re-prompts after a denial | A deep link into the app's own Settings pane, with copy naming the exact toggle | A denied user cannot recover inside the app | FR-3 denial-recovery copy and Settings deep link |
| PL-10 | Material's four Bluetooth glyphs for the six **Pump**-link states | iOS ships no equivalent SF Symbol, and the Bluetooth SIG word and figure marks are trademark-encumbered (membership plus a Declaration ID) | A custom glyph set shipped in the app, with state also encoded in text and colour | If the marks cannot be used, the status-row glyph vocabulary diverges from the published Android status-icons documentation | FR-43 (six states with accompanying text, so state never depends on glyph recognition); the iOS status-icons page (FR-237) documents the iOS glyph set on its own terms |

#### B. Execution model and background behaviour

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-11 | Foreground service and wake locks (`PumpConnectionService`, `PARTIAL_WAKE_LOCK`, 20 min timeout / 15 min renewal / 2 min reconnect lock, `START_STICKY`) | iOS has no foreground service, no wake lock, no service-restart semantics, and no API — public or entitled — that keeps a third-party app running continuously | The `bluetooth-central` / `bluetooth-peripheral` background modes plus Core Bluetooth state preservation and restoration: the system holds the link instead of the app holding the CPU | No app-scheduled periodic work while backgrounded. Everything downstream of a timer becomes event-driven | FR-14, FR-15; the Reliability card (FR-166); the medical disclaimer's alert-delivery conditions (FR-234) |
| PL-12 | Guaranteed fixed-cadence background refresh — a 15 s **Pump** poll that also served as the ~30 s BLE keep-alive | `BGAppRefreshTask` is opportunistic and budgeted (`earliestBeginDate` is a floor, not a schedule); `BGProcessingTask` requires charging and idle; Core Bluetooth wakes on connect/disconnect and characteristic notifications only, never on a timer | Pump-driven cadence where the protocol allows a notifying characteristic, plus an immediate re-read on every foreground activation, plus honest degradation | Dashboard data can be arbitrarily old between foreground sessions. Stale at 6 min, Too Stale at 15 min, severity colour removed | FR-41 foreground re-read; FR-48/FR-49/FR-50/FR-51 **Freshness Tier** treatment and staleness badge; FR-83 **Coverage Claim**; FR-234 |
| PL-13 | Guaranteed background reconnection after the user force-quits | iOS permanently suppresses Core Bluetooth relaunch for a force-quit app until the user manually reopens it. No entitlement, background mode or API changes this, and no code can run to detect the condition while it holds | None. Disclosure plus after-the-fact detection: a last-ran timestamp, and a prominent report of the gap on next launch | Swiping the app away in the app switcher silently stops all background monitoring and all alerting | FR-15 (onboarding, Settings while paired, and the shipped pairing documentation — not dismissible-and-forgotten); FR-85 gap report; FR-166 Reliability card; FR-234 |
| PL-14 | Automatic restart after device reboot (`BootCompletedReceiver` restarting the **Pump** and alert services) | iOS provides no launch-on-boot to third-party apps under any entitlement; there is no `RECEIVE_BOOT_COMPLETED` analogue. Core Bluetooth state restoration applies only after the user has unlocked the device at least once | State restoration covers system-eviction relaunch; the reboot gap is covered by disclosure and by the same last-ran gap detector | After a restart, nothing is captured, uploaded or alerted until the phone is unlocked and — for the force-quit case — the app is reopened | FR-85 (onboarding and Settings copy, verbatim); FR-234 alert-delivery conditions |
| PL-15 | An ongoing, non-dismissible, permanent notification whose existence proves the monitor is alive, mutated with the coverage text | Every iOS notification is user-dismissible and one-shot. There is no ongoing flag and no notification tied to process liveness. A Live Activity — the nearest primitive — runs roughly 8 h active and about 12 h on the Lock Screen, is user-dismissible, and normally starts only from the foreground | A declarative **Coverage Claim** with an absolute expiry, decayed by four independent mechanisms with no code running (widget timeline entry, Live Activity `staleDate`, Watch-local decay, scheduled lapse notification) | No surface can be relied on to be present. The **absence** of a watching indicator must never be read as "watching" | FR-83/FR-84 (the in-app status row is the authoritative claim and the copy says so); FR-119 bounded lifetime; FR-85 lapse notification; FR-235 prohibits any guaranteed-alert claim |
| PL-16 | Guaranteed periodic coverage heartbeat — re-send every `max(timeout/2, 5 s)`, 3 minutes in production, from the foreground service's scope | No guaranteed periodic execution exists to drive a heartbeat | An absolute expiry piggybacked on Core Bluetooth-driven writes; the wrist decays on its own clock | A force-quit app is never relaunched by Core Bluetooth, so the wrist's decay to "no recent data" is the only signal the user gets | FR-126/FR-127 wrist claim and **Not-Watching Reason**; FR-122 wrist decay; FR-85 |
| PL-17 | A long-lived **Backend** alert stream (SSE) held open while the app is suspended or terminated | A background `URLSessionConfiguration` supports only discrete upload and download tasks; streaming data tasks are unsupported and a suspended app has no runloop. APNs is the only path — **deferred for v1** (settled decision 7) | SSE while the process is alive, opportunistic pulls of pending alerts at every execution opportunity, and the on-device **Alert Floor** as the only background alerting mechanism | **Backend**-generated alerts — including caregiver alerts, trajectory, prediction and IOB escalation — do not reach a suspended or terminated app. Caregiver alerting is degraded | FR-157; FR-83/FR-84 (the claim degrades rather than implying continuous **Backend** coverage); FR-234 states it in the published disclaimer |
| PL-18 | Guaranteed periodic background work — a daily retention worker and a 15-minute Nightscout sync floor (WorkManager) | `BGAppRefreshTask`/`BGProcessingTask` are opportunistic and budgeted against user launch patterns | Opportunity-driven work at every execution opportunity, plus an immediate run on foreground | On a rarely opened app, retention and Nightscout-sourced sync may not run for days | FR-144; FR-153 last-successful-sync time and its five distinct states |
| PL-19 | Continuous outbound queue drain — every 3 seconds, forever, from the foreground service | No continuous background execution | Drain in the foreground and in system-granted windows only | Upload latency is materially worse and has no upper bound | FR-142 (the queue's user-visible state); FR-152 connectivity states |
| PL-20 | Forcing delivery of a queued upload | The system may mark background transfers discretionary and hold them for an unbounded time; the app cannot override this | Nothing. The queue depth and state are shown honestly | An upload can sit undelivered indefinitely with no user action available | FR-142 |
| PL-21 | A backgrounded 90-second AI inference request surviving app suspension | iOS suspends within seconds and the request dies. `beginBackgroundTask` grants roughly 30 s and cannot be renewed | Cancel on background and disclose it. Not fixable without chat persistence, which would create a durable store of health-related conversation content that Android deliberately does not have | Asking a question, switching apps and returning loses the answer | FR-110 (explicit disclosure of the interrupted request) |
| PL-22 | **Alert Floor** evaluation on a guaranteed 15-second poll under a wake lock | Evaluation cadence is dictated entirely by Core Bluetooth wake events | The 360,000 ms Fresh window is the whole tolerance budget; the claim decays when it is exceeded | An alarm can be late by up to the gap between wake events, and the claim says so rather than implying continuity | FR-83/FR-84; FR-71 alert body states the provenance; FR-234 |

#### C. Alerting

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-23 | Do Not Disturb / Focus / silent-switch override, free via `ACCESS_NOTIFICATION_POLICY` + `setBypassDnd(true)` on the low and high channels | Requires `UNNotificationInterruptionLevel.critical`, gated on the Critical Alerts entitlement, which Apple grants **per Team ID** after manual review. Under **fork-and-build** every **Builder** signs with their own team, so it is structurally unobtainable (settled decision 4) | `.timeSensitive`, self-serve in Xcode: breaks through Focus when permitted and escapes the Notification Summary. Runtime auto-upgrade to `.critical` if the entitlement is ever present, resolved from `criticalAlertSetting` at post time | An urgent-low alarm **can be silenced by the ring/silent switch, and the app cannot detect that it was** | FR-66 (copy present in the default configuration, suppressed only when `.critical` is active); FR-83 claim detail; FR-171 notification status card; FR-234 and FR-235 |
| PL-24 | Alarm volume boost and restore (`AudioManager.STREAM_ALARM` to max on a low, persisted saved-volume, restored on acknowledge) and the "Boost Volume for Lows" toggle | iOS exposes no public API to set output or ringer volume; driving `MPVolumeView` is a review rejection; there is no API to read the silent-switch position or the current ringer volume | Deleted, not ported, and **no volume control exists anywhere in the product**: no code sets output, ringer or alarm volume, and no code reads or infers the silent-switch position (FR-66). FR-170 offers no volume row. Loudness over silent would require Critical Alerts (PL-23) | An alarm can never be louder than the user's current setting, and the app cannot tell the phone is muted | FR-66 owns the audibility honesty statement and the no-volume-control rule; FR-171 notification status card; FR-234 |
| PL-25 | Custom per-notification vibration waveforms (the low channel's `[0, 500, 200, 500, 200, 500]`) | No public API attaches a vibration waveform to a delivered notification on iOS. Haptics are chosen by the system from interruption level and sound; the private vibration-pattern route is a rejection | Severity encoded in the sound plus a bounded temporal re-alarm ladder | The tactile urgent-vs-warning distinction is gone | FR-66 out-of-scope statement; FR-67/FR-170 (the sound is the severity carrier) |
| PL-26 | A wrist haptic fired from the background without a notification (`0/500/200/500` urgent vs a one-shot 300 ms warning) | `WKInterfaceDevice.play(_:)` is honoured only while the Watch app is running and frontmost. watchOS has no API to vibrate from a background wake | Deliver the alert as a Watch-scheduled notification; urgency carried by interruption level and sound | The urgent double-buzz is gone, and per PL-23 the wrist alarm can be silenced by the ring/silent switch undetectably | FR-128 (the distinction is stated as interruption level and sound); FR-134 states watchOS gives independent notification controls the app cannot override or detect; FR-234 |
| PL-27 | Per-severity custom sounds on the wrist | A notification mirrored from iPhone onto Apple Watch plays watchOS's own default alert sound and haptic | Watch-scheduled notifications for alerts (FR-128); the custom sound choice is an iPhone-only feature | Sound choice does not change what the wrist plays for mirrored notifications | FR-134 (watchOS controls the app cannot override); FR-170 (the picker is scoped to phone alerts) |
| PL-28 | The notification channel model — per-category sound, importance, vibration and DND-bypass tunable independently by the user in system settings | iOS has no notification channels. The system offers only app-level notification settings plus Focus and Scheduled Summary allowances | Category granularity moves into the app: per-category sound and delivery preferences honoured when each request is built | A user who mutes the app in iOS Settings mutes low alerts, high alerts and AI notifications **together** | FR-171 (one card itemising every suppressing condition, each with its own route to the setting that fixes it) |
| PL-29 | Choosing **any** sound in the system sound library as an alert sound — the `RingtoneManager` picker (`AlertNotificationManager.kt:131-175`, `SettingsScreen.kt`), persistable read URI permission, per-URI title resolution. Android ships **no** `res/raw` directory at all: the user's whole ringtone and notification library is the set | iOS exposes no API to enumerate, preview or select the system sound library, and a notification sound may only reference a bundle or container file (≤30 s, PCM/MA4/µLaw/aLaw as `.aiff`/`.wav`/`.caf`). There is no cross-app URI permission model. The bundled set is the **forced substitute for a capability iOS removes**, not a design preference | A curated set bundled in the app — deliberately alarm-like for lows, notification-like for highs and informational — with in-place preview, plus the explicit **Silent** option, which is real Android parity (`AlertSoundStore.SILENT_URI`) and not an iOS invention. FR-67 owns the sound model and the tier on which Silent is offered. User-imported audio is **deferred**, not offered: it adds a transcode failure mode to an alarm path whose failure mode is silence, and FR-67 names the revisit condition | The user cannot pick their own ringtone. A user migrating from Android loses whatever sound they had chosen and must pick from the bundled set | FR-67 (the sound model states the set is closed at build time and why); FR-170 (the picker states that only included sounds are selectable) |
| PL-30 | `setLocalOnly` double-buzz avoidance | iPhone notifications mirror to a worn Watch automatically with no per-notification opt-out | The **Watch-scheduled notification is the primary wrist path** and mirroring is the fallback, never the mechanism: iOS mirrors only while the iPhone is locked, so a mirroring-only design is silent whenever the phone is unlocked and in use — a common daytime state. Both paths share an identity-derived identifier, so a mirrored copy **replaces** rather than stacks (FR-128) | None expected — one fresh low produces one wrist experience. **Offsetting parity gain:** the dismiss action carries the specific alert identifier and *can* silence an **Alert Floor** alarm, which the Android wrist dismiss provably cannot (see PD-17) | FR-128 owns the wrist transport for the whole PRD; FR-131 dismissal; a fallback-only state is reported as degraded coverage (FR-126, FR-127) |

#### D. Apple Watch

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-31 | Custom watch faces — the `:watchface` module: DIGITAL_FULL and ANALOG_MECHANICAL, WFF v2, 450x450 circular scenes, five-slot and three-slot layouts with `DefaultProviderPolicy` binding our own providers, branding text, per-variant overlay defaults | watchOS provides no third-party watch face API of any kind and never has. Apple owns face layout, clock rendering, ambient behaviour and tint. Not an entitlement gap — the surface does not exist at any tier | WidgetKit accessory complications the **user** places on the face **they** chose, the same widgets in the Watch Smart Stack, plus iPhone Lock Screen widgets and a Dynamic Island surface | The guarantee that glucose, IOB, graph, alerts and chat are visible together on one face does not survive. Placement is the user's; the app cannot place anything | FR-117 ("the app ships no watch face… any UI implying otherwise is a defect"); FR-118 guided setup **and active-face detection that states plainly when none of ours is on the face**; the Apple Watch setup page (FR-224) |
| PL-32 | Watch Face Push and phone-set active face (`WatchFacePusher`, `WatchFaceReceiveService`, `WatchFaceInstaller`, DWF validation token, `SET_PUSHED_WATCH_FACE_AS_ACTIVE`, the slot-limit retry and the Samsung double-update workaround) | No face installation API exists, and pushing an executable artifact to a paired device is separately prohibited by App Review Guideline 2.5.2 | Complications ship inside the reviewed, signed bundle. Optionally a shareable face **configuration** the user confirms — a suggestion, never an install | The user must add every complication by hand | FR-117, FR-118 (any shareable configuration is presented as a suggestion the user must confirm); FR-224 |
| PL-33 | Phone-controlled watch-face theme (`dark` / `clinical_blue` / `high_contrast`) and Show Seconds | Apple owns face colour and time rendering. Complications render in a system-controlled tint the app cannot override, so no per-app appearance preference can reach them | **None, and no rebinding.** The theme is not re-expressed as a high-contrast or appearance preference for the **Watch app's** own screens: such a control could not affect the complications the setting exists to style, so it would be a control that does nothing. Legibility is instead an unconditional requirement — every wrist state is encoded on symbol and text, verified by the merge-blocking greyscale review (PL-34) | No control offered, and none offered in its place. (Both settings were already inert on Android — validated, stored, read by nothing) | FR-134 — the offered Watch preference set is exactly eight and contains no theme, appearance or show-seconds control, and the section states why |
| PL-34 | Complication colour under our control — the alerts bell's six-branch hue encoding (grey / amber / red) and the sparkline's four colour-encoded overlay layers (basal teal/blue-grey, bolus pink/orange/purple, IOB blue, activity-mode purple/orange) | watchOS renders complications in an accented/tinted mode using the tint the **user** chose for their face | Every wrist state re-encoded on symbol and text, not hue, verified by a merge-blocking greyscale review. The full seven-layer full-colour graph lives only inside the **Watch app** and on iPhone widgets | The wrist sparkline ships **without** the basal, bolus, IOB and activity-mode overlays | FR-117 (states the omission and why); FR-133 (where full colour is real); FR-126 greyscale requirement |
| PL-35 | Unmetered phone→watch complication refresh | High-priority wrist transfers draw on an OS daily allowance; Android has no cap | Pre-baked timeline entries make **Freshness Tier** and **Coverage Claim** decay free; metered transfers are spent only on material change, with a floor of at most one per 15 minutes; when the allowance is exhausted the app degrades to unmetered delivery rather than dropping data | A data-driven wrist refresh is not guaranteed per **Glucose Reading**; the wrist can lag | FR-120/FR-121 (the wrist always shows the reading's own age and its **Freshness Tier**), FR-122 |
| PL-36 | Watch-side self-update and a separate watch artifact (`WearAppUpdateChecker`, `WearApkPusher`, `WatchApkReceiveService`, `PackageInstaller`, the 100 MB cap, the 15 s install timer, and the documented ADB sideload route) | watchOS has no sideloading, no package installer and no API to transfer or install an executable on the paired device; the same code-download prohibition applies | The **Watch app** ships inside the phone app bundle, so versions cannot diverge after a successful install. A mismatch is reported as a diagnostic only | The capability "update the watch app from the phone" no longer exists. Net improvement overall, and Android's hardest documented install step disappears | FR-115 single-bundle delivery; FR-173 build-mismatch warning directing the user to TestFlight; FR-224 |
| PL-37 | A guaranteed AI Chat entry point on the wrist (a slot on our own watch face) | watchOS permits no third-party faces (PL-31) | A WidgetKit accessory complication plus a Smart Stack widget the user adds manually | A user who adds neither has no wrist chat entry point at all | FR-117 (the chat widget kind is enumerated), FR-118 guided setup, FR-224 |
| PL-38 | A guaranteed chat glyph colour (Android tints the chat complication `0xFF3B82F6`) | Accessory rendering applies the face's tint | The glyph must be identifiable in monochrome | None, if the glyph reads in greyscale | FR-126's greyscale gate is the enforcement. `[NOTE FOR PM]` No user-facing disclosure owed; confirm. |
| PL-39 | A developer loop that can exercise the primary wrist input path | watchOS dictation does not function in the Simulator, and the lead developer has no Apple Watch (context 10) | Three one-tap prompts and a widget prefill cover the same downstream state machine in the Simulator; truncation and blank handling are unit-testable on the plain string | Wrist dictation is validated only by DanielDanielson on hardware, from their own fork under their own Apple Developer account | §9 **Validation Tier** model; the release checklist; §8 |

#### E. Drivers and extensibility

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-40 | Runtime **Driver** installation — sideloading a DEX JAR into `filesDir/plugins/`, the Custom Plugins card, the Add Plugin document picker, the 50 MB / `PK\x03\x04` ZIP-magic / canonical-path-containment install pipeline, per-**Driver** Remove, and the "Custom plugins are not verified by GlycemicGPT" trust warning | Apple forbids it at two independent levels: Guideline 2.5.2 (TestFlight is not a carve-out) and OS-level code signing — every executable page must be signed at build time; `dlopen` succeeds only for frameworks already embedded in the bundle. No entitlement exists to request (settled decision 1) | The **Driver Catalog**: every **Driver** compiled in, listed with name, version, protocol, **Capability** slots and **Verification Status**. An unmerged **Driver** is run by forking, opening Xcode and signing with your own Apple credentials | Trying a community **Driver** now requires a fork, Xcode and your own Apple credentials — a materially higher bar than `adb push`. Contributing one requires a source change, a merged PR and a rebuild by each **Builder** | FR-21, FR-22 (the list doubles as "what does this build contain"); **Verification Status** replaces the install-time trust warning; the contributor guide (FR-225) **deletes** the runtime-plugin path rather than adapting it and states the tradeoff plainly (UJ-6) |
| PL-41 | Runtime per-**Driver** containment — `RestrictedContext` throwing `SecurityException` for ~30 `Context` operations with exactly seven allowlisted system services (BLUETOOTH, LOCATION, POWER, ALARM, SENSOR, USB, WIFI), and `ScopedCredentialProvider` namespacing runtime-plugin credentials | iOS has no per-module runtime capability restriction: every compiled-in **Driver** shares one sandbox, one entitlement set, one container and one Keychain. Swift cannot deny a linked module access to Core Bluetooth or the file system, and there is no `getSystemService` chokepoint | Compile-time containment: **Driver** targets depend only on the shared safety module, the **Driver** API and Core Bluetooth, enforced by build-graph dependency; a CI import lint; CODEOWNERS review on trust-boundary files | Stronger than Android for the code it covers, but it enforces **nothing at runtime**. (Android's own docs record `RestrictedContext` as porous — a plugin could reflect over host classes to bypass it) | FR-21, FR-22, FR-31; FR-212 (project-lead review on trust-boundary files); the contributor guide (FR-225) |
| PL-42 | Registration guaranteed by compilation — Hilt's `@Binds @IntoSet` multibinding means a **Driver** that compiles is registered | Swift cannot enumerate protocol conformances at runtime | An assertion of the **Driver Catalog's** exact expected set of ids, run inside the `iOS Gate` **Required Check** (FR-197) | A compiled-but-unregistered **Driver** would be silently absent from the running app. The failure mode is net-new to iOS | FR-21 (the check is the control); FR-205 public-interface snapshot gate. Engineering-facing: no end-user surface is owed |
| PL-43 | Runtime **Driver** API-version rejection (exact equality at registry init and JAR load) | With compile-time linking the runtime check is structurally unreachable | A build-time assertion: every **Driver's** declared API version equals the project's constant, failing the `iOS Gate` **Required Check** (FR-197) | None functionally — the enforcement moment moves from runtime to CI, and a mismatch fails the build instead of making the **Driver** silently vanish | FR-21; the contributor guide (FR-225) |

#### F. App surfaces

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-44 | Chart detail forced landscape via `Activity.requestedOrientation` ("sensor landscape") | iOS has no per-screen orientation property and no sensor-landscape concept; `requestGeometryUpdate` interacts with the user's rotation lock differently and is not honoured the same way on iPad | Request landscape on entry, restore the prior mask on **every** exit path; the chart stays fully usable if the request is not honoured | On iPad the detail chart simply renders in the window's current orientation | FR-56 (the chart is fully usable either way, so no failure state is presented to the user). `[NOTE FOR PM]` iPad support is an open question in 5.3; the disclosure need depends on the answer. |
| PL-45 | The draggable meal entry button — a per-device persisted FAB position and a "Reset position to default" TalkBack action | Not a platform impossibility but a deliberate consequence of the iOS layout model and the tab bar; retaining it would fight the platform | A fixed entry point above the tab bar safe area plus a redundant "Log a meal" Home list row | Drag is dropped entirely; the position-reset accessibility action disappears with it | FR-93 (a second, redundant entry point means the capability's purpose — reachability — is preserved). `[NOTE FOR PM]` This is the one row in this table that is a choice rather than a hard platform bar; confirm it belongs in PL rather than PD. |
| PL-46 | In-process recovery from an oversized image decode — catching `OutOfMemoryError` and showing "That photo is too large to process. Try a smaller one." | iOS has no catchable out-of-memory condition; the system jetsams the process | A header-only pre-check before decode, a one-pass downsample that never holds a full-resolution image, plus a launch-time recovery marker after a termination | The same user-facing copy is reachable, but a jetsam mid-upload is recovered on next launch rather than in-process | FR-95 (the same failure copy; the marker produces an honest failure state on next launch rather than resuming into a spinner) |
| PL-47 | Re-prompting for camera permission after a first denial | iOS never re-prompts | A deep link into the app's Settings pane | A denied user must leave the app to recover | FR-94 denial copy and Settings deep link |
| PL-48 | Labelling TTS voices that require a network connection ("Online") | iOS exposes no equivalent flag on `AVSpeechSynthesisVoice` | The label is removed rather than guessed | A user cannot tell which voices need connectivity | FR-113 (the label is absent; nothing is claimed). `[NOTE FOR PM]` No disclosure is owed for an absent label; confirm. |
| PL-49 | Portability of a persisted TTS voice identifier | An Android `ai_tts_voice` value never resolves on iOS, and no cross-platform settings migration path exists or should be built | Unknown-voice fallback to the system voice | A user moving from Android re-picks their voice once | FR-113 fallback behaviour. `[NOTE FOR PM]` No migration is offered, so no disclosure is owed; confirm. |

#### G. Network and platform policy

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-50 | An App Transport Security exception scoped to private/LAN IP ranges — cleartext to 10.x, 172.16–31.x, 192.168.x and CGNAT while ATS stays enforced for every public host | ATS exceptions are per-domain and accept neither IP addresses nor CIDR ranges. `NSAllowsLocalNetworking` is documented as covering single-label and `.local` names and link-local ranges, not RFC1918 literals, and its presence causes `NSAllowsArbitraryLoads` to be ignored | **The in-app policy is the substitute and the requirement**: no cleartext to any host that is not literal loopback, private (RFC1918), carrier-NAT (100.64.0.0/10) or link-local, classified in-app by strict literal-address parsing and never by DNS lookup, enforced at save time and again per request, identically in debug and release (FR-150, NFR-20). The `Info.plist` configuration that achieves this is an **architecture decision requiring empirical verification** — whether `NSAllowsLocalNetworking` covers raw private-IP literals is genuinely unsettled and is stated nowhere in this PRD as fact (§15). Until architecture records a verified baseline, the Entitlements and Plist Guard (FR-204) treats the committed plist as the baseline and fails any widening diff | A policy bug in app code is the only thing between a user and cleartext to a public host — a security property Android gets platform help with | FR-150 (public addresses always require https, refused before a request is issued); FR-163's acknowledgement dialog and the persistent insecure-transport banner |
| PL-51 | Reaching a LAN-hosted **Backend** with no additional permission gate | iOS 14+ Local Network Privacy prompts once; denial is permanent until the user visits iOS Settings and cannot be re-prompted in-app. The Simulator neither presents nor enforces it | An explicit named state and a Settings deep link, so denial never presents as an unreachable **Backend** | A new failure mode with no Android counterpart that otherwise looks like an unreachable **Backend** | FR-151, FR-162 (the local-network-blocked state names the cause and offers the deep link) |
| PL-52 | A battery-optimization exemption the user can grant (`isIgnoringBatteryOptimizations` and its Settings intent), documented as a prerequisite on two Android pages, and the published "<5%/day" battery figure | iOS has no per-app battery-optimization allowlist, no Samsung-style sleeping-apps list, and no setting that grants durable background execution. The Android battery figure measures an Android background model | A Reliability card reporting the conditions the user **can** control: Background App Refresh status, Low Power Mode, and force-quit (which stops Core Bluetooth state restoration) | There is nothing the user can toggle to buy reliability; the Android battery number is deliberately dropped rather than inherited | FR-166 Reliability card (renders only when a condition actually degrades monitoring, names it, and links to the setting); the install runbook (FR-223) and the troubleshooting page's reliability statement (FR-237) |

#### H. Build, distribution and engineering gates

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-53 | A project-published, project-signed installable binary and in-app self-update (`app-release.apk` from the topmost release, the `dev-latest` debug pre-release, `AppUpdateChecker`, `REQUEST_INSTALL_PACKAGES`, the FileProvider install intent, and all the download hardening around it) | Apple offers no signed-artifact-on-a-releases-page model at any tier; ad-hoc is capped at 100 devices per class per team per year; the Enterprise Program forbids outside-organisation distribution; `itms-services://` requires Enterprise. Guideline 2.5.2 independently forbids downloading and executing code. **fork-and-build** is what keeps GPL-3.0-only workable (settled decision 3) | Source at signed tags; each **Builder's** own fork signs with their own Apple Developer account and uploads to their own internal TestFlight (up to 100 internal testers, no Beta App Review). The app keeps a read-only upstream version notice with an "Open TestFlight" action. That upstream-release check (FR-188) is the single permitted network exception in **Backend-optional mode**, is user-toggleable and is off by default (NFR-23) | There is no download link. Every user must fork, register identifiers and build | FR-179, FR-188, FR-173 ("the app never downloads or installs any build, for itself or for the Watch"); the install runbook opens with the prerequisites gate (FR-223) |
| PL-54 | An installed build that runs indefinitely | A TestFlight build expires 90 days after upload and stops launching | A scheduled rebuild workflow shipped enabled by default, plus an in-app expiry countdown with escalating prominence | An expired build **does not launch, therefore does not monitor and does not alert** — a silent loss of monitoring for a glucose monitor | FR-187 (countdown, escalating prominence, the exact refresh action); FR-186; FR-223 documents it in the body of the install page, not a footnote; FR-173 |
| PL-55 | A rebuild schedule that cannot be switched off behind the **Builder's** back | GitHub disables scheduled workflows after 60 days of repository inactivity — 30 days **before** the TestFlight build expires | Any repository activity, including the upstream sync, re-arms it; the in-app countdown is the backstop | A quiet fork can lose its automatic rebuild while the **Builder** believes it is armed | FR-186 states it on the build page, not in troubleshooting; FR-187's countdown is the independent backstop |
| PL-56 | The fixed release-signer fingerprint equality check (`RELEASE_SIGNER_SHA256=55f0d0cd…`) | Every **Builder** signs with their own Apple Distribution certificate; there is no project-known identity to compare against | A property assertion on the archive: Apple Distribution identity, `get-task-allow == false`, `TeamIdentifier` matching the configured team, unexpired profile. Hard fail, before upload | Nothing structurally ties an installed build to a project-known identity | FR-184; FR-223 (the install runbook states plainly that the project holds no signing key and can vouch for no binary); FR-233 records the port provenance |
| PL-57 | A verified build toolchain (the Gradle wrapper checksum) | Xcode has no wrapper-checksum equivalent | Toolchain trust reduces to the GitHub-hosted runner image plus an in-repo version pin: the Xcode version pinned explicitly with `xcode-select` and tracked as a reviewed dependency (FR-208), and the resolved package graph committed and drift-checked (FR-201) | A weaker supply-chain guarantee at the toolchain layer | FR-201 and FR-208 (FR-193 defers to them); §10; the published iOS security-testing page, required by FR-237 (5.12) |
| PL-58 | Building and installing with no developer account, no renewal and no per-user cost | Apple requires a paid Apple Developer Program membership for TestFlight; a free account gets 7-day sideload profiles only. Distribution certificates and provisioning profiles expire annually | None. Disclosure and lifecycle surfacing | Every **Builder** pays annually and renews certificates and profiles on a one-year cycle | FR-223 prerequisites gate (read before investing effort); FR-187 surfaces certificate, profile and membership days-to-expiry where the pipeline recorded them |
| PL-59 | An `applicationId` that is just a string | Apple's App ID namespace is globally unique across all developer accounts, so every **Builder** must register their own | A one-time identifier and capability registration step in the **Builder's** own account | The largest new setup burden in the whole product, with no Android counterpart | FR-181, FR-182; FR-223 step order |
| PL-60 | Free side-by-side stable and development installs (`applicationIdSuffix ".debug"`) | Each variant needs its own globally unique App ID, provisioning profile and App Store Connect record | One identifier with a branch-selectable channel | Not provided in v1: a **Builder** cannot run stable and development side by side | FR-183, FR-187 (the channel is shown so a **Builder** always knows which build they are running). `[NOTE FOR PM]` Open in 5.10 — if side-by-side becomes a requirement it changes what FR-182 registers. |
| PL-61 | Watch-face build artifacts (`GlycemicGPT-WatchFace-Digital/Analog` APKs, WFF assets, the certificate-assertion carve-out) | Consequence of PL-31 — there is no face artifact to build, sign, publish or exclude | Nothing needed. Strictly better on the signing axis: Android's watch-face APKs were debug-signed, whereas everything on iOS is signed by the **Builder's** own Distribution certificate | A lost build product; no user-facing behaviour beyond PL-31 | FR-184, FR-189 (build-time composition of what ships) |
| PL-62 | Upstream-enforced gates on, and verification of, the binary each user installs — on Android, upstream CI built the APK users side-loaded, so every gate ran against the exact artifact | Under **fork-and-build** the installed binary is produced by the **Builder's** own workflow, from their fork, at their chosen commit, signed with their certificate. Upstream holds no signing identity, can require no status check there, and cannot produce a signed device build at all | The gates ship unbypassable-by-default inside the workflow the **Builder** forks — a red guard means no artifact; the workflow builds from a pinned upstream tag by default; the upstream commit SHA, **Contract Pin** version and guard results are stamped into the build and surfaced in-app | Every published architectural claim is a claim about **source at a stated tag**, not about the binary anyone is running | FR-187 in-app provenance; FR-196 (the pipeline as a supported surface **and** the **Builder** boundary); FR-221; FR-233 |
| PL-63 | Cheap CI minutes (Linux runners) | macOS runner minutes carry roughly a 10x multiplier on private repositories | Keeping non-Xcode **Required Checks** on `ubuntu-latest`, and `swift test` for platform-independent modules | A **Builder** who makes their fork private can exhaust the free allowance in a handful of iOS-plus-watchOS builds and lose the ability to rebuild before expiry | FR-223 — the install runbook's prerequisites gate states the ~10x macOS-minutes multiplier on private forks before the **Builder** invests any effort, alongside the membership gate, and states the consequence in the same breath as the 90-day expiry rather than in a separate performance note: with no minutes left the build-and-upload workflow cannot be re-run, and an expired build does not launch, does not monitor and does not alert (PL-54). The documented remedies are keeping the fork public or budgeting paid minutes |
| PL-64 | SAST depth — Semgrep `p/kotlin` + `p/java` as the SAST policy | These packs produce zero findings on Swift, and no Swift pack of comparable breadth exists from any vendor | CodeQL `swift` + `security-extended` (version-pinned), Semgrep `p/secrets` retained unchanged, gitleaks, and project-specific SwiftLint custom rules encoding this app's **Safety Constants** and SI rules | A green Static Analysis Gate on iOS carries measurably less assurance than the same-shaped Android gate. A naming-only port would produce a permanently green check that tests nothing | §10; FR-200; the published iOS security-testing page, required by FR-237 (5.12), which records the residual gap the way Android recorded its MobSF decision |
| PL-65 | Manifest and network-security posture linting (Android Lint, the named verifier for HTTPS enforcement and the compensating control cited in Android's MobSF decline) | Apple ships nothing comparable: `xcodebuild analyze` covers C/Objective-C, not Swift, and never inspects `Info.plist` or entitlements | The Entitlements and Plist Guard — deterministic, covering ATS exceptions, `get-task-allow` in release, background modes, usage-description strings and non-grantable entitlements | Covers the specific posture class deterministically but is narrower than Android Lint | §10; FR-204 |
| PL-66 | Artifact-level scanning | Upstream holds no signing identity, so upstream CI cannot produce a signed device build; the iOS analogue of APK-artifact SAST is unreachable upstream **even in principle** | Source-level `Info.plist`/entitlements linting upstream | Android's accepted residual gap — material present only in the built artifact — persists and widens slightly | §10; the published iOS security-testing page, required by FR-237 (5.12) |
| PL-67 | Dependency CVE coverage comparable to Maven's (Android's baseline: ~1,175 resolved packages clean, every locked coordinate scannable) | SwiftPM advisories in OSV and the GitHub Advisory Database are materially sparser, and a remote SPM `binaryTarget` is a checksummed zip with no resolvable package identity, so it cannot be CVE-scanned at all | Policy rather than tooling: remote `binaryTarget` dependencies forbidden outright, exceptions requiring lead review, written justification and `checksum:` pinning; vendored C/ObjC kept in-tree as source so static analysis can read it | A class of dependency is structurally unscannable | §10; FR-201 (the scan and the resolved graph); FR-204 (the build-script and plugin guard that fails an unallowlisted `binaryTarget(`); FR-212 (lead review) |
| PL-68 | Simulator/emulator-level BLE smoke coverage | Core Bluetooth does not exist in the iOS Simulator — `CBCentralManager` never reaches `poweredOn`. The Android emulator at least presented a non-functional Bluetooth stack | Trace-replay tests over recorded frames behind a transport seam, plus the **Simulated Driver**, plus a written hardware-validation checklist executed by the maintainer | Neither CI ever tested BLE against real hardware, so **release-gate parity is preserved**; what is lost is Simulator-level smoke | §9 **Validation Tier** model; FR-206, FR-207; FR-209 records the coverage delta honestly |

#### I. Documentation and policy

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-69 | An inheritable device verification table with existing Verified statuses | No Android device status may be inherited: iOS is a different transport stack, and **Verification Status** is a claim about this platform | Only Tandem t:slim X2 can reach Verified in v1, and only after DanielDanielson validates on their own hardware from their own fork under their own Apple Developer account (context 9). Medtronic ships present-but-gated at Beta, matching Android's own label (settled decision 5) | The verification table starts almost empty | §8; FR-22 renders **Verification Status** per **Driver**; FR-234 defers to the README table |

**PL-70 — retired, not renumbered, and not reused.** It recorded a forced loss that does not exist. Each repository in the org keeps its own `docs/` tree and the `website` repository pulls them in; iOS pages are under no naming constraint from `android-unofficial`. What remains true is stated in FR-219: a link leaving this `docs/` tree is written as an absolute URL, never a relative path.

#### J. Observability and diagnosability

| ID | Android capability | Why iOS cannot | Closest honest substitute | User-visible impact | Where the user is told |
|---|---|---|---|---|---|
| PL-71 | The project possessing the binary a user runs, and therefore receiving a crash report, a stack trace or a device log it can reproduce against a known build — upstream CI built the APK users side-loaded | Consequence of **fork-and-build** (PL-53, settled decision 3): the project publishes source only, holds no signing key and never possesses a **Builder's** binary. No entitlement or service changes this | **None claimed.** Every failure the app can detect is made legible to the user, on the device, at the time; the user hands over what the project cannot see. No requirement in this PRD may be justified by "we will see it in crash reports" (NFR-32) | A defect nobody reports is a defect nobody learns about. Diagnosis depends entirely on what the user can read on their own screen and choose to send | FR-158 user-initiated scrubbed export (the only hand-over path); FR-236 privacy document states plainly that the project receives no crash data and that a **Builder**-supplied DSN reports to that **Builder's** own account; FR-226 security disclosure policy |
| PL-72 | A continuous process-level record: the foreground service ran for the whole monitoring period, so `adb logcat` and the in-app record had no gaps | iOS suspends and terminates the app (PL-11, PL-13), so no log can hold an entry for an interval in which no code ran | A bounded in-app ring buffer present in every build configuration, scrubbed per SI-9, exportable by the user (NFR-33) | The log has honest gaps, and an empty interval means "we were not running **or** nothing happened" — the export cannot distinguish them. A reader who assumes silence means health will misdiagnose | NFR-33 requires the export to state it, so the gap is disclosed at the moment the log is read; FR-158 owns the export and shows the user its contents before sharing. `[NOTE FOR PM]` FR-158's consequences do not yet carry the gap statement NFR-33 mandates. Add it to FR-158 or the disclosure lives only in §6. |

---

### 7.2 Deliberate divergences (PD)

Changed on purpose. Rows marked **fix** correct a defect present in the Android product; rows marked **improvement** change correct-but-inferior behaviour.

| ID | Android behaviour | iOS behaviour | Rationale |
|---|---|---|---|
| PD-1 **fix** | Two unpair entry points with materially different effects: the Settings path clears credentials only, leaving a live session, a running service and a stale bond | One canonical unpair, always confirmed, that tears down session, credentials and advertising and then instructs the user to forget the device in iOS Settings (FR-17) | A half-unpaired state is a support-load hazard and, given PL-1, the stale bond is the exact thing that blocks a successful re-pair (UJ-4) |
| PD-2 **fix** | Tandem copy hard-coded into the central-scan pairing branch | Every string on the pairing screen — blurb, code instructions, discoverable-as copy — is supplied by the active **Driver** (FR-2) | Hard-coded copy would mislabel any future contributed **Driver** (UJ-6) |
| PD-3 **fix** | RSSI frozen at first sighting in the discovered-device list | Signal strength updates live while the entry is visible (FR-4) | A frozen bar misrepresents proximity during the one task where proximity matters |
| PD-4 **fix** | Reconnecting rendered as the plain scan UI with no indication at all | Reconnecting is an explicit state whenever a pending connection is outstanding, visible on the pairing screen (FR-8, FR-13) | Indistinguishable states are the fastest route to a user concluding the app is dead (SI-6) |
| PD-5 **improvement** | No cancel affordance and no UI timeout on connect/authenticate; the OS GATT connect eventually errors out | A Cancel action plus a 45 s watchdog, deliberately longer than the **Driver's** own 30 s authentication timeout so the **Driver's** real transition always wins (FR-9) | On iOS a pending connection **never** times out by design; shipping Android's screen would produce an unrecoverable spinner whose only escape is force-quitting — which additionally kills background monitoring (PL-13). The watchdog bounds the pairing screen's own affordance only; it is not a reconnection cap. FR-13 forbids any attempt cap, maximum-failures abort or give-up condition while a pairing exists |
| PD-6 **fix** | The advertise-and-wait force-first-pair switch exists but is unreachable from the pairing UI, so every Medtronic re-pair advertises first-pair | Exposed from Re-pair (FR-6) | The switch exists precisely for the case the UI made unreachable |
| PD-7 **fix** | A trust or authentication failure with no **Pump** selected renders nothing; the dashboard status row is a non-tappable dead end | The failure still produces a user-visible signal, and the status row is tappable straight into the pairing flow when pairing has failed (FR-20) | A silent failure in a monitoring app is the failure mode SI-6 exists to prevent |
| PD-8 **fix** | Four deprecated **Pump** interfaces and their four registry adapters, two carrying live defects: the history-log adapter returns an empty list when no **Driver** is active (indistinguishable from "the patient had no boluses"), and deprecated signatures default their **Safety Limits** parameter to the absolute bounds when a caller omits the user's narrowed configuration | Not ported. No active **Driver** is a distinguishable error, never an empty result (FR-33); **Safety Limits** are read fresh at every validation pass and may only narrow (FR-32) | Both defects are safety-relevant: one fabricates clinical absence, the other silently widens the **Glucose Validity Bound** (SI-11). Note the deliberate asymmetry this does **not** touch: **Driver**-level validation runs against the current, narrowable **Safety Limits** (FR-32) while storage-layer rejection runs against the absolute **Glucose Validity Bound** 20–500 (FR-138), so a narrowing never retroactively invalidates a stored row. Two gates, different bounds, by design |
| PD-9 **fix** | The reference **Driver's** manual-entry path validates against the absolute bound and silently does nothing on invalid input | Validates against the **current Safety Limits** and shows an inline error (FR-35) | The reference **Driver** is what every contributed **Driver** copies (UJ-6) |
| PD-10 **fix** | A text setting edited and then navigated away from without blurring loses the edit | Text inputs persist on focus loss **and** on leaving the screen (FR-29) | Silent data loss in a settings surface |
| PD-11 **improvement** | The **Driver** kill switch leaves the plugin present but inert | A **compilation condition**, not a runtime flag: the gated **Driver** is not compiled into the shipped binary and is absent from the **Driver Catalog**, every list and every picker, while the **Builder's** prior slot selection is preserved for a later build that re-enables it. Both halves are required: CI additionally builds a configuration with **every Driver's gate enabled**, so gated code stays compiled and test-covered. 5.10 FR-189 owns the build composition, FR-27 owns what the **Builder** and user see, and 5.11 FR-208 owns the all-**Drivers**-enabled CI configuration | Absent is unambiguous; inert-but-present is a state a user can misread, and a defect can still reach it. A compilation condition without the CI configuration is untested code; the CI configuration without the compilation condition is not a kill switch |
| PD-12 **improvement** | US formatting forced inside the glucose formatter only; device-locale formatting for IOB, basal, battery, reservoir, TIR percentages, CV% and GMI — so a comma-decimal device shows "6.7 mmol/L" next to "1,23u". Java's `%f` rounds half-up | Every dashboard number uses a dot decimal separator and explicit half-up rounding regardless of device locale. Pinned ties: 12.5% → "13%", a mean of 100.5 → "101", 0.125 U → "0.13" (FR-60) | Two defects compound: a mixed-separator screen, and Foundation's `String(format:)` rounding half-to-**even**, which would render 12.5% as "12%" and 100.5 as "100" in a naive port, silently drifting from the Android string and from the **Watch app** |
| PD-13 **fix** | The Recent Boluses / Bolus History **Glucose-Reading**-at-event column (labelled "BG" in the Android UI) prints a raw mg/dL integer with no unit label, even for mmol/L users — the one glucose surface on the Android dashboard that ignores the display preference | Renders in the user's display unit with its label, converted once through the **Conversion Factor** and rounded last (FR-92) | SI-3. A raw mg/dL integer shown to a mmol/L user is a misreadable number on an insulin screen |
| PD-14 — | Severity banding treats a value exactly at `low` as Low and exactly at `high` as High, while Time in Range counts both as in-range | Identical, and pinned by test in both places (FR-47, FR-58) | Recorded so the inconsistency is not silently "fixed" on one platform only. **No behavioural divergence** — the divergence is that iOS pins it deliberately where Android leaves it accidental |
| PD-15 **improvement** | Urgency carried by a custom vibration waveform and an alarm-volume boost, plus `setOnlyAlertOnce(false)` | A bounded finite **phone** re-alarm ladder: exactly 5 repeats at 120-second intervals, ending 10 minutes after the initial alarm, cancelled unconditionally on acknowledge and before any network call (FR-76). The wrist has its own separate Watch-scheduled 30-minute ladder (FR-129), and each phone repeat updates the existing wrist notification in place rather than adding a haptic | Temporal substitute for two mechanisms iOS does not have (PL-24, PL-25), kept well inside the 64 pending-request limit. A tuning parameter, not a ported constant. Two surfaces at two cadences is deliberate: the wrist ladder must keep running with the app force-quit, which the phone ladder cannot do |
| PD-16 **fix** | Two graph surfaces with different Y clamps — 20/500 on the sparkline, 40/400 on the detail view — and a reading outside the axis pinned to the boundary | **One rule for every graph surface on phone and wrist**, owned by FR-52 and cross-referenced by FR-133: the axis DEFAULTS to 40–300 mg/dL for readability and EXPANDS to include any reading outside it (lower bound `min(40, lowest visible)`, upper bound `max(300, highest visible)`, further expanded to include any **Alert Threshold** grid line drawn). A reading is **never** pinned to a boundary; a 35 mg/dL reading draws below the 40 line, not on it | Two defects, both closed. A reading below 40 was visible on one chart and clipped off the other — no reading inside the **Glucose Validity Bound** may be visible on one surface and absent from another (SI-2). And pinning draws a valid in-bound reading at a false height, which misstates a glucose value to the user (SI-3) |
| PD-17 **fix** | The wrist dismiss carries an empty payload and assumes the most recent alert | The dismiss payload carries the identifier of the specific alert (FR-131) | Two alerts arriving in quick succession can cross-dismiss on Android. Combined with PL-30, the iOS mirrored dismiss can also silence an **Alert Floor** alarm, which the Android wrist dismiss provably cannot |
| PD-18 **fix** | The Watch chat watchdog is 30 s while the phone-side AI call is 90 s | One shared timeout across the phone request and the **Watch app's** in-flight watchdog (FR-114) | A slow-but-successful answer surfaces as a wrist timeout, then gets replaced by the real response — an inconsistency the user reads as a broken feature |
| PD-19 **fix** | Alert history retention pinned at a fixed 7 days, and cleanup running only when the alerts screen is opened — so a user who never opened that screen was never pruned at all | Alert history follows the user's chosen retention window (1–30 days, default 7) and is pruned by the same scheduled retention pass as every other table, never on screen open (FR-139). FR-87 defers to FR-139 and restates no fixed rule | Retention that runs only when a screen is opened is not retention: it is an unbounded table with a cosmetic filter. Both halves are corrected — the window becomes the user's, and the pruning becomes scheduled |
| PD-20 **fix** | A raw **Pump**-history cleanup path with zero production callers, so `raw_history_logs` grew without bound in full-stack mode | Every table is bounded by one retention window and the cleanup is actually called (FR-139, NFR-16) | Dead safety code implies a protection that is not being exercised |
| PD-21 **fix** | Six post-login fetches running on the sign-in screen's scope, cancelled if the user backgrounds that screen | Device registration and post-login work run on a task tied to the app (FR-156) | Backgrounding the sign-in screen mid-flight left the account half-initialised |
| PD-22 **fix** | A **Backend** URL carrying a path prefix is silently accepted and then a different URL is requested | A URL carrying a path, query or fragment is rejected at save time with a specific message (FR-150) | Silently requesting a different host path than the user typed is unexplainable from the outside |
| PD-23 **improvement** | Outbound queue bound 5,000 rows; stale in-flight reclaim window 60 seconds | **20,000 rows**; 15 minutes (FR-140, FR-142) | iOS defers work Android performed immediately (PL-19). At the 15-second cadence the enqueue rate is roughly 8 rows/min, so 5,000 rows is about 10 hours — an iPhone suspended overnight exceeds that and would silently discard the oldest **Pump** history. FR-142 is the enforced cap; NFR-7's data-volume table and NFR-16 quote it and state no second number |
| PD-24 **improvement** | `PumpCredentialProvider` on `EncryptedSharedPreferences` for built-in **Drivers**; `ScopedCredentialProvider` on **plain** `SharedPreferences` for runtime plugins, a documented accepted risk | Every **Driver** uses per-**Driver** namespaced Keychain storage, device-only, after-first-unlock (FR-18) | Strictly stronger than either Android path, and it removes Android's documented revisit trigger. After-first-unlock is required so overnight reconnection works while locked (SI-10) |
| PD-25 **improvement** | Fail-fast invariant enforcement via Kotlin `require`/`check`, throwing catchable `IllegalArgumentException` — including `TimeInRangeData`'s throw on inconsistent aggregate percentages and `FreshnessThresholds`' throw on an invalid pair | Failable or throwing initialisers, and a surface that degrades instead of dying. `precondition` and `fatalError` are prohibited for any value originating from a device, the **Backend** or a **Driver**; trapping is reserved for genuine programmer error (NFR-14) | Semantics preserved, mechanism changed: a trapping assertion would kill a monitoring app mid-background-wake (SI-2). The two Android `require()` sites would become traps in an idiomatic Swift port, so the divergence is deliberate rather than a defect port. Enforced by a SwiftLint custom rule (FR-208) and by FR-206 |
| PD-26 — | Moshi tolerates unknown fields and a missing consumed field surfaces at the use site | One shared decoder configuration used by both the networking layer and the contract tests, with Swift's synthesized `Codable` overridden so unknown fields are tolerated and a **missing consumed field fails loudly** (FR-155, FR-215) | Swift's default breaks SI-12 in the dangerous direction. Sharing one decoder object also removes the Android hazard of hand-copying the decoder configuration into the test and letting it drift |
| PD-27 — | The Medtronic handshake consumes `org.openminimed:javasake:0.2.0` and `org.bouncycastle:bcprov-jdk18on:1.84` as binary dependencies | A clean-room Swift reimplementation of the SAKE state machine, Session, SeqCrypt, KeyDatabase and DeviceType, with AES-CMAC per RFC 4493 over CommonCrypto | There is no JVM on iOS and no supported way to execute Java bytecode. GPL-3.0 permits the reimplementation outright; each Swift file cites its upstream OpenMinimed source exactly as the Kotlin port does, and palmarci's attribution carries into the iOS third-party licence bundle (FR-231, FR-232). Acceptance is byte-parity against OpenMinimed's captured 780G pairing trace |
| PD-28 **fix** | Both release build types silently fall back to the debug signing config when the release keystore variable is unset; only a post-build fingerprint assertion prevents a debug-signed "release" reaching patients | Manual signing pinned in a committed xcconfig, plus a hard-fail property assertion on the archive run **before** upload so a wrongly signed archive never consumes a build number (FR-184) | Automatic signing is the exact ambiguity that produced the Android defect. See PL-56 for what the fingerprint check could not become |
| PD-29 — | `versionCode` derived as `major*1_000_000 + minor*10_000 + patch`, with a permanent `DEV_RUN_NUMBER_OFFSET = 500` | A clock-derived monotonic build number plus a never-decreasing offset, with a documented `BUILD_NUMBER_OFFSET` escape hatch (FR-191) | App Store Connect requires strictly increasing build numbers per **Builder**, and a packed formula collides the moment a **Builder** archives locally before using the pipeline |
| PD-30 **improvement** | Watch-face APKs published debug-signed, deliberately carved out of the certificate assertion | No carve-out exists: every shipped artifact is signed by the **Builder's** own Distribution certificate and covered by the same assertion (FR-184, FR-189) | Consequence of PL-31/PL-61, and strictly better on the signing axis |
| PD-31 **improvement** | Wear data travels over the Wear OS Data Layer, which routes through Google Play Services | Phone↔**Watch app** transport involves no third-party service (FR-115, FR-134) | A genuine privacy improvement, recorded as such in the privacy document (FR-236) |
| PD-32 **fix** | No CI validation of documentation frontmatter or `pages`-array membership (a new page silently failed to publish); no link checker; a pull-request template CONTRIBUTING tells contributors to fill out that does not exist; a dangling `docs/dev/monorepo-port-ledger.md` reference; six inconsistent repository slugs across policy documents; the EC-JPAKE file carrying a prose port note but no Apache-2.0 identifier and no Particle Industries copyright | All closed: a page publication gate, a link checker, a real template, one canonical slug, and an SPDX identifier plus the required copyright travelling with the EC-JPAKE file (FR-219, FR-231) | Apache-2.0 §4 requires the notice travel with the file; the rest are silent-failure classes in the only product surface with no fallback if it is wrong |
| PD-33 **improvement** | Dependency-scan and build jobs declare no `timeout-minutes`; pip/go/tarball tool pins sit under no dependency manager and rot silently | Every lane declares an explicit timeout (FR-197); automated updates cover Actions pins, Swift packages, pinned analysis-tool versions and the pinned Xcode version via custom managers (FR-194) | A hung lane blocks merges indefinitely, and an unmanaged pin is an unpatched pin |
| PD-34 **improvement** | A plugin manifest id independent of the **Driver's** own metadata id, so the registry can key on one while the UI displays the other; a 65,536-char manifest size cap and a resource-shadowing hazard | Compile-time `PluginMetadata` is the single source of truth; there is no manifest (FR-21, FR-22) | The divergence hazard is permanently eliminated rather than guarded |
| PD-35 **improvement** | Versioned notification channels recreated to change a sound, guarded by a lock with a non-atomic increment hazard | Sound and interruption level are per-request properties; the whole recreation mechanism disappears (FR-67, FR-170) | The upside of PL-28: no channel-version state to corrupt |
| PD-36 **improvement** | `CalibrationTarget` is a declared **Capability** in the plugin API — the only member of the set that requires writing to a device — implemented by no shipped **Driver**, with no calibration screen and no validation path | Removed. The closed **Capability** set is exactly **six**: glucose source, insulin source, pump status, BGM source, data sync, bolus-category provider. There is no calibration case, no calibration protocol, no calibration slot and no slot-resolution branch; a **Driver** cannot declare it and the platform cannot resolve it (FR-30, FR-31). The published contribution contract and the disclaimer's permitted-operations list carry no calibration entry (FR-225, FR-234), and §11 NG-17 states the closure | Keeping it forced SI-1 — the strongest safety claim in this product — to carry a carve-out. With it removed, "no device command exists in any **Capability** protocol" is true unconditionally and is enforced by the FR-205 snapshot gate. A future CGM **Driver** needing calibration is a PRD change with its own safety review, not a slot left open |
| PD-37 **fix** | The raw device MAC address rendered unmasked as the **Pump** subtitle, in the discovered-device list and in the Settings card | No surface renders a device identifier at all. A **Pump** is a name and a model; the stored pairing record keys on an opaque per-installation identifier with a name/serial fingerprint as its recovery path, and no log line at or above debug level carries a peer identifier (FR-19) | SI-9. A hardware address is a persistent identifier for the patient's device, displayed for no user benefit and carried into every screenshot pasted into a support thread. The masking also makes the identity model honest: the visible name is not the key, so PL-8's recovery path is legible rather than surprising |
| PD-38 **fix** | `fallbackToDestructiveMigration()` as the schema backstop: an unhandled migration path or a downgrade silently wipes local **Pump** history | No destructive backstop exists. Every schema hop has an explicit, tested migration; an unmigratable store surfaces an explicit user-visible failure with a stated recovery path, and a failed migration leaves the previous store intact and readable by the previous build (NFR-15) | Silent deletion of the patient's own history is the worst failure a monitoring store can have, and it is invisible: the app simply starts empty. Under **fork-and-build** a **Builder** can and will install an older build, so a downgrade must not be a data-loss event |
| PD-39 — | The 30-day chart truncates at its oldest end once the series exceeds 2,000 rows | Identical: the same 2,000-row ceiling, the same oldest-end truncation, on the same chart (NFR-7, FR-52) | Recorded so the truncation reads as inherited Android behaviour rather than being discovered as an iOS bug. **No behavioural divergence.** Truncation stays silent to correctness but is never silent to the user where it changes what a chart means |
| PD-40 — | No localization at all: a single `values/` resource set, a 9-line `strings.xml` carrying 6 strings, every other user-visible string inline in Kotlin | English only in v1, stated as a position rather than an omission. All user-visible copy lives in localizable string resources per target and a lint gate fails a new inline user-visible literal (NFR-31) | **Matched — not a loss.** Neither client is localized, so "full parity" does not obligate iOS to internationalize. The resource discipline is a small improvement that makes a later translation a data change rather than a rewrite; the locale-independent number formatting (PD-12) may not be undone by a future translation without changing the log scrubber and the cross-surface fixture together |
| PD-41 — | Two Tandem decode gates exist only as parser code — required by no stated requirement, covered by no test: the `egvStatusId` byte of the CGM EGV response (cargo byte 6), and the selector byte of the 17-byte `ControlIQIOBResponse` (opcode 109), whose cargo carries two different insulin-on-board figures | Identical decode behaviour, stated as FR-32 consequences with pinned tests and Trace-Replay fixtures (FR-36). A reading is accepted only when `egvStatusId` is in 1…3 (1 = VALID, 2 = LOW, 3 = HIGH — all three carry a real glucose value) and is **discarded** for 0 (INVALID) and for 4 and above (UNAVAILABLE and any future value); all five cases are pinned. The IOB selector at cargo byte 16 resolves `0` = Control-IQ off → the Mudaliar IOB (bytes 0–3, milliunits), `1` = Control-IQ on → the Swan-6hr IOB (bytes 12–15, milliunits), any other value → the Mudaliar value; `0`, `1` and an unknown selector are pinned against a cargo whose two IOB fields differ | **No behavioural divergence** — parity is matched. The row exists so the port cannot drop either gate silently. Both failures produce a plausible, in-range, dosing-relevant number that no other check in this PRD catches: the validity gate is independent of the **Glucose Validity Bound**, so a warm-up or error sentinel landing inside 20–500 would render at hero scale, in a severity colour, Fresh, and be alertable (SI-2); and both IOB candidates sit inside every bound the product enforces, so selecting the wrong one misstates insulin on board with nothing to detect it (SI-7). §15 OQ-7 asks whether both belong in the Safety Invariant Register rather than in a **Driver**-general FR. A Medtronic equivalent of the validity gate must be identified before that **Driver** leaves Beta |
| PD-42 **improvement** | The trend glyph and the glucose value come from two SEPARATE **Pump** transactions — on Tandem the trend icon id (`cgmTrendIconId`) is read from the HomeScreenMirror response, opcodes 56/57, not from the EGV response that carries the value — but the 15-second foreground poll kept the two reads close, so the glyph is rendered beside the value with no provenance and no age of its own | The glyph carries its OWN source timestamp, is classified under the CGM policy (FR-49) against that timestamp, and renders at the WORSE of its own **Freshness Tier** and the value's, never a better one. A glyph whose own source is Too Stale, or absent entirely, renders as the unknown "?" glyph in the de-emphasised colour beside a value that may still be Fresh; the value's own tier, caption and severity colour are unaffected by the glyph's age (FR-46) | On iOS the two reads can land in different foreground activations, so the coupling Android bought with its poll is unavailable (PL-12) and no display rule can recover it. Without the split the dashboard would present a stale direction claim beside a fresh number, on the surface a user reads fastest and least carefully. FR-46 owns the rule for the whole PRD; any surface that renders the glyph renders it under these provenance rules or it reintroduces the failure |
| PD-43 — | A blood-glucose-meter reading from a BGM-source plugin reaches exactly one surface: the contributing plugin's own card. It enters no shared glucose surface — not the hero, not the chart, not Time in Range, not the statistics, not the alert path — and the only shipped consumer is the example plugin's own card | Identical. A meter reading is a distinct record type carrying its meter name and **Driver** id (FR-24); its only consuming surface is the contributing **Driver's** own dashboard card (FR-37, positioned in the **Driver**-contributed card region by FR-39), always labelled with its meter name and the word "meter" so it can never be read as a CGM value. It never enters the hero, the chart glucose series (FR-52), Time in Range (FR-58), CGM statistics (FR-59) or the **Alert Floor** (FR-71), and never sets, resets or refreshes a **Glucose Reading's Freshness Tier**; with no CGM **Glucose Reading** present the hero still shows "--" even when a recent meter reading exists (FR-46). The one place a meter reading may win against a CGM reading is the bolus glucose-at-event cross-reference, which selects on timestamp proximity alone and names the meter when it wins (FR-92). It is stored and marked as meter-sourced by FR-137 | **No behavioural divergence** — recorded as parity, not as an addition, because BGM source is one of the six **Capabilities** and a reader who finds a shipped BGM **Driver** with almost no dashboard presence would otherwise read it as an iOS omission and "fix" it. Two BGM sources may be active concurrently (FR-24), which is why the meter name travels on the reading rather than on the card. Keeping meter readings out of the **Alert Floor** and out of the **Freshness Tier** clock is what stops a fingerstick arming an alarm the sensor did not support or resetting a staleness timer the sensor owns (SI-5); keeping them out of Time in Range and the CGM statistics is what stops a fingerstick being counted as sensor coverage |
| PD-44 — | The **Backend's** analytics settings carry a bolus-category display-label override map keyed by computation role (`AnalyticsSettingsStore`), cached locally, rendered over the app's own category vocabulary, and cleared on sign-out | Identical, owned end to end by FR-89. The map is reconciled together with the day-boundary hour on every **Backend** reconcile pass (FR-40) and cached locally. Resolution is: the **Backend** label for that category when present and non-blank, else the app's own vocabulary (Meal+Corr, Correction, Meal, Auto Corr, Override, AI Suggested, Other). A response whose display-label list is absent leaves the cached map untouched; a response carrying an explicit empty list clears it; a label entry with no computation role is dropped rather than applied to an arbitrary category. In **Backend-optional mode** no map exists and the app's own vocabulary is always used. The map is cleared on sign-out together with the rest of the analytics settings (FR-167) | **No behavioural divergence** — a straight port, recorded because it is invisible in every screenshot and would otherwise be dropped as a **Backend** implementation detail. Two properties are load-bearing and are pinned by test: the map is presentation only — changing it moves no delivery between categories, changes no fixed-order position, and changes no total, count or percentage — and it is **not** a fallback for a missing **Driver** bolus-category provider **Capability**; the two mechanisms are independent (FR-89). Clearing on sign-out is what stops a departing account's labels rendering over the next account's data |
| PD-45 **fix** | Onboarding's Features copy promises "daily briefs, meal analysis, and pattern recognition", and the AI notification row is described as "AI analysis insights and daily briefs", while the client ships no brief view, no brief view model and no brief endpoint call — the **Backend** exposes brief endpoints the app never calls | The copy names only surfaces that ship: the meal capture and estimate flow (5.5), the AI Chat tab (FR-105), and the **Backend**-pushed insight delivered as a notification at the informational tier (FR-65). The Features card reads "With a connected server, get photo meal analysis, an AI chat, and AI insights delivered as notifications — powered by your choice of AI provider." (FR-159), and the AI sound row describes that notification rather than a screen (FR-170). Both strings are pinned by test | Porting the wording would promise a surface that does not exist, in the one place a first-run user forms their expectation of the product. The absence itself is preserved deliberately — no brief screen is added, because adding one is net-new work rather than a port (FR-105 Out of Scope) — so what changes is the promise, not the feature set |
| PD-46 **fix** | Three inconsistent validation regimes against the same 20–500 numbers: history extractors DROP readings outside the active limits, model constructors THROW (`require(… in 20..500)`), and the **Backend**-supplied alert-threshold path CLAMPS each value with `coerceIn(20, 500)` before checking ordering | Exactly two gates, each with one bound, each pinned by its own test, and no clamping path anywhere. **Driver**-level validation (FR-32) runs against the CURRENT, **Backend**-narrowable **Safety Limits** at every validation pass, so a narrowing changes which live readings a **Driver** accepts without a restart. Storage-layer rejection (FR-138) runs against the ABSOLUTE **Glucose Validity Bound** of 20–500 and never against the narrowed limits, at write and again at read. Out-of-bound is always rejection, never clamping (SI-2). **Backend**-mediated rows never pass a **Driver** validation pass at all, so they are only ever bounded by the absolute 20–500 | The asymmetry is deliberate and has to survive the reader who finds it: a stored row must not be retroactively invalidated by a later narrowing, so the store cannot adopt the **Driver's** bound; and a narrowing must take effect on live readings without a restart, so the **Driver** cannot adopt the store's. The visible consequence is stated rather than inferred — a narrowing changes which NEW **Driver**-sourced readings enter Time in Range, GMI, CV, the chart and the **Alert Floor's** input set, and leaves already-stored readings in all of them (FR-138) — and both tests name the asymmetry so a future reader does not "fix" one bound into the other (SI-11). PD-8 records the two deprecated-adapter defects that made a silent widening possible; this row records the asymmetry itself, so a reader scanning for it does not have to find it inside PD-8's rationale |

---

### 7.3 Additive substitutes (PA)

| ID | What | Why it exists | Android capability it compensates for |
|---|---|---|---|
| PA-1 | **Live Activity on the Lock Screen and Dynamic Island**, carrying glucose, trend, **Freshness Tier**, **Pump**-link state and the **Coverage Claim**, with a `staleDate` that self-degrades and no stale reading left on screen when the OS ends it (FR-119, which owns this surface; FR-20 requires only that **Pump**-link state is one of the values it carries) | The only iOS primitive that is glanceable, out-of-app and rich. Bounded at roughly 8 h active plus about 12 h on the Lock Screen, user-dismissible, so it may never be the sole carrier of the claim | Partially compensates PL-15 (the permanent foreground-service notification) and PL-16 |
| PA-2 | **WidgetKit accessory complications on watchOS** in every family that can render honestly — glucose, IOB, sparkline, coverage/alert indicator, AI Chat entry — plus the same widgets in the Watch Smart Stack (FR-117) | The only way our data reaches an Apple watch face | Compensates PL-31 and PL-37, partially |
| PA-3 | **iPhone Lock Screen and Home Screen widgets** rendering the same values, the same **Freshness Tier** treatment and the same **Coverage Claim** states from the same render functions, with full-colour banding where the OS permits it (FR-119) | Net-new glanceable surface; also the only place, alongside the **Watch app's** own screens, where the full seven-layer overlay graph survives | Partially compensates PL-34 |
| PA-4 | **Pre-baked decay timelines**: every time-driven transition scheduled as a future timeline entry when data arrives — Fresh→Stale→Too Stale, IOB ageing, and **Coverage Claim** expiry — so the wrist degrades correctly with the app force-quit, powered off or out of range, at zero refresh budget (FR-122) | iOS gives no periodic execution, so decay must be pre-computed rather than driven | Compensates PL-12, PL-16, PL-35 |
| PA-5 | **Proactive coverage-lapse notification (dead-man's switch)**: on every wake, cancel and re-schedule a single local notification for the current claim's `validUntil`. If the app runs again it never fires; if the app dies it fires (FR-85) | Silence becomes the alarm. The only mechanism that can interrupt a user when no application code is running | Compensates PL-13, PL-14, PL-15 |
| PA-6 | **Watch-scheduled wrist alerts and a locally scheduled 30-minute (1,800,000 ms) re-alarm ladder that terminates when the reading ages past Too Stale** (FR-128, FR-129) | Wrist delivery must not depend on iPhone lock state or on mirroring, and the ladder must keep running if the app is force-quit or loses Bluetooth — but must never alarm forever off a frozen snapshot | Compensates PL-26 and, partially, PL-13 |
| PA-7 | **The Simulated Driver as a shipped, first-class Driver** in the **Driver Catalog** — realistic synthetic data, no Bluetooth, subject to every gate and to the **Safety Constant** drift guard, exercising the full non-Bluetooth **Driver** surface (FR-35, FR-207) | Core Bluetooth does not exist in the Simulator and the lead developer has no iPhone and no Apple Watch (context 10). Android's `plugins/example` is a standalone JVM project outside `settings.gradle.kts`, so this is net-new engineering, not a port, and it is on the critical path | Compensates PL-68; it is also the reference implementation contributors copy (UJ-6) |
| PA-8 | **The Trace-Replay Driver as a shipped, first-class Driver** — replays recorded, de-identified real-**Pump** frames through the production parsers, deterministically, with fixtures versioned alongside the parsers (FR-36, FR-206) | Proves rejection-not-clamping (SI-2) and that the history cursor never advances past an undecoded record (SI-8) with no radio and no **Pump** | Compensates PL-68 |
| PA-9 | **The fork-and-build pipeline as a supported product surface** — CODEOWNERS-gated, SHA-pinned, inside SECURITY.md response scope, with a fixed documented secret set, isolated credential validation, a distribution-signing hard fail, and an explicit **Builder** boundary for key custody, Apple account state, certificate lifecycle and the 90-day rebuild (FR-179–FR-196, settled decision 6) | There is no project-published binary, so the pipeline **is** the distribution mechanism and must be engineered as product, not as internal tooling | Compensates PL-53; it is also the affordance that replaces PL-40 for running an unmerged **Driver** |
| PA-10 | **Scheduled rebuild workflow, enabled by default in every fork**, plus in-app build provenance, channel, source tag, 7-character commit SHA and a days-to-expiry countdown with escalating prominence (FR-186, FR-187) | Android has no expiry to surface. Without this, a **Builder's** glucose monitor stops launching with no warning | Compensates PL-54, PL-55; the provenance stamp partially compensates PL-62 |
| PA-11 | **Simulator-tier validation as a named tier** — full behavioural exercise of app, **Watch app** and widget extensions against the **Simulated Driver**, XCUITest on both Simulator destinations with a published result bundle, and documentation of exactly what cannot be exercised this way (FR-207, FR-209, §9) | The lead developer's entire loop is the Simulator; without a named tier, Simulator-green would be mistaken for validated | Compensates PL-68; bounds the claims that may be made from Simulator results |
| PA-12 | **Developer fault-injection surface**, compiled out of release builds with a CI check asserting unreachability: synthetic **Glucose Readings**, forced **Backend** unreachability, a compressed **Freshness Tier** policy (20,000 ms / 45,000 ms) substituted at exactly one swap point, forced alert firing, and immediate **Coverage Claim** expiry (FR-176 owns the surface and the release-build gate; FR-88 adds the two alerting-specific injections) | Every alerting, freshness and coverage path must be reachable without a **Pump**, a **Backend** outage or a six-hour wait | No Android counterpart; it is what makes PA-7 and PA-11 sufficient |
| PA-13 | **Guided complication setup with active-face detection** — the app enumerates each widget kind and its steps, and states plainly when none of ours is on the active face (FR-118) | Placement belongs to the user and to watchOS, so the app must teach placement and detect its absence rather than assume it | Compensates PL-31, PL-32, PL-37 |
| PA-14 | **Verification Status as declared per-Driver metadata** (Verified / Protocol-Implemented / Beta), rendered in the **Driver** list and cross-checked in CI against the Device Verification Matrix (FR-22, §8) | Android carries no equivalent field. Under compile-time linking there is no install-time moment at which to warn about trust | Replaces the "Custom plugins are not verified by GlycemicGPT" install warning lost with PL-40 |
| PA-15 | **Scrubbed diagnostic log export** — a bounded in-memory buffer with four scrubbing rules applied before emission and again before export, user-initiated, showing the user what it contains before sharing (FR-158) | iOS gives users no way to read an app's system log; a **Builder** or tester reporting a bug otherwise has nothing to send (UJ-3). Android users have `adb logcat` | No Android counterpart; it exists because the Android debugging affordance (`adb logcat`) does not survive the port. Upholds SI-9 |
| PA-16 | **Driver Catalog registration assertion inside the `iOS Gate` Required Check** (FR-197), asserting the Catalog's exact expected set of ids, plus a **Driver** protocol public-interface snapshot gate (FR-21, FR-205) | Swift cannot enumerate protocol conformances, so registration must be asserted rather than derived | Compensates PL-42 (Hilt `@Binds @IntoSet` registration-by-compilation) |
| PA-17 | **Entitlements, Plist, signing-material and build-script guard** (FR-204) and the **Contract Pin** guards for version agreement, endpoint presence and field presence (FR-214) | Apple ships no manifest linter, and non-grantable entitlements must be kept out of the committed entitlements file entirely so no fork's build breaks on an entitlement its owner cannot obtain | Compensates PL-65; see §10 for the full substitution mapping |
| PA-18 | **Internal entry-point routing** — a widget, complication, Smart Stack entry, Live Activity or notification tap resolving to a specific in-app destination, including a chat entry point whose prefill is truncated to 500 characters (FR-63, FR-105, FR-114, FR-117, FR-119) | Every glanceable surface iOS gives us is inert without a route into the app behind it. The route travels the system's own widget/complication URL mechanism, which only the app's own extensions can populate; the app registers **no** custom URL scheme that accepts data from another app and ships no share extension, so none of these is a third-party input surface (NFR-22). **Backend**-only destinations stay registered so a restored path resolves, and redirect to Home when no **Backend** is configured | **None — entirely net-new scope.** Android registers no deep links, no `ACTION_VIEW` intent filter, no `AppWidgetProvider`, no `TileService` and no `ShortcutManager`. This is additive, not parity restoration; it exists only because PA-2 and PA-3 exist |

---

### 7.4 Notes

**Disclosure surfaces.** Every forced loss above names the product surface where the user is told, and every one of those surfaces is now required by an FR. Five of them are told on a published documentation page rather than in the app — PL-1, PL-2, PL-8, PL-10 and PL-52 — and each cites **FR-237** (5.12), which requires the pairing-troubleshooting page and the iOS status-icons page to exist and to carry those exact statements. They previously cited FR-220, which requires no page to exist and no statement to appear on one — and whose basename-collision premise is itself void (see the PL-70 retirement note). A sixth, **PL-63**, is told on the install runbook and cites **FR-223**, whose prerequisites gate carries the macOS-minutes statement.


**FR-237 is scope, not an overrun.** It was created to close a real defect — five forced-loss rows named a disclosure surface no FR required to exist — and it stands. The published scope of this PRD is **FR-1 through FR-237**; 5.12's allocated range is FR-219 through FR-237. Nothing is renumbered, and the five citations above plus FR-19's in-app statement resolve against it as written.

`[NOTE FOR PM]` **Forced losses whose disclosure is carried by the wrong requirement:**
- **PL-72** (honest gaps in the log export) — CLOSED. FR-158 now carries the statement on the artifact itself ("The export states its own gaps, on the artifact"), so the disclosure is required by the FR that owns the export, not only by NFR-33.
- **PL-3, PL-7, PL-38, PL-48, PL-49** are recorded with no user-facing disclosure on the grounds that they have no user-visible impact beyond states already disclosed elsewhere. Confirm that reading.
- **PL-39, PL-42, PL-43, PL-57, PL-61, PL-64, PL-65, PL-66, PL-67, PL-68 and PL-71** disclose to a **Builder** or a reviewer rather than to a patient: their surfaces are §9, §10, the published iOS security-testing page, required by FR-237 (5.12) and the contributor documentation. No end-user copy is owed for any of them; PL-71 additionally reaches the user through FR-236. Confirm that reading once, rather than per row.
- **PL-44** (chart-detail landscape on iPad) depends on 5.3's open question of whether iPad is a supported target at all.
- **PL-45** (the draggable meal button) is the one row in the forced-loss table that is a platform-fit choice rather than a hard platform bar. Confirm whether it belongs in PL or in PD.

`[NOTE FOR PM]` **Rows that overlap by design and must not be de-duplicated:** PL-13/PL-14 (force-quit and reboot are different mechanisms with the same outcome and different remedies); PL-15/PL-16 (surface permanence vs claim cadence); PL-23/PL-24 (entitlement vs volume API — a reader who conflates them will assume Critical Alerts would restore the boost, which it would not); PL-53/PL-58 (no binary vs the paid-membership barrier); PL-71/PL-72 (never receiving a report at all vs the gaps inside the report the user does send); PD-8/PD-46 (the deprecated adapters that made a silent widening possible vs the two-gate asymmetry itself, which a reader must be able to find without reading PD-8); PL-12/PD-42 (the lost refresh cadence vs the one display rule that cadence was silently holding up).

`[NOTE FOR PM]` **PD-14, PD-39, PD-40, PD-41, PD-43 and PD-44** record preserved behaviour, not changes: the severity-banding edge case, the 30-day chart's oldest-end truncation, the absence of localization on both clients, the two Tandem decode gates, the BGM-source consuming surface, and the **Backend**-synced bolus-category label map. They are in the ledger because it is the single place a reader learns what differs, and "this looks like a bug and is deliberately kept" — or, for the last three, "this is barely visible, so it was probably dropped" — is exactly the kind of thing that gets silently "fixed" on one platform later.

`[NOTE FOR PM]` **PD-42 is conformed.** FR-46 owns trend-glyph provenance and 5.7 now carries it by cross-reference: the wrist renders the glyph at the worse of the two Freshness Tiers and degrades it independently of the value. This note previously requested that edit and was left stale after it was applied — which caused a later reviewer to re-report the closed defect as an open wrist-safety bug.


`[NOTE FOR PM]` **PD-13** is the one divergence in this table still awaiting confirmation before it is pinned by test: the **Glucose-Reading**-at-event column rendering in the user's display unit. PD-19 (alert-history retention) and PD-23 (the two queue constants) were open in the parallel draft and are now settled — the retention window follows the user's setting and the queue bound is 20,000 rows — so neither carries an assumption any longer.

**Open questions carried into §15** (§15 owns their `OQ-n` identifiers; this list does not number them):
- Medtronic transport spike (b) — whether a 780G's discovery filter accepts an iOS advertisement carrying the identity as a standard GAP local name rather than as manufacturer data (PL-4). Needs a physical **Pump**; neither the lead developer nor DanielDanielson has one. Left open for a community validator per settled decision 5.
- Whether an already-bonded Medtronic **Pump** reconnects to a backgrounded iPhone by stored peer identity rather than by name. If it does, PL-6's degradation is narrower than stated. Untestable without hardware.
- **The `Info.plist` App Transport Security posture that achieves FR-150 / NFR-20 (PL-50).** Whether `NSAllowsLocalNetworking` covers raw private-IP literals rather than only single-label and `.local` names is unverified, and `NSAllowsArbitraryLoads` is ignored in its presence. This is an architecture decision requiring empirical verification; until it lands, no section may state a plist posture as settled, and FR-204's guard baselines on the committed file. The product requirement itself is not open.
- Whether FR-76's phone ladder (PD-15, 5 repeats at 120 s) survives a real-user tuning pass before the first tagged release. It is invented, not ported. The wrist's 30-minute ladder (FR-129) is a separate parameter.
- Whether side-by-side stable and development installs (PL-60) is a real product requirement, since it changes what FR-182 registers for every **Builder**.
- Whether the **Watch app** is given an independent **Backend** data path so the wrist has data when the iPhone is dead — which would put a **Backend** credential in the Watch Keychain and create a second freshness semantics.

**Closed since the parallel draft, and deliberately absent from §15:** the **Keychain** accessibility class (device-only, after-first-unlock — PD-24) and the deployment floor (iOS 17.0 / watchOS 10.0, NFR-1). Both are settled; neither is an open question in this ledger or anywhere else.


## 8. Per-Device Verification Matrix and Status Vocabulary

This section defines the three Verification Status words, the evidence each one requires, the product gating each one implies, and the table that is the project's single authority on which device is at which status. FR-22 renders a Driver's Verification Status in the Driver list; FR-234 publishes the same statuses in the README table. Both are cross-checked in CI against **this** table.

### 8.1 Status vocabulary

| Verification Status | Evidence required | Product gating implied |
|---|---|---|
| **Verified** | The Driver has been exercised on physical iOS hardware — an iPhone, plus an Apple Watch where any wrist surface is in scope — against a physical instance of the exact Pump model named in the row, by a **named** validator, on a **stated** date, from a build that validator produced from their own fork under their own Apple Developer account (decision 3, decision 9, FR-179, FR-183). This is Validation Tier 4 evidence and nothing else counts, and the evidence takes exactly one form: a completed run of the single written hardware-validation checklist FR-207 requires, committed alongside this table. | No gating copy beyond the standing medical disclaimer and the untested-device clause (FR-234). The Driver may be presented as an ordinary monitoring path. The Verification Status still says nothing about firmware revisions, iOS versions or hardware models other than those recorded. |
| **Protocol-Implemented** | The protocol is fully implemented and passes Tier 1 and Tier 2: the Driver builds into the **Driver Catalog**, runs end to end in the Simulator against the **Simulated Driver** harness (FR-207), and passes FR-206's per-Driver protocol tests over recorded frames — framing, byte order, event-type ID mapping, multi-packet reassembly, connection state machine, **Glucose Validity Bound** rejection, cursor non-advance on decode failure. No one has run it against the physical device on iOS. | Shipped and selectable. The Driver list row, the pairing copy and the README table all read *unverified on hardware*, with an empty validator and an empty date. Nothing in-product may imply the device has been tested. |
| **Beta** | Implemented, but with a **named** unproven element: an unvalidated transport assumption, an iOS platform constraint that structurally degrades the flow, or an absent recorded-frame corpus. The named element is written into the Gating column of this table, not left as a vibe. | Shipped present-but-gated. The Beta label appears in the Driver list (FR-22), in the pairing copy, and in the README table (FR-234). Documentation states the Driver is not suitable as a sole monitoring path on iOS (FR-16). Where a compile-time kill switch exists (FR-27), the switch is the escape hatch, not a silent removal. |

Three further rules bind the vocabulary:

- **Status is per-device-model, never per-Driver.** The Tandem Driver serves both t:slim X2 and Mobi; the two models carry separate rows and may carry different statuses. Evidence about one model is not evidence about the other.
- **No status is inherited from the Android table, at any point** (FR-234). The iOS Bluetooth stack is a different code path; an inherited "Verified" would be a safety claim about software nobody has run.
- **The Simulated Driver and the Trace-Replay Driver can never be Verified.** Verified requires a physical device and a named hardware validator. Neither has a device to validate against, so both sit permanently at Beta by construction — which is also the honest signal that they are not clinical data sources.

### 8.2 The raise rule

**A Verification Status may only be RAISED by evidence recorded in the table in §8.3.** The record is a named validator plus a stated date plus the hardware and OS versions used, and the underlying evidence is a completed run of the written hardware-validation checklist FR-207 requires; a status change without that record is not a status change. A status may be LOWERED at any time by anyone, with no evidence and no ceremony — a suspicion is sufficient grounds to demote, because demotion cannot make a false safety claim.

Corollaries:

- A row whose validator and date cells are empty cannot read Verified. That is a mechanical check, not a judgement call.
- CI fails if a Driver's declared Verification Status metadata (FR-22) disagrees with this table, or if the README table (FR-234) disagrees with either.
- Evidence recorded against one iPhone model, one Apple Watch model and one iOS/watchOS version pair is exactly that. It does not generalize, and the table records what was actually used rather than implying a range.
- **The raise rule rests on one named person.** Tandem t:slim X2 — the only row that can reach Verified in v1 — can be raised only by **DanielDanielson (they/them)**, who holds the sole iPhone + Apple Watch + t:slim X2 combination on the project and is the sole executor of Validation Tier 4. **fork-and-build** forbids the obvious substitute: the project cannot hand a build to another validator without conveying a binary (decision 3). This is a single point of failure stated as such, not a staffing footnote; §9.4 records the failure modes and the mitigations.

*[NOTE FOR PM]* Whether a change to a Driver's protocol or transport code automatically demotes that Driver's row from Verified pending re-validation is unresolved and is already flagged as an open question in 5.2 and carried into §15. It matters more here than it looks: under the raise rule, an automatic demotion is cheap to apply and expensive to reverse, because reversal needs another Tier 4 session from the one person who can run them (§9.4).

### 8.3 The iOS device table

| Device | Connection | Verification Status | Validated by / on | Gating |
|---|---|---|---|---|
| **Tandem t:slim X2** | Phone-scans-and-connects. The app is the Bluetooth central; it scans for the Pump's service, the user taps a Pump and types a 6–16 character pairing code read off the Pump screen (FR-4, FR-5). | **Protocol-Implemented** today, and the only device that can reach **Verified** in v1. The row reads Verified only once the validator and date cells carry a completed checklist run (§8.2, FR-207); empty cells read Protocol-Implemented, mechanically. | **DanielDanielson (they/them) — the single point of failure named in §8.2.** iPhone + Apple Watch + t:slim X2, building from their own fork under their own Apple Developer account and installing via their own TestFlight. Date, iPhone model, Watch model and iOS/watchOS versions recorded at validation. No second validator exists for this row, and the project never conveys a binary, not even to a hardware validator. | None beyond the standing disclaimer, the untested-device clause, and the alert-delivery conditions of FR-234. The forced parity losses of decision 4 and decision 7 apply to this row as to every other: `.timeSensitive` urgent-low alerts can be silenced by the ring/silent switch undetectably, and **Backend**-generated alerts do not reach a suspended or terminated app in v1. |
| **Tandem Mobi** | Phone-scans-and-connects, same Driver and same protocol as the t:slim X2; the model is detected from the advertised name. The Mobi has **no screen**, so the pairing code comes from the printed PIN behind the cartridge well after a charging-pad double-press (FR-5). | **Protocol-Implemented** | None. Nobody on the project has a Mobi. | Shipped and selectable; labelled *unverified on hardware* in the Driver list, in the pairing copy and in the README. Two model-specific paths carry no evidence at all on iOS: the no-screen pairing-code instruction path, and the battery read, where the V1 opcode is deliberately tried first and the V2 opcode is the fallback — because V2 kills the connection on a t:slim X2 while the Mobi needs V2 for its charging flag. That ordering has been observed only on Android. |
| **Medtronic MiniMed 680G / 770G / 780G** | Phone-advertises-and-waits. The app is the Bluetooth **peripheral** and the Pump is the central: the app advertises under a fixed name matching the Pump's `Mobile .{0,7}` matcher, the user selects that name on the Pump, and no code is entered (FR-6). A second client link back to the Pump is then required, because the CGM, IDD, battery and device-information data live only on the Pump's own GATT server. | **Beta** — present-but-gated, matching the Android repository's own label for these models. | None. Nobody on the project has a MiniMed 700-series Pump. | Shipped present-but-gated behind the compile-time kill switch (FR-27) — a gated-off Driver is excluded from the shipped binary by a compilation condition, and CI separately builds a configuration with every Driver's gate enabled so the gated code stays compiled and test-covered (FR-189, FR-208). Documented as not suitable as a sole monitoring path on iOS (FR-16). Named unproven elements, both of which are the split transport spike of §8.4: (a) whether Core Bluetooth can yield a usable `CBPeripheral` for the central that connected to our `CBPeripheralManager`; (b) whether the Pump's discovery filter accepts an iOS advertisement that carries the identity as a standard local name rather than as manufacturer data — iOS emits no manufacturer-specific data from the peripheral role at all. Additional standing degradations, stated in-product and not hidden: first pairing **and** every re-establishment are foreground-only, because a backgrounded iOS advertiser has its local name stripped and its service UUIDs moved where only Apple devices can read them; Android's "the pump is remembered — GlycemicGPT reconnects on its own" is false here and is not carried over. |
| **Simulated Driver** | None. No Bluetooth, no radio, realistic synthetic data. | **Beta**, permanently. | Not applicable — no device exists to validate against, so no validator can be named. Exercised continuously at Tier 1 by CI and by every contributor. | Shipped in every configuration including release, in the **Driver Catalog** and the Driver list like any other Driver, subject to the same compile-time exclusion (FR-27) and to every gate in 5.11 including the **Safety Constant** drift guard. Must never be presented as a clinical data source, and its Beta label is the user-visible half of that. |
| **Trace-Replay Driver** | None. Replays recorded real-Pump frames through the production parsers. | **Beta**, permanently. | Not applicable, as above. Its committed fixtures are de-identified before commit — glucose values, insulin doses and serial numbers synthesized or offset — because the repository is public under fork-and-build. | Shipped, kill-switchable, Beta permanently. Load-bearing asymmetry: the frames it replays **are** evidence for a *device* row's Tier 2 coverage, but replaying them is never evidence for this row's own status, and a green Trace-Replay run never raises any device row above Protocol-Implemented. |
| **Nightscout source (Backend-mediated)** | Not a device and not a Bluetooth Driver. HTTPS to the user's own **Backend**, which is the sole path by which Nightscout-sourced data reaches the app. No Nightscout URL and no Nightscout API secret exists anywhere in the app or its storage (decision 8, FR-38, FR-153). | **Protocol-Implemented** — and it can never reach Verified, because Verified requires a physical device and a named hardware validator and there is neither. | Not applicable. Its evidence is the **Contract Pin** guards (FR-214) over the byte-for-byte vendored **Backend** OpenAPI plus round-trip tests, not hardware. | Declares the data-sync **Capability** only, which is multi-instance, so activating it can never evict a Pump Driver's glucose-source, insulin-source or pump-status slot (FR-38). Absent by construction in **Backend-optional mode**. Every ingested row carries its source marker, so a Nightscout-sourced reading stays distinguishable from a Driver-sourced one after the fact. |

### 8.4 Medtronic: the split transport spike

Decision 5 splits the Medtronic transport question into two, deliberately, because the two halves have different costs and different owners:

| Spike | Question | Needs a Pump? | Tier | Owner | Status |
|---|---|---|---|---|---|
| (a) | Can Core Bluetooth return a usable `CBPeripheral` for the central that just connected to our `CBPeripheralManager`? Primary path: `retrieveConnectedPeripherals(withServices:)`. Fallback: `retrievePeripherals(withIdentifiers:)` keyed on the `CBCentral` identifier — widely observed to work, nowhere documented or guaranteed by Apple. | **No.** Two Core Bluetooth peers suffice; the Pump's central role can be played by any stand-in. | 3 | Lead developer | **Done first.** It is the highest-risk unknown in the Medtronic port: every parser and reader below it is worthless if the client link cannot be established, so it is answered before any of them is built. |
| (b) | Does a 780G's discovery filter accept an iOS advertisement carrying the identity in `CBAdvertisementDataLocalNameKey` plus the mode-appropriate service UUID, with no manufacturer-specific data? | **Yes.** | 4 | **Open — left for a community validator.** Neither the lead developer nor DanielDanielson has a MiniMed Pump. | Unresolved, and it is the reason the Medtronic rows stay at Beta. Supporting inference only: Medtronic's own iOS app pairs with these Pumps under the identical Apple restriction, so the Pump's filter cannot *require* manufacturer data. Inference is not evidence and does not satisfy the raise rule. |

*[ASSUMPTION]* Spike (a) runs at Tier 3 on macOS Core Bluetooth with a second Core Bluetooth peer standing in for the Pump's central role. If macOS and iOS diverge on `CBCentral`-to-`CBPeripheral` resolution, the spike re-runs at Tier 4 and its answer does not transfer.

---

## 9. Validation Tier Model

Four tiers. Each proves a strictly different class of property, each is executed by a different set of people, and the cost per tier rises by roughly an order of magnitude while the population able to run it shrinks to one. The model exists because the usual iOS assumption — "it works in the Simulator" — is false for this app in ways that are invisible rather than noisy.

### 9.1 The four tiers

| Tier | What runs there | What it PROVES | What it CANNOT prove | Executed by |
|---|---|---|---|---|
| **Tier 1 — Simulator + Simulated Driver** (the daily loop) | `swift test` over the platform-independent Driver, domain, unit-conversion, **Contract Pin** and **Safety Constant** modules (FR-210); `Build & Test` for phone, **Watch app** and widget extension with `-warnings-as-errors` and Swift 6 strict concurrency (FR-208); `UI Tests (Simulator)` on both iOS and watchOS destinations (FR-209); FR-207's full path against the **Simulated Driver** — ingestion, **Freshness Tier** classification, **Alert Floor** evaluation, **Coverage Claim** derivation and decay, phone-to-Watch rendering; **Driver Catalog** registration, **Capability** eviction, **Safety Limits** narrowing, card and detail rendering; every §10 gate. | Everything that is not radio-, entitlement-, background-scheduler- or notification-delivery-dependent. All pure decision logic and every boundary pair in it. **WatchConnectivity is exercisable here**: the watchOS Simulator does pair with the iOS Simulator, so session activation, reachability, application context and user-info transfer run for real — which is what makes FR-116's claim (every wrist surface demonstrable in the Simulator) achievable by a developer with no iPhone and no Apple Watch. | **Core Bluetooth does not exist in the iOS Simulator.** `CBCentralManager` reports state `.unsupported` and never reaches `.poweredOn`; `CBPeripheralManager` is equally absent. No BLE code path executes at all — no scan, no advertise, no GATT, no pairing handshake, no bond, no state preservation and restoration. Also unprovable: entitlement resolution and signing (Simulator builds are unsigned and entitlements are not validated against a profile); background execution budgets; notification delivery under Focus, Do Not Disturb, notification summary or the ring/silent switch; complication and widget refresh budgets; always-on display legibility; Low Power Mode; Keychain after-first-unlock behaviour across a real device lock; Data Protection behaviour while locked. See §9.2 — several of these do not merely go untested, they pass falsely. | Anyone with a Mac and Xcode: the lead developer, every contributor from a fork, and CI on `macos-latest`. |
| **Tier 2 — Trace replay against recorded Pump frames** | FR-206's per-Driver protocol tests, behind the transport seam, over committed de-identified byte traces: framing and CRC, little-endian decoding for the Tandem protocol, event-type ID mapping, multi-packet reassembly including the documented idle timeout, the connection state machine, history-cursor non-advance on a frame that failed to decode (SI-8), rejection rather than clamping of glucose outside the **Glucose Validity Bound** (SI-2), completed-deliveries-only filtering (SI-7), and Tandem epoch offset `1199145600` decoding across non-UTC zones in both hemispheres and a DST spring-forward gap. The Medtronic SAKE handshake replays through a deterministic queued RNG asserting stage-by-stage byte parity and tamper rejection. | Everything the wire format determines, deterministically, with no radio. This is where the majority of what Android enforced only through a non-blocking reviewer's judgement (the "BLE Protocol Safety" check) becomes an executable check. It is also the only tier a fork contributor can use to prove a Driver they wrote is correct (UJ-6). | That the trace corpus resembles the device's real behaviour — it proves only that the parser matches the frames someone recorded. Nothing about timing, connection-interval negotiation, MTU behaviour, bond loss, encryption failure, reconnect backoff, Core Bluetooth delegate and queue semantics, or state restoration. And a device family with **no recorded frames** has no Tier 2 coverage at all: today that is Tandem Mobi and every Medtronic model, which is precisely why those rows are not Verified. | CI on every pull request, and any contributor via `swift test`. No Xcode, no Simulator, no network, no account. |
| **Tier 3 — macOS bench against a real Pump** | A macOS host target linking the same Driver module and driving real Core Bluetooth on the Mac's own radio against a physical Tandem t:slim X2: scan and discovery filtering on the Pump's service UUID, connection bring-up, MTU and connection-parameter behaviour, the live pairing and authentication handshake, live status reads, history paging and cursoring. Also Medtronic spike (a) (§8.4), which needs no Pump. **This tier is the only source of new recorded frame corpora**, which feed Tier 2. | That the protocol implementation talks to a real device — the one thing Tiers 1 and 2 structurally cannot show. It is the cheapest place to find a protocol error, and it can be run repeatedly, at will, by the person who writes the code. | Anything iOS-specific. macOS Core Bluetooth is not iOS Core Bluetooth: there is no iOS background execution model, no state preservation and restoration, no App Switcher force-quit suppression, no **Watch app**, no entitlements or provisioning, no notification delivery, no Focus, no Low Power Mode, no Data Protection while locked, no TestFlight. A green Tier 3 says the bytes are right. It says nothing whatever about whether the app monitors overnight. | The lead developer, who has a Mac, an Apple Developer account and a Tandem t:slim X2, and **no iPhone and no Apple Watch** (decision 10). |
| **Tier 4 — On-device hardware smoke** | The written hardware-validation checklist **required and owned by FR-207**: one committed, CODEOWNERS-held document, executable by any Builder holding the hardware, whose completion is a documented release gate rather than a CI status and is explicitly not one of the five **Required Checks** of FR-197. Sections contributing items (5.1, 5.4, 5.7) contribute to that one list; this section defines no second list. Contents: pairing, re-pair and unpair on real hardware; Core Bluetooth state preservation and restoration after a genuine background relaunch; overnight reconnection while the device is locked, which is what SI-10's after-first-unlock Keychain class exists for; the **Alert Floor**'s achievable background evaluation cadence (FR-86); urgent-low delivery at `.timeSensitive` under Focus, Do Not Disturb, notification summary and the ring/silent switch — **including confirming that the alarm can in fact be silenced and that the app cannot detect it** (decision 4); Watch complication refresh budgets and the metered-allowance behaviour of FR-122; **Coverage Claim** render-and-decay on the wrist across a real disconnection (SI-6, FR-126); force-quit suppression (FR-15); Low Power Mode; the 90-day TestFlight expiry and rebuild (FR-186). | Everything that only exists on real hardware under the real OS — which is, unhelpfully, the set of properties on which patient safety actually depends. It is the sole evidence class that satisfies the §8.2 raise rule for **Verified**. | Any device nobody owns. Tier 4 covers exactly one Pump model (Tandem t:slim X2), one iPhone model, one Apple Watch model and one iOS/watchOS version pair at a time. It proves nothing about Tandem Mobi, nothing about any MiniMed model, and nothing about OS versions other than the one recorded. | **DanielDanielson, alone.** They build from their own fork under their own Apple Developer account and install via their own TestFlight; they are never a tester on a project-held TestFlight, because that would make the project convey a binary (decision 3, decision 9). |

### 9.2 What Tier 1 falsely passes

The Simulator does not merely fail to test the properties that matter most — it **passes** several of them, green, and the failure surfaces only on hardware and often only after hours. Treating a green Tier 1 run as evidence about any of the following is a category error:

| Property | Simulator behaviour | Hardware behaviour | When it fails |
|---|---|---|---|
| Entitlements | Not validated. Simulator builds are unsigned; an entitlement the signing team does not hold is simply never checked. | Signing resolves entitlements against the provisioning profile. A non-grantable entitlement fails the build for every Builder — which is exactly why FR-204 forbids `com.apple.developer.usernotifications.critical-alerts` from ever appearing in a committed entitlements file. | At sign time in a Builder's fork, not upstream. |
| Background execution | Background tasks are triggerable on demand from the debugger with no budget and no throttling. | The scheduler decides, weighted by usage, battery, Low Power Mode and thermals. There is no guaranteed periodic execution. | After hours or days of real backgrounding on a rarely-opened app. |
| Notification delivery | Authorization is granted freely and notifications appear with no Focus filtering, no summary batching and no ring/silent gate. A `.timeSensitive` urgent low always shows and always sounds. | Focus, Do Not Disturb, notification summary, per-app settings and the ring/silent switch all apply. `.timeSensitive` is not `.critical` and can be silenced without the app knowing. | Overnight, in exactly the scenario UJ-2 exists for. |
| Complication and widget refresh | Reloads are effectively unbudgeted. | A metered daily allowance applies; exhausting it degrades delivery. FR-122 reads the remaining allowance at runtime and never hardcodes it. | After a day of normal use, not in a test run. |
| Core Bluetooth | Absent entirely — `.unsupported`, never `.poweredOn`. This one at least fails loudly rather than falsely. | The whole transport, plus state restoration, bonding, and relaunch-into-background. | Immediately on hardware; never in the Simulator. |
| Data Protection and Keychain | File protection and Keychain accessibility classes are not meaningfully enforced against a locked device. | `NSFileProtectionComplete` would fail background writes while locked; a `WhenUnlocked` Keychain class would break overnight reconnection (SI-10). | Overnight, silently, as missing data rather than as an error. |

Two consequences follow and are binding on how this project is developed. First, no Tier 1 result may be cited as evidence for a Verification Status, ever. Second, every property in the table above must appear as a line item on the FR-207 hardware-validation checklist, because Tier 4 is the only place it is observable.

### 9.3 Tier-to-status mapping

| Verification Status | Minimum tiers passed |
|---|---|
| Beta | Tier 1, with the named unproven element recorded in §8.3 |
| Protocol-Implemented | Tier 1 + Tier 2 (a recorded frame corpus for that device family must exist) |
| Verified | Tier 1 + Tier 2 + Tier 4, with a completed FR-207 checklist run and its validator, date, hardware and OS versions recorded in §8.3. Tier 3 is not on the path — it accelerates Tiers 1 and 2 and produces their fixtures, but it proves nothing iOS-specific and therefore cannot raise a status on its own. |

### 9.4 Named risk: Tier 4 has exactly one person

**The only tier that can prove the properties on which patient safety depends is executed by one volunteer.** DanielDanielson owns the sole set of hardware — iPhone, Apple Watch, Tandem t:slim X2 — that can run the checklist, and the distribution model forbids the obvious workaround: the project cannot hand a build to a substitute validator without conveying a binary, which fork-and-build exists to avoid (decision 3). The concrete failure modes if they become unavailable:

- No device row can ever be raised to **Verified**. The table freezes at Protocol-Implemented for Tandem t:slim X2 and the project ships with no hardware-validated device at all.
- The release gate becomes unexecutable. Since checklist completion is the gate rather than a CI status, "no validator" and "gate not met" are the same state, and there is no honest way to release past it.
- Changes to the alerting, background-execution, restoration or Watch-delivery paths become unvalidatable in principle — these are precisely the paths Tiers 1 through 3 cannot reach.
- Medtronic spike (b) is already in this state today and is recorded as such: it is open, assigned to no one, and left for a community validator.

Mitigations, none of which fully closes it:

- Keep the checklist written, versioned and executable by **any** Builder who has the hardware — never as tacit knowledge in one person's head. That is FR-207's requirement, not an aspiration here. A checklist a stranger can run is the only form of redundancy available under fork-and-build.
- Recruit a second validator per device family, and treat "no validator for device X" as the normal, expected state that the table records honestly rather than as an embarrassment to be papered over.
- Record every Tier 4 execution with validator, date, hardware models, OS versions and the build identifier, so a lapse in validation is visible as an ageing date rather than as silence.
- Push maximum coverage down into Tiers 1 and 2, deliberately and continuously, so that the irreducible Tier 4 surface stays as small as it can be. Every invariant moved into a replay test or a type invariant is one fewer line item competing for the single validator's time.

*[NOTE FOR PM]* This is the highest-severity structural risk in the whole port and it is a staffing risk, not an engineering one. It belongs in S14 with an owner, not only here.

---

## 10. Security Gate Substitution Table

Android's five **Required Checks** on `develop` are `Security Scan Gate`, `Dependency Scan Gate`, `Workflow Lint`, `Workflow Security`, `Android Gate`, matched by GitHub on the job `name:` and not the workflow `name:`. The iOS roster keeps the count, the shape and three of the five names: `Static Analysis Gate`, `Dependency Scan Gate`, `Workflow Lint`, `Workflow Security`, `iOS Gate` (FR-197). What follows is the substitution, gate by gate, with the coverage actually lost stated rather than smoothed over.

**The roster is closed at five and this section does not extend it.** FR-197 owns those five literal strings and owns the host assignment for every mechanical gate this PRD names anywhere — including the ones with no Android ancestor, which is why they do not appear as rows below: the **Driver Catalog** registration check, the **Driver** protocol snapshot gate, the License Header Gate, the **Contract Pin** guards, the **Safety Constant** drift guard, the documentation publication gates, the accessibility identifier registry check and the deployment-floor check (NFR-1). Each is a step or a test inside one of the five, or is explicitly a non-required job; see FR-197 for which. §10.1 maps only the Android-to-iOS lineage of the five names themselves.

### 10.1 Required Check substitutions

| Android gate (required-check name) | Android tool | iOS gate (required-check name) | iOS tool | Coverage lost | What compensates |
|---|---|---|---|---|---|
| `Security Scan Gate` | Semgrep CLI 1.169.0 with registry packs `p/kotlin`, `p/java`, `p/secrets`; whole-directory scan of `app/ wear-device/ watchface/ plugins/ tools/`; jq gate blocking on ERROR/HIGH, WARNING non-blocking, INFO ignored; fail-closed on `SEMGREP_EXIT >= 2` with `${:-2}` default | `Static Analysis Gate` | CodeQL language `swift` with the `security-extended` suite, **query pack pinned by version**, plus Semgrep `p/secrets` retained unchanged, plus gitleaks promoted to a first-class failing step; same two-part jq gate, same fail-closed semantics, plus a hard failure if the analyzer reports zero analyzed files (FR-200) | **The entire `p/kotlin` + `p/java` rule corpus. Semgrep's `p/kotlin` and `p/java` packs match Kotlin and Java syntax and produce ZERO findings on Swift** — a name-only port would be a permanently green check that tests nothing. CodeQL's Swift suite is not of comparable breadth and no vendor ships one. Also lost: `watchface` as a scan root, since watchOS forbids third-party watch faces and there is no module | The query pack is pinned by version, which *closes* an Android hole: there, the CLI was pinned but registry rule content was fetched at scan time, so a green commit could turn red with no repo change. `p/secrets` is regex/entropy matching and ports unchanged, so the in-repo, merge-blocking secret lane survives. Scope is derived from the build graph (autobuild over a scheme compiling every shipping target) rather than a hand-maintained root list, so a new Driver module cannot be silently unscanned. Unprocessable files are surfaced as a non-blocking `::warning::` with the file list — Android's `.errors[]` PartialParsing surfacing, preserved, and a real recurring case on Swift. Critically, the invariants are moved *out* of SAST: the **Glucose Validity Bound** becomes a type invariant, the read-only Driver posture becomes the API-surface snapshot gate (FR-205), and protocol framing becomes Tier 2 replay tests (FR-206) |
| `Dependency Scan Gate` | OSV-Scanner v2.3.3 (`go install`) over per-module `gradle.lockfile` plus the root `settings-gradle.lockfile`, which exist only because `lockAllConfigurations()` and the `resolveAndLockAll` task produce them; `--recursive --no-ignore --config=osv-scanner.toml`; any known vulnerability fails, no severity floor; weekly cron `0 6 * * 1`; three jobs with an `if: always()` aggregation gate | `Dependency Scan Gate` (name unchanged) | OSV-Scanner v2 over the committed `Package.resolved` — SPM resolution pinning is native and always on — with the identical flags, the identical weekly cron, the identical three-job structure and the identical five-branch aggregation tree; plus a `Resolution Drift` step inside `iOS Gate` failing on any diff after resolve, and builds run with automatic package resolution disabled (FR-201) | **Advisory depth.** SwiftPM coverage in OSV and the GitHub Advisory Database is materially sparser than Maven's: Android's documented first-scan baseline was ~1,175 resolved packages with zero findings, and a green Swift scan means substantially less than a green Gradle scan did. Separately, a remote SPM `binaryTarget` is a checksummed zip with no resolvable package identity, so it cannot be matched to an advisory at all — a hole the Gradle lockfile did not have, since every locked Maven coordinate is scannable | Dependency minimalism becomes the primary control and OSV the secondary: prefer the Swift standard library and Apple frameworks, and route every new package to lead review. Remote `binaryTarget` is forbidden by default and must be `checksum:`-pinned if ever accepted (FR-204). The resolved package count is recorded in the `osv-scanner.toml` header so the thinness of the baseline is auditable rather than implied. Suppression discipline is carried verbatim: zero active entries, a written `reason` per entry, prefer an `ignoreUntil` that forces re-evaluation, quarterly review, never lower a threshold. Simplification banked: the entire Gradle locking apparatus — `lockAllConfigurations()`, the `excludedFromLocking` set, `resolveAndLockAll` — has no successor and is deliberately not ported |
| `Workflow Lint` | actionlint 1.7.7 and shellcheck 0.10.0, installed as SHA-256-verified release tarballs (`023070a2…`, `6c881ab0…`) rather than actions, so the gate has no unpinned dependency of its own; plus the SHA-pin guard and the composite-action secrets-context guard | `Workflow Lint` (name unchanged) | Identical tools, identical versions, identical checksum verification, identical three guards, `ubuntu-latest`, `timeout-minutes: 5` (FR-202) | **Nothing.** The gate operates on `.github/**`, not on app source, and is platform-neutral | Not applicable — but fork-and-build creates a guard class Android never needed, and it is hosted next door rather than here: the build-time-code-execution guard, which fails any `PBXShellScriptBuildPhase` in `project.pbxproj` and any `.plugin(` or `binaryTarget(` in `Package.swift` absent from a committed CODEOWNERS-owned allowlist, is part of FR-204's Entitlements and Plist Guard and therefore runs inside `Static Analysis Gate`, not inside this check (FR-197). Each of those is arbitrary code executing inside a build that carries a Builder's Apple signing credentials. Within this check, the SHA-pin guard is materially more important for the same reason: Android had one project-held keystore, iOS has N Builder identities |
| `Workflow Security` | zizmor 1.5.2 + PyYAML 6.0.2, `--min-severity=medium` over `.github/workflows/ .github/actions/`, `GH_TOKEN: ${{ github.token }}` for online audits; plus the inline PyYAML `pull_request_target` PR-head-checkout backstop that zizmor structurally cannot express | `Workflow Security` (name unchanged) | Identical tools, versions, threshold and backstop — including the `doc.get("on", doc.get(True))` YAML-1.1 boolean-key handling and the `github.event.pull_request.head` substring test on `with.ref` / `with.repository` (FR-203) | **Nothing.** Platform-neutral. The known blind spots port too and are restated rather than quietly dropped: laundering the head ref through a prior step's output evades the backstop, and a manual `git fetch` of the PR head in a `run:` block is not detected | Same suppression discipline, unchanged: allowlist one audit id at a time in `zizmor.yml` with a written rationale, never lower `--min-severity`. `zizmor.yml` stays CODEOWNERS-gated to the project lead precisely because an edit can silently widen what the gate ignores (FR-212), and CODEOWNERS review is explicitly the third layer the backstop relies on, not a substitute for either mechanical guard |
| `Android Gate` | Gradle on JDK 17: `testDebugUnitTest`, `lintDebug`, `assembleDebug`; `if: always()` aggregation over a `dorny/paths-filter` change detector, treating "nothing relevant changed" as a pass | `iOS Gate` | `swift test` for the platform-independent Driver, domain, unit-conversion and guard modules, plus `xcodebuild` build and unit test for the phone app, **Watch app** and widget extension; unsigned Simulator builds with `CODE_SIGNING_ALLOWED=NO`; `-warnings-as-errors` and Swift 6 strict concurrency; SwiftLint `--strict` plus `swift-format lint`; identical `if: always()` aggregation tree (FR-208) | **Android Lint.** It is named in Android's own security matrix as the verifier for HTTPS enforcement, and in the MobSF decision as the compensating control for manifest posture — exported components, `debuggable`, `allowBackup`, `usesCleartextTraffic`, weak `network_security_config`. Apple ships nothing comparable: `xcodebuild analyze` is the Clang analyzer over C and Objective-C, not Swift, and inspects neither `Info.plist` nor entitlements; SwiftLint has no security or manifest awareness. Also lost: `watchface` has no successor target, and the emulator lane at least presented a (non-functional) Bluetooth stack where the Simulator presents none | A purpose-built, deterministic **Entitlements and Plist Guard** inside `Static Analysis Gate`, with no false-positive tax (FR-204): any widening of the App Transport Security configuration past the baseline architecture records as empirically verified — the guard is a no-broadening guard, and this PRD states no plist posture as settled while that verification is open (§15) — plus `get-task-allow` true in Release, `UIBackgroundModes` exact-set match, present and non-placeholder usage-description strings, non-grantable entitlements, committed signing material, Keychain accessibility class, database data-protection class. Narrower than Android Lint, and stated as narrower. Gained with no Android analogue: `-warnings-as-errors` plus Swift 6 strict concurrency is a compile-time data-race check, directly relevant to Core Bluetooth delegate-queue code. SwiftLint carries project-specific custom rules no generic pack contains — no bare `20` / `500` / `18.0156` outside the canonical definitions, no `precondition` or `fatalError` on any value from Bluetooth, the **Backend** or persistence (SI-2), no `privacy: .public` interpolation of Pump identifiers (SI-9) |

### 10.2 Non-required jobs and retired lanes

Every iOS job below reports its own status without gating merge. The seven that survive the port are exactly the seven FR-197 enumerates as non-required — `Detect Dependency Changes`, `OSV-Scanner`, `Detect iOS-Relevant Changes`, `Build & Test`, `UI Tests (Simulator)`, `App Token Auth Check`, `Attribution Check` — and no row here adds a sixth Required Check.

| Android job (reported status) | iOS job | Note |
|---|---|---|
| `Detect Dependency Changes`, `OSV-Scanner` | `Detect Dependency Changes`, `OSV-Scanner` | Unchanged in role; feed the `Dependency Scan Gate` aggregation. |
| `Detect Android-Relevant Changes` | `Detect iOS-Relevant Changes` | Paths filter remapped to `Sources/**`, `Apps/**`, `Tests/**`, `Package.swift`, `Package.resolved`, `*.xcodeproj/**`, `*.xcconfig`, `*.entitlements`, `Info.plist`, `Resources/**`, the workflow file, and the bundled attribution texts. The Android subtlety survives: licence documents are in the filter because they ship as bundled resources and are gated by a drift test (FR-211). |
| `Build & Test` | `Build & Test` | Same name, entirely different toolchain (FR-208). |
| `Instrumented Tests (emulator)` — KVM udev rule, `reactivecircus/android-emulator-runner`, three-state AVD cache with a never-save-on-failure guard, API 35 | `UI Tests (Simulator)` | The whole emulator apparatus is deleted, not ported — macOS runners ship the Simulators. Three Android decisions are carried verbatim: deliberately **not** a Required Check and not in `needs:` of the gate while it stabilizes, so a flaky simulator cannot wedge unrelated pull requests; **no auto-retry**, a red result is re-run as a single job and never disabled; and if DerivedData or SPM artifacts are cached, the restore-plus-explicit-save split with a `success()` guard is kept so a failed run never poisons the cache. Result bundle uploaded `if: ${{ !cancelled() }}`, 14-day retention (FR-209). Coverage delta stated honestly: UI and migration coverage ports, nothing Bluetooth-related runs here. |
| `App Token Auth + Runner Check` | `App Token Auth Check` | Ports unchanged, including the fork guard `github.event_name != 'pull_request' \|\| github.event.pull_request.head.repo.fork != true`, because GitHub withholds org and repo secrets from fork `pull_request` runs. The KVM-runner reminder step is dropped. |
| `Attribution Check` | `Attribution Check` | Text-only and language-agnostic; ports unchanged, including the base-ref-only checkout and the remote-only ref fetch of PR commits (FR-218). |
| `Resolve 1Password canary` (Secrets Plumbing Check, `workflow_dispatch`-only) | **Retired upstream.** Descendant is `Validate Secrets` in the Builder's own fork | The project holds no signing identity and publishes no binary, so there is nothing upstream for it to canary. FR-180 names the workflow and this row carries no second name for it. The fork-facing workflow is `workflow_dispatch`-only and explicitly non-required (it cannot run on an upstream pull request); it asserts that every required secret is present and non-empty, that the App Store Connect API key authenticates, and that the certificate repository clones and decrypts, emitting pass/fail and non-sensitive identifiers only (5.10, FR-180). |
| `Materialize debug keystore via composite action` (Signing Action Smoke, `workflow_dispatch`-only) | **Retired upstream.** Descendant is `Signing Smoke` in the Builder's own fork | Every hygiene property carries over to the ephemeral-keychain composite action: `umask` before write, delete-before-create, trap-on-error cleanup, 0600 modes, path-only logging, and caller-side `if: always()` teardown, because composite actions still cannot register a post-job step (FR-185). |

### 10.3 Advisory layers: CodeRabbit custom checks and org-wide GitGuardian

All of these are advisory on Android and remain advisory here unless explicitly changed. Android sets `fail_commit_status: false`, which makes even a `mode: error` custom check non-blocking with respect to merge; and CodeRabbit skips pull requests authored by dependency, release and CI bots entirely.

| Android gate | Tool | iOS gate | Tool | Coverage lost | What compensates |
|---|---|---|---|---|---|
| CodeRabbit custom check **"No Hardcoded Secrets"** (`mode: error`, non-blocking) | CodeRabbit SaaS | Same check, same name, same severity framing | CodeRabbit SaaS, with the enumerated patterns extended to the iOS credential classes Android had no reason to name: App Store Connect API keys (`AuthKey_*.p8`, key ID, issuer ID), `.p12` and `.cer` certificates, `.mobileprovision` profiles, `DEVELOPMENT_TEAM` identifiers in `.xcconfig` or `ExportOptions.plist`, fastlane `MATCH_PASSWORD` | Nothing from the tool. The loss is inherited weakness: it blocks nothing, and it skips bot-authored pull requests, which under fork-and-build means a bot bump can land upstream and propagate into every Builder's credentialed build with no automated secret review from this layer | gitleaks is promoted from a CodeRabbit-only advisory tool to a first-class **failing** step inside `Static Analysis Gate`; Semgrep `p/secrets` is retained as the second in-repo blocking lane; and FR-204 fails any committed signing material deterministically, which is a stronger control than pattern matching for exactly the credential classes that matter most here. All bot-authored dependency pull requests route to manual project-lead review with no auto-merge |
| CodeRabbit custom check **"Medical Safety Review"** (`mode: error`, non-blocking) — on Android the **only** verifier of mg/dL canonicality, the 20–500 bound and the 18.0156 factor | CodeRabbit SaaS | Same check, text retained verbatim in substance **including its explicit non-violations**, so reviewers do not "fix" correct code: user-facing mmol/L display literals (3.9, 10.0, 22.2; ~1.1 and ~27.8 as the display equivalents of the bounds) and mmol/L input converted before storage are not violations | CodeRabbit SaaS **plus the type system plus the drift guard** | Nothing from the tool — but Android's enforcement strength on this row was effectively zero, and copying the configuration would import a known-weak control into a repository where the safe design is still cheap | The invariants stop being review matters. The **Glucose Validity Bound** is a type invariant on a value type whose only storage is canonical mg/dL, with a failable or throwing initializer and never a `precondition` (SI-2, SI-3). Each **Safety Constant** has exactly one definition in a module both the app and the **Watch app** link (SI-4). The Safety Constant drift guard inverts Android's enumeration: instead of asserting each known duplication site still has its expected occurrence count, CI asserts that **no** bare `20`, `500`, `18.0156` or `1199145600` appears in a glucose or pump-time context outside the canonical definitions, which is self-maintaining (FR-217). CodeRabbit is defence in depth |
| CodeRabbit custom check **"BLE Protocol Safety"** (`mode: error`, non-blocking) — GATT ops serialized and timed out, state transitions handled, little-endian for the Tandem protocol, no raw Pump data or serials at INFO, GATT 133 handling, bond loss, reassembly idle timeout | CodeRabbit SaaS | Same name, **rewritten against Core Bluetooth**: one outstanding peripheral operation at a time with an explicit timeout; every `CBPeripheral` delegate path handles `didDisconnectPeripheral`, `CBError.peerRemovedPairingInformation`, `CBError.connectionTimeout` and `CBATTError.insufficientAuthentication`; `centralManager(_:willRestoreState:)` rebuilds from the restored peripherals dictionary and never assumes in-memory state survived; the manager is constructed with a stable restore identifier | CodeRabbit SaaS **plus Tier 2 replay tests** | Roughly half the concrete Android rules are Android-GATT-specific and are unreviewable or simply wrong on iOS — `GATT 133` does not exist, bond loss surfaces differently. Conversely iOS adds a failure class Android never had: state preservation and restoration, where the app is relaunched into the background and must rebuild state without resuming arbitrary work | The mechanical half leaves review entirely and becomes executable: byte order, event-type IDs, multi-packet reassembly with its documented idle timeout, and the connection state machine all move into FR-206 Tier 2 replay tests, which run in CI with no radio. The logging rule becomes a SwiftLint custom rule banning `privacy: .public` interpolation of Pump identifiers (SI-9). What remains for review is genuinely semantic: restoration correctness and delegate-path completeness |
| **Org-wide GitGuardian** — push-time secret scanning. There is **no** GitGuardian workflow, action or configuration in the Android repository; it appears in-repo only as an allowed bot in the attribution check's `ALLOWED_BOTS`. Documented as an assumed-but-unverified external control, with GitHub platform Secret Scanning + Push Protection as the expected backstop once the repository lives under the GlycemicGPT organization | GitGuardian SaaS (external) | **Carried over unchanged**, still org-wide and still out of repo | GitGuardian SaaS (external), plus GitHub Secret Scanning + Push Protection on the same expected-but-unverified basis | Nothing structurally — but it does not become more verified by being ported. It never blocked a merge and still does not, and its status in the Android repository is "expected", not "observed" | The in-repo lane is the one that blocks: Semgrep `p/secrets` plus gitleaks as a failing step inside `Static Analysis Gate`. One fork-and-build-specific caveat has no Android analogue and must be stated: **org-wide scanning covers the upstream repository, not any Builder's fork.** A Builder's own Actions secrets, App Store Connect key and certificates live in their own GitHub account, entirely outside the reach of any control this project operates |

### 10.4 Carried-forward Android decisions and their revisit triggers

Two Android decisions were evaluated and deliberately declined. Both are carried forward. One of them has a revisit trigger that names Play Store distribution, and the iOS distribution model superficially trips it — so the answer has to be stated explicitly rather than assumed.

#### Declined: MobSF / artifact-level SAST — **decision holds; the revisit trigger is NOT tripped**

Android's stated rationale, verbatim in substance: MobSF is acknowledged as *not* redundant with Semgrep — it covers manifest posture, packaging and build configuration, and secrets embedded in the packaged artifact that never appear in source. It was declined because the app is monitoring-only and read-only; because it is distributed by GitHub side-load rather than the Play Store, so there is no pre-launch security report and no store-review threat model; because MobSF manifest and permission heuristics are high-false-positive on an app that legitimately needs BLE, location for BLE scanning and foreground-service permissions; and because running it means building and scanning an artifact on every pull request plus maintaining a suppression baseline. Android's revisit trigger, verbatim intent: **add an APK/manifest SAST gate if the app is ever distributed via the Play Store, OR if ANY write/therapeutic surface (bolus, basal, pump-setting, or other device-command capability) is introduced.**

iOS distribution goes through App Store Connect and TestFlight rather than side-loading. That looks like the trigger's store-distribution condition. It is not, for three reasons, in ascending order of decisiveness:

1. **The trigger's actual content is store *review* and a store-provided security report** — the external bar that makes artifact posture someone else's gating concern. Under fork-and-build there is no App Store listing and no public review. Each Builder installs on their own devices through their own TestFlight under their own team. *[ASSUMPTION: Builders use internal testing on their own team, which requires no Beta App Review; external TestFlight testing does require Beta App Review, so a Builder who distributes to other people re-enters review territory and this assumption stops holding for them.]*
2. **The compensating control Android relied on is gone.** Android Lint covered the manifest and network-security posture class defensively; Apple ships nothing comparable. So declining artifact SAST on iOS leaves a *wider* gap than declining it on Android did — which is why the **Entitlements and Plist Guard** exists (FR-204) and why its scope must not be allowed to shrink.
3. **Upstream CI structurally cannot produce the artifact.** The project holds no signing key and publishes no binary (decision 3). There is no project-built `.ipa` for a gate to scan. An artifact-level gate would have to run inside each Builder's fork, over each Builder's signed artifact — results upstream never sees and cannot gate a merge on. The gate is therefore not merely declined on cost grounds; it is **unreachable upstream even in principle**.

**Restated iOS revisit trigger:** reinstate artifact-level SAST if the project ever publishes a binary itself — that is, if any project-held signing identity or project-operated TestFlight or App Store listing comes into existence, which would also break the GPL-3.0-only fork-and-build posture — **or** if any therapeutic write surface is ever introduced anywhere (SI-1). Distribution through App Store Connect *by a Builder, under a Builder's own account* does **not** trip it.

**Residual gap, stated plainly and unchanged from Android's own statement:** secrets or material present only in the built artifact — bundled resources, the embedded provisioning profile, the entitlements as actually signed — are inspected by nothing. On iOS the gap widens slightly, because there are now N artifacts, one per Builder, and upstream sees none of them.

#### Declined: a dedicated secret-scanning gate — **decision holds, with one strengthening and a revisit trigger Android did not have**

Android's stated rationale: `Security Scan Gate` already runs Semgrep's `p/secrets` over the source tree; `gitleaks` runs on every pull request through CodeRabbit; GitGuardian runs org-wide at push time. A third pass over the same tree would add maintenance and noise without new coverage. The `p/secrets` lane is kept because it is free inside the existing SAST run and gives an in-repo, merge-blocking signal independent of the external services. **No revisit trigger is documented for this decision** — that absence is a fact about the Android repository, not an omission here.

The decision holds on iOS, because all three layers survive the port intact: `p/secrets` is regex and entropy matching and is language-agnostic, so the in-repo blocking lane is one of the few things that ports *unchanged* while the Kotlin and Java packs die; CodeRabbit's gitleaks stays; GitGuardian stays org-wide. No sixth Required Check named `Secret Scan Gate` is added — the coverage lives inside `Static Analysis Gate`.

One change, forced by fork-and-build: **gitleaks is promoted from a CodeRabbit-only advisory tool to a first-class failing step inside `Static Analysis Gate`.** Android's honest caveat was that of three nominal layers only one actually blocked a merge, and CodeRabbit's commit status is non-failing. That asymmetry is worse here, because a credential class leaked into this repository is no longer one project keystore under one person's control but the class of credentials that N Builders wire into their own forks. Alongside it, FR-204 adds a deterministic committed-signing-material check that no pattern matcher is needed for.

**Revisit trigger recorded where Android had none:** revisit if `Static Analysis Gate` ever stops running both Semgrep `p/secrets` and gitleaks, or if a credential class enters the repository that regex and entropy scanning cannot recognize.


## 11. Non-Goals (Explicit)

Each row is permanent for this product, not a v1 cut. Anything with a revisit condition lives in §12, not here.

| ID | Non-goal | Reason |
|---|---|---|
| NG-1 | **No therapeutic write surface, ever.** No bolus, basal, pump-setting or device command in any Driver protocol, in any Driver, or behind any flag. | SI-1 is architectural, not a scope decision; it is enforced by the closed six-member Capability set (FR-30), read-only-by-construction (FR-31) and the Driver protocol public-interface snapshot gate (FR-205) — not by policy. |
| NG-2 | **No closed loop, no dosing, no dose recommendation.** Not for insulin, not for carbs, not from the AI. | The product is monitoring-only; IOB is reported by the Pump and never computed (FR-90, SI-7), meal estimates are carb ranges carrying a never-dose qualifier (FR-96, UJ-5), and AI Chat carries standing safety disclaimers (FR-111). |
| NG-3 | **No App Store listing and no project-published installable binary.** Not a release asset, not a signed IPA, not a "download the latest build" path. | GPL-3.0-only conflicts with App Store terms, and the project does not own the OpenMinimed-derived copyright it relies on under palmarci / Pal Marci's explicit relicensing permission — so this is a settled consequence of the facts on the acknowledgments page (FR-232, FR-233), not a preference. |
| NG-4 | **No project-held signing key and no project-operated TestFlight.** No internal testers on a project account, including the hardware validator. | Adding anyone as a tester on a project-held account would make the project convey a signed binary and reintroduce exactly the licence conflict fork-and-build exists to avoid; DanielDanielson validates from their own fork under their own Apple Developer account (FR-179, FR-196). |
| NG-5 | **No project-operated Backend, relay or push service, hosted or otherwise.** | The Backend is the user's own, self-hosted; Backend-optional mode is a first-class supported mode (FR-143, FR-152). The project operates nothing, so there is nothing to breach and nothing to shut down. |
| NG-6 | **No telemetry, no analytics, and no crash reports reaching the project.** | Permanent because there is nothing on the receiving end and never will be: the project operates no service (NG-5) and holds no account any build could report to, so this is not a toggle anyone can flip back. FR-189 is the single definition of the no-project-telemetry rule and FR-236 is its published surface; this row defers to both and restates neither the mechanism nor its CI enforcement. |
| NG-7 | **No direct Nightscout client.** No Nightscout URL and no API secret ever live in the app. | Nightscout-sourced data reaches the app through the Backend as a Driver-shaped Capability (FR-38, FR-153); a direct client would put a second credential and a second freshness regime on the device. |
| NG-8 | **No runtime Driver loading, no sideloaded Driver, and no in-app Driver install UI.** | iOS forbids executing code that was not in the signed bundle, so Android's runtime-loaded plugin mechanism has no counterpart at any tier; a Driver is a compile-time-linked Swift module and the Driver Catalog is the sole registration path (FR-21), with a compile-time exclusion kill switch as the only inclusion control (FR-27). |
| NG-9 | **No custom watch face, no face gallery, no phone-pushed face, and no phone-controlled face theme or seconds display — and no per-app appearance preference standing in for one.** | watchOS has no third-party watch face API and never has; the user places our complications on the face they chose, and the app can only teach placement and detect its absence (FR-117, FR-118). Complications render in a system-controlled tint the app cannot override, so an appearance preference could not reach them — it would be a control that does nothing. Recorded as a forced loss in §7, not a rebound feature. |
| NG-10 | **No guaranteed unsilenceable alarm, and no alarm-volume control anywhere.** The urgent-low alert can be silenced by the ring/silent switch, the app cannot detect that it was, no code sets output, ringer or alarm volume, and no code reads or infers the switch position. | Critical Alerts is granted by Apple per Team ID and is structurally unobtainable under fork-and-build (decision 4); the app ships on `.timeSensitive` with runtime auto-upgrade if the entitlement is ever present, states the limitation, and is forbidden from claiming otherwise on any surface (FR-66, FR-234, FR-235). iOS exposes no public API to set output or ringer volume and none to read the switch position, so Android's alarm-volume boost is deleted rather than substituted (§7 PL-24). |
| NG-11 | **No FDA clearance, no CE mark, no regulatory submission, and no medical-device claim.** The app is a supplement to, never a replacement for, the Pump and CGM's own displays and alarms. | The project makes no clinical claim and no claim about what any installed binary contains, because every Builder compiles and signs their own (FR-196, FR-234). |
| NG-12 | **No in-app self-update, no APK-equivalent download path, and no watch-app push.** | Updating means re-running the fork's pipeline and installing through the Builder's own TestFlight; the app can at most compare tags and show a non-actionable notice (FR-188) — the single permitted exception to Backend-optional network silence, user-toggleable and off by default, carrying and receiving no health data (NFR-23) — and the Watch app ships inside the same bundle (FR-115). |
| NG-13 | **No localization in v1.** English only, strings inline in Swift. | Verified parity, not a cut: the Android client ships a single `values/` resource set with a six-string `strings.xml` and every other string inline in Kotlin, so there is no localization capability to port. |
| NG-14 | **No Android-to-iOS data migration path.** A user moving from the Android client starts with an empty local store. | The iOS store starts at schema v1 with no Android artifact to import; history is backfilled from the Backend or re-read from Pump history (FR-146), and building an export/import bridge would create a health-data transfer surface neither platform has today. |
| NG-15 | **No HealthKit read or write, and no health-data export or share surface.** | Verified absent from Android (no `androidx.health`, `allowBackup=false`, no share or export); a HealthKit write would create a therapeutic-adjacent data path with no Android counterpart. The only export that exists is the scrubbed diagnostic log of FR-158, which carries no health value (SI-9). |
| NG-16 | **The project makes no claim about what any installed build contains.** | Every architectural claim in every published document is a claim about the source at a stated tag, not about the binary anyone is running; upstream cannot inspect, reproduce or revoke a Builder's build (FR-196). |
| NG-17 | **No calibration write surface.** There is no calibration-target Capability, no calibration protocol, no calibration slot, no slot-resolution branch and no calibration screen; a Driver cannot declare one. | The Capability set is closed at **six**, not Android's seven (FR-30). No shipped Driver implements calibration, it is the only member that would require writing to a device, and its presence forced SI-1 — the strongest safety claim in this product — to carry a carve-out for a permitted `calibrate` command. Removing it makes "no device command exists in any Capability protocol" true unconditionally and keeps FR-205's snapshot gate from failing on the project's own shipped protocol. A future CGM Driver that needs calibration is a PRD change with its own safety review, not a slot left open (FR-30, which cross-references this row as the reason). Recorded as a deliberate divergence in §7. |

---

## 12. MVP Scope

The mandate is full parity. The MVP is therefore the whole product: **FR-1 through FR-237, all twelve feature sections, both shipped device Drivers, the Watch app, the Builder pipeline, the engineering gates and the published documentation** — minus exactly the deferrals enumerated below, each of which is deferred because a platform fact or a cross-repository dependency makes it undeliverable now, not because it was traded for schedule. No feature section is thinned.

### 12.1 In scope

| Section | FRs | In v1 | Carve-outs |
|---|---|---|---|
| 5.1 Pump Connection and Pairing | FR-1 – FR-20 | Full | Medtronic advertise-and-wait pairing ships gated at Beta (D-2). |
| 5.2 Drivers and the Device Catalog | FR-21 – FR-38 | Full | Tandem Driver at Verified only after D-2's device pass; every other Driver ships at Protocol-Implemented or Beta. |
| 5.3 Glucose Monitoring and the Dashboard | FR-39 – FR-64 | Full | — |
| 5.4 Alerting and the Coverage Contract | FR-65 – FR-88 | Full | Critical-Alerts-dependent behaviour is the runtime-upgrade path only (D-3); Backend-generated alerts do not reach a suspended or terminated app (D-1); alert sounds are the bundled curated set, user-imported audio deferred (D-9). |
| 5.5 Insulin, Meals and Analysis | FR-89 – FR-104 | Full | — |
| 5.6 AI Chat | FR-105 – FR-114 | Full | — |
| 5.7 Apple Watch and Glanceable Surfaces | FR-115 – FR-134 | Full | Shareable watch-face configuration file is optional (D-6). |
| 5.8 Data, Storage, Sync and Backend | FR-135 – FR-158 | Full | APNs device-token path reserved and unwired (D-1). |
| 5.9 Onboarding, Settings and Accessibility | FR-159 – FR-178 | Full | — |
| 5.10 Build, Sign, Install and Update | FR-179 – FR-196 | Full | Side-by-side stable and development install not provided (D-4). |
| 5.11 Engineering Gates and Contract Guards | FR-197 – FR-218 | Full | UI Tests (Simulator) ships non-required (D-5). |
| 5.12 Documentation, Licensing and Policy | FR-219 – FR-237 | Full | Device Verification Matrix ships nearly empty and fills as validators appear (D-7). Publication depends on a prerequisite in `lumose-health/website` that this repository cannot satisfy — stated below, not assumed. |

Non-negotiable in v1, called out because they are the parts most likely to be proposed as cuts: the **Simulated Driver** and **Trace-Replay Driver** (FR-35, FR-36) — with no Core Bluetooth in the iOS Simulator and no iPhone for the lead developer, they are the only executable Drivers during most of development; the five **Required Checks** running to completion on a fork pull request (FR-199), which is the precondition for UJ-6; the **Alert Floor** and the **Coverage Claim** with a single expiry driving all four decay mechanisms (FR-71, FR-83, FR-84); and the install runbook validated end to end by someone who did not write it (FR-223), because under fork-and-build the runbook *is* the delivery mechanism. Add to that the **pairing-troubleshooting page and the iOS status-icons page** (FR-237): they are the named disclosure surface for five §7 forced losses — bond removal is a user procedure iOS exposes no API for (PL-1), a stale service cache can leave a Pump connected and delivering nothing (PL-2), a reinstall or restore can leave a saved Pump unrecognised (PL-8), the iOS glyph vocabulary diverges from Android's published set (PL-10) and iOS has no battery-optimization exemption or durable-background setting to grant (PL-52). §7's own rule is that a forced loss with no disclosure surface is a defect, so cutting either page reopens five defects at once.

### 12.2 Deferred, with revisit conditions

| ID | Deferred | Why | Revisit condition |
|---|---|---|---|
| D-1 | **APNs and all Backend-push delivery.** v1 ships SSE while the process is alive, the on-device Alert Floor, and opportunistic pulls; the device-token field stays present and unpopulated. | Settled decision 7. The blocker is a cross-repository commitment, not the contract: the wire slot already exists. Consequence: Backend-generated alerts — including caregiver alerts — do **not** reach a suspended or terminated app in v1. Recorded as a Parity Ledger loss (FR-157). | The Backend repository accepts per-deployment APNs configuration. Client work is then limited to populating the reserved field and handling a background push; no Contract Pin change is required, which is why the field is reserved rather than removed. |
| D-2 | **Medtronic hardware verification.** The Driver ships present-but-gated at **Verification Status: Beta**, matching Android's own label. Transport spike part (a) is in v1 scope and early; part (b) is not. | Settled decision 5. Part (b) — whether a 780G's discovery filter accepts an iOS advertisement carrying the identity as a standard GAP local name rather than as manufacturer-specific data under company id 0x01F9 — requires a physical 780G. Neither the lead developer nor DanielDanielson has one. | A community validator with a physical 780G completes spike (b) and the on-device checklist. Promotion out of Beta is then a Device Verification Matrix change plus, if part (b) fails, a documented transport change — not a re-architecture, because the resolver seam exists from P0. |
| D-3 | **Everything conditional on the Critical Alerts entitlement**: DND/silent-switch override, guaranteed audibility, and any Coverage Claim wording that would assert it. | Settled decision 4. Apple grants the entitlement per Team ID; every Builder signs with their own team. The provisioning workflow reports its absence and continues, and nothing in the build may hard-depend on it (FR-182). | The entitlement is present at runtime on a Builder's team. The upgrade to `.critical` is automatic with **zero code change** (FR-66); only the Coverage Claim detail copy follows. |
| D-4 | **Side-by-side stable and development install on one iPhone.** One App ID set, branch-selectable channel (FR-183). | On Android this was free (`applicationIdSuffix`); on iOS it costs every Builder a second globally-unique App ID, provisioning profile, App Store Connect record and TestFlight setup — roughly doubling onboarding. | The hardware validator demonstrates a need to run both simultaneously. Must be decided **before** the FR-182 provisioning workflow is built, because it changes what that workflow registers. |
| D-5 | **`UI Tests (Simulator)` as a sixth Required Check.** Ships reporting but non-required (FR-209). | Matches Android's emulator lane while the suite stabilizes. | A stated promotion criterion is agreed and met (see OQ-52). Android has carried the "while it beds in" state indefinitely with no criterion; a stated trigger is what prevents the same drift. |
| D-6 | **Shareable `.watchface` configuration file** (FR-118). | Device-only and unverifiable in the Simulator, so it cannot sit on the critical path. It is the closest analogue to Android's watch-face variant push, which is otherwise a total loss. | DanielDanielson's first device pass confirms it is worth the maintenance; it is additive and gates nothing. OQ-31 carries the standing form of the question, as OQ-52 does for D-5. |
| D-7 | **Verified status for every device except Tandem t:slim X2.** Tandem Mobi and Medtronic ship carrying Android's own labels. | Verification Status is a statement about *this* code running on *that* hardware; an inherited "Verified" would be a false safety claim about software nobody has run (FR-234). | A named validator with the named hardware completes the device checklist. The matrix row changes; the code does not. |
| D-8 | **Any published battery-consumption figure.** Android publishes "< 5% per day"; iOS publishes nothing rather than inheriting it. | The iOS design trades a persistent connection for connect → burst-read → disconnect cycles plus an indefinite pending connect, so the Android figure is unbacked here. | A measured figure from a full overnight soak on the validator's device. Until then the page omits the claim.  |
| D-9 | **User-imported alert audio and the transcode-to-CAF import path** (FR-67). v1 ships the bundled curated set plus "Default" for every tier and "Silent" for the informational tier, and nothing else is selectable. | Additive scope, not parity: Android's system `RingtoneManager` picker has no iOS counterpart, so the bundled set is the forced substitute for the whole system sound library (a forced loss recorded in §7) — but an import path is a *further* feature that adds a transcode failure mode to an alarm path whose failure mode is silence. | The bundled set has shipped through one tagged release **and** import, transcode and delivery of a real low alarm can be validated end to end at Validation Tier 4 on physical hardware (§9), so a failed transcode can never silently substitute the system default on a low. |

### 12.3 Sequencing

Ordered so that the things that can invalidate architecture happen while they are still cheap. Two of the four project-critical unknowns (P0.1, P0.6) are answerable with **no iPhone and no Pump**; the rest of the honesty-critical unknowns land on one person's hardware and must be budgeted as device time from project start, not discovered late.

| Phase | Work | Why here | Exit criterion |
|---|---|---|---|
| **P0.1** | **Medtronic transport spike part (a)**: can Core Bluetooth return a `CBPeripheral` for a central that connected to our `CBPeripheralManager`? | Answerable on a Mac with a second BLE central and **no Pump** — Core Bluetooth is fully available on macOS. A negative answer makes the entire Medtronic read layer unreachable even after a successful handshake, which changes the Driver architecture. It must therefore precede committing the Driver protocol seam. | Answered yes or no, recorded in the repository with the probe source. The link-resolver seam is either justified or Medtronic is re-scoped before parser work begins. |
| **P0.2** | **Safety Constant module and validating domain types**: the Conversion Factor, the Glucose Validity Bound, the Tandem epoch offset 1199145600; throwing initializers plus failable convenience initializers; `precondition`/`fatalError` banned on Bluetooth-, Backend- and persistence-sourced values. | SI-2, SI-3 and SI-4 are the foundation everything else links against, and the module must build for the app, the Watch app and every extension. Retrofitting this after parsers exist is how clamping gets introduced. | Boundary tests at min, max, min−1, max+1; the Safety Constant drift guard (FR-217) green; the module linked by both the app and the Watch app. |
| **P0.3** | **Required Check roster, fork-runnable, with a seeded-finding canary** (FR-197 – FR-199, FR-213). | Every later phase merges through these. A gate added after the code it should have guarded is a gate that grandfathers a defect. | All five checks complete on a pull request from a fork with a read-only token; the seeded finding proves the analysis gate can fail the build. |
| **P0.4** | **Contract Pin vendored, one shared decoder configuration, tolerant-reader guards in both directions** (FR-214 – FR-216). | SI-12 is broken by Swift's synthesized `Codable` *by default*, and fork-and-build makes the newer-app → older-Backend direction the normal case rather than an edge case. | Every defaulted field decodes when absent, asserted by test; a missing consumed field fails loudly. |
| **P0.5** | **Simulated Driver and Trace-Replay Driver as shipped first-class Drivers** (FR-35, FR-36). | Net-new engineering, not a port (`plugins/example` is not a built module on Android). With no Core Bluetooth in the Simulator and no iPhone for the lead developer, these are the only executable Drivers for most of the project. | Both appear in the Driver Catalog, both drive the full dashboard, alerting and Watch surfaces in the Simulator (FR-207). |
| **P0.6** | **EC-JPAKE and the Medtronic handshake ported to Swift with Kotlin ↔ Swift differential vectors on a seeded RNG**, exercised through the trace harness on a macOS bench. | ~10,400 LOC of protocol and crypto with no Apple-platform library underneath: CryptoKit exposes neither raw P-256 point addition and arbitrary-base scalar multiplication nor AES-CMAC. A subtle error produces a handshake that fails only against real firmware, which the lead developer cannot reach. Doing this against recorded frames on macOS is the only way to find it early. | Byte-identical vectors against the Kotlin implementation across the full handshake; replay tests green (FR-206). |
| **P1** | **Tandem read path end to end on the macOS bench**: transport, framing, parsers, durable history cursors, encrypted store, Alert Floor logic, dashboard. | Everything below the transport is offline-provable. Cursor durability must land before either fast path ships — iOS terminates apps routinely, and Android's in-memory cursors self-heal only because a durable slow loop backs them. | Trace-Replay Driver reproduces a recorded session with identical totals; no cursor advances past an undecoded record (SI-8). |
| **P2** | **Surfaces**: Watch app and complications, glanceable surfaces, AI Chat, meals, onboarding and Settings, accessibility identifier registry. | Depends on P1's data and on the shared safety module; independent of hardware except for the checks named in P4. | Greyscale distinguishability gate green for all six coverage branches; accessibility identifiers registered and enforced. |
| **P3** | **Builder pipeline and published documentation** (FR-179 – FR-196, FR-219 – FR-237), including the license generator and its drift test. | The pipeline is a supported product surface and the runbook is the delivery mechanism; both need to exist before anyone outside the project can produce a build to validate. | The install runbook is executed end to end by someone who did not write it, from a clean GitHub account and a clean Apple Developer account, before the repository is announced. **And:** a page of the `docs/` tree is fetched from glycemicgpt.org and confirmed to render with its frontmatter title and working links. |
| **P4** | **DanielDanielson's device pass** on their own fork build against their own t:slim X2: background Core Bluetooth evaluation cadence, Keychain lock-state and file-protection semantics, Local Network Privacy, Focus and ring/silent behaviour, felt haptics per tier, complications after 18 hours, force-quit and post-reboot recovery, a full overnight soak in Low Power Mode. | These are the properties the Simulator gives **false positives** on. The measured background cadence in particular decides whether the 360,000 ms Fresh window is honest — and the honest response to a slow cadence is a copy change, never a wider Fresh boundary. | The written device checklist is completed and recorded per release; the Fresh window is either confirmed or the Coverage Claim copy changes. Schedule early — it can invalidate copy, and copy changes ripple across the app, the Watch app and the docs. |
| **P5** | **Community validation**: Medtronic spike (b), Tandem Mobi, any contributed Driver. | Unbounded on an external volunteer; must not gate v1. | Device Verification Matrix rows gain a validator and a date. |

[NOTE FOR PM] The single-point-of-failure in P4 is a resourcing decision, not an engineering one. Funding a second hardware validator removes it for every BLE, background, notification and Watch behaviour in the product simultaneously — it is the highest-leverage spend available and it is independent of the Medtronic outcome.

---

## 13. Success Metrics

The project can never observe its users: it operates no Backend, ships no telemetry and holds no analytics (NG-5, NG-6). Every metric below is therefore observable from the repository, from CI, from the Device Verification Matrix, or from public community channels — and **no metric may be redefined in a way that would require telemetry to measure.**

**Sample floor.** SM-1, SM-2 and SM-12 rest on voluntary reports from **Builders** — the project cannot read anyone's Actions logs (A-50). Below **n = 10 distinct Builders** none of these figures is reported as a number; the metric reads "insufficient reports" instead. A median over three installs is noise presented as evidence, and this project has no second source to correct it.

| ID | Tier | Metric | Observable from | Target | Validates |
|---|---|---|---|---|---|
| SM-1 | Primary | **Builder install success.** Share of reported install attempts reaching a launching build without an upstream-owned defect, and share of failures that map to a *named* preflight message rather than an opaque Xcode or App Store Connect error. | Structured install-report issue template; every preflight failure emits a specific greppable message naming the exact secret or setting at fault. | ≥ 90% of reported failures classify to a named message; zero unclassifiable failure classes open across two consecutive releases. | FR-179 – FR-185, FR-223; UJ-3 |
| SM-2 | Primary | **Time from fork to first launching build**, self-reported median, for a Builder who already holds a paid Apple Developer Program membership. | Install-report template field. | Median ≤ 90 minutes; ≤ 1 upstream-owned blocking defect per release cycle. | FR-180 – FR-183, FR-223; UJ-3 |
| SM-3 | Primary | **Hardware-verified device count and matrix freshness.** Every row at Verified names a validator and a date, and no Verified row predates the last change to that Driver's protocol code. | Device Verification Matrix (S8) versus git history of the Driver trees, checked in CI. | Tandem t:slim X2 at Verified before the first tag; zero Verified rows without a named validator; zero stale Verified rows. | FR-22, FR-234; S8, S9 |
| SM-4 | Primary | **Required Check integrity.** Five checks configured and named exactly; each proven able to fail; none with `continue-on-error`; roster comparison green; zero merges to `develop` with a Required Check bypassed. | Branch-protection ruleset, workflow files, the roster comparison step, merge history. | 100%, every release. | FR-197 – FR-218 |
| SM-5 | Primary | **Coverage-honesty defects.** Reports in which the app claimed watching while it was not, or rendered a value staler than its Freshness Tier permits, on any surface. | Issue tracker, label `coverage-honesty`. | Zero. Any single occurrence is release-blocking; this is a count, never an average. | FR-83 – FR-86, FR-126; SI-6 |
| SM-6 | Primary | **Safety-invariant escapes.** Merged commits that reintroduced a Safety Constant literal, a therapeutic write primitive, a clamped glucose value, or a trap on Bluetooth/Backend/persistence-sourced data — and were caught only after merge. | Git history plus the gate that should have caught each. | Zero. Each occurrence is a gate defect and is fixed by adding or tightening a gate, never by a review reminder. | FR-204, FR-205, FR-217; SI-1, SI-2, SI-4 |
| SM-7 | Secondary | **Driver contributions.** Externally contributed Drivers reaching the Driver Catalog, each naming who will validate on which physical hardware. | Merged pull requests; the Driver Catalog. | ≥ 1 within 12 months of announce; 100% of submissions name a validator and hardware. | FR-21, FR-31, FR-206, FR-225; UJ-6 |
| SM-8 | Secondary | **Fork pull-request gate parity.** Share of external pull requests on which all five Required Checks complete with a read-only token and no secret. | CI run history on fork pull requests. | 100%. | FR-199; UJ-6 |
| SM-9 | Secondary | **Expiry lapses.** Reports of "the app stopped launching" after the first 90 days post-announce. | Issue tracker, label `build-expiry`. | Zero. Each one is a defect in FR-186, FR-187 or FR-223, never a user error. | FR-186 – FR-188, FR-223 |
| SM-10 | Secondary | **Cross-version contract failures.** Reports of a hard parse failure against an older Backend, or of a missing consumed field passing silently. | Issue tracker, label `contract`; the tolerant-reader guards. | Zero. | FR-155, FR-215, FR-216; SI-12 |
| SM-11 | Secondary | **Documentation-truth gates.** Link check, `pages`-array membership, frontmatter completeness under `docs/**`, required-check roster comparison, and license asset drift test green on every run; every published number quoting its single authoritative site. | CI, plus a fetch of each published page after a release — a green in-repo gate is not evidence of publication. | 100% green; zero published numbers disagreeing across pages; zero pages required by an FR that return nothing at their published URL. | FR-219, FR-220, FR-228 – FR-230, FR-213 |
| SM-12 | Secondary | **Issue-class mix.** Share of open issues that are provisioning or signing failures rather than app behaviour. | Issue labels. | Provisioning share falls release over release. A rising share means the runbook is the defect, not the Builder. | FR-223; UJ-3 |
| SM-13 | Secondary | **Simulator-provable coverage.** Share of FRs whose acceptance criteria are executable with no iPhone — via the Simulated Driver, the Trace-Replay Driver or replay tests. | Test inventory versus the FR list; the device checklist. | ≥ 80% of FRs; every remaining FR appears on the on-device checklist **by name**. | FR-35, FR-36, FR-206, FR-207; S9 |
| SM-14 | **Counter** | **Alert volume — do not optimize.** Neither up nor down. Specifically forbidden as means: widening the Fresh window, raising an Alert Threshold default, lengthening the cooldown, or shortening the re-alarm ladder in response to noise complaints. | Any change to the constants in FR-72, FR-74, FR-76 whose changelog cites alert volume. | Any such change requires an explicit PM ruling recorded against SI-5 and SI-6, not a tuning commit. | FR-72 – FR-76 |
| SM-15 | **Counter** | **Honesty copy — do not optimize away.** The Coverage Claim caveat, the Not-Watching Reason, Freshness Tier de-emphasis, Beta labels, the never-dose qualifier and the alert-audibility disclosure are load-bearing, not clutter. | Any UI change deleting or shortening a string covered by FR-48, FR-66, FR-83, FR-96, FR-127, FR-235. | Zero silent removals. The greyscale distinguishability gate stays merge-blocking; a cleaner screen is not a reason. | FR-48, FR-66, FR-83, FR-96, FR-127, FR-235; SI-6 |
| SM-16 | **Counter** | **CI wall-clock and macOS minutes — do not optimize by weakening a gate.** Removing, renaming, paths-filtering or making advisory a Required Check is the predicted failure path under macOS runner cost pressure (R-16). | Roster comparison step; `continue-on-error` scan; paths filters on Required Checks. | Zero. Cost is reduced by keeping the repository public and moving platform-independent targets to `swift test` — never by reducing the gate set (R-14). | FR-197, FR-198, FR-210 |
| SM-17 | **Counter** | **Onboarding step count — do not optimize by hiding a prerequisite.** The paid Apple Developer Program requirement, the unskippable safety acknowledgement and the alert-audibility disclosure stay in the path. | Onboarding flow; the install runbook. | Zero removals. | FR-159, FR-160, FR-165, FR-223, FR-234 |
| SM-18 | **Counter** | **Crash-free rate, DAU, retention, funnel conversion — do not introduce.** Every one of these requires telemetry the project has committed not to ship. Their absence is a feature of the product, not a measurement gap to close. | — | Zero telemetry integrations; the DSN stays empty in every configuration the pipeline produces. | FR-189, FR-236; NG-6 |

---

## 14. Risks and Mitigations

Ranked most severe first. Owner is the person who must act, not the person who is affected. `R-n` IDs are stable and are never renumbered, so rank order — not ID order — carries severity.

**R-1 — Medtronic may be unimplementable on iOS at the transport layer, and it cannot be proven either way without hardware.** *(Critical. Owner: project lead, then a community validator.)*
There is no documented API to obtain a `CBPeripheral` for the central that just connected to our `CBPeripheralManager`, and iOS cannot emit the manufacturer-specific advertisement the pump's matcher was reverse-engineered against. Either failure makes the entire read layer unreachable even after a successful handshake. Nobody on the team owns a 780G. Everything below the transport is offline-provable; nothing at the transport is.
*Mitigation:* split the spike (decision 5). Part (a) runs at **P0.1**, on macOS, with no Pump, ahead of any parser work, behind a link-resolver seam. Part (b) is deferred to a community validator (D-2) and the Driver ships present-but-gated at Beta with Android's own label.
*Residual:* the parity mandate is unmeetable for that device until someone with a 780G appears. That is stated, not hidden.

**R-2 — ~10,400 LOC of safety-critical BLE protocol and crypto with no Apple-platform library underneath it.** *(Critical. Owner: project lead.)*
Tandem's EC-JPAKE needs raw P-256 point addition and arbitrary-base scalar multiplication that CryptoKit does not expose; Medtronic needs a clean-room Swift reimplementation of the JVM-only six-stage handshake, the per-direction sequence cipher, and AES-CMAC, which neither the JCE nor CryptoKit provides. A wrong encoding length, a mis-reduced ZKP hash or an unblinded scalar produces a handshake that fails **only against real firmware** — which the lead developer cannot reach.
*Mitigation:* **P0.6** — port the captured-trace harness to Swift first, add Kotlin ↔ Swift differential vectors under a seeded RNG, and validate on a macOS bench where Core Bluetooth is fully available, before any iPhone work. Replay tests are a Required Check (FR-206).
*Residual:* firmware-specific behaviour still only appears on DanielDanielson's t:slim X2 (R-5).

**R-3 — No background execution guarantee, so the Alert Floor and the Coverage Claim become conditional on Core Bluetooth producing wake events.** *(Critical. Owner: project lead; measured by DanielDanielson.)*
Android's foreground service polls every 15 s forever and doubles as the ~30 s BLE keep-alive. iOS suspends between callbacks, background refresh is opportunistic at ~15 minutes or worse, and a poll-only peripheral generates no wake events at all. Compounding, all invisible while they happen: force-quitting from the app switcher permanently disables Core Bluetooth relaunch until the user reopens the app; nothing runs after reboot until first unlock; Low Power Mode removes the backfill path.
*Mitigation:* architecture plus honesty — connect → burst-read → disconnect cycles with an indefinite pending connect, history backfill on every wake, a persisted last-successful-wake timestamp, prominent data age everywhere, and a Coverage Claim that decays with no code running (FR-84, FR-85, FR-86). Measured cadence is a **P4** exit criterion.
*Residual:* if the measured cadence is worse than the 360,000 ms Fresh window assumes, the fix is copy, never a wider boundary. Recorded in the Parity Ledger.

**R-4 — The urgent-low alarm is silenceable and the app cannot detect that it was.** *(Critical. Owner: PM, for disclosure wording.)*
Critical Alerts is unobtainable per-Builder under fork-and-build; `.timeSensitive` breaks through Focus but not the ring/silent switch, and neither the switch position nor the ringer volume is readable by any public API. Android gets both from ordinary install-time permissions. This does not merely degrade a feature — it undermines the honest-coverage architecture on the single most safety-relevant path in the product.
*Mitigation:* settled decision 4 — ship on `.timeSensitive` with automatic runtime upgrade; state the limitation in onboarding, in Settings, in the notification status card and in the published disclaimer; prohibit any guaranteed-alert claim on any surface (FR-66, FR-171, FR-234, FR-235).
*Residual:* a Builder with the phone muted can miss an urgent low. Unfixable on this platform under this distribution model; it is a recorded Parity Ledger loss, not a defect.

**R-5 — Validation Tier 4 has exactly one person: the entire BLE, background, notification and Watch surface is validated by the maintainer DanielDanielson (they/them) alone, on one set of hardware, and no second path to hardware validation exists.** *(High. Owner: PM — this is a resourcing decision.)*
Tier 4 — on-device hardware smoke — is the sole evidence class that can raise a Verification Status to Verified (S9, §9.3, §9.4), and that one person holds the only iPhone, Apple Watch and Tandem t:slim X2 that can run its checklist. They build from their own fork under their own Apple Developer account; the distribution model forbids the obvious workaround, because handing a build to a substitute validator would convey a binary (decision 3, decision 9, NG-4). Core Bluetooth does not exist in the iOS Simulator; the lead developer has no iPhone and no Apple Watch; DanielDanielson has no Medtronic hardware, so Medtronic spike (b) is already unowned. Worse, the Simulator produces **false positives** on exactly the properties that matter: entitlements, Local Network Privacy, Keychain lock-state and file-protection semantics, background wake and Core Bluetooth state restoration, WidgetKit and WatchConnectivity budgets, Focus, the ring/silent switch, and Watch haptics.
*Mitigation:* push maximum coverage into replay tests and the Simulated Driver (SM-13, ≥ 80%) so the irreducible Tier 4 surface stays as small as possible; treat a Simulator result on any device-only property as **no result**; publish a written on-device checklist any Builder with the hardware can execute — never tacit knowledge in one person's head — as an explicit release gate, executed by the validator and recorded per release with validator, date, hardware models, OS versions and build identifier, so a lapse shows as an ageing date rather than as silence (S9).
*Residual:* one illness, one lost device or one departure stops all hardware validation outright: no row can be raised to Verified, and because checklist completion *is* the release gate rather than a CI status, "no validator" and "gate not met" become the same state. Funding a second validator is the only real mitigation and it is the highest-leverage spend available.

**R-6 — Fork-and-build distributes the supply-chain blast radius across every Builder's Apple Developer account.** *(High. Owner: project lead.)*
`Package.swift` is executable Swift evaluated at resolve time, SPM build-tool plugins run during build, and Xcode Run Script phases run on every build — all inside a job holding the Builder's App Store Connect private key, certificate passphrase and personal access token. Android had one project-held keystore under one person's control. A single compromised or unpinned action in the build lane exfiltrates the signing identity of **every Builder who has synced that workflow**.
*Mitigation:* the build lane is the highest-trust file in the repository — CODEOWNERS-gated, minimal action set, plain `run:` steps preferred, every reference SHA-pinned with no exception, a mechanical build-script and plugin guard over the project file and `Package.swift` against an owned allowlist, checksum-pinned binary targets or none, secrets scoped to the narrowest job (FR-185, FR-193, FR-202, FR-204, FR-212). SECURITY.md states explicitly that syncing upstream runs new code with the Builder's credentials, and that reading the workflow diff is a reasonable precaution (FR-195, FR-196).
*Residual:* a Builder who blindly syncs and never reads a diff is trusting upstream completely. That is inherent to the model and is disclosed.

**R-7 — Kotlin-to-Swift translation of validation and parsing has two failure modes, both worse than Android's.** *(High. Owner: project lead.)*
A literal transcription of `require` to `precondition` traps the process — a crash inside a background Core Bluetooth restoration wake that the user never sees, and that gets the app deprioritised for future relaunch. Clamping to avoid the trap fabricates a plausible glucose or dose. Alongside: Swift traps on integer overflow where Kotlin wraps (the CRC loop, the 8-bit transaction id, a uint32 exceeding Int32); `Data` slices carry a non-zero start index, so an index-based parser silently reads wrong offsets after the first slice; and `Double` → `Int` on NaN traps.
*Mitigation:* SI-2 as a typed rule — throwing initializers plus failable convenience initializers, `precondition`/`fatalError` banned by lint on any value originating from Bluetooth, the Backend or persistence; boundary tests at min, max, min−1, max+1; fuzz tests over truncated and random payloads; all four hazards enforced by lint (FR-217, and the P0.2 exit criteria).
*Residual:* a trap in a code path no test reaches still fails invisibly in the background. The lint ban is the primary control precisely because it is mechanical.

**R-8 — `Codable` silently breaks the tolerant reader in the direction fork-and-build makes normal.** *(High. Owner: project lead.)*
Swift's synthesized decoder throws on an absent key for a non-optional property that carries a default, so every DTO field with a constructor default converts from tolerant to hard-failing — visible only against an older Backend, which upstream CI never exercises. Simultaneously, because each Builder builds from an arbitrary commit against a self-hosted Backend of arbitrary age, the newer-app → older-Backend direction becomes the **common** case rather than an edge case.
*Mitigation:* one shared decoder configuration, explicit defaults decoded field by field, and a contract smoke test asserting that every defaulted field decodes when absent — an assertion Android cannot even fail (FR-155, FR-215, FR-216). SI-12 is preserved: unknown fields tolerated, missing **consumed** fields loud.
*Residual:* the SI-12 carve-out requested for the two dispersion flags (OQ-36) is the one deliberate hole and needs an explicit ruling.

**R-9 — Insulin records can be lost through history-cursor bugs that iOS makes far more likely.** *(High. Owner: project lead.)*
Medtronic's bolus cursor is process-local, unpersisted, and advances before the orchestrator persists — tolerable on Android only because a durable slow loop self-heals it. Tandem's history cursor lives only in memory and its sequence markers are record indices, not sequence numbers, with deduplication resting entirely on a unique-timestamp index. iOS terminates apps routinely.
*Mitigation:* SI-8 as a hard rule — no cursor advances past a record that was not successfully decoded; both cursors are durable before either fast path ships (P1); the durable path is the source of truth for insulin totals; write-time deduplication with documented collision winners (FR-137, FR-140).
*Residual:* under-reporting insulin is silent by nature. The Insulin Summary reporting only completed deliveries (SI-7, FR-90) limits the blast radius but does not detect a gap.

**R-10 — Bond removal is impossible and peripheral identity is unstable, so trust failures can strand a user permanently.** *(High. Owner: project lead.)*
Every Android recovery path calls `removeBond()`, which has no iOS equivalent at any tier; recovery becomes a manual Settings → Forget This Device procedure plus physical access to the Pump's pairing menu. Meanwhile the peripheral identifier is per-app-install, so a reinstall, a bundle-ID change or a device migration silently loses the binding — and Builders reinstall constantly, because TestFlight builds expire every 90 days.
*Mitigation:* persist the Pump serial as the durable identity and re-bind on serial match; port the counter-based restraint policy faithfully (never invalidate after a successful session; tolerate the full consecutive-failure budget); the broken-pairing wall explains the manual procedure in place of doing it (FR-11, FR-12, FR-17, FR-19).
*Residual:* UJ-4's wall is an explanation, not a fix. Expect it to be a recurring support case, compounded by Tandem's one-connection-at-a-time constraint colliding with t:connect.

**R-11 — The three Safety Constants have no owner and iOS multiplies the surfaces.** *(High. Owner: project lead.)*
On Android the Glucose Validity Bound is duplicated across roughly nineteen sites — including 20..499 and 21..500 off-by-one variants and a SQL literal — held equal only by a comment-stripped source scan with no iOS counterpart. iOS adds the Watch app, an iOS widget extension, a Watch complication extension and an App Group boundary. The epoch offset is the worst of the three: getting it wrong shifts every Pump timestamp by the device's UTC offset (Foundation has no `LocalDateTime`, so the decode-then-reanchor step does not port literally) and silently destroys the freshness, staleness and coverage architecture everything else rests on.
*Mitigation:* SI-4 — one definition in a module both the app and the Watch app link (P0.2), plus an **inverse** drift guard: CI fails on any bare `20`, `500`, `18.0156` or `1199145600` in a glucose or Pump-time context outside the canonical definitions (FR-217). The inverse scan is self-maintaining; a new duplication site fails without anyone updating a list.
*Residual:* the guard cannot see a constant that arrives from the Backend. SI-11 covers that direction (Safety Limits may only narrow).

**R-12 — A name-only port of the security gates yields Required Checks that are permanently green and test nothing.** *(Medium-High. Owner: project lead.)*
Semgrep's Kotlin and Java packs produce exactly zero findings on Swift, and no Swift ruleset of comparable depth exists from any vendor. Copying the workflow by tool name would manufacture false assurance on a health-data app. Compounding: SwiftPM advisory coverage in OSV and the GitHub Advisory Database is a small fraction of Maven's, so the dependency gate will be green far more often than it is correct.
*Mitigation:* CodeQL Swift `security-extended` as the blocking analysis with a seeded finding proving it can fail the build; a non-zero-rule-count and non-zero-analyzed-files canary; both OSV and Dependabot; a deliberately tiny dependency surface as the primary control; the coverage delta stated plainly in the security document rather than implied as parity (FR-200, FR-201). Invariants move **out** of static analysis and into the type system, the API-surface snapshot and replay tests.
*Residual:* Swift static-analysis depth remains materially thinner than Kotlin's. Recorded as a parity loss, not papered over.

**R-13 — The honest-coverage claim loses its permanence guarantee.** *(Medium-High. Owner: project lead.)*
Android's foreground-service notification is unconditional, undismissable and always present, with caching that exists specifically so a redundant service start cannot overwrite "this phone is NOT watching" with reassuring copy. iOS has no undismissable persistent surface: a Live Activity is user-dismissable and expires. A degraded state can therefore vanish from every out-of-app surface overnight — precisely the window the app exists to cover.
*Mitigation:* the Coverage Claim becomes declarative — one selector, one expiry, four decay mechanisms (widget timeline entry, Live Activity stale date, Watch-local decay, scheduled lapse notification), with pessimistic seeding and a never-overwrite-a-degraded-status rule ported to every surface (FR-83 – FR-85, FR-126). Silence itself becomes the alarm.
*Residual:* a force-quit app is never relaunched by Core Bluetooth, so the wrist's decay to "no recent data" is the only signal. That is by design and is disclosed (FR-15, FR-85).

**R-14 — macOS runner cost is the most likely reason someone weakens a gate.** *Severity: medium.*
Every build, test and UI-test gate must run on a macOS runner, which carries roughly a 10x minute multiplier on a private repository and queues more slowly than Linux. The required-check set is therefore under standing cost pressure, and the cheapest-looking relief — removing a check, adding a `paths:` filter, or making one non-required — is exactly the change that silently reduces coverage.
*Mitigation:* keep the upstream repository public (OQ-49); move every platform-independent target to `swift test` so it runs on Linux; treat the roster of five Required Checks as fixed by FR-197, with SM-16 as the counter-metric that names weakening a gate as a failure rather than an optimisation.

*Identifier note: **R-15 through R-19 and R-23** were assigned during drafting and retired before this pass. The live set is **R-1 – R-14 and R-20 – R-22**; a reader finding no other gap has found none.*

**R-20 — The promotion, changelog and sync-back pipeline is ported from a pipeline that was never exercised end to end.** *(Medium. Owner: project lead.)*
Android documents it as "built, unit-proven in parts, never exercised end to end", with the lockfile-regeneration path labelled an unproven path. Porting it wholesale makes the first iOS release its own first live test.
*Mitigation:* exercise the full cycle on a throwaway repository before the first release; verify empirically that the dependency bot reports the type the auto-merge tier matches on; author the auto-merge label relay here rather than porting a reference to a file Android does not actually have (FR-192, FR-194).
*Residual:* none material once exercised; the risk is entirely one of skipping the rehearsal.

**R-21 — Two GPL-3.0-only distribution residuals are unresolved and gate the highest-traffic published pages.** *(Medium. Owner: PM and counsel.)*
Whether "users become the manufacturer of their own personal medical device" — today reserved for third-party forks that add device control — now describes **every** Builder; and whether adding a hardware validator as an internal TestFlight tester on a maintainer's account would be a conveyance under Apple's terms.
*Mitigation:* decision 9 already forecloses the second by construction (the validator builds from their own fork under their own account). For the first, the install page states the builder relationship factually and asserts no legal conclusion in either direction, pending counsel review before the first tagged release (FR-223, FR-234).
*Residual:* if counsel says the framing applies, the question becomes whether it changes only the disclaimer wording or also whether fork-and-build instructions are published publicly at all (OQ-56).

**R-22 — Contributor documentation drifts from enforced behaviour, and the Android prose already carries at least six such drifts.** *(Low-Medium. Owner: project lead.)*
Copying the prose would import errors that make a contributor's local run weaker than CI while claiming parity.
*Mitigation:* generate or verify the Required Check table against the configured ruleset in CI, and drive local reproduction from the same committed script CI invokes so the two cannot diverge (FR-197, FR-213). SM-11 tracks it.
*Residual:* prose about *why* a gate exists still drifts; only the enforced list is mechanically checked.

---

## 15. Open Questions

Every question below is unresolved in this PRD. Questions marked **(blocking)** must be answered before the implementation work they gate begins.

Each question carries a stable `OQ-n` identifier, cited from §12, §13, §14 and from the feature sections. **An ID retired by a ruling is never reused and never renumbered**, so a gap in the sequence is a settled question, not a missing one. Ten questions earlier drafts carried here are now settled in the sections that own them and have been struck: the Keychain accessibility class (device-only after-first-unlock, SI-10, FR-204), reconnect policy (FR-13 — no attempt cap, no give-up condition), wrist alert transport (FR-128/FR-129 — Watch-scheduled primary, mirroring fallback), the glucose validation window (FR-32 against current Safety Limits, FR-138 against the absolute Glucose Validity Bound, asymmetric by design), the deployment floor (NFR-1 — iOS 17.0 / watchOS 10.0), the calibration Capability (FR-30 — removed, the set is six), the accessibility identifier registry owner (FR-177 owns the registry and the per-surface requirement, NFR-30 owns the system-wide parity counts, FR-208 owns the check), the graph Y axis (FR-52/FR-133 — default 40-300, expanding, never pinning), the Watch appearance preference (deleted; §7 forced loss) and alert-history retention (FR-139 — the user's retention window, pruned on schedule).

The eleven retired identifiers are **OQ-1 – OQ-6, OQ-8, OQ-28, OQ-30, OQ-44 and OQ-57**. Those eleven gaps are exactly the eleven struck questions above and nothing else is absent: the live set is the 51 questions, of which five (OQ-36, OQ-48, OQ-49, OQ-50, OQ-56) are now RESOLVED in place and retained for their rationale below, running OQ-7 through OQ-63 with no other break. A reader finding a gap not on that list has found a defect. Trend-arrow provenance is the eleventh question that closed, but it was never a standalone `OQ-n` — it lived inside OQ-7, is now owned by FR-46, and is retired in place rather than being given an identifier on its way out.

### Enforcement tier and the Safety Invariant Register

- **OQ-7** — **Do the two Tandem device-reported decode gates belong in the Safety Invariant Register rather than in a Driver-general FR?** Both are now owned by FR-32 (5.2) with pinned tests and Trace-Replay fixtures: (a) the `egvStatusId` sensor-validity gate, which accepts a reading only when the device's own status byte is in 1…3 and is independent of the Glucose Validity Bound — without it, warm-up and error sentinels render as real glucose; (b) the `ControlIQIOBResponse` selector byte, which chooses which of the two IOB values in the same response is live — picking wrong shows a plausible, wrong, dosing-relevant number that no range check would catch. Both failure modes produce an in-range number no other check can detect, which is the register's own admission criterion. Trend-arrow provenance, previously part of this item, is owned by FR-46 and is closed. A Medtronic equivalent of the sensor-validity gate must be identified before that Driver leaves Beta.

### Devices, Drivers and hardware validation

- **OQ-9** — **(blocking for Medtronic) Spike (b):** whether a 780G's discovery filter accepts an iOS advertisement carrying the identity as a standard GAP local name rather than as manufacturer-specific data under company id 0x01F9. Needs a physical Pump; neither the lead developer nor DanielDanielson has one. Who validates, and does FR-6 ship gated behind an unvalidated label until they do?
- **OQ-10** — Whether an already-bonded Medtronic Pump will reconnect to a backgrounded iPhone by stored peer identity rather than by advertised name. If it does, FR-16's foreground-only degradation is narrower than stated. Cannot be assumed and cannot be tested without hardware.
- **OQ-11** — The 2-minute scan auto-stop and the 10 s discovered-device age-out have no Android counterpart. Confirm both values or accept them as newly introduced for iOS.
- **OQ-12** — Should the 45 s connect watchdog be user-visible as a countdown, or silent until it fires?
- **OQ-13** — Android's live CGM path and live Basal path have known validation gaps that the pairing/connection layer does not touch; flagged only so 5.3 does not assume 5.1 resolved them.
- **OQ-14** — Does the iOS Driver API version constant reset to 1 for the new SDK, or inherit Android's 5 to keep cross-repo changelogs aligned? (Android currently carries a three-way drift: code says 5, docs say 2, its own example says 1.)
- **OQ-15** — Should the Simulated Driver and Trace-Replay Driver be excludable from a release build by the compile-time exclusion of FR-27, or always present? FR-35 and FR-36 currently ship them in every configuration including release. CI's all-Drivers-enabled build (FR-27, FR-208) removes the coverage argument for excluding them; what remains is whether two non-clinical data sources should sit in the Driver list where a Builder could activate one by mistake.
- **OQ-16** — Data sync has no Capability protocol on Android — it is a pure activation and mutual-exclusion tag. Keep it that way, or give it a protocol now that a Backend-mediated Nightscout source is a first-class shipped source?
- **OQ-17** — Verification Status is net-new metadata with no Android equivalent. Who assigns it, and does a change to a Driver's protocol code automatically demote it from Verified pending re-validation on DanielDanielson's hardware?
- **OQ-18** — Trace-Replay fixtures: what is the de-identification standard, and who reviews a submitted trace before it lands in a public repo?

### Dashboard, alerting and the wrist

- **OQ-19** — CGM-active percentage assumes exactly 12 Glucose Readings per hour (Android behaviour). A source with a different cadence misreports coverage — should the expected cadence be declared by the Driver's glucose-source Capability instead of hard-coded?
- **OQ-20** — SI-5 forbids the Alert Floor from firing on thresholds neither the user nor their Backend set, but FR-47's severity banding colours from the default Alert Threshold set (55/70/180/250) when nothing has been set. Confirm colouring from defaults is acceptable while alerting from them is not, and that the two are visibly distinguishable.
- **OQ-21** — Dynamic Type and the fixed 64pt hero numeral: Android has no equivalent, so there is no reference behaviour. Does the hero value scale with Dynamic Type at all, or stay fixed while only surrounding text scales?
- **OQ-22** — Is iPad a supported target for this release? FR-56 (chart detail landscape) assumes iPhone only.
- **OQ-23** — Carried from research and unanswerable from the Android repo: when the iPhone is suspended or unreachable, what must the Watch app still be able to show? (Owned by 5.7, but it constrains what the dashboard's data relay must produce.)
- **OQ-24** — **(product ruling needed)** Coverage Claim wording without Critical Alerts: "watching" versus "watching, but you may not hear it". Strict SI-6 argues for the caveat; it would show for nearly every Builder nearly always, risking desensitization of the one surface built to be believed. FR-66 currently puts the caveat in claim *detail* copy, not in claim *state*.
- **OQ-25** — FR-76's phone-side re-alarm ladder cadence and cap (currently 5 repeats at 120 s, ending 10 minutes after the initial alarm) is invented, not ported — it substitutes for two Android mechanisms with no iOS analogue. It needs a real-user tuning pass before the first tagged release, together with FR-129's Watch-side 30-minute ladder, because the two are what the user actually experiences side by side.
- **OQ-26** — Achievable background Core Bluetooth evaluation cadence against a real t:slim X2 is unmeasured and gates whether the 360,000 ms Fresh window is honest. Requires DanielDanielson's fork build on their own hardware. Sequence early (P4) — the honest response to a slow cadence is a coverage-copy change, not a wider Fresh boundary.
- **OQ-27** — Whether the informational tier (IOB warning, no-data, unknown types) should be permitted to break through Focus at all, given Android routes it to a non-DND-bypassing channel and iOS `.active` is the honest equivalent — confirmed as-is, but worth a ruling if caregivers complain about missed data-gap alerts.
- **OQ-29** — Confirm the live glanceable surface's OS lifetime bound against the shipping iOS/watchOS version, and confirm the restart policy when it expires overnight. (FR-119)
- **OQ-31** — Is a shareable watch-face configuration file in scope for v1 as the closest analogue to Android's watch-face variant push, given it is device-only and unverifiable in the Simulator? (FR-118)
- **OQ-32** — Should the Watch app hold a Backend credential and fetch independently in Backend-connected mode, or does every wrist value come from the app only? (Affects FR-122, FR-126 and the Keychain threat model; 5.8 owns the answer.)

### Meals, AI and analysis

- **OQ-33** — Does the Backend return an image for a food record, or does the Home recent-meal card keep Android's neutral placeholder thumbnail permanently?
- **OQ-34** — Is the read-only re-log sheet acceptable for v1, or should the port block on the Backend gaining a create-record-from-common-food path?
- **OQ-35** — Should the 5xx meal diagnostic log survive at all under SI-9, given the error body can contain food identity and carb values? If the scrubber cannot guarantee otherwise, the log must be dropped rather than weakened.
- **OQ-36** — **RESOLVED.** The SI-12 carve-out is approved: `wideSpread` and `identityAgreement` are marked optional-with-default in the Contract Pin, so the exception is explicit in the contract rather than implicit in the client. They are presentation hints on a meal carb estimate, not safety-critical values, and an exception a reader can see beats one they cannot.
- **OQ-37** — Is the Glucose-Reading-at-event unit conversion (FR-92 — a deliberate divergence from Android's raw mg/dL column) approved as an intentional Parity Ledger entry?
- **OQ-38** — Is a debug-only bundled-sample-photo injector in v1 scope, given the Simulator has no camera and the capture path is otherwise unreachable in the developer's loop?
- **OQ-39** — Confirm the Backend's actual AI inference ceiling so the single AI request timeout is set from evidence rather than inherited from Android's 90 s.
- **OQ-40** — Confirm that `GET /api/ai/provider` returning exactly 404 for "no provider configured" is pinned by the Contract Pin, since it is the sole discriminator between the terminal no-provider state and the retryable offline state.
- **OQ-41** — Should the "Disable TTS" menu copy be renamed to match the "spoken responses" vocabulary used elsewhere, accepting a deliberate copy divergence from Android?
- **OQ-42** — Does the maintainer's device pass for watchOS dictation need to gate release, given the lead developer has no Apple Watch and dictation does not function in the watchOS Simulator?

### Data, storage and Backend

- **OQ-43** — What is the real per-Driver enqueue rate? The outbound queue bound is fixed at 20,000 rows (FR-142) and is sized from Tandem's 15-second fast cadence at roughly 8 rows/min; a Driver with a materially different cadence changes the hours-without-upload arithmetic that number was chosen from.
- **OQ-45** — **ASSIGNED TO ARCHITECTURE** (not unanswered; the product requirement is settled and only the mechanism is open). In plain terms: the app must be allowed to talk to a **Backend** on the user's own home network over plain `http`, while being forbidden from doing so with anything on the public internet. Apple's App Transport Security is the OS-level control for that, and it is a poor fit — its exceptions are written per *domain name* and accept neither IP addresses nor address ranges, which is exactly how a home-network server is usually addressed. **Settled and not in question:** no plaintext request leaves the device for any host that is not a literal loopback, private (RFC1918), carrier-NAT (100.64.0.0/10) or link-local address or a `.local` name, classified by literal address only, never by DNS lookup, identically in every build configuration (FR-150, NFR-20). **Open:** which `Info.plist` configuration actually achieves that, and what proves it on a device. Whether `NSAllowsLocalNetworking` covers raw private-IP literals rather than only single-label and `.local` names is unverified, and its presence causes `NSAllowsArbitraryLoads` to be ignored. Architecture settles it empirically and records the verified baseline; FR-204's Entitlements and Plist Guard then prevents that baseline being broadened. No section may state a plist posture as fact before then.
- **OQ-46** — Should the Settings Network section carry its own persistent "Local Network access denied" banner alongside the insecure-transport banner, or is the in-section card of FR-162 sufficient? The condition is invisible in the Simulator and will otherwise be misdiagnosed as a Backend fault.
- **OQ-47** — Does the ATS posture need explicit App Review justification text drafted, given internal TestFlight distribution under a Builder's own account triggers no Beta App Review but a Builder who later distributes externally would?

### Build, distribution and gates

- **OQ-48** — **RESOLVED.** Fault injection is gated on a dedicated compile-time flag that is OFF in every build the pipeline produces, in both channels; only a local Xcode build enables it (FR-176). Gating on "not TestFlight" was rejected because the `develop` channel ships through TestFlight too, so that test would disable the Developer section for legitimate development builds while still leaving it reachable elsewhere.
- **OQ-49** — **RESOLVED.** The upstream repository stays **public indefinitely**. This keeps macOS runner minutes off the ~10x private multiplier and removes the standing cost pressure on the five Required Checks (R-14). It is also consistent with everything else: the project holds no secrets, ships no binary, and every Builder forks it anyway.
- **OQ-50** — **RESOLVED.** One App ID set per Builder, registered once. The channel is a build-time branch choice — `develop` for a development build, `main` for a production build — and a new build replaces the installed one rather than sitting beside it (FR-182). This mirrors the verified Loop browser-build model, where a second concurrent app requires its own distinct identifier set.
- **OQ-51** — Which bundled alert sounds ship, and who authors and licenses them? FR-67 requires an alarm-like low set distinct from the notification-like high and informational sets, plus "Default" for every tier and "Silent" for the informational tier; the assets themselves are unspecified and must be GPL-3.0-compatible. User-imported audio is deferred (D-9), so the bundled set is the entire v1 sound library and a missing asset has no fallback.
- **OQ-52** — What is the promotion criterion that moves `UI Tests (Simulator)` from non-required to a sixth Required Check?
- **OQ-53** — What licenses go on the dependency license allowlist at day one, and who arbitrates a request to add one — project lead alone, or lead plus a licensing review? (The GPL-3.0-only interaction with the EC-JPAKE implementation's licence is the specific case.)
- **OQ-54** — Should the required-check roster comparison read the branch-protection ruleset via the API (authoritative but needs an admin-read token and is not fork-runnable) or compare against a committed copy of the ruleset (fork-safe but can itself drift)?
- **OQ-55** — Should CodeRabbit's `fail_commit_status` be flipped to true so its Medical Safety and BLE Protocol Safety checks actually block merge, or does it stay advisory now that those invariants are enforced mechanically? Does the project want `gitleaks` as a hard-failing step inside `Static Analysis Gate` (FR-200), given Android deliberately declined a third secret-scanning pass — a divergence from a recorded Android decision, justified here by CodeRabbit's non-blocking commit status?
- **OQ-56** — **RESOLVED, and the resolution is a decision rather than a legal opinion.** No counsel review will be obtained. The published position is that a Builder who forks the repository, supplies their own Apple Developer credentials and builds their own binary already stands in the builder relationship, and the project supplies only the source that makes that possible. The disclaimer states that relationship **factually** and asserts no legal conclusion about manufacturer status — mirroring how the established open-source iOS diabetes projects describe it. `[NOTE FOR PM]` Recorded as the product owner's explicit call, made with the risk stated; this PRD offers no legal advice.
- **OQ-58** — Should the fork template ship a scheduled workflow that rebuilds automatically before the 90-day expiry, or is an automatic rebuild a Builder never sees a worse failure mode than a build that visibly lapses?
- **OQ-59** — What is the committed scheduled-rebuild cadence and the exact escalation thresholds for the in-app expiry countdown (30/14/7/3/1 days assumed)?
- **OQ-60** — Is a 90-day retention on upstream Simulator `.app` release assets sufficient, given that upstream release assets are the only artifact the lead developer can run?
- **OQ-61** — Does the lead keep a 1Password-backed local signing convenience path for their own maintainer and validation builds, or is every signing path fork-owned with no exception? It must never become a project-held signing identity and must not be referenced from any fork-facing workflow.
- **OQ-62** — Is a Builder who edits the disclaimer, adds a crash-reporting DSN, or changes an Alert Threshold default in their own fork still described as running "GlycemicGPT" in these documents, and does the privacy document need to say so explicitly?

### Contracts this PRD names but does not specify

These are deliberately architecture's to write, but they gate downstream phases and are listed here so nobody discovers them mid-build. Each is a **blocking** input to the phase named.

| # | Contract | Why the PRD does not settle it | Gates |
|---|---|---|---|
| **C-1** | **Driver lifecycle contract** — the exact states, transitions and re-entrancy rules a **Driver** must honour between registration, activation, connection, suspension and teardown. | Mechanism, not capability. §5.2 states what activation must guarantee, not how a Driver is driven. | P1 (Driver work) |
| **C-2** | ~~Capability slot resolution~~ — **RESOLVED, no longer a contract gap.** FR-23 and FR-30 now share one model: the **set of active Driver ids** is what persists, Capability slots are **derived** from it by a total deterministic function with a stable id tiebreak, and no slot table exists. The divergence an earlier draft resolved by precedence cannot arise. | Was a genuine defect — two sections describing one mechanism differently. | — |
| **C-3** | **Phone↔Watch Coverage Claim payload schema.** FR-83 and FR-126 pin the claim's behaviour on each side but no wire schema exists, and the two sections name state vocabularies that must be proven identical. | SI-4 requires one definition; the transport is architecture's. | P2 (Watch) |
| **C-4** | **Local database schema and migration policy.** The iOS store starts at v1 with no Android inheritance (there is no migration path, NG-14), but no schema or forward-migration rule is stated. | Storage design is architecture's. | P1 |
| **C-5** | **Outbound upload payload.** FR-140 fixes the wire quirks that must be preserved and states Glucose Readings are never enqueued, but the full payload shape lives in the **Contract Pin**, not here. | Owned by the vendored OpenAPI document (FR-214). | P1 |

`[NOTE FOR PM]` C-2 was the only defect among these rather than a deferral, and it is now closed. C-1, C-3, C-4 and C-5 remain legitimate architecture deferrals.

## 16. Assumptions Index

Every `[ASSUMPTION]` in this document, surfaced for confirmation. Text is carried verbatim from the owning section; the ID and the owning FR are added for traceability. Confirming or rejecting any of these is a PM action, not an engineering one.

`A-n` IDs are stable and are never reused or renumbered. Six are retired here because a ruling turned the assumption into a requirement, and a gap in the sequence means exactly that: **A-4** (a disabled Driver is excluded by a compilation condition and CI builds an all-Drivers-enabled configuration — FR-27), **A-27** (the graph Y axis defaults to 40-300 and expands, never pins — FR-52, FR-133), **A-28** (the Watch appearance preference is deleted, not rebound; the Android face theme is a forced loss in §7), **A-29** (alert history follows the user's retention window, pruned on schedule — FR-139), **A-31** (the outbound queue bound is 20,000 rows — FR-142) and **A-45** (the deployment floor is iOS 17.0 / watchOS 10.0 — NFR-1).

### Assumptions from 5.1 — Pump Connection and Pairing

- **A-1** [ASSUMPTION: the 10 s age-out for discovered pumps in the scan list is an iOS-side choice; Android never aged entries out and has no corresponding number.]
- **A-2** [ASSUMPTION: Android has no scan timeout at any layer; the 2-minute scan auto-stop bound is introduced for iOS and matches the pump-side pairing-code timeout documented as "a couple of minutes".]
- **A-3** [Implicit assumption, stated in FR-9: the 45 s UI connect watchdog has no Android counterpart and is chosen to sit above the Driver's 30 s authentication timeout so the Driver's own transition always wins.]

### Assumptions from 5.2 — Drivers and the Device Catalog

- **A-5** [ASSUMPTION: Verification Status is static metadata declared by the Driver and cross-checked in CI against the Device Verification Matrix; Android carries no equivalent field and this is net-new.]
- **A-6** [ASSUMPTION: the Simulated Driver uses a project reverse-domain id and ships in every configuration including release; Android's analogue is a standalone JVM project outside `settings.gradle.kts`, so this is net-new work rather than a port.]
- **A-7** [ASSUMPTION: Trace-Replay traces are de-identified before commit — glucose values, insulin doses and device serial numbers are synthesized or offset — because a raw capture would put health data in the repository, and a fork-and-build repo is public.]

### Assumptions from 5.3 — Glucose Monitoring and the Dashboard

- **A-8** [ASSUMPTION] The local-network-permission-denied reachability state is surfaced in the status row itself rather than only inside Settings. (FR-44)
- **A-9** [ASSUMPTION] Chart detail forced-landscape targets iPhone; on iPad the orientation request is not honoured the same way and the detail chart renders in the window's current orientation. (FR-56)

### Assumptions from 5.4 — Alerting and the Coverage Contract

- **A-10** [ASSUMPTION: Android encodes urgency in a custom vibration waveform and an alarm-volume boost, neither of which exists on iOS; a 2-minute x 5 ladder is the chosen temporal substitute and is a tuning parameter, not a ported constant.] (FR-76)
- **A-11** [ASSUMPTION: keeping the Not-Watching Reason set at five preserves parity with the Android wire vocabulary that the Watch app already decodes; the extra iOS notification-degradation causes are additive detail text under NOTIFICATIONS_DENIED, not new states.] (FR-83)
- **A-12** [ASSUMPTION: the Backend Active expiry window is not present in Android, which never needed one; reusing the Fresh boundary keeps a single number driving all four decay mechanisms.] (FR-84 — the boundary is 360,000 ms, stated there and not restated as a second site here)

### Assumptions from 5.5 — Insulin, Meals and Analysis

- **A-13** [ASSUMPTION: the SmartGuard auto-basal micro-bolus exclusion happens inside the Medtronic Driver, at the point the frame is decoded, so no downstream surface applies a second filter — the Insulin Summary and Recent Boluses consume whatever the Driver reports as a completed Bolus.] (FR-90)
- **A-14** [ASSUMPTION: the upload-in-progress recovery marker is a small on-device flag, not a persisted copy of the photo or of any estimate.] (FR-95)
- **A-15** [ASSUMPTION: the meal photo upload uses the same 90-second request budget Android's vision client uses, and is not moved to a background session in v1.] (FR-95)
- **A-16** [ASSUMPTION: the dispersion flags `wideSpread` and `identityAgreement` are marked optional-with-default in the Contract Pin, making them an explicit carve-out from SI-12's fail-loudly rule for missing consumed fields; every other consumed field in the meal payloads remains required.] (FR-98)
- **A-17** [ASSUMPTION: the nutrition, comorbidity, provenance and dispersion payload shapes are unchanged from the Android contract and are covered byte-for-byte by the Contract Pin.] (FR-102)

### Assumptions from 5.6 — AI Chat

- **A-18** [ASSUMPTION: the menu item copy "Disable TTS" is retained verbatim from Android even though this section otherwise calls the feature spoken responses; no evidence proposes replacement copy.] (FR-113)
- **A-19** [ASSUMPTION: voices are sorted by quality descending, then region, then name, and labelled `<region> - <voice name>` with an `(HD)` suffix for enhanced or premium voices; Android's variant-token derivation produces nonsense against iOS voice identifiers and no iOS copy exists.] (FR-113)
- **A-20** [ASSUMPTION: Android's watchdog copy "Request timed out. Check phone connection." is replaced by "Request timed out. Try again later." because the Watch app's AI request no longer necessarily depends on the phone; no evidence fixes the replacement wording.] (FR-114)
- **A-21** [ASSUMPTION: the Watch chat entry points stay visible in Backend-optional mode rather than being hidden, matching Android's ungated chat complication; the terminal message carries the honesty instead.] (FR-114)
- **A-22** [ASSUMPTION: the Smart Stack chat widget carries no prefill, since Android has no Smart Stack analogue to port; only the app's own complication may prefill.] (FR-114)
- **A-23** [ASSUMPTION: the single AI request timeout value is 90 seconds, adopting Android's phone-side figure — its code documents LLM inference at 20-60 s — because the Backend's own inference ceiling is unverified.] (5.6 feature-specific NFRs)

### Assumptions from 5.7 — Apple Watch and Glanceable Surfaces

- **A-24** FR-118: shipping a shareable `.watchface` configuration is optional for v1; it is device-only and cannot be validated in the Simulator, so it is not on the critical path.
- **A-25** FR-119: the OS bound on the live glanceable surface is 8 hours active with up to 12 hours of residual Lock Screen presence; the exact figures must be re-verified against the shipping OS, and the surface must never present a value older than its Freshness Tier permits regardless.
- **A-26** FR-122: the metered wrist-refresh allowance is a system value in the tens per day; the design must not depend on a specific number (it is read at runtime, never hardcoded).

### Assumptions from 5.8 — Data, Storage, Sync and Backend

- **A-30** FR-141: the stale-in-flight reclaim window is 15 minutes on iOS, not Android's 60 seconds, because a system-deferred background upload legitimately takes longer than a minute and a shorter window would re-send batches the system is still holding.
- **A-32** FR-150: a Backend URL carrying a path, query or fragment is rejected at save time with a specific message — a deliberate divergence from Android, which silently ignored a path prefix and then requested a different URL than the user typed.

### Assumptions from 5.9 — Onboarding, Settings and Accessibility

- **A-33** [ASSUMPTION: the app's display name in permission-fallback copy is "GlycemicGPT", matching Android's strings; the fork's bundle display name is a Builder-controlled value and the copy reads from it.]
- **A-34** [ASSUMPTION: the Settings section order in FR-166 promotes Android's Glucose Units card, Data Retention card and Open Source Licenses row to their own top-level sections. If the PM prefers Android's nesting, the equivalent order is Account, Network, Drivers, Sync (containing Retention), Meal Intelligence, Notifications, Watch, Appearance (containing Units), About (containing Licenses), Developer — the surfaces and their identifiers are identical either way.]

### Assumptions from 5.10 — Build, Sign, Install and Update

- **A-35** [ASSUMPTION: the fork secret set is `TEAMID`, `FASTLANE_ISSUER_ID`, `FASTLANE_KEY_ID`, `FASTLANE_KEY`, `MATCH_PASSWORD`, `GH_PAT` — six items, following the Loop/xDrip4iOS precedent; the Android repo fixes no equivalent naming.] (FR-180)
- **A-36** [ASSUMPTION: the scheduled rebuild fires every 30 days, chosen so two consecutive failures still leave time to act; the Android repo has no expiry analogue and fixes no cadence.] (FR-186)
- **A-37** [ASSUMPTION: build expiry is computed as the recorded upload timestamp plus 90 days, since no on-device API reports a TestFlight build's expiry.] (FR-187)
- **A-38** [ASSUMPTION: expiry prominence escalates as a passive Settings row until 30 days remain, a persistent non-blocking banner at 14, and a local notification at 7, 3 and 1 — the Android repo has no expiry surface to derive thresholds from.] (FR-187)
- **A-39** [ASSUMPTION: CFBundleVersion is minutes since a fixed epoch; the exact unit is an implementation choice, the monotonicity property is the requirement.] (FR-191)

### Assumptions from 5.11 — Engineering Gates and Contract Guards

- **A-40** [ASSUMPTION] Exact timeout-minutes values for the macOS-hosted Static Analysis Gate, iOS Gate and UI Tests (Simulator) jobs are set at implementation time; only the requirement that every job declares one is fixed here (Android's dependency-scan and build jobs have none, and that gap is closed rather than ported).
- **A-41** [ASSUMPTION] (FR-211) The Android repository has no equivalent dependency license allowlist gate; the allowlist's initial contents are set at implementation time from the resolved graph's actual licenses.
- **A-42** [ASSUMPTION] (FR-218) The Android repository's lead-owned `.github/dco.yml` indicates the DCO app is the sign-off enforcement mechanism; the local commit-msg hook warns about a missing `Signed-off-by` trailer but does not block.

### Assumptions from 5.12 — Documentation, Licensing and Policy

- **A-43** [RETIRED — moot] Assumed things about how the website ingests documentation. How glycemicgpt.org discovers, orders and routes this repository's `docs/` tree is the `website` repository's concern and is out of scope for this PRD (FR-220 Out of Scope).
- **A-44** [RETIRED — moot] Assumed a website-side link check. Link checking is entirely in-repo: relative links are checked within this `docs/` tree, and every link leaving it is absolute (FR-219).
- **A-46** [ASSUMPTION: the install page states the builder relationship factually — the user forks, signs and installs their own build — and asserts no legal conclusion about manufacturer status in either direction, pending counsel review.] (FR-223)

### 6. Non-Functional Requirements

- **A-51** [ASSUMPTION: iOS 18's supported-iPhone set is identical to iOS 17's, and watchOS 11 drops Series 4, Series 5 and SE 1st generation. Verify against Apple's published support lists before the floor is written into build settings; if either is wrong the trade-off above changes, not the requirement to publish one number.] (NFR-1 — the floor itself is settled at iOS 17.0 / watchOS 10.0; what is assumed here is Apple's device support lists, not the floor)
- **A-52** [ASSUMPTION: iPhone XS, XS Max, XR, SE 2nd generation and later for the phone; Apple Watch Series 4 and later plus SE and Ultra for the wrist. Regenerate from Apple's published lists at implementation time.] (NFR-1, supported device set)
- **A-53** [ASSUMPTION: no responsiveness target in §6.2 has an Android counterpart to port — the Android client publishes none. These are new targets, chosen to be provable in the Simulator on the floor runtime plus one device-tier confirmation, and they should be reviewed by the project lead.] (§6.2)
- **A-54** [ASSUMPTION: TLS 1.2 as the negotiated minimum, i.e. the platform default with no downgrade. Confirm that no self-hosted Backend deployment the project documents requires anything older; if one does, that is a Backend fix, not an app exception.] (NFR-20)

### 8 – 10. Matrices, Validation Tiers and Gate Substitutions

- **A-55** [ASSUMPTION] Medtronic spike (a) runs at Validation Tier 3 on macOS Core Bluetooth with a second Core Bluetooth peer standing in for the Pump's central role. If macOS and iOS diverge on `CBCentral`-to-`CBPeripheral` resolution, the spike re-runs at Tier 4 and its answer does not transfer. (§8.4; compare A-49)
- **A-56** [ASSUMPTION: Builders use internal testing on their own team, which requires no Beta App Review; external TestFlight testing does require Beta App Review, so a Builder who distributes to other people re-enters review territory and this assumption stops holding for them.] (§10.4; compare OQ-47)

### New in this back matter (§11 – §15)

- **A-47** [ASSUMPTION: v1 scope is the full FR-1 through FR-237 set minus exactly the deferrals D-1 through D-9 in §12.2; no feature section is thinned for schedule, because the mandate is full parity. FR-237 is the one requirement added after the FR space was first published; it was created to give five §7 forced losses a disclosure surface that no FR previously required to exist, and it extends 5.12's range to FR-219 – FR-237. Nothing was renumbered to accommodate it.]
- **A-48** [ASSUMPTION: every success metric in §13 is measurable from the repository, CI, the Device Verification Matrix or public community channels, and no metric will be redefined in a way that requires telemetry — the project ships none (NG-6).]
- **A-49** [ASSUMPTION: Medtronic transport spike part (a) is answerable on macOS with a second BLE central and no Pump, because Core Bluetooth is fully available on macOS; only part (b) requires a physical 780G. If part (a) turns out to need iPhone hardware, it moves onto DanielDanielson's device time and P0.1 is no longer early.]
- **A-50** [ASSUMPTION: fork count, voluntary install reports and issue-class labels are the only externally observable proxies for Builder install success; the project cannot read a Builder's Actions logs, so SM-1, SM-2 and SM-12 depend on a structured issue template being adopted and used.]
