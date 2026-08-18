# declared_types.awk — the type-ish declarations in one Swift file.
#
# Reads COMMENT-STRIPPED Swift on stdin (lib/strip_swift_comments.awk) and emits
# one `keyword|Name` record per declaration.
#
# Used to build the set of names a consumer must not cast to: the Capability port
# protocols (read from Sources/DriverAPI/Capabilities/) and every type a Driver
# target declares (read from Sources/Drivers/). Reading them rather than listing
# them in the guard means a renamed port or a new Driver type is covered the day
# it lands, with nothing to keep in sync.
#
# The whole file is collapsed to ONE token stream before declarations are read,
# so a declaration split across lines — `public final\nclass Foo` — is seen the
# same as one on a single line. Line numbers are not reported because the callers
# want names, not locations.
#
# Names must start with a capital letter, which is what separates a type name
# from `case protocolMismatch` and friends. A lowercase-named type would be
# missed; nothing in this codebase has one, and Swift's own convention is the
# reason the filter is cheap.
#
# `extension` is deliberately NOT a declaration keyword here. An extension names
# a type it does not declare, and reading it as a declaration puts that name on
# the caller's cast-target list: one `extension Data { … }` inside a Driver and
# an ordinary `as? Data` anywhere else under Sources/ becomes a gate failure,
# which is the noise that gets a guard switched off. A type a Driver actually
# declares is read from its own struct/class/actor/enum/protocol/typealias
# keyword, wherever its extensions live. The cost is precise and documented:
# a Driver that RETROACTIVELY conforms a type it does not declare adds no name
# for the cast rule to match — see THE RESIDUAL in driver_guards.sh and the
# `known-limit-retroactive-conformance-smuggle` self-test case.

BEGIN {
    split("struct class actor enum protocol typealias", keywords, " ")
    for (i in keywords) is_keyword[keywords[i]] = 1
    count = 0
}

{
    line = $0
    gsub(/[^A-Za-z0-9_]+/, " ", line)
    parts = split(line, token, " ")
    for (i = 1; i <= parts; i++) {
        count++
        stream[count] = token[i]
    }
}

END {
    for (i = 1; i < count; i++) {
        if ((stream[i] in is_keyword) && stream[i + 1] ~ /^[A-Z]/) {
            print stream[i] "|" stream[i + 1]
        }
    }
}
