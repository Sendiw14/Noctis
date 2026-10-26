import Foundation
import HealthProviding
import InsightsKit
import RecoveryKit
import ReviewKit
import SleepAnalysisKit
import SleepKit

/// Turns Health data into what `ReviewEngine` reads: one derived row per night, and the insights it may point to. Pure: no I/O and no clock. Nothing raw goes past here
/// (APP_RULES.md R39).
public nonisolated enum ReviewInputsBuilder {
    /// Days of history a review reads: a month, the month before it, and the 28 nights before that, with a margin for a month's 31 days.
    public static let historyDays = InsightInputsBuilder.historyDays

    public static func nights(
        sleep: [RawSleepSample], hrv: [HRVSample], restingHeartRate: [HeartRateSample], needMinutes: Double, now: Date, timeZone: TimeZone
    ) -> [ReviewNightInput] {
        let history = SleepSessionEngine.history(from: sleep, asOf: now, timeZone: timeZone)
        let metrics = NightMetricsBuilder.metrics(for: history, hrv: hrv, restingHeartRate: restingHeartRate)
        return nights(history: history, metrics: metrics, needMinutes: needMinutes, now: now)
    }

    public static func nights(history: SleepHistory, metrics: [NightMetrics], needMinutes: Double, now: Date) -> [ReviewNightInput] {
        let scores = Dictionary(
            RecoveryHistoryEngine.scores(history: metrics, needMinutes: needMinutes, asOf: now).map { ($0.night, $0.score) },
            uniquingKeysWith: { first, _ in first }
        )
        let sessions = Dictionary(history.nights.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        return metrics.filter { $0.wakeTime <= now }.map { night in
            let stages = sessions[night.night].flatMap { SleepMetricsEngine.metrics(for: $0).stages }.map {
                ReviewStages(deep: Int($0.deep.rounded()), core: Int($0.core.rounded()), rem: Int($0.rem.rounded()))
            }
            return ReviewNightInput(
                night: night.night, asleepMinutes: night.asleepMinutes, stages: stages, bedtimeMinutes: night.bedtimeMinutes, wakeMinutes: night.wakeMinutes,
                recoveryScore: scores[night.night], hrv: night.hrv, restingHeartRate: night.restingHeartRate
            )
        }
    }

    /// The insights a review may point to: every one the person has not dismissed or hidden, with the score the Insights tab ranks it by. Ids only. `placedIn` (DEBUG mock
    /// runs only: a fresh mock has no history of insights found during last week) dates every insight inside that period.
    public static func insights(from library: InsightLibrary, placedIn period: ReviewPeriod? = nil, calendar: Calendar = .current) -> [ReviewInsightInput] {
        let placed = period.flatMap {
            calendar.date(from: DateComponents(year: $0.lastMorning.year, month: $0.lastMorning.month, day: $0.lastMorning.day, hour: 12))
        }
        return library.visible.filter { $0.state != .dismissed }.map {
            ReviewInsightInput(id: $0.record.id, generatedAt: placed ?? $0.record.generatedAt, score: InsightRanking.score($0.record))
        }
    }
}
