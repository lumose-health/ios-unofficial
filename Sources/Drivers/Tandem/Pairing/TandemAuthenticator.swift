import CryptoKit
import DriverAPI
import TandemWire

/// A byte-only authorization handshake. The caller transports each request and
/// passes its matching response; no radio or device command is owned here.
///
/// Any rejection ends the handshake: the state is terminal and all secret
/// material is cleared. A new attempt needs a new authenticator.
///
/// A reference type, so that there is one set of secrets for `reset()` and
/// `deinit` to clear rather than one per value copy. The `PairingCode` the
/// caller passed in, and a `derivedSecret` the caller has read, are the
/// caller's to manage.
final class TandemAuthenticator {
    /// One request to transport. `cargo` is readable because it must be sent, but
    /// it never appears in a rendering: a legacy pump request carries an HMAC of
    /// the code, which would allow offline guessing if logged.
    struct Request {
        let kind: TandemAuthorizationRequest
        let cargo: [UInt8]
    }

    private enum Stage: Equatable {
        case ready1a, waiting1a, ready1b, waiting1b, ready2, waiting2
        case ready3, waiting3, ready4, waiting4
        case readyCentral, waitingCentral, readyPump, waitingPump, complete, failed
    }

    private var stage: Stage
    private var codeBytes: [UInt8] = []
    private var arithmetic: EcJpake?
    private var ownRound1: [UInt8] = []
    private var peerRound1: [UInt8] = []
    private var derived: [UInt8] = []
    private var confirmationKey: SymmetricKey?
    private var clientNonce: [UInt8] = []
    private var legacyChallenge: [UInt8] = []
    private var legacyInstance: UInt16 = 0
    private var legacyHMACKey: [UInt8] = []
    private let randomBytes: EcJpake.RandomBytes

    init(code: PairingCode, randomBytes: @escaping EcJpake.RandomBytes = EcJpake.systemRandomBytes) throws(DriverFailure) {
        self.randomBytes = randomBytes
        if TandemHandshake(for: code) == .modern {
            stage = .ready1a
            do { arithmetic = try EcJpake(role: .client, secret: code.utf8Bytes, randomBytes: randomBytes) }
            catch { throw .pairingRejected(.secureHandshakeRejected) }
        } else {
            stage = .readyCentral
            codeBytes = code.utf8Bytes
        }
    }

    deinit { clearAllMaterial() }

    /// True only after the pump's response was verified.
    var isComplete: Bool { stage == .complete }
    /// True after a rejection or `reset()`.
    var hasFailed: Bool { stage == .failed }
    /// The secret for a completed modern handshake. A legacy handshake has none.
    var derivedSecret: [UInt8]? { stage == .complete && !derived.isEmpty ? derived : nil }

    /// Names of the fields still holding handshake material. Names only, never values.
    var heldMaterial: [String] {
        var held: [String] = []
        if !codeBytes.isEmpty { held.append("code") }
        if arithmetic != nil { held.append("arithmetic") }
        if !ownRound1.isEmpty { held.append("ownRound1") }
        if !peerRound1.isEmpty { held.append("peerRound1") }
        if !derived.isEmpty { held.append("derivedSecret") }
        if confirmationKey != nil { held.append("confirmationKey") }
        if !clientNonce.isEmpty { held.append("clientNonce") }
        if !legacyChallenge.isEmpty { held.append("legacyChallenge") }
        if !legacyHMACKey.isEmpty { held.append("legacyHMACKey") }
        return held
    }

    func nextRequest() throws -> Request {
        do { return try buildRequest() } catch { throw reject(error) }
    }

    func consume(_ cargo: [UInt8], for responseTo: TandemAuthorizationRequest) throws {
        do { try advance(cargo, for: responseTo) } catch { throw reject(error) }
    }

    func reset() {
        clearAllMaterial()
        stage = .failed
    }

    private func buildRequest() throws -> Request {
        switch stage {
        case .ready1a:
            guard let arithmetic else { throw EcJpakeError.invalidState }
            ownRound1 = try arithmetic.round1()
            stage = .waiting1a
            return Request(kind: .jpake1a, cargo: TandemKeyConfirmation.appInstanceID + Array(ownRound1.prefix((EcJpakeRound1.encodedSize / 2))))
        case .ready1b:
            stage = .waiting1b
            return Request(kind: .jpake1b, cargo: TandemKeyConfirmation.appInstanceID + Array(ownRound1.dropFirst((EcJpakeRound1.encodedSize / 2))))
        case .ready2:
            guard let arithmetic else { throw EcJpakeError.invalidState }
            let payload = try arithmetic.round2()
            stage = .waiting2
            return Request(kind: .jpake2, cargo: TandemKeyConfirmation.appInstanceID + payload)
        case .ready3:
            stage = .waiting3
            return Request(kind: .jpake3, cargo: TandemKeyConfirmation.sessionKeyRequestCargo())
        case .ready4:
            clientNonce = try randomBytes(TandemKeyConfirmation.nonceSize)
            guard let confirmationKey, let cargo = TandemKeyConfirmation.keyConfirmationCargo(clientNonce: clientNonce, key: confirmationKey) else { throw EcJpakeError.invalidRandomness }
            stage = .waiting4
            return Request(kind: .jpake4, cargo: cargo)
        case .readyCentral:
            let instanceBytes = try randomBytes(TandemLegacyHandshake.appInstanceIDSize)
            guard instanceBytes.count == TandemLegacyHandshake.appInstanceIDSize else { throw EcJpakeError.invalidRandomness }
            legacyInstance = UInt16(instanceBytes[0]) | UInt16(instanceBytes[1]) << 8
            legacyChallenge = try randomBytes(TandemLegacyHandshake.challengeSize)
            guard let cargo = TandemLegacyHandshake.centralChallengeCargo(appInstanceID: legacyInstance, challenge: legacyChallenge) else { throw EcJpakeError.invalidRandomness }
            stage = .waitingCentral
            return Request(kind: .centralChallenge, cargo: cargo)
        case .readyPump:
            guard let code = PairingCode(String(decoding: codeBytes, as: UTF8.self)),
                  let cargo = TandemLegacyHandshake.pumpChallengeCargo(appInstanceID: legacyInstance, code: code, hmacKey: legacyHMACKey)
            else { throw EcJpakeError.invalidState }
            stage = .waitingPump
            return Request(kind: .pumpChallenge, cargo: cargo)
        default: throw DriverFailure.pairingRejected(.secureHandshakeRejected)
        }
    }

    private func advance(_ cargo: [UInt8], for responseTo: TandemAuthorizationRequest) throws {
        switch (stage, responseTo) {
        case (.waiting1a, .jpake1a), (.waiting1b, .jpake1b):
            let expected = TandemKeyConfirmation.appInstanceID.count + (EcJpakeRound1.encodedSize / 2)
            guard cargo.count >= expected, Array(cargo.prefix(TandemKeyConfirmation.appInstanceID.count)) == TandemKeyConfirmation.appInstanceID else { throw EcJpakeError.malformedPayload }
            peerRound1 += cargo[TandemKeyConfirmation.appInstanceID.count..<expected]
            if stage == .waiting1a { stage = .ready1b }
            else {
                guard let arithmetic else { throw EcJpakeError.invalidState }
                _ = try arithmetic.readRound1(peerRound1)
                stage = .ready2
            }
        case (.waiting2, .jpake2):
            let expected = TandemKeyConfirmation.appInstanceID.count + EcJpakeRound2.encodedSize(from: .server)
            guard cargo.count >= expected, Array(cargo.prefix(TandemKeyConfirmation.appInstanceID.count)) == TandemKeyConfirmation.appInstanceID,
                  let arithmetic else { throw EcJpakeError.malformedPayload }
            _ = try arithmetic.readRound2(Array(cargo[TandemKeyConfirmation.appInstanceID.count..<expected]))
            derived = try arithmetic.deriveSecret()
            arithmetic.reset()
            self.arithmetic = nil
            stage = .ready3
        case (.waiting3, .jpake3):
            guard let nonce = TandemKeyConfirmation.pumpNonce(fromSessionKeyResponse: cargo),
                  Array(cargo.prefix(TandemKeyConfirmation.appInstanceID.count)) == TandemKeyConfirmation.appInstanceID,
                  let key = TandemKeyConfirmation.confirmationKey(derivedSecret: derived, pumpNonce: nonce)
            else { throw EcJpakeError.malformedPayload }
            confirmationKey = key; stage = .ready4
        case (.waiting4, .jpake4):
            guard cargo.count >= TandemKeyConfirmation.keyConfirmationSize,
                  Array(cargo.prefix(TandemKeyConfirmation.appInstanceID.count)) == TandemKeyConfirmation.appInstanceID
            else { throw EcJpakeError.malformedPayload }
            guard let confirmationKey, TandemKeyConfirmation.pumpConfirmationIsValid(cargo, key: confirmationKey, clientNonce: clientNonce) else {
                throw DriverFailure.pairingRejected(.codeRejected)
            }
            stage = .complete
            clearWorkingMaterial()
        case (.waitingCentral, .centralChallenge):
            // The challenge hash is parsed but not verified: no confirmed formula
            // exists for it, and validation against pump hardware is pending.
            guard let response = TandemLegacyHandshake.parseCentralChallengeResponse(cargo), response.appInstanceID == legacyInstance else { throw EcJpakeError.malformedPayload }
            legacyHMACKey = response.hmacKey; stage = .readyPump
        case (.waitingPump, .pumpChallenge):
            guard cargo.count >= TandemLegacyHandshake.pumpChallengeResponseSize,
                  UInt16(cargo[0]) | UInt16(cargo[1]) << 8 == legacyInstance,
                  let outcome = TandemLegacyHandshake.parsePumpChallengeResponse(cargo)
            else { throw EcJpakeError.malformedPayload }
            guard outcome == .accepted else { throw DriverFailure.pairingRejected(.codeRejected) }
            stage = .complete
            clearWorkingMaterial()
        default: throw DriverFailure.pairingRejected(.secureHandshakeRejected)
        }
    }

    /// Ends the handshake and returns the category to report. A verified
    /// success stands: a stray message after it is refused without undoing it.
    private func reject(_ error: any Error) -> DriverFailure {
        if stage != .complete {
            clearAllMaterial()
            stage = .failed
        }
        do { throw error }
        catch let failure as DriverFailure { return failure }
        catch EcJpakeError.zkpValidationFailed { return .pairingRejected(.codeRejected) }
        catch { return .pairingRejected(.secureHandshakeRejected) }
    }

    private func clearWorkingMaterial() {
        arithmetic?.reset()
        arithmetic = nil
        codeBytes.wipe(); ownRound1.wipe(); peerRound1.wipe()
        clientNonce.wipe(); legacyChallenge.wipe(); legacyHMACKey.wipe()
        confirmationKey = nil
    }

    private func clearAllMaterial() {
        clearWorkingMaterial()
        derived.wipe()
    }
}

extension TandemAuthenticator.Request: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "Tandem request \(kind)" }
    var debugDescription: String { "Tandem request \(kind)" }
    var customMirror: Mirror { Mirror(self, children: ["kind": kind], displayStyle: .struct) }
}

extension TandemAuthenticator: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "Tandem authenticator" }
    var debugDescription: String { "Tandem authenticator" }
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .class) }
}
