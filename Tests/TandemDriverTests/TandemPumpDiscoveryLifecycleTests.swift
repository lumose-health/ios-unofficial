import Foundation
import Testing
@testable import TandemDriver

extension TandemPumpDiscoveryTests {
    private func names(_ engine: TandemPumpDiscovery) async -> [String] {
        await engine.currentSnapshot().pumps.map(\.name)
    }

    @Test func equalSignalTiesOrderByFirstSeenThenInsertion() async {
        let (engine, central, clock, _) = setup(); await start(engine, central)
        let later = UUID()
        central.send(.discovered(.init(identifier: later, localName: "Later", rssi: -60)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        // A wall clock can step back, so arrival order and first-seen order can disagree;
        // first-seen wins.
        clock.advance(by: -5)
        central.send(.discovered(.init(identifier: UUID(), localName: "Earlier", rssi: -60)))
        await eventually { await engine.currentSnapshot().pumps.count == 2 }
        // Same instant: arrival order decides.
        clock.advance(by: 10)
        for name in ["Third", "Fourth", "Fifth"] {
            central.send(.discovered(.init(identifier: UUID(), localName: name, rssi: -60)))
        }
        await eventually { await engine.currentSnapshot().pumps.count == 5 }
        #expect(await names(engine) == ["Earlier", "Later", "Third", "Fourth", "Fifth"])
        // A fresh sighting moves lastSeen, not firstSeen, so the order holds.
        central.send(.discovered(.init(identifier: later, localName: "Later", rssi: -60)))
        await eventually { await engine.currentSnapshot().pumps.first { $0.name == "Later" }?.lastSeen == clock.now }
        #expect(await names(engine) == ["Earlier", "Later", "Third", "Fourth", "Fifth"])
    }

    @Test func unavailableSignalSortsAfterPumpsWithSignal() async {
        let (engine, central, _, _) = setup(); await start(engine, central)
        central.send(.discovered(.init(identifier: UUID(), localName: "None",
                                       rssi: TandemScanTiming.unavailableRSSI)))
        central.send(.discovered(.init(identifier: UUID(), localName: "Weak", rssi: -90)))
        central.send(.discovered(.init(identifier: UUID(), localName: "Strong", rssi: -40)))
        await eventually { await engine.currentSnapshot().pumps.count == 3 }
        #expect(await names(engine) == ["Strong", "Weak", "None"])
        #expect(await engine.currentSnapshot().pumps.map(\.signalStrength) == [-40, -90, nil])
    }

    @Test func missingOrEmptyNameFallsBackAndAdvertisedNameSticks() async {
        let (engine, central, _, _) = setup(); await start(engine, central)
        let silent = UUID(), blank = UUID(), mobi = UUID()
        central.send(.discovered(.init(identifier: silent, localName: nil, rssi: -50)))
        central.send(.discovered(.init(identifier: blank, localName: "", rssi: -60)))
        central.send(.discovered(.init(identifier: mobi, localName: "Tandem Mobi", rssi: -70)))
        await eventually { await engine.currentSnapshot().pumps.count == 3 }
        let pumps = await engine.currentSnapshot().pumps
        #expect(pumps.map(\.name) == ["Tandem Pump", "Tandem Pump", "Tandem Mobi"])
        #expect(pumps.map(\.model) == [.unknown, .unknown, .mobi])
        central.send(.discovered(.init(identifier: mobi, localName: nil, rssi: -30)))
        await eventually { await engine.currentSnapshot().pumps.first?.signalStrength == -30 }
        #expect(await engine.currentSnapshot().pumps.first?.name == "Tandem Mobi")
        #expect(await engine.currentSnapshot().pumps.first?.model == .mobi)
    }

    @Test func centralIsNotBuiltBeforeTheFirstStartScan() async {
        let factory = CentralFactory()
        let engine = TandemPumpDiscovery(makeCentral: { factory.make() }, clock: ManualClock(),
                                         scheduler: ManualScheduler())
        _ = await engine.snapshots()
        _ = await engine.currentSnapshot()
        await engine.noteUserInteraction()
        await engine.stopScanIfActive()
        #expect(factory.callCount == 0)
        await engine.startScan()
        #expect(factory.callCount == 1)
        await engine.startScan()
        #expect(factory.callCount == 1)
    }

    @Test func snapshotsStartWithCurrentAndANewCallFinishesThePrevious() async {
        let (engine, central, _, _) = setup(); await start(engine, central)
        central.send(.discovered(.init(identifier: UUID(), localName: nil, rssi: -50)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        var first = await engine.snapshots().makeAsyncIterator()
        let initial = await first.next()
        #expect(initial == (await engine.currentSnapshot()))
        #expect(initial?.state == .scanning)
        #expect(initial?.pumps.count == 1)
        var second = await engine.snapshots().makeAsyncIterator()
        let ended = await first.next()
        #expect(ended == nil)
        #expect(await second.next()?.pumps.count == 1)
        await engine.stopScan()
        #expect(await second.next()?.state == .stopped(.user))
    }

    @Test func restartClearsTheList() async {
        let (engine, central, _, _) = setup(); await start(engine, central)
        central.send(.discovered(.init(identifier: UUID(), localName: nil, rssi: -50)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        await engine.startScan()
        let snapshot = await engine.currentSnapshot()
        #expect(snapshot.pumps.isEmpty)
        #expect(snapshot.state == .scanning)
        #expect(central.stopCount == 1)
        #expect(central.startCalls.count == 2)
    }

    @Test func housekeepingPublishesOnlyWhenSomethingChanged() async {
        let (engine, central, clock, scheduler) = setup(); await start(engine, central)
        central.send(.discovered(.init(identifier: UUID(), localName: nil, rssi: -50)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        var updates = await engine.snapshots().makeAsyncIterator()
        _ = await updates.next()
        await scheduler.tick(); await scheduler.tick()
        clock.advance(by: TandemScanTiming.ageOut + 1); await scheduler.tick()
        let aged = await updates.next()
        #expect(aged?.state == .scanning)
        #expect(aged?.pumps.isEmpty == true)
        await scheduler.tick()
        await engine.stopScan()
        #expect(await updates.next()?.state == .stopped(.user))
    }

    @Test func releasedEngineStopsConsumingAndReleasesTheCentral() async throws {
        let factory = CentralFactory(), scheduler = ManualScheduler()
        weak var released: TandemPumpDiscovery?
        // Held from outside so the stream stays open: only cancelling the loop can end it.
        var central: FakeCentral?
        do {
            let engine = TandemPumpDiscovery(makeCentral: { factory.make() }, clock: ManualClock(),
                                             scheduler: scheduler)
            released = engine
            await engine.startScan()
            let built = try #require(factory.built)
            central = built
            central?.send(.radioStateChanged(.poweredOn))
            await eventually { await engine.currentSnapshot().state == .scanning }
        }
        await eventually { released == nil }
        await eventually { factory.consumerEnded.isSet }
        #expect(scheduler.liveCount == 0)
        central?.send(.discovered(.init(identifier: UUID(), localName: nil, rssi: -50)))
        central = nil
        await eventually { factory.built == nil }
    }
}
