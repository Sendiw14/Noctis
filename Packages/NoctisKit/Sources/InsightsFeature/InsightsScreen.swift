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
    let zoom: Namespace.ID
    let openInsight: (String) -> Void
    let openHistory: () -> Void
    let openReviews: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.featureGate) private var gate
    @State private var scrollPosition = ScrollPosition(edge: .top)

    public init(
        viewModel: InsightsViewModel, zoom: Namespace.ID, openInsight: @escaping (String) -> Void, openHistory: @escaping () -> Void,
        openReviews: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.zoom = zoom
        self.openInsight = openInsight
        self.openHistory = openHistory
        self.openReviews = openReviews
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
                trailing: showsHistory ? AnyView(InsightsHistoryButton(locked: !viewModel.canOpenHistory) {
                    // History is Premium: a free person's tap opens the paywall (R58).
                    if viewModel.canOpenHistory { openHistory() } else { appModel.presentPaywall(.insightsHistory) }
                }) : nil
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
            InsightsContent(viewModel: viewModel, zoom: zoom, openInsight: openInsight, openReviews: openReviews)
        }
        // Any touch during the reveal skips to its end.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in viewModel.skipReveal() }, including: viewModel.reveal != .none ? .all : .subviews)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        // A lapse or a purchase: what was Premium goes back to what is free, or unlocks in place (R57).
        .onChange(of: gate.tier) { viewModel.tierChanged() }
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
    /// History is Premium: a lock beside the glyph, and the tap opens the paywall.
    var locked = false
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
                .overlay(alignment: .bottomTrailing) {
                    if locked {
                        LockGlyph(size: 12).foregroundStyle(NoctisAppColor.blockInk).offset(x: 2, y: 2)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "History, Premium" : "History")
        .accessibilityHint(locked ? "Opens what Premium includes." : "Shows every insight so far.")
        .accessibilityIdentifier("insights.history")
    }
}

/// What the tab shows under the field: the chips and the filter's list, a
/// learning card, or a state.
struct InsightsContent: View {
    let viewModel: InsightsViewModel
    let zoom: Namespace.ID
    let openInsight: (String) -> Void
    var openReviews: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var appModel

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
                InsightChipRow(chips: screen.chips, selected: viewModel.filter, isLocked: { viewModel.lockedFeature(forFilter: $0) != nil }) { category in
                    // A category chip is Premium: a tap opens the paywall and the chip stays where it was (R58).
                    if let feature = viewModel.lockedFeature(forFilter: category) {
                        NoctisHaptics.selection()
                        appModel.presentPaywall(for: feature)
                    } else {
                        viewModel.select(filter: category)
                    }
                }
                // A filter moves the list with springs: rows leave and arrive, the rest re-flow.
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    if let featured = screen.featured {
                        InsightFeaturedCard(content: featured, reveal: viewModel.reveal, lowPower: viewModel.isLowPower, zoom: zoom, viewModel: viewModel) {
                            openInsight(featured.id)
                        }
                        .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    if let note = screen.note {
                        InsightsNoteCard(note: note)
                            .transition(.opacity)
                    }
                    // Reviews, above Recent: the weekly and monthly reviews (APP_RULES.md R63). Free for everyone; what is Premium inside them is marked there.
                    if screen.showsInsights {
                        InsightsReviewsRow(open: openReviews)
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    if !screen.groups.isEmpty {
                        InsightRowsSection(groups: screen.groups, zoom: zoom, viewModel: viewModel, open: openInsight)
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    if !screen.records.isEmpty {
                        InsightRecordsSection(tiles: screen.records)
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    // Everything past the featured story and the most recent insight is Premium: said once, by one card (R58).
                    if !viewModel.showsEverything, screen.showsInsights, let card = LockedCopy.card(for: .insightsAll) {
                        LockedCard(title: card.title, line: card.line, identifier: "insights.locked") { appModel.presentPaywall(.insightsAll) }
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                }
                .animation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion), value: screen)
            }
        }
    }
}
