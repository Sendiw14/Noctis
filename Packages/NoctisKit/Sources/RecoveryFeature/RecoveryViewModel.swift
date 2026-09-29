import DesignSystem
import Foundation
import HomeFeature
import NoctisCore
import Observation
import RecoveryKit
import SwiftUI

/// The Recovery tab's view model: holds the latest `RecoverySnapshot`, the
/// selection (a segment, and a factor when its detail is open), the render
/// model for it and the `RecoveryScreenContent` the views lay out, and
/// decides when to rebuild: on appear, on pull-to-refresh, when Health data
/// changes and when the selection moves. Views read `screen` and nothing
/// else (APP_RULES.md R20). One instance serves the Recovery tab and the
/// screen Home's ring zooms into.
@Observable
public final class RecoveryViewModel {
    public private(set) var snapshot: RecoverySnapshot?
    /// Nil until the first snapshot arrives (the tab shows its skeleton).
    public private(set) var screen: RecoveryScreenContent?
    public private(set) var model: RecoveryRenderModel?
    /// A factor's page, while one is open.
    public private(set) var factor: RecoveryFactorContent?
    /// The segment and factor chosen; moves at once, before the content
    /// follows.
    public private(set) var selection = RecoverySelection()
    public private(set) var isRefreshing = false
    /// The day's reveal for this tab (`HomeRevealPhase`, shared): the ring
    /// fills and the numbers count up.
    public private(set) var reveal: HomeRevealPhase = .none
    /// Bumped each time a touch or scroll skips the reveal.
    public private(set) var revealSkips = 0
    public private(set) var revealPlayed = false
    /// Low Power Mode: no count-up (the end state shows at once).
    public private(set) var isLowPower: Bool

    private let repository: RecoveryRepository
    private let profile: () -> UserProfileSnapshot
    private let connectHealth: () async -> Void
    private let introGate: HomeIntroGate
    private let reduceMotion: () -> Bool
    private let lowPower: () -> Bool
    private let clock: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private var observation: Task<Void, Never>?
    private var revealEnd: Task<Void, Never>?
    private var isVisible = false
    private var revealDecided = false

    /// The key of this tab's once-a-day reveal.
    public static let introKey = "noctis.recovery.lastIntroDay"
    /// How long the reveal takes, start to end.
    public static let revealDuration = 1.6

    public init(
        repository: RecoveryRepository,
        profile: @escaping () -> UserProfileSnapshot,
        connectHealth: @escaping () async -> Void = {},
        introGate: HomeIntroGate = HomeIntroGate(key: RecoveryViewModel.introKey),
        reduceMotion: @escaping () -> Bool = { HomeViewModel.systemReduceMotion() },
        lowPower: @escaping () -> Bool = { HomeViewModel.systemLowPower() },
        clock: @escaping () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.repository = repository
        self.profile = profile
        self.connectHealth = connectHealth
        self.introGate = introGate
        self.reduceMotion = reduceMotion
        self.lowPower = lowPower
        isLowPower = lowPower()
        self.clock = clock
        self.calendar = calendar
        self.locale = locale
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

    public func select(segment: RecoverySegment) {
        guard selection.segment != segment else { return }
        var next = selection
        next.segment = segment
        move(to: next)
    }

    /// A factor's detail over `range` nights.
    public func select(factor: RecoveryFactorKind?, range: RecoveryFactorRange) {
        var next = selection
        next.factor = factor
        next.factorRange = range
        guard next != selection else { return }
        move(to: next)
    }

    /// A deep link or Home's zoom: `segment`, and a factor's detail when
    /// given.
    public func open(segment: RecoverySegment, factor: RecoveryFactorKind? = nil, factorRange: RecoveryFactorRange = .fortnight) {
        move(to: RecoverySelection(segment: segment, factor: factor, factorRange: factorRange))
    }

    private func move(to next: RecoverySelection) {
        selection = next
        skipReveal()
        Task { await rebuild(for: next, animated: true) }
    }

    // MARK: Building

    private func apply(_ snapshot: RecoverySnapshot) async {
        self.snapshot = snapshot
        await rebuild(for: selection, animated: screen != nil)
    }

    private func rebuild(for target: RecoverySelection, animated: Bool) async {
        guard let snapshot else { return }
        let built = await repository.model(for: target, in: snapshot)
        // A newer selection has already moved on; let its build win.
        guard target == selection else { return }
        // The screen follows the segment; a factor's detail reads the
        // render model directly.
        var segmentSelection = target
        segmentSelection.factor = nil
        let segmentModel = target.factor == nil ? built : await repository.model(for: segmentSelection, in: snapshot)
        let content = RecoveryScreenBuilder.build(snapshot, model: segmentModel, selection: segmentSelection, now: clock(), calendar: calendar, locale: locale)
        let factor = target.factor == nil
            ? nil
            : RecoveryScreenBuilder.factorContent(snapshot, model: built, selection: target, calendar: calendar, locale: locale)
        let publish = {
            self.model = built
            if self.screen != content { self.screen = content }
            if self.factor != factor { self.factor = factor }
        }
        if animated {
            withAnimation(NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion()), publish)
        } else {
            publish()
        }
        updateReveal()
    }

    // MARK: Reveal

    /// The first Today with a score that's on screen each calendar day uses
    /// up this tab's reveal; it plays without Reduce Motion (which still
    /// uses the day up).
    private func updateReveal() {
        guard isVisible, !revealDecided, screen?.today != nil || screen?.history != nil else { return }
        revealDecided = true
        guard introGate.claim(now: clock(), calendar: calendar), !reduceMotion() else { return }
        reveal = .pending
    }

    /// The content is on screen in its start state: run the reveal.
    public func beginReveal() {
        guard reveal == .pending, screen?.today != nil || screen?.history != nil else { return }
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
