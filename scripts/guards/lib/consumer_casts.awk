# consumer_casts.awk — casts that narrow a Capability port or a Driver type.
#
# Reads COMMENT-STRIPPED Swift on stdin and emits one `line|operator|Type` record
# per `as?` / `as!` / `is` whose target is a name in `-v names="…"` (space
# separated).
#
# WHY THIS EXISTS
#
# `Driver/capability(_:)` returns a `CapabilityPort`, whose payloads are `any`
# existentials of the six port protocols. The platform can only call what a port
# declares, and every port declares reads — but a Driver may conform its own
# concrete type to a port, hand it over, and a consumer may downcast the
# existential back to that concrete type and call whatever it declares:
#
#     guard case .doseCategoryProvider(let port) = driver.capability(.doseCategoryProvider),
#           let smuggled = port as? ExtraTherapyPort else { return }
#     smuggled.enactTherapy()          // a surface DriverAPI never declared
#
# Swift cannot make that unrepresentable — an existential is downcastable, and
# there is no sealed-conformance feature to lean on. What CAN be forbidden is the
# second line: the downcast is the only way to reach the smuggled surface, it is
# consumer-side, and it is a text shape. So it is a gate failure.
#
# HOW IT MATCHES
#
# The whole stripped file becomes one token stream, so a cast wrapped across
# lines (`value as?` / `    GlucoseSource`) reads the same as one on a line.
# `?` and `!` are kept as part of tokens, which is what makes `as?` a token of
# its own and — more importantly — keeps `is` a WORD: `isDriverActive` tokenizes
# as one identifier and is not an `is` check, so it cannot be confused for one.
#
# `any` and `some` between the operator and the type are skipped, and a trailing
# `?`/`!` on the type name is ignored, so `as? any GlucoseSource` and
# `as! GlucoseSource!` both report `GlucoseSource`.
#
# Swift does not require a space between the operator and the type name:
# `p as?GlucoseSource` compiles and narrows exactly like the spaced spelling.
# Because `?` and `!` stay inside tokens, that spelling would otherwise arrive
# as ONE token matching nothing, so a token that BEGINS `as?` or `as!` and
# continues is split into the operator and what follows before matching.
#
# Reported line numbers are the TYPE's line, which is the one worth looking at.

BEGIN {
    total = split(names, name, " ")
    for (i = 1; i <= total; i++) if (name[i] != "") related[name[i]] = 1
    count = 0
}

{
    line = $0
    gsub(/[^A-Za-z0-9_?!]+/, " ", line)
    parts = split(line, token, " ")
    for (i = 1; i <= parts; i++) {
        t = token[i]
        # The unspaced spelling: `as?GlucoseSource` is one token here, because
        # `?` and `!` are token characters. Split the operator off so it reads
        # the same as `as? GlucoseSource`. Nothing else produces a token that
        # BEGINS with `as?`/`as!` and continues: `?`/`!` can only abut an
        # identifier where source had them adjacent, and an identifier cannot
        # contain either character.
        if (t ~ /^as[?!]./) {
            count++
            stream[count] = substr(t, 1, 3)
            source_line[count] = FNR
            t = substr(t, 4)
        }
        count++
        stream[count] = t
        source_line[count] = FNR
    }
}

END {
    for (i = 1; i <= count; i++) {
        operator = ""
        j = i + 1
        if (stream[i] == "as?" || stream[i] == "as!") {
            operator = stream[i]
        } else if (stream[i] == "as" && (stream[j] == "?" || stream[j] == "!")) {
            operator = "as" stream[j]
            j++
        } else if (stream[i] == "is") {
            operator = "is"
        }
        if (operator == "") continue

        while (j <= count && (stream[j] == "any" || stream[j] == "some")) j++
        if (j > count) continue

        target = stream[j]
        gsub(/[?!]+$/, "", target)
        if (target in related) printf "%d|%s|%s\n", source_line[j], operator, target
    }
}
