---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/8-5-the-five-required-checks.md.stamp.json
persona: dev
memory_mode: advisory
gates:
  - "bash scripts/ci-local.sh --self-test"
  - "/bin/bash scripts/ci-local.sh --self-test"
  - "bash scripts/ci-local.sh workflow-pins"
  - "bash scripts/ci-local.sh workflow-policy"
  - "swift build"
  - "swift test"
max_cycles: 3
---

# Story 8.5: The five Required Checks

Status: done

<!-- Planning note (for the maintainer): PROTECTED PATH. This adds four workflow files and changes
`.github/workflows/ios.yml`, `scripts/ci-local.sh` and `CONTRIBUTING.md` (lead-only in
CODEOWNERS). It goes through normal review and the maintainer merges; the PM does not.

No Apple signing credential and no App Store Connect secret is needed or referenced. Nothing in
the five checks signs anything: pull-request builds stay unsigned Simulator builds. Signing,
`release-gated`, the secret set and App tokens (FR-180, FR-183-FR-185, and FR-199's App-token
bullet) belong to Story 8.1 and are deferred there explicitly.

Scope against 8.6. The epics give 8.6 the analyzers (CodeQL, Semgrep, gitleaks, OSV, actionlint,
zizmor). A Required Check that runs nothing would be a permanently green name, which the PRD
warns about by name. So this story gives every one of the five real content, and takes the cheap,
fully specified parts of FR-201, FR-202 and FR-203 with it: OSV-Scanner, actionlint plus
shellcheck plus the pin and secrets guards, and zizmor plus the backstop. 8.6 keeps CodeQL Swift,
Semgrep `p/secrets`, gitleaks, the zero-analyzed-files rule and the documentation statements,
and inherits the rest as verification. The PM should trim 8.6's scope accordingly.

Every tool pin below (actionlint, shellcheck, OSV-Scanner, zizmor) was checked against its
upstream release or PyPI when this story was written.

Branch protection is a manual step. After the PR's five checks have reported once, the maintainer
adds them to the develop ruleset (exact list and order of operations in Dev Notes). The
roster-verification step fails until that is done, by design.

Estimate: ~650 reviewable lines (four ~45-line workflows, ~350 lines of `ci-local.sh` and a
Ruby helper, half of it self-tests, plus small config files). Route: NOT chosen here; the PM
routes via /v1/route. -->

## Story

As a maintainer,
I want a fixed, named gate roster,
so that branch protection has stable strings to key on.

## Acceptance Criteria

From epics.md Story 8.5 (FR-197, FR-198, FR-199, FR-213), with the hosted gates of FR-201,
FR-202 and FR-203 described above. AC numbering is local to this file.

1. **Exactly five Required Checks, by job name (FR-197).** The roster is these five job
   `name:` strings, each defined in exactly one job across `.github/workflows/`:

   | Required Check | Workflow file | Shape | Runner, timeout |
   |---|---|---|---|
   | `Static Analysis Gate` | `static-analysis.yml` (new) | unconditional | `macos-26`, 15 |
   | `Dependency Scan Gate` | `dependency-scan.yml` (new) | `if: always()` aggregation | `ubuntu-latest`, 5 |
   | `Workflow Lint` | `workflow-lint.yml` (new) | unconditional | `ubuntu-latest`, 5 |
   | `Workflow Security` | `workflow-security.yml` (new) | unconditional | `ubuntu-latest`, 5 |
   | `iOS Gate` | `ios.yml` (exists) | `if: always()` aggregation | `ubuntu-latest`, 5 |

   Every other job is non-required and keeps its own status: `Detect iOS-Relevant Changes`,
   `Build & Test`, `UI Tests (Simulator)` (existing), `Detect Dependency Changes` and
   `OSV-Scanner` (new). `scripts/ci-local.sh` holds the canonical roster in one array,
   `REQUIRED_CHECKS`, and `CONTRIBUTING.md` publishes it.
2. **Always reported, fail closed (FR-198).**
   - The three unconditional checks have no `if:`, no `needs:`, and their workflow's
     `pull_request` trigger has no `paths` or `paths-ignore`.
   - The two aggregation checks are `if: always()`, `needs: [<detect job>, <work job>]`, and
     run `bash scripts/ci-local.sh gate-verdict` with `needs.*.result` passed through `env:`,
     never interpolated into `run:`. `gate-verdict` takes a new `GATE_NAME` env (default
     `iOS Gate`) used only in its messages; its five-branch decision is unchanged: detect not
     `success` fails; `schedule` or `workflow_dispatch` requires a successful work job; push or
     pull request with nothing relevant changed passes with the skip reason; work `success`
     passes; anything else fails.
   - No Required Check job uses `continue-on-error`.
3. **Each check runs something real, through the one script (FR-213).** Every gate step is a
   `bash scripts/ci-local.sh <command>` call; workflows hold no gate logic of their own. New
   commands, each exiting non-zero with a named message (never a partial pass) when its tool is
   missing or the wrong version:
   - `static-analysis`: `safety_guards.sh`, `driver_guards.sh`, and both `--self-test`s, which
     carry the Driver delivery-verb scan (FR-31) and the direct-system-time lint (FR-61) that
     FR-197 hosts here. It prints one line saying CodeQL, Semgrep and gitleaks are not wired yet.
   - `dependency-scan`: requires `osv-scanner` 2.3.3, runs
     `osv-scanner scan source --recursive --no-ignore --config=osv-scanner.toml .` (FR-201's
     flags). Any known vulnerability fails. `osv-scanner.toml` is committed with zero
     `[[IgnoredVulns]]` and a header recording the first scan's result and resolved package
     count.
   - `workflow-lint`: requires `actionlint` 1.7.7 and `shellcheck` 0.10.0; runs
     `actionlint -oneline -shellcheck=<that shellcheck>` with no file arguments, then
     `workflow-pins` (existing SHA-pin guard), then the composite-action secrets guard (any
     `${{ secrets.` under `.github/actions/**` on a line whose first non-space character is not
     `#` fails; a missing `.github/actions` passes and says so), then `workflow-policy`, then
     `required-checks`.
   - `workflow-security`: requires `zizmor` 1.5.2; runs `zizmor --config zizmor.yml
     --min-severity=medium .github/workflows/` (plus `.github/actions/` only when it exists),
     then the `pull_request_target` backstop (FR-203): any workflow that has a
     `pull_request_target` trigger and an `actions/checkout` whose `with.ref` or
     `with.repository` mentions `github.event.pull_request.head` fails. YAML 1.1's bare `on:`
     parsing to `true` is handled.
   - `install-ci-tools <workflow-lint|workflow-security|dependency-scan>`: Linux x86_64 only
     (named failure elsewhere); downloads into `.build/ci-tools/` and verifies each artifact
     with `sha256sum -c -` before use. Pins in Dev Notes. CI calls this; local users install
     the same versions themselves.
4. **Workflow policy, offline (FR-197, FR-198, FR-199).** `workflow-policy` parses every file
   in `.github/workflows/` and fails, listing every offender, when:
   - a roster name is missing, or defined by more than one job;
   - a Required Check job has `continue-on-error`, or the shape in AC 2 does not hold;
   - an aggregation job's `run:` text contains `needs.`;
   - any job anywhere lacks `timeout-minutes`;
   - a workflow lacks `concurrency`, or its group does not contain `github.ref`;
   - a workflow with a `pull_request` trigger has workflow-level `permissions` other than
     exactly `contents: read`, a job-level permission other than `contents: read` or (only on a
     job whose name starts with `Detect `) `pull-requests: read`, any `secrets.` reference, or a
     `pull_request_target` trigger;
   - an `actions/checkout` step lacks `with.persist-credentials: false`.
   It runs on a clean checkout of this branch with no network, no tools beyond Ruby, and
   passes.
5. **The roster is checked against the real ruleset (FR-197).** `required-checks [RULES_JSON]`
   reads the roster between `<!-- required-checks:begin -->` and `<!-- required-checks:end -->`
   in `CONTRIBUTING.md` and fails unless it equals `REQUIRED_CHECKS`. It then reads the develop
   rules JSON from the given file, or fetches
   `https://api.github.com/repos/${GITHUB_REPOSITORY:-lumose-health/ios-unofficial}/rules/branches/develop`
   (with `Authorization: Bearer $GH_TOKEN` when set; any HTTP or parse failure fails closed).
   It collects every `context` from rules of type `required_status_checks` and fails unless that
   set equals the roster exactly. Any entry with an `integration_id` other than `15368`
   (GitHub Actions) fails, so a different app cannot satisfy a check by name. In CI this runs
   inside `Workflow Lint` with `GH_TOKEN: ${{ github.token }}`.
6. **Fork pull requests get the same verdict (FR-199).** All five trigger on plain
   `pull_request`; none references a secret; every workflow is `permissions: contents: read` at
   the top; detect jobs alone add `pull-requests: read`; every checkout sets
   `persist-credentials: false`; no job signs, and none references a signing identity,
   certificate, provisioning profile or App Store Connect key. `Workflow Security` uses
   `GH_TOKEN: ${{ github.token }}` (read-only on a fork) for zizmor's online audits. All of this
   is enforced by AC 4, not by convention.
7. **Dependency Scan triggers (FR-201).** `dependency-scan.yml` runs on `pull_request` and
   `push` to develop and main, `workflow_dispatch`, and `schedule: cron '0 6 * * 1'`.
   `Detect Dependency Changes` runs the paths filter only on push and pull request and outputs
   `should_scan` as `'false'` when the filter did not run, so the gate always has a value; on
   `schedule` and `workflow_dispatch` the gate requires a successful scan (AC 2). The `deps`
   filter: `Package.swift`, `Package.resolved`, `**/Podfile.lock`,
   `**/*.xcodeproj/project.pbxproj`, `osv-scanner.toml`, `.github/workflows/dependency-scan.yml`,
   `scripts/ci-local.sh`.
8. **Concurrency.** Each new workflow declares `concurrency: group: <workflow-name>-${{
   github.ref }}`, `cancel-in-progress: true` (FR-197). `ios.yml` keeps its current
   pull-request-only cancellation (Dev Notes says why); the policy accepts either.
9. **Documented once.** `CONTRIBUTING.md` (new; the full contributor guide is later work)
   contains a short "Required checks" section: the five names between the markers, one per
   bullet, a sentence that branch protection on `develop` requires exactly these, and that
   `bash scripts/ci-local.sh <command>` reproduces each one. `ci-local.sh usage` lists every
   command and names the gates that are still to come (CodeQL, Semgrep, gitleaks).
10. **Self-tests, under both shells.** `ci-local.sh --self-test` covers every new failure path
    with fixtures under `.build/` and no network and no tools beyond Ruby: `gate-verdict` with
    `GATE_NAME=Dependency Scan Gate` on skip, schedule-skip and failure; the composite-secrets
    guard (hit, commented line, missing directory); each `workflow-policy` violation in AC 4
    plus a passing fixture and an `on:`-as-`true` fixture; `required-checks` (match, missing,
    extra, wrong `integration_id`, no status-check rule, `CONTRIBUTING.md` drift, unreadable
    JSON); the backstop (hit and clean); and each tool-requiring command failing with its named
    message when the tool is absent from `PATH`. It passes under `bash` (5) and `/bin/bash`
    (3.2).
11. **Gates.** All six frontmatter gates pass locally. On the PR itself, all five Required
    Checks report, and all pass except `Workflow Lint`'s roster step, which passes once the
    maintainer has updated the ruleset (Dev Notes). The Dev Agent Record lists the first
    OSV-Scanner and zizmor results, any finding fixed, and the reviewable diff size.

## Tasks / Subtasks

- [x] Task 1: `scripts/ci-local.sh` (AC 1-5, 9, 10)
  - [ ] `REQUIRED_CHECKS=('Static Analysis Gate' 'Dependency Scan Gate' 'Workflow Lint'
        'Workflow Security' 'iOS Gate')` near the other lists.
  - [ ] `GATE_NAME` in `gate_verdict`; keep every existing message substring the self-test
        asserts, or update the assertions in the same change.
  - [ ] Commands: `static-analysis`, `dependency-scan`, `workflow-lint`, `workflow-policy`,
        `workflow-security`, `required-checks`, `install-ci-tools`. Update `usage`.
  - [ ] Self-test cases (AC 10).
- [x] Task 2: Ruby helper for YAML and JSON work, e.g. `scripts/lib/workflow_policy.rb`, called
      by `ci-local.sh` with explicit arguments (policy, backstop, required-checks comparison).
      Ruby 2.6 compatible (see pitfalls).
- [x] Task 3: workflows (AC 1, 2, 6-8)
  - [ ] `.github/workflows/static-analysis.yml`: job `Static Analysis Gate`.
  - [ ] `.github/workflows/dependency-scan.yml`: jobs `Detect Dependency Changes`,
        `OSV-Scanner`, `Dependency Scan Gate`.
  - [ ] `.github/workflows/workflow-lint.yml`: job `Workflow Lint` (install tools, then
        `workflow-lint`, with `GH_TOKEN: ${{ github.token }}` for the roster step).
  - [ ] `.github/workflows/workflow-security.yml`: job `Workflow Security`.
  - [ ] `.github/workflows/ios.yml`: add `GATE_NAME: iOS Gate` to the gate step's `env`.
        Nothing else changes unless actionlint or zizmor finds something; record any fix.
- [x] Task 4: config files: `osv-scanner.toml`, `zizmor.yml` (no allowlist entries; any entry
      added later needs one audit id and a written rationale), `CONTRIBUTING.md`.
- [ ] Task 5: run the gates; push; read the PR's own five checks and record their first results.

## Dev Notes

### Known pitfalls (read before writing code)

- The worker cannot compile, so write carefully. A `switch` after any statement in a function or getter needs `return switch`. Test functions that `await` must be `async`. In Swift Testing, `#expect` over a key-path closure such as `allSatisfy(\.x)` is treated as throwing, so bind it to a `let` first. Typed-throws closures can't call `NSLock.withLock` and throw a typed error; use `lock()`/`defer unlock()`. In an init, assign every stored property before reading any `self` property.
- AppFeature and the other packages also build for macOS (`swift test` runs on macOS in CI). Wrap iOS-only APIs in `#if os(iOS)`.
- Never write a numeric safety constant inline, and never disguise one. Literals equal to safety constants (for example 18, 20, 21, 55, 58, 61, 70, 180, 250) trip the guard. Hex colour components count too.
- Swift 6 strict concurrency. Tests that check state that settles asynchronously must wait with the existing `eventually` helper, not assert immediately.
- Code comments must not mention stories, epics, AC numbers, agents or cycles. No private UIKit API.
- Diff budget: about 800 reviewable lines.

Specific to this story:
- **bash 3.2 and 5.** `/bin/bash` on macOS is 3.2. No `mapfile`/`readarray`, no `declare -A`,
  no `${var,,}`, no `[[ -v name ]]`, no negative array indices, no `;&`. Under `set -u`, expand
  arrays as `${arr[@]+"${arr[@]}"}`, as the script already does. Quote array elements that
  contain spaces (`'iOS Gate'`).
- **Ruby 2.6.** The local `/usr/bin/ruby` is 2.6.10. No `filter_map`, no `tally`, no numbered
  block parameters (`_1`), no pattern matching, no endless methods, no `Hash#except`. Use
  `YAML.safe_load(text, aliases: false)` exactly as `pin_scan` does. The CI runners have newer
  Ruby; write for the older one.
- **`on:` is `true`.** Psych reads a bare `on:` key as the boolean `true`. Look up the trigger
  map under both `"on"` and `true`.
- **GitHub expressions in YAML.** `if: always()` may also be written `if: ${{ always() }}`;
  accept both. Never put `${{ needs.* }}` or `${{ github.event.* }}` inside a `run:` block.

### Tool pins (verified when this story was written)

| Tool | Artifact | sha256 |
|---|---|---|
| actionlint 1.7.7 | `https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_1.7.7_linux_amd64.tar.gz` | `023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757` |
| shellcheck 0.10.0 | `https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz` | `6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87` |
| OSV-Scanner 2.3.3 | `https://github.com/google/osv-scanner/releases/download/v2.3.3/osv-scanner_linux_amd64` (a bare binary; `chmod +x`) | `777b4bb7ddd10bdcc8a1aa398d37d05e91e866e7586f9cff3fca2f72b8153033` |
| zizmor 1.5.2 | PyPI wheel `zizmor-1.5.2-py3-none-manylinux_2_28_x86_64.whl` | `0c5f656106c430748858ae459c41c9eed09a1e01e5f42015d80c8fe34740d173` |

zizmor installs into a venv: `python3 -m venv .build/ci-tools/zizmor-venv`, then
`pip install --no-deps --require-hashes -r <requirements file>` where the file holds
`zizmor==1.5.2 --hash=sha256:<above>`. The PRD also pins PyYAML 6.0.2 for the backstop; this
story writes the backstop in Ruby (already used by `pin_scan`), so PyYAML is not needed. Record
that deviation.

Action references: reuse the SHAs already in `ios.yml` and add no new third-party action:
`actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0`,
`dorny/paths-filter@7b450fff21473bca461d4b92ce414b9d0420d706 # v4.0.2`. Tools are installed
by `install-ci-tools`, not by marketplace actions.

### What exists today, and what each check gets

| Check | Today | This story | Later |
|---|---|---|---|
| `Static Analysis Gate` | Absent. The guards run only inside `Build & Test`, and only when iOS paths change. | Unconditional job running the safety and Driver guards (FR-31 scan, FR-61 lint). They keep running in `Build & Test` too; both cost seconds. | 8.6: CodeQL `swift` `security-extended` with a pinned pack, Semgrep `p/secrets`, gitleaks, zero-analyzed-files failure. 8.7: Entitlements/Plist guard (FR-204). 8.9: License Header Gate. |
| `Dependency Scan Gate` | Absent. | Detect + OSV-Scanner + aggregation; weekly and on demand. | 8.6: the documentation statement on thin SwiftPM advisory coverage; quarterly suppression review. `Resolution Drift` is hosted in `iOS Gate` and belongs to 8.4. |
| `Workflow Lint` | Absent. `ci-local.sh workflow-pins` exists but nothing in CI runs it. | FR-202 in full, the offline policy, and the roster check. | 8.6 verifies. |
| `Workflow Security` | Absent. | zizmor at medium-or-higher and the `pull_request_target` backstop (FR-203). | 8.6 verifies. |
| `iOS Gate` | Exists: `if: always()` over `Detect iOS-Relevant Changes` and `Build & Test`, fail-closed through `gate-verdict`. | `GATE_NAME` only. | 8.4 `Resolution Drift`; 8.7 guards; 8.9 license checks. |

### How the five relate to `iOS Gate` and to branch protection

`iOS Gate` is already the pattern: an always-running job that turns a skipped-or-failed work
job into one honest verdict. `Dependency Scan Gate` reuses the same `gate-verdict` command, so
both aggregations share one implementation and one set of self-tests. The other three never
skip, so they need no aggregation. `Build & Test`, `OSV-Scanner` and the two detect jobs are
never required: their results reach branch protection only through their gate. Requiring
`Build & Test` directly would wedge every pull request that does not touch iOS paths, because
a skipped job never reports success.

Branch protection on develop is the repository ruleset "Protect develop" (id 18785256). Today it
has deletion, non-fast-forward, pull-request (squash only, zero approvals) and linear-history
rules and **no required status checks at all**, so not even `iOS Gate` is required yet. Its
bypass list is "Organization admin: always".

### Maintainer steps (GitHub settings, after the PR's checks have run once)

1. Settings → Rules → Rulesets → **Protect develop** → add **Require status checks to pass**.
2. Add exactly these five, each with source **GitHub Actions**:
   - `Static Analysis Gate`
   - `Dependency Scan Gate`
   - `Workflow Lint`
   - `Workflow Security`
   - `iOS Gate`
3. Do NOT add `Build & Test`, `UI Tests (Simulator)`, `Detect iOS-Relevant Changes`,
   `Detect Dependency Changes` or `OSV-Scanner`. Leave "Require branches to be up to date" off
   (squash merges with linear history already serialize develop).
4. Re-run `Workflow Lint` on the PR; its roster step now passes. Merge.
5. Rebase or update every other open PR to develop. A PR branched before this merge has none of
   the four new workflow files, so three of its checks are never created and it waits forever.
6. Optional but recommended: open a throwaway PR from a fork and confirm all five pass with no
   secret (FR-199). First-time-contributor workflow approval may apply; that is a click, not a
   failure.

**Bypass (maintainer decision).** FR-197 says bypass actors may skip review but never the five
checks. In GitHub, a ruleset's bypass list applies to every rule in it, so adding the checks to
"Protect develop" (which has an always-bypass actor) leaves them bypassable, which is the
current practice for merging past unrelated red CI. Meeting FR-197 literally means putting the
five checks in a second ruleset targeting develop with an empty bypass list. The roster check
reads the merged rules for the branch, so it passes either way.

### Why `ios.yml` keeps its concurrency expression

`ios.yml` cancels in-progress runs only for pull requests. Cancelling a push run on develop
would leave a merged commit without a verdict. FR-197 says `cancel-in-progress: true`; the new
workflows follow it, and the policy accepts `ios.yml`'s expression. Record the deviation; the
PRD sync can decide.

### Validating workflow YAML without actionlint

`actionlint`, `shellcheck`, `zizmor` and `osv-scanner` are not installed on the planning host
(`command -v` finds none; only Ruby 2.6 is present). Locally, the YAML is validated by
`bash scripts/ci-local.sh workflow-pins` (it parses every workflow with Psych and fails on
invalid YAML or an unpinned action) and by `bash scripts/ci-local.sh workflow-policy` (the AC 4
structure). The full actionlint, shellcheck and zizmor run happens in this PR's own
`Workflow Lint` and `Workflow Security` jobs. The PM reads those results before the merge
decision. If a developer has the pinned tools installed, `bash scripts/ci-local.sh
workflow-lint` and `workflow-security` reproduce CI exactly.

### First-run expectations

- OSV-Scanner over `Package.resolved` (GRDB 7.11.1 only). If it reports a vulnerability, do
  not suppress it to get green. Record it and escalate with NEEDS-HUMAN; a suppression needs
  a written reason and an `ignoreUntil` date (FR-201) and is the maintainer's call.
- zizmor and actionlint over the five workflow files. Fix real findings in the workflow. A
  `zizmor.yml` allowlist entry needs one audit id, a written rationale and the narrowest scope;
  lowering `--min-severity` is never the fix.
- `osv-scanner --no-ignore` ignores `.gitignore`, so a local run also scans untracked
  directories such as `_bmad*`. CI's clean checkout does not have them. Mention this in
  `usage` or a comment.

### Out of scope (do not build)

- Anything that signs, uploads, or needs a secret: Story 8.1 (FR-180, FR-183-FR-185,
  `release-gated`, App tokens). Story 8.2 (identifiers).
- CodeQL, Semgrep, gitleaks and the zero-analyzed-files rule (8.6). Entitlements and Plist
  guard (8.7). License Header Gate (8.9). `Resolution Drift` (8.4).
- `Attribution Check`, `App Token Auth Check` and the auto-merge scope guard: non-required
  `pull_request_target` jobs from FR-194 and FR-218, not part of this roster.
- Changing the GitHub ruleset. That is the maintainer's step above; no workflow or script
  writes repository settings.
- The rest of `CONTRIBUTING.md` (8.12).

### Project structure notes

- New: `.github/workflows/static-analysis.yml`, `.github/workflows/dependency-scan.yml`,
  `.github/workflows/workflow-lint.yml`, `.github/workflows/workflow-security.yml`,
  `scripts/lib/workflow_policy.rb`, `osv-scanner.toml`, `zizmor.yml`, `CONTRIBUTING.md`.
- Modified: `scripts/ci-local.sh`, `.github/workflows/ios.yml` (one `env` line).
- Branch from `develop`, for example `ci/required-check-roster`.
- Lane note: 1.7c also edits `scripts/ci-local.sh` (one array line). Whichever merges second
  rebases; the two edits do not overlap.

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 8.5 (and 8.1, 8.4, 8.6, 8.7 for
  scope edges)]
- [Source: prd.md §5.11 preamble (:3965), FR-197 (:3989), FR-198 (:4009), FR-199 (:4021),
  FR-201 (:4051), FR-202 (:4067), FR-203 (:4080), FR-213 (:4221); §5.10 FR-179 (:3698),
  FR-196 (:3918) for the signing boundary]
- [Source: ARCHITECTURE-SPINE.md Deferred: "the required-check roster is fixed by the PRD"]
- [Source: .github/workflows/ios.yml, scripts/ci-local.sh, .github/CODEOWNERS]
- [Source: GitHub API, `GET /repos/lumose-health/ios-unofficial/rules/branches/develop` and
  ruleset 18785256, read 2026-11-01: no `required_status_checks` rule present]

## Dev Agent Record

### Agent Model Used

Codex (Amelia)

### Debug Log References

- `bash scripts/ci-local.sh --self-test`, `/bin/bash scripts/ci-local.sh --self-test`, `bash scripts/ci-local.sh workflow-pins`, and `bash scripts/ci-local.sh workflow-policy`: pass.
- `swift build` and `swift test`: fail before compilation because SwiftPM cannot write its default module cache under this sandbox. Retrying `swift build --disable-sandbox` with caches inside the checkout reached dependency resolution, then failed because `github.com` DNS was unavailable.
- `gh api repos/lumose-health/ios-unofficial/rules/branches/develop`: network unavailable.

### Completion Notes List

- Implemented the five named jobs, the shared verdict, offline workflow policy, published roster comparison, tool installers, guards, and failure-path fixtures.
- First OSV-Scanner and zizmor scan results remain pending: the pinned tools are absent locally and network access is unavailable. No scan finding was suppressed or fixed. The OSV config header records one resolved package and the pending first result.
- The backstop uses Ruby 2.6 YAML parsing, so PyYAML is not installed. `ios.yml` retains pull-request-only cancellation as specified.
- Reviewable code and config diff is about 545 added lines and 6 removed lines, excluding this record and checkpoint artifacts.
- No PR was pushed and no hosted check results were observed in this cycle because GitHub was unreachable. The develop ruleset remains a maintainer step.

### File List

- `scripts/ci-local.sh`
- `scripts/lib/workflow_policy.rb`
- `scripts/lib/workflow_policy_test.rb`
- `.github/workflows/ios.yml`
- `.github/workflows/static-analysis.yml`
- `.github/workflows/dependency-scan.yml`
- `.github/workflows/workflow-lint.yml`
- `.github/workflows/workflow-security.yml`
- `CONTRIBUTING.md`
- `osv-scanner.toml`
- `zizmor.yml`

### PM notes before dispatch (2026-11-02)
- Accepted that this story absorbs OSV, actionlint and zizmor from 8.6. 8.6 will be re-scoped down when it's written.
- Changing the required checks in the "Protect develop" ruleset is a maintainer action in GitHub settings, and FR-197 says these checks are not bypassable. This change must NOT try to modify repository rulesets or settings. It only adds the workflows and the offline/advisory roster comparison.
- Every new workflow must pass on this PR itself. A new check that is red on its own introducing PR blocks the merge.
- budget: CONTINUATION_REQUIRED sha256:a69dd9212bc3a3aed8e215c642c9461569955d2424d68e5884778c186eaa5c92 cycle 1 2026-11-02T04:04:25Z
