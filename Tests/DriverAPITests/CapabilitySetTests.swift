import Foundation
import Testing

@testable import DriverAPI

/// The Capability set is closed at six (FR-30, AD-12, SI-1).
///
/// "Closed" is a claim about the future, so it is asserted from three directions
/// that fail for different reasons:
///
/// * the ``Capability`` enum's case count — catches a seventh case;
/// * ``CapabilityPort``, exhaustively switched here — a seventh case does not
///   compile past this suite, and there is no erased supertype through which a
///   Driver could hand the platform anything else;
/// * a scan of the target's DECLARATIONS for protocols — catches a seventh port
///   added anywhere in `DriverAPI`, in any formatting.
///
/// The third used to be a per-line regex requiring the conformance on the same
/// line as the keyword, which a line-wrapped declaration walked straight past.
/// It now reads a token stream over the whole file (see
/// ``DriverAPISource/declarations()``), and ``portScanSeesALineWrappedProtocol``
/// pins that.
@Suite("The closed Capability set")
struct CapabilitySetTests {

    /// The six, spelled out. Changing this list is changing the product, and the
    /// test says so where it fails.
    static let expectedCapabilities: Set<Capability> = [
        .glucoseSource,
        .insulinSource,
        .pumpStatus,
        .bgmSource,
        .dataSync,
        .doseCategoryProvider,
    ]

    static let expectedPorts: Set<String> = [
        "GlucoseSource",
        "InsulinSource",
        "PumpStatusSource",
        "BGMSource",
        "DataSync",
        "DoseCategoryProvider",
    ]

    /// The protocols `DriverAPI` declares that are NOT Capability ports. Listed
    /// so the port scan can be a scan for *every* protocol in the target — a
    /// seventh port hidden in a non-obvious file is caught by exactly the same
    /// assertion as one added to `Capabilities/`.
    ///
    /// `Driver` is the only one, and that is now load-bearing beyond the count:
    /// `SafetyLimitsSource` used to be here, and it was a protocol a Driver could
    /// conform with captured limits. A replacement for it — any driver-implementable
    /// protocol that supplies safety state — fails this assertion the moment it is
    /// declared, wherever in the target it is put.
    static let expectedNonPortProtocols: Set<String> = [
        "Driver",
    ]

    @Test("There are exactly six Capabilities, and they are these six")
    func capabilitySetIsClosedAtSix() {
        #expect(Capability.allCases.count == 6)
        #expect(Set(Capability.allCases) == Self.expectedCapabilities)
    }

    @Test("DriverAPI declares exactly six Capability ports, and no other protocol beyond Driver")
    func exactlySixPortsAreDeclared() throws {
        var ports: Set<String> = []
        var others: Set<String> = []
        for declaration in try DriverAPISource.declarations() where declaration.keyword == "protocol" {
            if Self.expectedNonPortProtocols.contains(declaration.name) {
                others.insert(declaration.name)
                continue
            }
            #expect(
                declaration.path.hasPrefix("Sources/DriverAPI/Capabilities/"),
                "protocol \(declaration.name) is declared in \(declaration.path); Capability ports live in Capabilities/"
            )
            ports.insert(declaration.name)
        }
        #expect(ports == Self.expectedPorts, "declared ports: \(ports.sorted())")
        #expect(others == Self.expectedNonPortProtocols)
    }

    /// The counterexample the cycle-1 scan missed, verbatim in shape: a seventh
    /// port whose conformance sits on the following line. If this stops being
    /// seen, the assertion above is decorative again.
    @Test("The port scan sees a protocol whose declaration is split across lines")
    func portScanSeesALineWrappedProtocol() throws {
        let source = """
        /// A protocol in a doc comment must not count.
        public protocol
            ExtraSource:
                Sendable,
                CustomStringConvertible
        {
            func enactTherapy() async
        }
        """
        let declarations = try DriverAPISource.declarations(in: source)
        #expect(declarations.count == 1)
        #expect(declarations.first?.name == "ExtraSource")
        #expect(declarations.first?.inherited == ["Sendable", "CustomStringConvertible"])
    }

    /// A Driver hands the platform a ``CapabilityPort``, and there are six of
    /// them. This switch is exhaustive and has no `default`: a seventh case
    /// cannot be added to `CapabilityPort` without this test failing to COMPILE,
    /// which is a stronger statement than any count assertion.
    @Test("Every port maps onto exactly one Capability, and the six ports cover the six Capabilities")
    func portsMapOntoTheCapabilitySet() {
        let ports: [CapabilityPort] = [
            .glucoseSource(StubGlucoseSource()),
            .insulinSource(StubInsulinSource()),
            .pumpStatus(StubPumpStatusSource()),
            .bgmSource(StubBGMSource()),
            .dataSync(StubDataSync()),
            .doseCategoryProvider(StubDoseCategoryProvider()),
        ]
        let reported = ports.map(\.capability)
        #expect(Set(reported) == Self.expectedCapabilities)
        #expect(reported.count == Set(reported).count, "two ports report the same Capability")

        // The other direction: every Capability has a port. Exhaustive, so a new
        // Capability case does not compile until it has one.
        for capability in Capability.allCases {
            let port = ports.first { $0.capability == capability }
            #expect(port != nil, "\(capability) has no CapabilityPort case")
            switch capability {
            case .glucoseSource, .insulinSource, .pumpStatus, .bgmSource, .dataSync, .doseCategoryProvider:
                break
            }
        }
    }

    /// The closure is about what a Driver can HAND OVER, so it is asserted on the
    /// Driver contract too: what comes back is a `CapabilityPort`, an enum, not
    /// an existential a Driver target can widen by conforming its own type to a
    /// public marker and a consumer can narrow again with `as?`.
    @Test("A Driver can only hand back one of the six ports")
    func driverVendsOnlyTheClosedSet() async {
        let driver = StubDriver()
        for capability in Capability.allCases {
            guard let port = driver.capability(capability) else {
                Issue.record("the stub claims \(capability) and returned no port")
                continue
            }
            #expect(port.capability == capability, "\(capability) returned the port for \(port.capability)")
        }
    }

    // MARK: - No calibration, anywhere

    /// Android's seventh capability, `CALIBRATION_TARGET`, sends a fingerstick
    /// reading back to a sensor. It is deliberately absent (see ``Capability``),
    /// and its absence is pinned rather than trusted: it is the one capability
    /// whose direction is outward, so it is the one whose reintroduction would
    /// make a therapeutic write look like an ordinary addition.
    ///
    /// The scan runs over stripped code — the doc comments that EXPLAIN the
    /// absence say "calibration" repeatedly and must not trip it.
    @Test("No calibration member exists anywhere in DriverAPI")
    func nothingInTheTargetMentionsCalibration() throws {
        var offenders: [String] = []
        for (path, line) in try DriverAPISource.lines() where line.lowercased().contains("calibrat") {
            offenders.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
        }
        #expect(offenders.isEmpty, "calibration is not part of the closed set: \(offenders)")
    }

    @Test("No Capability case names calibration")
    func noCapabilityCaseNamesCalibration() {
        #expect(Capability.allCases.allSatisfy { !$0.rawValue.lowercased().contains("calibrat") })
    }

    /// The scan above asserts an absence, so it must be shown capable of
    /// reporting a presence — otherwise a stripper change that elided everything
    /// would leave it green forever.
    @Test("The calibration scan sees a calibration member when there is one")
    func calibrationScanCanFail() throws {
        let source = "/// no calibration is accepted here\nfunc acceptCalibration() {}"
        let code = try DriverAPISource.stripped(source)
        let hits = code.split(separator: "\n").filter { $0.lowercased().contains("calibrat") }
        #expect(hits.count == 1, "the comment must be elided and the declaration must not be")
    }
}
