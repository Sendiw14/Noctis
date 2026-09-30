import DesignSystem
import HomeFeature
import InsightsKit
import NoctisCore
import SwiftUI

/// Insights on the tab scaffold: the butter field (date, the title, a line
/// saying how many are new and History at the trailing edge) and, on the
/// paper under it, the chips and whatever the filter shows. One scroll. It
/// reads only `InsightsViewModel` (APP_RULES.md R20).
public struct InsightsScreen: View {
    static let contentMaxWidth: CGFloat = 680

    let viewModel: InsightsViewModel
    let openInsight: (String) -> Void
    let openHistory: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .top)

    public init(viewModel: InsightsViewModel, openInsight: @escaping (String) -> Void, openHistory: @escaping () -> Void) {
        self.viewModel = viewModel
        self.openInsight = openInsight
        self.openHistory = openHistory
    }

    public var body: some View {
        TabScreenScaffold(
            .insights,
            presentation: .tab,
            header: TabScreenHeader(
                // A space while loading keeps the caption's line, so the title doesn't drop when it arrives.
                dateCaption: viewModel.screen?.dateCaption ?? " ",
                title: "Insights",
                summary: viewModel.screen.map { AnyView(summary($0.summary)) },
                trailing: showsHistory ? AnyView(InsightsHistoryButton(open: openHistory)) : nil
            ),
            entrance: viewModel.fieldEntrance,
            onEntered: { viewModel.fieldEntered() },
            contentTop: .below(NoctisSpacing.md),
            scrollPosition: $scrollPosition,
            refresh: {
                await viewModel.refresh()
                NoctisHaptics.soft()
            }
        ) {
            InsightsContent(viewModel: viewModel, openInsight: openInsight)
        }
        // Any touch during the reveal skips to its end.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in viewModel.skipReveal() }, including: viewModel.reveal != .none ? .all : .subviews)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .task(id: viewModel.reveal == .pending) {
            guard viewModel.reveal == .pending else { return }
            // After the content has laid out in its start state.
            try? await Task.sleep(for: .seconds(0.15))
            viewModel.beginReveal()
        }
        // A second press of the Insights tab: back to the top (or back out of a pushed page).
        .onChange(of: appModel.tabRetap) { _, retap in
            guard retap?.tab == .insights else { return }
            if appModel.insightsPath.isEmpty {
                withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
                    scrollPosition.scrollTo(edge: .top)
                }
            } else {
                appModel.insightsPath = []
            }
        }
    }

    /// Only when there are insights to look back over.
    private var showsHistory: Bool {
        guard let screen = viewModel.screen else { return false }
        return screen.state == nil && screen.learning == nil
    }

    private func summary(_ text: String) -> some View {
        Text(text)
            .noctisFont(17, relativeTo: .body)
            .foregroundStyle(.noctisFieldInk2)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : NoctisMotion.settle, value: text)
            .accessibilityIdentifier("insights.summary")
    }
}

/// History at the field's trailing edge: a 36pt circle in a 44pt target.
struct InsightsHistoryButton: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Circle()
                .fill(NoctisAppColor.blockInk.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NoctisAppColor.blockInk)
                )
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("History")
        .accessibilityHint("Shows every insight so far.")
        .accessibilityIdentifier("insights.history")
    }
}

/// What the tab shows under the field: the chips and the filter's list, a
/// learning card, or a state.
struct InsightsContent: View {
    let viewModel: InsightsViewModel
    let openInsight: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let screen = viewModel.screen {
                body(screen)
                    .id(viewModel.revealSkips)
                    .transition(.opacity)
            } else {
                InsightsSkeletonView()
                    .transition(.opacity)
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: viewModel.screen == nil)
    }

    @ViewBuilder
    private func body(_ screen: InsightsScreenContent) -> some View {
        if let state = screen.state {
            InsightsStateView(state: state, viewModel: viewModel)
        } else if let learning = screen.learning {
            InsightsLearningCard(content: learning)
        } else {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                InsightChipRow(chips: screen.chips, selected: viewModel.filter) { viewModel.select(filter: $0) }
                // A filter moves the list with springs: rows leave and arrive, the rest re-flow.
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    if let featured = screen.featured {
                        InsightFeaturedCard(content: featured, reveal: viewModel.reveal, lowPower: viewModel.isLowPower) {
                            openInsight(featured.id)
                        }
                        .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    if let note = screen.note {
                        InsightsNoteCard(note: note)
                            .transition(.opacity)
                    }
                    if !screen.groups.isEmpty {
                        InsightRowsSection(groups: screen.groups, open: openInsight)
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    if !screen.records.isEmpty {
                        InsightRecordsSection(tiles: screen.records)
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                }
                .animation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion), value: screen)
            }
        }
    }
}
