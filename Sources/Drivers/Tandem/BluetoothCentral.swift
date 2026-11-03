import Foundation

public enum BluetoothAuthorization: Hashable, Sendable { case denied, restricted }

public enum BluetoothRadioState: Hashable, Sendable {
    case unknown, resetting, unsupported, unauthorized(BluetoothAuthorization), poweredOff, poweredOn
}

public struct PeripheralSighting: Hashable, Sendable {
    public let identifier: UUID
    public let localName: String?
    public let rssi: Int
    public init(identifier: UUID, localName: String?, rssi: Int) {
        self.identifier = identifier
        self.localName = localName
        self.rssi = rssi
    }
}

public enum CentralEvent: Sendable {
    case radioStateChanged(BluetoothRadioState)
    case discovered(PeripheralSighting)
}

public protocol BluetoothCentral: Sendable {
    var events: AsyncStream<CentralEvent> { get }
    func startScan(services: [String])
    func stopScan()
}

public enum TandemBluetooth {
    // Android TandemProtocol.kt:16-17.
    public static let pumpServiceUUID = "0000FDFB-0000-1000-8000-00805F9B34FB"
}
