import CryptoKit
import DriverAPI
import Foundation
import Testing
import TandemWire
@testable import TandemDriver

private let instanceID = TandemKeyConfirmation.appInstanceID
private let wrongInstanceID: [UInt8] = [2, 0]
private let round1Half = EcJpakeRound1.encodedSize / 2
private let secureRejection = DriverFailure.pairingRejected(.secureHandshakeRejected)
private let codeRejection = DriverFailure.pairingRejected(.codeRejected)

/// A source whose every draw differs, so a role's two public points differ too.
private func distinctDraws(startingAt first: UInt8) -> EcJpake.RandomBytes {
    var next = first
    return { count in
        defer { next += 1 }
        return [UInt8](repeating: next, count: count)
    }
}

/// Runs a real server role against the client, one step at a time. Steps
/// alternate between the client building a request and consuming a response.
private final class SimulatedPump {
    static let stepCount = 10
    /// The steps that consume a response, with the request each one answers.
    static let responseSteps: [(step: Int, kind: TandemAuthorizationRequest)] = [
        (1, .jpake1a), (3, .jpake1b), (5, .jpake2), (7, .jpake3), (9, .jpake4)
    ]

    let client: TandemAuthenticator
    let server: EcJpake
    var requests: [TandemAuthenticator.Request] = []
    var round1OnWire: [UInt8]
    var sentInstanceID = instanceID
    var serverSecret: [UInt8] = []
    private let pumpNonce = [UInt8](repeating: 0x51, count: TandemKeyConfirmation.nonceSize)

    init(clientCode: String = "123456", serverCode: String = "123456") throws {
        client = try TandemAuthenticator(code: try #require(PairingCode(clientCode)), randomBytes: distinctDraws(startingAt: 0x60))
        server = try EcJpake(role: .server, secret: Array(serverCode.utf8), randomBytes: distinctDraws(startingAt: 0x70))
        round1OnWire = try server.round1()
    }

    func run(steps count: Int) throws {
        for step in 0..<count { try perform(step: step) }
    }

    func perform(step: Int) throws {
        switch step {
        case 0, 2, 4, 6, 8:
            requests.append(try client.nextRequest())
        case 1:
            try client.consume(sentInstanceID + round1OnWire.prefix(round1Half), for: .jpake1a)
        case 3:
            _ = try server.readRound1(Array(requests[0].cargo.dropFirst(instanceID.count) + requests[1].cargo.dropFirst(instanceID.count)))
            try client.consume(sentInstanceID + round1OnWire.dropFirst(round1Half), for: .jpake1b)
        case 5:
            let serverRound2 = try server.round2()
            _ = try server.readRound2(Array(requests[2].cargo.dropFirst(instanceID.count)))
            serverSecret = try server.deriveSecret()
            try client.consume(sentInstanceID + serverRound2, for: .jpake2)
        case 7:
            try client.consume(sentInstanceID + pumpNonce + [UInt8](repeating: 0, count: TandemKeyConfirmation.reservedSize), for: .jpake3)
        default:
            let key = try #require(TandemKeyConfirmation.confirmationKey(derivedSecret: serverSecret, pumpNonce: pumpNonce))
            let cargo = try #require(TandemKeyConfirmation.keyConfirmationCargo(clientNonce: [UInt8](repeating: 0x72, count: TandemKeyConfirmation.nonceSize), key: key))
            try client.consume(sentInstanceID + cargo.dropFirst(instanceID.count), for: .jpake4)
        }
    }
}

/// A legacy pump, with the client's instance ID bytes fixed by its random source.
private final class SimulatedLegacyPump {
    static let code = "12345678901"
    static let stepCount = 4
    static let instance: [UInt8] = [0x42, 0x42]
    let client: TandemAuthenticator
    let hmacKey = [UInt8](repeating: 0x38, count: TandemLegacyHandshake.hmacKeySize)
    var sentInstance = instance

    init() throws {
        client = try TandemAuthenticator(code: try #require(PairingCode(Self.code)), randomBytes: { [UInt8](repeating: 0x42, count: $0) })
    }

    var centralResponse: [UInt8] {
        sentInstance + [UInt8](repeating: 0, count: TandemLegacyHandshake.challengeHashSize) + hmacKey
    }

    func run(steps count: Int) throws {
        if count > 0 { _ = try client.nextRequest() }
        if count > 1 { try client.consume(centralResponse, for: .centralChallenge) }
        if count > 2 { _ = try client.nextRequest() }
        if count > 3 { try client.consume(sentInstance + [1], for: .pumpChallenge) }
    }
}

private func expectEnded(_ client: TandemAuthenticator, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(client.hasFailed, sourceLocation: sourceLocation)
    #expect(!client.isComplete, sourceLocation: sourceLocation)
    #expect(client.derivedSecret == nil, sourceLocation: sourceLocation)
    #expect(client.heldMaterial == [], sourceLocation: sourceLocation)
    #expect(throws: secureRejection, sourceLocation: sourceLocation) { try client.nextRequest() }
    for kind in TandemAuthorizationRequest.allCases {
        #expect(throws: secureRejection, sourceLocation: sourceLocation) {
            try client.consume(instanceID + [UInt8](repeating: 1, count: EcJpakeRound1.encodedSize), for: kind)
        }
    }
    #expect(client.hasFailed, sourceLocation: sourceLocation)
    #expect(!client.isComplete, sourceLocation: sourceLocation)
}

private func expectRejected(
    _ client: TandemAuthenticator, as failure: DriverFailure,
    sourceLocation: SourceLocation = #_sourceLocation, by action: () throws -> Void
) {
    #expect(throws: failure, sourceLocation: sourceLocation) { try action() }
    expectEnded(client, sourceLocation: sourceLocation)
}

private func expectRound1Rejected(
    as failure: DriverFailure, sourceLocation: SourceLocation = #_sourceLocation, tampering: ([UInt8]) throws -> [UInt8]
) throws {
    let pump = try SimulatedPump()
    pump.round1OnWire = try tampering(pump.round1OnWire)
    try pump.run(steps: 3)
    expectRejected(pump.client, as: failure, sourceLocation: sourceLocation) { try pump.perform(step: 3) }
}

/// The curve's field prime, big-endian.
private let fieldPrime: [UInt8] = [
    0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
]
private let coordinateSize = EcJpakeScalar.encodedSize
/// First Y byte of the first point in a round 1 payload: length, 0x04, X.
private let firstPointY = 2 + coordinateSize

/// p - y, the Y of the same X on the other side of the curve.
private func negated(_ y: [UInt8]) -> [UInt8] {
    var result = y
    var borrow = 0
    for index in y.indices.reversed() {
        let difference = Int(fieldPrime[index]) - Int(y[index]) - borrow
        result[index] = UInt8(truncatingIfNeeded: difference)
        borrow = difference < 0 ? 1 : 0
    }
    return result
}

@Suite("Tandem authorization state machine")
struct TandemAuthenticatorTests {
    // MARK: Successful handshakes

    @Test func modernHandshakeWithSimulatedServer() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: SimulatedPump.stepCount)
        #expect(pump.requests.map(\.kind) == [.jpake1a, .jpake1b, .jpake2, .jpake3, .jpake4])
        #expect(pump.client.isComplete)
        #expect(!pump.client.hasFailed)
        #expect(pump.client.derivedSecret == pump.serverSecret)
    }

    @Test func modernSuccessKeepsOnlyTheDerivedSecret() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: SimulatedPump.stepCount)
        #expect(pump.client.heldMaterial == ["derivedSecret"])
    }

    @Test func legacyHandshakeWithSimulatedPump() throws {
        let code = try #require(PairingCode(SimulatedLegacyPump.code))
        let pump = try SimulatedLegacyPump()
        let central = try pump.client.nextRequest()
        #expect(central.kind == .centralChallenge)
        #expect(central.cargo.count == TandemLegacyHandshake.appInstanceIDSize + TandemLegacyHandshake.challengeSize)
        try pump.client.consume(pump.centralResponse, for: .centralChallenge)
        let challenge = try pump.client.nextRequest()
        #expect(challenge.kind == .pumpChallenge)
        #expect(Array(challenge.cargo.dropFirst(TandemLegacyHandshake.appInstanceIDSize)) == TandemLegacyHandshake.hmacSHA1(key: code.utf8Bytes, data: pump.hmacKey))
        try pump.client.consume(SimulatedLegacyPump.instance + [1], for: .pumpChallenge)
        #expect(pump.client.isComplete)
        #expect(pump.client.derivedSecret == nil)
        #expect(pump.client.heldMaterial == [])
    }

    @Test func aStrayMessageCannotUndoAVerifiedSuccess() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: SimulatedPump.stepCount)
        #expect(throws: secureRejection) { try pump.client.consume([], for: .jpake4) }
        #expect(throws: secureRejection) { try pump.client.nextRequest() }
        #expect(pump.client.isComplete)
        #expect(pump.client.derivedSecret == pump.serverSecret)
    }

    // MARK: Terminal states

    @Test func aFreshHandshakeIsNeitherCompleteNorFailed() throws {
        for client in [try SimulatedPump().client, try SimulatedLegacyPump().client] {
            #expect(!client.isComplete)
            #expect(!client.hasFailed)
            #expect(client.derivedSecret == nil)
        }
    }

    @Test("Reset ends a modern handshake at any point", arguments: 0...SimulatedPump.stepCount)
    func resetAtEveryModernStep(steps: Int) throws {
        let pump = try SimulatedPump()
        try pump.run(steps: steps)
        pump.client.reset()
        expectEnded(pump.client)
    }

    @Test("Reset ends a legacy handshake at any point", arguments: 0...SimulatedLegacyPump.stepCount)
    func resetAtEveryLegacyStep(steps: Int) throws {
        let pump = try SimulatedLegacyPump()
        try pump.run(steps: steps)
        pump.client.reset()
        expectEnded(pump.client)
    }

    @Test func aCopiedReferenceSharesTheResetState() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: 6)
        let copy = pump.client
        copy.reset()
        #expect(pump.client.heldMaterial == [])
        #expect(pump.client.hasFailed)
    }

    // MARK: Secret lifetime

    @Test("The derived secret stays unreadable until confirmation passes", arguments: 0..<SimulatedPump.stepCount)
    func derivedSecretNeedsConfirmation(steps: Int) throws {
        let pump = try SimulatedPump()
        try pump.run(steps: steps)
        #expect(pump.client.derivedSecret == nil)
        #expect(!pump.client.isComplete)
    }

    @Test func arithmeticSecretsAreClearedOnceTheSecretIsDerived() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: 5)
        #expect(pump.client.heldMaterial.contains("arithmetic"))
        try pump.perform(step: 5)
        #expect(!pump.client.heldMaterial.contains("arithmetic"))
    }

    @Test func aFailingRandomSourceEndsTheHandshake() throws {
        let code = try #require(PairingCode(SimulatedLegacyPump.code))
        let client = try TandemAuthenticator(code: code, randomBytes: { _ in throw EcJpakeError.invalidRandomness })
        expectRejected(client, as: secureRejection) { _ = try client.nextRequest() }
    }

    // MARK: Protocol violations

    @Test("A response in the wrong step ends the handshake", arguments: 0..<SimulatedPump.stepCount)
    func outOfOrderResponse(steps: Int) throws {
        let expected = SimulatedPump.responseSteps.first { $0.step == steps }?.kind
        for wrong in TandemAuthorizationRequest.allCases where wrong != expected {
            let pump = try SimulatedPump()
            try pump.run(steps: steps)
            expectRejected(pump.client, as: secureRejection) { try pump.client.consume([], for: wrong) }
        }
    }

    @Test func aSecondRequestBeforeTheResponseEndsTheHandshake() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: 1)
        expectRejected(pump.client, as: secureRejection) { _ = try pump.client.nextRequest() }
    }

    @Test("A short response ends the handshake", arguments: SimulatedPump.responseSteps.map(\.step))
    func shortModernResponse(step: Int) throws {
        let kind = try #require(SimulatedPump.responseSteps.first { $0.step == step }?.kind)
        let pump = try SimulatedPump()
        try pump.run(steps: step)
        expectRejected(pump.client, as: secureRejection) { try pump.client.consume(instanceID, for: kind) }
    }

    @Test func shortLegacyResponsesEndTheHandshake() throws {
        let central = try SimulatedLegacyPump()
        try central.run(steps: 1)
        expectRejected(central.client, as: secureRejection) { try central.client.consume([1], for: .centralChallenge) }
        let challenge = try SimulatedLegacyPump()
        try challenge.run(steps: 3)
        expectRejected(challenge.client, as: secureRejection) { try challenge.client.consume([1], for: .pumpChallenge) }
    }

    @Test("A wrong instance ID ends the handshake", arguments: SimulatedPump.responseSteps.map(\.step))
    func wrongModernInstanceID(step: Int) throws {
        let pump = try SimulatedPump()
        try pump.run(steps: step)
        pump.sentInstanceID = wrongInstanceID
        expectRejected(pump.client, as: secureRejection) { try pump.perform(step: step) }
    }

    @Test func wrongLegacyInstanceIDsEndTheHandshake() throws {
        let central = try SimulatedLegacyPump()
        try central.run(steps: 1)
        central.sentInstance = wrongInstanceID
        expectRejected(central.client, as: secureRejection) { try central.client.consume(central.centralResponse, for: .centralChallenge) }
        let challenge = try SimulatedLegacyPump()
        try challenge.run(steps: 3)
        expectRejected(challenge.client, as: secureRejection) { try challenge.client.consume(wrongInstanceID + [1], for: .pumpChallenge) }
    }

    @Test func legacyRejectionIsFinal() throws {
        let pump = try SimulatedLegacyPump()
        try pump.run(steps: 3)
        expectRejected(pump.client, as: codeRejection) { try pump.client.consume(SimulatedLegacyPump.instance + [0], for: .pumpChallenge) }
        #expect(throws: secureRejection) { try pump.client.consume(SimulatedLegacyPump.instance + [1], for: .pumpChallenge) }
        #expect(!pump.client.isComplete)
    }

    // MARK: Wrong code and proof failures

    @Test func wrongCodeFailsAtConfirmation() throws {
        let pump = try SimulatedPump(serverCode: "654321")
        try pump.run(steps: 9)
        expectRejected(pump.client, as: codeRejection) { try pump.perform(step: 9) }
    }

    @Test func aFailedProofIsReportedAsCodeRejected() throws {
        try expectRound1Rejected(as: codeRejection) { round1 in
            var bytes = round1
            bytes[bytes.count - 1] ^= 1
            return bytes
        }
    }

    // MARK: Attacks on the exchange

    @Test func reflectedRound1IsRejected() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: 1)
        try pump.client.consume(pump.requests[0].cargo, for: .jpake1a)
        let second = try pump.client.nextRequest()
        expectRejected(pump.client, as: codeRejection) { try pump.client.consume(second.cargo, for: .jpake1b) }
    }

    @Test func reflectedRound2IsRejected() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: 5)
        expectRejected(pump.client, as: secureRejection) { try pump.client.consume(pump.requests[2].cargo, for: .jpake2) }
    }

    @Test func reflectedRound2WithACurvePrefixFailsProofValidation() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: 5)
        let curvePrefix: [UInt8] = [0x03, 0x00, 0x17]
        let cargo = instanceID + curvePrefix + pump.requests[2].cargo.dropFirst(instanceID.count)
        expectRejected(pump.client, as: codeRejection) { try pump.client.consume(cargo, for: .jpake2) }
    }

    @Test func reflectedConfirmationIsRejected() throws {
        let pump = try SimulatedPump()
        try pump.run(steps: 9)
        expectRejected(pump.client, as: codeRejection) { try pump.client.consume(pump.requests[4].cargo, for: .jpake4) }
    }

    @Test func crossedPeerPointsAreRejected() throws {
        try expectRound1Rejected(as: codeRejection) { round1 in
            let pointField = 1 + EcJpakePoint.encodedSize
            var crossed = round1
            crossed.replaceSubrange(0..<pointField, with: round1[round1Half..<round1Half + pointField])
            crossed.replaceSubrange(round1Half..<round1Half + pointField, with: round1[0..<pointField])
            return crossed
        }
    }

    @Test func peerPointsCrossedWithTheirProofsFailAtRound2() throws {
        let pump = try SimulatedPump()
        pump.round1OnWire = Array(pump.round1OnWire.dropFirst(round1Half) + pump.round1OnWire.prefix(round1Half))
        try pump.run(steps: 5)
        expectRejected(pump.client, as: codeRejection) { try pump.perform(step: 5) }
    }

    @Test func aPointOffTheCurveIsRejected() throws {
        try expectRound1Rejected(as: secureRejection) { round1 in
            var bytes = round1
            bytes[firstPointY + coordinateSize - 1] ^= 1
            return bytes
        }
    }

    @Test func theZeroPointIsRejected() throws {
        try expectRound1Rejected(as: secureRejection) { round1 in
            var bytes = round1
            bytes.replaceSubrange(2..<firstPointY + coordinateSize, with: [UInt8](repeating: 0, count: 2 * coordinateSize))
            return bytes
        }
    }

    @Test func theWrongYOfAValidXIsRejected() throws {
        try expectRound1Rejected(as: codeRejection) { round1 in
            var bytes = round1
            let y = firstPointY..<firstPointY + coordinateSize
            bytes.replaceSubrange(y, with: negated(Array(bytes[y])))
            return bytes
        }
    }

    @Test func aOneByteInfinityIsRejected() throws {
        try expectRound1Rejected(as: secureRejection) { round1 in
            [1, 0] + round1.dropFirst(2)
        }
    }

    @Test("A compressed point is rejected", arguments: [UInt8(0x02), 0x03])
    func compressedPointWithFullLength(prefix: UInt8) throws {
        try expectRound1Rejected(as: secureRejection) { round1 in
            var bytes = round1
            bytes[1] = prefix
            return bytes
        }
    }

    @Test func aCompressedLengthPointIsRejected() throws {
        try expectRound1Rejected(as: secureRejection) { round1 in
            [UInt8(1 + coordinateSize), 0x02] + round1.dropFirst(2)
        }
    }

    @Test func aProofUnderTheWrongIdentityIsRejected() throws {
        try expectRound1Rejected(as: codeRejection) { _ in
            try EcJpake(role: .client, secret: Array("123456".utf8), randomBytes: { [UInt8](repeating: 0x39, count: $0) }).round1()
        }
    }

    // MARK: Construction and randomness

    @Test func constructionFailuresAreTyped() throws {
        let code = try #require(PairingCode("123456"))
        func make() throws(DriverFailure) -> TandemAuthenticator { try TandemAuthenticator(code: code) }
        #expect(try !make().isComplete)
    }

    @Test func productionHandshakesDrawFreshRandomness() throws {
        let code = try #require(PairingCode("123456"))
        let first = try TandemAuthenticator(code: code).nextRequest()
        let second = try TandemAuthenticator(code: code).nextRequest()
        #expect(first.cargo != second.cargo)
    }

    // MARK: Redaction

    private func renderings(of value: Any) -> [String] {
        var printed = "", debugPrinted = "", dumped = ""
        print(value, to: &printed)
        debugPrint(value, to: &debugPrinted)
        dump(value, to: &dumped)
        return [printed, debugPrinted, dumped, "\(value)", String(describing: value), String(reflecting: value)]
    }

    private func expectRedacted(_ value: Any, placeholder: String, secrets: [[UInt8]], sourceLocation: SourceLocation = #_sourceLocation) {
        for rendering in renderings(of: value) {
            #expect(rendering.contains(placeholder), sourceLocation: sourceLocation)
            #expect(rendering.split(separator: "\n").count == 1, "A rendering lists stored fields", sourceLocation: sourceLocation)
            for secret in secrets {
                #expect(!rendering.contains(String(decoding: secret, as: UTF8.self)), sourceLocation: sourceLocation)
                #expect(!rendering.contains(secret.map { String(format: "%02x", $0) }.joined()), sourceLocation: sourceLocation)
                #expect(!rendering.contains("\(secret)"), sourceLocation: sourceLocation)
            }
        }
    }

    @Test func aRenderedAuthenticatorShowsNoSecret() throws {
        let legacy = try SimulatedLegacyPump()
        try legacy.run(steps: 3)
        expectRedacted(legacy.client, placeholder: "Tandem authenticator", secrets: [Array(SimulatedLegacyPump.code.utf8), legacy.hmacKey])
        let pump = try SimulatedPump()
        try pump.run(steps: SimulatedPump.stepCount)
        expectRedacted(pump.client, placeholder: "Tandem authenticator", secrets: [Array("123456".utf8), pump.serverSecret])
    }

    @Test func aRenderedRequestShowsOnlyItsKind() throws {
        let pump = try SimulatedLegacyPump()
        try pump.run(steps: 2)
        let request = try pump.client.nextRequest()
        let code = try #require(PairingCode(SimulatedLegacyPump.code))
        let digest = TandemLegacyHandshake.hmacSHA1(key: code.utf8Bytes, data: pump.hmacKey)
        #expect(request.cargo == SimulatedLegacyPump.instance + digest)
        for rendering in renderings(of: request) {
            #expect(rendering.contains("pumpChallenge"))
            #expect(!rendering.contains("cargo"))
            #expect(!rendering.contains(digest.map { String(format: "%02x", $0) }.joined()))
            #expect(!rendering.contains("\(digest)"))
            #expect(!rendering.contains("\(request.cargo)"))
        }
    }

    @Test func aRenderedParticipantShowsNoSecret() throws {
        let code = Array("a7Q!kZ".utf8)
        let scalar = [UInt8](repeating: 0x29, count: EcJpakeScalar.encodedSize)
        let participant = try EcJpake(role: .client, secret: code, randomBytes: { [UInt8](repeating: 0x29, count: $0) })
        _ = try participant.round1()
        expectRedacted(participant, placeholder: "EC-JPAKE participant", secrets: [code, scalar])
    }
}
