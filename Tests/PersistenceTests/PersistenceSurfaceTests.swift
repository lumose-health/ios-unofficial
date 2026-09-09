import Foundation
import Testing

/// Structural rules about the target's source, asserted against the tree rather
/// than trusted to review.
///
/// Each one is a single line somebody could add in a hurry, in a file nobody
/// re-reads, and none of them breaks a build when it lands.
@Suite("Persistence source surface")
struct PersistenceSurfaceTests {

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // PersistenceTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root

    /// Directories the scans do not walk: build products (which contain the
    /// dependency's own sources, and would make every rule below fail on code this
    /// repository did not write) and version-control bookkeeping.
    private static let skippedDirectories: Set<String> = [".build", ".git", ".swiftpm"]

    /// Every Swift file in the REPOSITORY, with COMMENTS REMOVED and STRING
    /// LITERAL CONTENTS BLANKED.
    ///
    /// The whole repository, not one subtree: a rule about where an import may
    /// appear is only worth as much as the set of places it looked. Comments have
    /// to go, or every rule below fails on the doc comment that explains it. The
    /// paragraph saying "there is no `@unchecked Sendable` here" is not an
    /// `@unchecked Sendable`. String contents go for the same reason in both
    /// directions: a quoted mention of a forbidden pattern is not the pattern, and
    /// a quoted `//` is not a comment and must not swallow the code that follows
    /// it on the line.
    private static func swiftFiles(under directory: String = "") throws -> [(path: String, source: String)] {
        let root = directory.isEmpty
            ? repositoryRoot
            : repositoryRoot.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var files: [(String, String)] = []
        for case let url as URL in walker {
            if skippedDirectories.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            files.append((relativePath(of: url), withoutComments(source)))
        }
        return files.sorted { $0.0 < $1.0 }
    }

    private static func relativePath(of url: URL) -> String {
        let root = repositoryRoot.resolvingSymlinksInPath().path
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    /// A single pass that knows just enough Swift to tell code from the rest:
    /// line comments, nested block comments, and string literals in their plain,
    /// multiline and raw-delimited spellings. Comment text and string interiors
    /// become spaces; newlines survive so line structure does; everything else is
    /// handed through untouched.
    private static func withoutComments(_ source: String) -> String {
        var output = [Character]()
        let characters = Array(source)
        var index = 0

        func matches(_ text: String, at offset: Int = 0) -> Bool {
            let start = index + offset
            let end = start + text.count
            guard end <= characters.count else { return false }
            return String(characters[start..<end]) == text
        }
        func blankOne() {
            output.append(characters[index] == "\n" ? "\n" : " ")
            index += 1
        }
        func copy(count: Int) {
            for _ in 0..<count {
                output.append(characters[index])
                index += 1
            }
        }

        while index < characters.count {
            if matches("//") {
                while index < characters.count, characters[index] != "\n" {
                    output.append(" ")
                    index += 1
                }
                continue
            }
            if matches("/*") {
                var depth = 0
                repeat {
                    if matches("/*") {
                        depth += 1
                        output.append(contentsOf: "  ")
                        index += 2
                    } else if matches("*/") {
                        depth -= 1
                        output.append(contentsOf: "  ")
                        index += 2
                    } else {
                        blankOne()
                    }
                } while depth > 0 && index < characters.count
                continue
            }

            var pounds = 0
            while matches("#", at: pounds) { pounds += 1 }
            if matches("\"", at: pounds) {
                let delimiter = String(repeating: "#", count: pounds)
                let quotes = matches(delimiter + "\"\"\"") ? "\"\"\"" : "\""
                let closer = quotes + delimiter
                copy(count: pounds + quotes.count)
                while index < characters.count, !matches(closer) {
                    if pounds == 0, characters[index] == "\\", index + 1 < characters.count {
                        output.append(contentsOf: "  ")
                        index += 2
                    } else {
                        blankOne()
                    }
                }
                if index < characters.count { copy(count: closer.count) }
                continue
            }
            if pounds > 0 {
                copy(count: pounds)
                continue
            }

            copy(count: 1)
        }
        return String(output)
    }

    /// The value of putting the SQL vendor behind one target is entirely in
    /// nothing else importing it: a screen that builds a query has moved a storage
    /// decision into the UI, and a Driver that gains a database has its own
    /// storage path (AD-3). The manifest test pins the dependency; this pins the
    /// import, which is the thing that would actually appear first — and it looks
    /// at every Swift file in the repository, tests included, because a test that
    /// reaches for the vendor directly is a test that stops holding the store to
    /// its own API.
    @Test("GRDB is imported only inside the Persistence target")
    func grdbIsImportedOnlyInPersistence() throws {
        let scanned = try Self.swiftFiles()
        let importers = scanned
            .filter { Self.importsGRDB($0.source) }
            .map(\.path)
        #expect(
            importers.allSatisfy { $0.hasPrefix("Sources/Persistence/") },
            "GRDB must stay inside Sources/Persistence/; these import it: \(importers)"
        )
        #expect(!importers.isEmpty, "the scan found no GRDB import at all, so it is proving nothing")
        // The scan is only worth the tree it walked. These are files it must have
        // reached: one in each Swift-bearing corner of the repository.
        let reached = Set(scanned.map(\.path))
        for expected in [
            "Package.swift",
            "Sources/Persistence/LocalStore.swift",
            "Sources/SafetyCore/Glucose.swift",
            "Sources/Drivers/Simulated/SimulatedDriver.swift",
            "Tests/PersistenceTests/PersistenceSurfaceTests.swift",
            "Tests/SafetyCoreTests/PackageManifestTests.swift",
        ] {
            #expect(reached.contains(expected), "the scan never reached \(expected)")
        }
    }

    /// Whether a file IMPORTS the vendor, rather than whether the two words appear
    /// in it. An import declaration can carry attributes (`@testable`,
    /// `@preconcurrency`, `@_exported`) and can name a kind or a submodule
    /// (`import class GRDB.DatabasePool`), so this reads the shape of the
    /// declaration instead of one spelling of it.
    private static func importsGRDB(_ source: String) -> Bool {
        source.range(
            of: #"(?m)^\s*(?:@[A-Za-z_]\w*(?:\([^)]*\))?\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|actor|let|var|func)\s+)?GRDB\b"#,
            options: .regularExpression
        ) != nil
    }

    /// The detector, against text this repository does not have: every spelling of
    /// the import it must find, and mentions it must not mistake for one.
    @Test("The import detector reads imports, not mentions")
    func importDetectionReadsStatements() {
        #expect(Self.importsGRDB("import Foundation\nimport GRDB\n"))
        #expect(Self.importsGRDB("    @testable import GRDB"))
        #expect(Self.importsGRDB("@preconcurrency import GRDB"))
        #expect(Self.importsGRDB("@_exported import GRDB"))
        #expect(Self.importsGRDB("import class GRDB.DatabasePool"))
        #expect(Self.importsGRDB("import GRDB.DatabasePool"))
        #expect(!Self.importsGRDB("#expect(!stripped.contains(\"import GRDB\"))"))
        #expect(!Self.importsGRDB("let sql = \"SELECT 1\" // import GRDB one day"))
        #expect(!Self.importsGRDB("import GRDBCustom"))
    }

    /// Safety Limits are narrowable — a user or a remote setting can move them —
    /// and the store enforces only the ABSOLUTE bound. A store that could be
    /// handed a limit would be a store whose contents depend on a setting, and
    /// history written under a narrow limit would be missing readings that were
    /// always valid.
    @Test("No Safety Limit is a parameter to anything in the store")
    func theStoreTakesNoSafetyLimits() throws {
        let mentions = try Self.swiftFiles(under: "Sources/Persistence")
            .filter { $0.source.contains("SafetyLimits") }
            .map(\.path)
        #expect(mentions.isEmpty, "narrowable limits belong upstream of the store; found in: \(mentions)")
    }

    /// Swift 6 checks data-race safety at compile time, and `@unchecked` is the
    /// word for "trust me instead". The store is a value over Sendable parts, so
    /// there is nothing to opt out of — and if that changes, it should change
    /// visibly.
    @Test("The store opts out of no concurrency checking")
    func noUncheckedSendable() throws {
        let optOuts = try Self.swiftFiles(under: "Sources/Persistence")
            .filter { $0.source.contains("@unchecked") || $0.source.contains("nonisolated(unsafe)") }
            .map(\.path)
        #expect(optOuts.isEmpty, "concurrency checking is opted out of in: \(optOuts)")
    }

    /// At-rest protection is not a choice a consumer makes. The seam exists so the
    /// FAILURE path can be exercised, and it stays internal so the only way to open
    /// a store from outside this package is the one that protects the file. A
    /// `public` in this file would be an opt-out, and an opt-out taken once — in a
    /// scratch harness, in an extension somebody wrote in a hurry — is an
    /// unprotected database carrying health data.
    @Test("Nothing in the protection seam is public")
    func theProtectionSeamIsInternal() throws {
        let file = try #require(
            try Self.swiftFiles(under: "Sources/Persistence")
                .first { $0.path.hasSuffix("StoreFileProtection.swift") },
            "the protection seam moved; this rule is looking at nothing"
        )
        #expect(
            !file.source.contains("public"),
            "the protection seam must not be reachable from outside the package"
        )
    }

    /// The public way in takes no protection argument at all — the rule above says
    /// the seam is unreachable, and this says the door has no handle for it either.
    @Test("The public open declares no protection parameter")
    func thePublicOpenTakesNoProtection() throws {
        let file = try #require(
            try Self.swiftFiles(under: "Sources/Persistence")
                .first { $0.path.hasSuffix("LocalStore.swift") },
            "the store moved; this rule is looking at nothing"
        )
        let publicOpens = Self.declarations(of: "public static func open(", in: file.source)
        #expect(!publicOpens.isEmpty, "the store declares no public open, so this rule is proving nothing")
        for declaration in publicOpens {
            #expect(
                !declaration.contains("protection"),
                "the public open must not offer a protection parameter: \(declaration)"
            )
        }
    }

    /// Each declaration that starts with `prefix`, up to its opening brace — enough
    /// to read a signature and no more.
    private static func declarations(of prefix: String, in source: String) -> [String] {
        source.components(separatedBy: prefix)
            .dropFirst()
            .map { tail in
                prefix + String(tail.prefix(while: { $0 != "{" }))
            }
    }

    /// The rules above are only as good as the stripping underneath them. A
    /// stripper that removed too much would make every one of them pass on a file
    /// that broke the rule, so what it removes is checked against text this
    /// repository does not have.
    @Test("Comment removal takes the comments and leaves the code")
    func commentRemovalKeepsCode() {
        let stripped = Self.withoutComments("""
        /// no @unchecked Sendable lives here
        struct A: @unchecked Sendable {} // trailing note about SafetyLimits
        /* import GRDB */
        let kept = 1
        """)
        #expect(stripped.contains("struct A: @unchecked Sendable {}"))
        #expect(stripped.contains("let kept = 1"))
        #expect(!stripped.contains("no @unchecked Sendable lives here"))
        #expect(!stripped.contains("SafetyLimits"))
        #expect(!stripped.contains("import GRDB"))
    }

    /// A `//` inside a string literal is text, not a comment. A stripper that cut
    /// the line there would hide whatever follows it, and every prohibition above
    /// would pass on a file that broke it.
    @Test("A quoted comment marker hides nothing after it")
    func quotedCommentMarkerHidesNothing() {
        let stripped = Self.withoutComments(
            #"let marker = "//"; final class Escape: @unchecked Sendable {}"#
        )
        #expect(stripped.contains("@unchecked Sendable"))
        #expect(!stripped.contains("//"))
    }

    /// String interiors are blanked in every spelling, so a mention is never
    /// mistaken for the thing itself, while the code around the literal survives.
    @Test("String literal contents are blanked, quotes and code kept")
    func stringContentsAreBlanked() {
        let stripped = Self.withoutComments(
            "let mention = \"import GRDB\"\n"
                + "let raw = #\"@unchecked\"#\n"
                + "let multi = \"\"\"\n  SafetyLimits\n  \"\"\"\n"
                + "let escaped = \"a \\\" b // c\"\n"
                + "let kept = 2"
        )
        #expect(!stripped.contains("import GRDB"))
        #expect(!stripped.contains("@unchecked"))
        #expect(!stripped.contains("SafetyLimits"))
        #expect(!stripped.contains("//"))
        #expect(stripped.contains("let mention = \""))
        #expect(stripped.contains("let kept = 2"))
    }

    /// And the signature reader is only as good as what it takes: a helper that
    /// returned an empty string would make the rule above pass on a declaration
    /// that broke it.
    @Test("The signature reader takes each declaration up to its body")
    func declarationReadingStopsAtTheBody() {
        let found = Self.declarations(of: "public static func open(", in: """
        public static func open(at url: URL, protection: Seam) -> Self { fatalError() }
        static func open(at url: URL, protection: Seam) -> Self { fatalError() }
        public static func open(at url: URL) -> Self { fatalError() }
        """)
        #expect(found.count == 2)
        #expect(found.first?.contains("protection: Seam") == true)
        #expect(found.last?.contains("protection") == false)
        #expect(found.allSatisfy { !$0.contains("fatalError") })
    }
}
