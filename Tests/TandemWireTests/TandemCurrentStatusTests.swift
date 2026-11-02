import Testing
@testable import TandemWire

@Suite("Tandem current status")
struct TandemCurrentStatusTests {
    @Test func egvAndroidVector() throws {
        let response = try #require(TandemEGVResponse.parse(Self.bytes("c87c131c7b000100")))
        #expect(response.pumpSeconds == 471039176)
        #expect(response.glucoseMgdl == 123)
        #expect(response.egvStatusID == 1)
        #expect(response.trendRate == 0)
        #expect(TandemEGVResponse.parse([0, 1, 2, 3, 4, 5, 6]) == nil)
        let ungated = try #require(TandemEGVResponse.parse([0, 0, 0, 0, 0xFF, 0xFF, 0, 0xFF]))
        #expect(ungated.glucoseMgdl == UInt16.max)
        #expect(ungated.egvStatusID == 0)
        #expect(ungated.trendRate == -1)
    }

    @Test func iobSelectors() throws {
        let prefix = Self.bytes("c4090000201c0000b80b0000dc050000")
        for (selector, expected) in [(UInt8(0), UInt32(2500)), (1, 1500), (2, 2500)] {
            let response = try #require(TandemIOBResponse.parse(prefix + [selector]))
            #expect(response.mudaliarMilliunits == 2500)
            #expect(response.timeRemainingSeconds == 7200)
            #expect(response.mudaliarTotalMilliunits == 3000)
            #expect(response.swan6hrMilliunits == 1500)
            #expect(response.selector == selector)
            #expect(response.selectedMilliunits == expected)
        }
        #expect(TandemIOBResponse.parse(Array(prefix)) == nil)
    }

    @Test func iobAndroidVectors() throws {
        let first = try #require(TandemIOBResponse.parse(Self.bytes("c00000007c380000f1000000a100000000")))
        #expect(first.mudaliarMilliunits == 192)
        #expect(first.timeRemainingSeconds == 14460)
        #expect(first.mudaliarTotalMilliunits == 241)
        #expect(first.swan6hrMilliunits == 161)
        #expect(first.selectedMilliunits == 192)
        let second = try #require(TandemIOBResponse.parse(Self.bytes("b80000008c370000f10000009a00000001")))
        #expect(second.mudaliarMilliunits == 184)
        #expect(second.timeRemainingSeconds == 14220)
        #expect(second.mudaliarTotalMilliunits == 241)
        #expect(second.swan6hrMilliunits == 154)
        #expect(second.selectedMilliunits == 154)
    }

    private static func bytes(_ hex: String) -> [UInt8] {
        let chars = Array(hex.utf8)
        return stride(from: 0, to: chars.count, by: 2).compactMap { index in
            UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16)
        }
    }
}
