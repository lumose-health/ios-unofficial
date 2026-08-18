import Foundation
import SafetyCore

/// The only way to admit a glucose reading, and the holder of the Safety Limits
/// in force (FR-32, SI-11).
///
/// ## Why this is a final class and not a protocol
///
/// The previous shape was `protocol SafetyLimitsSource` with a `currentLimits`
/// requirement and a `validate(mgdl:)` extension that read it on every call. That
/// reads fresh only if the CONFORMER answers fresh, and the conformer is a Driver:
///
/// ```swift
/// struct CapturedLimits: SafetyLimitsSource {
///     let currentLimits: SafetyLimits   // captured once, at init
/// }
/// ```
///
/// That compiles, passes every gate, and validates against a bound the user
/// narrowed an hour ago — which is the behaviour AC 7 exists to forbid. "Asked
/// again on every call" is worth nothing when the thing being asked is free to
/// answer from a copy it took at start-up.
///
/// So the limits state moved to a type the PLATFORM owns and a Driver can neither
/// build nor stand in for:
///
/// * `final`, so it cannot be subclassed and its `validate(mgdl:)` cannot be
///   overridden;
/// * a class and not a protocol, so there is nothing to conform to and no
///   substitute to supply;
/// * ``init(limits:)`` and ``adopt(_:)`` are `@_spi(DriverPlatform)`, so an
///   ordinary `import DriverAPI` — what a Driver writes — cannot see them. A
///   Driver cannot construct one, and cannot change the limits inside the one it
///   was handed. `scripts/guards/driver_guards.sh` fails any `@_spi` import under
///   `Sources/Drivers/`, which is the one way around that (AD-16, and the same
///   pattern ``DriverLifecycle`` uses).
///
/// A Driver therefore RECEIVES a validator — the platform hands it one when it
/// constructs the Driver — and the only thing it can do with it is ask. The
/// limits it validates against are whatever the platform last adopted, read
/// inside the call, every call.
///
/// ## What this does NOT close, exactly
///
/// A value a Driver already read can still be stale. ``limitsInForce`` hands back
/// a `SafetyLimits`, and a `Glucose` that ``validate(mgdl:)`` admitted was admitted
/// against the bound in force at that instant; if the user narrows their range a
/// moment later, neither retroactively becomes invalid. Nothing in an API shape
/// can fix that, because the reading was genuinely admissible when it was read.
///
/// What bounds the damage is that a `SafetyLimits` value cannot validate anything
/// — ``SafetyLimits/validate(mgdl:)`` is internal to `DriverAPI` — so a captured
/// copy buys a Driver nothing but a pair of numbers to display. And the terminal
/// enforcement is not here at all: the write-time absolute-bound gate on the
/// persistence path (its own story) is what refuses an out-of-bound value on the
/// way into storage, no matter which Driver produced it or what it validated
/// against. This type is the near gate, not the last one.
///
/// ## Concurrency
///
/// `Sendable` and internally locked: the platform adopts new limits from wherever
/// the user changed them while a Driver validates readings on the actor that
/// guards the device edge (AD-4). `@unchecked` because the safety argument is the
/// lock rather than the type of the storage — every access to `limits` below is
/// inside `lock`.
public final class SafetyLimitsValidator: @unchecked Sendable {

    private let lock = NSLock()
    private var limits: SafetyLimits

    /// Starts the validator at `limits`.
    ///
    /// PLATFORM ONLY. A Driver that could construct one of these could construct
    /// it around ``SafetyLimits/absolute`` and validate against the widest legal
    /// bound forever, which is the whole failure this type exists to prevent.
    @_spi(DriverPlatform)
    public init(limits: SafetyLimits) {
        self.limits = limits
    }

    /// Puts `limits` in force from the next validation onward.
    ///
    /// PLATFORM ONLY, and the reason this type is a reference type: every Driver
    /// holding this validator sees the change without being re-injected, told, or
    /// rebuilt. There is no invalidation step, so there is no invalidation step to
    /// forget.
    ///
    /// Not called `apply`/`set`/`update` on purpose — those read as commands in a
    /// contract whose entire posture is that it issues none, and
    /// `DriverAPITests`' command-verb scan fails on them.
    @_spi(DriverPlatform)
    public func adopt(_ limits: SafetyLimits) {
        lock.withLock { self.limits = limits }
    }

    /// The limits in force at this instant.
    ///
    /// For display and diagnostics. It is a VALUE, so what a caller holds is a
    /// snapshot of a past instant and not a second handle on the live limits —
    /// and it cannot validate anything, because ``SafetyLimits/validate(mgdl:)``
    /// is internal to this module.
    public var limitsInForce: SafetyLimits {
        lock.withLock { limits }
    }

    /// Validates one mg/dL value against the limits in force RIGHT NOW.
    ///
    /// The limits are read inside this call. There is no cached copy, no
    /// snapshot taken at construction, and no way for a caller to supply its own
    /// answer to "what are the limits" — that is the difference between this and
    /// the protocol it replaced.
    ///
    /// - Returns: a ``SafetyCore/Glucose``, so a value that passes cannot
    ///   subsequently be treated as out of range.
    /// - Throws: ``DriverFailure/valueRejected(bound:)`` naming the bound that
    ///   refused it. Per AD-22 the caller CONSUMES the record and advances its
    ///   cursor: the value parsed cleanly, it is simply not admissible, and
    ///   retrying it forever would wedge history behind a number that will never
    ///   become valid.
    public func validate(mgdl: Double) throws(DriverFailure) -> Glucose {
        let inForce = lock.withLock { limits }
        return try inForce.validate(mgdl: mgdl)
    }
}
