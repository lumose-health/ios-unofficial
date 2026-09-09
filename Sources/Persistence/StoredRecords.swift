import Foundation
import DriverAPI
import SafetyCore

/// A stored CGM reading, with the source that wrote it.
///
/// The reading itself is a `DriverAPI` ``DriverAPI/GlucoseSample`` rather than a
/// re-declared row struct: the platform already has one shape for "a glucose value
/// and the instant the sensor produced it", and a second one that differs only in
/// which module declares it is how two copies of a safety type drift apart. The
/// source is the store's own concern — it decides collisions — so it is carried
/// beside the sample, not inside it.
public struct StoredGlucoseSample: Hashable, Sendable {

    public let sample: GlucoseSample

    public let source: StoreSource

    public init(sample: GlucoseSample, source: StoreSource) {
        self.sample = sample
        self.source = source
    }
}

/// A stored pump-status snapshot, with the source that wrote it.
public struct StoredPumpStatus: Hashable, Sendable {

    public let snapshot: PumpStatusSnapshot

    public let source: StoreSource

    public init(snapshot: PumpStatusSnapshot, source: StoreSource) {
        self.snapshot = snapshot
        self.source = source
    }
}

/// A stored insulin delivery, with the source that wrote it.
///
/// The delivery itself is `DriverAPI`'s ``DriverAPI/DoseRecord`` for the same
/// reason readings are `GlucoseSample`s: the platform has one shape for "insulin
/// that reached the patient, and when the device finished it", and a second one
/// declared here would be a second place the units mean something.
public struct StoredDoseRecord: Hashable, Sendable {

    public let dose: DoseRecord

    public let source: StoreSource

    public init(dose: DoseRecord, source: StoreSource) {
        self.dose = dose
        self.source = source
    }
}

/// One record of a pump's own history log, kept as the device wrote it.
///
/// ## Why the bytes are kept
///
/// A history record is the pump's account of what it did, and the platform's
/// reading of it is an interpretation. Interpretations get corrected: a field
/// misread as minutes turns out to be seconds, an event type nobody had seen
/// before turns up in a firmware release. Keeping the payload means a corrected
/// decoder can be run over history the user already has, instead of over history
/// they no longer do.
///
/// ## Identity
///
/// A pump numbers its own history records, and that number — paired with the
/// source, since two pumps number independently — is the record's identity. So a
/// backfill that overlaps a previous one stores nothing new, which is what makes
/// re-reading a log cheap enough to do freely. Android keys this table on the
/// sequence number ALONE while its own documentation says "unique per pump"; the
/// source is part of the key here because two pumps really do reuse numbers.
public struct RawPumpHistoryRecord: Hashable, Sendable {

    /// The pump that produced the record.
    public let source: StoreSource

    /// The pump's own number for this record.
    public let sequenceNumber: Int64

    /// When the PUMP says the event happened, converted from its epoch at the
    /// Driver boundary. Retention is judged against this.
    public let recordedAt: Date

    /// The pump's own code for what kind of event this is, unmapped.
    public let eventTypeIdentifier: Int

    /// The record exactly as the pump wrote it.
    public let payload: Data

    public init(
        source: StoreSource,
        sequenceNumber: Int64,
        recordedAt: Date,
        eventTypeIdentifier: Int,
        payload: Data
    ) {
        self.source = source
        self.sequenceNumber = sequenceNumber
        self.recordedAt = recordedAt
        self.eventTypeIdentifier = eventTypeIdentifier
        self.payload = payload
    }
}
