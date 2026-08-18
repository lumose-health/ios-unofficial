import Foundation

/// The app's single source of "now" (AD-14).
///
/// ## The contract
///
/// **No surface reads the wall clock directly.** Freshness and staleness tiers,
/// chart windows, day-boundary alignment, and any decay or age computation all
/// take their current time from an injected `Clock` — including code paths that
/// look too small to matter (FR-61). `scripts/guards/safety_guards.sh` enforces
/// this mechanically: `Date()`, `Date.now` and `Date.init` are rejected anywhere
/// under `Sources/` except ``SystemClock``, the one adapter that is
/// allowed to touch the system time.
///
/// ## Why
///
/// Time-dependent behaviour that reads the wall clock cannot be tested at its
/// boundaries — a "data is stale after N minutes" tier can only be verified by
/// sleeping, and a day-boundary bug only reproduces near midnight. Worse, two
/// surfaces that each call the system clock separately can disagree about the
/// same instant, so a reading is "3 minutes old" on the phone and "4 minutes old"
/// on the watch. One injected clock removes both problems: tests drive it, and
/// everything derived from a single `now` stays internally consistent.
///
/// ## Designing against it
///
/// Give any time-dependent API an explicit clock parameter (or hold one as a
/// stored property) rather than reaching for the system time inside. See
/// ``GlucoseReading/age(asOf:)`` for the shape.
///
/// ## Naming
///
/// The standard library also declares a `Clock` protocol, for measuring
/// durations and suspending tasks — a different concern from wall-clock reads.
/// A module's own declaration shadows the standard library's, so in a file that
/// imports SafetyCore an unqualified `Clock` means *this* one. Code that wants
/// the standard library's — `ContinuousClock`, `SuspendingClock`, anything
/// measuring elapsed time — must spell it `Swift.Clock`.
public protocol Clock: Sendable {

    /// The current instant, as this clock reports it.
    ///
    /// Callers that need several times to agree should read `now` once and pass
    /// the value down, rather than reading it repeatedly.
    var now: Date { get }
}
