import Foundation

/// Where a ``DataSync`` Driver mirrors data to.
///
/// The destination is DECLARED by the Driver and rendered to the user; it is not
/// something the platform sets. A user who cannot see where their glucose history
/// is being copied cannot consent to it.
public struct SyncDestination: Hashable, Sendable {

    /// The service as the user knows it, e.g. "Nightscout".
    public let serviceName: String

    /// The host the Driver mirrors to, without scheme, credentials or path.
    ///
    /// Host only, deliberately: a full URL carries an API secret often enough
    /// that rendering one is a credential-disclosure bug waiting for a
    /// screenshot (SI-9).
    public let host: String

    /// Creates a destination, or `nil` when `host` is not a bare host.
    ///
    /// `host` may carry a port (`nightscout.example:1337`); it may not be
    /// empty and may not carry a scheme, credentials, a path, a query or a
    /// fragment, so any of `/`, `@`, `?`, `#` or whitespace refuses the value.
    /// A colon is admitted ONLY as the port separator: at most one, with a
    /// non-empty host before it and only ASCII digits naming a port in
    /// `1...65535` after it. Anything else colon-shaped is refused —
    /// `https:nightscout.example`, `mailto:token` and `example.com:s3cr3t` are
    /// not hosts, and the last is a colon-delimited secret this type exists to
    /// keep off the screen.
    /// The refusal is the host-only contract enforced at the type rather than
    /// promised in a comment: `https://token@example.com/path` stored here
    /// would be rendered to the user, and rendering it is exactly the
    /// credential disclosure this field exists to make impossible (SI-9).
    public init?(serviceName: String, host: String) {
        guard !host.isEmpty,
              !host.contains(where: { "/@?#".contains($0) || $0.isWhitespace })
        else { return nil }
        let parts = host.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count > 1 {
            guard parts.count == 2,
                  !parts[0].isEmpty,
                  parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
                  let port = Int(parts[1]),
                  (1...65535).contains(port)
            else { return nil }
        }
        self.serviceName = serviceName
        self.host = host
    }
}

/// The kinds of record a ``DataSync`` Driver is willing to mirror.
///
/// A declaration, not a command: it tells the user and the platform what leaves
/// the device, before anything does.
public enum MirroredRecordKind: String, CaseIterable, Hashable, Sendable {
    case glucose
    case fingerstick
    case insulin
    case pumpStatus
}

/// What a ``DataSync`` Driver is currently doing.
///
/// ``failing`` carries the reason so the Drivers screen can say what broke
/// rather than showing an exclamation mark the user cannot act on (AD-13).
public enum SyncState: Hashable, Sendable {

    /// Nothing pending; the last attempt succeeded, or none has been made yet.
    case idle

    /// An attempt is in flight.
    case mirroring

    /// The last attempt failed and the Driver will retry.
    case failing(DriverFailure)

    /// The user has turned this destination off. No data leaves the device.
    case disabled
}
