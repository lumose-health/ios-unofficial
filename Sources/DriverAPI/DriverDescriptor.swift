import Foundation

/// A Driver's reverse-domain identity, e.g. `com.glycemicgpt.tandem`.
///
/// The same string doubles as the Driver's settings-suite name and its Keychain
/// service name, so two Drivers sharing an identifier share credentials. It is a
/// distinct type rather than a `String` for that reason: a bare string is easy to
/// pass where a display name was meant.
public struct DriverIdentifier: Hashable, Sendable, CustomStringConvertible {

    public let rawValue: String

    /// Creates an identifier from a reverse-domain string, or `nil` when the
    /// string is not one.
    ///
    /// Failable rather than lenient because the identifier is a NAMESPACE: two
    /// Drivers whose identifiers collapse to the same degenerate value (empty,
    /// whitespace, a bare word) would share a settings suite and a Keychain
    /// service without either of them naming the other. The shape required is
    /// the one the doc line above promises: at least two labels joined by `.`,
    /// each label non-empty and made of letters, digits and `-`. Nothing is
    /// trimmed — an identifier that needed trimming was assembled wrong
    /// somewhere worth hearing about.
    public init?(_ rawValue: String) {
        let labels = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty,
                  label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            else { return nil }
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// How a Driver reaches whatever it is reading from.
///
/// Rendered as the "Protocol" column on the Drivers screen. It is closed on
/// purpose: a transport this list does not name is a new class of background
/// behaviour, and background behaviour is what the Coverage Claim rests on
/// (AD-11).
public enum DriverTransport: String, CaseIterable, Hashable, Sendable {

    /// Direct Bluetooth Low Energy to the device.
    case bluetoothLowEnergy

    /// An HTTP service — an app-hosted Nightscout source, a sync destination.
    case network

    /// No device and no network: the Simulated and Trace-Replay Drivers.
    case inProcess
}

/// How much a Driver has actually been proven against the hardware it names
/// (FR-22).
///
/// This is the vocabulary the Drivers screen shows the user VERBATIM. It is never
/// inferred, never computed from whether the Driver is currently connected, and
/// never upgraded by a Driver about itself — a Driver claiming its own
/// verification is a Driver marking its own homework.
///
/// The wording tracks the Android README's device table ("Protocol-compatible
/// (unverified on hardware)", "Beta, read-only, unverified on hardware") so a
/// user reading both projects sees one claim, not two.
public enum VerificationStatus: String, CaseIterable, Hashable, Sendable {

    /// Never exercised against the device it names, in any form. The honest
    /// default: a new Driver starts here.
    case unverified

    /// Implements the documented protocol and passes its own tests, but has not
    /// been run against real hardware by anyone.
    case protocolCompatible

    /// Exercised on real hardware, with known gaps — the state the Medtronic
    /// Driver ships in.
    case beta

    /// Exercised on real hardware across the whole Capability set it claims.
    case hardwareVerified
}

/// Everything the platform knows about a Driver without instantiating it.
///
/// Compile-time metadata: an entry in ``DriverCatalog`` is written by hand, in
/// the same change that adds the Driver's target, and `driver_guards.sh` fails
/// the build if a target under `Sources/Drivers/` has no entry here.
///
/// ``targetName`` is what makes that check mechanical rather than a matter of
/// opinion — it is the SPM target name, so the guard can match an entry to a
/// manifest declaration by string equality instead of guessing from a display
/// name somebody localised.
public struct DriverDescriptor: Hashable, Sendable, Identifiable {

    /// The reverse-domain identity. Doubles as settings suite and Keychain service.
    public var id: DriverIdentifier { identifier }

    /// The reverse-domain identity.
    public let identifier: DriverIdentifier

    /// The SPM target name under `Sources/Drivers/`, e.g. `"Tandem"`.
    ///
    /// The link between this catalog and the package manifest. See
    /// `scripts/guards/driver_guards.sh`.
    public let targetName: String

    /// What the user sees, e.g. `"Tandem Insulin Pump"`.
    public let displayName: String

    /// How it reaches the device. Rendered as the Protocol column.
    public let transport: DriverTransport

    /// The Driver's own semantic version, e.g. `"1.0.0"`.
    public let version: String

    /// Exactly what this Driver provides, from the closed set of six.
    ///
    /// A claim, and a checkable one: a Driver whose ``Driver/capability(_:)``
    /// returns `nil` for something listed here is a defect the platform surfaces
    /// as ``DriverFailure/capabilityUnavailable(_:)``.
    public let capabilities: Set<Capability>

    /// How far this Driver has been proven. Shown to the user verbatim.
    public let verification: VerificationStatus

    public init(
        identifier: DriverIdentifier,
        targetName: String,
        displayName: String,
        transport: DriverTransport,
        version: String,
        capabilities: Set<Capability>,
        verification: VerificationStatus
    ) {
        self.identifier = identifier
        self.targetName = targetName
        self.displayName = displayName
        self.transport = transport
        self.version = version
        self.capabilities = capabilities
        self.verification = verification
    }
}
