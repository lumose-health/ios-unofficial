#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# Add Driver compilation conditions here when a Driver first uses one.
ALL_DRIVER_CONDITIONS=()
# Entries are SDK:project-path:scheme. List each scheme when its project lands.
XCODE_BUILD_SCHEMES=('iphonesimulator:Apps/GlycemicGPT/GlycemicGPT.xcodeproj:GlycemicGPT')
# Entries are project-path:scheme and project-path:reason, respectively.
# An opt-out is only for a project that has no UI-test target yet.
XCODE_UITEST_SCHEMES=()
XCODE_UITEST_DESTINATIONS=()
XCODE_UITEST_OPTOUT=('Apps/GlycemicGPT/GlycemicGPT.xcodeproj:no UI-test target yet')
# Entries are project-path:reason, for a scheme with no test action of its own
# (its code is tested elsewhere). The project is still built.
XCODE_TEST_OPTOUT=('Apps/GlycemicGPT/GlycemicGPT.xcodeproj:app code is tested through the package tests')
REQUIRED_CHECKS=('Static Analysis Gate' 'Dependency Scan Gate' 'Workflow Lint' 'Workflow Security' 'iOS Gate')

usage() {
  cat <<'EOF'
Usage: bash scripts/ci-local.sh <command>
  ios-gate       Build and test Swift, Drivers, guards, and declared Xcode targets
  ui-tests       Run declared XCUITest schemes on declared Simulator destinations
  gate-verdict   Evaluate DETECT_RESULT, SHOULD_BUILD, WORK_RESULT, EVENT_NAME
  static-analysis    Run CodeQL, gitleaks, safety and Driver guards
  swift-analysis     Trace the app build and evaluate CodeQL Swift results
  secrets-scan       Scan the committed tree with gitleaks
  static-guards      Run gitleaks, safety and Driver guards and their self-tests
  needs-verdict      Fail unless every job in NEEDS_RESULTS succeeded
  dependency-scan    Scan source with pinned OSV-Scanner
  workflow-lint      Run actionlint, shellcheck, pins, policy and the roster checks
  workflow-policy    Check required job and workflow structure offline
  workflow-security  Run zizmor and the pull_request_target backstop
  workflow-pins      Check action references under .github/workflows and .github/actions
  required-checks    Compare docs/ci-checks.md and the develop ruleset with the roster
  install-ci-tools   Install pinned tools for workflow-lint, workflow-security,
                     dependency-scan, static-analysis, swift-analysis
                     or secrets-scan
  --self-test    Exercise the verdict and guard failure paths without Xcode

Required checks on develop (also listed in docs/ci-checks.md):
  Static Analysis Gate   static-analysis
  Dependency Scan Gate   dependency-scan (needs osv-scanner 2.3.3)
  Workflow Lint          workflow-lint (needs actionlint 1.7.7, shellcheck 0.10.0)
  Workflow Security      workflow-security (needs zizmor 1.5.2)
  iOS Gate               ios-gate

Semgrep p/secrets is not wired yet. OSV-Scanner --no-ignore also
scans untracked local directories; CI uses a clean checkout.
EOF
}

header() { printf '\n== %s ==\n' "$1"; }
fail() { printf 'ci-local: %s\n' "$1" >&2; return 1; }

gate_verdict() {
  local detect=${DETECT_RESULT:-} build=${WORK_RESULT:-} should=${SHOULD_BUILD:-} event=${EVENT_NAME:-} gate=${GATE_NAME:-iOS Gate}
  if [[ -z "$detect" || -z "$build" || -z "$should" || -z "$event" ]]; then fail 'gate input is empty'; return 1; fi
  if [[ "$detect" != success ]]; then fail "detect-changes result is ${detect:-empty}; gate fails"; return 1; fi
  if [[ "$event" == workflow_dispatch || "$event" == schedule ]]; then
    [[ "$build" == success ]] || { fail "${event} requires a successful build (got ${build:-empty})"; return 1; }
    echo "$gate: work succeeded"; return 0
  fi
  if [[ "$event" != push && "$event" != pull_request ]]; then fail "unknown event ${event:-empty}"; return 1; fi
  if [[ "$should" == false ]]; then echo "$gate: relevant paths unchanged; work skipped"; return 0; fi
  if [[ "$should" != true ]]; then fail "should_build is ${should:-empty}; gate fails"; return 1; fi
  [[ "$build" == success ]] || { fail "required build is ${build:-empty}; gate fails"; return 1; }
  echo "$gate: work succeeded"
}

pin_scan() {
  ruby -ryaml -e '
    files = Dir.glob(".github/{workflows,actions}/**/*.{yml,yaml}").sort
    bad = false
    walk = lambda do |node, file|
      case node
      when Hash
        node.each do |key, value|
          if key == "uses"
            valid = value.is_a?(String) && (
              value.start_with?("./") ||
              value.match?(/\Adocker:\/\/[^\s@]+@sha256:[0-9a-f]{64}\z/) ||
              value.match?(/\A[^\s@]+@[0-9a-f]{40}\z/)
            )
            unless valid
              warn "#{file}: unpinned action: #{value.inspect}"
              bad = true
            end
          else
            walk.call(value, file)
          end
        end
      when Array
        node.each { |entry| walk.call(entry, file) }
      end
    end
    files.each do |file|
      begin
        walk.call(YAML.safe_load(File.read(file), aliases: false), file)
      rescue Psych::Exception => error
        warn "#{file}: invalid YAML: #{error.message}"
        bad = true
      end
    end
    exit(bad ? 1 : 0)
  '
}

require_tool() {
  local tool=$1 version=$2 version_arg=${3:---version} actual version_re
  command -v "$tool" >/dev/null 2>&1 || { fail "$tool $version is required"; return 1; }
  actual=$("$tool" "$version_arg" 2>&1) || { fail "$tool $version is required"; return 1; }
  version_re=${version//./\\.}
  # A trailing sentence period ("release 2.27.2.") still matches; "2.27.20" or "2.27.2.1" does not.
  [[ "$actual" =~ (^|[^0-9.])${version_re}([^0-9.]|[.]([^0-9]|$)|$) ]] || { fail "$tool $version is required (got $actual)"; return 1; }
}

# Runs everything the Static Analysis workflow runs, on one machine. CI runs
# static-guards and swift-analysis as separate jobs so they do not compete for cores.
static_analysis() {
  local pid status=0
  mkdir -p .build/static-analysis
  swift_analysis > .build/static-analysis/codeql.log 2>&1 &
  pid=$!
  trap 'kill "$pid" 2>/dev/null || true' EXIT
  static_guards
  wait "$pid" || status=$?
  cat .build/static-analysis/codeql.log
  trap - EXIT
  [[ "${status:-2}" == 0 ]] || { fail "swift-analysis failed with status ${status:-2}"; return 1; }
}

static_guards() {
  secrets_scan
  bash scripts/guards/safety_guards.sh
  bash scripts/guards/driver_guards.sh
  bash scripts/guards/safety_guards.sh --self-test
  bash scripts/guards/driver_guards.sh --self-test
  echo 'Semgrep p/secrets is not wired yet.'
}

# Every needed job must have succeeded. NEEDS_RESULTS is "job=result job=result".
needs_verdict() {
  local gate=${GATE_NAME:-Static Analysis Gate} entry name result count=0
  local -a entries=()
  read -r -a entries <<< "${NEEDS_RESULTS:-}" || true
  [[ ${#entries[@]} -gt 0 ]] || { fail "$gate: needs results are empty"; return 1; }
  for entry in "${entries[@]}"; do
    name=${entry%%=*}
    result=${entry#*=}
    [[ "$entry" == *=* && -n "$name" ]] || { fail "$gate: malformed needs result: $entry"; return 1; }
    [[ "$result" == success ]] || { fail "$gate: $name result is ${result:-empty}; gate fails"; return 1; }
    count=$((count + 1))
  done
  echo "$gate: all $count needed jobs succeeded"
}

swift_analysis() {
  local status=0 build_command
  local tools=${CI_LOCAL_TOOLS:-$ROOT/.build/ci-tools}
  [[ ! -d "$tools" ]] || PATH="$tools:$PATH"
  [[ ! -d "$tools/codeql" ]] || PATH="$tools/codeql:$PATH"
  require_tool codeql 2.27.2
  check_xcode
  # The CodeQL Swift extractor ships as x86_64 only; Apple silicon runs it under Rosetta 2.
  if [[ "$(uname -m)" == arm64 ]] && ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    fail 'swift-analysis needs Rosetta 2 on Apple silicon (softwareupdate --install-rosetta)'; return 1
  fi
  mkdir -p .build/static-analysis
  rm -rf .build/codeql .build/static-analysis/codeql.sarif
  mkdir -p .build/codeql
  build_command='xcodebuild build -project Apps/GlycemicGPT/GlycemicGPT.xcodeproj -scheme GlycemicGPT -sdk iphonesimulator -derivedDataPath .build/codeql/dd CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO'
  codeql database create .build/codeql/db --language=swift --source-root=. --overwrite --command="$build_command" || status=$?
  [[ "${status:-2}" == 0 ]] || { fail "codeql database create failed with status ${status:-2}"; return 1; }
  status=0
  codeql database analyze .build/codeql/db --format=sarif-latest --output=.build/static-analysis/codeql.sarif --threads=2 --ram=4096 \
    codeql/swift-queries@1.3.12:codeql-suites/swift-security-extended.qls \
    codeql/swift-queries@1.3.12:diagnostics/ExtractedFiles.ql || status=$?
  [[ "${status:-2}" == 0 ]] || { fail "codeql database analyze failed with status ${status:-2}"; return 1; }
  git ls-files 'Sources/*.swift' 'Apps/*.swift' > .build/static-analysis/tracked-swift.txt
  ruby scripts/lib/sarif_gate.rb .build/static-analysis/codeql.sarif codeql-exclusions.txt .build/static-analysis/tracked-swift.txt
}

secrets_scan() {
  local -a options=()
  local tools=${CI_LOCAL_TOOLS:-$ROOT/.build/ci-tools}
  [[ ! -d "$tools" ]] || PATH="$tools:$PATH"
  require_tool gitleaks 8.30.1 version
  mkdir -p .build/static-analysis
  rm -rf .build/static-analysis/tree .build/static-analysis/gitleaks.json
  mkdir -p .build/static-analysis/tree
  git archive HEAD | tar -x -C .build/static-analysis/tree
  [[ ! -f .gitleaks.toml ]] || options=(--config .gitleaks.toml)
  gitleaks dir .build/static-analysis/tree --no-banner --redact --exit-code 1 \
    --report-format json --report-path .build/static-analysis/gitleaks.json "${options[@]+"${options[@]}"}"
}

dependency_scan() {
  require_tool osv-scanner 2.3.3
  # The SwiftPM Package.resolved extractor is not in OSV-Scanner's default
  # plugin set; without it the scan finds no package sources and exits 128.
  osv-scanner scan source --recursive --no-ignore --config=osv-scanner.toml \
    --experimental-plugins=swift/packageresolved .
}

composite_secrets() {
  local file line
  if [[ ! -d .github/actions ]]; then echo 'composite-secrets: .github/actions is absent'; return 0; fi
  while IFS= read -r file; do
    # The -n test keeps a last line that has no trailing newline.
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ \$\{\{[[:space:]]*secrets\. ]]; then fail "$file: composite action secrets reference"; return 1; fi
    done < "$file"
  done < <(find .github/actions -type f | sort)
}

workflow_policy() { ruby scripts/lib/workflow_policy.rb policy "${1:-.github/workflows}"; }
workflow_backstop() { ruby scripts/lib/workflow_policy.rb backstop .github/workflows; }
required_checks() { ruby scripts/lib/workflow_policy.rb required-checks "${REQUIRED_CHECKS_DOC:-docs/ci-checks.md}" "${1:-}" "${REQUIRED_CHECKS[@]}"; }

# The published roster must match REQUIRED_CHECKS. The ruleset comparison is
# advisory here because only a maintainer can change the develop ruleset, and a
# workflow that is red until then would block its own pull request. Run
# `required-checks` directly for the strict comparison.
workflow_lint() {
  require_tool actionlint 1.7.7
  require_tool shellcheck 0.10.0
  actionlint -oneline "-shellcheck=$(command -v shellcheck)"
  pin_scan
  composite_secrets
  workflow_policy
  ruby scripts/lib/workflow_policy.rb roster-doc "${REQUIRED_CHECKS_DOC:-docs/ci-checks.md}" "${REQUIRED_CHECKS[@]}"
  if ! ruby scripts/lib/workflow_policy.rb ruleset "${1:-}" "${REQUIRED_CHECKS[@]}"; then
    echo '::warning title=Required checks::The develop ruleset does not require exactly the checks in docs/ci-checks.md.'
  fi
}

workflow_security() {
  require_tool zizmor 1.5.2
  local -a paths=(.github/workflows/)
  [[ ! -d .github/actions ]] || paths+=(.github/actions/)
  zizmor --config zizmor.yml --min-severity=medium "${paths[@]}"
  workflow_backstop
}

install_ci_tools() {
  local target=${1:-} artifact hash url archive
  local darwin=false codeql=false gitleaks=false
  case "$target" in
    workflow-lint|workflow-security|dependency-scan) ;;
    static-analysis) darwin=true; codeql=true; gitleaks=true ;;
    swift-analysis) darwin=true; codeql=true ;;
    secrets-scan) darwin=true; gitleaks=true ;;
    *) fail "unknown install-ci-tools target: $target"; return 1;;
  esac
  if [[ "$darwin" == true ]]; then
    [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { fail "install-ci-tools $target requires Darwin arm64"; return 1; }
    [[ "$codeql" == false ]] || command -v zstd >/dev/null 2>&1 || { fail 'zstd is required'; return 1; }
  else
    [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { fail 'install-ci-tools requires Linux x86_64'; return 1; }
  fi
  mkdir -p .build/ci-tools
  if [[ "$codeql" == true ]]; then
    url=https://github.com/github/codeql-action/releases/download/codeql-bundle-v2.27.2/codeql-bundle-swift-osx64.tar.zst
    hash=25a08dfd23997ccf6374b5a70d9aa27a510e027f1b5aed60e1a653f8a3596375
    archive=.build/ci-tools/codeql-bundle.tar.zst
    curl -fsSL "$url" -o "$archive"
    printf '%s  %s\n' "$hash" "$archive" | shasum -a 256 -c -
    zstd -dc "$archive" | tar -xf - -C .build/ci-tools
  fi
  if [[ "$gitleaks" == true ]]; then
    url=https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_darwin_arm64.tar.gz
    hash=b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5
    archive=.build/ci-tools/gitleaks.tar.gz
    curl -fsSL "$url" -o "$archive"
    printf '%s  %s\n' "$hash" "$archive" | shasum -a 256 -c -
    tar -xzf "$archive" -C .build/ci-tools gitleaks
  fi
  if [[ "$darwin" == true ]]; then
    : # CodeQL and gitleaks are installed above.
  elif [[ "$target" == workflow-lint ]]; then
    url=https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_1.7.7_linux_amd64.tar.gz
    hash=023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757
    archive=.build/ci-tools/actionlint.tar.gz
    curl -fsSL "$url" -o "$archive"
    printf '%s  %s\n' "$hash" "$archive" | sha256sum -c -
    tar -xzf "$archive" -C .build/ci-tools actionlint
    url=https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz
    hash=6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87
    archive=.build/ci-tools/shellcheck.tar.xz
    curl -fsSL "$url" -o "$archive"
    printf '%s  %s\n' "$hash" "$archive" | sha256sum -c -
    tar -xJf "$archive" -C .build/ci-tools shellcheck-v0.10.0/shellcheck
    cp .build/ci-tools/shellcheck-v0.10.0/shellcheck .build/ci-tools/shellcheck
  elif [[ "$target" == dependency-scan ]]; then
    url=https://github.com/google/osv-scanner/releases/download/v2.3.3/osv-scanner_linux_amd64
    hash=777b4bb7ddd10bdcc8a1aa398d37d05e91e866e7586f9cff3fca2f72b8153033
    artifact=.build/ci-tools/osv-scanner
    curl -fsSL "$url" -o "$artifact"
    printf '%s  %s\n' "$hash" "$artifact" | sha256sum -c -
    chmod +x "$artifact"
  else
    # pip refuses any artifact whose sha256 differs from the pinned manylinux wheel.
    printf 'zizmor==1.5.2 --hash=sha256:0c5f656106c430748858ae459c41c9eed09a1e01e5f42015d80c8fe34740d173\n' > .build/ci-tools/zizmor-requirements.txt
    python3 -m venv .build/ci-tools/zizmor-venv
    .build/ci-tools/zizmor-venv/bin/pip install --quiet --disable-pip-version-check --no-deps --only-binary=:all: --require-hashes -r .build/ci-tools/zizmor-requirements.txt
    ln -sf zizmor-venv/bin/zizmor .build/ci-tools/zizmor
  fi
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    if [[ "$codeql" == true ]]; then printf '%s\n' "$ROOT/.build/ci-tools/codeql" >> "$GITHUB_PATH"; fi
    printf '%s\n' "$ROOT/.build/ci-tools" >> "$GITHUB_PATH"
  else
    if [[ "$codeql" == true ]]; then echo "install-ci-tools: add $ROOT/.build/ci-tools/codeql to PATH"; fi
    echo "install-ci-tools: add $ROOT/.build/ci-tools to PATH"
  fi
}

driver_conditions() {
  local source line condition declared known found=0
  while IFS= read -r source; do
    while IFS= read -r line; do
      while [[ "$line" =~ ([A-Za-z_][A-Za-z_0-9]*_DRIVER_ENABLED) ]]; do
        condition=${BASH_REMATCH[1]}
        line=${line#*"$condition"}
        declared=0
        for known in "${ALL_DRIVER_CONDITIONS[@]+"${ALL_DRIVER_CONDITIONS[@]}"}"; do [[ "$known" == "$condition" ]] && declared=1; done
        if (( ! declared )); then printf '%s: undeclared Driver condition: %s\n' "$source" "$condition" >&2; found=1; fi
      done
    done < <(grep -E '^[[:space:]]*#(if|elseif)\b' "$source" || true)
  done < <(find Sources -type f -name '*.swift' | sort)
  (( ! found ))
}

project_paths() {
  find . \( -path './.build' -o -path './.swiftpm' -o -name '_bmad*' \) -prune -o \( -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print -prune
}

# Every discovered project or workspace needs at least one SDK:path:scheme build entry.
project_tripwire() {
  local project entry rest listed
  while IFS= read -r project; do
    project=${project#./}
    listed=0
    for entry in "${XCODE_BUILD_SCHEMES[@]+"${XCODE_BUILD_SCHEMES[@]}"}"; do
      rest=${entry#*:}
      [[ "$entry" == *:*:* && "${rest%%:*}" == "$project" && -n "${rest#*:}" ]] && listed=1
    done
    (( listed )) || { fail "Xcode project $project has no XCODE_BUILD_SCHEMES entry"; return 1; }
  done < <(project_paths)
  if [[ -z "$(project_paths)" ]]; then echo 'no Xcode targets declared yet'; fi
}

container_flag() {
  case "$1" in
    *.xcworkspace) echo -workspace ;;
    *.xcodeproj) echo -project ;;
    *) fail "not an Xcode project or workspace: $1"; return 1 ;;
  esac
}

ui_project_tripwire() {
  local project entry listed reason
  while IFS= read -r project; do
    project=${project#./}
    listed=0
    for entry in "${XCODE_UITEST_SCHEMES[@]+"${XCODE_UITEST_SCHEMES[@]}"}"; do
      [[ "${entry%%:*}" == "$project" && -n "${entry#*:}" ]] && listed=1
    done
    for entry in "${XCODE_UITEST_OPTOUT[@]+"${XCODE_UITEST_OPTOUT[@]}"}"; do
      reason=${entry#*:}
      if [[ "${entry%%:*}" == "$project" && "$entry" == *:* && -n "${reason//[[:space:]]/}" ]]; then
        echo "UI tests opted out for $project: $reason"
        listed=1
      fi
    done
    (( listed )) || { fail "Xcode project $project has no UI-test scheme or reasoned opt-out"; return 1; }
  done < <(project_paths)
  if [[ -z "$(project_paths)" ]]; then echo 'no Xcode targets declared yet'; fi
}

check_xcode() {
  local expected actual
  expected=$(cat .xcode-version)
  command -v xcodebuild >/dev/null 2>&1 || { fail 'requires Xcode: xcodebuild is unavailable'; return 1; }
  actual=$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode //p') || { fail 'requires Xcode: xcodebuild failed'; return 1; }
  [[ "$actual" == "$expected" ]] || { fail "Xcode version mismatch: expected $expected, got ${actual:-empty}"; return 1; }
  xcodebuild -version
}

test_optout_reason() {
  local entry reason
  for entry in "${XCODE_TEST_OPTOUT[@]+"${XCODE_TEST_OPTOUT[@]}"}"; do
    reason=${entry#*:}
    if [[ "${entry%%:*}" == "$1" && "$entry" == *:* && -n "${reason//[[:space:]]/}" ]]; then
      echo "$reason"
      return 0
    fi
  done
  return 1
}

run_xcode_builds() {
  local entry sdk project scheme destination flag reason
  local -a actions
  local -a entries=("${XCODE_BUILD_SCHEMES[@]+"${XCODE_BUILD_SCHEMES[@]}"}")
  project_tripwire
  for entry in "${entries[@]+"${entries[@]}"}"; do
    sdk=${entry%%:*}; project=${entry#*:}; scheme=${project#*:}; project=${project%%:*}
    [[ "$entry" == *:*:* && -n "$project" && -n "$scheme" ]] || { fail "invalid Xcode build entry: $entry"; return 1; }
    flag=$(container_flag "$project")
    destination='platform=iOS Simulator,name=iPhone 17'
    if [[ "$sdk" == watchsimulator ]]; then destination='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'; fi
    actions=(build test)
    if reason=$(test_optout_reason "$project"); then
      actions=(build)
      echo "Xcode test action opted out for $project: $reason"
    fi
    header "Xcode ${actions[*]}: $scheme ($sdk)"
    xcodebuild "${actions[@]}" "$flag" "$project" -scheme "$scheme" -sdk "$sdk" -destination "$destination" -derivedDataPath .build/xcode-dd CODE_SIGNING_ALLOWED=NO
  done
}

ios_gate() {
  local condition flags=()
  header 'Toolchain and Bash'; bash --version | head -1; check_xcode
  header 'Default Swift build and tests'
  swift build --build-tests --disable-automatic-resolution -Xswiftc -warnings-as-errors
  swift test --skip-build
  header 'Every Driver build and tests'
  driver_conditions
  if [[ -z "${ALL_DRIVER_CONDITIONS[@]+present}" ]]; then echo 'No Driver conditions declared; building and testing every Driver target again'; fi
  for condition in "${ALL_DRIVER_CONDITIONS[@]+"${ALL_DRIVER_CONDITIONS[@]}"}"; do flags+=(-Xswiftc "-D${condition}"); done
  swift build --scratch-path .build/all-drivers --build-tests --disable-automatic-resolution -Xswiftc -warnings-as-errors "${flags[@]+"${flags[@]}"}"
  swift test --scratch-path .build/all-drivers --skip-build "${flags[@]+"${flags[@]}"}"
  header 'Safety guards'; bash scripts/guards/safety_guards.sh; bash scripts/guards/safety_guards.sh --self-test
  header 'Driver guards'; bash scripts/guards/driver_guards.sh; bash scripts/guards/driver_guards.sh --self-test
  header 'Xcode targets'; run_xcode_builds
}

ui_tests() {
  local entry project scheme destination safe flag
  local -a schemes=("${XCODE_UITEST_SCHEMES[@]+"${XCODE_UITEST_SCHEMES[@]}"}") destinations=("${XCODE_UITEST_DESTINATIONS[@]+"${XCODE_UITEST_DESTINATIONS[@]}"}")
  header 'Simulator UI tests'
  ui_project_tripwire
  if (( ${#schemes[@]} > 0 && ${#destinations[@]} == 0 )); then fail 'UI test schemes require destinations'; return 1; fi
  mkdir -p .build/ui-results
  for entry in "${schemes[@]+"${schemes[@]}"}"; do
    project=${entry%%:*}; scheme=${entry#*:}
    [[ "$entry" == *:* && -n "$project" && -n "$scheme" ]] || { fail "invalid UI-test entry: $entry"; return 1; }
    flag=$(container_flag "$project")
    for destination in "${destinations[@]+"${destinations[@]}"}"; do
      safe=$(printf '%s-%s' "$scheme" "$destination" | tr -c '[:alnum:]_-' '_')
      # xcodebuild refuses an existing result bundle, so clear this run's path first.
      rm -rf ".build/ui-results/${safe}.xcresult"
      xcodebuild test "$flag" "$project" -scheme "$scheme" -destination "$destination" -derivedDataPath .build/xcode-dd -resultBundlePath ".build/ui-results/${safe}.xcresult" CODE_SIGNING_ALLOWED=NO
    done
  done
}

assert_case() {
  local label=$1 expected=$2 message=$3 output status=0; shift 3
  output=$("$@" 2>&1) || status=$?
  if [[ "$expected" == pass ]]; then
    (( status == 0 )) || { fail "self-test $label unexpectedly failed: $output"; return 1; }
  else
    (( status != 0 )) || { fail "self-test $label unexpectedly passed"; return 1; }
    [[ "$output" == *"$message"* ]] || { fail "self-test $label missed expected message '$message': $output"; return 1; }
  fi
  echo "self-test: $label: $expected"
}

self_test() {
  local fixture=.build/ci-local-self-test
  rm -rf "$fixture"
  mkdir -p "$fixture"
  assert_case detect-failure fail 'detect-changes result is failure' env DETECT_RESULT=failure SHOULD_BUILD=true WORK_RESULT=success EVENT_NAME=pull_request "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case irrelevant-pr pass '' env DETECT_RESULT=success SHOULD_BUILD=false WORK_RESULT=skipped EVENT_NAME=pull_request "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case skipped-required-build fail 'required build is skipped' env DETECT_RESULT=success SHOULD_BUILD=true WORK_RESULT=skipped EVENT_NAME=pull_request "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case cancelled-build fail 'required build is cancelled' env DETECT_RESULT=success SHOULD_BUILD=true WORK_RESULT=cancelled EVENT_NAME=push "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case dispatch-skipped fail 'workflow_dispatch requires a successful build' env DETECT_RESULT=success SHOULD_BUILD=false WORK_RESULT=skipped EVENT_NAME=workflow_dispatch "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case dispatch-success pass '' env DETECT_RESULT=success SHOULD_BUILD=false WORK_RESULT=success EVENT_NAME=workflow_dispatch "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case schedule-skipped fail 'schedule requires a successful build' env DETECT_RESULT=success SHOULD_BUILD=false WORK_RESULT=skipped EVENT_NAME=schedule "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case push-success pass '' env DETECT_RESULT=success SHOULD_BUILD=true WORK_RESULT=success EVENT_NAME=push "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case pr-success pass '' env DETECT_RESULT=success SHOULD_BUILD=true WORK_RESULT=success EVENT_NAME=pull_request "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case pr-failure fail 'required build is failure' env DETECT_RESULT=success SHOULD_BUILD=true WORK_RESULT=failure EVENT_NAME=pull_request "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case unknown-event fail 'unknown event merge_group' env DETECT_RESULT=success SHOULD_BUILD=true WORK_RESULT=success EVENT_NAME=merge_group "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case garbage-should-build fail 'should_build is garbage' env DETECT_RESULT=success SHOULD_BUILD=garbage WORK_RESULT=success EVENT_NAME=pull_request "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case empty-values fail 'gate input is empty' env -u DETECT_RESULT -u SHOULD_BUILD -u WORK_RESULT -u EVENT_NAME "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case dependency-skip pass '' env GATE_NAME='Dependency Scan Gate' DETECT_RESULT=success SHOULD_BUILD=false WORK_RESULT=skipped EVENT_NAME=pull_request "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case dependency-schedule-skip fail 'schedule requires a successful build' env GATE_NAME='Dependency Scan Gate' DETECT_RESULT=success SHOULD_BUILD=false WORK_RESULT=skipped EVENT_NAME=schedule "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  assert_case dependency-failure fail 'required build is failure' env GATE_NAME='Dependency Scan Gate' DETECT_RESULT=success SHOULD_BUILD=true WORK_RESULT=failure EVENT_NAME=pull_request "$BASH" "$ROOT/scripts/ci-local.sh" gate-verdict
  ruby scripts/lib/workflow_policy_test.rb
  mkdir -p "$fixture/secrets/.github/actions"
  printf 'name: test\n# ${{ secrets.COMMENTED }}\n' > "$fixture/secrets/.github/actions/action.yml"
  (cd "$fixture/secrets"; assert_case composite-comment pass '' composite_secrets)
  printf 'run: ${{ secrets.EXPOSED }}\n' >> "$fixture/secrets/.github/actions/action.yml"
  (cd "$fixture/secrets"; assert_case composite-hit fail 'composite action secrets reference' composite_secrets)
  printf 'name: test\nrun: ${{secrets.TIGHT}}\n' > "$fixture/secrets/.github/actions/action.yml"
  (cd "$fixture/secrets"; assert_case composite-hit-unspaced fail 'composite action secrets reference' composite_secrets)
  printf 'name: test\nrun: ${{ secrets.NO_NEWLINE }}' > "$fixture/secrets/.github/actions/action.yml"
  (cd "$fixture/secrets"; assert_case composite-hit-no-newline fail 'composite action secrets reference' composite_secrets)
  rm -rf "$fixture/secrets/.github/actions"
  (cd "$fixture/secrets"; assert_case composite-absent pass '' composite_secrets)
  assert_case missing-actionlint fail 'actionlint 1.7.7 is required' env PATH=/usr/bin:/bin "$BASH" "$ROOT/scripts/ci-local.sh" workflow-lint
  assert_case missing-zizmor fail 'zizmor 1.5.2 is required' env PATH=/usr/bin:/bin "$BASH" "$ROOT/scripts/ci-local.sh" workflow-security
  assert_case missing-osv fail 'osv-scanner 2.3.3 is required' env PATH=/usr/bin:/bin "$BASH" "$ROOT/scripts/ci-local.sh" dependency-scan
  ruby scripts/lib/sarif_gate_test.rb
  assert_case missing-codeql fail 'codeql 2.27.2 is required' env CI_LOCAL_TOOLS="$ROOT/$fixture/no-tools" PATH=/usr/bin:/bin "$BASH" "$ROOT/scripts/ci-local.sh" swift-analysis
  assert_case missing-gitleaks fail 'gitleaks 8.30.1 is required' env CI_LOCAL_TOOLS="$ROOT/$fixture/no-tools" PATH=/usr/bin:/bin "$BASH" "$ROOT/scripts/ci-local.sh" secrets-scan
  mkdir -p "$fixture/mock-bin"
  ln -s /usr/bin/dirname "$fixture/mock-bin/dirname"
  ln -s /bin/cat "$fixture/mock-bin/cat"
  printf '#!/bin/sh\necho Linux\n' > "$fixture/mock-bin/uname"
  chmod +x "$fixture/mock-bin/uname"
  assert_case wrong-install-platform fail 'requires Darwin arm64' env PATH="$ROOT/$fixture/mock-bin:/usr/bin:/bin" "$BASH" "$ROOT/scripts/ci-local.sh" install-ci-tools static-analysis
  printf '#!/bin/sh\nif [ "$1" = -s ]; then echo Darwin; else echo arm64; fi\n' > "$fixture/mock-bin/uname"
  assert_case missing-zstd fail 'zstd is required' env PATH="$ROOT/$fixture/mock-bin" "$BASH" "$ROOT/scripts/ci-local.sh" install-ci-tools static-analysis
  printf '#!/bin/sh\necho "CodeQL command-line toolchain release 2.27.2."\n' > "$fixture/mock-bin/codeql"
  chmod +x "$fixture/mock-bin/codeql"
  assert_case missing-xcodebuild fail 'xcodebuild is unavailable' env CI_LOCAL_TOOLS="$ROOT/$fixture/no-tools" PATH="$ROOT/$fixture/mock-bin" "$BASH" "$ROOT/scripts/ci-local.sh" swift-analysis
  assert_case unset-status fail 'status 2' "$BASH" "$ROOT/scripts/ci-local.sh" status-default-test
  assert_case needs-all-success pass '' env NEEDS_RESULTS='guards=success codeql=success' "$BASH" "$ROOT/scripts/ci-local.sh" needs-verdict
  assert_case needs-failure fail 'codeql result is failure' env NEEDS_RESULTS='guards=success codeql=failure' "$BASH" "$ROOT/scripts/ci-local.sh" needs-verdict
  assert_case needs-skipped fail 'guards result is skipped' env NEEDS_RESULTS='guards=skipped codeql=success' "$BASH" "$ROOT/scripts/ci-local.sh" needs-verdict
  assert_case needs-cancelled fail 'codeql result is cancelled' env NEEDS_RESULTS='guards=success codeql=cancelled' "$BASH" "$ROOT/scripts/ci-local.sh" needs-verdict
  assert_case needs-empty-result fail 'codeql result is empty' env NEEDS_RESULTS='guards=success codeql=' "$BASH" "$ROOT/scripts/ci-local.sh" needs-verdict
  assert_case needs-unset fail 'needs results are empty' env -u NEEDS_RESULTS "$BASH" "$ROOT/scripts/ci-local.sh" needs-verdict
  assert_case needs-blank fail 'needs results are empty' env NEEDS_RESULTS='  ' "$BASH" "$ROOT/scripts/ci-local.sh" needs-verdict
  assert_case needs-malformed fail 'malformed needs result' env NEEDS_RESULTS='guards=success codeql' "$BASH" "$ROOT/scripts/ci-local.sh" needs-verdict
  mkdir -p "$fixture/.github/workflows" "$fixture/.github/actions"
  (cd "$fixture"; printf 'steps:\n  - uses: a/b@v1.0.0\n' > .github/workflows/check.yml; assert_case action-tag fail 'unpinned action' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - uses: a/b@1234abcd\n' > .github/workflows/check.yml; assert_case short-sha fail 'unpinned action' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - uses: a/b\n' > .github/workflows/check.yml; assert_case missing-at fail 'unpinned action' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - uses : a/b@main\n' > .github/workflows/check.yml; assert_case spaced-uses fail 'unpinned action' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - {uses: a/b@main}\n' > .github/workflows/check.yml; assert_case flow-uses fail 'unpinned action' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - "uses": a/b@main\n' > .github/workflows/check.yml; assert_case quoted-uses fail 'unpinned action' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - uses: docker://alpine@sha256:abcd\n' > .github/workflows/check.yml; assert_case short-docker-digest fail 'unpinned action' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - uses: a/b@AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' > .github/workflows/check.yml; assert_case uppercase-sha fail 'unpinned action' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - uses: a/b@%040d\n' 0 > .github/workflows/check.yml; assert_case pinned-action pass '' pin_scan)
  (cd "$fixture"; printf 'steps:\n  - uses: docker://alpine@sha256:%064d\n' 0 > .github/workflows/check.yml; assert_case pinned-docker pass '' pin_scan)
  mkdir -p "$fixture/Sources"; printf '#if SAMPLE_DRIVER_ENABLED\n#endif\n' > "$fixture/Sources/Test.swift"
  (cd "$fixture"; assert_case undeclared-driver-condition fail 'undeclared Driver condition' driver_conditions)
  (cd "$fixture"; assert_case no-project-build pass '' project_tripwire; assert_case no-project-ui pass '' ui_project_tripwire)
  mkdir -p "$fixture/Test.xcodeproj"
  (cd "$fixture"; assert_case unlisted-build-project fail 'Test.xcodeproj has no XCODE_BUILD_SCHEMES entry' project_tripwire; assert_case unlisted-ui-project fail 'has no UI-test scheme or reasoned opt-out' ui_project_tripwire)
  (cd "$fixture"; XCODE_BUILD_SCHEMES=('iphonesimulator:Test.xcodeproj:Test'); assert_case listed-build-project pass '' project_tripwire)
  (cd "$fixture"; XCODE_BUILD_SCHEMES=('iphonesimulator:Test.xcodeproj:'); assert_case empty-build-scheme fail 'Test.xcodeproj has no XCODE_BUILD_SCHEMES entry' project_tripwire)
  mkdir -p "$fixture/Other.xcodeproj"
  (cd "$fixture"; XCODE_BUILD_SCHEMES=('iphonesimulator:Test.xcodeproj:Test'); assert_case second-build-project fail 'Other.xcodeproj has no XCODE_BUILD_SCHEMES entry' project_tripwire)
  rm -rf "$fixture/Other.xcodeproj"
  assert_case container-project pass '' container_flag Test.xcodeproj
  assert_case container-workspace pass '' container_flag Test.xcworkspace
  assert_case container-other fail 'not an Xcode project or workspace' container_flag Test
  [[ "$(container_flag App.xcworkspace)" == -workspace && "$(container_flag App.xcodeproj)" == -project ]] || { fail 'self-test container-flag-value: wrong flag'; return 1; }
  echo 'self-test: container-flag-value: pass'
  (cd "$fixture"; XCODE_UITEST_OPTOUT=('Test.xcodeproj:'); assert_case empty-ui-optout-reason fail 'has no UI-test scheme or reasoned opt-out' ui_project_tripwire)
  (cd "$fixture"; XCODE_UITEST_OPTOUT=('Test.xcodeproj:no UI-test target yet'); assert_case reasoned-ui-optout pass '' ui_project_tripwire)
  mkdir -p "$fixture/Test.xcodeproj/project.xcworkspace"
  (cd "$fixture"; XCODE_UITEST_OPTOUT=('Test.xcodeproj:no UI-test target yet'); assert_case nested-workspace-ignored pass '' ui_project_tripwire)
  (XCODE_TEST_OPTOUT=('Test.xcodeproj:tested elsewhere'); assert_case reasoned-test-optout pass '' test_optout_reason Test.xcodeproj)
  (XCODE_TEST_OPTOUT=('Test.xcodeproj: '); assert_case blank-test-optout-reason fail '' test_optout_reason Test.xcodeproj)
  (XCODE_TEST_OPTOUT=('Other.xcodeproj:tested elsewhere'); assert_case other-project-test-optout fail '' test_optout_reason Test.xcodeproj)
  echo 'self-test: all cases passed'
}

case "${1:-}" in
  ios-gate) ios_gate ;;
  ui-tests) ui_tests ;;
  gate-verdict) gate_verdict ;;
  workflow-pins) pin_scan ;;
  static-analysis) static_analysis ;;
  swift-analysis) swift_analysis ;;
  static-guards) static_guards ;;
  needs-verdict) needs_verdict ;;
  secrets-scan) secrets_scan ;;
  status-default-test) status=''; [[ "${status:-2}" == 0 ]] || fail "status ${status:-2}" ;;
  dependency-scan) dependency_scan ;;
  workflow-lint) workflow_lint "${2:-}" ;;
  workflow-policy) workflow_policy "${2:-}" ;;
  workflow-security) workflow_security ;;
  required-checks) required_checks "${2:-}" ;;
  install-ci-tools) install_ci_tools "${2:-}" ;;
  --self-test) self_test ;;
  '') usage ;;
  *) usage >&2; exit 2 ;;
esac
