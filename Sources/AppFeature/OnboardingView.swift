import SwiftUI

public struct OnboardingFlowView: View {
    @Bindable private var model: OnboardingModel
    private let onFinished: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    public init(model: OnboardingModel, onFinished: @escaping () -> Void) { self.model = model; self.onFinished = onFinished }
    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch model.stage {
                    case .welcome: welcome.modifier(OnboardingSwipeModifier(model: model))
                    case .features: features.modifier(OnboardingSwipeModifier(model: model))
                    case .safety: safety
                    case .backend: backend
                    case .signIn: signIn
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            controls.padding(16)
        }
        .onChange(of: model.isFinished) { _, finished in if finished { onFinished() } }
        .accessibilityElement(children: .contain)
    }
    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill").font(.system(size: 96)).foregroundStyle(StatusColor.primary.swiftUIColor(colorScheme)).accessibilityHidden(true)
            Text(OnboardingCopy.welcomeTitle).font(.largeTitle.bold()).foregroundStyle(.primary)
            Text(OnboardingCopy.welcomeSubtitle).font(.title3)
            Text(OnboardingCopy.welcomeBody).font(.body).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.featuresTitle).font(.title2.bold())
            ForEach(Array(OnboardingCopy.features.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol).font(.system(size: 32)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        Text(item.body).font(.subheadline).foregroundStyle(.primary)
                        if item.comingToIOS {
                            Text(OnboardingCopy.comingToIOS).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                                .padding(.horizontal, 8).padding(.vertical, 2).background(.fill.secondary, in: Capsule())
                                .accessibilityIdentifier(OnboardingIdentifier.comingToIOS)
                        }
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .combine)
            }
        }
    }
    private var safety: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(StatusColor.error.swiftUIColor(colorScheme)); Text(OnboardingCopy.safetyTitle).font(.title2.bold()) }
            ForEach(Array(OnboardingCopy.safetyCards.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol).font(.system(size: 24)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.subheadline.weight(.semibold)); Text(item.body).font(.subheadline).foregroundStyle(.primary) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .combine)
            }
            Text(OnboardingCopy.noTherapeuticWrites).font(.subheadline).foregroundStyle(.primary).accessibilityIdentifier(OnboardingIdentifier.noTherapeuticWrites)
        }
    }
    private var backend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: "lock.shield").accessibilityHidden(true); Text(OnboardingCopy.backendTitle).font(.title2.bold()) }
            Text(OnboardingCopy.backendBody)
            TextField(OnboardingCopy.serverURLPlaceholder, text: Binding(get: { model.serverURL }, set: { model.updateServerURL($0) })).textFieldStyle(.roundedBorder).autocorrectionDisabled().accessibilityLabel(OnboardingCopy.serverURLLabel).accessibilityIdentifier(OnboardingIdentifier.serverURL)
                #if os(iOS)
                .keyboardType(.URL).textInputAutocapitalization(.never).textContentType(.URL)
                #endif
            Button { _ = model.testConnection() } label: {
                HStack { if model.isTestingConnection { ProgressView() }; Text(model.isTestingConnection ? OnboardingCopy.testing : OnboardingCopy.testConnection) }.frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).disabled(model.isTestingConnection || model.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier(OnboardingIdentifier.testConnection)
            if let result = model.connectionResult {
                Text(result.text).font(.subheadline).foregroundStyle(result.isSuccess ? StatusColor.primary.swiftUIColor(colorScheme) : StatusColor.error.swiftUIColor(colorScheme)).accessibilityIdentifier(OnboardingIdentifier.connectionResult)
            }
            Text(OnboardingCopy.escapePrompt).font(.subheadline).foregroundStyle(.primary).frame(maxWidth: .infinity)
            Button(OnboardingCopy.continueWithoutServer) { model.continueWithoutServer() }.buttonStyle(.borderless).frame(maxWidth: .infinity).accessibilityIdentifier(OnboardingIdentifier.continueWithoutServer)
        }
    }
    private var signIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnboardingCopy.signInTitle).font(.title2.bold()); Text(OnboardingCopy.signInBody)
            TextField(OnboardingCopy.emailLabel, text: Binding(get: { model.email }, set: { model.updateEmail($0) })).textFieldStyle(.roundedBorder).autocorrectionDisabled().accessibilityIdentifier(OnboardingIdentifier.email)
                #if os(iOS)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).textContentType(.username)
                #endif
            SecureField(OnboardingCopy.passwordLabel, text: Binding(get: { model.password }, set: { model.updatePassword($0) })).textFieldStyle(.roundedBorder).accessibilityIdentifier(OnboardingIdentifier.password)
                #if os(iOS)
                .textContentType(.password)
                #endif
            if let error = model.loginError { Text(error).font(.subheadline).foregroundStyle(StatusColor.error.swiftUIColor(colorScheme)).accessibilityIdentifier(OnboardingIdentifier.loginError) }
            Button(model.isSigningIn ? OnboardingCopy.signingIn : OnboardingCopy.signIn) { _ = model.signIn() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(model.isSigningIn || model.email.isEmpty || model.password.isEmpty).accessibilityIdentifier(OnboardingIdentifier.signIn)
        }
    }
    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(OnboardingStage.allCases, id: \.rawValue) { stage in
                    Circle().fill(stage == model.stage ? StatusColor.primary.swiftUIColor(colorScheme) : Color.gray).frame(width: stage == model.stage ? 10 : 8, height: stage == model.stage ? 10 : 8)
                        .accessibilityLabel(OnboardingPageIndicator.label(index: stage.rawValue, current: model.stage.rawValue, count: OnboardingStage.allCases.count))
                        .accessibilityIdentifier(OnboardingPageIndicator.identifier(index: stage.rawValue))
                }
            }
            let controls = OnboardingControls.make(stage: model.stage, connectionSucceeded: model.connectionSucceeded)
            HStack {
                if let leading = controls.leading {
                    Button(leading == .skip ? OnboardingCopy.skip : OnboardingCopy.back) {
                        withAnimation { if leading == .skip { model.skip() } else { model.back() } }
                    }.buttonStyle(.borderless).accessibilityIdentifier(leading == .skip ? OnboardingIdentifier.skip : OnboardingIdentifier.back)
                } else { Spacer() }
                Spacer()
                if let trailing = controls.trailing {
                    switch trailing {
                    case .next(let enabled): Button(OnboardingCopy.next) { withAnimation { model.next() } }.buttonStyle(.borderedProminent).disabled(!enabled).accessibilityIdentifier(OnboardingIdentifier.next)
                    case .understand: Button(OnboardingCopy.understand) { withAnimation { model.acknowledgeSafety() } }.buttonStyle(.borderedProminent).accessibilityIdentifier(OnboardingIdentifier.next)
                    }
                }
            }
        }
    }
}

/// Horizontal swipe between the Welcome and Features pages. Simultaneous, so the
/// enclosing ScrollView keeps its vertical scrolling.
private struct OnboardingSwipeModifier: ViewModifier {
    let model: OnboardingModel
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture().onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -80 { withAnimation { model.swipe(.forward) } }
                else if value.translation.width > 80 { withAnimation { model.swipe(.backward) } }
            })
    }
}
