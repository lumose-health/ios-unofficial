# Print the `targetName` of every DriverDescriptor that is a MEMBER of
# `DriverCatalog.entries`, as `name|line`.
#
# Usage:  awk -f strip_swift_comments.awk DriverCatalog.swift \
#           | awk -f catalog_entries.awk - DriverCatalog.swift
#
# Same two inputs and the same reason as manifest_driver_targets.awk: the
# STRIPPED text says which lines are code, the RAW text carries the string
# values the stripper elides. Reading only the raw text would count a
# commented-out entry as a registration, which is precisely the mistake this
# check exists to catch — someone comments a Driver out of the catalog while
# leaving its target in the build.
#
# WHAT CHANGED, AND WHY IT MATTERED
#
# The first version of this file printed every line containing `targetName`
# anywhere in DriverCatalog.swift. That is not "is this Driver registered", it is
# "does this Driver's name appear in the registration FILE" — and the two come
# apart the moment somebody writes
#
#     extension DriverCatalog { static let tandemEntry = DriverDescriptor(…) }
#
# which mentions `targetName: "Tandem"`, satisfies the guard, and leaves
# `DriverCatalog.entries` empty. A descriptor nothing lists is not a catalog
# entry; the Drivers screen renders `entries` and would show nothing.
#
# So the scan now walks the `entries` array literal itself and counts only
# `targetName` occurrences INSIDE its brackets. Everything else in the file is
# ignored, and a file with no readable `entries` array is an error rather than an
# empty answer — an unreadable catalog must not look like a catalog with no
# Drivers in it.
#
# `targetName` is the field matched rather than the display name or the
# reverse-domain id, because it is the one field defined to equal the SPM target
# name. See DriverDescriptor's doc comment.
#
# LIMIT: an entry built by a function call or spliced in from another `let` is
# not resolved — this reads a literal array of literal descriptors, which is what
# a compile-time catalog is. Anything cleverer than that fails the guard by not
# being seen, which is the safe direction: the target it belongs to still has no
# entry, and rule A1 says so.

function value_after(key, line,   p, rest, q) {
    p = index(line, key)
    if (p == 0) return ""
    rest = substr(line, p + length(key))
    q = index(rest, "\"")
    if (q == 0) return ""
    rest = substr(rest, q + 1)
    q = index(rest, "\"")
    if (q == 0) return ""
    return substr(rest, 1, q - 1)
}

NR == FNR { stripped[FNR] = $0; total = FNR; next }
{ raw[FNR] = $0 }

END {
    state = "SEEK"
    depth = 0
    opened = 0

    for (line = 1; line <= total; line++) {
        code = stripped[line]

        if (state == "SEEK") {
            # A declaration, not a use: `entries` preceded by `let` on the same
            # line. Without that, `entries.first { … }` in a lookup helper would
            # start the scan in the middle of a function body.
            p = index(code, "entries")
            if (p == 0) continue
            l = index(code, "let")
            if (l == 0 || l > p) continue
            code = substr(code, p + length("entries"))
            state = "SEEK_EQ"
        }

        if (state == "SEEK_EQ") {
            # After the `=`, so the `[` of the TYPE annotation
            # (`: [DriverDescriptor]`) is not mistaken for the array literal.
            p = index(code, "=")
            if (p == 0) continue
            code = substr(code, p + 1)
            state = "SEEK_OPEN"
        }

        if (state == "SEEK_OPEN") {
            p = index(code, "[")
            if (p == 0) continue
            code = substr(code, p)
            state = "INSIDE"
        }

        if (state == "INSIDE") {
            n = length(code)
            closed_here = 0
            for (i = 1; i <= n; i++) {
                c = substr(code, i, 1)
                if (c == "[") {
                    depth++
                    opened = 1
                } else if (c == "]") {
                    depth--
                    if (depth <= 0) {
                        state = "DONE"
                        closed_here = 1
                        break
                    }
                }
            }
            # An empty value is printed rather than skipped: it means the entry was
            # written in a shape this scan cannot read, and a silently dropped entry
            # would read as "no such Driver is registered".
            #
            # `closed_here` keeps a descriptor that shares its line with the
            # array's closing `]` — a one-line `entries` literal, say — from
            # being dropped: by the time the print test runs, the depth for that
            # line is already 0.
            if ((depth >= 1 || closed_here) && index(code, "targetName") > 0)
                print value_after("targetName", raw[line]) "|" line
            if (state == "DONE") break
        }
    }

    if (!opened) {
        print "catalog_entries: no readable DriverCatalog.entries array" > "/dev/stderr"
        exit 2
    }
}
