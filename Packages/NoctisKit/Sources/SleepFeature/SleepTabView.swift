import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

/// The Sleep tab: "Sleep" in a large title, a segmented Day | Week | Month
/// control, and the range's content on the paper. One scroll; reads only
/// `SleepViewModel` (APP_RULES.md R20).
public struct SleepTabView: View {
    static let contentMaxWidth: CGFloat = 680

    let viewModel: SleepViewModel
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var fieldHeight: CGFloat = 0

    public init(viewModel: SleepViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = viewModel
        ScrollView {
            SleepContent(viewModel: viewModel, fieldHeight: $fieldHeight)
        }
        .scrollPosition($scrollPosition)
        .scrollClipDisabled()
        .noctisSectionStatusBar(.sleep, fieldHeight: fieldHeight)
        .refreshable {
            await viewModel.refresh()
            NoctisHaptics.soft()
        }
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        // Any touch during the reveal skips to its end.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in viewModel.skipReveal() }, including: viewModel.reveal != .none ? .all : .subviews)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
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
        .navigationTitle("Sleep")
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The scrolling content: the sage field (date, title, control, and the day's
/// hero), then whatever the selection shows on the paper.
struct SleepContent: View {
    let viewModel: SleepViewModel
    @Binding var fieldHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The first thing under the field is a card (not a dormant state or the
    /// skeleton's blocks), so it rides up over the field's edge.
    private var firstIsCard: Bool {
        guard let screen = viewModel.screen else { return true }
        return screen.state == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SleepFieldView(viewModel: viewModel, height: $fieldHeight)
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
            .frame(maxWidth: SleepTabView.contentMaxWidth)
            .padding(.horizontal, NoctisSpacing.lg)
            .padding(.top, firstIsCard ? -NoctisSectionField<EmptyView, EmptyView>.overlap : NoctisSpacing.md)
            .padding(.bottom, NoctisSpacing.xl)
            .frame(maxWidth: .infinity)
        }
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

/// The sage field: the date, "Sleep", the segmented control, and on Day the
/// night strip and the night's hero, over flat hills.
struct SleepFieldView: View {
    let viewModel: SleepViewModel
    @Binding var height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NoctisSectionField(.sleep, bottomInset: NoctisHillsMotif.height + NoctisSpacing.lg, height: $height) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                SleepHeaderView(viewModel: viewModel)
                if let screen = viewModel.screen, screen.state == nil, screen.selection.range == .day {
                    SleepNightPicker(items: screen.picker, selected: screen.selection.night) { night in
                        NoctisHaptics.snapLight()
                        viewModel.select(night: night)
                    }
                    if let day = screen.day {
                        SleepHeroView(day: day, reveal: viewModel.reveal, lowPower: viewModel.isLowPower)
                            .transition(.opacity)
                    }
                } else if viewModel.screen == nil {
                    SleepFieldSkeleton()
                }
            }
            .animation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion), value: viewModel.screen?.selection.night)
        } motif: {
            NoctisHillsMotif()
        }
    }
}

/// Date caption, "Sleep", and the segmented control, on the field.
struct SleepHeaderView: View {
    let viewModel: SleepViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            // A space while loading keeps the caption's line, so the title doesn't drop when it arrives.
            NoctisCaption(viewModel.screen?.dateCaption ?? " ", style: .noctisFieldInk2)
            Text("Sleep")
                .noctisFont(34, .bold, relativeTo: .largeTitle)
                .tracking(-0.6)
                .foregroundStyle(.noctisFieldInk)
                .accessibilityAddTraits(.isHeader)
            if viewModel.screen?.state == nil {
                Picker("Range", selection: rangeBinding) {
                    ForEach(SleepRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, NoctisSpacing.xs)
                .disabled(viewModel.screen == nil)
                .accessibilityIdentifier("sleep.range")
            }
        }
    }

    private var rangeBinding: Binding<SleepRange> {
        Binding {
            viewModel.selection?.range ?? .day
        } set: { range in
            NoctisHaptics.snapLight()
            viewModel.select(range: range)
        }
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
            DormantRingView()
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
                }
            case .noSleepData(let title, let message):
                DormantTextView(title: title, detail: message, titleSize: 22)
                if let health = URL(string: "x-apple-health://") {
                    NoctisTextButton("Open Health", adaptive: true) { openURL(health) }
                        .accessibilityHint("Opens the Health app.")
                }
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

/// Placeholders for the night strip and the hero, on the field, while the
/// first snapshot loads.
struct SleepFieldSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    var lowPower: Bool { HomeViewModel.systemLowPower() }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            HStack(spacing: NoctisSpacing.xs) {
                ForEach(0..<7, id: \.self) { _ in
                    Capsule().fill(NoctisAppColor.blockInk.opacity(0.10)).frame(width: 44, height: 56)
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
