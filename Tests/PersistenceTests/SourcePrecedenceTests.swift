import Foundation
import Testing
@testable import Persistence

/// The collision rule, on its own, away from the database.
@Suite("Source identity and precedence")
struct SourcePrecedenceTests {

    /// Source identity decides collisions, so `"pump"` and `" pump"` being two
    /// sources is not a cosmetic problem: the precedence order silently stops
    /// covering one of them.
    @Test("A source identifier is refused when it is empty or padded",
          arguments: ["", " ", "pump ", " pump", "\npump"])
    func refusesUnusableIdentifiers(identifier: String) {
        let failure = #expect(throws: PersistenceFailure.self) {
            _ = try StoreSource(identifier)
        }
        #expect(failure == .sourceRejected(identifier: identifier))
    }

    @Test("An ordinary identifier is kept verbatim")
    func keepsOrdinaryIdentifiers() throws {
        #expect(try StoreSource("pump-a").identifier == "pump-a")
    }

    /// "Which of these two ranks higher" would have two answers.
    @Test("A precedence order listing a source twice is refused")
    func refusesDuplicateEntries() throws {
        let pump = try StoreSource("pump")
        let cloud = try StoreSource("cloud")
        #expect(throws: PersistenceFailure.self) {
            _ = try SourcePrecedence(order: [pump, cloud, pump])
        }
    }

    @Test("Rank follows the order, and an unlisted source ranks last")
    func rankFollowsTheOrder() throws {
        let pump = try StoreSource("pump")
        let cloud = try StoreSource("cloud")
        let meter = try StoreSource("meter")
        let precedence = try SourcePrecedence(order: [pump, cloud])

        #expect(precedence.rank(of: pump) == 0)
        #expect(precedence.rank(of: cloud) == 1)
        #expect(precedence.rank(of: meter) == 2)
    }

    @Test("The listed source outranks the unlisted one, whichever is stored")
    func listedOutranksUnlisted() throws {
        let pump = try StoreSource("pump")
        let meter = try StoreSource("meter")
        let precedence = try SourcePrecedence(order: [pump])

        #expect(precedence.standing(stored: pump, incoming: meter) == .storedWins)
        #expect(precedence.standing(stored: meter, incoming: pump) == .incomingWins)
    }

    /// The tiebreak that keeps the outcome independent of arrival order when
    /// nobody has ranked either source.
    @Test("Equal ranks resolve on the identifier, symmetrically")
    func equalRanksResolveOnTheIdentifier() throws {
        let alpha = try StoreSource("alpha")
        let zebra = try StoreSource("zebra")

        #expect(SourcePrecedence.unranked.standing(stored: alpha, incoming: zebra) == .storedWins)
        #expect(SourcePrecedence.unranked.standing(stored: zebra, incoming: alpha) == .incomingWins)
    }

    /// Nothing about the ORIGIN separates two rows from the same source, so this
    /// type says so and leaves the decision to the store, which can see the
    /// values.
    @Test("Two rows from one source are reported as such, not resolved")
    func sameSourceIsReportedNotResolved() throws {
        let pump = try StoreSource("pump")
        #expect(SourcePrecedence.unranked.standing(stored: pump, incoming: pump) == .sameSource)
    }

    @Test("An unranked precedence lists nothing")
    func unrankedIsEmpty() {
        #expect(SourcePrecedence.unranked.order.isEmpty)
    }
}
