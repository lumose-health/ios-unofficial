# Strip Swift comments from stdin/files, leaving only code.
#
# The safety guards count how many times a constant appears in the SOURCE, so a
# doc comment that legitimately mentions a value ("never introduce 18.02") must
# not be counted, and — the direction that actually matters — a comment must not
# be able to HIDE a real occurrence from the scan.
#
# Handles, in order of precedence:
#   * `/* ... */` block comments, nested (Swift allows nesting), spanning lines;
#   * `//` line comments, to end of line;
#   * double-quoted string literals, whose contents are PRESERVED and whose `//`
#     or `/*` do not start a comment. Without this, a line like
#     `let url = "https://x"  // note` would have everything after `https:` eaten,
#     which could hide a constant later on the same line — a false NEGATIVE, the
#     unsafe direction.
#
# Deliberately conservative where Swift's grammar gets exotic: multi-line (`"""`)
# and raw (`#"..."#`) string literals are not modelled, so their contents are
# treated as code and counted. Over-counting fails the guard loudly; it never
# hides a duplicate. `instr` is reset per line for the same reason — an unbalanced
# quote cannot swallow the rest of the file.

BEGIN { block = 0 }

{
    line = $0
    out = ""
    instr = 0
    i = 1
    n = length(line)

    while (i <= n) {
        c = substr(line, i, 1)
        two = substr(line, i, 2)

        if (block > 0) {
            if (two == "*/") { block--; i += 2; continue }
            if (two == "/*") { block++; i += 2; continue }
            i++
            continue
        }

        if (instr == 1) {
            if (c == "\\") { out = out c substr(line, i + 1, 1); i += 2; continue }
            if (c == "\"") { instr = 0; out = out c; i++; continue }
            out = out c
            i++
            continue
        }

        if (two == "/*") { block++; i += 2; continue }
        if (two == "//") { break }
        if (c == "\"") { instr = 1; out = out c; i++; continue }

        out = out c
        i++
    }

    print out
}
