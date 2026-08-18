import Foundation

/// The at-rest protection class the store applies to every file it owns (AD-6, SI-10).
///
/// ## Why there is exactly one case
///
/// The obvious second case would be iOS's `complete`, which is stronger: the file
/// is unreadable whenever the device is locked. That is the wrong answer here, and
/// not by a small margin — a CGM sample arriving in the background while the phone
/// is in a pocket would fail to write, so the reading the user needs most is the
/// one the store drops (FR-135, FR-136).
///
/// `completeUntilFirstUserAuthentication` keeps the file unreadable until the user
/// has unlocked the device once since boot, and readable thereafter — the same
/// posture the platform's own health data takes, and the one that survives a
/// background write.
///
/// So this vocabulary offers one value. An option nobody can select is an option
/// nobody selects by mistake, and the reasoning above lives here rather than in a
/// review comment on the day someone reaches for the stronger-sounding one.
enum StoreProtectionClass: String, CaseIterable, Hashable, Sendable {

    /// Unreadable until the device has been unlocked once since boot.
    case completeUntilFirstUserAuthentication
}

/// The seam through which the store applies at-rest protection.
///
/// ## Internal on purpose
///
/// Nothing in this file is public, and that is the whole design. Protection is not
/// a policy a consumer of the package chooses: the public way to open a store
/// applies it, full stop, and there is no parameter to hand it something that does
/// nothing. A seam that reached the public surface would be an opt-out, and an
/// opt-out taken once — in a scratch harness, in an extension somebody wrote in a
/// hurry — is an unprotected database carrying health data.
///
/// It stays a seam rather than a direct `FileManager` call for two reasons. The
/// store must be able to FAIL when protection cannot be applied — an unprotected
/// database that opens successfully is the failure nobody notices — and that path
/// has to be exercised. And the attribute itself is an iOS/watchOS concept: on
/// macOS, where the package's gates run, setting it is a no-op, so a test that
/// asserted the file's attribute would assert nothing. Tests reach the seam
/// through `@testable`; consumers cannot reach it at all.
protocol StoreFileProtecting: Sendable {

    /// Applies `protection` to the file or directory at `url`.
    ///
    /// - Throws: any error the platform raises. The store turns it into
    ///   ``PersistenceFailure/protectionUnavailable(path:detail:)`` and refuses to
    ///   open, rather than continuing with a file it could not protect.
    func protect(itemAt url: URL, as protection: StoreProtectionClass) throws
}

/// The shipping implementation: the platform's own file-protection attribute.
///
/// On iOS and watchOS this sets `NSFileProtectionKey`. On macOS the attribute does
/// not exist and this is a documented no-op — macOS is a build and test platform
/// for this package, not a shipping one, and pretending otherwise would mean
/// asserting a protection the host cannot provide.
struct SystemFileProtection: StoreFileProtecting {

    init() {}

    func protect(itemAt url: URL, as protection: StoreProtectionClass) throws {
        #if os(iOS) || os(watchOS) || os(tvOS)
        try FileManager.default.setAttributes(
            [.protectionKey: Self.attribute(for: protection)],
            ofItemAtPath: url.path
        )
        #endif
    }

    #if os(iOS) || os(watchOS) || os(tvOS)
    private static func attribute(for protection: StoreProtectionClass) -> FileProtectionType {
        switch protection {
        case .completeUntilFirstUserAuthentication:
            .completeUntilFirstUserAuthentication
        }
    }
    #endif
}
