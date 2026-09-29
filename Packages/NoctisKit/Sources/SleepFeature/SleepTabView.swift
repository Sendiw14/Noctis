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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: SleepViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = viewModel
        ScrollView {
            SleepContent(viewModel: viewModel)
        }
        .scrollClipDisabled()
        .noctisStatusBarGuard()
        .refreshable {
            await viewModel.refresh()
            NoctisHaptics.soft()
        }
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        // Any touch during the reveal skips to its end.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in viewModel.skipReveal() }, including: viewModel.reveal != .none ? .all : .subviews)
        .task { await viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
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

/// The scrolling content: the header, then whatever the selection shows.
struct SleepContent: View {
    let viewModel: SleepViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SleepHeaderView(viewModel: viewModel)
            Color.clear.frame(height: NoctisSpacing.md)
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
        .frame(maxWidth: SleepTabView.contentMaxWidth)
        .padding(.horizontal, NoctisSpacing.lg)
        .padding(.top, NoctisSpacing.xs)
        .padding(.bottom, NoctisSpacing.xl)
        .frame(maxWidth: .infinity)
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
                    SleepRangePlaceholder(range: screen.selection.range)
                }
            }
        }
    }
}

/// Date caption, "Sleep", and the segmented control.
struct SleepHeaderView: View {
    let viewModel: SleepViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            NoctisCaption(viewModel.screen?.dateCaption ?? "", style: .noctisInk3)
            Text("Sleep")
                .noctisFont(34, .bold, relativeTo: .largeTitle)
                .tracking(-0.6)
                .foregroundStyle(NoctisAppColor.ink)
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

/// Track-colored blocks shaped like the day view while the first snapshot
/// loads; a slow pulse, none under Reduce Motion or Low Power Mode.
struct SleepSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false
    var lowPower: Bool { HomeViewModel.systemLowPower() }

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            HStack(spacing: NoctisSpacing.xs) {
                ForEach(0..<7, id: \.self) { _ in
                    Capsule().fill(NoctisAppColor.track).frame(width: 44, height: 56)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: NoctisSpacing.md) {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    Capsule().fill(NoctisAppColor.track).frame(width: 190, height: 64)
                    Capsule().fill(NoctisAppColor.track).frame(width: 130, height: 16)
                }
                Spacer(minLength: 0)
                Circle().fill(NoctisAppColor.track).frame(width: 96, height: 96)
            }
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
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
            .fill(NoctisAppColor.track)
            .frame(height: height)
    }
}

/// Week and Month arrive with their views.
struct SleepRangePlaceholder: View {
    let range: SleepRange

    var body: some View {
        DormantTextView(title: "\(range.title) is on its way", detail: nil)
            .frame(maxWidth: .infinity)
            .padding(.top, NoctisSpacing.xl)
    }
}

/// The detail sheets arrive with Week and Month.
struct SleepDetailSheet: View {
    let detail: SleepDetail
    let screen: SleepScreen

    var body: some View {
        Text(detail.rawValue)
    }
}
