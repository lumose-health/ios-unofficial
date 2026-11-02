public struct TandemEGVResponse: Equatable, Sendable {
    public static let opcode: UInt8 = 35

    public let pumpSeconds: UInt32
    public let glucoseMgdl: UInt16
    public let egvStatusID: UInt8
    public let trendRate: Int8

    public static func parse(_ cargo: [UInt8]) -> TandemEGVResponse? {
        guard cargo.count >= 8 else { return nil }
        return TandemEGVResponse(
            pumpSeconds: readUInt32(cargo, at: 0),
            glucoseMgdl: UInt16(cargo[4]) | (UInt16(cargo[5]) << 8),
            egvStatusID: cargo[6],
            trendRate: Int8(bitPattern: cargo[7])
        )
    }
}

public struct TandemIOBResponse: Equatable, Sendable {
    public static let opcode: UInt8 = 109

    public let mudaliarMilliunits: UInt32
    public let timeRemainingSeconds: UInt32
    public let mudaliarTotalMilliunits: UInt32
    public let swan6hrMilliunits: UInt32
    public let selector: UInt8

    public var selectedMilliunits: UInt32 {
        selector == 1 ? swan6hrMilliunits : mudaliarMilliunits
    }

    public static func parse(_ cargo: [UInt8]) -> TandemIOBResponse? {
        guard cargo.count >= 17 else { return nil }
        return TandemIOBResponse(
            mudaliarMilliunits: readUInt32(cargo, at: 0),
            timeRemainingSeconds: readUInt32(cargo, at: 4),
            mudaliarTotalMilliunits: readUInt32(cargo, at: 8),
            swan6hrMilliunits: readUInt32(cargo, at: 12),
            selector: cargo[16]
        )
    }
}

private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset])
        | (UInt32(bytes[offset + 1]) << 8)
        | (UInt32(bytes[offset + 2]) << 16)
        | (UInt32(bytes[offset + 3]) << 24)
}
