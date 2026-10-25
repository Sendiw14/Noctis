import DesignSystem
import NoctisCore
import SwiftUI

/// Shown only after signing in with Apple (APP_RULES.md R69): the given name Apple handed over, in a field the person can change or clear. It is the
/// profile's own name field, used on Home's greeting and Profile, and it stays on this iPhone. Anyone can skip it, and a person who did not sign in
/// never sees it.
struct NameScreen: View {
    @Binding var name: String
    let onNext: () -> Void
    let onBack: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        OnboardingStepScaffold(section: .home, step: nil, title: ["What should we", "call you?"], subtitle: nil, onBack: onBack) {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                Text("Optional. It is used on Home and in Profile, and you can change it any time.")
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Your name", text: $name)
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(onNext)
                    .padding(.horizontal, NoctisSpacing.lg)
                    .frame(minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).fill(NoctisAppColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).stroke(NoctisAppColor.hairline, lineWidth: 1))
                    .accessibilityIdentifier("onboarding.name")
            }
        } actions: {
            VStack(spacing: 4) {
                OnboardingPrimaryButton("Continue", identifier: "name.continue", action: onNext)
                OnboardingSecondaryButton("Skip for now", identifier: "name.skip") {
                    name = ""
                    onNext()
                }
            }
        }
    }
}
