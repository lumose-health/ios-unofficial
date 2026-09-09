# Parity Review — `prd.md` against `android-unofficial`

**Question asked:** what does the Android app do that the iOS PRD neither requires (§5 FR) nor records as a deliberate loss (§7 PL/PD/PA)?

**Method.** Direct walk of the Android source tree — `app/src/main/java/com/glycemicgpt/mobile/**` (presentation, domain, data, service, plugin, wear, di, logging), `wear-device/`, `watchface/`, `plugins/`, `.github/workflows/`, `docs/`, `contract/`, top-level policy files — sampling the capabilities a user or maintainer would notice if they vanished, plus everything safety-relevant. Every candidate was then grepped against the PRD several ways before being called a gap. The 14 `research/*.json` subsystem analyses were used as an index only; every finding below is cited to Kotlin/XML/YAML source, not to the research files.

**Concurrency note.** `prd.md` was edited by another process during this review (6381 → 6412 lines). Every finding was re-verified against the 6412-line file; line numbers below are from that version.

**Out of scope by instruction** (already recorded, not reported here): no localization in the Android client; no deep links / AppWidgetProvider / TileService / ShortcutManager; `plugins/example` not a built module; runtime plugin loading replaced by compile-time drivers; no custom watch face on watchOS; calibration-target Capability removed; APNs deferred; Critical Alerts unobtainable.

---

## Verdict

The parity claim **holds for the app itself and breaks down at the edges** — inside the two shipped Drivers, and across the release and dependency-bot pipeline.

Where the PRD is good it is exceptional. The Alert Floor's nine gates port in exact order; the wake-lock triple (20 / 15 / 2 min), the wire codec byte sizes (13/21/12), the freshness boundaries, `18.0156`, `RELEASE_SIGNER_SHA256`, the `versionCode` formula, `DEV_RUN_NUMBER_OFFSET = 500`, the vibration waveform, the 65,536-char manifest cap, the plugin sandbox's seven allowlisted services, the Tandem reconnection ladder verbatim, the Simulated Driver's synthetic-data maths, the 1280 px / 5 MiB / quality-90→40 image ladder, every CI tool pin and both SHA-256 digests — roughly a hundred quoted values were checked and only those listed below diverge. The PRD also invents nothing: it claims no gate, no dependency and no Android behaviour that does not exist, apart from the specific rows called out here.

But the Ledger is **not complete**, and the gaps are not evenly distributed. Three findings are load-bearing enough to block sign-off:

- A **clinical-numbers defect** — Android keeps two separate glucose threshold sets and the PRD has only one, which changes what Time in Range reports (C1).
- An **unreachable-path defect** — onboarding's Backend-optional escape hatch is specified on a stage the user cannot reach (C2).
- A **safety-gate inversion** — the PRD states three times that no Medtronic sensor-validity gate exists and one must be found, when Android ships two (C3).

All three are the exact failure the Parity Ledger exists to prevent — not "we chose to drop it", but "nobody noticed it was there". C3 is the sharpest instance: the Ledger row written to stop a decode gate being dropped silently is itself dropping two decode gates silently, one Driver over.

Below the Criticals, the pattern is consistent: **the Medtronic Driver's protocol-safety layer is largely unrepresented** (H3–H5, M18–M21) and **the release pipeline's privileged-access controls are absent** (H6, H7, H9–H14). Both are areas where a defect is invisible to a user until it is severe.

---

## Counts

| Severity | Silent drops (MISSING) | Misstatements (MISSTATED) | Total |
|---|---|---|---|
| Critical | 0 | 3 | **3** (C1–C3) |
| High | 14 | 4 | **18** (H1–H18) |
| Medium | 28 | 7 | **35** (M1–M35) |
| Low | 25 | 16 | **41** (L1–L41) |
| **Total** | **67** | **30** | **97** |

M14 and M9 are each both a drop and a misstatement; each is counted once, under the column that better describes the fix.

Findings cluster by subsystem. The four subsystems ported first — dashboard, alerting, data, wrist — are the cleanest. The **two shipped Drivers** and the **release/bot pipeline** carry the heaviest concentration, and all three Criticals involve a claim about Android that source contradicts.

---

## CRITICAL

### C1 — MISSTATED — The PRD collapses Android's **two** glucose threshold sets into one

**Android.** Two deliberately distinct stores, two endpoints, two consumer sets:

| | Store | Endpoint | Consumers |
|---|---|---|---|
| **Display target range** | `GlucoseRangeStore` | `GET /api/settings/target-glucose-range` | hero severity banding, chart grid lines, **Time in Range buckets**, target caption, **watch glucose banding** |
| **Alert thresholds** | `AlertThresholdStore` | `GET /api/settings/alert-thresholds` | **Alert Floor only**, its arming gate, the Coverage Claim, the Settings editor |

- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/data/local/GlucoseRangeStore.kt` — separate `SharedPreferences` file `"glucose_range"`, defaults 55/70/180/250, own `lastFetchedMs`.
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/data/local/AlertThresholdStore.kt:28-41` states the rule verbatim in source: *"These are deliberately distinct from `GlucoseRangeStore` (the **display** target range): a safety floor firing at display-range values instead of the user's real alert thresholds would alarm at the wrong glucose levels and desync from the server."*
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/home/HomeViewModel.kt:453-458` — `thresholdsFromStore()` reads `glucoseRangeStore`; `:308-320` feeds exactly those four values into `repository.observeTimeInRange(...)`.
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/AlertFloor.kt:129-135` — `classify()` reads `alertThresholdStore`.
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/PumpPollingOrchestrator.kt:304-325` — the watch gets `glucoseRangeStore` values for banding, and the source comment contrasts the two explicitly: *"One classification feeds both consumers, off the synced server alert thresholds (GLY-115) **rather than the display range**."*

**PRD.** The Glossary (prd.md:112) defines only **Alert Threshold**. There is no term, no FR and no ledger row for the display target range, and every display FR attributes banding to the alert set:

- FR-47 (prd.md:885): *"…else urgent-high colour, **against the Alert Threshold set**"*
- FR-52 (prd.md:950): *"Dashed grid lines … at the low, high and urgent-high **Alert Threshold** values"*
- FR-58 (prd.md:1027, 1032): bucket comparisons and the `"Target: <low>-<high>"` footer
- FR-124 / FR-125 (prd.md:2269, 2275-2280): wrist banding, and "**Alert Threshold** sanitization on the wrist"

Meanwhile FR-40 (prd.md:797) reconciles "glucose range" *and* "Alert Thresholds" as separate objects, and FR-155 (prd.md:2757) validates "target range" and "Alert Thresholds" under **different** rules. So the PRD fetches and validates an endpoint that **nothing in the document consumes**. `grep -i "target range"` returns exactly one hit in 6412 lines, and it is that orphan validation bullet.

**Impact.** A user whose target range is 80–140 and whose alert thresholds are 70–180 gets a materially different Time in Range percentage, different hero colours and different chart grid lines on iOS than on Android. TIR is a clinical number people take to appointments. It also invalidates OQ-20's premise (prd.md:1138): Android never colours from *alert* defaults, because banding comes from a different store that has always-populated defaults and no provenance concept at all.

**Where it should live.** A new Glossary term (**Target Range**), ownership assigned in FR-47 / FR-52 / FR-58 and FR-124 / FR-125, with FR-40 and FR-155 pointing at it; plus a PD row recording that the two sets exist, are fetched separately, and must not be unified.

---

### C2 — MISSTATED — The Backend-optional escape hatch is placed on a stage the user can never reach

**Android.** `"Don't run a server?"` + `"Use without a server (BLE-only)"` (`testTag = onboarding_continue_without_server`) live inside **`ServerSetupPage`** — the Backend stage, index 3.

- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/onboarding/OnboardingPages.kt:3-10` — `WELCOME=0, FEATURES=1, DISCLAIMER=2, SERVER=3, LOGIN=4`
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/onboarding/OnboardingScreen.kt:130-140` — `PAGE_SERVER -> ServerSetupPage(… onContinueWithoutServer = viewModel::continueWithoutServer)`
- Same file `:636-653` — the label and the `TextButton`, inside `ServerSetupPage`

**PRD.** FR-164 (prd.md:3078): *"The **Sign-in stage** carries the label 'Don't run a server?' and a control reading 'Use without a server'…"* — while FR-159 (prd.md:2931) states: *"The **Backend stage's 'Next' is disabled until a connection test has succeeded** in this session."*

Read together, a user with no Backend cannot leave stage 3, and the only control that would put them into Backend-optional mode sits on stage 4. As specified, Backend-optional mode is unreachable through onboarding.

**Impact.** UJ-3 and UJ-4 — the product's headline journeys — are blocked. Backend-optional mode is described throughout the PRD as *"a first-class supported mode, not a degraded state"*, and this is the only entry into it for a new install.

**Where it should live.** FR-164's first bullet must name the **Backend** stage (index 3), matching FR-159's own stage indexing.

---

### C3 — MISSTATED — "A Medtronic equivalent of the sensor-validity gate must be identified" — Android already ships two

**PRD claim, in three places, verbatim:**
- FR-32 notes (prd.md:766): *"A Medtronic equivalent of the `egvStatusId` gate **must be identified** before that Driver leaves Beta."*
- PD-41 (prd.md:5780): *"A Medtronic equivalent of the validity gate **must be identified** before that **Driver** leaves Beta"*
- OQ-7 (prd.md:6246): same sentence.

**Actual — two independent, shipped, safety-relevant Medtronic sensor-validity gates:**

1. **History path — sentinel set.** `android-unofficial/plugins/shipped/medtronic/src/main/java/com/glycemicgpt/mobile/ble/messages/MedtronicHistoryParser.kt:196-197`:
   ```kotlin
   /** Sensor-glucose sentinel values that are not real mg/dL (`SGMeasurementData.__str__`). */
   val SG_SENTINELS = setOf(0x0301, 0x0303, 0x030D)
   ```
   applied at `:509-512`, **before** the Safety-Limits bound check:
   ```kotlin
   if (mgDl in SG_SENTINELS) return@mapNotNull null
   if (mgDl < limits.minGlucoseMgDl || mgDl > limits.maxGlucoseMgDl) return@mapNotNull null
   ```
2. **Live-read path — SFLOAT sentinel rejection.** `android-unofficial/plugins/shipped/medtronic/src/main/java/com/glycemicgpt/mobile/ble/read/CgmReader.kt:69-72`:
   ```kotlin
   if (!measurement.glucoseMgDl.isFinite()) {
       throw MedtronicReadException("SG is a non-finite SFLOAT sentinel (no value)")
   }
   ```

Only the **third** gate is genuinely outstanding, and Android names it precisely rather than leaving it unidentified — `CgmReader.kt:67-68`:
```kotlin
// TODO(48.C2/F): gate on the sensor-status annunciation (CgmMeasurement.status) so a sensor in
// warm-up or error doesn't surface a misleading SG.
```

**Impact.** The PRD collapses "one of three gates is a known TODO" into "no gate exists", which converts **two shipped safety gates into work nobody is required to port**. Both catch exactly the failure PD-41 exists to name: a sentinel that lands inside 20–500 renders at hero scale, in a severity colour, Fresh, and alertable, with nothing else in the product able to detect it (SI-2). `0x0301` = 769 decimal is outside the bound and would be caught anyway, but the sentinel check runs first by design and the SFLOAT path has no bound backstop at all — a garbled `NaN` compared against `20..500` is false in both directions.

**Where it should live.** FR-32 consequences alongside the two Tandem gates; PD-41's "what" column; FR-36 Trace-Replay fixtures; and OQ-7's closing sentence, which should read that two gates exist and the annunciation gate is the outstanding one.

---

## HIGH

### H1 — MISSING — Sign-out's other three effects: it stops Pump monitoring, resets onboarding, and re-gates the safety acknowledgement

**Android.** `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/settings/SettingsViewModel.kt:526-536`:

```kotlin
fun logout() {
    PumpConnectionService.stop(appContext)
    authRepository.logout(viewModelScope)
    appSettingsStore.onboardingComplete = false
    ...
    _navigateToOnboarding.trySend(Unit)
}
```

`NavHost.kt:205-211` consumes that with `popUpTo(0) { inclusive = true }`. Because `onboardingComplete` is now false, `OnboardingViewModel.getStartPage()` (`android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/onboarding/OnboardingViewModel.kt:259-267`) returns `WELCOME`, so the signed-out user **re-runs the unskippable safety acknowledgement**.

**PRD.** FR-167 (prd.md:3132-3157) enumerates what sign-out clears and preserves and says nothing about the navigation destination, back-stack clearing, resetting onboarding completion, re-consent, or **stopping Pump monitoring**. FR-159 states the start-stage rule correctly (`Backend stage only when a saved URL exists AND onboarding was previously completed`) but never says sign-out is what flips that second condition. Grepped `sign-out` × `onboarding` / `logout` / `navigate` — no hit.

**Impact.** Both halves are safety-relevant. Whether the Alert Floor keeps running after sign-out is a coverage question, and whether the user re-consents to the disclaimer is a regulatory-posture question. Silence means an implementer picks either answer.

**Where it should live.** New consequences on FR-167, cross-referenced from FR-63 and FR-159. If iOS deliberately keeps the user in Settings with monitoring alive — defensible, since Backend-optional mode is first-class here — that is a **PD row**, not silence.

---

### H2 — MISSING — The alert stream's reconnect ladder, stability gate and auth-rejection back-off

**Android.** `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/AlertStreamService.kt`:

- `:49-50` — `MAX_BACKOFF_MS = 60_000L`, `STABLE_CONNECTION_MS = 10_000L`
- `:354-357` — `backoffMs = minOf(1000L * (1 shl attempt.coerceAtMost(6)), MAX_BACKOFF_MS)` → 1s, 2s, 4s, 8s, 16s, 32s, then 60s flat
- `:283-286` — `if (code == 401 || code == 403) { reconnectAttempt.set(5.coerceAtLeast(attempt)) }` — an auth rejection jumps the ladder to ≥32 s so a rejected token cannot hot-loop the Backend
- `:303-312` `resetBackoffIfStable()` — backoff resets to 0 **only** after the stream has been open ≥10 s **and** an event arrived; the source comment says this exists "to prevent rapid connect/fail cycles from keeping backoff at 0"
- `:133-140` — a redundant `onStartCommand` is ignored while already CONNECTED, explicitly because otherwise it "would flash 'server alerts paused' for the seconds the reconnect takes"
- `:367-370` — a woken reconnect coroutine bails if another path already restored a CONNECTED stream

**PRD.** FR-157 (prd.md, §5.8) says *"Stream transport parameters are **preserved**: 30-second connect and 75-second read timeout…"* and stops there. Nothing states the ladder, the 60 s ceiling, the 10 s stability precondition, the 401/403 escalation or the already-connected guards. The single `grep` hit for "backoff ladder" is FR-141's unrelated upload-retry disclaimer.

Contrast §5.1 FR-13, which reproduces the **BLE** reconnect ladder in full — so the omission is specific to the alert stream, not a general policy of leaving reconnection to the platform.

**Impact.** `AlertStreamStateHolder` drives `isAlertingDegraded`, which is **gate 1 of the Alert Floor** (FR-71) and state (1) of the FR-83 Coverage Claim selector. Without the stability gate, a flapping Backend pins backoff at 0 and the Coverage Claim oscillates Backend Active ↔ Not Watching. Without the already-connected guard, every Settings open flashes "server alerts paused". Both are precisely the claim-flapping FR-83's ticker and copy exist to prevent.

**Where it should live.** FR-157 (which already owns "transport parameters"), with the claim-flapping consequence cross-referenced from FR-83.

---

### H3 — MISSING — Medtronic's entire history-timestamp model

**Android.** `android-unofficial/plugins/shipped/medtronic/src/main/java/com/glycemicgpt/mobile/ble/messages/MedtronicHistoryParser.kt:182-189, 200-203, 438-461, 470-497`. Medtronic history records carry **only a relative offset**. Absolute time resolves against the most recent `NGP_REFERENCE_TIME` record, which the pump stores as **naive local wall-clock with no timezone or DST field** and is therefore anchored in `ZoneId.systemDefault()`. Records seen before any reference record are **dropped and counted**, never mis-timestamped. Annunciation timestamps use a separate `2000-01-01T00:00:00Z` epoch.

**PRD.** Greps for `reference time`, `NGP`, `local wall-clock`, `systemDefault`, and `2000` as an epoch → **zero**. The PRD names only the Tandem epoch `1199145600` as a Safety Constant (SI-4, FR-217) and requires DST tests for that one alone.

**Impact.** Getting this wrong shifts **every** Medtronic history timestamp by the local UTC offset — which corrupts Freshness Tier, alert age, the ±5-minute glucose-at-event window, TIR period boundaries and day-boundary analysis simultaneously. It is a second pump-time epoch problem, structurally harder than Tandem's (which is a fixed constant), and it is unrepresented.

**Where it should live.** FR-32 consequences or a Medtronic entry alongside the Tandem epoch in the Safety Constant set (SI-4, FR-217).

---

### H4 — MISSING — IEEE-11073 SFLOAT/FLOAT reserved-code rejection on insulin values

**Android.** `android-unofficial/plugins/shipped/medtronic/src/main/java/com/glycemicgpt/mobile/ble/messages/MedtronicCodec.kt:99-103, 124-141, 177-182` returns `NaN`/`±Infinity` for the five reserved SFLOAT mantissa codes (`0x07FE, 0x07FF, 0x0800, 0x0801, 0x0802`) *specifically because upstream does not*, and every consumer gates on `isFinite()` (`CgmReader.kt:70-72, 99`; `MedtronicHistoryParser.kt:562, 622`). The KDoc states why: *"a reserved/garbled insulin field therefore decodes to a bogus finite number… callers gate it with `isFinite()` + a physiological range check… so a sentinel never surfaces as a real reservoir/IOB/basal/bolus amount."*

**PRD.** Greps for `SFLOAT`, `medfloat`, `IEEE`, `11073`, and `non-finite` in a Driver context → **zero**.

**Impact.** This is the same failure class the PRD elevates to a pinned FR-32 consequence for Tandem's `egvStatusId`, applied to **insulin** values — IOB, reservoir, basal and bolus. FR-138 requires a finiteness check at the *storage* boundary, which catches a `NaN` but not the "bogus finite number" the codec exists to prevent. SI-7's delivered-insulin honesty has no other guard here.

**Where it should live.** FR-32 consequences, with FR-206 replay fixtures.

---

### H5 — MISSING — Medtronic per-pump E2E-CRC feature-bit reads

**Android.** `android-unofficial/plugins/shipped/medtronic/src/main/java/com/glycemicgpt/mobile/ble/read/CgmFeature.kt:26-27, 36-64` (`E2E_CRC_BIT = 1 shl 12`, the `0xFFFF` chicken-and-egg sentinel, and the fix for upstream's always-validate bug), `IddFeatures.kt:33-34, 81`, `IddStatus.kt:250-261` (`stripIddE2e`), consumed at `CgmReader.kt:50-56` and `HistoryReader.kt:74-81`. Every one of those files states the same rule: **read the flag per pump, never hardcode 780G** — 680G and 770G must not be assumed to use the CRC.

**PRD.** Greps for `E2E`, `CRC-16/CCITT`, `feature bit` → **zero**. Tier 2's generic *"framing and CRC"* does not encode the per-pump rule.

**Impact.** Hardcoding either way is a hard failure: assume CRC present and every valid record from a 680G/770G is rejected; assume absent and corrupt records are accepted on a 780G.

**Where it should live.** FR-32 consequences or PL-4's neighbourhood; FR-206 fixtures per model.

---

### H6 — MISSING — The `release-gated` GitHub Environment and its required-reviewer pause

**Android.** Seven jobs across three workflows declare `environment: release-gated` — `release.yml:28, 58, 134, 318`; `changelog-pr.yml:24, 331`; `sync-main-to-develop.yml:29`. The comments are explicit: *"The RELEASE app key exists only as a secret in this approval-gated environment (no plain org/repo copy)"* (`release.yml:26-28`) and *"it pauses for a required-reviewer approval on every run"* (`release.yml:53-58`).

**PRD.** Greps for `release-gated`, `environment:`, `required-reviewer` → **zero**.

**Impact.** This is the human pause on the pipeline that mints privileged tokens and pushes to `main`. Under fork-and-build the PRD already argues (settled decision 6, prd.md:37) that the pipeline is a supported surface *because* Builders load their own App Store Connect key into a run executing project workflow code. The environment gate is the control that makes that argument hold, and as specified the iOS promotion pipeline has no equivalent.

**Where it should live.** FR-183 / FR-185 (custody within a run) and FR-192 (promotion), with §10 recording the substitution.

---

### H7 — MISSING — The four-App least-privilege token split

**Android.** Four distinct GitHub Apps with separate secret pairs, each scoped to one class of privileged write: `CI_APP_ID` (`ci.yml:52`), `RELEASE_APP_ID` (`release.yml:39, 67, 151, 507`), `MERGE_APP_ID` (`changelog-pr.yml:46, 340`; `sync-main-to-develop.yml:40`), `RENOVATE_APP_ID` (`regen-gradle-lockfiles.yml:140-144`, with `permission-contents: write`) — all layered on `permissions: contents: read` or `{}` at workflow level.

**PRD.** The only two App-token mentions concern *not* minting one; FR-222 mints one for the docs dispatch. No requirement that release, changelog or sync writes use scoped App tokens rather than the ambient `GITHUB_TOKEN`.

**Where it should live.** FR-183, FR-192, FR-222 and §10.2.

---

### H8 — MISSING — MEDICAL-DISCLAIMER.md loses three whole sections

**Android.** `android-unofficial/MEDICAL-DISCLAIMER.md`:
- `## Health Data Processing` (`:31-43`) — the enumerated processed data classes, *"AI analysis is performed by the backend you point this app at, not on the phone"*, and *"It is the user's responsibility to review the data-handling policy of any provider that will receive their health data before configuring it."*
- `## AI Limitations` (`:45-54`) — four named LLM failure modes (**hallucinate / misinterpret data / provide outdated information / lack context**) and *"Never act on AI suggestions without consulting your healthcare team."*
- `## Critical Warnings` items **1, 2, 3 and 5** (`:58-66`) — including *"severe hypoglycemia, diabetic ketoacidosis (DKA), or other life-threatening conditions"* and *"contact your healthcare provider or emergency services immediately."*

**PRD.** FR-234 carries warning item **4** only. `hallucinat` hits only FR-160 — the *in-app* onboarding card — which explicitly places *"the wording and hosting of MEDICAL-DISCLAIMER.md"* out of scope. `DKA` and `emergency services` → **zero**.

**Impact.** The published disclaimer is the document a regulator, a clinician or a worried family member reads. Three of its four substantive sections have no owning requirement, and the AI-limitations section is the only place the product tells a user in writing that the model can be confidently wrong.

**Where it should live.** FR-234, which currently under-specifies the document it owns.

---

### H9–H15 — MISSING and MISSTATED in the release and dependency-bot pipeline

| # | Finding | Type | Source | Home |
|---|---|---|---|---|
| **H9** | **FR-194's auto-merge allowlist admits "workflow files"; Android forbids them.** Actual allowlist is `^((.*/)?build\.gradle\.kts\|(.*/)?gradle\.lockfile\|gradle/libs\.versions\.toml\|settings\.gradle\.kts\|settings-gradle\.lockfile)$` — no workflow file — and `renovate.json5:79` routes every Actions bump including digest re-pins to manual review. FR-194's own next-but-one bullet says *"Nothing touching … CI action pins … can auto-merge."* The FR contradicts itself and Android. | MISSTATED | `renovate-file-scope.yml:64`; `renovate.json5:79` | FR-194 |
| **H10** | **FR-194's allowlist ∩ gate-coverage rule is unsatisfiable for four of its entries.** `Gemfile`, `Gemfile.lock`, `Brewfile` and `mise.toml` are in neither the `deps` filter (FR-201) nor the `ios` filter (FR-208), so every bot PR touching them fails the guard permanently. `Gemfile.lock` matters most — FR-193 calls it *"the second real lockfile in an iOS repository and is not optional"*. Android has no such hole: every entry in its allowlist is matched by `GATE_RE`, with "Keep in sync with…" headers on both. | MISSTATED | `renovate-file-scope.yml:63-64, 74-75` | FR-194, FR-201 |
| **H11** | **Renovate's expedited CVE channel is absent.** `osvVulnerabilityAlerts: true` and `vulnerabilityAlerts: {enabled: true, labels: ["security","dependencies"]}`, commented *"both bypass the soak + limits for real CVEs."* FR-194 carries `minimumReleaseAge: "7 days"` and the rate limits but no bypass — so as written a critical advisory sits behind a 7-day soak in a medical monitoring app. | MISSING | `renovate.json5:39-42` | FR-194 |
| **H12** | **Every bot dependency PR would fail DCO as specified.** FR-192 says *"Every bot commit is DCO signed off (`git commit -s` / `--signoff`)"* — but `--signoff` is a git-CLI flag the dependency bot's commit never passes through. Android solves it in bot config: `gitAuthor` + `commitBody: "Signed-off-by: {{{gitAuthor}}}"`. Separately, `baseBranchPatterns: ["develop"]` is unrepresented, so the bot would open PRs against `main`, bypassing FR-192's own promotion topology. | MISSING | `renovate.json5:5-7, 16-23` | FR-194, FR-192 |
| **H13** | **FR-197's blanket `concurrency: <name>-${{ github.ref }}` with `cancel-in-progress: true` contradicts Android and is a functional regression.** Four workflows deliberately do the opposite with inline reasons — `release.yml:8-10`, `changelog-pr.yml:12-16` (*"two same-day promotions would otherwise both build the changelog/<DATE> branch and race the force-with-lease push"*), `sync-main-to-develop.yml:14-16`, `dev-pre-release.yml:26-28`. The three `pull_request_target` gates key on **PR number**, not `github.ref`. Applied literally the rule cancels release, changelog and sync runs mid-push. | MISSTATED | `release.yml:8-10`; `changelog-pr.yml:12-16`; `sync-main-to-develop.yml:14-16`; `dev-pre-release.yml:26-28` | FR-197 |
| **H14** | **FR-190's CHANGELOG section-visibility claim is fabricated.** *"CHANGELOG section visibility carries over: `feat`, `fix`, `perf`, `docs`, `refactor`, `ci` visible; `chore`, `test` hidden."* `release-please-config.json` contains **no `changelog-sections` key**; `grep -rn "changelog-sections"` over the repo returns zero. There is nothing to carry over — release-please defaults apply — and the sentence would be transcribed into the iOS config as verified fact. | MISSTATED | `release-please-config.json:1-21` | FR-190 |
| **H15** | **The three ADRs vanish.** `docs/adr/{0001,0002,0003}` plus `_meta.json`. Greps for `ADR`, `adr/`, `architecture decision record` → zero; FR-220's eight-row section table has no `adr/`. Substance survives partly in FR-214/215/216, but three recorded decisions do not: ADR-0001's forward rule (*"introduce a `/v2` sibling and keep the old path until the shipped app fleet has aged out — do not mutate an unversioned path in place"*), ADR-0002's directional limit (*"It does **not** establish newer app → older backend compatibility"*) plus the backend-side cross-cadence obligation, and ADR-0003's reasoned rejection of a full DTO↔spec structural diff. | MISSING | `docs/adr/**` | FR-220 |

---

### H16 — MISSING — `docs/dev/plugin-architecture.md` (803 lines) has no successor requirement

**Android.** The Driver/plugin SDK developer reference: three-layer architecture, module setup, a minimum viable plugin, every SDK contract, threading rules, error handling, the Capability table, the descriptor vocabularies, the event bus, DI registration, the safety invariants and `PLUGIN_API_VERSION` semantics.

**PRD.** FR-225's Driver contribution path is five procedural bullets. The PRD cites this file **only** to say *"port from the Kotlin source, never from the Android documentation"* — which fixes an accuracy defect but not the page's disappearance. FR-220's `dev/` row is *"Contributing, the **Driver** contribution guide, security testing"*.

**Impact.** This is the largest document in the tree and the artifact **UJ-6** — "a contributor adds a Driver for an unsupported Pump" — actually depends on. Four further `docs/dev/` pages also lose their counterpart (see L-table).

**Where it should live.** FR-220's `dev/` section row and FR-225.

---

### H17 — MISSING — No community or support channel anywhere in the iOS documentation set

**Android.** `README.md:12, 87-89`; `CONTRIBUTING.md:342-345`; and every troubleshooting page ends in a "still stuck, ask here" pointer — `docs/troubleshooting/cant-pair-pump.md:96`, `docs/daily-use/connecting-medtronic-pump.md:73`.

**PRD.** Greps for `Discord`, `Discussions`, `community channel`, `support channel` → **zero**. FR-226 names only the two *private security* addresses, and FR-225 names only the conduct address.

**Impact.** Under fork-and-build the project receives no crash report and no device log (PL-71), so the user-initiated channel is the *entire* diagnostic path. The pages FR-220 and FR-237 require would terminate with nowhere to go.

**Where it should live.** FR-220, FR-225, FR-237.

---

### H18 — MISSING — GOVERNANCE.md and the project role model

**Android.** `GOVERNANCE.md:1-7` is a canonical pointer naming *"project roles and permissions, how contributors advance, decision-making and disputes, the funding and compensation model, branch protection, code ownership, and security governance"*, reinforced by `CONTRIBUTING.md:69-71` (Contributor / Committer / Maintainer / Project Lead) and `README.md:89`.

**PRD.** `GOVERNANCE.md` appears twice, both incidental — FR-212's CODEOWNERS roster and FR-192's doc-only path list. No FR requires it, states its content, or records the org-canonical relationship. FR-225 covers CONTRIBUTING and the Code of Conduct and skips roles entirely.

**Impact.** FR-212 gates trust-boundary files on "project-lead review" — a role the document set never defines.

**Where it should live.** FR-225.

---

## MEDIUM

### M1 — MISSING — The user-facing "Backend Sync" toggle has no owning FR

**Android.** A per-device Settings switch, default ON, that gates the entire outbound-queue drain while leaving the Backend URL and the enqueue path intact.

- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/data/local/AppSettingsStore.kt:91-96` — `backendSyncEnabled`, default `true`
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/BackendSyncManager.kt:211-228`:
  ```kotlin
  // Local queue hygiene runs BEFORE the drain gates: with sync disabled or no active
  // session … the enqueuer keeps writing, so the size bound must not depend on being
  // able to drain. … the bound doesn't need 3s granularity in a posture that can persist for weeks.
  val canDrain = appSettingsStore.backendSyncEnabled && authTokenStore.hasActiveSession()
  ```
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/settings/SettingsScreen.kt:1289-1330` — card title "Backend Sync", subtitle "Push pump events to GlycemicGPT server", hidden when no Backend is configured

**PRD.** "Backend sync control" appears exactly twice (prd.md:2857 and prd.md:3119), both times only as an item *hidden in Backend-optional mode*. No FR defines its existence, default or effect. FR-142 / FR-143 / FR-144 describe the drain as gated solely on Backend-configured plus an active session — an implementer reading only the FRs ships no such toggle, and the two visibility bullets dangle over a control that does not exist.

**Impact.** It is the only user control for "stop uploading my pump data" while keeping a Backend configured and signed in — a privacy affordance, and the one whose off-state deliberately fills the bounded queue.

**Where it should live.** FR-144 (drain gating) plus the Settings section FR (FR-166 / FR-175 region).

---

### M2 — MISSING — Phone→watch bolus-category-label channel and the wrist bolus-marker labels

**Android.**
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/wear/WearDataContract.kt:118-122` — `CATEGORY_LABELS_PATH = "/glycemicgpt/category_labels"`, `KEY_CATEGORY_LABELS_JSON`
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/wear/WearDataSender.kt:178-193` — `sendCategoryLabels(...)`; caller `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/settings/SettingsViewModel.kt:1160`
- `android-unofficial/wear-device/src/main/java/com/glycemicgpt/weardevice/presentation/GraphDetailActivity.kt:590-646` — `drawBolusMarkers` writes a text label above every diamond via `buildBolusLabel`: `"2.5u"`, `"0.5u Auto"`, or `"<units>u <categoryLabel>"`

**PRD.** FR-134 declares itself *"the single definition of **what** the Watch consumes"* and enumerates *"exactly, and only"* eight preferences — no label channel. FR-133 (prd.md:2383) lists the graph layers as *"… basal stepped area, IOB area, **Bolus markers**, and per-segment glucose colouring"* — markers, no per-marker text. FR-89 / PD-44 scope the label map to phone surfaces only.

**Accuracy note that should be carried into the fix.** The *category* half is a dead wire on Android: `WearHistorySerializer.BolusRecord` has no `category` field (`android-unofficial/app/src/main/java/com/glycemicgpt/mobile/wear/WearHistorySerializer.kt:75-82`) and `GlycemicDataListenerService.kt:118-127` constructs `BolusHistoryRecord` without one, so `categoryLabels[record.category]` always looks up `""`. What a Wear user actually sees is the **numeric units label** plus the `"Auto"` fallback. So the capability owed a home is the per-marker unit label; the category sync should be recorded as dropped rather than ported.

**Where it should live.** FR-133 (marker label content and its display-unit behaviour), plus one PL/PD row for the label channel.

---

### M3 — MISSING/incomplete — FR-53 clamps a chart label it never defines, and the legend's vocabulary is dropped

**Android.** `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/home/GlucoseTrendChart.kt:1004-1028` — each bolus marker draws a units label `"%.1fu"` at 8sp and, above it, a **type tag** at 7sp resolved through the category-label map, with plain `MEAL` deliberately skipped to reduce clutter (`bolusTypeLabel`, `:904-926`) and abbreviated by `if (label.length > 8) label.take(7) + "."` (`:929-934`). The legend (`:482-518`) emits per-basal-mode entries "Auto"/"Manual"/"Sleep"/"Exercise" and per-bolus-type entries under the same abbreviation rule.

**PRD.** FR-53 says only *"Marker labels clamp to a non-negative y"* — a positioning rule for labels the PRD never says exist, never gives content to, and never sizes. It covers legend *presence* (*"lists only series actually present"*) but not the entry vocabulary or the abbreviation rule. FR-53's **Out of Scope** punts "bolus category derivation, category labels" to 5.5 — but 5.5's FR-89 owns the *Insulin Summary card*, not chart markers, so the marker type tag falls between two FRs and lands in neither.

**Impact.** A user loses the ability to read what each bolus on the chart *was* and how much it was.

**Where it should live.** FR-53 consequences.

---

### M4 — MISSING — The bolus/basal category colour vocabulary is unspecified for the phone

**Android.**
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/theme/Theme.kt:782-801` — `BolusTypeColors`: Correction `#E91E63`, ManualCorrection `#FF5722`, Meal `#7C4DFF`, MealWithCorrection `#AB47BC`, Override `#FFA000`, Other `#78909C`; `colorForCategory` adds AI_SUGGESTED `#00BCD4`
- `GlucoseTrendChart.kt:103-108` — `ChartColors` basal: Automated `#00BCD4`, Manual `#78909C`, Sleep `#7E57C2`, Exercise `#FF9800`
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/home/InsulinSummaryCard.kt:44-45` — Basal `#38BDF8` / Bolus `#8B5CF6` for the stacked bar and legend

**PRD.** The document contains exactly **five** distinct hex values in total (`#22C55E`, `#334155`, `#EAB308`, `#EF4444`, plus the amber caution set `#FFF8E1`/`#5D4200`/`#B26A00`/`#3A2E07`/`#FCEFC7`/`#F2C14E`). FR-53 pins overlay *alphas* (0.06 / 0.15 / 0.6 / 0.4) but no hues. PL-34 names "bolus pink/orange/purple, basal teal/blue-grey" — but PL-34 is a **watchOS complication** loss row, not a phone requirement.

**Impact.** These colours are the shared visual key across three surfaces — chart markers, Recent Boluses type badges, Insulin Summary breakdown dots. Without them the cross-card correlation a user reads at a glance disappears, and the NFR-28 non-colour-encoding question is never asked of a vocabulary that is currently colour-only.

**Where it should live.** FR-53 (chart), FR-89 (breakdown rows and the basal/bolus bar), FR-91 (type badge).

---

### M5 — MISSING — Driver declaration sync to the Backend

**Android.** `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/home/HomeViewModel.kt:246-253, 549-598` — on every change of the active pump plugin, `PUT /api/settings/plugin-declarations` with `{pluginId, pluginName, pluginVersion, declaredCategories, categoryMappings}`, and `DELETE` when there is no plugin, no bolus-category provider, or an empty declared set (`GlycemicGptApi.kt:128-132`).

**PRD.** `grep` for `declaration`, `declaredCategories`, `plugin-declarations`, `categoryMappings` — zero hits. FR-214's endpoint/field-presence roster does not list it.

**Impact.** This is how the Backend learns the Pump's *native* category vocabulary. Without it the Backend-supplied label-override map that FR-89 / PD-44 depend on has nothing to key against, and a stale declaration persists after a Driver swap.

**Where it should live.** FR-40 (the reconcile pass) or FR-89, plus FR-214's Contract Pin endpoint list.

---

### M6 — MISSING — The `pump_info` hardware block on every upload

**Android.**
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/PumpPollingOrchestrator.kt:693-702` — `cacheHardwareInfoOnce()` runs in the slow loop, once per session
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/BackendSyncManager.kt:80-82, 266-286` — maps to `PumpHardwareInfoDto` with eleven fields (`serialNumber, modelNumber, partNumber, pumpRev, armSwVer, mspSwVer, configABits, configBBits, pcbaSn, pcbaRev, pumpFeatures`) and attaches it to **every** `PumpPushRequest`

**PRD.** FR-140's wire-quirks bullet enumerates the preserved payload shape (`bg_reading` carrying `iob_at_event`; Basal duplicating `pump_activity_mode` into `control_iq_mode`; Glucose Readings never enqueued) and omits `pump_info` entirely. FR-214's field-presence guard names no field of it. Zero PRD hits for `pump_info`, `serialNumber`, or any of the eleven names.

**Where it should live.** FR-140's wire-quirks bullet and FR-214's field-presence set.

---

### M7 — MISSING — Per-store reconcile staleness windows (only the 1-hour alert-threshold one is stated)

**Android** gates each on-load reconcile behind its own clock (`HomeViewModel.kt:217, 221, 234, 240, 243`):

| Object | Window | Source |
|---|---|---|
| Glucose range | **15 min** | `HomeViewModel.kt:601` `RANGE_REFRESH_INTERVAL_MS = 900_000L` (overriding the store's own 1 h at `GlucoseRangeStore.kt:69`) |
| Analytics config | **15 min** | `AnalyticsSettingsStore.kt:92` `STALE_THRESHOLD_MS = 900_000L` |
| Safety limits | 1 h | `SafetyLimitsStore.kt:77` |
| Pump profile | 1 h | `PumpProfileStore.kt:69` |
| Alert thresholds | 1 h | `AlertThresholdStore.kt:177` |
| Glucose unit / meal intelligence | **unconditional** | `HomeViewModel.kt:206-215` |

**PRD.** FR-80 states the 1-hour alert-threshold window and FR-40 correctly captures the unconditional glucose-unit reconcile. The other four windows appear nowhere; FR-40 reads as though pull-to-refresh reconciles everything ungated.

**Impact.** A naive port either re-fetches everything on every dashboard load — a battery and network cost NFR-6's budget does not account for — or never re-fetches at all.

**Where it should live.** FR-40 consequences.

---

### M8 — MISSTATED — FR-137 states the dedup conflict strategy for batch writes only

**Android.** The conflict strategy differs between single and batch inserts:

- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/data/local/dao/PumpDao.kt:109-113` — `insertCgm` = `REPLACE`, `insertCgmBatch` = `IGNORE`
- `PumpDao.kt:41-45` — `insertBasal` = `REPLACE`, `insertBasalBatch` = `IGNORE`
- `PumpDao.kt:64-68` — both bolus inserts = `REPLACE`
- Callers: `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/data/repository/PumpDataRepository.kt:183-204` — live single write vs history/Nightscout batch write

The real rule: a **live single-row write WINS** against an existing row at the same timestamp; a **batch** write (history backfill, Nightscout ingest at `plugin/nightscout/NightscoutDataMapper.kt:57, 87`) **loses**.

**PRD claim.** FR-137 (prd.md:2481): *"Batch writes of Glucose Readings and Basal readings keep the FIRST writer on collision; Bolus writes keep the LAST writer."* — half the rule. Since FR-137 is titled *"cross-source collision resolution"*, the omitted half is exactly the case it exists to pin: whether a Driver reading or a Nightscout row wins on the same millisecond depends on which **path** wrote second, not on which source it was.

**Where it should live.** FR-137.

---

### M9 — MISSTATED — PD-46 attributes the `coerceIn` clamp to the wrong fetch, and misses a fourth regime

**PRD claim.** PD-46: *"…and the **Backend-supplied alert-threshold path CLAMPS** each value with `coerceIn(20, 500)` before checking ordering."*

**Actual.** The alert-threshold path does **not** clamp — it validates ordering on the raw floats, rounds, range-checks and drops the whole response: `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/data/repository/AuthRepository.kt:421-461`. The `coerceIn(MIN_THRESHOLD, MAX_THRESHOLD)` clamp is in the **glucose-range** path: `HomeViewModel.kt:465-468` (constants at `:602-603`).

**A fourth regime the PRD misses.** The glucose range has **two** fetch implementations with different rules:
- `AuthRepository.fetchGlucoseRange` (`:340-363`) — rounds, requires 20–500, **strict** `ul < lo < hi < uh`, drops on failure
- `HomeViewModel.refreshGlucoseRange` (`:463-490`) — **truncates** with `toInt()`, **clamps** with `coerceIn`, and uses **non-strict** outer comparisons (`urgentLow > low || low >= high || high > urgentHigh`, so `ul == low` and `high == urgentHigh` are accepted)

FR-155 preserves only the `AuthRepository` variant.

**Where it should live.** PD-46's rationale text and FR-155's validation bullet. (The rationale is load-bearing — a reader uses it to decide which behaviour to port.)

---

### M10 — MISSTATED — PD-16 records two graph surfaces; Android has three, and the pinning defect belongs to the one PD-16 omits

**PRD claim.** PD-16 (prd.md:5755): *"**Two** graph surfaces with different Y clamps — 20/500 on the sparkline, 40/400 on the detail view — and a reading outside the axis **pinned to the boundary** … A reading below 40 was visible on one chart and **clipped off** the other."* Restated at prd.md:1129 and prd.md:2424.

**Actual — three surfaces, and the row describes the wrong one:**

1. **Phone chart** — `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/home/GlucoseTrendChart.kt:96-97` `CHART_Y_MIN = 40f`, `CHART_Y_MAX = 300f` — **fixed constants, not data-driven** — and `:714` `val clampedValue = reading.glucoseMgDl.coerceIn(yMin.toInt(), yMax.toInt())`. **This is the surface that pins.** PD-16 does not mention it at all, and 40/300 never appears in the row.
2. **Wrist sparkline** — `android-unofficial/wear-device/src/main/java/com/glycemicgpt/weardevice/complications/WatchGraphRenderer.kt:75-89` — `minY = min(values.min(), low-10).coerceAtLeast(20)`, `maxY = max(values.max(), high+10).coerceAtMost(500)`; `yPos` is **unclamped**. The 20/500 bound also **never binds**: every reading reaching the renderer has already passed `isValidGlucose(mgDl) == mgDl in 20..500` (`GlucoseDisplayUtils.kt:17`, enforced at `GlycemicDataListenerService.kt:170`), and `low` is sanitized to `40..200` so `low-10 >= 30`.
3. **Wrist detail** — `android-unofficial/wear-device/src/main/java/com/glycemicgpt/weardevice/presentation/GraphDetailActivity.kt:155-156, 280-296, 858-867` — `Y_MIN_DEFAULT = 40`, `Y_MAX_DEFAULT = 400`, likewise **unclamped** in `yPos`, and `drawGlucoseDots`/`drawGlucoseLine` (`:537-588`) cull on **x only**, with no `clipRect`.

So on the two wrist surfaces a 35 mg/dL reading is drawn **below** the 40 line — outside the plot rect, over the time-axis strip — not pinned to it and not clipped. The direction of the "clipped off" claim is inverted and the "false height from pinning" mechanism belongs to the phone chart, which the row omits.

**Impact.** The iOS fix (FR-52's one expanding axis) still closes the real defect, so no user behaviour is at risk. But the Ledger is the audit record of what Android did, and a maintainer checking "did we get the phone chart right?" finds the phone chart absent from the row that exists to answer that.

**Where it should live.** PD-16 and its two mirrored notes at prd.md:1129 and prd.md:2424.

---

### M11 — MISSTATED — "Wrist Alerts off disables all wrist alerting" is stricter than Android, in the unsafe direction

**Android.** `android-unofficial/wear-device/src/main/java/com/glycemicgpt/weardevice/data/GlycemicDataListenerService.kt:217, 231-233`:

```kotlin
val alertsEnabled = WatchDataRepository.watchFaceConfig.value.showAlert
...
if (!alertType.equals("none", ignoreCase = true) && alertsEnabled && rebuzz) vibrateForAlert(alertType)
```

`showAlert` gates **only the vibration**. The alert is still stored (`:224-229`), the Alerts complication still fires immediately (`:282-285`) and still renders amber/red (`AlertsComplicationDataSource.kt:105-112`), and `AlertsActivity` still displays it. Unlike IoB (`IoBComplicationDataSource.kt:38`) and Graph (`GraphComplicationDataSource.kt:49`), the alerts complication is gated by **no** preference.

**PRD claim.** FR-134 (prd.md:2401): *"The Wrist Alerts setting states its consequence in plain words: turning it off **disables all wrist alerting for lows and highs**."*

FR-117 separately says only IOB and the sparkline honour preferences, which is consistent with Android — but FR-134's absolute wording invites an implementation that also suppresses the coverage/alert indicator, which would take the SI-6 "not watching" cue off the wrist along with the alarm. Nothing in 5.7 or §7 says Android's toggle silences the buzz only.

**Where it should live.** FR-134 — bound the consequence to alert *delivery*, not to the coverage/alert indicator. If the wider suppression is intended, that is a PD row.

---

### M12 — MISSING — The wrist alert screen never renders the alert message body

**Android.** `android-unofficial/wear-device/src/main/java/com/glycemicgpt/weardevice/presentation/AlertsActivity.kt:137-145` renders `currentAlert.message` at `maxLines = 3`, fed from `KEY_ALERT_MESSAGE` (`WearDataContract.kt:39`, `GlycemicDataListenerService.kt:228`). This is the Backend- or floor-authored alert body — the only place the wrist carries the alert's actual prose.

**PRD.** FR-128 (prd.md:2325-2331) enumerates the alert screen exhaustively — glucose value gated on `20..500`, the always-visible age line, the `"as of <age> - data stale"` variant, the `"Not watching - check your phone."` line, the dismiss button — and never mentions the message body. FR-129 says the terminating notification "does not re-assert the alert value" but says nothing about body text. prd.md:1231 (*"The body is the alert message verbatim"*) is the **phone** notification, under FR-71.

**Impact.** A wrist alert showing only "Urgent Low" plus an age drops the one sentence explaining the episode.

**Where it should live.** FR-128 consequences.

---

### M13 — MISSING — Insulin Summary: the pump-native label parenthetical, the count header and the no-category footer

**Android.** `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/presentation/home/InsulinSummaryCard.kt`:
- `:250-257` — with the "Show Pump Labels" toggle on, each breakdown row renders `"<display label> (<pump-native name>)"`, built from `HomeViewModel.pumpLabelMap` (`HomeViewModel.kt:171-188`)
- `:228-233` — a `"<n> boluses"` header
- `:266-276` — a fallback footer `"<n> boluses (<m> corrections)"` when there is no category breakdown
- `:161` — TDD renders as `"%.1f U/day"`; legend values as `"%.1fU (%.0f%%)"`

**PRD.** FR-176 names the toggle *"Show Pump Labels (Pump-native category names beside display labels)"*, but FR-89 — which owns the card — never describes the rendering, the source of the native names, the count header, the fallback footer, or the TDD/legend formats.

**Where it should live.** FR-89 consequences.

---

### M14 — MISSING + MISSTATED — Battery-adaptive polling, and NFR-11's "matches Android exactly"

**Android.**
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/PumpConnectionService.kt:56-57` — `LOW_BATTERY_THRESHOLD = 15`, `CRITICAL_BATTERY_THRESHOLD = 5`; `:137-187` — an `ACTION_BATTERY_CHANGED` receiver sets `pollingOrchestrator.phoneBatteryLow`, **releases the wake lock below 5%**, and re-acquires the correct lock kind on recovery based on connection state
- `android-unofficial/app/src/main/java/com/glycemicgpt/mobile/service/PumpPollingOrchestrator.kt:185-186, 455` — `LOW_BATTERY_MULTIPLIER = 3`, applied via `effectiveInterval()` to **all three** poll loops (fast 15 s → 45 s, medium and slow 5 min → 15 min)

**PRD.** NFR-12 covers Low Power Mode and thermal state — both OS conditions the app *reports* — but nothing covers device battery percentage. `grep -i "LOW_BATTERY|battery percentage|15%"` → zero hits. Meanwhile **NFR-11 asserts**: *"Foreground poll cadence matches Android exactly; background cadence is opportunity-driven."* Android's foreground cadence is not a constant, so the assertion is true only of the ≥15% case.

**Impact.** Mostly structural on iOS — there is no app-scheduled background cadence to reduce — but the **foreground** loop does exist, NFR-11 explicitly claims parity for it, and PL-11/PL-12 cover the wake lock and the lost cadence generically without naming this behaviour. A reader cannot tell whether it was considered or dropped.

**Where it should live.** One clause in NFR-11 or NFR-12, or a PL row.

---

### M15 — MISSING — The Driver-facing debug-logger hook that feeds the debug console

**Android.** `DebugLogger` is a first-class member of the **public Driver contract**:

- `android-unofficial/plugins/pump-driver-api/src/main/java/com/glycemicgpt/mobile/domain/plugin/PluginContext.kt` — the platform hands each Driver exactly six services: `androidContext`, `settingsStore`, `credentialProvider`, **`debugLogger`**, `eventBus`, `safetyLimits` (plus `pluginId` and `apiVersion`)
- `android-unofficial/plugins/pump-driver-api/src/main/java/com/glycemicgpt/mobile/domain/pump/DebugLogger.kt` — `logPacket(direction, opcode, opcodeName, txId, cargoHex, cargoSize, parsedValue, error)` and `updateLastPacket(...)`, with a `Direction { TX, RX }` enum. The field set maps one-to-one onto FR-176's console rendering.

**PRD.** Five of Android's six Driver-facing services have owners — `settingsStore` → FR-29, `credentialProvider` → FR-18, `eventBus` → FR-34, `safetyLimits` → FR-32, `androidContext` → recorded as gone in PL-41, `apiVersion` → FR-21/PL-43. **`debugLogger` has none.** FR-176 specifies the console (capacity 100, the exact per-entry fields, the SI-9 constraints) but never says how a Driver emits a frame into it, so FR-205's Driver-protocol public-interface snapshot gate has no stated obligation to include the hook.

**Impact.** A contributed Driver (UJ-6) would have no way to feed the BLE debug console — the tool FR-176 exists to give contributors, and the one FR-225's Driver contribution guide points them at.

**Where it should live.** FR-176 (the producer side) or a new consequence on FR-21/FR-30 enumerating the Driver-facing service set, with FR-205 asserting it.

---

### M16–M35 — Drivers, CI, build and policy

| # | Capability + source | Type | Gap | Home |
|---|---|---|---|---|
| **M16** | `getFullHistoryLogs` full-sync variant — `plugins/pump-driver-api/.../capabilities/PumpStatus.kt:24-27`, `.../pump/PumpDriver.kt:40-43`, `PluginMetadata.kt:6` (*"v5: getFullHistoryLogs() overload added"*), `TandemBleDriver.kt:180-206`, `HISTORY_LOOKBACK_INDICES = 2000` at `:312` | MISSING | FR-146 covers the user-facing initial download and its 2-min/20-min bounds correctly, but not the **two-method Driver-API surface** nor the ~24 h lookback cap on the incremental path — which decides whether a gap longer than the window is fillable at all | FR-146, FR-30 |
| **M17** | Tandem bolus-category set and its derivation ladder — `plugin/TandemBolusCategoryProvider.kt:18-39` mapping `CONTROL_IQ, BG_FOOD, BG_ONLY, FOOD_ONLY, OVERRIDE, QUICK, UNKNOWN` → `AUTO_CORRECTION, FOOD_AND_CORRECTION, CORRECTION, FOOD, OVERRIDE, OTHER, OTHER`; `StatusResponseParser.kt:622-635` | MISSING | FR-89 specifies the *platform* vocabulary and the no-provider flag ladder — but Tandem **has** a provider, so the Driver-side ladder (source 7 → CONTROL_IQ, source 2 → OVERRIDE, meal ∧ corr → BG_FOOD…) is what actually assigns categories. Zero PRD hits for any of the seven names. (`QUICK` is declared but unreachable — a latent defect worth not porting) | FR-30 or FR-89 |
| **M18** | `MedtronicPumpModel` capability tier — `ble/read/MedtronicPumpModel.kt:32-72` (`HCL_FEATURE_SUPPORTED = 1L shl 28`, `SMART_SETTINGS_SUPPORTED = 1L shl 29`, `supportsSmartGuard`, `supportsAutoCorrectionBolus`) | MISSING | Model is inferred from IDD Features **capability bits, deliberately not the model string** (*"the marketing model name is not on the wire… substring-matching it is unreliable"*). FR-4 defines model detection for Tandem's advertised name only | FR-22, FR-32 |
| **M19** | Medtronic vendor UUID base — `ble/protocol/MedtronicProtocol.kt:34-38`: `MEDTRONIC_BASE_SUFFIX = "-0000-1000-0000-009132591325"`, commented *"The variant field is 0000, NOT the SIG 8000 — the real pump never finds vendor services advertised on the 8000 form, which silently broke pairing and every IDD/HAT/CM read (issue #844)"* | MISSING | Core Bluetooth takes full 128-bit `CBUUID`s, so the identical trap exists. PL-4 covers the advertisement payload and `0xFE82`/`0xFE81` correctly but not the base | FR-32 NFRs or PL-4 |
| **M20** | Medtronic CGM trend derivation — `ble/read/CgmReader.kt:90-116`: rate-of-change bucketed by the 780G manual's 1 / 2 / 3 mg-dL-per-min thresholds onto the 7-state enum, `UNKNOWN` when absent or non-finite | MISSING | FR-46/PD-42 own trend provenance for **Tandem** (icon id from HomeScreenMirror, opcodes 56/57 — correct and well-specified). Medtronic derives the arrow from a numeric rate **in the same response as the value**, so PD-42's split-provenance rule does not apply and no rule replaces it | FR-46 |
| **M21** | Medtronic battery gate — `ble/read/BatteryReader.kt:25-49`: `1..100` with **0 explicitly rejected** as spurious; `isCharging` always `false` (replaceable battery, no charging state on the SIG service) | MISSING | The port would inherit an inconsistency: Tandem **clamps** with `coerceIn(0, 100)` (`StatusResponseParser.kt:157, 176`) where Medtronic **rejects**. The PRD's reject-never-clamp posture is stated only for glucose and doses | FR-32 or FR-49 |
| **M22** | Licensee allowlist **contents** — `build.gradle.kts:36-118`: seven SPDX allows (`Apache-2.0, MIT, BSD-2-Clause, BSD-3-Clause, ICU, SAX-PD, SAX-PD-2.0`), two `allowUrl`, 15 version-pinned `allowDependency` each with a `because`; canonical texts in `docs/licenses/` | MISSING | FR-229 asserts *"This FR is the single definition of the allowlist"* but names **no allowed identifier**, and 5.11 delegates *"its initial contents"* to FR-229 — the delegation dangles. `MIT`, `BSD-2`, `BSD-3`, `ICU`, `SAX-PD`, `CUP`, `BouncyCastle` → zero PRD hits | FR-229 |
| **M23** | `docs/contract/safety-constants.md:1-76` | MISSING | The phrase *"safety-constants source-of-truth document"* appears in FR-213, FR-217 and FR-212's roster, but **no FR requires it to exist or states its contents**, and FR-220's table has no `contract/` row. Lost: the per-constant **backend owner** (`apps/api/src/core/units.py MGDL_PER_MMOL`, `tandem_regions.py TANDEM_EPOCH_OFFSET_SECONDS`) and *"it must change in both repos in the same coordinated release"* | FR-217, FR-220 |
| **M24** | Four more `docs/dev/` pages: `spdx-header-policy.md` (272 ln), `dependency-updates.md` (202 ln), `release-and-promotion.md` (122 ln), `wear-os-architecture.md`, `instrumented-tests-ci.md` | MISSING | FR-220's `dev/` row names three of eight. Sharpest: **FR-234 requires the README `## License` section to carry "pointers to `LICENSE` and the SPDX header policy" — a required pointer with no required target**, under FR-219's link checker. `dependency-updates.md` also uniquely carries *"Residual risk: label management is a trusted operation"* | FR-220 |
| **M25** | Per-device pairing page — `docs/daily-use/connecting-medtronic-pump.md:1-75`: BT-vs-CareLink decision table, the single-peer precondition, advertise-and-wait explanation + `"Mobile 000001"`, five numbered steps, "What it reads", four failure cases, and the **SmartGuard micro-bolus attribution limitation stated as a documented read-path limitation** (`:51`) | MISSING | FR-220's `daily-use/` row is generic; no FR requires a per-Driver pairing page. The in-app strings exist (FR-6, FR-16, SI-7) but no *published* page does. 5.1's preamble corrects Android's false *"reconnects on its own"* claim for **in-app copy only** — the doc-side correction has no owner | FR-220 |
| **M26** | `Auto Label PRs` — `auto-label.yml:1-152` + `autolabeler-config.json:1-59`: path-glob labels, 11 Conventional-Commit type mappings, `breaking-change` detection, `needs triage` fallback, `minimatch@10.0.3 --ignore-scripts` under `pull_request_target`, paginated `listFiles` | MISSING | 5.12's feature-NFRs **depend** on it: *"Documentation-only pull requests MUST receive the `docs` label"* — with nothing specified to apply it | FR-192 or §10.2 |
| **M27** | `changelog-pr-config.json:1-97` taxonomy — nine ordered scopes, five priority-ordered sub-categories + `defaultSubCategory`, `excludeLabels`, `keepLabels` | MISSING | The PRD says the taxonomy *"ports largely intact"* but FR-192 specifies only the cutoff marker and PR title — nothing requires the scope remap (Mobile→iOS, Wear OS→Apple Watch, Watch Face→removed, Plugins→Drivers) | FR-192 |
| **M28** | `Renovate Config Validator` — `renovate-config-validator.yml:1-53` (`renovate@43.260.2 --strict`, Node 24) | MISSING | Zero PRD hits. FR-194 governs the bot's policy; nothing validates the bot config | FR-194, §10.2 |
| **M29** | `regen-gradle-lockfiles.yml:45-52, 80-83` — three hard `if:` guards on the job that executes PR-branch build scripts (bot author, **same-repo only**, `renovate/` branch prefix) plus `cache-read-only: true` (*"never let it write to the shared Actions cache other workflows read from"*) | MISSING | FR-194 specifies the two-job split, the pinned-SHA checkout, `core.hooksPath /dev/null` and the non-force push — but not these four supply-chain controls on the one job that runs PR-authored code | FR-194 |
| **M30** | `shell.nix:1-65` — reproducible dev environment pinning SDK platforms, build-tools, JDK 17, Gradle and emulator images | MISSING | Zero `nix` hits. FR-193 claims the toolchain is *"the same on a maintainer's machine as in CI"* but names only `.xcode-version`, `Package.resolved`, `Gemfile.lock`. `Brewfile` and `mise.toml` appear **only inside FR-194's allowlist regex** — no FR requires either to exist | FR-193 |
| **M31** | `tools/medtronic-ble-spike/**` as a separately-locked, out-of-bot-scope tree — own `lockAllConfigurations()` + `gradle.lockfile`; in the OSV scan (`--recursive`) and the Semgrep root; `ignorePaths: ["tools/**"]` (`renovate.json5:33-34`); hard-rejected by the scope guard *before* generic patterns (`renovate-file-scope.yml:91-98`); excluded from lockfile regen | PARTIAL | Only the Semgrep half survives (FR-200's *"any research spike"*). Nothing requires the spike's own resolved graph to be scanned, and nothing marks a spike tree human-only for the bot | FR-194, FR-201 |
| **M32** | SECURITY.md coordinated-disclosure terms — `SECURITY.md:23`: *"We ask that you give us a reasonable period to address the issue before any public disclosure"* plus the keep-you-updated commitment | MISSING | FR-226 states only the first-response expectation. Greps for `coordinated disclosure`, `public disclosure`, `reasonable period`, `disclosure window` → zero | FR-226 |
| **M33** | FR-197 / §10.2's *"exactly the seven"* non-required roster | MISSTATED | Contradicted by three other FRs: FR-180 declares `Validate Secrets` non-required, FR-185 declares `Signing Smoke` non-required, FR-194 declares the scope guard non-required — none of the three is in the seven | FR-197, §10.2 |
| **M34** | The scope guard's required status | MISSTATED | FR-194 asserts *"branch protection keys only on those five literal names"* **as Android's rule**. `renovate-file-scope.yml:1-8` says the opposite: *"**Required status check** … Registering it as a required check on develop is a maintainer go-live step"*, echoed in `dependency-updates.md:193`. Android's intended roster is **six**. The iOS decision is defensible but belongs in a **PD row**, not in a claim about Android — and the job name `Renovate File Scope` never appears in the PRD, though branch protection keys on job names | FR-194, §7.2 |
| **M35** | FR-192's admin-merge validation | MISSTATED | FR-192 attributes validation to **all three** admin-merged PRs; `release.yml:70-82` does **zero** validation (greps a PR number, runs `gh pr merge --squash --admin`). A strengthening presented as a carry-over. Merge strategies also differ and are unstated: `--squash --admin` for release/sync, `--rebase --admin` preceded by `gh pr review --approve` for changelog | FR-192 |

---

## LOW

| # | Finding | Type | Android source | PRD site |
|---|---|---|---|---|
| L1 | **PL-35 says "Android has no cap" on phone→watch complication refresh.** Android throttles deliberately: BG 30 s, IoB 60 s, graph 120 s. | MISSTATED | `wear-device/.../data/GlycemicDataListenerService.kt:414-416` | PL-35 (prd.md:5662) |
| L2 | **PL-34/FR-117 say the sparkline had four overlay layers.** Android's sparkline already excluded bolus markers — three layers. `GraphComplicationDataSource.kt:67` sets `bolusHistory = emptyList()` with the comment `// too small at 400x100`, and `:76` `showBolusMarkers = false`. The row overstates the loss by one layer and attributes an existing Android decision to the accented-rendering constraint. | MISSTATED | `wear-device/.../complications/GraphComplicationDataSource.kt:67, 76` | PL-34, FR-117 |
| L3 | **FR-236 undercounts the Sentry lockdown.** `DROPPED_BREADCRUMB_PREFIXES` has **five** entries (`http`, `navigation`, `ui.`, `network`, `device.event`) — FR-236 names four. FR-236 also omits `event.contexts.device?.apply { timezone = null; locale = null }`, whose own source comment records that nulling the user alone was empirically insufficient against geo-inference. A port reproducing only FR-236's list reopens a coarse-location leak Android closed deliberately. | MISSTATED | `app/.../logging/SentryInitializer.kt:47-48, 103-106` | FR-236 |
| L4 | **FR-34 claims per-subscriber event buffers.** Android has one shared `MutableSharedFlow(extraBufferCapacity = 256, onBufferOverflow = DROP_OLDEST)` — in Kotlin the buffer is shared across all collectors, so a slow subscriber causes drop-oldest for everyone. The 256, drop-oldest and no-replay all verify; the isolation property is an unrecorded improvement. | MISSTATED | `app/.../plugin/PluginEventBusImpl.kt:407-410` | FR-34 |
| L5 | **Upload batch sizes.** 50 queue events and 100 raw history rows per push. FR-141 depends on the batch concept ("marks the batch failed") and FR-142's cap arithmetic reasons from enqueue rate; the drain rate is the other half. | MISSING | `app/.../service/BackendSyncManager.kt:58-59, 228, 255` | FR-140 or FR-142 |
| L6 | **An unparseable queue row is marked permanently failed, not retried** — collected into `failedParseIds`, `markFailed(..., "JSON parse error")`, excluded from `validIds`, never counted against the retry budget. FR-141 classifies transport and HTTP failures only, so a locally corrupt row has no stated disposition and would head-of-line block the oldest-first queue. | MISSING | `app/.../service/BackendSyncManager.kt:236-251` | FR-141 |
| L7 | **Bolus uploads split event type by flag** — `"correction"` when `isCorrection`, else `"bolus"` — and upload only `units` + `isAutomated`; `correctionUnits`, `mealUnits` and `category` are stored locally but never uploaded. This is itself a wire quirk (the Backend's `correction` type is client-derived) and FR-140's quirks bullet omits it. | MISSING | `app/.../data/remote/PumpEventMapper.kt:35-58` | FR-140 |
| L8 | **Two distinct correction figures in the Insulin Summary.** Besides the four-branch portion ladder, Android computes `correctionUnits` = `totalCorrection/days` (summing, over boluses matching `isCorrection \|\| correctionUnits > 0`, `correctionUnits` if `> 0` **else the whole `units`**) plus `correctionCount`. FR-89 specifies only the portion ladder. `bolusCount` survives via the VoiceOver bullet; `correctionCount` does not. | MISSING | `app/.../domain/compute/DashboardComputations.kt:115-118, 169-188`; `domain/model/InsulinSummary.kt:13-28` | FR-89 |
| L9 | **`BolusCategoryMapper` uses the provider only for a non-empty category** — `if (provider != null && bolus.category.isNotEmpty())`, so a pre-migration row with `category == ""` falls to the flag ladder even when a provider exists. FR-89 says only "with no provider the flag ladder applies". | MISSING | `app/.../domain/compute/BolusCategoryMapper.kt:23` | FR-89 |
| L10 | **FR-102 misquotes the comorbidity attribution string.** Android renders `"From $source ($tier source)"` — e.g. "From FoodData Central (authoritative source)". FR-102 quotes `"From <source> (<trust tier lowercased>)"`, dropping the trailing word "source". The PRD treats meal copy as verbatim. | MISSTATED | `app/.../presentation/meal/MealComponents.kt:489-497` | FR-102 |
| L11 | **FR-103's meal-history row enumeration omits confidence.** Android renders the full `CarbEstimateContent` per row — carb range **plus confidence label plus confidence bar** plus correction note. FR-103 lists only description, range with note, timestamp and Delete. FR-97 rescues it by implication but the explicit list contradicts it. | MISSTATED | `app/.../presentation/meal/MealHistoryScreen.kt:146-151` | FR-103 |
| L12 | **FR-134's "single definition of what the Watch consumes" collides with FR-113.** `KEY_CONFIG_AI_TTS` and `KEY_CONFIG_AI_TTS_VOICE` ride the same `CONFIG_PATH` payload as the eight preferences. FR-113 carves this out correctly; FR-134's "exactly, and only … Eight preferences" does not acknowledge it. Wording collision, not a gap. | MISSTATED | `wear-device/.../data/WearDataContract.kt:115-116`; `ChatActivity.kt:61-107` | FR-134 |
| L13 | **Watch graph range/count footer** — `"${config.graphRangeHours}h  \|  ${readings.size} readings"` under the plot. FR-133 specifies the plot, panning, tooltip, ticks and the "not enough data" state, but no caption. | MISSING | `wear-device/.../presentation/GraphDetailActivity.kt:388-396` | FR-133 |
| L14 | **No defined wrist copy for "the companion app is unreachable."** `ChatActivity.kt:361-368` renders `"Phone not connected"` / `"Failed to send request"`; `WearMessageSender.kt:16-38` has a 10 s capability/node-discovery-plus-send timeout. FR-114's failure list has no companion-unreachable line, and FR-131 says the Watch clears optimistically "even when the app is unreachable" without defining a user-visible statement. | MISSING | `wear-device/.../presentation/ChatActivity.kt:361-368`; `WearMessageSender.kt:16-38` | FR-114, FR-131 |
| L15 | **Debug console controls** — the "Clear" action, the `"<n> entries"` count line (`debug_entry_count`) and the connection-state indicator (`debug_connection_state`). FR-176 pins the buffer capacity (100, verified) and every injection but not these three. | MISSING | `app/.../presentation/debug/BleDebugScreen.kt:77-79, 118-127` | FR-176 |
| L16 | **App base palette unpinned.** `Theme.kt:669-715` defines Slate950/900/800/700/400/300/100/50 and Blue600/500/400. FR-175 says only "the palette is fixed". | MISSING | `app/.../presentation/theme/Theme.kt:669-715` | FR-175 |
| L17 | **Onboarding copy drift unrecorded.** Android: *"use the app as a direct **BLE** pump monitor"* and the control *"Use without a server **(BLE-only)**"*. FR-161/FR-164 drop both parentheticals. Defensible Glossary substitutions, but §7 records neither. | MISSTATED | `app/.../presentation/onboarding/OnboardingScreen.kt:568, 651` | FR-161, FR-164 |
| L18 | **Recent-meal glance refreshes on every ON_RESUME except the first** (the VM already fetched in `init`). Not in FR-93. | MISSING | `app/.../presentation/home/HomeScreen.kt:75-78` | FR-93 |
| L19 | **Detail-screen back-stack guard.** Chart detail and Bolus History share Home's ViewModel and pop back rather than crash when Home is absent from the back stack. FR-63 states the shared model but not the guard. | MISSING | `app/.../presentation/navigation/NavHost.kt:365-381, 391-407` | FR-63 |
| L20 | **AI Chat input placeholder `"Ask about your glucose data..."` and header `"AI Chat"`.** FR-111 pins the empty-state title but not these. | MISSING | `app/.../presentation/chat/AiChatScreen.kt:243, 383` | FR-111 |
| L21 | **Settings Pump card Driver notes.** The active Driver's `InfoText` descriptor renders under `pump_settings_notes` inside the **Settings** Pump card. FR-37 covers the mechanism but locates it on *"the pairing card"*; the identifier and the Settings location are unstated. | MISSING | `app/.../presentation/settings/SettingsScreen.kt:1096-1102` | FR-37 |
| L22 | **Medtronic RACP self-contradiction fail-loud and the two memory bounds.** *"A pump that says 'no records found' after streaming frames is contradicting itself… Fail so the read is retried with the cursors unchanged"*; `MAX_RECORDS_PER_REPORT = 50_000`; page 200 with a cross-page cap. Partly implied by SI-8, but the contradiction case and the bounds are unstated. | MISSING | `plugins/shipped/medtronic/.../HistoryReader.kt:110-120`; `MedtronicSessionReader.kt:319-326, 478`; `MedtronicReadGateway.kt:59-69, 306` | FR-32 NFRs |
| L23 | **Medtronic IDD structural decode gates** — response-opcode equality, trailing-byte rejection, bounds-checked optional-field walk, size-field-vs-buffer equality. Tier 2's *"framing and CRC"* is the nearest cover. | MISSING | `plugins/shipped/medtronic/.../IddStatus.kt:144-147, 160-162, 207-210, 234-236`; `CgmMeasurement.kt:71-76, 93-100, 119-123` | FR-206 |
| L24 | **FR-232 drops HMAC from the in-source-citation set.** FR-232 lists **four** files (*"protocol, JPAKE, HKDF and status-parsing"*); FR-231 lists **five** (adding HMAC), matching `spdx-header-policy.md:125-131`. Separately `acknowledgments.md:21` names a *different* four including `EcJpake.kt` — the Apache-2.0 port, not a pumpX2 MIT citation; neither PRD list resolves that. | MISSTATED | `docs/dev/spdx-header-policy.md:125-131`; `docs/concepts/acknowledgments.md:21` | FR-231, FR-232 |
| L25 | **FR-226 replaces "commit SHA" with "build number".** `SECURITY.md:20` asks for *"the app version / commit SHA you tested against"*. Under fork-and-build the build number is a Builder-local counter (FR-191) identifying nothing upstream, while FR-187 already stamps a 7-character commit SHA in-app. | MISSTATED | `SECURITY.md:20` | FR-226 |
| L26 | **PRIVACY.md's "What an error report contains"** (stack trace, OS/runtime versions, app version + commit hash, triggering line) is dropped. FR-236 requires the never-transmit list verbatim but no positive-contents list, and `Sentry` is never named in the PRD. | MISSING | `PRIVACY.md:30-36` | FR-236 |
| L27 | **`THIRD_PARTY_LICENSES.md`'s normative scoping rule** — *"Keep this document scoped to lineage; do not expand it into a runtime-dependency list"*, plus the may-appear-in-both-places note (SQLCipher). That rule is what stops a maintainer folding FR-228's generated `runtime_dependencies.md` into it. | MISSING | `docs/THIRD_PARTY_LICENSES.md:3-18` | FR-228, FR-232 |
| L28 | **Android's *published* required-check roster contradicts the PRD's closed five in two places.** `CONTRIBUTING.md:262-274` publishes **Attribution Check** under *"Every PR must pass these checks before it can be merged"*. FR-194/FR-218 make both non-required with sound reasons, but no PD or §10.2 row records the contradiction. | MISSTATED | `CONTRIBUTING.md:262-274`; `docs/dev/dependency-updates.md:193` | §10.2 |
| L29 | **CONTRIBUTING loses five sections** — `## Code Style`, `## Ways to Contribute`, `## Project Structure`, the CodeRabbit CLI local pre-review, and the published required-CI-checks / fork-PR-handling sections. Greps → zero. | MISSING | `CONTRIBUTING.md:75-83, 231-239, 262-286, 290-299, 313-330` | FR-225 |
| L30 | **README loses five sections** — `## Overview` (including *"a **monitoring and analysis platform** … it does not, and will not, issue therapeutic writes"*), `## Relationship to the Platform`, `## Installation`, `## Development`, `## Contributing`. FR-234 requires only the safety blockquote, `## Disclaimer`, `## License` and the device table. | MISSING | `README.md:33-89` | FR-234 |
| L31 | **`bootstrap-sha` and `package-name`** are absent from FR-190's otherwise-complete release-please enumeration. `bootstrap-sha` determines where release-please starts scanning on a fresh repository — exactly this situation. | MISSING | `release-please-config.json:3, 7` | FR-190 |
| L32 | **R8 / resource shrinking has no PL or PD row.** `isMinifyEnabled`, `isShrinkResources`, `proguard-android-optimize.txt`. Zero PRD hits for `proguard`, `R8`, `minify`, `shrink`. | MISSING | `app/build.gradle.kts:136-140` | §7 |
| L33 | **`permissions: {}` at workflow *and* job level** on four workflows; FR-222 carries the pattern for the docs dispatch only. | MISSING | `changelog-pr.yml:8-10, 25-26`; `sync-main-to-develop.yml:18`; `notify-docs-update.yml:13, 18` | FR-197 |
| L34 | **Semgrep exclusion policy tightened without a PD row.** FR-200 says *"A basename-scoped exclusion pattern is not permitted"*; Android uses exactly two (`AesEcb.java`, `.gradle`), each with a written reason. A deliberate improvement, unrecorded. | MISSTATED | `security-scan.yml:69-76` | FR-200, §7.2 |
| L35 | **Internal version drift on a pinned tool.** §10.1 says *"OSV-Scanner v2"*; FR-201 says *"v2.3.3"*. Android is `v2.3.3`. | MISSTATED | `dependency-scan.yml:71` | FR-201, §10.1 |
| L36 | **A stale action pin carried forward silently.** `notify-docs-update.yml:22` pins `create-github-app-token@1b10c78c…` where all **twelve** other call sites use `bcd2ba49… # v3.2.0`. FR-222 reproduces the stale pin verbatim without noting the skew. | MISSTATED | `notify-docs-update.yml:22` | FR-222 |
| L37 | **`.coderabbit.yaml` beyond the three custom checks** — `path_filters`, `base_branches: ["develop"]` + `auto_pause_after_reviewed_commits: 3` + bot `ignore_usernames`, six `labeling_instructions`, `pre_merge_checks` at `mode: warning`, the enabled-tools list including `detekt`, and `knowledge_base.code_guidelines.filePatterns`. §10.3 covers only the custom checks and GitGuardian. | MISSING | `.coderabbit.yaml:44-79, 168-199, 247-293` | §10.3 |
| L38 | **`scripts/mobile-dev.sh`** — the device/emulator helper with named BLE log-tag filters and a `BLE_RAW` hex stream, the maintainer's primary BLE debugging surface. Zero PRD hits; FR-213 covers `ci-local.sh` gate reproduction only. | MISSING | `scripts/mobile-dev.sh:1-238` | FR-213 |
| L39 | **`acknowledgments.md`'s contribute-back close**, including the Nightscout Foundation donation pointer, is dropped from FR-232. Greps for `donat`, `Nightscout Foundation` → zero. | MISSING | `docs/concepts/acknowledgments.md:50-54` | FR-232 |
| L40 | **`RestrictedContext` operation count understated by ~30%.** The 5.2 description says it *"blocked ~30 `Context` operations"*; the class has **41** `override fun` declarations (a few are overloads). PL-41 repeats the same figure. | MISSTATED | `app/.../plugin/RestrictedPluginContext.kt` | PL-41, 5.2 |
| L41 | **"~1,175 resolved packages" is a faithful quote but is not reproducible from the repo** — 844 lockfile entries across all eight lockfiles, 442–450 unique coordinates. Worth an inline caveat, since FR-201 makes this figure the anchor of the iOS `osv-scanner.toml` header. | MISSTATED | `osv-scanner.toml:10-14`; `docs/dev/security-testing.md:156` | PL-67, FR-201 |

---

## Verified correct — the inverse check

The following PRD claims were checked against source and **match exactly**. Listed because a parity audit that only reports failures misrepresents the document.

**Safety constants and decision logic**
- Conversion Factor `18.0156`, converted once from the most precise mg/dL source, rounded last; the separate offset-free `convertSpread` path — `domain/format/GlucoseFormat.kt:26, 41-87` (SI-3, FR-60, FR-175)
- Glucose Validity Bound 20–500, reject-never-clamp — `DashboardComputations.kt:27-28`; `PumpDataRepository.kt:292-306` (FR-138, PD-46)
- Freshness: CGM 6 min / 15 min, Pump 15 min / 60 min, half-open boundaries, negative age FRESH for display — `domain/freshness/Freshness.kt:45-49, 96-134` (FR-49)
- Debug-fast policy 20,000 / 45,000 ms at exactly one swap point — `Freshness.kt:128-134` (FR-49, FR-176, PA-12)
- Alert-Floor forward-skew tolerance **exactly** 60,000 ms; `age >= -60000 && classify(max(age,0)) == FRESH` — `Freshness.kt:59, 79-81` (FR-72)
- Wall-clock rewind high-water mark and its "fails toward alarming" residual — `Freshness.kt` doc + `AlertFloor.kt:197-206` (FR-72)
- **Alert Floor gate order** — rewind → mark advance → episode re-arm → null classification → alerting-degraded → data-trust bound → notification capability → cooldown → episode guard → fire. Matches FR-71's nine-step list step for step, including "capability checked **before** the cooldown is stamped" and the `min(recentServerAlertMs, nowMs)` clamp — `service/AlertFloor.kt:197-300` (FR-71–FR-75)
- `FLOOR_COOLDOWN_MS = 30 * 60_000L`, and `WRIST_ALERT_REBUZZ_MS = AlertFloor.FLOOR_COOLDOWN_MS` — `AlertFloor.kt:339`; `PumpPollingOrchestrator.kt:467` (FR-74, FR-129, PA-6)
- Alert vocabulary `low_urgent/low_warning/high_warning/high_urgent/iob_warning`; severities `warning/urgent/emergency`; low/high routing sets — `domain/alerting/AlertTypes.kt` (FR-65)
- Five `FloorNotWatchingReason` arms and the selector's precedence order — `domain/alerting/AlertingStatus.kt:27-33, 85-98` (FR-83, FR-127)
- Sample SD (n−1); CV% = sd/mean×100, 0 when mean ≤ 0; **GMI = 3.31 + 0.02392 × mean** from raw mg/dL; CGM-active = valid×100/(hours×12) clamped 0–100 — `DashboardComputations.kt:60-88` (FR-59)
- TIR by SQL aggregate over `BETWEEN 20 AND 500` with the exact five bucket comparisons, and the deliberate `low`/`high` boundary divergence from FR-47 — `dao/PumpDao.kt:129-149` (FR-58, PD-14)

**Background, storage and transport**
- Wake locks: `WAKE_LOCK_TIMEOUT_MS = 20 min`, `WAKE_LOCK_RENEW_MS = 15 min`, `RECONNECT_WAKE_LOCK_TIMEOUT_MS = 2 min`, `PARTIAL_WAKE_LOCK`, `START_STICKY` — `PumpConnectionService.kt:59-62, 287` (PL-11)
- Coverage heartbeat `max(timeout/2, 5 s)` × `FreshnessPolicy.CGM.staleAfterMs = 360_000` → 3 min in production — `WearMonitoringStatusForwarder.kt:78, 84-85` (PL-16)
- Queue drain tick 3 s; idle hygiene 60 s; hourly cleanup — `BackendSyncManager.kt:57-72` (PL-19, FR-144)
- Retry ladder `2000 × 2^retryCount`; `MAX_RETRIES = 5`; 408/429/502/503/504 not counted — `dao/SyncDao.kt:19-33`; `BackendSyncManager.kt:336` (FR-141)
- Queue cap 5,000 → 20,000 and stale-sending 60 s → 15 min, both correctly recorded as raises — `BackendSyncManager.kt:58-62` (FR-142, PD-23)
- Manual refresh order IOB → basal → battery → reservoir → glucose with `REQUEST_STAGGER_MS = 500L`, plus the concurrent settings reconcile and the CAS in-flight guard — `HomeViewModel.kt:409-450` (FR-40)
- Chart row caps 2,000 glucose/IOB/basal and 500 bolus — `dao/PumpDao.kt:30-34, 73-80, 118-122` (NFR-7, FR-52, PD-39)
- Retention 1–30 days default 7, one transactional delete across six tables, raw table keeps the max-sequence anchor — `AppSettingsStore.kt:97-101`; `PumpDao.kt:153-163` (FR-139, PD-20)
- Cleartext policy: https always; http only on the private-range opt-in; strict IPv4 parsing rejecting octal/hex/bare-decimal; `::ffff:` by embedded v4; `.local` with a required label; never a DNS lookup; enforced at save **and** request — `remote/UrlSecurityPolicy.kt:33-249` (FR-150, FR-151, PL-50)
- Token refresh: 5 min proactive, 3 startup attempts at 1 s/2 s, 60 s transient reschedule, 10 s refresh-client timeouts, single mutex, session-generation logout guard — `auth/AuthManager.kt:66-582` (FR-147, FR-148)
- DB version 13, seven explicit migrations, `fallbackToDestructiveMigration` correctly recorded as the defect, 32-byte hex passphrase — `AppDatabase.kt:19-33`; `di/DatabaseModule.kt:30, 144-149` (FR-136, PD-38)
- `allowBackup="false"` → the iOS analogue (device-only, after-first-unlock, never iCloud) is carried by SI-10 and FR-204 — `AndroidManifest.xml:57`

**Wrist**
- Coverage validity clamp 10,000–1,800,000 ms, default 360,000 ms; `MAX_HISTORY_RECORDS = 500`; `MAX_BOLUS_UNITS = 25f`; `MAX_BASAL_RATE = 15f` — `GlycemicDataListenerService.kt:398-413` (FR-126, FR-132)
- History codec 13 / 21 / 12 bytes, little-endian, flags encoding — `WearHistorySerializer.kt:10-17` (FR-132)
- Threshold sanitization 40–200 / max(low+1,100)–400 / 20–low / high–500 — `GlucoseDisplayUtils.kt:21-32` (FR-125)
- Wrist clock-trust bound ±60,000 ms — `WatchFreshness.kt:42` (FR-123)
- `WRIST_ALERT_REFRESH_MS = 5 * 60_000L` — `PumpPollingOrchestrator.kt:461` (FR-130)
- Watch chat watchdog 30 s vs the phone's 90 s, correctly recorded as a defect fixed rather than ported — `ChatActivity.kt:378` (PD-18)
- Haptics `[0, 500, 200, 500]` urgent / one-shot 300 ms warning — `GlycemicDataListenerService.kt:372-376` (PL-26)
- Chat complication tint `0xFF3B82F6` — `ChatComplicationDataSource.kt:58` (PL-38)
- Five-slot / three-slot layouts, 450×450 circular scenes, per-variant overlay defaults — watchface templates; `WatchFaceVariant.kt:22-25` (PL-31)
- Watch APK 100 MB cap and 15 s install timer — `WatchApkReceiveService.kt:51`; `SettingsViewModel.kt:1086` (PL-36)
- Alerts bell's **six**-branch hue encoding — `AlertsComplicationDataSource.kt:105-112` (PL-34)
- PD-17's "empty payload, assumes most recent alert" — `WearMessageSender.kt:74` `ByteArray(0)`; `WearChatRelayService.kt:64` `getLatestUnacknowledgedServerId()` (PD-17)
- PL-33's claim that Show Seconds and watch-face theme were **already inert** on Android — confirmed: both are validated and stored but read by no renderer

**Notifications, plugins, build**
- Vibration waveform `[0, 500, 200, 500, 200, 500]` on the low channel; `setBypassDnd(true)` on low and high only (AI channel correctly excluded); `setOnlyAlertOnce(!isLow)` — `AlertNotificationManager.kt:128-160, 323` (PL-23, PL-25, PD-15)
- `STREAM_ALARM` boost to max with persisted saved-volume restore, and the "Boost Volume for Lows" toggle — `AlertNotificationManager.kt:349, 375-379`; `SettingsScreen.kt:1484` (PL-24)
- Four scrub rules (token, email, mg/dL, mmol/L) applied before emission — `logging/ReleaseTree.kt:23-33` (PA-15, FR-158)
- Driver id regex `^[a-zA-Z][a-zA-Z0-9._-]{1,127}$` — `DexPluginLoader.VALID_PLUGIN_ID` (FR-21)
- 50 MB / `PK\x03\x04` / canonical-path containment install pipeline — `PluginFileManager.kt:179-181, 224-230` (PL-40)
- `RestrictedPluginContext` — **29** denying overrides, `ALLOWED_SYSTEM_SERVICES` of exactly **7** — (PL-41)
- 65,536-char manifest cap — `MAX_MANIFEST_SIZE` (PD-34)
- Medtronic company id `0x01F9`; Tandem `requestMtu(185)` and `CONNECTION_PRIORITY_HIGH` — `MedtronicProtocol`, `TandemProtocol.REQUIRED_MTU`, `BleConnectionManager.kt:699-701` (PL-4, PL-7)
- `versionCode = major*1_000_000 + minor*10_000 + patch` — `app/build.gradle.kts:32` (PD-29)
- `DEV_RUN_NUMBER_OFFSET=500` — `.github/workflows/dev-pre-release.yml:90-91` (PD-29)
- `RELEASE_SIGNER_SHA256: 55f0d0cdabf20b398ad30a0ce3e998e3192666e5c15e6d378b86e1c8de342990` and the release→debug signing fallback it guards — `.github/workflows/release.yml:338, 493-494`; `app/build.gradle.kts:142-147` (PL-56, PD-28)
- Medtronic `MEDTRONIC_DRIVER_ENABLED` env kill switch leaving the plugin present but inert — `app/build.gradle.kts:74` (FR-27, PD-11)
- Image pipeline: longest edge 1280, 5 MiB cap, quality 90 → 40 stepping 10 — `meal/ImageCompressor.kt:23-30` (FR-94)
- Carb bounds 0–1000 g and the four verbatim messages — `meal/MealModels.kt:25-52` (FR-100)

**Drivers and the Driver API**
- The six-Capability set and its 4 single-instance / 2 multi-instance split, minus calibration — `PluginCapability.kt:32-44` (FR-30, PD-36)
- FR-37's element vocabulary is **exactly right**: 9 card variants, 6 colours, 4 label styles, 13 icons, 6 settings variants, `MAX_ELEMENTS = 100`; settings-key regex `^[a-zA-Z][a-zA-Z0-9_.-]{0,127}$` — `SettingDescriptor.kt:11` (FR-29, FR-37)
- Every Safety-Limits bound (20 / 500 / 15,000 mU/hr / 25,000 mU) — `SafetyLimits.kt:44-54` — and the type-level 25 U bolus cap — `PumpModels.kt:70` (FR-32, FR-90)
- The seven `ConnectionState` values, and the reconnection ladder **verbatim**: 3 rapid disconnects, 3 zero-response connections, 20 encryption failures, attempt cap 10, `SLOW_RECONNECT_INTERVAL_MS = 120_000`, failure counter capped at 100, GATT `0x05`/`0x08`/`0x13` — `BleConnectionManager.kt:1338-1369` (FR-8, FR-13, PL-3)
- Handshake selection at ≤10 vs ≥11 characters — `BleConnectionManager.kt:1092` (FR-5)
- `Mobile 000001`, matcher `Mobile .{0,7}`, 30 s handshake / 60 s first-pair wait — `MedtronicBleConnectionManager.kt:442, 455, 458`; `MedtronicProtocol.kt:61` (FR-6, FR-16)
- **Both Tandem decode gates in FR-32/PD-41 are byte-accurate**: `egvStatusId` in 1…3 at cargo byte 6 (`StatusResponseParser.kt:193-213`), and the `ControlIQIOBResponse` opcode-109 17-byte selector at byte 16 with Mudaliar bytes 0–3 / Swan-6hr bytes 12–15
- FR-35's Simulated-Driver reference maths is exact: `130 + 50·sin(phase)`, ±10 jitter, `2π/12`, `MAX_HISTORY = 12`, 30 s default, 5–300 s step 5 — `ReadingSimulator.kt:113-121, 152`; `DemoGlucometerPlugin.kt:385-387` (FR-35, PA-7)
- `plugins/example` genuinely absent from `settings.gradle.kts`; FR-189's characterization of `MEDTRONIC_DRIVER_ENABLED` as a *runtime* flag Android leaves inert, improved to a compilation condition on iOS, is accurate — `app/build.gradle.kts:73, 102, 150`; `PluginFeatureGate.kt:20-28`
- The four deprecated pump interfaces and their two live defects, correctly refused (PD-8)

**CI, build and release — verified exactly**
- Every zizmor / actionlint / shellcheck / Semgrep / OSV pin **and both SHA-256 digests**; the OSV flags, weekly cron `0 6 * * 1`, three-job and five-branch aggregation; `osv-scanner.toml`'s zero-suppression discipline
- The PyYAML `pull_request_target` backstop including its `doc.get("on", doc.get(True))` YAML-1.1 handling **and** its documented not-airtight caveat
- The whole release-please config; the fallback-patch-release path (immutable-SHA manifest read, `git push --atomic`); the changelog cutoff marker, regex, double fallback and exact PR title; all three trigger predicates
- The sync-back five-file force-resolve, **and the PRD correctly identifies the phantom sixth allowlist entry**
- The release artifact contract and the debug-signed watch-face carve-out (PL-61, PD-30); the silent debug-signing fallback (PD-28); every `op-load-signing-secrets` hygiene property; the instrumented-tests lane in full
- Attribution Check's three layers, severities, precedence, bot-allowlist name-anchoring, CodeRabbit-footer stripping, sticky-comment pagination and the same-repo CRITICAL auto-close guard; the `commit-msg` hook; `dco.yml`; CODEOWNERS (with the `/Sources/Drivers/` parent-tree choice correctly *improving* on Android); the docs dispatch in full
- The five Required-Check job names and all eight non-required names — **and the PRD fabricates no gate that does not exist**: no detekt, ktlint, jacoco, coverage threshold, ABI split, configuration cache or `jvmToolchain` is claimed, correctly matching Android

**Contract, licensing and policy — verified exactly**
- `openapi.json` at 748,299 bytes / `3.1.0` / 164 paths / 274 schemas / no `servers` / no top-level `security`; `CONTRACT_VERSION` as a 2-byte `1`+newline; `info.x-contract-version` as a JSON **string**
- `LICENSE` = GPL-3.0-only, 35,149 bytes, 674 lines; `THIRD_PARTY_LICENSES.md` = 17,979 bytes; the nine `docs/licenses/*.txt` with GPL-3.0 correctly absent; `Copyright (C) 2026 Josh Engelbrecht`; `GPL-3.0-only` (not `-or-later`, not bare)
- Android's **19** drift-guard scan sites; the gitleaks history extraction (233 commits, ~5.9 MB, no leaks); the dangling `monorepo-port-ledger.md`; the **six** inconsistent repository slugs
- Code of Conduct = Contributor Covenant v2.1 with the diabetes-patience pledge and the four-rung ladder; the `info@` vs `security@` channel split
- The four OpenMinimed repos, palmarci's relicensing, all four individual credits, `particle-iot/ecjpake-java` Apache-2.0 © 2022 Particle Industries, and exactly the six movement credits; the EC-JPAKE open attribution gap and its closure
- Android's MobSF decline **with** its revisit trigger, and the secret-scanning decline **without** one — both recorded faithfully

**Checked and confirmed to have no Android counterpart** (so nothing was dropped): rotary / Digital Crown input, explicit swipe-to-dismiss handling, `AmbientModeSupport` in the Wear app, and any `TileService`. None exists in `wear-device/src/main`.

---

## Coverage and its limits

Every area named in the task was swept. Depth was **not uniform**, and the reader should weight accordingly.

**Read in full** — `plugins/pump-driver-api/**`, `plugins/shipped/{medtronic,tandem}/**`, all 18 workflows plus the composite action, `zizmor.yml`, `osv-scanner.toml`, `renovate.json5`, `release-please-config.json`, `.coderabbit.yaml`, the root policy documents, `contract/`, `docs/**`, `scripts/`, `tools/`, and the Gradle build files.

**Enumerated screen-by-screen and constant-by-constant** — `presentation/**`, `domain/**`, `data/**`, `service/**`, `plugin/**`, `wear/**`, `logging/**`, the manifest, `wear-device/**` and `watchface/**`. Every user-visible screen, control, empty state, error state, validation rule and numeric constant in those trees was grepped against the PRD several ways before being called a gap.

**Sampled rather than exhausted** — the Tandem cryptographic core (EC-JPAKE round arithmetic, HKDF/HMAC derivations) and the two Drivers' complete opcode tables. The Capability surfaces, connection state machines, parsers, decode gates, reconnection policy, timestamp models and per-model divergences above them **were** read. What remains unexamined is the arithmetic inside the crypto primitives — where a defect surfaces as a failed handshake rather than as a wrong number on screen, which is the least dangerous residual in this codebase.

**Two precision notes, below the reporting bar:**

- **PL-57** describes Android's toolchain trust as "the Gradle wrapper checksum". There is no `distributionSha256Sum` in `gradle/wrapper/gradle-wrapper.properties` and no `wrapper-validation-action` step; the mechanism is `gradle/actions/setup-gradle@v6`'s default wrapper-JAR validation plus `validateDistributionUrl=true`. The substance of the row — a verified toolchain artifact with no Xcode equivalent — holds; only the named mechanism is loose.
- Android's three-way `PLUGIN_API_VERSION` drift (code 5 / docs 2 / manifest 1) was confirmed, and the PRD's collapse of it to a single compile-time constant is correct and recorded.

---

## Recommended disposition

1. **C1–C3 block sign-off.** C1 changes a clinical number and needs a new Glossary term plus reassignment of four FRs. C2 is a one-line stage correction with a journey-blocking consequence. C3 is a three-place correction that converts two shipped safety gates from "must be identified" into "must be ported".
2. **Treat the Medtronic protocol-safety cluster (H3–H5, M18–M21) as one work item.** Its five findings share a cause — the PRD specifies the Tandem Driver in depth and the Medtronic Driver largely at the Capability surface. Both ship, and one of them is the Driver with the inverted BLE topology and the harder timestamp model. This cluster, not the individual rows, is the reason a Driver-scoped pass should precede FR-36's fixture work.
3. **Treat the release-pipeline cluster (H6, H7, H9–H14, M26–M31) as a second.** The PRD argues in settled decision 6 that the fork's pipeline is a supported surface *because* Builders load their own App Store Connect key into project-authored workflow code. The controls that make that argument hold — the approval-gated environment, the four-App token split, the bot-scope guards, the expedited CVE path — are the ones missing.
4. **H1, H2, H8 and H15–H18 need FR text before implementation starts.** Each currently leaves an implementer to invent behaviour on a safety, disclosure or contributor-facing surface.
5. **M1–M17 and M22–M25, M32–M35** are ordinary ledger work: most need a new FR consequence, seven need a ledger-row correction.
6. **L1–L41** can be batched into a single editorial pass, with two lifted out: **L3** (the Sentry device-context strip) has a privacy consequence, and **L24/L27** touch license-attribution obligations.
7. **The §7 and §10 misstatements matter more than their severity suggests** (C3, M8–M10, M33–M35, L28, L34–L36, L40, L41). The Ledger's stated purpose is to be the one place a reader learns what differs; a row that describes Android inaccurately is a row a future maintainer will "fix" in the wrong direction — which is precisely how C3 arose.
