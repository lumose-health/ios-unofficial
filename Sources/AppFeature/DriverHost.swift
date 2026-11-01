import Foundation
import Observation
import SafetyCore
@_spi(DriverPlatform) import DriverAPI

public enum DriverHostError: Error, Sendable {
    case activation(DriverFailure)
    case lifecycle(DriverFailure)
    case glucosePortUnavailable
    case insulinPortUnavailable

    public var recoverer: String { "Restart the app to try connecting again." }
}

public struct ActiveDriverPorts: Sendable {
    public let identifier: DriverIdentifier
    public let glucoseSource: any GlucoseSource
    public let insulinSource: any InsulinSource
}

@MainActor @Observable
public final class HomeModel {
    public let isDemo: Bool
    public private(set) var lifecycleState = DriverLifecycleState.notActivated
    public private(set) var ports: ActiveDriverPorts?
    public private(set) var hostError: DriverHostError?

    private var lifecycle = DriverLifecycle()
    private let driver: any Driver

    public init(driver: any Driver, demoIdentifiers: Set<DriverIdentifier>) {
        self.driver = driver
        self.isDemo = DemoDataLabel.isVisible(
            activeGlucoseDriver: driver.descriptor.identifier,
            demoIdentifiers: demoIdentifiers
        )
    }

    public var footerMessage: String? {
        HomeScaffoldModel.footer(isConnected: HomeScaffoldModel.isConnected(lifecycleState), hasGlucose: false)
    }

    public func activateIfNeeded() async {
        guard lifecycleState == .notActivated, hostError == nil else { return }
        do {
            try lifecycle.advance(to: .activating)
            lifecycleState = lifecycle.state
        } catch {
            hostError = .lifecycle(error)
            return
        }

        do {
            try await driver.activate()
        } catch {
            await fail(.activation(error))
            return
        }
        do {
            try lifecycle.advance(to: .active)
            lifecycleState = lifecycle.state
        } catch {
            await fail(.lifecycle(error))
            return
        }

        guard case .glucoseSource(let glucose)? = await driver.capability(.glucoseSource) else {
            await fail(.glucosePortUnavailable)
            return
        }
        guard case .insulinSource(let insulin)? = await driver.capability(.insulinSource) else {
            await fail(.insulinPortUnavailable)
            return
        }
        ports = ActiveDriverPorts(identifier: driver.descriptor.identifier, glucoseSource: glucose, insulinSource: insulin)
    }

    private func fail(_ error: DriverHostError) async {
        await driver.deactivate()
        do {
            try lifecycle.advance(to: .failed)
            lifecycleState = lifecycle.state
        } catch {
            // Keep the original activation or capability failure for recovery.
        }
        hostError = error
    }
}

public enum AppComposition {
    public static func makeSafetyValidator() -> SafetyLimitsValidator {
        do {
            let limits = try SafetyLimits(
                glucoseLower: SafetyConstants.glucoseValidRange.lowerBound,
                glucoseUpper: SafetyConstants.glucoseValidRange.upperBound
            )
            return SafetyLimitsValidator(limits: limits)
        } catch {
            preconditionFailure("Canonical glucose limits must be valid: \(error)")
        }
    }
}
