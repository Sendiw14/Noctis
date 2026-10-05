import CoachKit
import DesignSystem
import NoctisCore
import SwiftUI

/// A conversation, pushed over the hub: each question as a small chip on the
/// right and its answer under it as a structured card, never a bubble. The
/// input stays pinned under the answers. It reads only `CoachViewModel`
/// (APP_RULES.md R20).
struct CoachConversationScreen: View {
    let viewModel: CoachViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.xl) {
                    ForEach(viewModel.turns) { turn in
                        CoachTurnView(turn: turn, isLatest: turn.id == viewModel.turns.last?.id, viewModel: viewModel)
                            .id(turn.id)
                    }
                    // Today's free questions are used up (R60): one card, after the answers.
                    if viewModel.isLimited, !viewModel.isSending, let card = LockedCopy.card(for: .coachQuestions) {
                        LockedCard(systemImage: "sparkles", title: card.title, line: card.line, identifier: "coach.conversation.locked") {
                            appModel.presentPaywall(.coachQuestions)
                        }
                    }
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.top, NoctisSpacing.xs)
                .padding(.bottom, NoctisSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.turns.count) { _, _ in
                guard let last = viewModel.turns.last else { return }
                withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(last.id, anchor: .top)
                }
            }
        }
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: NoctisSpacing.sm) {
                if !viewModel.followUpQuestions.isEmpty {
                    CoachFollowUpChips(questions: viewModel.followUpQuestions) { viewModel.followUp($0) }
                        .transition(.opacity)
                }
                CoachInputBar(
                    viewModel: viewModel, placeholder: viewModel.isLimited ? CoachQuota.usedUpTitle : "Ask a follow-up", identifier: "coach.conversation"
                ) { viewModel.followUp() }
            }
            .background(NoctisAppColor.bg)
            .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: viewModel.followUpQuestions)
        }
        .navigationTitle(viewModel.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach.conversation")
    }
}

/// One question and its answer. Earlier ones stay compact (their summary, and
/// a tap opens them); the latest is in full.
struct CoachTurnView: View {
    let turn: CoachTurn
    let isLatest: Bool
    let viewModel: CoachViewModel
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .trailing, spacing: NoctisSpacing.md) {
            CoachQuestionChip(text: turn.question)
            CoachAnswerSlot(turn: turn, viewModel: viewModel, showsFull: isLatest || expanded) {
                withAnimation(NoctisMotion.flow) { expanded.toggle() }
            }
        }
    }
}

/// The question as a small right-aligned chip on the rose field color.
struct CoachQuestionChip: View {
    let text: String

    var body: some View {
        Text(text)
            .noctisFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(NoctisAppColor.blockInk)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, NoctisSpacing.md)
            .padding(.vertical, NoctisSpacing.sm)
            .background(NoctisSection.coach.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: 520, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("You asked: \(text)")
            .accessibilityIdentifier("coach.question")
    }
}

/// What stands under a question: the skeleton while it's read, the answer, or the error card.
struct CoachAnswerSlot: View {
    let turn: CoachTurn
    let viewModel: CoachViewModel
    let showsFull: Bool
    let toggle: () -> Void

    var body: some View {
        Group {
            switch turn.phase {
            case .loading:
                CoachLoadingBlock()
            case .answered(let answer) where answer.sourceKind == .scripted:
                CoachPlainCard(answer: answer, viewModel: viewModel)
            case .answered(let answer):
                if showsFull {
                    CoachAnswerCard(turn: turn, answer: answer, viewModel: viewModel)
                } else {
                    CoachCompactAnswer(answer: answer, open: toggle)
                }
            case .failed:
                CoachErrorCard { viewModel.retry(turn.id) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An earlier answer, folded to its summary.
struct CoachCompactAnswer: View {
    let answer: CoachAnswer
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            NoctisAppCard {
                HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                    Text(answer.summary)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .noctisIcon(12, .semibold, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityHint("Shows the whole answer.")
        .accessibilityIdentifier("coach.compact")
    }
}

/// "Reading your latest data…": a block in the shape of the answer, pulsing
/// slowly. No spinner.
struct CoachLoadingBlock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                .fill(NoctisAppColor.track)
                .frame(height: 132)
                .opacity(pulsing ? 0.55 : 1)
            Text("Reading your latest data…")
                .noctisFont(13, .medium, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .padding(.horizontal, NoctisSpacing.xs)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(NoctisMotion.pulse) { pulsing = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading your latest data")
        .accessibilityIdentifier("coach.loading")
    }
}

/// Coach couldn't put an answer together: an inline card, and a way to try again.
struct CoachErrorCard: View {
    let retry: () -> Void

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                Text("Coach couldn't answer that just now.")
                    .noctisFont(19, .semibold, relativeTo: .headline)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your data is fine; the answer just didn't come together.")
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                CoachPillButton(title: "Try again", identifier: "coach.retry", symbol: "arrow.clockwise", action: retry)
            }
        }
        .accessibilityIdentifier("coach.error")
    }
}
