# Strip Swift comments and string CONTENTS from stdin/files, leaving only code.
#
# The safety guards count how many times a constant appears in the SOURCE, so a
# doc comment that legitimately mentions a value ("never introduce 18.02") must
# not be counted, and — the direction that actually matters — neither a comment
# nor a string may HIDE a real occurrence from the scan.
#
# Handles, in order of precedence:
#   * `/* ... */` block comments, nested (Swift allows nesting), spanning lines;
#   * `//` line comments, to end of line;
#   * double-quoted string literals: the delimiters are kept (emitted as an empty
#     `""`) and the CONTENTS are elided, while scanning continues normally after
#     the closing quote. Two consequences, both required:
#       - a `//` or `/*` inside a string does not start a comment, so
#         `let url = "https://x"  // note` cannot eat a constant later on the
#         same line (a false NEGATIVE, the unsafe direction);
#       - an ordinary string that merely mentions a guarded value —
#         `"expected 18.0156"` — is not a definition and must not be counted
#         (a false POSITIVE, which erodes trust in the gate until it is ignored).
#   * `\( ... )` string interpolation: the interpolated expression is real code
#     and is emitted as code, so `"\(Date())"` still trips the clock guard.
#     Parentheses are matched, so `"\(f(x))"` is handled.
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
    interp = 0
    depth = 0
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

        # Inside a string, outside an interpolation: elide.
        if (instr == 1 && interp == 0) {
            if (two == "\\(") { interp = 1; depth = 1; out = out " "; i += 2; continue }
            if (c == "\\") { i += 2; continue }
            if (c == "\"") { instr = 0; out = out "\"\""; i++; continue }
            i++
            continue
        }

        # Inside an interpolation: this is code, keep it.
        if (interp == 1) {
            if (c == "(") { depth++ }
            else if (c == ")") {
                depth--
                if (depth == 0) { interp = 0; out = out " "; i++; continue }
            }
            out = out c
            i++
            continue
        }

        if (two == "/*") { block++; i += 2; continue }
        if (two == "//") { break }
        if (c == "\"") { instr = 1; i++; continue }

        out = out c
        i++
    }

    print out
}
