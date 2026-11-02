import Foundation
import Testing
@_spi(DriverPlatform) import DriverAPI
@testable import TandemWire

@Suite("Tandem read mapping")
struct TandemReadMapperTests {
    private let receivedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func malformedResponsesHaveTypedFailures() throws {
        let mapper = try Self.mapper()
        let shortEGV = try Self.message(opcode: TandemEGVResponse.opcode, cargo: [0, 1])
        let shortIOB = try Self.message(opcode: TandemIOBResponse.opcode, cargo: [0, 1])
        let egvFailure = #expect(throws: DriverFailure.self) {
            try mapper.map(shortEGV, receivedAt: receivedAt, pumpTimeZone: Self.utc())
        }
        let iobFailure = #expect(throws: DriverFailure.self) {
            try mapper.map(shortIOB, receivedAt: receivedAt, pumpTimeZone: Self.utc())
        }
        #expect(egvFailure == .decodeFailed(detail: "CurrentEGVGuiDataResponse"))
        #expect(iobFailure == .decodeFailed(detail: "ControlIQIOBResponse"))
        for failure in [egvFailure, iobFailure] {
            guard case .decodeFailed(let detail) = failure else { continue }
            #expect(detail.range(of: "[0-9]{2,}", options: .regularExpression) == nil)
        }
    }

    @Test func unresolvablePumpTimeIsDecodeFailure() throws {
        let validator = SafetyLimitsValidator(limits: try SafetyLimits(glucoseLower: 20, glucoseUpper: 500))
        let mapper = TandemReadMapper(validator: validator, resolvePumpTime: { _, _ in nil })
        for status: UInt8 in [1, 2, 3] {
            #expect(throws: DriverFailure.decodeFailed(detail: "pump timestamp")) {
                try mapper.map(Self.egv(glucose: 123, status: status), receivedAt: receivedAt, pumpTimeZone: Self.utc())
            }
        }
    }

    @Test func deviceStatusesGateBeforeValues() throws {
        let mapper = try Self.mapper()
        for status: UInt8 in [0, 4, 255] {
            let outcome = try mapper.map(Self.egv(glucose: 123, status: status), receivedAt: receivedAt, pumpTimeZone: Self.utc())
            #expect(outcome == .sensorReadingUnusable(egvStatusID: status))
            let zeroValue = try mapper.map(Self.egv(glucose: 0, status: status), receivedAt: receivedAt, pumpTimeZone: Self.utc())
            #expect(zeroValue == .sensorReadingUnusable(egvStatusID: status))
        }
        let outcome = try mapper.map(Self.egv(glucose: 123, status: 1), receivedAt: receivedAt, pumpTimeZone: Self.utc())
        guard case .glucose(let sample) = outcome else {
            Issue.record("expected glucose for status 1")
            return
        }
        #expect(sample.glucose.mgdl == 123)
        #expect(sample.recordedAt == Self.recordedAtUTC)
        #expect(sample.trend == nil)
    }

    /// LOW and HIGH never become a number, whatever value the frame carries: the edge of the
    /// sensor range (40 and 400 on Dexcom-class sensors), a value inside the range, zero, and
    /// a value the validator would refuse.
    @Test func lowAndHighStatusesAreOutOfRangeAndCarryNoNumber() throws {
        let mapper = try Self.mapper()
        let cases: [(UInt8, TandemGlucoseRangeSide)] = [(2, .below), (3, .above)]
        for (status, side) in cases {
            for glucose: UInt16 in [40, 400, 123, 0, 65535] {
                let outcome = try mapper.map(
                    Self.egv(glucose: glucose, status: status),
                    receivedAt: receivedAt,
                    pumpTimeZone: Self.utc()
                )
                #expect(outcome == .outOfRange(side, recordedAt: Self.recordedAtUTC))
            }
        }
    }

    @Test func outOfRangeIgnoresNarrowedLimits() throws {
        let validator = SafetyLimitsValidator(limits: try SafetyLimits(glucoseLower: 20, glucoseUpper: 500))
        validator.adopt(try SafetyLimits(glucoseLower: 150, glucoseUpper: 200))
        let mapper = TandemReadMapper(validator: validator)
        let outcome = try mapper.map(Self.egv(glucose: 40, status: 2), receivedAt: receivedAt, pumpTimeZone: Self.utc())
        #expect(outcome == .outOfRange(.below, recordedAt: Self.recordedAtUTC))
    }

    @Test func sameFrameResolvesAgainstTheZoneOfEachCall() throws {
        let mapper = try Self.mapper()
        let frame = try Self.egv(glucose: 123, status: 1)
        let low = try Self.egv(glucose: 40, status: 2)
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        let sydney = try #require(TimeZone(identifier: "Australia/Sydney"))
        // Pump wall clock 2025-01-15 08:00: CST is UTC-6, AEDT is UTC+11.
        let rows: [(TimeZone, Date)] = [
            (chicago, Date(timeIntervalSince1970: 1_736_949_600)),
            (sydney, Date(timeIntervalSince1970: 1_736_888_400)),
            (chicago, Date(timeIntervalSince1970: 1_736_949_600)),
        ]
        for (zone, expected) in rows {
            guard case .glucose(let sample) = try mapper.map(frame, receivedAt: receivedAt, pumpTimeZone: zone) else {
                Issue.record("expected glucose in \(zone.identifier)")
                continue
            }
            #expect(sample.recordedAt == expected)
            #expect(try mapper.map(low, receivedAt: receivedAt, pumpTimeZone: zone) == .outOfRange(.below, recordedAt: expected))
        }
    }

    @Test func validatorFailureIsPreservedAndLimitsAreReadEachTime() throws {
        let limits = try SafetyLimits(glucoseLower: 20, glucoseUpper: 500)
        let validator = SafetyLimitsValidator(limits: limits)
        let mapper = TandemReadMapper(validator: validator)
        let frame = try Self.egv(glucose: 123, status: 1)
        #expect(try mapper.map(frame, receivedAt: receivedAt, pumpTimeZone: Self.utc()) != .sensorReadingUnusable(egvStatusID: 1))
        let narrow = try SafetyLimits(glucoseLower: 150, glucoseUpper: 200)
        validator.adopt(narrow)
        let expected = #expect(throws: DriverFailure.self) { try validator.validate(mgdl: 123) }
        let actual = #expect(throws: DriverFailure.self) { try mapper.map(frame, receivedAt: receivedAt, pumpTimeZone: Self.utc()) }
        #expect(actual == expected)
        guard case .valueRejected(let bound) = actual else {
            Issue.record("expected the validator's value rejection")
            return
        }
        #expect(!bound.isEmpty)
        #expect(throws: DriverFailure.valueRejected(bound: bound)) {
            try mapper.map(Self.egv(glucose: 0, status: 1), receivedAt: receivedAt, pumpTimeZone: Self.utc())
        }
    }

    @Test func selectedIOBAndReceiveInstant() throws {
        let mapper = try Self.mapper()
        let prefix = Self.bytes("c4090000201c0000b80b0000dc050000")
        for (selector, units) in [(UInt8(0), 2.5), (1, 1.5), (2, 2.5)] {
            let message = try Self.message(opcode: TandemIOBResponse.opcode, cargo: prefix + [selector])
            let outcome = try mapper.map(message, receivedAt: receivedAt, pumpTimeZone: Self.utc())
            guard case .insulinOnBoard(let sample) = outcome else {
                Issue.record("expected insulin on board")
                continue
            }
            #expect(sample.units == units)
            #expect(sample.calculatedAt == receivedAt)
        }
    }

    @Test func otherOpcodeOrChannelIsConsumedWithoutReading() throws {
        let mapper = try Self.mapper()
        let other = try Self.message(opcode: 7, cargo: [])
        #expect(try mapper.map(other, receivedAt: receivedAt, pumpTimeZone: Self.utc()) == .notRead(channel: .currentStatus, opcode: 7))
        let otherChannel = try Self.message(opcode: TandemEGVResponse.opcode, cargo: [], channel: .authorization)
        #expect(try mapper.map(otherChannel, receivedAt: receivedAt, pumpTimeZone: Self.utc()) == .notRead(channel: .authorization, opcode: 35))
    }

    private static func mapper() throws -> TandemReadMapper {
        let limits = try SafetyLimits(glucoseLower: 20, glucoseUpper: 500)
        return TandemReadMapper(validator: SafetyLimitsValidator(limits: limits))
    }

    /// Pump wall clock 2025-01-15 08:00 read as UTC.
    private static let recordedAtUTC = Date(timeIntervalSince1970: 1_736_928_000)

    private static func utc() throws -> TimeZone {
        try #require(TimeZone(identifier: "UTC"))
    }

    private static func egv(glucose: UInt16, status: UInt8) throws -> TandemMessage {
        try message(opcode: TandemEGVResponse.opcode, cargo: [
            0x80, 0xE8, 0x0D, 0x20,
            UInt8(truncatingIfNeeded: glucose), UInt8(truncatingIfNeeded: glucose >> 8),
            status, 0,
        ])
    }

    private static func message(opcode: UInt8, cargo: [UInt8], channel: TandemChannel = .currentStatus) throws -> TandemMessage {
        var raw: [UInt8] = [opcode, 1, UInt8(cargo.count)] + cargo
        let crc = TandemMessage.crc16(raw)
        raw += [UInt8(truncatingIfNeeded: crc), UInt8(truncatingIfNeeded: crc >> 8)]
        return try #require(TandemMessage.decode(raw, channel: channel))
    }

    private static func bytes(_ hex: String) -> [UInt8] {
        let chars = Array(hex.utf8)
        return stride(from: 0, to: chars.count, by: 2).compactMap { index in
            UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16)
        }
    }
}
