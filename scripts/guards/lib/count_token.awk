# Count occurrences of a literal token on stdin. Prints a single integer.
#
# Usage:  awk -v tok='18.0156' -v bounded=1 -f count_token.awk
#
# `bounded=1` applies NUMERIC BOUNDARIES so that a widening or precision drift is
# caught rather than quietly matched. Plain substring counting would let
# `20...500` -> `20...5000`, `18.0156` -> `18.01565` and `18.0156` -> `18.0156e1`
# slip through, because the canonical token is a prefix of the drifted one —
# exactly the unsafe direction. So a bounded match is rejected when:
#   * a DIGIT precedes it   — `1199145600` does not contain the bound `19`;
#   * a DIGIT, `e` or `E` follows it — `20...5000` is not `20...500`.
#
# `.` and `_` are deliberately NOT boundaries. The guard counts the bare bound
# numerals as well as the range literal, and both `20` and `500` sit against a
# `.` inside the canonical `20...500`; treating `.` as a boundary would make the
# guard blind to one of them. `_` is already gone by this point — the caller
# normalises Swift digit separators first, so `1_199_145_600` arrives as
# `1199145600` and cannot be used to smuggle in a second copy.
#
# `bounded=0` counts plain substrings, for non-numeric tokens such as `Date()`.
#
# Matching is scanned per position rather than by regex, so repeated occurrences
# on one line are all counted — a regex that consumes its boundary character
# would miss the second of two adjacent matches and under-report.

BEGIN { count = 0; tl = length(tok) }

tl > 0 {
    s = $0
    start = 1
    while (1) {
        p = index(substr(s, start), tok)
        if (p == 0) break
        abs = start + p - 1

        ok = 1
        if (bounded == 1) {
            before = (abs > 1) ? substr(s, abs - 1, 1) : ""
            after = substr(s, abs + tl, 1)
            if (before ~ /[0-9]/) ok = 0
            if (after ~ /[0-9eE]/) ok = 0
        }
        if (ok) count++

        start = abs + 1
    }
}

END { print count + 0 }
