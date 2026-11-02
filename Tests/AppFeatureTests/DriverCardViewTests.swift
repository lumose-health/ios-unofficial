import Testing
import DriverAPI
@testable import AppFeature

@Suite("Driver card text contrast")
struct DriverCardViewTests {
    @Test func fixedColourPairsReachSmallTextContrast() {
        for color in CardColor.allCases {
            if color == .standard || color == .muted {
                #expect(color.rgb(dark: false) == nil)
                #expect(color.rgb(dark: true) == nil)
                continue
            }
            guard let light = color.rgb(dark: false), let dark = color.rgb(dark: true) else {
                Issue.record("Expected fixed colour pairs")
                continue
            }
            #expect(contrast(light, .init(red: 255, green: 255, blue: 255)) >= 4.5)
            #expect(contrast(dark, .init(red: 0x1C, green: 0x1C, blue: 0x1E)) >= 4.5)
        }
    }
}
