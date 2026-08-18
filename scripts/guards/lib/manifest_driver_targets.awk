# Print every SPM target declared under Sources/Drivers/, as `name|path`.
#
# Usage:  awk -f strip_swift_comments.awk Package.swift \
#           | awk -f manifest_driver_targets.awk - Package.swift
#
# Two inputs, in this order: the STRIPPED manifest on stdin, then the RAW
# manifest. Neither alone is enough.
#
#   * The stripped text is where the STRUCTURE is read. Its string contents are
#     elided, so a parenthesis inside a string literal cannot throw off the
#     balance count, and a `.target(` inside a comment is already gone — a
#     commented-out target must not demand a catalog entry.
#   * The raw text is where the VALUES are read, because the stripper elides
#     exactly the strings this scan needs: `name: "Tandem"` arrives as
#     `name:""`.
#
# The stripper emits one output line per input line, so line N of the first
# input describes line N of the second. That pairing is the whole trick, and it
# is why this cannot be run on a stripped file from somewhere else.
#
# LIMIT: a target whose `name:` or `path:` VALUE sits on a different line from
# its label is not matched, and the target is reported with an empty field. That
# is the safe direction — an empty name matches no catalog entry, so the guard
# fails loudly rather than passing something it did not really read. SwiftPM
# manifests are not written that way, and if one ever is, the fix is to write it
# normally.

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

function balance(text,   i, c, delta) {
    delta = 0
    for (i = 1; i <= length(text); i++) {
        c = substr(text, i, 1)
        if (c == "(") delta++
        else if (c == ")") delta--
    }
    return delta
}

NR == FNR { stripped[FNR] = $0; total = FNR; next }
{ raw[FNR] = $0 }

END {
    inside = 0
    for (line = 1; line <= total; line++) {
        code = stripped[line]

        if (inside == 0) {
            at = index(code, ".target(")
            if (at == 0) continue
            inside = 1
            depth = 0
            name = ""
            path = ""
            code = substr(code, at + length(".target"))
        }

        if (index(code, "name") > 0 && name == "") name = value_after("name", raw[line])
        if (index(code, "path") > 0 && path == "") path = value_after("path", raw[line])

        depth += balance(code)
        if (depth <= 0) {
            if (path ~ /^Sources\/Drivers\//) print name "|" path
            inside = 0
        }
    }
}
