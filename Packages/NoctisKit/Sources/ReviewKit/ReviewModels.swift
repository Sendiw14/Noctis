import Foundation
import InsightsKit
import RecoveryKit
import SleepKit

// What a review is made of (APP_RULES.md R39): the per-night values it is built from, the record it produces (derived values only: no raw sample, no source name, no
// Journal, no Coach text) and what the engine says when there are too few nights. A record is Codable, Equatable and versioned, so it can be stored and compared.

/// Stage minutes asleep; nil for a night whose sources gave no stages.
public nonisolated struct ReviewStages: Sendable, Equatable, Codable {
    public let deep: Int
    public let core: Int
    public let rem: Int

    public init(deep: Int, core: Int, rem: Int) {
        self.deep = deep
        self.core = core
        self.rem = rem
    }

    public var total: Int { deep + core + rem }
}

/// One night, as the engine reads it: the values the sleep and recovery engines already worked out. `night` is keyed by the evening, as everywhere else.
public nonisolated struct ReviewNightInput: Sendable, Equatable {
    public let night: SleepNightKey
    public let asleepMinutes: Double
    public let stages: ReviewStages?
    /// Minutes after noon on the evening, local clock (11:00 PM is 660), as the baselines count them.
    public let bedtimeMinutes: Double
    public let wakeMinutes: Double
    /// The night's recovery score as its own morning was scored; nil when it had none (still learning, or no heart numbers).
    public let recoveryScore: Int?
    public let hrv: Double?
    public let restingHeartRate: Double?

    public init(
        night: SleepNightKey, asleepMinutes: Double, stages: ReviewStages? = nil, bedtimeMinutes: Double, wakeMinutes: Double, recoveryScore: Int? = nil,
        hrv: Double? = nil, restingHeartRate: Double? = nil
    ) {
        self.night = night
        self.asleepMinutes = asleepMinutes
        self.stages = stages
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
        self.recoveryScore = recoveryScore
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
    }

    /// The morning the night ended on.
    public var morning: SleepNightKey { ReviewPeriod.morning(ofNight: night) }
}

/// An insight the engine may point to: its id, when it was generated and how it ranks (`InsightRanking.score`). Ids only: the words stay with the insight.
public nonisolated struct ReviewInsightInput: Sendable, Equatable {
    public let id: String
    public let generatedAt: Date
    public let score: Double

    public init(id: String, generatedAt: Date, score: Double) {
        self.id = id
        self.generatedAt = generatedAt
        self.score = score
    }
}

// MARK: - The record

/// One night of the period, for the charts: derived values only.
public nonisolated struct ReviewNightValues: Sendable, Equatable, Codable {
    public let morning: SleepNightKey
    public let asleepMinutes: Int
    public let stages: ReviewStages?
    public let bedtimeMinutes: Int
    public let wakeMinutes: Int
    public let recoveryScore: Int?

    public init(morning: SleepNightKey, asleepMinutes: Int, stages: ReviewStages?, bedtimeMinutes: Int, wakeMinutes: Int, recoveryScore: Int?) {
        self.morning = morning
        self.asleepMinutes = asleepMinutes
        self.stages = stages
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
        self.recoveryScore = recoveryScore
    }
}

public nonisolated struct ReviewSleep: Sendable, Equatable, Codable {
    public let averageMinutes: Double
    /// Nights that reached the sleep need.
    public let nightsReachedNeed: Int
    public let needMinutes: Int
    /// This period's average less the previous period's; nil unless the previous period has enough nights.
    public let deltaMinutes: Double?

    public init(averageMinutes: Double, nightsReachedNeed: Int, needMinutes: Int, deltaMinutes: Double?) {
        self.averageMinutes = averageMinutes
        self.nightsReachedNeed = nightsReachedNeed
        self.needMinutes = needMinutes
        self.deltaMinutes = deltaMinutes
    }
}

public nonisolated struct ReviewConsistency: Sendable, Equatable, Codable {
    public let bedtimeSD: Double
    public let wakeSD: Double
    /// This period's less the previous period's (minutes, negative is steadier); nil unless the previous period has enough nights.
    public let bedtimeSDDelta: Double?
    public let wakeSDDelta: Double?

    public init(bedtimeSD: Double, wakeSD: Double, bedtimeSDDelta: Double?, wakeSDDelta: Double?) {
        self.bedtimeSD = bedtimeSD
        self.wakeSD = wakeSD
        self.bedtimeSDDelta = bedtimeSDDelta
        self.wakeSDDelta = wakeSDDelta
    }
}

/// The best or longest night of a period, with its date and how many other nights equalled it.
public nonisolated struct ReviewExtreme: Sendable, Equatable, Codable {
    public let value: Double
    public let morning: SleepNightKey
    /// Other nights with the same value (the latest of them is `morning`).
    public let alsoOn: Int

    public init(value: Double, morning: SleepNightKey, alsoOn: Int) {
        self.value = value
        self.morning = morning
        self.alsoOn = alsoOn
    }
}

public nonisolated struct ReviewRecovery: Sendable, Equatable, Codable {
    public let average: Double
    public let scoredNights: Int
    public let high: ReviewExtreme
    public let low: ReviewExtreme
    /// The direction over the period's scored nights (`RecoveryHistoryEngine.trend`); nil under five scored nights.
    public let trend: RecoveryHistoryTrend?
    /// This period's average less the previous period's; nil unless both have enough scored nights.
    public let delta: Double?

    public init(average: Double, scoredNights: Int, high: ReviewExtreme, low: ReviewExtreme, trend: RecoveryHistoryTrend?, delta: Double?) {
        self.average = average
        self.scoredNights = scoredNights
        self.high = high
        self.low = low
        self.trend = trend
        self.delta = delta
    }
}

public nonisolated struct ReviewHeart: Sendable, Equatable, Codable {
    /// Average HRV in ms and its change; nil without five nights of it.
    public let hrvAverage: Double?
    public let hrvDelta: Double?
    public let restingHeartRateAverage: Double?
    public let restingHeartRateDelta: Double?

    public init(hrvAverage: Double?, hrvDelta: Double?, restingHeartRateAverage: Double?, restingHeartRateDelta: Double?) {
        self.hrvAverage = hrvAverage
        self.hrvDelta = hrvDelta
        self.restingHeartRateAverage = restingHeartRateAverage
        self.restingHeartRateDelta = restingHeartRateDelta
    }
}

public nonisolated struct ReviewTiming: Sendable, Equatable, Codable {
    /// Median bedtime and wake, minutes after noon on the evening (11:00 PM is 660).
    public let medianBedtimeMinutes: Double
    public let medianWakeMinutes: Double
    /// Minutes later than the previous period's median (negative is earlier); nil unless the previous period has enough nights.
    public let bedtimeShift: Double?
    public let wakeShift: Double?

    public init(medianBedtimeMinutes: Double, medianWakeMinutes: Double, bedtimeShift: Double?, wakeShift: Double?) {
        self.medianBedtimeMinutes = medianBedtimeMinutes
        self.medianWakeMinutes = medianWakeMinutes
        self.bedtimeShift = bedtimeShift
        self.wakeShift = wakeShift
    }
}

/// What can be compared between two periods.
public nonisolated enum ReviewMetric: String, Sendable, Equatable, Codable, CaseIterable {
    case duration
    case bedtimeVariation
    case recovery
    case hrv
    case restingHeartRate

    /// Lower is better for the bedtime's variation and the resting heart rate; higher for the rest.
    public var lowerIsBetter: Bool { self == .bedtimeVariation || self == .restingHeartRate }
}

/// One metric's change, set against the person's own variation.
public nonisolated struct ReviewChange: Sendable, Equatable, Codable {
    public let metric: ReviewMetric
    public let value: Double
    public let previous: Double
    /// (value - previous) over the person's own variation (the standard deviation of the underlying nightly values over the 28 nights before the period, never under the
    /// metric's floor). Signed: positive means the number went up.
    public let normalized: Double

    public init(metric: ReviewMetric, value: Double, previous: Double, normalized: Double) {
        self.metric = metric
        self.value = value
        self.previous = previous
        self.normalized = normalized
    }

    public var delta: Double { value - previous }
    /// Positive when the change was in the metric's good direction.
    public var goodness: Double { metric.lowerIsBetter ? -normalized : normalized }
}

/// What a headline can say. `.steady` is only ever said when a comparison was made and nothing moved by at least half the person's own variation; with nothing to
/// compare against it is `.noComparison`, never "steady".
public nonisolated enum ReviewHighlight: Sendable, Equatable, Codable {
    case change(ReviewChange)
    case steady
    case noComparison
}

/// The one thing a review may suggest, by a fixed priority; `.keepGoing` when none applies.
public nonisolated enum ReviewFocus: Sendable, Equatable, Codable {
    /// Bedtime varied by more than 45 minutes (the minutes it varied by).
    case steadyBedtime(minutes: Double)
    /// The last 7 nights added up to 60 minutes or more behind the sleep need (minutes behind).
    case sleepNeed(minutesBehind: Double)
    /// The median bedtime moved 45 minutes or more later than the previous period (minutes later).
    case gentleShiftBack(minutesLater: Double)
    /// Recovery was lower over five or more nights (the scored nights).
    case recentNights(nights: Int)
    case keepGoing
}

/// Only a month has these.
public nonisolated struct ReviewMonthlyExtras: Sendable, Equatable, Codable {
    public let recoveryRolling: [ReviewRollingPoint]
    public let longestNight: ReviewExtreme
    public let highestRecovery: ReviewExtreme?

    public init(recoveryRolling: [ReviewRollingPoint], longestNight: ReviewExtreme, highestRecovery: ReviewExtreme?) {
        self.recoveryRolling = recoveryRolling
        self.longestNight = longestNight
        self.highestRecovery = highestRecovery
    }
}

public nonisolated struct ReviewRollingPoint: Sendable, Equatable, Codable {
    public let morning: SleepNightKey
    public let value: Double

    public init(morning: SleepNightKey, value: Double) {
        self.morning = morning
        self.value = value
    }
}

public nonisolated struct ReviewRecord: Sendable, Equatable, Codable, Identifiable {
    /// Bump when a change would break an older reader; a record of another version is not read.
    public static let currentVersion = 2

    public let version: Int
    public let id: ReviewID
    public let firstMorning: SleepNightKey
    public let lastMorning: SleepNightKey
    public let generatedAt: Date
    public let nightsRecorded: Int
    public let nightsInPeriod: Int
    /// Whether the previous period had enough nights for anything to be compared with it.
    public let hasComparison: Bool
    public let sleep: ReviewSleep
    public let consistency: ReviewConsistency
    public let recovery: ReviewRecovery?
    public let heart: ReviewHeart
    public let timing: ReviewTiming
    public let nights: [ReviewNightValues]
    public let biggestImprovement: ReviewHighlight
    public let biggestChange: ReviewHighlight
    /// Every change of at least half the person's own variation, the largest first, at most three (a month's "Major changes"); empty when nothing moved by that much
    /// or there was nothing to compare with.
    public let topChanges: [ReviewChange]
    /// Insight ids, best first: one for a week, up to three for a month.
    public let topInsightIDs: [String]
    public let nextFocus: ReviewFocus
    public let monthly: ReviewMonthlyExtras?

    public init(
        id: ReviewID, firstMorning: SleepNightKey, lastMorning: SleepNightKey, generatedAt: Date, nightsRecorded: Int, nightsInPeriod: Int, hasComparison: Bool,
        sleep: ReviewSleep, consistency: ReviewConsistency, recovery: ReviewRecovery?, heart: ReviewHeart, timing: ReviewTiming, nights: [ReviewNightValues],
        biggestImprovement: ReviewHighlight, biggestChange: ReviewHighlight, topChanges: [ReviewChange] = [], topInsightIDs: [String], nextFocus: ReviewFocus,
        monthly: ReviewMonthlyExtras?, version: Int = ReviewRecord.currentVersion
    ) {
        self.version = version
        self.id = id
        self.firstMorning = firstMorning
        self.lastMorning = lastMorning
        self.generatedAt = generatedAt
        self.nightsRecorded = nightsRecorded
        self.nightsInPeriod = nightsInPeriod
        self.hasComparison = hasComparison
        self.sleep = sleep
        self.consistency = consistency
        self.recovery = recovery
        self.heart = heart
        self.timing = timing
        self.nights = nights
        self.biggestImprovement = biggestImprovement
        self.biggestChange = biggestChange
        self.topChanges = topChanges
        self.topInsightIDs = topInsightIDs
        self.nextFocus = nextFocus
        self.monthly = monthly
    }

    public var kind: ReviewKind { id.kind }
    public var period: ReviewPeriod { ReviewPeriod(kind: kind, firstMorning: firstMorning, lastMorning: lastMorning) }
}

/// What the engine returns: a record, or the count that is short.
public nonisolated enum ReviewResult: Sendable, Equatable {
    case record(ReviewRecord)
    /// Fewer nights than the kind needs: the nights there are, and the nights needed ("4 of 5 nights").
    case notEnoughNights(have: Int, need: Int)
}
