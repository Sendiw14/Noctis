import DesignSystem
import Foundation
import NoctisCore
import Observation
import SwiftUI
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
    /// Noon of the evening the last night began: a moment of that night,
    /// for opening it in Sleep. Nil without a last night.
    public var lastNightMoment: Date? {
        guard let key = snapshot?.lastNight?.night else { return nil }
        return calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day, hour: 12))
    }
    /// Nil until the first snapshot arrives (Home shows its skeleton).
    public private(set) var screen: HomeScreen?
    /// Always available, even while loading.
    public private(set) var header: HomeHeader
    public private(set) var isRefreshing = false
    /// How the color field arrives the first time Home is shown.
    public private(set) var fieldEntrance: NoctisFieldEntrance = .none
    /// The key of Home's once-a-day field wash.
    public static let washKey = "noctis.home.lastWashDay"
    /// The morning reveal (`HomeReveal`): `.pending` while its start state
    /// shows, `.playing` once it runs. Once per calendar day, on the first
    /// day-mode Home; the day is used up even under Reduce Motion, which
    /// never sees it.
    public private(set) var reveal: HomeRevealPhase = .none
    /// The field has arrived: today's wash is spent.
    public func fieldEntered() {
        _ = washGate.claim(now: clock(), calendar: calendar)
        fieldEntrance = .none
    }

    /// Whether the reveal played during this launch (read by UI tests).
    public private(set) var revealPlayed = false
    /// Low Power Mode is on: Home skips the score's count-up, the
    /// capsules' and bars' staggers and its ambient animations, and keeps
    /// every end state. (Reduce Motion is separate and unchanged.)
    public private(set) var isLowPower: Bool
    /// Bumped each time a touch or scroll skips the reveal; Home rebuilds
    /// its content at the end state.
    public private(set) var revealSkips = 0
    /// How far the hero has scrolled away, 0...1 in steps of 1%
    /// (`HomeCollapse`). Only the hero's own effect reads this.
    public private(set) var collapseProgress = 0.0
    /// Whether the compact bar shows. Kept apart from the progress, so the
    /// overlay that reads it isn't re-evaluated at every step of a scroll.
    public private(set) var showsCollapsedBar = false
    public var collapse: HomeCollapse { HomeCollapse(progress: collapseProgress, showsBar: showsCollapsedBar) }
    /// "New night added": true for `HomeLiveUpdate.bannerSeconds` after a
    /// Health change brings in a night Home didn't have.
    public private(set) var showsNewNight = false
    /// When the scheduled task will flip Home between day and evening.
    public private(set) var scheduledModeChange: Date?
    /// A screen drawn from the last launch's saved snapshot is up and
    /// Health hasn't answered yet: the morning reveal waits, so it never
    /// plays yesterday's numbers. Clears when fresh data arrives, or after
    /// `restoreGrace`.
    public private(set) var awaitsFreshData = false
    /// How long the reveal waits for fresh data before playing with the
    /// restored screen.
    public static let restoreGrace = 1.5

    private let repository: HomeRepository
    private let profile: () -> UserProfileSnapshot
    private let connectHealth: () async -> Void
    private let introGate: HomeIntroGate
    private let washGate: HomeIntroGate
    private let reduceMotion: () -> Bool
    private let lowPower: () -> Bool
    private let clock: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private var modeOverride: HomeMode?
    /// Whether the day's reveal has been decided (played, skipped, or
    /// already used up) by a screen with a score.
    private var revealDecided = false
    /// The first fresh snapshot after a restored one cross-fades in.
    private var revalidatingRestored = false
    private var observation: Task<Void, Never>?
    private var powerObservation: Task<Void, Never>?
    private var modeFlip: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var revealEnd: Task<Void, Never>?
    /// Waits out the reveal (tests hold it, so a slow run can't end it early).
    private let revealSleep: @Sendable (Double) async -> Void

    #if DEBUG
    /// DEBUG: print every new snapshot (`-noctisLogHomeSnapshot`).
    public var debugLogsSnapshots = false
    #endif

    public init(
        repository: HomeRepository,
        profile: @escaping () -> UserProfileSnapshot,
        connectHealth: @escaping () async -> Void = {},
        introGate: HomeIntroGate = HomeIntroGate(),
        washGate: HomeIntroGate = HomeIntroGate(key: HomeViewModel.washKey),
        reduceMotion: @escaping () -> Bool = { HomeViewModel.systemReduceMotion() },
        lowPower: @escaping () -> Bool = { HomeViewModel.systemLowPower() },
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        modeOverride: HomeMode? = nil,
        revealSleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.revealSleep = revealSleep
        self.repository = repository
        self.profile = profile
        self.connectHealth = connectHealth
        self.introGate = introGate
        self.washGate = washGate
        self.reduceMotion = reduceMotion
        self.lowPower = lowPower
        isLowPower = lowPower()
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
        // The field's arrival: the morning reveal's dusk lifting off it is
        // Home's own wash; otherwise the tab-entry wash once a day, then a
        // fade (the same as every tab).
        fieldEntrance = reveal == .pending ? .none : (washGate.isClaimed(now: clock(), calendar: calendar) ? .fade : .wash)
        // The last launch's snapshot, before the first frame: Home opens
        // with content, then revalidates in the background.
        if let restored = repository.restoredSnapshot {
            apply(restored)
            revalidatingRestored = true
            if reveal == .pending {
                awaitsFreshData = true
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Self.restoreGrace))
                    self?.awaitsFreshData = false
                }
            }
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
        let fresh = await repository.refresh(profile: profile())
        if revalidatingRestored {
            // What changed since the saved snapshot fades in; what
            // didn't stays put.
            revalidatingRestored = false
            awaitsFreshData = false
            withAnimation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion())) { apply(fresh) }
        } else {
            apply(fresh)
        }
        isRefreshing = false
        // The first fresh answer is when launch counts as populated.
        NoctisSignpost.end(.launchToPopulated)
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
        guard reveal == .pending, screen != nil, !awaitsFreshData else { return }
        reveal = .playing
        revealPlayed = true
        NoctisSignpost.begin(.reveal)
        revealEnd?.cancel()
        revealEnd = Task { [weak self] in
            await self?.revealSleep(HomeReveal.totalDuration)
            guard !Task.isCancelled, let self, self.reveal == .playing else { return }
            // Played out: the end state and `.none` look the same.
            self.reveal = .none
            NoctisSignpost.end(.reveal)
        }
    }

    /// A touch or scroll during the reveal: straight to the end state.
    public func skipReveal() {
        guard reveal != .none else { return }
        revealEnd?.cancel()
        reveal = .none
        revealSkips += 1
        NoctisSignpost.end(.reveal)
    }

    /// Scroll collapse: the hero's top and height in the scroll content,
    /// and the top of the visible region (both in points).
    public func scrolled(visibleTop: Double, heroTop: Double, heroHeight: Double) {
        let next = HomeCollapse.state(visibleTop: visibleTop, heroTop: heroTop, heroHeight: heroHeight, previous: collapse)
        // Written only when a derived value changes: a 1% step, or the
        // bar crossing its threshold.
        if next.progress != collapseProgress { collapseProgress = next.progress }
        if next.showsBar != showsCollapsedBar { showsCollapsedBar = next.showsBar }
    }

    /// "Not useful": the insight collapses now and stays away for the
    /// rest of this night.
    public func dismissInsight() {
        guard let insight = snapshot?.topInsight else { return }
        dropInsight()
        Task { _ = await repository.dismiss(id: insight.id) }
    }

    /// "Hide insights like this": this kind never shows again.
    public func hideInsights() {
        guard let insight = snapshot?.topInsight else { return }
        dropInsight()
        Task { _ = await repository.hide(insight.type) }
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

    #if DEBUG
    /// DEBUG `-noctisLowPowerMode`: the simulator can't switch Low Power
    /// Mode on, so this pretends it is.
    public nonisolated(unsafe) static var debugForcesLowPower = false
    #endif

    public static func systemLowPower() -> Bool {
        #if DEBUG
        if debugForcesLowPower { return true }
        #endif
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }

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
        powerObservation?.cancel()
        powerObservation = nil
        modeFlip?.cancel()
        modeFlip = nil
        bannerTask?.cancel()
        bannerTask = nil
    }

    private func apply(_ snapshot: HomeSnapshot, canReveal: Bool = true) {
        if self.snapshot != snapshot { self.snapshot = snapshot }
        let screen = HomeScreenBuilder.build(snapshot, now: clock(), calendar: calendar, locale: locale, modeOverride: modeOverride)
        updateReveal(for: screen, canReveal: canReveal)
        // Equal values aren't republished: a rebuild that changes nothing
        // (returning to the foreground, a refresh with the same data)
        // re-evaluates no view.
        if let before = self.screen?.mode, before != screen.mode {
            // The day ↔ evening morph runs until the paper has crossfaded.
            NoctisSignpost.begin(.morph)
            Task {
                try? await Task.sleep(for: .seconds(HomeMorph.paperDuration + 0.2))
                NoctisSignpost.end(.morph)
            }
        }
        if self.screen != screen { self.screen = screen }
        if header != screen.header { header = screen.header }
        scheduleModeFlip(at: screen.nextModeChange)
    }

    /// The first day-mode Home with a score each calendar day uses up the
    /// day's reveal; it plays without Reduce Motion (which never sees it,
    /// but still uses the day up). A screen with no score to reveal (still
    /// learning, no data yet) decides nothing: the reveal waits for the
    /// score, so cached or partial data never spends it.
    private func updateReveal(for screen: HomeScreen, canReveal: Bool) {
        guard canReveal, screen.mode == .day else {
            if reveal == .pending { reveal = .none }
            return
        }
        guard !revealDecided else { return }
        guard case .scored = screen.recovery else {
            // Nothing to reveal yet. A restored screen keeps waiting for
            // fresh data; a fresh one has none coming.
            if reveal == .pending, !awaitsFreshData { reveal = .none }
            return
        }
        revealDecided = true
        guard introGate.claim(now: clock(), calendar: calendar) else {
            if reveal == .pending { reveal = .none }
            return
        }
        reveal = reduceMotion() ? .none : .pending
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
        if powerObservation == nil {
            // Low Power Mode comes and goes while the app is open.
            powerObservation = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                    guard let self else { return }
                    let now = self.lowPower()
                    if now != self.isLowPower { self.isLowPower = now }
                }
            }
        }
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
    private let key: String

    /// `key` names the tab whose reveal this gates ("noctis.<tab>.lastIntroDay"):
    /// each tab plays its reveal once per calendar day.
    public init(defaults: UserDefaults = NoctisUserDefaults.standard, key: String = HomeIntroGate.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func claim(now: Date, calendar: Calendar) -> Bool {
        guard !isClaimed(now: now, calendar: calendar) else { return false }
        defaults.set(Self.key(now, calendar), forKey: key)
        return true
    }

    /// Whether today's reveal is already used up, without using it.
    public func isClaimed(now: Date, calendar: Calendar) -> Bool {
        defaults.string(forKey: key) == Self.key(now, calendar)
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
    /// Where a factor capsule starts in the reveal, after the content's
    /// delay. Low Power Mode drops the stagger: they rise together.
    public static func capsuleDelay(_ index: Int, lowPower: Bool) -> Double {
        lowPower ? 0 : capsuleStagger * Double(index)
    }

    /// Where a week bar starts growing. Low Power Mode: all at once.
    public static func weekDelay(_ index: Int, lowPower: Bool) -> Double {
        lowPower ? 0 : weekStagger * Double(index)
    }

    /// Whether the score counts up with the ring. Low Power Mode shows the
    /// score (its end state) from the start.
    public static func countsUp(lowPower: Bool) -> Bool { !lowPower }

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

    public var heroScale: Double { Self.scale(at: progress) }
    public var heroOpacity: Double { Self.opacity(at: progress) }

    public static func scale(at progress: Double) -> Double { 1 - (1 - minimumScale) * progress }
    public static func opacity(at progress: Double) -> Double { 1 - progress }

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
