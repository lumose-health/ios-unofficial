import Testing
@testable import AppFeature
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private struct TestAuthorizations: OnboardingAuthorizations {
    func requestNotificationAuthorization(options: NotificationAuthorizationOptions) async -> NotificationAuthorizationOutcome { .granted }
    func requestBluetoothAuthorization() async -> BluetoothAuthorizationOutcome { .allowed }
}

private actor RecordingAuthorizations: OnboardingAuthorizations {
    let notification: NotificationAuthorizationOutcome
    let bluetooth: BluetoothAuthorizationOutcome
    private(set) var calls: [String] = []
    private(set) var seenOptions: [NotificationAuthorizationOptions] = []
    init(notification: NotificationAuthorizationOutcome, bluetooth: BluetoothAuthorizationOutcome) { self.notification = notification; self.bluetooth = bluetooth }
    func requestNotificationAuthorization(options: NotificationAuthorizationOptions) async -> NotificationAuthorizationOutcome { calls.append("notification"); seenOptions.append(options); return notification }
    func requestBluetoothAuthorization() async -> BluetoothAuthorizationOutcome { calls.append("bluetooth"); return bluetooth }
    func recorded() -> ([String], [NotificationAuthorizationOptions]) { (calls, seenOptions) }
}

private actor GatedAuthorizations: OnboardingAuthorizations {
    private var notificationContinuation: CheckedContinuation<NotificationAuthorizationOutcome, Never>?
    private var bluetoothContinuation: CheckedContinuation<BluetoothAuthorizationOutcome, Never>?
    private(set) var calls: [String] = []
    func requestNotificationAuthorization(options: NotificationAuthorizationOptions) async -> NotificationAuthorizationOutcome {
        calls.append("notification")
        return await withCheckedContinuation { notificationContinuation = $0 }
    }
    func requestBluetoothAuthorization() async -> BluetoothAuthorizationOutcome {
        calls.append("bluetooth")
        return await withCheckedContinuation { bluetoothContinuation = $0 }
    }
    func notificationIsPending() -> Bool { notificationContinuation != nil }
    func bluetoothIsPending() -> Bool { bluetoothContinuation != nil }
    func releaseNotification() { notificationContinuation?.resume(returning: .granted); notificationContinuation = nil }
    func releaseBluetooth() { bluetoothContinuation?.resume(returning: .allowed); bluetoothContinuation = nil }
    func recordedCalls() -> [String] { calls }
}

private actor BackendStub: OnboardingBackend {
    var connection: ConnectionTestOutcome
    var signInOutcome: SignInOutcome
    private(set) var connectionCalls = 0
    private(set) var signInCalls = 0
    init(connection: ConnectionTestOutcome = .failed(reason: "offline"), signIn: SignInOutcome = .failed(message: "denied")) { self.connection = connection; self.signInOutcome = signIn }
    func testConnection(to url: String) async -> ConnectionTestOutcome { connectionCalls += 1; return connection }
    func signIn(url: String, email: String, password: String) async -> SignInOutcome { signInCalls += 1; return signInOutcome }
    func counts() -> (Int, Int) { (connectionCalls, signInCalls) }
}

private actor GatedBackend: OnboardingBackend {
    private var continuation: CheckedContinuation<ConnectionTestOutcome, Never>?
    func testConnection(to url: String) async -> ConnectionTestOutcome {
        await withCheckedContinuation { continuation = $0 }
    }
    func signIn(url: String, email: String, password: String) async -> SignInOutcome { .signedIn }
    func isPending() -> Bool { continuation != nil }
    func release() { continuation?.resume(returning: .connected); continuation = nil }
}

private actor GatedSignInBackend: OnboardingBackend {
    private var continuation: CheckedContinuation<SignInOutcome, Never>?
    func testConnection(to url: String) async -> ConnectionTestOutcome { .connected }
    func signIn(url: String, email: String, password: String) async -> SignInOutcome {
        await withCheckedContinuation { continuation = $0 }
    }
    func isPending() -> Bool { continuation != nil }
    func release(_ outcome: SignInOutcome) { continuation?.resume(returning: outcome); continuation = nil }
}

/// Counts writes of the onboarding completion flag.
private final class CountingDefaults: UserDefaults, @unchecked Sendable {
    private(set) var completionWrites = 0
    override func set(_ value: Bool, forKey defaultName: String) {
        if defaultName == OnboardingCompletion.key { completionWrites += 1 }
        super.set(value, forKey: defaultName)
    }
}

@Suite("Onboarding") struct OnboardingTests {
    @MainActor private func advanceToBackend(_ model: OnboardingModel) { model.next(); model.next(); model.acknowledgeSafety() }
    private func makeDefaults() -> (UserDefaults, String) { let name = "OnboardingTests-\(UUID())"; return (UserDefaults(suiteName: name)!, name) }

    @Test func stagesAndStartRule() {
        #expect(OnboardingStage.allCases.map(\.rawValue) == [0, 1, 2, 3, 4])
        #expect(OnboardingStage.allCases.count == 5)
        #expect(OnboardingStage.start(hasSavedBackendURL: false, onboardingPreviouslyComplete: false) == .welcome)
        #expect(OnboardingStage.start(hasSavedBackendURL: false, onboardingPreviouslyComplete: true) == .welcome)
        #expect(OnboardingStage.start(hasSavedBackendURL: true, onboardingPreviouslyComplete: false) == .welcome)
        #expect(OnboardingStage.start(hasSavedBackendURL: true, onboardingPreviouslyComplete: true) == .backend)
    }
    @MainActor @Test func controlsAndNavigationSafety() async {
        #expect(OnboardingControls.make(stage: .welcome, connectionSucceeded: false).leading == .skip)
        #expect(OnboardingControls.make(stage: .features, connectionSucceeded: true).trailing == .next(enabled: true))
        #expect(OnboardingControls.make(stage: .safety, connectionSucceeded: false).trailing == .understand)
        #expect(OnboardingControls.make(stage: .backend, connectionSucceeded: false).trailing == .next(enabled: false))
        #expect(OnboardingControls.make(stage: .backend, connectionSucceeded: true).trailing == .next(enabled: true))
        #expect(OnboardingControls.make(stage: .signIn, connectionSucceeded: true).trailing == nil)
        let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
        let model = OnboardingModel(backend: UnavailableOnboardingBackend(), authorizations: TestAuthorizations(), defaults: defaults)
        model.next(); #expect(model.stage == .features)
        model.next(); #expect(model.stage == .safety)
        model.next(); model.skip(); model.swipe(.forward); #expect(model.stage == .safety)
        #expect(!model.safetyAcknowledged)
        model.acknowledgeSafety(); #expect(model.stage == .backend && model.safetyAcknowledged)
        model.back(); #expect(model.stage == .safety)
        model.acknowledgeSafety(); model.updateServerURL("https://server")
        let task = model.testConnection()!; await task.value
        model.next(); #expect(model.stage == .backend)
        model.skip(); model.swipe(.forward); #expect(model.stage == .backend && model.safetyAcknowledged)
        model.back(); model.back(); #expect(model.stage == .safety)
    }
    @MainActor @Test func blankURLAndUnavailableFailure() async {
        let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = BackendStub()
        let model = OnboardingModel(backend: backend, authorizations: TestAuthorizations(), defaults: defaults)
        for value in ["", "  \n"] {
            model.updateServerURL(value); #expect(model.testConnection() == nil)
            #expect(model.connectionResult?.text == OnboardingCopy.blankURL)
        }
        #expect(await backend.counts().0 == 0)
        model.updateServerURL("https://server")
        let task = model.testConnection()!; await task.value
        #expect(model.connectionResult?.text == "Connection failed: offline")
        #expect(!model.connectionSucceeded)
        model.updateServerURL("https://other"); #expect(model.connectionResult == nil && !model.connectionSucceeded)
        let unavailable = OnboardingModel(backend: UnavailableOnboardingBackend(), authorizations: TestAuthorizations(), defaults: defaults, startStage: .backend, safetyAcknowledged: true)
        unavailable.updateServerURL("https://server"); let unavailableTask = unavailable.testConnection()!; await unavailableTask.value
        #expect(unavailable.connectionResult?.text == "Connection failed: this build can't connect to a server yet")
    }
    @MainActor @Test func everyAuthorizationOutcomeFinishesAndRequestsOnceInOrder() async {
        let notificationOutcomes: [NotificationAuthorizationOutcome] = [.granted, .denied, .failed]
        let bluetoothOutcomes: [BluetoothAuthorizationOutcome] = [.allowed, .denied, .restricted, .unsupported]
        for notification in notificationOutcomes {
            for bluetooth in bluetoothOutcomes {
                let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
                let authorizations = RecordingAuthorizations(notification: notification, bluetooth: bluetooth)
                let model = OnboardingModel(backend: UnavailableOnboardingBackend(), authorizations: authorizations, defaults: defaults)
                advanceToBackend(model)
                let task = model.continueWithoutServer()!
                await task.value
                #expect(model.isFinished && OnboardingCompletion.isComplete(in: defaults))
                #expect(model.authorizationResult == OnboardingAuthorizationResult(notification: notification, bluetooth: bluetooth))
                let recorded = await authorizations.recorded()
                #expect(recorded.0 == ["notification", "bluetooth"])
                #expect(recorded.1 == [.onboarding])
                let requested = recorded.1.first
                #expect(requested == [.alert, .sound, .badge, .criticalAlert])
                #expect(requested?.contains(.provisional) == false)
            }
        }
    }
    @MainActor @Test func bothCompletionPathsWaitForSequentialAuthorizationBeforePersisting() async {
        for useServerlessPath in [true, false] {
            let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
            let auth = GatedAuthorizations()
            let backend = BackendStub(signIn: .signedIn)
            let model = OnboardingModel(backend: backend, authorizations: auth, defaults: defaults, startStage: .backend, safetyAcknowledged: true)
            let task: Task<Void, Never>
            if useServerlessPath {
                task = model.continueWithoutServer()!
            } else {
                model.updateEmail("user@example.com"); model.updatePassword("secret")
                task = model.signIn()!
            }
            while !(await auth.notificationIsPending()) { await Task.yield() }
            #expect(!model.isFinished && !OnboardingCompletion.isComplete(in: defaults))
            #expect(await auth.recordedCalls() == ["notification"])
            if useServerlessPath { #expect(model.continueWithoutServer() == nil) }
            await auth.releaseNotification()
            while !(await auth.bluetoothIsPending()) { await Task.yield() }
            #expect(!model.isFinished && !OnboardingCompletion.isComplete(in: defaults))
            #expect(await auth.recordedCalls() == ["notification", "bluetooth"])
            await auth.releaseBluetooth()
            await task.value
            #expect(model.isFinished && OnboardingCompletion.isComplete(in: defaults))
        }
    }
    @MainActor @Test func successAndEscapeHatchComplete() async {
        let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = BackendStub(connection: .connected)
        let model = OnboardingModel(backend: backend, authorizations: TestAuthorizations(), defaults: defaults, startStage: .backend, safetyAcknowledged: true)
        model.updateServerURL("https://server"); let task = model.testConnection()!; await task.value
        #expect(model.connectionResult?.text == "Connected successfully")
        model.next(); #expect(model.stage == .signIn)
        let escape = OnboardingModel(backend: backend, authorizations: TestAuthorizations(), defaults: defaults)
        advanceToBackend(escape)
        escape.updateServerURL("https://server"); let failed = escape.testConnection()!; await failed.value
        let escapeTask = escape.continueWithoutServer()!; await escapeTask.value
        #expect(escape.isFinished && escape.serverURL.isEmpty && escape.connectionResult == nil)
        #expect(OnboardingCompletion.isComplete(in: defaults))
        escape.continueWithoutServer(); #expect(escape.isFinished)
    }
    @MainActor @Test func lateSignInAfterServerlessCompletionDoesNotCompleteTwice() async {
        let name = "OnboardingTests-\(UUID())"
        let defaults = CountingDefaults(suiteName: name)!; defer { defaults.removePersistentDomain(forName: name) }
        let backend = GatedSignInBackend()
        let auth = RecordingAuthorizations(notification: .granted, bluetooth: .allowed)
        let model = OnboardingModel(backend: backend, authorizations: auth, defaults: defaults, startStage: .signIn, safetyAcknowledged: true)
        model.updateEmail("user@example.com"); model.updatePassword("secret")
        let signIn = model.signIn()!
        while !(await backend.isPending()) { await Task.yield() }
        model.back(); #expect(model.stage == .backend)
        let completion = model.continueWithoutServer()!
        await completion.value
        #expect(model.isFinished && defaults.completionWrites == 1)
        await backend.release(.signedIn)
        await signIn.value
        #expect(await auth.recorded().0 == ["notification", "bluetooth"])
        #expect(defaults.completionWrites == 1)
        #expect(model.isFinished && !model.isSigningIn && model.loginError == nil && model.password.isEmpty)
    }
    @MainActor @Test func cancellationPreventsLateConnectionResult() async {
        let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = GatedBackend()
        let auth = GatedAuthorizations()
        let model = OnboardingModel(backend: backend, authorizations: auth, defaults: defaults)
        advanceToBackend(model)
        model.updateServerURL("https://server")
        let task = model.testConnection()!
        while !(await backend.isPending()) { await Task.yield() }
        let completion = model.continueWithoutServer()!
        while !(await auth.notificationIsPending()) { await Task.yield() }
        await backend.release()
        await task.value
        #expect(!model.isFinished && !OnboardingCompletion.isComplete(in: defaults))
        await auth.releaseNotification()
        while !(await auth.bluetoothIsPending()) { await Task.yield() }
        #expect(!model.isFinished && model.connectionResult == nil && !model.connectionSucceeded)
        await auth.releaseBluetooth()
        await completion.value
        #expect(model.isFinished && model.serverURL.isEmpty)
        #expect(model.connectionResult == nil && !model.connectionSucceeded)
    }
    @MainActor @Test func signInValidationFailureAndSuccess() async {
        let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = BackendStub(signIn: .failed(message: "bad credentials"))
        let auth = RecordingAuthorizations(notification: .granted, bluetooth: .allowed)
        let model = OnboardingModel(backend: backend, authorizations: auth, defaults: defaults, startStage: .backend, safetyAcknowledged: true)
        #expect(model.signIn() == nil && model.loginError == OnboardingCopy.blankCredentials)
        model.updateEmail("a@example.com"); model.updatePassword("secret")
        let failed = model.signIn()!; await failed.value
        #expect(model.loginError == "bad credentials" && model.password.isEmpty)
        #expect(await auth.recorded().0.isEmpty)
        let success = BackendStub(signIn: .signedIn)
        let second = OnboardingModel(backend: success, authorizations: TestAuthorizations(), defaults: defaults, startStage: .backend, safetyAcknowledged: true)
        second.updateEmail("a@example.com"); second.updatePassword("secret")
        let done = second.signIn()!; await done.value
        #expect(second.isFinished && second.password.isEmpty && OnboardingCompletion.isComplete(in: defaults))
    }
    @MainActor @Test func escapeAndSignInDoNothingBeforeSafetyAcknowledged() async {
        let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = BackendStub(signIn: .signedIn)
        let auth = RecordingAuthorizations(notification: .granted, bluetooth: .allowed)
        let model = OnboardingModel(backend: backend, authorizations: auth, defaults: defaults)
        model.updateEmail("a@example.com"); model.updatePassword("secret")
        for _ in OnboardingStage.allCases.prefix(3) {
            #expect(model.continueWithoutServer() == nil)
            #expect(model.signIn() == nil)
            #expect(!model.isFinished && !model.isSigningIn && model.loginError == nil)
            model.next()
        }
        #expect(model.stage == .safety && !model.safetyAcknowledged)
        #expect(!OnboardingCompletion.isComplete(in: defaults))
        #expect(await backend.counts().1 == 0)
        #expect(await auth.recorded().0.isEmpty)
        model.acknowledgeSafety(); let completion = model.continueWithoutServer()!; await completion.value
        #expect(model.isFinished && OnboardingCompletion.isComplete(in: defaults))
        let resumed = OnboardingModel(backend: backend, authorizations: TestAuthorizations(), defaults: defaults, startStage: .backend, safetyAcknowledged: true)
        #expect(resumed.safetyAcknowledged && resumed.stage == .backend)
        #expect(!OnboardingModel(backend: backend, authorizations: TestAuthorizations(), defaults: defaults, startStage: .safety).safetyAcknowledged)
    }
    @MainActor @Test func laterStartWithoutAcknowledgementLandsOnSafety() async {
        let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = BackendStub(connection: .connected, signIn: .signedIn)
        for start in [OnboardingStage.backend, .signIn] {
            let model = OnboardingModel(backend: backend, authorizations: TestAuthorizations(), defaults: defaults, startStage: start)
            #expect(model.stage == .safety && !model.safetyAcknowledged)
            model.updateEmail("a@example.com"); model.updatePassword("secret")
            #expect(model.continueWithoutServer() == nil)
            #expect(model.signIn() == nil)
            #expect(!model.isFinished && !model.isSigningIn)
        }
        #expect(!OnboardingCompletion.isComplete(in: defaults))
        #expect(await backend.counts().1 == 0)
    }
    @Test func monitoringLimitsCopyIsPinned() {
        #expect(OnboardingCopy.monitoringLimitsTitle == "What stops monitoring")
        #expect(OnboardingCopy.monitoringLimits == ["Force-quitting GlycemicGPT from the app switcher stops monitoring, including reconnecting to your pump, until you open the app again.", "Restarting your phone stops monitoring until you unlock it once.", "Low Power Mode cuts some of the background time GlycemicGPT uses to stay up to date."])
        #expect(OnboardingIdentifier.monitoringLimits == "onboarding_monitoring_limits")
    }
    @Test func previewNoticeIsShownWhileNoRealDriverOrBackend() {
        #expect(OnboardingPreview.showsNotice)
        #expect(OnboardingIdentifier.previewNotice == "onboarding_preview_notice")
        #expect(OnboardingCopy.welcomePreviewNotice == "This preview shows demo data only. Pump connection and server features are coming to iOS.")
        #expect(OnboardingCopy.backendPreviewNotice.contains("can't connect to a pump or a server"))
    }
    @MainActor @Test func staleConnectionResultIsDroppedAfterURLEdit() async {
        let (defaults, name) = makeDefaults(); defer { defaults.removePersistentDomain(forName: name) }
        let backend = GatedBackend()
        let model = OnboardingModel(backend: backend, authorizations: TestAuthorizations(), defaults: defaults, startStage: .backend, safetyAcknowledged: true)
        model.updateServerURL("https://first")
        let task = model.testConnection()!
        while !(await backend.isPending()) { await Task.yield() }
        model.updateServerURL("https://second")
        await backend.release()
        await task.value
        #expect(!model.isTestingConnection)
        #expect(model.connectionResult == nil && !model.connectionSucceeded)
        model.next(); #expect(model.stage == .backend)
    }
    @Test func pageIndicatorsAndFeatureHonesty() {
        #expect(OnboardingPageIndicator.label(index: 0, current: 0, count: 5) == "Page 1 of 5, current")
        #expect(OnboardingPageIndicator.label(index: 1, current: 0, count: 5) == "Page 2 of 5")
        #expect((0..<5).map(OnboardingPageIndicator.identifier) == (0..<5).map { "page_indicator_\($0)" })
        #expect(OnboardingCopy.features.filter(\.comingToIOS).count == 4)
        #expect(OnboardingCopy.features.allSatisfy { !$0.body.contains(OnboardingCopy.comingToIOS) })
        #expect(OnboardingCopy.comingToIOS == "Coming to iOS" && OnboardingIdentifier.comingToIOS == "onboarding_coming_to_ios")
        #expect(OnboardingCopy.safetyCards.count == 5)
    }
    @Test func pinnedVisibleCopyAndIdentifiers() {
        #expect(OnboardingCopy.welcomeTitle == "GlycemicGPT")
        #expect(OnboardingCopy.welcomeSubtitle == "Your diabetes management companion")
        #expect(OnboardingCopy.welcomeBody == "A direct pump monitor on its own — your on-call endo when you connect a server.")
        #expect(OnboardingCopy.featuresTitle == "What You Get")
        #expect(OnboardingCopy.safetyTitle == "Important Safety Information")
        #expect(OnboardingCopy.noTherapeuticWrites == "GlycemicGPT only reads from your pump. It never delivers a bolus, never changes your basal, and never changes a pump setting.")
        #expect(OnboardingCopy.backendTitle == "Connect a Server (Optional)")
        #expect(OnboardingCopy.backendBody == "A server adds AI, meal analysis, and caregiver features. You can skip it and use the app as a direct pump monitor.")
        #expect(OnboardingCopy.serverURLLabel == "Server URL" && OnboardingCopy.serverURLPlaceholder == "https://your-server.com")
        #expect(OnboardingCopy.testConnection == "Test Connection" && OnboardingCopy.testing == "Testing...")
        #expect(OnboardingCopy.blankURL == "Enter a server URL first" && OnboardingCopy.connected == "Connected successfully")
        #expect(OnboardingCopy.failurePrefix + OnboardingCopy.unavailableConnectionReason == "Connection failed: this build can't connect to a server yet")
        #expect(OnboardingCopy.escapePrompt == "Don't run a server?" && OnboardingCopy.continueWithoutServer == "Use without a server")
        #expect(OnboardingCopy.signInTitle == "Sign In")
        #expect(OnboardingCopy.signInBody == "Sign in to your GlycemicGPT server account to enable AI, meal, and caregiver features.")
        #expect(OnboardingCopy.emailLabel == "Email" && OnboardingCopy.passwordLabel == "Password")
        #expect(OnboardingCopy.signIn == "Sign In" && OnboardingCopy.signingIn == "Signing in...")
        #expect(OnboardingCopy.blankCredentials == "Email and password are required")
        #expect(OnboardingCopy.unavailableSignIn == "Sign-in isn't available in this build yet.")
        #expect(OnboardingCopy.skip == "Skip" && OnboardingCopy.back == "Back" && OnboardingCopy.next == "Next" && OnboardingCopy.understand == "I Understand")
        #expect(OnboardingIdentifier.skip == "skip_button" && OnboardingIdentifier.back == "back_button" && OnboardingIdentifier.next == "next_button")
        #expect(OnboardingIdentifier.serverURL == "onboarding_server_url" && OnboardingIdentifier.testConnection == "onboarding_test_connection")
        #expect(OnboardingIdentifier.connectionResult == "onboarding_connection_result" && OnboardingIdentifier.continueWithoutServer == "onboarding_continue_without_server")
        #expect(OnboardingIdentifier.email == "onboarding_email" && OnboardingIdentifier.password == "onboarding_password")
        #expect(OnboardingIdentifier.loginError == "onboarding_login_error" && OnboardingIdentifier.signIn == "onboarding_sign_in")
        #expect(OnboardingIdentifier.noTherapeuticWrites == "onboarding_no_therapeutic_writes")
        #expect(OnboardingCopy.features.map(\.title) == ["Direct Pump Connection", "AI-Powered Analysis", "Smart Alerts", "Self-Hosted Privacy"])
        #expect(OnboardingCopy.safetyCards.map(\.title) == ["Experimental Software", "AI Limitations", "Photo Carb Estimates Are Guesses", "Not FDA Approved", "Consult Your Healthcare Provider"])
    }
    @Test func unavailableBackendAndSymbolNames() async {
        let backend = UnavailableOnboardingBackend()
        #expect(await backend.testConnection(to: "https://server") == .failed(reason: OnboardingCopy.unavailableConnectionReason))
        #expect(await backend.signIn(url: "", email: "", password: "") == .failed(message: OnboardingCopy.unavailableSignIn))
        #expect(OnboardingIdentifier.noTherapeuticWrites == "onboarding_no_therapeutic_writes")
    }
}

#if canImport(UIKit)
extension OnboardingTests { @Test func everyOnboardingSymbolExists() { for symbol in OnboardingSymbol.all { #expect(UIImage(systemName: symbol) != nil, "Missing SF Symbol: \(symbol)") } } }
#elseif canImport(AppKit)
extension OnboardingTests { @Test func everyOnboardingSymbolExists() { for symbol in OnboardingSymbol.all { #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing SF Symbol: \(symbol)") } } }
#endif
