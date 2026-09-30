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

/// Recovery on the tab scaffold: the lavender field (date, the title, the
/// segmented control Today | 7D | 30D | 90D) and whatever the segment shows
/// on the paper. One scroll. The same component is the Recovery tab's root
/// and the screen Home's ring zooms into; it reads only `RecoveryViewModel`
/// (APP_RULES.md R20).
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

    /// How far the first thing under the field rides up over its edge: a
    /// card by 24pt; Today's ring on its paper disc so the disc is 24pt in;
    /// nothing for a state's dormant ring or the skeleton.
    private var top: TabContentTop {
        guard let screen = viewModel.screen else { return .below(NoctisSpacing.md) }
        if screen.state != nil || screen.learning != nil || screen.noSleep != nil { return .below(NoctisSpacing.md) }
        return screen.today != nil ? .overlapsDisc : .overlapsField
    }

    public var body: some View {
        ScrollViewReader { proxy in
            TabScreenScaffold(
                .recovery,
                presentation: presentation == .tab ? .tab : .pushed,
                header: TabScreenHeader(
                    // A space while loading keeps the caption's line, so the title doesn't drop when it arrives.
                    dateCaption: viewModel.screen?.dateCaption ?? " ",
                    title: "Recovery",
                    showsTitle: presentation == .tab,
                    control: viewModel.screen?.state == nil ? AnyView(segmentPicker) : nil
                ),
                entrance: presentation == .tab ? viewModel.fieldEntrance : .none,
                onEntered: { viewModel.fieldEntered() },
                contentTop: top,
                scrollPosition: $scrollPosition,
                refresh: {
                    await viewModel.refresh()
                    NoctisHaptics.soft()
                }
            ) {
                RecoveryContent(viewModel: viewModel, openFactor: openFactor)
            }
            .task(id: viewModel.screen?.today != nil) {
                guard let focus, viewModel.screen?.today != nil else { return }
                try? await Task.sleep(for: .seconds(0.05))
                proxy.scrollTo(focus, anchor: .top)
            }
        }
        .modifier(RecoveryNavigation(presentation: presentation))
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

    private var segmentPicker: some View {
        Picker("Range", selection: segmentBinding) {
            ForEach(RecoverySegment.allCases, id: \.self) { segment in
                Text(segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.screen == nil)
        .accessibilityIdentifier("recovery.range")
    }

    private var segmentBinding: Binding<RecoverySegment> {
        Binding {
            viewModel.selection.segment
        } set: { segment in
            NoctisHaptics.snapLight()
            viewModel.select(segment: segment)
        }
    }

    /// Back to the top: a second press of the Recovery tab.
    public func scrollToTop() {
        withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion)) {
            scrollPosition.scrollTo(edge: .top)
        }
    }
}

/// Pushed shows an inline "Recovery" with a back button (the tab's scaffold
/// hides the navigation bar itself).
private struct RecoveryNavigation: ViewModifier {
    let presentation: RecoveryPresentation

    func body(content: Content) -> some View {
        switch presentation {
        case .tab:
            content
        case .pushed:
            content
                .navigationTitle("Recovery")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// What the segment shows under the field, on the paper.
struct RecoveryContent: View {
    let viewModel: RecoveryViewModel
    let openFactor: (RecoveryFactorKind, RecoveryFactorRange) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
