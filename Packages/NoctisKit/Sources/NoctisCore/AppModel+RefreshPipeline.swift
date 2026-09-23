import Foundation
import HealthProviding
import InsightsKit
import RecoveryKit
import SleepKit

/// The NOCTIS data pipeline, broken into the named stages the architecture
/// is described in:
///
///     Health Data → Session Construction → Metrics → Baselines
///         → Recovery → History → Insights → Presentation
///
/// `AppModel.refresh()` orchestrates these; each stage here is independently
/// readable and named for what it does, not how `refresh()` happens to call
/// it. Two stages don't split as cleanly as the diagram suggests, and it's
/// worth being explicit about why rather than forcing an artificial seam:
///
/// - **Health Data** happens in two calls, not one.
///   `fetchSleepSamples` runs before a "latest night" is known;
///   `fetchSupplementaryHealthData` runs *after* Session Construction
///   determines which night's window to query (HRV/resting-HR are fetched
///   over the whole baseline window, but night-scoped heart-rate and
///   respiration need `latest.bedtime`/`latest.wakeTime` first).
/// - **Recovery** and **History** are computed together in
///   `computeRecoveryAndHistory`. Today's `RecoveryScore.deltaVsRecentBaseline`
///   needs the recent-history average as an input, so History (prior nights)
///   is necessarily computed before today's Recovery score. Splitting them
///   into two independently-orderable stages would mean either scoring
///   history twice or teaching `RecoveryScore` to backfill its own delta —
///   not worth it for what is otherwise a one-line dependency.
extension AppModel {
    // MARK: - Stage: Health Data (sleep)

    func fetchSleepSamples(from start: Date, to end: Date) async throws -> [RawSleepSample] {
        let raw = try await healthProvider.fetchSleepSamples(from: start, to: end)
        return sourceResolver.resolveSleepSamples(raw)
    }

    // MARK: - Stage: Session Construction

    struct SessionConstruction {
        let sessions: [SleepSession]
        let mainSessions: [SleepSession]
        let latest: SleepSession
    }

    func constructSessions(from sleepSamples: [RawSleepSample], asOf now: Date) -> SessionConstruction? {
        let sessions = SleepSessionEngine.buildSessions(from: sleepSamples)
        let mainSessions = SleepSessionEngine.mainSessions(in: sessions)
        guard let latest = SleepSessionEngine.mostRecentMainSession(in: sessions, asOf: now) else {
            return nil
        }
        return SessionConstruction(sessions: sessions, mainSessions: mainSessions, latest: latest)
    }

    // MARK: - Stage: Health Data (supplementary — needs the latest night's window)

    struct SupplementaryHealthData {
        let hrvSamples: [HRVSample]
        let restingSamples: [HeartRateSample]
        let nightHeartRate: [HeartRateSample]
        let nightRespiratory: [RespiratoryRateSample]
    }

    func fetchSupplementaryHealthData(windowStart: Date, now: Date, latest: SleepSession) async throws -> SupplementaryHealthData {
        let hrvSamples = try await healthProvider.fetchHRVSamples(from: windowStart, to: now)
        let restingSamples = try await healthProvider.fetchRestingHeartRate(from: windowStart, to: now)
        let nightHeartRate = try await healthProvider.fetchHeartRateSamples(from: latest.bedtime, to: latest.wakeTime)
        let nightRespiratory = try await healthProvider.fetchRespiratorySamples(from: latest.bedtime, to: latest.wakeTime.addingTimeInterval(3600))

        return SupplementaryHealthData(
            hrvSamples: hrvSamples,
            restingSamples: restingSamples,
            nightHeartRate: sourceResolver.resolveHeartRateSamples(nightHeartRate),
            nightRespiratory: nightRespiratory
        )
    }

    // MARK: - Stage: Metrics

    struct MetricsResult {
        let scored: [ScoredSession]
        let latestScored: ScoredSession
        let balance: SleepBalance
        let consistencyScore: Int
    }

    func computeMetrics(mainSessions: [SleepSession], needHours: Double) -> MetricsResult? {
        let scored: [ScoredSession] = mainSessions.enumerated().map { index, session in
            let priorSessions = Array(mainSessions[..<index])
            let quality = SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: priorSessions)
            return ScoredSession(session: session, quality: quality)
        }
        guard let latestScored = scored.last else { return nil }

        let balance = SleepMetricsEngine.balance(recentMainSessions: mainSessions, needHours: needHours)
        let bedtimeVariability = SleepMetricsEngine.bedtimeVariabilityMinutes(recentMainSessions: mainSessions)
        let consistencyScore = max(0, min(100, 100 - Int(bedtimeVariability)))

        return MetricsResult(scored: scored, latestScored: latestScored, balance: balance, consistencyScore: consistencyScore)
    }

    // MARK: - Stage: Baselines

    struct BaselinesResult {
        let hrv: Baseline
        let resting: Baseline
    }

    func computeBaselines(hrvSamples: [HRVSample], restingSamples: [HeartRateSample], before cutoff: Date) -> BaselinesResult {
        let priorHRVValues = hrvSamples.filter { $0.date < cutoff }.suffix(baselineWindowDays).map(\.sdnnMilliseconds)
        let hrvBaseline = BaselineEngine.baseline(from: Array(priorHRVValues))
        let priorRestingValues = restingSamples.filter { $0.date < cutoff }.suffix(baselineWindowDays).map(\.bpm)
        let restingBaseline = BaselineEngine.baseline(from: Array(priorRestingValues))
        return BaselinesResult(hrv: hrvBaseline, resting: restingBaseline)
    }

    // MARK: - Stage: Recovery + History

    struct RecoveryAndHistory {
        let today: RecoveryScore
        let history: [RecoveryHistoryPoint]
    }

    func computeRecoveryAndHistory(
        scored: [ScoredSession],
        latestScored: ScoredSession,
        hrvSamples: [HRVSample],
        restingSamples: [HeartRateSample],
        baselines: BaselinesResult,
        consistencyScore: Int
    ) -> RecoveryAndHistory {
        let historySlice = Array(scored.suffix(31).dropLast())
        var history: [RecoveryHistoryPoint] = historySlice.map { scoredSession in
            let score = recoveryScore(
                for: scoredSession,
                hrvSamples: hrvSamples,
                restingSamples: restingSamples,
                hrvBaseline: baselines.hrv,
                restingBaseline: baselines.resting,
                consistencyScore: consistencyScore,
                recentAverageRecovery: nil
            )
            return RecoveryHistoryPoint(date: scoredSession.session.wakeTime, score: score.overall)
        }

        let recentAverage = history.isEmpty ? nil : average(history.map { Double($0.score) })
        let today = recoveryScore(
            for: latestScored,
            hrvSamples: hrvSamples,
            restingSamples: restingSamples,
            hrvBaseline: baselines.hrv,
            restingBaseline: baselines.resting,
            consistencyScore: consistencyScore,
            recentAverageRecovery: recentAverage
        )
        history.append(RecoveryHistoryPoint(date: latestScored.session.wakeTime, score: today.overall))

        return RecoveryAndHistory(today: today, history: history)
    }

    private func recoveryScore(
        for scoredSession: ScoredSession,
        hrvSamples: [HRVSample],
        restingSamples: [HeartRateSample],
        hrvBaseline: Baseline,
        restingBaseline: Baseline,
        consistencyScore: Int,
        recentAverageRecovery: Double?
    ) -> RecoveryScore {
        let session = scoredSession.session
        let windowEnd = session.wakeTime.addingTimeInterval(3600)
        let hrvAtNight = hrvSamples.first { $0.date >= session.bedtime && $0.date <= windowEnd }?.sdnnMilliseconds
        let rhrAtNight = restingSamples.first { $0.date >= session.bedtime && $0.date <= windowEnd }?.bpm

        let input = RecoveryInput(
            sleepQualityOverall: scoredSession.quality.overall,
            sleepHours: session.totalAsleep / 3600,
            hrvToday: hrvAtNight,
            hrvBaseline: hrvBaseline,
            restingHRToday: rhrAtNight,
            restingHRBaseline: restingBaseline,
            consistencyScore: consistencyScore,
            loadScore: nil,
            recentAverageRecovery: recentAverageRecovery
        )
        return RecoveryEngine.computeScore(input)
    }

    // MARK: - Stage: Insights

    func generateInsights(scored: [ScoredSession], recoveryHistory: [RecoveryHistoryPoint]) -> [Insight] {
        InsightEngine.generate(scoredSessions: scored, recoveryHistory: recoveryHistory)
    }

    // MARK: - Helpers

    func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
