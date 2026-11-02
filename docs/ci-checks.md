# CI checks

Branch protection on `develop` requires exactly these five checks. Each one is
a GitHub Actions job name.

<!-- required-checks:begin -->
- Static Analysis Gate
- Dependency Scan Gate
- Workflow Lint
- Workflow Security
- iOS Gate
<!-- required-checks:end -->

The list between the markers must match `REQUIRED_CHECKS` in
`scripts/ci-local.sh`; `Workflow Lint` fails if they drift.

| Check | Workflow | What it runs | Local command |
|---|---|---|---|
| Static Analysis Gate | `static-analysis.yml` | Passes only when two jobs on separate runners both succeed: `CodeQL Swift` (CodeQL 2.27.2 with `codeql/swift-queries@1.3.12` `security-extended`) and `Guards and Secrets` (gitleaks 8.30.1, then the safety and Driver guards with their self-tests). A failed, skipped or cancelled job fails the gate. | `bash scripts/ci-local.sh install-ci-tools static-analysis`; `bash scripts/ci-local.sh swift-analysis`; `bash scripts/ci-local.sh static-guards`; or `bash scripts/ci-local.sh static-analysis` for both. |
| Dependency Scan Gate | `dependency-scan.yml` | OSV-Scanner 2.3.3 over the source tree when dependency files change, weekly, and on demand. Any known vulnerability fails. OSV-Scanner 2.3.3 reads `Package.resolved` but treats SwiftPM packages as unscannable, so SwiftPM advisory coverage is thin for now. | `bash scripts/ci-local.sh dependency-scan` |
| Workflow Lint | `workflow-lint.yml` | actionlint 1.7.7 with shellcheck 0.10.0, the action SHA-pin check, the composite-action secrets check, the workflow policy, and the roster check above. | `bash scripts/ci-local.sh workflow-lint` |
| Workflow Security | `workflow-security.yml` | zizmor 1.5.2 at medium severity and above, plus a check that no `pull_request_target` workflow checks out the pull request head. | `bash scripts/ci-local.sh workflow-security` |
| iOS Gate | `ios.yml` | The Swift package, Driver, guard and Xcode builds and tests when iOS paths change. | `bash scripts/ci-local.sh ios-gate` |

`Dependency Scan Gate` and `iOS Gate` always report. When nothing relevant
changed they pass and say the work was skipped; a failed or cancelled work job
fails them. None of the five needs a repository secret, so they give the same
result on pull requests from forks.

The local commands need the same tool versions as CI. On Linux x86_64,
`bash scripts/ci-local.sh install-ci-tools <workflow-lint|workflow-security|dependency-scan>`
downloads them into `.build/ci-tools/` and checks each sha256.
`install-ci-tools static-analysis` does the same for CodeQL and gitleaks on
Apple silicon macOS (`swift-analysis` or `secrets-scan` installs one of them).
CodeQL needs `zstd` to unpack, and `swift-analysis` needs Rosetta 2
because the CodeQL Swift extractor is x86_64 only.

CodeQL fails the gate on any result at `error` level or with a security
severity of 7.0 or more, and when it extracts no Swift file under `Sources/` or
`Apps/`. Warnings are printed but do not fail. The only exceptions are per-file
entries with a reason in `codeql-exclusions.txt`. gitleaks fails on any finding
in the committed tree; its exceptions live in `.gitleaks.toml`, each scoped to
one rule, exact files and exact strings, with a reason.

Semgrep's `p/kotlin` and `p/java` packs produce zero findings on Swift. Porting
those pack names would make an always-green check that tests nothing. CodeQL's
Swift suite carries less assurance than the Android gate did (PL-64). Package
targets not linked by the app appear as extraction warnings rather than failures.
Semgrep `p/secrets` remains deferred because its registry rules cannot be
checksum-pinned for an offline scan.

CodeQL has its own runner because it competes with the guard self-tests for
cores. When both ran on one runner the gate took 30m13s, against 16m40s before
CodeQL was added: the traced build, which runs under Rosetta, took about 23
minutes and the guard self-tests stretched from about 16.5 to 29.8 minutes.
With separate jobs the gate takes as long as the slower of the two: the first
split run took 22m34s (CodeQL 22m11s, guards and secrets 19m59s), about six
minutes more than before CodeQL was added. Almost all of that is the traced
build under Rosetta, which is accepted as the cost of analysing the Swift code.
