import DriverAPI

/// The capabilities held by the persisted active Drivers in this build.
public struct DriverSlots: Equatable, Sendable {
    public let singleInstance: [Capability: DriverIdentifier]
    public let multiInstance: [Capability: [DriverIdentifier]]
    public let pump: DriverIdentifier?
    public let glucose: DriverIdentifier?

    public func holder(of capability: Capability) -> DriverIdentifier? {
        singleInstance[capability]
    }

    public func members(of capability: Capability) -> [DriverIdentifier] {
        multiInstance[capability] ?? []
    }

    /// Derives slots with a stable raw-identifier tie break.
    public static func derive(active: Set<DriverIdentifier>, descriptors: [DriverDescriptor]) -> DriverSlots {
        let selected = descriptors.filter { active.contains($0.identifier) }
            .sorted {
                if $0.identifier.rawValue != $1.identifier.rawValue {
                    return $0.identifier.rawValue < $1.identifier.rawValue
                }
                if $0.transport.rawValue != $1.transport.rawValue {
                    return $0.transport.rawValue < $1.transport.rawValue
                }
                let left = $0.capabilities.map(\.rawValue).sorted()
                let right = $1.capabilities.map(\.rawValue).sorted()
                return left.lexicographicallyPrecedes(right)
            }
        var single: [Capability: DriverIdentifier] = [:]
        var multi: [Capability: [DriverIdentifier]] = [:]
        var pump: DriverIdentifier?
        var glucose: DriverIdentifier?
        for descriptor in selected {
            for capability in descriptor.capabilities {
                switch capability.cardinality {
                case .singleInstance:
                    if single[capability] == nil { single[capability] = descriptor.identifier }
                case .multiInstance:
                    multi[capability, default: []].append(descriptor.identifier)
                }
            }
            let isDevice: Bool
            switch descriptor.transport {
            case .bluetoothLowEnergy, .inProcess: isDevice = true
            case .network: isDevice = false
            }
            if isDevice {
                if pump == nil && (descriptor.capabilities.contains(.pumpStatus) ||
                                   descriptor.capabilities.contains(.insulinSource)) {
                    pump = descriptor.identifier
                }
                if glucose == nil && descriptor.capabilities.contains(.glucoseSource) {
                    glucose = descriptor.identifier
                }
            }
        }
        return DriverSlots(singleInstance: single, multiInstance: multi, pump: pump, glucose: glucose)
    }
}
