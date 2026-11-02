import Testing
import AppFeature
import DriverAPI

@Suite("App composition")
struct AppCompositionTests {
    @Test func demoIdentifiersFollowInProcessTransport() throws {
        let simulated = try #require(DriverIdentifier("com.example.simulated"))
        let traceReplay = try #require(DriverIdentifier("com.example.trace-replay"))
        let bluetooth = try #require(DriverIdentifier("com.example.bluetooth"))
        let network = try #require(DriverIdentifier("com.example.network"))
        let descriptors = [
            DriverDescriptor(identifier: simulated, targetName: "SimulatedDriver", displayName: "Simulated", transport: .inProcess, version: "1.0", capabilities: [.glucoseSource], verification: .beta),
            DriverDescriptor(identifier: traceReplay, targetName: "TraceReplayDriver", displayName: "Trace-Replay", transport: .inProcess, version: "1.0", capabilities: [.glucoseSource], verification: .beta),
            DriverDescriptor(identifier: bluetooth, targetName: "BluetoothDriver", displayName: "Bluetooth", transport: .bluetoothLowEnergy, version: "1.0", capabilities: [.glucoseSource], verification: .unverified),
            DriverDescriptor(identifier: network, targetName: "NetworkDriver", displayName: "Network", transport: .network, version: "1.0", capabilities: [.glucoseSource], verification: .unverified),
        ]

        #expect(AppComposition.demoIdentifiers(for: descriptors) == [simulated, traceReplay])
    }
}
