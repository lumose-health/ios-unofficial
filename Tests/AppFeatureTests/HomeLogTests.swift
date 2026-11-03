import Testing
import AppFeature
import DriverAPI

@Suite("Home refresh logging")
struct HomeLogTests {
    @Test func failureCaseNamesDoNotExposeAssociatedValues() {
        let cases: [(DriverFailure, String)] = [
            (.notPaired, "notPaired"), (.authenticationRejected, "authenticationRejected"),
            (.transportUnavailable, "transportUnavailable"), (.connectionLost, "connectionLost"),
            (.timedOut, "timedOut"), (.decodeFailed(detail: "secret"), "decodeFailed"),
            (.valueRejected(bound: "secret"), "valueRejected"), (.capabilityUnavailable(.glucoseSource), "capabilityUnavailable"),
            (.deviceFault(code: "secret"), "deviceFault"),
            (.illegalTransition(from: .active, to: .failed), "illegalTransition"),
            (.safetyLimitRejected(.notFinite), "safetyLimitRejected"), (.cancelled, "cancelled"),
            (.pairingRejected(.codeRejected), "pairingRejected"),
        ]
        for (failure, expected) in cases { #expect(failure.caseName == expected) }
    }
}
