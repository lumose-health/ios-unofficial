/// A pairing code exactly as the user entered it (FR-5).
///
/// Accepted when it is 6 to 16 characters long, counted in `Character`s
/// (grapheme clusters). Nothing else is checked here: no character-class
/// filtering, no trimming, no case folding. Whether the code is right is the
/// device's decision, made during the handshake.
///
/// The code is secret material (SI-9). `description`, `debugDescription` and
/// the reflection mirror never expose it, so string interpolation, `print` and
/// `dump` all show a fixed placeholder.
///
/// Two codes are equal only when their ``utf8Bytes`` are. `String` equality
/// would treat canonically equivalent spellings as one code, but those key
/// different handshakes.
public struct PairingCode: Hashable, Sendable {
    /// Shortest code accepted, in characters.
    public static let minimumLength = 6
    /// Longest code accepted, in characters.
    public static let maximumLength = 16

    private let value: String

    /// Returns `nil` when the length is outside
    /// ``minimumLength``...``maximumLength``. The string is kept verbatim.
    public init?(_ value: String) {
        guard (Self.minimumLength...Self.maximumLength).contains(value.count) else { return nil }
        self.value = value
    }

    /// Length in characters (grapheme clusters).
    public var characterCount: Int { value.count }

    /// The secret bytes a handshake is keyed with: the code's UTF-8 encoding.
    ///
    /// For an ASCII code this is byte-identical to the Android client, which
    /// encodes the code as US-ASCII. For a non-ASCII code the two differ:
    /// Android substitutes `?` for each non-ASCII character and this does not.
    /// No device code contains non-ASCII characters, so either encoding ends in
    /// the device rejecting the code.
    public var utf8Bytes: [UInt8] { Array(value.utf8) }

    public static func == (lhs: PairingCode, rhs: PairingCode) -> Bool {
        lhs.value.utf8.elementsEqual(rhs.value.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(utf8Bytes)
    }
}

extension PairingCode: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "pairing code" }
    public var debugDescription: String { "pairing code" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}
