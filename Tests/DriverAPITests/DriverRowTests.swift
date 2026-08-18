import Foundation
import Testing

@testable import DriverAPI

/// The Drivers screen, modelled rather than rendered.
///
/// No UI target exists until `AppFeature` arrives, so what is pinned here is the
/// mapping the screen will apply — the part that can be wrong in a way a user
/// would act on. A row that shows a Driver as verified because it happens to be
/// connected is the failure this suite exists to prevent.
@Suite("Drivers screen rows")
struct DriverRowTests {

    static let tandem = DriverDescriptor(
        identifier: DriverIdentifier("com.glycemicgpt.tandem")!,
        targetName: "Tandem",
        displayName: "Tandem Insulin Pump",
        transport: .bluetoothLowEnergy,
        version: "1.2.0",
        capabilities: [.glucoseSource, .insulinSource, .pumpStatus],
        verification: .protocolCompatible
    )

    @Test("Every row field comes from the descriptor it was built from")
    func rowMapsFromDescriptor() {
        let row = DriverRow(descriptor: Self.tandem, state: .active)
        #expect(row.id == Self.tandem.identifier)
        #expect(row.name == Self.tandem.displayName)
        #expect(row.transport == Self.tandem.transport)
        #expect(row.version == Self.tandem.version)
        #expect(row.verification == Self.tandem.verification)
        #expect(row.state == .active)
    }

    @Test("Only the active state reads as active")
    func onlyActiveIsActive() {
        for state in DriverLifecycleState.allCases {
            let row = DriverRow(descriptor: Self.tandem, state: state)
            #expect(row.isActive == (state == .active), "\(state)")
        }
    }

    /// Degraded gets its own assertion because it is the one that would be
    /// tempting to fold into active: the Driver IS connected. It is not providing
    /// everything it claims, and a Coverage Claim built on a row that said
    /// otherwise would overstate what is being watched (SI-6).
    @Test("A degraded Driver is not shown as active")
    func degradedIsNotActive() {
        #expect(DriverRow(descriptor: Self.tandem, state: .degraded).isActive == false)
    }

    /// Verification is a property of the Driver, not of its current connection.
    @Test("Verification status does not move with lifecycle state")
    func verificationIsIndependentOfState() {
        for state in DriverLifecycleState.allCases {
            #expect(DriverRow(descriptor: Self.tandem, state: state).verification == .protocolCompatible)
        }
    }

    @Test("Every verification status survives the mapping verbatim")
    func everyVerificationStatusMapsThrough() {
        for status in VerificationStatus.allCases {
            let descriptor = DriverDescriptor(
                identifier: Self.tandem.identifier,
                targetName: Self.tandem.targetName,
                displayName: Self.tandem.displayName,
                transport: Self.tandem.transport,
                version: Self.tandem.version,
                capabilities: Self.tandem.capabilities,
                verification: status
            )
            #expect(DriverRow(descriptor: descriptor, state: .active).verification == status)
        }
    }

    @Test("The catalog produces one row per entry, in catalog order")
    func catalogRowsFollowTheCatalog() {
        let rows = DriverCatalog.rows()
        #expect(rows.count == DriverCatalog.entries.count)
        #expect(rows.map(\.id) == DriverCatalog.entries.map(\.identifier))
    }

    /// A Driver the platform is not tracking rests at `notActivated` — not
    /// "unknown", which would be a state the lifecycle does not declare and a
    /// fifth thing for a screen to render.
    @Test("An untracked Driver rests at not-activated")
    func untrackedDriversRest() {
        #expect(DriverRow(descriptor: Self.tandem, state: .notActivated).state == .notActivated)
        let rows = [Self.tandem].map { DriverRow(descriptor: $0, state: .notActivated) }
        #expect(rows.allSatisfy { !$0.isActive })
    }
}
