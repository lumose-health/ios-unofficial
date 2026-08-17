# Judge the numeric literals found by scan_numerics.awk against the canonical
# safety constants.
#
# Usage:  awk -v spec='<name>:<value>:<band low>:<band high>;...' \
#             -v canonical_file='Sources/SafetyCore/SafetyConstants.swift' \
#             -f classify_numerics.awk < records
#
# Input records: `<file>|<line>|<raw>|<value>` (see scan_numerics.awk).
# Output lines:  `V|<message>` for a violation, `P|<message>` for a passed check.
# The canonical values live in safety_guards.sh, not here — this file is the rule,
# that file is the pin.
#
# Two rules, and it is worth being precise about what each one can and cannot do:
#
#   EXACT  A literal numerically EQUAL to a canonical constant is a definition of
#          it, whatever spelling it wears. Each constant must have exactly one
#          such literal under Sources/, and it must sit in the canonical file.
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

    for (k = 1; k <= ncanon; k++) {
        if (v == cval[k]) {
            count[k]++
            sites[k] = sites[k] " " $1 ":" $2
            next
        }
    }

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

        if (count[k] != 1) {
            printf "V|%s (%s): expected exactly one definition under Sources/, found %d%s\n", \
                cname[k], ctext[k], count[k], (s == "" ? "" : " at " s)
            continue
        }

        split(s, parts, ":")
        if (parts[1] != canonical_file) {
            printf "V|%s (%s): must be defined in %s, found at %s\n", cname[k], ctext[k], canonical_file, s
            continue
        }

        printf "P|%s (%s) defined exactly once, at %s\n", cname[k], ctext[k], s
    }
}
