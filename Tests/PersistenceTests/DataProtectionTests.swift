import Foundation
import SafetyCore
import Testing
@testable import Persistence

/// At-rest protection is the whole of the encryption posture here (AD-6, SI-10):
/// plain SQLite, and the platform's own file protection over it.
///
/// These gates run on macOS, where the protection attribute does not exist and
/// setting it is a no-op — so what is asserted is the store's INTENT, observed
/// through the seam it applies protection through. The attribute itself is
/// verified on a device; asserting it here would assert the host's silence.
@Suite("At-rest protection")
struct DataProtectionTests {

    private let clock = FixedClock(now: instant())

    /// `complete` is the option that must not be reachable: it makes the file
    /// unreadable whenever the device is locked, so a CGM sample arriving in a
    /// pocket fails to write — the reading the user needs most is the one dropped
    /// (FR-135, FR-136). It is absent from the vocabulary rather than avoided by
    /// convention.
    @Test("The store offers exactly one protection class, and it is not `complete`")
    func onlyOneProtectionClassExists() {
        #expect(StoreProtectionClass.allCases == [.completeUntilFirstUserAuthentication])
    }

    @Test("The database and its WAL and SHM siblings are all protected")
    func protectsTheDatabaseAndItsSiblings() async throws {
        let location = TemporaryStoreLocation()
        let recorder = RecordingFileProtection()
        _ = try await LocalStore.open(at: location.databaseURL, clock: clock, protection: recorder)

        let path = location.databaseURL.path
        let protected = Set(recorder.protectedPaths())
        #expect(protected.contains(path))
        #expect(protected.contains(path + "-wal"))
        #expect(protected.contains(path + "-shm"))
        #expect(
            recorder.applied.allSatisfy { $0.protection == .completeUntilFirstUserAuthentication },
            "every protected item must carry the same class: \(recorder.applied)"
        )
    }

    /// The directory comes first, and it matters that it does: on iOS a
    /// directory's class is the default for items created inside it, so the
    /// database file is protected from the instant SQLite creates it rather than
    /// from whenever the store gets around to it.
    @Test("The containing directory is protected before the database is created")
    func protectsTheDirectoryFirst() async throws {
        let location = TemporaryStoreLocation()
        let recorder = RecordingFileProtection()
        _ = try await LocalStore.open(at: location.databaseURL, clock: clock, protection: recorder)

        #expect(recorder.protectedPaths().first == location.directory.path)
    }

    /// The case the first-launch tests miss: every launch after the first, and any
    /// store living in a container something else made, finds the directory already
    /// there. Protecting it only when the store created it would leave it carrying
    /// whatever class that container had, and the sidecars SQLite makes later would
    /// inherit that instead of the store's own posture.
    @Test("A directory the store did not create is protected anyway")
    func protectsADirectoryItDidNotCreate() async throws {
        let location = TemporaryStoreLocation()
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let recorder = RecordingFileProtection()
        _ = try await LocalStore.open(at: location.databaseURL, clock: clock, protection: recorder)

        #expect(recorder.protectedPaths().first == location.directory.path)
    }

    /// And on the open after that, with the file already there too: the ordinary
    /// launch. A fresh recorder per open, so what is asserted is what THIS open
    /// asked for.
    @Test("A later open of an existing store protects the directory and the file again")
    func protectsOnEveryOpen() async throws {
        let location = TemporaryStoreLocation()
        _ = try await LocalStore.open(
            at: location.databaseURL,
            clock: clock,
            protection: RecordingFileProtection()
        )

        let recorder = RecordingFileProtection()
        _ = try await LocalStore.open(at: location.databaseURL, clock: clock, protection: recorder)

        let protected = recorder.protectedPaths()
        #expect(protected.first == location.directory.path)
        #expect(protected.contains(location.databaseURL.path))
        #expect(
            recorder.applied.allSatisfy { $0.protection == .completeUntilFirstUserAuthentication },
            "every protected item must carry the same class: \(recorder.applied)"
        )
    }

    /// A store that opened but could not be protected is worse than one that did
    /// not open: it works, so nobody looks at it again.
    @Test("A protection failure refuses the open")
    func refusesToOpenWhenProtectionFails() async throws {
        let location = TemporaryStoreLocation()
        let recorder = RecordingFileProtection()
        recorder.refusePathsEnding = "-wal"

        let failure = await #expect(throws: PersistenceFailure.self) {
            _ = try await LocalStore.open(at: location.databaseURL, clock: clock, protection: recorder)
        }
        guard case .protectionUnavailable(let path, _) = failure else {
            Issue.record("expected a protection failure, got \(String(describing: failure))")
            return
        }
        #expect(path.hasSuffix("-wal"))
    }

    /// The negative case above only means something if the same tree opens
    /// cleanly when protection succeeds.
    @Test("The same store opens when protection succeeds")
    func opensWhenProtectionSucceeds() async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(
            at: location.databaseURL,
            clock: clock,
            protection: RecordingFileProtection()
        )
        #expect(try await store.appliedMigrationIdentifiers() == ["v1"])
    }

    /// The public way in applies protection unconditionally: there is no parameter
    /// for it and no overload without one, so nothing outside this package can open
    /// a store that skips it.
    @Test("The public open applies protection with no way to opt out")
    func publicOpenHasNoProtectionParameter() async throws {
        let location = TemporaryStoreLocation()
        let store = try await LocalStore.open(at: location.databaseURL, clock: clock)
        #expect(try await store.appliedMigrationIdentifiers() == ["v1"])
    }
}
