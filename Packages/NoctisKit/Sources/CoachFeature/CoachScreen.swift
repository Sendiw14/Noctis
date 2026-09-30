import CoachKit
import DesignSystem
import NoctisCore
import SwiftUI

/// The Coach hub on the tab scaffold: the rose field (date, "Coach", one
/// line, and the info button at the trailing edge) and, under it, the suggested
/// questions as cards. The text field is pinned at the bottom. It reads only
/// `CoachViewModel` (APP_RULES.md R20).
public struct CoachScreen: View {
    let viewModel: CoachViewModel
    let ask: (CoachQuestion) -> Void
    let send: () -> Void
    let openHistory: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .top)

    public init(viewModel: CoachViewModel, ask: @escaping (CoachQuestion) -> Void, send: @escaping () -> Void, openHistory: @escaping () -> Void) {
        self.viewModel = viewModel
        self.ask = ask
        self.send = send
        self.openHistory = openHistory
    }

    public var body: some View {
        TabScreenScaffold(
            .coach,
            presentation: .tab,
            header: TabScreenHeader(
                // A space while loading keeps the caption's line, so the title doesn't drop when it arrives.
                dateCaption: viewModel.hub?.dateCaption ?? " ",
                title: "Coach",
                summary: AnyView(summary),
                trailing: AnyView(HStack(spacing: 0) {
                    if viewModel.keepsHistory { CoachHistoryButton(open: openHistory) }
                    CoachInfoButton { viewModel.openPrivacy() }
                })
            ),
            entrance: viewModel.fieldEntrance,
            onEntered: { viewModel.fieldEntered() },
            contentTop: .overlapsField,
            scrollPosition: $scrollPosition,
            refresh: {
                await viewModel.refresh()
                NoctisHaptics.soft()
            }
        ) {
            CoachHubContentView(viewModel: viewModel, ask: ask)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CoachInputBar(viewModel: viewModel, placeholder: "Ask about your sleep or recovery", identifier: "coach.hub", send: send)
        }
        .task { await viewModel.onAppear() }
        // A second press of the Coach tab: back to the top.
        .onChange(of: appModel.tabRetap) { _, retap in
            guard retap?.tab == .coach else { return }
            withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
    }

    private var summary: some View {
        Text(CoachHubContent.summary)
            .noctisFont(17, relativeTo: .body)
            .foregroundStyle(.noctisFieldInk2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("coach.summary")
    }
}

/// The info button at the field's trailing edge: a 36pt circle in a 44pt target.
struct CoachInfoButton: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Circle()
                .fill(NoctisAppColor.blockInk.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "info")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(NoctisAppColor.blockInk)
                )
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How Coach uses your data")
        .accessibilityIdentifier("coach.info")
    }
}

/// What the hub shows under the field.
struct CoachHubContentView: View {
    let viewModel: CoachViewModel
    let ask: (CoachQuestion) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let hub = viewModel.hub {
                content(hub).transition(.opacity)
            } else {
                CoachSkeletonView().transition(.opacity)
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: viewModel.hub == nil)
    }

    private func content(_ hub: CoachHubContent) -> some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            if hub.appleIntelligenceUnavailable {
                CoachAppleIntelligenceBanner(showsTurnOn: hub.showsTurnOnAppleIntelligence)
                    .transition(.opacity)
            }
            if hub.showsFirstRun {
                CoachFirstRunCard(openPrivacy: { viewModel.openPrivacy() }, dismiss: { viewModel.dismissFirstRun() })
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
            if let state = hub.state {
                CoachStateCard(state: state, viewModel: viewModel)
                Text(CoachHubContent.disabledReason)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
                    .padding(.horizontal, NoctisSpacing.xs)
            }
            if let note = hub.learningNote {
                CoachLearningNote(text: note)
            }
            ForEach(hub.cards) { card in
                CoachQuestionCardView(card: card) { ask(card.question) }
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion), value: hub)
    }
}
