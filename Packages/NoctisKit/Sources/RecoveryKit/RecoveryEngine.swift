import Foundation
import HealthProviding

/// Deterministic and versioned on purpose: the AI Coach explains this score,
/// it never computes it. If an input is missing, its factor is simply absent
/// from the breakdown — the score is renormalized over what's actually known,
/// and confidence drops accordingly. Nothing is ever invented.
public enum RecoveryEngine {
    public static let modelVersion = 1

    private static let weights: [RecoveryFactorKind: Double] = [
        .sleep: 0.34,
        .hrv: 0.26,
        .restingHeartRate: 0.18,
        .consistency: 0.14,
        .load: 0.08,
    ]

    public static func computeScore(_ input: RecoveryInput) -> RecoveryScore {
        var factors: [RecoveryFactor] = []
        var weightedSum = 0.0
        var weightUsed = 0.0

        if let sleepScore = input.sleepQualityOverall {
            factors.append(RecoveryFactor(
                kind: .sleep,
                score: sleepScore,
                currentValue: input.sleepHours,
                baselineValue: nil,
                unit: "h",
                confidence: .high
            ))
            accumulate(sleepScore, .sleep, &weightedSum, &weightUsed)
        }

        if let hrvToday = input.hrvToday, let baseline = input.hrvBaseline?.averageValue, baseline > 0 {
            let ratio = hrvToday / baseline
            let score = clampScore(50 + (ratio - 1) * 140)
            factors.append(RecoveryFactor(
                kind: .hrv,
                score: score,
                currentValue: hrvToday,
                baselineValue: baseline,
                unit: "ms",
                confidence: input.hrvBaseline?.confidence ?? .low
            ))
            accumulate(score, .hrv, &weightedSum, &weightUsed)
        }

        if let rhrToday = input.restingHRToday, let baseline = input.restingHRBaseline?.averageValue, rhrToday > 0 {
            let ratio = baseline / rhrToday
            let score = clampScore(50 + (ratio - 1) * 300)
            factors.append(RecoveryFactor(
                kind: .restingHeartRate,
                score: score,
                currentValue: rhrToday,
                baselineValue: baseline,
                unit: "bpm",
                confidence: input.restingHRBaseline?.confidence ?? .low
            ))
            accumulate(score, .restingHeartRate, &weightedSum, &weightUsed)
        }

        if let consistencyScore = input.consistencyScore {
            factors.append(RecoveryFactor(
                kind: .consistency,
                score: consistencyScore,
                currentValue: Double(consistencyScore),
                baselineValue: nil,
                unit: "score",
                confidence: .moderate
            ))
            accumulate(consistencyScore, .consistency, &weightedSum, &weightUsed)
        }

        if let loadScore = input.loadScore {
            factors.append(RecoveryFactor(
                kind: .load,
                score: loadScore,
                currentValue: Double(loadScore),
                baselineValue: nil,
                unit: "score",
                confidence: .moderate
            ))
            accumulate(loadScore, .load, &weightedSum, &weightUsed)
        }

        guard weightUsed > 0 else {
            return RecoveryScore(overall: 0, factors: [], confidence: .low, modelVersion: modelVersion, computedAt: .now, deltaVsRecentBaseline: nil)
        }

        let overall = clampScore(weightedSum / weightUsed)
        let delta = input.recentAverageRecovery.map { overall - Int($0.rounded()) }

        return RecoveryScore(
            overall: overall,
            factors: factors,
            confidence: overallConfidence(factorCount: factors.count),
            modelVersion: modelVersion,
            computedAt: .now,
            deltaVsRecentBaseline: delta
        )
    }

    private static func accumulate(_ score: Int, _ kind: RecoveryFactorKind, _ weightedSum: inout Double, _ weightUsed: inout Double) {
        let weight = weights[kind] ?? 0
        weightedSum += Double(score) * weight
        weightUsed += weight
    }

    private static func clampScore(_ value: Double) -> Int { min(max(Int(value.rounded()), 0), 100) }

    private static func overallConfidence(factorCount: Int) -> DataConfidence {
        switch factorCount {
        case 4...: .high
        case 2...3: .moderate
        default: .low
        }
    }
}
