import Foundation
import Observation

public enum OnboardingStage: Int, CaseIterable, Sendable {
    case welcome = 0, features = 1, safety = 2, backend = 3, signIn = 4

    public static func start(hasSavedBackendURL: Bool, onboardingPreviouslyComplete: Bool) -> Self {
        hasSavedBackendURL && onboardingPreviouslyComplete ? .backend : .welcome
    }
}

public enum OnboardingSwipe: Sendable { case forward, backward }

public struct OnboardingControls: Sendable, Equatable {
    public enum Leading: Sendable, Equatable { case skip, back }
    public enum Trailing: Sendable, Equatable { case next(enabled: Bool), understand }
    public let leading: Leading?
    public let trailing: Trailing?
    public static func make(stage: OnboardingStage, connectionSucceeded: Bool) -> Self {
        switch stage {
        case .welcome, .features: .init(leading: .skip, trailing: .next(enabled: true))
        case .safety: .init(leading: nil, trailing: .understand)
        case .backend: .init(leading: .back, trailing: .next(enabled: connectionSucceeded))
        case .signIn: .init(leading: .back, trailing: nil)
        }
    }
}

public enum OnboardingPageIndicator {
    public static func label(index: Int, current: Int, count: Int) -> String {
        "Page \(index + 1) of \(count)" + (index == current ? ", current" : "")
    }
    public static func identifier(index: Int) -> String { "page_indicator_\(index)" }
}

public struct OnboardingFeature: Sendable, Equatable {
    public let title: String
    public let body: String
    public let symbol: String
    public let comingToIOS: Bool
}

public struct OnboardingSafetyCard: Sendable, Equatable {
    public let title: String
    public let body: String
    public let symbol: String
}

public enum OnboardingCopy {
    public static let welcomeTitle = "GlycemicGPT"
    public static let welcomeSubtitle = "Your diabetes management companion"
    public static let welcomeBody = "A direct pump monitor on its own — your on-call endo when you connect a server."
    public static let welcomePreviewNotice = "This preview shows demo data only. Pump connection and server features are coming to iOS."
    public static let featuresTitle = "What You Get"
    public static let safetyTitle = "Important Safety Information"
    public static let noTherapeuticWrites = "GlycemicGPT only reads from your pump. It never delivers a bolus, never changes your basal, and never changes a pump setting."
    public static let backendTitle = "Connect a Server (Optional)"
    public static let backendBody = "A server adds AI, meal analysis, and caregiver features. You can skip it and use the app as a direct pump monitor."
    public static let backendPreviewNotice = "This preview can't connect to a pump or a server yet. Direct pump monitoring is coming to iOS."
    public static let serverURLLabel = "Server URL"
    public static let serverURLPlaceholder = "https://your-server.com"
    public static let testConnection = "Test Connection"
    public static let testing = "Testing..."
    public static let blankURL = "Enter a server URL first"
    public static let connected = "Connected successfully"
    public static let failurePrefix = "Connection failed: "
    public static let unavailableConnectionReason = "this build can't connect to a server yet"
    public static let escapePrompt = "Don't run a server?"
    public static let continueWithoutServer = "Use without a server"
    public static let signInTitle = "Sign In"
    public static let signInBody = "Sign in to your GlycemicGPT server account to enable AI, meal, and caregiver features."
    public static let emailLabel = "Email"
    public static let passwordLabel = "Password"
    public static let signIn = "Sign In"
    public static let signingIn = "Signing in..."
    public static let blankCredentials = "Email and password are required"
    public static let unavailableSignIn = "Sign-in isn't available in this build yet."
    public static let skip = "Skip"
    public static let back = "Back"
    public static let next = "Next"
    public static let understand = "I Understand"
    public static let comingToIOS = "Coming to iOS"
    public static let features: [OnboardingFeature] = [
        .init(title: "Direct Pump Connection", body: "Connect directly to your Tandem pump via BLE for real-time basal, bolus, IoB, reservoir, and battery data.", symbol: "antenna.radiowaves.left.and.right", comingToIOS: true),
        .init(title: "AI-Powered Analysis", body: "With a connected server, get photo meal analysis, an AI chat, and AI insights delivered as notifications — powered by your choice of AI provider.", symbol: "brain", comingToIOS: true),
        .init(title: "Smart Alerts", body: "Configurable glucose alerts, with Telegram delivery and caregiver escalation when you connect a server.", symbol: "bell", comingToIOS: true),
        .init(title: "Self-Hosted Privacy", body: "Run your own server and your data stays on your infrastructure — no cloud dependency, full control.", symbol: "lock", comingToIOS: true)
    ]
    public static let safetyCards: [OnboardingSafetyCard] = [
        .init(title: "Experimental Software", body: "This is alpha software under active development. It is functional but has not been broadly tested. Use at your own risk.", symbol: "flask"),
        .init(title: "AI Limitations", body: "AI can hallucinate, misinterpret data, and provide outdated or incorrect information. Never rely solely on AI suggestions.", symbol: "brain"),
        .init(title: "Photo Carb Estimates Are Guesses", body: "If you use the meal-photo feature, the carb numbers are AI estimates from an image and are frequently wrong, including misidentifying the food entirely. Never use a photo carb estimate to calculate an insulin dose or bolus. Always verify carbs yourself before dosing.", symbol: "camera"),
        .init(title: "Not FDA Approved", body: "This software is not approved by the FDA or any regulatory body for medical use. It is not a medical device.", symbol: "shield"),
        .init(title: "Consult Your Healthcare Provider", body: "Always consult with your endocrinologist before making changes to your diabetes management. Verify all AI suggestions with your care team.", symbol: "cross.case")
    ]
}

public enum OnboardingIdentifier {
    public static let skip = "skip_button", back = "back_button", next = "next_button"
    public static let serverURL = "onboarding_server_url", testConnection = "onboarding_test_connection"
    public static let connectionResult = "onboarding_connection_result", continueWithoutServer = "onboarding_continue_without_server"
    public static let email = "onboarding_email", password = "onboarding_password", loginError = "onboarding_login_error", signIn = "onboarding_sign_in"
    public static let noTherapeuticWrites = "onboarding_no_therapeutic_writes"
    public static let comingToIOS = "onboarding_coming_to_ios"
    public static let previewNotice = "onboarding_preview_notice"
}

/// Whether onboarding shows the preview notice next to copy that describes pump
/// monitoring and server features. It stays on while the app has no real pump
/// driver or server backend; switch it off once both are available.
public enum OnboardingPreview {
    public static let showsNotice = true
}

public enum OnboardingSymbol {
    public static let all = ["heart.fill", "antenna.radiowaves.left.and.right", "brain", "bell", "lock", "exclamationmark.triangle.fill", "flask", "camera", "shield", "cross.case", "lock.shield"]
}

public enum ConnectionTestOutcome: Sendable, Equatable { case connected, failed(reason: String) }
public enum SignInOutcome: Sendable, Equatable { case signedIn, failed(message: String) }
public protocol OnboardingBackend: Sendable {
    func testConnection(to url: String) async -> ConnectionTestOutcome
    func signIn(url: String, email: String, password: String) async -> SignInOutcome
}
public struct UnavailableOnboardingBackend: OnboardingBackend {
    public init() {}
    public func testConnection(to url: String) async -> ConnectionTestOutcome { .failed(reason: OnboardingCopy.unavailableConnectionReason) }
    public func signIn(url: String, email: String, password: String) async -> SignInOutcome { .failed(message: OnboardingCopy.unavailableSignIn) }
}
public struct ConnectionResultLine: Sendable, Equatable { public let text: String; public let isSuccess: Bool }

@MainActor @Observable
public final class OnboardingModel {
    public private(set) var stage: OnboardingStage
    public private(set) var safetyAcknowledged = false
    public private(set) var serverURL = ""
    public private(set) var isTestingConnection = false
    public private(set) var connectionResult: ConnectionResultLine?
    public private(set) var connectionSucceeded = false
    public private(set) var email = ""
    public private(set) var password = ""
    public private(set) var isSigningIn = false
    public private(set) var loginError: String?
    public private(set) var isFinished = false
    @ObservationIgnored private let backend: any OnboardingBackend
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    /// A start stage after `.safety` is honored only when the caller passes an explicit
    /// prior acknowledgement; without one, onboarding starts at `.safety`.
    public init(backend: any OnboardingBackend, defaults: UserDefaults, startStage: OnboardingStage = .welcome, safetyAcknowledged: Bool = false) {
        self.backend = backend; self.defaults = defaults
        self.safetyAcknowledged = safetyAcknowledged
        self.stage = startStage.rawValue > OnboardingStage.safety.rawValue && !safetyAcknowledged ? .safety : startStage
    }
    private var pastSafetyGate: Bool { stage.rawValue >= OnboardingStage.backend.rawValue && safetyAcknowledged }
    public func next() {
        switch stage { case .welcome: stage = .features; case .features: stage = .safety; case .backend where connectionSucceeded: stage = .signIn; default: break }
    }
    public func back() { if stage.rawValue >= OnboardingStage.backend.rawValue, let previous = OnboardingStage(rawValue: stage.rawValue - 1) { stage = previous } }
    public func skip() { if stage == .welcome || stage == .features { stage = .safety } }
    public func swipe(_ direction: OnboardingSwipe) {
        guard stage.rawValue < OnboardingStage.safety.rawValue else { return }
        switch direction { case .forward: next(); case .backward where stage == .features: stage = .welcome; default: break }
    }
    public func acknowledgeSafety() { guard stage == .safety else { return }; safetyAcknowledged = true; stage = .backend }
    public func updateServerURL(_ value: String) { serverURL = value; connectionResult = nil; connectionSucceeded = false }
    public func updateEmail(_ value: String) { email = value; loginError = nil }
    public func updatePassword(_ value: String) { password = value; loginError = nil }
    @discardableResult public func testConnection() -> Task<Void, Never>? {
        guard !isTestingConnection else { return nil }
        guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { connectionResult = .init(text: OnboardingCopy.blankURL, isSuccess: false); return nil }
        isTestingConnection = true; connectionResult = nil
        let url = serverURL
        let task = Task { [weak self, backend] in
            let outcome = await backend.testConnection(to: url)
            guard let self else { return }
            self.isTestingConnection = false
            // Drop a result for a URL the user has since edited.
            guard !Task.isCancelled, self.serverURL == url else { return }
            switch outcome {
            case .connected: self.connectionSucceeded = true; self.connectionResult = .init(text: OnboardingCopy.connected, isSuccess: true)
            case .failed(let reason): self.connectionSucceeded = false; self.connectionResult = .init(text: OnboardingCopy.failurePrefix + reason, isSuccess: false)
            }
        }
        connectionTask = task
        return task
    }
    public func continueWithoutServer() {
        guard pastSafetyGate, !isFinished else { return }
        connectionTask?.cancel(); connectionTask = nil
        serverURL = ""; connectionResult = nil; connectionSucceeded = false; isTestingConnection = false
        complete()
    }
    @discardableResult public func signIn() -> Task<Void, Never>? {
        guard pastSafetyGate, !isSigningIn else { return nil }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { loginError = OnboardingCopy.blankCredentials; password = ""; return nil }
        isSigningIn = true; loginError = nil
        let url = serverURL, email = email, password = password
        let task = Task { [weak self, backend] in
            let outcome = await backend.signIn(url: url, email: email, password: password)
            guard let self else { return }
            self.password = ""; self.isSigningIn = false
            switch outcome { case .signedIn: self.complete(); case .failed(let message): self.loginError = message }
        }
        return task
    }
    private func complete() { OnboardingCompletion.record(true, in: defaults); isFinished = true }
}
