import Foundation
import DriverAPI

/// What a batch write of insulin deliveries did, record by record.
///
/// ## Why a report and not a throw
///
/// The store refuses when one source reports two different deliveries of one
/// category at one instant: precedence cannot break that tie, and picking by
/// arrival order would make stored insulin depend on the order a backfill happened
/// to run in. That refusal is right per record and wrong per batch: a history
/// import that stops at the first collision loses every record after it, so one
/// odd pair of rows costs the user the rest of their history.
///
/// So the batch write returns this instead. Every record still gets the same
/// answer it would have got on its own; the ones the store refused are named here,
/// with where they sat in the batch, so the caller can log them, show them, or
/// hand them to whoever owns the Driver that produced them.
///
/// Nothing here is a resolution. The store did not merge the refused records, sum
/// them, or keep the later one. It stored one answer and handed the other back,
/// because a coincidence like an extended and a normal delivery finishing in the
/// same stored second is something a person has to look at, not something a
/// storage layer should guess about (AD-5).
public struct DoseIngestReport: Hashable, Sendable {

    /// One record the batch refused, and why.
    public struct Refusal: Hashable, Sendable {

        /// Where the record sat in the batch, so a caller can point at the row it
        /// came from rather than at "one of these".
        public let index: Int

        /// The record itself, so the caller still has it after the call. It is not
        /// in the store.
        public let dose: DoseRecord

        /// What the store refused it for, in the same words the single-record
        /// write's failure carries.
        public let detail: String

        public init(index: Int, dose: DoseRecord, detail: String) {
            self.index = index
            self.dose = dose
            self.detail = detail
        }
    }

    /// How many records the batch left settled: written, already there, or
    /// answered by a row a higher-precedence source owns. A replayed backfill
    /// settles every record and writes nothing, which is the property that makes
    /// re-running one cheap.
    public let settled: Int

    /// Every record the store refused, in batch order.
    public let refused: [Refusal]

    public init(settled: Int, refused: [Refusal]) {
        self.settled = settled
        self.refused = refused
    }

    /// Whether the whole batch landed. False means there is something to look at,
    /// not that the batch failed.
    public var isComplete: Bool { refused.isEmpty }
}
