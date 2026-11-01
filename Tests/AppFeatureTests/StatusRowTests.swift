import Testing
import Foundation
@testable import AppFeature
import DriverAPI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Suite("Home status row presentation")
struct StatusRowTests {
    @Test(arguments: [
        (PumpConnectionState.connected, StatusGlyph.linked, StatusColor.primary, nil as String?, "Pump connected"),
        (.connecting, .searching, .caution, "Connecting...", "Connecting to pump"),
        (.authenticating, .searching, .caution, "Connecting...", "Connecting to pump"),
        (.reconnecting, .reconnecting, .caution, "Reconnecting...", "Reconnecting to pump"),
        (.scanning, .searching, .caution, "Scanning...", "Scanning for pump"),
        (.authFailed, .crossedOut, .error, "Pairing failed", "Pump pairing failed"),
        (.disconnected, .crossedOut, .muted, "No pump", "No pump connected")
    ])
    func pumpStates(state: PumpConnectionState, glyph: StatusGlyph, color: StatusColor, text: String?, label: String) {
        let result = PumpLinkIndicator.make(state)
        #expect(result.glyph == glyph)
        #expect(result.color == color)
        #expect(result.text == text)
        #expect(result.accessibilityLabel == label)
    }

    @Test func notConfiguredHasNoCloudIndicatorsAndDisconnectedIsQuiet() {
        let state = StatusRowState.make(connection: .disconnected, backend: .notConfigured,
                                        activeDrivers: [DriverIdentifier("com.glycemicgpt.simulated")!])
        #expect(state.pumpLink.text == "No pump")
        #expect(state.sync == nil)
        #expect(state.reachability == nil)
        #expect(state.marks.isEmpty)
        let copy = (state.pumpLink.text ?? "") + " " + state.pumpLink.accessibilityLabel
        for word in ["error", "fail", "problem", "warning"] { #expect(!copy.localizedCaseInsensitiveContains(word)) }
    }

    @Test func visibleColorAndTextPairsDistinguishAllSixStates() {
        let states: [PumpConnectionState] = [.connected, .connecting, .reconnecting, .scanning, .authFailed, .disconnected]
        let pairs = states.map { state in
            let indicator = PumpLinkIndicator.make(state)
            return "\(indicator.color)|\(indicator.text ?? "")"
        }
        #expect(Set(pairs).count == 6)
        #expect(PumpLinkIndicator.make(.connecting) == PumpLinkIndicator.make(.authenticating))
    }

    @Test func syncBranchesUseFirstMatchAndSpeakPendingCount() {
        #expect(SyncIndicator.make(.init(hasError: true, pendingCount: 3, lastSync: .now)).accessibilityLabel == "Sync error")
        #expect(SyncIndicator.make(.init(hasError: false, pendingCount: 3, lastSync: .now)).accessibilityLabel == "3 readings pending sync")
        #expect(SyncIndicator.make(.init(hasError: false, pendingCount: 0, lastSync: .now)).glyph == .transfer)
        #expect(SyncIndicator.make(.init(hasError: false, pendingCount: 0, lastSync: nil)).accessibilityLabel == "Not synced")
    }

    @Test func reachabilityStates() {
        #expect(ReachabilityIndicator.make(.reachable).glyph == .cloudCheck)
        #expect(ReachabilityIndicator.make(.backendUnreachable).text == "Backend unreachable")
        #expect(ReachabilityIndicator.make(.offline).accessibilityLabel == "Device offline")
    }

    @Test func configuredStateExposesBothCloudIndicators() {
        let backend = BackendConfiguration.configured(.init(sync: .init(hasError: false, pendingCount: 2, lastSync: nil), reachability: .reachable))
        let state = StatusRowState.make(connection: .disconnected, backend: backend, activeDrivers: [])
        #expect(state.sync?.accessibilityLabel == "2 readings pending sync")
        #expect(state.reachability?.accessibilityLabel == "Backend reachable")
    }

    @Test func injectedBrandLookupSortsAndSkipsMissingEntries() {
        let a = DriverIdentifier("com.example.alpha")!
        let b = DriverIdentifier("com.example.beta")!
        let missing = DriverIdentifier("com.example.none")!
        let lookup: DriverBrandMarks.Lookup = { id in
            guard id != missing else { return nil }
            return BrandMark(name: id == a ? "Alpha" : "Beta", assetName: id.rawValue, height: id == a ? 16 : 12)
        }
        let result = DriverBrandMarks.make([b, missing, a], lookup: lookup)
        #expect(result.map(\.identifier) == [a, b])
        #expect(result.map(\.mark.height) == [16, 12])
        #expect(DriverBrandMarks.productionLookup(a) == nil)
    }

    @Test func brandMarkIdentifierUsesLowercasedName() {
        let mark = BrandMark(name: "Tandem", assetName: "tandem", height: 16)
        #expect(mark.accessibilityIdentifier == "status.brand.tandem")
    }
}

#if canImport(UIKit)
extension StatusRowTests {
    @Test func everyStatusGlyphResolvesToAnSFSymbol() {
        for glyph in StatusGlyph.allCases {
            #expect(UIImage(systemName: glyph.systemName) != nil, "Missing SF Symbol: \(glyph.systemName)")
        }
    }
}
#elseif canImport(AppKit)
extension StatusRowTests {
    @Test func everyStatusGlyphResolvesToAnSFSymbol() {
        for glyph in StatusGlyph.allCases {
            #expect(NSImage(systemSymbolName: glyph.systemName, accessibilityDescription: nil) != nil, "Missing SF Symbol: \(glyph.systemName)")
        }
    }
}
#endif

@Suite("Home status row colour tokens")
struct StatusRowColourTests {
    @Test func lightModeUsesHighContrastCautionAndError() {
        #expect(StatusColor.caution.rgb(dark: false) == StatusRGB(red: 0xA1, green: 0x62, blue: 0x07))
        #expect(StatusColor.error.rgb(dark: false) == StatusRGB(red: 0xB9, green: 0x1C, blue: 0x1C))
        #expect(StatusColor.primary.rgb(dark: false) == StatusRGB(red: 0x25, green: 0x63, blue: 0xEB))
        #expect(StatusColor.muted.rgb(dark: false) == nil)
    }

    @Test func darkModeKeepsTheBrighterCautionAndError() {
        #expect(StatusColor.caution.rgb(dark: true) == StatusRGB(red: 0xEA, green: 0xB3, blue: 0x08))
        #expect(StatusColor.error.rgb(dark: true) == StatusRGB(red: 0xEF, green: 0x44, blue: 0x44))
    }
}

@Suite("Hero age caption colour contrast")
struct HeroAgeCaptionColourTests {
    @Test func lightAgeColoursReachSmallTextContrastOnWhite() {
        for color in [HeroColor.green, .amber, .red] {
            guard let rgb = color.ageCaptionRGB(dark: false) else {
                Issue.record("Expected a fixed light-mode age colour")
                continue
            }
            #expect(contrast(rgb, .init(red: 255, green: 255, blue: 255)) >= 4.5)
        }
    }

    @Test func darkModeKeepsTheExistingAgeColours() {
        #expect(HeroColor.green.ageCaptionRGB(dark: true) == StatusRGB(red: 0x22, green: 0xC5, blue: 0x5E))
        #expect(HeroColor.amber.ageCaptionRGB(dark: true) == StatusRGB(red: 0xEA, green: 0xB3, blue: 0x08))
        #expect(HeroColor.red.ageCaptionRGB(dark: true) == StatusRGB(red: 0xEF, green: 0x44, blue: 0x44))
    }

    @Test func secondaryAgeCaptionUsesTheSystemSemanticColour() {
        #expect(HeroColor.secondary.ageCaptionRGB(dark: false) == nil)
        #expect(HeroColor.secondary.ageCaptionRGB(dark: true) == nil)
    }

    private func contrast(_ a: StatusRGB, _ b: StatusRGB) -> Double {
        func luminance(_ value: StatusRGB) -> Double {
            let channels = [value.red, value.green, value.blue].map { component -> Double in
                let c = Double(component) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let values = [luminance(a), luminance(b)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }
}
