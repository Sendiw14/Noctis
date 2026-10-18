import DesignSystem
import SwiftUI

/// The one text field, pinned under the content: at most 200 characters, a
/// 44pt Send that is off while nothing is typed or an answer is on its way,
/// and Return sends. It sits on the paper with a hairline, over whatever
/// scrolls beneath (R10: the bottom stack).
struct CoachInputBar: View {
    let viewModel: CoachViewModel
    let placeholder: String
    let identifier: String
    let send: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The counter appears when the limit is near.
    private static let counterFrom = 160

    var body: some View {
        VStack(alignment: .trailing, spacing: NoctisSpacing.xxs) {
            if viewModel.draft.count >= Self.counterFrom {
                Text("\(viewModel.draft.count) of \(CoachViewModel.maxLength)")
                    .noctisFont(12, .medium, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
                    .padding(.trailing, NoctisSpacing.xs)
                    .accessibilityLabel("\(viewModel.draft.count) of \(CoachViewModel.maxLength) characters")
                    .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: NoctisSpacing.sm) {
                // The placeholder in the quiet ink, not the system's placeholder grey (measured 1.7:1 on the white field in Light and 2.5:1 in Dark;
                // the quiet ink is 4.5:1 or better on the surface in both, NoctisAppContrastTests).
                TextField(
                    text: Binding(get: { viewModel.draft }, set: { viewModel.setDraft($0) }),
                    prompt: Text(placeholder).foregroundStyle(.noctisInk3),
                    axis: .vertical
                ) {
                    Text(placeholder)
                }
                .lineLimit(1...4)
                .noctisFont(17, relativeTo: .body)
                .foregroundStyle(NoctisAppColor.ink)
                .tint(NoctisSection.coach.ink)
                .submitLabel(.send)
                .focused($focused)
                .onSubmit { if viewModel.canSend { send() } }
                // The field is the whole bar, not only its text: 48 pt to tap, and a tap anywhere in it types (QA_LEDGER.md: the field's frame
                // was the 21 pt of its text, inside the padding).
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, NoctisSpacing.md)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(NoctisAppColor.surface)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
                )
                .accessibilityIdentifier("\(identifier).field")

                Button {
                    guard viewModel.canSend else { return }
                    send()
                } label: {
                    Circle()
                        .fill(viewModel.canSend ? NoctisAppColor.ctaFill : NoctisAppColor.track)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(viewModel.canSend ? NoctisAppColor.ctaLabel : NoctisAppColor.ink3)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send")
                .accessibilityHint(viewModel.isSending ? "Coach is still answering." : "Asks Coach your question.")
                .accessibilityIdentifier("\(identifier).send")
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: viewModel.draft.count >= Self.counterFrom)
        .padding(.horizontal, NoctisSpacing.lg)
        .padding(.top, NoctisSpacing.sm)
        .padding(.bottom, NoctisSpacing.sm)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(NoctisAppColor.bg)
        .overlay(alignment: .top) { Rectangle().fill(NoctisAppColor.hairline).frame(height: 1) }
    }
}
