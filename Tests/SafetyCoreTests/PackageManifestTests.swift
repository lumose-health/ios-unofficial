import Foundation
import Testing

/// SafetyCore sits at the bottom of the one-way dependency direction (AD-3), so a
/// dependency added here becomes a transitive dependency of every surface in the
/// app — phone, watch and all drivers. Keeping it at zero is a structural
/// property of the package, not a style preference, so it is asserted against the
/// manifest itself rather than trusted to review.
///
/// The same reasoning now covers the workspace's one external dependency. GRDB is
/// the SQL vendor behind `Persistence`, and the value of putting it behind one
/// target is entirely in nothing else importing it: a screen that builds a query
/// has moved a storage decision into the UI, and a Driver that gains a database is
/// a Driver with its own storage path (AD-3). Both are one line in a manifest, so
/// both are asserted here.
@Suite("Package manifest")
struct PackageManifestTests {

    /// The repository root, from this file's location: Tests/SafetyCoreTests/<this>.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // SafetyCoreTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    private static func manifestSource() throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
    }

    /// The manifest with every whitespace character removed.
    ///
    /// Swift accepts whitespace and newlines between a call and its parenthesis and
    /// around argument labels, so `.package (url:` and `.package(url:` declare the
    /// same dependency while only one of them contains `".package("`. Matching the
    /// collapsed text asserts against the declaration rather than against one
    /// formatting of it.
    private static func collapsed(_ manifest: String) -> String {
        manifest.filter { !$0.isWhitespace }
    }

    /// The argument list of the `.target` declaration named `name`, taken from the
    /// collapsed manifest by balancing parentheses.
    ///
    /// The assertion below is scoped to this slice because the same two strings
    /// matched independently across the whole manifest can come from two different
    /// declarations: `name: "SafetyCore"` also appears in the product, and a
    /// `dependencies: []` anywhere — a future target, a product — would satisfy the
    /// second half while SafetyCore itself had grown a dependency.
    ///
    /// Comments are not stripped, so a manifest comment that spelled `.target(`
    /// would be searched too. That direction is safe: an unbalanced or unnamed
    /// match returns nil and the test fails loudly rather than passing quietly.
    private static func targetArguments(named name: String, in manifest: String) -> Substring? {
        let text = collapsed(manifest)
        var searchStart = text.startIndex
        while let head = text.range(of: ".target(", range: searchStart..<text.endIndex) {
            guard let arguments = balancedArguments(
                in: text,
                openParenthesis: text.index(before: head.upperBound)
            ) else { return nil }
            if arguments.contains("name:\"\(name)\"") { return arguments }
            searchStart = head.upperBound
        }
        return nil
    }

    /// Every `.target` and `.testTarget` declaration, as `name` and the argument
    /// slice, so a rule can be asserted about targets this file does not name.
    /// A target added later is covered without editing the assertion.
    private static func allTargetDeclarations(in manifest: String) -> [(name: String, arguments: Substring)] {
        let text = collapsed(manifest)
        var declarations: [(name: String, arguments: Substring)] = []
        for keyword in [".target(", ".testTarget("] {
            var searchStart = text.startIndex
            while let head = text.range(of: keyword, range: searchStart..<text.endIndex) {
                searchStart = head.upperBound
                guard let arguments = balancedArguments(
                    in: text,
                    openParenthesis: text.index(before: head.upperBound)
                ) else { continue }
                guard let nameRange = arguments.range(of: "name:\""),
                      let closing = arguments.range(of: "\"", range: nameRange.upperBound..<arguments.endIndex)
                else { continue }
                declarations.append((String(arguments[nameRange.upperBound..<closing.lowerBound]), arguments))
            }
        }
        return declarations
    }

    /// The text between `openParenthesis` and the `)` that closes it.
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

    /// GRDB is the whole of the workspace's third-party surface. A second package
    /// is a decision, not a convenience — it is inherited by everything that links
    /// the target holding it, and it arrives with its own release cadence and its
    /// own supply chain. Adding one means editing this assertion, in the PR that
    /// adds it, where a reviewer sees it.
    @Test("GRDB is the only external package the workspace depends on")
    func grdbIsTheOnlyExternalPackage() throws {
        let manifest = Self.collapsed(try Self.manifestSource())
        let declarations = manifest.components(separatedBy: ".package(").count - 1
        #expect(declarations == 1, "the manifest declares \(declarations) external packages, expected exactly GRDB")
        #expect(
            manifest.contains(".package(url:\"https://github.com/groue/GRDB.swift.git\",exact:\"7.11.1\")"),
            "GRDB must be the official repository, pinned to an exact version (AD-6)."
        )
    }

    /// A range would let a patch release arrive without anyone reading its
    /// changelog. The thing behind this dependency is a schema and a migration
    /// engine over a user's health data; the version it runs is a reviewed choice.
    @Test("The GRDB pin is exact, not a range")
    func grdbPinIsExact() throws {
        let manifest = Self.collapsed(try Self.manifestSource())
        for looseSpelling in ["from:", "branch:", "revision:", ".upToNextMajor", ".upToNextMinor"] {
            #expect(
                !manifest.contains(looseSpelling),
                "the GRDB dependency must be exact-pinned; the manifest uses \(looseSpelling)."
            )
        }
    }

    @Test("The SafetyCore target declares an empty dependency list")
    func safetyCoreTargetHasNoDependencies() throws {
        let arguments = try #require(
            Self.targetArguments(named: "SafetyCore", in: try Self.manifestSource()),
            "The manifest declares no `.target` named SafetyCore."
        )
        #expect(
            arguments.contains("dependencies:[]"),
            "SafetyCore must have zero dependencies (AD-3); its target declares: \(arguments)"
        )
    }

    /// `DriverAPI` is the layer every Driver is allowed to see, so a dependency
    /// added here is one every Driver inherits — including the vendor targets
    /// AD-3 forbids from acquiring their own storage or network path. The list is
    /// asserted to be EXACTLY `["SafetyCore"]` rather than to contain it: a
    /// `contains` check passes on `["SafetyCore", "Persistence"]`, which is the
    /// edge the rule exists to prevent.
    @Test("The DriverAPI target depends on SafetyCore and nothing else")
    func driverAPIDependsOnSafetyCoreOnly() throws {
        let arguments = try #require(
            Self.targetArguments(named: "DriverAPI", in: try Self.manifestSource()),
            "The manifest declares no `.target` named DriverAPI."
        )
        #expect(
            arguments.contains("dependencies:[\"SafetyCore\"]"),
            "DriverAPI may depend only on SafetyCore (AD-3); its target declares: \(arguments)"
        )
    }

    // The two assertions above are only as good as the matching underneath them,
    // and both spellings below passed the plain `contains` checks they replace. So
    // the matching is exercised against manifests this repository does not have,
    // rather than trusted because the manifest it does have is well behaved.

    @Test("A package declaration is found however the call is spaced")
    func packageDeclarationMatchingToleratesWhitespace() {
        #expect(Self.collapsed(".package (url: \"x\", from: \"1.0.0\")").contains(".package("))
        #expect(Self.collapsed(".package\n    (url: \"x\")").contains(".package("))
    }

    @Test("The dependency assertion is bound to the SafetyCore declaration itself")
    func targetMatchingIsBoundToOneDeclaration() throws {
        // A product named SafetyCore, a SafetyCore target that HAS a dependency,
        // and a different target with none — the manifest that would satisfy two
        // independent `contains` checks while breaking AD-3.
        let manifest = """
        let package = Package(
            products: [.library(name: "SafetyCore", targets: ["SafetyCore"])],
            targets: [
                .target (
                    name: "SafetyCore",
                    dependencies: ["Elsewhere"]
                ),
                .target(name: "Elsewhere", dependencies: []),
            ]
        )
        """
        let arguments = try #require(Self.targetArguments(named: "SafetyCore", in: manifest))
        #expect(arguments.contains("dependencies:[\"Elsewhere\"]"))
        #expect(!arguments.contains("dependencies:[]"))
    }

    /// Empty scaffolding invites drift: a target directory that exists before it
    /// has an owner accumulates code nobody agreed to. Later targets arrive one at
    /// a time — `DomainCore/` and the rest of the Structural Seed are absent until
    /// the change that owns them. `Drivers/` arrived with `SimulatedDriver`, the
    /// first Driver to ship, and `Persistence/` with the on-device store.
    @Test("Only the declared targets exist under Sources/")
    func onlyDeclaredTargetsAreScaffolded() throws {
        let sources = Self.repositoryRoot.appendingPathComponent("Sources")
        let entries = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        #expect(entries == ["DriverAPI", "Drivers", "Persistence", "SafetyCore"])
    }

    /// `Persistence` is the only target allowed to see the SQL vendor, and its
    /// list is asserted EXACTLY for the same reason DriverAPI's is: a `contains`
    /// check passes on a list that has grown something it should not have.
    @Test("The Persistence target depends on SafetyCore, DriverAPI and GRDB only")
    func persistenceDependsOnItsThree() throws {
        let arguments = try #require(
            Self.targetArguments(named: "Persistence", in: try Self.manifestSource()),
            "The manifest declares no `.target` named Persistence."
        )
        #expect(
            arguments.contains(
                "dependencies:[\"SafetyCore\",\"DriverAPI\",.product(name:\"GRDB\",package:\"GRDB.swift\")]"
            ),
            "Persistence may depend only on SafetyCore, DriverAPI and GRDB; its target declares: \(arguments)"
        )
    }

    /// Read from the manifest rather than written out, so a target added by a
    /// later change is covered by this rule without anyone remembering to add it.
    @Test("No target other than Persistence declares GRDB")
    func onlyPersistenceDeclaresGRDB() throws {
        let declarations = Self.allTargetDeclarations(in: try Self.manifestSource())
        let holders = declarations.filter { $0.arguments.contains("GRDB") }.map(\.name).sorted()
        #expect(
            holders == ["Persistence"],
            "GRDB must stay behind one target; these declare it: \(holders)"
        )
    }

    /// The enumeration the two assertions above stand on. A helper that silently
    /// found no targets would make "no other target declares GRDB" true of an
    /// empty list, so what it reads is checked against targets this manifest has.
    @Test("Every declared target is enumerated, tests included")
    func targetEnumerationReadsTheWholeManifest() throws {
        let names = Set(Self.allTargetDeclarations(in: try Self.manifestSource()).map(\.name))
        #expect(names.isSuperset(of: [
            "SafetyCore", "SafetyCoreTests",
            "DriverAPI", "DriverAPITests",
            "SimulatedDriver", "SimulatedDriverTests",
            "Persistence", "PersistenceTests",
        ]))
    }

    /// `SimulatedDriver` is a Driver target, so it is held to the same ceiling
    /// every Driver is (AD-3): DriverAPI and SafetyCore, nothing else. Asserted
    /// EXACTLY, for the same reason ``driverAPIDependsOnSafetyCoreOnly`` is —
    /// `contains` would pass on a dependency list this target should never have.
    @Test("The SimulatedDriver target depends on DriverAPI and SafetyCore only")
    func simulatedDriverDependsOnDriverAPIAndSafetyCoreOnly() throws {
        let arguments = try #require(
            Self.targetArguments(named: "SimulatedDriver", in: try Self.manifestSource()),
            "The manifest declares no `.target` named SimulatedDriver."
        )
        #expect(
            arguments.contains("dependencies:[\"DriverAPI\",\"SafetyCore\"]"),
            "SimulatedDriver may depend only on DriverAPI and SafetyCore (AD-3); its target declares: \(arguments)"
        )
    }
}
