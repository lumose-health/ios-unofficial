import CryptoKit
import DriverAPI

/// Cargo layouts for the legacy (pre-EC-JPAKE) Tandem handshake, used when the
/// pump shows a long code. Mirrors the Android client's `TandemAuthenticator.kt`
/// and `HmacHelper.kt`.
///
///   central challenge request   app instance ID, 8-byte challenge
///   central challenge response  instance ID echo, challenge hash (SHA-1 size), 8-byte HMAC key
///   pump challenge request      app instance ID, HMAC-SHA1(key: code bytes, data: HMAC key)
///   pump challenge response     instance ID echo, success byte (1 = accepted)
///
/// The app instance ID is the caller's choice; Android draws a random one per
/// attempt. All integers are little-endian.
///
/// No recorded vectors exist for this handshake; the tests check the HMAC
/// wiring against RFC 2202 and hand-computed values, not Android parity.
enum TandemLegacyHandshake {
    static let appInstanceIDSize = 2
    static let challengeSize = 8
    static let challengeHashSize = Insecure.SHA1.byteCount
    static let hmacKeySize = 8

    /// Shortest central challenge response accepted. Longer is accepted, as on Android.
    static let centralChallengeResponseSize = appInstanceIDSize + challengeHashSize + hmacKeySize
    /// Shortest pump challenge response accepted.
    static let pumpChallengeResponseSize = appInstanceIDSize + 1

    struct CentralChallengeResponse: Equatable, Sendable {
        let appInstanceID: UInt16
        let challengeHash: [UInt8]
        let hmacKey: [UInt8]
    }

    enum PumpChallengeOutcome: Equatable, Sendable {
        case accepted
        case rejected
    }

    static func centralChallengeCargo(appInstanceID: UInt16, challenge: [UInt8]) -> [UInt8]? {
        guard challenge.count == challengeSize else { return nil }
        return littleEndian(appInstanceID) + challenge
    }

    /// `nil` when the cargo is too short to hold every field.
    static func parseCentralChallengeResponse(_ cargo: [UInt8]) -> CentralChallengeResponse? {
        guard cargo.count >= centralChallengeResponseSize else { return nil }
        let hashEnd = appInstanceIDSize + challengeHashSize
        return CentralChallengeResponse(
            appInstanceID: UInt16(cargo[0]) | UInt16(cargo[1]) << 8,
            challengeHash: Array(cargo[appInstanceIDSize..<hashEnd]),
            hmacKey: Array(cargo[hashEnd..<hashEnd + hmacKeySize])
        )
    }

    /// The pump challenge request, keyed by the code's bytes (see
    /// ``DriverAPI/PairingCode/utf8Bytes`` for how they relate to Android's).
    static func pumpChallengeCargo(appInstanceID: UInt16, code: PairingCode, hmacKey: [UInt8]) -> [UInt8]? {
        guard hmacKey.count == hmacKeySize else { return nil }
        return littleEndian(appInstanceID) + hmacSHA1(key: code.utf8Bytes, data: hmacKey)
    }

    /// `nil` when the cargo is too short to hold the success byte.
    static func parsePumpChallengeResponse(_ cargo: [UInt8]) -> PumpChallengeOutcome? {
        guard cargo.count >= pumpChallengeResponseSize else { return nil }
        // The success byte is public, so a plain comparison is fine here.
        return cargo[appInstanceIDSize] == 1 ? .accepted : .rejected
    }

    static func hmacSHA1(key: [UInt8], data: [UInt8]) -> [UInt8] {
        Array(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private static func littleEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }
}
