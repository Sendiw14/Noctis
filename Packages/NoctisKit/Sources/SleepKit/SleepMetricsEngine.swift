import Foundation

public struct SleepQualityBreakdown: Sendable, Equatable {
    public let overall: Int
    public let duration: Int
    public let timing: Int
    public let continuity: Int
    public let consistency: Int
}

public struct SleepBalance: Sendable, Equatable {
    /// Signed cumulative hours across the window: negative is debt, positive is surplus.
    public let balanceHours: Double
    public let rollingAverageHours: Double
    public let needHours: Double
}

/// All scores here are deterministic and versioned — the AI layer explains
/// them, it never computes or overrides them.
public enum SleepMetricsEngine {
    public static let modelVersion = 1

    public static func qualityBreakdown(for session: SleepSession, recentMainSessions: [SleepSession]) -> SleepQualityBreakdown {
        let hours = session.totalAsleep / 3600
        let durationScore = scoreCurve(value: hours, target: 8.0, tolerance: 2.4)

        let efficiency = session.sleepEfficiency
        let awakenings = session.awakeningsCount
        let continuityScore = clamp(Int((efficiency * 100).rounded()) - max(0, awakenings - 1) * 4)

        let remPct = session.totalAsleep > 0 ? session.remDuration / session.totalAsleep : 0
        let deepPct = session.totalAsleep > 0 ? session.deepDuration / session.totalAsleep : 0
        let hasStageData = session.remDuration + session.deepDuration + session.coreDuration > 0
        let stageScore = hasStageData
            ? clamp(100 - Int(abs(remPct - 0.215) * 260) - Int(abs(deepPct - 0.18) * 260))
            : 70

        let recentBedtimes = recentMainSessions.suffix(14).map { minutesOnEveningScale($0.bedtime) }
        let consistency = consistencyScore(from: recentBedtimes)

        let referenceBedtime = averageOrDefault(recentBedtimes)
        let timingScore = clamp(100 - Int(abs(minutesOnEveningScale(session.bedtime) - referenceBedtime) / 2))

        let overall = clamp(Int(
            Double(durationScore) * 0.34
                + Double(continuityScore) * 0.24
                + Double(stageScore) * 0.16
                + Double(consistency) * 0.16
                + Double(timingScore) * 0.10
        ))

        return SleepQualityBreakdown(overall: overall, duration: durationScore, timing: timingScore, continuity: continuityScore, consistency: consistency)
    }

    public static func balance(recentMainSessions: [SleepSession], needHours: Double = 8.0, window: Int = 14) -> SleepBalance {
        let recent = Array(recentMainSessions.suffix(window))
        guard !recent.isEmpty else {
            return SleepBalance(balanceHours: 0, rollingAverageHours: needHours, needHours: needHours)
        }
        let hoursList = recent.map { $0.totalAsleep / 3600 }
        let average = hoursList.reduce(0, +) / Double(hoursList.count)
        let cumulativeDeficit = hoursList.reduce(0.0) { $0 + ($1 - needHours) }
        return SleepBalance(balanceHours: cumulativeDeficit, rollingAverageHours: average, needHours: needHours)
    }

    public static func bedtimeVariabilityMinutes(recentMainSessions: [SleepSession], window: Int = 14) -> Double {
        let values = recentMainSessions.suffix(window).map { minutesOnEveningScale($0.bedtime) }
        return standardDeviation(of: values)
    }

    public static func waketimeVariabilityMinutes(recentMainSessions: [SleepSession], window: Int = 14) -> Double {
        let values = recentMainSessions.suffix(window).map { minutesSinceMidnight($0.wakeTime) }
        return standardDeviation(of: values)
    }

    // MARK: - Helpers

    private static func scoreCurve(value: Double, target: Double, tolerance: Double) -> Int {
        let deviation = abs(value - target)
        return Int((100.0 * max(0, 1 - deviation / tolerance)).rounded())
    }

    private static func clamp(_ value: Int) -> Int { min(max(value, 0), 100) }

    private static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }

    /// Bedtimes cluster around midnight, so 11 PM and 12:30 AM are 90 minutes
    /// apart, not ~23 hours — shift the small-hours side onto a 24h+ scale.
    private static func minutesOnEveningScale(_ date: Date, calendar: Calendar = .current) -> Double {
        let minutes = minutesSinceMidnight(date, calendar: calendar)
        return minutes < 12 * 60 ? minutes + 24 * 60 : minutes
    }

    private static func averageOrDefault(_ values: [Double], default fallback: Double = 23 * 60) -> Double {
        guard !values.isEmpty else { return fallback }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(of values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }

    private static func consistencyScore(from values: [Double]) -> Int {
        guard values.count >= 3 else { return 65 }
        let stddev = standardDeviation(of: values)
        return clamp(Int((100.0 * max(0, 1 - stddev / 75.0)).rounded()))
    }
}
