import Foundation
import SleepKit

/// Recovery: a 0–100 score from four factors, each judged against the
/// person's own 14-night baseline. The app runs `RecoveryModel.current`
/// (V3, `RecoveryModelV3`); V1 and V2 stay for their tests.
/// Deterministic: time comes in as `now`, never read from the clock.
///
/// - Under 5 nights of history: `.learning(nightsSoFar:)`.
/// - No main sleep that ended in the last 24 hours: `.noSleepLastNight`.
///   There is never a score without last night's sleep.
/// - Otherwise `.scored`: factors without data (or without a baseline)
///   are dropped and the remaining weights renormalized.
public enum RecoveryEngine {
    public static func evaluate(history: [NightMetrics], needMinutes: Double, asOf now: Date, model: RecoveryModel = .current) -> RecoveryState {
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
        let today = score(lastNight: lastNight, baselines: baselines, baselineNights: window.count, needMinutes: needMinutes, model: model)
        // Each night in the window, scored exactly as today was (same
        // model) — skipping nights that were still in the learning state
        // themselves.
        let windowScores = window.compactMap { night in
            scoreAsOfThatMorning(night, complete: complete, needMinutes: needMinutes, model: model).map { Double($0) }
        }
        return .scored(today.with(comparison: comparison(score: today.score, windowScores: windowScores)))
    }

    /// Each of `nights` scored as its own morning's recovery was: the
    /// same model against that night's own baselines. A night without
    /// sleep, not yet over at `now`, or from while the person was still
    /// learning (under 5 nights) has no score.
    public static func nightlyScores(history: [NightMetrics], nights: [SleepNightKey], needMinutes: Double, asOf now: Date, model: RecoveryModel = .current) -> [SleepNightKey: Int] {
        let complete = history.filter { $0.wakeTime <= now }
        let byNight = Dictionary(complete.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        var scores: [SleepNightKey: Int] = [:]
        for key in nights {
            guard let night = byNight[key],
                  let score = scoreAsOfThatMorning(night, complete: complete, needMinutes: needMinutes, model: model) else { continue }
            scores[key] = score
        }
        return scores
    }

    /// `night` scored with the history up to it, or nil while it was
    /// still in the learning state.
    static func scoreAsOfThatMorning(_ night: NightMetrics, complete: [NightMetrics], needMinutes: Double, model: RecoveryModel) -> Int? {
        guard complete.count(where: { $0.night <= night.night }) >= RecoveryModelV1.learningNights else { return nil }
        return score(
            lastNight: night,
            baselines: BaselineEngine.baselines(for: night.night, history: complete),
            baselineNights: BaselineEngine.window(for: night.night, in: complete).count,
            needMinutes: needMinutes,
            model: model
        ).score
    }

    /// Today's score against the mean of the window's scores; no
    /// baseline under `BaselineEngine.minimumNights` scored nights.
    public static func comparison(score: Int, windowScores: [Double]) -> RecoveryComparison {
        guard let baseline = BaselineEngine.baseline(windowScores) else {
            return RecoveryComparison(baseline: nil, nights: windowScores.count, delta: nil)
        }
        return RecoveryComparison(baseline: baseline.value, nights: baseline.nights, delta: Int((Double(score) - baseline.value).rounded()))
    }

    public static func score(
        lastNight: NightMetrics,
        baselines: Baselines,
        baselineNights: Int,
        needMinutes: Double,
        model: RecoveryModel = .current
    ) -> RecoveryResult {
        let raw = [
            durationFactor(lastNight, baselines, needMinutes: needMinutes),
            consistencyFactor(lastNight, baselines),
            model.scoresVariation ? hrvFactorV2(lastNight, baselines) : hrvFactorV1(lastNight, baselines),
            model.scoresVariation ? restingFactorV2(lastNight, baselines) : restingFactorV1(lastNight, baselines),
        ].compactMap { $0 }

        let weights = model.weights
        let totalWeight = raw.reduce(0) { $0 + (weights[$1.kind] ?? 0) }
        let factors = raw.map { factor in
            RecoveryFactor(
                kind: factor.kind,
                score: Int(factor.score.rounded()),
                weight: totalWeight > 0 ? (weights[factor.kind] ?? 0) / totalWeight : 0,
                value: factor.value,
                baseline: factor.baseline,
                delta: factor.delta,
                standardScore: factor.standardScore
            )
        }
        let weighted = raw.reduce(0) { $0 + $1.score * (weights[$1.kind] ?? 0) }
        var overall = totalWeight > 0 ? weighted / totalWeight : 0
        let heartCapApplied = model == .v3 && heartSignalsBothFarOff(raw)
        if heartCapApplied {
            overall = min(overall, Double(RecoveryModelV3.heartCapScore))
        }

        return RecoveryResult(
            night: lastNight.night,
            score: Int(overall.rounded()),
            factors: factors,
            confidence: confidence(factorCount: factors.count, baselineNights: baselineNights, model: model),
            baselineNights: baselineNights,
            modelVersion: model.version,
            baselines: baselines,
            missingFactors: gaps(lastNight, baselines, used: Set(factors.map(\.kind))),
            heartCapApplied: heartCapApplied
        )
    }

    /// V3's cap: HRV at least 1.5 SD below baseline and resting heart rate
    /// at least 1.5 SD above it (both directional scores ≤ −1.5).
    static func heartSignalsBothFarOff(_ factors: [RawFactor]) -> Bool {
        let limit = -RecoveryModelV3.heartCapStandardDeviations
        guard let hrv = factors.first(where: { $0.kind == .hrv })?.standardScore,
              let resting = factors.first(where: { $0.kind == .restingHeartRate })?.standardScore else { return false }
        return hrv <= limit && resting <= limit
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

    /// High: all four factors and a full 14-night window. Moderate: V2
    /// needs three or more factors AND seven or more nights (V1: either).
    /// Low: anything less.
    public static func confidence(factorCount: Int, baselineNights: Int, model: RecoveryModel = .current) -> RecoveryConfidence {
        if factorCount == RecoveryFactorKind.allCases.count && baselineNights >= RecoveryModelV1.highConfidenceNights {
            return .high
        }
        let enoughFactors = factorCount >= RecoveryModelV1.moderateConfidenceFactors
        let enoughNights = baselineNights >= RecoveryModelV1.moderateConfidenceNights
        switch model {
        case .v1: return enoughFactors || enoughNights ? .moderate : .low
        case .v2, .v3: return enoughFactors && enoughNights ? .moderate : .low
        }
    }

    // MARK: - Factors

    struct RawFactor {
        let kind: RecoveryFactorKind
        let score: Double
        let value: Double
        let baseline: Double?
        let delta: Double?
        var standardScore: Double?
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

    // V1: raw differences.

    private static func hrvFactorV1(_ night: NightMetrics, _ baselines: Baselines) -> RawFactor? {
        guard let hrv = night.hrv, let baseline = baselines.hrv?.value, baseline > 0 else { return nil }
        let score = 50 + (hrv / baseline - 1) * RecoveryModelV1.hrvPointsPerRatio
        return RawFactor(kind: .hrv, score: clamp(score), value: hrv, baseline: baseline, delta: hrv - baseline)
    }

    private static func restingFactorV1(_ night: NightMetrics, _ baselines: Baselines) -> RawFactor? {
        guard let resting = night.restingHeartRate, let baseline = baselines.restingHeartRate?.value else { return nil }
        let score = 50 - (resting - baseline) * RecoveryModelV1.restingPointsPerBPM
        return RawFactor(kind: .restingHeartRate, score: clamp(score), value: resting, baseline: baseline, delta: resting - baseline)
    }

    // V2: standard deviations of the person's own 14-night variation.
    // score = clamp(75 + 15·z), z in the good direction.

    private static func hrvFactorV2(_ night: NightMetrics, _ baselines: Baselines) -> RawFactor? {
        guard let hrv = night.hrv, let baseline = baselines.hrv else { return nil }
        let spread = max(baseline.standardDeviation, RecoveryModelV2.hrvStandardDeviationFloor)
        let z = (hrv - baseline.value) / spread
        return RawFactor(kind: .hrv, score: variationScore(z), value: hrv, baseline: baseline.value, delta: hrv - baseline.value, standardScore: z)
    }

    private static func restingFactorV2(_ night: NightMetrics, _ baselines: Baselines) -> RawFactor? {
        guard let resting = night.restingHeartRate, let baseline = baselines.restingHeartRate else { return nil }
        let spread = max(baseline.standardDeviation, RecoveryModelV2.restingStandardDeviationFloor)
        let z = (baseline.value - resting) / spread
        return RawFactor(kind: .restingHeartRate, score: variationScore(z), value: resting, baseline: baseline.value, delta: resting - baseline.value, standardScore: z)
    }

    static func variationScore(_ z: Double) -> Double {
        clamp(RecoveryModelV2.variationCenter + RecoveryModelV2.pointsPerStandardDeviation * z)
    }

    private static func clamp(_ score: Double) -> Double {
        min(max(score, 0), 100)
    }
}
