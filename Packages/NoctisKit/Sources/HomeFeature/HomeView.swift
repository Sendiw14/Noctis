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
    /// The Recovery screen the ring zooms into (built by the app, which
    /// knows the Recovery feature), scrolled to `focus`'s card when given.
    private let recoveryScreen: (RecoveryFactorKind?) -> AnyView
    /// A factor's detail, pushed from a capsule.
    private let recoveryFactor: (RecoveryFactorKind, RecoveryFactorRange) -> AnyView
    /// Tonight (built by the app, which knows the Night feature): the bedtime window and the alarm.
    private let tonightScreen: () -> AnyView
    /// Sleep sounds, pushed over Tonight.
    private let soundsScreen: () -> AnyView

    public init(
        viewModel: HomeViewModel,
        recoveryScreen: @escaping (RecoveryFactorKind?) -> AnyView,
        recoveryFactor: @escaping (RecoveryFactorKind, RecoveryFactorRange) -> AnyView,
        tonightScreen: @escaping () -> AnyView,
        soundsScreen: @escaping () -> AnyView
    ) {
        self.viewModel = viewModel
        self.recoveryScreen = recoveryScreen
        self.recoveryFactor = recoveryFactor
        self.tonightScreen = tonightScreen
        self.soundsScreen = soundsScreen
    }

    public var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.homePath) {
            HomeView(viewModel: viewModel, zoomNamespace: zoom)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .recoveryDetail(let focus):
                        recoveryScreen(focus)
                            .navigationTransition(.zoom(sourceID: HomeView.recoveryZoomID, in: zoom))
                    case .recoveryFactor(let kind, let range):
                        recoveryFactor(kind, range)
                    case .profile:
                        // R19: Profile isn't built yet (ROADMAP.md).
                        NoctisComingSoonView(title: "Profile", systemImage: "person.crop.circle")
                    case .tonight:
                        tonightScreen()
                    case .windDown:
                        // R19: Wind-down isn't built yet (ROADMAP.md).
                        NoctisComingSoonView(title: "Wind-down", systemImage: "moon.stars")
                    case .sounds:
                        soundsScreen()
                    }
                }
        }
    }
}

/// Where Home's sections send the person, and what they can do there.
struct HomeActions {
    var openProfile: () -> Void = {}
    /// Tonight: the bedtime window and the wake alarm.
    var openTonight: () -> Void = {}
    /// Wind-down, started (the evening hero's button).
    var openWindDown: () -> Void = {}
    /// Recovery detail, optionally scrolled to one factor.
    var openRecoveryDetail: (RecoveryFactorKind?) -> Void = { _ in }
    /// One factor's page, from its capsule on the ring.
    var openRecoveryFactor: (RecoveryFactorKind) -> Void = { _ in }
    /// Sleep on Day, on the night the Last night card shows.
    var openLastNight: () -> Void = {}
    /// Sleep on Week.
    var openWeek: () -> Void = {}
    /// The share preview ("Share today", "Share this night").
    var share: () -> Void = {}
    /// The Insight block opens that insight's page (Insights tab).
    var openInsight: (String) -> Void = { _ in }
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
    @Environment(\.horizontalSizeClass) private var sizeClass
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
        TabScreenScaffold(
            .home,
            header: header,
            entrance: viewModel.fieldEntrance,
            onEntered: { viewModel.fieldEntered() },
            fieldMaxWidth: contentWidth,
            contentMaxWidth: contentWidth,
            contentTop: top,
            compactBar: .custom,
            contentSpace: HomeView.contentSpace,
            // Paper plus the 3% grain, in both modes; the evening paper over
            // it in evening mode, and a flat dusk that lifts during the
            // morning reveal (off the field too).
            paperOverlay: AnyView(
                ZStack {
                    NoctisAppColor.eveningPaper.opacity(evening)
                    NoctisAppColor.dusk.opacity(dusk).id(viewModel.revealSkips)
                }
            ),
            // Nothing may show behind the status bar; the scrim wears the
            // evening paper and the dusk too.
            paperWashes: [
                NoctisWash(NoctisAppColor.eveningPaper, opacity: evening),
                NoctisWash(NoctisAppColor.dusk, opacity: dusk),
            ],
            fieldWashes: [NoctisWash(NoctisAppColor.dusk, opacity: dusk)],
            topOverlay: AnyView(HomeTopOverlay(viewModel: viewModel, scrollToTop: scrollToTop).zIndex(1)),
            scrollPosition: $scrollPosition,
            refresh: {
                await viewModel.refresh()
                NoctisHaptics.soft()
            },
            onScroll: { top in
                scrollProbe.top = top
                viewModel.scrolled(visibleTop: top, heroTop: heroFrame.minY, heroHeight: heroFrame.height)
            },
            onScrollPhase: { _, phase in
                if phase == .interacting { skipReveal() }
                // The collapse budget covers a scroll, finger down to rest.
                if phase == .interacting { NoctisSignpost.begin(.collapse) }
                if phase == .idle { NoctisSignpost.end(.collapse) }
            },
            configureScroll: { AnyView($0.modifier(HomeSwipeActionsContainer())) }
        ) {
            HomeContent(viewModel: viewModel, zoomNamespace: zoomNamespace, actions: actions) { heroFrame = $0 }
        }
        .environment(\.homePaperWash, HomePaperWash(evening: evening, dusk: dusk))
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: top)
        // Any touch or scroll during the morning reveal skips to its end.
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in skipReveal() }, including: revealRunning ? .all : .subviews)
        .task { await viewModel.onAppear() }
        .onAppear { NoctisSignpost.end(.launchToFirstFrame) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.updateClock() }
        }
        .onChange(of: model.tabRetap) { _, retap in
            // The Home tab pressed again: back out of any pushed screen, or
            // else back to the top.
            guard retap?.tab == .home else { return }
            if model.homePath.isEmpty { scrollToTop() } else { model.homePath = [] }
        }
        .onChange(of: heroFrame) { _, frame in
            viewModel.scrolled(visibleTop: scrollProbe.top, heroTop: frame.minY, heroHeight: frame.height)
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
        #if DEBUG
        .homeDebugProbe(lowPower: viewModel.isLowPower)
        #endif
    }

    /// One column at most 680pt wide; two columns to 1100 at regular width
    /// (R21). The field is as wide.
    private var contentWidth: CGFloat {
        sizeClass == .regular ? HomeContent.regularMaxWidth : HomeContent.compactMaxWidth
    }

    /// Day's ring sits on a paper disc that rides up over the field's edge,
    /// like Recovery Today; evening's Tonight hero and the states are text
    /// on the paper below it.
    private var top: TabContentTop {
        guard let screen = viewModel.screen else { return .below(NoctisSpacing.md) }
        switch screen.mode {
        case .evening: return .below(NoctisSpacing.xl)
        case .day:
            if case .scored = screen.recovery { return .overlapsDisc }
            return .below(NoctisSpacing.md)
        }
    }

    /// The field's contents: the date, the greeting (its emphasized word in
    /// cocoa), the one-sentence summary and the avatar.
    private var header: TabScreenHeader {
        let header = viewModel.header
        return TabScreenHeader(
            dateCaption: header.dateCaption,
            title: Text("\(Text(header.greetingLead))\(Text(header.greetingEmphasis).foregroundStyle(NoctisAppColor.blockCocoa))\(Text(header.greetingTrail))"),
            plainTitle: "Home",
            summary: AnyView(HomeHeaderSummary(header: header)),
            trailing: AnyView(HomeAvatarButton(open: actions.openProfile))
        )
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

    private var actions: HomeActions {
        HomeActions(
            openProfile: { model.homePath.append(.profile) },
            openTonight: { model.open(.tonight) },
            openWindDown: { model.open(.windDown(autostart: true)) },
            openRecoveryDetail: { model.homePath.append(.recoveryDetail(focus: $0)) },
            openRecoveryFactor: { model.homePath.append(.recoveryFactor($0, range: .fortnight)) },
            openLastNight: { model.open(.sleep(night: viewModel.lastNightMoment, range: .day)) },
            openWeek: { model.open(.sleep(night: nil, range: .week)) },
            share: { sharing = true },
            openInsight: { model.open(.insight(id: $0)) },
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

/// "Start wind-down" under the evening hero: R10's secondary action (44pt, ink2, no capsule),
/// with an arrow so it reads as a way on and not as a caption.
struct HomeWindDownButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Start wind-down")
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(NoctisAppColor.ink2)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Wind-down.")
        .accessibilityIdentifier("home.windDown")
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
                VStack(alignment: .leading, spacing: 0) {
                    EveningHeroView(content: screen.evening, viewModel: viewModel)
                        .accessibilityRotorEntry(id: HomeSection.tonight, in: rotor)
                    // A secondary action, not a second hero (R10): 44pt, ink2.
                    HomeWindDownButton(action: actions.openWindDown)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            NightPanelView(content: lastNight, open: actions.openLastNight, share: actions.share)
                .accessibilityRotorEntry(id: HomeSection.lastNight, in: rotor)
        }
    }

    @ViewBuilder
    private func blocks(_ screen: HomeScreen) -> some View {
        if let insight = screen.insight {
            InsightBlockView(content: insight, open: { actions.openInsight(insight.id) }, dismiss: actions.dismissInsight, hide: actions.hideInsights)
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
            Button(action: actions.openTonight) {
                TonightBlockView(content: screen.tonight)
            }
            .buttonStyle(NoctisCardButtonStyle())
            .accessibilityHint("Opens Tonight.")
            .accessibilityIdentifier("home.tonightBlock")
            .accessibilityRotorEntry(id: HomeSection.tonight, in: rotor)
            .transition(.opacity)
        }
        if let week = screen.week {
            WeekCardView(content: week, open: actions.openWeek)
                .accessibilityRotorEntry(id: HomeSection.week, in: rotor)
        }
    }
}

// MARK: - Header

/// The field's one-sentence summary, and "Updated 2h ago" once the data is
/// old. Text on the field wears its cocoa inks.
struct HomeHeaderSummary: View {
    let header: HomeHeader

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeSummaryLine(summary: header.summary)
            if let updated = header.updated {
                Text(updated)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
            }
        }
    }
}

/// The 36pt avatar at the field's trailing edge, in a 44pt target.
struct HomeAvatarButton: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Circle()
                .fill(NoctisAppColor.blockInk.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NoctisAppColor.blockInk)
                )
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
        .accessibilityHint("Opens your profile.")
    }
}

/// How much of the evening paper and the morning's dusk lie over Home's
/// paper: what the ring's paper disc must wear to match the page.
struct HomePaperWash: Equatable {
    var evening: Double = 0
    var dusk: Double = 0
}

private struct HomePaperWashKey: EnvironmentKey {
    static let defaultValue = HomePaperWash()
}

extension EnvironmentValues {
    var homePaperWash: HomePaperWash {
        get { self[HomePaperWashKey.self] }
        set { self[HomePaperWashKey.self] = newValue }
    }
}

/// The paper disc under day's ring, where it rides up over the field: the
/// same paper as the page behind it (evening paper and dusk included), so
/// the ring stands on paper. Its own view, so the dusk lifting re-draws
/// only this.
struct HomePaperDisc: View {
    @Environment(\.homePaperWash) private var wash

    var body: some View {
        Circle()
            .fill(NoctisAppColor.bg)
            .overlay(Circle().fill(NoctisAppColor.eveningPaper.opacity(wash.evening)))
            .overlay(Circle().fill(NoctisAppColor.dusk.opacity(wash.dusk)))
            .padding(-TabScreenScaffold<EmptyView>.discMargin)
            .accessibilityHidden(true)
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
    /// The factor's glyph in an icon tile.
    public var symbol: String {
        switch self {
        case .sleepDuration: "moon.zzz.fill"
        case .hrv: "waveform.path.ecg"
        case .restingHeartRate: "heart.fill"
        case .sleepConsistency: "clock.fill"
        }
    }

    /// The factor's color as a line: the fill's own hue, deep enough to read
    /// on a card (butter as a line on white would be 1.6:1).
    public var lineTint: Color {
        switch self {
        case .sleepDuration: NoctisAppColor.sectionSage
        case .hrv: NoctisAppColor.sectionLavender
        case .restingHeartRate: NoctisAppColor.orangeText
        case .sleepConsistency: NoctisAppColor.sectionButter
        }
    }

    /// Sleep sage, HRV lavender, resting HR orange, consistency butter.
    public var tint: Color {
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
    public var ringSegment: NoctisRingSegment {
        NoctisRingSegment(
            color: kind.tint, weight: weight, fraction: fraction, usual: usual,
            arc: NoctisRingArc(startDegrees: arc.startDegrees, endDegrees: arc.endDegrees, tickDegrees: arc.tickDegrees)
        )
    }
}

extension NightLane {
    /// The stage's glyph in an icon tile.
    public var symbol: String {
        switch self {
        case .awake: "eye.fill"
        case .rem: "sparkles"
        case .core: "moon.fill"
        case .deep: "zzz"
        }
    }

    /// On the night panel (and the stacked week bars): Awake butter, REM
    /// sage, Core the lighter core tint, Deep night lavender (cocoa would
    /// vanish on the cocoa panel).
    public var tint: Color {
        switch self {
        case .awake: NoctisAppColor.butter
        case .rem: NoctisAppColor.sage
        case .core: NoctisAppColor.coreTint
        case .deep: NoctisAppColor.nightDeep
        }
    }
}

/// The day ↔ evening morph's timing.
enum HomeMorph {
    /// The paper crossfades over this long.
    static let paperDuration = 1.2
}
