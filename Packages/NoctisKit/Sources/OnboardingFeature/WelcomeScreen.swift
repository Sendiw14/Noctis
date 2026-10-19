import AuthenticationServices
import DesignSystem
import NoctisCore
import NoctisText
import SwiftUI

/// Step 0, Welcome (APP_RULES.md R6, R69): four colour bands, one word each, and two ways in. Sign in with Apple is optional and local: the second
/// button goes to the very same place as the first one does, so nothing is behind either of them.
struct WelcomeScreen: View {
    /// "Continue without an account": the next onboarding step.
    let onContinue: () -> Void
    /// Signed in with Apple: the name step, with this given name offered (nil leaves the field as it is).
    let onSignedIn: (String?) -> Void
    /// The profile's name today: a name already there is never replaced.
    let existingName: String

    @Environment(AccountStore.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var message: String?
    @State private var reveal = WelcomeReveal()
    @State private var controlsHeight: CGFloat = 0
    @State private var started = false

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isDark: Bool { colorScheme == .dark }
    /// Ivory below the bands in Light, cocoa in Dark; the text on it flips.
    private var ground: Color { isDark ? NoctisPaper.ink : NoctisPaper.bg }
    private var foreground: Color { isDark ? NoctisPaper.ivory : NoctisPaper.cocoa }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let width = geometry.size.width
            let total = geometry.size.height + safeTop + safeBottom
            let scale = min(width / 402, total / 874)
            let bandsHeight = isAccessibilitySize ? max(total * 0.56, 340) : max(total - controlsHeight, 240)

            let content = VStack(spacing: 0) {
                WelcomeBands(size: CGSize(width: width, height: bandsHeight), safeTop: safeTop, scale: isAccessibilitySize ? min(scale, 0.6) : scale, reveal: reveal)
                controls(safeBottom: safeBottom)
                    .opacity(reveal.controls ? 1 : 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
            }
            .frame(width: width)

            Group {
                if isAccessibilitySize {
                    ScrollView { content }.scrollBounceBehavior(.basedOnSize)
                } else {
                    content
                }
            }
            .frame(width: width, height: total, alignment: .top)
        }
        .background(ground.ignoresSafeArea())
        .ignoresSafeArea()
        .onAppear { start() }
    }

    // MARK: Controls

    private func controls(safeBottom: CGFloat) -> some View {
        VStack(spacing: 10) {
            Text(PrivacyStatements.welcomeSubtitle(.shared))
                .noctisFont(14, relativeTo: .footnote)
                .foregroundStyle(foreground.opacity(isDark ? 0.72 : 0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

            SignInWithAppleButton(.continue) { request in
                NoctisHaptics.softImpact()
                message = nil
                // The name only: never the email (R69).
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                finish(result)
            }
            .signInWithAppleButtonStyle(isDark ? .white : .black)
            .frame(height: 56)
            .clipShape(Capsule())
            .accessibilityLabel("Continue with Apple")
            .accessibilityIdentifier("welcome.apple")

            if let message {
                Text(message)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(isDark ? NoctisPaper.butter : NoctisPaper.orangeText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("welcome.error")
            }

            Button {
                NoctisHaptics.softImpact()
                onContinue()
            } label: {
                Text("Continue without an account")
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(Capsule().stroke(foreground.opacity(isDark ? 0.35 : 0.25), lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue without an account")
            .accessibilityIdentifier("welcome.continue")

            footer.padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, max(safeBottom, 12) + 8)
    }

    private var footer: some View {
        Text(footerText)
            .noctisFont(11, relativeTo: .caption2)
            .foregroundStyle(foreground.opacity(isDark ? 0.68 : 0.72))
            .tint(foreground)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footerText: AttributedString {
        var text = AttributedString("By continuing you agree to Apple's ")
        var terms = AttributedString("Terms of Use")
        terms.link = StoreLegalLinks.appleStandardTerms
        terms.underlineStyle = .single
        var privacy = AttributedString("Privacy Policy")
        privacy.link = StoreLegalLinks.privacy
        privacy.underlineStyle = .single
        text += terms
        text += AttributedString(" and the ")
        text += privacy
        text += AttributedString(". \(NoctisMedicalNotice.statement)")
        return text
    }

    // MARK: Motion

    /// The bands slide down into place, top first, 0.1 s apart; each word follows 0.15 s after its band lands; the icons draw in; the subtitle and
    /// buttons come last, with one soft haptic as the last band lands. Reduce Motion: the end, at once, with no haptic.
    private func start() {
        guard !started else { return }
        started = true
        guard !reduceMotion else { reveal = .final; return }
        let landing = 0.55
        for index in 0..<4 {
            let delay = Double(index) * 0.1
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) { reveal.band[index] = true }
            withAnimation(.easeOut(duration: 0.25).delay(delay + landing * 0.6 + 0.15)) { reveal.word[index] = true }
            withAnimation(.easeOut(duration: 0.6).delay(delay + landing * 0.6 + 0.15)) { reveal.icon[index] = true }
        }
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(1.6)) { reveal.twinkle = true }
        withAnimation(.easeOut(duration: 0.3).delay(0.3 + landing + 0.25)) { reveal.controls = true }
        Task {
            try? await Task.sleep(for: .seconds(0.3 + landing))
            NoctisHaptics.softImpact()
        }
    }

    // MARK: Signing in

    private func finish(_ result: Result<ASAuthorization, any Error>) {
        let credential: Result<AppleSignInCredential, any Error> = result.flatMap { authorization in
            AppleSignInCredential(authorization).map { .success($0) } ?? .failure(ASAuthorizationError(.invalidResponse))
        }
        switch account.complete(credential, existingName: existingName) {
        case .signedIn(let prefill): onSignedIn(prefill)
        case .cancelled: break
        case .failed: message = "Couldn't sign in. You can continue without an account."
        }
    }
}
