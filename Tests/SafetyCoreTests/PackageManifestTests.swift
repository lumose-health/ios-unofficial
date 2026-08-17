import Foundation
import Testing

/// SafetyCore sits at the bottom of the one-way dependency direction (AD-3), so a
/// dependency added here becomes a transitive dependency of every surface in the
/// app — phone, watch and all drivers. Keeping it at zero is a structural
/// property of the package, not a style preference, so it is asserted against the
/// manifest itself rather than trusted to review.
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

    @Test("The package declares no external dependencies at all")
    func noExternalPackages() throws {
        let manifest = Self.collapsed(try Self.manifestSource())
        #expect(
            !manifest.contains(".package("),
            "SafetyCore must have zero dependencies (AD-3); the manifest declares an external package."
        )
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
    /// has a story and an owner accumulates code nobody agreed to. Later targets
    /// arrive one story at a time.
    @Test("Only the SafetyCore target directory exists under Sources/")
    func onlySafetyCoreIsScaffolded() throws {
        let sources = Self.repositoryRoot.appendingPathComponent("Sources")
        let entries = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        #expect(entries == ["SafetyCore"])
    }
}
