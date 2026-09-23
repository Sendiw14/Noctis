import Foundation
import SleepKit

/// Every detector here is a plain comparison over real, already-computed
/// metrics — no model, nothing invented. The AI Coach later turns these into
/// conversational language; this engine decides *whether* something is worth
/// saying and supplies the evidence for it.
public enum InsightEngine {
    /// The richest detector's window (`consistencyTrendInsight`) — the
    /// honest answer to "how much history until NOCTIS sees everything it
    /// can." Exposed so the UI can show real progress toward it instead of
    /// duplicating the number.
    public static let richestSignalWindow = 28

    public static func generate(scoredSessions: [ScoredSession], recoveryHistory: [RecoveryHistoryPoint]) -> [Insight] {
        var insights: [Insight] = []
        if let insight = bedtimeQualityInsight(scoredSessions) { insights.append(insight) }
        if let insight = durationTrendInsight(scoredSessions) { insights.append(insight) }
        if let insight = consistencyTrendInsight(scoredSessions) { insights.append(insight) }
        if let insight = recoveryTrendInsight(recoveryHistory) { insights.append(insight) }
        return insights
    }

    private static func bedtimeQualityInsight(_ scored: [ScoredSession]) -> Insight? {
        let recent = Array(scored.suffix(20))
        guard recent.count >= 10 else { return nil }

        let sorted = recent.sorted { eveningMinutes($0.session.bedtime) < eveningMinutes($1.session.bedtime) }
        let half = sorted.count / 2
        let earlier = Array(sorted.prefix(half))
        let later = Array(sorted.suffix(sorted.count - half))

        let earlierQuality = average(earlier.map { Double($0.quality.overall) })
        let laterQuality = average(later.map { Double($0.quality.overall) })
        guard abs(earlierQuality - laterQuality) >= 8 else { return nil }

        let earlierBedtime = formatClock(average(earlier.map { eveningMinutes($0.session.bedtime) }))
        let laterBedtime = formatClock(average(later.map { eveningMinutes($0.session.bedtime) }))

        return Insight(
            kind: "bedtimeQuality",
            category: .timing,
            title: "Your best nights follow earlier bedtimes.",
            evidence: [
                InsightEvidencePoint(label: earlierBedtime, value: "\(Int(earlierQuality))% average quality"),
                InsightEvidencePoint(label: laterBedtime, value: "\(Int(laterQuality))% average quality"),
            ],
            context: "Based on your last \(recent.count) nights, split by bedtime.",
            interpretation: "Your recent data suggests earlier nights have coincided with better sleep quality.",
            whatToNotice: "Nights that started before \(earlierBedtime) scored noticeably higher.",
            suggestion: "Try protecting a bedtime around \(earlierBedtime) a few nights this week.",
            confidence: recent.count >= 16 ? .high : .moderate
        )
    }

    private static func durationTrendInsight(_ scored: [ScoredSession]) -> Insight? {
        guard scored.count >= 14 else { return nil }
        let last7 = Array(scored.suffix(7))
        let previous7 = Array(scored.suffix(14).prefix(7))

        let recentAvg = average(last7.map { $0.session.totalAsleep / 3600 })
        let priorAvg = average(previous7.map { $0.session.totalAsleep / 3600 })
        let deltaMinutes = (recentAvg - priorAvg) * 60
        guard abs(deltaMinutes) >= 25 else { return nil }

        let direction = deltaMinutes > 0 ? "increased" : "decreased"
        return Insight(
            kind: "durationTrend",
            category: .sleep,
            title: "Your sleep duration has \(direction).",
            evidence: [
                InsightEvidencePoint(label: "This week", value: formatHours(recentAvg)),
                InsightEvidencePoint(label: "Previous week", value: formatHours(priorAvg)),
            ],
            context: "Comparing your last 7 nights with the 7 nights before that.",
            interpretation: "Your recent data suggests a real week-over-week shift in how long you're sleeping.",
            whatToNotice: "The change is about \(Int(abs(deltaMinutes))) minutes a night.",
            confidence: .moderate
        )
    }

    private static func consistencyTrendInsight(_ scored: [ScoredSession]) -> Insight? {
        guard scored.count >= richestSignalWindow else { return nil }
        let sessions = scored.map(\.session)
        let recentStddev = SleepMetricsEngine.bedtimeVariabilityMinutes(recentMainSessions: Array(sessions.suffix(14)))
        let priorStddev = SleepMetricsEngine.bedtimeVariabilityMinutes(recentMainSessions: Array(sessions.suffix(28).prefix(14)))
        let improvement = priorStddev - recentStddev
        guard improvement >= 12 else { return nil }

        return Insight(
            kind: "consistencyTrend",
            category: .consistency,
            title: "Your bedtime has become more consistent.",
            evidence: [
                InsightEvidencePoint(label: "Last 2 weeks", value: "±\(Int(recentStddev)) min"),
                InsightEvidencePoint(label: "2 weeks before", value: "±\(Int(priorStddev)) min"),
            ],
            context: "Comparing bedtime variability across your last 4 weeks.",
            interpretation: "Your recent data suggests your sleep schedule has steadied.",
            whatToNotice: "Less night-to-night variation in when you go to bed.",
            confidence: .moderate
        )
    }

    private static func recoveryTrendInsight(_ history: [RecoveryHistoryPoint]) -> Insight? {
        guard history.count >= 14 else { return nil }
        let last7 = Array(history.suffix(7))
        let previous7 = Array(history.suffix(14).prefix(7))
        let recentAvg = average(last7.map { Double($0.score) })
        let priorAvg = average(previous7.map { Double($0.score) })
        let delta = recentAvg - priorAvg
        guard abs(delta) >= 6 else { return nil }

        let direction = delta > 0 ? "improved" : "declined"
        return Insight(
            kind: "recoveryTrend",
            category: .recovery,
            title: "Your recovery has \(direction) this week.",
            evidence: [
                InsightEvidencePoint(label: "This week", value: "\(Int(recentAvg))"),
                InsightEvidencePoint(label: "Previous week", value: "\(Int(priorAvg))"),
            ],
            context: "Comparing your average recovery score across the last two weeks.",
            interpretation: "This has coincided with the sleep and heart-rate changes seen over the same period.",
            whatToNotice: "A \(Int(abs(delta)))-point shift in your weekly average.",
            confidence: .moderate
        )
    }

    // MARK: - Helpers

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func formatHours(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }

    private static func eveningMinutes(_ date: Date, calendar: Calendar = .current) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        return minutes < 12 * 60 ? minutes + 24 * 60 : minutes
    }

    private static func formatClock(_ minutesOnEveningScale: Double) -> String {
        let normalized = minutesOnEveningScale.truncatingRemainder(dividingBy: 24 * 60)
        let hour24 = Int(normalized) / 60
        let minute = Int(normalized) % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let period = hour24 < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", hour12, minute, period)
    }
}
