import DriverAPI

/// Which authorization handshake a Tandem pump expects (FR-5).
///
/// Chosen from the code's length alone, never asked of the user: pumps on
/// current firmware show a short code and run EC-JPAKE; older firmware shows
/// a longer code and runs the legacy HMAC-SHA1 challenge.
public enum TandemHandshake: Sendable {
    case modern
    case legacy

    /// Longest code, in characters, that selects the modern handshake.
    static let modernMaximumLength = 10

    public init(for code: PairingCode) {
        self = code.characterCount <= Self.modernMaximumLength ? .modern : .legacy
    }
}
