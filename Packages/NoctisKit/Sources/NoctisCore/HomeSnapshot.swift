import Foundation
import InsightsKit
import RecoveryKit
import SleepKit

/// What Home's data looks like right now, in the order a screen should
/// check it.
public nonisolated enum HomeDataState: Sendable, Equatable, Codable {
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

    /// Still learning the person's baseline.
    public var isLearning: Bool {
        if case .learning = self { true } else { false }
    }
}

/// One of the last seven nights; `asleepMinutes` is nil when no main
/// sleep was recorded, `stages` when its sources gave no stages.
public nonisolated struct NightDuration: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    public let asleepMinutes: Double?
    public let stages: NightStageMinutes?

    public init(night: SleepNightKey, asleepMinutes: Double?, stages: NightStageMinutes? = nil) {
        self.night = night
        self.asleepMinutes = asleepMinutes
        self.stages = stages
    }
}

/// Minutes asleep by stage (awake excluded). Unspecified sleep in a staged
/// night counts as Core, where the night panel draws it.
public nonisolated struct NightStageMinutes: Sendable, Equatable, Codable {
    public let deep: Double
    public let core: Double
    public let rem: Double

    public init(deep: Double, core: Double, rem: Double) {
        self.deep = deep
        self.core = core
        self.rem = rem
    }

    public init(_ totals: SleepTotals) {
        self.init(deep: totals.deep / 60, core: (totals.core + totals.unspecified) / 60, rem: totals.rem / 60)
    }
}

/// Tonight's plan from the profile: bedtime = wake time − sleep need, as
/// minutes since midnight.
public nonisolated struct TonightPlan: Sendable, Equatable, Codable {
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
    /// Heart rate recorded during last night; nil without any.
    public let lastNightHeart: NightHeartSeries?
    /// Last night's sleep quality (0...100), the same number the Sleep tab
    /// shows; nil while learning or when no factor could be scored.
    public let lastNightSleepQuality: Int?
    /// The newest Health sample of any type; nil with no data at all.
    public let newestSample: Date?
    public let lastUpdated: Date
    /// The geometry every chart and ring draws, worked out once here (on
    /// the repository's actor) so no view ever does.
    public let render: HomeRenderModel

    public init(
        dataState: HomeDataState,
        recovery: RecoveryState?,
        lastNight: SleepSession?,
        latestSleep: SleepSession?,
        recentNights: [NightDuration],
        weekAverageMinutes: Double?,
        tonight: TonightPlan,
        topInsight: Insight?,
        lastNightHeart: NightHeartSeries? = nil,
        lastNightSleepQuality: Int? = nil,
        newestSample: Date?,
        lastUpdated: Date,
        render: HomeRenderModel? = nil
    ) {
        self.dataState = dataState
        self.recovery = recovery
        self.lastNight = lastNight
        self.latestSleep = latestSleep
        self.recentNights = recentNights
        self.weekAverageMinutes = weekAverageMinutes
        self.tonight = tonight
        self.topInsight = topInsight
        self.lastNightHeart = lastNightHeart
        self.lastNightSleepQuality = lastNightSleepQuality
        self.newestSample = newestSample
        self.lastUpdated = lastUpdated
        self.render = render ?? HomeRenderModelBuilder.build(
            recovery: recovery,
            lastNight: lastNight,
            heart: lastNightHeart,
            recentNights: recentNights,
            needMinutes: tonight.needMinutes
        )
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
            lastNightHeart: lastNightHeart,
            lastNightSleepQuality: lastNightSleepQuality,
            newestSample: newestSample,
            lastUpdated: lastUpdated,
            render: render
        )
    }
}
