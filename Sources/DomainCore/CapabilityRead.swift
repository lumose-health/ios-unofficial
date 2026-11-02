@_spi(DriverPlatform) import DriverAPI

/// A selected capability and the Driver currently providing it.
public struct HeldPort: Sendable {
    public let holder: DriverIdentifier
    public let port: CapabilityPort

    public init(holder: DriverIdentifier, port: CapabilityPort) {
        self.holder = holder
        self.port = port
    }
}

/// Why a selected capability cannot currently be read.
public enum CapabilityReadError: Error, Hashable, Sendable {
    case noActiveDriver(Capability)
    case holderNotRunning(DriverIdentifier, Capability, DriverLifecycleState)
    case portUnavailable(DriverIdentifier, Capability)
    case notSingleInstance(Capability)
    case cancelled
}
