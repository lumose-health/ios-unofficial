#!/usr/bin/env bash
#
# Safety guards for Sources/ — the mechanical half of story 1.2 (AC 3, AC 4, AC 6).
#
# Two invariants that review cannot be trusted to hold over hundreds of PRs:
#
#   AD-2 / SI-4  Each safety constant is defined EXACTLY ONCE, in
#                Sources/SafetyCore/SafetyConstants.swift, and nowhere else —
#                no private copy, no inline literal, no "just this once" re-spell.
#                Copies of these values also live in the Android app and the
#                backend on independent release cadences; when they desync,
#                glucose is mis-converted or mis-validated. Android carries the
#                mirror-image guard (SafetyConstantDriftGuardTest.kt).
#
#   AD-14        Current time comes from an injected Clock. `Date()`, `Date.now`
#                and `Date.init` (plus the other spellings of "read the wall
#                clock") are rejected everywhere under Sources/SafetyCore except
#                SystemClock.swift — the single adapter, exempted by exact path.
#
# The scan is comment-stripped and string-literal aware (lib/strip_swift_comments.awk)
# so a doc comment may name a value without tripping the guard, and cannot hide a
# real occurrence from it. Numeric matching is digit-bounded (lib/count_token.awk)
# so `20...5000` and `18.01565` are caught rather than matched as the canonical
# token they are a prefix of.
#
# There is no per-line escape hatch, by design. A new legitimate occurrence of a
# guarded value means editing this script — deliberately, in the same PR, where a
# reviewer sees it — exactly as Android requires its SCAN_SITES inventory to be
# updated. A guard with a bypass comment stops being a guard the first time
# someone is in a hurry.
#
# Usage:  bash scripts/guards/safety_guards.sh              run the gate
#         bash scripts/guards/safety_guards.sh --self-test  prove the gate can fail
#         bash scripts/guards/safety_guards.sh --root DIR   scan DIR/Sources
#                                                           (used by --self-test)
#         bash scripts/guards/safety_guards.sh --quiet       report failures only
#
# Exit: 0 clean, 1 violation, 2 usage/environment error.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STRIPPER="$SCRIPT_DIR/lib/strip_swift_comments.awk"
COUNTER="$SCRIPT_DIR/lib/count_token.awk"

ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
MODE="check"
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --self-test) MODE="self-test"; shift ;;
        --quiet) QUIET=1; shift ;;
        --root)
            [ $# -ge 2 ] || { echo "--root needs a directory" >&2; exit 2; }
            ROOT="$2"; shift 2 ;;
        -h|--help) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Canonical values. These literals live HERE, not in Sources/ — the guard is the
# pin, the source is the single definition site. Changing one is a cross-repo
# decision: Android and the backend must move in the same change.
# ---------------------------------------------------------------------------
CANONICAL_FILE="Sources/SafetyCore/SafetyConstants.swift"
CLOCK_EXEMPT_FILE="Sources/SafetyCore/SystemClock.swift"

FACTOR="18.0156"           # mg/dL per mmol/L
RANGE_LITERAL="20...500"   # the inclusive glucose bound, as written in Swift
BOUND_LOW="20"
BOUND_HIGH="500"
BOUND_LOW_OUTSIDE="19"     # one below the inclusive lower bound
BOUND_HIGH_OUTSIDE="501"   # one above the inclusive upper bound
EPOCH="1199145600"         # Tandem epoch offset, seconds (2008-01-01T00:00:00Z)

# Every spelling of "read the wall clock". A superset of the three AC 4 names:
# the extras are the same act under another name, and leaving them out would let
# the guard be walked around without even trying.
CLOCK_FORBIDDEN="Date() Date.now Date.init timeIntervalSinceNow Date.timeIntervalSinceReferenceDate CFAbsoluteTimeGetCurrent"

SOURCES="$ROOT/Sources"
FAILURES=0

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok() { say "  ok   $*"; }
bad() { printf '  FAIL %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
die() { printf 'safety_guards: %s\n' "$*" >&2; exit 2; }

# --- normalisation ---------------------------------------------------------
# Comments out, Swift digit separators out (twice, because a single pass leaves
# `1_2_3` as `12_3`), whitespace around range operators out — so `20 ... 500`
# and `1_199_145_600` cannot be used to spell a second copy the scan misses.
normalize() {
    awk -f "$STRIPPER" "$1" \
        | sed -E 's/([0-9])_([0-9])/\1\2/g' \
        | sed -E 's/([0-9])_([0-9])/\1\2/g' \
        | sed -E 's/[[:space:]]*\.\.\.[[:space:]]*/.../g; s/[[:space:]]*\.\.<[[:space:]]*/..</g'
}

swift_files() {
    [ -d "$1" ] || return 0
    find "$1" -type f -name '*.swift' | LC_ALL=C sort
}

count_in_file() { normalize "$1" | awk -v tok="$2" -v bounded="$3" -f "$COUNTER"; }

rel() { printf '%s' "${1#"$ROOT"/}"; }

# total_and_sites <dir> <token> <bounded> -> "<total>|<rel(path):n rel(path):n ...>"
#
# The site list is space-separated, so a source path containing a space would be
# mis-split by the callers. That direction is safe: a mis-split site matches
# neither the canonical path nor the clock exemption, so the guard fails loudly
# rather than passing something it did not really check.
total_and_sites() {
    local dir="$1" token="$2" bounded="$3" total=0 sites="" file n
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        n=$(count_in_file "$file" "$token" "$bounded")
        if [ "$n" -gt 0 ]; then
            total=$((total + n))
            sites="$sites $(rel "$file"):$n"
        fi
    done <<EOF
$(swift_files "$dir")
EOF
    printf '%s|%s' "$total" "${sites# }"
}

# expect_count <token> <bounded> <expected> <where: canonical|anywhere> <description>
expect_count() {
    local token="$1" bounded="$2" expected="$3" where="$4" description="$5"
    local result total sites
    result=$(total_and_sites "$SOURCES" "$token" "$bounded")
    total="${result%%|*}"
    sites="${result#*|}"

    if [ "$total" -ne "$expected" ]; then
        bad "$description: expected $expected occurrence(s) of \`$token\` under Sources/, found $total${sites:+ (}${sites}${sites:+)}"
        return 0
    fi
    if [ "$expected" -gt 0 ] && [ "$where" = "canonical" ]; then
        case "$sites" in
            "$CANONICAL_FILE:$expected") ;;
            *) bad "$description: \`$token\` must be defined in $CANONICAL_FILE, found in ${sites:-nothing}"; return 0 ;;
        esac
    fi
    ok "$description (\`$token\` x$total)"
}

# ---------------------------------------------------------------------------
# Preconditions. A guard that passes on a tree it never actually read is worse
# than no guard, because it reports green.
# ---------------------------------------------------------------------------
[ -f "$STRIPPER" ] || die "missing helper: $STRIPPER"
[ -f "$COUNTER" ] || die "missing helper: $COUNTER"

run_check() {
    [ -d "$SOURCES" ] || die "no Sources/ directory under $ROOT"
    [ -n "$(swift_files "$SOURCES")" ] || die "no Swift files under $SOURCES — nothing was scanned"
    [ -f "$ROOT/$CANONICAL_FILE" ] || die "missing canonical constants file: $CANONICAL_FILE"

    say "safety_guards: scanning $SOURCES"
    say ""
    say "AD-2/SI-4 — one definition site per safety constant"

    expect_count "$FACTOR" 1 1 canonical "mg/dL per mmol/L factor"
    expect_count "$RANGE_LITERAL" 1 1 canonical "glucose bound range literal"
    expect_count "$EPOCH" 1 1 canonical "Tandem epoch offset"

    # The bare bound numerals. Exactly one each, and both inside the canonical
    # range literal — this is what catches a re-spelling the range-literal scan
    # cannot see: `20..<501`, `let minGlucose = 20`, `mgdl > 500`, a widened
    # `20...5000`. The off-by-one neighbours must not appear at all; an
    # exclusive-bound mistake is the classic way a safety bound drifts by one.
    expect_count "$BOUND_LOW" 1 1 canonical "lower bound numeral"
    expect_count "$BOUND_HIGH" 1 1 canonical "upper bound numeral"
    expect_count "$BOUND_LOW_OUTSIDE" 1 0 anywhere "no off-by-one lower bound"
    expect_count "$BOUND_HIGH_OUTSIDE" 1 0 anywhere "no off-by-one upper bound"

    # Any OTHER `18.x` numeral is a rounded conversion factor — 18.02, 18.0182,
    # 18.016 — which would make the watch and the phone print different numbers
    # for one reading. Exactly one `18.x` may exist, and the check above already
    # pinned it to the canonical value in the canonical file.
    local factor_variants
    factor_variants=$(
        {
            while IFS= read -r file; do
                [ -n "$file" ] || continue
                normalize "$file"
            done <<EOF
$(swift_files "$SOURCES")
EOF
        } | { grep -oE '(^|[^0-9])18\.[0-9]+' || true; } | wc -l | tr -d ' '
    )
    if [ "$factor_variants" -ne 1 ]; then
        bad "conversion factor: expected exactly one \`18.x\` numeral under Sources/, found $factor_variants (a rounded variant of the factor is a cross-surface display drift)"
    else
        ok "no rounded variants of the conversion factor"
    fi

    say ""
    say "AD-14 — one clock; the wall clock is reachable only through SystemClock"

    # A stale exemption is a violation, not a broken environment: the guard would
    # keep reporting green while exempting a path nobody can see any more.
    local exemption_present=1
    if [ ! -f "$ROOT/$CLOCK_EXEMPT_FILE" ]; then
        exemption_present=0
        bad "the clock exemption names $CLOCK_EXEMPT_FILE, which does not exist — remove the exemption or restore the file; a stale exemption silently widens the guard"
    fi

    local scope="$SOURCES/SafetyCore" token result total sites offenders
    for token in $CLOCK_FORBIDDEN; do
        result=$(total_and_sites "$scope" "$token" 0)
        total="${result%%|*}"
        sites="${result#*|}"
        offenders=""
        for site in $sites; do
            case "$site" in
                "$CLOCK_EXEMPT_FILE:"*) ;;
                *) offenders="$offenders $site" ;;
            esac
        done
        if [ -n "$offenders" ]; then
            bad "wall-clock read \`$token\` outside the exemption:${offenders} — take a Clock and read \`now\` from it (see Sources/SafetyCore/Clock.swift)"
        else
            ok "no \`$token\` outside $CLOCK_EXEMPT_FILE"
        fi
    done

    # The exemption must stay a one-line adapter. If SystemClock grows a second
    # wall-clock read it has started doing time-dependent WORK, which belongs in
    # a type that takes a Clock and can be tested at its boundaries.
    local exempt_reads
    if [ "$exemption_present" -eq 1 ]; then
        exempt_reads=$(count_in_file "$ROOT/$CLOCK_EXEMPT_FILE" "Date()" 0)
        if [ "$exempt_reads" -ne 1 ]; then
            bad "$CLOCK_EXEMPT_FILE must contain exactly one \`Date()\`, found $exempt_reads — the exemption is an adapter, not a home for logic"
        else
            ok "$CLOCK_EXEMPT_FILE holds exactly one wall-clock read"
        fi
    fi

    say ""
    if [ "$FAILURES" -gt 0 ]; then
        printf 'safety_guards: %d violation(s)\n' "$FAILURES" >&2
        return 1
    fi
    say "safety_guards: clean"
    return 0
}

# ---------------------------------------------------------------------------
# --self-test (AC 6): a guard that cannot fail is not a guard.
#
# Copies Sources/ to a scratch tree, injects one violation at a time, and asserts
# the guard rejects it — plus two controls that must still PASS, so the negative
# cases prove precision rather than a script that always fails.
# ---------------------------------------------------------------------------
SELF_TEST_CASES="
control-clean|PASS|
dup-factor|FAIL|Sources/SafetyCore/GuardProbe.swift|let duplicateFactor = 18.0156
drifted-factor|FAIL|Sources/SafetyCore/GuardProbe.swift|let roundedFactor = 18.02
dup-range|FAIL|Sources/SafetyCore/GuardProbe.swift|let duplicateRange = 20...500
spaced-range|FAIL|Sources/SafetyCore/GuardProbe.swift|let spacedRange = 20 ... 500
widened-range|FAIL|Sources/SafetyCore/GuardProbe.swift|let widenedRange = 20...5000
half-open-bound|FAIL|Sources/SafetyCore/GuardProbe.swift|let halfOpen = 20..<501
bare-lower-bound|FAIL|Sources/SafetyCore/GuardProbe.swift|let minGlucose = 20
bare-upper-bound|FAIL|Sources/SafetyCore/GuardProbe.swift|let maxGlucose = 500
off-by-one-bound|FAIL|Sources/SafetyCore/GuardProbe.swift|let ceiling = 501
dup-epoch-underscored|FAIL|Sources/SafetyCore/GuardProbe.swift|let epochCopy = 1_199_145_600
wall-clock-date|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = Date()
wall-clock-date-now|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = Date.now
wall-clock-date-init|FAIL|Sources/SafetyCore/GuardProbe.swift|let make = Date.init
wall-clock-in-string-tail|FAIL|Sources/SafetyCore/GuardProbe.swift|let u = \"https://x\"; let stamp = Date()
comments-only-control|PASS|Sources/SafetyCore/GuardProbe.swift|// 18.0156 and 20...500 and 1199145600 and Date() and Date.now
"

self_test_write() {
    # $1 target file, $2 line of Swift/comment
    printf 'import Foundation\n%s\n' "$2" > "$1"
}

self_test() {
    local total=0 bad_cases=0 line name expect path payload tmp status log

    printf 'safety_guards --self-test: proving each guard can fail\n\n'

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        name="${line%%|*}"; line="${line#*|}"
        expect="${line%%|*}"; line="${line#*|}"
        path="${line%%|*}"
        payload="${line#*|}"
        [ "$path" = "$payload" ] && payload=""

        total=$((total + 1))
        tmp=$(mktemp -d "${TMPDIR:-/tmp}/safety_guards_selftest.XXXXXX")
        cp -R "$ROOT/Sources" "$tmp/Sources"

        case "$name" in
            control-clean) ;;
            *) self_test_write "$tmp/$path" "$payload" ;;
        esac

        log="$tmp/guard.log"
        status=0
        bash "${BASH_SOURCE[0]}" --root "$tmp" --quiet >"$log" 2>&1 || status=$?

        if { [ "$expect" = "FAIL" ] && [ "$status" -eq 0 ]; } ||
           { [ "$expect" = "PASS" ] && [ "$status" -ne 0 ]; }; then
            printf '  FAIL %-26s expected the guard to %s, it exited %d\n' "$name" "$expect" "$status" >&2
            sed 's/^/         /' "$log" >&2
            bad_cases=$((bad_cases + 1))
        else
            printf '  ok   %-26s guard %s (exit %d)\n' "$name" "$expect" "$status"
        fi

        rm -rf "$tmp"
    done <<EOF
$SELF_TEST_CASES
EOF

    # Structural cases that mutate the tree rather than add a file.
    self_test_structural "missing-clock-exemption" "rm -f \"\$T/$CLOCK_EXEMPT_FILE\"" || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    self_test_structural "extra-read-in-exemption" "printf 'let extra = Date()\\n' >> \"\$T/$CLOCK_EXEMPT_FILE\"" || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    self_test_structural "constant-moved-out-of-canonical-file" \
        "sed -i.bak '/18\\.0156/d' \"\$T/$CANONICAL_FILE\" && rm -f \"\$T/$CANONICAL_FILE.bak\" && printf 'let factor = 18.0156\\n' > \"\$T/Sources/SafetyCore/Elsewhere.swift\"" \
        || bad_cases=$((bad_cases + 1))
    total=$((total + 1))

    printf '\n%d case(s), %d unexpected result(s)\n' "$total" "$bad_cases"
    [ "$bad_cases" -eq 0 ] || return 1
    printf 'safety_guards --self-test: every guard fails when it should\n'
    return 0
}

# self_test_structural <name> <mutation shell snippet using $T as the scratch root>
self_test_structural() {
    local name="$1" mutation="$2" tmp status log
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/safety_guards_selftest.XXXXXX")
    cp -R "$ROOT/Sources" "$tmp/Sources"
    T="$tmp" eval "$mutation"

    log="$tmp/guard.log"
    status=0
    bash "${BASH_SOURCE[0]}" --root "$tmp" --quiet >"$log" 2>&1 || status=$?

    if [ "$status" -eq 0 ]; then
        printf '  FAIL %-26s expected the guard to FAIL, it exited 0\n' "$name" >&2
        sed 's/^/         /' "$log" >&2
        rm -rf "$tmp"
        return 1
    fi
    printf '  ok   %-26s guard FAIL (exit %d)\n' "$name" "$status"
    rm -rf "$tmp"
    return 0
}

case "$MODE" in
    check) run_check ;;
    self-test) self_test ;;
esac
