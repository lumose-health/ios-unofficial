import CryptoKit
import Foundation

/// Cargo layouts and MACs for the last two EC-JPAKE exchanges: the session key
/// request and key confirmation. Mirrors the Android client's
/// `JpakeAuthenticator.kt`.
///
/// Cargo layouts:
///   session key request     app instance ID
///   session key response    app instance ID, pump nonce, reserved
///   key confirmation        app instance ID, nonce, reserved, HMAC-SHA256 digest
///
/// The confirmation key is HKDF-SHA256 with the pump's session-key nonce as
/// salt, the EC-JPAKE derived secret as input and empty info. Each side's
/// digest is HMAC-SHA256 of its own key-confirmation nonce under that key.
///
/// No recorded vectors exist for these steps; the tests prove the layouts and
/// MAC wiring against RFC cases and a simulated pump, not Android parity.
enum TandemKeyConfirmation {
    /// The app instance ID, little-endian. The Android client always sends 1.
    static let appInstanceID: [UInt8] = [1, 0]
    static let nonceSize = 8
    static let reservedSize = 8
    static let digestSize = SHA256.byteCount
    static let confirmationKeySize = SHA256.byteCount

    /// Offset of the nonce in every cargo here.
    private static let nonceOffset = appInstanceID.count
    /// Offset of the digest in a key-confirmation cargo.
    private static let digestOffset = appInstanceID.count + nonceSize + reservedSize
    /// Shortest session key response accepted.
    static let sessionKeyResponseSize = appInstanceID.count + nonceSize + reservedSize
    /// Size of a key-confirmation cargo, in either direction.
    static let keyConfirmationSize = digestOffset + digestSize

    /// Cargo of the session key request.
    static func sessionKeyRequestCargo() -> [UInt8] { appInstanceID }

    /// The pump's nonce from a session key response, or `nil` when the cargo
    /// is too short. Longer cargo is accepted, as on Android.
    static func pumpNonce(fromSessionKeyResponse cargo: [UInt8]) -> [UInt8]? {
        guard cargo.count >= sessionKeyResponseSize else { return nil }
        return Array(cargo[nonceOffset..<nonceOffset + nonceSize])
    }

    /// HKDF-SHA256(salt: pump nonce, input: derived secret, info: empty), 32 bytes.
    static func confirmationKey(derivedSecret: [UInt8], pumpNonce: [UInt8]) -> SymmetricKey? {
        guard pumpNonce.count == nonceSize else { return nil }
        return hkdf(inputKeyMaterial: derivedSecret, salt: pumpNonce, info: [], outputByteCount: confirmationKeySize)
    }

    /// The key-confirmation request: instance ID, `clientNonce`, zeroed reserved
    /// bytes, HMAC-SHA256(key, clientNonce). `nil` when the nonce is the wrong size.
    static func keyConfirmationCargo(clientNonce: [UInt8], key: SymmetricKey) -> [UInt8]? {
        guard clientNonce.count == nonceSize else { return nil }
        let digest = HMAC<SHA256>.authenticationCode(for: clientNonce, using: key)
        return appInstanceID + clientNonce + [UInt8](repeating: 0, count: reservedSize) + Array(digest)
    }

    /// Whether the pump's key-confirmation response carries HMAC-SHA256(key, its
    /// nonce), checked in constant time by CryptoKit. A short cargo is rejected.
    ///
    /// Both sides send the same layout keyed by the same key, so a device that
    /// does not know the code could otherwise pass this check by sending the
    /// phone's own key-confirmation cargo straight back. A response whose nonce
    /// equals `clientNonce` is therefore rejected.
    ///
    /// A `false` here means the code was wrong (or the response was reflected)
    /// and is reported as `PairingRejection.codeRejected`.
    static func pumpConfirmationIsValid(_ cargo: [UInt8], key: SymmetricKey, clientNonce: [UInt8]) -> Bool {
        guard cargo.count >= keyConfirmationSize, clientNonce.count == nonceSize else { return false }
        let nonce = Array(cargo[nonceOffset..<nonceOffset + nonceSize])
        // Nonces travel in the clear, so an ordinary comparison leaks nothing.
        guard nonce != clientNonce else { return false }
        let digest = cargo[digestOffset..<digestOffset + digestSize]
        return HMAC<SHA256>.isValidAuthenticationCode(Data(digest), authenticating: Data(nonce), using: key)
    }

    /// The HKDF this file uses, separated so its wiring can be checked against
    /// RFC 5869 directly.
    static func hkdf(inputKeyMaterial: [UInt8], salt: [UInt8], info: [UInt8], outputByteCount: Int) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
            salt: salt, info: info, outputByteCount: outputByteCount
        )
    }
}
