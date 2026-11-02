import DriverAPI

/// Reassembles notification fragments for one message at a time.
///
/// The assembled frame is bounded at ``maximumFrameSize``. A fragment that would
/// push it past that bound resets the assembly and throws: a malformed stream
/// that keeps one transaction ID and a nonzero packets-remaining nibble must not
/// grow the buffer without limit, and a truncated frame must never be handed on.
///
/// The Android client's `PacketAssembler.kt` does not bound the assembled frame;
/// it appends every fragment for a matching transaction ID.
public struct TandemPacketAssembler: Sendable {
    /// Header bytes of a canonical frame: opcode, transaction ID, cargo length.
    static let frameHeaderSize = 3
    /// Largest cargo the one-byte cargo length can declare.
    static let maximumCargoSize = Int(UInt8.max)
    /// Trailing CRC-16 bytes.
    static let frameChecksumSize = 2
    /// Largest canonical frame: header + maximum cargo + CRC (260 bytes).
    public static let maximumFrameSize = frameHeaderSize + maximumCargoSize + frameChecksumSize

    private var transactionID: UInt8?
    private var payload: [UInt8] = []

    public init() {}

    /// Feeds one notification. Returns the assembled frame when the last
    /// fragment arrives, `nil` while more fragments are expected.
    ///
    /// - Throws: `DriverFailure.decodeFailed` when the assembled frame would
    ///   exceed ``maximumFrameSize``. The partial frame is discarded and the
    ///   assembler is ready for a fresh message.
    public mutating func feed(_ notification: [UInt8]) throws(DriverFailure) -> [UInt8]? {
        guard notification.count >= 2 else { return nil }
        let incomingID = notification[1]
        if transactionID != incomingID {
            transactionID = incomingID
            payload.removeAll(keepingCapacity: true)
        }
        let fragment = notification.dropFirst(2)
        guard payload.count + fragment.count <= Self.maximumFrameSize else {
            reset()
            throw .decodeFailed(detail: "Tandem frame exceeds maximum size")
        }
        payload.append(contentsOf: fragment)
        guard notification[0] & 0x0F == 0 else { return nil }
        let message = payload
        reset()
        return message
    }

    private mutating func reset() {
        payload.removeAll(keepingCapacity: true)
        transactionID = nil
    }
}
