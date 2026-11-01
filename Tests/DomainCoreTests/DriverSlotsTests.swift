import Testing
import DriverAPI
import DomainCore

@Suite("Derived Driver slots")
struct DriverSlotsTests {
    private func descriptor(_ id: String, _ capabilities: Set<Capability>,
                            transport: DriverTransport = .inProcess) -> DriverDescriptor {
        TestDriver(id: id, capabilities: capabilities, transport: transport).descriptor
    }

    @Test func emptyAndUnknown() {
        let a = descriptor("test.pump.alpha", [.glucoseSource, .insulinSource, .pumpStatus])
        let empty = DriverSlots.derive(active: [], descriptors: [a])
        #expect(empty.singleInstance.isEmpty && empty.multiInstance.isEmpty)
        #expect(empty.pump == nil && empty.glucose == nil)
        let unknown = DriverSlots.derive(active: [DriverIdentifier("test.other.unknown")!], descriptors: [a])
        #expect(unknown == empty)
    }

    @Test func orderedHoldersAndMembers() {
        let a = descriptor("test.pump.alpha", [.glucoseSource, .insulinSource, .pumpStatus])
        let b = descriptor("test.pump.bravo", [.glucoseSource, .pumpStatus])
        let c = descriptor("test.bgm.two", [.bgmSource])
        let d = descriptor("test.bgm.one", [.bgmSource])
        let active = Set([a, b, c, d].map(\.identifier))
        let slots = DriverSlots.derive(active: active, descriptors: [b, c, a, d])
        #expect(slots.holder(of: .glucoseSource) == a.identifier)
        #expect(slots.pump == a.identifier && slots.glucose == a.identifier)
        #expect(slots.members(of: .bgmSource) == [d.identifier, c.identifier])
    }

    @Test func networkCannotHoldDeviceSlots() {
        let n = descriptor("test.net.glucose", [.glucoseSource, .pumpStatus], transport: .network)
        let slots = DriverSlots.derive(active: [n.identifier], descriptors: [n])
        #expect(slots.holder(of: .glucoseSource) == n.identifier)
        #expect(slots.pump == nil && slots.glucose == nil)
    }

    @Test func descriptorOrderDoesNotMatter() {
        let ds = [
            descriptor("test.pump.bravo", [.glucoseSource, .insulinSource]),
            descriptor("test.bgm.two", [.bgmSource]),
            descriptor("test.pump.alpha", [.glucoseSource, .pumpStatus]),
            descriptor("test.bgm.one", [.bgmSource]),
        ]
        let active = Set(ds.map(\.identifier))
        let expected = DriverSlots.derive(active: active, descriptors: ds)
        for _ in 0..<10 {
            #expect(DriverSlots.derive(active: active, descriptors: Array(ds.reversed())) == expected)
            #expect(DriverSlots.derive(active: active, descriptors: Array(ds.dropFirst()) + [ds[0]]) == expected)
        }
    }
}
