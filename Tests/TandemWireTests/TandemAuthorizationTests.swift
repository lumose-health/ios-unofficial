import Foundation
import Testing
@testable import TandemWire

@Suite("Authorization request framing")
struct TandemAuthorizationFramingTests {

    @Test("The closed set is exactly the seven authorization requests, with Android's opcodes")
    func closedSetOpcodes() {
        let opcodes = TandemAuthorizationRequest.allCases.map(\.opcode)
        // Android TandemProtocol: CENTRAL_CHALLENGE 16, PUMP_CHALLENGE 18, JPAKE_1A..4 32-40.
        #expect(opcodes == [16, 18, 32, 34, 36, 38, 40])
    }

    @Test("Every request round-trips through the assembler and decoder")
    func everyRequestRoundTrips() throws {
        let cargo: [UInt8] = [1, 0] + (0..<40).map { UInt8($0) }
        for request in TandemAuthorizationRequest.allCases {
            let chunks = try #require(request.chunks(transactionID: 0x5A, cargo: cargo))
            let message = try Self.reassemble(chunks)
            #expect(message.opcode == request.opcode)
            #expect(message.transactionID == 0x5A)
            #expect(message.cargo == cargo)
        }
    }

    @Test("A small frame matches a hand-built canonical frame byte for byte")
    func smallFrameBytes() throws {
        let chunks = try #require(TandemAuthorizationRequest.jpake3.chunks(transactionID: 7, cargo: [1, 0]))
        // opcode 38, tx 7, length 2, cargo 01 00, CRC-16/CCITT-FALSE little-endian.
        let body: [UInt8] = [38, 7, 2, 1, 0]
        let crc = TandemMessage.crc16(body)
        #expect(chunks == [[0, 7] + body + [UInt8(crc & 0xFF), UInt8(crc >> 8)]])
    }

    @Test("A 167-byte cargo is eleven chunks of at most 18 bytes counting down 10 to 0")
    func chunkCountForLongestHandshakeCargo() throws {
        // 167 = app instance ID + half of round 1, the longest EC-JPAKE request.
        let cargo = [UInt8](repeating: 0x6B, count: 167)
        let chunks = try #require(TandemAuthorizationRequest.jpake1a.chunks(transactionID: 3, cargo: cargo))
        #expect(chunks.count == 11)
        #expect(chunks.map { $0[0] } == (0...10).reversed().map { UInt8($0) })
        #expect(chunks.allSatisfy { $0[1] == 3 })
        let sizes = chunks.map(\.count)
        #expect(sizes.dropLast().allSatisfy { $0 == 18 })
        // 3 header + 167 cargo + 2 CRC = 172 = 10 x 16 + 12.
        #expect(sizes.last == 2 + 12)
        #expect(try Self.reassemble(chunks).cargo == cargo)
    }

    @Test("The largest cargo the remaining-count nibble allows round-trips; one more is refused")
    func maximumCargo() throws {
        #expect(TandemAuthorizationRequest.maximumCargoSize == 251)
        let cargo = [UInt8](repeating: 0xA5, count: TandemAuthorizationRequest.maximumCargoSize)
        let chunks = try #require(TandemAuthorizationRequest.jpake2.chunks(transactionID: 9, cargo: cargo))
        #expect(chunks.count == 16)
        #expect(chunks.first?[0] == 15)
        #expect(try Self.reassemble(chunks).cargo == cargo)
        #expect(TandemAuthorizationRequest.jpake2.chunks(transactionID: 9, cargo: cargo + [0]) == nil)
        #expect(TandemAuthorizationRequest.jpake2.chunks(
            transactionID: 9, cargo: [UInt8](repeating: 0, count: Int(UInt8.max))) == nil)
    }

    private static func reassemble(_ chunks: [[UInt8]]) throws -> TandemMessage {
        var assembler = TandemPacketAssembler()
        var frame: [UInt8]?
        for (index, chunk) in chunks.enumerated() {
            let result = try assembler.feed(chunk)
            if index < chunks.count - 1 { #expect(result == nil) } else { frame = result }
        }
        let raw = try #require(frame)
        return try #require(TandemMessage.decode(raw, channel: .authorization))
    }
}

@Suite("EC-JPAKE payload codec")
struct EcJpakePayloadTests {

    @Test("Every committed payload parses, consumes the recorded byte count, and re-encodes byte for byte")
    func committedPayloadsRoundTrip() throws {
        let fixture = try EcJpakeFixture.load("handshake-client-01.json")
        let rounds = try #require(fixture["rounds"] as? [String: String])
        let reads = try #require(fixture["read_results"] as? [String: Int])

        for (name, readBy) in [("server_round1", "client_read_round1"), ("client_round1", "server_read_round1")] {
            let bytes = try EcJpakeFixture.hex(try #require(rounds[name]))
            #expect(bytes.count == 330 && EcJpakeRound1.encodedSize == 330)
            let (round, consumed) = try EcJpakeRound1.parse(bytes)
            #expect(consumed == reads[readBy])
            #expect(round.encoded() == bytes)
        }

        let server = try EcJpakeFixture.hex(try #require(rounds["server_round2"]))
        #expect(server.count == 168 && EcJpakeRound2.encodedSize(from: .server) == 168)
        let (serverRound, serverConsumed) = try EcJpakeRound2.parse(server, from: .server)
        #expect(serverConsumed == reads["client_read_round2"])
        #expect(serverRound.encoded(from: .server) == server)
        #expect(Array(server.prefix(3)) == [0x03, 0x00, 0x17])

        let client = try EcJpakeFixture.hex(try #require(rounds["client_round2"]))
        #expect(client.count == 165 && EcJpakeRound2.encodedSize(from: .client) == 165)
        let (clientRound, clientConsumed) = try EcJpakeRound2.parse(client, from: .client)
        #expect(clientConsumed == reads["server_read_round2"])
        #expect(clientRound.encoded(from: .client) == client)
    }

    @Test("The truncation fixture, rebuilt from its base payload, fails with end of stream")
    func truncatedFixture() throws {
        let fixture = try EcJpakeFixture.load("malformed-round1-truncated-01.json")
        let input = try #require(fixture["input"] as? [String: Any])
        let outcome = try #require(fixture["outcome"] as? [String: Any])
        #expect(input["call"] as? String == "readRound1")
        #expect(outcome["message"] as? String == "Unexpected end of stream")
        let corruption = try #require(input["corruption"] as? [String: Any])
        #expect(corruption["op"] as? String == "truncate")
        let base = try EcJpakeFixture.hex(try #require(input["base_payload"] as? String))
        let length = try #require(corruption["length"] as? Int)
        let rebuilt = Array(base.prefix(length))
        #expect(throws: EcJpakePayloadError.unexpectedEndOfStream) { try EcJpakeRound1.parse(rebuilt) }
        // The untouched base payload parses, so it is the truncation that fails.
        #expect(try EcJpakeRound1.parse(base).byteCount == base.count)
    }

    @Test("Every truncation of a payload fails with end of stream, never a trap")
    func everyTruncation() throws {
        let rounds = try #require(try EcJpakeFixture.load("handshake-client-01.json")["rounds"] as? [String: String])
        let round1 = try EcJpakeFixture.hex(try #require(rounds["client_round1"]))
        for length in 0..<round1.count {
            #expect(throws: EcJpakePayloadError.unexpectedEndOfStream) {
                try EcJpakeRound1.parse(Array(round1.prefix(length)))
            }
        }
        let round2 = try EcJpakeFixture.hex(try #require(rounds["server_round2"]))
        for length in 0..<round2.count {
            #expect(throws: EcJpakePayloadError.unexpectedEndOfStream) {
                try EcJpakeRound2.parse(Array(round2.prefix(length)), from: .server)
            }
        }
    }

    @Test("A server round 2 that does not name P-256 is rejected")
    func wrongCurve() throws {
        let rounds = try #require(try EcJpakeFixture.load("handshake-client-01.json")["rounds"] as? [String: String])
        let server = try EcJpakeFixture.hex(try #require(rounds["server_round2"]))
        for index in 0..<3 {
            var wrong = server
            wrong[index] ^= 0x01
            #expect(throws: EcJpakePayloadError.malformedField) { try EcJpakeRound2.parse(wrong, from: .server) }
        }
        // A client round 2 read as the server's has no prefix to find.
        let client = try EcJpakeFixture.hex(try #require(rounds["client_round2"]))
        #expect(throws: EcJpakePayloadError.self) { try EcJpakeRound2.parse(client, from: .server) }
    }

    @Test("A compressed or wrongly sized point is malformed")
    func malformedPoint() throws {
        let rounds = try #require(try EcJpakeFixture.load("handshake-client-01.json")["rounds"] as? [String: String])
        let round1 = try EcJpakeFixture.hex(try #require(rounds["client_round1"]))
        var compressed = round1
        compressed[1] = 0x02
        #expect(throws: EcJpakePayloadError.malformedField) { try EcJpakeRound1.parse(compressed) }
        var shortLength = round1
        shortLength[0] = 64
        #expect(throws: EcJpakePayloadError.malformedField) { try EcJpakeRound1.parse(shortLength) }
    }

    @Test("Scalars are always written at 32 bytes, zero-padded")
    func scalarZeroPadding() throws {
        let one = try #require(EcJpakeScalar(bytes: [0x01]))
        #expect(one.bytes == [UInt8](repeating: 0, count: 31) + [0x01])
        #expect(EcJpakeScalar(bytes: [UInt8](repeating: 0, count: 33)) == nil)

        // A scalar whose top byte is zero is the Android minimal-length trap.
        let point = try #require(EcJpakePoint(bytes: [0x04] + [UInt8](repeating: 0x11, count: 64)))
        let leadingZero = try #require(EcJpakeScalar(bytes: [0x00] + [UInt8](repeating: 0x22, count: 31)))
        let round = EcJpakeRound2(point: point, proof: EcJpakeProof(commitment: point, response: leadingZero))
        let encoded = round.encoded(from: .client)
        #expect(encoded.count == 165)
        #expect(encoded[132] == 32)
        #expect(encoded[133] == 0x00)
    }

    @Test("A scalar written at minimal length is read and normalised to 32 bytes")
    func shortScalarIsNormalised() throws {
        let point = [UInt8]([65, 0x04]) + [UInt8](repeating: 0x11, count: 64)
        let payload = point + point + [31] + [UInt8](repeating: 0x22, count: 31)
        let (round, consumed) = try EcJpakeRound2.parse(payload, from: .client)
        #expect(consumed == payload.count)
        #expect(round.proof.response.bytes == [0] + [UInt8](repeating: 0x22, count: 31))
        #expect(round.encoded(from: .client).count == 165)
    }
}

/// Reads the committed vectors in place. They are not package resources:
/// `validate_fixtures.py` and `verify_vectors.sh` expect them where they are.
enum EcJpakeFixture {
    struct BadHex: Error {}

    static func load(_ name: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TandemWireTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
        let url = root.appendingPathComponent("Tests/Fixtures/EcJpake").appendingPathComponent(name)
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        return try #require(object as? [String: Any])
    }

    static func hex(_ value: String) throws -> [UInt8] {
        let digits = Array(value.utf8)
        guard digits.count.isMultiple(of: 2) else { throw BadHex() }
        return try stride(from: 0, to: digits.count, by: 2).map { index in
            guard let byte = UInt8(String(decoding: digits[index..<index + 2], as: UTF8.self), radix: 16) else {
                throw BadHex()
            }
            return byte
        }
    }
}
