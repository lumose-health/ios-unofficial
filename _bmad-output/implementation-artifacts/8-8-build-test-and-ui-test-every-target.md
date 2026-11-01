---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/8-8-build-test-and-ui-test-every-target.md.stamp.json
persona: dev
memory_mode: advisory
gates:
  - "swift build"
  - "swift test"
  - "bash scripts/guards/safety_guards.sh"
  - "bash scripts/guards/safety_guards.sh --self-test"
  - "bash scripts/guards/driver_guards.sh"
  - "bash scripts/guards/driver_guards.sh --self-test"
  - "bash scripts/ci-local.sh ios-gate"
  - "bash scripts/ci-local.sh --self-test"
  - "bash scripts/ci-local.sh workflow-pins"
  - "ruby -ryaml -e 'YAML.safe_load(File.read(\".github/workflows/ios.yml\"), aliases: false)'"
max_cycles: 3
---

# Story 8.8: Build, test and UI-test every target

Status: done

<!-- Route rationale (for the PM): CI workflow + local gate script, first CI the repo
has ever had. Not safety-critical code, but a supply-chain and trust-boundary
surface (workflow files run with repository context; the gate script becomes the
single definition every later gate plugs into). local_gpu: red — CI/workflow
changes are RED per the delegation protocol, and this Mac has no local GPU anyway.
PROTECTED PATH: adds .github/workflows/ (CI workflow files, CODEOWNERS lead-only),
so THE MERGE ESCALATES TO THE MAINTAINER regardless of gate evidence. The PM never
merges this PR. -->

<!-- Sequencing: first story of the pipeline lane, runs in parallel with the story
that bootstraps the Xcode app target (1.13 per the 2026-10-30 change record). It
must therefore NOT assume an app/Watch/widget target exists, and must make adding
them a one-line list edit when they land. -->

## Story

As a maintainer,
I want every target built and tested on every change,
So that a break is caught before a Builder finds it.

## Scope — what is real now vs deferred

The repository today is a pure Swift package (`SafetyCore`, `DriverAPI`,
`SimulatedDriver` under `Sources/Drivers/Simulated`, `Persistence` + GRDB 7.11.1
exact) with **no CI at all** — `.github/` contains only `CODEOWNERS`. There is no
Xcode project, no app, no Watch app, no widget extension and no UI-test target.

This story makes real: the `iOS` workflow with its `Detect iOS-Relevant Changes`,
`Build & Test`, `UI Tests (Simulator)` and `iOS Gate` jobs; the one committed
local-reproduction script `scripts/ci-local.sh` that the workflow calls; the
Xcode toolchain pin `.xcode-version`; and an every-Driver build configuration.
The app/Watch/widget builds and the Simulator UI tests are **explicitly deferred**
(see "Deferred — explicit, not dropped") but the structure that runs them ships
now, so the targets that land later are added by listing them once.

## Acceptance Criteria

1. **Workflow and job names.** A new workflow `.github/workflows/ios.yml`
   (workflow `name: iOS`) with exactly these jobs and job `name:` strings, which
   are a contract because branch protection keys on the job name (FR-197):
   - `detect-changes` → `Detect iOS-Relevant Changes` (non-required)
   - `build` → `Build & Test` (non-required; reaches merge gating only through `iOS Gate`)
   - `ui-tests` → `UI Tests (Simulator)` (non-required, NOT in `iOS Gate`'s `needs:`, FR-209)
   - `ios-gate` → `iOS Gate` (the Required Check, FR-197/FR-208)
   No job uses `continue-on-error`. Every job declares `timeout-minutes`
   (suggested: detect 5, build 30, ui-tests 45, gate 5). The workflow declares
   `concurrency: { group: ios-${{ github.ref }}, cancel-in-progress: true }` (FR-197).

2. **Triggers and always-report shape (FR-198).** Triggers: `pull_request`
   (branches `develop`, `main`; types opened/synchronize/reopened), `push`
   (branches `develop`, `main`), `workflow_dispatch`. **No workflow-level `paths:`
   filter** — path relevance is decided by `detect-changes` only. `iOS Gate` is
   `if: always()` with `needs: [detect-changes, build]` and implements the five-branch
   decision exactly: detect result not `success` → fail; event `workflow_dispatch`
   or `schedule` → require build `success`; push/PR with `should_build != 'true'` →
   print skip reason, pass; build `success` → pass; anything else (`failure`,
   `cancelled`, `skipped` when a build was due) → fail. Every `needs.*` value
   reaches the shell through `env:` only, never `${{ }}` inside `run:`.

3. **The decision logic is testable locally.** The five-branch verdict lives in
   `scripts/ci-local.sh gate-verdict` (reads `DETECT_RESULT`, `SHOULD_BUILD`,
   `WORK_RESULT`, `EVENT_NAME` from the environment) and the `iOS Gate` job calls
   it after a `persist-credentials: false` checkout. `scripts/ci-local.sh --self-test`
   asserts every branch, including: detect `failure` with build `success` → fail;
   PR with `SHOULD_BUILD=false` and build `skipped` → pass; PR with
   `SHOULD_BUILD=true` and build `skipped` → fail; build `cancelled` → fail;
   `workflow_dispatch` with `SHOULD_BUILD=false` and build `skipped` → fail;
   empty/unset values → fail (fail closed, never default-pass).

4. **Paths filter (FR-208).** `detect-changes` sets `should_build` from a filter
   that matches at least: `Sources/**`, `Apps/**`, `Tests/**`, `Package.swift`,
   `Package.resolved`, `.xcode-version`, `Contract/**`, `**/*.xcodeproj/**`,
   `**/*.xcconfig`, `**/*.entitlements`, `**/Info.plist`, `Resources/**`,
   `.github/workflows/ios.yml`, `README.md`, `LICENSE`,
   `docs/THIRD_PARTY_LICENSES.md`, `docs/licenses/**` — **plus** `scripts/ci-local.sh`
   and `scripts/guards/**`, because the gate executes them and a guard edit that
   skipped the build would merge unexercised (this extends FR-208's list; see
   Open questions). Paths that do not exist yet are listed anyway so the filter
   needs no edit when they land.

5. **Build & Test runs the real gate (FR-208, FR-210, FR-213).** On the pinned
   macOS runner the job: checks out with `persist-credentials: false`; selects
   Xcode from `.xcode-version` explicitly (`sudo xcode-select -s
   /Applications/Xcode_<ver>.app`, never the image default); then runs
   `bash scripts/ci-local.sh ios-gate` and nothing else that matters — no gate
   command is written inline in the workflow.

6. **`scripts/ci-local.sh ios-gate` (FR-213)** is the single definition of the
   iOS Gate's invocation, runnable unchanged on this Mac, and in order:
   a. asserts `xcodebuild -version` reports exactly the version in `.xcode-version`
      and fails with a named message otherwise (FR-193/FR-208); on a machine
      without Xcode it exits non-zero with a named "requires Xcode" message,
      never a partial pass;
   b. `swift build --build-tests --disable-automatic-resolution -Xswiftc -warnings-as-errors`
      (default configuration);
   c. `swift test --skip-build` (or an equivalent that reuses step b's products);
   d. the every-Driver configuration (AC 7);
   e. `bash scripts/guards/safety_guards.sh` and `--self-test`;
   f. `bash scripts/guards/driver_guards.sh` and `--self-test`;
   g. the Xcode-targets step (AC 8).
   It uses `set -euo pipefail`, prints a header per step, and exits non-zero on
   the first failing step. Scratch output goes under `.build/` only.

7. **Every-Driver configuration (AD-17, FR-189, FR-208).** The script holds ONE
   list of Driver compilation conditions (`ALL_DRIVER_CONDITIONS`, empty today —
   no Driver is compile-gated yet) and builds AND tests with every listed
   condition defined (`-Xswiftc -D<COND>` per entry) into a separate scratch path
   (e.g. `.build/all-drivers`) so it never perturbs the default build. To keep
   the list honest it also fails if any `#if`/`#elseif` under `Sources/` references
   an identifier matching `*_DRIVER_ENABLED` that is not in the list (the
   Android `MEDTRONIC_DRIVER_ENABLED` analogue). Composition stays subtractive:
   the list may only ENABLE Driver conditions; the script defines no other
   `-D` flag and nothing that adds a capability (FR-189). With the list empty the
   step still runs (it is then a second full build+test of every Driver target)
   and says so in its output.

8. **Adding Xcode targets is a one-list edit.** The script holds
   `XCODE_BUILD_SCHEMES` (app, Watch app, widget extension; empty today) and
   `XCODE_UITEST_DESTINATIONS` / `XCODE_UITEST_SCHEMES` (empty today).
   - `ios-gate` step g runs, per listed scheme, an unsigned Simulator
     `xcodebuild build test` (`-sdk iphonesimulator` / `watchsimulator`,
     `CODE_SIGNING_ALLOWED=NO`, `-warnings-as-errors` equivalent) — FR-199, FR-208.
   - `scripts/ci-local.sh ui-tests` runs XCUITest per listed scheme × destination
     with `-resultBundlePath .build/ui-results/<name>.xcresult` (FR-209).
   - **Self-maintaining tripwire:** both steps FAIL if the repository contains any
     `*.xcodeproj` or `*.xcworkspace` (outside `.build/`, `.swiftpm/`) while the
     corresponding list is empty — so the target-adding change cannot forget to
     list them. With no project present and lists empty, each prints a named
     "no Xcode targets declared yet" line and passes.
   - The `UI Tests (Simulator)` job exists now, calls `scripts/ci-local.sh ui-tests`,
     uploads `.build/ui-results/` with `actions/upload-artifact`
     `if: ${{ !cancelled() }}`, `if-no-files-found: ignore`, `retention-days: 14`,
     no automatic retry (FR-209). It is gated on `should_build` like `Build & Test`.

9. **Supply chain (FR-193, FR-202).** Every `uses:` pins a full 40-hex commit SHA
   with a trailing `# vX.Y.Z` comment. `scripts/ci-local.sh workflow-pins` checks
   every `uses:` under `.github/workflows/` and `.github/actions/` (skipping `./`
   and `docker://`), lists all offenders, and fails on any unpinned or `@`-less
   reference; `--self-test` proves it fails on a tag ref, a short SHA and a
   missing `@`. (This is the SHA-pin half of the future `Workflow Lint` check;
   that job itself is NOT created here.)

10. **Least privilege and fork-safety (FR-199).** Workflow-level
    `permissions: contents: read`. Only `detect-changes` adds `pull-requests: read`
    (job-level, listing `contents: read` too since job permissions replace, not
    merge). No `secrets.` reference, no `pull_request_target`, no signing
    identity, certificate, profile or App Store Connect key anywhere in the file;
    every checkout sets `persist-credentials: false`. The workflow must pass
    unchanged on a fork PR with a read-only token — verify structurally in-story
    (grep evidence in the Dev Agent Record) and list the live fork-PR run as a
    maintainer post-merge check.

11. **Toolchain pin.** A committed `.xcode-version` containing exactly `26.6`
    (this Mac: Xcode 26.6, build 17F113). The runner label is pinned explicitly
    (expected `macos-26`, never `macos-latest`) — see "Runner image" in Dev Notes
    for what has and has not been verified.

12. **Fork-reproducible locally.** A developer runs `bash scripts/ci-local.sh ios-gate`
    on this Mac and gets the same verdict CI does; `bash scripts/ci-local.sh`
    with no arguments prints usage listing every subcommand and states which
    gates are not yet implemented in the script (static analysis, dependency
    scan, workflow security — owned elsewhere) rather than silently skipping them.

13. **Language rule.** No story/epic/AC/cycle vocabulary in the workflow, the
    script or any comment; FR-x / AD-x / SI-x references are fine. Comments say
    what the step enforces and why in plain words.

14. All gates in the frontmatter green; first live CI run on the PR green.

## Tasks / Subtasks

- [ ] Task 1: `.xcode-version` + `scripts/ci-local.sh` skeleton with usage, `gate-verdict`, `workflow-pins`, `--self-test` (AC 3, 9, 11, 12)
- [ ] Task 2: `ios-gate` subcommand — Xcode assertion, build with warnings-as-errors and no auto-resolution, test, guards (AC 6)
- [ ] Task 3: every-Driver configuration with `ALL_DRIVER_CONDITIONS` + undeclared-condition tripwire (AC 7)
- [ ] Task 4: `XCODE_*` lists, the Xcode build step, `ui-tests` subcommand, and the project-present tripwire (AC 8)
- [ ] Task 5: `.github/workflows/ios.yml` — four jobs, triggers, filter, permissions, concurrency, timeouts, pinned actions (AC 1, 2, 4, 5, 8, 10)
- [ ] Task 6: local validation (actionlint if obtainable, YAML parse, pins, self-test) and structural fork-safety evidence (AC 9, 10, 14)
- [ ] Task 7: open the PR, confirm the live run is green on all four jobs, record run URL + timings in the Dev Agent Record (AC 14)

## Dev Notes

### Builds on (do not modify)

- `scripts/guards/safety_guards.sh`, `scripts/guards/driver_guards.sh` and
  `scripts/guards/lib/*.awk` — call them, do not edit them. (Their headers carry
  old "story 1.4 (AC 9)" tags; out of scope here — do not touch.)
- `Package.swift`, `Package.resolved`, all of `Sources/` and `Tests/` — this
  story adds CI, it changes no product code. If a source change looks needed to
  get the build green, stop and record NEEDS-HUMAN.
- `.github/CODEOWNERS` — governance file, lead-only. `/.github/workflows/` is
  already lead-routed. Do not edit it (see Open questions on `scripts/ci-local.sh`).

### Verified facts (checked while writing this story, 2026-10-30)

- `swift build --build-tests -Xswiftc -warnings-as-errors` on develop @ 12243eb
  is CLEAN on this Mac (Xcode 26.6 / Swift 6.3.3), including GRDB, ~16 s warm-ish.
  So warnings-as-errors does not need a carve-out today.
- `bash` on this Mac is 5.3 (`/run/current-system/sw/bin/bash`). macOS runners'
  `/bin/bash` is 3.2; `#!/usr/bin/env bash` on GitHub macOS images normally picks
  Homebrew bash 5 — **verify on the first CI run** (print `bash --version` in the
  script header). If it is 3.2, the existing guards may break (associative arrays,
  `mapfile`); do not rewrite them — install/pin bash 5 in the job or record NEEDS-HUMAN.
- `actionlint` and `shellcheck` are NOT installed here. `ruby`, `yq`, `gh`,
  `brew` are.
- Known flake: `WallClockSchedulerTests` is timing-sensitive under load (sprint
  status, 2026-08-19: 1 in 259 locally). CI runners are loaded machines. Do NOT add
  a retry (FR-209 forbids automatic retries) or skip it. If it flakes in CI,
  re-run the single job, record it, and report it as the trigger for the deferred
  clock-hardening item.

### Runner image (verify at implementation)

The GitHub runner-images README for `macos-26-arm64` (image 20261026.0455.2,
fetched 2026-10-30) lists **Xcode 26.6 build 17F113 as the default** — the exact
build on this Mac — at `/Applications/Xcode_26.6.app`, with 26.5…26.0.1 also
installed. Simulator runtimes listed there are iOS/watchOS 26.2, 26.4, 26.5 (no
26.6 runtime listed — irrelevant until UI tests exist, but check before the UI
lane goes live). Not verified: that the runner **label** is exactly `macos-26`
(vs `macos-26-arm64`/`macos-26-xlarge`), that the image is GA rather than preview,
and the `Xcode_26.6.app` path. Confirm all three on the first run (print
`xcodebuild -version` and `ls /Applications | grep Xcode`) and record them. Do
not use `macos-latest` — FR-200 says `macos-latest` for the static-analysis job,
but that is a different job and an unpinned label contradicts FR-193's toolchain
pin; flagged for that work, not changed here.

### Actions to use (pins reviewed in the Android repo — re-verify)

`android-unofficial/.github/workflows/android.yml`
is the template for the detect/build/gate shape (read it; it is ~250 lines). Its
pins are a starting point, not a trust root — confirm each SHA is the tag's commit
with `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` (dereference annotated tags):
- `actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0`
- `dorny/paths-filter@7b450fff21473bca461d4b92ce414b9d0420d706 # v4.0.2`
- `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1`
No other third-party action. No caching action in this change (keeps the pinned
surface minimal; SPM cache is a later optimisation). Known Android gaps NOT to
port: its gate job has no `timeout-minutes`, and it puts `pull-requests: read` at
workflow level — both are fixed here.
Note: on `push`, dorny/paths-filter diffs against git history; with
`persist-credentials: false` on a public repo this works in Android — confirm on
the first push-to-develop run (post-merge, maintainer).

### Script design constraints

- One script, `scripts/ci-local.sh`, subcommands: `ios-gate`, `ui-tests`,
  `gate-verdict`, `workflow-pins`, `--self-test`, no-arg usage. FR-213 names this
  exact path; later gates (static analysis, dependency scan, workflow lint and
  security) are added as subcommands of the same script, so leave the dispatcher
  obviously extensible — but do not stub those gates as passing.
- Self-test style: follow `safety_guards.sh --self-test` (temp dirs under
  `.build/`, each case proves the check can fail, loud summary). The self-test
  must not need network or Xcode.
- The workflow's `run:` blocks are one-liners that call the script. No `${{ }}`
  inside any `run:`.
- The tripwire greps (AC 7 condition scan, AC 8 project scan) must strip `.build/`,
  `.swiftpm/` and `_bmad*/` from their search roots.

### Local validation (Task 6)

- Run `which actionlint`. If absent (it is today), obtain the pinned binary into
  `.build/tools/` only: actionlint 1.7.7 darwin_arm64 from the GitHub release,
  verified against the release's `actionlint_1.7.7_checksums.txt` (FR-202's
  sha256 is for linux_amd64 and will not match). Run
  `.build/tools/actionlint -oneline .github/workflows/ios.yml`. If network is
  blocked in the sandbox, record that and fall back to the frontmatter
  `ruby -ryaml` parse gate plus `yq '.jobs | keys' .github/workflows/ios.yml`
  and a manual check of every `name:`/`needs:`/`if:` against AC 1–2. Do not
  `brew install` anything.
- Fork-safety evidence: paste the output of
  `grep -nE 'secrets\.|pull_request_target|persist-credentials|permissions' .github/workflows/ios.yml`
  into the Dev Agent Record.

### Worker sandbox rules

- Scratch only under `.build/` in the worktree (tools, temp dirs, result bundles).
- One operation per Bash call — no chained `&&` pipelines of unrelated steps.
- Never commit `.claude/`, `_bmad/` or anything outside the declared file surface.
- SPM fetch of GRDB needs network; if blocked, record NEEDS-HUMAN rather than
  vendoring.

### Testing standards summary

No Swift tests are added. Tests here are the script's `--self-test` cases
(verdict branches, pin checker, both tripwires) and the live CI run. Every check
added must have a self-test case proving it can fail.

### Project structure notes

File surface (exhaustive): `.github/workflows/ios.yml` (new),
`scripts/ci-local.sh` (new), `.xcode-version` (new). Estimated diff ~450–600
added lines across 3 files, well inside the PR size budget. Branch from
`develop` (e.g. `ci/ios-gate`). PR targets `develop`.
MERGE: protected path (CI workflow files) — the PM prepares full gate evidence
and escalates to the maintainer, who merges. The maintainer also adds `iOS Gate`
to the `Protect develop` ruleset when ready; that is not part of this change.

### Deferred — explicit, not dropped

Each item below is required by FR-208/FR-209 but cannot be real until its
prerequisite exists. The structure above is what it plugs into.

| Deferred item | Requirement | Lands with | How it plugs in |
|---|---|---|---|
| Build + unit-test the phone app | FR-208 | the app-target bootstrap (1.13 per change record) | add scheme to `XCODE_BUILD_SCHEMES` |
| Build + unit-test Watch app and widget extension | FR-208 | Epic 3 (3.1/3.2) | add schemes to `XCODE_BUILD_SCHEMES` |
| XCUITest on iOS + watchOS Simulator, result bundle | FR-209 | first UI-test target (app bootstrap / Epic 3) | add to `XCODE_UITEST_SCHEMES` / `_DESTINATIONS`; job already exists |
| Real Driver compilation conditions | FR-189, AD-17 | first gated Driver (Medtronic, Epic 7) | add condition to `ALL_DRIVER_CONDITIONS` (tripwire forces it) |
| SwiftLint `--strict`, `swift-format lint`, project custom rules | FR-208 | guard/lint work (8.7) | new step in `ios-gate` |
| Deployment-floor + shared-safety-module build-settings check | FR-208, NFR-1, NFR-4 | app bootstrap (Xcode targets) | new step in `ios-gate` |
| Accessibility identifier registry (static half) | FR-208, FR-177 | 6.4 | new step in `ios-gate` |
| Full `Resolution Drift` step | FR-201, FR-193 | 8.4 | `--disable-automatic-resolution` here is the partial |
| Version-source check | FR-190 | 8.4 | new step in `ios-gate` |
| Other four Required Checks, roster-vs-ruleset comparison | FR-197, FR-200–203 | 8.5 / 8.6 | subcommands of `scripts/ci-local.sh` |
| SPM build cache | — | optional later | `actions/cache`, pinned |
| Clock-flake hardening for `WallClockSchedulerTests` | — | test-infra work | sprint-status deferral |

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-8.8; #Story-8.5 (roster); #Story-8.6; #Story-8.7]
- [Source: _bmad-output/planning-artifacts/prds/prd-ios-unofficial-2026-08-01/prd.md — §5.11 preamble (always-report pattern); FR-189, FR-193, FR-197, FR-198, FR-199, FR-202, FR-208, FR-209, FR-210, FR-212, FR-213]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-ios-unofficial-2026-08-03/ARCHITECTURE-SPINE.md#AD-17, #AD-3]
- [Source: android-unofficial/.github/workflows/android.yml — detect/build/gate template; workflow-lint.yml — pinned-tool install pattern]
- [Source: _bmad-output/implementation-artifacts/1-6-encrypted-local-store-write-time-invariants.md — current gates list]
- [Source: github.com/actions/runner-images images/macos/macos-26-arm64-Readme.md, fetched 2026-10-30]

### Open questions (for the PM / maintainer)

1. **Change record not found.** `_bmad-output/planning-artifacts/sprint-change-proposal-2026-10-30.md`
   does not exist in this checkout; sequencing here is taken from the PM's brief.
   Also, epics.md still titles 1.13 "Home dashboard and the glucose hero", not an
   app-target bootstrap — the change record presumably re-scopes it.
2. **Script path.** FR-213 fixes `scripts/ci-local.sh`; this story follows the PRD
   rather than a `scripts/ci/ios-gate.sh` name.
3. **Paths filter extension.** AC 4 adds `scripts/ci-local.sh` and `scripts/guards/**`
   to FR-208's filter list. Without them a guard-only PR skips the build. PRD edit
   suggested.
4. **CODEOWNERS.** CI executes `scripts/ci-local.sh`, so it is effectively
   workflow code; FR-212's roster does not list it. Suggest adding it lead-only
   (governance change for the maintainer, not done here).
5. **`macos-latest` in FR-200** conflicts with the explicit toolchain pin of
   FR-193/FR-208; raise when the static-analysis job is written.

## Dev Agent Record

### Agent Model Used

Codex GPT-6

### Debug Log References

- 2026-10-31 local gate run: raw `swift build`, `swift test`, and `bash scripts/ci-local.sh ios-gate` failed while SwiftPM compiled the manifest because the sandbox denied writes to `/Users/devbox/.cache/clang/ModuleCache`. A cache redirected into `.build/` plus `--disable-sandbox` allowed the equivalent Swift build and test to pass.
- The separate `.build/all-drivers` scratch build attempted to fetch GRDB; GitHub network access was unavailable in this worker environment.
- `gh repo view` could not connect to `api.github.com`; action tag verification, PR creation, and the first live CI run remain outstanding.

### Completion Notes List

- Added the four-job `iOS` workflow, path filter, least-privilege permissions, pinned action references, and always-report gate verdict.
- Added `.xcode-version` containing `26.6` and a single local script for the package, guards, Driver conditions, Xcode targets, UI tests, gate verdict, and workflow pin checks.
- Script self-test passed all verdict, pin, Driver-condition, and Xcode-project tripwire cases. `workflow-pins`, YAML safe load, `yq '.jobs | keys'`, both normal guards, and both guard self-tests passed (72 safety cases and 68 Driver cases).
- The equivalent warnings-as-errors package build passed, followed by 269 Swift tests in 34 suites. These used sandbox-specific cache and `--disable-sandbox` options; the exact raw frontmatter Swift gates are still red in this environment.
- Fork-safety grep evidence: lines 11 and 23 declare `permissions`; lines 31, 66, 81, and 104 set `persist-credentials: false`; no `secrets.` or `pull_request_target` match.
- `actionlint` was absent and could not be fetched while GitHub access was unavailable. YAML parse and structural job checks passed. The first fork-PR run and the first push-to-develop filter behavior require maintainer verification after connectivity returns.
- Protected workflow path requires maintainer merge; no merge attempted.

Cycle 2 review and verification (2026-10-31):

- Fixed Bash 3.2 empty-array iteration throughout `ci-local.sh`; the self-test now invokes `$BASH` with the absolute script path. `/bin/bash scripts/ci-local.sh --self-test` and `/bin/bash scripts/ci-local.sh ui-tests` passed.
- Fixed Xcode build entries to carry SDK, project path, and scheme; UI-test entries carry project path and scheme. Every `xcodebuild` call now selects `-project` and writes DerivedData under `.build/xcode-dd`.
- Fixed the UI-test project check with `XCODE_UITEST_OPTOUT` entries of `project:reason`. A project must have a listed UI-test scheme or a nonempty opt-out reason; self-tests cover both results.
- Fixed workflow pin checking with a YAML walk that catches spaced, flow-style, and quoted `uses` keys. It requires lowercase 40-character action SHAs and 64-character Docker digests. Added passing and failing self-tests for both reference types.
- Fixed self-test verdict coverage for successful push and PR builds, failed PR builds, unknown events, and invalid `should_build`; failure cases assert their expected diagnostic. The fixture is removed before each run.
- Fixed the paths filter for `Package@swift-*.swift`, `.github/actions/**`, and `Plugins/**`.
- Deviated from AC 1's literal `cancel-in-progress: true` at the PM's explicit direction: only PR runs are cancelled, preserving push-to-develop runs.
- Final implementation surface: three new files, 362 lines total (`scripts/ci-local.sh` 247, `.github/workflows/ios.yml` 114, `.xcode-version` 1).
- The cycle 2 exact `swift build`, `swift test`, and `bash scripts/ci-local.sh ios-gate` commands stopped at the SwiftPM manifest because sandbox permissions deny writes to `~/.cache/clang/ModuleCache`. The independent cycle 1 launcher re-run reported all ten frontmatter gates green; no product source changed in this cycle.
- `bash scripts/ci-local.sh --self-test`, `workflow-pins`, both normal guards, and Ruby YAML safe-load passed locally. `yq '.jobs | keys'` returned exactly the four required job IDs. `/bin/bash` reports version 3.2.57 and passed the script self-test.
- Fork-safety grep after the edit: lines 11 and 23 declare permissions; lines 31, 69, 84, and 107 set `persist-credentials: false`; no `secrets.` or `pull_request_target` match.
- GitHub's runner-images README lists `macos-26` as the Apple Silicon label, and its macOS 26 image README lists Xcode 26.6 build 17F113 at `/Applications/Xcode_26.6.app`. The PM reports independently verifying the three action tag SHAs. `gh repo view` still cannot connect to `api.github.com`, so a PR and live job results remain unverified.
- Final cycle 2 frontmatter results in this sandbox: seven passed (`safety_guards.sh`, its 72-case self-test, `driver_guards.sh`, its 68-case self-test, `ci-local.sh --self-test`, `workflow-pins`, Ruby YAML safe-load); three stopped at the sandbox-denied SwiftPM module cache (`swift build`, `swift test`, `ci-local.sh ios-gate`). The cycle 1 launcher reported all ten gates green in its independent environment before these review fixes; the revised code still needs that independent re-run.
- `actionlint` is absent locally and could not be fetched from GitHub here. The PM's independent actionlint 1.7.7 check reported only its outdated `macos-26` label table. No live CI run URL or timings exist yet.

### File List

- `.github/workflows/ios.yml` (new)
- `.xcode-version` (new)
- `scripts/ci-local.sh` (new)
- budget: CONTINUATION_REQUIRED sha256:5ca5fef84258f055909ea1da49db57b63d98eadebd56125f6656c70c0bf04585 cycle 1 2026-10-31T07:21:49Z

- budget: CONTINUATION from cycle 1 sha256:5ca5fef84258f055909ea1da49db57b63d98eadebd56125f6656c70c0bf04585 trigger=WORKER_SIGNAL usage=unobserved/n/a cycle 2 2026-10-31T07:40:08Z

- budget: CONTINUATION_REQUIRED sha256:2a6bf828809f5a6a88c0fb0e80dc660cebc31f39f117d2a9ee9e32ec2c3e5634 cycle 2 2026-10-31T07:50:18Z

## PM notes for cycle 2 (2026-10-31): independent review findings

Launcher re-run of cycle 1: **all 10 gates passed.** The PM verified the three action SHAs against their tags. actionlint 1.7.7 only flags `macos-26` as an unknown label because it predates that runner, so ignore it. Your sandbox can't run Swift or reach the network; the launcher re-runs the gates, so don't burn the cycle on that.

An independent review returned APPROVE-WITH-FIXES. Fix all of the following:

1. **MAJOR: bash 3.2 compatibility** (`ci-local.sh` around :69, :99, :118-120, :132-133). Iterating an empty array under `set -u` aborts with `unbound variable` on bash < 4.4, and macOS `/bin/bash` is 3.2. Reproduced: `--self-test`, `ui-tests` and `ios-gate` all die. Use the `${arr[@]+"${arr[@]}"}` form everywhere. The self-test also re-invokes `bash "$0"`, which picks whatever bash is on PATH: re-invoke with the same interpreter (`"$BASH"`) and an absolute path (`"$ROOT/scripts/ci-local.sh"`). The script must pass under `/bin/bash` 3.2.
2. **MAJOR: Xcode targets need `-project`** (:96-106). `xcodebuild build test -scheme X` run from the repo root opens `Package.swift`, not `Apps/GlycemicGPT/GlycemicGPT.xcodeproj`, so the first app scheme added will fail with "does not contain a scheme". Make each list entry carry its project path (for example `iphonesimulator:Apps/GlycemicGPT/GlycemicGPT.xcodeproj:GlycemicGPT`) and pass `-project`. The app-shell work in flight puts the project at exactly that path, with scheme `GlycemicGPT`. Keep the list empty here; that change adds itself to the list.
3. **MINOR: `-derivedDataPath .build/xcode-dd`** on every xcodebuild call (:105, :135). Nothing goes to `~/Library/Developer/Xcode/DerivedData`.
4. **MINOR: UI-test guard would go permanently red** (:129) once a project exists with no UI-test target, and the app shell has none yet. Add an explicit, per-project, documented opt-out: an `XCODE_UITEST_OPTOUT` list entry carrying a reason string. The guard passes only when every project is either listed in the UI-test schemes or opted out with a reason.
5. **MINOR: `workflow-pins` can be fooled** (:50-56). `- uses : a/b@main`, `- {uses: a/b@main}` and `- "uses": a/b@main` all pass. Replace the line grep with a YAML walk using `ruby -ryaml` (already a gate dependency; ruby 2.6 has no `safe_load_file`, so use `YAML.safe_load(File.read(f), aliases: false)`). Visit every `uses` value under every workflow in `.github/workflows/`. Require lowercase `[0-9a-f]{40}` for actions and reusable workflows, and `@sha256:` for `docker://` refs.
6. **MINOR: self-test coverage** (:140-167). Add these cases:
   - push and PR verdicts where the build succeeded (pass), and a PR where the build failed (fail)
   - an unknown event such as `merge_group` (fail)
   - a garbage `SHOULD_BUILD` (fail)
   - a correctly pinned ref passing `pin_scan`, alongside each fooling form above failing
   - the project guard passing when no project exists

   `assert_case` must match the expected failure message, not just any non-zero exit. `rm -rf` the `.build/ci-local-self-test` fixture first.
7. **MINOR: paths filter** (ios.yml:35-55). Add `Package@swift-*.swift`, `.github/actions/**` and `Plugins/**`.
8. **NIT: concurrency** (ios.yml:14-16). Use `cancel-in-progress: ${{ github.event_name == 'pull_request' }}` so pushes to develop are never cancelled. This overrides the story text; the PM accepts the deviation. Record it in the Dev Agent Record.

Out of scope for you: CODEOWNERS coverage for `scripts/ci-local.sh` and `scripts/guards/` is governance, and the maintainer handles it. The Xcode build-number check (NIT) is also out. Leave both alone.

Finish the Dev Agent Record with the final diff size and a line per finding: fixed, or deviated with a reason.
