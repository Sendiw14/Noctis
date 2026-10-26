import CoachKit
import DesignSystem
import NoctisCore
import SwiftUI

// MARK: - Reveal

/// An answer arrives section by section: each rises 12pt with a 60ms stagger,
/// sprung, once. Reduce Motion: a plain fade, all together. A section that has
/// already been revealed (a page opened again) is simply there.
private struct CoachRevealModifier: ViewModifier {
    let index: Int
    @State private var appeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(index: Int, play: Bool) {
        self.index = index
        _appeared = State(initialValue: !play)
    }

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .onAppear {
                guard !appeared else { return }
                withAnimation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion).delay(reduceMotion ? 0 : Double(index) * 0.06)) {
                    appeared = true
                }
            }
    }
}

extension View {
    fileprivate func coachReveal(_ index: Int, play: Bool) -> some View {
        modifier(CoachRevealModifier(index: index, play: play))
    }
}

// MARK: - The answer

/// A structured answer: the summary on a cocoa block, what it rests on, what
/// changed and what to notice, tonight's suggestion when there is one, the
/// pattern when there is one, how sure Coach is, where to look, where it came
/// from and whether it helped. Never a bubble.
struct CoachAnswerCard: View {
    let turn: CoachTurn
    let answer: CoachAnswer
    let viewModel: CoachViewModel
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let play = !turn.revealed
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            CoachSummaryBlock(answer: answer)
                .coachReveal(0, play: play)
            if !answer.contributors.isEmpty {
                CoachContributorsCard(contributors: answer.contributors)
                    .coachReveal(1, play: play)
            }
            CoachTextSection(title: "WHAT CHANGED", text: answer.whatChanged, identifier: "coach.changed")
                .coachReveal(2, play: play)
            CoachTextSection(title: "WHAT TO NOTICE", text: answer.whatToNotice, identifier: "coach.notice")
                .coachReveal(3, play: play)
            if let tonight = answer.tonightSuggestion {
                CoachTonightBlock(text: tonight)
                    .coachReveal(4, play: play)
            }
            if let pattern = answer.pattern {
                CoachPatternSection(text: pattern, note: answer.patternNote)
                    .coachReveal(5, play: play)
            }
            CoachConfidenceRow(answer: answer)
                .coachReveal(6, play: play)
            if !answer.destinations.isEmpty {
                CoachDestinationRow(destinations: answer.destinations, intent: answer.intent) { appModel.open($0) }
                    .coachReveal(7, play: play)
            }
            CoachSourceFooter(answer: answer)
                .coachReveal(8, play: play)
            if turn.messageID != nil {
                CoachFeedbackRow(selected: turn.feedback) { viewModel.setFeedback($0, for: turn.id) }
                    .coachReveal(9, play: play)
            }
        }
        .onAppear { viewModel.markRevealed(turn.id) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.answer")
    }
}

/// The summary sentence at 22 bold on a cocoa block; the number it is about,
/// when it names one, at 44 beside it (above it when the line is long).
struct CoachSummaryBlock: View {
    let answer: CoachAnswer

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: NoctisSpacing.md) {
                sentence
                number
            }
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                number
                sentence
            }
        }
        .padding(NoctisSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoctisAppColor.blockCocoa, in: RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
        .noctisContrastBorder()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.summary.block")
    }

    private var sentence: some View {
        Text(answer.summary)
            .noctisFont(22, .bold, relativeTo: .title3)
            .foregroundStyle(NoctisPaper.bg)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var number: some View {
        if let key = answer.keyNumber {
            NoctisMetric(CoachMetric.value(key), size: 44, tone: .nightPanel)
                .accessibilityLabel("\(key.label), \(key.spoken)")
        }
    }
}

/// What the answer rests on: a row per fact, its tile, its words and its value.
struct CoachContributorsCard: View {
    let contributors: [CoachContributor]

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                NoctisCaption("WHAT'S BEHIND THIS", style: .noctisInk3)
                ForEach(Array(contributors.enumerated()), id: \.offset) { index, contributor in
                    if index > 0 { Rectangle().fill(NoctisAppColor.hairline).frame(height: 1) }
                    CoachContributorRow(contributor: contributor)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.contributors")
    }
}

struct CoachContributorRow: View {
    let contributor: CoachContributor

    var body: some View {
        let tile = CoachContributorTile.of(factID: contributor.factID)
        HStack(spacing: NoctisSpacing.sm) {
            NoctisIconTile(systemImage: tile.symbol, fill: tile.tile.fill, foreground: NoctisAppColor.blockInk, size: 40)
            Text(contributor.label)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(.noctisInk2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            NoctisMetric(CoachMetric.value(contributor), size: 24, relativeTo: .title3, maxScale: 1.4, tone: .paper)
                .multilineTextAlignment(.trailing)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contributor.label), \(contributor.spoken)")
    }
}

/// "WHAT CHANGED", "WHAT TO NOTICE": a small caps label and a paragraph.
struct CoachTextSection: View {
    let title: String
    let text: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            NoctisCaption(title, style: .noctisInk3)
            Text(text)
                .noctisFont(17, relativeTo: .body)
                .foregroundStyle(NoctisAppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, NoctisSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Tonight's suggestion, when there is one: a lavender block with cocoa ink.
struct CoachTonightBlock: View {
    let text: String

    var body: some View {
        NoctisColorBlock(fill: NoctisAppColor.blockLavender) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption("TONIGHT'S SUGGESTION", style: .noctisFieldInk2)
                Text(text)
                    .noctisFont(19, .semibold, relativeTo: .headline)
                    .foregroundStyle(.noctisFieldInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .environment(\.noctisFieldSection, .recovery)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.tonight")
    }
}

/// A pattern in the data, when there is one, with the app's own line that it
/// isn't proof of a cause.
struct CoachPatternSection: View {
    let text: String
    let note: String?

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption("PATTERN", style: .noctisInk3)
                Text(text)
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.pattern")
    }
}

/// "Moderate confidence · based on 14 nights", and why when it isn't high.
struct CoachConfidenceRow: View {
    let answer: CoachAnswer

    private var dot: Color {
        switch answer.confidence {
        case .high: NoctisAppColor.sage
        case .moderate: NoctisAppColor.butter
        case .low: NoctisAppColor.orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            HStack(spacing: NoctisSpacing.xs) {
                Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(answer.confidenceLine)
                    .noctisFont(13, .semibold, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, NoctisSpacing.sm)
            .padding(.vertical, NoctisSpacing.xs)
            .frame(minHeight: 32)
            .background(NoctisAppColor.track, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coach.confidence")
            if let caution = answer.caution {
                Text(caution)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NoctisSpacing.xs)
                    .accessibilityIdentifier("coach.caution")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Open Recovery", "See bedtime", "Open Sleep": 44pt buttons that go to the exact screen.
struct CoachDestinationRow: View {
    let destinations: [AppRoute]
    let intent: CoachIntent
    let open: (AppRoute) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoctisSpacing.sm) { buttons }
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) { buttons }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttons: some View {
        ForEach(Array(destinations.enumerated()), id: \.offset) { _, route in
            CoachPillButton(title: CoachDestinationText.title(route, intent: intent), identifier: "coach.open.\(route.name)", symbol: "arrow.forward") {
                open(route)
            }
        }
    }
}

/// Where the answer came from, and the fixed line that Coach isn't advice.
struct CoachSourceFooter: View {
    let answer: CoachAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
            if let source = CoachSourceText.label(answer.sourceKind) {
                HStack(spacing: NoctisSpacing.xs) {
                    Image(systemName: answer.sourceKind == .appleIntelligence ? "sparkles" : "waveform.path.ecg")
                        .noctisIcon(12, .semibold, relativeTo: .caption)
                        .accessibilityHidden(true)
                    Text(source)
                        .noctisFont(13, .medium, relativeTo: .footnote)
                }
                .foregroundStyle(.noctisInk2)
                .accessibilityIdentifier("coach.source")
            }
            Text(answer.footer)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coach.footer")
        }
        .padding(.horizontal, NoctisSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Helpful" and "Not helpful": kept on this device, next to the answer, and
/// nowhere else.
struct CoachFeedbackRow: View {
    let selected: CoachFeedback?
    let choose: (CoachFeedback) -> Void

    var body: some View {
        // Side by side when both fit; stacked when large text cannot have them in one row (at AX5 each broke inside its word: "Helpf / ul").
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoctisSpacing.sm) { buttons }
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) { buttons }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.feedback")
    }

    @ViewBuilder
    private var buttons: some View {
        button(.helpful, title: "Helpful", symbol: selected == .helpful ? "hand.thumbsup.fill" : "hand.thumbsup")
        button(.notHelpful, title: "Not helpful", symbol: selected == .notHelpful ? "hand.thumbsdown.fill" : "hand.thumbsdown")
    }

    private func button(_ feedback: CoachFeedback, title: String, symbol: String) -> some View {
        let isSelected = selected == feedback
        return Button {
            choose(feedback)
        } label: {
            HStack(spacing: NoctisSpacing.xs) {
                Image(systemName: symbol).noctisIcon(14, .semibold, relativeTo: .subheadline)
                Text(title).noctisFont(15, .semibold, relativeTo: .subheadline)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? NoctisAppColor.blockInk : NoctisAppColor.ink)
            .padding(.horizontal, NoctisSpacing.md)
            .frame(minHeight: 44)
            .background(isSelected ? NoctisSection.coach.fill : NoctisAppColor.track, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("coach.feedback.\(feedback.rawValue)")
    }
}

// MARK: - A fixed reply

/// Medical, crisis, "I can help with...": a calm, plain card. No block colors,
/// no confidence, no source. The crisis reply carries "Find help".
struct CoachPlainCard: View {
    let answer: CoachAnswer
    let viewModel: CoachViewModel
    @State private var showsHelp = false

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                Text(answer.summary)
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let link = answer.helpLink {
                    // The built-in list for the person's region, which needs no network; findahelpline.com is one tap further inside it.
                    CoachPillButton(title: link.title, identifier: "coach.findHelp", symbol: "phone.fill") { showsHelp = true }
                        .accessibilityHint("Opens phone numbers for your region.")
                }
                if !answer.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                        ForEach(answer.suggestions, id: \.self) { suggestion in
                            CoachSuggestionButton(title: suggestion) { viewModel.followUp(suggestion) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsHelp) { CoachHelpSheet() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.plain")
    }
}

/// A question to try, as a full-width 44pt row.
struct CoachSuggestionButton: View {
    let title: String
    let ask: () -> Void

    var body: some View {
        Button(action: ask) {
            HStack(spacing: NoctisSpacing.xs) {
                Text(title)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisSection.coach.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .noctisIcon(12, .semibold, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach.suggestion")
    }
}

// MARK: - Follow-ups

/// The questions to ask next: chips above the input, at most three.
struct CoachFollowUpChips: View {
    let questions: [CoachQuestion]
    /// In the page (accessibility sizes): one under the other, wrapping, instead of a row that scrolls sideways under the answer.
    var stacked = false
    let ask: (CoachQuestion) -> Void

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                ForEach(questions, id: \.self) { question in
                    Button {
                        ask(question)
                    } label: {
                        Text(CoachQuestionText.text(question))
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, NoctisSpacing.md)
                            .padding(.vertical, NoctisSpacing.xs)
                            .frame(minHeight: 44, alignment: .leading)
                            .background(NoctisAppColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach.followup.\(question.token)")
                }
            }
            .accessibilityIdentifier("coach.followups")
        } else {
            scrolling
        }
    }

    private var scrolling: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NoctisSpacing.xs) {
                ForEach(questions, id: \.self) { question in
                    Button {
                        ask(question)
                    } label: {
                        Text(CoachQuestionText.text(question))
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                            .padding(.horizontal, NoctisSpacing.md)
                            .frame(minHeight: 44)
                            .background(NoctisAppColor.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach.followup.\(question.token)")
                }
            }
            .padding(.horizontal, NoctisSpacing.lg)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("coach.followups")
    }
}
