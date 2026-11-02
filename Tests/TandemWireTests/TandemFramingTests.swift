import Testing
import DriverAPI
@testable import TandemWire

@Suite("Tandem framing")
struct TandemFramingTests {
    @Test func crcCheckValue() {
        #expect(TandemMessage.crc16(Array("123456789".utf8)) == 0x29B1)
    }

    @Test func assemblerVectors() throws {
        var assembler = TandemPacketAssembler()
        #expect(try assembler.feed([0x00, 0x01, 0xAA, 0xBB]) == [0xAA, 0xBB])
        #expect(try assembler.feed([0x01, 0x05, 0x01, 0x02]) == nil)
        #expect(try assembler.feed([0x00, 0x05, 0x03, 0x04]) == [0x01, 0x02, 0x03, 0x04])
        #expect(try assembler.feed([0x01, 0x01, 0xAA]) == nil)
        #expect(try assembler.feed([0x00, 0x02, 0xBB]) == [0xBB])
        #expect(try assembler.feed([0x00]) == nil)
    }

    @Test func maximumFrameSizeIsHeaderPlusMaximumCargoPlusCRC() {
        #expect(TandemPacketAssembler.maximumFrameSize == 3 + 255 + 2)
    }

    @Test func frameOfExactlyMaximumSizeAssembles() throws {
        var assembler = TandemPacketAssembler()
        let first = [UInt8](repeating: 0x11, count: 130)
        let last = [UInt8](repeating: 0x22, count: 130)
        #expect(try assembler.feed([0x01, 0x07] + first) == nil)
        let frame = try #require(try assembler.feed([0x00, 0x07] + last))
        #expect(frame.count == TandemPacketAssembler.maximumFrameSize)
        #expect(frame == first + last)
    }

    @Test func sameTransactionStreamPastTheBoundIsRejectedAndResets() throws {
        var assembler = TandemPacketAssembler()
        let fragment = [UInt8](repeating: 0x33, count: 18)
        var fed = 0
        while fed + fragment.count <= TandemPacketAssembler.maximumFrameSize {
            #expect(try assembler.feed([0x01, 0x09] + fragment) == nil)
            fed += fragment.count
        }
        #expect(throws: DriverFailure.decodeFailed(detail: "Tandem frame exceeds maximum size")) {
            try assembler.feed([0x01, 0x09] + fragment)
        }
        // The partial frame was discarded: a final fragment on the same
        // transaction ID yields only its own bytes, not the overflowed prefix.
        #expect(try assembler.feed([0x00, 0x09, 0xAB]) == [0xAB])
    }

    @Test func freshMessageAssemblesAfterARejection() throws {
        var assembler = TandemPacketAssembler()
        let oversized = [UInt8](repeating: 0x44, count: TandemPacketAssembler.maximumFrameSize + 1)
        #expect(throws: DriverFailure.self) {
            try assembler.feed([0x00, 0x03] + oversized)
        }
        #expect(try assembler.feed([0x01, 0x04, 0x01, 0x02]) == nil)
        #expect(try assembler.feed([0x00, 0x04, 0x03]) == [0x01, 0x02, 0x03])
    }

    @Test func twoPacketIOBMessage() throws {
        var assembler = TandemPacketAssembler()
        #expect(try assembler.feed(Self.bytes("01026d0211c4090000201c0000b80b0000dc")) == nil)
        let completed = try assembler.feed(Self.bytes("00020500000069a7"))
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
