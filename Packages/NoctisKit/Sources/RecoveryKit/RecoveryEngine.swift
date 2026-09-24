import Foundation
import SleepKit

/// Recovery v1 (`RecoveryModelV1`): a 0–100 score from four factors, each
/// judged against the person's own 14-night baseline. Deterministic: time
/// comes in as `now`, never read from the clock.
///
/// - Under 5 nights of history: `.learning(nightsSoFar:)`.
/// - No main sleep that ended in the last 24 hours: `.noSleepLastNight`.
///   There is never a score without last night's sleep.
/// - Otherwise `.scored`: factors without data (or without a baseline)
///   are dropped and the remaining weights renormalized.
public enum RecoveryEngine {
    public static func evaluate(history: [NightMetrics], needMinutes: Double, asOf now: Date) -> RecoveryState {
        let complete = history.filter { $0.wakeTime <= now }
        guard complete.count >= RecoveryModelV1.learningNights else {
            return .learning(nightsSoFar: complete.count)
        }
        guard let lastNight = complete.max(by: { $0.wakeTime < $1.wakeTime }),
              now.timeIntervalSince(lastNight.wakeTime) <= RecoveryModelV1.lastNightWindow else {
            return .noSleepLastNight
        }
        let baselines = BaselineEngine.baselines(for: lastNight.night, history: complete)
        let window = BaselineEngine.window(for: lastNight.night, in: complete)
        let today = score(lastNight: lastNight, baselines: baselines, baselineNights: window.count, needMinutes: needMinutes)
        // Each night in the window, scored exactly as today was — skipping
        // nights that were still in the learning state themselves.
        let scorable = window.filter { night in
            complete.count { $0.night <= night.night } >= RecoveryModelV1.learningNights
        }
        let windowScores = scorable.map { night in
            Double(score(
                lastNight: night,
                baselines: BaselineEngine.baselines(for: night.night, history: complete),
                baselineNights: BaselineEngine.window(for: night.night, in: complete).count,
                needMinutes: needMinutes
            ).score)
        }
        return .scored(today.with(comparison: comparison(score: today.score, windowScores: windowScores)))
    }

    /// Today's score against the mean of the window's scores; no
    /// baseline under `BaselineEngine.minimumNights` scored nights.
    public static func comparison(score: Int, windowScores: [Double]) -> RecoveryComparison {
        guard let baseline = BaselineEngine.baseline(windowScores) else {
            return RecoveryComparison(baseline: nil, nights: windowScores.count, delta: nil)
        }
        return RecoveryComparison(baseline: baseline.value, nights: baseline.nights, delta: Int((Double(score) - baseline.value).rounded()))
    }

    public static func score(lastNight: NightMetrics, baselines: Baselines, baselineNights: Int, needMinutes: Double) -> RecoveryResult {
        let raw = [
            durationFactor(lastNight, baselines, needMinutes: needMinutes),
            consistencyFactor(lastNight, baselines),
            hrvFactor(lastNight, baselines),
            restingFactor(lastNight, baselines),
        ].compactMap { $0 }

        let totalWeight = raw.reduce(0) { $0 + (RecoveryModelV1.weights[$1.kind] ?? 0) }
        let factors = raw.map { factor in
            RecoveryFactor(
                kind: factor.kind,
                score: Int(factor.score.rounded()),
                weight: totalWeight > 0 ? (RecoveryModelV1.weights[factor.kind] ?? 0) / totalWeight : 0,
                value: factor.value,
                baseline: factor.baseline,
                delta: factor.delta
            )
        }
        let weighted = raw.reduce(0) { $0 + $1.score * (RecoveryModelV1.weights[$1.kind] ?? 0) }
        let overall = totalWeight > 0 ? weighted / totalWeight : 0

        return RecoveryResult(
            night: lastNight.night,
            score: Int(overall.rounded()),
            factors: factors,
            confidence: confidence(factorCount: factors.count, baselineNights: baselineNights),
            baselineNights: baselineNights,
            modelVersion: RecoveryModelV1.version,
            baselines: baselines,
            missingFactors: gaps(lastNight, baselines, used: Set(factors.map(\.kind)))
        )
    }

    /// Why each unused factor is missing.
    static func gaps(_ night: NightMetrics, _ baselines: Baselines, used: Set<RecoveryFactorKind>) -> [RecoveryFactorKind: RecoveryFactorGap] {
        var gaps: [RecoveryFactorKind: RecoveryFactorGap] = [:]
        for kind in RecoveryFactorKind.allCases where !used.contains(kind) {
            switch kind {
            case .sleepDuration:
                gaps[kind] = .unavailable
            case .sleepConsistency:
                gaps[kind] = .buildingBaseline
            case .hrv:
                gaps[kind] = night.hrv == nil ? (baselines.hrvNights > 0 ? .notRecorded : .unavailable) : .buildingBaseline
            case .restingHeartRate:
                gaps[kind] = night.restingHeartRate == nil
                    ? (baselines.restingHeartRateNights > 0 ? .notRecorded : .unavailable)
                    : .buildingBaseline
            }
        }
        return gaps
    }

    /// High: all four factors and a full 14-night window. Moderate: three
    /// or more factors, or seven or more nights. Low: anything less.
    public static func confidence(factorCount: Int, baselineNights: Int) -> RecoveryConfidence {
        if factorCount == RecoveryFactorKind.allCases.count && baselineNights >= RecoveryModelV1.highConfidenceNights {
            return .high
        }
        if factorCount >= RecoveryModelV1.moderateConfidenceFactors || baselineNights >= RecoveryModelV1.moderateConfidenceNights {
            return .moderate
        }
        return .low
    }

    // MARK: - Factors

    private struct RawFactor {
        let kind: RecoveryFactorKind
        let score: Double
        let value: Double
        let baseline: Double?
        let delta: Double?
    }

    private static func durationFactor(_ night: NightMetrics, _ baselines: Baselines, needMinutes: Double) -> RawFactor? {
        guard needMinutes > 0 else { return nil }
        let ratio = night.asleepMinutes / needMinutes
        let score = ratio >= 1 ? 100 : 100 - (1 - ratio) * RecoveryModelV1.durationPointsPerShortfall
        let baseline = baselines.sleepDuration?.value
        return RawFactor(kind: .sleepDuration, score: clamp(score), value: night.asleepMinutes, baseline: baseline, delta: baseline.map { night.asleepMinutes - $0 })
    }

    private static func consistencyFactor(_ night: NightMetrics, _ baselines: Baselines) -> RawFactor? {
        guard let bedtime = baselines.bedtime?.value, let wake = baselines.wakeTime?.value else { return nil }
        let deviation = (abs(night.bedtimeMinutes - bedtime) + abs(night.wakeMinutes - wake)) / 2
        let score = 100 * (1 - deviation / RecoveryModelV1.consistencyZeroAtMinutes)
        return RawFactor(kind: .sleepConsistency, score: clamp(score), value: deviation, baseline: nil, delta: night.bedtimeMinutes - bedtime)
    }

    private static func hrvFactor(_ night: NightMetrics, _ baselines: Baselines) -> RawFactor? {
        guard let hrv = night.hrv, let baseline = baselines.hrv?.value, baseline > 0 else { return nil }
        let score = 50 + (hrv / baseline - 1) * RecoveryModelV1.hrvPointsPerRatio
        return RawFactor(kind: .hrv, score: clamp(score), value: hrv, baseline: baseline, delta: hrv - baseline)
    }

    private static func restingFactor(_ night: NightMetrics, _ baselines: Baselines) -> RawFactor? {
        guard let resting = night.restingHeartRate, let baseline = baselines.restingHeartRate?.value else { return nil }
        let score = 50 - (resting - baseline) * RecoveryModelV1.restingPointsPerBPM
        return RawFactor(kind: .restingHeartRate, score: clamp(score), value: resting, baseline: baseline, delta: resting - baseline)
    }

    private static func clamp(_ score: Double) -> Double {
        min(max(score, 0), 100)
    }
}
