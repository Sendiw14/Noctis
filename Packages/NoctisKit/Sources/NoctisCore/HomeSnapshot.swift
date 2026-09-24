import Foundation
import InsightsKit
import RecoveryKit
import SleepKit

/// What Home's data looks like right now, in the order a screen should
/// check it.
public nonisolated enum HomeDataState: Sendable, Equatable {
    /// This device has no Health data store.
    case healthDataUnavailable
    /// Health access hasn't been granted.
    case permissionRequired
    /// A Health query failed.
    case failed
    /// No sleep, HRV or heart rate data at all in the history window.
    case empty
    /// The newest sample of any type is more than 24 hours old.
    case stale(newestSample: Date)
    /// Fewer than 5 nights of sleep so far.
    case learning(nightsSoFar: Int)
    /// Recent data exists, but no main sleep ended in the last 24 hours.
    case noSleepLastNight
    case ready
}

/// One of the last seven nights; `asleepMinutes` is nil when no main
/// sleep was recorded.
public nonisolated struct NightDuration: Sendable, Equatable {
    public let night: SleepNightKey
    public let asleepMinutes: Double?

    public init(night: SleepNightKey, asleepMinutes: Double?) {
        self.night = night
        self.asleepMinutes = asleepMinutes
    }
}

/// Tonight's plan from the profile: bedtime = wake time − sleep need, as
/// minutes since midnight.
public nonisolated struct TonightPlan: Sendable, Equatable {
    public let bedtimeMinutes: Int
    public let wakeMinutes: Int
    public let needMinutes: Int

    public init(profile: UserProfileSnapshot) {
        bedtimeMinutes = noctisBedtimeMinutes(wakeMinutes: profile.typicalWakeMinutes, needMinutes: profile.needMinutes)
        wakeMinutes = profile.typicalWakeMinutes
        needMinutes = profile.needMinutes
    }
}

/// Everything Home shows, built by `HomeRepository`. Views read this and
/// nothing else (APP_RULES.md R20).
public nonisolated struct HomeSnapshot: Sendable, Equatable {
    public let dataState: HomeDataState
    /// Nil when there's no data to judge (unavailable, permission,
    /// failure, empty).
    public let recovery: RecoveryState?
    /// Last night's main sleep (ended within 24 hours), if any.
    public let lastNight: SleepSession?
    /// The seven nights ending last night, oldest first.
    public let recentNights: [NightDuration]
    public let tonight: TonightPlan
    public let topInsight: Insight?
    public let lastUpdated: Date

    public init(
        dataState: HomeDataState,
        recovery: RecoveryState?,
        lastNight: SleepSession?,
        recentNights: [NightDuration],
        tonight: TonightPlan,
        topInsight: Insight?,
        lastUpdated: Date
    ) {
        self.dataState = dataState
        self.recovery = recovery
        self.lastNight = lastNight
        self.recentNights = recentNights
        self.tonight = tonight
        self.topInsight = topInsight
        self.lastUpdated = lastUpdated
    }
}
