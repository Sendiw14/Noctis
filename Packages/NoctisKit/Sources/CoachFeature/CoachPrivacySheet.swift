import DesignSystem
import NoctisCore
import SwiftUI

/// "How Coach uses your data": plain words, not values. Which kinds of facts
/// a question can see, where answers are written, what is stored and how to
/// delete it, and that Coach isn't medical advice.
struct CoachPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let title = "How Coach uses your data"

    /// The kinds of facts (never their values) a question can see: from the data inventory (APP_RULES.md R41).
    static var sees: [String] { PrivacyStatements.coachSees(.shared) }

    static var neverSees: String { PrivacyStatements.coachNeverSees(.shared) }

    /// Nil, and the section hidden, if the inventory ever says a remote model can write an answer.
    static var written: String? { PrivacyStatements.coachWritten(.shared) }

    static var stored: String { PrivacyStatements.coachStored(.shared) }

    static let notAdvice =
        "Coach shares patterns from your data. It isn't medical advice, and it can't diagnose anything. If something about your sleep or health worries you, a doctor is the right person to ask."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.lg) {
                    // An inline navigation title is one line and was cut at accessibility sizes ("How Coach uses your d…" on an SE at AX3):
                    // there the title is the page's own heading, which wraps.
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(Self.title)
                            .noctisFont(28, .bold, relativeTo: .title)
                            .foregroundStyle(NoctisAppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
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
                    if let written = Self.written { section("WHERE ANSWERS ARE WRITTEN") { paragraph(written) } }
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
            .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "" : Self.title)
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
