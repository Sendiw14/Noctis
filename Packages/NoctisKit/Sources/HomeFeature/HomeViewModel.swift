import Foundation
import NoctisCore
import Observation
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
    /// The ring should draw itself in when it next appears: the first
    /// scored Home of the day, unless Reduce Motion is on.
    public private(set) var introPending = false

    private let repository: HomeRepository
    private let profile: () -> UserProfileSnapshot
    private let connectHealth: () async -> Void
    private let introGate: HomeIntroGate
    private let reduceMotion: () -> Bool
    private let clock: () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private var observation: Task<Void, Never>?

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
        locale: Locale = .autoupdatingCurrent
    ) {
        self.repository = repository
        self.profile = profile
        self.connectHealth = connectHealth
        self.introGate = introGate
        self.reduceMotion = reduceMotion
        self.clock = clock
        self.calendar = calendar
        self.locale = locale
        self.header = HomeScreenBuilder.header(now: clock(), newestSample: nil, calendar: calendar, locale: locale)
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

    /// Re-reads the clock (greeting, "Updated … ago") — on returning to
    /// the foreground.
    public func updateClock() {
        if let snapshot {
            apply(snapshot)
        } else {
            header = HomeScreenBuilder.header(now: clock(), newestSample: nil, calendar: calendar, locale: locale)
        }
    }

    /// True once after `introPending` is set: the caller plays the intro.
    public func consumeIntro() -> Bool {
        guard introPending else { return false }
        introPending = false
        return true
    }

    public static func systemReduceMotion() -> Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        false
        #endif
    }

    /// Stops watching Health (tests and teardown).
    public func stopObserving() {
        observation?.cancel()
        observation = nil
    }

    private func apply(_ snapshot: HomeSnapshot) {
        self.snapshot = snapshot
        let screen = HomeScreenBuilder.build(snapshot, now: clock(), calendar: calendar, locale: locale)
        // The first scored Home each day claims the intro, whether or not
        // Reduce Motion lets it play.
        if case .scored = screen.recovery, introGate.claim(now: clock(), calendar: calendar) {
            introPending = !reduceMotion()
        }
        self.screen = screen
        header = screen.header
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

/// Remembers the day Home's ring last drew itself in, so it happens once
/// a day. Stored under `noctis.` so `-noctisResetState` clears it.
public final class HomeIntroGate {
    public static let defaultsKey = "noctis.home.lastIntroDay"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func claim(now: Date, calendar: Calendar) -> Bool {
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        let key = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        guard defaults.string(forKey: Self.defaultsKey) != key else { return false }
        defaults.set(key, forKey: Self.defaultsKey)
        return true
    }
}
