import Foundation
import NoctisCore
import Observation
import SleepKit
#if canImport(UIKit)
import UIKit
#endif

/// Home's view model: holds the latest `HomeSnapshot`, turns it into the
/// `HomeScreen` the views lay out, and decides when to rebuild — on
/// appear, on pull-to-refresh, and whenever Health data changes
/// (`HKObserverQuery` via `HomeRepository.changes()`). Views read `header`
/// and `screen` and nothing else (APP_RULES.md R20).
@Observable
public final class HomeViewModel {
    public private(set) var snapshot: HomeSnapshot?
    /// Nil until the first snapshot arrives (Home shows its skeleton).
    public private(set) var screen: HomeScreen?
    /// Always available, even while loading.
    public private(set) var header: HomeHeader
    public private(set) var isRefreshing = false
    /// The morning reveal (`HomeReveal`): `.pending` while its start state
    /// shows, `.playing` once it runs. Once per calendar day, on the first
    /// day-mode Home; the day is used up even under Reduce Motion, which
    /// never sees it.
    public private(set) var reveal: HomeRevealPhase = .none
    /// Whether the reveal played during this launch (read by UI tests).
    public private(set) var revealPlayed = false
    /// Bumped each time a touch or scroll skips the reveal; Home rebuilds
    /// its content at the end state.
    public private(set) var revealSkips = 0
    /// How far the hero has scrolled away (`HomeCollapse`).
    public private(set) var collapse = HomeCollapse.expanded
    /// "New night added": true for `HomeLiveUpdate.bannerSeconds` after a
    /// Health change brings in a night Home didn't have.
    public private(set) var showsNewNight = false
    /// When the scheduled task will flip Home between day and evening.
    public private(set) var scheduledModeChange: Date?

    private let repository: HomeRepository
    private let profile: () -> UserProfileSnapshot
    private let connectHealth: () async -> Void
    private let introGate: HomeIntroGate
    private let reduceMotion: () -> Bool
    private let clock: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private var modeOverride: HomeMode?
    private var observation: Task<Void, Never>?
    private var modeFlip: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var revealEnd: Task<Void, Never>?

    #if DEBUG
    /// DEBUG: print every new snapshot (`-noctisLogHomeSnapshot`).
    public var debugLogsSnapshots = false
    #endif

    public init(
        repository: HomeRepository,
        profile: @escaping () -> UserProfileSnapshot,
        connectHealth: @escaping () async -> Void = {},
        introGate: HomeIntroGate = HomeIntroGate(),
        reduceMotion: @escaping () -> Bool = { HomeViewModel.systemReduceMotion() },
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        modeOverride: HomeMode? = nil
    ) {
        self.repository = repository
        self.profile = profile
        self.connectHealth = connectHealth
        self.introGate = introGate
        self.reduceMotion = reduceMotion
        self.clock = clock
        self.calendar = calendar
        self.locale = locale
        self.modeOverride = modeOverride
        self.header = HomeScreenBuilder.loadingHeader(
            now: clock(), plan: TonightPlan(profile: profile()), calendar: calendar, locale: locale, modeOverride: modeOverride
        )
        // Start at dusk behind the skeleton when today's reveal is still
        // to come, so the first frame doesn't flash paper.
        if header.mode == .day, !reduceMotion(), !introGate.isClaimed(now: clock(), calendar: calendar) {
            reveal = .pending
        }
    }

    /// Shows the cached snapshot at once, starts watching Health for
    /// changes (once), then rebuilds.
    public func onAppear() async {
        if snapshot == nil, let cached = await repository.cachedSnapshot {
            apply(cached)
        } else {
            updateClock()
        }
        startObserving()
        await refresh()
    }

    /// Pull-to-refresh, "Try again", and every Health change.
    public func refresh() async {
        isRefreshing = true
        apply(await repository.refresh(profile: profile()))
        isRefreshing = false
        #if DEBUG
        if debugLogsSnapshots, let snapshot { print(snapshot.debugSummary) }
        #endif
    }

    /// "Connect Apple Health": onboarding's authorization flow, then a
    /// fresh read.
    public func connectAppleHealth() async {
        await connectHealth()
        await refresh()
    }

    /// Re-reads the clock (mode, greeting, "Updated … ago") — on appear,
    /// on returning to the foreground, and at each mode boundary.
    public func updateClock() {
        updateClock(canReveal: true)
    }

    /// `canReveal`: false when the mode flips while Home is already on
    /// screen (at 4 AM), so the morning reveal waits for the next time
    /// Home appears instead of playing over the morph.
    private func updateClock(canReveal: Bool) {
        if let snapshot {
            apply(snapshot, canReveal: canReveal)
        } else {
            header = HomeScreenBuilder.loadingHeader(
                now: clock(), plan: TonightPlan(profile: profile()), calendar: calendar, locale: locale, modeOverride: modeOverride
            )
        }
    }

    /// Home's content is on screen in its start state: run the reveal.
    public func beginReveal() {
        guard reveal == .pending, screen != nil else { return }
        reveal = .playing
        revealPlayed = true
        revealEnd?.cancel()
        revealEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HomeReveal.totalDuration))
            guard !Task.isCancelled, let self, self.reveal == .playing else { return }
            // Played out: the end state and `.none` look the same.
            self.reveal = .none
        }
    }

    /// A touch or scroll during the reveal: straight to the end state.
    public func skipReveal() {
        guard reveal != .none else { return }
        revealEnd?.cancel()
        reveal = .none
        revealSkips += 1
    }

    /// Scroll collapse: the hero's top and height in the scroll content,
    /// and the top of the visible region (both in points).
    public func scrolled(visibleTop: Double, heroTop: Double, heroHeight: Double) {
        let next = HomeCollapse.state(visibleTop: visibleTop, heroTop: heroTop, heroHeight: heroHeight, previous: collapse)
        if next != collapse { collapse = next }
    }

    /// "Not useful": the insight collapses now and stays away for the
    /// rest of this night.
    public func dismissInsight() {
        guard let insight = snapshot?.topInsight else { return }
        dropInsight()
        Task { _ = await repository.dismiss(insight) }
    }

    /// "Hide insights like this": this kind never shows again.
    public func hideInsights() {
        guard let insight = snapshot?.topInsight else { return }
        dropInsight()
        Task { _ = await repository.hide(insight) }
    }

    private func dropInsight() {
        guard let snapshot else { return }
        apply(snapshot.replacingInsight(nil))
    }

    #if DEBUG
    /// DEBUG `-homeModeFlipIn <seconds>`: flip day ↔ evening once, after
    /// `seconds`, to show the mode morph on demand.
    public func debugFlipMode(after seconds: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            self.modeOverride = self.header.mode == .day ? .evening : .day
            self.updateClock(canReveal: false)
        }
    }
    #endif

    public static func systemReduceMotion() -> Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }

    /// Stops watching Health and the mode clock (tests and teardown).
    public func stopObserving() {
        observation?.cancel()
        observation = nil
        modeFlip?.cancel()
        modeFlip = nil
        bannerTask?.cancel()
        bannerTask = nil
    }

    private func apply(_ snapshot: HomeSnapshot, canReveal: Bool = true) {
        self.snapshot = snapshot
        let screen = HomeScreenBuilder.build(snapshot, now: clock(), calendar: calendar, locale: locale, modeOverride: modeOverride)
        updateReveal(for: screen, canReveal: canReveal)
        self.screen = screen
        header = screen.header
        scheduleModeFlip(at: screen.nextModeChange)
    }

    /// The first day-mode Home of each calendar day uses up the day's
    /// reveal; it plays only with a score to reveal and without Reduce
    /// Motion.
    private func updateReveal(for screen: HomeScreen, canReveal: Bool) {
        guard canReveal, screen.mode == .day, introGate.claim(now: clock(), calendar: calendar) else {
            if reveal == .pending { reveal = .none }
            return
        }
        let scored = if case .scored = screen.recovery { true } else { false }
        reveal = scored && !reduceMotion() ? .pending : .none
    }

    /// A Health change that brings a night Home didn't have shows "New
    /// night added" for a moment.
    private func noteLiveUpdate(from before: SleepNightKey?) {
        guard let after = snapshot?.lastNight?.night, after != before else { return }
        showsNewNight = true
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HomeLiveUpdate.bannerSeconds))
            guard !Task.isCancelled else { return }
            self?.showsNewNight = false
        }
    }

    /// One task, replaced on every rebuild, that wakes at the next mode
    /// boundary and rebuilds while the app is open.
    private func scheduleModeFlip(at date: Date) {
        guard modeOverride == nil, scheduledModeChange != date else { return }
        modeFlip?.cancel()
        scheduledModeChange = date
        let delay = max(date.timeIntervalSince(clock()), 0)
        modeFlip = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay + 0.5))
            guard !Task.isCancelled, let self else { return }
            self.scheduledModeChange = nil
            self.updateClock(canReveal: false)
        }
    }

    private func startObserving() {
        guard observation == nil else { return }
        observation = Task { [weak self, repository] in
            for await _ in await repository.changes() {
                guard let self else { return }
                let before = self.snapshot?.lastNight?.night
                let hadSnapshot = self.snapshot != nil
                await self.refresh()
                if hadSnapshot { self.noteLiveUpdate(from: before) }
            }
        }
    }
}

/// Remembers the day Home's ring last drew itself in, so it happens once
/// a day. Stored under `noctis.` so `-noctisResetState` clears it.
public final class HomeIntroGate {
    public static let defaultsKey = "noctis.home.lastIntroDay"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func claim(now: Date, calendar: Calendar) -> Bool {
        guard !isClaimed(now: now, calendar: calendar) else { return false }
        defaults.set(Self.key(now, calendar), forKey: Self.defaultsKey)
        return true
    }

    /// Whether today's reveal is already used up, without using it.
    public func isClaimed(now: Date, calendar: Calendar) -> Bool {
        defaults.string(forKey: Self.defaultsKey) == Self.key(now, calendar)
    }

    private static func key(_ now: Date, _ calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }
}

/// The morning reveal's phases.
public nonisolated enum HomeRevealPhase: Sendable, Equatable {
    /// Nothing to play: everything shows its end state.
    case none
    /// Start state: dusk background, empty ring, bars not drawn yet.
    case pending
    /// Running (and, once finished, still `.playing` until the next launch).
    case playing
}

/// The reveal's timing (seconds).
public nonisolated enum HomeReveal {
    /// Dusk crossfades to paper first…
    public static let backgroundDuration = 1.2
    /// …then the ring fills (the score lands with a medium haptic)…
    public static let ringDuration = 0.9
    /// …the factor capsules rise, one after another…
    public static let capsuleStagger = 0.06
    /// …the night panel's bars draw left to right…
    public static let nightDuration = 0.8
    /// …and This week's bars grow, one after another.
    public static let weekStagger = 0.04
    /// The capsules' rise, in points (R9).
    public static let rise: Double = 12
    /// From the dusk starting to lift to the last bar landing (and the
    /// score's haptic), with a little room.
    public static var totalDuration: Double {
        backgroundDuration + max(ringDuration, nightDuration, capsuleStagger * 3 + 0.5, weekStagger * 6 + 0.5) + 0.4
    }
}

/// Scroll collapse: the hero shrinks (1.0 → 0.85) and fades as it scrolls
/// away; at 70% scrolled past, the compact bar appears, and it goes again
/// below 65% so it can't flicker at the line.
public nonisolated struct HomeCollapse: Sendable, Equatable {
    /// How much of the hero has scrolled past the top, 0...1, in steps of
    /// 1% (finer steps don't change a pixel).
    public let progress: Double
    public let showsBar: Bool

    public static let expanded = HomeCollapse(progress: 0, showsBar: false)
    public static let minimumScale = 0.85
    public static let barShowsAt = 0.7
    public static let barHidesBelow = 0.65

    public var heroScale: Double { 1 - (1 - Self.minimumScale) * progress }
    public var heroOpacity: Double { 1 - progress }

    public static func state(visibleTop: Double, heroTop: Double, heroHeight: Double, previous: HomeCollapse) -> HomeCollapse {
        guard heroHeight > 0 else { return .expanded }
        let raw = min(max((visibleTop - heroTop) / heroHeight, 0), 1)
        let progress = (raw * 100).rounded() / 100
        let showsBar = previous.showsBar ? progress >= barHidesBelow : progress >= barShowsAt
        return HomeCollapse(progress: progress, showsBar: showsBar)
    }
}

public nonisolated enum HomeLiveUpdate {
    /// How long "New night added" stays.
    public static let bannerSeconds = 2.0
}
