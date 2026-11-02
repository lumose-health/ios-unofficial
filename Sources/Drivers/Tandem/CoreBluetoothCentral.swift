#if os(iOS)
import CoreBluetooth
import Foundation

/// The Core Bluetooth adapter: the only file that imports CoreBluetooth.
///
/// Constructing it creates the `CBCentralManager`, which is what makes iOS show the
/// Bluetooth permission prompt, so the Driver builds it only when the user first starts
/// a scan (FR-3). Every callback lands on one dedicated serial queue and is converted to
/// a `CentralEvent` yielded into a single unbounded stream, so the consumer sees radio
/// changes and sightings in the order Core Bluetooth produced them (AD-4).
///
/// `@unchecked Sendable` is sound: every stored property is a `let`, and the manager is
/// only touched on `queue`.
public final class CoreBluetoothCentral: BluetoothCentral, @unchecked Sendable {
    public let events: AsyncStream<CentralEvent>
    private let queue = DispatchQueue(label: "com.glycemicgpt.tandem.central")
    private let manager: CBCentralManager
    // `CBCentralManager.delegate` is weak; this strong reference keeps the delegate alive
    // for exactly as long as the manager.
    private let delegate: CentralDelegate

    public init() {
        let (stream, continuation) = AsyncStream<CentralEvent>.makeStream(bufferingPolicy: .unbounded)
        events = stream
        delegate = CentralDelegate { event in continuation.yield(event) }
        // No restoration identifier: background scanning is out of scope (AD-11).
        manager = CBCentralManager(delegate: delegate, queue: queue,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    public func startScan(services: [String]) {
        queue.async { [manager] in
            guard manager.state == .poweredOn else { return }
            // Duplicates allowed so RSSI updates live (FR-4).
            manager.scanForPeripherals(withServices: services.map { CBUUID(string: $0) },
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    public func stopScan() {
        queue.async { [manager] in manager.stopScan() }
    }
}

private final class CentralDelegate: NSObject, CBCentralManagerDelegate, Sendable {
    private let emit: @Sendable (CentralEvent) -> Void

    init(emit: @escaping @Sendable (CentralEvent) -> Void) { self.emit = emit }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: BluetoothRadioState = switch central.state {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized(CBManager.authorization == .restricted ? .restricted : .denied)
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
        emit(.radioStateChanged(state))
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        emit(.discovered(PeripheralSighting(identifier: peripheral.identifier, localName: name,
                                            rssi: RSSI.intValue)))
    }
}
#endif
