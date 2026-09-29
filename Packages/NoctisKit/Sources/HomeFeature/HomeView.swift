import DesignSystem
import NoctisCore
import RecoveryKit
import SwiftUI

/// The Home tab: Home in a navigation stack that pushes Recovery (zooming
/// out of the ring) and Profile.
public struct HomeTabView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom
    private let viewModel: HomeViewModel

    public init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.homePath) {
            HomeView(viewModel: viewModel, zoomNamespace: zoom)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .recoveryDetail(let focus):
                        RecoveryDetailView(viewModel: viewModel, focus: focus)
                            .navigationTransition(.zoom(sourceID: HomeView.recoveryZoomID, in: zoom))
                    case .profile:
                        // R19: Profile isn't built yet (ROADMAP.md).
                        NoctisComingSoonView(title: "Profile", systemImage: "person.crop.circle")
                    }
                }
        }
    }
}

/// Where Home's sections send the person, and what they can do there.
struct HomeActions {
    var openProfile: () -> Void = {}
    /// Recovery detail, optionally scrolled to one factor.
    var openRecoveryDetail: (RecoveryFactorKind?) -> Void = { _ in }
    var openSleep: () -> Void = {}
    /// The share preview ("Share today", "Share this night").
    var share: () -> Void = {}
    var dismissInsight: () -> Void = {}
    var hideInsights: () -> Void = {}
}

/// "How am I today?" — one top-aligned scroll on the paper. Reads only
/// `HomeViewModel` (APP_RULES.md R20).
///
/// Motion, each with a job: the morning reveal (once a day), the hero
/// shrinking into a compact bar as it scrolls away, the day ↔ evening
/// morph, and "New night added" when Health delivers one.
struct HomeView: View {
    static let recoveryZoomID = "recovery"
    /// Home's scroll content, for measuring the hero.
    nonisolated static let contentSpace = "home.content"

    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var heroFrame: CGRect = .zero
    /// The scroll offset, kept where writing it invalidates nothing: a
    /// scroll writes no state, only the view model's collapse when a step
    /// or a threshold is crossed.
    @State private var scrollProbe = HomeScrollProbe()
    @State private var sharing = false
    /// The morning reveal's dusk over the paper (and the status bar scrim).
    @State private var dusk: Double
    /// The evening paper over the day paper: 1 in evening mode.
    @State private var evening: Double

    init(viewModel: HomeViewModel, zoomNamespace: Namespace.ID) {
        self.viewModel = viewModel
        self.zoomNamespace = zoomNamespace
        _dusk = State(initialValue: viewModel.reveal == .pending ? 1 : 0)
        _evening = State(initialValue: viewModel.header.mode == .evening ? 1 : 0)
    }

    var body: some View {
        #if DEBUG
        let _ = HomeBodyProbe.hit("HomeView")
        #endif
        // The compact bar is a sibling above the scroll view, not part of it.
        ZStack(alignment: .top) {
            scroll
            HomeTopOverlay(viewModel: viewModel, scrollToTop: scrollToTop)
                .zIndex(1)
        }
        // Paper plus the 3% grain, in both modes; the evening paper over it
        // in evening mode, and a flat dusk that lifts during the morning
        // reveal.
        .background {
            PaperBackground(adaptive: true)
                .overlay(NoctisAppColor.eveningPaper.opacity(evening))
                .overlay(NoctisAppColor.dusk.opacity(dusk).id(viewModel.revealSkips))
                .ignoresSafeArea()
        }
        // Any touch or scroll during the morning reveal skips to its end.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in skipReveal() }, including: revealRunning ? .all : .subviews)
        .task { await viewModel.onAppear() }
        .onAppear { NoctisSignpost.end(.launchToFirstFrame) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.updateClock() }
        }
        .onChange(of: viewModel.reveal) { _, phase in
            let target: Double = phase == .pending ? 1 : 0
            guard !reduceMotion else {
                dusk = target
                return
            }
            // Dusk lifts over 1.2s when the reveal plays; a reveal that
            // won't play (no score) just lets it go with the skeleton.
            withAnimation(phase == .playing ? NoctisMotion.draw(HomeReveal.backgroundDuration) : NoctisMotion.fade) {
                dusk = target
            }
        }
        .onChange(of: viewModel.header.mode) { _, mode in
            // The paper crossfades with the mode morph (instantly under
            // Reduce Motion).
            withAnimation(reduceMotion ? nil : NoctisMotion.draw(HomeMorph.paperDuration)) {
                evening = mode == .evening ? 1 : 0
            }
        }
        .sheet(isPresented: $sharing) {
            if let share = viewModel.screen?.share {
                SharePreviewSheet(content: share)
            }
        }
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .homeDebugProbe(lowPower: viewModel.isLowPower)
        #endif
    }

    private var revealRunning: Bool { viewModel.reveal != .none }

    /// Jumps straight to the reveal's end state, with no animation.
    private func skipReveal() {
        guard revealRunning else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dusk = 0
            viewModel.skipReveal()
        }
    }

    private var scroll: some View {
        ScrollView {
            HomeContent(viewModel: viewModel, zoomNamespace: zoomNamespace, actions: actions) { heroFrame = $0 }
        }
        .scrollPosition($scrollPosition)
        .onScrollPhaseChange { old, phase in
            if phase == .interacting { skipReveal() }
            // The collapse budget covers a scroll, finger down to rest.
            if phase == .interacting { NoctisSignpost.begin(.collapse) }
            if phase == .idle { NoctisSignpost.end(.collapse) }
        }
        .onScrollGeometryChange(for: Double.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, top in
            scrollProbe.top = top
            viewModel.scrolled(visibleTop: top, heroTop: heroFrame.minY, heroHeight: heroFrame.height)
        }
        .onChange(of: heroFrame) { _, frame in
            viewModel.scrolled(visibleTop: scrollProbe.top, heroTop: frame.minY, heroHeight: frame.height)
        }
        // R14: cards keep their shadows at the scroll view's edges.
        .scrollClipDisabled()
        .modifier(HomeSwipeActionsContainer())
        // Nothing may show behind the status bar; the scrim wears the
        // evening paper and the dusk too.
        .noctisStatusBarGuard(washes: [
            NoctisWash(NoctisAppColor.eveningPaper, opacity: evening),
            NoctisWash(NoctisAppColor.dusk, opacity: dusk),
        ])
        .refreshable {
            await viewModel.refresh()
            NoctisHaptics.soft()
        }
    }

    private var actions: HomeActions {
        HomeActions(
            openProfile: { model.homePath.append(.profile) },
            openRecoveryDetail: { model.homePath.append(.recoveryDetail(focus: $0)) },
            openSleep: { model.open(.sleep) },
            share: { sharing = true },
            dismissInsight: { removeInsight(viewModel.dismissInsight) },
            hideInsights: { removeInsight(viewModel.hideInsights) }
        )
    }

    /// The Insight block collapses with a spring and a soft haptic, and
    /// the gap closes — once the long-press menu has finished closing, so
    /// the collapse isn't hidden under the menu's own return animation.
    private func removeInsight(_ change: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(Self.menuDismissal))
            NoctisHaptics.soft()
            withAnimation(reduceMotion ? nil : NoctisMotion.flow, change)
        }
    }

    /// How long the system's context menu takes to close.
    static let menuDismissal = 0.5

    private func scrollToTop() {
        withAnimation(reduceMotion ? nil : NoctisMotion.flow) {
            scrollPosition.scrollTo(edge: .top)
        }
    }
}

/// The latest scroll offset. A plain class in `@State`: assigning to it
/// never invalidates a view.
final class HomeScrollProbe {
    var top: Double = 0
}

/// iOS 27: Home is the container for the Insight block's swipe actions.
private struct HomeSwipeActionsContainer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.swipeActionsContainer()
        } else {
            content
        }
    }
}

/// Home's sections, for the VoiceOver "Sections" rotor.
enum HomeSection: String, CaseIterable, Hashable {
    case recovery = "Recovery"
    case lastNight = "Last night"
    case insight = "Insight"
    case tonight = "Tonight"
    case week = "This week"
}

/// Home's scrolling content. Day: Recovery hero, night panel, Insight,
/// Tonight block, This week. Evening: Tonight hero, compact Recovery,
/// night panel, Insight, This week. 28pt below the hero, 16pt between
/// sections. R21: two columns at regular width (hero and night panel
/// left, blocks right), otherwise one column at most 680pt wide.
struct HomeContent: View {
    /// R21: the single column never grows past this.
    static let compactMaxWidth: CGFloat = 680
    /// Two columns stop growing here, so cards don't stretch across a
    /// very wide window.
    static let regularMaxWidth: CGFloat = 1100
    /// Space below the hero.
    static let heroSpacing: CGFloat = 28

    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID
    let actions: HomeActions
    /// The hero's frame in the scroll content, for the scroll collapse.
    var onHeroFrame: (CGRect) -> Void = { _ in }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morph
    @Namespace private var rotor

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        #if DEBUG
        let _ = HomeBodyProbe.hit("HomeContent")
        #endif
        VStack(alignment: .leading, spacing: 0) {
            HomeHeaderView(header: viewModel.header, openProfile: actions.openProfile)
            // R6: content starts 24pt below the title.
            Color.clear.frame(height: NoctisSpacing.xl)
            // The skeleton crossfades into the content in place.
            ZStack(alignment: .top) {
                if let screen = viewModel.screen {
                    sections(screen)
                        // A skipped reveal rebuilds the content at its end
                        // state, cutting every animation in flight.
                        .id(viewModel.revealSkips)
                        .transition(.opacity)
                } else {
                    HomeSkeletonView(columns: isRegular ? 2 : 1, mode: viewModel.header.mode)
                        .transition(.opacity)
                }
            }
            .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: viewModel.screen == nil)
        }
        .frame(maxWidth: isRegular ? Self.regularMaxWidth : Self.compactMaxWidth)
        .padding(.horizontal, NoctisSpacing.lg)
        .padding(.top, NoctisSpacing.xs)
        .padding(.bottom, NoctisSpacing.xl)
        .frame(maxWidth: .infinity)
        .coordinateSpace(.named(HomeView.contentSpace))
        .environment(\.noctisEveningPaper, viewModel.header.mode == .evening)
        .environment(\.homeReveal, viewModel.reveal)
        .environment(\.homeLowPower, viewModel.isLowPower)
        .environment(\.homeMorph, reduceMotion ? nil : morph)
        .task(id: revealReady) {
            guard revealReady else { return }
            // After the skeleton's crossfade.
            try? await Task.sleep(for: .seconds(0.3))
            viewModel.beginReveal()
        }
        .accessibilityRotor("Sections") {
            ForEach(presentSections, id: \.self) { section in
                AccessibilityRotorEntry(Text(section.rawValue), id: section, in: rotor)
            }
        }
    }

    private var revealReady: Bool { viewModel.reveal == .pending && viewModel.screen != nil && !viewModel.awaitsFreshData }

    private var presentSections: [HomeSection] {
        guard let screen = viewModel.screen else { return [] }
        return HomeSection.allCases.filter { section in
            switch section {
            case .recovery, .tonight: true
            case .lastNight: screen.lastNight != nil
            case .insight: screen.insight != nil
            case .week: screen.week != nil
            }
        }
    }

    /// Day ↔ evening: the ring shrinks into (or grows out of) the compact
    /// card while the Tonight hero rises and fades (.settle). Reduce
    /// Motion: a 0.2s crossfade of the whole column.
    @ViewBuilder
    private func sections(_ screen: HomeScreen) -> some View {
        if reduceMotion {
            ZStack(alignment: .top) {
                column(screen)
                    .id(screen.mode)
                    .transition(.opacity)
            }
            .animation(NoctisMotion.reduced, value: screen.mode)
        } else {
            column(screen)
                .animation(NoctisMotion.settle, value: screen.mode)
        }
    }

    @ViewBuilder
    private func column(_ screen: HomeScreen) -> some View {
        if isRegular {
            HStack(alignment: .top, spacing: NoctisSpacing.md) {
                VStack(spacing: 0) {
                    hero(screen)
                    Color.clear.frame(height: Self.heroSpacing)
                    VStack(spacing: NoctisSpacing.md) { leadSections(screen) }
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: NoctisSpacing.md) { blocks(screen) }
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                hero(screen)
                Color.clear.frame(height: Self.heroSpacing)
                VStack(spacing: NoctisSpacing.md) {
                    leadSections(screen)
                    blocks(screen)
                }
            }
        }
    }

    private func hero(_ screen: HomeScreen) -> some View {
        VStack(spacing: 0) {
            switch screen.mode {
            case .day:
                DayHeroView(content: screen.recovery, viewModel: viewModel, zoomNamespace: zoomNamespace, actions: actions)
                    .accessibilityRotorEntry(id: HomeSection.recovery, in: rotor)
                    .transition(.opacity)
            case .evening:
                EveningHeroView(content: screen.evening, viewModel: viewModel)
                    .accessibilityRotorEntry(id: HomeSection.tonight, in: rotor)
                    .transition(.opacity.combined(with: .offset(y: 24)))
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(HomeView.contentSpace)) } action: { onHeroFrame($0) }
    }

    /// Evening's compact Recovery card, then the night panel.
    @ViewBuilder
    private func leadSections(_ screen: HomeScreen) -> some View {
        if screen.mode == .evening {
            CompactRecoveryCard(content: screen.recovery, viewModel: viewModel, zoomNamespace: zoomNamespace, openDetail: actions.openRecoveryDetail)
                .accessibilityRotorEntry(id: HomeSection.recovery, in: rotor)
                .transition(.opacity)
        }
        if let lastNight = screen.lastNight {
            NightPanelView(content: lastNight, open: actions.openSleep, share: actions.share)
                .accessibilityRotorEntry(id: HomeSection.lastNight, in: rotor)
        }
    }

    @ViewBuilder
    private func blocks(_ screen: HomeScreen) -> some View {
        if let insight = screen.insight {
            InsightBlockView(content: insight, dismiss: actions.dismissInsight, hide: actions.hideInsights)
                .accessibilityRotorEntry(id: HomeSection.insight, in: rotor)
                // It fades faster than the spring that closes the gap, so
                // the block below never slides over its text.
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: AnyTransition.scale(scale: 0.94, anchor: .top)
                        .combined(with: AnyTransition.opacity.animation(NoctisMotion.select))
                ))
        }
        if screen.mode == .day {
            TonightBlockView(content: screen.tonight)
                .accessibilityRotorEntry(id: HomeSection.tonight, in: rotor)
                .transition(.opacity)
        }
        if let week = screen.week {
            WeekCardView(content: week, open: actions.openSleep)
                .accessibilityRotorEntry(id: HomeSection.week, in: rotor)
        }
    }
}

// MARK: - Header

/// Date caption, greeting, one-sentence summary and the avatar.
struct HomeHeaderView: View {
    let header: HomeHeader
    let openProfile: () -> Void

    private var emphasis: Color {
        header.mode == .evening ? NoctisAppColor.lavenderText : NoctisAppColor.orangeText
    }

    var body: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                NoctisCaption(header.dateCaption, style: .noctisInk3)
                Text("\(Text(header.greetingLead))\(Text(header.greetingEmphasis).foregroundStyle(emphasis))\(Text(header.greetingTrail))")
                    .noctisFont(34, .bold, relativeTo: .largeTitle)
                    .tracking(-0.6)
                    .foregroundStyle(NoctisAppColor.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HomeSummaryLine(summary: header.summary)
                if let updated = header.updated {
                    Text(updated)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: openProfile) {
                Circle()
                    .fill(NoctisAppColor.track)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NoctisAppColor.ink2)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
            .accessibilityHint("Opens your profile.")
        }
    }
}

/// 13pt uppercase caption with 0.08em tracking ("LAST NIGHT").
struct NoctisCaption<Style: ShapeStyle>: View {
    let text: String
    let style: Style

    init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }

    var body: some View {
        Text(text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .tracking(13 * 0.08)
            .foregroundStyle(style)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Loading

/// Skeleton blocks in the track color while the first snapshot loads,
/// shaped like what's coming (the ring hero by day, the bedtime hero in
/// the evening) so the content crossfades in without a jump; a slow
/// pulse, none under Reduce Motion.
struct HomeSkeletonView: View {
    var columns = 1
    var mode: HomeMode = .day
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeLowPower) private var lowPower
    @State private var dimmed = false

    var body: some View {
        Group {
            if columns > 1 {
                HStack(alignment: .top, spacing: NoctisSpacing.md) {
                    VStack(spacing: HomeContent.heroSpacing) {
                        heroBlock
                        block(height: 280)
                    }
                    VStack(spacing: NoctisSpacing.md) {
                        block(height: 110)
                        block(height: 120)
                        block(height: 200)
                    }
                }
            } else {
                VStack(spacing: HomeContent.heroSpacing) {
                    heroBlock
                    VStack(spacing: NoctisSpacing.md) {
                        block(height: 280)
                        block(height: 110)
                    }
                }
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .onAppear {
            // The pulse is ambient: none under Reduce Motion or Low Power.
            guard !reduceMotion, !lowPower else { return }
            withAnimation(NoctisMotion.pulse) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your sleep data")
    }

    @ViewBuilder
    private var heroBlock: some View {
        switch mode {
        case .day:
            VStack(spacing: NoctisSpacing.md) {
                NoctisRingLayout(
                    maxDiameter: ScoredHeroView.ringDiameter,
                    narrowDiameter: ScoredHeroView.narrowRingDiameter,
                    narrowBelowWidth: ScoredHeroView.narrowBelowWidth
                ) {
                    Circle().strokeBorder(NoctisAppColor.track, lineWidth: ScoredHeroView.ringLineWidth)
                }
                Capsule().fill(NoctisAppColor.track).frame(width: 160, height: 28)
                Capsule().fill(NoctisAppColor.track).frame(height: 76)
            }
            .frame(maxWidth: .infinity)
        case .evening:
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                Capsule().fill(NoctisAppColor.track).frame(width: 80, height: 14)
                Capsule().fill(NoctisAppColor.track).frame(width: 220, height: 88)
                Capsule().fill(NoctisAppColor.track).frame(width: 120, height: 22)
                Capsule().fill(NoctisAppColor.track).frame(height: 22).padding(.vertical, NoctisSpacing.xs)
                Capsule().fill(NoctisAppColor.track).frame(width: 180, height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
            .fill(NoctisAppColor.track)
            .frame(height: height)
    }
}

// MARK: - Colors

extension RecoveryFactorKind {
    /// Sleep sage, HRV lavender, resting HR orange, consistency butter.
    var tint: Color {
        switch self {
        case .sleepDuration: NoctisAppColor.sage
        case .hrv: NoctisAppColor.lavender
        case .restingHeartRate: NoctisAppColor.orange
        case .sleepConsistency: NoctisAppColor.butter
        }
    }
}

extension RingSegmentContent {
    /// The ring's segment: its factor's color and the render model's
    /// angles (nothing is laid out again).
    var ringSegment: NoctisRingSegment {
        NoctisRingSegment(
            color: kind.tint, weight: weight, fraction: fraction, usual: usual,
            arc: NoctisRingArc(startDegrees: arc.startDegrees, endDegrees: arc.endDegrees, tickDegrees: arc.tickDegrees)
        )
    }
}

extension NightLane {
    /// On the night panel (and This week's stacked bars): Awake butter,
    /// REM sage, Core orange, Deep night lavender (cocoa would vanish on
    /// the cocoa panel).
    var tint: Color {
        switch self {
        case .awake: NoctisAppColor.butter
        case .rem: NoctisAppColor.sage
        case .core: NoctisAppColor.orange
        case .deep: NoctisAppColor.nightDeep
        }
    }
}

/// The day ↔ evening morph's timing.
enum HomeMorph {
    /// The paper crossfades over this long.
    static let paperDuration = 1.2
}
