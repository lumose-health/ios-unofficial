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
#   * string literals in ALL FOUR Swift spellings — ordinary `"..."`, multi-line
#     `"""..."""`, and the raw forms of each with any number of `#` delimiters
#     (`#"..."#`, `##"..."##`, `#"""..."""#`). The delimiters are kept (emitted
#     as an empty `""`) and the CONTENTS are elided, while scanning continues
#     normally after the closing delimiter. Two consequences, both required:
#       - a `//` or `/*` inside a string does not start a comment, so
#         `let url = "https://x"  // note` cannot eat a constant later on the
#         same line (a false NEGATIVE, the unsafe direction);
#       - an ordinary string that merely mentions a guarded value —
#         `"expected 18.0156"` — is not a definition and must not be counted
#         (a false POSITIVE, which erodes trust in the gate until it is ignored).
#   * string interpolation: the interpolated expression is real code and is
#     emitted as code, so `"\(Date())"` still trips the clock guard. Its extent
#     is found by counting parentheses in the expression's RAW TEXT, which is
#     where this parser stops being a parser — see LIMITS below.
#
# DELIMITER AWARENESS is what makes the string handling safe rather than merely
# plausible, and it runs both ways:
#   * a raw string closes only on `"` followed by ITS OWN number of `#`s, so an
#     inner `"` — `#"harmless "quoted" text"#` — does not end it early and let
#     the rest of the string be scanned as code (noise), and, far worse, does not
#     leave the parser mid-string over real code that follows on the same line;
#   * interpolation must carry the SAME number of `#`s as the delimiter. `\#(…)`
#     inside `#"…"#` is executed code and is scanned; the identical text inside
#     `##"…"##` is inert characters and is elided. Getting this backwards in
#     either direction is a bug: treating executed code as text hides a
#     wall-clock read (this is the cycle-3 review finding, whose probe was
#     `#"timestamp: \#(Date())"#`), and treating text as code invents duplicates.
#
# Multi-line strings are the one construct with state that outlives a line, so
# `instr` is reset per line EXCEPT inside one — an unbalanced quote on an
# ordinary line cannot swallow the rest of the file. An unterminated multi-line
# literal would, so it is refused in END with a nonzero exit rather than reported
# as a clean scan of a file whose tail was silently elided.
#
# LIMITS — stated exactly, because the previous version of this header said
# "not modelled: nothing", and that was false in the unsafe direction.
#
# String DELIMITERS are modelled completely: every form Swift 6 accepts, with any
# `#` count, opens and closes where the compiler says it does. What is best-effort
# is the INSIDE of an interpolation. Once `\(` opens one, this parser only counts
# parentheses in the text until they balance; it does not re-enter comment or
# string handling for the expression. So a `)` written inside a `/* … */` comment,
# or inside a nested string literal, within the interpolated expression is counted
# as a real closing paren. The interpolation is then closed EARLY, and the rest of
# the expression — on that line — is elided as if it were string text.
#
# Both spellings of that are compiler-validated bypasses, not theory. Each
# compiles, runs, and reads the wall clock under `swift -swift-version 6`:
#
#     let stamp = "\({ /* ) */ Date() }())"           # `)` hidden in a comment
#     let a = "\(String(")").count + Date().hashValue)"   # `)` in a nested literal
#
# and this stripper emits `let stamp =  { /*  ""` and `let a =  String(")" ""` —
# the `Date()` is gone from both. The guard carries them as DOCUMENTED KNOWN
# BYPASSES in --self-test (`known-bypass-interpolation-comment-paren`,
# `known-bypass-interpolation-nested-literal-paren`), expected to pass through, so
# the day they stop passing through we learn coverage improved instead of finding
# out by accident.
#
# The over-counting direction — a `(` hidden the same way, leaving the
# interpolation open so text is scanned as code — is the loud one: it invents
# violations, a human looks, nothing ships wrong.
#
# Closing this properly means lexing Swift rather than approximating it; see the
# DEFERRED-WORK note in safety_guards.sh (story 8-6, swift-syntax analysis). The
# residual risk beyond it is this parser simply being wrong, which is what the
# guard's --self-test cases exist to keep honest.

BEGIN { block = 0; instr = 0; multi = 0; hashes = 0; interp = 0; depth = 0 }

# The n characters at s[pos] are all `#`. n == 0 is vacuously true, which is what
# makes the ordinary (non-raw) string fall out of the same code as the raw ones.
function all_hashes(s, pos, n,   k) {
    for (k = 0; k < n; k++) if (substr(s, pos + k, 1) != "#") return 0
    return 1
}

# Swift requires a multi-line literal's opening delimiter to be the last thing on
# its line. Checking that keeps `"""` inside an ordinary expression from being
# mistaken for one and putting the parser into multi-line state.
function rest_is_blank(s, pos) {
    return (substr(s, pos) ~ /^[[:space:]]*$/)
}

{
    line = $0
    out = ""
    if (multi == 0) { instr = 0; hashes = 0; interp = 0; depth = 0 }
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
            if (c == "\\") {
                # `\(`, `\#(`, `\##(` … — interpolation, but only when the hash
                # count matches this literal's delimiter exactly.
                if (all_hashes(line, i + 1, hashes) && substr(line, i + 1 + hashes, 1) == "(") {
                    interp = 1; depth = 1; out = out " "; i += 2 + hashes; continue
                }
                # Otherwise: an escape in an ordinary string (consumes the next
                # character, so `\"` cannot close it), or a plain backslash in a
                # raw string, where nothing but the delimiter is special.
                if (hashes == 0) { i += 2; continue }
                i++
                continue
            }
            if (c == "\"") {
                if (multi == 1) {
                    if (substr(line, i, 3) == "\"\"\"" && all_hashes(line, i + 3, hashes)) {
                        instr = 0; multi = 0; out = out "\"\""; i += 3 + hashes; continue
                    }
                    i++
                    continue
                }
                if (all_hashes(line, i + 1, hashes)) {
                    instr = 0; out = out "\"\""; i += 1 + hashes; continue
                }
                i++
                continue
            }
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

        # `#` opens a raw string only when the run of `#`s is followed by a quote;
        # otherwise it is ordinary Swift (`#available`, `#if`, a macro) and stays.
        if (c == "#") {
            h = 1
            while (substr(line, i + h, 1) == "#") h++
            if (substr(line, i + h, 1) == "\"") {
                hashes = h
                if (substr(line, i + h, 3) == "\"\"\"" && rest_is_blank(line, i + h + 3)) {
                    instr = 1; multi = 1; i += h + 3; continue
                }
                instr = 1; multi = 0; i += h + 1; continue
            }
            out = out substr(line, i, h)
            i += h
            continue
        }

        if (c == "\"") {
            hashes = 0
            if (substr(line, i, 3) == "\"\"\"" && rest_is_blank(line, i + 3)) {
                instr = 1; multi = 1; i += 3; continue
            }
            instr = 1; multi = 0; i++; continue
        }

        out = out c
        i++
    }

    print out
}

END {
    if (multi == 1) {
        print "strip_swift_comments: unterminated multi-line string literal — refusing to report a scan whose tail was elided" > "/dev/stderr"
        exit 3
    }
}
