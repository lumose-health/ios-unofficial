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
# ---------------------------------------------------------------------------
# WHAT THIS GUARD CATCHES, AND WHAT IT DOES NOT
#
# Stated exactly, because a guard whose reach is overstated is worse than one
# with no documentation: people stop looking where it cannot see.
#
# Constants — CAUGHT:
#   * any literal numerically EQUAL to a canonical constant, in ANY Swift literal
#     spelling: `18.0156`, `1.80156e1`, `2e1...5e2`, `0x14`, `1_199_145_600`,
#     `0b10100`. Literals are lexed and decoded to doubles and compared as
#     NUMBERS (lib/scan_numerics.awk), so spelling cannot hide a second
#     definition. This part is complete — there is no equal value that escapes.
#   * a DRIFTED near-copy that lands inside the band around a canonical value:
#     18.0 / 18.02 / 18.0182 for the factor, 19 / 21 / 499 / 501 for the bounds,
#     any 2001–2014 Unix-epoch-shaped number for the epoch. The bands are listed
#     below with the values.
#   * the inclusive spelling of the range: `20..<500` or `20..<501` fails, since
#     the exclusive form silently moves a safety bound by one.
#
# Constants — NOT CAUGHT (know this; do not assume the gate has your back here):
#   * drift that lands OUTSIDE the band — `let f = 15.0`, `let ceiling = 900`.
#     Band-widening trades this for false positives on unrelated code; the bands
#     are set where drift actually occurs (rounding and off-by-one), not where it
#     is theoretically possible.
#   * a value never written as a literal: `18.0 + 0.0156`, `factor * 2`, a value
#     read from a plist, a constant assembled at runtime. Only the first operand
#     of that example is visible to a literal scan (and it is in the band, so it
#     happens to fail — do not rely on that).
#   * a value that is only ever string TEXT. Every Swift string form — ordinary,
#     multi-line, and the raw variants with any number of `#`s — has its contents
#     elided, in every case, because naming a value is not defining one. What is
#     NOT elided is interpolation: `"\(x)"`, `#"\#(x)"#` and `##"\##(x)"##` are
#     executed code and are scanned as code (see the clock note below).
#   * a value inside an ADVERSARIALLY constructed interpolation. The interpolated
#     expression is scanned on a best-effort LEXICAL basis — its end is found by
#     counting parentheses in the raw text — so a `)` hidden inside a comment or a
#     nested string literal within the expression closes the scan early and elides
#     what follows. See "Known bypasses" below; this is not a hypothetical.
#
# Clock — CAUGHT: every forbidden spelling with arbitrary whitespace and line
# breaks around the call parentheses and member dots (`Date ()`, `Date .now`,
# `Date . init`), and reads inside ordinary string interpolation of any string
# form — `"\(Date())"`, `#"\#(Date())"#`, `##"\##(Date())"##`, and the multi-line
# equivalents.
#
# Clock — NOT CAUGHT:
#   * reaching the wall clock through a type this list does not name (`NSDate()`,
#     `DispatchTime.now()`, `mach_absolute_time()`) — extend CLOCK_FORBIDDEN when
#     such a call has a legitimate reason to appear;
#   * a read inside an adversarially constructed interpolation, per the known
#     bypasses below.
#
# ---------------------------------------------------------------------------
# KNOWN BYPASSES (documented, executable, expected to pass through)
#
# This scan is TEXT-BASED. It lexes Swift well enough to be useful and not well
# enough to be a compiler, and the gap is not evenly distributed: string
# delimiters are modelled exactly, while the inside of an interpolation is
# approximated by counting parentheses. Someone who knows that can walk past the
# gate on purpose. Both spellings below compile, run, and do the forbidden thing
# under `swift -swift-version 6`, and the guard exits 0 on each of them TODAY:
#
#     let stamp = "\({ /* ) */ Date() }())"              # `)` hidden in a comment
#     let a = "\(String(")").count + Date().hashValue)"  # `)` in a nested literal
#
# In both, the `)` inside the comment or nested literal is counted as the end of
# the interpolation, so `Date()` is elided as string text and never scanned.
#
# They are carried in --self-test as xfail cases
# (`known-bypass-interpolation-comment-paren`,
# `known-bypass-interpolation-nested-literal-paren`) rather than left in prose,
# because a limit nobody executes is a limit nobody notices going stale. If one
# starts being caught, --self-test says so loudly: that is good news, and it means
# these coverage statements now understate the guard and must be rewritten in the
# same change.
#
# What this does NOT mean: the guard is not defeated by ordinary code, or by
# ordinary mistakes, which is what it is for. Drift arrives as a copy-pasted
# constant or a convenient `Date()`, not as a paren smuggled through a block
# comment. Treat the bypasses as the honest edge of a text scan, and as the reason
# the deferred work below exists.
#
# ---------------------------------------------------------------------------
# DEFERRED-WORK — story 8-6 (swift-syntax static analysis)
#
# The awk lexer under lib/ is INTERIM. Closing the interpolation gap by hand means
# reimplementing Swift's lexer in awk, one adversarial probe at a time, and each
# round has bought less than the one before — cycle 3 hardened string delimiters
# and cycle 4's review walked straight past them through an interpolated
# expression. That is a signal about the approach, not about the effort.
#
# Story 8-6 replaces this with swift-syntax, which parses the language instead of
# approximating it: interpolations, comments and nested literals stop being
# special cases because the parser already knows what they are. When it lands,
# these rules port to it, the xfail cases become ordinary FAIL cases, and this
# section and the coverage statements above go away.
#
# Until then: do not harden the awk further in response to a new probe. Add the
# probe as a documented xfail and take it to 8-6.
# ---------------------------------------------------------------------------
#
# The scan is comment-stripped and string-literal aware (lib/strip_swift_comments.awk):
# a doc comment or a string of any form may name a value without tripping the
# guard, and no string DELIMITER can hide a real occurrence from it — the
# delimiter and its `#` count are tracked, so a string cannot end early (leaving
# the parser scanning text as code) or late (swallowing the code after it). The
# one place a real occurrence can still hide is inside an interpolated expression,
# per the known bypasses above.
#
# There is no per-line escape hatch, by design. A new legitimate occurrence of a
# guarded value means editing this script — deliberately, in the same PR, where a
# reviewer sees it — exactly as Android requires its SCAN_SITES inventory to be
# updated. A guard with a bypass comment stops being a guard the first time
# someone is in a hurry.
#
# Usage:  bash scripts/guards/safety_guards.sh                       run the gate
#         bash scripts/guards/safety_guards.sh --self-test           prove the gate can fail
#         bash scripts/guards/safety_guards.sh --self-test --explain ...and show WHY
#         bash scripts/guards/safety_guards.sh --root DIR            scan DIR/Sources
#                                                                    (used by --self-test)
#         bash scripts/guards/safety_guards.sh --quiet               report failures only
#
# `--explain` prints each self-test case's guard output. It exists because "the
# case failed" is weak evidence on its own: a case can fail for a reason that has
# nothing to do with what it is testing, and then the rule it was meant to prove
# is untested while the table says otherwise.
#
# Exit: 0 clean, 1 violation, 2 usage/environment error.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STRIPPER="$SCRIPT_DIR/lib/strip_swift_comments.awk"
COUNTER="$SCRIPT_DIR/lib/count_token.awk"
SCANNER="$SCRIPT_DIR/lib/scan_numerics.awk"
CLASSIFIER="$SCRIPT_DIR/lib/classify_numerics.awk"

ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
MODE="check"
QUIET=0
EXPLAIN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --self-test) MODE="self-test"; shift ;;
        --explain) EXPLAIN=1; shift ;;
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
#
# CANON_SPEC drives the numeric rules: `name:value:band low:band high`, records
# separated by `;`. A literal equal to the value is a definition (exactly one
# allowed, in the canonical file); a literal inside the band but not equal to the
# value is drift, and always fails.
#
# Band rationale:
#   factor 17.5–18.5   every rounded conversion factor in the wild (18, 18.02,
#                      18.0182) lands here; nothing else legitimately does.
#   bounds ±5%         the off-by-one and nudged-bound mistakes (19, 21, 499,
#                      501) without swallowing ordinary small integers.
#   epoch 1.0e9–1.4e9  any Unix timestamp between 2001 and 2014, which is the
#                      only reason a number of that magnitude would be typed out.
# ---------------------------------------------------------------------------
CANONICAL_FILE="Sources/SafetyCore/SafetyConstants.swift"
CLOCK_EXEMPT_FILE="Sources/SafetyCore/SystemClock.swift"

RANGE_LITERAL="20...500"   # the inclusive glucose bound, as written in Swift

CANON_SPEC="mg/dL per mmol/L factor:18.0156:17.5:18.5"
CANON_SPEC="$CANON_SPEC;glucose lower bound:20:19:21"
CANON_SPEC="$CANON_SPEC;glucose upper bound:500:475:525"
CANON_SPEC="$CANON_SPEC;Tandem epoch offset:1199145600:1000000000:1400000000"

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
# Comments and string contents out, Swift digit separators out (twice, because a
# single pass leaves `1_2_3` as `12_3`), whitespace around range operators out —
# so `20 ... 500` and `1_199_145_600` cannot spell a copy the scan misses.
normalize() {
    awk -f "$STRIPPER" "$1" \
        | sed -E 's/([0-9])_([0-9])/\1\2/g' \
        | sed -E 's/([0-9])_([0-9])/\1\2/g' \
        | sed -E 's/[[:space:]]*\.\.\.[[:space:]]*/.../g; s/[[:space:]]*\.\.<[[:space:]]*/..</g'
}

# The clock scan needs a different normalisation, because Swift lets whitespace —
# including newlines — sit between a callee and its parentheses and around member
# dots. `Date ()` and `Date .now` type-check and read the wall clock exactly like
# `Date()`; a guard that only knows one formatting of the call is decoration. So:
# join the file into a single stream, then collapse whitespace around dots, before
# call parentheses, and inside an empty argument list.
#
# Joining lines can in principle manufacture a match across a line boundary (a
# `Date` type annotation followed by a line starting with `(`). That direction is
# safe — the guard fails loudly and a human looks — and the construct does not
# occur in practice.
normalize_clock() {
    awk -f "$STRIPPER" "$1" \
        | tr '\n' ' ' \
        | sed -E 's/[[:space:]]*\.[[:space:]]*/./g; s/([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+\(/\1(/g; s/\([[:space:]]+\)/()/g'
    printf '\n'
}

swift_files() {
    [ -d "$1" ] || return 0
    find "$1" -type f -name '*.swift' | LC_ALL=C sort
}

count_in_file() { normalize "$1" | awk -v tok="$2" -v bounded="$3" -f "$COUNTER"; }
count_in_file_clock() { normalize_clock "$1" | awk -v tok="$2" -v bounded=0 -f "$COUNTER"; }

rel() { printf '%s' "${1#"$ROOT"/}"; }

# total_and_sites <dir> <token> <bounded> <counter fn> -> "<total>|<rel(path):n ...>"
#
# The site list is space-separated, so a source path containing a space would be
# mis-split by the callers. That direction is safe: a mis-split site matches
# neither the canonical path nor the clock exemption, so the guard fails loudly
# rather than passing something it did not really check.
total_and_sites() {
    local dir="$1" token="$2" bounded="$3" counter="$4" total=0 sites="" file n
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        n=$("$counter" "$file" "$token" "$bounded")
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
    result=$(total_and_sites "$SOURCES" "$token" "$bounded" count_in_file)
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

# Every numeric literal under Sources/, decoded to its value.
numeric_records() {
    local file
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        normalize "$file" | awk -v file="$(rel "$file")" -f "$SCANNER"
    done <<EOF
$(swift_files "$SOURCES")
EOF
}

# ---------------------------------------------------------------------------
# Preconditions. A guard that passes on a tree it never actually read is worse
# than no guard, because it reports green.
# ---------------------------------------------------------------------------
[ -f "$STRIPPER" ] || die "missing helper: $STRIPPER"
[ -f "$COUNTER" ] || die "missing helper: $COUNTER"
[ -f "$SCANNER" ] || die "missing helper: $SCANNER"
[ -f "$CLASSIFIER" ] || die "missing helper: $CLASSIFIER"

run_check() {
    [ -d "$SOURCES" ] || die "no Sources/ directory under $ROOT"
    [ -n "$(swift_files "$SOURCES")" ] || die "no Swift files under $SOURCES — nothing was scanned"
    [ -f "$ROOT/$CANONICAL_FILE" ] || die "missing canonical constants file: $CANONICAL_FILE"

    say "safety_guards: scanning $SOURCES"
    say ""

    # Scan integrity comes first: every count below is a count of the STRIPPED
    # source, so a file the stripper refuses has not been checked, and reporting
    # the rest as clean would be reporting a green gate over an unread file.
    # The stripper refuses exactly one thing — an unterminated multi-line string
    # literal, which would otherwise elide everything after it.
    local file msg unscannable=0 scanned=0
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        scanned=$((scanned + 1))
        if ! msg=$(awk -f "$STRIPPER" "$file" 2>&1 >/dev/null); then
            bad "$(rel "$file") could not be scanned — ${msg:-the comment/string stripper failed}"
            unscannable=1
        fi
    done <<EOF
$(swift_files "$SOURCES")
EOF
    if [ "$unscannable" -eq 1 ]; then
        printf 'safety_guards: %d violation(s) — nothing else was checked, because the counts would be meaningless\n' "$FAILURES" >&2
        return 1
    fi
    ok "all $scanned source file(s) parse"

    say ""
    say "AD-2/SI-4 — one definition site per safety constant (by VALUE, not spelling)"

    # The value rules: equality in any spelling, plus the drift bands.
    local verdict message
    while IFS='|' read -r verdict message; do
        case "$verdict" in
            V) bad "$message" ;;
            P) ok "$message" ;;
            "") ;;
            *) die "unexpected classifier output: $verdict|$message" ;;
        esac
    done <<EOF
$(numeric_records | awk -v spec="$CANON_SPEC" -v canonical_file="$CANONICAL_FILE" -f "$CLASSIFIER")
EOF

    # One thing the value rules cannot see: whether the bound is spelled
    # INCLUSIVELY. `20..<500` and `20..<501` decode to the same two canonical
    # literals as `20...500` while meaning something different — and an
    # exclusive-bound mistake is the classic way a safety bound drifts by one.
    # So the canonical range literal is also pinned textually.
    expect_count "$RANGE_LITERAL" 1 1 canonical "inclusive glucose bound spelling"

    say ""
    say "AD-14 — one clock; the wall clock is reachable only through SystemClock"

    # A stale exemption is a violation, not a broken environment: the guard would
    # keep reporting green while exempting a path nobody can see any more.
    local exemption_present=1
    if [ ! -f "$ROOT/$CLOCK_EXEMPT_FILE" ]; then
        exemption_present=0
        bad "the clock exemption names $CLOCK_EXEMPT_FILE, which does not exist — remove the exemption or restore the file; a stale exemption silently widens the guard"
    fi

    local scope="$SOURCES/SafetyCore" token result sites offenders site
    for token in $CLOCK_FORBIDDEN; do
        result=$(total_and_sites "$scope" "$token" 0 count_in_file_clock)
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
        exempt_reads=$(count_in_file_clock "$ROOT/$CLOCK_EXEMPT_FILE" "Date()" 0)
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
# the guard rejects it — plus controls that must still PASS, so the negative
# cases prove precision rather than a script that always fails.
#
# The `equivalent-*` and `drifted-*` cases are the false-negative class an
# adversarial review demonstrated against the previous textual guard: Swift
# spellings that are the same number, and near-misses that are not. The `clock-
# space-*` cases are the whitespace bypass from the same review. The `string-*`,
# `raw-string-*` and `multiline-*` cases pin both directions of string handling —
# mentioning a value is not defining it, but no string form may be used as cover
# for a real one, and the `#`-count controls pin the line between the two.
#
# A third kind of case runs at the end: xfail cases for the DOCUMENTED KNOWN
# BYPASSES in the header, which assert what the guard does not catch. A guard's
# stated limits are a claim like any other, and this is where that claim is
# checked instead of remembered.
#
# Every probe spelling below was compiled and run before being trusted; the ones
# that look like typos (`\#(…)` inside a `##"…"##` literal) are the point.
# ---------------------------------------------------------------------------
SELF_TEST_CASES="
control-clean|PASS|
dup-factor|FAIL|Sources/SafetyCore/GuardProbe.swift|let duplicateFactor = 18.0156
drifted-factor|FAIL|Sources/SafetyCore/GuardProbe.swift|let roundedFactor = 18.02
integer-factor|FAIL|Sources/SafetyCore/GuardProbe.swift|let crudeFactor = 18.0
dup-range|FAIL|Sources/SafetyCore/GuardProbe.swift|let duplicateRange = 20...500
spaced-range|FAIL|Sources/SafetyCore/GuardProbe.swift|let spacedRange = 20 ... 500
widened-range|FAIL|Sources/SafetyCore/GuardProbe.swift|let widenedRange = 20...5000
half-open-bound|FAIL|Sources/SafetyCore/GuardProbe.swift|let halfOpen = 20..<501
bare-lower-bound|FAIL|Sources/SafetyCore/GuardProbe.swift|let minGlucose = 20
bare-upper-bound|FAIL|Sources/SafetyCore/GuardProbe.swift|let maxGlucose = 500
off-by-one-bound|FAIL|Sources/SafetyCore/GuardProbe.swift|let ceiling = 501
dup-epoch-underscored|FAIL|Sources/SafetyCore/GuardProbe.swift|let epochCopy = 1_199_145_600
equivalent-factor-scientific|FAIL|Sources/SafetyCore/GuardProbe.swift|let factorCopy: Double = 1.80156e1
equivalent-range-scientific|FAIL|Sources/SafetyCore/GuardProbe.swift|let rangeCopy: ClosedRange<Double> = 2e1...5e2
equivalent-epoch-scientific|FAIL|Sources/SafetyCore/GuardProbe.swift|let epochCopy: TimeInterval = 1.1991456e9
equivalent-bound-hex|FAIL|Sources/SafetyCore/GuardProbe.swift|let lowCopy = 0x14
equivalent-bound-binary|FAIL|Sources/SafetyCore/GuardProbe.swift|let lowCopy = 0b10100
drifted-factor-hexfloat|FAIL|Sources/SafetyCore/GuardProbe.swift|let crudeFactor = 0x1.2p4
drifted-factor-scientific|FAIL|Sources/SafetyCore/GuardProbe.swift|let factorCopy = 1.802e1
drifted-range-scientific|FAIL|Sources/SafetyCore/GuardProbe.swift|let rangeCopy = 2.1e1...4.99e2
drifted-epoch-scientific|FAIL|Sources/SafetyCore/GuardProbe.swift|let epochCopy = 1.199145601e9
wall-clock-date|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = Date()
wall-clock-date-now|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = Date.now
wall-clock-date-init|FAIL|Sources/SafetyCore/GuardProbe.swift|let make = Date.init
clock-space-paren|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = Date ()
clock-space-dot-now|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = Date .now
clock-space-inside-parens|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = Date (  )
clock-space-dot-init|FAIL|Sources/SafetyCore/GuardProbe.swift|let make = Date . init
clock-in-string-interpolation|FAIL|Sources/SafetyCore/GuardProbe.swift|let note = \"stamped \\(Date())\"
constant-in-string-interpolation|FAIL|Sources/SafetyCore/GuardProbe.swift|let note = \"factor \\(18.0156)\"
wall-clock-in-string-tail|FAIL|Sources/SafetyCore/GuardProbe.swift|let u = \"https://x\"; let stamp = Date()
string-then-real-duplicate|FAIL|Sources/SafetyCore/GuardProbe.swift|let s = \"harmless\"; let dup = 18.0156
raw-string-interpolation-clock|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = #\"timestamp: \\#(Date())\"#
raw-string-multihash-interpolation-clock|FAIL|Sources/SafetyCore/GuardProbe.swift|let stamp = ##\"timestamp: \\##(Date())\"##
raw-string-interpolated-constant|FAIL|Sources/SafetyCore/GuardProbe.swift|let note = #\"factor \\#(18.0156)\"#
raw-string-then-real-duplicate|FAIL|Sources/SafetyCore/GuardProbe.swift|let q = #\"harmless \"quoted\" text\"#; let dup = 18.0156
raw-string-inner-shorter-delimiter|FAIL|Sources/SafetyCore/GuardProbe.swift|let q = ##\"a \"# b\"##; let dup = 18.0156
hash-directive-then-constant|FAIL|Sources/SafetyCore/GuardProbe.swift|let x = #line + 20
comments-only-control|PASS|Sources/SafetyCore/GuardProbe.swift|// 18.0156 and 20...500 and 1199145600 and Date() and Date.now
block-comment-control|PASS|Sources/SafetyCore/GuardProbe.swift|/* 18.0156 20...500 1199145600 Date() 18.02 501 */
string-contents-control|PASS|Sources/SafetyCore/GuardProbe.swift|let s = \"18.0156 20...500 1199145600 Date() Date.now 18.02 501\"
raw-string-contents-control|PASS|Sources/SafetyCore/GuardProbe.swift|let s = #\"18.0156 20...500 1199145600 Date() Date.now 18.02 501\"#
raw-string-fewer-hashes-control|PASS|Sources/SafetyCore/GuardProbe.swift|let inert = ##\"inert \\#(Date()) 18.0156\"##
identifier-digits-control|PASS|Sources/SafetyCore/GuardProbe.swift|let sha20 = value500 + hash1199145600
"

self_test_write() {
    # $1 target file, $2 line of Swift/comment
    printf 'import Foundation\n%s\n' "$2" > "$1"
}

self_test_scratch() {
    # A copy of Sources/ to mutate. Printed so the caller can populate it.
    local tmp
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/safety_guards_selftest.XXXXXX")
    cp -R "$ROOT/Sources" "$tmp/Sources"
    printf '%s' "$tmp"
}

# self_test_run <name> <expect PASS|FAIL> <scratch root>
#
# The single place a case's verdict is decided, so all three kinds of case
# (single line, multi line, structural mutation) are judged identically and
# `--explain` shows the same evidence for each. Removes the scratch tree.
self_test_run() {
    local name="$1" expect="$2" tmp="$3" status=0 log="$3/guard.log"

    bash "${BASH_SOURCE[0]}" --root "$tmp" --quiet >"$log" 2>&1 || status=$?

    if { [ "$expect" = "FAIL" ] && [ "$status" -eq 0 ]; } ||
       { [ "$expect" = "PASS" ] && [ "$status" -ne 0 ]; }; then
        printf '  FAIL %-42s expected the guard to %s, it exited %d\n' "$name" "$expect" "$status" >&2
        sed 's/^/         /' "$log" >&2
        rm -rf "$tmp"
        return 1
    fi
    printf '  ok   %-42s guard %s (exit %d)\n' "$name" "$expect" "$status"
    if [ "$EXPLAIN" -eq 1 ]; then sed 's/^/         | /' "$log"; fi
    rm -rf "$tmp"
    return 0
}

# self_test_multiline <name> <expect> <line>...
#
# For probes that need more than one line — the multi-line string literals, whose
# whole point is state that outlives a line. The lines are passed as arguments
# rather than embedded in SELF_TEST_CASES so that backslashes and quotes reach
# the file exactly as typed; a mangled probe would "pass" while testing nothing.
self_test_multiline() {
    local name="$1" expect="$2" tmp
    shift 2
    tmp=$(self_test_scratch)
    printf '%s\n' "import Foundation" "$@" > "$tmp/Sources/SafetyCore/GuardProbe.swift"
    self_test_run "$name" "$expect" "$tmp"
}

# ---------------------------------------------------------------------------
# Documented known bypasses (xfail). See the KNOWN BYPASSES section in the header.
#
# These assert what the guard does NOT do. They are here rather than in prose so
# the limit is executed on every self-test run: a documented limit that nobody
# runs drifts out of date silently, in whichever direction is least convenient.
#
# An xfail that starts being CAUGHT is reported as an unexpected result on
# purpose. It is good news, but it makes the coverage statements in this script
# and in lib/strip_swift_comments.awk overstate the guard's limits, and those have
# to be rewritten in the same change — a red self-test is what makes that happen
# rather than being meant to happen.
# ---------------------------------------------------------------------------

# self_test_known_bypass <name> <why> <line of Swift>
self_test_known_bypass() {
    local name="$1" why="$2" payload="$3" tmp status=0
    tmp=$(self_test_scratch)
    self_test_write "$tmp/Sources/SafetyCore/GuardProbe.swift" "$payload"

    bash "${BASH_SOURCE[0]}" --root "$tmp" --quiet >"$tmp/guard.log" 2>&1 || status=$?

    if [ "$status" -ne 0 ]; then
        printf '  XPASS %-41s known bypass is now CAUGHT (exit %d)\n' "$name" "$status" >&2
        printf '        This is an improvement, not a regression. Promote the case to a\n' >&2
        printf '        FAIL case and rewrite the coverage statements in this script and\n' >&2
        printf '        in lib/strip_swift_comments.awk, which still claim it escapes.\n' >&2
        sed 's/^/         /' "$tmp/guard.log" >&2
        rm -rf "$tmp"
        return 1
    fi
    printf '  xfail %-41s not caught, as documented — %s\n' "$name" "$why"
    if [ "$EXPLAIN" -eq 1 ]; then sed 's/^/         | /' "$tmp/guard.log"; fi
    rm -rf "$tmp"
    return 0
}

# self_test_structural <name> <expect> <mutation shell snippet using $T as the scratch root>
self_test_structural() {
    local name="$1" expect="$2" mutation="$3" tmp
    tmp=$(self_test_scratch)
    T="$tmp" eval "$mutation"
    self_test_run "$name" "$expect" "$tmp"
}

self_test() {
    local total=0 bad_cases=0 bypasses=0 line name expect path payload tmp

    printf 'safety_guards --self-test: proving each guard can fail\n\n'

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        name="${line%%|*}"; line="${line#*|}"
        expect="${line%%|*}"; line="${line#*|}"
        path="${line%%|*}"
        payload="${line#*|}"
        [ "$path" = "$payload" ] && payload=""

        total=$((total + 1))
        tmp=$(self_test_scratch)

        case "$name" in
            control-clean) ;;
            *) self_test_write "$tmp/$path" "$payload" ;;
        esac

        self_test_run "$name" "$expect" "$tmp" || bad_cases=$((bad_cases + 1))
    done <<EOF
$SELF_TEST_CASES
EOF

    # Multi-line string literals: the contents are text like any other string,
    # but the interpolation inside them is executed code, and the code AFTER the
    # closing delimiter is code — both on the same line as the delimiter and
    # after it. Each of those is one way a wall-clock read or a duplicate
    # constant could sit in plain sight while the gate reported green.
    self_test_multiline "multiline-interpolation-clock" FAIL \
        'let ml = """' 'stamp \(Date())' '"""' || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    self_test_multiline "multiline-raw-interpolation-clock" FAIL \
        'let ml = #"""' 'stamp \#(Date())' '"""#' || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    self_test_multiline "multiline-close-then-duplicate" FAIL \
        'let n = """' 'text' '""".count + Int(18.0156)' || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    self_test_multiline "multiline-contents-control" PASS \
        'let ml = """' '18.0156 20...500 1199145600 Date() Date.now 18.02 501' '"""' \
        || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    # An unterminated multi-line literal is the one input that could make the
    # stripper elide a file's whole tail. It must be refused, not scanned.
    self_test_multiline "unterminated-multiline-string" FAIL \
        'let ml = """' 'text' || bad_cases=$((bad_cases + 1))
    total=$((total + 1))

    # Structural cases that mutate the tree rather than add a file.
    self_test_structural "missing-clock-exemption" FAIL "rm -f \"\$T/$CLOCK_EXEMPT_FILE\"" || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    self_test_structural "extra-read-in-exemption" FAIL "printf 'let extra = Date()\\n' >> \"\$T/$CLOCK_EXEMPT_FILE\"" || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    self_test_structural "spaced-read-in-exemption" FAIL "printf 'let extra = Date ()\\n' >> \"\$T/$CLOCK_EXEMPT_FILE\"" || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    # The one thing the value rules cannot see: the canonical range re-spelled
    # exclusively. It decodes to the same two literals, in the same file, so only
    # the textual spelling check can catch it.
    self_test_structural "exclusive-bound-spelling" FAIL \
        "sed -i.bak 's/20\\.\\.\\.500/20..<500/' \"\$T/$CANONICAL_FILE\" && rm -f \"\$T/$CANONICAL_FILE.bak\"" \
        || bad_cases=$((bad_cases + 1))
    total=$((total + 1))
    self_test_structural "constant-moved-out-of-canonical-file" FAIL \
        "sed -i.bak '/18\\.0156/d' \"\$T/$CANONICAL_FILE\" && rm -f \"\$T/$CANONICAL_FILE.bak\" && printf 'let factor = 18.0156\\n' > \"\$T/Sources/SafetyCore/Elsewhere.swift\"" \
        || bad_cases=$((bad_cases + 1))
    total=$((total + 1))

    # The documented limits, executed. Kept last and counted separately: they
    # assert what the guard does NOT catch, so folding them into the case total
    # would inflate the number that means "ways this guard was proven to fail".
    printf '\n  known bypasses — text-scan limits, deferred to story 8-6 (swift-syntax)\n'
    self_test_known_bypass "known-bypass-interpolation-comment-paren" \
        "a \`)\` inside a comment ends the interpolation scan early" \
        'let stamp = "\({ /* ) */ Date() }())"' || bad_cases=$((bad_cases + 1))
    bypasses=$((bypasses + 1))
    self_test_known_bypass "known-bypass-interpolation-nested-literal-paren" \
        "so does a \`)\` inside a nested string literal" \
        'let a = "\(String(")").count + Date().hashValue)"' || bad_cases=$((bad_cases + 1))
    bypasses=$((bypasses + 1))

    printf '\n%d case(s), %d documented known bypass(es), %d unexpected result(s)\n' \
        "$total" "$bypasses" "$bad_cases"
    [ "$bad_cases" -eq 0 ] || return 1
    printf 'safety_guards --self-test: every guard fails when it should, and every\n'
    printf 'documented bypass still bypasses\n'
    return 0
}

case "$MODE" in
    check) run_check ;;
    self-test) self_test ;;
esac
