public enum TandemChannel: String, CaseIterable, Sendable {
    case currentStatus, qualifyingEvents, historyLog, authorization, control, controlStream
}

/// A frame whose declared cargo and checksum have passed validation.
public struct TandemMessage: Equatable, Sendable {
    public let channel: TandemChannel
    public let opcode: UInt8
    public let transactionID: UInt8
    public let cargo: [UInt8]

    public static func decode(_ raw: [UInt8], channel: TandemChannel) -> TandemMessage? {
        guard raw.count >= 5 else { return nil }
        let cargoEnd = 3 + Int(raw[2])
        guard raw.count >= cargoEnd + 2 else { return nil }
        let actual = UInt16(raw[cargoEnd]) | (UInt16(raw[cargoEnd + 1]) << 8)
        guard crc16(Array(raw[..<cargoEnd])) == actual else { return nil }
        return TandemMessage(
            channel: channel,
            opcode: raw[0],
            transactionID: raw[1],
            cargo: Array(raw[3..<cargoEnd])
        )
    }

    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var remainder: UInt16 = 0xFFFF
        for byte in bytes {
            remainder ^= UInt16(byte) << 8
            for _ in 0..<8 {
                remainder = (remainder & 0x8000 == 0)
                    ? (remainder &<< 1)
                    : ((remainder &<< 1) ^ 0x1021)
            }
        }
        return remainder
    }
}
