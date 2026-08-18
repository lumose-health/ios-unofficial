/// The closed set of things a Driver may provide (AD-12, FR-30, SI-1).
///
/// Six members, and the set is CLOSED: adding a seventh is a PRD change, not a
/// pull request. The closure is the point. An open capability set is how a
/// therapeutic write eventually arrives — not as `deliverBolus()` in a review
/// somebody waves through, but as a plausible new capability that a later
/// capability quietly builds on.
///
/// ## What is deliberately absent
///
/// Android declares a seventh, `CALIBRATION_TARGET` — a Driver that *accepts* a
/// calibration from a fingerstick reading. It is absent here, on purpose: it is
/// the one capability in that set whose direction is inward-to-outward, a value
/// this app sends to a device. It is not a therapeutic write, but it is the only
/// shape in the set that would make one look ordinary. There is no calibration
/// member anywhere in `DriverAPI`, and `DriverAPITests` pins its absence.
///
/// ## Naming
///
/// The case names track Android's `PluginCapability`
/// (`plugins/pump-driver-api/.../plugin/PluginCapability.kt`) so the two apps
/// describe the same Driver with the same words — with one deliberate exception,
/// ``doseCategoryProvider``, explained on that case.
public enum Capability: String, CaseIterable, Hashable, Sendable {

    /// Continuous glucose readings: a standalone CGM, or a pump that streams one.
    case glucoseSource

    /// Insulin on board and completed dose history, read-only (SI-7).
    case insulinSource

    /// Pump hardware state — battery, reservoir, model and firmware. Read-only.
    case pumpStatus

    /// Fingerstick blood-glucose readings from a meter.
    case bgmSource

    /// Mirroring readings to an external service the user already runs
    /// (Nightscout, Tidepool). Nothing here reaches a pump.
    case dataSync

    /// Mapping a device's own dose-category labels onto the platform vocabulary.
    ///
    /// Android calls this `BOLUS_CATEGORY_PROVIDER`. The word is dropped here
    /// because `bolus` is a denied symbol in `scripts/guards/driver_guards.sh`,
    /// which scans `DriverAPI` and every Driver target for delivery verbs. Naming
    /// the read-side capability with a denied word would have forced the guard to
    /// carry a per-symbol exemption — and an exemption list is precisely how a
    /// write surface eventually gets waved through. A category is a property of a
    /// dose that already happened, so `dose` is the accurate word regardless.
    case doseCategoryProvider
}

/// The one thing a Driver may hand the platform: one of exactly six ports.
///
/// ## Why an enum, and not a marker protocol
///
/// The first version of this file declared `protocol DriverCapability` and had
/// ``Driver/capability(_:)`` return `any DriverCapability`. That is an OPEN set
/// wearing a closed set's documentation. A Driver target can conform its own type
/// to a public marker, hand it back through the existential, and a consumer can
/// downcast it to the concrete type and call whatever it likes — which is a
/// runtime plug-in mechanism, arrived at by accident, in the one project whose
/// entire posture is that no such mechanism exists (AD-12, AD-17).
///
/// So the family is this enum instead. Its cases are the closed set: a seventh
/// Capability cannot be handed to the platform because there is no case to put it
/// in, and there is no erased supertype to smuggle it through. Adding one means
/// adding a case here and a ``Capability`` there, in `DriverAPI`, in a diff — and
/// the switch below stops compiling until both are done.
///
/// The payloads are `any` existentials of the six port protocols, which is the
/// narrow kind of erasure: the platform can only call what the port declares, and
/// every port declares reads.
///
/// ## The seam that remains, stated exactly
///
/// An existential is DOWNCASTABLE, and Swift has no sealed conformances. So a
/// Driver can conform its own concrete type to one of the six ports, hand it over
/// in the matching case, and a consumer that knows the concrete type can narrow
/// the existential back to it and call members this module never declared:
///
/// ```swift
/// guard case .doseCategoryProvider(let port) = await driver.capability(.doseCategoryProvider),
///       let smuggled = port as? ExtraPort else { return }
/// smuggled.performStepTwo()
/// ```
///
/// The enum does not close that and no arrangement of Swift types can. What is
/// true is narrower and worth stating in those terms: the platform holding
/// `any DoseCategoryProvider` can call nothing but what `DoseCategoryProvider`
/// declares, and the downcast — the one step that reaches anything else — is a
/// gate failure. `scripts/guards/driver_guards.sh` fails any `as?`, `as!` or `is`
/// against a Capability port, `Driver`, `CapabilityPort` or a Driver-target type
/// anywhere under `Sources/` outside this module. The guard's header documents
/// what that still leaves, and its self-test pins the residual as an
/// expected-uncaught case so the claim cannot quietly grow.
public enum CapabilityPort: Sendable {

    /// Continuous glucose readings.
    case glucoseSource(any GlucoseSource)

    /// Insulin on board and completed doses.
    case insulinSource(any InsulinSource)

    /// Pump hardware state.
    case pumpStatus(any PumpStatusSource)

    /// Fingerstick readings.
    case bgmSource(any BGMSource)

    /// Mirroring to an external service the user runs.
    case dataSync(any DataSync)

    /// Device dose-category labels mapped onto the platform vocabulary.
    case doseCategoryProvider(any DoseCategoryProvider)

    /// Which member of the closed set this port is.
    ///
    /// Exhaustive on purpose and without a `default`: a new case here fails to
    /// compile until it has a ``Capability`` to name, and a new ``Capability``
    /// with no port shows up as an unbuildable switch in the tests.
    public var capability: Capability {
        switch self {
        case .glucoseSource: return .glucoseSource
        case .insulinSource: return .insulinSource
        case .pumpStatus: return .pumpStatus
        case .bgmSource: return .bgmSource
        case .dataSync: return .dataSync
        case .doseCategoryProvider: return .doseCategoryProvider
        }
    }
}
