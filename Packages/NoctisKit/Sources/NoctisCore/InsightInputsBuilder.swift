import Foundation
import HealthProviding
import InsightsKit
import RecoveryKit
import SleepAnalysisKit
import SleepKit

/// Turns Health data into what `InsightEngineV2` reads: one derived row per
/// night. Pure: no I/O and no clock. Nothing raw goes past here.
public nonisolated enum InsightInputsBuilder {
    /// Days of history the insights read: the 90 a record looks back over,
    /// and the 14 nights of baseline behind the oldest of them, and a
    /// margin for the 28-night comparisons.
    public static let historyDays = 110

    public static func build(
        sleep: [RawSleepSample], hrv: [HRVSample], restingHeartRate: [HeartRateSample],
        needMinutes: Double, now: Date, timeZone: TimeZone
    ) -> InsightInputs {
        let history = SleepSessionEngine.history(from: sleep, asOf: now, timeZone: timeZone)
        let metrics = NightMetricsBuilder.metrics(for: history, hrv: hrv, restingHeartRate: restingHeartRate)
        return build(history: history, metrics: metrics, needMinutes: needMinutes, now: now)
    }

    public static func build(history: SleepHistory, metrics: [NightMetrics], needMinutes: Double, now: Date) -> InsightInputs {
        let quality = Dictionary(
            SleepQualityEngine.series(history: history.nights, needMinutes: needMinutes).map { ($0.night, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let recovery = RecoveryHistoryEngine.scores(history: metrics, needMinutes: needMinutes, asOf: now)
        let recoveryByNight = Dictionary(recovery.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        let sessions = Dictionary(history.nights.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })

        let nights = metrics.map { night -> InsightNightInput in
            let result = quality[night.night]
            let shares = sessions[night.night].flatMap { SleepMetricsEngine.metrics(for: $0).stages?.asleepShares }
            return InsightNightInput(
                night: night.night, wakeTime: night.wakeTime, asleepMinutes: night.asleepMinutes,
                bedtimeMinutes: night.bedtimeMinutes, wakeMinutes: night.wakeMinutes,
                hrv: night.hrv, restingHeartRate: night.restingHeartRate,
                deepShare: shares?.deep, remShare: shares?.rem, coreShare: shares?.core,
                continuityScore: result?.factor(.continuity)?.score,
                stageScore: result?.factor(.stages)?.score,
                hrvScore: recoveryByNight[night.night]?.factorScore(.hrv),
                durationScore: result?.factor(.duration)?.score,
                consistencyScore: result?.factor(.consistency)?.score,
                qualityScore: result.flatMap { $0.isScored ? $0.score : nil }
            )
        }
        return InsightInputs(
            nights: nights, needMinutes: needMinutes,
            balance: SleepBalanceEngine.balance(history: history.nights, needMinutes: needMinutes),
            recoveryScores: recovery, asOf: now
        )
    }
}
