import DesignSystem
import Foundation
import InsightsKit
import SleepKit

// The insight block's words and evidence chart, from `InsightEngine`'s
// evidence (the engine hands over numbers, never sentences).

nonisolated extension HomeScreenBuilder {
    /// The featured insight, whichever rule found it: the first three keep
    /// their small charts; the rest show their two numbers.
    static func insightCard(_ record: InsightRecord, format: HomeFormat) -> InsightCardContent {
        if case .baseline(let evidence) = record.evidence, let kind = record.type.baselineKind {
            return insightCard(Insight(kind: kind, evidence: evidence), format: format, id: record.id)
        }
        let words = InsightScreenBuilder.build(record, format: format)
        return InsightCardContent(
            id: record.id, title: words.title, message: words.rowLine,
            chart: .figures(words.comparison, join: words.comparisonJoin),
            accessibilityLabel: "\(words.title). \(words.rowLine)"
        )
    }

    static func insightCard(_ insight: Insight, format: HomeFormat, id: String = "") -> InsightCardContent {
        let evidence = insight.evidence
        let minutes = Int(abs(evidence.delta).rounded())
        let amount = HomeFormat.compactDuration(minutes, minutesWord: true)
        switch insight.kind {
        case .sleepDurationShift:
            let less = evidence.delta < 0
            let title = less ? "Shorter night than usual" : "Longer night than usual"
            let lastNight = HomeFormat.durationMetric(Int(evidence.value.rounded()))
            let usual = HomeFormat.durationMetric(Int(evidence.baseline.rounded()))
            let longest = max(evidence.value, evidence.baseline, 1)
            return InsightCardContent(
                id: id,
                title: title,
                message: "\(amount) \(less ? "less" : "more") than your usual.",
                chart: .comparison(
                    lastNight: InsightBar(label: "Last night", value: lastNight, fraction: evidence.value / longest),
                    usual: InsightBar(label: "Usual", value: usual, fraction: evidence.baseline / longest)
                ),
                accessibilityLabel: "\(title). Last night \(lastNight.spoken); usual \(usual.spoken)."
            )
        case .bedtimeShift:
            let later = evidence.delta > 0
            let title = later ? "Later bedtime than usual" : "Earlier bedtime than usual"
            // Whole hours around both times, with at least half an hour
            // of room on each side (minutes after noon).
            let start = ((min(evidence.value, evidence.baseline) - 30) / 60).rounded(.down) * 60
            let end = ((max(evidence.value, evidence.baseline) + 30) / 60).rounded(.up) * 60
            func position(_ minutes: Double) -> Double { (minutes - start) / max(end - start, 1) }
            let usualTime = format.clock(minutesAfterNoon: evidence.baseline)
            let lastTime = format.clock(minutesAfterNoon: evidence.value)
            return InsightCardContent(
                id: id,
                title: title,
                message: "\(amount) \(later ? "later" : "earlier") than your usual.",
                chart: .timeline(
                    usual: InsightTick(label: "Usual", time: usualTime, position: position(evidence.baseline)),
                    lastNight: InsightTick(label: "Last night", time: lastTime, position: position(evidence.value))
                ),
                accessibilityLabel: "\(title). Last night \(lastTime); usual \(usualTime)."
            )
        case .consistentBedtime:
            let streak = evidence.streakNights ?? 0
            let tolerance = Int(InsightEngine.streakToleranceMinutes)
            // The card draws the last week; the insight's page draws two.
            let recent = Array(evidence.recentNights.suffix(InsightEngine.streakWindowNights))
            let count = recent.count
            let dots = recent.enumerated().map { index, within in
                let morning = evidence.night.adding(days: index - count + 2)
                return InsightNightDot(label: format.weekday(morning, width: .narrow), within: within)
            }
            let withinCount = recent.filter { $0 == true }.count
            let message = "\(streak) nights in a row within \(tolerance) min of your usual bedtime."
            return InsightCardContent(
                id: id,
                title: "Steady bedtime",
                message: message,
                chart: .nights(dots, caption: "Last \(count) nights"),
                accessibilityLabel: "Steady bedtime. \(streak) nights in a row within \(tolerance) minutes of your usual bedtime; "
                    + "\(withinCount) of the last \(count) nights."
            )
        }
    }
}
