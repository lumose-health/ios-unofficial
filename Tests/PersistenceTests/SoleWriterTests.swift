import Foundation
import SafetyCore
import Testing
@testable import Persistence

/// One writer connection per database file, enforced rather than asked for.
///
/// The rule is not decoration. Two writer connections on one file would resolve a
/// collision against rows the other has not committed yet: the higher-precedence
/// source would lose intermittently, on a schedule nobody can reproduce from a bug
/// report.
@Suite("Sole writer")
struct SoleWriterTests {

    private let clock = FixedClock(now: instant())

    /// The choice made here, stated as a test: a second open SHARES the writer
    /// rather than failing. An app opens its store on launch, and a scene, an
    /// extension entry point or a harness can all reasonably ask again — refusing
    /// would push every caller into building a singleton of its own, which is this
    /// problem moved rather than solved.
    @Test("Two opens of the same path share one writer connection")
    func secondOpenSharesTheWriter() async throws {
        let location = TemporaryStoreLocation()
        let first = try await LocalStore.open(at: location.databaseURL, clock: clock)
        let second = try await LocalStore.open(at: location.databaseURL, clock: clock)

        #expect(first.writerIdentity == second.writerIdentity)
    }

    /// The same file reached by two spellings of one path is one file, and must be
    /// one writer. The second spelling is built here, as a symlink to the store's
    /// directory, so the aliasing is real on every host rather than an accident of
    /// where the temporary directory happens to live.
    @Test("A path spelled two ways is still one writer")
    func symlinkedPathsShareTheWriter() async throws {
        let location = TemporaryStoreLocation()
        let first = try await LocalStore.open(at: location.databaseURL, clock: clock)

        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceTests-alias-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: location.directory)
        defer { try? FileManager.default.removeItem(at: link) }
        let second = try await LocalStore.open(
            at: link.appendingPathComponent("store.sqlite"),
            clock: clock
        )

        #expect(first.writerIdentity == second.writerIdentity)
    }

    /// Sharing a connection has to mean sharing the data, not just the object: a
    /// write through one handle is visible through the other with nothing in
    /// between.
    @Test("A write through one handle is immediately visible through the other")
    func sharedWriterSharesData() async throws {
        let location = TemporaryStoreLocation()
        let first = try await LocalStore.open(at: location.databaseURL, clock: clock)
        let second = try await LocalStore.open(at: location.databaseURL, clock: clock)

        let reading = try sample(120, at: instant())
        try await first.record(reading, from: try source("pump"))
        #expect(try await second.glucoseReadings().map(\.sample) == [reading])
    }

    /// Two different files get two writers — otherwise the assertions above would
    /// pass on a registry that handed out one connection for everything.
    @Test("Two different files get two writers")
    func differentPathsGetDifferentWriters() async throws {
        let one = TemporaryStoreLocation()
        let other = TemporaryStoreLocation()
        let first = try await LocalStore.open(at: one.databaseURL, clock: clock)
        let second = try await LocalStore.open(at: other.databaseURL, clock: clock)

        #expect(first.writerIdentity != second.writerIdentity)
    }

    /// The precedence order and the clock belong to the store value, not to the
    /// connection — so sharing a writer does not silently hand a caller somebody
    /// else's collision rule.
    @Test("A shared writer does not share the precedence order")
    func sharedWriterKeepsItsOwnPrecedence() async throws {
        let location = TemporaryStoreLocation()
        let pumpFirst = try await LocalStore.open(
            at: location.databaseURL,
            clock: clock,
            precedence: try SourcePrecedence(order: [try source("pump"), try source("cloud")])
        )
        let cloudFirst = try await LocalStore.open(
            at: location.databaseURL,
            clock: clock,
            precedence: try SourcePrecedence(order: [try source("cloud"), try source("pump")])
        )

        try await pumpFirst.record(try sample(120, at: instant()), from: try source("pump"))
        try await cloudFirst.record(try sample(180, at: instant()), from: try source("cloud"))

        #expect(try await pumpFirst.glucoseReadings().first?.source == (try source("cloud")))
    }
}
