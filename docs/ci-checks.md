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
| Static Analysis Gate | `static-analysis.yml` | The safety and Driver guards and their self-tests. CodeQL, Semgrep and gitleaks are not wired in yet. | `bash scripts/ci-local.sh static-analysis` |
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
