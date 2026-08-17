# Extract every Swift numeric literal from stripped source, with its VALUE.
#
# Usage:  awk -v file='Sources/SafetyCore/X.swift' -f scan_numerics.awk < stripped
# Output: one record per literal, `<file>|<line>|<raw spelling>|<value %.17g>`
#
# Why a lexer and not grep: the safety constants must be defined exactly once, and
# a textual scan only knows about the spellings someone thought to list. Swift will
# happily accept `1.80156e1`, `2e1...5e2`, `0x14` and `1_199_145_600` as the very
# same values as `18.0156`, `20...500` and `1199145600`. Those are not obfuscation —
# they are ordinary literal forms, and every one of them defeated the textual guard
# this replaces. Comparing NUMBERS instead of TEXT closes that class completely:
# whatever form a duplicate is written in, it is decoded to the same double.
#
# Literal forms decoded: decimal integer and float, with `_` separators and
# `e`/`E` exponents; hexadecimal (`0x1F`) including hex floats (`0x1.8p3`);
# binary (`0b1010`); octal (`0o17`). Swift has no numeric type suffixes, so the
# literal always ends where the digits do.
#
# The scan is a left-to-right lexer, not a regex sweep, because the surrounding
# characters decide what a run of digits means:
#   * identifiers are consumed whole, so `sha256` and `value20` yield nothing;
#   * a `.` begins a fraction only when a digit follows, so `20...500` decodes as
#     two literals (20, 500) rather than one malformed float;
#   * string literals (already emptied by strip_swift_comments.awk) are skipped.
#
# Values are printed with %.17g — enough digits to round-trip a double exactly —
# so the caller compares the same bit pattern the Swift compiler would produce.

function digitval(ch,   d) {
    d = index("0123456789abcdef", tolower(ch))
    return d - 1
}

function baseint(str, base,   k, v) {
    v = 0
    for (k = 1; k <= length(str); k++) v = v * base + digitval(substr(str, k, 1))
    return v
}

function basefrac(str, base,   k, v, scale) {
    v = 0
    scale = 1 / base
    for (k = 1; k <= length(str); k++) {
        v += digitval(substr(str, k, 1)) * scale
        scale /= base
    }
    return v
}

# Consumes the literal starting at the global `pos` and prints its record.
function emit_number(s, n,   start, raw, val, digits, frac, expo, sign, nxt) {
    start = pos
    val = 0

    if (substr(s, pos, 2) ~ /^0[xX]$/) {
        pos += 2
        digits = ""
        while (pos <= n && substr(s, pos, 1) ~ /[0-9a-fA-F_]/) { digits = digits substr(s, pos, 1); pos++ }
        frac = ""
        if (substr(s, pos, 1) == "." && substr(s, pos + 1, 1) ~ /[0-9a-fA-F]/) {
            pos++
            while (pos <= n && substr(s, pos, 1) ~ /[0-9a-fA-F_]/) { frac = frac substr(s, pos, 1); pos++ }
        }
        gsub(/_/, "", digits)
        gsub(/_/, "", frac)
        val = baseint(digits, 16) + basefrac(frac, 16)
        if (substr(s, pos, 1) ~ /[pP]/) {
            pos++
            sign = 1
            if (substr(s, pos, 1) == "+") pos++
            else if (substr(s, pos, 1) == "-") { sign = -1; pos++ }
            expo = ""
            while (pos <= n && substr(s, pos, 1) ~ /[0-9_]/) { expo = expo substr(s, pos, 1); pos++ }
            gsub(/_/, "", expo)
            val = val * (2 ^ (sign * (expo + 0)))
        }
    } else if (substr(s, pos, 2) ~ /^0[bB]$/) {
        pos += 2
        digits = ""
        while (pos <= n && substr(s, pos, 1) ~ /[01_]/) { digits = digits substr(s, pos, 1); pos++ }
        gsub(/_/, "", digits)
        val = baseint(digits, 2)
    } else if (substr(s, pos, 2) ~ /^0[oO]$/) {
        pos += 2
        digits = ""
        while (pos <= n && substr(s, pos, 1) ~ /[0-7_]/) { digits = digits substr(s, pos, 1); pos++ }
        gsub(/_/, "", digits)
        val = baseint(digits, 8)
    } else {
        digits = ""
        while (pos <= n && substr(s, pos, 1) ~ /[0-9_]/) { digits = digits substr(s, pos, 1); pos++ }
        if (substr(s, pos, 1) == "." && substr(s, pos + 1, 1) ~ /[0-9]/) {
            digits = digits "."
            pos++
            while (pos <= n && substr(s, pos, 1) ~ /[0-9_]/) { digits = digits substr(s, pos, 1); pos++ }
        }
        nxt = substr(s, pos + 1, 1)
        if (substr(s, pos, 1) ~ /[eE]/ && (nxt ~ /[0-9]/ || (nxt ~ /[-+]/ && substr(s, pos + 2, 1) ~ /[0-9]/))) {
            digits = digits substr(s, pos, 1)
            pos++
            if (substr(s, pos, 1) ~ /[-+]/) { digits = digits substr(s, pos, 1); pos++ }
            while (pos <= n && substr(s, pos, 1) ~ /[0-9_]/) { digits = digits substr(s, pos, 1); pos++ }
        }
        gsub(/_/, "", digits)
        val = digits + 0
    }

    # A literal that consumed nothing would spin the caller's loop forever.
    if (pos <= start) pos = start + 1

    raw = substr(s, start, pos - start)
    printf "%s|%d|%s|%.17g\n", file, FNR, raw, val
}

{
    line = $0
    n = length(line)
    pos = 1

    while (pos <= n) {
        c = substr(line, pos, 1)

        if (c == "\"") {
            pos++
            while (pos <= n && substr(line, pos, 1) != "\"") {
                if (substr(line, pos, 1) == "\\") pos++
                pos++
            }
            pos++
            continue
        }

        if (c ~ /[A-Za-z_]/) {
            while (pos <= n && substr(line, pos, 1) ~ /[A-Za-z0-9_]/) pos++
            continue
        }

        if (c ~ /[0-9]/) {
            emit_number(line, n)
            continue
        }

        pos++
    }
}
