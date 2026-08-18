import Foundation
import Testing

@testable import DriverAPI

/// The failure taxonomy is declared once (AD-13, spine §141).
@Suite("Driver failure taxonomy")
struct DriverFailureTests {

    /// One `Error` type in the target, not one per Driver and not one per
    /// concern. The scan is over source rather than over a hand-written list,
    /// because the thing being prevented is a SECOND enum somebody adds later —
    /// and a hand-written list is exactly what that person would not update.
    ///
    /// It reads declarations from a token stream rather than line by line. The
    /// cycle-1 version required `Error` on the same line as the keyword, so
    /// `enum OtherFailure:` with `Error` wrapped onto the next line — ordinary
    /// formatting for a long conformance list — was invisible to the one test
    /// that existed to see it.
    @Test("DriverAPI declares exactly one Error type")
    func exactlyOneErrorType() throws {
        let declared = try DriverAPISource.declarations()
            .filter { $0.inherited.contains("Error") }
        #expect(declared.count == 1, "Error-conforming types in DriverAPI: \(declared.map(\.description))")
        #expect(declared.first?.name == "DriverFailure", "\(declared.map(\.description))")
    }

    /// The counterexample the cycle-1 scan missed, plus the retro-conformance
    /// shape (`extension X: Error`) that no keyword scan would have seen at all.
    @Test("The Error-type scan sees a second one however it is written")
    func errorTypeScanCanFail() throws {
        let wrapped = try DriverAPISource.declarations(in: """
        public enum OtherFailure:
            Error,
            Hashable
        {
            case somethingElse
        }
        """)
        #expect(wrapped.count == 1)
        #expect(wrapped.first?.name == "OtherFailure")
        #expect(wrapped.first?.inherited.contains("Error") == true)

        let retro = try DriverAPISource.declarations(in: "extension WireFault: Error {}")
        #expect(retro.first?.name == "WireFault")
        #expect(retro.first?.inherited.contains("Error") == true)

        // …and it does not fire on a type that merely mentions the word, on a
        // parameter of type `Error`, or on the word inside a comment.
        let innocent = try DriverAPISource.declarations(in: """
        /// enum SomethingElse: Error — in prose only.
        public struct ErrorBanner: Hashable {
            func handle(_ error: Error) {}
        }
        """)
        #expect(innocent.count == 1)
        #expect(innocent.first?.name == "ErrorBanner")
        #expect(innocent.first?.inherited == ["Hashable"])
    }

    /// Decode failure and value rejection are different outcomes with different
    /// cursor behaviour (AD-22). Merging them is the defect this pins against, so
    /// the two cases must not be equal even when their payloads read alike.
    @Test("Decode failure and value rejection are distinct cases")
    func decodeAndRejectionAreDistinct() {
        let decode = DriverFailure.decodeFailed(detail: "history frame 12")
        let rejection = DriverFailure.valueRejected(bound: "history frame 12")
        #expect(decode != rejection)
    }

    @Test("Pairing failures distinguish never-paired from credential-rejected")
    func pairingFailuresAreDistinct() {
        #expect(DriverFailure.notPaired != DriverFailure.authenticationRejected)
    }

    @Test("A failure carries the Capability that was unavailable")
    func capabilityFailureCarriesTheCapability() {
        let failure = DriverFailure.capabilityUnavailable(.glucoseSource)
        #expect(failure != .capabilityUnavailable(.insulinSource))
        guard case .capabilityUnavailable(let capability) = failure else {
            Issue.record("payload lost")
            return
        }
        #expect(capability == .glucoseSource)
    }

    @Test("Safety-limit rejections say which bound failed")
    func limitRejectionsCarryTheirReason() {
        let rejections: [SafetyLimitRejection] = [
            .widensAbsoluteBound(lower: 10, upper: 600),
            .notFinite,
            .emptyOrInverted(lower: 200, upper: 100),
        ]
        // Distinct reasons, so a consumer can say what the user got wrong rather
        // than showing one generic refusal (AD-13).
        #expect(Set(rejections).count == rejections.count)
    }
}
