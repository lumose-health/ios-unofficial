import CryptoKit
import Foundation
import Testing
import DriverAPI
@testable import TandemDriver

/// No recorded Android vectors exist for handshake selection, the session-key
/// and key-confirmation steps, or the legacy handshake. These tests pin the
/// layouts to the Android client's source, the MAC and KDF wiring to RFC test
/// cases and values computed independently (Python `hmac`/`hashlib`), and the
/// confirmation exchange to a simulated pump.
@Suite("Tandem pairing message logic")
struct TandemPairingLogicTests {

    // MARK: Handshake selection

    @Test("Ten characters or fewer selects EC-JPAKE; eleven or more selects legacy")
    func handshakeSelection() throws {
        for (length, expected) in [(6, TandemHandshake.modern), (10, .modern), (11, .legacy), (16, .legacy)] {
            let code = try #require(PairingCode(String(repeating: "7", count: length)))
            #expect(TandemHandshake(for: code) == expected, "length \(length)")
        }
    }

    // MARK: Session key and key confirmation

    @Test("The HKDF wiring reproduces RFC 5869 test case 1")
    func hkdfRFC5869Case1() {
        let key = TandemKeyConfirmation.hkdf(
            inputKeyMaterial: [UInt8](repeating: 0x0b, count: 22),
            salt: Self.hex("000102030405060708090a0b0c"),
            info: Self.hex("f0f1f2f3f4f5f6f7f8f9"),
            outputByteCount: 42
        )
        let okm = key.withUnsafeBytes { Array($0) }
        #expect(okm == Self.hex(
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"))
    }

    @Test("The confirmation key salts with the pump nonce and keys with the derived secret")
    func confirmationKeyArgumentOrder() throws {
        // HKDF-SHA256(salt: 0x42 x 8, ikm: "123456", info: empty, L: 32), computed in Python.
        let key = try #require(TandemKeyConfirmation.confirmationKey(
            derivedSecret: Array("123456".utf8), pumpNonce: [UInt8](repeating: 0x42, count: 8)))
        #expect(key.withUnsafeBytes { Array($0) } ==
                Self.hex("f967768081d5a3bf14a8d39c195c831cdcfb392c28a8b45a1c4d76a0e43e4d5c"))
        #expect(TandemKeyConfirmation.confirmationKey(derivedSecret: [1], pumpNonce: [1, 2]) == nil)
    }

    @Test("Session key request and response layouts")
    func sessionKeyLayouts() {
        #expect(TandemKeyConfirmation.sessionKeyRequestCargo() == [1, 0])
        let nonce: [UInt8] = [9, 8, 7, 6, 5, 4, 3, 2]
        let response = [UInt8]([1, 0]) + nonce + [UInt8](repeating: 0xEE, count: 8)
        #expect(TandemKeyConfirmation.pumpNonce(fromSessionKeyResponse: response) == nonce)
        #expect(TandemKeyConfirmation.pumpNonce(fromSessionKeyResponse: response + [0xFF]) == nonce)
        #expect(TandemKeyConfirmation.pumpNonce(fromSessionKeyResponse: Array(response.dropLast())) == nil)
        #expect(TandemKeyConfirmation.pumpNonce(fromSessionKeyResponse: []) == nil)
    }

    @Test("Key confirmation cargo: instance ID, nonce, zeroed reserved, HMAC-SHA256 digest")
    func keyConfirmationLayout() throws {
        let key = SymmetricKey(data: Self.hex("f967768081d5a3bf14a8d39c195c831cdcfb392c28a8b45a1c4d76a0e43e4d5c"))
        let clientNonce = [UInt8](repeating: 0x24, count: 8)
        let cargo = try #require(TandemKeyConfirmation.keyConfirmationCargo(clientNonce: clientNonce, key: key))
        #expect(cargo.count == 50)
        #expect(Array(cargo[0..<2]) == [1, 0])
        #expect(Array(cargo[2..<10]) == clientNonce)
        #expect(Array(cargo[10..<18]) == [UInt8](repeating: 0, count: 8))
        // HMAC-SHA256(key, 0x24 x 8), computed in Python.
        #expect(Array(cargo[18..<50]) ==
                Self.hex("d702cc1b5e3e48858863f45518da48915d763ea6d81615e48302713ef2f711fd"))
        #expect(TandemKeyConfirmation.keyConfirmationCargo(clientNonce: [1], key: key) == nil)
    }

    @Test("A simulated pump's confirmation is accepted, and any flipped bit is rejected")
    func simulatedPumpConfirmation() throws {
        let phoneNonce = [UInt8](repeating: 0x33, count: 8)
        let derivedSecret = [UInt8](repeating: 0x5C, count: 32)
        let sessionNonce: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let phoneKey = try #require(TandemKeyConfirmation.confirmationKey(
            derivedSecret: derivedSecret, pumpNonce: sessionNonce))

        // The pump derives its own key independently and confirms its own nonce.
        let pumpKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: derivedSecret), salt: sessionNonce,
            info: [UInt8](), outputByteCount: 32)
        let pumpNonce: [UInt8] = [0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7]
        let pumpDigest = Array(HMAC<SHA256>.authenticationCode(for: pumpNonce, using: pumpKey))
        let pumpCargo = [UInt8]([1, 0]) + pumpNonce + [UInt8](repeating: 0, count: 8) + pumpDigest

        #expect(TandemKeyConfirmation.pumpConfirmationIsValid(pumpCargo, key: phoneKey, clientNonce: phoneNonce))

        // One flipped bit in the nonce or in the digest fails.
        for index in [2, 9, pumpCargo.count - 32, pumpCargo.count - 1] {
            var corrupt = pumpCargo
            corrupt[index] ^= 0x01
            #expect(!TandemKeyConfirmation.pumpConfirmationIsValid(corrupt, key: phoneKey, clientNonce: phoneNonce), "byte \(index)")
        }

        // A different secret (the wrong code) fails.
        let wrongKey = try #require(TandemKeyConfirmation.confirmationKey(
            derivedSecret: [UInt8](repeating: 0x5D, count: 32), pumpNonce: sessionNonce))
        #expect(!TandemKeyConfirmation.pumpConfirmationIsValid(pumpCargo, key: wrongKey, clientNonce: phoneNonce))

        // Short cargo fails.
        #expect(!TandemKeyConfirmation.pumpConfirmationIsValid(Array(pumpCargo.dropLast()), key: phoneKey, clientNonce: phoneNonce))
        #expect(!TandemKeyConfirmation.pumpConfirmationIsValid([], key: phoneKey, clientNonce: phoneNonce))
    }

    @Test("The phone's own confirmation sent back is rejected, even though its MAC is valid")
    func reflectedConfirmationIsRejected() throws {
        let key = try #require(TandemKeyConfirmation.confirmationKey(
            derivedSecret: [UInt8](repeating: 0x5C, count: 32), pumpNonce: [1, 2, 3, 4, 5, 6, 7, 8]))
        let phoneNonce: [UInt8] = [0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17]
        let phoneCargo = try #require(TandemKeyConfirmation.keyConfirmationCargo(clientNonce: phoneNonce, key: key))
        #expect(!TandemKeyConfirmation.pumpConfirmationIsValid(phoneCargo, key: key, clientNonce: phoneNonce))

        // Altering only the reserved bytes does not get a reflection past the check.
        var tweaked = phoneCargo
        tweaked[10] ^= 0xFF
        #expect(!TandemKeyConfirmation.pumpConfirmationIsValid(tweaked, key: key, clientNonce: phoneNonce))

        // A genuine pump confirmation under the same key, with its own nonce, passes.
        let pumpNonce: [UInt8] = [0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7]
        let pumpCargo = try #require(TandemKeyConfirmation.keyConfirmationCargo(clientNonce: pumpNonce, key: key))
        #expect(TandemKeyConfirmation.pumpConfirmationIsValid(pumpCargo, key: key, clientNonce: phoneNonce))
        // A malformed client nonce fails closed.
        #expect(!TandemKeyConfirmation.pumpConfirmationIsValid(pumpCargo, key: key, clientNonce: [1]))
    }

    // MARK: Legacy handshake

    @Test("The legacy HMAC wiring reproduces RFC 2202 HMAC-SHA1 test case 2")
    func legacyHMACRFC2202() {
        // Distinct key and data, so swapping them fails.
        let digest = TandemLegacyHandshake.hmacSHA1(
            key: Array("Jefe".utf8), data: Array("what do ya want for nothing?".utf8))
        #expect(digest == Self.hex("effcdf6ae5eb2fa2d27416d5f184df9c259a7c79"))
    }

    @Test("Central challenge request and response layouts")
    func centralChallenge() throws {
        let challenge: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        #expect(TandemLegacyHandshake.centralChallengeCargo(appInstanceID: 0xBEEF, challenge: challenge) ==
                [0xEF, 0xBE] + challenge)
        #expect(TandemLegacyHandshake.centralChallengeCargo(appInstanceID: 1, challenge: [1]) == nil)

        let hash = [UInt8](repeating: 0xC3, count: Insecure.SHA1.byteCount)
        let hmacKey: [UInt8] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
        let response = [UInt8]([0xEF, 0xBE]) + hash + hmacKey
        #expect(response.count == 30)
        let parsed = try #require(TandemLegacyHandshake.parseCentralChallengeResponse(response))
        #expect(parsed.appInstanceID == 0xBEEF)
        #expect(parsed.challengeHash == hash)
        #expect(parsed.hmacKey == hmacKey)
        #expect(TandemLegacyHandshake.parseCentralChallengeResponse(response + [0]) == parsed)
        #expect(TandemLegacyHandshake.parseCentralChallengeResponse(Array(response.dropLast())) == nil)
        #expect(TandemLegacyHandshake.parseCentralChallengeResponse([]) == nil)
    }

    @Test("The pump challenge request is HMAC-SHA1 keyed by the code bytes over the pump's HMAC key")
    func pumpChallengeRequest() throws {
        let code = try #require(PairingCode("123456"))
        let cargo = try #require(TandemLegacyHandshake.pumpChallengeCargo(
            appInstanceID: 0x0102, code: code, hmacKey: [1, 2, 3, 4, 5, 6, 7, 8]))
        // HMAC-SHA1(key: "123456", data: 01..08), computed in Python.
        #expect(cargo == [0x02, 0x01] + Self.hex("d174efaa8af3dba63ab6895653dbbe0d098f9553"))
        #expect(TandemLegacyHandshake.pumpChallengeCargo(appInstanceID: 1, code: code, hmacKey: [1]) == nil)
    }

    @Test("The pump challenge response reports accepted only for success byte 1")
    func pumpChallengeResponse() {
        #expect(TandemLegacyHandshake.parsePumpChallengeResponse([0, 0, 1]) == .accepted)
        #expect(TandemLegacyHandshake.parsePumpChallengeResponse([0, 0, 0]) == .rejected)
        #expect(TandemLegacyHandshake.parsePumpChallengeResponse([0, 0, 2]) == .rejected)
        #expect(TandemLegacyHandshake.parsePumpChallengeResponse([0, 0]) == nil)
        #expect(TandemLegacyHandshake.parsePumpChallengeResponse([]) == nil)
    }

    private static func hex(_ value: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            bytes.append(UInt8(value[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }
}
