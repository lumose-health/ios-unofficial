// EC-JPAKE arithmetic derives from particle-iot/ecjpake-java (Apache-2.0,
// Copyright 2022 Particle Industries, Inc.). Wire layout is in TandemWire.
import CryptoBoringWrapper
import CryptoKit
import Foundation
import TandemWire

/// Arithmetic failures carry no secret material in their descriptions.
enum EcJpakeError: Error, Equatable {
    case unexpectedEndOfStream
    case malformedPayload
    case zkpValidationFailed
    case invalidState
    case invalidRandomness
}

extension Array where Element == UInt8 {
    /// Overwrites the bytes, then empties the array. Best effort: an earlier
    /// copy of the buffer, or a store the compiler removes, can outlive this.
    mutating func wipe() {
        for index in indices { self[index] = 0 }
        removeAll(keepingCapacity: false)
    }
}

/// One EC-JPAKE participant. The random-byte closure is internal so tests can
/// replay recorded draws; production uses the system random generator.
///
/// A reference type, so that there is one set of secrets for `reset()` and
/// `deinit` to clear rather than one per value copy.
final class EcJpake {
    enum Role { case client, server }
    typealias RandomBytes = (Int) throws -> [UInt8]

    private let group: BoringSSLEllipticCurveGroup
    private let id: [UInt8]
    private let peerID: [UInt8]
    private let role: Role
    private let randomBytes: RandomBytes
    private var secret: [UInt8]
    private var x1: ArbitraryPrecisionInteger?
    private var x2: ArbitraryPrecisionInteger?
    private var ownFirst: EllipticCurvePoint?
    private var ownSecond: EllipticCurvePoint?
    private var peerFirst: EllipticCurvePoint?
    private var peerSecond: EllipticCurvePoint?
    private var peerRound2: EllipticCurvePoint?

    /// Redraws allowed per scalar. A uniform draw falls outside 1...n-1 with
    /// probability near 2^-32, so reaching this limit means a broken source.
    private static let scalarDrawLimit = 8

    init(role: Role, secret: [UInt8], randomBytes: @escaping RandomBytes = EcJpake.systemRandomBytes) throws(EcJpakeError) {
        do { group = try BoringSSLEllipticCurveGroup(.p256) } catch { throw .invalidState }
        self.role = role
        id = Array((role == .client ? "client" : "server").utf8)
        peerID = Array((role == .client ? "server" : "client").utf8)
        self.secret = secret
        self.randomBytes = randomBytes
    }

    deinit { reset() }

    /// Names of the fields still holding key material. Names only, never values.
    var heldMaterial: [String] {
        var held: [String] = []
        if !secret.isEmpty { held.append("secret") }
        if x1 != nil { held.append("x1") }
        if x2 != nil { held.append("x2") }
        return held
    }

    static func systemRandomBytes(_ count: Int) throws -> [UInt8] {
        var rng = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
    }

    func round1() throws -> [UInt8] {
        guard x1 == nil, !secret.isEmpty else { throw EcJpakeError.invalidState }
        let firstScalar = try drawScalar()
        let firstNonce = try drawScalar()
        let secondScalar = try drawScalar()
        let secondNonce = try drawScalar()
        let first = try EllipticCurvePoint(multiplying: firstScalar, on: group)
        let second = try EllipticCurvePoint(multiplying: secondScalar, on: group)
        let result = EcJpakeRound1(
            firstPoint: try wire(first), firstProof: try proof(generator: group.generator, scalar: firstScalar, point: first, nonce: firstNonce),
            secondPoint: try wire(second), secondProof: try proof(generator: group.generator, scalar: secondScalar, point: second, nonce: secondNonce)
        )
        x1 = firstScalar; x2 = secondScalar; ownFirst = first; ownSecond = second
        return result.encoded()
    }

    func readRound1(_ bytes: [UInt8]) throws -> Int {
        guard peerFirst == nil else { throw EcJpakeError.invalidState }
        let parsed: (round: EcJpakeRound1, byteCount: Int)
        do { parsed = try EcJpakeRound1.parse(bytes) }
        catch EcJpakePayloadError.unexpectedEndOfStream { throw EcJpakeError.unexpectedEndOfStream }
        catch { throw EcJpakeError.malformedPayload }
        let first = try point(parsed.round.firstPoint)
        let second = try point(parsed.round.secondPoint)
        guard try valid(parsed.round.firstProof, generator: group.generator, point: first, id: peerID),
              try valid(parsed.round.secondProof, generator: group.generator, point: second, id: peerID)
        else { throw EcJpakeError.zkpValidationFailed }
        peerFirst = first; peerSecond = second
        return parsed.byteCount
    }

    func round2() throws -> [UInt8] {
        guard let secondScalar = x2, let first = ownFirst, let peerFirst, let peerSecond else { throw EcJpakeError.invalidState }
        let blind = try drawBytes(16)
        let nonce = try drawScalar()
        let generator = try EllipticCurvePoint(adding: EllipticCurvePoint(adding: peerFirst, peerSecond, on: group), first, on: group)
        let scalar = try secondScalar * (ArbitraryPrecisionInteger(bytes: blind) * group.order + ArbitraryPrecisionInteger(bytes: secret))
        let publicPoint = try EllipticCurvePoint(multiplying: generator, by: scalar, on: group)
        return try EcJpakeRound2(point: wire(publicPoint), proof: proof(generator: generator, scalar: scalar, point: publicPoint, nonce: nonce))
            .encoded(from: role == .client ? .client : .server)
    }

    func readRound2(_ bytes: [UInt8]) throws -> Int {
        guard let first = ownFirst, let second = ownSecond, let peerFirst, peerRound2 == nil else { throw EcJpakeError.invalidState }
        let parsed: (round: EcJpakeRound2, byteCount: Int)
        do { parsed = try EcJpakeRound2.parse(bytes, from: role == .client ? .server : .client) }
        catch EcJpakePayloadError.unexpectedEndOfStream { throw EcJpakeError.unexpectedEndOfStream }
        catch { throw EcJpakeError.malformedPayload }
        let generator = try EllipticCurvePoint(adding: EllipticCurvePoint(adding: first, second, on: group), peerFirst, on: group)
        let publicPoint = try point(parsed.round.point)
        guard try valid(parsed.round.proof, generator: generator, point: publicPoint, id: peerID) else { throw EcJpakeError.zkpValidationFailed }
        peerRound2 = publicPoint
        return parsed.byteCount
    }

    func deriveSecret() throws -> [UInt8] {
        guard let secondScalar = x2, let peerSecond, let peerRound2 else { throw EcJpakeError.invalidState }
        let blind = try drawBytes(16)
        let product = try (secondScalar * (ArbitraryPrecisionInteger(bytes: blind) * group.order + ArbitraryPrecisionInteger(bytes: secret))).modulo(group.order, nonNegative: true)
        let negative = try ArbitraryPrecisionInteger(integerLiteral: 0).sub(product, modulo: group.order)
        let adjustment = try EllipticCurvePoint(multiplying: peerSecond, by: negative, on: group)
        let combined = try EllipticCurvePoint(adding: peerRound2, adjustment, on: group)
        let shared = try EllipticCurvePoint(multiplying: combined, by: secondScalar, on: group)
        let encoding = Array(try shared.x962Representation(compressed: false, on: group))
        guard encoding.count == EcJpakePoint.encodedSize else { throw EcJpakeError.malformedPayload }
        let x = Array(encoding[1..<(1 + EcJpakeScalar.encodedSize)])
        return Array(SHA256.hash(data: Data(x.drop(while: { $0 == 0 }))))
    }

    func reset() {
        secret.wipe()
        x1 = nil; x2 = nil; ownFirst = nil; ownSecond = nil
        peerFirst = nil; peerSecond = nil; peerRound2 = nil
        // BoringSSL clears each scalar when its last reference goes. The local
        // blinding values and point encodings are left to the allocator.
    }

    /// A uniform scalar in 1...n-1, by rejection sampling.
    private func drawScalar() throws -> ArbitraryPrecisionInteger {
        for _ in 0..<Self.scalarDrawLimit {
            let bytes = try drawBytes(EcJpakeScalar.encodedSize)
            if try isInScalarRange(bytes) { return try ArbitraryPrecisionInteger(bytes: bytes) }
        }
        throw EcJpakeError.invalidRandomness
    }

    private func isInScalarRange(_ bytes: [UInt8]) throws -> Bool {
        let value = try ArbitraryPrecisionInteger(bytes: bytes)
        return value > 0 && value < group.order
    }

    private func drawBytes(_ count: Int) throws -> [UInt8] {
        let bytes = try randomBytes(count)
        guard bytes.count == count else { throw EcJpakeError.invalidRandomness }
        return bytes
    }

    private func point(_ wire: EcJpakePoint) throws -> EllipticCurvePoint {
        do { return try EllipticCurvePoint(x962Representation: wire.bytes, on: group) }
        catch { throw EcJpakeError.malformedPayload }
    }

    private func wire(_ point: EllipticCurvePoint) throws -> EcJpakePoint {
        guard let result = EcJpakePoint(bytes: Array(try point.x962Representation(compressed: false, on: group))) else { throw EcJpakeError.malformedPayload }
        return result
    }

    private func hash(generator: EllipticCurvePoint, commitment: EllipticCurvePoint, point: EllipticCurvePoint, id: [UInt8]) throws -> ArbitraryPrecisionInteger {
        var input: [UInt8] = []
        for p in [generator, commitment, point] {
            let bytes = Array(try p.x962Representation(compressed: false, on: group))
            input += [0, 0, 0, UInt8(bytes.count)] + bytes
        }
        input += [0, 0, 0, UInt8(id.count)] + id
        return try ArbitraryPrecisionInteger(bytes: Array(SHA256.hash(data: Data(input)))).modulo(group.order, nonNegative: true)
    }

    private func proof(generator: EllipticCurvePoint, scalar: ArbitraryPrecisionInteger, point: EllipticCurvePoint, nonce: ArbitraryPrecisionInteger) throws -> EcJpakeProof {
        let commitment = try EllipticCurvePoint(multiplying: generator, by: nonce, on: group)
        let h = try hash(generator: generator, commitment: commitment, point: point, id: id)
        let response = try nonce.sub(scalar.mul(h, modulo: group.order), modulo: group.order)
        guard let wireScalar = EcJpakeScalar(bytes: Array(try Data(bytesOf: response, paddedToSize: EcJpakeScalar.encodedSize))) else { throw EcJpakeError.malformedPayload }
        return try EcJpakeProof(commitment: wire(commitment), response: wireScalar)
    }

    private func valid(_ proof: EcJpakeProof, generator: EllipticCurvePoint, point: EllipticCurvePoint, id: [UInt8]) throws -> Bool {
        guard try isInScalarRange(proof.response.bytes) else { throw EcJpakeError.malformedPayload }
        let commitment = try self.point(proof.commitment)
        let response = try ArbitraryPrecisionInteger(bytes: proof.response.bytes)
        let h = try hash(generator: generator, commitment: commitment, point: point, id: id)
        let left = try EllipticCurvePoint(multiplying: generator, by: response, on: group)
        let right = try EllipticCurvePoint(multiplying: point, by: h, on: group)
        return try EllipticCurvePoint(adding: left, right, on: group).isEqual(to: commitment, on: group)
    }
}

extension EcJpake: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String { "EC-JPAKE participant" }
    var debugDescription: String { "EC-JPAKE participant" }
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .class) }
}
