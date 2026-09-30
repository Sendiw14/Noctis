import Foundation
import RecoveryKit
import SleepAnalysisKit
import SleepKit

/// One night as the insight rules see it: derived values only.
public struct InsightNightInput: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    public let wakeTime: Date
    public let asleepMinutes: Double
    /// Minutes after noon on the evening (11:00 PM = 660).
    public let bedtimeMinutes: Double
    public let wakeMinutes: Double
    public let hrv: Double?
    public let restingHeartRate: Double?
    /// Each stage's share of the time asleep (0...1); nil without stages.
    public let deepShare: Double?
    public let remShare: Double?
    public let coreShare: Double?
    // The pattern rule's outcome reads only these three scores (0...100):
    /// The sleep-quality continuity factor.
    public let continuityScore: Int?
    /// The sleep-quality stage-balance factor.
    public let stageScore: Int?
    /// Recovery's HRV factor.
    public let hrvScore: Int?
    // Scores that are themselves computed from bedtime or duration; no rule
    // about bedtime may read them as an outcome (they would be circular).
    public let durationScore: Int?
    public let consistencyScore: Int?
    public let qualityScore: Int?

    public init(
        night: SleepNightKey, wakeTime: Date, asleepMinutes: Double, bedtimeMinutes: Double, wakeMinutes: Double,
        hrv: Double? = nil, restingHeartRate: Double? = nil,
        deepShare: Double? = nil, remShare: Double? = nil, coreShare: Double? = nil,
        continuityScore: Int? = nil, stageScore: Int? = nil, hrvScore: Int? = nil,
        durationScore: Int? = nil, consistencyScore: Int? = nil, qualityScore: Int? = nil
    ) {
        self.night = night
        self.wakeTime = wakeTime
        self.asleepMinutes = asleepMinutes
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.deepShare = deepShare
        self.remShare = remShare
        self.coreShare = coreShare
        self.continuityScore = continuityScore
        self.stageScore = stageScore
        self.hrvScore = hrvScore
        self.durationScore = durationScore
        self.consistencyScore = consistencyScore
        self.qualityScore = qualityScore
    }

    public var metrics: NightMetrics {
        NightMetrics(
            night: night, wakeTime: wakeTime, asleepMinutes: asleepMinutes, bedtimeMinutes: bedtimeMinutes,
            wakeMinutes: wakeMinutes, hrv: hrv, restingHeartRate: restingHeartRate
        )
    }
}

/// Everything `InsightEngineV2` reads: the nights (up to the 90 a record
/// looks back over, and the baselines behind them), the recovery score of
/// each morning, and the 7-night balance.
public struct InsightInputs: Sendable, Equatable {
    /// One per night, oldest first.
    public let nights: [InsightNightInput]
    public let needMinutes: Double
    public let balance: SleepBalanceResult?
    /// Every scored morning, oldest first (`RecoveryHistoryEngine.scores`).
    public let recoveryScores: [RecoveryDayScore]
    public let asOf: Date

    public init(nights: [InsightNightInput], needMinutes: Double, balance: SleepBalanceResult?, recoveryScores: [RecoveryDayScore], asOf: Date) {
        var seen = Set<SleepNightKey>()
        self.nights = nights.sorted { $0.night < $1.night }.filter { seen.insert($0.night).inserted }
        self.needMinutes = needMinutes
        self.balance = balance
        self.recoveryScores = recoveryScores.sorted { $0.night < $1.night }
        self.asOf = asOf
    }

    public var metrics: [NightMetrics] { nights.map(\.metrics) }

    /// Nights that ended by `asOf`.
    public var complete: [InsightNightInput] { nights.filter { $0.wakeTime <= asOf } }

    /// The newest complete night, if it ended within the last 24 hours:
    /// the night every rule is about.
    public var lastNight: InsightNightInput? {
        guard let last = complete.max(by: { $0.wakeTime < $1.wakeTime }),
              asOf.timeIntervalSince(last.wakeTime) <= RecoveryModelV1.lastNightWindow else { return nil }
        return last
    }
}
