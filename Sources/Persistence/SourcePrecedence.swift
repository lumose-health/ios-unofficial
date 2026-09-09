import Foundation

/// Where a stored row came from.
///
/// A validated identifier rather than a bare `String`, because source identity is
/// what decides a collision: two spellings of the same origin — `"tandem"` and
/// `" tandem"` — are two sources to a database, and the precedence order silently
/// stops covering one of them. The rule is deliberately narrow (non-empty, no
/// surrounding whitespace) rather than a vocabulary, since the set of sources
/// grows with every Driver and a closed enum here would mean editing this file to
/// ship one.
public struct StoreSource: Hashable, Sendable, Comparable {

    /// The identifier as it is stored and compared.
    public let identifier: String

    /// - Throws: ``PersistenceFailure/sourceRejected(identifier:)`` when the
    ///   identifier is empty or has leading or trailing whitespace.
    public init(_ identifier: String) throws(PersistenceFailure) {
        guard !identifier.isEmpty,
              identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw .sourceRejected(identifier: identifier)
        }
        self.identifier = identifier
    }

    public static func < (lhs: StoreSource, rhs: StoreSource) -> Bool {
        lhs.identifier < rhs.identifier
    }
}

/// How two rows competing for the same key compare.
public enum SourceStanding: Hashable, Sendable {

    /// The row already in the database keeps the key.
    case storedWins

    /// The arriving row takes the key.
    case incomingWins

    /// Both rows carry the same source, so nothing about their ORIGIN separates
    /// them. The store decides on the values instead: identical values are a
    /// replay and a no-op, differing values are a contradiction the caller sees.
    case sameSource
}

/// The ordered list of sources, most trusted first, that resolves a collision.
///
/// ## The rule, stated once
///
/// Two rows collide when they claim the same key — the same instant, for the
/// per-instant tables. Exactly one survives, chosen by:
///
/// 1. **rank**, the position in ``order``. A source this list does not name ranks
///    after every source it does, so an unconfigured Driver never displaces a
///    configured one.
/// 2. **identifier**, lexicographically, when ranks tie. This only fires between
///    two unlisted sources; it exists so the outcome does not depend on which of
///    them happened to write first.
/// 3. **same source** — handled by the store, not here. See ``SourceStanding/sameSource``.
///
/// Steps 1 and 2 are functions of the two sources alone, so replaying the same
/// records in any order reaches the same database. That is the property this type
/// exists for: a backfill that runs twice, or a live poll racing a cloud sync,
/// must not leave two users with different histories.
///
/// ## What Android does, and why this differs
///
/// Android's store has the same unique-per-timestamp indexes and a `source`
/// column, but no precedence at all: which row survives falls out of the DAO
/// conflict strategy the calling path happened to use — `REPLACE` on the live
/// poll, `IGNORE` on the history backfill and the cloud sync. So the winner there
/// is decided by the code path, not by the data. The semantics carried over are
/// the unique keys and the single-row-per-instant shape; the resolution rule is
/// net-new and deliberate.
public struct SourcePrecedence: Hashable, Sendable {

    /// Sources most trusted first. May be empty, which ranks every source equally
    /// and leaves step 2 to decide.
    public let order: [StoreSource]

    /// No source outranks another; collisions resolve on the identifier alone.
    public static let unranked = SourcePrecedence()

    private init() {
        self.order = []
    }

    /// - Throws: ``PersistenceFailure/precedenceRejected(detail:)`` when a source
    ///   appears twice — "which of these ranks higher" would have two answers.
    public init(order: [StoreSource]) throws(PersistenceFailure) {
        var seen: Set<StoreSource> = []
        for source in order where !seen.insert(source).inserted {
            throw .precedenceRejected(detail: "the source \(source.identifier) is listed more than once")
        }
        self.order = order
    }

    /// `source`'s position in ``order``, or one past the end when it is unlisted.
    public func rank(of source: StoreSource) -> Int {
        order.firstIndex(of: source) ?? order.count
    }

    /// Which of two rows keeps the key they both claim.
    public func standing(stored: StoreSource, incoming: StoreSource) -> SourceStanding {
        if stored == incoming { return .sameSource }
        let storedRank = rank(of: stored)
        let incomingRank = rank(of: incoming)
        if storedRank != incomingRank {
            return storedRank < incomingRank ? .storedWins : .incomingWins
        }
        return stored < incoming ? .storedWins : .incomingWins
    }
}
