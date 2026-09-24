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

/// Where Home's sections send the person.
struct HomeActions {
    var openProfile: () -> Void = {}
    /// Recovery detail, optionally scrolled to one factor.
    var openRecoveryDetail: (RecoveryFactorKind?) -> Void = { _ in }
    var openSleep: () -> Void = {}
}

/// "How am I today?" — one top-aligned scroll on the paper. Reads only
/// `HomeViewModel.header` and `.screen` (APP_RULES.md R20).
struct HomeView: View {
    static let recoveryZoomID = "recovery"

    let viewModel: HomeViewModel
    let zoomNamespace: Namespace.ID

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            HomeContent(
                viewModel: viewModel,
                zoomNamespace: zoomNamespace,
                actions: HomeActions(
                    openProfile: { model.homePath.append(.profile) },
                    openRecoveryDetail: { model.homePath.append(.recoveryDetail(focus: $0)) },
                    openSleep: { model.open(.sleep) }
                )
            )
        }
        // R14: cards keep their shadows at the scroll view's edges.
        .scrollClipDisabled()
        // Nothing may show behind the status bar.
        .noctisStatusBarGuard()
        // Paper plus the 3% grain, in both modes.
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.onAppear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.updateClock() }
        }
        .navigationTitle("Home")
        .toolbar(.hidden, for: .navigationBar)
    }
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

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        // R12: one TimelineView, and only in evening mode, where the
        // countdown, the summary and the strip's "now" marker move.
        if viewModel.header.mode == .evening {
            TimelineView(.everyMinute) { context in
                page(now: context.date)
            }
        } else {
            page(now: nil)
        }
    }

    private func page(now: Date?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeHeaderView(header: viewModel.header, now: now, openProfile: actions.openProfile)
            // R6: content starts 24pt below the title.
            Color.clear.frame(height: NoctisSpacing.xl)
            if let screen = viewModel.screen {
                sections(screen, now: now)
            } else {
                HomeSkeletonView(columns: isRegular ? 2 : 1)
            }
        }
        .frame(maxWidth: isRegular ? Self.regularMaxWidth : Self.compactMaxWidth)
        .padding(.horizontal, NoctisSpacing.lg)
        .padding(.top, NoctisSpacing.xs)
        .padding(.bottom, NoctisSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sections(_ screen: HomeScreen, now: Date?) -> some View {
        if isRegular {
            HStack(alignment: .top, spacing: NoctisSpacing.md) {
                VStack(spacing: 0) {
                    hero(screen, now: now)
                    Color.clear.frame(height: Self.heroSpacing)
                    VStack(spacing: NoctisSpacing.md) { leadSections(screen) }
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: NoctisSpacing.md) { blocks(screen) }
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                hero(screen, now: now)
                Color.clear.frame(height: Self.heroSpacing)
                VStack(spacing: NoctisSpacing.md) {
                    leadSections(screen)
                    blocks(screen)
                }
            }
        }
    }

    @ViewBuilder
    private func hero(_ screen: HomeScreen, now: Date?) -> some View {
        switch screen.mode {
        case .day:
            DayHeroView(content: screen.recovery, viewModel: viewModel, zoomNamespace: zoomNamespace, openDetail: actions.openRecoveryDetail)
        case .evening:
            EveningHeroView(content: screen.evening, now: now ?? screen.evening.times.windowStart)
        }
    }

    /// Evening's compact Recovery card, then the night panel.
    @ViewBuilder
    private func leadSections(_ screen: HomeScreen) -> some View {
        if screen.mode == .evening {
            CompactRecoveryCard(content: screen.recovery, viewModel: viewModel, zoomNamespace: zoomNamespace, openDetail: actions.openRecoveryDetail)
        }
        if let lastNight = screen.lastNight {
            NightPanelView(content: lastNight, open: actions.openSleep)
        }
    }

    @ViewBuilder
    private func blocks(_ screen: HomeScreen) -> some View {
        if let insight = screen.insight {
            InsightBlockView(content: insight)
        }
        if screen.mode == .day {
            TonightBlockView(content: screen.tonight)
        }
        if let week = screen.week {
            WeekCardView(content: week, open: actions.openSleep)
        }
    }
}

// MARK: - Header

/// Date caption, greeting, one-sentence summary and the avatar.
struct HomeHeaderView: View {
    let header: HomeHeader
    let now: Date?
    let openProfile: () -> Void

    private var emphasis: Color {
        header.mode == .evening ? NoctisAppColor.lavenderText : NoctisAppColor.orangeText
    }

    var body: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                NoctisCaption(header.dateCaption, color: NoctisAppColor.ink3)
                Text("\(Text(header.greetingLead))\(Text(header.greetingEmphasis).foregroundStyle(emphasis))\(Text(header.greetingTrail))")
                    .noctisFont(34, .bold, relativeTo: .largeTitle)
                    .tracking(-0.6)
                    .foregroundStyle(NoctisAppColor.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(header.summary.text(at: now ?? .now))
                    .noctisFont(17, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let updated = header.updated {
                    Text(updated)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisAppColor.ink3)
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
struct NoctisCaption: View {
    let text: String
    let color: Color

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .tracking(13 * 0.08)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Loading

/// Skeleton blocks in the track color while the first snapshot loads: a
/// ring where the hero goes, then sections; a slow pulse, none under
/// Reduce Motion.
struct HomeSkeletonView: View {
    var columns = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Group {
            if columns > 1 {
                HStack(alignment: .top, spacing: NoctisSpacing.md) {
                    VStack(spacing: HomeContent.heroSpacing) {
                        heroBlock
                        block(height: 240)
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
                        block(height: 240)
                        block(height: 110)
                    }
                }
            }
        }
        .opacity(dimmed ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your sleep data")
    }

    private var heroBlock: some View {
        VStack(spacing: NoctisSpacing.md) {
            NoctisRingLayout(maxDiameter: 220) {
                Circle().strokeBorder(NoctisAppColor.track, lineWidth: 22)
            }
            Capsule().fill(NoctisAppColor.track).frame(width: 160, height: 14)
            Capsule().fill(NoctisAppColor.track).frame(height: 64)
        }
        .frame(maxWidth: .infinity)
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

extension NightLane {
    /// On the night panel: Awake butter, REM sage, Core orange, Deep
    /// lavender (cocoa would vanish on the cocoa panel).
    var tint: Color {
        switch self {
        case .awake: NoctisAppColor.butter
        case .rem: NoctisAppColor.sage
        case .core: NoctisAppColor.orange
        case .deep: NoctisAppColor.lavender
        }
    }
}
