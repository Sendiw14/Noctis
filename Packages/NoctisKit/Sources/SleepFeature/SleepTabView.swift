import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

/// The Sleep tab, on the tab scaffold: the sage field (date, "Sleep", the
/// segmented Day | Week | Month control, and the night's hero), then the
/// range's content on the paper. One scroll; reads only `SleepViewModel`
/// (APP_RULES.md R20).
public struct SleepTabView: View {
    static let contentMaxWidth: CGFloat = 680

    let viewModel: SleepViewModel
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.featureGate) private var gate
    @State private var scrollPosition = ScrollPosition(edge: .top)

    public init(viewModel: SleepViewModel) {
        self.viewModel = viewModel
    }

    /// The first thing under the field is a card (not a dormant state), so
    /// it rides up over the field's edge; the skeleton's blocks do too.
    private var top: TabContentTop {
        guard let screen = viewModel.screen else { return .overlapsField }
        return screen.state == nil ? .overlapsField : .below(NoctisSpacing.md)
    }

    public var body: some View {
        @Bindable var model = viewModel
        TabScreenScaffold(
            .sleep,
            header: header,
            entrance: viewModel.fieldEntrance,
            onEntered: { viewModel.fieldEntered() },
            contentTop: top,
            scrollPosition: $scrollPosition,
            refresh: {
                await viewModel.refresh()
                NoctisHaptics.soft()
            }
        ) {
            SleepContent(viewModel: viewModel)
        }
        // Any touch during the reveal skips to its end.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in viewModel.skipReveal() }, including: viewModel.reveal != .none ? .all : .subviews)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        // A lapse or a purchase: what was Premium goes back to what is free, or unlocks in place (R57).
        .onChange(of: gate.tier) { viewModel.tierChanged() }
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: gate.tier)
        // The Sleep tab pressed again: back to the top.
        .onChange(of: appModel.tabRetap) { _, retap in
            guard retap?.tab == .sleep else { return }
            withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .task(id: viewModel.reveal == .pending && viewModel.screen?.day != nil) {
            guard viewModel.reveal == .pending, viewModel.screen?.day != nil else { return }
            // After the content has laid out in its start state.
            try? await Task.sleep(for: .seconds(0.15))
            viewModel.beginReveal()
        }
        .sheet(item: $model.detail) { detail in
            if let screen = viewModel.screen {
                SleepDetailSheet(detail: detail, screen: screen)
            }
        }
    }

    private var header: TabScreenHeader {
        TabScreenHeader(
            // A space while loading keeps the caption's line, so the title doesn't drop when it arrives.
            dateCaption: viewModel.screen?.dateCaption ?? " ",
            title: "Sleep",
            control: viewModel.screen?.state == nil ? AnyView(rangePicker) : nil,
            hero: viewModel.screen?.state == nil ? AnyView(SleepFieldHero(viewModel: viewModel)) : nil
        )
    }

    private var rangePicker: some View {
        NoctisSegmentedControl(
            "Range", segments: SleepRange.allCases.map { NoctisSegment($0, title: $0.title, isLocked: viewModel.lockedFeature(for: $0) != nil) },
            selection: rangeBinding, identifier: "sleep.range"
        )
        .disabled(viewModel.screen == nil)
    }

    private var rangeBinding: Binding<SleepRange> {
        Binding {
            viewModel.selection?.range ?? .day
        } set: { range in
            // A locked range opens the paywall and the selection stays where it was (R58).
            if let feature = viewModel.lockedFeature(for: range) {
                NoctisHaptics.selection()
                appModel.presentPaywall(for: feature)
                return
            }
            NoctisHaptics.snapLight()
            viewModel.select(range: range)
        }
    }
}

/// What the selection shows under the field, on the paper.
struct SleepContent: View {
    let viewModel: SleepViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let screen = viewModel.screen {
                body(screen)
                    .id(viewModel.revealSkips)
                    .transition(.opacity)
            } else {
                SleepSkeletonView()
                    .transition(.opacity)
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: viewModel.screen == nil)
    }

    @ViewBuilder
    private func body(_ screen: SleepScreen) -> some View {
        if let state = screen.state {
            SleepStateView(state: state, viewModel: viewModel)
        } else {
            VStack(spacing: NoctisSpacing.md) {
                if let banner = screen.banner {
                    SleepBannerView(banner: banner)
                }
                switch screen.selection.range {
                case .day:
                    SleepDayView(screen: screen, viewModel: viewModel)
                case .week, .month:
                    SleepRangeView(screen: screen, viewModel: viewModel)
                }
            }
        }
    }
}

/// What lives on the sage field under the control: on Day the night strip
/// and the night's hero; on Week and Month the summary strip; then the
/// highlights.
struct SleepFieldHero: View {
    let viewModel: SleepViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            if let screen = viewModel.screen, screen.state == nil, screen.selection.range == .day {
                SleepNightPicker(
                    items: screen.picker, selected: screen.selection.night,
                    locked: Set(screen.picker.map(\.night).filter { viewModel.lockedFeature(forNight: $0) != nil })
                ) { night in
                    // Nights 4 to 14 are Premium: a tap opens the paywall and the selection stays (R58).
                    if let feature = viewModel.lockedFeature(forNight: night) {
                        NoctisHaptics.selection()
                        appModel.presentPaywall(for: feature)
                        return
                    }
                    NoctisHaptics.snapLight()
                    viewModel.select(night: night)
                }
                if let day = screen.day {
                    SleepHeroView(day: day, reveal: viewModel.reveal, lowPower: viewModel.isLowPower)
                        .transition(.opacity)
                }
                SleepHighlightRow(highlights: screen.highlights)
            } else if let screen = viewModel.screen, screen.state == nil, let summary = screen.summary {
                SleepSummaryStrip(summary: summary) { viewModel.selectedBar = $0 }
                    .transition(.opacity)
                SleepHighlightRow(highlights: screen.highlights)
            } else if viewModel.screen == nil {
                SleepFieldSkeleton()
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion), value: viewModel.screen?.selection.night)
    }
}

/// Apple Health hasn't updated: what's shown is what was last read.
struct SleepBannerView: View {
    let banner: SleepBanner
    @Environment(\.openURL) private var openURL

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Text(banner.title)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(banner.detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                if let health = URL(string: "x-apple-health://") {
                    NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                        .accessibilityHint("Opens the Health app.")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Nothing to show yet: what's going on, and its one action.
struct SleepStateView: View {
    let state: SleepStateContent
    let viewModel: SleepViewModel
    @Environment(\.openURL) private var openURL
    @State private var connecting = false

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            DormantRingView(onField: true)
            switch state {
            case .connect(let title, let message, let showsButton):
                DormantTextView(title: title, detail: message, titleSize: 22)
                if showsButton {
                    NoctisCTA("Connect Apple Health", isLoading: connecting, adaptive: true) {
                        connecting = true
                        Task {
                            await viewModel.connectAppleHealth()
                            connecting = false
                        }
                    }
                    HealthDataSettingsLink()
                }
            case .noSleepData(let title, let message):
                DormantTextView(title: title, detail: message, titleSize: 22)
                if let health = URL(string: "x-apple-health://") {
                    NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                        .accessibilityHint("Opens the Health app.")
                }
                HealthDataSettingsLink()
            case .failed(let message):
                DormantTextView(title: message, detail: nil)
                NoctisCTA("Try again", icon: "arrow.clockwise", adaptive: true) {
                    Task { await viewModel.refresh() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NoctisSpacing.xl)
        .accessibilityIdentifier("sleep.state")
    }
}

/// The night's or week's highlights, as small butter capsules under the
/// hero; nothing (and no space) when there are none.
struct SleepHighlightRow: View {
    let highlights: [SleepHighlightContent]

    var body: some View {
        if !highlights.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NoctisSpacing.xs) { capsules }
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) { capsules }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }

    private var capsules: some View {
        ForEach(highlights) { NoctisHighlightCapsule($0.text) }
    }
}

/// Placeholders for the night strip and the hero, on the field, while the
/// first snapshot loads.
struct SleepFieldSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    var lowPower: Bool { HomeViewModel.systemLowPower() }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            HStack(spacing: NoctisSpacing.xs) {
                // Up to 44pt each, less where the row is narrower: seven fixed 44pt capsules are 356pt, wider than an SE's 335pt of content,
                // and they widened the whole skeleton past the 20pt side margins.
                ForEach(0..<7, id: \.self) { _ in
                    Capsule().fill(NoctisAppColor.blockInk.opacity(0.10)).frame(height: 56).frame(maxWidth: 44)
                }
            }
            HStack(spacing: NoctisSpacing.md) {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    Capsule().fill(NoctisAppColor.blockInk.opacity(0.10)).frame(width: 190, height: 64)
                    Capsule().fill(NoctisAppColor.blockInk.opacity(0.10)).frame(width: 130, height: 16)
                }
                Spacer(minLength: 0)
                Circle().fill(NoctisAppColor.blockInk.opacity(0.10)).frame(width: 96, height: 96)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(dimmed ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion, !lowPower else { return }
            withAnimation(NoctisMotion.pulse) { dimmed = true }
        }
        .accessibilityHidden(true)
    }
}

/// Track-colored blocks shaped like the day view's cards while the first
/// snapshot loads; a slow pulse, none under Reduce Motion or Low Power Mode.
struct SleepSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    var lowPower: Bool { HomeViewModel.systemLowPower() }

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            block(height: 250)
            block(height: 220)
            block(height: 120)
        }
        .opacity(dimmed ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion, !lowPower else { return }
            withAnimation(NoctisMotion.pulse) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your sleep")
        .accessibilityIdentifier("sleep.skeleton")
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
            .fill(NoctisAppColor.track)
            .frame(height: height)
    }
}
