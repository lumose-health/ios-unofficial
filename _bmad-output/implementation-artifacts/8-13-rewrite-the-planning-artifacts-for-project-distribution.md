---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/8-13-rewrite-the-planning-artifacts-for-project-distribution.md.stamp.json
persona: tech-writer
memory_mode: advisory
gates:
  - "! grep -nF 'Amendment 2026-10-30' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md"
  - "grep -qxF '### 0.2 Revision Log' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md"
  - "awk '/^### 0\\.2 Revision Log$/{f=1;next} f&&/^#/{f=0} f' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md | grep -E '^\\| 20[0-9]{2}-[0-9]{2}-[0-9]{2} \\|' | grep -F TestFlight | grep -F C1 | grep -F C2 | grep -qF C3"
  - "! grep -qx 'updated: 2026-08-10' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md"
  - "! grep -nE '[Uu]nder \\**fork-and-build|publishes no binary|holds no signing|no signing key|structurally unobtainable|never as a tester on|conveys no binary|every user is a Builder|Each user builds|Every user builds' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/addendum.md _bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md"
  - "! grep -nE \"templated on the Builder's Team ID|Builder-side signing|a Builder's own DSN is their choice\" _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/addendum.md _bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md"
  - "! grep -qx \"updated: '2026-08-03'\" _bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md"
  - "! grep -nF 'default Alert Threshold set' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md"
  - "! grep -qF 'reconciles glucose range' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md && grep -qF 'concurrently reconciles the Target Range' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md"
  - "! grep -qF 'The Sign-in stage carries the label' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md && ! grep -qF 'lives on the following stage' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md && grep -qF 'The Backend stage (index 3) carries the label' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md"
  - "! grep -nF 'must be identified' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md && [ \"$(grep -cF 'the annunciation gate is the outstanding one' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md)\" -ge 2 ]"
  - "grep -qF '**L1**' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md && grep -qF '**L2**' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md"
  - "[ \"$(sed -nE 's/^#### (FR-(179|18[0-9]|19[0-6]|219|22[0-9]|23[0-7])): (.*)$/\\1: \\3/p' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md)\" = \"$(sed -nE 's/^\\*\\*(FR-(179|18[0-9]|19[0-6]|219|22[0-9]|23[0-7]))\\*\\*: (.*)$/\\1: \\3/p' _bmad-output/planning-artifacts/epics.md)\" ]"
  - "[ \"$(sed -nE 's/^#### (FR-(179|18[0-9]|19[0-6]|219|22[0-9]|23[0-7])): (.*)$/\\1: \\3/p' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md)\" = \"$(sed -nE 's/^\\| (FR-(179|18[0-9]|19[0-6]|219|22[0-9]|23[0-7])) \\| Epic 8 \\| (.*) \\|$/\\1: \\3/p' _bmad-output/planning-artifacts/epics.md)\" ]"
  - "! grep -rn '/Users/' _bmad-output/planning-artifacts/"
  - "! grep -rniE 'josh|engelbrecht' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/addendum.md _bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md _bmad-output/planning-artifacts/epics.md && [ \"$(grep -oiE 'josh|engelbrecht' _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md | wc -l)\" -le 7 ]"
  - "! { git diff --name-only $(git merge-base HEAD develop); git ls-files --others --exclude-standard; } | grep -vE '^_bmad-output/(planning-artifacts/(prds/prd-ios-unofficial-2026-08-01/(prd|addendum)\\.md|architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE\\.md|epics\\.md)|implementation-artifacts/(8-13-|sprint-status\\.yaml$))'"
max_cycles: 3
---

Status: review

# Story 8.13: Rewrite the planning artifacts for project distribution

<!-- Planning note (for the maintainer): documentation only. No Swift, no workflow, no config, no
dependency. Four files may change: prd.md, addendum.md, ARCHITECTURE-SPINE.md, and epics.md (FR
inventory titles only). Estimate: ~200-280 changed lines across those four files. PRD paragraphs are
long single lines, so the line count understates the word diff. Route: NOT chosen here; the PM routes
via /v1/route. The source of truth for this story is sprint-change-proposal-2026-10-30.md, which is
read-only here. -->

## Story

As a maintainer,
I want the PRD, addendum and architecture spine to describe project distribution accurately,
so that no future story is built on the superseded fork-and-build text.

## Acceptance Criteria

From epics.md Story 8.13 and Sprint Change Proposal 2026-10-30 (§2.4, §2.5, §4.1, §4.11, Appendix A).

1. **Every Appendix A row is dispositioned.** All 64 rows in table A below (A01-A64), in Appendix A
   order, are handled per their disposition: remove rows have the obsolete assertion removed, rewrite
   rows are rewritten to the replacement intent, and leave rows keep their requirement. Rows marked
   *already applied* are verified and not edited again.
2. **Appendix A's gaps are closed.** Every supplementary row in table S (S01-S23) is dispositioned
   the same way. These are locations with the same fork-and-build premise that Appendix A missed,
   found while this story was prepared. Any further hit found by the sweep in Task 6 gets a new S row
   in the Dev Agent Record.
3. **Parity-review leftovers fixed (C1, C2, C3)** exactly as table C specifies:
   OQ-20 and FR-40 use the Target Range (C1); FR-164 puts the escape hatch on the Backend stage, and
   FR-159's note agrees (C2); PD-41 and OQ-7 no longer say a Medtronic validity gate "must be
   identified" (C3).
4. **Architecture spine.** AD-9 states fixed project identifiers for the project build and Team-ID
   templating only for self-builds; the stack line states project-side signing; the deferred-telemetry
   row reflects the open FR-189 decision; spine frontmatter `updated:` is bumped.
5. **Release gates defined once.** The PRD defines the external-distribution release gates **L1**,
   **L2**, **A1** and **E1** once, in §5.10's Description, and other sections cite them by ID. No text
   claims any gate is resolved, or that Critical Alerts has been granted.
6. **Amendment block removed, revision log added.** The `> **Amendment 2026-10-30 …**` blockquote
   (prd.md ≈ line 43) is deleted. A `### 0.2 Revision Log` section takes its place, directly before
   `## 1. Vision`, with a row dated the day of the rewrite that records the distribution change and
   the C1/C2/C3 fixes (format in Dev Notes). PRD frontmatter `updated:` is set to the same date.
7. **IDs are stable.** No decision, FR, NFR, PL, PD, PA, NG, D, R, OQ, A or SI identifier is deleted or
   renumbered. FR count stays 237. Where an item is obsolete, its ID stays and its text is replaced with
   the new position or with a one-line "Withdrawn (revision <date>): <reason>" statement.
8. **Epics stay in sync, and only where Appendix A names them.** FR titles that change in the PRD are
   mirrored in both FR lists in epics.md (the `**FR-N**:` inventory and the FR Coverage Map). No epics
   story body changes: Appendix A's epics rows are already applied (verify only).
9. **Publication hygiene.** No `/Users/…` path, and no new occurrence of the maintainer's real name,
   in any changed file. Write "the maintainer". Existing GitHub handles (for example DanielDanielson)
   may stay.
10. **No code changes.** Only the four planning files listed above change, plus this story file and
    `sprint-status.yaml`.
11. **All gates pass** from the repo root.

## Tasks / Subtasks

- [x] Task 1: Read the sources, then establish the baseline (AC 1, 2, 3)
  - [x] Read `_bmad-output/planning-artifacts/sprint-change-proposal-2026-10-30.md` in full (§2.1 for
        the gate table, §4.1 for the amendment's content, §4.3-§4.7 for the rewritten Epic 8 stories).
        It is read-only in this story.
  - [x] Run every gate once and record in Debug Log which ones fail (expected list in Dev Notes).
  - [x] Line numbers in tables A/S/C are approximate (taken from today's files). **Locate each row by
        its anchor (ID or heading), never by line number.** Appendix A's own numbers are off by about
        2 because the amendment block was inserted after they were taken.
- [x] Task 2: Front matter of the PRD (AC 1, 5, 6, 7)
  - [x] Rows A01-A04 (decisions 3, 4, 6, 9). Keep the table and the numbering.
  - [x] Remove the amendment blockquote; add `### 0.2 Revision Log` in its place (AC 6).
  - [x] Rows A05-A06, S01, S02 (Vision, JTBD, Non-Users, UJ-3, Glossary).
- [x] Task 3: PRD §5.1-§5.9 rows (AC 1, 2, 3)
  - [x] A07-A11, S03-S07.
  - [x] Table C rows C1a, C1c, C2a, C2b (OQ-20 in 5.3, FR-40 and FR-155, FR-164, FR-159 note).
- [x] Task 4: PRD §5.10-§5.12 (AC 1, 2, 5, 7)
  - [x] A12 first: write the §5.10 Description, including the L1/L2/A1/E1 gate table (AC 5).
  - [x] A13-A34, S08-S10.
- [x] Task 5: PRD §6-§16 (AC 1, 2, 3)
  - [x] A35-A46, S11-S23.
  - [x] Table C rows C1b (OQ-20 in §15), C3a (PD-41), C3b (OQ-7).
- [x] Task 6: Sweep for anything the tables missed (AC 2)
  - [x] `grep -nE 'fork-and-build|own fork under their own|own TestFlight|every Builder|Builder.?s Team ID|project-held|project-operated' <prd.md> <addendum.md>`
        Every remaining hit must be either new-model text you wrote (for example "fork-and-build,
        the advanced self-build path") or a leave row. Anything else gets a new S row in Completion
        Notes and gets handled.
  - [x] Also check `grep -n 'decision 3\|decision 9\|NG-4' <prd.md>`: every citation must still make
        sense against the rewritten decision.
- [x] Task 7: Addendum rows A47-A53 (AC 1)
- [x] Task 8: Epics rows A54-A61 (AC 8)
  - [x] A54: mirror every changed FR title (FR-179-FR-196, FR-219-FR-237) into both epics lists.
  - [x] A55-A61: verify the already-applied rows and record "verified" per row. Do not edit. A58: verify the 8.7 bullet against your A27 rewrite.
- [x] Task 9: Spine rows A62-A64, plus frontmatter `updated:` (AC 4)
- [x] Task 10: Gates and record (AC 9, 10, 11)
  - [x] All gates pass. Tick every A/S/C row in the Completion Notes checklist with its final
        disposition and new location (heading).
  - [x] Report diff size (`git diff --stat`) in Completion Notes.

## Dev Notes

### Rules of the road

- **Docs only.** Never touch `Sources/`, `Tests/`, `Apps/`, `scripts/`, `.github/`, `Package.swift`.
  Never touch `prds/.../research/`, `review-*.md`, `.memlog.md`, or the sprint change proposal; they are
  historical evidence.
- **`_bmad-output` is published.** Never write the maintainer's real name (write "the maintainer"). Never
  write a local `/Users/…` path. The existing `Copyright (C) 2026 …` strings in FR-230/FR-231's
  consequences are a LICENSE content requirement; leave them exactly as they are (the name gate allows
  them and nothing more).
- **Do not invent facts.** Nothing is resolved yet: L1 has no chosen path, Critical Alerts has not been
  granted, the public link is not live, and no crash-reporting decision has been made. Write those
  as open, owned by the maintainer, and gated. Do not invent bundle identifiers, Team IDs, secret names,
  cadences or dates beyond what the proposal states. Story 8.2′ owns the identifier values. The cadence
  is what §4.5 says: weekly change-triggered plus monthly unconditional uploads.
- **Vocabulary is binding (PRD §0).** Use exactly these terms, and add them to the Glossary (A06):
  - **Project build**: a build signed by the project and delivered through the project's TestFlight.
  - **Self-build**: a build a Builder produces from their own fork with their own Apple credentials.
  - **Builder**: a user who makes a self-build. Not every user is a Builder any more.
  - **Fork-and-build**: the advanced self-build path.
- **Phrases that must not survive in prd.md, addendum.md or the spine** (gate 5). Do not use them in
  new text either, including the revision log: "under fork-and-build" (any capitalisation or bold),
  "publishes no binary", "holds no signing", "no signing key", "structurally unobtainable", "never as a
  tester on", "conveys no binary", "every user is a Builder", "each/every user builds".
- **Disposition semantics:**
  - **remove**: delete the obsolete assertion. If it carries an ID or a numbered row (decisions,
    FR-179, NG-4, OQ-61, PL-53), keep the ID and replace the text with the new position, or with
    `Withdrawn (revision <date>): <one-line reason>` (AC 7). Delete prose without IDs outright.
  - **rewrite**: restate the requirement for project distribution, using the replacement intent. Keep
    the testable consequences that still hold, and keep any FR, SI or decision cross-references that
    still apply.
  - **leave**: the requirement does not change. **One edit is allowed:** if the line uses a gate-5
    phrase as its premise, replace only that phrase (for example "under fork-and-build a Builder can
    install a debug configuration" becomes "a Builder can install a debug configuration on a
    self-build") so the sentence stays true. Change nothing else.
  - **already applied**: the change landed with the sprint change proposal's own commit. Verify it and
    record "verified".
- **Style.** Match the surrounding PRD voice: plain, declarative, testable. No marketing words. No
  "story", "epic", "AC n" or other process vocabulary in the PRD, addendum or spine. Cite the change as
  "Sprint Change Proposal 2026-10-30" only in the revision log.

### Release gates (define once, in §5.10's Description, as a table; cite by ID elsewhere)

Carry these over from proposal §2.1 without changing their meaning. Bold the IDs as `**L1**`, `**L2**`,
`**A1**`, `**E1**` (gate 12 checks for `**L1**` and `**L2**`).

| Gate | Blocks | Resolution paths (the maintainer decides) |
|---|---|---|
| **L1**: GPL-3.0-only vs the Apple Developer Program License Agreement | Any external TestFlight build | counsel opinion and accepted residual risk; relicensing iOS-original code with every contributor's consent; or a GPL additional permission, which needs the consent of the copyright holders of any ported Android code |
| **L2**: OpenMinimed copyright in the Medtronic Driver | Any project build containing the Medtronic Driver | Medtronic is compiled out of the project build through FR-189's compile-time exclusion; self-builds may include it; holder permission may be sought later |
| **A1**: Beta App Review | External testers and the public link | a monitoring-only submission (decision 2) |
| **E1**: 90-day TestFlight expiry | Every installed build | project CI uploads faster than builds expire (FR-186) |

Then state that internal TestFlight (App Store Connect team members, up to 100, no Beta App Review) is
not blocked by A1, that L1 still applies in principle, and that the internal-only posture while L1 is
open is the maintainer's call.

### Table A: Appendix A rows (64), in Appendix A order

File keys: **PRD** = `_bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md`;
**ADD** = `.../prd-ios-unofficial-2026-08-01/addendum.md`;
**EPI** = `_bmad-output/planning-artifacts/epics.md`;
**SPN** = `_bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md`.
"≈" = line today. Appendix class: O = obsolete, R = rewrite, U = unchanged.

| Row | File | Anchor (≈ line) | Current gist | App. A | Disposition | Replacement intent |
|---|---|---|---|---|---|---|
| A01 | PRD | §0.1 decision **3** (≈34) | Distribution is fork-and-build; project ships source only, holds no key; every user is a Builder | O | remove (keep row 3, replace text) | Decision: the project publishes its own TestFlight build from the maintainer's Apple Developer account, internal group first, public link once L1, L2, A1 clear; fork-and-build stays as the advanced self-build path. Why: community demand; fork-and-build was too high a bar. The licensing conflicts survive as release gates on external distribution, not as blockers on building. Where it bites: §5.10, NG-3, §8, §9 |
| A02 | PRD | decision **4** (≈35) | Critical Alerts unobtainable because every user has their own Team ID | R | rewrite | One project Team ID can apply once and every project-build user inherits a grant. The application is a maintainer action and nothing is granted yet. `.timeSensitive` with runtime upgrade to `.critical` stands, and self-builds will normally never carry the entitlement |
| A03 | PRD | decision **6** (≈37) | The fork's pipeline is the supported product surface | R | rewrite | The project's release pipeline is the primary supported surface (CODEOWNERS-gated, SHA-pinned, signing only in the protected `release-gated` environment, inside security-response scope). The fork pipeline is a secondary supported surface. Key custody, account state, certificate lifecycle and rebuild cadence stay with the Builder for self-builds |
| A04 | PRD | decision **9** (≈40) | DanielDanielson validates only from their own fork, never as a tester on a project TestFlight | O | remove (keep row 9, replace text) | Validators, including DanielDanielson, may test project TestFlight builds; a self-build is still acceptable evidence when its build provenance is recorded. Where it bites: §9 Tier 4, R-5 |
| A05 | PRD | §1 Vision, the "It ships the way…" paragraph (≈53); UJ-3 Marcus (≈87-88) | Each user builds, signs and installs their own, and there is no binary; Marcus forks, pastes secrets, runs a workflow and gets his own build | R | rewrite both | **Vision:** the project delivers the app through its own TestFlight (internal first, then a public link once its gates clear). People who prefer to sign their own copy can still fork and build. Drop the claim that self-building is what keeps the app distributable. **UJ-3:** retitle "Marcus installs the app, having never opened App Store Connect." He joins the project's TestFlight from a link (internal invite until the public link exists), installs, and pairs. Settings shows the commit, build number and expiry. Edge case: a build expires after 90 days, and the project's scheduled uploads plus the in-app expiry warning keep him covered. One closing sentence points to the self-build path (FR-179). Keep "See FR-179 through FR-196" |
| A06 | PRD | §3 Glossary: **Builder**, **Fork-and-build** (≈115-116) | Every user is a Builder; fork-and-build is the distribution model | R | rewrite | Redefine both and add **Project build** and **Self-build** (see Vocabulary) |
| A07 | PRD | FR-? identifier-stability consequence, "A hardware step validates identifier stability…" (≈445) | Matters more under fork-and-build | U | leave (premise phrase only) | "…matters more here than in a normal app: Builders reinstall frequently, and every TestFlight build expires after 90 days" |
| A08 | PRD | FR-22 Description (≈497) and consequence "Medtronic renders Beta" (≈534) | Driver list matters because nobody but the Builder vouches for a build | R | rewrite | The Driver list shows what this build contains. Verification Status matters because hardware validation is community evidence, not a vendor claim. Project builds omit Medtronic (L2), so "Medtronic renders Beta" becomes "where Medtronic is compiled in, it renders Beta" |
| A09 | PRD | FR-66 and the forced-loss restatements (≈1185, ≈1222, ≈1513, ≈2365) | Critical Alerts unobtainable; the runtime upgrade "will not activate for the typical Builder" | R | rewrite | The entitlement is not held today. The project may obtain it for project builds (decision 4), self-builds normally will not, and the silent-switch copy stays until `.critical` is actually active. ≈1222 and ≈2365 probably need no change; verify |
| A10 | PRD | FR-150 (≈2695), NFR-20 (≈5208, ≈5218) | Same ATS rule in every configuration | U | leave (premise phrase only) | Replace "under fork-and-build a Builder can install a debug configuration" with a self-build phrasing |
| A11 | PRD | Device fingerprint consequence (≈2790) | Signing-certificate component dropped because every Builder signs differently | R | rewrite | Keep the requirement (SHA-256 of vendor identifier + bundle identifier). Restate the reason: the Android signing-certificate component has no portable iOS equivalent, and project builds and self-builds sign with different identities |
| A12 | PRD | §5.10 Description (≈3668-3684) | Project is not a publisher; N Builder identities; Team-ID templating for everyone; Builder CI rebuilds; upstream produces no installable artifact | R | rewrite | The project publishes again, through TestFlight. Trust topology: one project signing identity confined to the `release-gated` environment (fork PRs never reach it), plus self-builders' own identities. Fixed project identifiers for the project build; Team-ID templating for self-builds only. Project CI uploads on a schedule (E1). Upstream CI also produces the signed project build. **Insert the L1/L2/A1/E1 table here** (AC 5). Keep the Android-comparison and versioning paragraphs that are still true |
| A13 | PRD | FR-179 heading + statement (≈3688) | No project-held signing material; never an installable signed binary | O | remove (keep FR-179, retitle) | Retitle `FR-179: Fork-and-build as the advanced self-build path`. A Builder can produce a self-build from a fork with their own signing material. The project's signing material is never exposed to forks or to fork pull requests. Note: Story 8.1′ already cites "FR-179 rewritten" |
| A14 | PRD | FR-180 (≈3705) | Builder's fixed secret set in a fork | R | rewrite | One documented secret set for the project's release environment and one for a self-builder's fork, each validatable in isolation without any value reaching a log |
| A15 | PRD | FR-181 (≈3720) | Every identifier derived from the Builder's Team ID | R | rewrite | Retitle (suggested) `FR-181: Fixed project identifiers, Team-ID templating for self-builds`. The project build uses fixed identifiers registered under the project Team ID; self-builds derive theirs from the Builder's Team ID so they never collide (AD-9) |
| A16 | PRD | FR-182 (≈3731-3744) | Builder runs one-time registration | R | rewrite | The project registers its identifiers once; a Builder runs the same workflow in their fork. Entitlements granted only by application (Critical Alerts) are reported, not failed on. The project's application for Critical Alerts is tracked under decision 4 |
| A17 | PRD | FR-183 (≈3746) | Build, sign and upload from the Builder's own fork | R | rewrite | Retitle (suggested) `FR-183: Building, signing and uploading the project build`. The release workflow on `develop` or `main` uploads a signed build to the project's TestFlight, and the same workflow runs in a fork with the fork owner's secrets |
| A18 | PRD | FR-184 (≈3762) | Distribution-signing property assertion | R | rewrite | The project build also hard-fails unless the signing identity matches the pinned project signer (pinnable like Android's `RELEASE_SIGNER_SHA256`); self-builds keep the property assertion |
| A19 | PRD | FR-185 (≈3773) | Custody of signing material within a run | U | leave | |
| A20 | PRD | FR-186 (≈3784) | Builder rebuilds on demand and on a schedule | R | rewrite | Weekly change-triggered and monthly unconditional uploads run from the upstream repository for the project build. The fork template keeps them enabled for self-builders (proposal §4.5) |
| A21 | PRD | FR-187 (≈3797) | In-app provenance, channel, expiry | U | leave | |
| A22 | PRD | FR-188 (≈3809) | Upstream release notice plus TestFlight deep link | R | rewrite | TestFlight delivers updates to project-build users; the in-app newer-release notice applies to self-builds only (proposal §4.5). The never-download/never-execute rule stays |
| A23 | PRD | FR-189 (≈3821) | Driver exclusion; no build contains a project telemetry credential | R | rewrite | Driver exclusion unchanged. Medtronic is excluded from the project build (L2). Whether the project build carries a crash-reporting credential is an open maintainer decision; until it is made, no build carries one. A self-build never carries a project-owned credential |
| A24 | PRD | FR-195 (≈3899) | Syncing a fork with upstream | U | leave | |
| A25 | PRD | FR-196 (≈3911-3925, including the consequence "The project makes no claim…" ≈3923) | The fork pipeline is the supported surface; project claims nothing about any build | R | rewrite | The project pipeline is the primary supported surface and the fork pipeline the secondary one. The Builder boundary applies to self-builds. The project can state what its own build contains (build number, commit); claims about self-builds stay claims about the source at a tag |
| A26 | PRD | FR-199 (≈4014-4022), FR-208 (≈4146-4154) | PR builds unsigned Simulator builds | U | leave | |
| A27 | PRD | FR-204 consequences: Critical Alerts entitlement (≈4099), signing material (≈4100) | Entitlement banned because no Builder build could sign with it | R | rewrite | Keep the ban on committing the entitlement to `.entitlements` while no grant exists, and restate the reason (no grant yet; self-builds cannot sign with it). Add: if the project is granted it, it may be added to the project build configuration only, never to the self-build configuration. The signing-material bullet stays unchanged |
| A28 | PRD | FR-216 consequence on the older-Backend direction (≈4267) | Newer app against older Backend is normal | U | leave (premise phrase only) | |
| A29 | PRD | 5.11 notes "Artifact-level scanning" (≈4327); §10.2 PL-66 revisit discussion (≈6044-6050) | Upstream cannot produce a signed artifact, so artifact SAST is unreachable; the revisit trigger is a project-published binary | R | rewrite | The revisit trigger has fired. Artifact-level scanning of the project build is now possible. Record it as an open item: add a new OQ at the end of "Build, distribution and gates" in §15 (next free number). Do not claim a scanner is adopted. Self-builds keep the residual |
| A30 | PRD | §5.12 Description (≈4346-4362), FR-223 (≈4441-4458), FR-226 supported-versions bullet (≈4500) | Docs are the only delivery mechanism; runbook is fork-to-app; only the latest tag is supported | R | rewrite | Primary runbook: join the TestFlight, install, pair, and report a problem through a community feedback/issue channel (GitHub issue template for device reports with pump model, iOS version and build number; closes parity H17). The fork-and-build runbook becomes the advanced path and keeps the 90-day and runner-minute disclosures. Retitle FR-223 (suggested) `FR-223: Install runbook, the self-build path, and the 90-day expiry`. FR-226: supported = the latest project TestFlight build and the latest tagged source revision |
| A31 | PRD | FR-232 consequences (≈4599-4601) and §5.12 acknowledgments paragraph (≈4362) | Any project binary is foreclosed; fork-and-build keeps this lawful | R | rewrite | State L2: the project build excludes the Medtronic Driver until every OpenMinimed holder grants permission; self-builds may include it. State L1 as an open gate on external distribution. No legal conclusion |
| A32 | PRD | FR-234 (≈4618-4637, including warning ≈4627, table state ≈4633, disclaimer ≈4637) | Tandem validated "from their own fork"; claims describe the source and "a Builder's own build is their own" | R | rewrite | Verified evidence may come from a project build (record the build number) or a self-build. Disclaimer claims describe the source at a tag and the project build at a build number; a self-build is its Builder's own. Restate the Critical Alerts clause as in A09 |
| A33 | PRD | FR-236 heading + body (≈4654-4668) | Crash posture "under fork-and-build"; every build is a Builder's | R | rewrite | Retitle `FR-236: Privacy document and the crash-reporting posture`. Posture follows the FR-189 decision: no credential today, and the document changes if the maintainer adds one. The source-versus-binary boundary applies to self-builds |
| A34 | PRD | §5.10 Parity-Ledger list: PL-53/PL-58 (≈4699), PL-54 (≈4700), PL-63 (≈4701) | No project binary; 90-day expiry; runner minutes | O / U / R | PL-53 line: remove the obsolete claim; PL-54: leave; PL-63: rewrite | PL-53/58: no releases-page binary and no in-app download/install; updates arrive through TestFlight, and paid Developer Program membership is needed only for a self-build. PL-63: the runner-minute cost falls on self-builders; project CI cost is the project's |
| A35 | PRD | 5.12 notes: counsel review of the manufacturer framing (≈4727); R-21 (≈6259-6262); OQ-56 (≈6341) | Under fork-and-build the framing arguably fits every user; OQ-56 resolved for self-builders | R | rewrite | The framing question now applies to self-builders. For project-build users the project is the distributor, which is part of L1's counsel question. Rewrite R-21's mitigation, which relied on decision 9's old form. Keep OQ-56's resolution for self-builds and add one sentence saying it does not cover the project build. No legal conclusion |
| A36 | PRD | §6 "Measurement honesty" (≈4741); §6.9 heading (≈5515); NFR-32 (≈5517-5530) | Project produces no binary and never sees a crash | R | rewrite | Retitle §6.9 `Observability and diagnosability` and NFR-32 (suggested) `NFR-32: The project receives no crash reports by default, and the design accepts it`. The project now holds its own build, but receives no crash data unless the FR-189 decision adds a credential. Device-measurement limits (decision 10) still apply |
| A37 | PRD | §7 PL-53 (≈5735), PL-56 (≈5738), PL-62 (≈5744), PL-71 (≈5764) | No project binary; no project signer to pin; gates never see the user's binary; project never holds the binary | O/R | rewrite each (PL-53 keeps its ID; its substitute changes) | PL-53: the substitute is the project TestFlight plus the self-build path; in-app self-update stays impossible. PL-56: a pinned project signer identity is restored for the project build. PL-62: gates run against the project build's artifact, not against self-builds. PL-71: the project holds its build; crash data depends on FR-189 |
| A38 | PRD | PA-9 (≈5836) | Fork-and-build pipeline as the supported surface | R | rewrite | The project release pipeline (primary) and the fork pipeline (secondary) as supported surfaces; compensates PL-53 |
| A39 | PRD | §8.1-§8.3 (≈5889-5922): Verified evidence (≈5891), the raise rule (≈5910), the device table (≈5918) | Evidence must come from the validator's own fork; one person; no substitute validator possible | R | rewrite | Evidence may come from a project TestFlight build or a self-build, with the build recorded. Project TestFlight testers can now submit Verification evidence, so the raise rule is no longer tied to one person by the distribution model. The checklist (FR-207) stays the only form of evidence |
| A40 | PRD | §10.1 `Resolve 1Password canary` row (≈6022); §10.2 gitleaks paragraph (≈6060) | No upstream signing to canary; gitleaks "forced by fork-and-build" | R / U | ≈6022 rewrite; ≈6060 leave (premise phrase only) | ≈6022: the descendant is `Validate Secrets` for the project's release environment and for forks (FR-180) |
| A41 | PRD | NG-3 (≈6073) | No App Store listing and no project-published installable binary | R | rewrite | No App Store listing, no release-asset IPA and no download link. The project TestFlight is the distribution channel, with external distribution gated on L1, L2 and A1. Keep the OpenMinimed attribution |
| A42 | PRD | NG-4 (≈6074) | No project-held key, no project TestFlight, no project testers | O | remove (keep NG-4) | `Withdrawn (revision <date>): the project now publishes its own TestFlight build (decision 3).` |
| A43 | PRD | NG-12 (≈6082) | Updating means re-running the fork's pipeline | R | rewrite | No in-app self-update and no download path. Project-build users update through TestFlight; self-builders re-run their pipeline; the FR-188 notice is for self-builds |
| A44 | PRD | D-3 (≈6120), R-4 (≈6197-6200), OQ-24 (≈6303) | Critical Alerts unobtainable per Builder | R | rewrite | D-3 stays deferred until a project grant exists; revisit condition: the grant. R-4: unobtainable for self-builds; the project has applied or may apply. OQ-24 stays open, but "nearly every Builder" becomes "every user until the project holds the grant" |
| A45 | PRD | R-6 (≈6208-6212) | Supply-chain blast radius spread across every Builder's account | R | rewrite | Retitle and restate: a malicious upstream change now reaches the project's release environment (one high-value target) and every self-builder's credentialed run. Mitigations: protected environment, CODEOWNERS, SHA pins |
| A46 | PRD | OQ-58 (≈6342); OQ-61 (≈6345) | Should the fork template rebuild automatically; does the lead keep a local signing path | R / O | OQ-58: rewrite to RESOLVED; OQ-61: remove (keep ID, RESOLVED/withdrawn) | OQ-58: **RESOLVED.** Project uploads are scheduled upstream and the fork template keeps them enabled (FR-186). OQ-61: **RESOLVED.** Project signing runs only through `fastlane match` in the release environment; no personal local signing path is part of the project |
| A47 | ADD | §1.4 Bond removal (private API at upload) | Private API caught on TestFlight upload | U | leave (premise phrase only if present) | "breaking the distribution model" still holds; no change needed |
| A48 | ADD | §1.6 Shared module and target topology | App Group identifiers templated on the Builder's Team ID | R | rewrite | Fixed project identifiers for the project build; templated on the Builder's Team ID only for self-builds (AD-9) |
| A49 | ADD | §2.1 Server-generated alerts | Per-deployment APNs: each Builder mints their own key | R | rewrite | The project build has one bundle ID, so per-deployment APNs for project builds would need the project's key on every Backend, which is the rejected shared-key option, or a relay, which is also rejected. Per-deployment APNs stays viable for self-builds. Decision 7's deferral stands |
| A50 | ADD | §2.2 Critical Alerts | Unobtainable under fork-and-build; don't ask Builders | R | rewrite | One project application covers every project-build user (decision 4, reopened); the runtime upgrade stays; self-builds remain uniform on `.timeSensitive` |
| A51 | ADD | §2.3 Distribution | Project binaries rejected; fork-and-build resolves both conflicts | O | remove (replace section body) | Keep the heading. Body: superseded by the 2026-10-30 decision to publish a project TestFlight build. The two original grounds stay as release gates L1 and L2 (PRD §5.10); fork-and-build remains the self-build path |
| A52 | ADD | §3.2 Medtronic, "Standing constraint" | Fork-and-build is "load-bearing" because no project binary could ship Medtronic | R | rewrite | The copyright constraint becomes L2: Medtronic is compiled out of the project build until every holder grants permission; self-builds may include it |
| A53 | ADD | §3.3 The manufacturer framing | Every iOS user compiles their own binary, so the framing arguably fits all of them | R | rewrite | The framing applies to self-builders. For the project build the question joins L1's counsel review. No legal conclusion |
| A54 | EPI | FR inventory (≈197-254) and FR Coverage Map (≈554-611) | Titles mirror the PRD's fork-and-build FR titles | R | rewrite (sync only) | Copy every changed FR heading title verbatim into both lists (gates 13 and 14). No other edit |
| A55 | EPI | Infrastructure line (≈349) | Was fork-and-build; now project TestFlight | O | already applied | Verify only |
| A56 | EPI | Epic 8 goal (≈660, ≈1780) | Rewritten to project TestFlight | R | already applied | Verify only |
| A57 | EPI | Stories 8.1-8.3 (≈1784-1836) | Rewritten as 8.1′-8.3′ | R | already applied | Verify only |
| A58 | EPI | Stories 8.4-8.8 (≈1837-1918); 8.7 FR-204 bullet (≈1895) | 8.7 says "any committed signing material" | U (8.7 bullet R) | leave; 8.7 bullet verify | The 8.7 bullet is generic and stays true after A27. Edit it only if your A27 rewrite changes what the guard rejects, and record why |
| A59 | EPI | Stories 8.9-8.11 (≈1919-1973); 8.10 | 8.10 rewritten (TestFlight-first runbook) | U (8.10 R) | already applied | Verify only |
| A60 | EPI | Story 8.12 (≈1974-1991) | FR-189 crash-credential decision added | R | already applied | Verify only |
| A61 | EPI | Story 2.4 (≈1043-1060) | Critical Alerts `.critical` path if granted | R | already applied | Verify only |
| A62 | SPN | AD-9 rule (≈114) | One App Group, identifier templated on the Builder's Team ID | R | rewrite | "one App Group container: a fixed project identifier for the project build, templated on the Builder's Team ID only for self-builds." The sole-writer rule and the snapshot rule are unchanged |
| A63 | SPN | Stack table, `fastlane + match` row (≈243) | "Builder-side signing" | R | rewrite | `Project signing from a project-owned match repository in the release-gated environment; the same lanes serve self-builds` |
| A64 | SPN | Deferred table, "Observability and crash reporting" (≈294) | "No project telemetry exists to design; a Builder's own DSN is their choice." | R | rewrite | Deferred until the maintainer decides whether the project build carries a crash-reporting credential (FR-189). A self-builder's own DSN stays their choice. Also bump spine frontmatter `updated:` to the rewrite date |

**Numbering note.** A01-A64 map one-to-one, in order, to the 64 rows of Appendix A. Row An is the nth
row of Appendix A. Mixed-class Appendix rows (A34, A37, A40, A46, A58, A59) keep a per-item
disposition inside the row. Primary classes: 44 R, 8 U, 6 O, 6 mixed. Six epics rows (A55-A57,
A59-A61) are already applied.

### Table S: supplementary rows (same premise, missed by Appendix A)

| Row | File | Anchor (≈ line) | Current gist | Disposition | Replacement intent |
|---|---|---|---|---|---|
| S01 | PRD | §2.1 JTBD "*(Maintainer)* Ship this to iPhone users…" (≈67) | Without the project taking custody of signing credentials | rewrite | Ship to iPhone users through a project TestFlight build without exposing project signing material to forks or contributors |
| S02 | PRD | §2.2 Non-Users: "Anyone who wants an App Store download" (≈72) and "…a self-signed build" (≈73) | Every user builds and signs their own copy | rewrite | No App Store listing, and installs go through TestFlight; the unsilenceable-alarm item applies until the project holds Critical Alerts, and always to self-builds |
| S03 | PRD | FR-36 assumption (≈714) and A-7 (≈6378) | "a fork-and-build repo is public" | leave (premise phrase only) | "the repository is public" |
| S04 | PRD | 5.4 OQ-24 restatement (≈1528) | Caveat would show for "nearly every Builder" | rewrite | As A44 |
| S05 | PRD | §5.8 ATS paragraph (≈2486) and the FR-158-area open question (≈2853) | A Builder controls their own Info.plist | rewrite | The project controls the project build's Info.plist; a Builder controls a self-build's. The no-security-property-rests-on-ATS rule stays |
| S06 | PRD | FR-178 (≈3575, ≈3598) | Validated by DanielDanielson from their own fork; Critical Alerts unobtainable | rewrite | As A39 for validation and A09 for Critical Alerts |
| S07 | PRD | FR-176 open question (≈3661-3662) | A Builder could install a debug configuration through their own TestFlight | rewrite | The project build ships a release configuration; the question remains only for self-builds |
| S08 | PRD | §5.11 Description guard-class sentence (≈3972) and FR-204 ATS bullet (≈4094) | Guard class exists "because of fork-and-build" | leave (premise phrase only) | The `Package.swift`/plugin guard class protects the project's release environment and every self-build; ATS wording as S05 |
| S09 | PRD | FR-218 (≈4319); §10.3 CodeRabbit row (≈6031) and GitGuardian row (≈6034) | A bot bump propagates into every Builder's credentialed build | rewrite | …propagates into the project's release run and every self-builder's run |
| S10 | PRD | FR-237 consequence (≈4683) | Upstream holds no signing identity, so artifact scanning is unreachable | rewrite | As A29 |
| S11 | PRD | NFR-2 (≈4830), NFR-34 (≈5561), PL-39 (≈5701), PL-69 (≈5756), §9.1 Tier 4 (≈5949), §9.4 (≈5976, ≈5985), R-5 (≈6203-6206) | Validation only by one person from their own fork; distribution forbids a substitute validator | rewrite | As A39: validators may use project TestFlight builds. The single-person risk remains a staffing fact (decision 10), no longer a distribution constraint. Keep R-5 as a risk and change its mitigation |
| S12 | PRD | NFR-4 (≈4880), NFR-18 (≈5170), OQ-50 (≈6335) | Identifiers and access groups derived from the Builder's Team ID; one App ID set per Builder | rewrite | As A15: fixed for the project build, Team-ID-derived for self-builds. OQ-50 stays RESOLVED, worded for both |
| S13 | PRD | NFR-15 (≈5119), PD-38 (≈5812), P0.4 (≈6137), R-8 title (≈6218) | "under fork-and-build a Builder can install an older build" / older-Backend direction normal | leave (premise phrase only) | Users can install an older build (TestFlight keeps previous builds, and self-builders choose their commit) |
| S14 | PRD | NFR-22 (≈5265), PL-1 (≈5648), PL-23 (≈5680), §9.2 Entitlements row (≈5957) | Critical Alerts unobtainable; private API "breaking fork-and-build" | rewrite | As A09; for PL-1, "breaking TestFlight distribution" |
| S15 | PRD | PL-55 (≈5737), PL-58 (≈5740), PL-60 (≈5742), D-4 (≈6121) | Rebuild schedule behind the Builder's back; no developer account needed on Android; side-by-side costs every Builder | rewrite | PL-58: project-build users need no developer account; self-builders still do. PL-55 and PL-60/D-4: restate for the project (a second channel costs the project one more App ID) and for self-builders |
| S16 | PRD | §7 PL-66 row (≈5748) | Upstream holds no signing identity | rewrite | As A29 |
| S17 | PRD | §10.1 `Workflow Lint` row (≈6006) | "fork-and-build creates a guard class…" | leave (premise phrase only) | "self-builds and the project release run create a guard class…" |
| S18 | PRD | NG-6 (≈6076) | No telemetry or crash reports, "permanent … never will be" | rewrite | Holds today. Replace "permanent" with: the project build carries no crash-reporting credential unless the maintainer's FR-189 decision adds one, and that decision must update this row, FR-236 and the privacy document together. **Flag in Completion Notes:** NG-6's "permanent" conflicts with the proposal opening FR-189 |
| S19 | PRD | NG-11 (≈6081), NG-16 (≈6086) | Project makes no claim about any installed binary because every Builder compiles their own | rewrite | The project can identify its own build; claims about self-builds stay source-at-a-tag claims |
| S20 | PRD | §12.1 (≈6112), §12.3 P3 (≈6142), SM-1 (≈6158) | Runbook *is* the delivery mechanism; P3 is the "Builder pipeline"; SM-1 measures Builder install success | rewrite | P3 becomes the project pipeline plus docs; its acceptance includes an install from the TestFlight link by someone outside the project. SM-1 covers project-build installs, with self-build installs as a secondary measure |
| S21 | PRD | OQ-49 (≈6334) | "the project holds no secrets, ships no binary" | rewrite | Keep RESOLVED (public repo). Drop the false clause; the project's signing material lives only in the protected release environment |
| S22 | PRD | OQ-59 (≈6343), A-35 (≈6426), A-36 (≈6427) | Fork secret set; 30-day rebuild cadence assumed | rewrite | A-35 covers the self-build secret set; the project's secret set is FR-180's. A-36/OQ-59: cadence per FR-186 (weekly change-triggered, monthly unconditional); expiry thresholds stay open |
| S23 | PRD | OQ-62 (≈6346) | Builder who edits their fork | leave | Still a self-build question |

### Table C: parity-review fixes (exact text)

| Row | Anchor (≈ line) | Current text (gist) | Required text |
|---|---|---|---|
| C1a | 5.3 notes, "**Open question (OQ-20) — display banding from defaults.**" (≈1172) | "FR-47's severity banding currently colours from the default Alert Threshold set (55/70/180/250)… Confirm that colouring from defaults is acceptable…" | Replace the bullet with: `- **OQ-20 — RESOLVED.** Display banding never uses Alert Thresholds. FR-47, FR-52, FR-58 and FR-124 colour and bucket from the **Target Range** (Glossary), which has always-populated defaults of 55/70/180/250 and no provenance gate. SI-5 is unaffected: it governs only the **Alert Floor**, which still never fires on Alert Thresholds that neither the user nor their Backend set. The two sets stay separate stores and must not be unified.` |
| C1b | §15 "Dashboard, alerting and the wrist", OQ-20 (≈6299) | Same question, shorter | `- **OQ-20** — **RESOLVED.**` followed by the same resolution in one or two sentences |
| C1c | FR-40 consequence (≈830) | "the refresh concurrently reconciles glucose range, glucose unit, …" | "the refresh concurrently reconciles the Target Range, glucose unit, meal-intelligence config, analytics settings, Pump profile, Safety Limits and Alert Thresholds — the Target Range and the Alert Thresholds as two separate objects from two separate endpoints." (keeps "In Backend-optional mode none of these are attempted.") Also check FR-155 (≈2774) "a target glucose range" and change it to "the Target Range" |
| C2a | FR-164 first consequence (≈3100) | "The Sign-in stage carries the label "Don't run a server?" and a control reading "Use without a server" (identifier `onboarding_continue_without_server`)…" | "The Backend stage (index 3) carries the label "Don't run a server?" and a control reading "Use without a server" (identifier `onboarding_continue_without_server`), matching Android's `ServerSetupPage`. It is always present and never disabled, whatever the state of the connection test (FR-159)." Keep the rest of the bullet (the "server" wording and testTag sentences) |
| C2b | FR-159 consequence "**Why this is a requirement and not a nicety.**" (≈2951) | "…and FR-164's "Use without a server" lives on the following stage — so a user … can never leave stage 3." | Rewrite the bullet so FR-164 owns the control on this stage: without the escape, the stage is a trap ("Next" disabled until a test succeeds, "Skip" does not reach it), so FR-164's "Use without a server" lives on the Backend stage itself, where the failed Backend attempt happens. Keep the test sentence. The bold first sentence of ≈2950 may stay, with "(FR-164)" added |
| C3a | PD-41, last sentence of the "Notes" cell (≈5815) | "A Medtronic equivalent of the validity gate must be identified before that **Driver** leaves Beta" | "Medtronic ships two sensor-validity gates of its own, the history-path `SG_SENTINELS` set and the live-path non-finite SFLOAT rejection, both ported under FR-32; the annunciation gate is the outstanding one, a named TODO in the Android source, and it must be ported or explicitly waived before that **Driver** leaves Beta" |
| C3b | OQ-7, closing sentence (≈6281) | "A Medtronic equivalent of the sensor-validity gate must be identified before that Driver leaves Beta." | "Medtronic's two shipped sensor-validity gates (the `SG_SENTINELS` set and the non-finite SFLOAT rejection) are owned by FR-32; the annunciation gate is the outstanding one, and it must be ported or explicitly waived before that Driver leaves Beta." |

C3 cross-check: FR-32 (≈653 and ≈776) already lists all three Medtronic gates correctly. Do not edit
it, but make C3a/C3b consistent with it. Gate 11 needs the exact phrase "the annunciation gate is the
outstanding one" at least twice.

### Revision log format (AC 6)

Put this directly after decision table §0.1 and before `## 1. Vision`, in place of the deleted
amendment blockquote:

```markdown
### 0.2 Revision Log

| Date | Change | Source |
|---|---|---|
| 2026-08-10 | PRD finalised. | Discovery and the parity, safety and downstream reviews |
| <YYYY-MM-DD> | <one paragraph: distribution moves to a project TestFlight build (internal first; public link gated on L1, L2, A1, E1); fork-and-build becomes the advanced self-build path; decisions 3, 4, 6 and 9 rewritten; NG-4 withdrawn; §5.10 and §5.12 rewritten; ledger, matrices, non-goals, risks, open questions and the addendum updated. Parity-review fixes: C1 (OQ-20 resolved; FR-40 reconciles the Target Range), C2 (FR-164's escape hatch on the Backend stage), C3 (PD-41 and OQ-7 name Medtronic's two shipped gates and the outstanding annunciation gate). The interim amendment note is removed.> | Sprint Change Proposal 2026-10-30 |
```

The dated row must be one table row on one line, and must contain "TestFlight", "C1", "C2" and "C3"
(gate 3). Use the actual date of the rewrite in both the row and the frontmatter `updated:`. Do not
put any gate-5 phrase in it. Also update §0.1's lead-in sentence ("Ten product decisions … treated as
settled") to say that decisions 3, 4, 6 and 9 were revised on that date (see 0.2).

### Gates (from the repo root): what each proves, and which fail today

| # | Proves | Today |
|---|---|---|
| 1 | Amendment block gone | **fails** |
| 2 | `### 0.2 Revision Log` heading exists | **fails** |
| 3 | A dated log row mentions TestFlight, C1, C2, C3 | **fails** |
| 4 | PRD `updated:` bumped | **fails** |
| 5 | Obsolete premise phrases gone from PRD, addendum, spine | **fails** (≈80 hits) |
| 6 | Addendum/spine Team-ID, signing and DSN text rewritten | **fails** |
| 7 | Spine `updated:` bumped | **fails** |
| 8 | C1: OQ-20 no longer bands from Alert Threshold defaults | **fails** |
| 9 | C1: FR-40 reconciles the Target Range | **fails** |
| 10 | C2: FR-164 on the Backend stage; FR-159 note agrees | **fails** |
| 11 | C3: "must be identified" gone; the annunciation phrase present ×2 | **fails** |
| 12 | L1/L2 defined in bold | **fails** |
| 13 | epics `**FR-N**:` titles = PRD titles (FR-179-196, FR-219-237) | passes (regression guard) |
| 14 | epics Coverage Map titles = PRD titles (same range) | passes (regression guard) |
| 15 | No `/Users/` path in planning artifacts | passes (regression guard) |
| 16 | No new maintainer real name (prd.md stays ≤ 7 existing copyright-string hits) | passes (regression guard) |
| 17 | Only the four planning files, this story and sprint-status changed | passes in a fresh worktree (regression guard); fails in the main checkout because of unrelated local edits |

Gates 13 and 14 check only the 5.10 and 5.12 FR ranges on purpose. FR-212's epics title already differs
from the PRD, and that is out of scope here.

### References

- Proposal: `_bmad-output/planning-artifacts/sprint-change-proposal-2026-10-30.md` (§2.1 gates, §2.5
  C1-C3 status, §4.1 amendment content, §4.3-§4.7 rewritten Epic 8 stories, Appendix A).
- Parity review C1-C3 evidence: `_bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/review-parity.md`
  (sections "C1", "C2", "C3").
- Epics: `_bmad-output/planning-artifacts/epics.md` (Story 8.13, and Stories 8.1′-8.3′, 8.10′, 8.12′ for
  the rewritten wording you should stay consistent with).

## Dev Agent Record

### Agent Model Used

OpenAI Codex (Paige technical-writing role supplied in the task prompt)

### Debug Log References

- Cycle 3: ran all 17 frontmatter gates twice after implementation; each run passed gates 1–17 from the repository root. `git diff --check` passed.
- Compared pre-existing PRD identifier sets against `HEAD`: no FR, NFR, PL, PD, PA, NG, D, R, OQ, A or SI identifier was removed; FR heading count remains 237.
- Baseline frontmatter gates: 1-4, 8-12 and 13-14 failed; 5-7, 15-17 passed.
- Current frontmatter gates 1-17 pass when run via Ruby YAML parsing from the repository root.
- Hindsight page listing/search could not connect (EHOSTUNREACH); no repository knowledge pages were available.
- Customization resolver was absent at `_bmad/scripts/resolve_customization.py`.

### Completion Notes List

- Reconciled project TestFlight distribution across the PRD, addendum and architecture spine. The project build uses fixed identifiers and protected project signing; the advanced self-build path uses each Builder’s credentials.
- Defined L1, L2, A1 and E1 once in PRD §5.10. None is declared resolved, and Critical Alerts remains ungranted. OQ-63 records the open artifact-scanning decision without selecting a scanner.
- Reworked hardware validation around provenance-recorded project TestFlight builds or self-builds. The current single-validator risk remains a staffing fact.
- NG-6’s former “permanent” no-crash-report wording conflicted with the open FR-189 decision; NG-6, FR-236 and the privacy-document requirement now require coordinated updates if that decision changes.
- Preserved all pre-existing FR, NFR, PL, PD, PA, NG, D, R, OQ, A and SI identifiers; the PRD still has 237 FR headings. Added OQ-63 for project-artifact scanning.
- Verified epics infrastructure and Epic 8 descriptions already reflected the project TestFlight change; synchronized FR-179’s title in both epics inventories without changing any story body.

- Final tracked diff: 5 files, 294 insertions and 317 deletions (`git diff --stat`). The story record is untracked in this checkout and is also part of the allowed file surface.
- The changed-file surface is the PRD, addendum, architecture spine, epics FR title lists, this story record and sprint status; no code, workflow or dependency file changed.

#### Appendix A, supplementary, and parity dispositions

- [x] A01 — obsolete claim replaced; ID retained — PRD §0.1 decision 3.
- [x] A02 — rewritten and checked — PRD decision 4.
- [x] A03 — rewritten and checked — PRD decision 6.
- [x] A04 — obsolete claim replaced; ID retained — PRD decision 9.
- [x] A05 — rewritten and checked — PRD §1 Vision, the "It ships the way…" paragraph; UJ-3 Marcus.
- [x] A06 — rewritten and checked — PRD §3 Glossary: Builder, Fork-and-build.
- [x] A07 — rewritten and checked — PRD FR-? identifier-stability consequence, "A hardware step validates identifier stability…".
- [x] A08 — rewritten and checked — PRD FR-22 Description and consequence "Medtronic renders Beta".
- [x] A09 — rewritten and checked — PRD FR-66 and the forced-loss restatements.
- [x] A10 — rewritten and checked — PRD FR-150, NFR-20.
- [x] A11 — rewritten and checked — PRD Device fingerprint consequence.
- [x] A12 — rewritten and checked — PRD §5.10 Description.
- [x] A13 — obsolete claim replaced; ID retained — PRD FR-179 heading + statement.
- [x] A14 — rewritten and checked — PRD FR-180.
- [x] A15 — rewritten and checked — PRD FR-181.
- [x] A16 — rewritten and checked — PRD FR-182.
- [x] A17 — rewritten and checked — PRD FR-183.
- [x] A18 — rewritten and checked — PRD FR-184.
- [x] A19 — retained and verified — PRD FR-185.
- [x] A20 — rewritten and checked — PRD FR-186.
- [x] A21 — retained and verified — PRD FR-187.
- [x] A22 — rewritten and checked — PRD FR-188.
- [x] A23 — rewritten and checked — PRD FR-189.
- [x] A24 — retained and verified — PRD FR-195.
- [x] A25 — rewritten and checked — PRD FR-196.
- [x] A26 — retained and verified — PRD FR-199, FR-208.
- [x] A27 — rewritten and checked — PRD FR-204 consequences: Critical Alerts entitlement, signing material.
- [x] A28 — retained and verified — PRD FR-216 consequence on the older-Backend direction.
- [x] A29 — rewritten and checked — PRD 5.11 notes "Artifact-level scanning"; §10.2 PL-66 revisit discussion.
- [x] A30 — rewritten and checked — PRD §5.12 Description, FR-223, FR-226 supported-versions bullet.
- [x] A31 — rewritten and checked — PRD FR-232 consequences and §5.12 acknowledgments paragraph.
- [x] A32 — rewritten and checked — PRD FR-234.
- [x] A33 — rewritten and checked — PRD FR-236 heading + body.
- [x] A34 — rewritten and checked — PRD §5.10 Parity-Ledger list: PL-53/PL-58, PL-54, PL-63.
- [x] A35 — rewritten and checked — PRD 5.12 notes: counsel review of the manufacturer framing; R-21; OQ-56.
- [x] A36 — rewritten and checked — PRD §6 "Measurement honesty"; §6.9 heading; NFR-32.
- [x] A37 — rewritten and checked — PRD §7 PL-53, PL-56, PL-62, PL-71.
- [x] A38 — rewritten and checked — PRD PA-9.
- [x] A39 — rewritten and checked — PRD §8.1-§8.3: Verified evidence, the raise rule, the device table.
- [x] A40 — rewritten and checked — PRD §10.1 `Resolve 1Password canary` row; §10.2 gitleaks paragraph.
- [x] A41 — rewritten and checked — PRD NG-3.
- [x] A42 — obsolete claim replaced; ID retained — PRD NG-4.
- [x] A43 — rewritten and checked — PRD NG-12.
- [x] A44 — rewritten and checked — PRD D-3, R-4, OQ-24.
- [x] A45 — rewritten and checked — PRD R-6.
- [x] A46 — rewritten and checked — PRD OQ-58; OQ-61.
- [x] A47 — retained and verified — ADD §1.4 Bond removal (private API at upload).
- [x] A48 — rewritten and checked — ADD §1.6 Shared module and target topology.
- [x] A49 — rewritten and checked — ADD §2.1 Server-generated alerts.
- [x] A50 — rewritten and checked — ADD §2.2 Critical Alerts.
- [x] A51 — obsolete claim replaced; ID retained — ADD §2.3 Distribution.
- [x] A52 — rewritten and checked — ADD §3.2 Medtronic, "Standing constraint".
- [x] A53 — rewritten and checked — ADD §3.3 The manufacturer framing.
- [x] A54 — rewritten and checked — EPI FR inventory and FR Coverage Map.
- [x] A55 — previously applied; verified — EPI Infrastructure line.
- [x] A56 — previously applied; verified — EPI Epic 8 goal.
- [x] A57 — previously applied; verified — EPI Stories 8.1-8.3.
- [x] A58 — previously applied; verified — EPI Stories 8.4-8.8; 8.7 FR-204 bullet.
- [x] A59 — previously applied; verified — EPI Stories 8.9-8.11; 8.10.
- [x] A60 — previously applied; verified — EPI Story 8.12.
- [x] A61 — previously applied; verified — EPI Story 2.4.
- [x] A62 — rewritten and checked — SPN AD-9 rule.
- [x] A63 — rewritten and checked — SPN Stack table, `fastlane + match` row.
- [x] A64 — rewritten and checked — SPN Deferred table, "Observability and crash reporting".
- [x] S01 — rewritten and checked — PRD §2.1 JTBD "*(Maintainer)* Ship this to iPhone users…".
- [x] S02 — rewritten and checked — PRD §2.2 Non-Users: "Anyone who wants an App Store download" and "…a self-signed build".
- [x] S03 — rewritten and checked — PRD FR-36 assumption and A-7.
- [x] S04 — rewritten and checked — PRD 5.4 OQ-24 restatement.
- [x] S05 — rewritten and checked — PRD §5.8 ATS paragraph and the FR-158-area open question.
- [x] S06 — rewritten and checked — PRD FR-178.
- [x] S07 — rewritten and checked — PRD FR-176 open question.
- [x] S08 — rewritten and checked — PRD §5.11 Description guard-class sentence and FR-204 ATS bullet.
- [x] S09 — rewritten and checked — PRD FR-218; §10.3 CodeRabbit row and GitGuardian row.
- [x] S10 — rewritten and checked — PRD FR-237 consequence.
- [x] S11 — rewritten and checked — PRD NFR-2, NFR-34, PL-39, PL-69, §9.1 Tier 4, §9.4, R-5.
- [x] S12 — rewritten and checked — PRD NFR-4, NFR-18, OQ-50.
- [x] S13 — rewritten and checked — PRD NFR-15, PD-38, P0.4, R-8 title.
- [x] S14 — rewritten and checked — PRD NFR-22, PL-1, PL-23, §9.2 Entitlements row.
- [x] S15 — rewritten and checked — PRD PL-55, PL-58, PL-60, D-4.
- [x] S16 — rewritten and checked — PRD §7 PL-66 row.
- [x] S17 — rewritten and checked — PRD §10.1 `Workflow Lint` row.
- [x] S18 — rewritten and checked — PRD NG-6.
- [x] S19 — rewritten and checked — PRD NG-11, NG-16.
- [x] S20 — rewritten and checked — PRD §12.1, §12.3 P3, SM-1.
- [x] S21 — rewritten and checked — PRD OQ-49.
- [x] S22 — rewritten and checked — PRD OQ-59, A-35, A-36.
- [x] S23 — retained and verified — PRD OQ-62.
- [x] C1a — exact parity correction verified — PRD §5.3 OQ-20.
- [x] C1b — exact parity correction verified — PRD §15 OQ-20.
- [x] C1c — exact parity correction verified — PRD FR-40 and FR-155.
- [x] C2a — exact parity correction verified — PRD FR-164.
- [x] C2b — exact parity correction verified — PRD FR-159.
- [x] C3a — exact parity correction verified — PRD PD-41.
- [x] C3b — exact parity correction verified — PRD OQ-7.

### File List

- `_bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md`
- `_bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/addendum.md`
- `_bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md`
- `_bmad-output/planning-artifacts/epics.md`
- `_bmad-output/implementation-artifacts/8-13-rewrite-the-planning-artifacts-for-project-distribution.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`

### PM decisions on drafting open points (2026-11-01)
- Rows Appendix A marks obsolete but that are cited elsewhere (FR-179, decisions 3 and 9, NG-4, OQ-61, addendum §2.3): KEEP the IDs and replace the text. Never delete an ID that other documents cite.
- The C2 fix includes rewriting FR-159's note so it agrees with FR-164.
- NG-6 vs FR-189: the sprint change reopened FR-189, so reword NG-6 to agree with it rather than calling "no crash reports" permanent. Record this in the revision log.
- Appendix A line numbers are stale (about 2 off). Locate rows by anchor text, not by line number.
- budget: CONTINUATION_REQUIRED sha256:d4a35f4c6ed06dc0e6c1758f4abaf1b52786ec0e6a7f93ea2f3483bf6fc80341 cycle 1 2026-11-01T15:45:17Z
- budget: CONTINUATION from cycle 1 sha256:d4a35f4c6ed06dc0e6c1758f4abaf1b52786ec0e6a7f93ea2f3483bf6fc80341 trigger=WORKER_SIGNAL usage=unobserved/n/a cycle 2 2026-11-01T15:45:28Z


### Cycle 2 handoff record (2026-11-01)

- Replaced §5.10 Description with project TestFlight distribution, fixed project identifiers, release-environment signing, and the L1/L2/A1/E1 table. Rewrote FR-179 to retain the identifier and describe fork-and-build as the advanced self-build path.
- Applied partial wording changes elsewhere in the PRD. These have not been fully proofread and must be reviewed and corrected by anchor before completion. Appendix A/S row checklist is not yet complete.
- Hindsight knowledge listing/search failed with EHOSTUNREACH; the customization resolver named in the activation instructions was absent.
- Ran all 17 frontmatter gates from the repository root after these edits: gates 1-12 and 15-17 pass; gates 13-14 fail because the FR title inventories in epics.md are not yet synchronized with PRD titles. Gate results are not acceptance completion.
- Continue cycle 3 with the story tables as authority. First repair the inaccurate validation/security/risk phrasing and complete the remaining A/S rows, then verify addendum, spine and epics before rerunning gates.
- budget: CONTINUATION_REQUIRED sha256:36417116b54b24d0c2f21c00213bc51e81b521d6dbd18f3f073ae346ec83e392 cycle 2 2026-11-01T15:46:42Z
- budget: CONTINUATION from cycle 2 sha256:36417116b54b24d0c2f21c00213bc51e81b521d6dbd18f3f073ae346ec83e392 trigger=WORKER_SIGNAL usage=unobserved/n/a cycle 3 2026-11-01T15:47:04Z
