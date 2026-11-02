import Foundation
import DriverAPI
import TandemWire

struct TraceFile: Decodable, Sendable {
    /// Largest trace file accepted, checked before any JSON is parsed.
    static let maximumFileBytes = 4 * 1024 * 1024
    /// Most frames one trace may hold; also sizes the replay stream buffers.
    static let maximumFrameCount = 4096

    let description: String
    let pumpTimeZone: TimeZone
    let provenance: Provenance
    let frames: [Frame]

    struct Provenance: Decodable, Sendable {
        let source: String
        let method: String
        let reviewedBy: String?

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: TraceKey.self)
            try values.requireExactly(["source", "method", "reviewedBy"])
            source = try values.decode(String.self, forKey: TraceKey("source"))
            method = try values.decode(String.self, forKey: TraceKey("method"))
            reviewedBy = try values.decodeIfPresent(String.self, forKey: TraceKey("reviewedBy"))
            guard ["synthesized", "deidentified-capture"].contains(source),
                  !method.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  source != "deidentified-capture" || !(reviewedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw TraceFormatError.invalid }
        }
    }

    struct Frame: Decodable, Sendable {
        let channel: TandemChannel
        let receivedAt: Date
        let notifications: [[UInt8]]
        let note: String

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: TraceKey.self)
            try values.requireExactly(["channel", "receivedAt", "notifications", "note"])
            let rawChannel = try values.decode(String.self, forKey: TraceKey("channel"))
            guard let channel = TandemChannel(rawValue: rawChannel) else { throw TraceFormatError.invalid }
            self.channel = channel
            receivedAt = try values.decode(Date.self, forKey: TraceKey("receivedAt"))
            note = try values.decode(String.self, forKey: TraceKey("note"))
            let hex = try values.decode([String].self, forKey: TraceKey("notifications"))
            guard !hex.isEmpty else { throw TraceFormatError.invalid }
            notifications = try hex.map(Self.bytes)
        }

        private static func bytes(_ hex: String) throws -> [UInt8] {
            let chars = Array(hex.utf8)
            guard !chars.isEmpty, chars.count.isMultiple(of: 2) else { throw TraceFormatError.invalid }
            var result: [UInt8] = []
            for index in stride(from: 0, to: chars.count, by: 2) {
                let alphabet = Array("0123456789abcdef".utf8)
                guard let highIndex = alphabet.firstIndex(of: chars[index]),
                      let lowIndex = alphabet.firstIndex(of: chars[index + 1]) else {
                    throw TraceFormatError.invalid
                }
                let high = UInt8(highIndex)
                let low = UInt8(lowIndex)
                result.append((high << 4) | low)
            }
            return result
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: TraceKey.self)
        try values.requireExactly(["format", "version", "vendor", "description", "pumpTimeZone", "provenance", "frames"])
        guard try values.decode(String.self, forKey: TraceKey("format")) == "glycemicgpt-trace",
              try values.decode(Int.self, forKey: TraceKey("version")) == 1,
              try values.decode(String.self, forKey: TraceKey("vendor")) == "tandem"
        else { throw TraceFormatError.invalid }
        description = try values.decode(String.self, forKey: TraceKey("description"))
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TraceFormatError.invalid }
        let zone = try values.decode(String.self, forKey: TraceKey("pumpTimeZone"))
        guard TimeZone.knownTimeZoneIdentifiers.contains(zone), let pumpTimeZone = TimeZone(identifier: zone) else {
            throw TraceFormatError.invalid
        }
        self.pumpTimeZone = pumpTimeZone
        provenance = try values.decode(Provenance.self, forKey: TraceKey("provenance"))
        frames = try values.decode([Frame].self, forKey: TraceKey("frames"))
        guard !frames.isEmpty, frames.count <= Self.maximumFrameCount else { throw TraceFormatError.invalid }
        // Receive times come from one phone clock and replay derives every timestamp
        // from them, so a trace whose receive times go backwards is rejected.
        for (earlier, later) in zip(frames, frames.dropFirst()) where later.receivedAt < earlier.receivedAt {
            throw TraceFormatError.invalid
        }
    }

    static func load(_ data: Data) throws(DriverFailure) -> TraceFile {
        guard data.count <= maximumFileBytes else { throw .decodeFailed(detail: "trace file") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(TraceFile.self, from: data) }
        catch { throw .decodeFailed(detail: "trace file") }
    }
}

private enum TraceFormatError: Error { case invalid }

private struct TraceKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int? = nil
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

private extension KeyedDecodingContainer where Key == TraceKey {
    func requireExactly(_ keys: Set<String>) throws {
        guard Set(allKeys.map(\.stringValue)) == keys else { throw TraceFormatError.invalid }
    }
}
