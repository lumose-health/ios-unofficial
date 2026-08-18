import Foundation

/// How far back the store keeps data (FR-139).
///
/// A validated type rather than an `Int` of days, for the same reason
/// ``SafetyCore/FreshnessThresholds`` is one: a window is settable by the user, a
/// settings screen is where an out-of-range number arrives, and a store that
/// clamped a bad value would quietly delete data the user asked it to keep — or
/// keep data they asked it to drop. It throws instead, and the caller decides what
/// the settings screen shows (AD-5).
///
/// The bounds and the default mirror Android's `AppSettingsStore`
/// (`MIN_RETENTION_DAYS` 1, `MAX_RETENTION_DAYS` 30, `DEFAULT_RETENTION_DAYS` 7),
/// which clamps where this throws.
public struct RetentionWindow: Hashable, Sendable {

    /// The shortest settable window, in days.
    public static let minimumDays = 1

    /// The longest settable window, in days.
    public static let maximumDays = 30

    /// The window in force until the user changes it, in days.
    public static let defaultDays = 7

    /// The window in force until the user changes it.
    public static let `default` = RetentionWindow(validated: defaultDays)

    /// The window, in whole days.
    public let days: Int

    /// The window as an elapsed time, for subtracting from a clock's `now`.
    public var duration: TimeInterval {
        TimeInterval(days) * Self.secondsPerDay
    }

    /// - Throws: ``PersistenceFailure/retentionOutOfRange(days:)`` outside
    ///   ``minimumDays``...``maximumDays``.
    public init(days: Int) throws(PersistenceFailure) {
        guard (Self.minimumDays...Self.maximumDays).contains(days) else {
            throw .retentionOutOfRange(days: days)
        }
        self.days = days
    }

    /// The one non-throwing way in, for the default alone — a literal this file
    /// owns and the bounds above already admit.
    private init(validated days: Int) {
        self.days = days
    }

    /// Seconds in a day, as a fixed span rather than a calendar one.
    ///
    /// Retention is "older than N days of elapsed time", not "before the calendar
    /// day N days ago": a calendar answer depends on a time zone and on daylight
    /// saving, so the same sweep would delete a different set of rows depending on
    /// where the phone was. A fixed span is the same everywhere and testable
    /// against an injected clock.
    private static let secondsPerDay: TimeInterval = 86_400
}
