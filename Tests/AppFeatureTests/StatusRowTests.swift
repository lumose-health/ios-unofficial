import Testing
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
