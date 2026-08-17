import Foundation

// ============================================================================
// GUARD EXEMPTION — the ONLY file under Sources/SafetyCore that may read the
// system time. scripts/guards/safety_guards.sh exempts this exact path and
// nothing else, and asserts that it contains exactly one wall-clock read.
//
// Do not add logic here. This file is an adapter, not a home for time-dependent
// behaviour: anything that *derives* something from "now" belongs in a type that
// takes a `Clock` (see Clock.swift), so it can be tested at its boundaries.
// ============================================================================

/// The production ``Clock``: the device's wall clock.
///
/// Inject this at the composition root and nowhere else. Tests inject a fixed or
/// scripted clock instead, which is the entire point of the protocol.
///
/// The device clock is not monotonic — the user can change it, and NTP can step
/// it — so it must not be used to measure elapsed time between two reads. It
/// answers "what time is it now", which is what freshness and day-boundary
/// alignment need.
public struct SystemClock: Clock {

    public init() {}

    public var now: Date { Date() }
}
