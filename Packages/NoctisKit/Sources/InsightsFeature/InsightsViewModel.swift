import DesignSystem
import Foundation
import HomeFeature
import InsightsKit
import NoctisCore
import Observation
import SwiftUI

/// The Insights tab's view model: holds the latest `InsightsSnapshot`, the
/// chip filter and the `InsightsScreenContent` the views lay out, and decides
/// when to rebuild: on appear, on pull-to-refresh, when Health data changes
/// and when the filter moves. Views read `screen` and nothing else
/// (APP_RULES.md R20). One instance serves the tab, History and the detail
/// page, and its snapshot is the one Home reads too (`InsightStore`).
@Observable
public final class InsightsViewModel {
    public private(set) var snapshot: InsightsSnapshot?
    /// Nil until the first snapshot arrives (the tab shows its skeleton).
    public private(set) var screen: InsightsScreenContent?
    /// The chip chosen; nil is All.
    public private(set) var filter: InsightCategory?
    public private(set) var isRefreshing = false
    /// The day's reveal for this tab (`HomeRevealPhase`, shared): the featured
    /// numbers count up.
    public private(set) var reveal: HomeRevealPhase = .none
    /// How the tab's color field arrives the first time it's shown.
    public private(set) var fieldEntrance: NoctisFieldEntrance = .none
    /// Bumped each time a touch or scroll skips the reveal.
    public private(set) var revealSkips = 0
    public private(set) var revealPlayed = false
    /// Low Power Mode: no count-up (the end state shows at once).
    public private(set) var isLowPower: Bool

    private let repository: InsightsRepository
    private let profile: () -> UserProfileSnapshot
    private let connectHealth: () async -> Void
    private let introGate: HomeIntroGate
    private let washGate: HomeIntroGate
    private let reduceMotion: () -> Bool
    private let lowPower: () -> Bool
    private let clock: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private let revealSleep: @Sendable (Double) async -> Void
    private var observation: Task<Void, Never>?
    private var revealEnd: Task<Void, Never>?
    private var isVisible = false
    private var revealDecided = false

    /// The key of this tab's once-a-day reveal.
    public static let introKey = "noctis.insights.lastIntroDay"
    /// The key of this tab's once-a-day field wash.
    public static let washKey = "noctis.insights.lastWashDay"
    /// How long the reveal takes, start to end.
    public static let revealDuration = 1.6

    public init(
        repository: InsightsRepository,
        profile: @escaping () -> UserProfileSnapshot,
        connectHealth: @escaping () async -> Void = {},
        introGate: HomeIntroGate = HomeIntroGate(key: InsightsViewModel.introKey),
        washGate: HomeIntroGate = HomeIntroGate(key: InsightsViewModel.washKey),
        reduceMotion: @escaping () -> Bool = { HomeViewModel.systemReduceMotion() },
        lowPower: @escaping () -> Bool = { HomeViewModel.systemLowPower() },
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        revealSleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
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
        self.revealSleep = revealSleep
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
            apply(cached)
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
        apply(await repository.refresh(profile: profile()))
        isRefreshing = false
    }

    /// "Connect Apple Health": onboarding's authorization flow, then a
    /// fresh read.
    public func connectAppleHealth() async {
        await connectHealth()
        await refresh()
    }

    // MARK: Filter

    /// A chip, or nil for All; the list morphs with a spring.
    public func select(filter next: InsightCategory?) {
        guard next != filter else { return }
        skipReveal()
        filter = next
        rebuild(animated: true)
    }

    // MARK: Insights

    /// The stored insight with `id`, wherever it lives (the tab, History).
    public func insight(id: String) -> StoredInsight? {
        snapshot?.insight(id: id)
    }

    /// Opening an insight: it stops counting as new.
    public func markSeen(id: String) {
        guard insight(id: id)?.state == .new else { return }
        Task { if let next = await repository.markSeen(id: id) { apply(next) } }
    }

    /// "Not useful": muted everywhere, and never featured again for this
    /// evidence.
    public func dismiss(id: String) async {
        if let next = await repository.dismiss(id: id) { apply(next, animated: true) }
    }

    /// "Hide insights like this".
    public func hide(_ type: InsightType) async {
        if let next = await repository.hide(type) { apply(next, animated: true) }
    }

    // MARK: Building

    private func apply(_ next: InsightsSnapshot, animated: Bool = false) {
        snapshot = next
        rebuild(animated: animated || screen != nil)
    }

    private func rebuild(animated: Bool) {
        guard let snapshot else { return }
        let content = InsightsScreenBuilder.build(snapshot, filter: filter, now: clock(), calendar: calendar, locale: locale)
        let publish = {
            if self.screen != content { self.screen = content }
        }
        if animated {
            // The list below morphs: a spring, and Reduce Motion's fade.
            withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion()), publish)
        } else {
            publish()
        }
        updateReveal()
    }

    // MARK: Reveal

    /// The first featured story that's on screen each calendar day uses up
    /// this tab's reveal; it plays without Reduce Motion (which still uses
    /// the day up).
    private func updateReveal() {
        guard isVisible, !revealDecided, screen?.featured != nil else { return }
        revealDecided = true
        guard introGate.claim(now: clock(), calendar: calendar), !reduceMotion() else { return }
        reveal = .pending
    }

    /// The content is on screen in its start state: run the reveal.
    public func beginReveal() {
        guard reveal == .pending, screen?.featured != nil else { return }
        reveal = .playing
        revealPlayed = true
        revealEnd?.cancel()
        revealEnd = Task { [weak self] in
            await self?.revealSleep(Self.revealDuration)
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
