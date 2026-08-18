#!/usr/bin/env bash
#
# Driver guards — the mechanical half of story 1.4 (AC 9).
#
# Four invariants that review cannot be trusted to hold over five Driver
# implementations and everything that follows them:
#
#   FR-22        CATALOG COMPLETENESS. Every Driver target under
#                Sources/Drivers/ is a MEMBER of DriverCatalog.entries, and every
#                entry names a target that is really built. A Driver that ships
#                without an entry is a Driver the user cannot see listed; an entry
#                without a target is a Driver the user is told they have and does
#                not. "Registered" means membership in the array, resolved by
#                lib/catalog_entries.awk — not a `targetName:` line somewhere in
#                the file, which a descriptor nothing references also has.
#
#   AD-12 / SI-1 SYMBOL SCAN. No delivery verb and no pump-write characteristic
#                identifier appears in DriverAPI or in any Drivers/* target.
#                There is no therapeutic write to call, and this is the check
#                that says so about code rather than about intent.
#
#   AD-16        PLATFORM SPI. No file under Sources/Drivers/ imports DriverAPI's
#                `DriverPlatform` SPI. `DriverLifecycle` — the only type that can
#                move a Driver between states — is SPI, so an ordinary
#                `import DriverAPI` cannot see it and a self-transitioning Driver
#                does not compile. The one way around that is to write the SPI
#                import into a Driver, and this rule is what refuses it.
#
#   AD-12        CONSUMER CASTS. Outside Sources/DriverAPI/, nothing narrows a
#                Capability port, the `Driver` protocol, `CapabilityPort`, or any
#                type a Driver target declares, with `as?`, `as!` or `is`. Cast
#                SYNTAX is what this matches, and only that — see THE RESIDUAL
#                below. The reasoning is in lib/consumer_casts.awk and in
#                "THE SEAM THIS CLOSES" below.
#
# This is the LOCAL truth today. FR-21's iOS Gate runs the same rules in CI when
# the CI work lands; until then, running this before a push is the enforcement.
#
# ---------------------------------------------------------------------------
# HOW THE SYMBOL SCAN MATCHES, AND WHY IT IS NOT A PLAIN WORD SEARCH
#
# A plain `\bdeliver\b` over Swift source is close to useless: nobody writes a
# bare `deliver`, they write `deliverBolus()`. Swift's own convention hides every
# denied word inside a camelCase identifier, where a word-boundary search cannot
# see it.
#
# So identifiers are SPLIT into words first — on camel humps and on every
# non-alphanumeric character — and the deny-list is matched against the resulting
# word sequence, case-insensitively:
#
#     deliverBolus()    -> deliver bolus     matches `deliver`, matches `bolus`
#     setBasalRate()    -> set basal rate    matches the pair `set basal`
#     temp_basal        -> temp basal        matches the pair `temp basal`
#     basalRate         -> basal rate        matches nothing — a basal READ is legal
#     settings          -> settings          matches nothing — `set` is a word, not a prefix
#     primaryDevice     -> primary device    matches nothing — `prime` is a word, not a prefix
#     insulinDelivered  -> insulin delivered matches nothing — `deliver` is a word,
#                                            and reading a COMPLETED dose is SI-7's
#                                            whole subject
#
# Multi-word terms (`set basal`, `write value`) match as an ADJACENT sequence, so
# they catch `setBasalRate` and `set_basal` without flagging every `set` and every
# `basal` in the codebase.
#
# ---------------------------------------------------------------------------
# THE ONE NAMING COLLISION, AND HOW IT WAS RESOLVED
#
# `bolus` is a denied word, and the closed Capability set contains a legitimate
# READ-side capability that Android calls `BolusCategoryProvider`: it maps a
# device's own dose-category labels onto the platform's. Under the matching above,
# `BolusCategoryProvider` splits to `bolus category provider` and trips.
#
# Two ways out, and only one of them is safe:
#
#   * an exemption list of legal identifiers — rejected. An exemption list is a
#     place a write surface can be added later by appending a line, and it is
#     read by whoever is in a hurry, which is exactly who this guard is for.
#   * name the read surface so it does not contain a denied word — taken. The
#     capability is `DoseCategoryProvider` and its Capability case is
#     `doseCategoryProvider`. A category describes a dose that already happened,
#     so the word is accurate on its own terms, and the parity with Android is
#     recorded in the doc comments instead of in the identifier.
#
# The result is that this guard has NO per-symbol escape hatch, the same posture
# safety_guards.sh takes about per-line ones. A new legitimate occurrence of a
# denied word means editing the deny-list in this file, deliberately, in the same
# PR, where a reviewer sees it.
#
# ---------------------------------------------------------------------------
# THE SEAM THIS CLOSES, AND THE ONE IT DOES NOT
#
# `Driver/capability(_:)` hands back a `CapabilityPort` — a six-case enum, so
# there is no seventh case to put anything in. The payloads are `any` existentials
# of the six port protocols, and an existential is DOWNCASTABLE. So a Driver can
# conform its own concrete type to a port, hand it over as one of the six, and a
# consumer can cast the existential back to the concrete type and call members
# `DriverAPI` never declared:
#
#     guard case .doseCategoryProvider(let port) = driver.capability(.doseCategoryProvider),
#           let smuggled = port as? ExtraTherapyPort else { return }
#     smuggled.enactTherapy()
#
# Swift has no sealed conformances and no way to make an existential
# non-downcastable, so the type system cannot close this. Two things narrow it to
# a shape a text scan can hold:
#
#   * rule D forbids the CONSUMER side. The downcast is the only way to reach the
#     smuggled surface at all — the platform holding `any DoseCategoryProvider`
#     can call nothing but what that protocol declares — and it is a text shape
#     outside DriverAPI. Everything under Sources/ except Sources/DriverAPI/ is
#     scanned for `as?`, `as!` and `is` against a Capability port name, `Driver`,
#     `CapabilityPort`, or any type declared in a Driver target. The name lists
#     are READ from the tree (lib/declared_types.awk), not typed here, so a
#     renamed port or a new Driver type is covered without an edit.
#   * the deny-list below covers the therapeutic vocabulary such a member would
#     be written in — `therapy`, `enact`, `administer`, `infuse`, `inject`
#     alongside the delivery verbs — in the Driver target itself, where the
#     smuggled type has to be declared.
#
# THE RESIDUAL, exactly. Three things escape; the first two compose:
#
#   * a member with an arbitrary name — `func performStepTwo()` — on a concrete
#     Driver port type is invisible to a text scan. There is no vocabulary to
#     match and no shape that distinguishes it from an ordinary helper.
#   * rule D's name list holds the types a Driver DECLARES. A Driver that
#     retroactively conforms a type it does not declare — `extension Data:
#     DoseCategoryProvider` — adds no name to that list, so a consumer's
#     `port as? Data` is not matched. Deliberate: reading `extension` as a
#     declaration would put every extended standard-library type on the
#     forbidden list and fail an ordinary `as? Data` in unrelated code, which
#     is the noise that gets a guard switched off. The reasoning is in
#     lib/declared_types.awk.
#   * rule D matches cast SYNTAX. It reads `as?`, `as!` and `is` written out
#     against a name it knows, and that is all it reads. The same narrowing
#     performed INDIRECTLY is not written that way and is not matched:
#
#         func narrow<T>(_ value: Any, to type: T.Type) -> T? { value as? T }
#         guard let smuggled = narrow(port, to: ExtraPort.self) else { return }
#
#     the cast is spelled against `T`, which is not a name any list can contain.
#     Reflection, `unsafeBitCast`, and any helper that takes or returns `Any` are
#     the same move in different words. A text scan cannot close this class:
#     matching it means resolving what `T` is bound to at each call site, which
#     means type-checking the program.
#
# So the bound this section used to state — that an arbitrary member is
# unreachable from another target without a downcast rule D forbids — does NOT
# hold against a consumer that means to reach it. What holds is narrower, and is
# worth saying plainly rather than restating the stronger claim:
#
#   * DriverAPI still declares no write member, so nothing reached this way is
#     part of the contract; it is one Driver's own surface, reached by one
#     consumer that went looking for it.
#   * the smuggled member has to be DECLARED in a Driver target, where the symbol
#     scan reads its vocabulary. Only an arbitrary NAME escapes that.
#   * reaching it takes a laundering helper written for the purpose. That is a
#     line in a diff.
#
# Which makes PR REVIEW of consumer targets the backstop here, and it is a human
# one — this guard does not carry that weight and should not be read as if it
# did. The closure point is the DEFERRED-WORK below.
#
# All three limits are EXECUTABLE rather than merely written down: --self-test
# carries `known-limit-arbitrary-member-on-a-driver-type`,
# `known-limit-retroactive-conformance-smuggle` and
# `known-limit-generic-cast-laundering` as expected-UNCAUGHT cases, counted
# separately from the cases that prove the guard fails. The day one starts
# being caught, the self-test says so instead of this claim quietly drifting.
#
# ---------------------------------------------------------------------------
# DEFERRED-WORK — story 8-6 (swift-syntax static analysis)
#
# The laundering gap above is not a hole more awk fills. Rule D reads a token
# stream, and each hardening round on it has bought less than the one before —
# cycle 3 taught it line-wrapped casts and `any`/`some` spellings, and cycle 3's
# re-review walked straight past all of it through a generic helper. That is a
# signal about the approach, not about the effort.
#
# Story 8-6 replaces the awk under lib/ with swift-syntax, which parses the
# language instead of approximating it. A parse tree is not a type checker, and
# closing this class fully means resolving what `T` binds to at each call site —
# but a parser is where that becomes possible at all, and where these rules
# should be reconsidered as a whole rather than patched once more.
#
# Until then: do not harden the awk further in response to a new probe. Add the
# probe as a documented expected-uncaught case and take it to 8-6.
# ---------------------------------------------------------------------------
#
# ---------------------------------------------------------------------------
# WHAT THIS GUARD DOES NOT CATCH
#
# Stated exactly, because a guard whose reach is overstated is worse than one with
# no documentation:
#
#   * a write reached through a name the deny-list does not contain. The list is
#     seeded with the vocabulary these pumps actually use; a Driver that spelled
#     its write `func doTheThing()` walks past. What stops that one is the
#     contract — DriverAPI declares no write member, so there is nothing for a
#     consumer to call — and review. This scan is the backstop, not the wall.
#   * an extra member on a concrete Driver port type, per THE RESIDUAL above.
#   * a cast that is not written as one. A generic narrowing helper, reflection,
#     `unsafeBitCast`, or any `Any`-typed indirection performs the downcast
#     without the syntax rule D matches, per THE RESIDUAL above.
#   * a denied word assembled at runtime, or read from a resource file.
#   * anything in a comment or a string. Contents are elided by
#     lib/strip_swift_comments.awk, deliberately: naming a delivery verb in prose
#     is not declaring one, and the doc comments in DriverAPI that EXPLAIN why
#     there is no bolus command would otherwise fail the build that ships them.
#   * the interpolation gap documented in safety_guards.sh, which shares the same
#     stripper. Story 8-6 (swift-syntax) closes it for both.
#
# KNOWN FUTURE FRICTION, recorded now so it is not a surprise: `suspend` and
# `resume` are denied words, and a Driver bridging Core Bluetooth delegate
# callbacks into async/await will want to call `continuation.resume(...)`. That
# will trip this guard, and it should — a reviewer should look at it once and
# decide, in the PR that introduces it, whether to narrow the term to its
# therapeutic shapes (`resume delivery`, `resume basal`) or to restructure the
# bridge. What must not happen is a silent exemption.
#
# ---------------------------------------------------------------------------
# Usage:  bash scripts/guards/driver_guards.sh                    run the gate
#         bash scripts/guards/driver_guards.sh --self-test        prove it can fail
#         bash scripts/guards/driver_guards.sh --self-test --explain  ...and show WHY
#         bash scripts/guards/driver_guards.sh --root DIR         scan DIR instead
#                                                                 (used by --self-test)
#         bash scripts/guards/driver_guards.sh --quiet            report failures only
#
# Exit: 0 clean, 1 violation, 2 usage/environment error.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STRIPPER="$SCRIPT_DIR/lib/strip_swift_comments.awk"
MANIFEST_TARGETS="$SCRIPT_DIR/lib/manifest_driver_targets.awk"
CATALOG_ENTRIES="$SCRIPT_DIR/lib/catalog_entries.awk"
DECLARED_TYPES="$SCRIPT_DIR/lib/declared_types.awk"
CONSUMER_CASTS="$SCRIPT_DIR/lib/consumer_casts.awk"

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

MANIFEST="Package.swift"
CATALOG_FILE="Sources/DriverAPI/DriverCatalog.swift"
DRIVERS_DIR="Sources/Drivers"
SOURCES_DIR="Sources"
API_DIR="Sources/DriverAPI"
CAPABILITIES_DIR="Sources/DriverAPI/Capabilities"
# The names a consumer must not cast to, beyond the six ports and the Driver
# targets' own types, which are read from the tree. `Driver` and `CapabilityPort`
# are here because narrowing either of them is the same move one step earlier:
# `driver as? TandemDriver` reaches the concrete Driver, and a switch over
# `CapabilityPort` is how the platform is supposed to read a port.
FIXED_CAST_TARGETS="Driver CapabilityPort"
# The two trees a Driver's code can live in. DriverAPI is included because the
# contract is where a write member would do the most damage: one there is
# inherited by every Driver at once.
SCAN_DIRS="Sources/DriverAPI Sources/Drivers"

# ---------------------------------------------------------------------------
# The deny-list: `words|why`, records separated by `;`.
#
# `words` is already SPLIT — lowercase, space separated — because that is the form
# the scan compares against. A multi-word entry matches those words adjacent and
# in order.
#
# The eight seeded by the story's AC are the vocabulary these pumps use for
# delivery. The four `… characteristic` / `write value` entries are the
# Core Bluetooth side of the same act: a Driver that never says "bolus" but calls
# `writeValue(_:for:type:)` on a pump's command characteristic has written to a
# pump.
#
# The last five are the vocabulary of the DOWNCAST seam (see THE SEAM THIS CLOSES
# above): a member smuggled onto a concrete port type is written in the language
# of doing something to a patient — `enactTherapy`, `administerCorrection`,
# `infuseUnits` — none of which contains a word the delivery list had. Checked
# against the legal read surface before adding: `DoseCategoryProvider` splits to
# `dose category provider`, and the words below appear in this target only inside
# comments, which are elided. `injected` and `therapeutic` are NOT `inject` and
# `therapy` — the scan matches words, and both have self-test controls.
# ---------------------------------------------------------------------------
DENY_SPEC="bolus|a dose command hides behind this noun"
DENY_SPEC="$DENY_SPEC;deliver|the delivery verb itself"
DENY_SPEC="$DENY_SPEC;set basal|writes the basal rate"
DENY_SPEC="$DENY_SPEC;temp basal|writes a temporary basal rate"
DENY_SPEC="$DENY_SPEC;suspend|stops delivery — a pump command"
DENY_SPEC="$DENY_SPEC;resume|restarts delivery — a pump command"
DENY_SPEC="$DENY_SPEC;prime|primes the tubing — a pump command"
DENY_SPEC="$DENY_SPEC;cannula|fills the cannula — a pump command"
DENY_SPEC="$DENY_SPEC;write value|the Core Bluetooth write call"
DENY_SPEC="$DENY_SPEC;write characteristic|a pump-write characteristic"
DENY_SPEC="$DENY_SPEC;command characteristic|a pump-write characteristic"
DENY_SPEC="$DENY_SPEC;control characteristic|a pump-write characteristic"
DENY_SPEC="$DENY_SPEC;therapy|what a smuggled write calls itself"
DENY_SPEC="$DENY_SPEC;enact|the verb a smuggled write is written in"
DENY_SPEC="$DENY_SPEC;administer|giving a dose to a patient"
DENY_SPEC="$DENY_SPEC;infuse|putting insulin into a patient"
DENY_SPEC="$DENY_SPEC;inject|putting insulin into a patient"

FAILURES=0

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok() { say "  ok   $*"; }
bad() { printf '  FAIL %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
die() { printf 'driver_guards: %s\n' "$*" >&2; exit 2; }

rel() { printf '%s' "${1#"$ROOT"/}"; }

swift_files() {
    [ -d "$1" ] || return 0
    find "$1" -type f -name '*.swift' | LC_ALL=C sort
}

# --- normalisation ---------------------------------------------------------
# Comments out, string contents out, identifiers split into words, everything
# lowercased, every non-alphanumeric run collapsed to a single space, and each
# line padded with a leading and trailing space so a whole-word match is a plain
# substring search for " word ".
#
# The two camel rules are separate because they do different jobs: the first
# splits `deliverBolus` at a lower-to-upper hump, the second splits `BGMSource`
# and `setUUIDValue` where a run of capitals meets a capitalised word. Without
# the second, an acronym swallows the word after it.
#
# The stripper emits one line per input line, and nothing below joins lines, so
# reported line numbers are the file's own.
normalize_symbols() {
    awk -f "$STRIPPER" "$1" \
        | sed -E 's/([a-z0-9])([A-Z])/\1 \2/g' \
        | sed -E 's/([A-Z]+)([A-Z][a-z])/\1 \2/g' \
        | tr 'A-Z' 'a-z' \
        | sed -E 's/[^a-z0-9]+/ /g; s/^/ /; s/$/ /'
}

# ---------------------------------------------------------------------------
# Preconditions. A guard that passes on a tree it never read is worse than no
# guard, because it reports green.
# ---------------------------------------------------------------------------
[ -f "$STRIPPER" ] || die "missing helper: $STRIPPER"
[ -f "$MANIFEST_TARGETS" ] || die "missing helper: $MANIFEST_TARGETS"
[ -f "$CATALOG_ENTRIES" ] || die "missing helper: $CATALOG_ENTRIES"
[ -f "$DECLARED_TYPES" ] || die "missing helper: $DECLARED_TYPES"
[ -f "$CONSUMER_CASTS" ] || die "missing helper: $CONSUMER_CASTS"

# --- rule A: catalog completeness ------------------------------------------

manifest_driver_targets() {
    awk -f "$STRIPPER" "$ROOT/$MANIFEST" \
        | awk -f "$MANIFEST_TARGETS" - "$ROOT/$MANIFEST"
}

catalog_registered_targets() {
    awk -f "$STRIPPER" "$ROOT/$CATALOG_FILE" \
        | awk -f "$CATALOG_ENTRIES" - "$ROOT/$CATALOG_FILE"
}

check_catalog_completeness() {
    say "FR-22 — every Driver target is in the catalog, and every entry is a real target"

    local targets entries name path target_name entry_name entry_line found directory

    targets=$(manifest_driver_targets) || die "could not read $MANIFEST — the completeness rules did not run"
    entries=$(catalog_registered_targets) || die "could not read $CATALOG_FILE — the completeness rules did not run"

    # A1 — a Driver target with no catalog entry. The failure the AC names: a
    # Driver ships and the Drivers screen does not list it.
    local unlisted=0
    while IFS='|' read -r name path; do
        [ -n "$name$path" ] || continue
        if [ -z "$name" ]; then
            bad "a target at $path declares no readable name in $MANIFEST — the catalog cannot be matched against it"
            unlisted=1
            continue
        fi
        found=0
        while IFS='|' read -r entry_name entry_line; do
            [ -n "$entry_name" ] || continue
            [ "$entry_name" = "$name" ] && found=1
        done <<EOF
$entries
EOF
        if [ "$found" -eq 0 ]; then
            bad "Driver target \`$name\` ($path) has no entry in $CATALOG_FILE — every shipped Driver is listed explicitly (FR-22)"
            unlisted=1
        fi
    done <<EOF
$targets
EOF
    [ "$unlisted" -eq 1 ] || ok "every Driver target under $DRIVERS_DIR/ has a catalog entry"

    # A2 — a catalog entry naming a target that is not built. The user is told
    # they have a Driver they do not have.
    local stale=0
    while IFS='|' read -r entry_name entry_line; do
        [ -n "$entry_name$entry_line" ] || continue
        if [ -z "$entry_name" ]; then
            bad "$CATALOG_FILE:$entry_line registers an entry whose targetName could not be read"
            stale=1
            continue
        fi
        found=0
        while IFS='|' read -r name path; do
            [ -n "$name" ] || continue
            [ "$name" = "$entry_name" ] && found=1
        done <<EOF
$targets
EOF
        if [ "$found" -eq 0 ]; then
            bad "catalog entry \`$entry_name\` ($CATALOG_FILE:$entry_line) names no target under $DRIVERS_DIR/ in $MANIFEST"
            stale=1
        fi
    done <<EOF
$entries
EOF
    [ "$stale" -eq 1 ] || ok "every catalog entry names a Driver target the manifest declares"

    # A3 — a Driver directory nobody builds. Not in the AC, but it is the third
    # way the three lists can disagree, and it costs one loop: code under
    # Sources/Drivers/ that no target declares is compiled by nothing, tested by
    # nothing, and listed nowhere, while looking exactly like a shipped Driver.
    local orphan=0
    if [ -d "$ROOT/$DRIVERS_DIR" ]; then
        while IFS= read -r directory; do
            [ -n "$directory" ] || continue
            name=$(basename "$directory")
            found=0
            while IFS='|' read -r target_name path; do
                [ -n "$path" ] || continue
                [ "$path" = "$DRIVERS_DIR/$name" ] && found=1
            done <<EOF
$targets
EOF
            if [ "$found" -eq 0 ]; then
                bad "$DRIVERS_DIR/$name is not declared as a target in $MANIFEST — it is built by nothing"
                orphan=1
            fi
        done <<EOF
$(find "$ROOT/$DRIVERS_DIR" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
EOF
    fi
    [ "$orphan" -eq 1 ] || ok "every directory under $DRIVERS_DIR/ is a declared target"
}

# --- rule B: symbol scan ---------------------------------------------------

check_symbols() {
    say ""
    say "AD-12/SI-1 — no delivery verb or pump-write identifier in the Driver surface"

    local scanned=0 unscannable=0 file directory term why hits offenders message

    # Scan integrity first: a file the stripper refuses has not been checked, and
    # reporting the rest as clean would report a green gate over an unread file.
    # The flag is local rather than a read of FAILURES, which may already carry a
    # catalog violation — attributing that to an unreadable file would send whoever
    # sees it looking in the wrong place.
    for directory in $SCAN_DIRS; do
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            scanned=$((scanned + 1))
            if ! message=$(awk -f "$STRIPPER" "$file" 2>&1 >/dev/null); then
                bad "$(rel "$file") could not be scanned — ${message:-the comment/string stripper failed}"
                unscannable=1
            fi
        done <<EOF
$(swift_files "$ROOT/$directory")
EOF
    done
    if [ "$unscannable" -eq 1 ]; then
        printf 'driver_guards: a source file could not be scanned — the symbol rules did not run\n' >&2
        return 1
    fi
    [ "$scanned" -gt 0 ] || die "no Swift files under ${SCAN_DIRS// /, } — nothing was scanned"
    ok "all $scanned source file(s) parse"

    while IFS='|' read -r term why; do
        [ -n "$term" ] || continue
        offenders=""
        for directory in $SCAN_DIRS; do
            while IFS= read -r file; do
                [ -n "$file" ] || continue
                hits=$(normalize_symbols "$file" | grep -n -F " $term " | cut -d: -f1 | tr '\n' ',' || true)
                [ -n "$hits" ] && offenders="$offenders $(rel "$file"):${hits%,}"
            done <<EOF
$(swift_files "$ROOT/$directory")
EOF
        done
        if [ -n "$offenders" ]; then
            bad "\`$term\` — $why:${offenders}"
        else
            ok "no \`$term\`"
        fi
    done <<EOF
$(printf '%s' "$DENY_SPEC" | tr ';' '\n')
EOF
}

# --- rule C: the platform SPI stays with the platform ----------------------

check_platform_spi() {
    say ""
    say "AD-16 — no Driver target imports the platform SPI"

    local file hits offenders=""

    while IFS= read -r file; do
        [ -n "$file" ] || continue
        hits=$(awk -f "$STRIPPER" "$file" | grep -n -F '@_spi' | cut -d: -f1 | tr '\n' ',' || true)
        [ -n "$hits" ] && offenders="$offenders $(rel "$file"):${hits%,}"
    done <<EOF
$(swift_files "$ROOT/$DRIVERS_DIR")
EOF

    if [ -n "$offenders" ]; then
        bad "an SPI import in a Driver target — DriverLifecycle belongs to the platform (AD-16):${offenders}"
    else
        ok "no Driver target reaches for the platform SPI"
    fi
}

# --- rule D: no consumer narrows a port back to a concrete type -------------

# `keyword|Name` for every type declared under <dir>.
declared_types_under() {
    local file
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        awk -f "$STRIPPER" "$file" | awk -f "$DECLARED_TYPES" -
    done <<EOF
$(swift_files "$ROOT/$1")
EOF
}

# Every Swift file under Sources/ that is NOT part of the contract itself.
# DriverAPI is excluded on purpose: it is where the six ports and CapabilityPort
# are DECLARED, and a rule that fired there would be a rule against declaring
# them. Everything else — Driver targets today, DomainCore and the UI later — is
# a consumer.
consumer_files() {
    [ -d "$ROOT/$SOURCES_DIR" ] || return 0
    local file
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        case "$file" in
            "$ROOT/$API_DIR"/*) continue ;;
        esac
        printf '%s\n' "$file"
    done <<EOF
$(find "$ROOT/$SOURCES_DIR" -type f -name '*.swift' | LC_ALL=C sort)
EOF
}

check_consumer_casts() {
    say ""
    say "AD-12 — no consumer narrows a Capability port or a Driver type with a cast"

    local ports port_count related file hits line operator target clean=1

    ports=$(declared_types_under "$CAPABILITIES_DIR" | grep '^protocol|' | cut -d'|' -f2 | LC_ALL=C sort -u) \
        || die "could not read the Capability ports under $CAPABILITIES_DIR — the cast rule did not run"
    port_count=$(printf '%s\n' "$ports" | grep -c '[^[:space:]]' || true)
    # The closed set is six (FR-30). Reading a different number means the scan is
    # not looking at the port set it thinks it is, and a cast rule built on a
    # name list that silently went short is a rule that reports green.
    [ "$port_count" -eq 6 ] \
        || die "read $port_count Capability port protocol(s) under $CAPABILITIES_DIR, expected 6 — the cast rule did not run against the real set"

    related=$(
        {
            printf '%s\n' "$ports"
            printf '%s\n' $FIXED_CAST_TARGETS
            declared_types_under "$DRIVERS_DIR" | cut -d'|' -f2
        } | grep '[^[:space:]]' | LC_ALL=C sort -u | tr '\n' ' '
    ) || die "could not build the cast-target name list — the cast rule did not run"

    while IFS= read -r file; do
        [ -n "$file" ] || continue
        if ! hits=$(awk -f "$STRIPPER" "$file" | awk -v names="$related" -f "$CONSUMER_CASTS" - 2>&1); then
            bad "$(rel "$file") could not be scanned for casts — ${hits:-the scan failed}"
            clean=0
            continue
        fi
        while IFS='|' read -r line operator target; do
            [ -n "$target" ] || continue
            bad "$(rel "$file"):$line — \`$operator $target\` narrows a Capability port or a Driver type back to something DriverAPI never declared (AD-12)"
            clean=0
        done <<EOF
$hits
EOF
    done <<EOF
$(consumer_files)
EOF

    [ "$clean" -eq 1 ] && ok "no consumer casts against the closed set"
    return 0
}

run_check() {
    [ -f "$ROOT/$MANIFEST" ] || die "no $MANIFEST under $ROOT"
    [ -f "$ROOT/$CATALOG_FILE" ] || die "missing catalog: $CATALOG_FILE — it is the sole registration path and must exist even when empty"

    say "driver_guards: scanning $ROOT"
    say ""

    check_catalog_completeness
    check_symbols || return 1
    check_platform_spi
    check_consumer_casts

    say ""
    if [ "$FAILURES" -gt 0 ]; then
        printf 'driver_guards: %d violation(s)\n' "$FAILURES" >&2
        return 1
    fi
    say "driver_guards: clean"
    return 0
}

# ---------------------------------------------------------------------------
# --self-test: a guard that cannot fail is not a guard.
#
# Copies Package.swift and Sources/ to a scratch tree, injects one violation at a
# time, and asserts the guard rejects it — plus controls that must still PASS, so
# the negative cases prove precision rather than a script that always fails.
#
# The controls matter more here than in safety_guards.sh, because this scan's
# failure mode is noise: a deny-list that fires on `basalRate`, `settings` or a
# doc comment about the dose-category capability gets switched off within a week.
# Every such near-miss the naming decision above depends on is a case below.
#
# Scratch lives under .build/, which is already ignored, rather than in TMPDIR:
# the tree is a copy of the repository and belongs beside it.
# ---------------------------------------------------------------------------
SELF_TEST_HOME=""

self_test_scratch() {
    local tmp
    tmp=$(mktemp -d "$SELF_TEST_HOME/case.XXXXXX")
    cp -R "$ROOT/Sources" "$tmp/Sources"
    cp "$ROOT/$MANIFEST" "$tmp/$MANIFEST"
    printf '%s' "$tmp"
}

# self_test_run <name> <expect PASS|FAIL> <scratch root> [guard script]
self_test_run() {
    local name="$1" expect="$2" tmp="$3" guard="${4:-${BASH_SOURCE[0]}}" status=0 log="$3/guard.log"

    bash "$guard" --root "$tmp" --quiet >"$log" 2>&1 || status=$?

    if { [ "$expect" = "FAIL" ] && [ "$status" -eq 0 ]; } ||
       { [ "$expect" = "PASS" ] && [ "$status" -ne 0 ]; }; then
        printf '  FAIL %-46s expected the guard to %s, it exited %d\n' "$name" "$expect" "$status" >&2
        sed 's/^/         /' "$log" >&2
        rm -rf "$tmp"
        return 1
    fi
    printf '  ok   %-46s guard %s (exit %d)\n' "$name" "$expect" "$status"
    if [ "$EXPLAIN" -eq 1 ]; then sed 's/^/         | /' "$log"; fi
    rm -rf "$tmp"
    return 0
}

# Adds a Driver target to the scratch manifest and a source file under it.
self_test_add_driver_target() {
    local tmp="$1" name="$2" body="${3:-let placeholder = true}"
    mkdir -p "$tmp/$DRIVERS_DIR/$name"
    printf 'import Foundation\n%s\n' "$body" > "$tmp/$DRIVERS_DIR/$name/Probe.swift"
    # Inserted before the closing bracket of the targets array, which is the last
    # `]` in the manifest.
    awk -v decl="        .target(name: \"$name\", path: \"$DRIVERS_DIR/$name\")," '
        { lines[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                if (i == NR - 1) print decl
                print lines[i]
            }
        }' "$tmp/$MANIFEST" > "$tmp/$MANIFEST.new"
    mv "$tmp/$MANIFEST.new" "$tmp/$MANIFEST"
}

# The cycle-3 re-review's laundering probe, as a SEPARATE consumer target: a
# generic helper narrows an existential to a Driver's concrete type without ever
# writing a cast against a name rule D knows. `value as? T` is the only cast in
# the file, and `T` is not a name any list can contain.
#
# It lives outside Sources/Drivers/ because that is the shape the reviewer built
# and because everything under Sources/ except Sources/DriverAPI/ is a consumer,
# so this is exactly where rule D is meant to bite.
#
# The `direct` shape writes the SAME probe with the narrowing spelled out. It is
# the control for the xfail: without it, "not caught" would be equally consistent
# with this path never being scanned at all, and the documented limit would be
# proving nothing.
self_test_add_generic_launderer() {
    local tmp="$1" driver="${2:-Probe}" shape="${3:-laundered}" narrowing
    case "$shape" in
        direct) narrowing='port as? ExtraPort' ;;
        *) narrowing='narrow(port, to: ExtraPort.self)' ;;
    esac
    mkdir -p "$tmp/Sources/PlatformProbe"
    cat > "$tmp/Sources/PlatformProbe/Narrow.swift" <<SWIFT
import DriverAPI
import $driver

func narrow<T>(_ value: Any, to type: T.Type) -> T? { value as? T }

func inspect(_ port: any DoseCategoryProvider) {
    guard let smuggled = $narrowing else { return }
    smuggled.performStepTwo()
}
SWIFT
}

# The descriptor literal for <name>, as it appears inside the entries array.
self_test_descriptor_literal() {
    printf '        DriverDescriptor(\n'
    printf '            identifier: DriverIdentifier("com.glycemicgpt.%s")!,\n' "$1"
    printf '            targetName: "%s",\n' "$1"
    printf '            displayName: "%s",\n' "$1"
    printf '            transport: .inProcess,\n'
    printf '            version: "1.0.0",\n'
    printf '            capabilities: [],\n'
    printf '            verification: .unverified\n'
    printf '        ),\n'
}

# The descriptor literal for <name>, all on one line — for cases that mutate
# formatting (where a line break falls) rather than what the array contains.
self_test_descriptor_literal_oneline() {
    printf 'DriverDescriptor(identifier: DriverIdentifier("com.glycemicgpt.%s")!, targetName: "%s", displayName: "%s", transport: .inProcess, version: "1.0.0", capabilities: [], verification: .unverified)' \
        "$1" "$1" "$1"
}

# Registers <name> in DriverCatalog.entries so its descriptor literal shares a
# line with the array's closing `]` — proving that a registration is read by
# ARRAY MEMBERSHIP, not by which line happens to hold the bracket.
#
# Walks to the closing bracket rather than assuming the array starts empty:
# the array this runs against already holds real entries (SimulatedDriver was
# the first), so a fixture that only knew how to open an empty `[]` would
# silently no-op the moment a real registration landed — exactly the failure
# this replaces.
self_test_add_catalog_entry_sharing_closing_line() {
    local tmp="$1" name="$2" entry
    local file="$tmp/$CATALOG_FILE"
    entry="$tmp/entry-inline.swift"
    self_test_descriptor_literal_oneline "$name" > "$entry"

    awk -v entryfile="$entry" '
        function emit_inline(   text) {
            getline text < entryfile
            close(entryfile)
            return text
        }
        !done && /static let entries: \[DriverDescriptor\] = \[\]/ {
            sub(/\[\]/, "[" emit_inline() "]")
            print
            done = 1
            next
        }
        !done && /static let entries: \[DriverDescriptor\] = \[$/ {
            print
            in_array = 1
            next
        }
        in_array && !done && /^[[:space:]]*\]/ {
            sub(/\]/, emit_inline() "]")
            print
            done = 1
            in_array = 0
            next
        }
        { print }
        END { if (!done) { print "self-test: no entries array to register into" > "/dev/stderr"; exit 3 } }
    ' "$file" > "$file.new"
    mv "$file.new" "$file"
}

# Rewrites the `entries` declaration as a computed `var`, which the member
# scan cannot read (catalog_entries.awk keys on a `let` declaration), so the
# guard must die with "could not be read" rather than answer "no Drivers".
#
# Handles both the empty-array and the opened-multiline shapes, and errors
# when neither is found, because the `sed` this replaces matched only the
# empty-array spelling: the moment the first real entry landed in the
# catalog, that mutation silently no-opped and its case kept failing for an
# unrelated reason (a Fake target with no entry) instead of the named one.
self_test_make_catalog_unreadable() {
    local tmp="$1"
    local file="$tmp/$CATALOG_FILE"
    awk '
        !done && /static let entries: \[DriverDescriptor\] = \[\]/ {
            sub(/static let entries: \[DriverDescriptor\] = \[\]/, "static var entries: [DriverDescriptor] { [] }")
            print
            done = 1
            next
        }
        !done && /static let entries: \[DriverDescriptor\] = \[$/ {
            sub(/static let entries: \[DriverDescriptor\] = \[/, "static var entries: [DriverDescriptor] { [")
            print
            done = 1
            next
        }
        { print }
        END { if (!done) { print "self-test: no entries declaration to rewrite" > "/dev/stderr"; exit 3 } }
    ' "$file" > "$file.new"
    mv "$file.new" "$file"
}

# Registers <name> in DriverCatalog.entries — the real thing, inside the array.
#
# Three shapes, because they are the three the guard has to tell apart:
#
#   entry         a member of `entries`. A registration.
#   commented     the same lines inside a block comment. NOT a registration —
#                 someone commented a Driver out of the catalog and left its
#                 target in the build.
#   disconnected  a `static let FakeEntry = DriverDescriptor(…)` beside the
#                 array. Mentions `targetName`, is referenced by nothing, and
#                 renders on no screen. NOT a registration — and it is exactly
#                 what the first version of this guard accepted.
self_test_add_catalog_entry() {
    # Two `local` statements, deliberately: bash expands every word of a `local`
    # command before the builtin assigns anything, so `file="$tmp/…"` on the
    # SAME line would read the CALLER's `tmp`, not the parameter beside it
    # (ShellCheck SC2318). Every current caller happens to hold the same path in
    # a local `tmp`, which is exactly the kind of accident that stops holding.
    local tmp="$1" name="$2" shape="${3:-entry}" entry
    local file="$tmp/$CATALOG_FILE"

    case "$shape" in
        disconnected)
            printf '%s\n' \
                "extension DriverCatalog {" \
                "    static let ${name}Entry = DriverDescriptor(" \
                "        identifier: DriverIdentifier(\"com.glycemicgpt.${name}\")!," \
                "        targetName: \"$name\"," \
                "        displayName: \"$name\"," \
                "        transport: .inProcess," \
                "        version: \"1.0.0\"," \
                "        capabilities: []," \
                "        verification: .unverified" \
                "    )" \
                "}" >> "$file"
            return 0
            ;;
        commented)
            entry="$tmp/entry.swift"
            { printf '        /*\n'; self_test_descriptor_literal "$name"; printf '        */\n'; } > "$entry"
            ;;
        *)
            entry="$tmp/entry.swift"
            self_test_descriptor_literal "$name" > "$entry"
            ;;
    esac

    # Inserted into the array literal: either by opening the empty one, or after
    # the opening bracket of one a previous call already opened.
    #
    # The text arrives in a FILE rather than through `awk -v`, because the entry
    # is several lines long and a newline inside a `-v` assignment is an error in
    # the awk this script is written for (stock BSD awk, bash 3.2).
    awk -v entryfile="$entry" '
        function emit(   text) {
            while ((getline text < entryfile) > 0) print text
            close(entryfile)
        }
        !done && /static let entries: \[DriverDescriptor\] = \[\]/ {
            sub(/= \[\]/, "= [")
            print
            emit()
            print "    ]"
            done = 1
            next
        }
        !done && /static let entries: \[DriverDescriptor\] = \[$/ {
            print
            emit()
            done = 1
            next
        }
        { print }
        END { if (!done) { print "self-test: no entries array to register into" > "/dev/stderr"; exit 3 } }
    ' "$file" > "$file.new"
    mv "$file.new" "$file"
}

# self_test_symbol <name> <expect> <target: api|driver> <line of Swift>
self_test_symbol() {
    local name="$1" expect="$2" where="$3" payload="$4" tmp
    tmp=$(self_test_scratch)
    if [ "$where" = "driver" ]; then
        self_test_add_driver_target "$tmp" "Probe" "$payload"
        self_test_add_catalog_entry "$tmp" "Probe"
    else
        printf 'import Foundation\n%s\n' "$payload" > "$tmp/Sources/DriverAPI/GuardProbe.swift"
    fi
    self_test_run "$name" "$expect" "$tmp"
}

# self_test_structural <name> <expect> <mutation shell snippet using $T as the scratch root>
self_test_structural() {
    local name="$1" expect="$2" mutation="$3" tmp
    tmp=$(self_test_scratch)
    T="$tmp" eval "$mutation"
    self_test_run "$name" "$expect" "$tmp"
}

# ---------------------------------------------------------------------------
# Documented known limits (xfail). See THE RESIDUAL and DEFERRED-WORK in the
# header.
#
# These assert what the guard does NOT do. They are here rather than in prose so
# the limit is executed on every self-test run: a documented limit nobody runs
# drifts out of date silently, in whichever direction is least convenient.
#
# A limit that starts being CAUGHT is reported as an unexpected result on
# purpose. It is good news, and it also means the residual statement in this
# header now understates the guard and has to be rewritten in the same change —
# a red self-test is what makes that happen rather than being meant to happen.
# ---------------------------------------------------------------------------

# self_test_known_limit <name> <why> <mutation using $T as the scratch root>
self_test_known_limit() {
    local name="$1" why="$2" mutation="$3" tmp status=0
    tmp=$(self_test_scratch)
    T="$tmp" eval "$mutation"

    bash "${BASH_SOURCE[0]}" --root "$tmp" --quiet >"$tmp/guard.log" 2>&1 || status=$?

    if [ "$status" -ne 0 ]; then
        printf '  XPASS %-46s known limit is now CAUGHT (exit %d)\n' "$name" "$status" >&2
        printf '        This is an improvement, not a regression. Promote the case to a\n' >&2
        printf '        FAIL case and rewrite THE RESIDUAL in this script'"'"'s header, which\n' >&2
        printf '        still claims this one escapes.\n' >&2
        sed 's/^/         /' "$tmp/guard.log" >&2
        rm -rf "$tmp"
        return 1
    fi
    printf '  xfail %-46s not caught, as documented — %s\n' "$name" "$why"
    if [ "$EXPLAIN" -eq 1 ]; then sed 's/^/         | /' "$tmp/guard.log"; fi
    rm -rf "$tmp"
    return 0
}

# self_test_sabotaged <name> <expect> <mutation using $G as the copied guard dir>
#
# The other question, which no source mutation can reach: does the guard notice
# when one of its own rules did not run at all? The mutation breaks a COPY of the
# helpers and that copy is what runs. The gate in the working tree is untouched.
self_test_sabotaged() {
    local name="$1" expect="$2" mutation="$3" tmp
    tmp=$(self_test_scratch)
    cp -R "$SCRIPT_DIR" "$tmp/guards"
    G="$tmp/guards" eval "$mutation"
    self_test_run "$name" "$expect" "$tmp" "$tmp/guards/driver_guards.sh"
}

self_test() {
    local total=0 bad_cases=0 limits=0

    SELF_TEST_HOME=$(mktemp -d "$ROOT/.build/driver_guards_selftest.XXXXXX")
    trap 'rm -rf "$SELF_TEST_HOME"' EXIT

    printf 'driver_guards --self-test: proving each guard can fail\n\n'
    printf '  catalog completeness (FR-22)\n'

    run_case() { total=$((total + 1)); "$@" || bad_cases=$((bad_cases + 1)); }
    run_limit() { limits=$((limits + 1)); "$@" || bad_cases=$((bad_cases + 1)); }

    # The tree as it stands must pass, or every FAIL case below proves nothing.
    run_case self_test_structural "control-clean" PASS ':'

    # The AC's named failure mode: a fake Driver target with no catalog entry.
    run_case self_test_structural "driver-target-without-catalog-entry" FAIL \
        'self_test_add_driver_target "$T" Fake'
    # …and the same tree with the entry added must pass, or the case above would
    # be proving only that the guard dislikes new targets.
    run_case self_test_structural "driver-target-with-catalog-entry" PASS \
        'self_test_add_driver_target "$T" Fake; self_test_add_catalog_entry "$T" Fake'
    # A registration that was commented out is not a registration.
    run_case self_test_structural "commented-out-catalog-entry" FAIL \
        'self_test_add_driver_target "$T" Fake; self_test_add_catalog_entry "$T" Fake commented'
    # Nor is a descriptor that sits beside the array and is listed by nothing.
    # This is the shape the cycle-1 guard accepted as a registration, and the
    # shape its own positive case was written in.
    run_case self_test_structural "descriptor-outside-the-entries-array" FAIL \
        'self_test_add_driver_target "$T" Fake; self_test_add_catalog_entry "$T" Fake disconnected'
    # Two Drivers, both registered: the insertion path has to keep working once
    # the array is no longer empty, or the PASS cases above would only ever be
    # testing an array with one element in it.
    run_case self_test_structural "two-drivers-both-registered" PASS \
        'self_test_add_driver_target "$T" Fake; self_test_add_catalog_entry "$T" Fake;
         self_test_add_driver_target "$T" Other; self_test_add_catalog_entry "$T" Other'
    # Where the brackets fall is a formatting choice, not a contract: a
    # descriptor that shares its line with the closing `]` of the entries
    # array — the whole literal on one line, say — is still a member. Walks
    # to the closing bracket rather than assuming the array is empty, since
    # the tree this runs against already carries a real entry.
    run_case self_test_structural "entry-on-the-arrays-closing-line" PASS \
        'self_test_add_driver_target "$T" Fake;
         self_test_add_catalog_entry_sharing_closing_line "$T" Fake'
    # An entries array the scan cannot read at all must be an error, not an empty
    # answer: "no Drivers are registered" and "the catalog could not be read" have
    # opposite meanings and the same shape. The mutation is the ONLY change in
    # this scratch tree, so the case fails for the named reason and no other.
    run_case self_test_structural "unreadable-entries-array" FAIL \
        'self_test_make_catalog_unreadable "$T"'
    # An entry for a Driver that is not built: the user is told they have a
    # Driver they do not have.
    run_case self_test_structural "catalog-entry-without-driver-target" FAIL \
        'self_test_add_catalog_entry "$T" Ghost'
    # Source under Sources/Drivers/ that no target declares.
    run_case self_test_structural "driver-directory-without-target" FAIL \
        'mkdir -p "$T/'"$DRIVERS_DIR"'/Ghost" && printf "import Foundation\n" > "$T/'"$DRIVERS_DIR"'/Ghost/Probe.swift"'
    # The catalog file itself is the registration path; losing it must not read
    # as "no Drivers to check".
    run_case self_test_structural "missing-catalog-file" FAIL \
        'rm -f "$T/'"$CATALOG_FILE"'"'

    printf '\n  symbol scan (AD-12, SI-1) — violations\n'

    run_case self_test_symbol "deliver-verb-in-driver-api" FAIL api 'func deliverDose() {}'
    run_case self_test_symbol "deliver-verb-in-driver-target" FAIL driver 'func deliverDose() {}'
    run_case self_test_symbol "bolus-command-in-driver-target" FAIL driver 'func startBolus() {}'
    run_case self_test_symbol "bare-bolus-identifier" FAIL driver 'let bolus = 1'
    run_case self_test_symbol "set-basal-pair" FAIL driver 'func setBasalRate(_ rate: Double) {}'
    run_case self_test_symbol "set-basal-underscored" FAIL driver 'let set_basal = 1'
    run_case self_test_symbol "temp-basal-pair" FAIL driver 'func tempBasal() {}'
    run_case self_test_symbol "suspend-command" FAIL driver 'func suspendPump() {}'
    run_case self_test_symbol "resume-command" FAIL driver 'func resumePump() {}'
    run_case self_test_symbol "prime-command" FAIL driver 'func primeTubing() {}'
    run_case self_test_symbol "cannula-command" FAIL driver 'func fillCannula() {}'
    run_case self_test_symbol "core-bluetooth-write" FAIL driver 'func send() { peripheral.writeValue(data, for: c, type: .withResponse) }'
    run_case self_test_symbol "pump-write-characteristic" FAIL driver 'let commandCharacteristic = "x"'
    run_case self_test_symbol "control-characteristic" FAIL driver 'let controlCharacteristic = "x"'
    run_case self_test_symbol "uppercase-spelling" FAIL driver 'let BOLUS_LIMIT = 1'
    # The vocabulary of the downcast seam: what a member smuggled onto a concrete
    # port type is called, none of which contains a delivery verb.
    run_case self_test_symbol "enact-verb" FAIL driver 'func enactCorrection() {}'
    run_case self_test_symbol "therapy-noun" FAIL driver 'let therapyMode = 1'
    run_case self_test_symbol "administer-verb" FAIL driver 'func administerDose() {}'
    run_case self_test_symbol "infuse-verb" FAIL driver 'func infuseUnits() {}'
    run_case self_test_symbol "inject-verb" FAIL driver 'func injectUnits() {}'

    printf '\n  symbol scan — controls that must NOT fire\n'

    # The naming decision the guard depends on: a comment about the read-side
    # dose-category capability, and the identifier that replaced Android's
    # BolusCategoryProvider, must both pass.
    run_case self_test_symbol "comment-about-bolus-category-capability" PASS api \
        '// Android calls this BolusCategoryProvider; a bolus category is a read.'
    run_case self_test_symbol "dose-category-provider-identifier" PASS api \
        'protocol DoseCategoryProvider { var declaredCategories: Set<String> { get } }'
    run_case self_test_symbol "bolus-inside-an-elided-string" PASS api \
        'let label = "deliver a bolus and prime the cannula"'
    # Word matching, not prefix matching. Each of these is a real word that
    # starts with a denied one, and each would break the codebase if it fired.
    run_case self_test_symbol "settings-is-not-set-basal" PASS driver 'let settings = 1'
    run_case self_test_symbol "basal-read-is-legal" PASS driver 'let basalRate = 1.0'
    run_case self_test_symbol "primary-is-not-prime" PASS driver 'let primaryDevice = 1'
    run_case self_test_symbol "delivered-is-not-deliver" PASS driver 'let insulinDelivered = 1.0'
    run_case self_test_symbol "read-value-is-not-write-value" PASS driver 'func read() { peripheral.readValue(for: c) }'
    run_case self_test_symbol "notify-value-is-not-write-value" PASS driver 'func sub() { peripheral.setNotifyValue(true, for: c) }'
    # Dependency injection is the ordinary meaning of this word in Swift, and a
    # therapeutic RANGE is a read. Both would break the codebase if they fired.
    run_case self_test_symbol "injected-is-not-inject" PASS driver 'let injectedClock = 1'
    run_case self_test_symbol "therapeutic-is-not-therapy" PASS driver 'let therapeuticRange = 1'

    printf '\n  platform SPI (AD-16)\n'

    # DriverLifecycle is SPI, so a Driver that stores one does not compile under
    # an ordinary import. The way around that is to write the SPI import — which
    # is a line, in a diff, that this rule refuses.
    run_case self_test_symbol "spi-import-in-a-driver-target" FAIL driver \
        '@_spi(DriverPlatform) import DriverAPI'
    run_case self_test_symbol "spi-import-with-other-attributes" FAIL driver \
        '@preconcurrency @_spi(DriverPlatform) import DriverAPI'
    # The ordinary import a Driver actually writes must pass, or the rule would
    # just be banning Drivers from using DriverAPI.
    run_case self_test_symbol "plain-import-in-a-driver-target" PASS driver \
        'import DriverAPI'
    # And the rule is about Driver targets: DriverAPI declares the SPI, so its own
    # use of the attribute is the thing working as intended.
    run_case self_test_symbol "spi-declaration-in-driver-api" PASS api \
        '@_spi(DriverPlatform) public struct PlatformOnly: Sendable {}'

    printf '\n  consumer casts (AD-12) — violations\n'

    # The reviewer's counterexample, in the shape it was written: a Driver conforms
    # its own type to a port, and narrows the existential back to it to reach a
    # surface DriverAPI never declared. The downcast is the reachable step, so the
    # downcast is what fails.
    run_case self_test_symbol "smuggled-concrete-port-downcast" FAIL driver \
        'struct ExtraPort: DoseCategoryProvider {
    func performStepTwo() {}
}
func use(_ port: any DoseCategoryProvider) {
    guard let smuggled = port as? ExtraPort else { return }
    smuggled.performStepTwo()
}'
    run_case self_test_symbol "downcast-to-a-capability-port" FAIL driver \
        'func f(_ p: Any) { _ = p as? DoseCategoryProvider }'
    run_case self_test_symbol "forced-downcast-to-a-capability-port" FAIL driver \
        'func f(_ p: Any) { _ = p as! GlucoseSource }'
    run_case self_test_symbol "is-check-against-the-driver-protocol" FAIL driver \
        'func f(_ v: Any) -> Bool { v is Driver }'
    run_case self_test_symbol "downcast-to-the-port-enum" FAIL driver \
        'func f(_ v: Any) { _ = v as? CapabilityPort }'
    # Where the line breaks fall is not a variable: the scan reads a token stream.
    run_case self_test_symbol "line-wrapped-downcast" FAIL driver \
        'func f(_ p: Any) {
    _ = p as?
        GlucoseSource
}'
    # `any` between the operator and the type must not hide it either.
    run_case self_test_symbol "downcast-through-an-existential-spelling" FAIL driver \
        'func f(_ p: Any) { _ = p as? any InsulinSource }'
    # Swift does not require a space between the operator and the type, so the
    # unspaced spelling is the same narrowing and must fail the same way.
    run_case self_test_symbol "unspaced-optional-downcast" FAIL driver \
        'func f(_ p: Any) { _ = p as?GlucoseSource }'
    run_case self_test_symbol "unspaced-forced-downcast" FAIL driver \
        'func f(_ p: Any) { _ = p as!InsulinSource }'

    printf '\n  consumer casts — controls that must NOT fire\n'

    # DriverAPI is where the ports are DECLARED. A rule that fired there would be
    # a rule against declaring them.
    run_case self_test_symbol "cast-inside-driver-api-is-not-a-consumer-cast" PASS api \
        'func f(_ p: Any) { _ = p as? GlucoseSource }'
    run_case self_test_symbol "unrelated-downcast-is-legal" PASS driver \
        'func f(_ v: Any) { _ = v as? Int }'
    # `is` is matched as a WORD. An identifier that starts with those two letters
    # and continues into a related name is the false positive that would make this
    # rule unusable, so it is pinned.
    run_case self_test_symbol "is-inside-an-identifier" PASS driver \
        'let isDriverActive = true'
    # An upcast widens; it reaches nothing the port did not already declare.
    run_case self_test_symbol "upcast-is-not-a-downcast" PASS driver \
        'func f(_ p: StubPort) { _ = p as any GlucoseSource }'
    run_case self_test_symbol "cast-inside-an-elided-string" PASS driver \
        'let hint = "write port as? GlucoseSource"'
    run_case self_test_symbol "cast-in-a-comment" PASS driver \
        '// never reach for `port as? GlucoseSource` — the port is the whole surface'
    # An extension declares no type. A Driver that extends a standard type must
    # not put that type's name on the cast-target list, or an ordinary
    # `as? Data` in ANY consumer becomes a gate failure the day a Driver adds a
    # Data helper — and a gate that fails on unrelated code is a gate someone
    # switches off. The seam this leaves open is the retroactive-conformance
    # known limit below.
    run_case self_test_symbol "extension-does-not-poison-the-cast-list" PASS driver \
        'extension Data { var frameMarker: UInt8? { first } }
func f(_ v: Any) { _ = v as? Data }'
    # The control for the laundering xfail at the end of this run: the same probe,
    # in the same consumer file, with the narrowing written out. It has to be
    # caught, or "not caught" down there would only be saying that nothing under
    # Sources/PlatformProbe/ is read.
    run_case self_test_structural "consumer-outside-drivers-is-scanned" FAIL \
        'self_test_add_driver_target "$T" Probe "struct ExtraPort: DoseCategoryProvider {
    func performStepTwo() {}
}"; self_test_add_catalog_entry "$T" Probe; self_test_add_generic_launderer "$T" Probe direct'

    printf '\n  scan integrity\n'

    # A file the stripper refuses is a file that was not read. Reporting the rest
    # as clean would be a green gate over unread source.
    run_case self_test_structural "unscannable-source-file" FAIL \
        'printf "/* open\n" > "$T/Sources/DriverAPI/GuardProbe.swift"'
    # The control comes first in spirit: an untouched copy of the guard must pass,
    # so a sabotage case failing means the sabotage was noticed rather than that
    # running from a copy fails by itself.
    run_case self_test_sabotaged "guard-copy-control" PASS ':'
    run_case self_test_sabotaged "stripper-exits-nonzero" FAIL \
        'printf "BEGIN { exit 3 }\n" > "$G/lib/strip_swift_comments.awk"'
    # The harder version of the same question. This helper does not crash — it
    # reads every line and reports no Driver targets at all, exiting 0, which is
    # indistinguishable from a repository that has none. Rule A1 goes vacuous and
    # cannot notice. What notices is that A1 is not the only rule: the directory
    # scan and the catalog cross-check reach the manifest by different routes, and
    # a Driver that exists still fails both.
    # The cast rule is built on a name list READ from the tree, so a reader that
    # goes quiet would leave it scanning for nothing and reporting green. What
    # notices is the count: the port set is six, and a scan that reads a different
    # number is not looking at the port set.
    run_case self_test_sabotaged "port-name-reader-goes-quiet" FAIL \
        'printf "{ next }\n" > "$G/lib/declared_types.awk"'
    run_case self_test_sabotaged "manifest-reader-goes-quiet" FAIL \
        'printf "{ next }\n" > "$G/lib/manifest_driver_targets.awk"; self_test_add_driver_target "$tmp" Fake; self_test_add_catalog_entry "$tmp" Fake'

    # The documented limits, executed. Kept last and counted separately: they
    # assert what the guard does NOT catch, so folding them into the case total
    # would inflate the number that means "ways this guard was proven to fail".
    printf '\n  known limits — text-scan limits, deferred to story 8-6 (swift-syntax)\n'

    # An arbitrary-named extra member on a concrete Driver port type: no
    # vocabulary to match, and no shape that separates it from an ordinary
    # helper.
    run_limit self_test_known_limit "known-limit-arbitrary-member-on-a-driver-type" \
        "an arbitrary member name gives a text scan nothing to match" \
        'self_test_add_driver_target "$T" Probe "struct ExtraPort: DoseCategoryProvider {
    func performStepTwo() {}
}"; self_test_add_catalog_entry "$T" Probe'

    # The second residual: a Driver retroactively conforms a type it does not
    # declare. `extension Data: DoseCategoryProvider` adds no name to the
    # cast-target list — `extension` is deliberately not read as a declaration,
    # per the extension control above — so the narrowing back to `Data` is a
    # cast against a name rule D never learned.
    run_limit self_test_known_limit "known-limit-retroactive-conformance-smuggle" \
        "conforming a standard type adds no Driver-declared name for rule D to match" \
        'self_test_add_driver_target "$T" Probe "extension Data: DoseCategoryProvider {
    public var declaredCategories: Set<String> { [] }
    public func platformCategory(for label: String) -> DoseCategory? { nil }
    public func performStepTwo() {}
}
func use(_ port: any DoseCategoryProvider) {
    guard let smuggled = port as? Data else { return }
    smuggled.performStepTwo()
}"; self_test_add_catalog_entry "$T" Probe'

    # And the reviewer'"'"'s cycle-3 probe: a consumer target reaches that member
    # through a generic narrowing helper, so the only cast written anywhere is
    # `value as? T`. Rule D matches cast SYNTAX against names it knows, and `T`
    # is not one — which is why more awk is the wrong answer here.
    run_limit self_test_known_limit "known-limit-generic-cast-laundering" \
        "a generic helper narrows without writing a cast rule D can match" \
        'self_test_add_driver_target "$T" Probe "public struct ExtraPort: DoseCategoryProvider {
    public func performStepTwo() {}
}"; self_test_add_catalog_entry "$T" Probe; self_test_add_generic_launderer "$T" Probe'

    printf '\n%d case(s), %d documented known limit(s), %d unexpected result(s)\n' \
        "$total" "$limits" "$bad_cases"
    [ "$bad_cases" -eq 0 ] || return 1
    printf 'driver_guards --self-test: every guard fails when it should, every legal\n'
    printf 'read-side name still passes, and every documented limit still escapes\n'
    return 0
}

case "$MODE" in
    check) run_check ;;
    self-test)
        mkdir -p "$ROOT/.build"
        self_test
        ;;
esac
