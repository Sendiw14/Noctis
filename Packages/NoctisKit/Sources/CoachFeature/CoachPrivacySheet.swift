import DesignSystem
import SwiftUI

/// "How Coach uses your data": plain words, not values. Which kinds of facts
/// a question can see, where answers are written, what is stored and how to
/// delete it, and that Coach isn't medical advice.
struct CoachPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The kinds of facts (never their values) a question can see.
    static let sees = [
        "Your recovery score today and what it's built from: sleep, HRV, resting heart rate and bedtime consistency.",
        "Last night's sleep: how long, how well, and the share of deep and REM sleep.",
        "Your usual bedtime and wake time, and the bedtime that fits your sleep need.",
        "This week's average night, your sleep balance and how much your bedtime varies.",
        "The insights NOCTIS has already found, as numbers.",
    ]

    static let neverSees = "It never sees your name, your Apple Account, individual Health readings or when they were taken, or which app or device recorded them."

    static let written = "Answers are written on your iPhone by Apple Intelligence when it's available. Otherwise NOCTIS builds them from your data with no model at all. Nothing you ask and nothing about your health is sent to a server."

    static let stored = "Your questions and Coach's answers are kept on this iPhone only. They aren't synced, aren't in backups and are protected while your iPhone is locked. Delete one conversation, or all of them, from History."

    static let notAdvice = "Coach shares patterns from your data. It isn't medical advice, and it can't diagnose anything. If something about your sleep or health worries you, a doctor is the right person to ask."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
                    section("WHAT A QUESTION CAN SEE") {
                        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                            ForEach(Self.sees, id: \.self) { line in
                                HStack(alignment: .firstTextBaseline, spacing: NoctisSpacing.sm) {
                                    Circle().fill(NoctisSection.coach.ink).frame(width: 6, height: 6).accessibilityHidden(true)
                                    paragraph(line)
                                }
                            }
                            paragraph(Self.neverSees).padding(.top, NoctisSpacing.xxs)
                        }
                    }
                    section("WHERE ANSWERS ARE WRITTEN") { paragraph(Self.written) }
                    section("WHAT IS KEPT") { paragraph(Self.stored) }
                    section("NOT MEDICAL ADVICE") { paragraph(Self.notAdvice) }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.top, NoctisSpacing.md)
                .padding(.bottom, NoctisSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
            .background { PaperBackground(adaptive: true).ignoresSafeArea() }
            .navigationTitle("How Coach uses your data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("coach.privacy.done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("coach.privacy")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            NoctisCaption(title, style: .noctisInk3)
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .noctisFont(17, relativeTo: .body)
            .foregroundStyle(NoctisAppColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
