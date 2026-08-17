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

    @Test("The package declares no external dependencies at all")
    func noExternalPackages() throws {
        let manifest = try Self.manifestSource()
        #expect(
            !manifest.contains(".package("),
            "SafetyCore must have zero dependencies (AD-3); the manifest declares an external package."
        )
    }

    @Test("The SafetyCore target declares an empty dependency list")
    func safetyCoreTargetHasNoDependencies() throws {
        let manifest = try Self.manifestSource()
        #expect(manifest.contains("name: \"SafetyCore\","))
        #expect(manifest.contains("dependencies: []"))
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
