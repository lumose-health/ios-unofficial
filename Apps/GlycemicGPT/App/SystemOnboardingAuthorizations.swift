import AppFeature
import CoreBluetooth
import UserNotifications

struct SystemOnboardingAuthorizations: OnboardingAuthorizations {
    func requestNotificationAuthorization(options: NotificationAuthorizationOptions) async -> NotificationAuthorizationOutcome {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: Self.map(options))
            return granted ? .granted : .denied
        } catch { return .failed }
    }
    func requestBluetoothAuthorization() async -> BluetoothAuthorizationOutcome { await BluetoothAuthorizationProbe.request() }
    private static func map(_ options: NotificationAuthorizationOptions) -> UNAuthorizationOptions {
        var result: UNAuthorizationOptions = []
        if options.contains(.alert) { result.insert(.alert) }
        if options.contains(.sound) { result.insert(.sound) }
        if options.contains(.badge) { result.insert(.badge) }
        if options.contains(.criticalAlert) { result.insert(.criticalAlert) }
        if options.contains(.provisional) { result.insert(.provisional) }
        return result
    }
}

/// Asks for Bluetooth permission by creating a short-lived central manager and waiting for
/// its first settled state.
///
/// There is deliberately no timeout. The system dialog moves at the user's pace, and any
/// deadline would race someone who is still reading it. Waiting indefinitely is safe because
/// the probe keeps itself alive (`retainedSelf`) for as long as the request is pending:
/// `CBCentralManager` holds its delegate weakly, so without that self-reference nothing would
/// own the probe while `request()` is suspended, and an optimized build could free the probe,
/// its manager and the continuation, leaving the caller suspended forever.
@MainActor
private final class BluetoothAuthorizationProbe: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var continuation: CheckedContinuation<BluetoothAuthorizationOutcome, Never>?
    /// Strong self-reference held from `start` until the continuation resumes. Cleared in
    /// `finish`, which breaks the cycle and lets the probe deallocate.
    private var retainedSelf: BluetoothAuthorizationProbe?

    static func request() async -> BluetoothAuthorizationOutcome {
        if CBManager.authorization != .notDetermined { return map(CBManager.authorization, state: nil) }
        return await withCheckedContinuation { continuation in
            BluetoothAuthorizationProbe().start(continuation)
        }
    }

    private func start(_ continuation: CheckedContinuation<BluetoothAuthorizationOutcome, Never>) {
        self.continuation = continuation
        retainedSelf = self
        manager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        let authorization = CBManager.authorization
        // A nil queue delivers delegate callbacks on the main queue.
        MainActor.assumeIsolated { handle(state: state, authorization: authorization) }
    }

    private func handle(state: CBManagerState, authorization: CBManagerAuthorization) {
        // `.unknown` and `.resetting` are transient while the user has not answered yet;
        // wait for a settled state instead of reporting a premature result.
        if authorization == .notDetermined, state == .unknown || state == .resetting { return }
        finish(Self.map(authorization, state: state))
    }

    private func finish(_ outcome: BluetoothAuthorizationOutcome) {
        // Taking the continuation out first guarantees it resumes exactly once.
        guard let continuation else { return }
        self.continuation = nil
        manager?.delegate = nil
        manager = nil
        retainedSelf = nil
        continuation.resume(returning: outcome)
    }

    private static func map(_ authorization: CBManagerAuthorization, state: CBManagerState?) -> BluetoothAuthorizationOutcome {
        if state == .unsupported { return .unsupported }
        switch authorization {
        case .allowedAlways: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .unsupported
        @unknown default: return .unsupported
        }
    }
}
