import Foundation
import Testing

@testable import DriverAPI

/// The DriverAPI boundary refuses values no device can have produced (AD-22).
///
/// Glucose gets this from ``SafetyCore/Glucose`` and the validator; the other
/// physical measurements and the two identity-bearing strings get it from their
/// initializers, pinned here. The rule is the same everywhere: a model that
/// EXISTS is a model whose numbers are physically possible and whose strings
/// honour their stated contract, so a decoding artefact cannot become a
/// platform record by being constructed.
@Suite("Boundary validation")
struct ModelValidationTests {

    static let anInstant = Date(timeIntervalSince1970: 1_755_000_000)

    // MARK: - DriverIdentifier

    @Test("A reverse-domain identifier is accepted verbatim")
    func identifierAcceptsReverseDomain() throws {
        let identifier = try #require(DriverIdentifier("com.glycemicgpt.tandem"))
        #expect(identifier.rawValue == "com.glycemicgpt.tandem")
        #expect(identifier.description == "com.glycemicgpt.tandem")
        #expect(DriverIdentifier("io.t-1.reader") != nil, "digits and hyphens are legal label characters")
    }

    /// The identifier doubles as settings-suite and Keychain service name, so a
    /// degenerate value is a namespace two Drivers can collide in. None of
    /// these may produce an identifier at all.
    @Test(
        "A value that is not a reverse-domain identifier is refused",
        arguments: [
            "",
            " ",
            "   ",
            "tandem",
            "com.",
            ".tandem",
            "com..tandem",
            "com. glycemicgpt.tandem",
            "com.glycemicgpt.tandem ",
            "com.glycemic gpt",
            "com.glycemicgpt.tandem\n",
        ]
    )
    func identifierRefusesMalformedValues(rawValue: String) {
        #expect(DriverIdentifier(rawValue) == nil, "accepted: \(rawValue.debugDescription)")
    }

    // MARK: - SyncDestination

    @Test("A bare host is accepted, with or without a port")
    func destinationAcceptsBareHosts() throws {
        let plain = try #require(SyncDestination(serviceName: "Nightscout", host: "nightscout.example"))
        #expect(plain.host == "nightscout.example")
        #expect(SyncDestination(serviceName: "Nightscout", host: "nightscout.example:1337") != nil)
        #expect(SyncDestination(serviceName: "Nightscout", host: "nightscout.example:1") != nil)
        #expect(SyncDestination(serviceName: "Nightscout", host: "nightscout.example:65535") != nil)
    }

    /// The host-only contract, enforced rather than promised: a URL that
    /// carries a scheme, credentials, a path, a query or a fragment is the
    /// credential-disclosure shape SI-9 exists to keep off the screen. A colon
    /// passes only as the port separator — one colon, digits in `1...65535`
    /// after it — so a scheme-prefixed value or a colon-delimited secret is
    /// refused too.
    @Test(
        "A destination that is more than a host is refused",
        arguments: [
            "",
            "https://nightscout.example",
            "https://token@nightscout.example/path",
            "token@nightscout.example",
            "nightscout.example/api/v1",
            "nightscout.example?token=abc",
            "nightscout.example#fragment",
            " nightscout.example",
            "nightscout example",
            "https:nightscout.example",
            "mailto:token",
            "nightscout.example:1337:1338",
            "nightscout.example:s3cr3t",
            "nightscout.example:13a7",
            "nightscout.example:+443",
            "nightscout.example:0",
            "nightscout.example:65536",
            "nightscout.example:",
            ":1337",
        ]
    )
    func destinationRefusesNonHosts(host: String) {
        #expect(
            SyncDestination(serviceName: "Nightscout", host: host) == nil,
            "accepted: \(host.debugDescription)"
        )
    }

    // MARK: - Insulin quantities

    @Test("Insulin on board accepts finite, non-negative quantities")
    func insulinOnBoardAcceptsMeasurements() throws {
        let sample = try InsulinOnBoardSample(units: 2.5, calculatedAt: Self.anInstant)
        #expect(sample.units == 2.5)
        #expect(try InsulinOnBoardSample(units: 0, calculatedAt: Self.anInstant).units == 0)
    }

    /// Negative AND non-finite both classify as ``DriverFailure/valueRejected(bound:)``,
    /// never decode-class: these initializers run after parsing, and a NaN that
    /// reached one re-reads to the same NaN, so a decode-class refusal would
    /// wedge the cursor behind it forever (AD-22).
    @Test("Insulin on board refuses a quantity no device can have measured, value-class")
    func insulinOnBoardRefusesGarbage() {
        for units in [-0.5, Double.nan, .infinity, -.infinity] {
            do {
                _ = try InsulinOnBoardSample(units: units, calculatedAt: Self.anInstant)
                Issue.record("\(units) was admitted")
            } catch {
                guard case .valueRejected = error else {
                    Issue.record("\(units) must refuse value-class, got \(error): the record is consumed and the cursor advances (AD-22)")
                    continue
                }
            }
        }
    }

    @Test("A dose record accepts finite, non-negative quantities")
    func doseRecordAcceptsMeasurements() throws {
        let record = try DoseRecord(units: 1.35, completedAt: Self.anInstant, category: .correction)
        #expect(record.units == 1.35)
    }

    /// A negative completed dose subtracts from insulin on board, and NaN
    /// poisons every sum it touches. Both are refusals, and the failure is
    /// ``DriverFailure/valueRejected(bound:)`` so the cursor semantics of
    /// AD-22 apply: the record is consumed, the value is dropped.
    @Test("A dose record refuses a quantity no pump can have completed")
    func doseRecordRefusesGarbage() {
        for units in [-1.0, Double.nan, .infinity, -.infinity] {
            do {
                _ = try DoseRecord(units: units, completedAt: Self.anInstant, category: .other)
                Issue.record("\(units) was admitted as a completed dose")
            } catch {
                guard case .valueRejected(let bound) = error else {
                    Issue.record("wrong failure for \(units): \(error)")
                    continue
                }
                #expect(!bound.isEmpty)
            }
        }
    }

    // MARK: - Pump status

    @Test("A snapshot accepts reported values, and nil for the unreported")
    func snapshotAcceptsPossibleValues() throws {
        let full = try PumpStatusSnapshot(
            batteryFraction: 0.75,
            reservoirUnits: 142.5,
            observedAt: Self.anInstant
        )
        #expect(full.batteryFraction == 0.75)
        #expect(full.reservoirUnits == 142.5)

        let empty = try PumpStatusSnapshot(observedAt: Self.anInstant)
        #expect(empty.batteryFraction == nil)
        #expect(empty.reservoirUnits == nil)

        let bounds = try PumpStatusSnapshot(batteryFraction: 0, reservoirUnits: 0, observedAt: Self.anInstant)
        #expect(bounds.batteryFraction == 0)
        _ = try PumpStatusSnapshot(batteryFraction: 1, observedAt: Self.anInstant)
    }

    @Test("A snapshot refuses a battery fraction outside 0...1, value-class")
    func snapshotRefusesImpossibleBattery() {
        for fraction in [-0.01, 1.01, Double.nan, .infinity, -.infinity] {
            do {
                _ = try PumpStatusSnapshot(batteryFraction: fraction, observedAt: Self.anInstant)
                Issue.record("\(fraction) was admitted")
            } catch {
                guard case .valueRejected = error else {
                    Issue.record("\(fraction) must refuse value-class, got \(error) (AD-22)")
                    continue
                }
            }
        }
    }

    @Test("A snapshot refuses a negative or non-finite reservoir, value-class")
    func snapshotRefusesImpossibleReservoir() {
        for units in [-1.0, Double.nan, .infinity, -.infinity] {
            do {
                _ = try PumpStatusSnapshot(reservoirUnits: units, observedAt: Self.anInstant)
                Issue.record("\(units) was admitted")
            } catch {
                guard case .valueRejected = error else {
                    Issue.record("\(units) must refuse value-class, got \(error) (AD-22)")
                    continue
                }
            }
        }
    }
}
