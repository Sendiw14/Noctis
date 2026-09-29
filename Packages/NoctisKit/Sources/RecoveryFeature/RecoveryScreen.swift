import DesignSystem
import HomeFeature
import NoctisCore
import RecoveryKit
import SwiftUI

/// How a `RecoveryScreen` is presented.
public enum RecoveryPresentation: Sendable {
    /// The Recovery tab's root: the large title is part of the content.
    case tab
    /// Pushed over Home from the ring: the navigation bar carries the
    /// title and the back button.
    case pushed
}

/// Recovery: the date, the title, the segmented control (Today | 7D | 30D |
/// 90D) and whatever the segment shows, on the paper. One scroll. The same
/// component is the Recovery tab's root and the screen Home's ring zooms
/// into; it reads only `RecoveryViewModel` (APP_RULES.md R20).
public struct RecoveryScreen: View {
    static let contentMaxWidth: CGFloat = 680

    let viewModel: RecoveryViewModel
    let presentation: RecoveryPresentation
    /// A factor whose card to scroll to (a capsule on Home was tapped).
    let focus: RecoveryFactorKind?
    let openFactor: (RecoveryFactorKind, RecoveryFactorRange) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .top)

    public init(
        viewModel: RecoveryViewModel,
        presentation: RecoveryPresentation,
        focus: RecoveryFactorKind? = nil,
        openFactor: @escaping (RecoveryFactorKind, RecoveryFactorRange) -> Void
    ) {
        self.viewModel = viewModel
        self.presentation = presentation
        self.focus = focus
        self.openFactor = openFactor
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                RecoveryContent(viewModel: viewModel, presentation: presentation, openFactor: openFactor)
            }
            .scrollPosition($scrollPosition)
            .scrollClipDisabled()
            .task(id: viewModel.screen?.today != nil) {
                guard let focus, viewModel.screen?.today != nil else { return }
                try? await Task.sleep(for: .seconds(0.05))
                proxy.scrollTo(focus, anchor: .top)
            }
        }
        .modifier(RecoveryChrome(presentation: presentation))
        .refreshable {
            await viewModel.refresh()
            NoctisHaptics.soft()
        }
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
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
    }

    /// Back to the top: a second press of the Recovery tab.
    public func scrollToTop() {
        withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
            scrollPosition.scrollTo(edge: .top)
        }
    }
}

/// The chrome a presentation adds: the tab hides the navigation bar and
/// guards the status bar; pushed shows an inline "Recovery" with a back
/// button.
private struct RecoveryChrome: ViewModifier {
    let presentation: RecoveryPresentation

    func body(content: Content) -> some View {
        switch presentation {
        case .tab:
            content
                .noctisStatusBarGuard()
                .navigationTitle("Recovery")
                .toolbar(.hidden, for: .navigationBar)
        case .pushed:
            content
                .navigationTitle("Recovery")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The scrolling content: the header, then whatever the selection shows.
struct RecoveryContent: View {
    let viewModel: RecoveryViewModel
    let presentation: RecoveryPresentation
    let openFactor: (RecoveryFactorKind, RecoveryFactorRange) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecoveryHeaderView(viewModel: viewModel, presentation: presentation)
            Color.clear.frame(height: NoctisSpacing.md)
            ZStack(alignment: .top) {
                if let screen = viewModel.screen {
                    body(screen)
                        .id(viewModel.revealSkips)
                        .transition(.opacity)
                } else {
                    RecoverySkeletonView(charts: viewModel.selection.segment != .today)
                        .transition(.opacity)
                }
            }
            .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: viewModel.screen == nil)
        }
        .frame(maxWidth: RecoveryScreen.contentMaxWidth)
        .padding(.horizontal, NoctisSpacing.lg)
        .padding(.top, NoctisSpacing.xs)
        .padding(.bottom, NoctisSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func body(_ screen: RecoveryScreenContent) -> some View {
        if let state = screen.state {
            RecoveryStateView(state: state, viewModel: viewModel)
        } else {
            VStack(spacing: NoctisSpacing.md) {
                if let banner = screen.banner {
                    RecoveryBannerView(banner: banner)
                }
                if let learning = screen.learning {
                    RecoveryLearningView(content: learning)
                } else if let none = screen.noSleep {
                    RecoveryNoSleepView(content: none)
                } else if let today = screen.today {
                    RecoveryTodayView(today: today, viewModel: viewModel, openFactor: openFactor)
                } else if let history = screen.history {
                    RecoveryHistoryView(history: history, viewModel: viewModel, openFactor: openFactor)
                }
            }
        }
    }
}

/// Date caption, "Recovery", and the segmented control.
struct RecoveryHeaderView: View {
    let viewModel: RecoveryViewModel
    let presentation: RecoveryPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            // A space while loading keeps the caption's line, so the title doesn't drop when it arrives.
            NoctisCaption(viewModel.screen?.dateCaption ?? " ", style: .noctisInk3)
            if presentation == .tab {
                Text("Recovery")
                    .noctisFont(34, .bold, relativeTo: .largeTitle)
                    .tracking(-0.6)
                    .foregroundStyle(NoctisAppColor.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            if viewModel.screen?.state == nil {
                Picker("Range", selection: segmentBinding) {
                    ForEach(RecoverySegment.allCases, id: \.self) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.top, NoctisSpacing.xs)
                .disabled(viewModel.screen == nil)
                .accessibilityIdentifier("recovery.range")
            }
        }
    }

    private var segmentBinding: Binding<RecoverySegment> {
        Binding {
            viewModel.selection.segment
        } set: { segment in
            NoctisHaptics.snapLight()
            viewModel.select(segment: segment)
        }
    }
}
