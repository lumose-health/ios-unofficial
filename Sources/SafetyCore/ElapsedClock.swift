import Foundation

/// Time passed since an arbitrary origin, for measuring wall-clock changes against.
/// Current time still comes from ``Clock`` (AD-14).
public protocol ElapsedClock: Sendable {
    var elapsed: TimeInterval { get }
}

/// Sleep-surviving elapsed time for detecting wall-clock changes.
public struct SystemElapsedClock: ElapsedClock {
    private let origin = ContinuousClock().now

    public init() {}

    public var elapsed: TimeInterval {
        let parts = origin.duration(to: ContinuousClock().now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
