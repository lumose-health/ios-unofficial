import Foundation
import os
import DriverAPI

public enum RefreshStep: String, Equatable, Sendable {
    case pumpStatus
    case glucose
}

public protocol HomeLogging: Sendable {
    func refreshReadFailed(step: RefreshStep, failure: DriverFailure)
}

public struct OSHomeLog: HomeLogging {
    private let logger = Logger(subsystem: "com.glycemicgpt.ios", category: "AppFeature")
    public init() {}
    public func refreshReadFailed(step: RefreshStep, failure: DriverFailure) {
        logger.warning("Refresh read failed: \(step.rawValue, privacy: .public) (\(failure.caseName, privacy: .public))")
    }
}

extension DriverFailure {
    public var caseName: String {
        switch self {
        case .notPaired: "notPaired"
        case .authenticationRejected: "authenticationRejected"
        case .transportUnavailable: "transportUnavailable"
        case .connectionLost: "connectionLost"
        case .timedOut: "timedOut"
        case .decodeFailed: "decodeFailed"
        case .valueRejected: "valueRejected"
        case .capabilityUnavailable: "capabilityUnavailable"
        case .deviceFault: "deviceFault"
        case .illegalTransition: "illegalTransition"
        case .safetyLimitRejected: "safetyLimitRejected"
        case .pairingRejected: "pairingRejected"
        case .cancelled: "cancelled"
        }
    }
}
