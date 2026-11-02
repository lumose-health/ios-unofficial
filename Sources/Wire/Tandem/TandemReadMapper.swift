import Foundation
import DriverAPI

/// Which side of the sensor's reportable range an EGV status declared.
public enum TandemGlucoseRangeSide: Equatable, Sendable {
    /// `egvStatusId` 2: the sensor reads below the range it can report.
    case below
    /// `egvStatusId` 3: the sensor reads above the range it can report.
    case above
}

public enum TandemReadOutcome: Equatable, Sendable {
    case glucose(GlucoseSample)
    /// The sensor said the reading is outside its reportable range. No number is carried on
    /// purpose: the value in the frame is the edge of the range, not the real glucose, and
    /// showing it would hide how far out the reading is.
    case outOfRange(TandemGlucoseRangeSide, recordedAt: Date)
    case insulinOnBoard(InsulinOnBoardSample)
    case sensorReadingUnusable(egvStatusID: UInt8)
    case notRead(channel: TandemChannel, opcode: UInt8)
}

/// Maps decoded current-status messages to readings (AD-22).
///
/// | input | outcome | consumed |
/// |---|---|---|
/// | opcode 35, cargo too short | throws `.decodeFailed(detail: "CurrentEGVGuiDataResponse")` | no |
/// | opcode 109, cargo too short | throws `.decodeFailed(detail: "ControlIQIOBResponse")` | no |
/// | EGV, `egvStatusId` 0, or 4 and above | `.sensorReadingUnusable(egvStatusID:)` | yes |
/// | EGV, status 2 (LOW) or 3 (HIGH), any value | `.outOfRange(.below / .above, recordedAt:)`, never a number | yes |
/// | EGV, status 1-3, pump time unresolvable | throws `.decodeFailed(detail: "pump timestamp")` | no |
/// | EGV, status 1, value the validator refuses | throws the validator's `.valueRejected(bound:)` unchanged | yes |
/// | EGV, status 1, value admitted | `.glucose(GlucoseSample)`: `recordedAt` from pump time, `trend: nil` | yes |
/// | opcode 109, cargo parsed | `.insulinOnBoard`, `calculatedAt` = receive instant | yes |
/// | any other opcode, or any channel other than current status | `.notRead(channel:opcode:)` | yes |
///
/// Status is checked before the value, so no value is ever validated or surfaced for a
/// status other than 1. The pump's time zone is supplied on every call, so a caller that
/// follows the pump across zones maps each frame against the zone current at that moment.
public struct TandemReadMapper: Sendable {
    private let validator: SafetyLimitsValidator
    private let resolvePumpTime: @Sendable (UInt32, TimeZone) -> Date?

    public init(validator: SafetyLimitsValidator) {
        self.validator = validator
        self.resolvePumpTime = TandemPumpTime.date
    }

    init(
        validator: SafetyLimitsValidator,
        resolvePumpTime: @escaping @Sendable (UInt32, TimeZone) -> Date?
    ) {
        self.validator = validator
        self.resolvePumpTime = resolvePumpTime
    }

    public func map(
        _ message: TandemMessage,
        receivedAt: Date,
        pumpTimeZone: TimeZone
    ) throws(DriverFailure) -> TandemReadOutcome {
        guard message.channel == .currentStatus else {
            return .notRead(channel: message.channel, opcode: message.opcode)
        }
        switch message.opcode {
        case TandemEGVResponse.opcode:
            guard let response = TandemEGVResponse.parse(message.cargo) else {
                throw .decodeFailed(detail: "CurrentEGVGuiDataResponse")
            }
            let rangeSide: TandemGlucoseRangeSide?
            switch response.egvStatusID {
            case 1: rangeSide = nil
            case 2: rangeSide = .below
            case 3: rangeSide = .above
            default: return .sensorReadingUnusable(egvStatusID: response.egvStatusID)
            }
            if let rangeSide {
                return .outOfRange(rangeSide, recordedAt: try recordedAt(response, in: pumpTimeZone))
            }
            let glucose = try validator.validate(mgdl: Double(response.glucoseMgdl))
            let recordedAt = try recordedAt(response, in: pumpTimeZone)
            return .glucose(GlucoseSample(glucose: glucose, recordedAt: recordedAt, trend: nil))
        case TandemIOBResponse.opcode:
            guard let response = TandemIOBResponse.parse(message.cargo) else {
                throw .decodeFailed(detail: "ControlIQIOBResponse")
            }
            let units = Double(response.selectedMilliunits) / 1000
            return .insulinOnBoard(try InsulinOnBoardSample(units: units, calculatedAt: receivedAt))
        default:
            return .notRead(channel: message.channel, opcode: message.opcode)
        }
    }

    private func recordedAt(_ response: TandemEGVResponse, in zone: TimeZone) throws(DriverFailure) -> Date {
        guard let date = resolvePumpTime(response.pumpSeconds, zone) else {
            throw .decodeFailed(detail: "pump timestamp")
        }
        return date
    }
}
