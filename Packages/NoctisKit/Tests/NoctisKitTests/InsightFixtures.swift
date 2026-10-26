import Foundation

@testable import InsightsKit
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepKit

/// Hand-built insight inputs: one row per night, oldest first, the last
/// ending on the evening of Sep 23, 2026 (woke 7:00 AM on Sep 24).
enum InsightFixture {
    static let last = SleepNightKey(year: 2026, month: 9, day: 23)
    static let asOf = Fixture.morningAfter

    struct Row {
        var asleep = 420.0
        var bedtime = 660.0
        var wake = 1140.0
        var hrv: Double?
        var resting: Double?
        var deep: Double?
        var rem: Double?
        var continuity: Int?
        var stage: Int?
        var hrvScore: Int?
        var duration: Int?
        var consistency: Int?
        var quality: Int?
    }

    /// `count` nights ending on `last`; `row(index, night)` describes each
    /// (index 0 is the oldest).
    static func inputs(
        count: Int,
        endingOn end: SleepNightKey = last,
        need: Double = 480,
        balance: SleepBalanceResult? = nil,
        recovery: [RecoveryDayScore] = [],
        asOf: Date = asOf,
        row: (Int, SleepNightKey) -> Row = { _, _ in Row() }
    ) -> InsightInputs {
        let nights = (0..<count).map { index -> InsightNightInput in
            let night = end.adding(days: index - (count - 1))
            let r = row(index, night)
            let wakeDay = night.adding(days: 1)
            return InsightNightInput(
                night: night, wakeTime: Fixture.date(wakeDay.year, wakeDay.month, wakeDay.day, 7),
                asleepMinutes: r.asleep, bedtimeMinutes: r.bedtime, wakeMinutes: r.wake, hrv: r.hrv, restingHeartRate: r.resting,
                deepShare: r.deep, remShare: r.rem, coreShare: r.deep.flatMap { d in r.rem.map { 1 - d - $0 } },
                continuityScore: r.continuity, stageScore: r.stage, hrvScore: r.hrvScore,
                durationScore: r.duration, consistencyScore: r.consistency, qualityScore: r.quality
            )
        }
        return InsightInputs(nights: nights, needMinutes: need, balance: balance, recoveryScores: recovery, asOf: asOf)
    }

    static func recoveryScore(_ night: SleepNightKey, _ score: Int) -> RecoveryDayScore {
        let wakeDay = night.adding(days: 1)
        return RecoveryDayScore(
            night: night, date: Fixture.date(wakeDay.year, wakeDay.month, wakeDay.day, 7), score: score, confidence: .high, factorScores: [], capApplied: false
        )
    }

    /// A daily score per night ending on `last`, from `score(index)`.
    static func recoveryScores(count: Int, endingOn end: SleepNightKey = last, _ score: (Int) -> Int) -> [RecoveryDayScore] {
        (0..<count).map { recoveryScore(end.adding(days: $0 - (count - 1)), score($0)) }
    }

    static func balance(minutes: Double?, recorded: Int = 7) -> SleepBalanceResult {
        SleepBalanceResult(minutes: minutes, night: last, recordedNights: recorded, series: [])
    }

    /// The records of one type, from `InsightEngineV2.generate`.
    static func records(_ inputs: InsightInputs, _ type: InsightType, history: InsightHistory = InsightHistory()) -> [InsightRecord] {
        InsightEngineV2.generate(inputs, history: history).filter { $0.type == type }
    }

    static func types(_ inputs: InsightInputs) -> Set<InsightType> {
        Set(InsightEngineV2.generate(inputs).map(\.type))
    }
}
