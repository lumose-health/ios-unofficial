import DriverAPI
import SafetyCore
import TandemWire

public actor TandemDriver: Driver {
    public static let identifier = DriverIdentifier("com.glycemicgpt.tandem")!
    public nonisolated let descriptor = DriverDescriptor(
        identifier: TandemDriver.identifier, targetName: "TandemDriver",
        displayName: "Tandem Insulin Pump", transport: .bluetoothLowEnergy,
        version: "1.0.0", capabilities: [.glucoseSource, .insulinSource, .pumpStatus],
        verification: .unverified
    )
    public nonisolated let discovery: TandemPumpDiscovery
    public init(clock: any Clock = SystemClock(), scheduler: any Scheduler = WallClockScheduler()) {
        self.init(makeCentral: { Self.makeCentral() }, clock: clock, scheduler: scheduler)
    }
    init(makeCentral: @escaping @Sendable () -> any BluetoothCentral, clock: any Clock, scheduler: any Scheduler) {
        discovery = TandemPumpDiscovery(makeCentral: makeCentral, clock: clock, scheduler: scheduler)
    }
    private static func makeCentral() -> any BluetoothCentral {
        #if os(iOS)
        CoreBluetoothCentral()
        #else
        UnsupportedBluetoothCentral()
        #endif
    }
    public nonisolated func capability(_ capability: Capability) -> CapabilityPort? { nil }
    public func activate() async throws(DriverFailure) { throw .notPaired }
    public func deactivate() async { await discovery.stopScanIfActive() }
}

private struct UnsupportedBluetoothCentral: BluetoothCentral {
    let events: AsyncStream<CentralEvent> = AsyncStream { continuation in
        continuation.yield(.radioStateChanged(.unsupported))
        continuation.finish()
    }
    func startScan(services: [String]) {}
    func stopScan() {}
}
