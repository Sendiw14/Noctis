import DesignSystem
import Foundation
import HomeFeature
import NoctisCore
import Observation
import SleepKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The Sleep tab's view model: holds the latest `SleepSnapshot`, the
/// selection (a night and Day, Week or Month), the render model for that
/// selection and the `SleepScreen` the views lay out, and decides when to
/// rebuild: on appear, on pull-to-refresh, when Health data changes and
/// when the selection moves. Views read `screen` and nothing else
/// (APP_RULES.md R20).
@Observable
public final class SleepViewModel {
    public private(set) var snapshot: SleepSnapshot?
    /// Nil until the first snapshot arrives (the tab shows its skeleton).
    public private(set) var screen: SleepScreen?
    public private(set) var model: SleepRenderModel?
    /// The picker's selection; moves at once, before the content follows.
    public private(set) var selection: SleepSelection?
    public private(set) var isRefreshing = false
    /// The day's reveal for this tab (`HomeRevealPhase`, shared): the
    /// ribbon draws left to right, the ring fills and the numbers count up.
    public private(set) var reveal: HomeRevealPhase = .none
    /// How the tab's color field arrives the first time it's shown.
    public private(set) var fieldEntrance: NoctisFieldEntrance = .none
    /// Bumped each time a touch or scroll skips the reveal.
    public private(set) var revealSkips = 0
    public private(set) var revealPlayed = false
    /// Low Power Mode: no count-up (the end state shows at once).
    public private(set) var isLowPower: Bool
    /// A detail sheet (Balance, Consistency, Timing) is open.
    public var detail: SleepDetail?
    /// The bar picked in a week's or a month's chart (by the scrub, a tap or
    /// the summary strip's longest and shortest); another range or night
    /// clears it.
    public var selectedBar: Int?

    private let repository: SleepRepository
    private let profile: () -> UserProfileSnapshot
    private let connectHealth: () async -> Void
    private let introGate: HomeIntroGate
    private let washGate: HomeIntroGate
    private let reduceMotion: () -> Bool
    private let lowPower: () -> Bool
    private let clock: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    /// Whether a feature is shown in full: the feature table's answer (R57, R59), and open with no gate (a test that does not care).
    private let isUnlocked: (Feature) -> Bool
    private var observation: Task<Void, Never>?
    private var revealEnd: Task<Void, Never>?
    private var isVisible = false
    private var revealDecided = false
    private var announcedHighlights: Set<String> = []
    /// Whether the selection is on the newest night, and stays on it when
    /// a newer one arrives.
    private var followsLatest = true
    /// A deep link that arrived before the first snapshot.
    private var requested: (night: SleepNightKey?, range: SleepRange)?

    /// The key of this tab's once-a-day reveal.
    public static let introKey = "noctis.sleep.lastIntroDay"
    /// The key of this tab's once-a-day field wash.
    public static let washKey = "noctis.sleep.lastWashDay"
    /// How long the reveal takes, start to end.
    public static let revealDuration = 1.6

    public init(
        repository: SleepRepository,
        profile: @escaping () -> UserProfileSnapshot,
        connectHealth: @escaping () async -> Void = {},
        introGate: HomeIntroGate = HomeIntroGate(key: SleepViewModel.introKey),
        washGate: HomeIntroGate = HomeIntroGate(key: SleepViewModel.washKey),
        reduceMotion: @escaping () -> Bool = { HomeViewModel.systemReduceMotion() },
        lowPower: @escaping () -> Bool = { HomeViewModel.systemLowPower() },
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        isUnlocked: @escaping (Feature) -> Bool = { _ in true }
    ) {
        self.isUnlocked = isUnlocked
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
        // The color wash plays once per tab per day (the first time the tab
        // is shown); after that the field just fades in.
        fieldEntrance = washGate.isClaimed(now: clock(), calendar: calendar) ? .fade : .wash
    }

    /// The field has arrived: today's wash is spent.
    public func fieldEntered() {
        _ = washGate.claim(now: clock(), calendar: calendar)
        fieldEntrance = .none
    }

    // MARK: Lifecycle

    /// The tab is on screen: shows the cached snapshot at once, starts
    /// watching Health (once), then rebuilds.
    public func onAppear() async {
        isVisible = true
        if snapshot == nil, let cached = await repository.cachedSnapshot {
            await apply(cached)
        } else {
            updateReveal()
        }
        startObserving()
        await refresh()
    }

    public func onDisappear() {
        isVisible = false
    }

    /// Pull-to-refresh, "Try again", and every Health change.
    public func refresh() async {
        isRefreshing = true
        await apply(await repository.refresh(profile: profile()))
        isRefreshing = false
    }

    /// "Connect Apple Health": onboarding's authorization flow, then a
    /// fresh read.
    public func connectAppleHealth() async {
        await connectHealth()
        await refresh()
    }

    // MARK: Selection

    /// The Premium feature a range needs while it is locked: Month (Day and Week are free). Nil when it can be shown.
    public func lockedFeature(for range: SleepRange) -> Feature? {
        range == .month && !isUnlocked(.sleepMonth) ? .sleepMonth : nil
    }

    /// The nights a free person can open: the newest three. Any older night in the picker is Premium (nights 4 to 14).
    public func lockedFeature(forNight night: SleepNightKey) -> Feature? {
        guard !isUnlocked(.sleepNightPicker14), let snapshot else { return nil }
        let free = snapshot.nights(endingAt: snapshot.defaultNight, count: 3).map(\.night)
        return free.contains(night) || night > snapshot.defaultNight ? nil : .sleepNightPicker14
    }

    /// Whether the quality card shows the four factors and "What changed?" (Premium), or the score alone.
    public var showsQualityFactors: Bool { isUnlocked(.sleepQualityFactors) }

    /// Whether Week's Consistency, Balance and Timing cards open their detail sheets (Premium).
    public var opensDetailSheets: Bool { isUnlocked(.sleepConsistencyBalanceTimingDetails) }

    /// What a selection may be for this tier: a locked range falls back to Week, a locked night to the newest.
    private func allowed(_ wanted: SleepSelection, in snapshot: SleepSnapshot) -> SleepSelection {
        var result = wanted
        if lockedFeature(for: result.range) != nil { result.range = .week }
        if lockedFeature(forNight: result.night) != nil { result.night = snapshot.defaultNight }
        return result
    }

    /// A change of tier (a lapse, or a purchase): a locked range or night that was open goes back to what is free.
    public func tierChanged() {
        guard let snapshot, let current = selection else { return }
        let next = allowed(current, in: snapshot)
        if next != current { move(to: next) }
    }

    /// Chooses a night (Day) or the night a week or month ends on.
    public func select(night: SleepNightKey) {
        guard lockedFeature(forNight: night) == nil else { return }
        guard var next = selection, next.night != night else { return }
        next.night = night
        move(to: next)
    }

    public func select(range: SleepRange) {
        guard lockedFeature(for: range) == nil else { return }
        guard var next = selection, next.range != range else { return }
        next.range = range
        move(to: next)
    }

    /// A deep link's destination (`AppRoute.sleep`): the night containing
    /// `destination.night` (the newest when nil) on its range.
    public func open(_ destination: SleepDestination) {
        open(night: destination.night.map { SleepNightKey(containing: $0, in: calendar.timeZone) }, range: destination.range)
    }

    /// A deep link: `night` (nil for the newest) on `range`.
    public func open(night: SleepNightKey?, range: SleepRange) {
        guard let snapshot else {
            requested = (night, range)
            return
        }
        move(to: allowed(SleepSelection(night: night ?? snapshot.defaultNight, range: range), in: snapshot))
    }

    private func move(to next: SleepSelection) {
        selection = next
        selectedBar = nil
        followsLatest = next.night == snapshot?.defaultNight
        skipReveal()
        Task { await rebuild(for: next, animated: true) }
    }

    // MARK: Building

    private func apply(_ snapshot: SleepSnapshot) async {
        self.snapshot = snapshot
        var next = selection ?? SleepSelection(night: snapshot.defaultNight, range: .day)
        if let request = requested {
            next = SleepSelection(night: request.night ?? snapshot.defaultNight, range: request.range)
            requested = nil
        } else if followsLatest {
            // Looking at the newest night: a newer one arriving is the one to show.
            next.night = snapshot.defaultNight
        }
        next = allowed(next, in: snapshot)
        followsLatest = next.night == snapshot.defaultNight
        selection = next
        await rebuild(for: next, animated: screen != nil)
    }

    private func rebuild(for target: SleepSelection, animated: Bool) async {
        guard let snapshot else { return }
        let built = await repository.model(for: target, in: snapshot)
        // A newer selection has already moved on; let its build win.
        guard target == selection else { return }
        let screen = SleepScreenBuilder.build(snapshot, model: built, selection: target, now: clock(), calendar: calendar, locale: locale)
        let publish = {
            self.model = built
            if self.screen != screen { self.screen = screen }
        }
        if animated {
            // The content below morphs: a spring, and Reduce Motion's fade.
            withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion()), publish)
        } else {
            publish()
        }
        updateReveal()
        announce(screen.highlights)
    }

    /// A personal highlight gets one soft haptic the first time it's shown
    /// (per night or week), and only while the tab is on screen.
    private func announce(_ highlights: [SleepHighlightContent]) {
        let fresh = highlights.map(\.id).filter { !announcedHighlights.contains($0) }
        guard isVisible, !fresh.isEmpty else { return }
        announcedHighlights.formUnion(fresh)
        NoctisHaptics.soft()
    }

    // MARK: Reveal

    /// The first day-view with data that's on screen each calendar day
    /// uses up this tab's reveal; it plays without Reduce Motion (which
    /// still uses the day up).
    private func updateReveal() {
        guard isVisible, !revealDecided, screen?.day != nil else { return }
        revealDecided = true
        guard introGate.claim(now: clock(), calendar: calendar), !reduceMotion() else { return }
        reveal = .pending
    }

    /// The content is on screen in its start state: run the reveal.
    public func beginReveal() {
        guard reveal == .pending, screen?.day != nil else { return }
        reveal = .playing
        revealPlayed = true
        revealEnd?.cancel()
        revealEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.revealDuration))
            guard !Task.isCancelled, let self, self.reveal == .playing else { return }
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

    // MARK: Observing

    public func stopObserving() {
        observation?.cancel()
        observation = nil
        revealEnd?.cancel()
        revealEnd = nil
    }

    private func startObserving() {
        guard observation == nil else { return }
        observation = Task { [weak self, repository] in
            for await _ in await repository.changes() {
                guard let self else { return }
                await self.refresh()
            }
        }
    }
}

/// Which detail sheet is open.
public enum SleepDetail: String, Sendable, Identifiable, Hashable {
    case consistency
    case balance
    case timing

    public var id: String { rawValue }
}
