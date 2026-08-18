import Foundation

/// One row of the Drivers screen (FR-22).
///
/// ## Modelled, not rendered
///
/// There is no UI target yet — `AppFeature` arrives with its own story — so the
/// screen exists here as the data it will show and a test that pins the mapping.
/// The same deferral the freshness badge used: build the decision, defer the
/// pixels. When the screen lands it renders these rows and adds nothing to them,
/// which is the point — a view that derives its own Verification Status is a view
/// that can disagree with the catalog.
///
/// Every field is carried, none is computed from the outside. ``isActive`` is
/// derived from ``state`` rather than passed in separately, so a row cannot claim
/// to be active while showing a state that says otherwise.
public struct DriverRow: Hashable, Sendable, Identifiable {

    /// The Driver's reverse-domain identity — stable across renames, so a row
    /// keeps its place in a list when its display name changes.
    public let id: DriverIdentifier

    /// What the user sees, from ``DriverDescriptor/displayName``.
    public let name: String

    /// The Protocol column, from ``DriverDescriptor/transport``.
    public let transport: DriverTransport

    /// The Driver's semantic version, from ``DriverDescriptor/version``.
    public let version: String

    /// Where this Driver is in its lifecycle right now — the platform's
    /// ``DriverLifecycle/state``, not anything the Driver reports about itself.
    public let state: DriverLifecycleState

    /// How far this Driver has been proven, from
    /// ``DriverDescriptor/verification``. Shown verbatim; never inferred from
    /// ``state``. A connected Driver is not a verified one.
    public let verification: VerificationStatus

    /// Whether this Driver is providing everything it claims.
    ///
    /// ``DriverLifecycleState/degraded`` is deliberately NOT active: a Driver that
    /// is connected but not delivering one of its capabilities must not be
    /// rendered as though it were, because the Coverage Claim must never overstate
    /// what is being watched (SI-6).
    public var isActive: Bool { state == .active }

    /// Builds the row for one catalog entry in one lifecycle state.
    ///
    /// The only way to make a row: there is no memberwise initializer, so a row's
    /// fields cannot drift from the descriptor they claim to describe.
    public init(descriptor: DriverDescriptor, state: DriverLifecycleState) {
        self.id = descriptor.identifier
        self.name = descriptor.displayName
        self.transport = descriptor.transport
        self.version = descriptor.version
        self.state = state
        self.verification = descriptor.verification
    }
}

extension DriverCatalog {

    /// A row per catalog entry, in catalog order.
    ///
    /// - Parameter state: the lifecycle state of a given Driver. Drivers the
    ///   platform is not tracking yet are ``DriverLifecycleState/notActivated`` —
    ///   the resting state, not an error state, and not "unknown". A Driver the
    ///   platform has no lifecycle for is one it has not activated.
    public static func rows(
        state: (DriverDescriptor) -> DriverLifecycleState = { _ in .notActivated }
    ) -> [DriverRow] {
        entries.map { DriverRow(descriptor: $0, state: state($0)) }
    }
}
