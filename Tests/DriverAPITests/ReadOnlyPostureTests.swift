import Foundation
import Testing

@testable import DriverAPI

/// The read-only posture is STRUCTURAL: there is nothing for a Driver to call
/// (FR-31, AD-12, SI-1).
///
/// A rule that "no Driver writes to a pump" enforced by review is a rule that
/// holds until the review that does not. These assertions are about the shape of
/// the contract instead — a Capability port whose members are all reads cannot
/// grow a write without the shape changing, and the shape is what is checked.
///
/// `scripts/guards/driver_guards.sh` covers the other half, the delivery-verb
/// symbol scan, and it covers the Driver targets too. This suite covers the
/// contract's grammar; the guard covers its vocabulary.
@Suite("Read-only posture")
struct ReadOnlyPostureTests {

    /// Verbs that mean "make something happen", as a leading word.
    ///
    /// Checked as a PREFIX of a member name rather than anywhere in it, because
    /// what distinguishes a command from a query in this contract is what the
    /// member name starts with: `latestStatus()` reads, `setStatus()` does not.
    static let commandVerbs = [
        "set", "write", "send", "deliver", "start", "stop", "cancel",
        "issue", "trigger", "program", "enable", "disable", "apply",
        "update", "configure", "reset", "clear", "commit", "post", "put",
    ]

    @Test("No Capability port declares a settable property")
    func noSettableRequirements() throws {
        var offenders: [String] = []
        for (path, code) in try DriverAPISource.files(under: "Capabilities") {
            for property in Self.propertyRequirements(inTokens: DriverAPISource.tokenize(code))
            where property.accessors.contains("set") {
                offenders.append("\(path): `\(property.name)` declares a setter")
            }
        }
        #expect(offenders.isEmpty, "a Capability port declares a settable property: \(offenders)")
    }

    @Test("Every property requirement in a Capability port is exactly `{ get }`")
    func everyPropertyIsGetOnly() throws {
        var offenders: [String] = []
        for (path, code) in try DriverAPISource.files(under: "Capabilities") {
            for property in Self.propertyRequirements(inTokens: DriverAPISource.tokenize(code))
            where property.accessors != ["get"] {
                offenders.append(
                    "\(path): `\(property.name)` is `{ \(property.accessors.joined(separator: " ")) }`"
                )
            }
        }
        #expect(offenders.isEmpty, "not a `{ get }` requirement: \(offenders)")
    }

    @Test("No Capability port declares a mutating member")
    func noMutatingMembers() throws {
        var offenders: [String] = []
        for (path, line) in try DriverAPISource.lines(under: "Capabilities") where line.contains("mutating") {
            offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
        }
        #expect(offenders.isEmpty, "a Capability port declares a mutating member: \(offenders)")
    }

    @Test("No function anywhere in DriverAPI is named with a command verb")
    func noCommandVerbs() throws {
        var offenders: [String] = []
        for (path, line) in try DriverAPISource.lines() {
            guard let name = Self.functionName(declaredIn: line) else { continue }
            guard let verb = Self.commandVerbs.first(where: { Self.name(name, startsWithWord: $0) }) else { continue }
            offenders.append("\(path): `\(name)` starts with the command verb `\(verb)`")
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// The scans above assert absences. Each is shown able to report a presence,
    /// so a change to the matching cannot quietly disarm them.
    @Test("The posture scans see a violation when there is one")
    func postureScansCanFail() {
        #expect(Self.functionName(declaredIn: "    func setBasalRate(_ u: Double)") == "setBasalRate")
        #expect(Self.name("setBasalRate", startsWithWord: "set"))
        #expect(Self.name("deliverDose", startsWithWord: "deliver"))

        // The accessor scan reads a token stream, so a requirement a formatter
        // splits across lines is the same requirement — the shape a per-line
        // scan walked straight past.
        let wrapped = DriverAPISource.tokenize("var status: PumpStatusSnapshot {\n    get\n    set\n}")
        #expect(Self.propertyRequirements(inTokens: wrapped).first?.accessors == ["get", "set"])
        let getOnly = DriverAPISource.tokenize("var latest: GlucoseSample? { get }")
        #expect(Self.propertyRequirements(inTokens: getOnly).first?.accessors == ["get"])
        #expect(Self.propertyRequirements(inTokens: getOnly).first?.name == "latest")

        // …and that they are not merely matching any substring. A read whose name
        // happens to begin with the letters of a command verb is not a command.
        #expect(Self.name("settings", startsWithWord: "set") == false)
        #expect(Self.name("startedAt", startsWithWord: "start") == false)
        #expect(Self.name("posture", startsWithWord: "post") == false)
        #expect(Self.functionName(declaredIn: "/// the func keyword in prose") == nil)
    }

    /// Every property requirement in `tokens`, as its name and accessor tokens.
    ///
    /// Token-based for the same reason ``DriverAPISource/declarations()`` is: a
    /// requirement a formatter splits across lines must read the same as one on
    /// a single line, or the scan is a formatting preference rather than a
    /// check. The accessor block is the first braced block after the `var`,
    /// which in a protocol is the only block a property requirement has.
    static func propertyRequirements(inTokens tokens: [String]) -> [(name: String, accessors: [String])] {
        var found: [(name: String, accessors: [String])] = []
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard tokens[index] == "var", index + 1 < tokens.count else { continue }
            let name = tokens[index + 1]
            guard var cursor = tokens[(index + 2)...].firstIndex(of: "{") else { continue }
            var depth = 0
            var accessors: [String] = []
            while cursor < tokens.count {
                if tokens[cursor] == "{" {
                    depth += 1
                } else if tokens[cursor] == "}" {
                    depth -= 1
                    if depth == 0 { break }
                } else {
                    accessors.append(tokens[cursor])
                }
                cursor += 1
            }
            found.append((name, accessors))
            index = cursor
        }
        return found
    }

    /// The name of the function declared on `line`, or `nil`.
    static func functionName(declaredIn line: String) -> String? {
        let collapsed = line.filter { !$0.isWhitespace }
        guard let keyword = collapsed.range(of: "func"), collapsed.contains("(") else { return nil }
        let rest = collapsed[keyword.upperBound...]
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    /// Whether `name` begins with `word` as a whole camelCase word — `setBasal`
    /// yes, `settings` no.
    static func name(_ name: String, startsWithWord word: String) -> Bool {
        guard name.hasPrefix(word) else { return false }
        let remainder = name.dropFirst(word.count)
        guard let next = remainder.first else { return true }
        return next.isUppercase || next == "_"
    }
}
