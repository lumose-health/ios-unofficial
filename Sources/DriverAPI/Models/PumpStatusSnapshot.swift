import Foundation

/// What a pump reports about itself at one instant, read-only.
///
/// One snapshot rather than four separate reads, because the fields are consumed
/// together and a screen assembled from four independently-timed reads shows a
/// state the pump was never actually in.
///
/// Every measured field is optional. A pump that does not report reservoir
/// volume, or a frame that carried battery and nothing else, produces a snapshot
/// with `nil` in the fields it could not fill — never a zero, never a plausible
/// default (AD-13). A missing reservoir reading rendered as `0.0 U` is an alarm
/// the user cannot act on; rendered as unknown, it is a fact.
public struct PumpStatusSnapshot: Hashable, Sendable {

    /// Remaining battery, 0…1. `nil` when the pump did not report it.
    public let batteryFraction: Double?

    /// Units of insulin remaining in the reservoir. `nil` when not reported.
    public let reservoirUnits: Double?

    /// Model, firmware and the identity the user can check against the device.
    public let hardware: PumpHardwareInfo?

    /// When the PUMP produced this state, converted from its own epoch at the
    /// Driver boundary.
    public let observedAt: Date

    /// Creates a snapshot, refusing a value no pump can have reported.
    ///
    /// `nil` stays the honest answer for a field the pump did not fill. A
    /// PRESENT value must be physically possible: a battery fraction outside
    /// `0...1` or a negative reservoir is a decoding artefact, and a snapshot
    /// is refused at construction rather than rendered as fact (AD-22).
    ///
    /// Value-class for every refusal, non-finite included — this is a
    /// post-parse validator, and bytes that did not parse surface
    /// ``DriverFailure/decodeFailed(detail:)`` before any snapshot is
    /// constructed; the reasoning is on ``DriverFailure``.
    ///
    /// - Throws: ``DriverFailure/valueRejected(bound:)`` when `batteryFraction`
    ///   is present and not a finite value in `0...1`, or `reservoirUnits` is
    ///   present and not finite and non-negative.
    public init(
        batteryFraction: Double? = nil,
        reservoirUnits: Double? = nil,
        hardware: PumpHardwareInfo? = nil,
        observedAt: Date
    ) throws(DriverFailure) {
        if let batteryFraction {
            guard batteryFraction.isFinite, (0...1).contains(batteryFraction) else {
                throw .valueRejected(bound: "a battery fraction must be a finite value in 0...1")
            }
        }
        if let reservoirUnits {
            guard reservoirUnits.isFinite, reservoirUnits >= 0 else {
                throw .valueRejected(bound: "reservoir volume must be a finite, non-negative number of units")
            }
        }
        self.batteryFraction = batteryFraction
        self.reservoirUnits = reservoirUnits
        self.hardware = hardware
        self.observedAt = observedAt
    }
}

/// The pump's identity, as it reports it.
///
/// Carries no serial number. A serial identifies a device and, through it, a
/// person; the user already knows which pump is theirs, and the diagnostic value
/// of a full serial does not pay for a health identifier in a log line (SI-9).
/// ``modelName`` and ``firmwareVersion`` are what a support conversation needs.
public struct PumpHardwareInfo: Hashable, Sendable {

    /// The model as the pump names itself, e.g. "t:slim X2".
    public let modelName: String

    /// The firmware version string, verbatim from the device.
    public let firmwareVersion: String

    public init(modelName: String, firmwareVersion: String) {
        self.modelName = modelName
        self.firmwareVersion = firmwareVersion
    }
}
