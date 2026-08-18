import Testing

@testable import SafetyCore

/// Exactly three presentation cases carrying the FR-51 contract. Pins the
/// literal text and the case mapping, not a rendered UI — no UI target exists
/// yet.
@Suite("FreshnessBadge")
struct FreshnessBadgeTests {

    @Test("Fresh renders nothing")
    func freshRendersNothing() {
        let badge = FreshnessBadge(.fresh)
        #expect(badge == .none)
        #expect(badge.text == nil)
        #expect(badge.color == nil)
    }

    @Test("Stale renders literal text \"Stale\" in amber")
    func staleRendersAmber() {
        let badge = FreshnessBadge(.stale)
        #expect(badge == .stale)
        #expect(badge.text == "Stale")
        #expect(badge.color == .amber)
    }

    @Test("TooStale renders literal text \"Too old\" in the error color")
    func tooStaleRendersError() {
        let badge = FreshnessBadge(.tooStale)
        #expect(badge == .tooStale)
        #expect(badge.text == "Too old")
        #expect(badge.color == .error)
    }
}
