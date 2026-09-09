---
title: Adversarial Architecture Review — ARCHITECTURE-SPINE.md (GlycemicGPT iOS + watchOS)
scope: ARCHITECTURE-SPINE.md AD-1..AD-15, Consistency Conventions, Structural Seed, Deferred table — attacked against prd.md FR-1..FR-237, SI-1..SI-12, NFR-1..NFR-34
date: 2026-08-03
posture: adversarial — this document constructs pairs of units one level down (features/epics, two Drivers, phone vs Watch, app vs extension) that each obey every AD to the letter and still build something incompatible
---

# Adversarial Architecture Review — the Spine

## 0. How to read this

This is an attack document. The method is fixed and mechanical:

> Take two units one level below the spine — two feature epics, two Drivers, the phone and the Watch, the app and a widget extension. Give each one nothing but the spine and its own PRD section. Have each one make every decision the spine leaves open, in a way that obeys **every** AD to the letter. Then check whether the two artifacts fit together.

Every finding names **two concrete units**, walks the **compliance** of each against the ADs that bind it, states the **divergence**, states the **user-visible or safety consequence**, and closes with the **actual Binds / Prevents / Rule text** of a new or tightened AD. A finding without a concrete pair was cut. §7 records what I attacked and could not break — that section is not filler.

**Verdict.** The spine is a strong document and it is strongest exactly where the PRD is most dangerous: the Coverage Claim selector has one home and one owner (AD-10), `Glucose` cannot hold an invalid number (AD-5), no therapeutic write exists to call (AD-12), and the dependency rule (AD-3) is genuinely airtight. But the spine has **one structural hole that produces five separate critical divergences**: it defines a module graph in which *no module is shared between any two units that must agree on a data shape*. AppFeature and WidgetShared share only `SafetyCore`. AppFeature and WatchFeature share only `SafetyCore`. And AD-3 asserts the drawn graph in CI, so the edge that would fix it fails the build. Every cross-process, cross-device and cross-extension payload in this product — the widget snapshot, the phone→Watch claim, the threshold push, the history codec, the alert-ack reverse channel — is therefore, as the spine stands, defined twice by two teams who never compile against each other.

The second systemic hole is that AD-13 types errors but **assigns no owner for recovery**, and its own convention ("one typed error enum per module boundary") *guarantees* two Drivers produce disjoint, non-comparable failure taxonomies. Recovery policy — retry, latch, drop, stall — is where a monitoring app lives or dies overnight, and it is currently per-Driver folklore.

The third is that three of the six Deferred rows are not deferrable. "Per-screen state shape" is defended with the sentence *"two units cannot diverge incompatibly over it"* — that sentence is false three times over, and §5 constructs each counter-example.

**Counts: 6 critical, 10 high, 6 medium, 2 low. 24 findings.**

---

## 1. Critical

### A-1 — Two Drivers, two irreconcilable meanings of "successfully decoded", one silently loses insulin and the other wedges history forever

**Severity: critical.** **Units:** `Drivers/Tandem` (epic 5.2) and `Drivers/Medtronic` (epic 5.2). **ADs at issue:** AD-5, AD-13, AD-3, AD-12, SI-8, SI-2.

**The seam.** AD-5 makes `Glucose.init` throw outside `20...500`. SI-8 says a history cursor "never advances past a record that was not successfully decoded." Nothing anywhere in the spine says whether a frame that *parsed perfectly* but carried a value the domain rejected counts as decoded.

**Unit A — Tandem.** Reads AD-5 and AD-13 together: a throw is a typed error, a typed error on the history path is a decode failure, SI-8 says stop. Implementation: `catch { return .decodeFailure(bound: .glucoseValidity) }`, cursor not advanced. Complies with AD-5 (throws, never clamps), AD-13 (typed error, last-known-good in force, surfaces the bound that failed), AD-3, AD-4, AD-12.

**Unit B — Medtronic.** Reads the same ADs and separates layers: framing/CRC/opcode decode succeeded; value validation is a *domain* rejection, not a decode failure. Implementation: log the violated bound, drop the record, advance past it, per FR-146's "records extracted from history are subject to the same rejection rule as live data: out-of-bound values are dropped." Complies with AD-5, AD-13, AD-3, AD-4, AD-12 identically.

**The divergence.** One physical event — a pump history record carrying an out-of-bound glucose, or a reserved IEEE-11073 SFLOAT, or a `SG_SENTINEL` — produces two opposite pipeline behaviours. And the two failures are *both* bad in different directions:

- Unit B loses the record and every consumer downstream silently under-counts. This is exactly the SI-8 failure mode ("silently lost insulin records").
- Unit A stops the cursor **permanently**. Nothing in the spine or the PRD gives a stalled cursor an escape hatch, an operator surface, or a diagnostic. Live polling keeps working, the dashboard looks perfect, the Coverage Claim says Floor Watching — and history, insulin totals and every uploaded row have been frozen since a single bad frame three weeks ago.

**Amplifier.** Under a Backend-narrowed Safety Limit (FR-32, FR-155) the fraction of records failing the bound is remotely controllable. On Unit A's semantics, a Backend that narrows to a window the pump's own readings fall outside converts a config change into a total, silent, permanent history stall.

**Consequence.** Under-reported insulin on board (SI-7's stated harm: "under-treatment of a low") on one pump family; permanently frozen history with a healthy-looking UI on the other. Two Drivers, same test suite, same green CI.

**The fix — new AD-16.**

> ### AD-16 — Decode failure and value rejection are different outcomes, and only one stops a cursor
>
> - **Binds:** `DriverAPI`, `Drivers/*`, SI-2, SI-8
> - **Prevents:** two Drivers giving one physical event opposite pipeline semantics; a single bad record permanently freezing history behind a healthy-looking UI.
> - **Rule:** a Driver's history read returns, per record, exactly one of three outcomes declared in `DriverAPI`: **decoded**, **rejected** (the frame parsed; a domain bound or a device validity gate refused the value), or **undecodable** (framing, CRC, length, reassembly or opcode failed). A cursor advances past *decoded* and *rejected* records and **never** past an *undecodable* one. A `rejected` record is recorded as a rejection row carrying its sequence number and the violated bound, so the loss is countable and not silent. An undecodable record that blocks the cursor for longer than one retention window raises a stalled-history diagnostic on the sync surface; a stalled cursor is never invisible. A Driver may not collapse these three cases into two.

---

### A-2 — The app and the widget extension have no module in which the snapshot's shape can be written once, and AD-3 fails the build if you add one

**Severity: critical.** **Units:** `AppFeature` (writer, epic 5.3/5.7) and `WidgetShared` + the widget/complication extensions (reader, epic 5.7). **ADs at issue:** AD-9, AD-3, AD-2.

**The seam.** AD-9: "The app is the only writer. Extensions read a small versioned snapshot file written by the app — never the database." It says the file is *versioned*. It never says **where the type that defines it lives**, and the spine's own dependency graph makes that question unanswerable: the asserted edges are `AF --> DC | PS | BC` and `WX --> WG --> SC`. There is no `AF --> WG` edge. AD-3 says "the graph above is asserted by a CI check over the resolved package manifest" — so a team that *adds* the edge to create one definition trips the CI gate that the build-pipeline epic (5.10/5.11) wrote from the same drawing.

**Unit A — the dashboard/Live-Activity epic.** Writes the projection as a `Codable` struct in `AppFeature` with keys `["v":2,"bg":…,"ts":…,"iob":…,"unit":"mgdl","claim":{"state":…,"validUntil":…,"reason":…},"series":[…]]`, JSON, into the App Group container. Complies with AD-9 (one writer, versioned, not the DB), AD-2 (AppFeature links SafetyCore), AD-3 (no new edges), AD-13, AD-1.

**Unit B — the glanceable epic.** Writes the reader in `WidgetShared` against its own struct, with the series as `[(Date, Int)]` pairs, `unit` as an enum with cases `mgdl/mmol`, and `reason` as its own `String`. Complies with AD-2 (WidgetShared links SafetyCore), AD-3, AD-9 (read-only), AD-13.

**The divergence.** The two structs are never compiled against each other. There is no build failure, no test that can see both — the reader's fixtures are hand-written, the writer's are hand-written, and they were written from prose. Version 2 on one side and version 2 on the other are different documents. AD-2's build-failure clause covers *Safety Constants*, which per the Glossary is exactly three values — it does not cover a payload schema.

**Consequence.** Best case: every widget renders the no-data state forever, which NFR-4 requires be shown "never as an error", so the failure is *designed to be invisible*. Worst case: the shapes agree except in one field's meaning — `ts` is the sensor timestamp on one side and the write time on the other — and every Lock Screen widget renders a stale value as Fresh. That is the precise SI-6 lethal lie, on the surface the user checks most and opens the app least.

**Note.** The exact same construction applies to the phone→Watch payload (A-3) and to the Watch app→Watch-container hop. This is one root cause with three instances; §15 of the PRD already records it as open contract **C-3**, assigned to architecture, and the spine did not discharge it.

**The fix — new AD-17.**

> ### AD-17 — Every payload that crosses a process, device or extension boundary is defined once, in a module both sides link
>
> - **Binds:** `SafetyCore`, `AppFeature`, `WatchFeature`, `WidgetShared`, widget and complication extensions, SI-4, PRD contract C-3
> - **Prevents:** a writer and a reader of the same bytes compiling against two different definitions of them; a boundary shape defined in prose and implemented twice.
> - **Rule:** no type that is serialised across a process, device or extension boundary may be declared in a module only one side of that boundary links. Every such payload — the glanceable projection, the phone→Watch state write, the threshold push, the preference push, the history codec, the alert-acknowledgement message — is declared in `SafetyCore` (or a `SharedContracts` module that `SafetyCore` vends and every target links directly, per NFR-4's "as a dependency of the target itself, not through a transitive path"), together with its encoder, its decoder, and its schema version. Both the writer and the reader are compiled against that one declaration; a round-trip test living beside the declaration is the only fixture either side may use. **AD-3's asserted graph is amended to admit this module as a permitted dependency of every target.** A boundary payload declared anywhere else is a build failure.

---

### A-3 — The phone and the Watch conform to AD-10 and still disagree about the Coverage Claim, because AD-10 versions one direction of one message

**Severity: critical.** **Units:** `AppFeature`/`DomainCore` (epic 5.4, claim producer) and `WatchFeature` (epic 5.7, claim renderer). **ADs at issue:** AD-10, AD-2, AD-13, AD-14.

**The seam.** AD-10 does three things well — the selector is pure, lives in `SafetyCore`, and the Watch never derives. It does one thing incompletely: "the phone-to-Watch payload carries an explicit schema version; on mismatch the Watch degrades to *not watching* with a reason." That governs the **claim message only**, in **one direction**, and it governs the *envelope* version, not the *vocabulary* inside it.

**Unit A — the alerting epic.** Implements FR-83's eight Not-Watching Reasons: `NOTIFICATIONS_DENIED`, `THRESHOLDS_NOT_SYNCED`, `THRESHOLDS_NOT_CONFIGURED`, `PUMP_DISCONNECTED`, `NO_FRESH_READING`, `BACKEND_HAS_NO_DATA`, `SAFETY_LIMITS_TOO_NARROW`, `CLOCK_UNTRUSTED`. Sends the claim with schema version 1. Fully AD-10 compliant: one selector, phone computes, version present.

**Unit B — the Watch epic.** Implements FR-127's five wrist arms, and FR-126's "an unrecognised or absent reason renders a distinguishable generic line" and "an unrecognised coverage state string fails closed". Renders, decays, never derives. Accepts schema version 1 — the envelope *matches*. Fully AD-10 compliant.

**The divergence.** The envelope version is equal and the vocabulary is not. Three of the eight reasons — including `SAFETY_LIMITS_TOO_NARROW`, which the PRD's own safety review identifies as the remote monitoring kill switch, and `CLOCK_UNTRUSTED` — have no wrist arm and collapse to the generic "Monitoring degraded — nothing is watching for lows or highs." AD-10's mismatch escape hatch never fires, because *nothing mismatched*: the schema version guards the envelope, and the vocabulary drifted inside it.

**Second divergence in the same pair.** AD-10 says the Watch "renders **and decays**" — it does not say the decay function is shared. FR-126 gives the Watch a clamp the phone does not have (validity window clamped to 10,000–1,800,000 ms, default 360,000 ms when absent) and FR-122 pre-bakes decay as timeline entries; the phone recomputes on a 30,000 ms ticker. Two conforming implementations of "decays" that disagree at the boundary by up to one ticker period, in the direction where the wrist still says *watching* after the phone has stopped.

**Consequence.** A user whose Backend narrowed their Safety Limits to a window that discards every reading sees, on the wrist, "nothing is watching" with no cause — and the PRD is explicit that a reason "that is true-sounding and wrong … sends the user to fix the wrong thing." They replace a working sensor. The reason vocabulary is precisely the thing SI-6 exists to deliver, and it drifts with both sides green.

**The fix — tighten AD-10.**

> ### AD-10 (tightened) — The Coverage Claim has one implementation, one owner, and one vocabulary
>
> - **Binds:** SI-6, FR-83, FR-84, FR-126, FR-127
> - **Prevents:** the wrist claiming coverage the phone cannot deliver; two selectors drifting apart; **a reason vocabulary drifting inside a matching envelope; two conforming decay implementations disagreeing about the expiry instant.**
> - **Rule:** the selector lives in `SafetyCore` and is pure. The phone computes; the Watch renders and decays the phone's claim and never derives one. **The claim state set, the Not-Watching Reason set and the decay function are one declaration in `SafetyCore` (AD-17), consumed by every surface — phone banner, Live Activity, widget, complication, Watch.** A surface may choose different *copy* per reason; it may not choose a different *set*. Adding a reason without adding its rendering on every surface is a build failure, not a fallback. The phone-to-Watch payload carries an explicit schema version **and the vocabulary hash of the reason set**; on mismatch of either, the Watch degrades to *not watching* with a reason, never to a stale claim. Every surface derives decay from the single `validUntil` and from no other number; a surface may not hold a second timeout.

---

### A-4 — AD-9 guarantees one writer and nothing about the write, so a widget can read a torn snapshot and render a stale value as Fresh

**Severity: critical.** **Units:** `Persistence`/`AppFeature` (snapshot writer, epic 5.8/5.3) and the widget + complication extensions (readers, epic 5.7). **ADs at issue:** AD-9, AD-4, AD-13, SI-6.

**The seam.** AD-9's whole content is *who* may write. It says nothing about *how*: no atomic replace, no coordination, no monotonic sequence, no self-consistency requirement across fields. AD-4's actor discipline stops the app racing itself; it has no authority over a second process.

**Unit A — the writer.** Opens the container URL, encodes the projection, writes it in place with `Data.write(to:)` (or streams a large `series` array). Complies with AD-9 (sole writer), AD-4 (the write happens inside its actor), AD-13, AD-1. On iOS, `Data.write(to:options:)` without `.atomic` is a truncate-then-write.

**Unit B — the reader.** WidgetKit invokes the timeline provider on the OS's schedule, in a *separate process*, at a moment the writer cannot observe. Reads the file, decodes, renders. Complies with AD-9 (read-only, not the DB), AD-2 (links SafetyCore), NFR-4 (malformed → no-data state).

**The divergence.** A read that lands inside a non-atomic write sees one of three things. Truncated → decode fails → no-data state (survivable). Byte-mixed → decode fails (survivable). **Structurally valid but semantically mixed** — the new glucose value with the previous record's sensor timestamp, or the previous claim's `validUntil` beside the new value — decodes cleanly and renders. NFR-4's "malformed renders the no-data state" does not catch it, because it is not malformed.

**Consequence.** A widget rendering a 40-minute-old glucose value stamped with a fresh timestamp: severity-coloured, no staleness badge, a `validUntil` in the future so the pre-baked decay entry never fires. This is the single failure SI-6 names as "the most dangerous failure mode in this product", produced by two units both obeying AD-9, on the surface with the highest glance-to-open ratio in the product. It is also structurally untestable in the Simulator (§9 records WidgetKit budgets and refresh as a false-positive class).

**Second face.** Two extensions (phone widget, Live Activity) and the Watch app's own container writer are three writers of three files under one rule that says "one writer" without saying "one writer *per container*" — NFR-4 says the identifier resolves to two container instances joined by no filesystem.

**The fix — tighten AD-9.**

> ### AD-9 (tightened) — One App Group, one writer per container, one atomic record
>
> - **Binds:** `Persistence`, `AppFeature`, `WatchFeature`, widget and complication extensions, NFR-4, NFR-19, SI-6
> - **Prevents:** two processes writing one SQLCipher file; an extension holding a lock a background wake needs; **a reader observing a partially-updated projection and rendering a stale value as fresh.**
> - **Rule:** one App Group identifier, templated on the Builder's Team ID, resolving to **two containers joined by no filesystem — a phone container written only by the iOS app and read by the phone extensions, and a Watch container written only by the Watch app and read by the wrist complications. Exactly one writer per container; no requirement may assume a write on one device is visible on the other.** The app is the only writer of the SQLCipher database. Extensions read a small versioned projection — never the database. **The projection is one file containing one self-consistent record, replaced atomically (write-to-temporary plus rename, or `.atomicWrite`); a partial file is never observable. Every record carries a monotonic sequence number and every value carries its own source timestamp inside the same record, so a reader can never pair one field's value with another field's age. A reader that decodes a record whose sequence is not greater than the last one it rendered keeps what it has; it never renders backwards.**

---

### A-5 — The narrowable Safety Limits gate does not exist in the spine, so one team puts it inside `Glucose` and destroys stored history

**Severity: critical.** **Units:** `Drivers/*` + `DriverAPI` (epic 5.2) and `Persistence` (epic 5.8). **ADs at issue:** AD-5, AD-13, AD-6, SI-2, SI-11.

**The seam.** AD-5 states exactly one bound: "the initializer **throws** outside `20...500`." The PRD has **two** gates and calls the asymmetry deliberate: the Driver gate (FR-32) runs against the *current, Backend-narrowable* Safety Limits at every validation pass; the storage gate (FR-138) runs against the *absolute* 20–500, at write **and again at read**. The spine mentions `SafetyLimits` once, as a noun in the Structural Seed, and never says which gate is which.

**Unit A — the Driver epic.** Reads AD-5 and AD-13, sees `SafetyLimits` in `DriverAPI`, and does the obvious idiomatic thing: makes the validity bound a property of the value type, so that the one place a number becomes a `Glucose` is the one place the bound is enforced. `try Glucose(mgdl:, within: limits)`, defaulting to the absolute bound. Complies with AD-5 word for word — it throws, never clamps, never `precondition`s, never substitutes; storage stays canonical mg/dL. Complies with AD-13 (typed error, last-known-good, names the bound). Complies with SI-11 (narrows only).

**Unit B — the Persistence epic.** Reads AD-5 and AD-6, implements FR-138: reject at write and at read against the absolute bound, and reconstructs rows on read-back through the same initializer.

**The divergence.** The two units share the initializer. Persistence calls it with whatever the ambient limits are; the Driver team's signature makes the narrowed limits the natural argument at every call site. After a Backend narrowing to, say, 70–300, every historical row outside that window **fails to reconstruct on read-back**. FR-138 forbids exactly this: "A Safety Limits change never rewrites, deletes, hides or retroactively invalidates a stored row." Nothing in the spine forbids it — AD-5 is satisfied at every call.

**Consequence.** A remote configuration change silently erases the user's low episodes from the chart, from Time in Range and from GMI — the numbers people take to their care team — while every row is still on disk. Worse, the erasure is *selective toward lows*, because a narrowing is most likely to cut the bottom of the range. And it is remotely triggerable, which upgrades a misconfiguration into a data-integrity attack in the one direction SI-11 explicitly permits.

**The fix — tighten AD-5, add AD-18.**

> ### AD-5 (tightened) — `Glucose` is a value type that cannot hold an invalid number, against one absolute bound
>
> - **Binds:** SI-2, SI-3, every FR carrying a glucose value
> - **Prevents:** a clamped or coerced reading entering the system; a crash loop from a trapping initializer during a background wake; **a narrowable bound reaching the value type and retroactively invalidating stored rows.**
> - **Rule:** storage is canonical mg/dL. The initializer **throws** outside the **absolute** Glucose Validity Bound `20...500` — never `precondition`, never a clamp, never a silent substitution. **That bound is a compile-time constant of `SafetyCore` and takes no parameter: `Glucose.init` accepts no bound, no limits object and no policy. Backend-narrowed Safety Limits are a separate admission filter applied to newly acquired Driver readings only (AD-18); they never appear in a constructor signature and never run on a read-back path.** mmol/L exists only as a formatting output, converted once by the single Conversion Factor, rounded last.

> ### AD-18 — Safety Limits are a Driver-side admission filter with a single current value, pushed, never cached
>
> - **Binds:** `DriverAPI`, `Drivers/*`, `DomainCore`, SI-11, FR-32, FR-155
> - **Prevents:** a narrowing that never reaches a connected Driver; two Drivers holding two different "current" limits; a narrowing that reaches storage or a read-back path.
> - **Rule:** exactly one current `SafetyLimits` value exists, owned by `DomainCore`, validated atomically on ingest (whole-record drop, last-known-good stands, never a clamp). It is delivered to each Driver actor as a `Sendable` value **on every change**, and each Driver reads the value it holds **at every validation pass** — never a copy taken at connect, at activation or at pairing. A Driver declares in `DriverAPI` the sequence number of the limits it last applied, and `DomainCore` surfaces any Driver lagging the current sequence as a coverage fact. Safety Limits are applied at exactly one point: admission of a newly acquired Driver reading. They are never applied at storage write, at storage read, at Backend ingest, or on the Watch.

---

### A-6 — Alert acknowledgement has two owners, two devices, and an AD-9 rule that says "the app is the only writer" about a Watch that must write

**Severity: critical.** **Units:** `DomainCore` alerting (epic 5.4) and `WatchFeature` (epic 5.7); secondarily `BackendClient` sync (epic 5.8). **ADs at issue:** AD-9, AD-13, AD-4, AD-10.

**The seam.** FR-76 states a cross-surface invariant: "an acknowledgement on **either** surface cancels **both**" ladders — the iPhone's 5×120 s ladder and the Watch's own 30-minute, Watch-scheduled ladder. FR-74 says per-type cooldowns and acknowledged types are "persisted to storage shared by the app and the Watch app." NFR-4 says **no such shared storage exists**: two containers, no filesystem joins them, WatchConnectivity is the only path. AD-9 says "the app is the only writer" — and per the Glossary, "the app" is the iPhone application.

**Unit A — the alerting epic.** Persists ack state in the phone's store, mutates it on the notification action (FR-77's pinned six-step order), reconciles with the Backend (FR-78 merge, push-before-pull). Complies with AD-9 (the app writes, nobody else), AD-13 (typed errors, no silent default), AD-4.

**Unit B — the Watch epic.** Schedules the wrist notification and the 30-minute ladder locally (FR-128, FR-129), clears optimistically on dismissal (FR-131), persists its ladder state in the Watch container. Complies with AD-9 as it reads it — the Watch container is a different container, it is not the database, and AD-9's writer clause is about the SQLCipher file. Complies with AD-10 (renders and decays, never derives).

**The divergence.** There is no reverse channel in the spine. AD-10 defines *phone→Watch*, one message, one direction. Nothing in the spine obliges the wrist ack to reach the phone, obliges the phone ack to reach the wrist, or defines what happens when either message is lost — which on WatchConnectivity is the normal case, not the exception (a `sendMessage` to an unreachable counterpart fails; a `transferUserInfo` arrives minutes later; the Watch may be off the wrist). Both units are internally correct and FR-76's invariant is satisfied by neither.

**Consequence, two directions, both bad.** The user acknowledges an urgent low on the phone at 02:41; the wrist keeps alarming every 30 minutes until the reading ages past Too Stale — which the PRD's own reasoning calls "alarm-spam that trains users to disable notifications", and the notification they disable is the only one that alarms while the phone is in another room. Or: the user acknowledges on the wrist, the message is dropped, the phone's cooldown never advances, and FR-74's re-arm logic treats the next reading as an unacknowledged sustained condition. A third face: a Backend re-delivery whose `acknowledged` field is *absent* decodes to the documented default `false` (FR-155) and, without FR-78's merge implemented as an owner-enforced rule rather than a convention, resurrects an acknowledged alert.

**The fix — new AD-19, plus the AD-9 amendment in A-4.**

> ### AD-19 — Every mutable entity has exactly one owning module, and cross-device mutation is a versioned, idempotent, acknowledged message
>
> - **Binds:** `DomainCore`, `WatchFeature`, `BackendClient`, `Persistence`, FR-74, FR-76, FR-77, FR-78
> - **Prevents:** two features mutating one entity's state through two paths; an acknowledgement that silences one surface and not the other; a Backend re-delivery resurrecting a locally-acknowledged alert.
> - **Rule:** every persisted entity names exactly one owning module in a table kept beside this spine. `DomainCore` owns alert lifecycle and acknowledgement; `Persistence` owns row identity and durability; `BackendClient` owns transport and never writes an entity field directly — it submits a typed *intent* to the owner. Acknowledgement is merge-only and monotonic: `acknowledged` is a latch that only ever moves false→true locally, and no inbound payload, decode default or re-delivery may move it back. **A wrist acknowledgement is a cross-device intent carrying the specific alert identifier, a schema version and an idempotency key; it is retried until acknowledged by the phone, applied at most once, and a phone-side acknowledgement is mirrored to the Watch by the same mechanism. Neither surface's ladder may be cancelled by local state alone when the counterpart is reachable, and the unreachable case degrades toward silence on the wrist (the ladder terminates) rather than toward repetition.**

---

## 2. High

### A-7 — Two Drivers, two different "current" Safety Limits

**Severity: high.** **Units:** `Drivers/Tandem` and `Drivers/Medtronic`. Covered structurally by AD-18 above; recorded separately because the *timing* divergence is independent of the *placement* divergence in A-5.

Tandem takes the limits as an initializer argument to its actor at activation (AD-4 says types crossing a module boundary are `Sendable` value types — a snapshot is the idiomatic reading). Medtronic reads a `DriverAPI` accessor per validation pass. Both comply with AD-1, AD-3, AD-4, AD-12. After a narrowing sync, Tandem keeps admitting readings the user's Backend has excluded for the entire life of a connection — which, per AD-11 and FR-13, is *indefinite*. SI-11's whole point ("a compromised or misconfigured Backend could otherwise disable the safety bound") is defeated in the permissive direction on one Driver and honoured on the other. **Closed by AD-18's "reads the value it holds at every validation pass — never a copy taken at connect" plus the applied-sequence surface.**

---

### A-8 — SI-8 requires durable cursors; AD-3 forbids a Driver from having anywhere to put one

**Severity: high.** **Units:** `Drivers/*` (epic 5.2) and `Persistence`/`DomainCore` (epic 5.8). **ADs at issue:** AD-3, AD-4, SI-8.

AD-3 is emphatic and correct: "a Driver may depend **only** on `DriverAPI` and `SafetyCore`" — it "prevents a Driver acquiring its own storage or network path." SI-8's iOS enforcement column says "Same, **plus persisted cursors** — iOS termination makes process-local cursors lose data", and risk R-9 records that Medtronic's Android bolus cursor is process-local and advances before the orchestrator persists, while Tandem's is in-memory over record indices. The spine never says how a cursor gets durable when its owner may not persist.

**Unit A** returns an opaque cursor token from every history read through a `DriverAPI` port and lets `DomainCore` commit it. **Unit B** holds the cursor in its actor and re-derives it after relaunch from FR-146's "highest stored raw-history sequence number" anchor. Both comply with AD-3 and AD-4 exactly.

Unit B loses every record acquired since the last anchor write on each of the routine terminations AD-11 exists to handle, and its re-derivation depends on a row that FR-139's retention pass and FR-143's Backend-optional purge are both entitled to prune down to a single anchor. **Consequence:** silent insulin loss on one Driver only, on a schedule set by iOS's termination behaviour — invisible in CI, invisible on the bench, and only visible in a total that is quietly low.

> ### AD-20 — A cursor is a Driver-opaque token the platform commits with the records it covers
>
> - **Binds:** `DriverAPI`, `Drivers/*`, `DomainCore`, `Persistence`, SI-8
> - **Prevents:** a process-local cursor losing records across the routine terminations AD-11 exists to survive; two Drivers with two different post-crash cursor semantics.
> - **Rule:** a history cursor is an opaque `Sendable` value declared in `DriverAPI`, produced by the Driver and **never** interpreted by the platform. A Driver holds no durable cursor of its own and derives no cursor from stored rows. Every history read returns records plus the cursor that covers exactly those records, and `DomainCore` commits records and cursor **in one Persistence transaction** — a cursor is never committed ahead of the records it implies, and never behind. A cursor is per (Driver id, stream) and survives app termination, reinstall of the same build, and retention purge. Retention may never delete a row a live cursor depends on.

---

### A-9 — AD-2 mandates *linkage*, not *use*, and covers only three constants

**Severity: high.** **Units:** `AppFeature` (epic 5.3) and `WatchFeature` (epic 5.7); also `WidgetShared`. **ADs at issue:** AD-2, AD-14, SI-4.

AD-2's rule is: `SafetyCore` "is linked by **every** target that renders, validates or decays a glucose value … A second definition of a **Safety Constant** anywhere is a build failure." A "Safety Constant" is a Glossary term meaning exactly three values: the Conversion Factor, the Glucose Validity Bound, the Tandem epoch offset.

**Unit A** links SafetyCore, uses its constants, and writes its own `func tier(_ age: TimeInterval) -> Tier` in `AppFeature` with `360_000` and `900_000` inline, because the hero's ticker lives there. **Unit B** links SafetyCore and writes its own on the wrist. Both comply with AD-2 to the letter — nothing duplicated is a *Safety Constant* — and with AD-3, AD-13.

The PRD's 5.4 NFR is explicit that this must not happen: "The Freshness Tier constants, the Glucose Validity Bound, the Conversion Factor, the 30-minute cooldown, the 60,000 ms skew tolerance, the coverage expiry window, and the alert-type vocabulary must have exactly one definition each … The Android risk that the Wear module mirrors freshness numbers independently must not be reproduced." The spine dropped every item on that list except the second and third.

**Consequence.** The exact Android defect the port exists to fix: a phone that says Stale beside a wrist that says Fresh, a debug compressed policy that applies on one target and not the other, and a 6-minute boundary that is 6 minutes in two places until someone edits one.

> ### AD-2 (tightened) — `SafetyCore` is linked by every rendering target, and it is the only place a safety number or a safety decision exists
>
> - **Binds:** all
> - **Prevents:** phone, Watch and widget disagreeing about the same stored value (SI-4); **a target that links `SafetyCore` and then reimplements its decisions locally.**
> - **Rule:** `SafetyCore` has zero dependencies and is linked **directly by the target itself, not through a transitive path**, by every target that renders, validates or decays a glucose value — iOS app, watchOS app, widget extension, complication extension, and every Driver. **`SafetyCore` is the sole home of the Governed Set: the Conversion Factor, the Glucose Validity Bound, the Tandem epoch offset, the Freshness Tier boundaries (CGM and Pump) and their half-open comparison, the debug compressed policy and its single swap point, the alertability predicate and its 60,000 ms skew tolerance, the 1,800,000 ms cooldown, the coverage expiry window, the Coverage Claim selector and its decay, the claim-state and Not-Watching-Reason vocabularies, the alert-type vocabulary, glucose banding, and the glucose/IOB render functions.** A second definition of any Governed Set member — a literal, a re-derivation, or a private reimplementation — is a build failure enforced by the drift guard, whose inventory is this list and not a shorter one. A target may choose its own *presentation* of a Governed Set result; it may not compute the result.

---

### A-10 — A Driver-contributed card renders a health value through a path that never touches `SafetyCore`

**Severity: high.** **Units:** `Drivers/Tandem` and `Drivers/Medtronic`, rendered by `AppFeature`. **ADs at issue:** AD-1, AD-2, AD-3, AD-5, SI-3, SI-6.

FR-37 lets a Driver contribute dashboard cards from a closed vocabulary of nine element variants — "no Driver supplies view code." The vocabulary is closed; **the values inside the elements are strings the Driver produced.**

**Unit A** emits a text row `"IOB  2.45 u"`. **Unit B** emits `"IOB 2,45U"` — its own formatter, its own locale, its own unit spelling. Neither constructs a `Glucose`, so AD-5 is not engaged. Neither names a UI framework, so AD-1 is satisfied. Neither depends on anything but `DriverAPI` and `SafetyCore`, so AD-3 is satisfied. `AppFeature`, the rendering target, does link `SafetyCore` — so AD-2 is satisfied. Every AD passes, and a health value reached the screen having been formatted by a module that never consulted the Conversion Factor, the user's unit preference, or the Freshness Tier.

**Consequence.** A user on mmol/L reads a hero of `6.7 mmol/L` and, four rows below, a Driver card showing `120` — an unlabelled mg/dL number in a dosing-adjacent context, which is SI-3's stated harm. And a Driver-card value carries no staleness badge and no de-emphasis, so an hour-old IOB sits at full contrast beside a hero the freshness ticker has correctly greyed out.

> ### AD-21 — A Driver contributes values, never rendered text
>
> - **Binds:** `DriverAPI`, `Drivers/*`, `AppFeature`, SI-3, SI-4, SI-6, FR-37
> - **Prevents:** a health value reaching a screen through a formatting path that never consulted `SafetyCore`; two Drivers formatting the same quantity two ways.
> - **Rule:** a Driver-contributed descriptor element carries **typed, unformatted domain values with their own source timestamps** — `Glucose`, `Insulin`, `BasalRate`, `Percentage`, `Date` — never a pre-formatted numeric string. Formatting, unit conversion, locale, Freshness Tier treatment and severity are applied by the rendering target using `SafetyCore`'s render functions and the user's current preference. A descriptor element whose payload is a string containing a decimal digit fails the descriptor validation gate. Free text is permitted only for labels, titles and Driver-authored copy that contains no measurement.

---

### A-11 — AD-13 gives each Driver its own error enum and no owner for recovery, so one pump family stops reconnecting overnight

**Severity: high.** **Units:** `Drivers/Tandem` and `Drivers/Medtronic`, consumed by `DomainCore`. **ADs at issue:** AD-13, AD-4, AD-11, FR-8, FR-13.

AD-13's rule types errors. The Consistency Conventions add "one typed error enum per module boundary" — which, applied to two Driver modules, *guarantees* two disjoint enums with no common supertype. FR-8 pins the seven connection states and FR-13 pins the reconnection rule ("no attempt limit… the only things that stop it are the user unpairing and one positive determination that the pairing is no longer valid — the latched Auth Failed state"). Neither the spine nor the PRD says **which Driver-level failures constitute a positive determination.**

**Unit A — Tandem.** EC-JPAKE handshake rejection → `.pairingRejected` → latch Auth Failed. Transport timeout, `CBError.connectionTimeout`, `peerRemovedPairingInformation` → transient → reconnect forever. **Unit B — Medtronic.** SAKE stage failure and `CBATTError.insufficientAuthentication` both map to `.authenticationFailed` → latch Auth Failed, because on that transport an authentication ATT error genuinely means the bond is gone. Both are internally reasonable, both are typed, neither substitutes a default, both leave last-known-good in force. Full AD-13, AD-4, AD-11, AD-12 compliance.

**Consequence.** A transient radio condition that Tandem rides out puts Medtronic into a latched state that FR-13 says is cleared "by user action, never from an attempt count." At 02:15 the pump goes out of range for eleven seconds. The app never reconnects. The Coverage Claim correctly reports `PUMP_DISCONNECTED` — an accurate reason for a state the app itself chose and will not leave — and the proactive lapse notification (FR-85) is the only thing that fires, hours later. The two Drivers have different overnight coverage semantics and no test can compare them, because their error types are incomparable by construction.

> ### AD-22 — Failure *classification* is a closed platform vocabulary; only *detection* is per-Driver
>
> - **Binds:** `DriverAPI`, `Drivers/*`, `DomainCore`, AD-13, FR-8, FR-13, SI-6
> - **Prevents:** two Drivers assigning two different recovery policies to the same class of failure; a transient radio condition latching a permanent stop on one pump family.
> - **Rule:** `DriverAPI` declares one closed `DriverFailure` classification — `transient`, `deviceRejectedCredentials`, `pairingNoLongerValid`, `capabilityUnavailable`, `protocolViolation`, `undecodable` — and one closed `DisconnectedReason` set covering `poweredOff`, `unauthorized`, `unsupported`, `resetting`, `outOfRange`, `unknown`. A Driver's own error enum is its *detail*, carried as an associated diagnostic payload; the classification is mandatory and is what crosses the boundary. **Recovery policy is owned by `DomainCore` alone and is identical for every Driver:** only `deviceRejectedCredentials` and `pairingNoLongerValid` may latch Auth Failed and stop reconnection; everything else reconnects indefinitely per FR-13. A Driver never decides to stop trying. A conformance test drives every Driver through the same classified failure sequence and asserts identical platform-level behaviour.

---

### A-12 — AD-12's CI scan cannot survive contact with a real BLE Driver, and will degrade into per-Driver allowlists

**Severity: high.** **Units:** the CI-gates epic (5.11) and each Driver epic (5.2). **ADs at issue:** AD-12, AD-1, AD-4, SI-1.

AD-12's rule: "CI scans Driver targets for delivery verbs and pump-write characteristic identifiers and fails on a match." Every read-only pump protocol in this product **requires GATT writes**: the Android Medtronic link writes to the CGM and IDD RACP control points to request records (`AndroidMedtronicGattLink.kt:186,408-418`), and the Tandem protocol is request/response over a write characteristic. There is no read-only pump.

**Unit A — the CI epic** implements the scan as specified: flag `write`, `send`, `set`, `deliver`, `bolus`, `command`, plus known write-characteristic UUIDs. **Unit B — the Driver epics** cannot build. The negotiated outcome is always the same: a per-Driver suppression list, checked in beside the Driver, maintained by the person adding the write.

**Consequence.** SI-1's *mechanical* gate — the one enforcement in the register that is supposed to be executable rather than reviewer judgement — becomes a discretionary allowlist maintained by the same person adding the symbol. FR-205's protocol snapshot gate still covers the `DriverAPI` surface, which is the load-bearing half; but the scan the spine advertises is the half that would catch a Driver writing a delivery opcode to a characteristic the port never exposes, and that half is now opt-out.

> ### AD-12 (tightened) — No therapeutic write exists to call, and every device write is a declared read request
>
> - **Binds:** SI-1, `DriverAPI`, `Drivers/*`
> - **Prevents:** a write surface appearing behind a flag, a subclass, or a future Capability; **a CI gate degrading into a per-Driver suppression list because the rule as stated forbids the transport every Driver needs.**
> - **Rule:** no protocol in `DriverAPI` declares a write, command or set member. The Capability set is closed at six; adding to it is a PRD change. **A Driver performs GATT writes only through a single named transport type per Driver, whose payloads are constructed exclusively by a request builder over an opcode allowlist committed as data in the repository — one file per Driver, reviewed as a safety artifact. CI asserts three things and no others: (1) no `DriverAPI` member is write-shaped (FR-205's snapshot); (2) every `CBPeripheral.write*` call site in every Driver target is inside that Driver's single transport type; (3) every opcode reaching that transport is a literal member of the committed allowlist. A change to an allowlist file is a required-review path.** There is no symbol-name scan and no suppression list.

---

### A-13 — Restoration identifiers are unowned, so one Driver's overnight relaunch quietly does not happen

**Severity: high.** **Units:** `Drivers/Tandem` and `Drivers/Medtronic`, with the app target (5.10). **ADs at issue:** AD-11, AD-4, AD-3, Consistency Conventions (Ids).

AD-11 makes Core Bluetooth restoration "the only load-bearing relaunch path" — the entire Coverage Claim rests on it. AD-4 gives each Driver its own actor. The Ids convention covers settings suites and Keychain service names and **not restoration identifiers**. Nothing says who constructs a `CBCentralManager` or `CBPeripheralManager`, or when.

**Unit A — Tandem** constructs its central eagerly when the Driver Catalog is built at launch, with restoration identifier `"central"`. **Unit B — Medtronic** constructs its central and peripheral manager lazily on activation, with restoration identifier `"central"` too — both are private to their module, and neither team can see the other's string. Both comply with AD-11 (identifiers configured), AD-4 (actor-owned), AD-3.

**Consequences, two of them.** (1) iOS delivers a restoration payload only to a manager recreated with the matching identifier during launch; a lazily-constructed manager on a background relaunch either never receives `willRestoreState` or receives it after the relaunch window has closed. The Driver that chose lazy construction simply does not reconnect overnight — and the failure is invisible, because the app looks fine the moment the user opens it, which is also the moment the eager path would have reconnected anyway. (2) Identical identifiers across two managers is undefined-to-hostile: restored peripherals delivered to the wrong Driver's actor.

> ### AD-11 (tightened) — Core Bluetooth restoration is the only load-bearing relaunch path, and the platform owns its identifiers and its wake-up order
>
> - **Binds:** `Drivers/*`, `DomainCore`, app target, SI-6
> - **Prevents:** a coverage claim resting on background execution iOS does not guarantee; **a restoration payload delivered to no manager, or to the wrong one.**
> - **Rule:** `CBCentralManager` and `CBPeripheralManager` are configured with restoration identifiers, and restoration is the only relaunch mechanism any coverage claim may rest on. `BGTaskScheduler` and background `URLSession` are best-effort and may never extend a claim. **Restoration identifiers are derived by the platform from the Driver id (`<driver id>.central`, `<driver id>.peripheral`) and are never authored inside a Driver; a Driver-authored literal fails lint. Every Driver in the Catalog that holds a persisted pairing constructs its managers synchronously during app launch, before the launch callback returns, whether or not it is the active Driver — restoration is a launch-time obligation, not an activation-time one. A test asserts that a cold launch constructs exactly one manager per (Driver, role) and that a restored peripherals dictionary is routed to the actor whose Driver id matches the identifier.**

---

### A-14 — AD-14 binds two modules out of nine, and never says *one instance*

**Severity: high.** **Units:** `SafetyCore`/`DomainCore` (bound) versus `AppFeature`, `WatchFeature`, `WidgetShared`, `Drivers/*` (unbound). **ADs at issue:** AD-14, AD-2.

AD-14's binds line is `SafetyCore`, `DomainCore`, and its lint rule is "a direct `Date()` in `SafetyCore` or `DomainCore` fails lint." Every rendering module and every extension is outside it. It also says "a single `Clock` protocol supplies every current time" — a *protocol*, not a single value.

**Unit A — the dashboard epic.** FR-50's freshness ticker lives in `AppFeature`; it samples `Date()` directly, since the lint rule does not reach there. **Unit B — the Watch epic.** FR-122 pre-bakes timeline entries at `sensorTimestamp + 6min`, computed against `WatchFeature`'s own `Date()`. **Unit C — the widget.** Computes its timeline against the extension process's `Date()` while `validUntil` was minted by the app process's clock.

All three comply with AD-14 (nothing in the bound modules calls `Date()`), AD-2 (all link SafetyCore), AD-13. Two additional legal outcomes: two units construct two *instances* of the same `Clock` type — fine in production, divergent under FR-176's debug compressed policy and in every test that advances time; and a Driver converting a pump epoch (`1199145600`) resolves "now" against a clock the freshness classifier never sees.

**Consequence.** The debug compressed policy (Stale at 20 s) applies on one target and not the other, so the fault-injection surface the whole Simulator-only validation strategy depends on gives false confidence. In production, the divergence is small but structural: the surfaces that decay do so against different clocks, and FR-72's rewind high-water mark is *explicitly process-local*, so the widget process has no rewind detection at all while the app is reporting `CLOCK_UNTRUSTED`.

> ### AD-14 (tightened) — One injectable clock, one instance, every module
>
> - **Binds:** all modules and all targets
> - **Prevents:** freshness, decay, chart windows and day-boundary alignment disagreeing about *now*; **a rendering target or an extension reading a clock the domain cannot substitute; two instances of the same clock diverging under test or under the debug policy.**
> - **Rule:** a single `Clock` protocol declared in `SafetyCore` supplies every current time in every module and every target, including `AppFeature`, `WatchFeature`, `WidgetShared`, every extension and every Driver. A direct `Date()`, `Date.now`, `CFAbsoluteTimeGetCurrent` or `DispatchTime.now` outside the single production `Clock` implementation and the single monotonic-uptime source fails lint **project-wide**. Each process resolves exactly one clock instance at its composition root and passes it down; a module never constructs one. The debug Freshness policy and any injected clock are substituted at that one root, so every surface in that process moves together. A rewind high-water mark is per process by design (FR-72); every process that renders a claim runs the same guard against the same shared implementation.

---

### A-15 — The wrist clamps the thresholds the phone drops, and AD-13 says clamping never happens

**Severity: high.** **Units:** `DomainCore`/`BackendClient` (epic 5.4/5.8) and `WatchFeature` (epic 5.7). **ADs at issue:** AD-13, AD-2, AD-10, SI-2, SI-5.

FR-81: an invalid Backend threshold response "is DROPPED, never clamped, leaving last-known-good values in place." FR-125: the Watch **sanitizes** a corrupt or hostile threshold payload by dependent clamping — "low clamped to 40-200; high clamped to max(low+1, 100)-400; urgent low clamped to 20-low; urgent high clamped to high-500." FR-116 requires "the wrist and the phone hero must band identically for the same stored value."

**Unit A** implements drop-and-keep-last-good. **Unit B** implements clamp-to-ordered-set, plus an absent-keys fallback to 55/70/180/250 "for display banding only". Unit A complies with AD-13 exactly. Unit B complies with AD-13 as its authors read it — banding colour is display, not a "safety path", and FR-125 tells them to clamp — and with AD-10 (it derives no claim) and AD-2 (it links SafetyCore).

**The divergence.** Feed both a hostile threshold set. The phone bands against the last good values; the wrist bands against a clamped derivative of the hostile ones. FR-116's identical-banding requirement fails, and the spine contains no rule that resolves which of the two is right, because AD-13's "no silent defaults on a safety path" never defines the boundary of a safety path — and *banding a glucose value by severity* sits exactly on the line. (Note that AD-13 and the PRD also both ignore the Glossary's harder point: banding is computed from the **Target Range**, a *different* four-value set with a different store, so a wrist that sanitizes "Alert Thresholds" for banding is banding off the wrong set entirely.)

> ### AD-13 (tightened) — Typed errors, no silent defaults, and one named boundary for what counts as a safety path
>
> - **Binds:** all
> - **Prevents:** a failure becoming a plausible-looking value; **two units disagreeing about whether their path is safety-relevant, and clamping on one side of a boundary the other side drops on.**
> - **Rule:** every fallible boundary returns a typed error. **The safety path is defined, not inferred: any computation whose output can change a rendered glucose value, its severity or freshness treatment, an Alert Threshold, a Target Range, a Safety Limit, an alert decision, or the Coverage Claim. On that path no unit substitutes a default, a clamp or a zero — on any target, including the Watch and every extension.** A rejected reading, threshold, Target Range or Safety Limit leaves last-known-good in force and surfaces the bound that failed. **A receiver of a cross-device payload validates and *rejects*; it never repairs. A rejected payload leaves the receiver's previous values in force, and a receiver with no previous values renders an explicit unconfigured state — never a built-in default presented as a user's setting.** Defaults that exist only to give a classifier something to compute are held in a distinct provenance state (AD-23) and are never rendered as though a user chose them.

---

### A-16 — AD-7 states the loud half of the tolerant reader and drops the quiet half, so two DTO authors disagree about an absent optional

**Severity: high.** **Units:** the sync epic (5.8) and the alerting/chat epics (5.4/5.6), both inside `BackendClient`. **ADs at issue:** AD-7, AD-13, SI-12.

AD-7's rule: "unknown fields ignored, a **missing consumed field throws**." FR-155 has a third clause the spine omits: "applies **the documented default for every absent optional field** — including `is_automated` (false), `acknowledged` (false), `raw_accepted` (0), `raw_duplicates` (0) and `source` ('mobile')."

**Unit A — the sync epic** reads AD-7 literally: `acknowledged` is consumed, therefore absent ⇒ throw. **Unit B — the alerting epic** implements FR-155: absent ⇒ documented default. Both write explicit `init(from:)`, neither uses synthesized `Codable`, both use the one decoder configuration. Both comply with AD-7 as written; only one complies with the PRD.

**Consequence.** Unit A's alert-history pull throws on the first response from a Backend version that omits `acknowledged`, and FR-75's episode guard falls back to "no recent Backend alert" (fail-toward-alerting, so duplicate alarms), while FR-78's reconciliation cannot drain. A whole feature degrades on a field whose absence the contract permits. The inverse risk is worse: if the two teams settle the other way and make *consumed* fields defaultable, SI-12's entire asymmetry inverts and a renamed field silently becomes a plausible value.

**Second face in the same module.** AD-7 says "exactly one `JSONDecoder` configuration exists." `BackendClient` carries the Contract-Pinned GlycemicGPT surface *and* the Backend-mediated Nightscout payloads *and* the AI Chat streaming surface. FR-155 requires "Backend timestamps are accepted with or without fractional seconds" — one `dateDecodingStrategy` cannot do that without a custom closure, which is the correct answer but is not what "exactly one configuration" tells two teams to build.

> ### AD-7 (tightened) — One decoder, explicit tolerant reading, three named field classes
>
> - **Binds:** `BackendClient`, SI-12, FR-155
> - **Prevents:** a newer Backend silently breaking an older client; a renamed field silently becoming `nil`; **two DTO authors treating the same absent field as fatal and as defaulted.**
> - **Rule:** exactly one `JSONDecoder` configuration exists, with a date strategy that accepts ISO-8601 with and without fractional seconds. Every Backend DTO implements `init(from:)` explicitly. **Every decoded field is declared as exactly one of three classes, and the class is stated at the declaration site: `required` (absent ⇒ throw), `defaulted(value)` (absent ⇒ the documented default, and the default is committed beside the Contract Pin), or `ignored`. Unknown fields are always ignored. A field with no declared class is a build failure.** No Backend-supplied value is a strict enum; unrecognised members decode to an explicit unknown case. Synthesized `Codable` is prohibited on Backend DTOs. A contract test asserts both directions — an added unknown field decodes, an absent `required` field throws, an absent `defaulted` field yields its documented default.

---

## 3. Medium

### A-17 — Two epics, two migration v4s

**Severity: medium.** **Units:** the insulin/meals epic (5.5) and the sync epic (5.8), both writing `Persistence` migrations. AD-6 says "Migrations are numbered, forward-only, and start at v1." Two branches in flight both add "v4"; both comply. On merge, the registration order decides which v4 exists, and any Builder who installed either branch's TestFlight build carries a database stamped v4 with the other schema — and forward-only means there is no repair. **Fix:** amend AD-6's rule to *"migration identifiers are unique, immutable, non-numeric strings of the form `<yyyymmdd>-<slug>`, registered in one ordered manifest file; a duplicate identifier, a reordering of a released identifier, or an edit to a released migration's body fails CI. The schema version a build reports is the identifier of its last registered migration, never an integer."*

### A-18 — `Glucose Reading` has two producers and its identity is Deferred

**Severity: medium.** **Units:** `Drivers/*` (producer) and `BackendClient` Nightscout ingest (producer), writing the same table. The Deferred table waves the schema away ("the columns are the code's"). FR-137's rules — one Glucose Reading per timestamp, one Bolus per (units, timestamp), **first**-writer-wins for glucose and basal, **last**-writer-wins for bolus — are a cross-epic contract, not a column choice. Two teams implementing them independently get: a Nightscout-sourced bolus overwriting a Driver-sourced one at the same (units, ms), duplicate near-identical glucose rows when a mmol/L-native Nightscout site round-trips through the Conversion Factor to a value 1 mg/dL off the pump's, and a chart with double points and a skewed Time in Range. **Fix:** a new row in an entity-ownership table under AD-19 naming, per entity, the dedup key, the collision winner and the source marker, declared in `Persistence` and asserted by a two-producer test — and the Deferred table's "full database schema" row narrowed to *"column types and indexes are the code's; entity identity, dedup key, collision winner and source marker are fixed by AD-19 and are not deferred."*

### A-19 — Alert Thresholds have three provenances and no home

**Severity: medium.** **Units:** the settings epic (5.9) and the alerting epic (5.4). The spine's Config convention says "App Group `UserDefaults` only for non-safety preferences" — forbidding the obvious home for Alert Thresholds and naming no replacement. FR-73 needs a tri-state provenance (`none` / `backend` / `local`) that a raw key-value store cannot represent: a missing `Int` reads as 0, indistinguishable from a configured 0, and the difference between them is "the Alert Floor is disarmed" versus "the Alert Floor alarms at every reading." Two teams pick two homes and two representations; both comply with every AD. **Fix:** extend AD-19's ownership table — *"Alert Thresholds and Target Range are two distinct four-value sets in two distinct stores, both owned by `DomainCore`, both persisted in the encrypted store and never in `UserDefaults`. Each carries an explicit provenance of `none | backend | local`; absence of a value and a value of zero are distinct states that no store representation may conflate. A built-in default set is reachable only through the `none` provenance and can never arm the Alert Floor."*

### A-20 — The clock-rewind guard is process-local across three rendering processes

**Severity: medium.** **Units:** the app process and the widget extension process. FR-72 states the rewind high-water mark "is process-local, is never persisted across launches". The app therefore reports `CLOCK_UNTRUSTED` and suppresses evaluation while the widget extension — a separate process with its own mark, freshly born on every timeline refresh — has no history to compare against and renders the last claim it read, with a pre-baked decay entry computed against the rewound clock. Both comply. **Consequence:** the phone banner says nothing is watching; the Lock Screen widget beside it still reads "watching". Folded into AD-14's tightening plus an explicit rule that a renderer never presents a claim state its own process cannot vouch for the freshness of.

### A-21 — "Per-Driver protocol detail" defers the number the Coverage Claim's expiry is built on

**Severity: medium.** **Units:** `Drivers/Tandem` and `Drivers/Medtronic`, consumed by the alerting epic. FR-84 sets `validUntil = sensor timestamp + 360,000 ms` for Floor Watching — one number, project-wide, derived from a CGM cadence. Medtronic's advertise-and-wait transport requires the app open and on screen for reconnection (FR-15), and its achievable background cadence is the split-spike unknown of §8.4. A Driver whose realised cadence exceeds the Fresh boundary produces a claim that expires between every reading — a wrist and a widget that oscillate Watching → Not Watching → Watching all night. Both Drivers comply with every AD. The PRD's answer is "that is a coverage fact to surface, not a constant to widen" — the spine gives no place to surface it. **Fix:** `DriverAPI` declares a per-Driver `expectedReadingCadence`, and `DomainCore` surfaces a Driver whose cadence exceeds the Fresh boundary as a standing coverage fact rather than letting the claim oscillate.

### A-22 — `SafetyCore` render functions and locale

**Severity: medium.** **Units:** `WidgetShared` and `WatchFeature`. AD-1 says "Domain code names no platform framework"; `SafetyCore` must nonetheless format `2.45` and `6.7`, and FR-121 requires "a fixed POSIX locale so a comma-decimal device locale cannot produce `2,45`", while FR-138 requires "a dot decimal separator regardless of the device's locale." A team reading AD-1 strictly keeps formatting out of `SafetyCore` and does it locally, per target, with the device locale. Two targets, two decimal separators, for the same stored value — SI-4's stated harm ("phone and wrist disagree about the same reading") in its most literal form. **Fix:** state in AD-1 that `SafetyCore` may name `Foundation` value types and formatters, and in AD-2's Governed Set that the glucose and IOB render functions and their fixed POSIX locale live there and nowhere else.

---

## 4. Low

### A-23 — AD-15's `[ASSUMPTION]` is a cross-epic dependency with no holder

**Severity: low.** **Units:** the build/signing epic (5.10) and `BackendClient` (5.8). AD-15's in-app policy is authoritative and unambiguous, and the Entitlements and Plist Guard prevents broadening — *after* a device-verified baseline is recorded. Until then, two units both comply while the shipped plist is broader than the code: the code refuses the request, the plist permits it, and nothing observable differs. Under fork-and-build, a Builder editing ATS in their own fork (PRD OQ) is a third unit. Low because the in-app policy is the load-bearing half and it is stated precisely. **Fix:** give the assumption an owner and a gate — the Plist Guard fails closed until the baseline file exists in the repository.

### A-24 — The AD-8 conformance canary has no Medtronic counterpart

**Severity: low.** **Units:** `Drivers/Tandem` and `Drivers/Medtronic`. AD-8 gives Tandem a byte-parity conformance test against the Kotlin implementation's existing vectors, explicitly "the canary for an upstream rebase." Medtronic's SAKE state machine is a clean-room reimplementation of a Java artifact with no vendored vectors named anywhere. Two crypto-adjacent Drivers, two evidence levels, one spine sentence covering only the first. §9's Tier 2 does require "the Medtronic SAKE handshake replays through a deterministic queued RNG asserting stage-by-stage byte parity and tamper rejection" — so the PRD covers it and the spine does not restate it. Low, and recorded only because AD-8's confident framing reads as if the crypto question is closed for both.

---

## 5. The Deferred table, row by row

The task asked for a concrete divergence permitted by each deferred row. Three of the six are defensible; three are not.

| Deferred row | Verdict | The divergence it permits |
| --- | --- | --- |
| **Per-screen view and state shape** — *"two units cannot diverge incompatibly over it"* | **False, three times.** | The widget snapshot record (A-2, A-4), the phone→Watch payload (A-3), and the Driver-contributed card descriptor (A-10) are all "state shapes" that cross a boundary no compiler checks. The sentence is true only for state that never leaves one module. Narrow the row to *"per-screen view state internal to one target"* and let AD-17 own the rest. |
| **Full database schema** — *"the columns are the code's"* | **Half false.** | Columns, yes. Entity identity is not: two producers write `Glucose Reading` and `Bolus` (A-18), and dedup key + collision winner + source marker are a cross-epic contract. Also unowned here: cursor rows (A-8), threshold provenance (A-19), and the migration identifier scheme (A-17). |
| **Backend wire schema** — *"owned by the vendored Contract Pin"* | **Sound, with one gap.** | The Pin owns the shapes; it does not own *field class* — required vs defaulted vs ignored (A-16). Two teams read the same Pin and disagree about an absent optional. AD-7's tightening closes it without touching this row. |
| **Per-Driver protocol detail** — *"AD-3 and AD-12 bound what matters across them"* | **False.** | AD-3 and AD-12 bound *dependencies* and *write surface*. They do not bound decode-vs-reject semantics (A-1), cursor durability (A-8), failure classification and recovery (A-11), Safety Limits currency (A-7), restoration identifiers (A-13) or reading cadence (A-21). Six cross-Driver divergences, none of them protocol detail, all of them currently deferred. |
| **Medtronic transport viability** — *"a negative result changes `Drivers/Medtronic` only"* | **Sound.** | Correctly scoped; the spike is sequenced first in the PRD. |
| **CI runner topology / observability** | **Sound.** | Genuinely repository tooling; the required-check roster is PRD-fixed. |

---

## 6. Summary of proposed spine changes

| # | Action | Closes |
| --- | --- | --- |
| AD-16 (new) | Decoded / rejected / undecodable, and only undecodable stops a cursor | A-1 |
| AD-17 (new) | Boundary payloads declared once in a module both sides link; AD-3's graph amended to admit it | A-2, A-3 |
| AD-18 (new) | Safety Limits: one current value, pushed, read per validation pass, admission-only | A-5, A-7 |
| AD-19 (new) | One owning module per entity; acknowledgement is a monotonic latch; cross-device intents are versioned, idempotent, acknowledged | A-6, A-18, A-19 |
| AD-20 (new) | Cursor is a Driver-opaque token committed with its records in one transaction | A-8 |
| AD-21 (new) | A Driver contributes typed values, never rendered text | A-10 |
| AD-22 (new) | Closed failure classification in `DriverAPI`; recovery policy owned by `DomainCore` | A-11 |
| AD-2 (tighten) | The Governed Set — linkage plus exclusive use | A-9, A-22 |
| AD-5 (tighten) | One absolute bound; the constructor takes no policy | A-5 |
| AD-7 (tighten) | required / defaulted / ignored field classes | A-16 |
| AD-9 (tighten) | One writer *per container*; atomic replace; monotonic sequence; self-consistent record | A-4 |
| AD-10 (tighten) | One vocabulary and one decay, versioned by hash | A-3 |
| AD-11 (tighten) | Platform-derived restoration identifiers; launch-time manager construction | A-13 |
| AD-12 (tighten) | Declared transport type + committed opcode allowlist, not a symbol scan | A-12 |
| AD-13 (tighten) | A named safety-path boundary; receivers reject, never repair | A-15 |
| AD-14 (tighten) | Binds every module and target; one instance per process | A-14, A-20 |
| AD-6 (amend) | String migration identifiers in one ordered manifest | A-17 |
| Deferred table | Narrow three rows per §5 | A-2, A-18, A-21 |

---

## 7. What I attacked and could **not** break

This section is the other half of the review. Several of the most promising-looking attack surfaces in this spine are genuinely closed, and knowing which ones are closed is what makes the open ones worth spending money on.

**AD-10's claim computation, on the phone side.** I tried hard to construct two features that both compute a Coverage Claim. I could not. "The selector lives in `SafetyCore` and is pure" plus "the phone computes; the Watch renders and decays and never derives one" is airtight for the units it names, and FR-83's "forking it per surface is prohibited by a test" backs it. The holes I did find (A-3) are in the *vocabulary inside the message* and in the *surfaces AD-10 forgot to name* — the widget extension is never mentioned in AD-10 — not in the computation. This is the strongest AD in the document.

**AD-12 at the type level.** I could not construct two Drivers where one exposes a therapeutic write through a conforming port. With the Capability set closed at six, calibration removed, and no write member declared anywhere in `DriverAPI`, a write cannot be reached through the port by any conforming Driver — the type system carries the invariant, not a convention. A-12 is an attack on the *CI mechanism*, and I want to be explicit that it is not an attack on the invariant: FR-205's protocol snapshot gate is the load-bearing half and it survives.

**AD-5's unit canonicalisation.** I tried to get mmol/L into storage through two Drivers, through Nightscout ingest, and through the Watch. I could not do it in a way that also obeys the spine: the value type is mg/dL by construction, mmol/L exists only as a formatting output, and every ingest path in the PRD names mg/dL explicitly. The remaining risk (A-10) is a Driver formatting a *string*, which never becomes a `Glucose` at all — a different attack, and one the type system was never asked to stop.

**AD-6's key.** I could not construct two units that disagree about the database key. One generation point, Keychain, device-only, after-first-unlock, never derived from user input, refuse-to-open rather than mint a second — FR-136 and AD-6 agree completely and leave no decision to a downstream unit. The one gap adjacent to it is the *file protection class* of the database and the container, which AD-6 does not state and NFR-19 does (folded into AD-9's tightening); the key itself is closed.

**AD-3's dependency rule, on its own terms.** I could not find a compliant pair where a Driver acquires storage, networking or UI. The rule is unambiguous and mechanically checkable. What I found instead is that it is *so* effective that it forbids something SI-8 requires (A-8) and forbids the edge AD-17 needs (A-2) — those are consequences of a working rule, not failures of it, and both are fixed by adding a permitted dependency rather than weakening the prohibition.

**AD-11's claim rule.** "Restoration is the only relaunch mechanism any coverage claim may rest on; `BGTaskScheduler` and background `URLSession` are best-effort and may never extend a claim" — I could not construct two units that disagree about this. The sentence closes the door. The hole (A-13) is in identifier ownership and construction timing, not in what a claim may rest on.

**AD-8.** I could not construct a divergence between two units over the crypto fork. "No cryptographic code is authored or vendored", an exact upstream tag, one product declaration and one access-level change as the entire maintained delta, and a byte-parity conformance test as the rebase canary — this is a tighter statement of the riskiest item in the port than most projects manage, and there is no decision left for a downstream unit to make differently.

**AD-4.** Swift 6 language mode, strict concurrency complete, warnings as errors, `Sendable` value types across boundaries. I could not construct two units that disagree about data-race safety, because the compiler is the arbiter and both units answer to it. AD-4's limit is that it has no authority across a *process* boundary — which is A-4, and which is a gap in AD-9's remit rather than in AD-4's.

**The `Alert Threshold` / `Target Range` separation.** I expected to break this and could not, at the spine level: the PRD Glossary states it, FR-47 and FR-58 restate it, FR-116 restates it for the wrist, and a test configures the two sets differently and asserts TIR follows the Target Range. The residual risk (A-19) is about *where the two stores live and how provenance is represented*, not about whether two units might collapse them.
