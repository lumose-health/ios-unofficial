import Testing
import DriverAPI
@testable import AppFeature

@Suite("Driver card text contrast")
struct DriverCardViewTests {
    @Test func badgeTextReachesSmallTextContrastOnItsCompositedFill() {
        for color in CardColor.allCases {
            for dark in [false, true] {
                if color == .standard || color == .muted {
                    #expect(color.rgb(dark: dark) == nil)
                    #expect(color.badgeFillRGB(dark: dark) == nil)
                    continue
                }
                guard let text = color.rgb(dark: dark), let fill = color.badgeFillRGB(dark: dark) else {
                    Issue.record("Expected a fixed colour for \(color) in \(dark ? "dark" : "light") mode")
                    continue
                }
                #expect(fill != CardColor.cardBackgroundRGB(dark: dark), "fill should be tinted")
                #expect(contrast(text, fill) >= 4.5, "\(color) in \(dark ? "dark" : "light") mode")
            }
        }
    }

}
