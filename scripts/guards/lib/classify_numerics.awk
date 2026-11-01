# Judge the numeric literals found by scan_numerics.awk against the canonical
# safety constants.
#
# Usage:  awk -v spec='<name>:<value>:<band low>:<band high>;...' \
#             -v canonical_file='Sources/SafetyCore/SafetyConstants.swift' \
#             -f classify_numerics.awk < records
#
# Input records: `<file>|<line>|<raw>|<value>` (see scan_numerics.awk).
# Output lines:  `V|<message>` for a violation, `P|<message>` for a passed check, and
#                one final `D|<n>` marker naming how many canonical constants were
#                judged. The marker is printed at the very end of END, so a caller
#                that sees it knows these rules ran over the whole record stream.
#                Without it the caller cannot tell a clean run from a scan that died
#                and said nothing — and silence read as clean is the one failure a
#                gate must not have.
# The canonical values live in safety_guards.sh, not here — this file is the rule,
# that file is the pin.
#
# Two rules, and it is worth being precise about what each one can and cannot do:
#
#   EXACT  A literal numerically EQUAL to a canonical constant is a definition of
#          it, whatever spelling it wears. Each declared constant has exactly one
#          literal, in the canonical file; constants that share a value share
#          that count.
#          This rule is complete: there is no way to write an equal value that
#          escapes it.
#
#   BAND   A literal that is *near* a canonical constant without being equal to
#          it is a drifted copy — `18.02` for the conversion factor, `501` for an
#          off-by-one bound, `1199145601` for the epoch. This rule is a heuristic
#          and is honest about it: it catches drift inside the band and nothing
#          outside it. See safety_guards.sh's header for the coverage statement.

BEGIN {
    FS = "|"
    ncanon = split(spec, recs, ";")
    for (k = 1; k <= ncanon; k++) {
        split(recs[k], f, ":")
        cname[k] = f[1]
        ctext[k] = f[2]
        cval[k] = f[2] + 0
        clo[k] = f[3] + 0
        chi[k] = f[4] + 0
        count[k] = 0
        sites[k] = ""
    }
}

{
    v = $4 + 0
    matched = 0

    for (k = 1; k <= ncanon; k++) {
        if (v == cval[k]) {
            count[k]++
            sites[k] = sites[k] " " $1 ":" $2
            matched = 1
        }
    }
    if (matched) next

    for (k = 1; k <= ncanon; k++) {
        if (v >= clo[k] && v <= chi[k]) {
            printf "V|%s:%s: `%s` is numerically close to the %s (%s) without being equal to it — a drifted copy of a safety constant is more dangerous than a missing one, because both surfaces still work and disagree; use SafetyConstants\n", \
                $1, $2, $3, cname[k], ctext[k]
            next
        }
    }
}

END {
    for (k = 1; k <= ncanon; k++) {
        s = sites[k]
        sub(/^ /, "", s)

        # Distinct named constants may share a value; each must still be its own
        # literal in the canonical file, so expect one literal per declaration.
        expected = 0
        for (j = 1; j <= ncanon; j++) if (cval[j] == cval[k]) expected++
        if (count[k] != expected) {
            printf "V|%s (%s): expected %d literal(s) with this value under Sources/, found %d%s — use SafetyConstants at any extra site\n", \
                cname[k], ctext[k], expected, count[k], (s == "" ? "" : " at " s)
            continue
        }

        nsites = split(s, parts, " ")
        invalid_site = 0
        for (i = 1; i <= nsites; i++) {
            split(parts[i], location, ":")
            if (location[1] != canonical_file) invalid_site = 1
        }
        if (invalid_site) {
            printf "V|%s (%s): every literal must be defined in %s, found at %s\n", cname[k], ctext[k], canonical_file, s
            continue
        }

        printf "P|%s (%s) defined %d time(s), at %s\n", cname[k], ctext[k], expected, s
    }

    # The end-of-run marker, after the last verdict. See the header: this is the
    # caller's evidence that the rules above ran, rather than producing nothing.
    printf "D|%d\n", ncanon
}
