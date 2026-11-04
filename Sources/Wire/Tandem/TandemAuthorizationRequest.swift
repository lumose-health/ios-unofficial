/// The only outbound messages this package can frame (SI-1, AD-12).
///
/// A closed set: the two legacy challenge requests and the five EC-JPAKE
/// requests on the authorization characteristic. There is no initializer from
/// an opcode, so no other message can be framed through ``chunks(transactionID:cargo:)``.
///
/// Tandem numbers each request/response pair consecutively within a family,
/// request even and response odd: legacy from 16, EC-JPAKE from 32.
public enum TandemAuthorizationRequest: CaseIterable, Sendable {
    /// Legacy handshake: central challenge, then pump challenge.
    case centralChallenge, pumpChallenge
    /// EC-JPAKE: round 1 in two halves, round 2, session key, key confirmation.
    case jpake1a, jpake1b, jpake2, jpake3, jpake4

    private static let legacyFamilyBase: UInt8 = 16
    private static let jpakeFamilyBase: UInt8 = 32
    /// A request and its response occupy two consecutive opcodes.
    private static let opcodesPerExchange: UInt8 = 2

    /// The request opcode. The response opcode is one more.
    public var opcode: UInt8 {
        switch self {
        case .centralChallenge: Self.legacyFamilyBase
        case .pumpChallenge: Self.legacyFamilyBase + Self.opcodesPerExchange
        case .jpake1a: Self.jpakeFamilyBase
        case .jpake1b: Self.jpakeFamilyBase + Self.opcodesPerExchange
        case .jpake2: Self.jpakeFamilyBase + 2 * Self.opcodesPerExchange
        case .jpake3: Self.jpakeFamilyBase + 3 * Self.opcodesPerExchange
        case .jpake4: Self.jpakeFamilyBase + 4 * Self.opcodesPerExchange
        }
    }

    /// Bytes of each chunk header: packets remaining, then the transaction ID.
    static let chunkHeaderSize = 2
    /// Frame bytes carried per chunk on the authorization characteristic.
    static let shortChunkPayloadSize = 16
    /// Largest chunk on the authorization characteristic, header included
    /// (Android `TandemProtocol.CHUNK_SIZE_SHORT`).
    public static let maximumChunkSize = chunkHeaderSize + shortChunkPayloadSize
    /// Packets remaining is a 4-bit field, so a frame spans at most 16 chunks.
    static let maximumChunkCount = 16
    /// Largest cargo whose frame fits in ``maximumChunkCount`` chunks (251 bytes).
    public static let maximumCargoSize = maximumChunkCount * shortChunkPayloadSize
        - TandemPacketAssembler.frameHeaderSize - TandemPacketAssembler.frameChecksumSize

    /// Builds the canonical frame — opcode, transaction ID, cargo length, cargo,
    /// CRC-16 little-endian — and splits it into chunks whose first byte holds
    /// the packets remaining after it (low nibble) and whose second byte is the
    /// transaction ID. Same layout as the Android client's `Packetize.encode`.
    ///
    /// Returns `nil` when `cargo` is longer than ``maximumCargoSize``. The
    /// remaining count must fit in four bits: a count that wrapped to zero would
    /// end the frame early at the receiver.
    public func chunks(transactionID: UInt8, cargo: [UInt8]) -> [[UInt8]]? {
        guard cargo.count <= Self.maximumCargoSize else { return nil }
        var frame = [opcode, transactionID, UInt8(cargo.count)] + cargo
        let checksum = TandemMessage.crc16(frame)
        frame.append(UInt8(truncatingIfNeeded: checksum))
        frame.append(UInt8(truncatingIfNeeded: checksum >> 8))

        let size = Self.shortChunkPayloadSize
        let count = (frame.count + size - 1) / size
        return (0..<count).map { index in
            let start = index * size
            let end = min(start + size, frame.count)
            return [UInt8(count - index - 1), transactionID] + frame[start..<end]
        }
    }
}
