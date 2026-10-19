import DesignSystem
import NoctisCore
import SwiftUI

/// Shown only after signing in with Apple (APP_RULES.md R69): the given name Apple handed over, in a field the person can change or clear. It is the
/// profile's own name field, used on Home's greeting and Profile, and it stays on this iPhone. Anyone can skip it, and a person who did not sign in
/// never sees it.
struct NameScreen: View {
    @Binding var name: String
    let onNext: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        OnboardingScaffold(
            step: nil,
            title: "What should we",
            emphasis: "call you?"
        ) {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                Text("Optional. It is used on Home and in Profile, and you can change it any time.")
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisPaper.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .noctisTextBlock()
                TextField("Your name", text: $name)
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisPaper.ink)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(onNext)
                    .padding(.horizontal, NoctisSpacing.lg)
                    .frame(minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).fill(NoctisPaper.surface))
                    .overlay(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous).stroke(NoctisPaper.hairline, lineWidth: 1))
                    .accessibilityIdentifier("onboarding.name")
            }
        } bottomStack: {
            VStack(spacing: NoctisSpacing.sm) {
                NoctisCTA("Continue", action: onNext)
                NoctisTextButton("Skip for now") {
                    name = ""
                    onNext()
                }
            }
        }
    }
}
