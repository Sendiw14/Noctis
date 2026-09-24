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
/// Returns the single most relevant insight, or none. A shift outranks a
/// streak; between two shifts the larger one (in minutes) wins, with
/// duration winning a tie. Nothing fires without a baseline (5+ nights).
public enum InsightEngine {
    public static let shiftThresholdMinutes: Double = 30
    public static let streakToleranceMinutes: Double = 30
    public static let minimumStreakNights = 5

    /// The top insight for the most recent night in `history` that ended
    /// within the last 24 hours, or nil.
    public static func topInsight(history: [NightMetrics], asOf now: Date) -> Insight? {
        let complete = history.filter { $0.wakeTime <= now }
        guard let lastNight = complete.max(by: { $0.wakeTime < $1.wakeTime }),
              now.timeIntervalSince(lastNight.wakeTime) <= RecoveryModelV1.lastNightWindow else { return nil }
        let baselines = BaselineEngine.baselines(for: lastNight.night, history: complete)
        return topInsight(lastNight: lastNight, baselines: baselines, history: complete)
    }

    public static func topInsight(lastNight: NightMetrics, baselines: Baselines, history: [NightMetrics]) -> Insight? {
        let shifts = [durationShift(lastNight, baselines), bedtimeShift(lastNight, baselines)].compactMap { $0 }
        // Strict `>` keeps the earlier entry on a tie: duration is listed first.
        if let top = shifts.reduce(nil, { best, next -> Insight? in
            guard let best else { return next }
            return abs(next.evidence.delta) > abs(best.evidence.delta) ? next : best
        }) {
            return top
        }
        return consistentBedtime(lastNight, baselines, history: history)
    }

    // MARK: - Rules

    static func durationShift(_ night: NightMetrics, _ baselines: Baselines) -> Insight? {
        guard let baseline = baselines.sleepDuration else { return nil }
        let delta = night.asleepMinutes - baseline.value
        guard abs(delta).rounded() >= shiftThresholdMinutes else { return nil }
        let less = delta < 0
        return Insight(
            kind: .sleepDurationShift,
            title: less ? "Shorter night than usual" : "Longer night than usual",
            message: "Compared with your recent baseline, you slept \(formatMinutes(abs(delta))) \(less ? "less" : "more") last night.",
            evidence: InsightEvidence(night: night.night, value: night.asleepMinutes, baseline: baseline.value, delta: delta, baselineNights: baseline.nights)
        )
    }

    static func bedtimeShift(_ night: NightMetrics, _ baselines: Baselines) -> Insight? {
        guard let baseline = baselines.bedtime else { return nil }
        let delta = night.bedtimeMinutes - baseline.value
        guard abs(delta).rounded() >= shiftThresholdMinutes else { return nil }
        let later = delta > 0
        return Insight(
            kind: .bedtimeShift,
            title: later ? "Later bedtime than usual" : "Earlier bedtime than usual",
            message: "Compared with your recent baseline, you went to bed \(formatMinutes(abs(delta))) \(later ? "later" : "earlier") last night.",
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
        return Insight(
            kind: .consistentBedtime,
            title: "Steady bedtime",
            message: "Compared with your recent baseline, you went to bed within 30 minutes of your typical time for \(streak) nights in a row.",
            evidence: InsightEvidence(
                night: night.night,
                value: night.bedtimeMinutes,
                baseline: baseline.value,
                delta: night.bedtimeMinutes - baseline.value,
                baselineNights: baseline.nights,
                streakNights: streak
            )
        )
    }

    /// "45 min", "1h", "1h 10m".
    static func formatMinutes(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        guard rounded >= 60 else { return "\(rounded) min" }
        let hours = rounded / 60
        let remainder = rounded % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
