---
title: Downstream Readiness Review — PRD GlycemicGPT for iOS and Apple Watch
subject: prd.md (144,703 words, 237 FRs, 17 sections) + addendum.md
reviewed: 2026-08-03
lenses: solution architect, UX designer, epic/story planner
question: can they proceed, and where will they get stuck
---

# Downstream Readiness Review

## 0. How this review was done

The whole of `prd.md` was read — §0–§4 and §5.3, §5.4, §5.7, §8–§16 directly; §5.1–5.2, §5.5–5.6, §5.8–5.9, §5.10–5.12 and §6–§10 through five parallel deep readers working from the same three-lens brief and the same context (§0–§4, the six journeys, the Glossary, the Safety Invariant Register, and `addendum.md`). Load-bearing cross-references were followed to their targets rather than taken on trust, and a number of claims were checked mechanically against the document and against the Android source at `android-unofficial`.

Findings are tagged by lens. Severity is:

- **Blocking** — work on that area cannot responsibly start. Something must be decided by someone who is not the downstream owner.
- **High** — work can start, but a wrong guess here is expensive to unwind.
- **Medium** — the owner will invent something reasonable; it should be ratified rather than discovered.
- **Low** — hygiene, or a correctness defect in the document rather than in the product.

---

## 1. Verdict

**All three can start. None of the three can start everywhere.**

This is an unusually strong PRD. It is specified at a level of precision most implementation plans never reach: single-owner rules with named cross-references that actually resolve, pinned boundary pairs that are test cases already written, an enforcement mechanism attached to every safety invariant, a validation-tier model that tells you which of your green tests are lying, and a parity ledger whose own rule is that a forced loss with no disclosure surface is a defect. The document's self-awareness is its most valuable property: most of the blocking findings below sit in the gaps between the `[NOTE FOR PM]` blocks, not in territory the authors thought was settled.

The obstacles are not vagueness. They are three specific things:

1. **A small number of load-bearing contracts were never written down** — the Driver lifecycle contract, the phone↔Watch Coverage Claim payload schema, the local database schema and its migration policy, the outbound upload payload, the Driver UI element vocabulary, the build-failure taxonomy, the fork secret set, the authoritative `UIBackgroundModes` list, and the NFR → validation-tier → owner map that NFR-34's own acceptance gate consumes. Each is a contract, not an implementation choice, so architecture cannot settle it alone.
2. **A handful of requirements are specified in terms of platform signals the PRD elsewhere states iOS does not provide.** FR-11/FR-12's restraint counters, FR-118/FR-134's active-face detection, FR-166's force-quit condition, and — most consequentially — SI-1's and SI-9's stated CI mechanisms, which are dataflow properties assigned to syntactic tools. These are not ambiguities; they are requirements that will fail on contact.
3. **Seven open questions are marked blocking and none has an owner or a slot.** OQ-9, OQ-36, OQ-45, OQ-48, OQ-49, OQ-50, OQ-56. Two of them (OQ-45 ATS, OQ-50 App ID count) gate architecture and the build pipeline respectively, and OQ-50 says so explicitly ("must be decided **before** the FR-182 provisioning workflow is built"). A further set of decisions sits outside §15 in prose that reads as settled but is not: NFR-10's battery figure, §8.2's auto-demotion rule, NFR-3's floor-runtime CI question, and the iPad target.

**By lens:**

**Architecture can start now** on the phase-zero spine — the shared safety module (P0.2), the Contract Pin and decoder configuration (P0.4), the Required Check roster (P0.3), the Medtronic spike (a) (P0.1), and the EC-JPAKE differential harness (P0.6). That is genuinely the right ordering and the exit criteria are real. It cannot responsibly start on the Driver subsystem (FR-21–FR-38) until the lifecycle contract, the slot-resolution model and the import allowlist are settled, and it cannot start on the alerting/coverage pipeline's cross-surface half until the Coverage Claim payload schema exists.

**UX can start now** on the dashboard, the coverage/honesty vocabulary and the wrist — these are the best-specified surfaces in the document. It cannot start on onboarding (FR-159 has a trap that makes the product's headline claim unreachable), on the Driver/pairing UI (the element vocabulary is given as counts, not members), or on the docs surface (no owner, no IA, and a persona-to-task gap nobody has addressed). It also needs a ruling on how much of the pinned pixel geometry it is permitted to change.

**Epic planning can start** on the phase-zero work, which is the only part of §12.3 with an FR mapping and testable exit criteria. It cannot produce a full backlog: P1, P2, P4 and P5 have no FR allocation at all, P2 is roughly ninety FRs in one phase with an exit criterion covering a tenth of them, FR sizing varies by about 20× between adjacent FRs, and roughly 25 FRs need clarification before a story can be written against them.

**Severity counts**

| Lens | Blocking | High | Medium | Low | Total |
|---|---:|---:|---:|---:|---:|
| Architect (ARCH-1…84) | 15 | 39 | 28 | 2 | 84 |
| UX designer (UX-1…39) | 4 | 21 | 11 | 3 | 39 |
| Epic/story planner (PLAN-1…45) | 6 | 19 | 17 | 3 | 45 |
| **Total** | **25** | **79** | **56** | **8** | **168** |

Findings tagged with two lenses are counted under the primary one.

One theme cuts across all three lenses and is worth naming before the detail: **the document's cross-reference discipline is excellent and its cross-reference *currency* is not.** Several `[NOTE FOR PM]` residuals describe defects that the target section has since closed (§7.4 on PD-42, §6's notes on PL-72), and one reviewer working from §7.4 duly reported the closed defect as open. Two ID spaces (§14's risks, §15's open-question range) carry claims about their own completeness that are false. None of this is severe on its own; collectively it means a downstream reader cannot trust a `[NOTE FOR PM]` without re-verifying it, which is exactly the property those notes exist to provide.

---

## 2. Architect

### 2.1 Blocking — requirements specified in terms of signals the platform does not provide

**ARCH-1 — FR-11 and FR-12 are built on GATT status bytes that FR-10 and PL-3 say iOS does not expose.** *(Blocking)*
FR-12 tolerates "up to 20 consecutive **encryption failures**" with a pinned test at 19. FR-11 enters the broken-pairing wall on "three consecutive **rapid disconnects**". Checked against the Android source (`plugins/shipped/tandem/.../BleConnectionManager.kt`): `encryptionFailureCount` increments only on `GATT_INSUFFICIENT_ENCRYPTION = 0x08`, and `rapidDisconnectCount` increments only on `GATT_CONN_TERMINATE_PEER_USER = 0x13` — there is no time component at all, so "rapid" is a mis-port of a status byte. FR-10 states plainly: *"A failure category is never inferred from a raw link-layer status byte, because iOS does not expose them."*
*Downstream must invent:* an entirely new behavioural classifier over `CBError` plus timing, defining what counts as an encryption failure and a rapid disconnect. A false positive strands a user in a manual iOS Settings procedure (FR-12's own last bullet). That is a patient-safety design decision, not architecture's to make alone.

**ARCH-2 — FR-118 and FR-134 require detecting whether a complication is on the *active* watch face.** *(Blocking for the wrist-guidance epic)*
`WidgetCenter.getCurrentConfigurations` reports configured widget instances; it does not report which face is active or whether a given complication sits on it. FR-118 then requires the app to state "plainly that nothing of ours is on the wrist" — which would be wrong for a user whose complication is on a non-active face. FR-134 repeats the requirement in Settings > Watch.
*Downstream must ask:* is the requirement "any face" or "the active face"? If the latter, it needs a mechanism or it must be dropped, and FR-118's user-facing copy changes either way.

**ARCH-3 — FR-166's Reliability card requires a force-quit signal that does not exist.** *(Blocking for that story)*
The card renders when "the app having been force-quit from the app switcher" is true, and "copy names the specific condition". FR-15 already concedes there is no programmatic handle. FR-85's mechanism is a last-ran-timestamp gap, which cannot distinguish force-quit from reboot-before-first-unlock, jetsam, a dead battery, or a user who simply did not open the app.
*Downstream must ask:* downgrade to FR-85's inferred "has not run since X" (in which case it is not a third condition), or declare it unbuildable.

**ARCH-4 — SI-1's stated CI mechanism is not implementable literally.** *(Blocking for the SI-1 gate design)*
§4 SI-1 says "CI rejects any write-shaped symbol in Driver modules". Every BLE pump driver writes to characteristics — Tandem's protocol is request/response over a write characteristic. A blanket rejection fails the Tandem Driver on day one. The real mechanism is FR-31's "known therapy control-point characteristic" plus a "delivery-verb denylist", which is a *maintained list* with no named curator, no contents, and no rule for an unknown pump's therapy characteristic UUID. FR-205's protocol snapshot gate is genuinely strong but covers only the protocol module's *public interface* — a Driver that internally writes a bolus opcode produces no snapshot diff.
*Downstream must ask:* who owns the denylist and the characteristic list, and what is the honest claim §4 should make instead.

**ARCH-5 — SI-9's and SI-2's stated CI mechanisms are dataflow properties enforced by syntactic tools.** *(Blocking for the gate design; High for the invariants)*
SI-9: "CI rejects logging of health-typed values." SI-2 / FR-208: ban `precondition`/`fatalError` "on any value originating from Bluetooth, the Backend, or persistence". *Originating from* is a dataflow property. The only mechanisms named are SwiftLint custom rules, which are syntactic, and CodeQL `security-extended` for Swift contains no such query.
*Downstream must ask:* move these into the type system (a glucose type that is not interpolatable, a non-`CustomStringConvertible` wrapper, a `Tainted<T>` boundary) — an architecture decision the PRD should have requested — or accept that two invariants §4 claims are mechanical are enforced by convention. The addendum §1.5 already says both warrant a lint rule; it does not say a lint rule can express them.

### 2.2 Blocking — load-bearing contracts that were never written

**ARCH-6 — There is no Driver lifecycle contract anywhere in §5.2.** *(Blocking)*
Three lifecycle moments are named (initialize, activation hook, deactivation hook) with no ordering, no sync/async determination, no timeout, no re-entrancy rule, no threading or actor model, and no statement of what a Driver may assume exists when each fires (Safety Limits? Keychain? a peripheral?). FR-26 requires selections "restored **synchronously** during launch, before any Bluetooth manager is created"; FR-23 describes the overlap window as bounded by "the duration of the activation hook rather than an unbounded **suspension**" — Swift-concurrency vocabulary for an `async` hook. A synchronous restore cannot await an async hook. This is the single most load-bearing missing contract in the document.

**ARCH-7 — FR-23 and FR-30 specify two incompatible slot-resolution models.** *(Blocking)*
FR-23: activation "persists its slot claims"; "Conflict detection reads the persisted slot assignments, not the in-memory active set; where the two diverge, the persisted value wins." FR-30: "The pump slot resolves to the **first active Driver** declaring pump status or insulin source… Slot resolution iterates an order-stable collection." Explicit persisted assignment versus first-match over the active set. They disagree exactly during the overlap window FR-23 itself guarantees exists. This is the central data model of the Driver subsystem.

**ARCH-8 — The Driver overlap window has no reconciliation rule.** *(Blocking, with ARCH-7)*
§5.2 accepts "a brief window where two Drivers hold the same slot and both may publish; events carry the publishing Driver's id so the overlap is detectable." Detectable by whom, and then what? During the overlap two Drivers publish glucose for one slot. Does the dashboard render both? Does the Alert Floor evaluate both? Dedup, last-writer-wins, suppression? SI-5 and SI-6 both have stakes here and neither is discharged.

**ARCH-9 — The phone↔Watch Coverage Claim payload has no schema, and the state vocabulary is defined twice, differently.** *(Blocking)*
FR-83 pins "exactly one of: **Backend Active**, **Floor Watching**, or **Not Watching** with a Not-Watching Reason… pinned by test." FR-126 pins three *wrist* states: something is watching / the app reported nothing is watching, with the reason / **the app has not reported recently**. The wrist collapses the first two and introduces a fourth name (`not-reported-recently`, also used by FR-123) that appears nowhere in FR-83's pinned vocabulary or in §3. FR-127 pins the *reason* vocabulary as a shared contract test — "a rename on either side fails the contract test" — but nothing pins the *state* vocabulary, and nothing defines the payload the phone actually sends (state, `validUntil`, reason, re-alarm flag, sequence). FR-129 additionally requires a `re-alarm` flag ("Re-alarm defaults to on when the app's payload omits the flag") that is defined nowhere else.
*Downstream must invent:* the whole phone→Watch coverage wire contract, which SI-6 makes safety-critical.

**ARCH-10 — §5.8 defines nine record kinds and six tables and never gives a schema, and there is no migration strategy anywhere.** *(Blocking)*
FR-135 names "nine record kinds"; FR-137 names dedup keys; FR-139 names "six pump-data tables". No record's field set, nullability or identity is defined. There is no schema-versioning or migration story in the document. Under fork-and-build this is worse than in a normal app: N Builders on N arbitrary commits, upgrading across arbitrary version jumps, against a database the app "refuses to open rather than minting a second key" (FR-136). A failed migration is total loss of monitoring with no specified recovery.
*Downstream must ask:* does a bad migration wipe, halt, or degrade? That has product consequences, not just engineering ones.

**ARCH-11 — The outbound upload payload is specified only as three wire quirks.** *(Blocking)*
FR-140 gives "IOB uploads under the `bg_reading` event type carrying `iob_at_event`; Basal duplicates `pump_activity_mode` into `control_iq_mode`; Glucose Readings are never enqueued" — and that is the entire specification of what the app writes to the user's Backend. FR-214's Contract Pin guards cover *responses* on five endpoints, and its documented blind spots explicitly exclude "request-body drift". The one direction that writes the user's health data is contractually unguarded and unspecified.

**ARCH-12 — FR-93 / FR-103: "a feature-disabled response" is an undefined discriminator.** *(Blocking)*
FR-93's whole availability state machine turns on distinguishing three probe outcomes: success → ready, "a feature-disabled response" → disabled, "anything else" → unreachable. No status code, error code, or body field is named. FR-106 pins its equivalent precisely (*"An HTTP 404 — and only a 404"*) **and** carries OQ-40 asking for it to be pinned in the Contract Pin; the meal side has neither. Getting it wrong collapses "server down" into "feature off" — the exact failure FR-103 forbids in its strongest sentence (*"it must **never** show 'No meals logged yet.'"*). This is a Backend fact, not architecture's to invent.

**ARCH-13 — FR-180 vs FR-223: the fork secret contract is self-contradictory.** *(Blocking)*
FR-180 fixes six items (`TEAMID`, `FASTLANE_ISSUER_ID`, `FASTLANE_KEY_ID`, `FASTLANE_KEY`, `MATCH_PASSWORD`, `GH_PAT`) and says the set is "fixed, named in one place". FR-223's runbook lists "Issuer ID, Key ID, base64-encoded `.p8` contents, Team ID, bundle-ID prefix, app name" — drops two, adds two. Every downstream artifact (workflow, runbook, preflight validation, rotation doc, SM-1's named-failure metric) keys on this set.

**ARCH-14 — §5.10 has no signing and provisioning model, only assertions about its outputs.** *(Blocking)*
FR-182 registers App IDs, FR-184 asserts properties of an already-embedded profile, FR-185 governs custody within a run. Nothing states where the distribution certificate and provisioning profile come from or how they are renewed. The only clue is `MATCH_PASSWORD` plus one clause in FR-180 ("the private certificate repository clones and decrypts") — i.e. `fastlane match`, which requires each Builder to create and maintain a *second, private, encrypted repository*. That repository appears nowhere in FR-182, nowhere in FR-183, and nowhere in FR-223's step list. Either match is the model and a whole onboarding step is missing from the highest-consequence page in the product, or it is not and `MATCH_PASSWORD` is vestigial.

### 2.3 High — contradictions and unbuildable-as-written

**ARCH-15 — FR-83's selector order lets the app claim Backend Active while nothing can reach the user.** *(High, arguably blocking — it is a direct SI-6 violation)*
FR-83 resolves in order: (1) Backend alerting not degraded → **Backend Active**; (2) the app cannot post alert notifications → `NOTIFICATIONS_DENIED`. Backend alerts are delivered through `UNUserNotificationCenter` (FR-66, FR-68). A user with notifications denied and a healthy SSE stream therefore gets **Backend Active** — a positive coverage claim on a device where no alert can be presented. SI-6 says the claim "never overstates". The notification-capability gate must precede the Backend gate, or the claim must carry the degradation.

**ARCH-16 — FR-84 + FR-85 generate a routine time-sensitive "nothing is watching" notification with no fatigue policy.** *(High)*
FR-84 sets Backend Active `validUntil` to now + 360,000 ms. FR-85 schedules the lapse notification at `validUntil`, at `.timeSensitive`, cancelled and re-scheduled "on every wake". A backgrounded phone that gets no Core Bluetooth wake for six minutes — a phone on a desk, a pump out of range, an overnight gap — fires it. Nothing in the document rate-limits it, bounds it by time of day, or suppresses it for a known-benign cause. SM-14 forbids fixing this by widening constants, correctly, which makes the missing policy more urgent, not less.

**ARCH-17 — FR-129's "phone repeats update the wrist notification in place" is not achievable from a suspended app.** *(High)*
FR-129: "The phone's bounded finite ladder (FR-76) governs the phone; each of its repeats updates the existing wrist notification in place under the identity-derived identifier (FR-128) and adds no wrist haptic." FR-76's repeats are pre-scheduled `UNNotificationRequest`s that fire while the app is suspended; a scheduled local notification cannot send a WatchConnectivity update. Achieving this requires a wake plus a metered transfer per repeat, which contradicts FR-122's discipline that metered spend is reserved for material change. As written, the test FR-129 demands ("pins the wrist haptic count… one at onset, then one per 30 minutes, regardless of how many phone-side repeats fired") cannot pass with the mechanism described.

**ARCH-18 — FR-31's import allowlist makes the Tandem Driver unbuildable.** *(High)*
FR-31: the `iOS Gate` fails the build "if a Driver target imports anything beyond the shared safety module, the Driver API and the Bluetooth framework". Addendum §1.1: Tandem pairing is EC-JPAKE, requiring raw P-256 point addition and arbitrary-base scalar multiplication that CryptoKit does not expose, with "swift-crypto/BoringSSL, or a hand-written implementation over a bignum library" as the realistic options. Neither is on the allowlist; read literally, neither is Foundation.
*Downstream must ask:* vendor the crypto into the shared safety module (putting BoringSSL inside the module SI-4 exists to keep minimal), widen the allowlist (weakening FR-31's stated compile-time replacement for Android's `RestrictedContext`), or restructure. Not a unilateral call.

**ARCH-19 — FR-6 is fully specified while its foundational spike is unanswered, and §5.1's open questions omit that spike.** *(High; blocking for the Medtronic epic)*
Addendum §1.3(a): whether Core Bluetooth can return a `CBPeripheral` for a central that connected to our `CBPeripheralManager` is undocumented, and "a negative answer invalidates the driver architecture before it is built". FR-6 specifies the full advertise-and-wait flow — phases, copy, 60 s prompt, 30 s handshake bound, re-pair force-first-pair — with no gate on that spike. §5.1's own open questions list spike (b) and omit spike (a), the more dangerous of the two. §12.3 does put it at P0.1, so the sequencing is right; the FR does not reflect it and the fallback if (a) is negative is unstated.

**ARCH-20 — FR-32 never addresses Backend-optional mode.** *(High)*
Safety Limits are "accepted only from Backend sync, and no local override exists anywhere in the app", exposed as "a live value that always has a current reading", and FR-33 forbids ever returning "a default-constructed Safety Limits". In Backend-optional mode there is never a sync. What are the Safety Limits with no Backend, and how is that not a default-constructed value? SI-5's never-defaults rule pulls the same direction. Unanswerable from the text, and Backend-optional is a first-class supported mode.

**ARCH-21 — SI-4's Safety Constant set does not cover the constants FR-32 relies on.** *(High)*
SI-4 enumerates exactly three (Conversion Factor, Glucose Validity Bound, Tandem epoch offset). FR-32 introduces a type-level 25 U bolus cap, a 25,000 mU limit, a 15,000 mU/hr basal cap, a 3,600,000 ms staleness threshold, and an explicitly asserted **×1000 scale relationship** between two of them. None are in the drift-guard set, and a dual-representation constant with an asserted scale relationship is precisely what drifts. Separately: SI-11 and §3 define Safety Limits as glucose bounds only, while FR-32 gives them basal and bolus fields whose narrowing-only obligation is never stated.

**ARCH-22 — FR-8 declares a seven-state connection model and never gives the transitions.** *(High)*
"The seven names and their transitions are the Android set." FR-8 is consumed by pairing, the dashboard status row, diagnostics, the polling gate, the Watch forwarding path, plus FR-1, FR-6, FR-9, FR-13, FR-20, FR-43 and FR-119. The transition table exists only in Kotlin, and the PRD elsewhere warns "port from the Kotlin source, never from the Android documentation". Every consumer will reverse-engineer it independently and they will not agree. A state machine is exactly the artifact a PRD should carry.

**ARCH-23 — Auth Failed's entry condition is undefined for the phone-scans-and-connects shape.** *(High)*
FR-8 and FR-13 both say Auth Failed is entered "only from a rejected or expired secure handshake (**FR-6**)" — and FR-6 is the *advertise-and-wait* FR. The central-scan shape (FR-5/FR-10) has "code rejected", "secure handshake timed out" and "the Pump rejected the secure handshake" categories and nothing says whether any latches Auth Failed. Since Auth Failed is one of only two conditions that stop indefinite reconnection (FR-13), this is the highest-consequence undefined transition in the section. Compounding it: on Android, `AUTH_FAILED` is set from `rapidDisconnectCount >= 3`, a path FR-13 explicitly forbids.

**ARCH-24 — FR-13's backoff ladder does not compose as written.** *(High)*
"attempt count saturating at 10, delay `min(1000 × 2^min(attempt,5), 32000)` ms — 1 s, 2 s, 4 s, 8 s, 16 s, 32 s, then 32 s flat — then a 120,000 ms interval thereafter." The formula caps at attempt 5, the saturation is at 10, and the transition to 120 s is never conditioned on anything. The Kotlin resolves it: `MAX_FAST_RECONNECT_ATTEMPTS = 10` is the FAST→SLOW *phase boundary*, and `MAX_CONSECUTIVE_RECONNECT_FAILURES = 100` is a separate log-only cap. The PRD conflated the phase threshold with a saturation cap. No one can write a passing test for the ladder as stated. Also: Android's SLOW phase runs the 120 s timer concurrently with a passive `autoConnect=true` GATT, so FR-13's claim that "the foreground ladder matches Android" is not exact.

**ARCH-25 — FR-89's `dataSpanHours` is never defined, and it determines the headline number.** *(High, blocking for that story)*
"The days denominator is `dataSpanHours / 24` clamped into `[1, periodHours/24]`, measured from now rather than from the newest event." *Measured from now* fixes the end of the span, not the start. If the start is the period start, `dataSpanHours == periodHours` always and the clamp is a no-op; if it is the oldest event in the window, the denominator differs. Total daily dose — the card's headline figure — is unbuildable until this resolves.

**ARCH-26 — FR-89's `periodStart(daysBack, boundaryHour, zone)` has no DST or zone-change rule.** *(High)*
"Today's local date at the boundary hour" is undefined on a spring-forward day when that hour does not exist and ambiguous on fall-back when it occurs twice. FR-61 pins a shared injected clock but says nothing about the zone. A user who flies changes their day boundary mid-period with no stated behaviour. This silently mis-windows insulin totals.

**ARCH-27 — FR-89's bolus-category label override map has no wire shape.** *(High)*
"a display-label list keyed by computation role", then "a label entry with no computation role is dropped" — implying a list of entries with an optional role field, not a keyed map. Undefined: whether the Backend's role vocabulary matches the app's seven categories; what happens to an unrecognised role (FR-89 defines that fallback only for *Driver*-supplied names); and whether "absent" is distinguishable from "explicit empty list" through FR-215's shared decoder given SI-12's asymmetry. Three distinct behaviours (untouched / cleared / dropped) hang on a shape nobody has written down.

**ARCH-28 — FR-114's "one shared timeout" is unbuildable under one of the two architectures the PRD deliberately leaves open.** *(High)*
FR-114's Out of Scope explicitly refuses to decide whether the Watch calls the Backend directly or relays through the phone: "This section fixes the behaviour contract, which must hold identically either way." It does not. Under relay, the watch watchdog must exceed the phone's request timeout *plus* WatchConnectivity round-trip latency, or the exact Android defect FR-114 claims to fix reappears as a zero-margin race. "Share **one** timeout value" plus "the Watch can never report a timeout while the request is still running" are jointly satisfiable only in the direct-call design.

**ARCH-29 — FR-111 and FR-114 take opposite postures on the same consumed field.** *(High)*
FR-111: "a chat response missing `disclaimer` … fails loudly as a decode error" (SI-12). FR-114: the Watch renders the disclaimer "defaulting to 'Not medical advice. Consult your doctor.' when the disclaimer is blank." Missing versus blank is a real distinction, but nothing states the Backend never returns blank; under a relay design the phone's decoder throws before the Watch's default is reachable, making the Watch AC dead code; under a direct-call design there are two decoders for one payload, which FR-215 forbids ("Exactly one shared decoder object"). Unresolvable without ARCH-28.

**ARCH-30 — FR-112's guarantee is stronger than the mechanism it names.** *(High)*
"strips image markdown and HTML image tags" is the mechanism; "assistant content can never cause an outbound network fetch" and "Rendering an assistant reply issues zero network requests" are the guarantees. Stripping `![]()`, `![][]` and `<img>` does not close `<video poster>`, `<object>`, `<link>`, `<iframe>`, CSS `url()`, or reference-style link definitions, depending on the renderer. The only construction that delivers the guarantee is a renderer that cannot fetch at all — a mechanism the FR pre-empts by naming a weaker one. The PRD itself notes "No Safety Invariant covers outbound-fetch suppression", so the strongest claim in the FR rests on nothing.

**ARCH-31 — No app-lifecycle → request-state taxonomy exists, and FR-95 and FR-110 assume different ones.** *(High)*
Chat mandates explicit cancel-on-background (FR-110). Meal upload gets "A request interrupted because the app left the foreground surfaces as an honest failure" plus a launch-time marker for jetsam (FR-95). Between them, four distinct platform states — backgrounded-but-alive, suspended, jetsammed, user-terminated — are conflated differently. This is a cross-cutting boundary contract that also touches SI-6, and nothing in the document names the states.

**ARCH-32 — FR-143 + FR-166 + FR-168 leave a signed-out user with a retained URL unable to arm the Alert Floor.** *(High, arguably blocking)*
FR-143: sign-out "preserves the Backend URL" and "clears Backend-provenance Alert Thresholds", and makes "a non-blank stored Backend URL … the single canonical signal for whether a Backend is configured". FR-166 makes the threshold editor editable only in Backend-optional mode; FR-168 makes it read-only "whenever a Backend is configured" and aborts any save that finds a Backend. Composed: a signed-out user with a retained URL has no thresholds and no editor, so the Alert Floor cannot be armed by any in-app path. FR-169's status line sits in error styling saying "On-device alarms are OFF until you set all four thresholds" beside a control that refuses to let them.
*Someone must rule:* does "Backend configured" mean URL-present or session-valid?

**ARCH-33 — SI-8's durability rests on an anchor row three FRs may delete and an unstated monotonicity assumption.** *(High)*
FR-146 anchors history resume on "the highest stored raw-history sequence number". FR-139 prunes but "the single highest-sequence row is always retained". FR-143 deletes "all raw pump-history rows except the highest-sequence anchor" with a repeating purge sweep. Three independent deletion paths must each preserve exactly one row; losing it costs a 20-minute foreground re-download. Additionally unstated: whether pump sequence numbers are monotonic and never reset across pump replacement, rollover, or a re-pair. If they reset, the anchor silently blocks all future history and FR-146's non-advancing-history diagnostic fires forever.

**ARCH-34 — FR-144 lists five background workloads with no scheduling model, priority order, or arbitration rule.** *(High)*
The slice attaches independent, mutually unaware ladders: FR-141's 2s→32s ×5 retry budget and 15-minute reclaim; FR-144's 3-second foreground tick, 60-second hygiene throttle and 1-hour threshold throttle; FR-154's ~20-second wall-clock deadline plus ~15-minute refresh request; FR-147's 3×(1s,2s) refresh retries with a 60-second floor. iOS grants one budget for all of them. Nothing states what runs first when a ~30-second window must serve token refresh + queue drain + retention + threshold refresh + Nightscout sync, or what is dropped. FR-144's "Every background handler completes or aborts cleanly within the window" is the requirement; the arbitration rule that makes it achievable is missing.

**ARCH-35 — There is no error taxonomy, and two classifiers collide on 401.** *(High)*
Five incompatible classifications live in §5.8 alone: FR-141 (transport/408/429/502/503/504 → no retry increment; any other non-2xx → increment), FR-147 (five refresh outcomes), FR-152 (three connectivity states), FR-154 (six run outcomes), FR-155 (drop vs fail-loud). The concrete collision: an upload batch receiving 401. FR-141 increments the retry count on it; FR-148 says a 401 triggers "exactly one serialized refresh-and-retry". Neither FR references the other. Five 401s and the batch is dropped by FR-141's cleanup pass.

**ARCH-36 — FR-155's "documented default" list is open-ended while FR-215 requires it closed.** *(High)*
FR-155 enumerates defaults "**including** `is_automated`, `acknowledged`, `raw_accepted`, `raw_duplicates`, `source`". FR-215 requires "a test enumerates **every** field carrying a default and asserts that omitting its key still decodes". The closed list exists in neither the PRD nor the Contract Pin — and OQ-36 proves the pin does not currently mark such fields optional. SI-12's enforceability depends on a list nobody owns.

**ARCH-37 — FR-171's per-condition deep links do not exist, and the FR contradicts itself about it.** *(High)*
"each itemized condition carries its own control that opens the relevant iOS setting". iOS offers `openSettingsURLString` and (15.4+) a notification-settings link. There is no deep link to Scheduled Summary, Time Sensitive, lock-screen delivery, Notification Center delivery, or sound. FR-171's own later bullet concedes this. As written, a designer must draw eight buttons that all go to the same place.

**ARCH-38 — FR-169's wording drifts from SI-5 on the safety-critical point.** *(High)*
SI-5 forbids the Alert Floor firing on defaults. FR-79 states the reconciled version correctly: the built-ins exist "only so the classifier and the Watch relay have values to **compute a display state** with. With provenance `none`, **no alarm fires at any glucose value**." FR-169 says the stored defaults "exist only for the Watch alert **relay**" — which a story writer reading FR-169 in isolation will implement as a wrist alarm firing on 55/70/180/250. Safety-critical wording drift, not a nit. Related: OQ-20 asks the same question for display banding and is still open.

**ARCH-39 — FR-181's committed provisioning-profile specifier contradicts FR-180's zero-source-edit guarantee.** *(High)*
"`CODE_SIGN_STYLE = Manual` with the provisioning profile specifier pinned in a committed xcconfig." A profile specifier names a record in a *particular* Apple account. A committed literal cannot be correct for every Builder, and FR-180 forbids the Builder editing any tracked file. Also in tension with FR-179's rule that a committed build-settings file carrying team-scoped signing data fails the Entitlements and Plist Guard.

**ARCH-40 — Export compliance is absent, and it breaks the UJ-3 happy path.** *(High)*
`ITSAppUsesNonExemptEncryption` and export compliance appear **zero times** in `prd.md` and `addendum.md` (verified by grep). This app ships EC-JPAKE, HKDF and HMAC. Without the Info.plist declaration, every App Store Connect upload lands in Missing Compliance and is not installable from TestFlight until the Builder manually answers the questionnaire — turning FR-183's automated upload into a manual step and silently breaking FR-186's *scheduled* rebuild, since nobody answers a questionnaire at 3 a.m. on day 30. FR-204 enumerates required Info.plist keys and omits it.

**ARCH-41 — FR-186's "enabled by default in every fork" is not how GitHub forks behave.** *(High)*
Actions are disabled by default in a forked repository and must be enabled by hand; scheduled triggers in particular do not fire until then. FR-223's step list never says "enable Actions in your fork", which means the runbook as specified does not produce a working build at all. Compounds with the 60-day-inactivity disable the FR does correctly document.

**ARCH-42 — FR-187's expiry value cannot be computed where FR-187 says it is computed.** *(High)*
Two consequences contradict: "Values are injected at archive time and are read-only at runtime" and A-37's "expiry is computed as the recorded upload timestamp plus 90 days". The upload happens *after* the archive. A re-uploaded or delayed archive ships a wrong countdown on a surface FR-187 itself says must never overstate coverage.

**ARCH-43 — FR-189's compile-time Driver exclusion collides with FR-201 and FR-208.** *(High)*
FR-189 requires a disabled Driver to be absent from the shipped binary and from the Catalog — not `#if`-emptied, but not compiled. In SwiftPM that is a manifest-level decision, i.e. environment-driven logic in `Package.swift` — which FR-204 flags as the fork-and-build blast-radius hazard and CODEOWNERS-gates. FR-201's Resolution Drift step then fails on any diff between resolved manifests and the committed `Package.resolved`, and a conditionally shaped manifest resolves differently per configuration. FR-208's all-Drivers configuration makes it two graphs against one lockfile.

**ARCH-44 — FR-217 Layer 3's inverse literal scan has an undefined classifier.** *(High)*
"CI fails if a bare `20`, `500`, `18.0156` or `1199145600` appears in a glucose or **Pump**-time context." The latter two are trivially scannable. `20` and `500` are two of the most common integers in any codebase — HTTP 500, `.seconds(20)`, 500 ms timeouts, 20 pt padding. The FR specifies token-level parsing and boundary semantics carefully and never defines "glucose context", which is the entire difficulty. The likely outcome is that the scan is narrowed until it catches nothing — destroying the self-maintaining property R-11's mitigation depends on.

**ARCH-45 — FR-47 contradicts its own note on Light-theme contrast, with no replacement values.** *(High; also UX)*
FR-47: "#EAB308… #EF4444… #22C55E. These three values are identical in the Light and Dark themes." The Note under §5.3: green and yellow on a white surface fall short of WCAG AA for small text, so "within the appearance owned by FR-175, darken only the TEXT variants in the Light appearance, never a fill, dot or badge." No darkened values are given, and the consequence bullet forbids the change the note requires.

**ARCH-46 — Two channels, one App Store Connect record, one version space.** *(High)*
FR-183 supports `main` and `develop` inputs; its Out of Scope declines a second App ID/ASC record (deferred to OQ-50). FR-190 single-sources `MARKETING_VERSION` from release-please, which bumps only on promotion to `main`. A `develop` build therefore uploads under the same marketing version to the same TestFlight record and, per FR-191's monotonic clock-derived build number, becomes the newest build in the group — TestFlight auto-updates the Builder onto a development build they did not choose. No FR resolves this.

### 2.4 Medium

**ARCH-47 — FR-40's fixed read order and 500 ms gap are mechanism at capability altitude, and glucose is read last.** The sequence "IOB, basal rate, battery status, reservoir level, glucose, with a 500 ms gap" puts the alerting-critical value last, ~2.5 s in. Nothing says whether the ordering and pacing are Tandem protocol requirements or ported accident. Ask.

**ARCH-48 — The 64 pending-notification-request budget has no owner.** FR-76 asserts a test pins the cap. The budget is also consumed by FR-85's lapse notification, FR-187's expiry notifications at 7/3/1 days, simultaneous ladders for different alert types, and caregiver patient-name variants. Nobody allocates it.

**ARCH-49 — FR-70's slot identity and FR-76's ladder are not reconciled.** FR-70's identifier is `"<alertType>|<patient>"` and re-posting replaces. FR-76 schedules 5 repeats. Are the repeats posted under the slot identifier (replacing, one banner) or distinct identifiers (five banners)? Not stated, and the two FRs point in opposite directions.

**ARCH-50 — FR-115's build-mismatch banner needs a value only a running, reachable Watch app can supply.** The unknown case (Watch app installed but never launched, or unreachable) is unspecified.

**ARCH-51 — FR-92's absolute-bound branch may be unreachable, or FR-138's guarantee is weaker than stated.** FR-92 requires an out-of-bound glucose-at-event value rejected at the model boundary; FR-138 makes storage canonical-and-validated; FR-90 says out-of-bound bolus rows are "skipped when read back from local storage", implying storage can hold invariant-violating rows. One answer is needed.

**ARCH-52 — FR-145's backward-clock rule has no number.** "A backward wall-clock movement suppresses freshness claims" — no threshold, no mechanism, no cross-reference, while FR-116/FR-123 pin −60,000/−60,001 ms. Either 5.8 defers to FR-49/FR-72 explicitly or a third clock rule gets invented.

**ARCH-53 — FR-157's SSE read timeout may trip FR-152's unreachable flip.** FR-152 flips on "2 consecutive transport failures" and excludes only long-running AI inference. FR-157's stream has a 75-second read timeout. Two stream timeouts on a healthy Backend would report it unreachable.

**ARCH-54 — FR-176's "Simulate Backend Unreachable" and FR-152's hysteresis interact unspecified.** FR-176 says injected failures are "accounted for exactly like a real transport failure", so the toggle does not produce the state it names until two requests have failed.

**ARCH-55 — OQ-32 is answered by fiat inside FR-135 while §15 still lists it open.** FR-135: "There is no independent wrist fetch path in any mode." OQ-32 still asks the question and FR-134's notes still route it to 5.8 as unresolved.

**ARCH-56 — FR-136's "32 bytes hex-encoded to a 64-character lowercase string" is an SQLCipher artifact at capability altitude,** presupposing the storage engine. The capability is "a 256-bit key from a CSPRNG, device-only, never regenerated".

**ARCH-57 — FR-136 does not address device migration or restore-from-backup.** Keychain items survive device transfer and encrypted backup restore; the database file may or may not. Under the never-mint-a-second-key rule the failure mode is a permanently unopenable app.

**ARCH-58 — FR-29's build-time settings-key validation and FR-37's runtime descriptor-key validation cannot both hold.** Driver-supplied descriptor keys cannot be validated at build time. Separately, FR-28's "An initialization failure drops that Driver's settings-store entry" reads as destroying persisted user configuration on a transient failure; if "entry" means the in-memory registry record, it must say so.

**ARCH-59 — FR-34 specifies an event channel with no event taxonomy.** Buffer depth (256), overflow policy and subscriber isolation are pinned; the event set is never enumerated (one member named in passing). Worse: FR-23's acceptance criterion is "a test observes the slot as continuously occupied across the swap" — if observation runs over a drop-oldest channel, the test's own evidence is droppable.

**ARCH-60 — FR-21's exact-set Catalog assertion contradicts FR-27's kill switch.** FR-21 asserts "the Catalog's **exact expected set** of Driver ids"; FR-27 lets a Builder produce a build with a Driver absent. FR-208's all-gates-on CI configuration solves coverage, not the exact-set assertion. Also unresolved: FR-27 says a *maintainer* may disable a Driver, but under fork-and-build every user forks.

**ARCH-61 — FR-30 gives resolution rules for two slots while FR-23 names four single-instance Capabilities.** Bolus-category provider is single-instance and therefore evictable, and has no resolution rule at all.

**ARCH-62 — FR-30 calls data sync a "mutual-exclusion tag" while FR-24 makes it multi-instance.** Probably a stale word from Android; under a binding-vocabulary rule someone will implement it.

**ARCH-63 — "Scanning" names two mechanisms.** FR-8 lists it as a connection state; FR-6 uses it for *advertising* ("Scanning, or advertising with no terminal fault while Disconnected, renders the waiting card"). §0 makes vocabulary binding; this is the inverse defect — one term, two mechanisms — in the state model every other section consumes.

**ARCH-64 — FR-11 and FR-12 conflict on the strongest wall detector.** FR-12 says the wall is never presented "when a successful authenticated session has previously been established with that Pump and the user has not unpaired" — no exception. FR-11's first condition (the system reporting the peripheral removed its pairing information) can only occur *after* a bond existed. Read literally, FR-12 suppresses the one high-confidence signal iOS actually gives.

**ARCH-65 — `Static Analysis Gate` carries every unconditional text check *and* CodeQL Swift on macOS.** FR-198 forbids a `paths:` filter on it; FR-200 puts CodeQL autobuild over a scheme compiling every shipping target in it; FR-197 and FR-219 add the License Header Gate and four documentation checks. A one-line typo in `docs/troubleshooting/` triggers a full CodeQL Swift build of the app, Watch app, every extension and every Driver on a macOS runner — contradicting the same section's NFR and FR-208's doc-only-PR intent. Architecture must be told which constraint yields.

**ARCH-66 — FR-204's ATS baseline is "the Info.plist as committed" in a repository that has no Info.plist.** Honestly flagged, but operationally the first commit's accidental shape becomes the baseline, and the verification that would replace it needs a device on a LAN.

**ARCH-67 — FR-187 cannot deep-link "the Builder's own workflow" without knowing which fork it is.** The enumerated injected values do not include the fork's owner/repo. One more injected value; currently unbuildable as written.

**ARCH-68 — NFR-30's accessibility registry is a cross-repo build dependency with no pinning rule.** "Generated from the Android source, committed, and diffed by CI" — which Android commit, and what happens when Android adds a `testTag` mid-cycle? NFR-30 itself admits it "drifts every time the Android client changes".

### 2.5 Low

**ARCH-69 — FR-202/FR-203/FR-222 pin exact tool versions and SHA-256 digests inside the PRD while the section's own NFR mandates a bot to bump them.** shellcheck 0.10.0 + digest, actionlint 1.7.7 + digest, zizmor 1.5.2, PyYAML 6.0.2, OSV-Scanner v2.3.3, a 40-hex action SHA. The document is designed to be stale after the first Renovate PR. The requirement — pinned by exact version, verified by digest — is right; the values belong in the repo.

### 2.6 §6–§10 (NFRs, Parity Ledger, verification matrix, validation tiers, gate substitutions)

**ARCH-70 — NFR-22's declared background-mode set contradicts PL-11, PL-6 and §8.3, and FR-204 asserts it as an exact match.** *(Blocking for the entitlements and Plist-guard work)*
NFR-22 fixes the capabilities as "exactly: App Groups, Keychain Sharing, Background Modes for **Bluetooth central**, Time Sensitive Notifications, Push only if wired", and FR-204 asserts a `UIBackgroundModes` **exact-set match**. But PL-11's substitute names `bluetooth-central` **and** `bluetooth-peripheral`, Medtronic's entire transport is the peripheral role (PL-4, PL-6, §8.3), and NFR-11 relies on "a system-granted refresh or processing task", which needs `fetch` and `processing`. As written the guard fails the app it guards, or the Medtronic driver and all background-task work are undeclarable.
*Downstream must ask:* what is the authoritative `UIBackgroundModes` list, and does it vary with the compile-time Driver gate (FR-27 / PD-11)? If it does, FR-204's exact-set assertion needs a per-configuration baseline.

**ARCH-71 — NFR-18's first-run purge contradicts NFR-19's "generated once, never regenerated", and no NFR covers an undecryptable store.** *(High)*
NFR-19: the 32-byte database key is "generated once, never regenerated." NFR-18: "Keychain items survive app deletion, so a first run after a fresh install purges the app's own items before anything reads them." Device-only Keychain items do not restore to a new device, but an encrypted container *can* arrive via device restore — producing a store the app cannot decrypt, on a path NFR-15 does not cover (it covers *unmigratable*, not *undecryptable*). PL-8 handles the pairing-identity half of restore; nothing handles the data half. Architecture must invent the purge scope, the restore-detection signal, and whether an undecryptable store is deleted (against NFR-15's no-destructive-fallback spirit) or surfaced. Pairs with ARCH-57.

**ARCH-72 — NFR-6 asserts a Watch cold-start behaviour NFR-4's data contract does not permit.** *(High)*
NFR-4: the Watch-side container is written by the Watch app only, and "an absent, unreadable or malformed container renders the no-data state." NFR-6: "The Watch app and every widget render real cached data on cold start rather than `--`, because the widget reads the shared on-device cache directly and does not require the Watch app process to have run first." If the Watch app is the sole writer, a never-run Watch app means an empty container; the two cannot both hold. The implicit resolution (a WatchConnectivity delivery background-launches the Watch app to seed it) is stated nowhere and is exactly the class of platform assumption §9.2 warns about.

**ARCH-73 — Nothing in §6 requires an injectable clock, yet every tier depends on one.** *(High — load-bearing omission)*
Freshness classification, the backward-clock guard, the negative-age rule, Coverage Claim decay and expiry, the phone 5×120 s and wrist 30-minute ladders, the pre-baked decay timelines (PA-4), and Tier 2's "non-UTC zones in both hemispheres and a DST spring-forward gap" are all time-dependent. §6 mandates test seams for transport (§9.1 Tier 2, "behind the transport seam"), for Drivers (PA-7/PA-8) and for fault injection (PA-12) — but never for time. NFR-9's "not via an in-memory timer" is a durability rule, not a seam. FR-61 requires the injected clock for *the dashboard only*; nothing lifts it to a system-wide requirement covering the shared module, widget timelines and Watch decay.

**ARCH-74 — NFR-24's prohibition cannot be enforced by FR-158's four scrubbing rules.** *(High)*
NFR-24 prohibits "any Glucose Reading value, IOB value, Bolus or Basal amount, carb value, alert threshold value" in logs and claims the rules "are applied at emission **and** again at export." FR-158's four rules match only JWT shapes, emails, and numbers *suffixed with* `mg/dL` or `mmol/L`. A line reading `bg=412`, `iob=3.2`, `threshold=68` passes every rule. NFR-24's guarantee therefore rests on lint and discipline, not the mechanism it names — while NFR-14 simultaneously requires every rejection "recorded with enough context to diagnose it", which for an SI-2 rejection is precisely the value. Same class as ARCH-5: architecture must supply typed or structured logging with no free numerics, or a redaction-by-type API.

**ARCH-75 — NFR-33's diagnostic buffer is in memory (FR-158), so it is empty for exactly the failure it exists to diagnose.** *(High)*
NFR-33 makes the on-device buffer "the only diagnostic channel" under NFR-32 (no telemetry reaches the project), and NFR-17 requires a force-quit, termination or restart gap to be "detected from the data itself on next launch and reported". FR-158 states "the buffer is bounded and in memory." A jetsam (PL-46), a watchdog kill or any termination destroys it; the export then contains only post-relaunch lines and the honest-gaps statement covers the whole incident. Either a persisted, protection-class-correct, scrubbed-at-emission log (interacting with NFR-19's container rules), or the project accepts that its only diagnostic channel loses every crash-adjacent event.

**ARCH-76 — NFR-8 and NFR-13 state two different ingest orderings, and neither defines budget-exhaustion semantics.** *(High)*
NFR-13: "persist → derive → alert → present → enqueue upload." NFR-8: "persist the frame → advance the cursor only if it decoded (SI-8) → evaluate the Alert Floor → refresh the Coverage Claim → update wrist and widget surfaces → enqueue upload", "asserted by test." Two lists, different step vocabularies, one testable path. Worse, nothing states what happens when the ~10 s (extendable to ~30 s) restoration window expires mid-order: which steps are mandatory before yielding, whether a partial order is resumable, and whether the Coverage Claim reflects a wake that persisted but never alerted. This is the app's most safety-critical path.

**ARCH-77 — NFR-5's performance target is stated against a device nobody has and no tier can measure.** *(High)*
"One frame budget on the oldest supported device" — but NFR-2 marks the supported-device set itself as an `[ASSUMPTION]` to regenerate (A-52), Tier 1 is a Simulator on host hardware, Tier 3 is a Mac, and Tier 4 is one person on one unnamed iPhone model. NFR-5's own consequences then relocate acceptance to Simulator tests over the identifier registry, which measures something else. The only genuinely testable numbers in §6.2 are the 100 ms progress-state and 500 ms bounded-operation rules. Architecture must supply a Simulator-provable proxy (main-thread work budget, no synchronous I/O on the render path, off-main hit-testing) and the PRD should say that *is* the acceptance.

**ARCH-78 — NFR-7's two rows contradict each other.** *(Medium)*
"Analysis card series ('All' variants) — 50,000 rows" against "Retention — the user's configured retention window, 1–30 days, default 7." At 5-minute CGM cadence, 30 days is roughly 8,640 glucose rows; 50,000 is unreachable from the local store for any single series. Either the ceiling means all record kinds combined, or it implies a store the retention rule forbids — and NFR-7's own performance test would seed a state the product cannot reach.

**ARCH-79 — NFR-19 leaves the data-protection class as an either/or that FR-204 must assert deterministically.** *(Medium)*
"complete-until-first-user-authentication (**or** complete-unless-open)" — materially different semantics, since the latter only protects files not already open at lock, which is exactly the background-write case. FR-204 "asserts the setting", and a guard cannot assert a disjunction. Pick one and record it, as NFR-18 did for the Keychain class.

**ARCH-80 — NFR-12 requires a work-shedding policy the app has no scheduler for, and it competes with NFR-8's fixed order.** *(Medium)*
"Elevated thermal state may reduce background opportunities; the app reduces non-essential work … before it reduces anything on the Alert Floor path." Thermal pressure removes *granted* opportunities; the app's only lever is what it does inside a wake, which NFR-8 fixes as an immutable six-step order. Architecture must invent the work-class taxonomy and the point at which NFR-8's order may be truncated. Compounds ARCH-34 and ARCH-76.

**ARCH-81 — NFR-11's wrist-transfer rate rule is self-contradictory and silent on alert-state changes.** *(Medium)*
"spent only on material change … with a **floor of at most one per 15 minutes**" — a floor stated as a ceiling; PL-35 repeats the phrase. It is also unclear whether the cap applies to an alert-state change. If it does, a complication can show a pre-alarm value while the wrist notification (FR-128) is already alarming — two wrist surfaces disagreeing about a low, which is an SI-6 failure. Restate as a rate cap with a named exemption class.

**ARCH-82 — NFR-2's iPad and Mac opt-out is only half enforceable upstream.** *(Medium)*
"explicitly opted out in the build **and in App Store Connect**" — the ASC app record belongs to each Builder, not the project. FR-204 can guard `TARGETED_DEVICE_FAMILY`; it cannot guard a Builder's ASC toggles. §6's own closing question ("a Builder may reasonably expect their own TestFlight build to install on their own iPad") is unresolved, and PL-44's disclosure need depends on the answer. Ties to UX-7 / OQ-22.

**ARCH-83 — NFR-3 leaves the floor-runtime CI question open, and the two answers have materially different assurance.** *(Medium)*
"is a CI job on the floor Simulator runtime affordable … or does CI test only the newest pinned runtime with the floor checked by availability lint alone? The second is cheaper and materially weaker." NFR-1's "no unguarded newer API" consequence and NFR-3's floor-destination requirement both depend on the answer, and it drives macOS-runner cost (PL-63, OQ-49). Undecided means the CI epic cannot be sized.

**ARCH-84 — NFR-4 places "the glucose and IOB render functions" in a module required to have no UI.** *(Low)*
Almost certainly means string formatting, and FR-60 / PD-12 support that reading — but "render" is the same word §5.3 and §5.7 use for view work. One word; cheap to fix; otherwise the shared module's boundary is relitigated in every pull request.

---

## 3. UX Designer

### 3.1 Blocking

**UX-1 — FR-159's onboarding traps the Backend-optional user before the Backend-optional escape hatch.** *(Blocking)*
Verified directly in the text. FR-159 fixes stages Welcome=0, Features=1, Safety Ack=2, Backend=3, Sign-in=4; "Skip" appears "on stages 0 and 1 only… it never lands on 3 or 4"; from stage 2 on "the only forward affordance is a button"; and "**The Backend stage's 'Next' is disabled until a connection test has succeeded in this session.**" FR-164 places `onboarding_continue_without_server` on **stage 4**. A user with no Backend is therefore stranded on stage 3 with a disabled Next and no Skip. This also contradicts FR-161's "The stage is labelled optional… You can skip it and use the app as a direct pump monitor."
The product's headline claim — Backend-optional mode is first-class, not degraded — is unreachable as specified. The fix is a product decision (skip on stage 3? move the control? ungate Next?), not a design one.

**UX-2 — FR-37 gives the Driver UI vocabulary as counts, not members.** *(Blocking for the Driver-UI epic)*
"9 card element variants, 6 semantic colours, 4 label styles, 13 icons, and 6 settings descriptor variants." Not one member of any of the five sets is enumerated; roughly seven element names can be reverse-engineered from the validation error messages. A designer must invent 13 icons and 6 semantic colours; an architect must invent the conforming type surface; a planner cannot size it. FR-37's own rule that "a Driver cannot introduce a new element" makes getting the set wrong expensive to change later.

**UX-3 — OQ-24 is unresolved and it decides the shape of the primary honesty surface.** *(Blocking for the Coverage Claim design)*
Without Critical Alerts — the normal case for essentially every Builder — does the Coverage Claim say "watching" or "watching, but you may not hear it"? FR-66 currently puts the caveat in claim *detail* copy rather than claim *state*. This changes the banner, the complication, the Live Activity and the wrist for nearly every user, nearly always. It cannot be designed around; it must be ruled on.

### 3.2 High

**UX-4 — The PRD pins pixel geometry, hex colours, opacities and font sizes throughout §5.3, §5.5 and §5.9 without saying whether any of it is negotiable.** *(High)*
FR-39 (16/88/12/24 pt insets), FR-46 (64 pt / 40 pt / 8 pt / 4 pt offsets), FR-51 (0.15 opacity, 4 pt radius, 6/2 pt padding), FR-52 (36/32/8/8/24 pt plot insets, 3 pt dots, 0.08 and 0.3 opacities), FR-53 (full z-order, per-layer opacities, 4 pt diamonds, 18 pt stagger), FR-58 (24 pt bar, #334155, 12 pt radius), FR-97 (a 120 × 6 rounded track). Much of this is Android transcription, and Android's margin conventions are not iOS's. The document does not distinguish load-bearing geometry (FR-53's draw order genuinely is — glucose dots last is a safety rule) from inherited layout. A designer either freezes the Android layout or guesses which sentences they may break.

**UX-5 — FR-97's fixed 120 pt track cannot survive Dynamic Type.** *(High)*
It sits beside a confidence label and a carb range that must scale to AX5 per NFR-27. The actual requirement — "Medium and Low deliberately share one hue and are distinguished by length", never the error colour — is excellent. The 120 pt will force the designer to violate the FR or ship a clipping layout.

**UX-6 — FR-46's fixed 64 pt hero, FR-64's "never truncated at any Dynamic Type size", and OQ-21 form an unresolved three-way contradiction.** *(High)*
NFR-27 adds a fourth voice: "Fixed-size numerals (the hero, glanceable values) either scale with Dynamic Type or are explicitly bounded with a stated rationale; a hard-coded point size with no bound is a defect." OQ-21 admits there is no Android reference behaviour. The designer must resolve it, and it is the single most-read element in the product.

**UX-7 — OQ-22 (iPad) is unanswered, so the target device set for every layout is unknown.** *(High)*
FR-56 assumes iPhone; A-9 assumes iPad behaves differently; PL-44's disclosure need "depends on the iPad open question". Everything from the dashboard grid to the chart detail to Settings depends on the answer.

**UX-8 — AI Chat (FR-105–FR-114) has zero journey coverage, and the PRD says so without resolving it.** *(High)*
Confirmed mechanically: no FR in §5.6 carries a "Realizes UJ-n" line. The §5.6 note is candid — "S2 defines no user journey for AI Chat… Either the section stays journey-less… or S2 gains a seventh journey. Flagging rather than inventing one." It is a whole tab with a Watch surface, a spoken-response system, a voice picker and a safety-disclaimer regime. The designer has no entry state, no motivation and no success signal.

**UX-9 — §5.9 (FR-159–FR-178) is journey-orphaned in substance even though eleven FRs cite UJ-3.** *(High)*
UJ-3 is Marcus *building and installing*; it ends at "he pairs his pump". Nothing describes a user changing a setting, a Backend-optional user setting their own thresholds (FR-169 cites UJ-2, where Priya is asleep and never touches a threshold), or an assistive-technology user doing anything (FR-178 cites UJ-1/UJ-2, neither of which is an AT user). This is the largest surface in the product: a thirteen-section settings screen, a four-field threshold editor, a sound picker, a Watch section, an eight-condition notification card, a debug console, and the whole accessibility contract. At least two new journeys are needed before UX starts here.

**UX-10 — The advertise-and-wait pairing shape has no journey.** *(High)*
UJ-4 is Dana on a t:slim X2 — scan, list, code, iOS prompt, broken-pairing wall. One of exactly two pairing shapes is unnarrated. FR-6/FR-7/FR-16 carry a "Before you start" card, a waiting card with name-specific copy, a 60 s nudge, a first-pair-vs-reconnect distinction invisible on Android, a foreground-only discoverability disclosure, and a Beta warning that the Driver is "not suitable as a sole monitoring path". The designer must invent the emotional arc of a wait with no progress signal — and, given ARCH-19, may design something unbuildable.

**UX-11 — Ten of ~26 FRs in §5.5/§5.6 are journey-orphaned and the rest hang off one happy path.** *(High)*
UJ-5 covers photo → estimate → correct → save. It says nothing about identity confirmation (FR-99), provenance (FR-101), nutrition rendering (FR-102), meal history (FR-103) or common foods (FR-104) — six of the twelve meal FRs, and the ones with the most screens. Insulin (FR-89–92) has none.

**UX-12 — FR-94 / FR-101 / FR-102 fix literal screen order and control styling with no signal about what is negotiable.** *(High)*
FR-94: "The idle screen offers, in order: the explanatory line…; a filled 'Take photo' action; an outlined 'Choose from gallery' action; the permission line…; then secondary actions." Fill versus outline is a visual-system decision. Some of the neighbouring specification genuinely *is* load-bearing (FR-96's "pinned above the scroll region"; FR-102's "rendered by the content view rather than the card so a portion-only payload still shows it"). The document does not separate them.

**UX-13 — FR-89's deliberate under-reporting has no user-facing disclosure.** *(High)*
"A long Pump disconnect therefore under-reports rather than extrapolates" — the right choice, with no stated consequence. The card renders a confidently low total daily dose with no staleness marker and no gap indication, on a surface a user might act on. Every other surface in this product carries an honesty affordance for exactly this (SI-6, Freshness Tiers, Coverage Claims). This one does not.

**UX-14 — Copy is specified to the byte; almost everything a designer owns is absent.** *(High)*
FR-159, FR-160, FR-161, FR-163, FR-164, FR-168, FR-169, FR-170 and FR-171 pin roughly forty literal strings, most "pinned by test and not to be re-worded". That is right for the safety acknowledgement and the never-dose qualifier; it is over-reach for "Connected successfully" and "Login failed: HTTP `<code>`". Meanwhile §5.9 specifies no layout, no visual hierarchy, no motion, no loading state for the connection test, no keyboard or input model for the four-field threshold editor, and no error-recovery flow. The normal division of labour is inverted: the PRD took the words and left the design.

**UX-15 — FR-166 gives two contradictory Settings orderings, one inside an unresolved `[ASSUMPTION]`.** *(High)*
Thirteen sections in a fixed order, then A-34 immediately offers a different ten-section nesting. Beyond ordering there is no information architecture at all: no definition of card versus row versus section, no grouped-list-versus-custom decision, no empty or loading state for a section whose Driver metadata read throws, and no spec for what the screen looks like when Backend-optional mode hides three sections mid-session while FR-167 flips the thresholds editor "in the same frame".

**UX-16 — FR-220 forbids the prose FR-223 must contain.** *(High)*
FR-220: "Every page is written for a reader on glycemicgpt.org… Prose does not refer to 'this repository', to file paths, or to the reader's clone." FR-223 must tell the reader to fork *the repository*, add *repository secrets* and run a workflow; FR-225 must point at `scripts/ci-local.sh`; FR-219 requires absolute `github.com/lumose-health/ios-unofficial/blob/main/...` links. The rule needs scoping (presumably it is about *upstream's* clone, not the reader's fork), or the two highest-traffic pages violate it by construction.

**UX-17 — The docs surface has no owner, no IA, no voice standard — for a persona who cannot do the task.** *(High)*
FR-212 is declared the single CODEOWNERS roster and does **not** include `docs/`, `README.md` or `MEDICAL-DISCLAIMER.md` — the three highest-consequence prose surfaces in the product, one of which (FR-235) depends on a human review checklist with no named owner and no stated location. FR-223 targets Marcus, "comfortable with a phone and not much else", and the task is: create an App Store Connect API key, base64-encode a `.p8`, set repository secrets, dispatch a workflow. No FR requires screenshots, a guided script, a copy-pasteable block format, or a reading level. The gap between the persona and the task is the biggest UX risk in §5.12 and nothing addresses it.

**UX-18 — UJ-3 ends at success and skips every state a designer must draw.** *(High)*
No validation-failed state (FR-180), no lapsed-membership state (FR-182 warns "below a threshold" — which threshold, where?), no day-85 rebuild-and-reinstall flow, and no post-expiry state. On expiry the app *does not launch*, so the product has no surface at all at its single highest-severity moment; the last thing the user saw was our banner. There is no journey, no copy requirement and no onboarding-education requirement for "this stops working in 90 days unless you act".

**UX-19 — FR-187's expiry escalation model is the thing to design and it is entirely `[ASSUMPTION]`.** *(High)*
A-38's "passive Settings row until 30 days, persistent non-blocking banner at 14, local notification at 7, 3 and 1" is explicitly unanchored. No copy, no interruption level (they must not read as a glucose alarm; FR-235 constrains alerting language project-wide), no dismissal semantics, and no priority against the Coverage Claim banner that SI-6 requires on the same real estate. Two competing persistent non-blocking banners is a concrete hole.

### 3.3 Medium

**UX-20 — §8's Verification Status vocabulary is user-visible with no presentation spec.** FR-22 renders "exactly one of Verified, Protocol-Implemented, or Beta"; the same words appear in pairing copy and in the README table. No explanatory copy, no visual weight, no guidance on what a Builder should *do* about Beta. FR-16's safety-relevant statement ("not suitable as a sole monitoring path on iOS") lives only in documentation and never reaches the UI spec. On a monitoring app whose thesis is honesty, an unexplained enum on the row that answers "can I trust this?" is a gap the designer fills from nothing.

**UX-21 — The greyscale distinguishability gate is merge-blocking with no rubric.** FR-126 and §5.7's feature NFR make it "a merge-blocking human review, not a style note", explicitly not a Required Check. There is no reference set, no method, no pass threshold, and no named reviewer. The designer must invent the greyscale system *and* its acceptance rubric.

**UX-22 — FR-172 requires an instructional complication-placement tutorial with no spec.** "the section explains how to add the app's complications to an Apple face and its widget to Smart Stack." Multi-step, OS-version-dependent, illustration-hungry — 40% of a designer's time on that section — with no copy, no step count, no illustration guidance, and no statement of whether it lives inline, in a sheet, or in docs.

**UX-23 — Settings focus management is unaddressed.** NFR-26 fixes focus order for Home only. Settings is where it matters: thirteen sections, mode-dependent visibility, a card that re-evaluates on every foreground (FR-171), and a control that changes another section's editability "in the same frame" (FR-167). Nothing states where VoiceOver focus lands after a mode flip or after returning from iOS Settings.

**UX-24 — FR-89's combined VoiceOver description is the wrong pattern for a statistics card.** Eight values in one unnavigable utterance. Merging is exactly right in FR-96, where the safety requirement is that a number cannot be heard without its qualifier. Applied to a data table it makes the surface less usable.

**UX-25 — FR-91's fixed row inventory has no room for FR-92's conditional meter name.** FR-91 fixes the row as time, units, badge, "BG", IOB plus a reason line; FR-92 then requires the row to name the meter "where the winning reading came from a BGM source". A per-row conditional element in a fixed-column table is a layout problem neither FR solves.

**UX-26 — The Bolus History screen gets one sentence.** FR-91: it "offers the full period set filtered by retention and shares one period selection with the Home card." No grouping, day headers, paging, scroll behaviour, or distinct empty state. Contrast FR-103, which pins meal history to "a fixed page of 50 records with no pagination and no infinite scroll."

**UX-27 — FR-114's Watch chat screen has no state inventory.** Prompts, truncation, failure copy and the Backend-optional terminal message are given; idle → composing → in-flight → answer is not. The answer is unbounded plain text on a 41 mm screen, potentially with speech playing, with no scroll rule, no truncation rule, and no stated relationship between visible and spoken text.

**UX-28 — Provenance is specified twice, as two screens, with no owner.** FR-187 requires version/build/tag/commit/channel/dates/days-remaining; FR-216 requires "a screen reachable with no Backend connection" showing the upstream commit, the CONTRACT_VERSION and the paired Backend; FR-174/FR-166 own Settings composition. Nothing says whether these are one screen or three, and FR-187's certificate/profile/membership rows are conditional ("Where the pipeline recorded them") — a designer cannot lay out a surface whose fields may or may not exist.

### 3.4 Low

**UX-29 — Two carb precisions on one screen.** FR-97 renders grams to one decimal when fractional; FR-102 renders macros and net carbs in "**whole** units… no false precision on an estimate". The same screen may show "≈ 40.5–55 g carbs" above "≈ 34–49 g" net carbs. The whole-units rationale applies at least as strongly to the headline range.

**UX-30 — Pinned copy is already internally inconsistent on punctuation.** FR-4 uses `"Scanning..."` (three periods); UJ-5 uses `"Estimating carbs…"` (ellipsis character). Pinning copy to this granularity guarantees PRD-to-product drift and invites the copy to be treated as un-reviewable.

### 3.5 §6–§10 (accessibility parity, Parity Ledger disclosure, status vocabulary)

**UX-31 — NFR-30's registry has no rule for deleted or net-new surfaces, so the gate cannot be green.** *(Blocking for the accessibility work item; the design half of PLAN-10)*
The criterion is "every Compose `testTag` … has a byte-identical accessibility identifier on the corresponding iOS or watchOS surface", and "the diff is the gate." But PL-31/PL-32/PL-34 delete the watch face, PL-45 deletes the draggable FAB, PL-40 deletes the Custom Plugins card, PD-36 deletes calibration and PD-45 rewrites copy — while PA-1/PA-2/PA-3/PA-13/PA-18 add the Live Activity, widgets, Smart Stack, guided complication setup and internal routing with no Android ancestor at all. The only exception the PRD names is the single `pairing_fault` duplicate. A documented deletion allowlist and an additive namespace must exist before the check does.

**UX-32 — NFR-26's "one combined description per card" and NFR-30's per-`contentDescription` parity are not the same artifact, and the mapping is undefined.** *(High)*
Android's 113 `contentDescription` values sit on individual Compose nodes; NFR-26 requires iOS cards to expose *one merged* description so a value cannot be separated from its qualifier. "Every `contentDescription` has a corresponding combined VoiceOver description" is therefore a many-to-one relation whose rule nobody states — and CI is meant to diff it. FR-178 owns per-card phrasing, so the two must be reconciled by the same person.

**UX-33 — NFR-27 names a priority rule but no reflow ladder, while making largest-AX-size snapshots a gate.** *(High)*
"The glucose value and its trend glyph take priority over secondary metrics; a safety qualifier is never the element that drops" is the whole specification, applied to every screen at the smallest supported device width. What actually drops, in what order, on Home, chart detail, bolus history, meal capture and each settings card is uninvented. Whoever writes the first snapshot fixture silently becomes the spec author. A per-surface reflow order is needed before those tests are pinned. Pairs with UX-5 and UX-6.

**UX-34 — The five highest-stakes safety disclosures have a named surface, no named words, and no review requirement for the original copy.** *(High)*
PL-6 (Medtronic reconnection is foreground-only, and Android's "the pump is remembered — GlycemicGPT reconnects on its own" is *false* here), PL-13 (force-quit silently stops all monitoring), PL-15 (the absence of a watching indicator must never be read as watching), PL-23/PL-24 (the alarm can be silenced and the app cannot detect it), PL-54 (an expired build does not launch, monitor or alert). §7 requires the surface. NFR-31 declares such text "safety copy … any future *translation* of them is a safety change requiring the same review as a threshold change" — but the *original English* gets no equivalent review requirement, and FR-212's CODEOWNERS roster does not cover `docs/` or `MEDICAL-DISCLAIMER.md` (UX-17). Someone must write words that carry a probabilistic safety limitation without either driving abandonment or being skimmed, and someone must review them.

**UX-35 — Nobody owns the total disclosure load or its sequencing.** *(High)*
Counting only §7 and §5: force-quit (FR-15), silenceable alarms (FR-66), no guaranteed background cadence (FR-83/FR-84), 90-day expiry (FR-187), annual paid Apple membership (FR-223), App ID registration burden (FR-181), no re-prompt after a permission denial (FR-3), Local Network denial (FR-151), Beta-Driver gating (FR-16), and the unskippable safety acknowledgement (FR-160). Several must land at first run. Each is specified individually; none is budgeted collectively. A first-run flow stacking six "this may not alert you" statements trains dismissal — the exact failure SI-6 exists to prevent, and SM-17 forbids solving it by removing any of them. The honesty information architecture (what is onboarding, what is Settings-on-demand, what is the FR-166 Reliability card, what is docs-only) has to be invented and ratified.

**UX-36 — "Verified" is the one status word with no plain-language rendering, and it is the most dangerous one.** *(High)*
§8.1 gives Protocol-Implemented a patient-legible form ("*unverified on hardware*") and Beta a label plus "not suitable as a sole monitoring path". Verified gets nothing — while §8.1 itself says it "says nothing about firmware revisions, iOS versions or hardware models other than those recorded", and §8.3 shows it means one named volunteer, one iPhone, one Watch, one OS pair, one date. A patient will read it as clinical approval. Copy rendering Verified as evidence-with-scope, plus the date-and-hardware disclosure surface, is required by nothing today. Extends UX-20.

**UX-37 — §8.1 says status is per-device-model; FR-22 renders it per-Driver, and the collision is unresolved.** *(Medium)*
"The Tandem Driver serves both t:slim X2 and Mobi; the two models carry separate rows and may carry different statuses" — and §8.3 already has them at different evidence levels. What a single Driver list row shows when its two models disagree (worst-of, both, model-selected) is uninvented, and it is safety copy.

**UX-38 — PD-39 claims a user disclosure that has no surface.** *(Medium)*
NFR-7 and PD-39: 30-day chart truncation at 2,000 rows is "never silent to the user where it changes what a chart means" — but the only place it is stated is the Parity Ledger, which users do not read. At 5-minute cadence 2,000 rows is roughly 7 days, so the "30-day" chart silently is not one. §7's own standard is not formally binding on a PD row, but the substance is identical: either an on-chart treatment or drop the claim.

**UX-39 — Seven PL rows carry unresolved `[NOTE FOR PM] confirm` disclosure decisions.** *(Low)*
PL-3, PL-7, PL-38, PL-48, PL-49 (recorded as owing no user-facing copy), PL-44 (depends on the unanswered iPad question), PL-45 (may belong in PD rather than PL). Individually small; collectively the residue a designer trips over when auditing "every loss has a surface."

---

## 4. Epic and Story Planner

### 4.1 Blocking

**PLAN-1 — §12.3 gives no FR-to-phase allocation for P1, P2, P4 or P5.** *(Blocking for backlog construction)*
Only P0.3 (FR-197–199, 213), P0.4 (FR-214–216), P0.5 (FR-35, FR-36), P0.6 (FR-206) and P3 (FR-179–196, 219–237) name FRs. P1 ("Tandem read path end to end… Alert Floor logic, dashboard") and P2 ("Surfaces: Watch app and complications, glanceable surfaces, AI Chat, meals, onboarding and Settings, accessibility identifier registry") name subsystems, and their boundary is ambiguous — "dashboard" is in P1 while P2 is "Surfaces". A planner will assign roughly 140 FRs by guesswork.

**PLAN-2 — P2 is one phase of roughly ninety FRs with an exit criterion covering about a tenth of them.** *(Blocking)*
Exit: "Greyscale distinguishability gate green for all six coverage branches; accessibility identifiers registered and enforced." That says nothing about meals, AI Chat, onboarding, Settings, or the glanceable surfaces, all of which are inside P2. It is unestimable and its Done is undefined.

**PLAN-3 — Seven open questions are marked blocking and none has an owner or a slot.** *(Blocking)*
OQ-9 (Medtronic spike b — explicitly unowned), OQ-36 (SI-12 carve-out for the dispersion flags), OQ-45 (ATS plist — "blocking for architecture"), OQ-48 (debug gate under TestFlight), OQ-49 (repository stays public), OQ-50 (one App ID set or two — "must be decided **before** the FR-182 provisioning workflow is built"), OQ-56 (counsel; "blocking for publication", gates the two highest-traffic pages). §15 gives none of them an owner, a due phase, or a decision forum. Two of them gate P0/P3 work directly.

**PLAN-4 — §12.1 forecloses the only planning lever and does not say who may reopen it.** *(Blocking as a planning premise)*
"The MVP is therefore the whole product: FR-1 through FR-237, all twelve feature sections, both shipped device Drivers, the Watch app, the Builder pipeline, the engineering gates and the published documentation — minus exactly the deferrals enumerated below… No feature section is thinned." That is a defensible product stance under a parity mandate. It is also 237 FRs at this density against a team whose lead developer has no iPhone and whose entire Tier 4 surface is one volunteer. A planner needs to be told explicitly who holds the authority to cut, and against what criterion, or the first schedule conversation will relitigate the mandate.

### 4.2 High

**PLAN-5 — The sequencing has a real circular dependency around P3 and P4.** *(High)*
P4 is DanielDanielson's device pass, and §12.3 says "Schedule early — it can invalidate copy, and copy changes ripple across the app, the Watch app and the docs." But P4 requires a fork build, which requires P3's Builder pipeline; and P4's most important output (the measured background cadence, OQ-26) can invalidate copy produced in P2 and documentation produced in P3. As ordered, the thing that must happen early structurally happens fourth.

**PLAN-6 — D-4 / OQ-50 is a P3 blocker sitting in an unanswered open question.** *(High)*
"Must be decided **before** the FR-182 provisioning workflow is built, because it changes what that workflow registers." No owner, no date. It also has a downstream consequence nobody has costed: ARCH-46's single-ASC-record collision.

**PLAN-7 — FR sizing varies by roughly 20×, with epics and one-liners adjacent in the numbering.** *(High)*
Epics wearing FR numbers, at minimum: **FR-13** (reconnection ladder + phases + conformance test), **FR-32** (two-gate asymmetry + Safety Limits validation + staleness + history-extraction drops + two bolus caps + a ×1000 scale assertion + an API-signature rule + the Tandem `egvStatusId` gate with five pinned cases + the `ControlIQIOBResponse` selector gate with three), **FR-37** (the whole Driver UI vocabulary), **FR-23**, **FR-14**, **FR-52** and **FR-53** (the chart), **FR-89** (ten independently estimable pieces), **FR-104**, **FR-102**, **FR-138**, **FR-146**, **FR-155**, **FR-166**, **FR-176** (a debug console + a substitutable freshness policy + seven injections + two release-build gates, and the declared verification substrate for all of §5.4), **FR-192**, **FR-218**, and **FR-228+229+230** together. Against them: FR-62 is a one-line cross-reference, FR-7 is a warning string in two places, FR-16 is disclosure copy, FR-38 is almost entirely a pointer to FR-153, FR-174 is one row, FR-190 is one xcconfig line. Estimation across the document is not possible without a re-decomposition pass.

**PLAN-8 — The cross-reference "single owner" pattern creates a dependency graph nobody has drawn.** *(High)*
FR-79 cannot ship without FR-169; FR-80 without FR-168; FR-82 without FR-143; FR-44 without FR-152; FR-133 without FR-52; FR-120 and FR-119 without FR-46; FR-62 without FR-175; FR-88 without FR-176; FR-143/FR-164/FR-167 are one story, not three. FR-8 gates FR-1/6/9/13/20/43/119; FR-30 gates FR-23/24/25; FR-35 and FR-36 gate every Simulator-tier acceptance criterion in the document. A planner slicing by FR number will ship two-thirds of several safety rules. The graph is implicit and correct; it needs to be published.

**PLAN-9 — FR-177's completion criterion is defined by a cross-reference that explicitly refuses to define it.** *(High; trivially fixable)*
FR-177: "The registry is complete only when it reaches **NFR-30's identifier count**", citing NFR-30 "for the two system-wide parity counts". NFR-30 says the opposite twice: "**The parity target is a generated registry, not a pinned number**" and "**[NOTE FOR PM] Do not pin a count.**" §5.9's own description agrees with NFR-30. FR-177 is the declared acceptance substrate for every Simulator-runnable gate in §5.3, §5.4, §5.5, §5.9 and §5.10, so no definition of done exists for it and no CI check can be built.

**PLAN-10 — NFR-30's registry diff is red by construction on day one, with no exception policy.** *(High)*
The rule is byte-identical parity with Android `testTag`s. There is no policy for (a) net-new iOS surfaces with no Android counterpart — widgets, complications, Live Activity, Dynamic Island, build-expiry, Coverage Claim variants, the five Not-Watching Reason lines — or (b) Android surfaces with no iOS counterpart (the whole `:watchface` module). "The diff is the gate" needs a mapping table and an allowed-divergence list.

**PLAN-11 — FR-177 has a hard, invisible dependency on the §5.11 CI epic.** *(High)*
Its enforcement is written entirely in terms of `Build & Test`, `iOS Gate`, `UI Tests (Simulator)`, FR-197, FR-208 and FR-209. FR-177 cannot reach Done before those exist — and since FR-177 is also the acceptance substrate for four other sections, this is a critical-path constraint invisible from the FR numbering.

**PLAN-12 — Ownership and timing of the repo/CI/docs work is never stated, and there is a bootstrap ordering problem.** *(High)*
Roughly 45 of the 59 FRs in §5.10–§5.12 produce no app code. Nothing says whether §5.11 lands before §5.10 (it must: FR-219's docs gates, FR-211's header gate and FR-190's version check are all hosted inside checks FR-197 creates). Unaddressed: the first PR introducing `Static Analysis Gate` must itself pass gates that do not exist, and `iOS Gate` cannot aggregate `Build & Test` before any target builds.

**PLAN-13 — A large fraction of acceptance criteria are device-only and route to one person, with no allocation model.** *(High)*
FR-135, FR-151, FR-162, §5.8's feature NFRs (file protection, Keychain accessibility, Local Network, background scheduling, deferred-upload survival, Low Power Mode), §5.9's feature NFR (lock state, Focus, ring/silent), §5.1's five-item release gate, §5.7's eight on-device acceptance items, and every Tier 4 line in §9.1. All land on DanielDanielson. §9.4 and R-5 name this correctly as the highest-severity structural risk, but no epic structure exists for it. A planner cannot mark these stories Done inside a sprint. This needs an explicit "device validation batch" concept, not per-story hardware waits.

**PLAN-14 — The §5.1 hardware sign-off gate has no owner and an open question about its own existence.** *(High)*
Five items are a "documented release gate"; the section's own open questions then ask, for Medtronic, "Who validates, and does FR-6 ship gated behind an unvalidated label until they do?" A release gate with no named owner cannot be scheduled.

**PLAN-15 — FR-234's expected v1 table state makes the release depend on one named person.** *(High)*
Tandem t:slim X2 reaching Verified requires DanielDanielson to build from their own fork and commit a completed FR-207 checklist, and FR-207 makes checklist completion a release gate no CI job can execute. §9.4 states the consequence exactly: "'no validator' and 'gate not met' become the same state." Correctly identified, not resource-planned.

**PLAN-16 — Dependencies outside the project's control are scattered across FRs and never aggregated.** *(High)*
**Apple:** App ID and capability registration semantics (FR-182), the Critical Alerts grant (FR-182/FR-204 — correctly designed never to block), ASC upload-rejection message surfacing (FR-183/FR-191), the 90-day expiry itself (FR-186/FR-187), export compliance (ARCH-40), Beta App Review exemption for internal testers (FR-223, A-56). **GitHub:** fork Actions defaults and scheduled-workflow behaviour (ARCH-41), the 60-day inactivity disable (FR-186), `pull_request_target` semantics (FR-194/FR-203/FR-218), `security-events: write` not granted to fork PRs (FR-199), macOS minute pricing (OQ-49). **The `website` repo:** FR-222 requires a GitHub App installed with `repositories: website` plus `CI_APP_ID`/`CI_APP_PRIVATE_KEY` — a cross-repo installation this project does not own, with no fallback. **Counsel:** OQ-56 gates FR-223 and FR-234. **Tooling vendors:** `codeql/swift-queries@<x.y.z>` must exist at a pinnable version with `security-extended` Swift coverage or FR-200's entire premise fails. Each is knowable; none is on a single risk register a planner can schedule against.

**PLAN-17 — FR-90's flagship acceptance criterion is not mechanically testable.** *(High)*
"A test asserts that no surface renders the three values in a single additive row or with a sum/`=` affordance." No automated test can assert the absence of an implied equation across arbitrary layouts — and this enforces what the section calls "the single most load-bearing honesty rule" in the feature. It must become a concrete structural assertion (a lint over view composition, or a snapshot set) or an honestly labelled review gate.

**PLAN-18 — FR-194 contains an unresolved either/or inside its acceptance criteria.** *(High; send back)*
"Either it is written here or every reference to it, including its workflow-security allowlist entry, is removed." That is a decision, not a requirement. (Verified: `auto-merge-renovate.yml` does not exist in the Android repo, so the PRD's underlying claim is correct.)

### 4.3 Medium

**PLAN-19 — FRs a planner must send back before writing a single story.** Consolidated list at §6.

**PLAN-20 — Acceptance criteria not testable as written.** FR-64 ("remains legible"); FR-124 and FR-126 ("distinguishable by a reviewer who has not read the code"; the greyscale gate); FR-134 ("the true link state"); FR-96 ("asserts that a screen rendering a carb estimate with zero qualifier elements is impossible"); FR-97 ("a test asserts the two are distinguishable with colour perception removed" — no method, threshold or tool); FR-102 ("the app authors none of it and rewrites none of it"); FR-112 ("issues zero network requests" — no observation seam); FR-186 ("notifies the Builder" — no channel); FR-187 ("Where the pipeline recorded them" — conditional with no trigger); FR-196 ("that boundary is stated in writing" — where?); FR-217 ("in a glucose or Pump-time context"); FR-235 ("a review checklist item — explicitly a human review step" — no artifact, owner or location, in contrast to FR-207 which correctly makes its checklist a committed CODEOWNERS-held file).

**PLAN-21 — FR-96's required-lane counterpart does not test the requirement.** The `Build & Test` substitute asserts "every carb-rendering view model emits a non-empty qualifier constant", which does not establish that the qualifier is on screen *at the same time as* the number — the actual guarantee. Either size a third story for a structural assertion or record the residual gap.

**PLAN-22 — FR-186 is contradicted by an open question in the same document.** FR-186 mandates the scheduled rebuild, shipped enabled, at an assumed 30-day cadence (A-36). OQ-58 asks whether the fork template should ship a scheduled rebuild at all. A planner cannot write FR-186 stories while the FR's own existence is open.

**PLAN-23 — FR-196 is a posture, not a deliverable.** Its six consequences all defer elsewhere (FR-212, FR-202, FR-226, FR-223, FR-194) plus one statement about what the project claims. It will produce a story with nothing to build; merge or drop it.

**PLAN-24 — FR-207's checklist cannot be authored from its own section.** It must enumerate "every property §9.1 Tier 4 enumerates" and absorb contributions from §5.1, §5.4 and §5.7. That is a cross-epic assembly task with four upstream dependencies; it needs its own story with an explicit blocked-until list.

**PLAN-25 — FR-234's feature NFR cites a check no FR defines.** "`Static Analysis Gate`… carries FR-219's four docs checks plus FR-220's `externalLinks` check." FR-220 defines no `externalLinks` check, and FR-197 states explicitly that FR-220 "contributes no step". `externalLinks` is a *website-repo* concept (addendum §4) that FR-219 deliberately designed around.

**PLAN-26 — The Required Check list exists in three places, only one of which is drift-checked.** FR-197 compares `CONTRIBUTING.md` against the configured ruleset. FR-237 requires the published iOS security-testing page to document the five by exact name with thresholds — a third copy under no drift check, in a tree that also carries contributor documentation duplicating `CONTRIBUTING.md`. Nothing says which is authoritative, in a section whose stated purpose is that Android's CONTRIBUTING-vs-CI drift is not inherited.

**PLAN-27 — FR-105's Out of Scope mandates work in another section.** It requires FR-159's Features card and FR-170's sound-row copy to describe a Backend-pushed alert rather than a screen. A planner slicing §5.6 will not deliver it; a planner slicing §5.9 will not know §5.6 mandated it.

**PLAN-28 — SI and UJ traceability tags are applied inconsistently, so a traceability matrix built from them will mislead.** FR-8 and FR-12 are both tagged "Upholds SI-1" though neither concerns therapeutic writes (FR-12's actual invariant is SI-6). FR-2's SI-1 link sits inside a consequence bullet rather than the header. FR-30 — the actual structural basis for SI-1 having no carve-out — is tagged SI-1 alongside those weaker links, flattening the signal. Ninety FRs carry no "Realizes UJ" line at all.

**PLAN-29 — Meal retention interaction is unstated.** FR-89/FR-91 filter period choices by the local retention setting; FR-103 makes meal history Backend-only with no local cache, so retention presumably does not apply. No FR says so.

**PLAN-30 — Three message-length caps with no stated relationship.** Phone 2000, Watch 500, widget prefill 500 (FR-107, FR-114). Nothing states the Backend's own limit or which is authoritative. One story or two is genuinely ambiguous.

### 4.4 Low — document integrity defects

**PLAN-31 — §14 defines R-1…R-13, R-20, R-21, R-22 and nothing else, but R-16 and R-23 are cited from live text.** SM-16 and OQ-49 both cite R-16 ("macOS runner cost pressure"); SM-11 cites R-23. R-14 through R-19 and R-23 are never defined. §15 and §16 both explicitly enumerate their retired-ID gaps and state what a gap means; §14 does not. Seven dangling risk references, three of them live citations.

**PLAN-32 — §15's own falsifiability claim is false.** It states the live set "runs OQ-7 through OQ-63 with no other break" and that "a reader finding a gap not on that list has found a defect". Counted mechanically: 51 live questions, OQ-7 through OQ-**62**, with an unaccounted gap at **OQ-57** and no OQ-63 anywhere in the document. (Both were deliberately removed in the late docs-scope correction; the self-check sentence was not updated.) The count of 51 is correct; the range statement is not.

**PLAN-33 — §7.4 and §5.7 contradict each other about whether PD-42's conforming edit was made.** §7.4: "PD-42 needs one conforming edit outside this section… 5.7 does not yet carry it: FR-120's Fresh case renders 'the value with its trend glyph'… nothing degrades the glyph independently on the wrist." §5.7's notes: "PD-42's conforming edit is made… FR-120 now does." FR-120 as written *does* carry it, in full, with pinned provenance pairs. §7.4's note is stale. This is not hypothetical: one of the five reviewers on this pass, reading §7.4, reported the closed defect as an open High-severity wrist safety-display bug. A story writer will do the same.

### 4.5 §6–§10 (NFRs, matrices, tiers, gates)

**PLAN-34 — NFR-34's acceptance mechanism depends on an artifact that does not exist.** *(Blocking for the §6 epic; cheap to fix)*
NFR-34: "Every NFR in this section is tagged in the Validation Tier model (§9) as Simulator-provable, unit-test-provable, or device-only", and every device-only NFR must name an owner before v1 scope freeze or escalate to §12. §9 contains no per-NFR tagging — §9.1 and §9.2 classify *properties*, not NFR IDs. The gate governing all 34 NFRs has no input, so no NFR can be accepted or escalated. Someone must produce the NFR → tier → owner map.

**PLAN-35 — NFR-30's registry is generated from another repository with no pinning rule.** *(Blocking for that check; the CI half of ARCH-68)*
"Generated from the Android source, committed, and diffed by CI — the diff is the gate", with the note conceding the counts "drift every time the Android client changes." No `android-unofficial` revision is pinned, no regeneration cadence is defined, and no owner for reconciliation is named. As specified, an upstream Android commit turns the iOS gate red with no iOS change. Send back: pin a SHA in the iOS repo, define the bump ritual, pair it with UX-31's exception lists.

**PLAN-36 — NFR-10's publication rule is unsatisfiable in v1 by construction, and the decision is left as an open question.** *(High; send back)*
Publishing a battery figure requires "at least two people on at least two device models." §9.4 and §8.3 establish that exactly one person holds iPhone + Watch hardware, and §6's own note observes that §13 carries no measurement task with a named owner. The section then asks the question and answers it hypothetically ("which is acceptable, but should be decided rather than defaulted into"). A planner cannot schedule this. The PM should rule "no battery figure in v1" and record it in §12.2 alongside D-8.

**PLAN-37 — §8.1, §9.3 and §8.3 disagree about whether Tandem Mobi may hold Protocol-Implemented.** *(High)*
§8.1: "Status is per-device-**model**, never per-Driver … Evidence about one model is not evidence about the other." §9.3: Protocol-Implemented requires "Tier 1 + Tier 2 (**a recorded frame corpus for that device family** must exist)." §9.1 Tier 2: "a device family with **no recorded frames** has no Tier 2 coverage at all: today that is **Tandem Mobi** and every Medtronic model." §8.3 nonetheless lists Mobi as Protocol-Implemented. "Family" is undefined and the three statements cannot all be true. The outcome is user-visible safety copy on the Mobi row and in the README, so it must be resolved before the Driver epics are written.

**PLAN-38 — NFR-33's community frame-capture path is forbidden by §9.1 Tier 3.** *(High)*
NFR-33: "a validator can capture recorded real-Pump frames and a maintainer can replay them" — described as "the only way a Pump-specific defect becomes reproducible for a developer who has no such Pump." §9.1 Tier 3: "**This tier is the only source of new recorded frame corpora**", and Tier 3 is a macOS bench held by the lead developer, who owns only a t:slim X2. Since Mobi and every Medtronic model have no corpus and nobody on the project owns one, community capture is the sole route to Tier 2 for them — and §9 rules it out. Also unspecified (and A-7 flags it without resolving it): who de-identifies user-captured frames, with what tooling, and how that reconciles with NFR-25's "the export contains no raw pump frames".

**PLAN-39 — §9.4's single-validator constraint has four concrete plan consequences, and the mitigating artifact is unscheduled.** *(High)*
(a) Any story whose definition of done includes hardware validation is unestimable, because it queues behind a volunteer with no committed availability. (b) The release gate is binary and, per §9.4, "'no validator' and 'gate not met' become the same state" — so the release plan needs a pre-agreed "ship with zero Verified devices" path. §8.3 supports it mechanically (empty validator cells read Protocol-Implemented), so that should be the *default* plan with Verified treated as a post-release event. (c) FR-207's written checklist is the only redundancy that exists and therefore belongs early on the critical path, not near release. (d) Tier 4 items must be batched into as few sessions as possible, and no section defines that batching artifact — a session agenda ordered by what a single overnight soak can cover. (d) must be invented; (b) must be ratified. Extends PLAN-13 and PLAN-15.

**PLAN-40 — §8.2's auto-demotion question gates all Driver sequencing.** *(High)*
"Whether a change to a Driver's protocol or transport code automatically demotes that Driver's row from Verified pending re-validation is unresolved", and §8.2 notes demotion is "cheap to apply and expensive to reverse, because reversal needs another Tier 4 session from the one person who can run them." If demotion is automatic, every post-Verified Tandem pull request consumes the single validator — which changes how Driver work is batched and released. Carried as OQ-17; must be decided before the Tandem epic is sequenced.

**PLAN-41 — §6's notes contradict §7.4 and FR-158 on PL-72.** *(Medium; same class as PLAN-33)*
§6's note: "PL-72's honest-gaps statement is mandated only by NFR-33, and FR-158 — which owns the export — does not yet carry it." §7.4: "PL-72 … **CLOSED**. FR-158 now carries the statement on the artifact itself." FR-158 does carry it. A planner reading §6 first creates a story for work already done.

**PLAN-42 — §6.2 has no cold-start number despite NFR-6 calling it a target.** *(Medium)*
"Time-to-first-frame is a target; time-to-first-**honest**-frame is a requirement." The requirement half is genuinely testable — pessimistic seeds, no all-is-well flash, no network or Bluetooth before first frame. The target half has no number, so no acceptance criterion can be written and it will never be measured. Give it a Simulator-measurable number or delete the word "target".

**PLAN-43 — §6 adds a large, multiplicative, unsized test matrix that lands on the most expensive runners.** *(Medium)*
Snapshot tests for every registry screen at default *and* largest accessibility size (NFR-27); every complication and widget family in **every** rendering mode plus Always-On dimmed (NFR-28); pseudo-localized expansion on every screen (NFR-31); performance tests at six data ceilings (NFR-7); migration tests at **every prior schema version** (NFR-15); and a second all-Drivers-enabled build configuration (FR-208). A-53 correctly keeps these off the Required Check roster, but the wall clock lands on macOS runners at PL-63's ~10× multiplier — which §7 raises only for Builders' private forks, never for upstream. Size this as its own story set with a CI budget, and connect it to SM-16 and OQ-49.

**PLAN-44 — §9 models machine evidence only; the merge-blocking human gates sit in no tier and no capacity model.** *(Medium)*
The greyscale complication review (§5.7: "a merge-blocking human review, not a style note — and not a sixth Required Check"), CODEOWNERS trust-boundary review (FR-212), project-lead review required by SI-1, and CodeRabbit's advisory layers (§10.3) are all real per-pull-request costs on a project with one lead. None appears in §9's four tiers. Lead review has to be treated as a finite resource in sprint capacity.

**PLAN-45 — Orientation: how much of §6–§10 is schedulable work versus policy.** *(Medium — not a defect)*
*Genuine build stories:* NFR-4 (shared safety module and App Group contract), NFR-15 (migration framework and fixture stores), NFR-19 (encrypted store, key custody, protection class), NFR-24/25/33 (structured logging, scrubber, export, diagnostic state surface), NFR-30 (registry generator and CI diff), NFR-20 (the in-app address classifier and its two enforcement points), FR-207's checklist document, and the two §8.4 spikes.
*Acceptance criteria on other stories, not stories:* NFR-5, NFR-6, NFR-8, NFR-9, NFR-13, NFR-14, NFR-16, NFR-17, NFR-21, NFR-26 through NFR-29.
*Policy already discharged into FRs, needing no epic:* all of §10 (it maps to FR-197–FR-218), §8.1/§8.2's vocabulary, §9.1–§9.3.
*Policy needing a decision rather than a story:* NFR-10, NFR-34, §8.2's demotion rule, NFR-3's floor-runtime CI question, the iPad question.
*Hard sequencing constraints the slice implies but never states as a sequence:* NFR-4 gates every target; §8.4 spike (a) gates the entire Medtronic architecture and is marked "Done first"; OQ-45's ATS verification gates FR-204's real baseline; PA-7/PA-8 (the Simulated and Trace-Replay Drivers) gate Tiers 1 and 2 and therefore gate nearly everything else.

---

## 5. What is notably strong

This is worth stating precisely, because several of these are the kind of thing a revision pass quietly deletes as verbose.

**Invariants that are decidable, not aspirational.** §4 attaches an enforcement mechanism *and* a stated consequence to every invariant, and §12.3 P0.2 makes the shared safety module a phase-zero exit criterion with boundary tests at min, max, min−1, max+1. Better still, **FR-30 + FR-31 + FR-205** make SI-1 structurally decidable: removing the calibration-target Capability so that "no Capability member writes to a device" is *unconditionally* true means FR-205's protocol snapshot gate can treat any newly added write-shaped member as a failure, with no permitted-write exception to reason about. The strongest safety claim in the product is made checkable by a diff. That is genuinely excellent invariant engineering and it should survive editing intact.

**Single-owner rules that actually resolve.** "This FR is the single definition of X; section Y defers here and states no second rule" appears on freshness (FR-49), alertability (FR-72), trend-glyph provenance (FR-46), the chart Y axis (FR-52), wrist alert transport (FR-128), the wrist preference set (FR-134), retention (FR-139), threshold clearing (FR-143), the cleartext classifier (FR-150), reachability derivation (FR-152), the sound model (FR-67), the install remedy (FR-115), the reconnection rule (FR-13) and the Required Check roster (FR-197). Every one of those targets was followed and every one resolves except FR-177→NFR-30 (PLAN-9) — which stands out precisely because everything else holds. This pattern converts almost directly into architecture module boundaries.

**Precision on the two hardest honesty rules.** FR-49 declares itself the single definition of negative-age handling ("Fresh **for display only**, at every magnitude") and FR-72 owns alertability separately and more strictly, with the pinned pairs spelled out: −60,000 ms alertable, −60,001 ms not; 359,999 ms alertable, 360,000 ms not; −120,000 ms displays Fresh and is not alertable. FR-123 then carves out the one label exception and says so by name. Three sections, one rule, zero drift. Very few PRDs get this right even once.

**Pinned boundary pairs everywhere.** FR-47 (55/56/70/71/179/180/249/250), FR-52's five axis resolution cases, FR-58's bucket comparisons and its deliberate divergence from FR-47, FR-71's classification pairs, FR-116's tier pairs, FR-120's wrist provenance triples, FR-125's sanitization ladder. These are test cases already written. A test engineer can start from the document.

**The deliberate-asymmetry statements.** FR-32 and FR-138 each state, from their own side, that the Driver gate and the storage gate use different bounds *by design*, give the reason for each, and add "so a reader does not read it as a defect" and "a future reader does not 'fix' one into the other". This preempts exactly the "unify these two validators" refactor that would silently break the product. FR-92 does the same for the third bound. It is the single best-written idea in the document.

**Negative requirements with negative tests.** FR-12 specifies what the app must *not* do, with a pinned test that 19 encryption failures produce no user-visible effect, plus an explicit statement of why the false-positive cost is higher on iOS than Android. FR-51 requires that "a fully Fresh screen contains zero staleness-badge elements, and this is an assertable test invariant." FR-141 explicitly closes an inference a reader would otherwise make: "no backoff ladder in this section may be read as introducing one" for pump reconnection. Restraint requirements are almost never written down and are almost always lost in a port.

**§9, and §9.2 in particular.** "What Tier 1 falsely passes" — entitlements, background execution, notification delivery, complication budgets, Data Protection and Keychain, each with Simulator behaviour, hardware behaviour and *when it fails* — tells architecture exactly which test seams to build, and it is why FR-61's injectable clock, the Simulated Driver and the Trace-Replay Driver are non-negotiable in §12.1. The binding consequence ("no Tier 1 result may be cited as evidence for a Verification Status, ever") is the right shape.

**§8.2's raise rule.** Status may only be raised by recorded evidence; may be lowered by anyone with no ceremony, because demotion cannot make a false safety claim. Plus the mechanical corollary: a row with empty validator and date cells cannot read Verified. Asymmetric, enforceable, and correct.

**Error taxonomies where they exist.** FR-102's defensive decoding is complete for one payload (non-finite macros dropped, net carbs skipped on inverted bounds, the block omitted rather than rendered empty, the sugar note retained only when a surviving fact key justifies it "so a dropped sugars value cannot leave an orphaned caveat"). FR-148's session-refresh state machine is handed over complete — generation snapshotted on entry, the fast path comparing against the token the failing request actually carried, five distinguished outcomes with distinct store effects. FR-109 supplies for chat the exact status→copy table FR-95 owes for meals.

**Correctness rules most PRDs leave to a bug report.** FR-154: "Advance only as far as the MINIMUM of the full streams' maxima", plus the >500-records-in-one-millisecond case resolving to a transient error rather than a false success, plus per-page persistence with the reason. FR-150's literal-address parsing: strict octets, no leading zeros, explicit rejection of octal/hex/bare-decimal, IPv4-mapped IPv6 by embedded address, never a DNS lookup, with the DNS-rebinding reason given. FR-103's "A superseded load never writes state… because a repository that maps errors into a result type can swallow the cancellation."

**Honesty carried on the artifact, not just in the spec.** FR-158's export "states its own gaps, on the artifact" — "an empty interval means 'the app was not running **or** nothing happened', and the export cannot distinguish the two" — asserted by test and shown in the pre-share preview. Plus the unified-logging trap (interpolated numerics are public by default while dynamic strings are redacted), which is the exact way SI-9 would have been violated silently. FR-142's pending count excludes in-flight rows *and the surface says so*, so a dip does not read as data loss.

**FR-197 as a structural device.** A roster closed at exactly five, matched on job `name:`, with a published host assignment mapping every gate named anywhere in the PRD either to one of the five or explicitly to a non-required job, plus the rule that a Required Check failing without naming one of the five names a gate that does not exist. This single-handedly prevents the most common PRD-to-CI failure mode. FR-198's five-branch aggregation is stated precisely enough to write the workflow and its test from the FR text alone. FR-200's fail-closed set — especially "the gate fails if the analyzer reports zero analyzed files" — closes the specific way a name-only SAST port goes permanently green.

**FR-184 and FR-191 as models for replacing a lost Android control.** FR-184: a fixed-fingerprint equality cannot survive per-Builder signing, so it becomes four named property assertions, hard-fail, pre-upload so a bad archive never consumes a build number. FR-191: rejecting Android's packed `versionCode` *with its failure mode stated* (the collision made the updater report "up to date" forever). Rejecting a known-buggy parity item on the record is exactly right.

**§6.7 is designable-from, not a checklist.** NFR-26's one-combined-description-per-card as a *safety* mechanism (a number cannot be heard without its qualifier); NFR-28's requirement that every complication and widget family be snapshot-tested in monochrome, tinted and accented modes and in Always-On dimmed; NFR-29's rule that every gesture has a non-gestural equivalent so the chart is operable under Switch Control. NFR-30's refusal to pin a count, with the recount shown and the reason given ("the 253 figure was a grep-token artifact"), is the right call and it is documented. **We re-ran it independently: `grep -rn testTag app/src/main wear-device/src/main` returns exactly 249, and `contentDescription` returns exactly 113 — the PRD's self-correction is accurate to the digit.** Self-correction at that resolution is rare and it earns trust in the numbers elsewhere.

**§6's measurement-honesty rule.** Every NFR must be either Simulator/unit-provable or a target with a named protocol and a named owner, and "no NFR here is a claim about a measurement the project has not made." That single sentence is what makes NFR-10's refusal to publish a battery figure defensible rather than evasive, and it is why D-8 has a revisit condition instead of an inherited Android number.

**NFR-4 is the best NFR in the document.** It fixes the data contract (what may live in the App Group container, exactly one writer, cache-is-never-a-store, never an Alert Floor input), states the absent/unreadable/malformed behaviour, derives the container identifier from the Builder's Team ID because App IDs are globally unique, and names the Android defect it must not reproduce (the Wear module mirroring freshness numbers independently). Architecture can build directly from it. **NFR-8's fixed background-wake work order** — with upload last "because it is the only step whose failure is recoverable later" — is architecture-determining and correct.

**§10.1's honesty about the SAST substitution.** Semgrep's Kotlin and Java packs "produce ZERO findings on Swift — a name-only port would be a permanently green check that tests nothing", and the response is to move invariants *out* of static analysis into the type system, FR-205's snapshot gate and FR-206's replay tests. Naming the failure mode of the obvious port, and then not doing the obvious port, is the right instinct applied to the right problem. **NFR-20** does the same thing for transport: under fork-and-build "the app's own classifier is the enforcement mechanism; App Transport Security is not", because the Builder controls their own Info.plist.

**Deferrals with revisit conditions, not "later".** Every one of D-1 through D-9 carries a concrete trigger — "the Backend repository accepts per-deployment APNs configuration"; "the bundled set has shipped through one tagged release **and** import, transcode and delivery of a real low alarm can be validated end to end at Tier 4". D-5 explicitly names the Android failure it is avoiding ("Android has carried the 'while it beds in' state indefinitely with no criterion").

**§13's counter-metrics.** SM-14 through SM-18 name the specific degradations this product would suffer and forbid them in advance: do not optimize alert volume, and specifically not by widening the Fresh window or lengthening the cooldown; do not optimize away honesty copy; do not reduce the gate set under macOS cost pressure; do not hide a prerequisite to shorten onboarding; do not introduce telemetry. Naming the *means* as well as the metric is what makes these enforceable.

**The Parity Ledger's own rule.** A forced loss with no disclosure surface is a defect — and FR-237 exists because five rows named a surface no FR required to exist. §7.4 also flags rows that overlap by design and must not be de-duplicated, with the reason a reader who conflates PL-23 and PL-24 would draw the wrong conclusion.

**The `[NOTE FOR PM]` blocks.** They name their own gaps: the journey-orphaned insulin and AI-Chat FRs, the SI-12 carve-out flagged as blocking rather than quietly assumed, PD-13 asked for confirmation *before* tests pin it, the 5xx meal diagnostic log's "if the scrubber cannot guarantee otherwise, the log must be dropped rather than weakened", and line 741's "Port from the Kotlin source, never from the Android documentation" with the three-way API-version drift it found. That last note saves a real week of a real engineer's time. This self-disclosure is what made a specific review possible; most of the blocking findings above sit in the spaces those notes do not cover.

---

## 6. Send-back list

FRs a planner cannot write a story against, or an architect cannot design from, without an answer. Grouped by who must answer.

### Product / PM must rule

| Item | Question |
|---|---|
| FR-159 / FR-164 | How does a Backend-optional user get past onboarding stage 3? (UX-1) |
| FR-83 | Does `NOTIFICATIONS_DENIED` precede Backend Active in the selector? (ARCH-15) |
| FR-84 / FR-85 | What is the fatigue policy for the coverage-lapse notification? (ARCH-16) |
| OQ-24 | Audibility caveat in the claim *state* or the claim *detail*? (UX-3) |
| OQ-20 | Is colouring from default thresholds acceptable while alerting from them is not, and is the difference visible? |
| OQ-21 / FR-46 / FR-64 | Does the hero numeral scale with Dynamic Type? |
| OQ-22 | Is iPad a supported target? |
| FR-118 / FR-134 | "Any face" or "the active face"? (ARCH-2) |
| FR-143 / FR-168 | Does "Backend configured" mean URL-present or session-valid? (ARCH-32) |
| §12.1 | Who holds authority to cut scope, and against what criterion? (PLAN-4) |
| OQ-50 | One App ID set per Builder or two — before FR-182 is built. |
| OQ-48, OQ-49, OQ-56 | Debug gate under TestFlight; repository stays public; counsel on the manufacturer framing. |
| FR-194, FR-186 / OQ-58, FR-196 | Three FRs whose own existence or content is an unresolved either/or. |
| §5.5 / §5.6 / §5.9 | Do UJ-7 (AI Chat), UJ-8 (settings / thresholds), UJ-9 (advertise-and-wait pairing) and an assistive-technology journey get written? |
| NFR-10 / D-8 | Rule "no battery figure in v1" rather than leaving it as an open question (PLAN-36). |
| §8.2 / OQ-17 | Does a Driver protocol change auto-demote a Verified row? (PLAN-40) |
| §8.1 vs §9.3 vs §8.3 | What is a "device family", and may Tandem Mobi hold Protocol-Implemented with no frame corpus? (PLAN-37) |
| §9.4 / §12.3 P4 | Ratify "ship with zero Verified devices" as the default release plan. (PLAN-39b) |
| NFR-2 / OQ-22 | iPad — the ASC opt-out half is not enforceable upstream. (ARCH-82) |
| §7 disclosure load | Who owns the honesty information architecture and the review of the original safety copy? (UX-34, UX-35) |

### Backend / platform must answer

| Item | Question |
|---|---|
| FR-93 / FR-103 | What is the feature-disabled discriminator? (ARCH-12) |
| FR-95 | The status→copy map. (ARCH-13's sibling) |
| FR-89 | The label-override map's wire shape and role vocabulary. (ARCH-27) |
| FR-140 | The outbound upload payload. (ARCH-11) |
| §5.6 | Does `POST /api/ai/chat` stream? |
| OQ-36, OQ-39, OQ-40 | Dispersion-flag carve-out; the real inference ceiling; is 404 pinned in the Contract Pin? |
| FR-155 / FR-215 | The closed list of defaulted fields. (ARCH-36) |

### Architecture must write, then have ratified

Driver lifecycle contract (ARCH-6) · slot resolution and overlap reconciliation (ARCH-7, ARCH-8) · phone↔Watch Coverage Claim payload schema (ARCH-9) · local schema and migration policy (ARCH-10, ARCH-71) · app-lifecycle → request-state taxonomy (ARCH-31) · unified error taxonomy (ARCH-35) · background workload arbitration and the truncation point of NFR-8's fixed order (ARCH-34, ARCH-76, ARCH-80) · FR-8's connection state-machine transition table (ARCH-22) · FR-34's event taxonomy (ARCH-59) · the Driver UI element vocabulary (UX-2) · the build-failure taxonomy and notification channel (ARCH-15's §5.10 sibling) · the signing and provisioning model (ARCH-14) · the fork secret set (ARCH-13) · the authoritative `UIBackgroundModes` set (ARCH-70) · a system-wide injectable clock abstraction (ARCH-73) · typed or structured logging that makes SI-9 mechanical (ARCH-5, ARCH-74) · a persisted diagnostic buffer decision (ARCH-75) · the Watch cold-start wake-and-seed contract (ARCH-72) · the SI-1 denylist (ARCH-4) · FR-217's "glucose context" classifier (ARCH-44) · NFR-30's registry pin and exception policy (ARCH-68, PLAN-10, PLAN-35, UX-31) · the NFR → validation-tier → owner map NFR-34 requires (PLAN-34) · a Simulator-provable proxy for NFR-5 (ARCH-77).

### Document integrity (cheap, do in one pass)

R-14…R-19 and R-23 dangling, with R-16 and R-23 cited from live text (PLAN-31) · §15's OQ range self-check is false (PLAN-32) · §7.4's stale PD-42 note (PLAN-33) · §6's stale PL-72 note (PLAN-41) · FR-177's count references (PLAN-9) · FR-234's `externalLinks` check (PLAN-25) · NFR-7's 50,000-row ceiling vs the retention window (ARCH-78) · NFR-11's "floor of at most one per 15 minutes" (ARCH-81) · NFR-19's protection-class either/or (ARCH-79) · NFR-4's "render functions" (ARCH-84) · export compliance added to FR-204 and FR-223 (ARCH-40) · "enable Actions in your fork" added to FR-223 (ARCH-41) · FR-47's Light-theme text variants (ARCH-45) · undefined domain nouns added to §3: "precedence outcome", "grounded", "trust tier", "computation role", "dispersion band", "empirical dispersion" (§0 makes this a defect by the document's own rule).

**A general fix worth more than any single item:** give every `[NOTE FOR PM]` residual a state marker (`OPEN` / `CLOSED — verified against <FR> on <date>`) and re-verify the closed ones in a single pass. Two of them are currently wrong in opposite directions, and one caused a reviewer on this pass to report a closed defect as an open High-severity safety bug.

---

## 7. Recommended first moves

1. **Do not delay P0.** P0.1 through P0.6 are correctly identified, correctly ordered, and none of the blocking findings above touches them. Start there today.
2. **Run a short contract sprint in parallel with P0**, producing the missing contracts in §6's architecture list. They are the difference between P1/P2 being schedulable and being guesswork. Two of them are hours of work, not days: the NFR → tier → owner map (PLAN-34) and the authoritative background-mode set (ARCH-70), and each currently blocks a whole section's acceptance.
3. **Assign the seven blocking OQs an owner and a date this week.** Two of them (OQ-45, OQ-50) gate work that is already in the P0/P3 window.
4. **Re-decompose §12.3 P1 and P2 with an explicit FR allocation** and split the ~18 FRs identified in PLAN-7 before any estimation.
5. **Write the missing journeys before UX starts on onboarding, settings, AI Chat and advertise-and-wait pairing.** Four new journeys, not one.
6. **Give the pixel-geometry question an explicit ruling** — "these values are Android-derived defaults; design may re-judge them against the iOS HIG except where an FR states a safety reason" would unblock the whole design surface in one sentence.
7. **Pull FR-207's hardware-validation checklist forward to the critical path.** It is the only redundancy that exists against the single-validator risk, it is a document rather than code, and §9.4 already identifies it as the mitigation. Writing it late is the same as not having it. Pair it with a ratified "ship with zero Verified devices" default (PLAN-39).
8. **Do the stale-note and dangling-ID pass in one sitting.** It is under a day's work and it restores the property that makes this document unusually reviewable.
9. **Fund a second hardware validator.** §12.3's own note says it: "the highest-leverage spend available and it is independent of the Medtronic outcome." Every blocking and high finding about Tier 4 scheduling dissolves with it.
