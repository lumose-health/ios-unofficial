import Testing
@testable import TandemWire

@Suite("Tandem framing")
struct TandemFramingTests {
    @Test func crcCheckValue() {
        #expect(TandemMessage.crc16(Array("123456789".utf8)) == 0x29B1)
    }

    @Test func assemblerVectors() {
        var assembler = TandemPacketAssembler()
        #expect(assembler.feed([0x00, 0x01, 0xAA, 0xBB]) == [0xAA, 0xBB])
        #expect(assembler.feed([0x01, 0x05, 0x01, 0x02]) == nil)
        #expect(assembler.feed([0x00, 0x05, 0x03, 0x04]) == [0x01, 0x02, 0x03, 0x04])
        #expect(assembler.feed([0x01, 0x01, 0xAA]) == nil)
        #expect(assembler.feed([0x00, 0x02, 0xBB]) == [0xBB])
        #expect(assembler.feed([0x00]) == nil)
    }

    @Test func twoPacketIOBMessage() throws {
        var assembler = TandemPacketAssembler()
        #expect(assembler.feed(Self.bytes("01026d0211c4090000201c0000b80b0000dc")) == nil)
        let completed = assembler.feed(Self.bytes("00020500000069a7"))
        let raw = try #require(completed)
        let message = try #require(TandemMessage.decode(raw, channel: .currentStatus))
        #expect(message.opcode == TandemIOBResponse.opcode)
        #expect(message.transactionID == 2)
        #expect(message.channel == .currentStatus)
        #expect(TandemIOBResponse.parse(message.cargo)?.selectedMilliunits == 2500)
    }

    @Test func malformedFramesAreRefused() {
        #expect(TandemMessage.decode([], channel: .currentStatus) == nil)
        #expect(TandemMessage.decode([35, 1, 0, 0], channel: .currentStatus) == nil)
        #expect(TandemMessage.decode([35, 1, 8, 0, 0], channel: .currentStatus) == nil)
        var corrupt = Self.bytes("23010880e80d207b000100561f")
        corrupt[3] ^= 1
        #expect(TandemMessage.decode(corrupt, channel: .currentStatus) == nil)
    }

    private static func bytes(_ hex: String) -> [UInt8] {
        let chars = Array(hex.utf8)
        return stride(from: 0, to: chars.count, by: 2).compactMap { index in
            UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16)
        }
    }
}
