import DesignSystem
import NoctisCore
import SwiftUI

/// What floats over the top of Home: the compact bar once the hero has
/// scrolled 70% away, and "New night added" when Health delivers a night.
struct HomeTopOverlay: View {
    let viewModel: HomeViewModel
    let scrollToTop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if DEBUG
        let _ = HomeBodyProbe.hit("HomeTopOverlay")
        #endif
        VStack(spacing: NoctisSpacing.xs) {
            if viewModel.showsCollapsedBar, let screen = viewModel.screen, HomeCollapsedBar.shows(for: screen) {
                HomeCollapsedBar(screen: screen, action: scrollToTop)
                    .transition(.opacity)
            }
            if viewModel.showsNewNight {
                NewNightPill()
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion), value: viewModel.showsCollapsedBar)
        .animation(NoctisMotion.adaptive(NoctisMotion.settle, reduceMotion: reduceMotion), value: viewModel.showsNewNight)
    }
}

/// The hero, compact, pinned under the status bar: a 28pt ring, the score
/// and "Recovery" by day; a moon and "Bedtime 11:00 PM · in 2h 14m" in the
/// evening. Tapping it springs back to the top.
struct HomeCollapsedBar: View {
    let screen: HomeScreen
    let action: () -> Void
    @Environment(\.homeClock) private var clock
    private var now: Date { clock?.minute ?? .now }

    static let ringDiameter: CGFloat = 28

    /// By day the bar needs a score to show.
    static func shows(for screen: HomeScreen) -> Bool {
        if screen.mode == .evening { return true }
        if case .scored = screen.recovery { return true }
        return false
    }

    var body: some View {
        TabCompactBar(
            paper: paper,
            label: label,
            identifier: "home.collapsedBar",
            maxWidth: HomeContent.compactMaxWidth,
            action: action
        ) {
            // The same leading glyph as every tab's bar, in Home's apricot.
            Image(systemName: NoctisSection.home.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NoctisSection.home.ink)
                .accessibilityHidden(true)
            content
        }
    }

    /// The page's paper: the evening paper in evening mode.
    private var paper: Color {
        screen.mode == .evening ? NoctisAppColor.eveningPaper : NoctisAppColor.bg
    }

    @ViewBuilder
    private var content: some View {
        switch screen.mode {
        case .day:
            if case .scored(let scored) = screen.recovery {
                NoctisRecoveryRing(
                    segments: scored.segments.map(\.ringSegment),
                    diameter: Self.ringDiameter,
                    lineWidth: 4
                )
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
                Text("\(scored.score)")
                    .noctisFont(17, .bold, relativeTo: .body)
                    .monospacedDigit()
                    .foregroundStyle(NoctisAppColor.ink)
                Text("Recovery")
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
            }
        case .evening:
            BedtimeMoon()
            Text(screen.evening.times.status(at: now))
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .monospacedDigit()
                .foregroundStyle(NoctisAppColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var label: String {
        switch screen.mode {
        case .day:
            if case .scored(let scored) = screen.recovery { return "Recovery \(scored.score)" }
            return "Recovery"
        case .evening:
            let times = screen.evening.times
            return times.countdownMetric(at: now).map { "Bedtime \(times.bedtimeText), in \($0.spoken)" } ?? times.passedText
        }
    }
}

/// Matches `NoctisStatusBarScrim`'s fade.
enum NoctisStatusBarScrimMetrics {
    static let fadeHeight: CGFloat = 16
}

/// Slides down under the top for two seconds when a Health change brings
/// a new night; VoiceOver hears it too.
struct NewNightPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text("New night added")
                .noctisFont(13, .semibold, relativeTo: .footnote)
        }
        .foregroundStyle(NoctisAppColor.ink)
        .padding(.horizontal, NoctisSpacing.sm)
        .padding(.vertical, NoctisSpacing.xs)
        .background(NoctisAppColor.surface, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
        .shadow(color: NoctisPaper.cocoa.opacity(0.06), radius: 24, x: 0, y: 8)
        .padding(.top, NoctisSpacing.xs)
        .onAppear {
            AccessibilityNotification.Announcement("New night added").post()
        }
    }
}

/// The evening moon, drawing itself on as it arrives (none under Reduce
/// Motion).
struct BedtimeMoon: View {
    var size: CGFloat = 15
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeLowPower) private var lowPower
    @State private var shown = false

    var body: some View {
        ZStack {
            if shown || reduceMotion || lowPower {
                Image(systemName: "moon.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(NoctisAppColor.lavenderText)
                    .transition(.symbolEffect(.drawOn))
            }
        }
        .frame(width: size + 6, height: size + 6)
        .accessibilityHidden(true)
        .task {
            guard !shown, !reduceMotion, !lowPower else { return }
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation { shown = true }
        }
    }
}

/// The tab bar accessory in the evening, on every tab: a moon and
/// "Bedtime 11:00 PM · in 2h 14m". Tapping it goes to Home.
public struct HomeBedtimeAccessory: View {
    private let viewModel: HomeViewModel
    private let clock: HomeClock
    private let openHome: () -> Void

    /// The accessory is built in the tab bar's own hierarchy, so it takes
    /// the clock directly and reads the minute in its own `body`.
    public init(viewModel: HomeViewModel, clock: HomeClock, openHome: @escaping () -> Void) {
        self.viewModel = viewModel
        self.clock = clock
        self.openHome = openHome
    }

    public var body: some View {
        Button(action: openHome) {
            HStack(spacing: NoctisSpacing.xs) {
                BedtimeMoon()
                Text(status)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .monospacedDigit()
                    .foregroundStyle(NoctisAppColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, NoctisSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status)
        .accessibilityHint("Opens Home.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.bedtimeAccessory")
    }

    private var status: String {
        guard case .bedtime(let times) = viewModel.header.summary else { return "" }
        return times.status(at: clock.minute)
    }

    /// Whether the accessory shows: evening only.
    public static func isShown(for viewModel: HomeViewModel) -> Bool {
        viewModel.header.mode == .evening
    }
}
