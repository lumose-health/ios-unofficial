import Foundation
import Testing

@testable import SafetyCore

/// A clock the test controls completely.
///
/// This is the payoff of AD-14: age at an exact boundary is asserted directly,
/// with no sleeping and no tolerance window. `Clock` is written with its module
/// prefix throughout this file only for readability — the standard library also
/// declares a `Clock`, and although SafetyCore's shadows it, spelling out which
/// one is meant costs nothing here.
struct FixedClock: SafetyCore.Clock {
    var now: Date
}

/// A clock that advances by a fixed step on every read, to prove that code which
/// needs several times to agree reads `now` once rather than repeatedly.
final class TickingClock: SafetyCore.Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private let step: TimeInterval

    init(start: Date, step: TimeInterval) {
        self.current = start
        self.step = step
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        let value = current
        current = current.addingTimeInterval(step)
        return value
    }
}

@Suite("Clock injection")
struct ClockTests {

    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A fixed clock drives age exactly, with no wall-clock read")
    func ageFromFixedClock() throws {
        let reading = GlucoseReading(
            glucose: try Glucose(mgdl: 120),
            timestamp: reference
        )
        let clock = FixedClock(now: reference.addingTimeInterval(300))
        #expect(reading.age(asOf: clock) == 300)
    }

    @Test("Age is zero when the clock reads the measurement instant")
    func ageAtMeasurementInstant() throws {
        let reading = GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference)
        #expect(reading.age(asOf: FixedClock(now: reference)) == 0)
    }

    /// Clock skew between the pump and the phone routinely produces future-dated
    /// readings. The value type reports the signed age rather than clamping to
    /// zero — deciding what a negative age *means* is freshness policy, and
    /// swallowing the sign here would hide a clock that has jumped.
    @Test("A future-dated reading has a negative age, not a clamped zero")
    func negativeAge() throws {
        let reading = GlucoseReading(
            glucose: try Glucose(mgdl: 120),
            timestamp: reference.addingTimeInterval(90)
        )
        #expect(reading.age(asOf: FixedClock(now: reference)) == -90)
    }

    /// Rewinding the injected clock re-runs the same computation at a different
    /// instant — the property that makes day-boundary and staleness-tier logic
    /// testable at all, instead of only reproducing near midnight.
    @Test("The same reading yields any age the injected clock dictates", arguments: [
        0.0, 1.0, 299.0, 300.0, 301.0, 86_400.0,
    ])
    func ageTracksTheInjectedClock(offset: TimeInterval) throws {
        let reading = GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference)
        let clock = FixedClock(now: reference.addingTimeInterval(offset))
        #expect(reading.age(asOf: clock) == offset)
    }

    /// Two ages taken from one `now` agree; two ages taken from two reads of an
    /// advancing clock do not. This is the concrete failure the "read `now` once
    /// and pass it down" guidance on ``SafetyCore/Clock/now`` prevents.
    @Test("Reading now twice can disagree — read it once and pass it down")
    func repeatedReadsDisagree() throws {
        let reading = GlucoseReading(glucose: try Glucose(mgdl: 120), timestamp: reference)
        let clock = TickingClock(start: reference, step: 60)

        #expect(reading.age(asOf: clock) != reading.age(asOf: clock))

        let ticking = TickingClock(start: reference, step: 60)
        let onceNow = ticking.now
        let fixed = FixedClock(now: onceNow)
        #expect(reading.age(asOf: fixed) == reading.age(asOf: fixed))
    }

    /// `SystemClock` is the one adapter allowed to read the device clock. It is
    /// asserted loosely on purpose: the point is that it returns the wall clock,
    /// not that the test can predict it.
    @Test("SystemClock reports the wall clock")
    func systemClockReportsWallClock() {
        let before = Date.distantPast
        let clock = SystemClock()
        let sample = clock.now
        #expect(sample > before)
        #expect(abs(sample.timeIntervalSinceNow) < 5)
    }
}
