---
title: Adversarial Safety Review — PRD GlycemicGPT for iOS and Apple Watch
scope: prd.md §4 Safety Invariant Register vs. FR-1..FR-237, NFR-1..NFR-34, Parity Ledger §7, matrices §8–§10
date: 2026-08-03
posture: adversarial — this document hunts for requirements that can be implemented exactly as written while a Safety Invariant is violated
---

# Adversarial Safety Review

## 0. How to read this

This is an attack document. It does not summarise the PRD and it does not praise it. Every finding below is a **concrete scenario** with inputs and state, the **requirement it stems from**, the **invariant it breaks**, and a **severity**. Findings without a concrete scenario were cut.

§8 records what I tried to break and could not. That section is not filler — several of the strongest-looking attack surfaces in this product are genuinely closed, and knowing which ones are closed is what makes the open ones worth spending money on.

**Verdict.** The PRD's freshness, decay and honesty architecture is unusually strong — stronger than most shipped diabetes software. But the Coverage Claim selector (FR-83) has a structural hole at its very first branch that disarms the product's own irreducible safety net on evidence that proves nothing, and the Safety Limits mechanism that SI-11 exists to police is a silent, unbounded monitoring kill switch in the direction SI-11 explicitly permits. Three findings are release-blocking as written.

**Counts:** 3 critical, 10 high, 22 medium, 4 low. **39 findings.**

---

## 1. Critical

### F-1 — `Backend Active` disarms the Alert Floor on evidence that the Backend can alert, without evidence it has anything to alert *from*

**SI broken:** SI-6 (primary), SI-5 (secondary). **Severity: critical.**

**Stems from:** FR-83 selector step (1); FR-71 gate (4); FR-71's definition of degraded; FR-140; FR-153.

**The mechanism.** FR-83 resolves the claim by "One pure selector … evaluated strictly in this order: (1) Backend alerting is not degraded → **Backend Active**". FR-71 defines that condition as "`network is not reachable OR the Backend alert stream is not connected`" and stands the Alert Floor down on it: gate "(4) Backend alerting is not degraded → return". FR-83 further specifies "**Backend Active** shows no banner."

So a connected SSE socket is sufficient to (a) claim the strongest coverage state, (b) suppress every honesty banner, and (c) disarm the on-device Alert Floor. Nothing in FR-83, FR-71 or FR-157 requires any evidence that the Backend possesses glucose data, has ever evaluated a reading, or is capable of producing a glucose alert for this account.

**Why the Backend usually has no data.** FR-140 states flatly: "**Glucose Readings are never enqueued.**" The app never uploads glucose. The Backend's glucose therefore arrives only from a Nightscout connection — and FR-153 says "The source is **OFF by default**."

**Concrete scenario.** Marcus (UJ-3) builds his own copy, stands up a Backend because he wants AI Chat and analysis, and never configures Nightscout — the default. He pairs his t:slim X2. State: Backend URL set, session valid, network reachable, SSE stream connected, Pump connected, thresholds synced from the Backend, notifications authorised, readings arriving every 5 minutes over Bluetooth.

- FR-83 step (1) fires → claim = **Backend Active**.
- FR-83 → **no banner** on the phone; FR-126 renders the wrist's quiet "all clear" presentation.
- FR-71 gate (4) → the Alert Floor **returns without evaluating**, permanently, for as long as the stream stays up.
- 02:40. Glucose crosses 48 mg/dL. The Backend has never received a single glucose value for this account and issues nothing. The Alert Floor is standing down.

**No alarm fires on any surface, and every surface says coverage is fine.** SI-6's own stated failure consequence — "A silent app that looks like a watching app is the most dangerous failure mode in this product" — is realised exactly.

**Why this is not caught by the decay machinery.** FR-84 gives Backend Active `validUntil = now + 360,000 ms`, refreshed on every 30-second recomputation (FR-83). Decay only rescues the case where the app stops running. Here the app is running perfectly and the claim is continuously renewed.

**Why the disclosed limitations don't cover it.** PL-17 and FR-157 disclose that Backend alerts don't reach a *suspended* app. This scenario is the opposite: the app is alive, and *that* is what disarms the floor.

**Second, narrower face of the same hole.** FR-157 sets a 75-second stream read timeout, which bounds a silently-dead-but-connected stream. But within that ≤75 s window, and across any TCP half-open / NAT-rebind transition, the same three effects hold. FR-71's "deliberately pessimistic on disagreement" clause covers only *network-reachable vs. stream-connected* disagreement; it does not cover a stream that is connected and dead.

**Third face.** A Backend whose alert evaluator has crashed, whose user has alerting disabled in the web app, or which is a fresh instance with no patient record, is indistinguishable from a healthy one at the socket layer.

**What the requirement would have to say.** Backend Active must additionally require positive, recent evidence of Backend alert evaluation for this account — a heartbeat that carries an evaluation timestamp, or an explicit "I have glucose data as of T" assertion. Absent that, the Alert Floor must stay armed and the claim must not be Backend Active. Note that FR-83's five Not-Watching Reasons are a closed set with no member for "the Backend cannot see your glucose", so this needs a sixth reason or a change to the Backend Active precondition.

---

### F-2 — Backend-supplied Safety Limits are an unbounded, silent, remote monitoring kill switch, in the direction SI-11 explicitly permits

**SI broken:** SI-6 (primary); SI-11's purpose (the letter of SI-11 is satisfied). **Severity: critical.**

**Stems from:** FR-32; FR-155's Safety Limits validation rules; FR-42; FR-83's closed reason set; 5.3 Feature NFR ("A dropped row is never surfaced as an error row").

**The mechanism.** SI-11 defends one direction only: "Backend-supplied Safety Limits may only **narrow**, never widen, the Glucose Validity Bound … A compromised or misconfigured Backend could otherwise disable the safety bound." FR-32 implements the Driver gate against "the **current**, Backend-narrowable Safety Limits at every validation pass" and notes "narrowing the limits mid-stream changes which readings are accepted **without restarting the Driver**."

FR-155 validates a Safety Limits payload only for internal consistency: "Safety Limits reject min ≥ max, min outside 20–499, max outside 21–500, basal outside 1–15000 milliunits/hr, or bolus outside 1–25000 milliunits." **There is no minimum-width requirement anywhere.**

**Concrete scenario.** A Backend — compromised, misconfigured, mid-migration, or simply running a bad default — returns Safety Limits `min = 100, max = 101`. Every field passes FR-155. The window is narrower than 20–500, so FR-32's "the resulting window no wider than the absolute Glucose Validity Bound" passes. The record is accepted atomically and applied to the live Driver gate on the next validation pass, no restart.

From that instant:

- Every Glucose Reading outside 100–101 mg/dL is dropped at the Driver. That is essentially all of them, including every low and every urgent low.
- Dropped readings never enter the store, never reach the hero, never reach the chart, never reach the Alert Floor.
- 5.3's feature NFR: "rows outside the Glucose Validity Bound are dropped at the model boundary … **A dropped row is never surfaced as an error row.**"
- The Coverage Claim reaches FR-83 step (6) and resolves to `NO_FRESH_READING`. FR-127 renders on the wrist: "Monitoring degraded - no fresh glucose readings."

**The user is told their CGM has stopped.** The truth is that their own Backend instructed the app to discard every reading it receives, and the app is faithfully complying. The reason set is closed at five (FR-83: "The five Not-Watching Reasons are exactly …") and contains no member for this. There is no user-actionable path: the pump is connected, the sensor is fine, the app says "no fresh readings".

**FR-32 has a partial mitigation that does not reach this case.** FR-32 requires: "Every rejection is logged with the field and bound that failed, and is surfaced to the user as a configuration fault naming the offending value, so the app never appears to have lost the Pump with no explanation." That sentence is scoped to a **rejected Safety Limits payload**. Here the payload is *accepted* — it is perfectly valid — and it is the *readings* that are rejected. Nothing surfaces a reading-rejection rate, the currently-in-force Safety Limits window, or the fact that a narrowing is in effect.

**It persists through the obvious recovery attempt.** FR-42: "A failed Safety Limits fetch falls back to last-known-good; it never widens the Glucose Validity Bound (SI-11)." So taking the Backend offline does not restore monitoring. Only sign-out or Backend-URL removal clears them (FR-143) — and the user has no reason to try either, because the app is telling them the sensor is dead.

**An under-specification that makes it potentially unrecoverable.** SI-11 and FR-138 say limits "may only NARROW … and may never widen". The PRD never states whether the ratchet is evaluated against the **absolute 20–500 constant** or against the **currently in force** window. If the latter — a defensible reading of "may only narrow" and of FR-138's "clamp-on-write, clamp-on-read ordering" — a corrected Backend sending `20–500` is a *widening* and is **rejected**, leaving the user permanently trapped. This ambiguity sits on the single most safety-load-bearing sentence in SI-11 and must be resolved explicitly in the FR text.

**Minimum fix.** A floor on `max − min` (a window narrower than, say, the urgent-low-to-urgent-high span is not a safety limit, it is a denial of service); an in-app surface showing the in-force Safety Limits window and its provenance; a sixth Not-Watching Reason for "readings are being rejected by Safety Limits"; and an explicit statement that the narrowing ratchet is evaluated against the absolute constant, not against the current value.

---

### F-3 — The backward-clock high-water mark can disarm the Alert Floor permanently, and reports the wrong reason while it does

**SI broken:** SI-5 (arming), SI-6 (reason specificity). **Severity: critical.**

**Stems from:** FR-72's high-water-mark bullet; FR-83's closed five-reason set.

**The mechanism.** FR-72: "A **monotonic** high-water mark of every observed wall-clock time is kept and advanced by every Alert Floor evaluation, every data-trust-bound check and every Coverage Claim recomputation. While `now + 60,000 ms < highWaterMark`, the Alert Floor **suppresses evaluation** and the Coverage Claim treats the reading age as absent, resolving to `NO_FRESH_READING`."

The mark is monotonic and advanced by the Coverage Claim recomputation — which FR-83 runs **every 30 seconds** whenever the app is alive. There is **no stated upper bound on the mark, no reset path, no expiry, and no statement of whether it persists across process death.**

**Concrete scenario A — the transient forward jump that never ends.** A phone briefly acquires a bad time. Real causes: a carrier NITZ update with a wrong year (documented in the wild), an RTC that comes up at a garbage epoch after a deep battery drain, a user manually setting the date forward to test a calendar or to bypass a trial, or a TestFlight build's 90-day expiry prompting a user to set the clock forward (FR-186 / UJ-3 makes this a *predictable* user behaviour in this product specifically). The app runs once during that window; a Coverage Claim recomputation advances `highWaterMark` to, say, 2030-01-01.

The clock corrects. From then on, `now + 60,000 ms < highWaterMark` is true — and stays true for years.

- The Alert Floor **suppresses evaluation entirely** (FR-71 gate 1: "suppress evaluation entirely, including episode recovery"). It never fires again, at any glucose value, ever.
- The Coverage Claim reports `NO_FRESH_READING` — "Monitoring degraded - no fresh glucose readings" — while readings are arriving perfectly and rendering Fresh on the hero (FR-49 classifies display independently).
- There is no `CLOCK_UNTRUSTED` reason. The reason set is closed at five.
- There is no requirement anywhere to reset, bound, or expose the high-water mark.

The user sees fresh green numbers on their dashboard and a banner claiming there are no fresh readings. They have no way to diagnose it and no control that fixes it. Reinstalling may not fix it either — FR-136's fresh-install purge covers "database key, auth tokens and pump pairing secrets", not this.

**Concrete scenario B — the ordinary timezone-adjacent rewind.** A user flies west and their phone corrects backward by 3 hours before NTP settles, or a DST-adjacent bug moves the clock back 60 minutes. For the entire rewind duration the Alert Floor is suppressed and the reason given is `NO_FRESH_READING`. SI-6 requires "a **specific**, user-actionable cause". "No fresh glucose readings" is factually false and directs the user to check their sensor, which is fine.

**The spec gap cuts both ways and the PRD does not say which side it is on.** FR-72's only statement about persistence is about the opposite residual: "a rewind occurring while the process is dead leaves no mark — is documented and fails toward alarming, never toward silence." That sentence implies the mark is **not** persisted, which caps scenario A at one process lifetime — but it is an inference about a residual, not a requirement, and FR-74 explicitly persists the *cooldown* state to shared storage, so an implementer has every reason to persist the mark alongside it. **The PRD must state explicitly whether the high-water mark persists, and must bound it.** As written, the two readings have opposite critical failure modes: persisted → permanent silent disarm; not persisted → the rewind detector is defeated by any process restart.

---

## 2. High

### F-4 — FR-125 clamps Alert Thresholds on the Watch. The phone rejects; the wrist coerces. They then band the same reading differently.

**SI broken:** SI-4 (its stated failure consequence is literally "Phone and wrist disagree about the same reading"); SI-2's reject-never-clamp principle. **Severity: high.**

**Stems from:** FR-125 vs. FR-169, FR-81, FR-155, FR-47, FR-124.

**The contradiction, stated plainly.** FR-125 is titled "Alert Threshold **sanitization** on the wrist" and claims to uphold SI-2. Its first consequence is five clamps:

> "Sanitization runs in this dependent order, each clamp depending on the previous: low clamped to 40-200; high clamped to max(low+1, 100)-400; urgent low clamped to 20-low; urgent high clamped to high-500."

Every other threshold surface in the product rejects. FR-169: "out-of-range and out-of-order values **rejected rather than clamped** … never clamped (SI-2)." FR-81: "**never clamps** an out-of-range or misordered value into range … the entire response is dropped." FR-32: "**There is no clamping path anywhere on this surface.** A clamp would silently transform a malformed or hostile … payload into a plausible-looking one — precisely the failure SI-2 exists to prevent."

FR-125 is that clamping path, on the surface UJ-1 says the user trusts at a glance.

**Concrete scenario.** A user in Backend-optional mode uses FR-169 to set thresholds appropriate to their own care plan: urgent low 60, low **210**, high 260, urgent high 320. FR-169 accepts this — all four are inside 20–500 and satisfy `urgent low ≤ low < high ≤ urgent high`.

The app pushes them to the Watch. FR-125 clamps:
- `low` → clamped to 40–200 → **200** (was 210)
- `high` → clamped to max(201,100)–400 → 260 (unchanged)
- `urgent low` → clamped to 20–low(200) → 60 (unchanged)
- `urgent high` → clamped to high(260)–500 → 320 (unchanged)

Reading arrives: **205 mg/dL**, fresh.

- **Phone** (FR-47): `value ≤ low(210)` → **low band, amber**, hero coloured amber, "205" in the low colour.
- **Wrist** (FR-124, clamped low = 200): `205 > 200`, `205 < high(260)` → **in-range band, green**.

Sam turns their wrist mid-meeting (UJ-1), sees a green in-range 205, and puts their arm down. The phone in their pocket is showing the same reading in amber. This is precisely SI-4's stated harm.

**A second, sharper case.** Set `low = 35` (legal per FR-169: 35 ≥ 20). Watch clamps `low` to 40. A reading of 38: phone → in-range green (38 > 35); wrist → warning amber (38 ≤ 40). The two surfaces disagree in the *opposite* direction, so a user cannot even learn a consistent rule about which surface to trust.

**FR-125's own justification does not cover its own clamps.** FR-125 says "Sanitization can only narrow within the Glucose Validity Bound; no sanitized threshold can fall below 20 or above 500." That is a true statement about the *Glucose Validity Bound* and an irrelevant one about *thresholds* — clamping `low` from 210 to 200 changes which readings band as low, and has nothing to do with 20–500.

**The mitigation is real but partial.** FR-125's clamped values feed display banding only: "these fallbacks never cause a wrist alert, and no wrist alert is ever scheduled from a threshold the user or their Backend did not set", and FR-128 makes the app the classifier for wrist alerts. So SI-5 holds. **SI-4 does not.**

**Fix.** The wrist must reject a threshold set it cannot represent and render the un-banded value plus an explicit "thresholds unavailable" treatment, exactly as the phone drops a bad Backend response whole. A hostile-payload defence is a legitimate goal; clamping is the wrong instrument for it in a product whose SI register forbids clamping by name.

---

### F-5 — The Glossary's threshold ordering rule and FR-81/FR-155's are contradictory, and the losing configuration produces a permanent, unactionable, silent disarm

**SI broken:** SI-6 (specific, user-actionable reason); SI-5's arming path is starved. **Severity: high.**

**Stems from:** §3 Glossary vs. FR-81, FR-155, FR-169, FR-73, FR-83.

**The contradiction.** §3 Glossary, which the PRD declares binding ("Vocabulary is binding … Introducing a synonym anywhere in this document is a defect"):

> "**Alert Threshold** — … Ordering is enforced: `20 ≤ urgent low ≤ low < high ≤ urgent high ≤ 500`."

FR-169 (on-device editor) matches it: "Ordering must satisfy urgent low **≤** low < high **≤** urgent high".

FR-81 (Backend response) does not: "ordering is checked on the **raw** decimal values with **all-strict comparisons** (`urgent low < low < high < urgent high`)". FR-155 repeats it: "Alert Thresholds require **strict ordering** on the raw floats".

So `urgent low == low` is a **legal** configuration by the Glossary and by the on-device editor, and an **invalid** one when it arrives from a Backend.

**Concrete scenario.** A user who wants exactly one low alarm sets urgent low = 70 and low = 70 in their Backend's web app — a natural configuration, legal per the product's own Glossary, and one the app itself would accept if they were in Backend-optional mode.

- The app fetches thresholds (FR-80). FR-81 ordering validation fails on the raw values.
- FR-81: "On either failure the **entire response is dropped** and logged … If nothing was ever synced, the store stays in the disarmed `none` state." FR-81's title is "Invalid Backend threshold responses are discarded **whole**" and its statement is "**silently** discards".
- FR-73: provenance stays `none` → "**With provenance `none`, no alarm fires at any glucose value.**"
- FR-83 step (3) → `THRESHOLDS_NOT_SYNCED`. FR-127 on the wrist: "Monitoring degraded - alert thresholds haven't synced yet."

The user looks at their web app and sees four thresholds set. The phone says they haven't synced. **They never will.** Every hour, forever, FR-80's refresh-if-stale fires, fetches, and drops the response. The Alert Floor never arms. The failure is silent by requirement, the log is scrubbed of the values by SI-9, and the reason shown ("haven't synced yet") implies a transient condition that will resolve on its own.

**Aggravating factor.** The user is *worse off* than a user with no Backend, who would get `THRESHOLDS_NOT_CONFIGURED` and be offered the on-device editor (FR-79, FR-82). Here FR-80 states "With a Backend configured, **no editable field and no save control exists in the app**", so the one remedy is unreachable.

**Fix.** Reconcile the ordering rule to a single definition (the Glossary's, since it is declared binding), and make FR-81's discard non-silent when it leaves provenance at `none` — a persistent rejection of the Backend's thresholds is a coverage fact, not a log line.

---

### F-6 — An `emergency`-severity alert from a newer Backend is delivered non-interrupting because its *type string* is unknown, while the claim says Backend Active

**SI broken:** SI-6. **Severity: high.**

**Stems from:** FR-65; FR-66; FR-69; FR-83; FR-71 gate (4).

**The mechanism.** FR-65 routes delivery tier by **type-set membership**, not by severity:

> "Low-set and high-set alerts are delivered at the interrupting tier (FR-66); `iob_warning`, `no_data` and **every unrecognized type** are delivered at the informational tier (`.active`, default sound, **no Focus break-through**)."

`severity` is a separately decoded, separately consumed field with recognised values `warning` / `urgent` / `emergency`, and FR-69 renders the title from it: "Title prefix by severity: `emergency` → 'EMERGENCY'".

So the app can know an alert is an emergency and still refuse to break through Focus, because it does not recognise the type string.

**Concrete scenario.** The Backend ships a release adding `low_predicted_urgent` (a natural addition given FR-71 notes the Backend "evaluates trajectory, prediction horizons and IOB"). A Builder's iOS fork is on the previous CONTRACT_VERSION — the normal steady state under fork-and-build, where every Builder rebuilds on their own schedule (PL-54, PL-55).

02:50, Sleep Focus on, phone charging across the room (UJ-2's exact setup). The Backend evaluates a predicted urgent low and pushes `{alert_type: "low_predicted_urgent", severity: "emergency", current_value: 61, …}`.

- FR-65: type is unrecognised → decodes successfully (correct, SI-12) → delivered at the **informational tier**, `.active`, default sound, **no Focus break-through**.
- FR-69: the notification title reads "**EMERGENCY: 61 mg/dL**" — on a notification the OS has been told not to interrupt.
- FR-83: the stream is connected → claim = **Backend Active** → **no banner**.
- FR-71 gate (4): the Alert Floor is standing down.

Priya sleeps through it. Every surface says she is covered.

**Why SI-12 does not excuse it.** SI-12 governs *field* tolerance: "Unknown **fields** in a Backend response are tolerated; a missing consumed field fails loudly." FR-65 extends tolerant-reading to a *value* that selects an escalation tier, which is a different decision. Tolerant decoding is correct; tolerant **routing to the quiet tier** is not.

**Fix.** When the type is unrecognised, route by `severity`: `emergency` and `urgent` go to the interrupting tier. `severity` is already a consumed, validated field. The current rule fails toward silence on exactly the class of alert the product exists to deliver.

---

### F-7 — `Not Watching → validUntil = now` plus "schedule the lapse notification at validUntil" fires a `.timeSensitive` alarm on every routine idle-disconnect

**SI broken:** SI-6 (via the alarm-fatigue path that destroys the one surface designed to be believed); the alternative implementation reading breaks SI-6 directly. **Severity: high.**

**Stems from:** FR-84; FR-85; FR-83 step (4); FR-86.

**The collision.** FR-84: "For **Not Watching** it is **now** — an expired claim by construction." FR-85: "On **every wake** … the app cancels and re-schedules a single local notification for the current claim's `validUntil`. If the app runs again before then, that notification never fires; if the app dies, it fires. **Silence becomes the alarm.**" FR-85 also specifies the lapse notification is delivered at `.timeSensitive`.

FR-83 step (4) resolves **Not Watching / `PUMP_DISCONNECTED`** whenever the Pump is not connected — an instantaneous link-state test, per FR-43's six-state model.

FR-86 then tells us that a disconnect is the *normal operating cycle*: "The Pump's **idle disconnect is itself a background wake**, so a connect → poll → idle-disconnect → reconnect cycle is the **de-facto background evaluation cadence**."

**Concrete scenario.** Normal overnight operation, everything healthy. t:slim X2 idle-disconnects roughly every 30 seconds (the PRD cites a "~30 s idle drop" in 5.3's notes).

1. Idle disconnect → Core Bluetooth background wake.
2. FR-85: on this wake, cancel and re-schedule the lapse notification at the current claim's `validUntil`.
3. FR-83 step (4): Pump not connected → Not Watching / `PUMP_DISCONNECTED`.
4. FR-84: `validUntil = now`.
5. A local notification scheduled for a trigger date of *now* fires immediately.

The user receives a `.timeSensitive` "GlycemicGPT has stopped watching" notification **on every poll cycle, all night**. Within one night they disable notifications for the app — which FR-83 will then correctly report as `NOTIFICATIONS_DENIED`, having destroyed the coverage it was reporting on.

**The implementer's only escape is the silent failure.** The obvious defensive fix — suppress the lapse notification when `validUntil` is in the past or within some epsilon — is nowhere specified, and it disables the mechanism in exactly the cases FR-85 exists for: an app that is genuinely dying while Not Watching. The PRD specifies **no minimum lead time, no debounce, no hysteresis on the claim, and no distinction between a transient link gap and a lost pump.**

**Related, same root cause.** With the claim recomputing every 30 s (FR-83) and no hysteresis, the in-app banner, the widget, the Live Activity and the complication all oscillate between "watching" and "**NOT** watching for lows or highs" against the pump's duty cycle. UJ-1's contract — a plain complication means fresh *and* watching — becomes a strobe.

**Fix.** `PUMP_DISCONNECTED` must be qualified by a debounce that exceeds the driver's idle-disconnect period (the Fresh boundary is the natural candidate — a link gap shorter than the Fresh window costs no coverage). The lapse notification needs an explicit minimum lead time and an explicit rule for a `validUntil` in the past.

---

### F-8 — A reading the app rejects is presented identically to a reading that never arrived, so a decode defect is indistinguishable from a dead sensor — indefinitely

**SI broken:** SI-6 (specific reason); SI-2's "rejection is … logged with the violated bound" has no user-facing counterpart. **Severity: high.**

**Stems from:** 5.3 Feature NFR; FR-120; FR-32's device-validity gate; FR-83's closed reason set; SI-9.

**The mechanism.** Rejections are, by requirement, invisible:

- 5.3 feature NFR: "rows outside the Glucose Validity Bound are dropped at the model boundary and the dashboard falls back to the next valid reading or the no-data state (SI-2). **A dropped row is never surfaced as an error row.**"
- FR-120 (wrist): "A Glucose Reading outside 20-500 mg/dL renders `--` **regardless of age**, is REJECTED not clamped, is logged **without the value**" — and `--` is the identical rendering FR-120 gives Too Stale, whose accessibility label is "**No recent data**".
- FR-32's device-validity gate discards `egvStatusId` 0 and ≥ 4 silently.
- SI-9 forbids the value in the log, so even a Builder reading a diagnostic export (FR-158) sees only counts.

**Concrete scenario.** A Medtronic Driver ships at **Beta** (FR-22, §8.3) with a byte-order defect in its EGV parser — entirely plausible for a driver the project has never run against hardware, and PD-41 notes "**A Medtronic equivalent of the validity gate must be identified before that Driver leaves Beta**", i.e. it currently has none. Every decoded reading lands at 15,872 mg/dL.

- Storage gate (FR-138) rejects every row. Driver gate (FR-32) rejects every row. Neither surfaces anything.
- Hero: "--". Wrist: `--`, accessibility "No recent data". Complication: no value.
- Coverage Claim: pump connected, thresholds set, notifications on → step (6) → `NO_FRESH_READING` → "Monitoring degraded - no fresh glucose readings."

The app is receiving a reading every five minutes, rejecting all of them, and telling the user there are no readings. The user replaces their sensor. Then their transmitter. The app never says "we are receiving data from your pump and discarding it."

**The same shape, three other ways in.** (a) F-2's Safety Limits narrowing. (b) `egvStatusId` stuck at 4 (UNAVAILABLE) from a firmware revision the project has not seen — FR-32 discards "**4 and above and any future value**", correctly, and silently. (c) A Nightscout feed whose units are misconfigured to mmol/L upstream, so every value arrives as 5.6 and is rejected as < 20 (FR-153).

**Why it matters more here than in most products.** PL-2 already records "**Stale-cache silent notification loss** — a connected Pump delivering no data — is detected after the fact rather than pre-empted", and FR-11's wall fires only after three zero-response connections. That covers *no* data. It does not cover *rejected* data, which looks identical to the user and to the Coverage Claim.

**Fix.** A rejection counter that reaches a user-visible surface, and a distinct Not-Watching Reason (`READINGS_REJECTED`) naming the gate that is dropping them. SI-9 permits reporting the *bound* and the *count* without the value.

---

### F-9 — The Watch's ±30 s duplicate rule is keyed on timestamp alone and will drop a *differing* value, leaving the wrist showing a number the phone has superseded

**SI broken:** SI-4, SI-6. **Severity: high.**

**Stems from:** FR-122.

**The rule.** FR-122: "A newly arrived Glucose Reading whose **timestamp is within 30,000 ms of any cached entry** is dropped as a duplicate."

No value comparison. Two genuinely distinct readings 25 seconds apart are indistinguishable from a retransmission of one.

**Concrete scenario.** The user pulls to refresh on Home (FR-40) 20 seconds after a background poll landed. FR-40 explicitly routes the manual result through the same path ("The glucose result is routed through the same path the background poller uses, so a low fetched by a manual refresh during an outage reaches the Alert Floor immediately"). The pump returns a newer EGV with a sensor timestamp 22 seconds after the cached one.

- Phone: new reading accepted, hero updates from **118** to **57**, hero turns urgent-low red, Alert Floor fires.
- Watch: the new reading's timestamp is within 30,000 ms of the cached entry → **dropped as a duplicate**. FR-122's cache is what FR-120 renders and what FR-116 says the widget extension reads directly.
- The wrist complication continues to render **118**, Fresh, in-range green, with a normal relative-age label that keeps counting from the *old* timestamp.

The alert notification will reach the wrist by FR-128, but Sam's glance surface — the one UJ-1 says costs nothing and is trusted — is showing a stale, in-range number beside an urgent-low alert.

A second route to the same state: a Nightscout backfill (FR-153/FR-154) delivering a corrected value at a near-identical timestamp, absorbed by FR-137's write-time dedup on the phone but hitting FR-122's much looser ±30 s window on the wrist.

**Note the asymmetry.** FR-137 (phone) dedups on **exact timestamp equality** ("At most one Glucose Reading per timestamp"). FR-122 (wrist) dedups on a **30-second window**. Two different dedup semantics for the same record type across two surfaces — the drift SI-4 exists to prevent.

**Fix.** Make the wrist dedup match the phone's (exact timestamp), or at minimum require value equality in addition to timestamp proximity.

---

### F-10 — The Watch derives coverage validity in two places: it invents a window when one is absent, and it decays an absolute phone-clock instant against its own clock with no bounded skew

**SI broken:** SI-6 ("The Watch **never derives** its own claim"). **Severity: high.**

**Stems from:** FR-126; FR-84; FR-123.

**(a) Inventing a window.** FR-126: "The Watch clamps the advertised validity window to 10,000 ms - 1,800,000 ms … **The default when the window is absent is 360,000 ms.**"

FR-126 fails closed on an unrecognised *state* ("An unrecognised coverage state string fails closed to 'has not reported recently'") but fails **open** on an absent *window*. That asymmetry is the wrong way round: the state is the less dangerous field.

**Concrete scenario.** FR-129 explicitly contemplates version skew — "Re-alarm defaults to on when the app's payload omits the flag, so an **older app build** still re-alarms" — and FR-115 has a build-mismatch banner, so mismatched app/Watch builds are an anticipated state. An app build regresses and omits the window field (or a Watch build reads a renamed key as absent). The Watch receives `state = watching`, no window, and grants it **360,000 ms of coverage it invented**. Repeated on each state write, the wrist claims coverage indefinitely off a field the phone never sent. SI-6's mechanism — "carries an **explicit** expiry" — has been replaced by an implicit one computed on the wrist.

**(b) Decaying an absolute instant against an unsynchronised clock.** FR-84 emits `validUntil` as a timestamp and says "the Watch app **decays the phone's claim against its own clock** after the advertised window." FR-123's clock guard detects the Watch clock **running backward** by >60,000 ms; it does not detect a Watch clock that is steadily **offset**. A Watch whose clock sits 4 minutes behind the phone's never "runs backward" and never trips the guard — it simply reads every absolute instant 4 minutes late.

Result: the wrist renders "something is currently watching" for ~4 minutes after the claim actually expired, on every claim, indefinitely. FR-116's pinned pair — "Coverage Claim age `timeout-1` Watching / `timeout` not-watching-recently" — passes in the test suite because the test uses one clock.

**Fix.** Transmit a **duration** plus the phone's send instant, and decay it on the Watch's monotonic clock from receipt. Fail closed when the window is absent. FR-126's clamp then becomes a defence against a hostile duration rather than the only thing standing between a dead phone and a 30-minute false coverage claim.

### F-28 — Backend-optional mode, declared a first-class path, is unreachable during onboarding for the exact user the PRD says will be trapped

**SI broken:** SI-6 (the product cannot watch at all); the Glossary's own definition. **Severity: high.**

**Stems from:** FR-159; FR-161; FR-164; FR-162; FR-63.

**The trap, from FR-159's own consequences.**

> "Exactly 5 stages exist, indexed Welcome=0, Features=1, Safety Acknowledgement=2, **Backend=3**, Sign-in=4."
> "'Skip' appears on **stages 0 and 1 only** and animates to stage 2; **it never lands on 3 or 4**."
> "'Back' appears on stages 3 and 4 only."
> "**The Backend stage's 'Next' is disabled until a connection test has succeeded in this session.**"

The escape hatch is one stage further on: FR-164 puts it on **stage 4** — "The **Sign-in stage** carries the label 'Don't run a server?' and a control reading 'Use without a server'" — and FR-165 confirms there are exactly "**both onboarding completion paths**", both of which live on stage 4.

Stage 3 has no Skip, and its only forward affordance is a Next gated on a successful connection test. **A user who cannot make a Backend connection test succeed can never reach stage 4, can never complete onboarding, and therefore can never reach the app.** FR-63: "The start destination depends only on onboarding completion."

This contradicts the Glossary — "**Backend-optional mode** … A **first-class supported mode, not a degraded state**" — FR-161's own stage label "Connect a Server (**Optional**)", and 5.9's Description: "Finishing without a Backend is a first-class path, not a fallback."

**Concrete scenario, and it is the one the PRD itself predicts.** Marcus (UJ-3) builds his copy and points it at his self-hosted Backend on `192.168.1.40`. iOS raises the Local Network prompt; he taps Deny — or the prompt is dismissed by a notification, or he denied it during a previous app install. FR-162 records the consequence: the denial is "**permanent until they visit Settings**, and **the Simulator neither presents nor enforces the prompt**", so no Builder will have caught it in testing.

Every connection test now fails. Marcus is stuck on stage 3 of a 5-stage flow. His pump is paired-capable, the Alert Floor is fully functional, the entire local monitor works — and he cannot reach it. He has a glucose monitor that will not open. The correct product answer ("run it without a server") is rendered, in words, on the screen he cannot get to.

**Fix.** Put "Use without a server" on stage 3, or allow Skip to land on 4. One control, and it is currently on the wrong screen.

---

### F-29 — FR-169 states that the built-in default thresholds exist *for the Watch alert relay*, which is a direct SI-5 carve-out and contradicts FR-125 and FR-130

**SI broken:** SI-5. **Severity: high.**

**Stems from:** FR-169 vs. FR-125, FR-130, FR-73.

SI-5 is unconditional: the Alert Floor arms "only against thresholds the user or their Backend actually set — **never defaults**."

FR-169's final consequence:

> "The stored defaults 55 / 70 / 180 / 250 exist **only for the Watch alert relay** and are NEVER a source the Alert Floor fires from; until a real source exists the thresholds are reported as unconfigured (SI-5)."

Read literally, this says the defaults are *not* an Alert Floor source **but are** a Watch-alert-relay source — i.e. the wrist may raise an alarm from thresholds nobody set. That is the same invariant violation, relocated to the surface the user is most likely to be woken by.

The other two FRs say the opposite. FR-125: "the wrist falls back to low 70, high 180, urgent low 55, urgent high 250 **for display banding only**; **these fallbacks never cause a wrist alert**, and **no wrist alert is ever scheduled from a threshold the user or their Backend did not set**." FR-130: "When a Glucose Reading is not alertable — … **Alert Thresholds not configured** … — the wrist relay takes **no action at all**."

**Why this matters more than an ordinary wording slip.** FR-169 is the FR an implementer building the threshold store will read; FR-125 lives in 5.7 and FR-130 further still. The sentence names a specific consumer for the defaults and tells the implementer that consumer is allowed to use them. If it is implemented as written, a user with provenance `none` — including every user in F-5's permanent-disarm state and every user who has not yet completed threshold setup — gets wrist alarms at 55/70/180/250 while the phone correctly reports `THRESHOLDS_NOT_CONFIGURED` and stays silent. A wrist alarm the user never configured is indistinguishable from a real one, and it arrives on the surface whose whole purpose is to be believed.

**Fix.** Change "only for the Watch alert relay" to "only for the Watch's **display banding** (FR-125)". The defaults' single legitimate consumer is FR-124's banding function, not any alerting path.

---

### F-30 — `pump_events[].units` is an optional consumed field whose silent disappearance deletes every Nightscout insulin row and understates IOB, with no parse error and no test

**SI broken:** SI-7 (primary), SI-12. **Severity: high.**

**Stems from:** FR-214; FR-215; FR-153; SI-12's asymmetry.

The PRD states the whole failure itself, in FR-214:

> "The nullable-consumed-field rule is a **standing, enforced obligation**: any newly consumed optional field whose absence would silently degrade a safety surface must be added to the field-presence list in the same pull request rather than left to round-trip tests. **`pump_events[].units` is the canonical case — it is optional, the persistence mapper drops any event with a nil value, and a silent Backend rename would delete every Nightscout Bolus and Basal row and understate IOB with no parse error.**"

And FR-215 *requires* that it decode cleanly when absent: "**Older-Backend tolerance: any field the app treats as optional or defaulted decodes successfully when omitted.**"

**Concrete scenario.** The Backend renames `units` to `amount_units` in a minor release — the kind of change SI-12 exists to make loud. The app is on the previous Contract Pin.

- FR-215's tolerance rule: the field is optional → decodes successfully with `units = nil`. **No error.**
- FR-153's mapper drops every row with a nil value. **Every Nightscout-sourced Bolus and Basal row silently vanishes.**
- 5.5 FR-89's Insulin Summary, the basal/bolus split, the total daily dose, the Recent Boluses card and the chart's bolus markers all lose those deliveries.
- SI-7's stated harm inverted: insulin the patient actually received is not reported at all, so a user or the AI reasoning from the record concludes they have less insulin on board than they do — and stacks.

**Why SI-12 does not catch it.** SI-12's contract is "a **missing consumed field** fails loudly." `units` *is* consumed. It is classified as optional, so it is routed to the tolerant branch — and FR-214 admits the gate's blind spot explicitly: "it does not catch **removal of an optional or defaulted consumed field**."

**The only guard is a human remembering.** "A standing, enforced obligation" that a developer must discharge in the same pull request is not a mechanism. FR-214 has a field-presence list — a mechanism that would catch this — and `pump_events[].units` is the one field the FR names as the canonical hazard while leaving it off.

**Fix.** Put `pump_events[].units` on the field-presence list now. Any field whose nil value causes a **row drop** is a consumed field for SI-12's purposes regardless of its schema nullability; state that rule so the classification is derivable rather than remembered.

---

### F-36 — The scheduled rebuild that keeps the monitor alive is silently disabled by GitHub before it expires, and a disabled workflow emits nothing because it never fails

**SI broken:** SI-6. **Severity: high.**

**Stems from:** FR-186; FR-187; FR-171; PL-54; PL-55; UJ-3's edge case.

FR-186 names the hazard precisely and then does not close it:

> "GitHub **disables scheduled workflows in a repository with 60 days of inactivity — 30 days before the build expires**. Any repository activity … re-arms it."
> "A **failed** scheduled rebuild notifies the Builder rather than failing silently."

A workflow GitHub has **disabled** never runs, therefore never fails, therefore never notifies. FR-186 requires **no detection of the disabled state itself** — only documentation, plus FR-187's countdown as backstop.

**Concrete scenario, which is the modal Builder.** Marcus (UJ-3) forks, builds, installs, and — being a user rather than a developer — never touches the repository again. Day 60: GitHub disables his scheduled rebuild workflow. Nothing is emitted; his fork looks identical. Day 90: his TestFlight build expires.

PL-54 states the outcome: "An expired build **does not launch, therefore does not monitor and does not alert** — a **silent loss of monitoring** for a glucose monitor." FR-187 is unambiguous that this is total: "**No surface anywhere states or implies that monitoring, the Alert Floor, or the Coverage Claim continues past expiry.**"

**The backstop has a hole of its own.** FR-187's escalation is "a local notification at 7, 3 and 1" days. An expiry notice is not a glucose alert and is not time-sensitive, so it is subject to every suppression FR-171 enumerates — and FR-171 lists "Scheduled Summary enabled" as a condition that can "delay a non-time-sensitive notification by hours". A user who denied notification authorization — a state FR-165 explicitly contemplates and FR-83 reports as `NOTIFICATIONS_DENIED` — gets **no expiry warning at all**, and FR-187 states no fallback. The two silent-failure mechanisms compose: no rebuild, no warning, no launch.

PL-55 records the risk in one line — "A quiet fork can lose its automatic rebuild while the Builder believes it is armed" — and assigns it no mechanism.

**Fix.** FR-186 must require the app (or the workflow's own last-successful-run timestamp, read at archive time and surfaced by FR-187's Settings row) to detect *staleness of the rebuild mechanism*, not just of the build. A rebuild that has not run in 35 days is the signal; it is available 25 days before anything breaks. Additionally, the ≤7-day expiry state should be surfaced in-app as a persistent, non-dismissible banner rather than relying on a notification the user may have disabled.

---

## 3. Medium

### F-11 — FR-81's rounding rule silently annihilates an entire alert band and calls it "safe"

**SI:** SI-5 (the warning tier becomes unreachable), SI-6. **Severity: medium.**

FR-81: "Rounded ties at the urgent boundaries (69.8 / 70.2 → 70 / 70) are **legal and safe** because classification checks urgent bands first (FR-71)."

With urgent low = 70 and low = 70, FR-71's classifier (`value ≤ urgent low → low_urgent`) makes **`low_warning` unreachable at every glucose value**. The same collapse at the high end (179.6/179.7 → 180/180) makes `high_warning` unreachable. FR-47's severity banding collapses in step: the amber low band and the amber high band vanish from the dashboard.

**Scenario.** A Backend whose UI stores thresholds as floats and whose user set 69.8 and 70.2. The app rounds both to 70. From then on the user gets an *urgent* alarm at 70 and never a warning alarm at all — the graduated early-warning tier the product advertises has silently ceased to exist. The values render as "70 / 70" in FR-168's read-only line, which reads as a display bug rather than a behavioural change.

It is *safe* in the sense that it errs toward the more severe alert. It is not *honest*, and nothing tells the user their warning band is gone.

### F-12 — FR-70's slot replacement and FR-77's identity-specific acknowledgement are in conflict; a Backend re-delivery can hijack an Alert Floor alarm's notification while leaving its ladder and its acknowledgement state behind

**SI:** SI-5, SI-6. **Severity: medium.**

FR-70 keys the notification slot on `"<alertType>|<patientName or empty>"` and states "A Backend re-delivery therefore **replaces** an on-device Alert Floor notification of the same type rather than duplicating it." FR-77 keys acknowledgement on the **alert identifier** — "routes the action back … carrying **that specific alert's** identifier — never a most-recent-alert assumption" — and branches on the `local-floor:` prefix.

An Alert Floor notification and a Backend notification of the same type therefore **share a slot but not an identity**.

**Scenario.** 03:05, Backend-degraded. The Alert Floor fires `low_urgent`, identifier `local-floor:low_urgent:1754...`, notification slot `low_urgent|`, and FR-76 schedules a 5-repeat ladder. 03:06 the network returns and the stream reconnects, replaying a Backend `low_urgent` from 02:55 (FR-157: "Pending Backend alerts are pulled at every execution opportunity"). Same slot → the delivered notification is **replaced** by the Backend's copy carrying the Backend's identifier.

Priya taps "Got It". FR-77 runs against the Backend identifier: marks that alert acknowledged, cancels **that** alert's ladder, sends the ack to the Backend. The `local-floor:` branch (step 5) is never taken, so **FR-74's Alert Floor acknowledgement is never applied**.

Which ladder was cancelled is unspecified — FR-77 says "cancel the re-alarm ladder" without saying whether ladder requests are keyed by slot or by identifier. Both readings fail:
- Keyed by identifier → the Alert Floor's ladder survives and re-sounds at 2-minute intervals for the remaining 8 minutes after the user has acknowledged.
- Keyed by slot → the Alert Floor is silenced but FR-74's acknowledged-type state is never set, so the type is not re-armed on recovery and its cooldown behaves as unacknowledged.

FR-77 asserts "A test pins the ordering and asserts that an unreachable or hung Backend can never leave the alarm sounding, the ladder pending, or the notification on screen." That test cannot catch this, because the Backend here is reachable and the ladder that survives belongs to a *different* identifier.

**Fix.** State that ladder cancellation and duplicate suppression are keyed on the **notification slot**, and that acknowledging any alert occupying the Alert Floor's slot applies FR-74's acknowledgement to that type.

### F-13 — The total-daily-dose denominator is clamped to a minimum of one day, understating a dosing-relevant figure without qualification

**SI:** SI-7's family (insulin reported wrongly). **Severity: medium.**

5.5 FR-89: "The days denominator is `dataSpanHours / 24` **clamped into `[1, periodHours/24]`**, measured from now rather than from the newest event."

**Scenario.** A user pairs their pump at 18:00 and opens the Insulin Summary at 00:00, selecting the 7D period. Real data span: 6 hours, 11 U delivered. Denominator: `6/24 = 0.25`, clamped up to **1**. The card reports **"Total daily dose: 11 U"**. The user's actual daily requirement is ~44 U. The figure is understated fourfold with no caveat, no partial-period indicator, and no empty state.

The same figure is available to AI Chat for analysis and to the user for pattern reasoning. Compare FR-58, which refuses to render an internally inconsistent Time in Range aggregate at all ("rejected via a failable initializer, logged, and rendered as the empty state"). TDD gets a clamp where TIR gets a rejection.

**Fix.** Require a minimum data span before rendering TDD, or label the figure explicitly as covering a partial period.

### F-14 — A user's own correction bolus can be silently reclassified as automated, and can overwrite the pump's own record while doing so

**SI:** SI-7 (attribution of delivered insulin). **Severity: medium.**

FR-153: "A `correction` row is **marked automated regardless of the upload's own flag**; user doses arrive as `bolus`." FR-137: "**Bolus writes keep the LAST writer**" on a `(units, timestamp)` collision.

**Scenario.** A user delivers a 3.0 U correction from the pump at 14:02:11.000. The Tandem Driver records it, correctly flagged not-automated. Their Nightscout uploader (a different device, e.g. their looping partner's setup or an xDrip bridge) also records it as event type `correction`. It reaches the Backend and the app pulls it (FR-153) at the same `(3.0, 14:02:11.000)` key.

- FR-153 marks the incoming row **automated**.
- FR-137's last-writer-wins **overwrites** the pump-sourced row.
- 5.5 FR-89's portion ladder: "automated → **the whole delivery is correction**", category → **Auto Corr**.

The user's manual correction is now attributed to Control-IQ. Total daily dose is unaffected (SI-7's headline number holds), but the basal/bolus split, the food/correction portions, the category breakdown and any AI analysis of "how much am I correcting manually" are all wrong, permanently, with the row marked `nightscout-source` as the only forensic trace.

FR-137's stated aim is that collisions resolve "**deterministically**"; last-writer-wins across two asynchronous sources is not deterministic in any operational sense.

### F-15 — On a phone clock rewind, the hero renders a confident, severity-coloured, "just now" value while the banner directly beneath it says the app is NOT watching

**SI:** SI-6. **Severity: medium.**

FR-49 is explicit and deliberate: "A negative age … classifies as **Fresh FOR DISPLAY ONLY**, at every magnitude … its relative-age label reads '**just now**'. There is no second negative-age classification bound anywhere in this document and **no display tier that fails closed on a backward clock**."

FR-72 then suppresses alerting and resolves the claim to `NO_FRESH_READING` for the whole rewind window.

**Scenario.** The phone's clock corrects backward by 25 minutes at 03:00. A reading captured 20 minutes earlier at 118 mg/dL now has an age of −5 minutes.

- Hero (FR-46/FR-47/FR-49): **118**, in-range **green**, caption "**just now**", no staleness badge (FR-51: "Fresh renders **nothing at all**").
- Banner (FR-83): "Monitoring degraded — this phone is **NOT** watching for lows or highs: no fresh glucose readings."
- Widget / Lock Screen / complication (FR-119, FR-120): the same green, "just now" 118, because FR-120 renders the Fresh treatment.

The two most-read elements on the screen contradict each other, and the more prominent one (a 64pt green numeral) is the wrong one. On the wrist the contradiction is worse because FR-123's clock guard applies only to the **Watch's own** clock, not to a phone-clock rewind reflected in a forwarded reading — so the wrist shows `120 ->` Fresh with a normal age label.

The PRD chose this deliberately and states the reasoning. It is defensible as a *classification* rule (it prevents a clock bug from hiding data). It is not defensible as a *presentation* rule: a negative age is prima facie evidence that the age is not computable, and the honest presentation is the "unknown time" label FR-123 already invented for the Watch. Extending FR-123's label rule to any negative age beyond the 60,000 ms tolerance, on both targets, costs nothing and closes it.

### F-16 — FR-73's provenance migration heuristic can arm the Alert Floor from a timestamp rather than from evidence, in a product that has no installs to migrate

**SI:** SI-5. **Severity: medium.**

FR-73: "For installs that **predate an explicit provenance record**, absent provenance resolves to **backend** when a last-sync timestamp is non-zero and to `none` otherwise, so an upgrading user is never silently disarmed."

This is a new iOS application. There are no installs that predate an explicit provenance record. The clause is dead code that nonetheless creates the one arming path in the product that does not require evidence of user or Backend intent — it infers provenance from the existence of a timestamp. Any code path that writes a last-sync timestamp before or without writing provenance (a partial write, a crash between two stores, a future migration, a restored backup) arms the Alert Floor at whatever values happen to be in the store, which FR-73 itself says are "the built-in values 55 / 70 / 180 / 250 … chosen by no user".

SI-5 is unambiguous: "only against thresholds the user or their Backend **actually set** — never defaults." Delete the clause.

### F-17 — Thermal throttling degrades wrist refresh with no disclosure surface, unlike its Low Power Mode sibling

**SI:** SI-6. **Severity: medium.**

NFR-12 handles two degradation sources asymmetrically. Low Power Mode: "reports this in the Settings reliability card and, when it changes what is watching, in the **Coverage Claim's Not-Watching Reason** (SI-6)." Thermal: "Elevated thermal state may reduce background opportunities; the app reduces non-essential work (analysis recomputation, chart pre-rendering, **wrist refresh above the material-change floor**) before it reduces anything on the Alert Floor path" — and names **no disclosure surface at all**.

**Scenario.** iPhone in a car mount in direct sun, or charging on CarPlay in summer. Thermal state elevates. Wrist refresh drops to the material-change floor ("at most one per **15 minutes**", NFR-11/FR-122). The Coverage Claim still resolves to Floor Watching or Backend Active. The complication shows a value up to 15 minutes older than the phone's, with an age label that (correctly) counts up — but no user-facing statement that wrist delivery has been throttled.

NFR-17's blanket rule ("No surface anywhere renders a value in a way that implies it is current when its Freshness Tier says otherwise") saves the *value*, since the age keeps counting. It does not save the *coverage* claim, which is what SI-6 governs.

### F-18 — Two Drivers ship selectable at a Verification Status the tier model says they cannot hold, and one of them has no sensor-validity gate at all

**SI:** SI-2, SI-8. **Severity: medium.**

§9.3's tier-to-status mapping requires, for **Protocol-Implemented**: "Tier 1 + Tier 2 (**a recorded frame corpus for that device family must exist**)". §9.1 states: "a device family with **no recorded frames** has no Tier 2 coverage at all: **today that is Tandem Mobi and every Medtronic model**." §8.3 nonetheless lists **Tandem Mobi as Protocol-Implemented**, "Shipped and selectable."

Since §8.1 defines Protocol-Implemented evidence as precisely "Glucose Validity Bound rejection, cursor non-advance on decode failure" — i.e. SI-2 and SI-8 at the wire level, which only Tier 2 can demonstrate — Mobi ships selectable with SI-2 and SI-8 **unverified for its wire format**. Compounding it, §8.3 records that the Mobi/t:slim battery opcode ordering "has been observed **only on Android**".

Separately, PD-41: "**A Medtronic equivalent of the validity gate must be identified before that Driver leaves Beta**." Medtronic ships today (present, compile-gated) with no `egvStatusId` analogue, and PD-41 states the consequence in the PRD's own words: "a warm-up or error sentinel landing inside 20–500 would render at hero scale, in a severity colour, Fresh, and be **alertable** (SI-2)."

**Fix.** Either demote Mobi to Beta until a frame corpus exists, or amend §9.3. As written §8.3 and §9.3 contradict each other on a row that gates two invariants.

### F-19 — The Medical Safety Review carve-out allowlists hard-coded mmol/L equivalents of the Glucose Validity Bound, outside the conversion path

**SI:** SI-3, SI-4. **Severity: medium.**

§10.3 lists among the Medical Safety Review's "explicit non-violations": "**user-facing mmol/L display literals (3.9, 10.0, 22.2; ~1.1 and ~27.8 as the display equivalents of the bounds)**."

1.1 and 27.8 are the mmol/L renderings of 20 and 500 — i.e. the Glucose Validity Bound, typed as literals, outside the single 18.0156 conversion path that SI-3 and SI-4 exist to enforce. FR-169 already depends on them ("the derived mmol/L bounds label (1.1 / 27.7)" — note the PRD itself renders the upper bound as **27.7** in FR-169 and **27.8** in FR-60's anchor table and in §10.3, which is exactly the drift this guard is supposed to catch).

Nothing requires these to be *derived* from the constant rather than typed. Combined with §10.3's statement that Medical Safety Review "remains advisory" and that "CodeRabbit **skips pull requests authored by dependency, release and CI bots entirely**", the only merge-blocking enforcement of SI-3/SI-4 is the SwiftLint literal rule in `Static Analysis Gate` — which this carve-out explicitly exempts these values from.

Also: §10.1's rule list is stated as "no bare `20` / `500` / `18.0156` outside the canonical definitions" and **omits the Tandem epoch offset `1199145600`**, which SI-4 names as one of the three Safety Constants and which §10.3 and NFR-4 both include. Two enumerations of the same guard disagree.

### F-20 — An uncomputable Time in Range is rendered as the false statement "No glucose readings for this period"

**SI:** SI-6 (honesty of an on-screen assertion). **Severity: medium.**

FR-58: "An internally inconsistent aggregate (percentages outside 0–100, or a sum more than 0.5 away from 100 when not all-zero) is **rejected via a failable initializer, logged, and rendered as the empty state** — it never traps the process (SI-2)."

Rejecting is right. Rendering the empty state is not: FR-58's empty state is the literal string "**No glucose readings for this period**", which is false — there are readings, the aggregate failed. A user reasoning about a gap in their data ("did my sensor drop out on Tuesday?") is given a wrong answer by the app. The product's whole thesis is that a confident wrong statement is worse than none.

TIR is not an alarm surface, which caps the severity. But the same pattern recurs (F-8), and here the fix is a one-line copy change to a distinct "couldn't compute" state.

### F-21 — Outbound-queue eviction permanently loses insulin records that the history cursor has already advanced past

**SI:** SI-8's purpose ("Silently lost insulin records"). **Severity: medium.**

SI-8 protects the cursor: "History cursors never advance past a record that was not successfully **decoded**." FR-146 and FR-36 implement it correctly. But a record that decodes fine, is stored, and is enqueued can still be lost downstream:

FR-142: "When the queue exceeds its bound, the **OLDEST undelivered rows are dropped** … The bound is 20,000 rows." FR-139: retention then prunes local rows past the cutoff (1–30 days, default 7), retaining only "the single highest-sequence row … as the history resume anchor."

**Scenario.** A user travels for 10 days with a data-roaming-off phone and a 7-day retention setting. The queue saturates at 20,000 rows and evicts oldest-first. On return, the Backend receives the tail of the backlog. The evicted bolus and basal records are gone from the Backend permanently — the raw-history cursor advanced past them long ago (correctly, they decoded), so no re-pull will recover them, and retention has since removed them locally.

FR-142 does state "Data loss at the cap is the intended policy and is stated to the user in the sync surface, not discovered", which is the right posture. What is **not** stated is that the loss is **irrecoverable** — that reconnecting will not backfill, because the cursor cannot be rewound. A user watching a pending count fall reasonably reads it as delivery, not as eviction. The disclosure needs to say which.

### F-22 — FR-53 clamps the basal rate scale and pins out-of-scale segments — the exact display defect FR-52 was written to close for glucose

**SI:** none directly; the product's own anti-pinning principle. **Severity: medium.**

FR-52 is emphatic: "No reading is ever **pinned** to an axis boundary … **Pinning would place a valid, in-bound reading at a false height** — the Android display defect this rule closes — and is a defect here."

FR-53, ten lines later: "The basal stepped area … with the **rate scale maximum clamped to [0.1, 15.0] U/hr**."

A Medtronic 780G supports basal rates above 15 U/hr, and FR-132's own wrist bound is "basal rate outside **0-15 U/hr**" — rejected there, clamped here. On the phone chart a 22 U/hr temp-basal segment either draws off the plot or is pinned to the 15 U/hr ceiling, rendering a valid insulin value at a false height on a chart the user reads for insulin patterns. The rule FR-52 established for glucose (default, expand, never pin) is not applied to the insulin series on the same chart.

### F-31 — A pull request touching only the Xcode project generator manifest skips every Required Check and passes green, including the gate that mechanically enforces SI-1

**SI:** SI-1's enforcement, and by extension every gate hosted in `iOS Gate`. **Severity: medium.**

FR-198 makes a skip indistinguishable from a pass: "push or pull request with `should_*` not `'true'` → print the skip reason and **exit 0**" and "A `skipped` work job on a push or pull request where nothing relevant changed **resolves to a pass**."

That is only safe if the paths filter is complete. It is not. FR-208's `ios` filter and 5.10 FR-179's deployable-change regex enumerate different sets, and FR-208's omits at least three entries FR-179 includes: **`project.yml`**, **`fastlane/`** and **`Gemfile.lock`**.

`project.yml` is not an incidental file. FR-212 designates it in CODEOWNERS as "`*.xcodeproj/project.pbxproj` **or its generator manifest**" — i.e. it is treated as an arbitrary-code-execution vector, because it defines build phases and run scripts. A pull request that modifies only `project.yml` therefore:

- skips `Build & Test`, which hosts **FR-205's Driver protocol snapshot gate — the mechanical enforcement of SI-1** — and FR-206's protocol tests (SI-2, SI-7, SI-8) and FR-207's Simulated-Driver end-to-end path;
- resolves `iOS Gate` to **pass**;
- merges to `develop` with a green Required Check having executed none of the safety gates.

5.11 says as much about the adjacent gap: FR-193 notes fastlane "is pinned here because the build-and-sign lane is the only lane that runs fastlane, and **nothing in 5.11 covers it**."

**Fix.** Reconcile FR-208's `ios` filter with FR-179's regex, and state the rule that any path in CODEOWNERS' safety-review set is automatically in the `ios` filter. FR-197's own closure principle ("Every mechanical gate this PRD names … is a step or a test inside one of the five") is defeated if a path can route around all five.

### F-32 — SI-9's mechanical enforcement covers one rule; SI-9's scope is far wider

**SI:** SI-9. **Severity: medium.**

SI-9's iOS enforcement column claims "CI rejects logging of health-typed values". The actual mechanism in FR-208 is a single SwiftLint entry: "**no `privacy: .public` interpolation of Pump identifiers in logging**."

Nothing scans for a glucose value, an IOB value, a bolus amount, a threshold value or raw packet bytes in a log statement. NFR-24's prohibited list is comprehensive and correct as *policy*; FR-208 implements one item of it. FR-200's analyzer is claimed to uphold SI-9 but blocks only at "`security-severity >= 7.0` or `level == \"error\"`" — a credential-in-a-log finding at `warning` is "counted and printed **non-blocking**."

This does not make SI-9 false; the design (FR-158's four scrubbing rules applied "before emission **and** again before export", release builds at warning-and-above only) is sound, and the os_log interpolation trap is caught by name. It makes the **SI register's enforcement claim broader than the mechanism**. Given that SI-9's violation consequence is "PHI disclosure" in a public fork-and-build repository, the row should either name what is actually mechanical or the lint rule should be widened to the health-typed values NFR-24 already enumerates.

### F-33 — Toggling the display unit and saving without editing can move a stored Alert Threshold

**SI:** SI-3 ("converted once … rounded last"), SI-5. **Severity: medium.**

FR-169: "Four decimal-entry fields render … each **re-seeded** when its mg/dL value or the display unit changes", and on save the mmol/L path multiplies by the Conversion Factor. **No decimal precision is fixed for the re-seeded value.**

**Scenario.** Stored urgent low = 55 mg/dL. The user switches the display unit to mmol/L (FR-175). The field re-seeds to `55 ÷ 18.0156 = 3.0529…`, rendered at the product's standard one decimal (FR-60: "rounded last to **one decimal** for mmol/L") → **3.1**. The user edits nothing and taps Save. The save path multiplies: `3.1 × 18.0156 = 55.85` → rounds to **56**.

Their urgent-low threshold has moved from 55 to 56 mg/dL because they looked at it in different units. Repeat the toggle and it drifts again. This is a double conversion with a rounding step in the middle, which is exactly what SI-3's "converted **once** … rounded **last**" forbids, and it mutates a value that arms an alarm.

FR-169 already demonstrates awareness of round-trip hazards elsewhere — "The naive conversion of 500 (27.8) rounds back to 501 and would be rejected" — so the fix is in the same idiom: keep the canonical mg/dL value as the field's backing store and write it back unchanged unless the user actually edited the field.

### F-34 — A Backend-configured user who has never synced is never told that alarms are off

**SI:** SI-6. **Severity: medium.** *(Compounds F-5.)*

FR-169 (Backend-optional mode) requires an unambiguous statement: "'On-device alarms are OFF until you set all four thresholds.' in **ERROR styling**."

FR-168 (Backend configured, read-only) requires only: "When no sync has ever landed the line reads '**Waiting for the first sync from your server.**' and no values are shown."

Both states have provenance `none`, and FR-73 is explicit that in both "no alarm fires at any glucose value." One user is told in error styling that alarms are off; the other is told to wait. "Waiting for the first sync" reads as a transient, self-resolving condition. In F-5's scenario it is permanent.

The dashboard Coverage Claim does carry `THRESHOLDS_NOT_SYNCED`, so the information exists somewhere. But the Settings screen the user opened *specifically to check their thresholds* is the surface where this belongs, and it currently says the softer thing.

### F-35 — Conditions that degrade background monitoring have no required mapping to the Coverage Claim, unlike conditions that suppress a notification

**SI:** SI-6. **Severity: medium.**

FR-171 carries the mapping rule explicitly and correctly: "Every listed condition maps one-to-one onto a Not-Watching Reason the Coverage Claim can surface (SI-6); **a condition the card can report but the Coverage Claim cannot name is a defect**."

FR-166's Reliability card has **no equivalent sentence**, and 5.9 deliberately separates the two surfaces: "the Reliability card above reports the conditions that degrade background **Pump monitoring**, and FR-171's notification status card reports the conditions that suppress an alert."

So background-app-refresh denied, Low Power Mode and the force-quit state are surfaced **only on a Settings card the user must navigate to**. NFR-12 does require Low Power Mode to reach the claim "when it changes what is watching", but FR-166 imposes no general obligation, and F-17 already shows the thermal path reaching no surface at all.

SI-6 requires the claim to "resolve to *not watching* with a specific reason **rather than silence**". A condition that degrades monitoring and lives only behind two taps in Settings is closer to silence than to a claim.

### F-37 — The build-expiry countdown is computed from an anchor that does not exist when it is baked in, with no requirement to err conservative

**SI:** SI-6 applied to build life. **Severity: medium.**

FR-187: "Values are **injected at archive time** and are read-only at runtime; the app never queries App Store Connect. [ASSUMPTION: expiry is computed as the **recorded upload timestamp** plus 90 days, since no on-device API reports a TestFlight build's expiry.]"

At archive time the upload timestamp does not yet exist — the archive precedes the upload, and under FR-183/FR-184's pipeline the gap can be minutes or, on a failed-then-retried upload, days. The FR does not say which timestamp is baked in, and **states no requirement that the computed date err early**.

If the anchor is the archive time and upload is later, the app's countdown expires *before* the real build does — harmless. If the anchor is a later or wall-clock-derived value, the app's countdown runs *past* the real expiry, and the user's last warning ("1 day left") arrives after the build has already stopped launching. This is the one number in the entire build lane a patient acts on, and PL-54 makes the consequence total.

**Fix.** State the anchor explicitly and require the displayed expiry to be the **earliest** defensible date, with the escalation notifications scheduled against that.

### F-38 — Two invariants are claimed by gates whose consequences do not test them

**SI:** SI-7, SI-11. **Severity: medium.**

**SI-7.** FR-206 declares "Upholds SI-2, SI-7, SI-8", but its enumerated minimum is "frame framing, byte order … event-type ID mapping, multi-packet reassembly including the documented idle timeout, and the connection state machine." **No consequence tests bolus completion state, and none tests SmartGuard auto-basal micro-bolus exclusion** — the two behaviours SI-7 actually names. FR-214's field list and FR-215's golden fixtures contain nothing distinguishing completed from started, cancelled or in-progress. 5.5 FR-92 carries the exclusion as an `[ASSUMPTION]` about where it happens ("inside the Medtronic Driver, at the point the frame is decoded"), for a Driver with no recorded frame corpus (F-18). SI-7 is asserted in four places and mechanically verified in none.

**SI-11.** Claimed by FR-214 ("Upholds SI-11, SI-12"), FR-216 ("Upholds SI-11") and FR-168. FR-214 tests only that `min_glucose_mgdl` / `max_glucose_mgdl` are *declared in the pin*; FR-216 tests version signalling; FR-215's golden fixture "safety limits 20 / 500 / 3000 / 25000" sits **at** the bound, not outside it. **No gate anywhere exercises "a widening response is rejected atomically."** FR-32 states the rule and names a test for malformed configurations — "A test feeds each malformed configuration above and asserts the previous limits are still in force" — but the enumerated cases are *internally inconsistent* payloads (min ≥ max, bolus 0), not *widening* ones, because a widening payload like `10–600` is caught by the field range check rather than by the narrow-only rule. **The narrow-only rule itself has no named test.** Given F-2, this is the invariant most in need of one.

### F-39 — VoiceOver users get no staleness qualifier at the Stale tier that sighted users see on screen

**SI:** SI-6 (parity of the honesty signal across output channels). **Severity: medium.**

FR-51 renders a visible badge at both degraded tiers: "Stale renders the text '**Stale**' in amber; Too Stale renders the text '**Too old**' in grey."

FR-178's spoken description inserts the staleness clause "', reading is stale, last updated \<age\>' **only when the Freshness Tier is Too Stale**."

A sighted user at 8 minutes sees `112` with an amber **Stale** badge. A VoiceOver user at 8 minutes hears a bare `112` with no qualifier. Sam (UJ-1) — whose entire journey is "know, at a glance, whether the number I'm looking at is still true" — is a named dependent, and 5.7 makes the point that for this product screen-reader output "is arguably the most important" channel: "The accessibility labels carry the full state verbatim — screen-reader output is the one channel where the exact Android copy survives unchanged."

The wrist gets this right (FR-120: "accessibility label ends '(stale)'"). The phone does not.

---

## 4. Low

**F-23 — Retention setting is coerced, not rejected.** FR-139: "The setting accepts 1–30 days, defaults to 7, and **coerces** any out-of-range value into the range"; FR-176's settings surface repeats "coerced into 1-30 at both the setter and the persistence layer." A corrupted or migrated value of `0` becomes `1`, silently discarding up to 29 days of local monitoring data on the next retention pass. Everywhere else in the PRD an out-of-range persisted value is rejected. Low because the blast radius is history, not alerting.

**F-24 — CGM-active percentage is clamped to 0–100.** FR-59: "CGM-active percentage = valid readings × 100 ÷ (period hours × 12), **clamped to 0–100**, and 100 when period hours ≤ 0." A source delivering faster than 12/hr reports a capped 100%, and one delivering slower is scored against an assumed cadence the Driver never declared (OQ-19 flags this). A coverage statistic that cannot exceed 100 hides a cadence mismatch rather than surfacing it. Low; OQ-19 already names the root cause.

**F-25 — FR-137's collision resolution is called deterministic and is not.** "Batch writes of Glucose Readings and Basal readings keep the **FIRST** writer on collision." First-writer-wins is deterministic only given a fixed arrival order, which two asynchronous sources (Bluetooth Driver and Backend-mediated Nightscout pull) do not have. Which value occupies a contested timestamp is a race. Values are usually near-identical, hence low — but FR-137 should say "arrival-ordered", not "deterministic".

**F-26 — §7.4's PD-42 note contradicts FR-120's current text.** §7.4 states "FR-120's Fresh case renders 'the value with its trend glyph' … **nothing degrades the glyph independently on the wrist** and a Too Stale arrow can sit beside a Fresh value there." FR-120 as written does degrade the glyph independently, in detail, with pinned pairs (`120 ->?`, `120 ?`). The ledger note is stale relative to the FR and records an open SI-6 defect that has in fact been closed. Documentation drift, not a behavioural defect — but a reader triaging §7 will chase a ghost, and a reader trusting §7 over §5 could "fix" FR-120 backwards.

---

## 5. SI-1: the therapeutic-write attack, in full

SI-1 is the strongest claim in the product and I attacked it from six directions. **Five are closed. One is a genuine residue.**

| Attack | Result |
|---|---|
| A Capability that writes | **Closed.** FR-30: "The Capability set is exactly six and is **closed** … A Capability outside the set is a **compile error**." Calibration — "the only member that would require writing to a device" — is removed from the set, from slot resolution, from the protocol surface and from the published contract, and re-adding it is a PRD change (§11). This is the single best safety decision in the document: it lets SI-1 read without a carve-out. |
| A write member on a Driver protocol | **Closed.** FR-31: "No protocol in the Driver API declares a method that delivers insulin, changes a basal rate, writes a pump setting, or calibrates a sensor." FR-205 snapshot gate can "treat *any* newly added write-shaped member as a failure rather than having to distinguish a permitted one" — precisely because FR-30 left no permitted one. |
| A Driver reaching therapy through the app or network | **Closed.** FR-31: the `iOS Gate` fails the build "if a Driver target imports anything beyond the shared safety module, the Driver API and the Bluetooth framework", enforced by build-graph dependency (5.2 feature NFR), not convention. |
| A backend-supplied value reaching the pump | **Closed.** FR-140: "Nothing in the outbound payload is a command: the upload protocol carries **observations only**, with no bolus, basal, pump-setting or device-command field anywhere in it." Safety Limits and thresholds are inbound-only and inbound-consumed; FR-32: "Safety Limits are … accepted only from Backend sync, and **no local override exists anywhere in the app**." |
| A Driver settings write becoming a device write | **Closed.** FR-29: settings are namespaced, and "No Driver-owned settings value participates in glucose or dose validation." FR-31 classifies "Connect, disconnect, unpair and reconnect … as session and lifecycle, not therapy." |
| The wrist or a widget | **Closed.** FR-115: "No Driver, no Bluetooth central, and no Pump credential exists in the Watch app or its widget extension. **No wrist interaction can deliver insulin, change a Pump setting, or modify stored data**" — and that sentence is required verbatim in user documentation. NFR-21 restates the prohibition across every target and "behind a build setting or behind a runtime flag". |

### The residue — F-27, severity medium

**The CI enforcement is a denylist against an incomplete list, for a device family the project has never run.**

FR-31: "The `Static Analysis Gate` Required Check fails the build if any Driver target **writes to a known therapy control-point characteristic** or **exposes a symbol matching a delivery-verb denylist**."

Both halves are denylists, and every read in this product is implemented by a **write**: Tandem's EC-JPAKE pairing handshake is characteristic writes (addendum §1.1), and reading IOB requires writing opcode 109 (FR-32), reading the trend requires opcodes 56/57 (FR-46). So a Driver target necessarily performs many GATT writes, and the gate must distinguish permitted transport writes from prohibited therapy writes by **characteristic UUID** and by **symbol name**.

For Medtronic that list cannot be complete. The project holds no Medtronic hardware (§9.4, decision 10), the driver ships **Beta** on an "unproven transport" (§8.1), the SAKE state machine is a clean-room reimplementation of work the project does not own (addendum §3.2), and PD-41 records that not even the *glucose validity* gate for that family has been identified yet. A "known therapy control-point characteristic" list for a pump family nobody on the project can exercise is a list of what the reference implementation happened to expose.

A therapeutic write introduced into the Medtronic Driver — by a contributor, by a mistranscribed opcode, or by a merge — that targets a characteristic absent from the list and is named outside the delivery-verb denylist passes both halves of the gate. §10.4 confirms the surrounding assurance is thin: "declining artifact SAST on iOS leaves a *wider* gap than declining it on Android did", and PL-64: "A green Static Analysis Gate on iOS carries **measurably less assurance** than the same-shaped Android gate."

**This is not a claim that SI-1 is violated.** The architectural guarantee (FR-30's closed set) holds and is what actually makes SI-1 true; a therapeutic write would have to be smuggled in *below* the Capability layer, as a raw characteristic write inside a Driver. **The finding is that the CI mechanism SI-1 cites as its iOS enforcement is weaker than the invariant table implies**, and the invariant table should say so — SI-1's enforcement is the closed Capability set plus CODEOWNERS review, with the denylist as a third, partial layer, not the reverse.

**Fix.** Invert it where it can be inverted: require Driver targets to declare an **allowlist** of characteristic UUIDs they write to, checked against a committed manifest, so an undeclared write fails the build regardless of what it is named or where it points. That is mechanically checkable and does not depend on knowing the pump's therapy control points in advance.

### A second, unrelated weakness in SI-1's enforcement — see F-31

FR-205 is the strongest anti-write mechanism in the document, and it is correctly designed: "The gate carries **no permitted-write carve-out**. Because no member of the closed Capability set writes to a device (FR-30), *any* newly added write-shaped member is a failure … whether or not it is behind a flag."

But FR-205 is hosted in `Build & Test`, which is subject to FR-208's `ios` paths filter, and FR-198 makes a skipped job resolve to a **pass**. F-31 shows that filter is incomplete relative to FR-179's own definition of a deployable change. A change that routes around the filter routes around FR-205. The gate is right; its trigger condition is not.

### One boundary worth keeping explicit rather than closing

FR-234 publishes the only affirmative device-command carve-out in the PRD: "Permitted non-therapeutic device-management operations are enumerated as exactly two: **Bluetooth pair and unpair, and connect, reconnect and disconnect** — session and lifecycle operations, not therapy."

SI-1's literal text bans "**any device command**". The PRD reads SI-1 as therapeutic-scoped, bounds the carve-out to two named operations, and publishes it. That is the right handling and I am not calling it a violation — but it is the sentence a future contributor will cite when arguing for a third operation, so it should stay closed by enumeration rather than by category. Relatedly, FR-225's "**A Driver needing to write to a device is a PRD change with its own safety review, not a contribution**" is softer than FR-226's posture in the same section, which pre-declines such a report as "a feature request for **a different, unendorsed kind of project**". Conform FR-225 to FR-226 — a named procedure for adding a therapeutic write is an invitation, and FR-226 already establishes the project does not want one.

---

## 6. Cross-surface divergence: consolidated

Collecting the phone/Watch/widget/complication/notification disagreements found above, because they form a pattern rather than a set of unrelated bugs:

| # | Divergence | Root cause |
|---|---|---|
| F-4 | Phone bands a reading low, wrist bands it in-range | FR-125 clamps thresholds; FR-169/FR-81 reject them |
| F-9 | Wrist shows a superseded value the phone has replaced | FR-122 dedups on ±30 s; FR-137 dedups on exact timestamp |
| F-10 | Wrist claims coverage after the phone's claim expired | Absolute instant decayed against an unbounded-skew Watch clock |
| F-15 | Hero says Fresh/green, banner says NOT watching | FR-49 display rule vs. FR-72 alerting rule, no shared presentation |
| F-17 | Wrist lags up to 15 min with no coverage statement | NFR-12 thermal path names no disclosure surface |
| F-7 | Claim strobes across all four surfaces at the pump's duty cycle | No hysteresis on FR-83 step (4) |

The PRD is architecturally right about how to prevent this — one shared safety module (NFR-4, FR-116), one selector (FR-83), one axis rule (FR-52), one provenance rule (FR-46), one codec (FR-132). Every divergence above is a place where a *second* rule was introduced for the wrist anyway: a second threshold sanitiser, a second dedup window, a second freshness-vs-coverage reconciliation. The structural fix is a rule of the form *"any decision function that exists on the wrist must be the same function the phone calls, not an equivalent one"* — FR-72 already states exactly this for the data-trust bound, with a CI test that fails if the two paths do not call the same function. Extend that test's shape to threshold sanitisation, dedup and claim decay.

---

## 7. The alerting chain, end to end

Concrete sequences in which an urgent low fails to reach the user **and** the app fails to say so. Disclosed limitations are separated from undisclosed ones, because the PRD's honesty about the former is what makes the latter worth escalating.

### Undisclosed — these are defects

| # | Sequence | Finding |
|---|---|---|
| 1 | Backend configured, no Nightscout source, stream up → Backend Active, no banner, Alert Floor disarmed, Backend has no glucose → **urgent low, no alarm, no warning** | F-1 |
| 2 | Backend narrows Safety Limits to a 1 mg/dL window → all readings dropped → **no alarm; app reports "no fresh readings"** | F-2 |
| 3 | Clock briefly jumps forward, then corrects → Alert Floor permanently suppressed → **no alarm ever again; app reports "no fresh readings"** | F-3 |
| 4 | Newer Backend sends an unrecognised type at `emergency` severity → informational tier, no Focus break-through, Backend Active, floor disarmed → **sleeps through it** | F-6 |
| 5 | Backend sets `urgent low == low` → whole response dropped silently, provenance stays `none` → **floor never arms; app reports "thresholds haven't synced yet", forever** | F-5 |
| 6 | Driver decode defect → every reading rejected → **no alarm; app reports "no fresh readings"; user replaces sensor** | F-8 |
| 7 | Quiet fork → GitHub disables the scheduled rebuild at day 60 (emits nothing, because a disabled workflow never fails) → build expires at day 90 → **app does not launch; no monitoring, no Alert Floor, no claim** — and if notifications were denied, no expiry warning either | F-36 |
| 8 | Backend renames an optional consumed field → every Nightscout Bolus/Basal row silently dropped → **IOB and insulin history understated with no parse error**, feeding a low that gets over-treated | F-30 |
| 9 | Provenance `none` implemented per FR-169's literal text → **wrist alarms at 55/70/180/250 the user never set**, while the phone correctly stays silent | F-29 |

Sequences 2, 3, 5 and 6 share one signature: **the app is correctly not-watching, and gives a reason that is true-sounding and wrong.** SI-6 demands "a **specific**, user-actionable cause". A closed five-member reason set cannot express four distinct failure modes that all collapse into `NO_FRESH_READING` or `THRESHOLDS_NOT_SYNCED`. **The single highest-leverage change in this review is to open that set and add reasons for: readings-rejected-by-a-gate, clock-untrusted, and thresholds-rejected-as-invalid.**

### Disclosed — these are honest, and should stay disclosed

The PRD does this well and I want it on the record that it does:

- Ring/silent switch can silence an urgent low and **the app cannot detect it** (FR-66, PL-23, PL-24, UJ-2's edge case, onboarding copy). Stated in the journey, the FR, the ledger and the non-user list.
- Critical Alerts is structurally unobtainable under fork-and-build, and the alternative (per-Builder entitlement requests) is rejected *for the right reason*: "the people who skip the step believe they are covered. Inconsistent silent coverage is worse than a uniform documented limit" (addendum §2.2).
- Force-quit disables all background relaunch until manual reopen; nothing runs after reboot until first unlock (FR-85, PL-13, PL-14, with in-app copy required in both onboarding and Settings).
- Backend alerts do not reach a suspended or terminated app (FR-157, PL-17, with the Coverage Claim copy required to say so).
- The 10-minute gap between the end of FR-76's ladder and the 30-minute cooldown, during which a sustained unacknowledged urgent low makes no sound. Bounded by FR-74's "The Alert Floor can never go permanently silent on an ongoing emergency", flagged as invented-not-ported (PD-15), and carried as an open tuning question (OQ-25). Correctly handled.
- The Coverage Claim's audibility caveat is carried as an explicit open product question (OQ-24) with the tension stated honestly on both sides.

---

## 8. What I tried to break and could not

This is as load-bearing as §1–§4. Several of these are the attacks I expected to succeed.

**SI-8 — history cursor discipline.** Attacked via partial batches, process death mid-batch, background-window expiry, and resume anchoring. Closed: FR-146 ("The cursor advances only past records that were successfully decoded"), NFR-8's fixed background work order ("persist the frame → **advance the cursor only if it decoded (SI-8)** → evaluate the Alert Floor → …") which puts the cursor rule *before* alerting inside a 10-second restoration window, NFR-9 ("the cursor no further advanced than the last successfully decoded record"), FR-36's Trace-Replay fixture proving non-advance, and FR-154's per-page cursor persistence with the explicit note that Android's persist-on-exit is inadequate for a 30-second window. The only residue is downstream of the cursor entirely (F-21).

**SI-12 — tolerant reader.** Attacked via Swift's synthesized `Codable`, which is exactly backwards from the required asymmetry. Closed explicitly and repeatedly: FR-155 ("Swift's synthesized decoding does not apply property defaults for absent keys and **must be overridden field by field**"), enumerating the specific defaulted fields; addendum §1.5 flags it as one of two idiomatic-Swift traps warranting "a lint rule, not only a test"; SI-12's own row names it. I could not find a consumed field whose absence would default silently.

**SI-9 — logging, as a design.** Attacked via the os_log interpolation trap, which is the non-obvious way to leak PHI on this platform. Already closed by name: FR-158's "**iOS-specific trap, stated because a naive port hits it**: the unified logging system treats interpolated numeric values as **public by default** while redacting dynamic strings, so a health value interpolated into a log line is published to the system log **even though the scrubber never saw it**", with a lint gate. Also attacked via the mmol/L scrubber regex and locale — closed by FR-158's dot-separator requirement, which exists specifically so the scrubber still matches. NFR-24's prohibited list is comprehensive (it includes the Bluetooth device identifier and the Backend URL with credentials, both easy to forget). **The design holds; the CI enforcement is narrower than the SI-9 row claims — see F-32.**

**SI-10 — credentials.** Attacked via the locked-device path, which is where after-first-unlock designs usually break. Closed: FR-136, NFR-18 (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), FR-75's requirement that the alert store be readable while locked with "A test asserts the store's file protection level is **not raised above** after-first-unlock" (raising it is the failure, correctly identified), and 5.4's feature NFR calling that a release-blocking defect "because it fails only on a locked device, which the Simulator does not faithfully reproduce". Also attacked via Keychain items surviving app deletion — closed by FR-136's fresh-install purge, keyed on "a sentinel in storage that app deletion **does** wipe".

**SI-2 — the `precondition` trap.** This is the highest-probability real-world violation in the whole port and it is closed at four layers: SI-2's own row ("**never `precondition`**, which would trap a monitoring app mid-background-wake"), NFR-14's prohibition of `precondition`/`assert`/`fatalError`/`try!`/`as!`/force-unwrap on ingest, decode, background-wake, alerting, persistence and render paths, FR-49's threshold construction rule, 5.2's feature NFR ("trapping is reserved for genuine programmer errors (double-initializing the Driver Catalog is the only one)"), and addendum §1.5. I could not find a safety-relevant construction path where a trap survives.

**The freshness and decay architecture.** I attacked this hardest and it held. I could not construct a case where a Too Stale reading renders as Fresh, except through the deliberate negative-age rule (F-15, a presentation issue, not a classification hole). FR-50's wall-clock ticker with the suspend/resume rule ("resumes with a recomputed age, **never a cached tier**"), FR-41's guarantee that a re-read "never rewrites or back-dates a Glucose Reading's sensor timestamp", FR-61's single injectable clock enforced by lint, and FR-122's pre-baked future timeline entries so decay costs zero refresh budget — this is a genuinely well-designed subsystem. The pre-baked-timeline mechanism in particular is the right answer to a hard platform constraint.

**The trend-glyph provenance rule.** I expected the arrow to be the weak point, since it arrives on a different Tandem transaction (opcodes 56/57) than the value. FR-46 owns it for the entire product, requires the worse-of-two tiers, reserves `?` for a glyph whose own source is Too Stale, and FR-120 carries it to the wrist with pinned pairs. I could not construct a surface that renders a glyph fresher than its source. (§7.4's note claiming otherwise is stale — F-26.)

**Acknowledgement durability.** Attacked via offline ack, ack during background relaunch, ack racing a Backend re-delivery, and hung-Backend-blocks-silencing. Closed: FR-77's pinned unconditional network-independent ordering with the `local-floor:` early return, FR-78's merge-not-overwrite ingestion ("Callers branch on the **merged** result, never on the raw incoming payload"), FR-131's optimistic wrist clear with re-push if the app still holds the alert ("rather than staying falsely quiet"), and FR-75's guard that fails **toward** alerting ("A broken lookup may cost one duplicate alarm; it may never cost a missed one"). The one gap is identity-vs-slot (F-12), not durability.

**FR-83's pessimistic seed.** I attacked cold-start-into-an-outage, which is where coverage claims usually lie. Closed: "The synchronous first-frame seed uses no reading age and assumes no Backend, so **a cold start into an existing outage never renders all-is-well copy**", plus "On any pipeline error the claim emits a pessimistic snapshot and retries after 5,000 ms; it **never freezes and never goes quiet**", plus FR-84's "The claim is never persisted as authoritative across a process restart" and FR-126's "The Coverage Claim is **not persisted** … because coverage after a restart is genuinely unknown." Correct on every count.

**Widget cold start.** FR-116: "Because the widget extension reads the shared on-device cache **directly**, no widget surface depends on the Watch app process having run first — the Android cold-start defect where IOB alone rendered `--` cannot recur." Attacked via App Group container corruption — closed by NFR-4 ("The container is a cache, never a second store … **nothing in the container is an input to the Alert Floor**") and the malformed-container rule ("renders the no-data state … never renders a stale value").

---

## 9. Recommended disposition

**Release-blocking (must change before the FRs are frozen):**

1. **F-1** — Backend Active must require evidence the Backend can alert on this account's glucose, or must not disarm the Alert Floor. This is the one finding that produces a silent missed urgent low with every subsystem behaving exactly as specified.
2. **F-2** — Minimum-width floor on Safety Limits; in-app visibility of the in-force window; resolve the narrow-ratchet ambiguity in SI-11's own words.
3. **F-3** — State whether the high-water mark persists; bound it; add a distinct Not-Watching Reason for an untrusted clock.

**One-line edits with outsized consequences — make these before anything else, they are nearly free:**

4. **F-29** — FR-169: change "only for the Watch **alert relay**" to "only for the Watch's **display banding** (FR-125)". As written it authorises wrist alarms from thresholds nobody set.
5. **F-28** — FR-159/FR-164: move "Use without a server" onto stage 3, or let Skip land on stage 4. One control on the wrong screen makes Backend-optional mode unreachable for the user the PRD predicts will need it.
6. **F-5** — Reconcile the threshold ordering rule to the Glossary's `≤ … < … ≤`. A one-character contradiction produces a permanent silent disarm.
7. **F-30** — Add `pump_events[].units` to FR-214's field-presence list, and state the rule that any field whose nil value drops a row is *consumed* for SI-12's purposes.

**Fix before implementation starts:**

8. **F-6** — Route unrecognised alert types by `severity`, not by type-set membership.
9. **F-4** — Replace FR-125's clamps with rejection. FR-125 currently cites SI-2 while doing the thing SI-2 forbids.
10. **F-7** — Debounce `PUMP_DISCONNECTED`; specify a minimum lead time for the lapse notification.
11. **F-36** — Detect staleness of the *rebuild mechanism*, not just of the build; make the ≤7-day expiry state an in-app banner rather than a suppressible notification.
12. **F-31 / F-38** — Reconcile FR-208's paths filter with FR-179's regex; add a named test for SI-11's narrow-only rule and for SI-7's completion and micro-bolus exclusions. Both invariants are currently claimed by gates that do not test them, and one gate can be routed around entirely.

**Structural change worth more than any individual fix:**

13. **Open the Not-Watching Reason set.** Four separate critical/high findings (F-2, F-3, F-5, F-8) are only *silent* because the reason set is closed at five and every one of them collapses into a reason that is true-sounding and wrong. FR-83's `[ASSUMPTION]` justifying the closed set — "keeping the reason set at five preserves parity with the Android wire vocabulary that the Watch app already decodes" — is the weakest load-bearing assumption in the document: there is no Android Watch app in this product, the Watch app is being written from scratch in this same PRD, and FR-127 already requires a generic fallback line for "An unrecognised or absent reason", so the wire format tolerates extension by construction. Parity with a vocabulary nobody is bound to is not a reason to make four distinct silent failures indistinguishable.

---

*Reviewer's note: this document is deliberately hostile and reports only what it could break or could not. The PRD's honesty architecture — the expiring claim, the four decay mechanisms driven by one number, the pessimistic seed, the never-persist rules, the closed Capability set — is materially better than the norm for this class of software. That is precisely why the six silent-failure paths in §7 are worth blocking on: this product's entire value proposition is that when it is not watching, it says so.*
