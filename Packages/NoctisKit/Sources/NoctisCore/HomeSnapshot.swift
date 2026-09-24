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
/// sleep was recorded, `recovery` when that morning had no score.
public nonisolated struct NightDuration: Sendable, Equatable {
    public let night: SleepNightKey
    public let asleepMinutes: Double?
    /// That morning's recovery, scored as it was then
    /// (`RecoveryEngine.nightlyScores`).
    public let recovery: Int?

    public init(night: SleepNightKey, asleepMinutes: Double?, recovery: Int? = nil) {
        self.night = night
        self.asleepMinutes = asleepMinutes
        self.recovery = recovery
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
    /// The newest main sleep on record, however old — what a "no sleep
    /// last night" message can point back to.
    public let latestSleep: SleepSession?
    /// The seven nights ending last night, oldest first.
    public let recentNights: [NightDuration]
    /// Mean minutes asleep over `recentNights` that have data; nil when
    /// none do.
    public let weekAverageMinutes: Double?
    public let tonight: TonightPlan
    public let topInsight: Insight?
    /// The newest Health sample of any type; nil with no data at all.
    public let newestSample: Date?
    public let lastUpdated: Date

    public init(
        dataState: HomeDataState,
        recovery: RecoveryState?,
        lastNight: SleepSession?,
        latestSleep: SleepSession?,
        recentNights: [NightDuration],
        weekAverageMinutes: Double?,
        tonight: TonightPlan,
        topInsight: Insight?,
        newestSample: Date?,
        lastUpdated: Date
    ) {
        self.dataState = dataState
        self.recovery = recovery
        self.lastNight = lastNight
        self.latestSleep = latestSleep
        self.recentNights = recentNights
        self.weekAverageMinutes = weekAverageMinutes
        self.tonight = tonight
        self.topInsight = topInsight
        self.newestSample = newestSample
        self.lastUpdated = lastUpdated
    }
}

nonisolated extension HomeSnapshot {
    /// The same snapshot with another insight (or none).
    public func replacingInsight(_ insight: Insight?) -> HomeSnapshot {
        HomeSnapshot(
            dataState: dataState,
            recovery: recovery,
            lastNight: lastNight,
            latestSleep: latestSleep,
            recentNights: recentNights,
            weekAverageMinutes: weekAverageMinutes,
            tonight: tonight,
            topInsight: insight,
            newestSample: newestSample,
            lastUpdated: lastUpdated
        )
    }
}
