#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# Add Driver compilation conditions here when a Driver first uses one.
ALL_DRIVER_CONDITIONS=()
# Entries are SDK:project-path:scheme. List each scheme when its project lands.
XCODE_BUILD_SCHEMES=()
# Entries are project-path:scheme and project-path:reason, respectively.
# An opt-out is only for a project that has no UI-test target yet.
XCODE_UITEST_SCHEMES=()
XCODE_UITEST_DESTINATIONS=()
XCODE_UITEST_OPTOUT=()

usage() {
  cat <<'EOF'
Usage: bash scripts/ci-local.sh <command>
  ios-gate       Build and test Swift, Drivers, guards, and declared Xcode targets
  ui-tests       Run declared XCUITest schemes on declared Simulator destinations
  gate-verdict   Evaluate DETECT_RESULT, SHOULD_BUILD, WORK_RESULT, EVENT_NAME
  workflow-pins  Check action references under .github/workflows and .github/actions
  --self-test    Exercise the verdict and guard failure paths without Xcode

Static analysis, dependency scan, and workflow security gates are not implemented here yet.
EOF
}

header() { printf '\n== %s ==\n' "$1"; }
fail() { printf 'ci-local: %s\n' "$1" >&2; return 1; }

gate_verdict() {
  local detect=${DETECT_RESULT:-} build=${WORK_RESULT:-} should=${SHOULD_BUILD:-} event=${EVENT_NAME:-}
  if [[ -z "$detect" || -z "$build" || -z "$should" || -z "$event" ]]; then fail 'gate input is empty'; return 1; fi
  if [[ "$detect" != success ]]; then fail "detect-changes result is ${detect:-empty}; gate fails"; return 1; fi
  if [[ "$event" == workflow_dispatch || "$event" == schedule ]]; then
    [[ "$build" == success ]] || { fail "${event} requires a successful build (got ${build:-empty})"; return 1; }
    echo 'iOS Gate: build succeeded'; return 0
  fi
  if [[ "$event" != push && "$event" != pull_request ]]; then fail "unknown event ${event:-empty}"; return 1; fi
  if [[ "$should" == false ]]; then echo 'iOS Gate: iOS paths unchanged; build skipped'; return 0; fi
  if [[ "$should" != true ]]; then fail "should_build is ${should:-empty}; gate fails"; return 1; fi
  [[ "$build" == success ]] || { fail "required build is ${build:-empty}; gate fails"; return 1; }
  echo 'iOS Gate: build succeeded'
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

run_xcode_builds() {
  local entry sdk project scheme destination flag
  local -a entries=("${XCODE_BUILD_SCHEMES[@]+"${XCODE_BUILD_SCHEMES[@]}"}")
  project_tripwire
  for entry in "${entries[@]+"${entries[@]}"}"; do
    sdk=${entry%%:*}; project=${entry#*:}; scheme=${project#*:}; project=${project%%:*}
    [[ "$entry" == *:*:* && -n "$project" && -n "$scheme" ]] || { fail "invalid Xcode build entry: $entry"; return 1; }
    flag=$(container_flag "$project")
    destination='platform=iOS Simulator,name=iPhone 17'
    if [[ "$sdk" == watchsimulator ]]; then destination='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'; fi
    header "Xcode build and test: $scheme ($sdk)"
    xcodebuild build test "$flag" "$project" -scheme "$scheme" -sdk "$sdk" -destination "$destination" -derivedDataPath .build/xcode-dd CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
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
      xcodebuild test "$flag" "$project" -scheme "$scheme" -destination "$destination" -derivedDataPath .build/xcode-dd -resultBundlePath ".build/ui-results/${safe}.xcresult" CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
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
  echo 'self-test: all cases passed'
}

case "${1:-}" in
  ios-gate) ios_gate ;;
  ui-tests) ui_tests ;;
  gate-verdict) gate_verdict ;;
  workflow-pins) pin_scan ;;
  --self-test) self_test ;;
  '') usage ;;
  *) usage >&2; exit 2 ;;
esac
