import Foundation
import TandemWire
import Testing
@testable import TandemDriver

@Suite("EC-JPAKE recorded vectors")
struct EcJpakeVectorTests {
    @Test func bothRolesMatchRecordedPayloadsAndSecret() throws {
        let fixture = try Self.load("handshake-client-01.json")
        let rounds = try #require(fixture["rounds"] as? [String: String])
        let reads = try #require(fixture["read_results"] as? [String: Int])
        let secret = try Self.hex(try #require(fixture["secret"] as? String))
        let client = try Self.role(.client, secret: secret, fixture: fixture)
        let server = try Self.role(.server, secret: secret, fixture: fixture)
        let client1 = try client.round1(), server1 = try server.round1()
        #expect(client1 == (try Self.hex(try #require(rounds["client_round1"]))))
        #expect(server1 == (try Self.hex(try #require(rounds["server_round1"]))))
        #expect(try client.readRound1(server1) == reads["client_read_round1"])
        #expect(try server.readRound1(client1) == reads["server_read_round1"])
        let client2 = try client.round2(), server2 = try server.round2()
        #expect(client2 == (try Self.hex(try #require(rounds["client_round2"]))))
        #expect(server2 == (try Self.hex(try #require(rounds["server_round2"]))))
        #expect(try client.readRound2(server2) == reads["client_read_round2"])
        #expect(try server.readRound2(client2) == reads["server_read_round2"])
        let secrets = try #require(fixture["derived_secret"] as? [String: String])
        let expected = try Self.hex(try #require(secrets["client"]))
        #expect(secrets["client"] == secrets["server"])
        #expect(try client.deriveSecret() == expected)
        #expect(try server.deriveSecret() == expected)
    }

    @Test func corruptedProofIsRejected() throws {
        let fixture = try Self.load("malformed-round1-zkp-01.json")
        let input = try #require(fixture["input"] as? [String: Any])
        let corruption = try #require(input["corruption"] as? [String: Any])
        var bytes = try Self.hex(try #require(input["base_payload"] as? String))
        let offset = try #require(corruption["offset"] as? Int)
        let mask = try Self.hex(try #require(corruption["mask"] as? String))
        for (index, byte) in mask.enumerated() { bytes[offset + index] ^= byte }
        let reader = try EcJpake(role: .server, secret: Array("123456".utf8))
        #expect(throws: EcJpakeError.zkpValidationFailed) { try reader.readRound1(bytes) }
    }

    @Test func tamperedFirstRound1ProofIsRejected() throws {
        var bytes = try EcJpake(role: .client, secret: Self.code, randomBytes: Self.filled(0x29)).round1()
        bytes[Self.round1ResponseOffset] ^= 1
        let reader = try EcJpake(role: .server, secret: Self.code)
        #expect(throws: EcJpakeError.zkpValidationFailed) { try reader.readRound1(bytes) }
    }

    @Test func tamperedRound2ProofIsRejectedInBothDirections() throws {
        let client = try EcJpake(role: .client, secret: Self.code, randomBytes: Self.filled(0x29))
        let server = try EcJpake(role: .server, secret: Self.code, randomBytes: Self.filled(0x39))
        let clientRound1 = try client.round1(), serverRound1 = try server.round1()
        _ = try client.readRound1(serverRound1)
        _ = try server.readRound1(clientRound1)
        var clientRound2 = try client.round2(), serverRound2 = try server.round2()
        clientRound2[Self.round1ResponseOffset] ^= 1
        serverRound2[EcJpakeRound2.encodedSize(from: .server) - EcJpakeRound2.encodedSize(from: .client) + Self.round1ResponseOffset] ^= 1
        #expect(throws: EcJpakeError.zkpValidationFailed) { try server.readRound2(clientRound2) }
        #expect(throws: EcJpakeError.zkpValidationFailed) { try client.readRound2(serverRound2) }
    }

    @Test("A proof response outside 1...n-1 is malformed", arguments: [
        [UInt8](repeating: 0, count: EcJpakeScalar.encodedSize),
        groupOrder,
        [UInt8](repeating: 0xff, count: EcJpakeScalar.encodedSize)
    ])
    func outOfRangeResponseIsMalformed(response: [UInt8]) throws {
        var bytes = try EcJpake(role: .client, secret: Self.code, randomBytes: Self.filled(0x29)).round1()
        bytes.replaceSubrange(Self.round1ResponseOffset..<Self.round1ResponseOffset + response.count, with: response)
        let reader = try EcJpake(role: .server, secret: Self.code)
        #expect(throws: EcJpakeError.malformedPayload) { try reader.readRound1(bytes) }
    }

    @Test func leadingZeroBytesOfTheSharedPointAreStripped() throws {
        // This client scalar makes K.x start 0000557b. The expected secret was
        // computed with the arithmetic in scripts/spk2/ecjpake_replay.py.
        let clientDraws = [Self.scalar(0x11), Self.scalar(0x21),
                           try Self.hex("7777777777777777777777777777777777777777777777777777777777791c61"),
                           Self.scalar(0x22), [UInt8](repeating: 0x23, count: 16), Self.scalar(0x24), [UInt8](repeating: 0x25, count: 16)]
        let serverDraws = [Self.scalar(0x33), Self.scalar(0x31), Self.scalar(0x44), Self.scalar(0x32),
                           [UInt8](repeating: 0x34, count: 16), Self.scalar(0x35), [UInt8](repeating: 0x36, count: 16)]
        let client = try EcJpake(role: .client, secret: Self.code, randomBytes: Self.scripted(clientDraws))
        let server = try EcJpake(role: .server, secret: Self.code, randomBytes: Self.scripted(serverDraws))
        let clientRound1 = try client.round1(), serverRound1 = try server.round1()
        _ = try client.readRound1(serverRound1)
        _ = try server.readRound1(clientRound1)
        let clientRound2 = try client.round2(), serverRound2 = try server.round2()
        _ = try client.readRound2(serverRound2)
        _ = try server.readRound2(clientRound2)
        let expected = try Self.hex("651aa97fbc5e657fecfafb47bb42dd495bc8dc432222a22271fe193436b405db")
        #expect(try client.deriveSecret() == expected)
        #expect(try server.deriveSecret() == expected)
    }

    @Test func round1CannotRunTwice() throws {
        let participant = try EcJpake(role: .client, secret: Self.code)
        _ = try participant.round1()
        #expect(throws: EcJpakeError.invalidState) { try participant.round1() }
    }

    @Test func peerRound1CannotBeReadTwice() throws {
        let payload = try EcJpake(role: .server, secret: Self.code).round1()
        let participant = try EcJpake(role: .client, secret: Self.code)
        _ = try participant.readRound1(payload)
        #expect(throws: EcJpakeError.invalidState) { try participant.readRound1(payload) }
    }

    @Test func peerRound2CannotBeReadTwice() throws {
        let client = try EcJpake(role: .client, secret: Self.code)
        let server = try EcJpake(role: .server, secret: Self.code)
        let clientRound1 = try client.round1(), serverRound1 = try server.round1()
        _ = try client.readRound1(serverRound1)
        _ = try server.readRound1(clientRound1)
        let payload = try server.round2()
        _ = try client.readRound2(payload)
        #expect(throws: EcJpakeError.invalidState) { try client.readRound2(payload) }
    }

    @Test func resetClearsEveryHeldValueAndRefusesFurtherWork() throws {
        let payload = try EcJpake(role: .server, secret: Self.code).round1()
        let participant = try EcJpake(role: .client, secret: Self.code)
        #expect(participant.heldMaterial == ["secret"])
        _ = try participant.round1()
        _ = try participant.readRound1(payload)
        #expect(participant.heldMaterial == ["secret", "x1", "x2"])
        participant.reset()
        #expect(participant.heldMaterial.isEmpty)
        #expect(throws: EcJpakeError.invalidState) { try participant.round1() }
        #expect(throws: EcJpakeError.invalidState) { try participant.round2() }
        #expect(throws: EcJpakeError.invalidState) { try participant.deriveSecret() }
    }

    @Test func productionRandomSourceIsNotConstant() throws {
        let first = try EcJpake.systemRandomBytes(EcJpakeScalar.encodedSize)
        let second = try EcJpake.systemRandomBytes(EcJpakeScalar.encodedSize)
        #expect(first.count == EcJpakeScalar.encodedSize)
        #expect(first != second)
        #expect(Set(first).count > 1)
        let firstRound1 = try EcJpake(role: .client, secret: Self.code).round1()
        let secondRound1 = try EcJpake(role: .client, secret: Self.code).round1()
        #expect(firstRound1 != secondRound1)
    }

    @Test func drawsOutsideTheScalarRangeAreDiscarded() throws {
        var lastInRange = Self.groupOrder
        lastInRange[lastInRange.count - 1] -= 1
        let one = [UInt8](repeating: 0, count: EcJpakeScalar.encodedSize - 1) + [1]
        let accepted = [lastInRange, one, Self.scalar(0x29), Self.scalar(0x39)]
        let discarded = [[UInt8](repeating: 0, count: EcJpakeScalar.encodedSize), Self.groupOrder, [UInt8](repeating: 0xff, count: EcJpakeScalar.encodedSize)]
        let direct = try EcJpake(role: .client, secret: Self.code, randomBytes: Self.scripted(accepted)).round1()
        let resampled = try EcJpake(role: .client, secret: Self.code, randomBytes: Self.scripted(accepted.flatMap { discarded + [$0] })).round1()
        #expect(resampled == direct)
    }

    @Test func aRandomSourceThatNeverYieldsAScalarFails() throws {
        let participant = try EcJpake(role: .client, secret: Self.code, randomBytes: Self.filled(0))
        #expect(throws: EcJpakeError.invalidRandomness) { try participant.round1() }
    }

    private static let code = Array("123456".utf8)
    /// Offset of the first proof's response: point field, commitment field, scalar length byte.
    private static let round1ResponseOffset = 2 * (1 + EcJpakePoint.encodedSize) + 1
    /// The P-256 group order n, big-endian.
    private static let groupOrder: [UInt8] = ([
        0xffffffff, 0x00000000, 0xffffffff, 0xffffffff, 0xbce6faad, 0xa7179e84, 0xf3b9cac2, 0xfc632551
    ] as [UInt32]).flatMap { word in withUnsafeBytes(of: word.bigEndian) { Array($0) } }

    private static func scalar(_ byte: UInt8) -> [UInt8] { [UInt8](repeating: byte, count: EcJpakeScalar.encodedSize) }

    private static func filled(_ byte: UInt8) -> EcJpake.RandomBytes { { [UInt8](repeating: byte, count: $0) } }

    private static func scripted(_ draws: [[UInt8]]) -> EcJpake.RandomBytes {
        var next = 0
        return { count in
            guard next < draws.count, draws[next].count == count else { throw EcJpakeError.invalidRandomness }
            defer { next += 1 }
            return draws[next]
        }
    }

    private static func role(_ role: EcJpake.Role, secret: [UInt8], fixture: [String: Any]) throws -> EcJpake {
        let log = try #require((fixture["randomness"] as? [String: Any])?["log"] as? [[String: String]])
        let name = role == .client ? "client" : "server"
        let draws = try log.filter { $0["role"] == name }.map { try hex(try #require($0["bytes"])) }
        return try EcJpake(role: role, secret: secret, randomBytes: scripted(draws))
    }

    private static func load(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/EcJpake/").appendingPathComponent(name))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func hex(_ value: String) throws -> [UInt8] {
        try #require(value.count.isMultiple(of: 2))
        return try stride(from: 0, to: value.count, by: 2).map { offset in
            let start = value.index(value.startIndex, offsetBy: offset)
            return try #require(UInt8(value[start..<value.index(start, offsetBy: 2)], radix: 16))
        }
    }
}
