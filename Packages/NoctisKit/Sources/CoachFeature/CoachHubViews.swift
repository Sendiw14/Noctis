import CoachKit
import DesignSystem
import NoctisCore
import SwiftUI

extension CoachTile {
    /// The tile's flat fill: the section colors.
    var fill: Color {
        switch self {
        case .lavender: NoctisAppColor.blockLavender
        case .sage: NoctisAppColor.blockSage
        case .butter: NoctisAppColor.blockButter
        case .apricot: NoctisAppColor.fieldApricot
        case .rose: NoctisAppColor.fieldRose
        }
    }
}

/// A suggested question: a tall card with its tile, a title of up to two
/// lines and a chevron. Pressing it asks the question.
struct CoachQuestionCardView: View {
    let card: CoachQuestionCard
    let ask: () -> Void

    var body: some View {
        Button(action: ask) {
            NoctisAppCard {
                HStack(spacing: NoctisSpacing.md) {
                    NoctisIconTile(systemImage: card.symbol, fill: card.tile.fill, foreground: NoctisAppColor.blockInk, size: 48)
                    Text(card.title)
                        .noctisFont(19, .semibold, relativeTo: .headline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .noctisIcon(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk3)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 56)
            }
            .opacity(card.isEnabled ? 1 : 0.5)
        }
        .buttonStyle(NoctisCardButtonStyle())
        .disabled(!card.isEnabled)
        .accessibilityLabel(card.title)
        .accessibilityHint(card.isEnabled ? "Asks Coach." : CoachHubContent.disabledReason)
        .accessibilityIdentifier("coach.question.\(card.id)")
    }
}

/// "Answers are built from your data without Apple Intelligence": calm, with
/// a way to turn it on only when that is what's missing.
struct CoachAppleIntelligenceBanner: View {
    let showsTurnOn: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                    NoctisIconTile(systemImage: "sparkles", fill: NoctisAppColor.track, foreground: NoctisAppColor.ink2, size: 36)
                    Text(CoachHubContent.withoutAppleIntelligence)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if showsTurnOn {
                    CoachPillButton(title: CoachHubContent.turnOnAppleIntelligence, identifier: "coach.turnOn") {
                        if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
                    }
                    .accessibilityHint("Opens Settings.")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.banner")
    }
}

/// A 44pt capsule on the rose field color: the card-level button.
struct CoachPillButton: View {
    let title: String
    let identifier: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NoctisSpacing.xs) {
                Text(title)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let symbol {
                    Image(systemName: symbol).noctisIcon(13, .semibold, relativeTo: .subheadline)
                }
            }
            .foregroundStyle(NoctisAppColor.blockInk)
            .padding(.horizontal, NoctisSpacing.md)
            .frame(minHeight: 44)
            .background(NoctisSection.coach.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// "Coach explains patterns in your own data. It isn't medical advice." — the
/// first thing on the hub, until it has been read.
struct CoachFirstRunCard: View {
    let openPrivacy: () -> Void
    let dismiss: () -> Void

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                Text(CoachHubContent.firstRunText)
                    .noctisFont(19, .semibold, relativeTo: .headline)
                    .foregroundStyle(NoctisAppColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: NoctisSpacing.sm) {
                    CoachPillButton(title: CoachHubContent.firstRunButton, identifier: "coach.firstRun.privacy", action: openPrivacy)
                    NoctisTextButton("Got it", adaptive: true, action: dismiss)
                        .accessibilityIdentifier("coach.firstRun.dismiss")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.firstRun")
    }
}

/// Coach with nothing to read yet: the same copy the other tabs use, with
/// the same way out.
struct CoachStateCard: View {
    let state: CoachHubState
    let viewModel: CoachViewModel
    @Environment(\.openURL) private var openURL
    @State private var connecting = false

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                NoctisIconTile(systemImage: "sparkles", fill: NoctisAppColor.fieldRose, foreground: NoctisAppColor.blockInk, size: 56)
                switch state {
                case .connect(let title, let message, let showsButton):
                    text(title, message)
                    if showsButton {
                        NoctisCTA("Connect Apple Health", isLoading: connecting, adaptive: true) {
                            connecting = true
                            Task {
                                await viewModel.connectAppleHealth()
                                connecting = false
                            }
                        }
                    }
                case .noSleepData(let title, let message):
                    text(title, message)
                    if let health = URL(string: "x-apple-health://") {
                        NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                            .accessibilityHint("Opens the Health app.")
                    }
                case .failed(let message):
                    text(message, nil)
                    NoctisCTA("Try again", icon: "arrow.clockwise", adaptive: true) {
                        Task { await viewModel.refresh() }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.state")
    }

    private func text(_ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            Text(title)
                .noctisFont(22, .semibold, relativeTo: .title3)
                .foregroundStyle(NoctisAppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "You have 3 nights so far": Coach still answers, and says when it can't say more.
struct CoachLearningNote: View {
    let text: String

    var body: some View {
        NoctisAppCard {
            HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                NoctisIconTile(systemImage: "moon.stars", fill: NoctisAppColor.blockSage, foreground: NoctisAppColor.blockInk, size: 36)
                Text(text)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.learning")
    }
}

/// The hub's placeholder while its first build is on the way.
struct CoachSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                    .fill(NoctisAppColor.track)
                    .frame(height: 96)
            }
        }
        .opacity(pulsing ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(NoctisMotion.pulse) { pulsing = true }
        }
        .accessibilityHidden(true)
    }
}
