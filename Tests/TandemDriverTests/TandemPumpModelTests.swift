import Testing
@testable import TandemDriver

@Test func modelDetection() {
    #expect(TandemPumpModel.fromAdvertisedName(" t:slim X2 ABC ") == .tslimX2)
    #expect(TandemPumpModel.fromAdvertisedName("tslim\u{00A0}X2 1") == .tslimX2)
    #expect(TandemPumpModel.fromAdvertisedName("TANDEM   MOBI 1") == .mobi)
    #expect(TandemPumpModel.fromAdvertisedName("tslimX2") == .unknown)
    #expect(TandemPumpModel.fromAdvertisedName(nil) == .unknown)
    #expect(TandemPumpModel.fromAdvertisedName("OmniPod 5") == .unknown)
    #expect(TandemPumpModel.fromAdvertisedName("Tandem Pump") == .unknown)
    #expect(TandemPumpModel.fromAdvertisedName("") == .unknown)
    #expect(TandemPumpModel.tslimX2.displayName == "t:slim X2")
    #expect(TandemPumpModel.mobi.hasScreen == false)
    #expect(TandemPumpModel.unknown.hasScreen == nil)
}
