import Foundation
import Testing
@testable import TandemDriver

@Suite struct TandemPumpDiscoveryTests {
    func setup() -> (TandemPumpDiscovery, FakeCentral, ManualClock, ManualScheduler) {
        let central = FakeCentral(), clock = ManualClock(), scheduler = ManualScheduler()
        let engine = TandemPumpDiscovery(makeCentral: { central }, clock: clock, scheduler: scheduler)
        return (engine, central, clock, scheduler)
    }
    func start(_ engine: TandemPumpDiscovery, _ central: FakeCentral) async {
        await engine.startScan(); central.send(.radioStateChanged(.poweredOn))
        await eventually { await engine.currentSnapshot().state == .scanning }
    }

    @Test func lazilyStartsWithExactFilterAndRestartsCleanly() async {
        let (engine, central, _, _) = setup()
        await engine.startScan()
        #expect(central.startCalls.isEmpty)
        central.send(.radioStateChanged(.poweredOn))
        await eventually { !central.startCalls.isEmpty }
        #expect(central.startCalls == [[TandemBluetooth.pumpServiceUUID]])
        await engine.startScan()
        #expect(central.stopCount == 1)
        #expect(central.startCalls.count == 2)
    }

    @Test func upsertsOrdersAndHidesIdentifier() async {
        let (engine, central, _, _) = setup(); await start(engine, central)
        let weak = UUID(), strong = UUID()
        central.send(.discovered(.init(identifier: weak, localName: nil, rssi: -80)))
        central.send(.discovered(.init(identifier: strong, localName: "t:slim X2 A", rssi: -50)))
        await eventually { await engine.currentSnapshot().pumps.count == 2 }
        central.send(.discovered(.init(identifier: weak, localName: "Tandem Mobi", rssi: -40)))
        await eventually {
            let current = await engine.currentSnapshot()
            return current.pumps.first?.handle.description == "pump" && current.pumps.first?.model == .mobi
        }
        let snapshot = await engine.currentSnapshot()
        #expect(snapshot.pumps.count == 2)
        #expect(snapshot.pumps[0].name == "Tandem Mobi")
        #expect(snapshot.pumps[1].signalStrength == -50)
    }

    @Test func unavailableSignalIsNilAndStopRetainsList() async {
        let (engine, central, clock, scheduler) = setup(); await start(engine, central)
        let id = UUID(); central.send(.discovered(.init(identifier: id, localName: "", rssi: 127)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        #expect(await engine.currentSnapshot().pumps[0].signalStrength == nil)
        clock.advance(by: 20); await engine.stopScan(); await scheduler.tick()
        #expect(await engine.currentSnapshot().pumps.count == 1)
        #expect(await engine.currentSnapshot().state == .stopped(.user))
    }

    @Test func ageOutAndIdleTimeout() async {
        let (engine, central, clock, scheduler) = setup(); await start(engine, central)
        central.send(.discovered(.init(identifier: UUID(), localName: nil, rssi: -60)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        clock.advance(by: 9); await scheduler.tick(); #expect(await engine.currentSnapshot().pumps.count == 1)
        clock.advance(by: 2); await scheduler.tick(); #expect(await engine.currentSnapshot().pumps.isEmpty)
        clock.advance(by: 109); await scheduler.tick()
        #expect(await engine.currentSnapshot().state == .stopped(.idleTimeout))
        #expect(scheduler.liveCount == 0)
    }

    @Test func blockedRadioNeverStartsAndRadioLossClearsList() async {
        let (engine, central, _, _) = setup(); await engine.startScan()
        central.send(.radioStateChanged(.poweredOff))
        await eventually { if case .blocked(.poweredOff) = await engine.currentSnapshot().state { true } else { false } }
        #expect(central.startCalls.isEmpty)
        // A blocked scan does not resume on its own; the radio comes back, then the user restarts.
        // The radio state is not observable while blocked, so the user retries until it is back.
        central.send(.radioStateChanged(.poweredOn))
        await eventually {
            await engine.startScan()
            return await engine.currentSnapshot().state == .scanning
        }
        #expect(central.startCalls.count == 1)
        central.send(.discovered(.init(identifier: UUID(), localName: "x", rssi: -1)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        central.send(.radioStateChanged(.unauthorized(.restricted)))
        await eventually { if case .blocked(.permissionRestricted) = await engine.currentSnapshot().state { true } else { false } }
        #expect(await engine.currentSnapshot().pumps.isEmpty)
    }

    @Test func selectionReturnsEntryAndStops() async {
        let (engine, central, _, _) = setup(); await start(engine, central)
        let id = UUID(); central.send(.discovered(.init(identifier: id, localName: "Tandem Mobi", rssi: -45)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        let pump = await engine.currentSnapshot().pumps[0]
        #expect(await engine.select(pump.handle) == pump)
        #expect(await engine.currentSnapshot().state == .stopped(.pumpSelected))
    }
}

extension TandemPumpDiscoveryTests {
    @Test func everyRadioBlockReasonIsReported() async {
        let cases: [(BluetoothRadioState, BluetoothBlockedReason)] = [
            (.poweredOff, .poweredOff), (.unauthorized(.denied), .permissionDenied),
            (.unauthorized(.restricted), .permissionRestricted), (.unsupported, .unsupported),
            (.resetting, .resetting),
        ]
        for (radio, reason) in cases {
            let (engine, central, _, _) = setup()
            await engine.startScan(); central.send(.radioStateChanged(radio))
            await eventually {
                let value = await engine.currentSnapshot().state
                return value == .blocked(reason)
            }
            #expect(await engine.currentSnapshot().state == .blocked(reason))
            #expect(central.startCalls.isEmpty)
        }
    }

    @Test func interactionMovesIdleDeadlineAndUnknownWaitsForPower() async {
        let (engine, central, clock, scheduler) = setup()
        await engine.startScan()
        #expect(await engine.currentSnapshot().state == .waitingForBluetooth)
        central.send(.radioStateChanged(.poweredOn))
        await eventually { await engine.currentSnapshot().state == .scanning }
        clock.advance(by: 100); await engine.noteUserInteraction()
        clock.advance(by: 119); await scheduler.tick()
        #expect(await engine.currentSnapshot().state == .scanning)
        clock.advance(by: 2); await scheduler.tick()
        #expect(await engine.currentSnapshot().state == .stopped(.idleTimeout))
    }

    @Test func onlyRealBlockingConditionsMapToAReason() {
        #expect(TandemPumpDiscovery.blockedReason(for: .poweredOn) == nil)
        #expect(TandemPumpDiscovery.blockedReason(for: .unknown) == nil)
    }

    @Test func radioReturningToUnknownWaitsInsteadOfBlocking() async {
        let (engine, central, _, scheduler) = setup(); await start(engine, central)
        central.send(.discovered(.init(identifier: UUID(), localName: nil, rssi: -60)))
        await eventually { await engine.currentSnapshot().pumps.count == 1 }
        central.send(.radioStateChanged(.unknown))
        await eventually { await engine.currentSnapshot().state == .waitingForBluetooth }
        #expect(await engine.currentSnapshot().pumps.isEmpty)
        #expect(scheduler.liveCount == 0)
        central.send(.radioStateChanged(.poweredOn))
        await eventually { await engine.currentSnapshot().state == .scanning }
        #expect(central.startCalls.count == 2)
    }
}
