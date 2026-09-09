# Rubric Review — ARCHITECTURE-SPINE.md (GlycemicGPT iOS + watchOS)

**Artifact:** `_bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md`
**Driving input:** `_bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md` (+ `addendum.md`)
**Reviewed:** 2026-08-03
**Gate:** pre-handoff rubric walk against the good-spine checklist

Judged as a **spine** — a consistency contract fixing only the invariants that keep independently-built
units from diverging. Terseness is not a finding. Missing structural detail is not a finding. A
*divergence point left unfixed* is.

---

## Verdict

This is a strong spine in its domain core and a thin one at its edges. Fifteen ADs are terse,
mechanism-bearing and mostly enforceable, and the safety-critical type and decoding invariants
(AD-5, AD-7, AD-11, AD-12) are better than most solution designs achieve at ten times the length.
But the spine fixes the *phone's domain* and under-fixes everything that surrounds it: the Driver
lifecycle the PRD explicitly handed it (C-1), the Watch as an independently-built unit, the
build-composition dimension that three safety invariants rest on, and the operational envelope.
Four of the twelve safety invariants reach the reader as intentions rather than mechanisms.

**Counts:** 4 critical · 5 high · 5 medium · 4 low (18 findings)

**Not ready to hand off.** Findings 1–4 are each independently sufficient to let two units diverge
incompatibly, which is the defect class a spine exists to prevent. Findings 5–9 are cheap to fix
and mostly additive.

---

## What is genuinely strong

State this plainly, because most of it should survive the revision untouched.

- **The paradigm is earned, not decorative.** A pump Driver genuinely *is* an adapter and the PRD's
  closed read-only Capability set genuinely *is* a port list. The spine says so and declines to
  impose anything further (§ Design Paradigm). It buys the one property the project cannot do
  without: a domain core exercisable with no hardware — which matters because the lead developer has
  no iPhone and Core Bluetooth does not exist in the Simulator (addendum §1.2).

- **AD-5 is the model AD.** It converts SI-2 and SI-3 from review items into a type invariant, and it
  rejects `precondition` *with its reason stated* — a trap during a background Bluetooth wake the
  user never sees. That is exactly the translation trap addendum §1.5 flags, foreclosed in the type
  system rather than in a checklist.

- **AD-7 is the single best line in the document.** It identifies that Swift's synthesized `Codable`
  is the precise *inverse* of SI-12 and prohibits it outright, rather than asking authors to be
  careful. Enforceable, and it prevents its stated divergence.

- **AD-11 is the best safety decision here.** Restricting the Coverage Claim to Core Bluetooth state
  restoration, and explicitly demoting `BGTaskScheduler` and background `URLSession` to best-effort
  that "may never extend a claim", forecloses the most likely wrong implementation of SI-6. Most
  drafts would have listed all three as background mechanisms and let the feature layer choose.

- **AD-12 enforces SI-1 by construction plus a scan,** not by policy: no write member exists to call,
  and CI hunts delivery verbs and pump-write characteristic identifiers. Absence of surface beats
  review.

- **AD-8 is verified accurate.** I confirmed against `apple/swift-crypto` at `4.5.1` today:
  `CryptoBoringWrapper` is *not* declared as a product — only `Crypto`, `_CryptoExtras` and
  `CryptoExtras` are. The fork delta really is a product declaration plus an access-level change,
  no cryptographic code authored. Making the Kotlin-vector conformance test the *rebase canary* is
  the right mechanism for a fork that must track upstream.

- **AD-15 refuses to state a plist posture as fact** and marks it `[ASSUMPTION]` pending device
  verification. That is rare discipline and exactly what OQ-45 asked for. The problem (finding 12)
  is only that nothing carries it forward.

- **Version currency is real, not asserted.** Verified today against upstream release APIs:
  GRDB.swift **7.11.1** published 2026-06-18 and swift-crypto **4.5.1** published 2026-07-16 are
  both the current latest. No stale-training-data pins — and the memlog shows the GRDB 6 trap was
  consciously avoided. (One factual error rides along; see finding 5.)

- **The Deferred table's *reasoning* is mostly right.** Per-screen state, database columns and
  per-Driver protocol detail are correctly the code's. The defects below are about what is *absent*
  from that table, not what is in it.

---

## Critical

### F-1 — C-1, the Driver lifecycle contract, is absent entirely
**Severity: critical** · **Location:** no AD; § Deferred row "Per-Driver protocol detail" ·
**PRD:** §15 C-1 ("blocking input", gates P1)

The PRD hands architecture five contracts and marks C-1 blocking for P1 Driver work: *"the exact
states, transitions and re-entrancy rules a Driver must honour between registration, activation,
connection, suspension and teardown."* Nothing in the spine supplies it. AD-4 supplies a
*concurrency* rule ("each Driver owns an actor"), which is not a lifecycle. AD-3 and AD-12 bound
what a Driver may *depend on* and may not *expose*, not how it is driven.

The Deferred table then actively hides it: *"Per-Driver protocol detail — belongs to each Driver's
epic; AD-3 and AD-12 bound what matters across them."* That sentence is where the divergence lives.
Five units implement `DriverAPI` — `Drivers/Tandem`, `Drivers/Medtronic`, `Drivers/Simulated`,
`Drivers/TraceReplay`, and the app-hosted Nightscout source (FR-38) — and they are built by
different people at different times. Without a lifecycle contract each will invent its own
activation/connection/suspension semantics, and `DomainCore` cannot drive all five. This is the
single most consequential omission in the document.

The PRD already constrains the answer, so the contract is cheap to write:
- FR-28: an init failure skips that Driver, drops its settings entry, removes it from the list, and
  affects no other Driver; an *activation* failure returns a typed error, leaves it inactive, and
  writes no slot persistence.
- FR-26: selection survives relaunch, restart, upgrade **and background launch**.
- FR-21 feature NFR: Catalog construction and selection restoration complete **synchronously during
  launch, before any Bluetooth manager is created, with no network I/O** — the whole path must work
  on a background Bluetooth relaunch with no scene.
- FR-13: reconnection has no attempt cap and no give-up condition (and FR-141 forbids reading the
  upload retry budget as one).
- AD-11: restoration is a relaunch path, so the lifecycle has a *resume-from-restoration* entry
  point distinct from cold start.

**Fix:** add an AD that (a) declares the lifecycle state set as one closed enum in `DriverAPI`,
(b) fixes the legal transitions including the restoration entry point, (c) states the re-entrancy
rule — activate/deactivate idempotent, a second concurrent connect collapses into the first rather
than opening a second session, teardown always reaches a terminal state, (d) states that no
lifecycle call performs network I/O or blocks launch, and (e) states that a Driver's failure is
always local to that Driver. Keep it to eight lines; it is an invariant, not a design.

---

### F-2 — The build-composition dimension is silent, and three safety invariants rest on it
**Severity: critical** · **Location:** no AD; § Stack; AD-15 ("identically in every configuration") ·
**PRD:** FR-27, FR-189, FR-182, FR-176/OQ-48, FR-158, SI-1, SI-9

The spine never defines what a build configuration is, yet it depends on the concept and so does the
PRD, heavily:

- **FR-27 + FR-189:** disabling a Driver is a **compilation condition**, not a runtime flag; the
  gate is **keyed off each Driver's own canonical id constant** so a rename cannot leave the switch
  pointing at a nonexistent id; and CI must additionally build an **all-Drivers-enabled**
  configuration or the gated code ships untested. FR-189 states both halves are required and
  neither substitutes for the other.
- **FR-189:** the Simulated and Trace-Replay Drivers are governed by that same mechanism and
  explicitly **not** by `#if DEBUG`, so a shipped configuration cannot silently lose the only two
  Drivers testable without hardware.
- **FR-189 (SI-1):** *"No build setting, compilation condition, scheme, or configuration anywhere in
  the repository enables a therapeutic write. The only Driver-affecting setting is subtractive."*
  That is an AD-12 obligation the spine never states.
- **FR-189 (SI-9):** the crash/error DSN defaults to empty in every configuration and the build
  **hard-fails when a non-empty DSN is present in CI**.
- **OQ-48 (resolved):** fault injection is gated on a dedicated compile-time flag OFF in **both**
  channels, because `develop` also ships through TestFlight — so "not TestFlight" is not a valid test.
- **FR-158 / SI-9:** raw packet capture exists in non-release builds only; release builds emit at
  warning and above.
- **FR-182:** the channel (`develop` / `main`) is a **build-time branch choice**, not a second app —
  builds share bundle identifiers and replace each other.

AD-15 already leans on the concept — *"identically in every configuration"* — without the spine ever
saying what a configuration is or which ones exist. Left unfixed, each feature epic will invent its
own flag, some will reach for `#if DEBUG`, and the subtractive-only property that protects SI-1 will
not survive contact.

**Fix:** add an AD on build-time composition: the closed set of compilation conditions and their
naming rule (keyed on the owning Driver's canonical id constant); the rule that a condition may only
**subtract** a Driver and may never add a Capability or a write path; that `#if DEBUG` gates nothing
that ships and diagnostic-only surfaces use a dedicated named flag OFF in every pipeline
configuration; and that CI builds an all-conditions-enabled configuration so nothing gated loses
compilation and test coverage.

---

### F-3 — The Watch is modelled as a pure renderer; the PRD requires a semi-autonomous unit, and the graph forbids what it needs
**Severity: critical** · **Location:** § Invariants mermaid graph (`WF[WatchFeature] --> SC`), AD-9,
AD-10 · **PRD:** FR-115, FR-116, FR-122, FR-128, FR-129, FR-134, NFR-4, NFR-19

The dependency graph gives `WatchFeature` exactly one edge: `SafetyCore`. AD-9 governs "one App
Group, exactly one database writer" and describes extensions reading a snapshot file. AD-10 says the
Watch "renders and decays the phone's claim and never derives one." All three describe the *phone*
side. The Watch is a second device with its own process, its own storage and its own scheduler, and
the PRD requires it to do substantially more than render:

- **FR-122** — a Watch-side cache holding the last Glucose Reading, **up to 72 readings**, the last
  IOB and the display unit, **readable while the Watch is locked**, with its own duplicate rule
  (timestamp within 30,000 ms), its own overflow rule (drop oldest past 72), and its own corruption
  rule (a malformed record is dropped; an unreadable cache is discarded wholesale and renders "no
  recent data", never partial garbage). Every time-driven transition is **pre-baked as a future
  timeline entry** at arrival, so the wrist decays with the phone force-quit and zero messages.
- **FR-128/FR-129** — the **Watch-scheduled notification is the primary wrist alert path**, and a
  **30-minute re-alarm ladder is scheduled locally on the Watch** so it continues with the app
  force-quit. The wrist notification identifier is derived from the alert's identity so a mirrored
  copy *replaces* rather than stacks, and a test must assert a Watch-scheduled alert and its mirrored
  copy never coexist.
- **NFR-4** — the one App Group identifier resolves to **two container instances that no filesystem
  joins**: a phone-side container and a Watch-side container, each with **exactly one writer**, with
  WatchConnectivity as the only path between devices, and *"no requirement anywhere may assume a
  write on one device is visible on the other."*
- **NFR-19 / FR-134** — the container is written at the same protection class as the store
  (after-first-unlock, never when-unlocked) or the complication renders `--` after every lock cycle;
  and it holds no credential, no key, no raw frame.
- **NFR-4** — the container is a **cache, never a second store**, nothing in it is an input to the
  Alert Floor, and a reader never constructs a Glucose Reading the shared module did not validate.

AD-9 as written ("extensions read a small versioned snapshot file written by the app") is true of the
phone's widget extensions and silently wrong about the wrist. It also gives no mismatch rule — AD-10
supplies one for the Watch claim payload but nothing says what a widget extension does with a
snapshot whose version it does not recognise.

**Fix:** extend AD-9 (or add a sibling AD) to state: two disjoint containers, one writer each,
identical protection class, cache-never-store with no Alert-Floor input, and a single degradation
rule for an absent/unreadable/version-mismatched container — render the no-data state, never a stale
value, never an error. And state where the Watch's own scheduling and cache code lives, since the
graph currently permits it only inside `WatchFeature` with no shared codec.

---

### F-4 — C-3 is under-specified: AD-10 versions the claim, but far more crosses the link
**Severity: critical** · **Location:** AD-10 · **PRD:** §15 C-3 (blocking, gates P2), FR-116,
FR-120/121/132, FR-128, FR-129, FR-134

C-3 asks for the *phone↔Watch payload schema*, and notes the two sections "name state vocabularies
that must be proven identical" and that SI-4 requires one definition. AD-10 addresses only the
Coverage Claim: *"the phone-to-Watch payload carries an explicit schema version; on mismatch the
Watch degrades to not watching with a reason."* Good rule, wrong scope. What actually crosses:

- Glucose Readings, IOB and six hours of history (FR-120, FR-121, FR-132) — plus FR-116's "history
  codec", which NFR-4 places in the shared safety module.
- An alert delivery that **wakes a suspended Watch app in the background** (FR-128).
- The re-alarm flag, with an explicit **default-on-when-omitted** rule so an older app build still
  re-alarms (FR-129) — note this is a *tolerant-reader* rule in the opposite direction from AD-7's,
  and it is unstated.
- Eight named preferences carrying a **monotonic sequence value** so an unchanged payload is still
  delivered (FR-134), plus a **read-back** of what the Watch actually holds, because *"every 'synced
  to watch' claim derives from an acknowledged delivery or a read-back — never from 'we called the
  API'."*
- The five Not-Watching Reasons, whose vocabulary A-11 says preserves parity with the Android wire
  vocabulary the Watch already decodes.

No module in the graph or the structural seed owns these wire types. Phone and Watch will therefore
each write their own encode/decode — which is precisely the SI-4 defect NFR-4 says must not recur
(*"the Android defect where the Wear module mirrors freshness numbers independently must not be
reproduced"*).

**Fix:** name the owning module for the link types (`SafetyCore`, consistent with NFR-4 placing the
history codec there, or a small `WatchLink` module both sides link — either is fine, but pick one).
State one envelope version for the whole link with two rules: an unknown *message kind* is ignored,
an unknown *envelope version* degrades to not-watching with a reason. State that the Not-Watching
Reason set and the freshness/decay vocabularies have exactly one definition site. Generalise AD-10's
existing mismatch rule from the claim to the envelope.

---

## High

### F-5 — "SQLCipher via GRDB SPM package trait" is not true at the pinned version
**Severity: high** · **Location:** § Stack row "SQLCipher | via GRDB SPM package trait"; AD-6 ·
**Also:** run memlog line 4

Verified today against the actual tag. `GRDB.swift` **v7.11.1**'s `Package.swift` contains **no
`traits:` section**. SQLCipher is enabled by *editing GRDB's own manifest*: delete the `GRDBSQLite`
product and target, uncomment a dependency on `sqlcipher/SQLCipher.swift` (from 4.11.0), uncomment
the `GRDBSQLCipher` target, and add the `SQLITE_HAS_CODEC` / `SQLCipher` defines. Upstream's own
guidance is that users fork GRDB and modify the manifest; the traits PR (groue/GRDB.swift#1708) is
not in this tag and is driven by a `GRDBCIPHER` environment variable rather than a consumer-facing
trait.

What was genuinely unblocked in 2026 is that SQLCipher became consumable **via SwiftPM at all**
(GRDB 7.10.0 + `SQLCipher.swift`) — which is the useful half of the memlog's finding. But the
mechanism named in the Stack does not exist, and the consequence is architectural, not cosmetic:
**the project needs a second maintained fork.** That means a second exact pin, a second rebase
burden, a second entry on the dependency licence allowlist (OQ-53), and it interacts with FR-193's
`Package.resolved` / `.exact` discipline and FR-201's rule that cryptography-adjacent packages are
pinned exactly.

**Fix:** correct the Stack row to name the real mechanism and the pinned SQLCipher.swift version.
Extend AD-6 with a fork clause shaped like AD-8's — the fork exists, the delta is a manifest edit and
nothing else, it is pinned to an exact upstream tag — and add the canary AD-8 has but AD-6 lacks:
a test that opens the store file with stock SQLite and **asserts failure**, so a fork that silently
loses `SQLITE_HAS_CODEC` produces a red build rather than an unencrypted database holding PHI.

---

### F-6 — Deferring "Observability and crash reporting" wholesale drops a system-wide safety invariant
**Severity: high** · **Location:** § Deferred, final row; § Consistency Conventions "Logging" row ·
**PRD:** SI-9, NFR-24, NFR-32/33, FR-158, FR-189

The Deferred rationale — *"No project telemetry exists to design; a Builder's own DSN is their
choice"* — is right about telemetry and wrong about logging. SI-9 is a **system-wide invariant** with
concrete, centrally-ownable mechanism that FR-158 defines once:

- Four scrubbing rules with exactly one definition site, applied **before emission and again before
  export**: JWT-shaped → `[TOKEN]`, email → `[EMAIL]`, `\d{2,3} mg/dL` → `[BG]`, `\d{1,2}\.\d mmol/L`
  → `[BG]`.
- An **iOS-specific trap stated because a naive port hits it**: the unified logging system treats
  interpolated numeric values as **public by default** while redacting dynamic strings, so a health
  value interpolated into a log line reaches the system log *without the scrubber ever seeing it*.
  Every such interpolation must be explicitly marked private or omitted, **and a lint gate checks it**.
- All glucose formatting uses a dot decimal separator regardless of locale, so mmol/L output still
  matches the scrubber (SI-3) — a cross-cutting formatting rule with a safety consequence.
- Release builds emit at warning and above; raw packet traces are non-release-only, in memory, never
  written to disk unencrypted.
- FR-189: the DSN is empty in every configuration and a non-empty DSN **hard-fails the build in CI**.

The spine's only coverage is a Consistency Conventions row: *"Structured, one category per module.
No health value, raw payload or credential at any level (SI-9)."* That is a wish. It names no
mechanism, and it does not survive the numeric-interpolation trap — an author obeying it literally
still leaks.

**Fix:** promote to an AD. One log facade in a module every target links; health-typed values are
non-interpolatable **by construction** (no public `CustomStringConvertible`, so a leak is a compile
error rather than a lint miss); scrubbing exists once and runs at both emission and export; the
interpolation-privacy lint is named with its host check. Narrow the Deferred row to crash-reporting
*integration* only, and keep FR-189's empty-DSN/CI-hard-fail rule in the spine since it is an SI-1/
SI-9 boundary, not a Builder preference.

---

### F-7 — SI-5, SI-7, SI-8 and SI-11 have no architectural mechanism
**Severity: high** · **Location:** front-matter `binds: [… 'SI-1..SI-12' …]`; AD-13 · **PRD:** §4

The header binds all twelve invariants. Seven map to an AD (SI-1→AD-12, SI-2/SI-3→AD-5, SI-4→AD-2,
SI-6→AD-10/AD-11, SI-10→AD-6, SI-12→AD-7). Four do not, and the PRD's own framing is that *"an
invariant with no mechanism is a wish."*

- **SI-8 is the worst of the four.** History cursors never advance past a record that was not
  decoded, **and iOS termination makes process-local cursors lose data**, so cursors must be
  *persisted*. This is a contract spanning every Driver plus `Persistence`: FR-146 anchors resume on
  the highest stored raw-history sequence number and stops the advance at the last good record;
  FR-154 carries a separate Nightscout cursor; FR-36 requires a Trace-Replay fixture proving
  non-advance. Left to per-Driver epics (the Deferred table sends it there), Tandem and Medtronic
  will implement it differently and one will silently lose insulin records — the exact stated
  consequence.
- **SI-5.** The Alert Floor arms only on a reading fresh **by its own sensor timestamp** and only
  against thresholds actually set. Two wiring invariants follow that no feature epic can be trusted
  to rediscover: FR-34 — *"the Alert Floor does not read its inputs from this channel; it reads from
  persisted Pump data, so a dropped event cannot suppress an alert"* (the Driver event channel is
  explicitly best-effort, 256-deep, drop-oldest); and FR-49/FR-116 — a negative age classifies Fresh
  **for display only** and never arms the Floor.
- **SI-7.** Only completed deliveries count, and A-13/FR-140 put the filter **inside the Driver at
  the point the frame is decoded**, so no downstream surface applies a second one. That is a layering
  invariant, and it is the kind that erodes first.
- **SI-11.** Backend Safety Limits may only **narrow**, never widen, and a widening response is
  rejected **atomically** (FR-32, FR-81). AD-13 mentions Safety Limits but only says last-known-good
  stays in force on rejection — it never states the monotonic-narrowing rule or the whole-response
  atomicity, so a reader would implement per-field acceptance.

**Fix:** one AD covering ingest and cursor discipline (persisted cursors; a decode failure stops the
advance; the Alert Floor's inputs come from the store and never from the event channel; SI-7's filter
is at extraction), and one added clause in AD-13 for SI-11's narrow-only, whole-response-atomic rule.
Then the `binds:` claim becomes true.

---

### F-8 — FR-37's closed descriptor vocabulary is unaddressed — a guaranteed Driver-to-Driver divergence
**Severity: high** · **Location:** no AD; AD-12 closes the Capability set but not this ·
**PRD:** FR-37

A Driver contributes dashboard cards and one detail screen per card built entirely from a **fixed,
closed** declarative vocabulary — 9 card element variants, 6 semantic colours, 4 label styles, 13
icons, 6 settings descriptor variants — and *"a Driver cannot introduce a new element."* Ordering is
deterministic: platform cards 0–50, Driver cards 100+, lower sorts higher, ties broken by Driver id.
Structural bounds are **refusals, not truncations**: nesting deeper than 5 is not rendered, a detail
screen accepts exactly 100 elements and refuses 101. FR-38 places the Nightscout card at priority 200
in that same band.

This is a textbook cross-unit contract: every Driver epic and `AppFeature` must agree, and it is
exactly the kind of vocabulary that grows one element per epic until the phone and the platform
disagree about what is renderable. AD-12 already uses the right enforcement shape for the Capability
set ("closed at six; adding to it is a PRD change") — the descriptor vocabulary needs the same
sentence and does not have it.

**Fix:** one AD (or one clause in AD-12): the card/settings descriptor vocabulary and the priority
bands are declared in `DriverAPI`, are closed, an addition is a PRD change, and bounds violations are
refusals rather than truncations. Three lines.

---

### F-9 — AD-3's rule contradicts FR-38, and non-Driver Capability providers have no home
**Severity: high** · **Location:** AD-3; § Structural Seed · **PRD:** FR-38, FR-31, FR-21

AD-3 states flatly: *"a Driver may depend **only** on `DriverAPI` and `SafetyCore`."* FR-38 requires a
Capability participant that cannot obey that: the Backend-mediated Nightscout source declares the
data-sync Capability and *"lives in the app module, not a Driver target, because it needs the app's
networking and persistence stack that a Driver target is forbidden to import."*

So `DriverAPI` conformance is deliberately **not** confined to `Drivers/*` — but the spine never says
so, the structural seed has no home for an app-hosted provider, and AD-3's CI check ("the graph is
asserted from the resolved package manifest") plus AD-12's CI scan ("scans Driver targets") both need
a definition of *which targets are Driver targets* that the spine does not give. As written, a
reader implementing AD-3 literally either blocks FR-38 or weakens the rule for everything.

Related: FR-21 makes the Driver Catalog the sole registration path and requires it to be constructed
synchronously at launch before any Bluetooth manager with no network I/O. The spine never names which
module owns the Catalog.

**Fix:** scope AD-3's rule and AD-12's scan explicitly to `Drivers/*` by target-path convention;
state that `DriverAPI` conformance is permitted outside `Drivers/*` for providers that need the app
stack, and where those live; name the module that owns the Driver Catalog and restate its
no-network/synchronous-launch constraint as an invariant.

---

## Medium

### F-10 — C-5 is deferred to the Contract Pin, but the outbound queue is not a wire schema
**Severity: medium** · **Location:** § Deferred row "Backend wire schema" · **PRD:** §15 C-5
(blocking, gates P1), FR-140, FR-141, FR-142, FR-143, NFR-19

The Deferred row is correct that the *payload shape* belongs to the vendored Contract Pin. But C-5's
real cross-unit content is a state machine spanning `Persistence`, `DomainCore` and `BackendClient`,
and deferring the schema silently defers that too:

- **Ordering (FR-140):** the local write happens **first and unconditionally**; enqueue is a separate
  second step; an enqueue failure is logged and **swallowed** and never propagates into the poll loop,
  *"because a dropped upload row is harmless and a dead poll loop starves the dashboard and the Alert
  Floor."* That is a safety-shaped ordering rule and it belongs in a spine.
- **Row states (FR-141):** pending / in-flight / failed, with transport-and-{408,429,502,503,504}
  failures stamping the attempt time **without** incrementing retry count, other non-2xx
  incrementing, ineligible at 5, eligibility at `2000 ms × 2^retryCount`, and a row left in-flight by
  **process death** returning to pending after a **15-minute** reclaim (A-30, deliberately longer
  than Android's 60 s).
- **Bound (FR-142):** 20,000 rows, evict oldest-first, in-flight rows never evicted, failed rows
  *are* eligible.
- **Durability (FR-140, NFR-19):** a batch handed to the system for deferred upload is serialized to
  a file inside the protected container and deleted on completion or failure.
- **Mode change (FR-143):** the transition purges the queue and re-sweeps, because a Driver keeps
  producing rows and an enqueue can race the change.

**Fix:** one AD fixing the row state set, the reclaim-after-process-death rule, the eviction rule, and
the local-write-before-enqueue ordering with its non-propagating failure. Leave the payload fields to
the Contract Pin, as the Deferred row correctly says.

### F-11 — The Contract Pin has a folder but no rule, and AD-7's approved carve-out is missing
**Severity: medium** · **Location:** § Structural Seed (`contract/`); AD-7 · **PRD:** FR-214,
OQ-36 (resolved), A-16, FR-155

The seed shows `contract/ openapi.json + CONTRACT_VERSION` and the Deferred table says the wire schema
is "owned by the vendored Contract Pin", but no AD says who bumps the pin, what fails when the
vendored document and the DTOs disagree, or which check hosts that comparison.

More pointedly: **OQ-36 is resolved with an approved exception to AD-7's rule.** `wideSpread` and
`identityAgreement` are marked optional-with-default **in the Contract Pin**, precisely so *"the
exception is explicit in the contract rather than implicit in the client"* (A-16). AD-7 as written —
*"a missing consumed field throws"* — has no room for it, so an author implementing AD-7 literally
breaks the meal path, and an author who instead adds a client-side optional puts the exception in the
place the PM ruling forbids.

**Fix:** add the carve-out clause to AD-7 in one sentence — an exception to fail-loudly exists only as
an optional-with-default *in the Contract Pin*, never as client-side leniency — and add a Contract Pin
rule: the vendored document is the single source for Backend shapes, `CONTRACT_VERSION` is bumped with
it, and a DTO/document disagreement fails a named check.

### F-12 — No open-questions surface; OQ-45 is half-settled with no owner and no gate
**Severity: medium** · **Location:** AD-15 `[ASSUMPTION]`; document has no Open Questions section ·
**PRD:** OQ-45 ("ASSIGNED TO ARCHITECTURE")

OQ-45 explicitly assigns architecture the job of settling the ATS question **empirically** and
recording the verified baseline, after which FR-204's Entitlements and Plist Guard prevents
broadening it. AD-15 restates the already-settled half (the in-app classification policy, fixed by
FR-150/NFR-20) and correctly marks the open half `[ASSUMPTION]`. Refusing to assert an unverified
plist posture is the right call — but the spine has **no Open Questions section at all**, so the item
has no owner, no closing test and no gated phase. It exists only as an inline aside in one AD, which
is how an item of this kind gets lost. The PRD's own concern is live: whether `NSAllowsLocalNetworking`
covers raw private-IP literals is unverified, and its presence causes `NSAllowsArbitraryLoads` to be
ignored.

Related and also unrecorded: OQ-47 (whether ATS justification text is needed for a Builder who
distributes externally) and OQ-32 (whether the Watch holds a Backend credential — which materially
changes F-3's wrist topology and the Keychain threat model, and which 5.8 was told to answer).

**Fix:** add a short Open Questions section carrying OQ-45 with its owner, the on-device test that
closes it, and the phase it gates; add OQ-32 because it is an architecture-shaped question that
changes the module graph.

### F-13 — Backend-optional vs Backend-connected is a system-wide mode with no architectural home
**Severity: medium** · **Location:** no AD; § Capability→Architecture Map row 5.8 · **PRD:** FR-143,
FR-152, FR-153, FR-79/FR-82, NFR-23

FR-143 makes *a non-blank stored Backend URL the single canonical signal* for whether a Backend is
configured, and requires that *"every dependent behavior observes that one signal rather than
re-deriving it from ad-hoc checks."* The mode change is not cosmetic: it purges the outbound queue,
deletes all raw pump-history rows except the highest-sequence anchor (with a repeating sweep because
an enqueue can race the change), clears Backend-provenance Alert Thresholds while preserving
device-set ones, switches on the local threshold editor, and takes the app to network silence with
exactly one named exception (the upstream-release check, off by default).

Four units observe this — `AppFeature`, `WatchFeature`, `DomainCore`, `BackendClient` — which makes
"one signal, observed not re-derived" a textbook spine invariant. The spine does not mention mode at
all.

**Fix:** one clause in an AD: the mode signal has one definition site and one observer protocol;
nothing re-derives it; the mode transition's purge is atomic with respect to enqueue.

### F-14 — Port ownership for Persistence and BackendClient is undeclared; the graph as drawn cannot be wired
**Severity: medium** · **Location:** AD-1; § Invariants mermaid graph; § Structural Seed

AD-1 says every outside-world interaction crosses *"a port declared in `DriverAPI` or an adapter
module."* `DriverAPI` is a real ports module with a real rule. "or an adapter module" is not a rule —
it is the absence of one, and it is where the hexagon's dependency inversion silently stops.

Concretely, the graph has `DomainCore --> DriverAPI` and `DomainCore --> SafetyCore`, and no edge in
either direction between `DomainCore` and `Persistence`. The structural seed nonetheless puts
"repositories" **inside `DomainCore`**. With no edge, nothing can wire them: either `Persistence`
depends on `DomainCore` (inversion — an edge the graph lacks and AD-3 does not obviously permit), or
`DomainCore` depends on `Persistence` (no inversion, contradicting AD-1). Same question for
`BackendClient`.

There is also no named **composition root**, and the app has at least four entry paths that each need
one: normal launch, Core Bluetooth restoration relaunch (AD-11), a widget/complication extension
process, and the Watch app. FR-21's constraint — Catalog construction completes synchronously before
any Bluetooth manager, with no network I/O — is a composition-root property, and it is the one most
likely to be violated by a feature epic wiring things in a scene delegate.

**Fix:** name the module that declares the persistence and backend ports (a `Ports` module, or
`DomainCore` with the inversion edge drawn), correct the graph to match, and name the composition
root(s) with the launch-path constraint attached.

---

## Low

### F-15 — `binds:` overclaims
**Severity: low** · **Location:** front matter

`binds: ['FR-1..FR-237', 'SI-1..SI-12', 'NFR-1..NFR-34']`. Four SIs have no mechanism (F-7), and the
Capability→Architecture Map covers PRD §5 areas only — §6's 34 NFRs are never mapped, including
NFR-3 (pinned toolchain and a floor-runtime test destination), NFR-8 (main-thread and background-wake
work rules), NFR-13 (persist before derive), NFR-14 (no trap on any ingest/decode/background-wake/
render path — closely related to AD-5 but broader), NFR-15 (migrations never destroy data as a
fallback — directly an AD-6 obligation), and NFR-16 (bounded growth everywhere). Either narrow the
claim or add the NFR rows. NFR-15 in particular deserves a clause in AD-6: "forward-only" does not by
itself forbid a destructive fallback migration.

### F-16 — CI-enforced rules name no host check
**Severity: low** · **Location:** AD-3, AD-12, AD-14, AD-15 · **PRD:** FR-197

FR-197 closes the Required Check roster at exactly five (`Static Analysis Gate`, `Dependency Scan
Gate`, `Workflow Lint`, `Workflow Security`, `iOS Gate`) and states the rule plainly: *"A requirement
elsewhere that says 'a Required Check fails…' without naming one of the five names a gate that does
not exist."* Four ADs assert CI enforcement — the dependency-graph assertion, the write-verb scan,
the `Date()` lint, the plist guard — and none names its host. The Deferred row correctly leaves runner
topology to tooling, but host assignment is not runner topology; it is the difference between an
enforceable rule and an intention. One column added to the ADs, or a four-row table, closes it.

### F-17 — The structural seed restates PRD-owned metadata
**Severity: low** · **Location:** § Structural Seed (`Medtronic/ # SAKE reimplementation; Beta`)

Verification Status is PRD-owned metadata declared by the Driver and cross-checked in CI against the
Device Verification Matrix (FR-22, A-5), with OQ-17 still open on who assigns it and whether a
protocol change auto-demotes it. Restating "Beta" in the spine creates a second definition site for a
value that changes on a different cadence than this document — the same defect class SI-4 exists to
prevent. Drop the word.

### F-18 — Identifier templating and signing appear in the Stack but in no AD
**Severity: low** · **Location:** § Stack ("fastlane + match | Builder-side signing"); AD-9 ·
**PRD:** FR-181, FR-182, FR-190

AD-9 templates the App Group identifier on the Builder's Team ID — correct, and the right instinct.
But FR-181 makes that one instance of a broader cross-target contract: **every** bundle identifier,
App Group **and keychain access group** is templated on `$(DEVELOPMENT_TEAM)`, no literal
team-qualified identifier is committed, an entitlement naming a group outside the signing team's
prefix **fails signing rather than falling back**, and `CODE_SIGN_STYLE = Manual` with a pinned
profile specifier in a committed xcconfig. FR-190 adds that the Watch app's
`CFBundleShortVersionString` must equal the host app's or the build fails, single-sourced from one
xcconfig. These are consistency invariants across app, Watch app and every extension — exactly spine
material — and they currently rest on a two-word Stack row.

---

## Checklist scorecard

| # | Checklist item | Result |
|---|---|---|
| 1 | Fixes the real divergence points for features | **Partial.** Domain core and device edge: yes. Driver lifecycle (F-1), Watch unit (F-3), link payload (F-4), descriptor vocabulary (F-8), upload queue (F-10), mode signal (F-13): no. |
| 2 | Every Rule enforceable and preventing its divergence | **Mostly yes.** AD-5, AD-7, AD-11, AD-12 are exemplary. The Logging convention is a wish (F-6). AD-1's "or an adapter module" is not a rule (F-14). AD-3 contradicts FR-38 (F-9). Four ADs assert CI without naming a host (F-16). |
| 3 | Anything Deferred that lets units diverge | **Yes — three rows.** "Per-Driver protocol detail" hides C-1 (F-1). "Observability and crash reporting" drops SI-9's mechanism (F-6). "Backend wire schema" absorbs C-5's state machine (F-10). |
| 4 | Named technology verified-current and a real fit | **Yes on currency, one factual error.** GRDB 7.11.1 and swift-crypto 4.5.1 confirmed latest today; AD-8's fork rationale confirmed accurate against upstream. The SQLCipher acquisition mechanism is wrong (F-5). |
| 5 | Covers the PRD's capabilities, C-1..C-5 and OQ-45 | **C-1 absent (F-1). C-2 not carried — resolved in the PRD but its derivation rule is a live cross-unit invariant and appears nowhere. C-3 under-scoped (F-4). C-4 adequately seeded by AD-6. C-5 deferred too far (F-10). OQ-45 handled honestly but ungated (F-12).** |
| 6 | Every dimension decided, deferred or an open question | **No.** Build composition and configurations are wholly silent (F-2) — the operational/environmental envelope gap. Also silent: Backend-optional mode (F-13), composition root (F-14), identifier/signing contract (F-18). The document has no open-questions surface at all (F-12). |
| 7 | SI-1..SI-12 each have a mechanism | **8 of 12.** SI-5, SI-7, SI-8, SI-11 have none (F-7); SI-9's is a convention row, not a mechanism (F-6). |

### On C-2
The PRD marks C-2 resolved, so it is not a contract gap — but the *resolution* is a cross-unit
invariant the spine should carry and does not: the **set of active Driver ids** is what persists,
Capability slots are **derived** from it by a total deterministic function with a stable id tiebreak,
and **no slot table exists**. Three units depend on that (Drivers, `DomainCore`, `AppFeature`) and
FR-27 leans on it further — a gated-off Driver leaves its persisted slot entries intact and restores
on re-enable. One sentence in an AD; without it, someone will build the slot table the PRD deleted.

---

## Suggested fix order

1. **F-1** (C-1 Driver lifecycle) — blocks P1 and unblocks the most parallel work.
2. **F-2** (build composition) — cheap, and three safety invariants rest on it.
3. **F-3 + F-4** (Watch unit + link envelope) — one revision; blocks P2.
4. **F-7** (SI-5/7/8/11) and **F-6** (logging) — make the `binds:` claim true.
5. **F-5** (GRDB fork) — a factual correction plus AD-6's missing encryption canary.
6. **F-8, F-9, F-10, F-11, F-13, F-14** — each is one AD or one clause.
7. **F-12** — add the Open Questions section; it is where OQ-45, OQ-32 and any residue land.
8. Lows as editorial cleanup.

Estimated addition: five to seven ADs and roughly a dozen clauses. The document should still fit on
four pages, and it should. Nothing above asks it to become a solution design.

---

## Sources consulted for version verification

- [GRDB.swift latest release (v7.11.1, 2026-06-18)](https://api.github.com/repos/groue/GRDB.swift/releases/latest)
- [GRDB.swift Package.swift at v7.11.1](https://raw.githubusercontent.com/groue/GRDB.swift/v7.11.1/Package.swift)
- [Support SQLCipher using package traits — groue/GRDB.swift#1708](https://github.com/groue/GRDB.swift/pull/1708)
- [GRDB v7.10.0, Android, Linux, Windows, and SQLCipher+SwiftPM — Swift Forums](https://forums.swift.org/t/grdb-v7-10-0-android-linux-windows-and-sqlcipher-swiftpm/84754)
- [swift-crypto latest release (4.5.1, 2026-07-16)](https://api.github.com/repos/apple/swift-crypto/releases/latest)
- [swift-crypto Package.swift (products: Crypto, _CryptoExtras, CryptoExtras — CryptoBoringWrapper not exported)](https://raw.githubusercontent.com/apple/swift-crypto/main/Package.swift)
