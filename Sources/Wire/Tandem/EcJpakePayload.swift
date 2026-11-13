// EC-JPAKE payload byte layout, as written and read by the Android client's
// `EcJpake.kt` (a port of particle-iot/ecjpake-java, Apache-2.0, Copyright 2022
// Particle Industries, Inc.). Layout only: no hashing, no point arithmetic, no
// proof checking (AD-8). See Tests/Fixtures/EcJpake/README.md:
//   point   1-byte length (65) + uncompressed SEC1 encoding (0x04 || X || Y)
//   scalar  1-byte length (32) + 32 big-endian bytes, zero-padded
//   proof   point (commitment V) + scalar (response r)
//   round 1 point X1, proof, point X2, proof            (330 bytes)
//   round 2 [server only: 03 00 17] point X, proof      (165 / 168 bytes)

/// Why an EC-JPAKE payload could not be read. The handshake maps every case
/// onto one `PairingRejection` (AD-13).
public enum EcJpakePayloadError: Error, Equatable, Sendable {
    /// The payload ended before a field it declares (the truncation fixture).
    case unexpectedEndOfStream
    /// A field this protocol does not allow: a point that is not 65-byte
    /// uncompressed, a scalar over 32 bytes, or a server round 2 that does not
    /// name P-256.
    case malformedField
}

/// A P-256 point in uncompressed SEC1 form. Only the encoding is checked;
/// whether it lies on the curve is the arithmetic layer's question.
public struct EcJpakePoint: Equatable, Sendable {
    public static let encodedSize = 65
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.encodedSize, bytes.first == 0x04 else { return nil }
        self.bytes = bytes
    }
}

/// A scalar, always held and written as exactly 32 big-endian bytes.
///
/// Writing a scalar at its minimal length causes intermittent pairing failures,
/// because roughly 1 in 256 scalars has a leading zero byte and comes out short.
/// This type cannot hold one.
public struct EcJpakeScalar: Equatable, Sendable {
    public static let encodedSize = 32
    public let bytes: [UInt8]

    /// Left-pads `bytes` with zeros to 32 bytes. `nil` when longer.
    public init?(bytes: [UInt8]) {
        guard bytes.count <= Self.encodedSize else { return nil }
        self.bytes = [UInt8](repeating: 0, count: Self.encodedSize - bytes.count) + bytes
    }
}

/// A Schnorr zero-knowledge proof: commitment V and response r.
public struct EcJpakeProof: Equatable, Sendable {
    public let commitment: EcJpakePoint
    public let response: EcJpakeScalar

    public init(commitment: EcJpakePoint, response: EcJpakeScalar) {
        self.commitment = commitment
        self.response = response
    }

    static let encodedSize = 2 * EcJpakeReader.lengthPrefixSize + EcJpakePoint.encodedSize + EcJpakeScalar.encodedSize

    func encoded() -> [UInt8] {
        commitment.field + [UInt8(EcJpakeScalar.encodedSize)] + response.bytes
    }
}

/// Round 1 from either role: two public points, each with its proof.
public struct EcJpakeRound1: Equatable, Sendable {
    public static let encodedSize = 2 * (EcJpakePoint.fieldSize + EcJpakeProof.encodedSize)

    public let firstPoint: EcJpakePoint
    public let firstProof: EcJpakeProof
    public let secondPoint: EcJpakePoint
    public let secondProof: EcJpakeProof

    public init(firstPoint: EcJpakePoint, firstProof: EcJpakeProof,
                secondPoint: EcJpakePoint, secondProof: EcJpakeProof) {
        self.firstPoint = firstPoint
        self.firstProof = firstProof
        self.secondPoint = secondPoint
        self.secondProof = secondProof
    }

    /// Reads round 1 from the start of `bytes` and returns it with the number
    /// of bytes consumed. Trailing bytes are the caller's to judge, as with
    /// Android's `readRound1`.
    public static func parse(_ bytes: [UInt8]) throws(EcJpakePayloadError) -> (round: Self, byteCount: Int) {
        var reader = EcJpakeReader(bytes)
        let round = Self(firstPoint: try reader.point(), firstProof: try reader.proof(),
                         secondPoint: try reader.point(), secondProof: try reader.proof())
        return (round, reader.offset)
    }

    public func encoded() -> [UInt8] {
        firstPoint.field + firstProof.encoded() + secondPoint.field + secondProof.encoded()
    }
}

/// Round 2 from either role: one point and its proof. Only the server's is
/// prefixed with the named-curve announcement.
public struct EcJpakeRound2: Equatable, Sendable {
    public enum Sender: Sendable { case client, server }

    /// `ECCurveType.named_curve` (3), then secp256r1's RFC 4492 id (23) big-endian.
    static let namedCurvePrefix: [UInt8] = [0x03, 0x00, 0x17]

    public static func encodedSize(from sender: Sender) -> Int {
        prefix(sender).count + EcJpakePoint.fieldSize + EcJpakeProof.encodedSize
    }

    public let point: EcJpakePoint
    public let proof: EcJpakeProof

    public init(point: EcJpakePoint, proof: EcJpakeProof) {
        self.point = point
        self.proof = proof
    }

    /// Reads round 2 as written by `sender`, returning the bytes consumed. A
    /// server payload whose prefix does not name P-256 is ``EcJpakePayloadError/malformedField``.
    public static func parse(
        _ bytes: [UInt8], from sender: Sender
    ) throws(EcJpakePayloadError) -> (round: Self, byteCount: Int) {
        var reader = EcJpakeReader(bytes)
        guard try reader.take(prefix(sender).count) == prefix(sender) else { throw .malformedField }
        let round = Self(point: try reader.point(), proof: try reader.proof())
        return (round, reader.offset)
    }

    public func encoded(from sender: Sender) -> [UInt8] {
        Self.prefix(sender) + point.field + proof.encoded()
    }

    private static func prefix(_ sender: Sender) -> [UInt8] {
        sender == .server ? namedCurvePrefix : []
    }
}

extension EcJpakePoint {
    static let fieldSize = EcJpakeReader.lengthPrefixSize + encodedSize
    var field: [UInt8] { [UInt8(Self.encodedSize)] + bytes }
}

/// A forward-only reader. Fields are length-prefixed and the declared length
/// is honoured, as Android reads them, so a short payload is end of stream.
struct EcJpakeReader {
    static let lengthPrefixSize = 1
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func take(_ count: Int) throws(EcJpakePayloadError) -> [UInt8] {
        guard bytes.count - offset >= count else { throw .unexpectedEndOfStream }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    private mutating func field() throws(EcJpakePayloadError) -> [UInt8] {
        try take(Int(try take(Self.lengthPrefixSize)[0]))
    }

    mutating func point() throws(EcJpakePayloadError) -> EcJpakePoint {
        guard let point = EcJpakePoint(bytes: try field()) else { throw .malformedField }
        return point
    }

    /// A scalar written at less than full width is accepted, as on Android,
    /// and normalised to 32 bytes.
    mutating func scalar() throws(EcJpakePayloadError) -> EcJpakeScalar {
        guard let scalar = EcJpakeScalar(bytes: try field()) else { throw .malformedField }
        return scalar
    }

    mutating func proof() throws(EcJpakePayloadError) -> EcJpakeProof {
        EcJpakeProof(commitment: try point(), response: try scalar())
    }
}
