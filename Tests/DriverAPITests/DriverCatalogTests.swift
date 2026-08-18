import Foundation
import Testing

@testable import DriverAPI

/// `DriverCatalog` is the sole registration path, and it is a compile-time list
/// (FR-22, AD-12, AD-17).
@Suite("Driver catalog")
struct DriverCatalogTests {

    /// `SimulatedDriver` is the first Driver to ship, and the first
    /// registration here.
    @Test("The catalog registers the Simulated Driver, the first Driver to ship")
    func catalogRegistersSimulatedDriver() throws {
        #expect(DriverCatalog.entries.count == 1)
        #expect(DriverCatalog.rows().count == 1)
        let entry = try #require(DriverCatalog.entries.first)
        #expect(entry.targetName == "SimulatedDriver")
        #expect(entry.transport == .inProcess)
        #expect(entry.verification == .unverified)
        #expect(entry.capabilities == [.glucoseSource, .insulinSource])
    }

    /// A lookup for a Driver that is not registered must still be vacuous
    /// rather than trapping — the catalog is not empty any more, but most
    /// identifiers and most capabilities still answer nothing.
    @Test("Lookups answer the Simulated Driver where it is registered, and nothing where it is not")
    func lookupsMatchOnlyWhatIsRegistered() throws {
        let unregistered = try #require(DriverIdentifier("com.glycemicgpt.tandem"))
        #expect(DriverCatalog.entry(for: unregistered) == nil)

        let simulated = try #require(DriverIdentifier("com.glycemicgpt.simulated"))
        #expect(DriverCatalog.entry(for: simulated)?.targetName == "SimulatedDriver")

        for capability in [Capability.glucoseSource, .insulinSource] {
            #expect(DriverCatalog.entries(providing: capability).map(\.targetName) == ["SimulatedDriver"])
        }
        for capability in Capability.allCases where capability != .glucoseSource && capability != .insulinSource {
            #expect(DriverCatalog.entries(providing: capability).isEmpty, "\(capability)")
        }
    }

    /// Registration means MEMBERSHIP in ``DriverCatalog/entries``, and this is the
    /// check that resolves it by being the program rather than by reading it:
    /// `entries` here is the array itself, so a descriptor that sits beside it and
    /// is referenced by nothing cannot pass.
    ///
    /// `driver_guards.sh` asks the same question of the source text, which is the
    /// half that can run before a build and can see the package manifest. Neither
    /// replaces the other: the guard catches a target the manifest declares and
    /// the catalog omits; this catches the tree and the array disagreeing at all.
    ///
    /// This reads each target's declared `name` and `path` from `Package.swift`
    /// rather than assuming a Driver's DIRECTORY name equals its SPM target
    /// name — they are not required to match, and for `SimulatedDriver` they do
    /// not: the target is named `SimulatedDriver` and lives at
    /// `Sources/Drivers/Simulated/`. `DriverDescriptor/targetName` is defined to
    /// equal the SPM target name (see its doc comment), so that is what this
    /// compares against — a directory-basename comparison would fail on a
    /// perfectly correctly registered Driver.
    @Test("Every Driver target's manifest declaration is a member of the entries array")
    func everyDriverInTheTreeIsRegistered() throws {
        let driversRoot = DriverAPISource.repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("Drivers")

        let directories = Set(
            ((try? FileManager.default.contentsOfDirectory(
                at: driversRoot,
                includingPropertiesForKeys: [.isDirectoryKey]
            )) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
        )

        let manifestTargets = try Self.manifestDriverTargets()
        let manifestDirectories = Set(manifestTargets.compactMap { $0.path.split(separator: "/").last }.map(String.init))
        #expect(
            directories == manifestDirectories,
            "directories under Sources/Drivers/ \(directories.sorted()), manifest paths name \(manifestDirectories.sorted())"
        )

        let declaredNames = Set(manifestTargets.map(\.name))
        let registered = Set(DriverCatalog.entries.map(\.targetName))
        #expect(declaredNames == registered, "manifest target names \(declaredNames.sorted()), catalog entries \(registered.sorted())")
    }

    /// `(name, path)` for every `.target(` declared in `Package.swift` under
    /// `Sources/Drivers/`, read by balancing parentheses over whitespace-
    /// collapsed text — the same shape `PackageManifestTests` uses to find one
    /// named target, generalised to find every target's `path` too.
    private static func manifestDriverTargets() throws -> [(name: String, path: String)] {
        let manifestURL = DriverAPISource.repositoryRoot.appendingPathComponent("Package.swift")
        let raw = try String(contentsOf: manifestURL, encoding: .utf8)
        let collapsed = raw.filter { !$0.isWhitespace }

        var results: [(name: String, path: String)] = []
        var searchStart = collapsed.startIndex
        while let head = collapsed.range(of: ".target(", range: searchStart..<collapsed.endIndex) {
            guard let arguments = balancedArguments(
                in: collapsed,
                openParenthesis: collapsed.index(before: head.upperBound)
            ) else { break }
            if let name = stringValue(after: "name:", in: arguments),
               let path = stringValue(after: "path:", in: arguments),
               path.hasPrefix("Sources/Drivers/") {
                results.append((name, path))
            }
            searchStart = head.upperBound
        }
        return results
    }

    private static func balancedArguments(in text: String, openParenthesis: String.Index) -> Substring? {
        var depth = 0
        var index = openParenthesis
        while index < text.endIndex {
            switch text[index] {
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return text[text.index(after: openParenthesis)..<index] }
            default:
                break
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func stringValue(after key: String, in text: Substring) -> String? {
        guard let keyRange = text.range(of: key) else { return nil }
        let rest = text[keyRange.upperBound...]
        guard let openQuote = rest.firstIndex(of: "\"") else { return nil }
        let afterOpen = rest.index(after: openQuote)
        guard let closeQuote = rest[afterOpen...].firstIndex(of: "\"") else { return nil }
        return String(rest[afterOpen..<closeQuote])
    }

    /// The point of the catalog is that what ships is visible in one file before
    /// the build. A runtime registration path — a `register`, a bundle scan, a
    /// dynamic load — would put a Capability somewhere no reviewer saw, and AD-17
    /// requires composition to be subtractive only.
    @Test("No runtime loading surface exists")
    func noRuntimeLoadingSurface() throws {
        let forbidden = [
            "register", "unregister", "Bundle", "NSClassFromString", "dlopen",
            "principalClass", "objc_", "dynamic", "load(",
        ]
        var offenders: [String] = []
        for (path, line) in try DriverAPISource.lines() {
            for token in forbidden where line.contains(token) {
                offenders.append("\(path): `\(token)` in \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// `entries` is a `let`. A `var` would be mutable by anything that can see
    /// the type — including a test, and a catalog a test can mutate is a catalog
    /// production code can mutate.
    @Test("The catalog list is immutable")
    func catalogListIsImmutable() throws {
        let catalog = try DriverAPISource.files()
            .first { $0.path.hasSuffix("Sources/DriverAPI/DriverCatalog.swift") }
        let code = try #require(catalog?.code).filter { !$0.isWhitespace }
        #expect(code.contains("staticletentries:[DriverDescriptor]=["))
        #expect(code.contains("staticvarentries") == false)
    }

    /// No mutable stored global anywhere in the target. This is the other half of
    /// ``SafetyLimits``'s "no caching member": a `static var` is where a cached
    /// copy of a safety bound would live, and a cached safety bound keeps
    /// admitting values after the user has narrowed it.
    @Test("DriverAPI declares no mutable stored global")
    func noMutableStoredGlobals() throws {
        var offenders: [String] = []
        for (path, code) in try DriverAPISource.files() {
            for declaration in Self.staticVarDeclarations(inTokens: DriverAPISource.tokenize(code))
            where declaration.isStored {
                offenders.append("\(path): static var \(declaration.name)")
            }
        }
        for (path, line) in try DriverAPISource.lines() where line.contains("nonisolated(unsafe)") {
            offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
        }
        #expect(offenders.isEmpty, "mutable stored global state in DriverAPI: \(offenders)")
    }

    /// `static var` declarations, read from the token stream so a declaration a
    /// formatter splits across lines is seen the same as one on a single line —
    /// the same reason ``DriverAPISource/declarations()`` is not a per-line scan.
    ///
    /// Stored means an `=` is reached before any `{`: an initialised stored
    /// property assigns first, a computed one opens its body first.
    static func staticVarDeclarations(inTokens tokens: [String]) -> [(name: String, isStored: Bool)] {
        var found: [(name: String, isStored: Bool)] = []
        guard tokens.count >= 3 else { return found }
        for index in 0...(tokens.count - 3) where tokens[index] == "static" && tokens[index + 1] == "var" {
            let name = tokens[index + 2]
            var cursor = index + 3
            var isStored = true
            while cursor < tokens.count {
                if tokens[cursor] == "=" { break }
                if tokens[cursor] == "{" {
                    isStored = false
                    break
                }
                cursor += 1
            }
            found.append((name, isStored))
        }
        return found
    }

    /// The scan above asserts an absence, so it is shown able to report a
    /// presence — including the line-wrapped shape a per-line scan missed.
    @Test("The stored-global scan sees a declaration split across lines")
    func staticVarScanCanFail() {
        let wrapped = DriverAPISource.tokenize("static\nvar cached:\n    SafetyLimits? = nil")
        #expect(Self.staticVarDeclarations(inTokens: wrapped).first?.isStored == true)
        #expect(Self.staticVarDeclarations(inTokens: wrapped).first?.name == "cached")
        let computed = DriverAPISource.tokenize("static var rows: [DriverRow] { [] }")
        #expect(Self.staticVarDeclarations(inTokens: computed).first?.isStored == false)
    }

    // MARK: - The descriptor is what the guard matches on

    /// `driver_guards.sh` links a catalog entry to a package target by comparing
    /// `targetName` against the manifest. The field has to exist and has to be
    /// what the guard reads; renaming it silently would leave the guard matching
    /// nothing and reporting green.
    @Test("A descriptor names the package target it belongs to")
    func descriptorCarriesItsTargetName() throws {
        let descriptor = DriverDescriptor(
            identifier: try #require(DriverIdentifier("com.glycemicgpt.tandem")),
            targetName: "Tandem",
            displayName: "Tandem Insulin Pump",
            transport: .bluetoothLowEnergy,
            version: "1.0.0",
            capabilities: [.glucoseSource, .insulinSource, .pumpStatus],
            verification: .protocolCompatible
        )
        #expect(descriptor.targetName == "Tandem")
        #expect(descriptor.id == descriptor.identifier)
    }

    @Test("The verification vocabulary is closed, and starts at unverified")
    func verificationVocabulary() {
        #expect(
            VerificationStatus.allCases == [
                .unverified, .protocolCompatible, .beta, .hardwareVerified,
            ]
        )
    }

    @Test("The transport vocabulary is closed")
    func transportVocabulary() {
        #expect(DriverTransport.allCases == [.bluetoothLowEnergy, .network, .inProcess])
    }
}
