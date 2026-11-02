---
# linear: EMPTY = local-only epic — the PM must NOT create or sync anything in Linear.
linear:
stamp: _bmad-output/implementation-artifacts/8-6-swift-static-analysis-that-actually-analyses-swift.md.stamp.json
persona: dev
memory_mode: advisory
gates:
  - "bash scripts/ci-local.sh --self-test"
  - "/bin/bash scripts/ci-local.sh --self-test"
  - "bash scripts/ci-local.sh workflow-pins"
  - "bash scripts/ci-local.sh workflow-policy"
  - "swift build"
  - "swift test"
  - "bash scripts/ci-local.sh install-ci-tools static-analysis"
  - "bash scripts/ci-local.sh swift-analysis"
  - "bash scripts/ci-local.sh secrets-scan"
max_cycles: 3
---

# Story 8.6: Swift static analysis that actually analyses Swift

Status: done

<!-- Planning note (for the maintainer): PROTECTED PATH. This changes
`.github/workflows/static-analysis.yml` and `scripts/ci-local.sh` (both under CODEOWNERS lead-only
review) and adds pinned tool downloads. The maintainer merges; the PM does not.

Scope after 8.5. PR #27 took OSV-Scanner (FR-201), actionlint + shellcheck + the pin and
composite-secrets guards (FR-202) and zizmor + the pull_request_target backstop (FR-203). Those
stay as they are; this story only re-verifies them. What remains is FR-200: CodeQL `swift` with
`security-extended` at a pinned pack version, failing closed, failing on zero analyzed files, plus
gitleaks in the same job. Semgrep `p/secrets` is deferred (see "Open questions"). SwiftLint is
NOT here: FR-208 puts SwiftLint `--strict`, `swift-format lint` and the project custom rules in
`Build & Test` under `iOS Gate`, and 8.8's mapping assigns them to the guard/lint work (8.7).
Compiler warnings-as-errors is already applied by `ios-gate` (`swift build -Xswiftc
-warnings-as-errors`), so repeating it here would add time and no coverage. Periphery and
SwiftFormat are named by no FR.

No new Required Check: everything runs inside the existing `Static Analysis Gate` job. No secret:
CodeQL results are evaluated from a local SARIF file and never uploaded to code scanning, because
`security-events: write` is not granted to fork pull requests (prd.md §5.11 preamble).

Time. The gate takes about 17 minutes on push and up to about 24 on pull requests, almost all of
it the two guard self-tests (about 16.5 minutes, single-threaded bash). CodeQL runs in the
background while those self-tests run, so its 8-12 minutes of work mostly hides behind them.
Expected added wall time: 1-3 minutes (tool install plus any overrun). AC 8 caps it at 5.

Estimate: ~450 reviewable lines (ci-local.sh ~150 including self-tests, a Ruby SARIF evaluator
~120 and its test ~120, workflow ~15, docs ~20). A `.gitleaks.toml` allowlist, if the first run
needs one, is listed separately and does not count. Route: NOT chosen here; the PM routes via
/v1/route. -->

## Story

As a maintainer,
I want a security gate that finds real defects,
so that a green check means something.

## Acceptance Criteria

From epics.md Story 8.6 (FR-200; FR-201, FR-202 and FR-203 inherited from 8.5 as verification),
with the PRD's testable consequences. AC numbering is local to this file.

1. **CodeQL Swift, pinned, offline at scan time (FR-200).** A new command
   `bash scripts/ci-local.sh swift-analysis` builds a CodeQL database with language `swift` by
   tracing a fresh build of the app scheme, then analyses it with
   `codeql/swift-queries@1.3.12:codeql-suites/swift-security-extended.qls` from the CodeQL
   2.27.2 bundle. No pack is downloaded at scan time (no `--download`); a pack version mismatch
   fails. It writes `.build/static-analysis/codeql.sarif`.
2. **Blocking threshold (FR-200).** A Ruby evaluator, `scripts/lib/sarif_gate.rb`, reads the SARIF
   and fails on any result whose rule has `properties.security-severity >= 7.0` or whose effective
   level is `error`, printing each as one line (`<rule id> <path>:<line> <message>`). The effective
   level is the result's `level`, else the rule's `defaultConfiguration.level`, else `warning`.
   Rules are looked up across `tool.driver.rules` and every `tool.extensions[].rules`. `warning`
   results are counted and printed, non-blocking. `note` results are neither counted nor blocking.
3. **Fails closed (FR-200).** Each of these fails the gate with a named message:
   - `codeql database create` or `codeql database analyze` exits non-zero; an unset status is
     treated as 2 (`${status:-2}`);
   - the SARIF file is missing, empty, or not valid JSON, or has no `runs`;
   - **zero analyzed files**: no `swift/diagnostics/successfully-extracted-files` notification
     (from `diagnostics/ExtractedFiles.ql`, run alongside the suite) names a file under `Sources/`
     or `Apps/`.
   A tracked `*.swift` file under `Sources/` or `Apps/` (from `git ls-files`) that was not
   extracted is printed as one non-blocking `::warning::` listing every such path.
4. **Suppression is narrow and reasoned (FR-200).** There is no baseline. The only escape hatch is
   `codeql-exclusions.txt`, one `<repo-relative file path> # <reason>` per line. The evaluator
   rejects an entry with no reason, any glob character (`*`, `?`, `[`), a bare basename (no `/`),
   or a path that does not exist. The file is created only if the first run needs it.
5. **gitleaks in the same job (FR-200, FR-189).** A new command
   `bash scripts/ci-local.sh secrets-scan` exports the committed tree (`git archive HEAD`) to
   `.build/static-analysis/tree` and runs gitleaks 8.30.1 `dir` over it with the default rules,
   `--redact`, and a non-zero exit on any finding. Scanning the export, not the working
   directory, keeps `.build/`, downloaded tools and the CodeQL database out of the scan. Any
   allowlist lives in `.gitleaks.toml` (`[extend] useDefault = true`) as full-path entries, each
   with a written reason.
6. **Wired into the existing gate, never a new check (FR-197, FR-200).** `static-analysis` runs
   `swift-analysis` in the background with output to `.build/static-analysis/codeql.log`, runs
   `secrets-scan` and the four existing guard commands in the foreground, then waits for CodeQL,
   prints its log, and fails if it failed. A failing foreground step kills the background job. The
   job name, trigger, `permissions: contents: read`, concurrency and the five-check roster do not
   change, and `workflow-policy` still passes.
7. **Workflow.** `.github/workflows/static-analysis.yml` gains, in order after checkout: "Select
   pinned Xcode" (the same step as `ios.yml`), `bash scripts/ci-local.sh install-ci-tools
   static-analysis`, the existing `bash scripts/ci-local.sh static-analysis`, then an
   `actions/upload-artifact` step (the SHA already in `ios.yml`) with `if: always()`, name
   `static-analysis-results`, path `.build/static-analysis/*.sarif` and the gitleaks report,
   `if-no-files-found: warn`, `retention-days: 30`. `timeout-minutes` goes from 30 to 40. No
   secret, no new permission, no `shell:` or `working-directory:` override.
8. **Time.** The Dev Agent Record states the gate's wall time on this PR's own run and on the
   latest develop push run before it, and the difference. Added wall time is at most 5 minutes.
   If it is more, record the step timings and write NEEDS-HUMAN; do not drop the parallel run or
   raise the cap.
   **PM note (2026-11-02):** the first PR run (41404355798) took 30m13s, +13m33s over the 16m40s
   baseline: the traced build took ~23m under Rosetta and the guard self-tests stretched from
   ~16.5m to 29.8m on the shared runner. PM decision: CodeQL moves to its own job on a separate
   runner in `static-analysis.yml`; the `Static Analysis Gate` job becomes an aggregate that
   `needs:` both jobs and fails closed on any non-success (`needs-verdict`). Expected wall time is
   max(guards, CodeQL), not their sum. The roster stays at five checks.
9. **Pinned, checksum-verified tools.** `install-ci-tools static-analysis` (Darwin arm64 only;
   named failure elsewhere) downloads the pins in Dev Notes into `.build/ci-tools/`, verifies each
   with `shasum -a 256 -c -` before extracting, and adds the tool directories to `$GITHUB_PATH`
   (or prints them locally). `swift-analysis` and `secrets-scan` call `require_tool` for
   `codeql 2.27.2` and `gitleaks 8.30.1`. `install-ci-tools static-analysis` fails with a named
   message when `zstd` is absent, and `swift-analysis` when `xcodebuild` is. The existing Linux
   targets are unchanged.
10. **It passes today.** On the current develop tree, `swift-analysis` and `secrets-scan` pass.
    Each first-run finding is either fixed in this story or excluded with a per-entry reason
    (AC 4, AC 5); no rule or query is disabled and no severity threshold is changed. The Dev Agent
    Record lists every first-run result, what was done about it, and the extracted-file count.
11. **Documentation (FR-200).** `docs/ci-checks.md`'s Static Analysis Gate row names CodeQL
    2.27.2 / `codeql/swift-queries@1.3.12` `security-extended`, gitleaks 8.30.1 and the guards, and
    gives the local commands. One short paragraph states plainly that Semgrep's `p/kotlin` and
    `p/java` packs produce zero findings on Swift, so porting them by name would give a check that
    is always green and tests nothing, and that CodeQL's Swift suite carries less assurance than the
    Android gate did (PL-64). `ci-local.sh usage` lists the new commands; its "not wired yet" line
    and the matching `echo` in `static_analysis` name only Semgrep `p/secrets`.
12. **Inherited checks still hold (FR-201, FR-202, FR-203).** Dependency Scan Gate, Workflow Lint
    and Workflow Security are not modified and pass on this PR.
13. **Self-tests, both shells, offline.** `--self-test` adds, with fixtures under `.build/` and no
    network or tools beyond Ruby: the evaluator on a clean SARIF (pass), an `error`-level result,
    a `security-severity` of 7.0 (fail) and 6.9 at `warning` (pass, counted), a `note` (ignored),
    a level inherited from the rule default, a rule found only in `tool.extensions`, a missing
    file, an empty file, invalid JSON, zero extracted files, a non-extracted tracked file (pass
    with the warning text), and the exclusions file (valid entry excludes, glob, basename, no
    reason, nonexistent path); the unset-status default failing; and `swift-analysis`,
    `secrets-scan` and `install-ci-tools static-analysis` failing with their named messages when
    the tool or platform is wrong. It passes under `bash` (5) and `/bin/bash` (3.2).
14. **Gates.** All frontmatter gates pass. On the PR, all five Required Checks pass.

## Tasks / Subtasks

- [ ] Task 1: tool install (AC 9)
  - [ ] In `install_ci_tools`, accept `static-analysis`. Keep the Linux x86_64 check for the three
        existing targets; `static-analysis` requires Darwin arm64. Download, `shasum -a 256 -c -`,
        then extract: `zstd -dc <bundle> | tar -xf - -C .build/ci-tools` (gives
        `.build/ci-tools/codeql/codeql`), and `tar -xzf` the gitleaks archive. Add both
        `.build/ci-tools/codeql` and `.build/ci-tools` to the path output.
- [ ] Task 2: `swift-analysis` (AC 1-4)
  - [ ] Prepend `$ROOT/.build/ci-tools/codeql` and `$ROOT/.build/ci-tools` to `PATH` when they
        exist, so a local run after `install-ci-tools` works without editing `PATH`.
  - [ ] `require_tool codeql 2.27.2`, then `check_xcode` (named failure if `xcodebuild` is
        absent or the version differs from `.xcode-version`).
  - [ ] `rm -rf .build/codeql .build/static-analysis/codeql.sarif`; then
        `codeql database create .build/codeql/db --language=swift --source-root=. --overwrite
        --command='<build>'` with the build command in Dev Notes. A fresh derived-data path is
        required: an up-to-date build compiles nothing and extracts nothing.
  - [ ] `codeql database analyze .build/codeql/db --format=sarif-latest
        --output=.build/static-analysis/codeql.sarif --threads=2 --ram=4096
        codeql/swift-queries@1.3.12:codeql-suites/swift-security-extended.qls
        codeql/swift-queries@1.3.12:diagnostics/ExtractedFiles.ql`.
  - [ ] Capture each exit status into a variable; fail on `${status:-2} != 0`.
  - [ ] `ruby scripts/lib/sarif_gate.rb <sarif> <exclusions-file> <tracked-swift-list-file>`.
- [ ] Task 3: `scripts/lib/sarif_gate.rb` and `scripts/lib/sarif_gate_test.rb` (AC 2-4, 13).
      Ruby 2.6, `JSON.parse` only, explicit arguments, exit 0 or 1, messages to stderr except the
      `::warning::` line and the summary (`codeql: <n> extracted, <b> blocking, <w> warnings`).
- [ ] Task 4: `secrets-scan` (AC 5): `require_tool` gitleaks (see the version note in Dev Notes);
      `git archive HEAD | tar -x -C .build/static-analysis/tree` into a cleaned directory; then
      `gitleaks dir .build/static-analysis/tree --no-banner --redact --exit-code 1
      --report-format json --report-path .build/static-analysis/gitleaks.json`, adding
      `--config .gitleaks.toml` only when that file exists.
- [ ] Task 5: `static_analysis` orchestration (AC 6): background CodeQL, `trap` to kill it on
      exit, foreground `secrets-scan` and guards, `wait "$pid" || status=$?`, print the log, fail
      on non-zero. Update `usage` and the dispatch `case`.
- [ ] Task 6: workflow (AC 7) and docs (AC 11).
- [ ] Task 7: self-tests (AC 13).
- [ ] Task 8: first run (AC 10). Push, read the gate's log and SARIF artifact, fix or exclude
      each finding, record timings (AC 8).

## Dev Notes

### Read first (rules of the road)

- **Your sandbox has no network and no SwiftPM cache.** You cannot download CodeQL or gitleaks,
  resolve packages, or build with Xcode there. That is expected: the launcher reruns every gate
  outside the sandbox, including `install-ci-tools static-analysis`, `swift-analysis` and
  `secrets-scan`. What you can run in the sandbox: both `--self-test` gates, `workflow-pins` and
  `workflow-policy`. Write the network-dependent parts carefully, and make every one of them fail
  closed so a wrong guess shows up as a red gate, not a false green.
- **Every action and tool is pinned by full SHA or sha256.** Reuse action SHAs already in the
  repo; add no new third-party action. Tools come from `install-ci-tools`, never from a
  marketplace action and never from `brew install`. Check before extracting.
- **bash 3.2 and 5.** As in 8.5: no `mapfile`/`readarray`, no `declare -A`, no `${var,,}`, no
  `[[ -v ]]`, no negative indices. Under `set -u`, expand arrays as `${arr[@]+"${arr[@]}"}`.
  `wait "$pid"` returns the job's status in both. Keep `set -e` from killing the script before you
  read that status (`wait "$pid" || status=$?`).
- **Ruby 2.6.** No `filter_map`, `tally`, `_1`, pattern matching, endless methods or
  `Hash#except`. The runner's Ruby is newer; write for the older one.
- **Code comments must not mention stories, epics, AC numbers, agents or cycles.** FR-x, SI-x,
  AD-x and PL-x ids are fine.
- **Do not edit** `Sources/**` or `Tests/**` except to fix a real CodeQL finding (AC 10). If a
  finding is in `Sources/SafetyCore/**`, `Sources/Persistence/**`, dosing, alert-floor or
  ingestion-mapper code, do not fix it here: write NEEDS-HUMAN with the finding. Do not edit the
  other four workflows, `scripts/lib/workflow_policy.rb`, `osv-scanner.toml` or `zizmor.yml`.
- **Diff budget:** about 800 reviewable lines, not counting `.gitleaks.toml` or
  `codeql-exclusions.txt`. Report the reviewable size and the baseline entries separately in the
  Dev Agent Record.
- Scratch files only under `.build/`. One operation per Bash call.

### Tool pins (checked against the release APIs on 2026-11-02)

| Tool | Artifact | sha256 |
|---|---|---|
| CodeQL 2.27.2 (Swift-only macOS bundle, released 2026-10-07) | `https://github.com/github/codeql-action/releases/download/codeql-bundle-v2.27.2/codeql-bundle-swift-osx64.tar.zst` (393 MB) | `25a08dfd23997ccf6374b5a70d9aa27a510e027f1b5aed60e1a653f8a3596375` |
| gitleaks 8.30.1 (2026-03-21) | `https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_darwin_arm64.tar.gz` | `b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5` |

- The CodeQL hash is GitHub's own asset digest. The release has no checksum file for the
  Swift-only bundle.
- 2.27.2 bundles `codeql/swift-queries` 1.3.12 (from `github/codeql@codeql-cli/v2.27.2`,
  `swift/ql/src/qlpack.yml`). CodeQL 2.27.2 supports Swift 5.4-6.3; the pinned Xcode's Swift is
  6.3. 2.27.3 (2026-10-20) was not chosen because it was under two weeks old.
- The bundle is zstd-compressed. macOS's `bsdtar` (libarchive 3.7.4 here) has no zstd support,
  so decompress with `zstd -dc`. GitHub's macOS images ship `zstd`; if it is missing, fail with
  `zstd is required`. Do not switch to the 1.26 GB `.tar.gz` all-language bundle.
- `gitleaks version` prints the version. If `gitleaks --version` is not accepted, give
  `require_tool` an optional third argument naming the version argument; keep the default
  `--version` for every existing caller.

### The traced build

```
xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj -scheme GlycemicGPT
  -sdk iphonesimulator -derivedDataPath .build/codeql/dd
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
```

- **Why the app scheme and not `swift build`.** It is what ships: the iOS Simulator SDK compiles
  the app target and every package product it links, including the `#if os(iOS)` paths that a
  macOS `swift build` skips. FR-200 asks for scope derived from a scheme that compiles every
  shipping target. Today that is this one scheme. There is no Watch app or widget yet; when they
  land, their schemes are added here.
- A package target the app does not link is not compiled, so it is not analysed. The AC 3
  tracked-file comparison surfaces it as a `::warning::` with its paths instead of hiding it.
- Keep every argument free of spaces (no `-destination 'generic/platform=iOS Simulator'`), so
  how `--command` splits the string does not matter. If CodeQL does not accept the string, put
  the command in a function and pass `--command="bash scripts/ci-local.sh <internal subcommand>"`.
  Record which form you used.
- Build GRDB as the build does. CodeQL extracts it too, and the AC 3 comparison counts only
  `Sources/` and `Apps/`. A GRDB finding at the blocking threshold is a dependency finding: write
  NEEDS-HUMAN, do not exclude it on your own.
- Use `-disableAutomaticPackageResolution` if, and only if, `run_xcode_builds` gains it first.
  Today it does not; match it.

### Reading the SARIF

- CodeQL writes `@kind diagnostic` query results to
  `runs[].invocations[].toolExecutionNotifications[]`, with `descriptor.id` set to the query id
  and the file in `locations[].physicalLocation.artifactLocation.uri`. Count those with id
  `swift/diagnostics/successfully-extracted-files`. Confirm the shape against the first real
  SARIF from CI. If it differs, the count is zero and the gate fails, which is correct; fix the
  reader, and put a trimmed copy of the real shape in the self-test fixture.
- `security-severity` is a string in CodeQL SARIF (`"7.5"`). Parse it as a float; treat an
  unparseable value as absent.
- `ruleId` alone may be enough to find the rule; when `result.rule.toolComponent.index` is
  present, use it to pick the extension.
- `uri` values are relative to the source root. Strip a leading `file://` and the root prefix
  if CodeQL writes absolute URIs.

### Running in parallel, and the time budget

- Measured on develop (run 41397141332, push, 2026-11-02): the gate took 16 min 40 s; on a pull
  request run it took up to about 24 minutes. In `Build & Test` the safety guards plus their
  self-test took about 9 minutes and the Driver guards about 7.5 (run 41397141396), and the app's
  `xcodebuild build` took about 1 minute.
- CodeQL estimate on a 3-core, 7 GB `macos-26` runner: bundle download and unpack about 1 minute
  (sequential, in the install step), traced build 2-3 minutes, `security-extended` analysis 4-8
  minutes. Run in the foreground, that would add 8-12 minutes. In the background behind the 16.5
  minutes of single-threaded guard self-tests, it should add 1-3 minutes.
- `--threads=2 --ram=4096` leaves one core and some memory for the guards. If the guards slow
  down enough to break AC 8, try `--threads=1` before anything else, and record what you tried.
- Run `secrets-scan` before the guards (about 10 s). The `git archive` export is independent of
  the CodeQL database, so the order does not matter for correctness.
- Starting the background job: `swift_analysis > .build/static-analysis/codeql.log 2>&1 &` then
  `pid=$!`. The `trap` must not kill an unrelated process if CodeQL has already exited; `kill`
  failure is fine (`|| true`).

### gitleaks first-run expectations

- `Tests/Fixtures/EcJpake/*.json` hold EC-JPAKE handshake test vectors (long hex). They may trip
  gitleaks' generic-key or entropy rules. If they do, add a full-path `[[allowlists]]` entry per
  file in `.gitleaks.toml`, each with a `description` saying they are published protocol test
  vectors and not credentials. No directory or glob entries unless every file in the directory is
  the same kind of fixture, and then say so in the reason.
- `_bmad-output/` is tracked and published. A hit there is real until shown otherwise; scrub it,
  do not allowlist it.
- A true secret anywhere: stop, write NEEDS-HUMAN, do not allowlist. Rotation is the maintainer's.

### What exists today (develop @ 05a4450)

- `.github/workflows/static-analysis.yml`: job `Static Analysis Gate`, `macos-26`,
  `timeout-minutes: 30`, checkout (`persist-credentials: false`), then
  `bash scripts/ci-local.sh static-analysis`. No Xcode selection step.
- `scripts/ci-local.sh`:
  - `static_analysis` runs the two guards and their self-tests, then echoes "CodeQL, Semgrep and
    gitleaks are not wired yet."
  - `require_tool <tool> <version>` matches the version in `<tool> --version`.
  - `install_ci_tools` is Linux x86_64 only and uses `sha256sum -c -` (absent on macOS; use
    `shasum -a 256 -c -` for the Darwin target).
  - `check_xcode` compares `xcodebuild -version` with `.xcode-version` (26.6).
  - `assert_case <label> pass|fail <message> <cmd...>` is the self-test helper; the
    missing-tool cases run with `env PATH=/usr/bin:/bin`.
- `scripts/lib/workflow_policy.rb` enforces the roster shape. The changes in AC 7 are within it:
  a step-level `if: always()` on the upload step is allowed; a job-level `if` or `needs` is not.
  `SHELL_OVERRIDES` is empty, so add no `shell:` or `working-directory:`.
- `.github/workflows/ios.yml` has the Xcode selection step
  (`sudo xcode-select -s "/Applications/Xcode_$(cat .xcode-version).app"`) and
  `actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1`. Copy both.
- `.gitignore` already ignores `.build/`.

### Why these tools and not others

| Tool | Decision | Reason |
|---|---|---|
| CodeQL `swift` `security-extended` | **In** | FR-200 and the epic name it. It is the only maintained Swift taint and dataflow analyser that can run offline from a pinned bundle. |
| gitleaks | **In** | FR-200 names it in the same job; FR-189 relies on it to reject committed credentials. Single static binary, seconds to run. OQ-55 still asks whether it should hard-fail; this story makes it hard-fail as FR-200 says. |
| Semgrep `p/secrets` | **Deferred** | FR-200 names it, but the registry pack is fetched at scan time, so its rule content cannot be checksum-pinned, which conflicts with FR-200's own "no rule content fetched unpinned". Installing the CLI with `--require-hashes` also means hashing its whole Python dependency tree. Open question for the PM. |
| SwiftLint, swift-format | **Not here** | FR-208 places them in `Build & Test` under `iOS Gate`; owned by the guard/lint work. |
| `-warnings-as-errors` | **Already done** | `ios-gate` builds with it. |
| Periphery, SwiftFormat lint | **No** | No FR asks for them. |
| `xcodebuild analyze` | **No** | Runs the Clang analyser over C and Objective-C, not Swift (prd.md §5.11). |

### Out of scope (do not build)

- Semgrep `p/secrets` (open question). gitleaks over git history; this scans the committed tree.
- SwiftLint, swift-format and the project custom rules (FR-208). The Entitlements and Plist Guard
  (FR-204). Artifact-level scanning (OQ-63).
- Uploading SARIF to code scanning. It would need `security-events: write`, which fork pull
  requests do not get.
- The security-testing documentation page (FR-237); this story only edits `docs/ci-checks.md`.
- Any change to the other four Required Checks or to the develop ruleset.

### Project structure notes

- New: `scripts/lib/sarif_gate.rb`, `scripts/lib/sarif_gate_test.rb`. Only if the first run needs
  them: `.gitleaks.toml`, `codeql-exclusions.txt` (baseline, outside the diff budget).
- Modified: `scripts/ci-local.sh`, `.github/workflows/static-analysis.yml`, `docs/ci-checks.md`.
  Possibly a `Sources/**` file for a real CodeQL finding (AC 10).
- Branch from `develop`, for example `ci/codeql-swift`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md, Story 8.6 (and 8.5, 8.7 for scope edges)]
- [Source: prd.md §5.11 preamble (:3965-3981), FR-189 (:3840), FR-200 (:4034), FR-208
  (:4160-4168), PL-64 (:5756), OQ-55 (:6350)]
- [Source: _bmad-output/implementation-artifacts/8-5-the-five-required-checks.md: tool-pin
  pattern, scope hand-off, bash and Ruby pitfalls]
- [Source: _bmad-output/implementation-artifacts/8-8-build-test-and-ui-test-every-target.md:332:
  SwiftLint is assigned to the guard/lint work]
- [Source: docs/ci-checks.md, .github/workflows/static-analysis.yml, .github/workflows/ios.yml,
  scripts/ci-local.sh, scripts/lib/workflow_policy.rb]
- [Source: GitHub release APIs for github/codeql-action `codeql-bundle-v2.27.2` and
  gitleaks/gitleaks `v8.30.1`, read 2026-11-02; CI run timings from runs 41397141332 and
  41397141396]

### Open questions (for the PM)

1. Semgrep `p/secrets`: defer to a follow-up, vendor a pinned copy of the rules (check the
   Semgrep Rules License first), or drop it in favour of gitleaks alone (a PRD change)?
2. gitleaks hard-fails here as FR-200 says, while OQ-55 still asks whether it should. Confirm.
3. A package target the app does not link is warned about, not failed. If the maintainer wants
   that to fail, it is a one-line change in the evaluator.

## Dev Agent Record

### Agent Model Used

GPT-6 Codex (Amelia), cycle 1 of 3.

### Debug Log References

- `.build/gate-self-test-bash.log` and `.build/gate-self-test-bash32.log`: both complete with `self-test: all cases passed`.
- `.build/gate-swift-build.log` and `.build/gate-swift-test.log`: Swift manifest compilation blocked by the sandbox denying `~/.cache/clang/ModuleCache`.
- `workflow-pins` and `workflow-policy`: exit 0.
- `install-ci-tools static-analysis`: exits 1, `zstd is required` on this host.
- `swift-analysis`: exits 1, `codeql 2.27.2 is required`.
- `secrets-scan`: exits 1, `gitleaks 8.30.1 is required`.

### Completion Notes List

- Implemented the pinned Darwin arm64 installer, Swift database creation and SARIF analysis, the fail-closed SARIF evaluator, committed-tree gitleaks scan, parallel orchestration, workflow artifact upload, documentation, and offline self-tests.
- The traced build uses the direct `xcodebuild build ...` command string. No exclusions or gitleaks allowlist exists yet; the first real scan must determine whether any are needed.
- The evaluator's synthetic fixtures cover blocking levels and severities, extension rules, diagnostics, malformed and absent SARIF, tracked-file warnings, and exclusion validation. Both Bash self-test gates pass.
- Reviewable changes are about 280 added lines and 12 removed lines across five implementation files, excluding this record. Baseline entries: zero.
- Develop baseline Static Analysis Gate: 16 min 40 s, run 41397141332 (from the story's measured baseline). This PR's own run, added time, first-run findings, extracted-file count, and five Required Checks are pending; no PR run was available in this sandbox.

### File List

- `scripts/ci-local.sh`
- `scripts/lib/sarif_gate.rb`
- `scripts/lib/sarif_gate_test.rb`
- `.github/workflows/static-analysis.yml`
- `docs/ci-checks.md`

### PM decisions on drafting open points (2026-11-02)
- **Semgrep `p/secrets`: deferred**, because its rules can't be checksum-pinned. Record it as a follow-up with that reason.
- **gitleaks: HARD-FAIL.** A committed secret is never a warning. The OQ-55 discussion is resolved in favour of failing. Any false positive gets an allowlist entry with a reason, scoped to that exact finding.
- **Package targets the app doesn't link:** keep the current warning, and don't fail on them. Document this.
- PR #27 merged the five required checks. This change works inside the existing Static Analysis Gate and adds no new required check. Every check must pass on the change's own PR.
- budget: CONTINUATION_REQUIRED sha256:3860d42fb2c715c42aecaa5760cf1e90ae41441221e18b29e6cff9bff1d186fa cycle 1 2026-11-02T07:03:19Z

### First real run (2026-11-02, PR #29, run 41404355798)
- Pins verified: both sha256 match GitHub asset digests and the downloaded files.
- Fixes on first run: require_tool rejected CodeQL's "release 2.27.2." line; .build/codeql missing before database create; missing-tool self-tests picked up a local .build/ci-tools (now overridable via CI_LOCAL_TOOLS); named Rosetta 2 check added (Swift extractor is x86_64 only).
- CodeQL: 62 of 71 tracked Swift files extracted; 0 results at any level; no codeql-exclusions.txt. Not extracted: 9 files in Sources/Persistence (not linked by the app) -> warning, per PM decision.
- gitleaks: 13 sourcegraph-access-token hits, all 9 distinct values public commit SHAs (verified via commits API) in two PRD research JSON files; .gitleaks.toml allowlist scoped to that rule + those files + those exact strings; planted-string test still fails the scan.
- All five Required Checks green. Static Analysis Gate 30m13s vs develop baseline 16m40s = +13m33s (cap 5m). Traced build ~23m under Rosetta and contention; guard self-tests stretched 16.5m -> 29.8m. NEEDS-HUMAN per AC 8.
- After the split (run 41408052833, commit 9083617): workflow 22m34s (CodeQL Swift 22m11s, Guards and Secrets 19m59s, gate 17s) = +5m54s vs 16m40s baseline; still ~54s over the 5m cap. CodeQL is the critical path. All five Required Checks green. 62 extracted, 0 results; gitleaks clean.
