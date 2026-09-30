import Foundation
import RecoveryKit
import SleepKit

/// Insight v1: three deterministic rules, each carrying its evidence.
///
/// - `.sleepDurationShift`: last night's sleep is 30+ minutes off the
///   duration baseline.
/// - `.bedtimeShift`: last night's bedtime is 30+ minutes off the bedtime
///   baseline.
/// - `.consistentBedtime`: 5+ nights in a row, ending last night, each
///   within 30 minutes of the bedtime baseline.
///
/// Candidates are ranked: a shift outranks a streak; between two shifts
/// the larger one (in minutes) wins, with duration winning a tie. Nothing
/// fires without a baseline (5+ nights).
///
/// `InsightEngineV2` wraps these three as its rules 1-3; what is shown, and
/// when, is `InsightHistory`'s and `InsightLibrary`'s (fatigue, hiding,
/// dismissing).
public enum InsightEngine {
    public static let shiftThresholdMinutes: Double = 30
    public static let streakToleranceMinutes: Double = 30
    public static let minimumStreakNights = 5
    /// The streak's evidence shows this many nights, ending last night.
    public static let streakWindowNights = 7

    /// Every insight about last night, best first.
    public static func candidates(history: [NightMetrics], asOf now: Date) -> [Insight] {
        let complete = history.filter { $0.wakeTime <= now }
        guard let lastNight = complete.max(by: { $0.wakeTime < $1.wakeTime }),
              now.timeIntervalSince(lastNight.wakeTime) <= RecoveryModelV1.lastNightWindow else { return [] }
        let baselines = BaselineEngine.baselines(for: lastNight.night, history: complete)
        return candidates(lastNight: lastNight, baselines: baselines, history: complete)
    }

    public static func topInsight(lastNight: NightMetrics, baselines: Baselines, history: [NightMetrics]) -> Insight? {
        candidates(lastNight: lastNight, baselines: baselines, history: history).first
    }

    public static func candidates(lastNight: NightMetrics, baselines: Baselines, history: [NightMetrics]) -> [Insight] {
        let shifts = [durationShift(lastNight, baselines), bedtimeShift(lastNight, baselines)].compactMap { $0 }
        // A stable sort keeps the earlier entry on a tie: duration is listed first.
        let ranked = shifts.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (abs(lhs.element.evidence.delta), abs(rhs.element.evidence.delta))
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .map(\.element)
        return ranked + [consistentBedtime(lastNight, baselines, history: history)].compactMap { $0 }
    }

    // MARK: - Rules

    static func durationShift(_ night: NightMetrics, _ baselines: Baselines) -> Insight? {
        guard let baseline = baselines.sleepDuration else { return nil }
        let delta = night.asleepMinutes - baseline.value
        guard abs(delta).rounded() >= shiftThresholdMinutes else { return nil }
        return Insight(
            kind: .sleepDurationShift,
            evidence: InsightEvidence(night: night.night, value: night.asleepMinutes, baseline: baseline.value, delta: delta, baselineNights: baseline.nights)
        )
    }

    static func bedtimeShift(_ night: NightMetrics, _ baselines: Baselines) -> Insight? {
        guard let baseline = baselines.bedtime else { return nil }
        let delta = night.bedtimeMinutes - baseline.value
        guard abs(delta).rounded() >= shiftThresholdMinutes else { return nil }
        return Insight(
            kind: .bedtimeShift,
            evidence: InsightEvidence(night: night.night, value: night.bedtimeMinutes, baseline: baseline.value, delta: delta, baselineNights: baseline.nights)
        )
    }

    static func consistentBedtime(_ night: NightMetrics, _ baselines: Baselines, history: [NightMetrics]) -> Insight? {
        guard let baseline = baselines.bedtime else { return nil }
        let byNight = Dictionary(history.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        var streak = 0
        var key = night.night
        while let metrics = byNight[key], abs(metrics.bedtimeMinutes - baseline.value) <= streakToleranceMinutes {
            streak += 1
            key = key.adding(days: -1)
        }
        guard streak >= minimumStreakNights else { return nil }
        let recent = (0..<streakWindowNights).reversed().map { offset -> Bool? in
            byNight[night.night.adding(days: -offset)].map { abs($0.bedtimeMinutes - baseline.value) <= streakToleranceMinutes }
        }
        return Insight(
            kind: .consistentBedtime,
            evidence: InsightEvidence(
                night: night.night,
                value: night.bedtimeMinutes,
                baseline: baseline.value,
                delta: night.bedtimeMinutes - baseline.value,
                baselineNights: baseline.nights,
                streakNights: streak,
                recentNights: recent
            )
        )
    }
}
