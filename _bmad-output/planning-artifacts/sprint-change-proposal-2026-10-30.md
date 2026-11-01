---
title: Sprint Change Proposal — project TestFlight, installable-app-first, honest Tandem gating
date: 2026-10-30
author: PM with the maintainer
status: approved by the maintainer, 2026-10-30
scope: major
supersedes: PRD decisions 3, 6 (in part), 9; NG-4
---

# Sprint Change Proposal — 2026-10-30

## 1. Issue summary

Work stopped on 2026-09-09 after story 1.6 merged (PR #9). Six of roughly 80 stories are done; all of
them are foundations (SafetyCore, freshness, DriverAPI, Simulated Driver, encrypted store, EC-JPAKE
vectors). There is no app target, no UI and no build pipeline, so nothing can be installed. Meanwhile
community demand for an iOS client is significant.

Three changes were decided by the maintainer on 2026-10-30:

1. **Distribution (strategic pivot).** The project publishes its own TestFlight build from the
   maintainer's Apple Developer account, so community users install from a link instead of each
   forking and signing. This reverses PRD decision 3 (fork-and-build).
2. **Sequencing.** Build an installable app first: the app shell and dashboard on the Simulated
   Driver, plus the signing/TestFlight pipeline, ahead of Tandem Bluetooth. Run two independent
   lanes in parallel.
3. **Hardware honesty.** The team cannot exercise Bluetooth or real-device alert delivery (the
   Simulator has no Core Bluetooth; no iPhone or Watch on hand). Tandem ships labelled
   **Protocol-Implemented** with community-validation copy until hardware evidence exists.

Evidence: git history and PR list (develop at `12243eb`, `main` never promoted); PRD decisions 3, 4,
6, 9, 10 (prd.md:34–41); FR-179–FR-237; Story 8.1–8.3; §8.3 Verification table (prd.md:5885–5920).

## 2. Impact analysis

### 2.1 What the pivot does NOT remove — the licensing blocker

The PRD rejected project binaries on two independent grounds (addendum §2.3, §3.2; prd.md:4599; NG-3):

- **GPL-3.0-only vs Apple's Developer Program License Agreement**, which governs TestFlight as well
  as the App Store.
- **OpenMinimed copyright** in the Medtronic driver: "any future project-published binary would
  require permission from every holder."

Switching to a project TestFlight does not make either go away. They become **release gates on
external (public-link) distribution**, not blockers on building:

| Gate | Blocks | Resolution paths (the maintainer decides) |
|---|---|---|
| L1 — GPL vs DPLA | Any external TestFlight build | (a) counsel opinion and accept residual risk; (b) relicense iOS-original code with every contributor's consent; (c) add a GPL "additional permission" (App Store exception) — needs consent of copyright holders of any ported Android code |
| L2 — OpenMinimed copyright | Any project build containing the Medtronic driver | Compile Medtronic **out** of the project build via FR-27's compile-time exclusion; self-builders can still include it. Seek holder permission later. |
| A1 — Beta App Review | External testers / public link | Submit a monitoring-only build; no therapeutic write exists (decision 2), which is the strongest posture we have |
| E1 — 90-day expiry | Every installed build | Project CI must upload faster than builds expire (FR-186 becomes project cadence) |

**Internal TestFlight** (App Store Connect team members, up to 100, no Beta App Review) is not
blocked by A1. L1 still applies in principle; the maintainer to confirm whether internal-only distribution to
maintainers is acceptable pending counsel.

### 2.2 New upside the pivot creates

- **Critical Alerts becomes obtainable.** Decision 4 says the entitlement is "structurally
  unobtainable" because every user had their own Team ID. With one project Team ID the project can
  apply once and every user inherits it. Decision 4's runtime `.timeSensitive → .critical` upgrade
  already handles this. Action: the maintainer applies to Apple; D-3, OQ-24, NG-10 and FR-66 forced-loss copy
  reopen if granted. This is the single largest safety improvement available to the iOS client.
- **Validation is no longer a single point of failure.** §8.2/§8.3 held to one validator
  (DanielDanielson) because the project could not hand anyone a binary. Project TestFlight testers can
  now submit Verification evidence against a known build.
- **Crash visibility and artifact SAST.** PL-66's stated revisit trigger ("reinstate artifact-level
  SAST if the project ever publishes a binary") fires. Project-owned crash reporting becomes possible.

### 2.3 Epic impact

| Epic | Impact |
|---|---|
| 1 | Reordered (app shell first). 1.13 gains a DEMO DATA AC. Tandem stories 1.8–1.11 gain explicit Protocol-Implemented + validation-debt ACs (already PRD policy, now explicit in stories). |
| 2 | Unchanged in scope. 2.4 gains "upgrade to `.critical` if the project entitlement is granted" as a live path, not a theoretical one. |
| 3, 4, 6 | No change. |
| 5 | No change. (FR-189 telemetry credential question noted for 8.12.) |
| 7 | Medtronic excluded from the project build until L2 is resolved; still built in CI with every Driver enabled (AD-17, Story 8.8). |
| 8 | **Rewritten goal.** 8.1–8.3, 8.10, 8.12 rewritten for project distribution; fork-and-build kept as the advanced self-build path. 8.5 and 8.8 pulled forward. 8.4, 8.6, 8.9, 8.11 unchanged. |

No completed story is invalidated. No rollback.

### 2.4 Artifact conflicts

- **PRD:** ~60 locations depend on fork-and-build (full map in Appendix A). Classification: 9
  obsolete, ~45 rewrite, the rest unchanged (still valid for self-builders).
- **Architecture spine:** AD-9 (App Group templated on Builder Team ID, spine:114), stack line
  "fastlane + match: Builder-side signing" (spine:243), deferred telemetry (spine:294).
- **Addendum:** §1.6, §2.1, §2.2, §2.3, §3.2, §3.3.
- **UX:** no separate UX spec exists; affected copy lives in PRD FRs (Driver list, pairing copy,
  About/provenance).

### 2.5 Parity-review criticals — status check (requested)

| ID | Status | Left to fix |
|---|---|---|
| C1 two threshold sets | Mostly resolved — Target Range defined (prd:135), FR-47/52/58 and wrist banding use it, epics carry it | OQ-20 (prd:1170, :6297) still says banding uses Alert Thresholds; FR-40 (prd:828) says "glucose range" |
| C2 unreachable escape hatch | Partially resolved — Backend stage has its own escape (prd:2948) | FR-164 bullet 1 (prd:3098) still puts the label on the Sign-in stage; contradicts :2948–2949 |
| C3 Medtronic validity gates | Partially resolved — FR-32 ports all three gates (prd:651, :774) | PD-41 (prd:5813) and OQ-7 (prd:6279) still say a gate "must be identified" |

Sample of 9 of 18 High findings: 6 addressed, 2 not (H1 sign-out doesn't stop monitoring / reset
onboarding; H17 no community/support channel), 1 unclear (H16). **H17 matters more now**: a public
TestFlight with community validators needs a feedback/issue channel. The PRD has no revision log.

## 3. Recommended approach

**Direct adjustment + PRD amendment (no rollback, no MVP cut).**

- Add a dated amendment block to the top of the PRD that supersedes decisions 3, 9, NG-4 and
  rewrites 6, so the PRD is never silently wrong while the line-level rewrite is in progress.
- Do the ~60 line-level PRD/addendum/spine rewrites as one documentation story (tech-writer), using
  Appendix A as the checklist. Include the C1–C3 leftovers and a revision log.
- Restructure the backlog into two lanes and three release milestones.

Effort: Medium. Risk: Medium. The risk is the licensing gate (L1) — it is the long pole for the
public link and must start now, in parallel, as a maintainer-owned action.

### Release milestones

| Milestone | Audience | Contents | Gates |
|---|---|---|---|
| **M1 Internal demo** | App Store Connect team members (internal TestFlight) | App shell, dashboard, status row, tab bar on the Simulated Driver; DEMO DATA banner | Pipeline green; the maintainer confirms L1 posture for internal |
| **M2 Community beta** | Public TestFlight link | Epic 1 complete (Tandem, Protocol-Implemented), Epic 2 alert floor, first-run safety acknowledgement, feedback channel | L1 resolved; A1 passed; Medtronic compiled out (L2); H17 channel exists |
| **M3 Android parity** | Same | Epics 3, 4, 5, 6 | Same, plus Verification evidence upgrades Tandem to Verified where earned |

### Lanes (two stories in flight at once)

**Lane A — app:** 1.13 → {1.14, 1.15, 1.16} → 1.12 → 1.17 → 1.18 → 1.7 → 1.8 → 1.9 → 1.10 → 1.11 →
1.19 → 1.20 → Epic 2.

**Lane B — pipeline and docs:** 8.1′ → 8.2′ → 8.8 → 8.5 → 8.3′ → 8.4 → 8.10′ → PRD-amendment doc
story → 8.6 → 8.7 → 8.9 → 8.11 → 8.12′ → then joins Epic 2/3.

Protected paths in Lane B (CI workflows, signing, dependencies) escalate to the maintainer for merge per the
merge-authority rule. Expect maintainer-merge latency to set the pace of Lane B.

Revised estimate: M1 ≈ 1–2 weeks; M2 build-complete ≈ 4–5 weeks (calendar date depends on L1
and Beta App Review); M3 ≈ 8–10 weeks.

## 4. Detailed change proposals

### 4.1 PRD — amendment block (insert directly under the decisions table, prd.md:~42)

NEW:

> **Amendment 2026-10-30 (Sprint Change Proposal 2026-10-30).** Decision 3 is superseded: the project
> publishes its own TestFlight build from the maintainer's Apple Developer account. Fork-and-build
> remains a supported **advanced self-build path**. Decision 9 is superseded: validators may test
> project TestFlight builds. Decision 6 is rewritten: the project pipeline is the primary supported
> surface; the fork pipeline is secondary. NG-4 is withdrawn. External distribution is gated on
> licensing gates L1 (GPL-3.0 vs Apple DPLA) and L2 (OpenMinimed copyright; Medtronic is compiled out
> of project builds until resolved), on Beta App Review, and on a 90-day-expiry upload cadence.
> Decision 4 is reopened: the project Team ID applies for the Critical Alerts entitlement. Until the
> line-level rewrite lands, this amendment wins over any conflicting text below.

### 4.2 Epics — Epic 8 goal (epics.md:658–663 and :1773)

OLD: "A Builder forks the repository, adds their own Apple credentials, and produces a signed build on
their own iPhone through their own TestFlight — then keeps it alive past the 90-day expiry."

NEW: "The project produces a signed build and delivers it through its own TestFlight — internal first,
then a public link once licensing and Beta App Review gates clear — and keeps every installed build
alive past the 90-day expiry. A Builder who prefers to self-sign can still fork and build. Includes the
gates that make the pipeline trustworthy and the documentation that makes both paths followable."

### 4.3 Story 8.1 → 8.1′ "Signed project build to TestFlight"

NEW Acceptance Criteria (replace all):

- **Given** the project's App Store Connect API key and signing material stored as protected
  repository/environment secrets **When** the release workflow runs on `develop` or `main` **Then** a
  signed build is uploaded to the project's TestFlight (FR-183, rewritten).
- Signing material is managed by `fastlane match` against a private project-owned repository; the
  secret set is documented; credentials can be validated in isolation without exposing any value (FR-180).
- The build hard-fails if the archive is not signed by an Apple Distribution certificate **whose
  identity matches the pinned project signer** (FR-184, now pinnable like Android's `RELEASE_SIGNER_SHA256`).
- Any credential materialized during a run has restrictive permissions and is destroyed with the run (FR-185).
- The signing job runs only in a protected `release-gated` environment; fork PRs never reach it (H6).
- The same workflow still works in a fork with the fork owner's own secrets (self-build path, FR-179 rewritten).
- Medtronic is compiled out of the project build configuration (L2); the every-Driver build still compiles in CI (AD-17).
- **Protected path:** the maintainer merges.

### 4.4 Story 8.2 → 8.2′ "Register project identifiers and channels"

CHANGE: "bundle identifiers, App Group containers and Keychain access groups derive from the Builder's
Team ID" → "are fixed project identifiers for the project build, and template on the Team ID only for
self-builds (FR-181, AD-9)". Channel AC unchanged. ADD: "the internal TestFlight group is created and
the external group exists but is not enabled until gates L1 and A1 clear."

### 4.5 Story 8.3 → 8.3′ "Never let an installed build lapse"

CHANGE: "the workflow ships enabled by default in every fork" → "the project's scheduled weekly
change-triggered and monthly unconditional uploads run from the upstream repository; the fork template
keeps them enabled for self-builders (FR-186)". CHANGE FR-188 AC: "TestFlight delivers updates to
project-build users; the in-app newer-release notice applies to self-builds only." Rest unchanged.

### 4.6 Story 8.10 → 8.10′ "Install guide and published docs"

CHANGE: primary runbook = "join the TestFlight, install, pair, and how to report a problem"; the
fork-and-build runbook becomes the advanced path. ADD: a community feedback/issue channel (GitHub issue
template for device reports including pump model, iOS version, build number) — closes parity H17.

### 4.7 Story 8.12 → 8.12′

ADD: decide whether the project build carries a crash-reporting credential (FR-189 rewritten); if yes,
privacy disclosure updated accordingly.

### 4.8 Story 1.13 — add DEMO DATA AC

ADD:

> **And** whenever the active Driver is the Simulated Driver, every screen shows a persistent,
> non-dismissable "DEMO DATA — not your glucose" banner, and the hero value carries the same label to
> VoiceOver, so a tester can never read simulated numbers as their own.
> **And** builds whose only selectable Driver is the Simulated Driver are distributed to the internal
> TestFlight group only.

### 4.9 Stories 1.8–1.11 — make Protocol-Implemented explicit

ADD to each:

> **And** live-radio behaviour (scan, handshake, reconnect, background restoration) is recorded as
> validation debt in the Dev Agent Record; nothing in-product implies the device has been tested
> (prd.md:5890), and the Driver list and pairing copy read *unverified on hardware* until §8.3 evidence
> is recorded.

### 4.10 Story 2.4 — Critical Alerts

ADD: "**And** if the project's Critical Alerts entitlement is granted, urgent low is delivered as
`.critical` and the forced-loss copy for DND/silent switch is removed for project builds (decision 4,
reopened)."

### 4.11 New story — PRD distribution rewrite (Lane B, tech-writer)

"As a maintainer, I want the PRD, addendum and architecture spine to describe project distribution
accurately, so no future story is built on the superseded fork-and-build text." ACs: every Appendix A
row dispositioned; C1/C2/C3 leftovers fixed; PRD gets a revision log; amendment block removed once
complete. No code.

## 5. Implementation handoff

**Scope: Major** (reverses a settled PRD decision). Routed to PM (this session) for backlog and
artifacts, Architect for AD-9/stack changes inside the doc story, the maintainer for the gates below.

| Owner | Action |
|---|---|
| **Maintainer** | L1: choose a licensing path and start it now (counsel / relicense / exception). |
| **Maintainer** | Apply for the Critical Alerts entitlement under the project Team ID. |
| **Maintainer** | Confirm internal-TestFlight posture while L1 is open; confirm who the internal testers are (someone needs an iPhone — DanielDanielson?). |
| **Maintainer** | Confirm whether the t:slim X2 in PRD decision 10 is still on hand. |
| PM | Apply 4.1–4.10 to PRD and epics; add 4.11; update sprint-status ordering. |
| PM | Create story files for 1.13 and 8.1′; route via `/v1/route`; dispatch both lanes through AFK. |
| Dev workers | Implement per lane; protected-path PRs escalate to the maintainer. |

**Success criteria:** M1 internal build installable from TestFlight within ~2 weeks; every Appendix A
row dispositioned; L1 has a named path and owner; no screen ever shows simulated data unlabelled.

## Appendix A — fork-and-build dependency map

Source: research sweep 2026-10-30. O = obsolete, R = rewrite, U = unchanged.

| Location | ID | Class |
|---|---|---|
| prd:34 | Decision 3 | O |
| prd:35 | Decision 4 (Critical Alerts) | R |
| prd:37 | Decision 6 | R |
| prd:40 | Decision 9 | O |
| prd:51, :86 | Vision, UJ-3 Marcus | R |
| prd:113–114 | Glossary: Builder, Fork-and-build | R |
| prd:443 | Identifier stability | U |
| prd:495, :532 | FR-22 rationale | R |
| prd:1183, :1220, :1511, :2363 | FR-66, forced loss | R |
| prd:2693, :5206, :5216 | FR-150, NFR-20 ATS | U |
| prd:2788 | Device fingerprint | R |
| prd:3666–3684 | §5.10 intro | R |
| prd:3688 | FR-179 | O |
| prd:3705 | FR-180 | R |
| prd:3720 | FR-181 | R |
| prd:3731–3742 | FR-182 | R |
| prd:3746 | FR-183 | R |
| prd:3762 | FR-184 | R |
| prd:3773 | FR-185 | U |
| prd:3784 | FR-186 | R |
| prd:3797 | FR-187 | U |
| prd:3809 | FR-188 | R |
| prd:3821 | FR-189 | R |
| prd:3899 | FR-195 | U |
| prd:3911 | FR-196 | R |
| prd:4020, :4152 | FR-199, FR-208 | U |
| prd:4097–4098 | FR-204 guard | R |
| prd:4265 | FR-216 | U |
| prd:4325, :6044–6048 | PL-66, artifact SAST | R |
| prd:4344, :4439–4456, :4448, :4498 | §5.12, FR-223, FR-226 | R |
| prd:4599 | FR-232 licensing | R |
| prd:4631, :4635 | FR-234 | R |
| prd:4652–4666 | FR-236 crash posture | R |
| prd:4697–4699 | PL-53 / PL-54 / PL-63 | O / U / R |
| prd:4725, :6259–6260 | Counsel note, OQ-56 | R |
| prd:4739, :5513–5517 | §6 measurement, §6.9 | R |
| prd:5733, :5736, :5742, :5762 | PL-53, PL-56, PL-62, PL-71 | O/R |
| prd:5834 | PA-9 | R |
| prd:5889, :5908, :5916 | §8.1–8.3 Verification | R |
| prd:6020, :6058 | Gate table | R / U |
| prd:6071 | NG-3 | R |
| prd:6072 | NG-4 | O |
| prd:6080 | NG-12 | R |
| prd:6118, :6197, :6301 | D-3, OQ-24 | R |
| prd:6206–6207 | R-6 supply-chain blast radius | R |
| prd:6340, :6343 | OQ-58, OQ-61 | R / O |
| addendum §1.4 | Private API at upload | U |
| addendum §1.6 | App Group templating | R |
| addendum §2.1 | APNs | R |
| addendum §2.2 | Critical Alerts | R |
| addendum §2.3 | Distribution | O |
| addendum §3.2 | Medtronic licensing | R |
| addendum §3.3 | Manufacturer framing | R |
| epics:197–254, :554–611 | FR inventory titles | R |
| epics:349 | Infrastructure line | O |
| epics:660, :1773 | Epic 8 goal | R |
| epics:1777–1824 | Stories 8.1–8.3 | R |
| epics:1826–1907 | Stories 8.4–8.8 | U (8.7 FR-204 bullet R) |
| epics:1908–1961 | Stories 8.9–8.11 | U (8.10 R) |
| epics:1962–1981 | Story 8.12 | R |
| epics:1047 | Story 2.4 | R |
| spine:114 | AD-9 | R |
| spine:243 | Stack: fastlane + match | R |
| spine:294 | Deferred telemetry | R |
