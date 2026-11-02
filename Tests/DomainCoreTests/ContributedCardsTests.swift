import Testing
import DriverAPI
@testable import DomainCore

@Suite("Contributed card validation and order")
struct ContributedCardsTests {
    private let alpha = DriverIdentifier("test.cards.alpha")!
    private let bravo = DriverIdentifier("test.cards.bravo")!
    private func card(_ id: String, priority: Int = 100, title: String = "Title") -> DashboardCardDescriptor {
        DashboardCardDescriptor(id: id, title: title, priority: priority, elements: [])
    }

    @Test func invalidCardsAreOmittedAndOtherCardsRemain() {
        var logs: [String] = []
        let result = DashboardCardValidation.accepted([
            card("ok"), card(" "), card("blank-title", title: " \n"), card("too-low", priority: 99),
            card("ok"), card("after")
        ], from: alpha) { logs.append($0) }
        #expect(result.map(\.id) == ["ok", "after"])
        #expect(logs.count == 4)
        #expect(logs.allSatisfy { $0.contains(alpha.rawValue) })
        #expect(logs.allSatisfy { !$0.contains("Title") })
    }

    @Test(arguments: [
        ("Glucose 110 mg/dL", true),
        ("2.5 U", true),
        ("Pump \u{FF13}", true),
        ("Connected", false),
    ])
    func cardTextWithAnyDecimalDigitIsRefusedWhole(text: String, refused: Bool) {
        let asTitle = card("title", title: text)
        let asLabel = DashboardCardDescriptor(id: "label", title: "Status", priority: 100,
                                              elements: [.label(text: text, style: .body)])
        let asBadge = DashboardCardDescriptor(id: "badge", title: "Status", priority: 100,
                                              elements: [.statusBadge(text: text, color: .info)])
        var logs: [String] = []
        let result = DashboardCardValidation.accepted([asTitle, asLabel, asBadge], from: alpha) { logs.append($0) }
        if refused {
            #expect(result.isEmpty)
            #expect(logs.count == 3)
            #expect(logs.allSatisfy { $0 == "Driver \(alpha.rawValue) card refused: digit in card text" })
        } else {
            #expect(result == [asTitle, asLabel, asBadge])
            #expect(logs.isEmpty)
        }
    }

    @Test func orderUsesPriorityThenRawDriverAndCardIds() {
        let input = [
            ContributedCard(driver: bravo, card: card("z", priority: 110)),
            ContributedCard(driver: alpha, card: card("b", priority: 100)),
            ContributedCard(driver: alpha, card: card("a", priority: 100)),
            ContributedCard(driver: bravo, card: card("a", priority: 100)),
        ]
        let expected = [ContributedCard.ID(driver: alpha, card: "a"), ContributedCard.ID(driver: alpha, card: "b"),
                        ContributedCard.ID(driver: bravo, card: "a"), ContributedCard.ID(driver: bravo, card: "z")]
        for permutation in input.permutations { #expect(ContributedCard.ordered(permutation).map(\.id) == expected) }
    }

    @Test func registryOnlyReturnsCardsFromRunningDriversAndDropsLateResults() async throws {
        let inactive = TestDriver(id: "test.cards.inactive", capabilities: [])
        let active = TestDriver(id: alpha.rawValue, capabilities: [])
        let registry = try DriverRegistry(drivers: [inactive, active], store: RecordingSelectionStore())
        await inactive.setCards([card("inactive")])
        await active.setCards([card("active")])
        try await registry.activate(alpha)
        #expect(await registry.contributedCards().map(\.card.id) == ["active"])

        let gate = Gate()
        await active.setCards([card("late")], gate: gate)
        let read = Task { await registry.contributedCards() }
        await eventually { await gate.entered() }
        try await registry.deactivate(alpha)
        await gate.open()
        #expect(await read.value.isEmpty)
    }

    @Test func idKeepsDriverAndCardApartEvenWhenTheCardIdHasASlash() {
        let contributed = ContributedCard(driver: alpha, card: card("beta/x"))
        #expect(contributed.id == ContributedCard.ID(driver: alpha, card: "beta/x"))
        #expect(contributed.id != ContributedCard(driver: alpha, card: card("beta")).id)
    }

    @Test func hungDriverDoesNotHoldBackOtherDriversCards() async throws {
        let hung = TestDriver(id: "test.cards.hung", capabilities: [])
        let active = TestDriver(id: alpha.rawValue, capabilities: [])
        let registry = try DriverRegistry(drivers: [hung, active], store: RecordingSelectionStore())
        let gate = Gate()
        await hung.setCards([card("never")], gate: gate)
        await active.setCards([card("active")])
        try await registry.activate(hung.descriptor.identifier)
        try await registry.activate(alpha)
        let cards = await registry.contributedCards(timeout: .milliseconds(50))
        #expect(cards.map(\.card.id) == ["active"])
        await gate.open()
    }

    @Test func aDriverThatIgnoresCancellationHasAtMostOneCardQueryOutstanding() async throws {
        let hung = TestDriver(id: "test.cards.hung", capabilities: [])
        let registry = try DriverRegistry(drivers: [hung], store: RecordingSelectionStore())
        let gate = Gate()
        await hung.setCards([card("stale")], gate: gate)
        try await registry.activate(hung.descriptor.identifier)
        for _ in 0..<5 {
            #expect(await registry.contributedCards(timeout: .milliseconds(10)).isEmpty)
        }
        #expect(await hung.cardsCallCount == 1)
        #expect(await registry.hasCardQueryInFlight(hung.descriptor.identifier))

        await hung.setCards([card("fresh")])
        await gate.open()
        await eventually { await !registry.hasCardQueryInFlight(hung.descriptor.identifier) }
        #expect(await !registry.hasCardQueryInFlight(hung.descriptor.identifier))
        #expect(await registry.contributedCards().map(\.card.id) == ["fresh"])
        #expect(await hung.cardsCallCount == 2)
    }

    @Test func cancellingACardReadReturnsWithoutWaitingForDrivers() async throws {
        let hung = TestDriver(id: "test.cards.hung", capabilities: [])
        let registry = try DriverRegistry(drivers: [hung], store: RecordingSelectionStore())
        let gate = Gate()
        await hung.setCards([card("never")], gate: gate)
        try await registry.activate(hung.descriptor.identifier)
        let read = Task { await registry.contributedCards(timeout: .seconds(1_000)) }
        await eventually { await gate.entered() }
        read.cancel()
        #expect(await read.value.isEmpty)
        await gate.open()
    }
}

private func eventually(_ condition: @escaping () async -> Bool) async {
    for _ in 0..<100 {
        if await condition() { return }
        await Task.yield()
    }
}

private extension Array {
    var permutations: [[Element]] {
        guard count > 1 else { return [self] }
        return indices.flatMap { index in
            var rest = self
            let head = rest.remove(at: index)
            return rest.permutations.map { [head] + $0 }
        }
    }
}
