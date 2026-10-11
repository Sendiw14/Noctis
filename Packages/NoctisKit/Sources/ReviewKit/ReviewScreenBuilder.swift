import Foundation
import RecoveryKit
import SleepKit
import NoctisText

// Every word of a review, built from its numbers (APP_RULES.md R39). One type: the screens only lay out what it returns, and one lint test runs every string it can
// make, in every scenario, through the banned-language list. The voice is calm and plain: it says what the numbers say ("Compared with the week before...", "This has
// coincided with..."), claims no cause, uses no medical word, and has no streak, count of days missed or shame in it. A suggestion is said as one thing to try, never as
// something to do.

public nonisolated struct ReviewPageContent: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case cover, sleep, consistency, recovery, heart, timing, insight, records, nextFocus
    }

    public let kind: Kind
    public let headline: String
    /// Lines of evidence, each a sentence built from numbers.
    public let evidence: [String]
    /// A sentence tying two numbers together ("This has coincided with..."), present only when both numbers are in the record and both moved enough.
    public let interpretation: String?
    /// The insights this page points to (ids only; the words are the insight's own).
    public let insightIDs: [String]

    public var id: String { kind.rawValue }

    public var accessibilityLabel: String { ([headline] + evidence + [interpretation].compactMap { $0 }).joined(separator: " ") }
}

public nonisolated struct ReviewScreenContent: Sendable, Equatable {
    public let id: ReviewID
    /// "Your weekly review", "Your September review".
    public let title: String
    /// "Sep 20 – 26", "September 2026".
    public let dateRange: String
    public let pages: [ReviewPageContent]

    public func page(_ kind: ReviewPageContent.Kind) -> ReviewPageContent? { pages.first { $0.kind == kind } }
}

/// What a period with too few nights says, with the real count.
public nonisolated struct ReviewNotReadyContent: Sendable, Equatable {
    public let title: String
    /// "4 of 5 nights".
    public let count: String
    public let detail: String
    public let dateRange: String
}

public nonisolated enum ReviewScreenBuilder {
    // MARK: A review

    public static func build(_ record: ReviewRecord, format: ReviewFormat = ReviewFormat()) -> ReviewScreenContent {
        let words = Words(kind: record.kind)
        var pages: [ReviewPageContent] = [cover(record, words, format), sleep(record, words, format), consistency(record, words, format)]
        if let page = recovery(record, words, format) { pages.append(page) }
        if let page = heart(record, words) { pages.append(page) }
        pages.append(timing(record, words, format))
        if !record.topInsightIDs.isEmpty {
            pages.append(ReviewPageContent(
                kind: .insight, headline: record.kind == .weekly ? "An insight from this week." : "Insights from this month.", evidence: [], interpretation: nil,
                insightIDs: record.topInsightIDs
            ))
        }
        if let page = records(record, format) { pages.append(page) }
        pages.append(nextFocus(record, words))
        return ReviewScreenContent(id: record.id, title: title(record, format), dateRange: dateRange(record.period, format), pages: pages)
    }

    public static func title(_ record: ReviewRecord, _ format: ReviewFormat = ReviewFormat()) -> String {
        switch record.kind {
        case .weekly: "Your weekly review"
        case .monthly: "Your \(format.monthName(record.firstMorning)) review"
        }
    }

    public static func title(kind: ReviewKind) -> String {
        switch kind {
        case .weekly: "Your weekly review"
        case .monthly: "Your monthly review"
        }
    }

    public static func dateRange(_ period: ReviewPeriod, _ format: ReviewFormat = ReviewFormat()) -> String {
        switch period.kind {
        case .weekly: format.range(period.firstMorning, period.lastMorning)
        case .monthly: format.monthYear(period.firstMorning)
        }
    }

    // MARK: Too few nights

    public static func notReady(period: ReviewPeriod, have: Int, need: Int, format: ReviewFormat = ReviewFormat()) -> ReviewNotReadyContent {
        return ReviewNotReadyContent(
            title: "Not enough nights yet", count: "\(have) of \(need) nights so far",
            detail: "Your \(period.kind.rawValue) review appears once there are at least \(need).",
            dateRange: dateRange(period, format)
        )
    }

    /// A period that has not ended: only a link made by hand reaches it. No count is claimed.
    public static func notOver(period: ReviewPeriod, format: ReviewFormat = ReviewFormat()) -> ReviewNotReadyContent {
        let words = Words(kind: period.kind)
        return ReviewNotReadyContent(
            title: "This review isn't ready yet", count: "Ready on \(format.weekdayDay(period.nextMorning))",
            detail: "A \(words.period)'s review is made once the \(words.period) is over.", dateRange: dateRange(period, format)
        )
    }

    // MARK: Words that depend on the kind

    private struct Words {
        let kind: ReviewKind
        var period: String { kind == .weekly ? "week" : "month" }
        /// "the week before".
        var before: String { "the \(period) before" }
        /// "this week".
        var this: String { "this \(period)" }
    }

    // MARK: Cover

    private static func cover(_ record: ReviewRecord, _ words: Words, _ format: ReviewFormat) -> ReviewPageContent {
        var evidence: [String] = []
        let headline: String
        switch record.biggestImprovement {
        case .change(let change):
            headline = "Compared with \(words.before), \(improvement(change.metric))."
            evidence.append(changeEvidence(change, words))
        case .steady:
            // Steady only when nothing moved either way: a change that was not an improvement is still a change, and the headline does not say otherwise.
            if case .change = record.biggestChange {
                headline = "Here is your \(words.period)."
            } else {
                headline = "A steady \(words.period)."
                evidence.append("Compared with \(words.before), nothing moved by much.")
            }
        case .noComparison:
            headline = "Here is your \(words.period)."
            evidence.append("There weren't enough nights in \(words.before) to compare it with.")
        }
        if case .change(let change) = record.biggestChange, record.biggestChange != record.biggestImprovement {
            evidence.append("The biggest change was \(changeSentence(change, words)).")
        }
        evidence.append("\(record.nightsRecorded) of \(record.nightsInPeriod) nights were recorded.")
        return ReviewPageContent(kind: .cover, headline: headline, evidence: evidence, interpretation: nil, insightIDs: [])
    }

    private static func improvement(_ metric: ReviewMetric) -> String {
        switch metric {
        case .duration: "you slept longer"
        case .bedtimeVariation: "your bedtimes were steadier"
        case .recovery: "your recovery averaged higher"
        case .hrv: "your HRV averaged higher"
        case .restingHeartRate: "your resting heart rate averaged lower"
        }
    }

    /// "Average sleep was 6h 42m, up from 6h 5m."
    private static func changeEvidence(_ change: ReviewChange, _ words: Words) -> String {
        let up = change.value > change.previous ? "up" : "down"
        switch change.metric {
        case .duration: return "Average sleep was \(ReviewFormat.duration(change.value)), \(up) from \(ReviewFormat.duration(change.previous))."
        case .bedtimeVariation: return "Bedtime varied by \(ReviewFormat.minutes(change.value)), \(up) from \(ReviewFormat.minutes(change.previous))."
        case .recovery: return "Recovery averaged \(ReviewFormat.number(change.value)), \(up) from \(ReviewFormat.number(change.previous))."
        case .hrv: return "HRV averaged \(ReviewFormat.number(change.value)) ms, \(up) from \(ReviewFormat.number(change.previous)) ms."
        case .restingHeartRate: return "Resting heart rate averaged \(ReviewFormat.number(change.value)) bpm, \(up) from \(ReviewFormat.number(change.previous)) bpm."
        }
    }

    /// "in average sleep, which was 38 min shorter than the week before".
    private static func changeSentence(_ change: ReviewChange, _ words: Words) -> String {
        let higher = change.value > change.previous
        switch change.metric {
        case .duration: return "in average sleep, which was \(ReviewFormat.amount(change.delta)) \(higher ? "longer" : "shorter") than \(words.before)"
        case .bedtimeVariation: return "in how much your bedtime varied, which was \(ReviewFormat.amount(change.delta)) \(higher ? "more" : "less") than \(words.before)"
        case .recovery: return "in average recovery, which was \(ReviewFormat.number(abs(change.delta))) points \(higher ? "higher" : "lower") than \(words.before)"
        case .hrv: return "in average HRV, which was \(ReviewFormat.number(abs(change.delta))) ms \(higher ? "higher" : "lower") than \(words.before)"
        case .restingHeartRate: return "in average resting heart rate, which was \(ReviewFormat.number(abs(change.delta))) bpm \(higher ? "higher" : "lower") than \(words.before)"
        }
    }

    // MARK: Sleep

    private static func sleep(_ record: ReviewRecord, _ words: Words, _ format: ReviewFormat) -> ReviewPageContent {
        let sleep = record.sleep
        var evidence = ["You reached your \(ReviewFormat.duration(Double(sleep.needMinutes))) sleep need on \(sleep.nightsReachedNeed) of \(record.nightsRecorded) nights."]
        if let delta = sleep.deltaMinutes {
            evidence.append(abs(delta) < 1 ? "That is the same as \(words.before)." : "That is \(ReviewFormat.amount(delta)) \(delta > 0 ? "longer" : "shorter") than \(words.before).")
        }
        let staged = record.nights.compactMap(\.stages)
        if staged.count >= ReviewModel.minimumValues {
            let count = Double(staged.count)
            let deep = Double(staged.reduce(0) { $0 + $1.deep }) / count
            let core = Double(staged.reduce(0) { $0 + $1.core }) / count
            let rem = Double(staged.reduce(0) { $0 + $1.rem }) / count
            evidence.append("On average a night had \(ReviewFormat.duration(deep)) deep, \(ReviewFormat.duration(core)) core and \(ReviewFormat.duration(rem)) REM sleep.")
        }
        var interpretation: String?
        if let shift = record.timing.bedtimeShift, let delta = sleep.deltaMinutes {
            if shift >= 30, delta <= -20 {
                interpretation = "The later bedtimes have coincided with shorter nights."
            } else if shift <= -30, delta >= 20 {
                interpretation = "The earlier bedtimes have coincided with longer nights."
            }
        }
        return ReviewPageContent(
            kind: .sleep, headline: "You slept \(ReviewFormat.duration(sleep.averageMinutes)) a night on average.", evidence: evidence, interpretation: interpretation, insightIDs: []
        )
    }

    // MARK: Consistency

    private static func consistency(_ record: ReviewRecord, _ words: Words, _ format: ReviewFormat) -> ReviewPageContent {
        let consistency = record.consistency
        var evidence: [String] = []
        if let delta = consistency.bedtimeSDDelta {
            evidence.append(abs(delta) < 1 ? "Bedtime varied about as much as \(words.before)." : "Bedtime varied \(ReviewFormat.amount(delta)) \(delta < 0 ? "less" : "more") than \(words.before).")
        }
        if let delta = consistency.wakeSDDelta {
            evidence.append(abs(delta) < 1 ? "Wake time varied about as much as \(words.before)." : "Wake time varied \(ReviewFormat.amount(delta)) \(delta < 0 ? "less" : "more") than \(words.before).")
        }
        let bedtimes = record.nights.map(\.bedtimeMinutes)
        if let earliest = bedtimes.min(), let latest = bedtimes.max() {
            evidence.append("Your bedtimes ranged from \(format.clock(minutesAfterNoon: Double(earliest))) to \(format.clock(minutesAfterNoon: Double(latest))).")
        }
        return ReviewPageContent(
            kind: .consistency,
            headline: "Your bedtime varied by \(ReviewFormat.minutes(consistency.bedtimeSD)) and your wake time by \(ReviewFormat.minutes(consistency.wakeSD)).",
            evidence: evidence, interpretation: nil, insightIDs: []
        )
    }

    // MARK: Recovery

    private static func recovery(_ record: ReviewRecord, _ words: Words, _ format: ReviewFormat) -> ReviewPageContent? {
        guard let recovery = record.recovery else { return nil }
        func extreme(_ label: String, _ value: ReviewExtreme) -> String {
            let also = value.alsoOn > 0 ? ", and equalled on \(NoctisCount.otherNights(value.alsoOn))" : ""
            return "The \(label) was \(ReviewFormat.number(value.value)), on \(format.weekdayDay(value.morning))\(also)."
        }
        var evidence = [extreme("highest", recovery.high), extreme("lowest", recovery.low)]
        if let trend = recovery.trend {
            let slope = ReviewFormat.number(abs(trend.pointsPerWeek))
            switch trend.direction {
            case .rising: evidence.append("Across the \(words.period) it rose by about \(slope) points a week.")
            case .lower: evidence.append("Across the \(words.period) it fell by about \(slope) points a week.")
            case .steady: evidence.append("Across the \(words.period) it stayed steady.")
            }
        }
        if let delta = recovery.delta {
            evidence.append(abs(delta) < 0.5 ? "That is about the same as \(words.before)." : "That is \(ReviewFormat.number(abs(delta))) points \(delta > 0 ? "higher" : "lower") than \(words.before).")
        }
        var interpretation: String?
        if let delta = recovery.delta, let sleep = record.sleep.deltaMinutes {
            if delta <= -5, sleep <= -20 {
                interpretation = "The lower recovery has coincided with shorter nights."
            } else if delta >= 5, sleep >= 20 {
                interpretation = "The higher recovery has coincided with longer nights."
            }
        }
        return ReviewPageContent(
            kind: .recovery, headline: "Recovery averaged \(ReviewFormat.number(recovery.average)).", evidence: evidence, interpretation: interpretation, insightIDs: []
        )
    }

    // MARK: Heart

    private static func heart(_ record: ReviewRecord, _ words: Words) -> ReviewPageContent? {
        func line(_ name: String, _ unit: String, _ average: Double, _ delta: Double?) -> String {
            let base = "\(name) averaged \(ReviewFormat.number(average)) \(unit)"
            guard let delta else { return base + "." }
            return abs(delta) < 0.5 ? base + ", about the same as \(words.before)." : base + ", \(ReviewFormat.number(abs(delta))) \(unit) \(delta > 0 ? "higher" : "lower") than \(words.before)."
        }
        var lines: [String] = []
        if let value = record.heart.hrvAverage { lines.append(line("HRV", "ms", value, record.heart.hrvDelta)) }
        if let value = record.heart.restingHeartRateAverage { lines.append(line("Resting heart rate", "bpm", value, record.heart.restingHeartRateDelta)) }
        guard let first = lines.first else { return nil }
        return ReviewPageContent(kind: .heart, headline: first, evidence: Array(lines.dropFirst()), interpretation: nil, insightIDs: [])
    }

    // MARK: Timing

    private static func timing(_ record: ReviewRecord, _ words: Words, _ format: ReviewFormat) -> ReviewPageContent {
        let timing = record.timing
        var evidence: [String] = []
        if let shift = timing.bedtimeShift {
            evidence.append(abs(shift) < 1 ? "Your median bedtime was the same as \(words.before)." : "Your median bedtime was \(ReviewFormat.amount(shift)) \(shift > 0 ? "later" : "earlier") than \(words.before).")
        }
        if let shift = timing.wakeShift {
            evidence.append(abs(shift) < 1 ? "Your median wake time was the same as \(words.before)." : "Your median wake time was \(ReviewFormat.amount(shift)) \(shift > 0 ? "later" : "earlier") than \(words.before).")
        }
        return ReviewPageContent(
            kind: .timing,
            headline: "Your median bedtime was \(format.clock(minutesAfterNoon: timing.medianBedtimeMinutes)) and your median wake time \(format.clock(minutesAfterNoon: timing.medianWakeMinutes)).",
            evidence: evidence, interpretation: nil, insightIDs: []
        )
    }

    // MARK: A month's records

    private static func records(_ record: ReviewRecord, _ format: ReviewFormat) -> ReviewPageContent? {
        guard let monthly = record.monthly else { return nil }
        func also(_ extreme: ReviewExtreme) -> String { extreme.alsoOn > 0 ? ", and equalled on \(NoctisCount.otherNights(extreme.alsoOn))" : "" }
        let longest = monthly.longestNight
        var evidence: [String] = []
        if let best = monthly.highestRecovery {
            evidence.append("Your highest recovery was \(ReviewFormat.number(best.value)), on \(format.weekdayDay(best.morning))\(also(best)).")
        }
        return ReviewPageContent(
            kind: .records, headline: "Your longest night was \(ReviewFormat.duration(longest.value)), on \(format.weekdayDay(longest.morning))\(also(longest)).",
            evidence: evidence, interpretation: nil, insightIDs: []
        )
    }

    // MARK: Next focus

    private static func nextFocus(_ record: ReviewRecord, _ words: Words) -> ReviewPageContent {
        let headline: String
        var evidence: [String]
        switch record.nextFocus {
        case .steadyBedtime(let minutes):
            headline = "One thing to try: a steadier bedtime."
            evidence = ["Your bedtime varied by \(ReviewFormat.minutes(minutes)) \(words.this).", "Going to bed around the same time each night is one way to try."]
        case .sleepNeed(let behind):
            headline = "One thing to try: an earlier night when it suits you."
            evidence = ["Over the last 7 nights you slept \(ReviewFormat.amount(behind)) less than your \(ReviewFormat.duration(Double(record.sleep.needMinutes))) a night."]
        case .gentleShiftBack(let later):
            headline = "One thing to try: moving your bedtime back a little."
            evidence = ["Your median bedtime was \(ReviewFormat.amount(later)) later than \(words.before).", "A few minutes earlier each night is a gentle way to try."]
        case .recentNights(let nights):
            headline = "One thing to try: keeping your next few bedtimes regular."
            evidence = ["Recovery was trending lower across these \(nights) scored nights."]
        case .keepGoing:
            headline = "Nothing stands out to work on."
            evidence = ["Your \(words.period) looked steady, so there is nothing to change."]
        }
        return ReviewPageContent(kind: .nextFocus, headline: headline, evidence: evidence, interpretation: nil, insightIDs: [])
    }

    /// Every string a review can say for `record`, for the lint: pages, headlines, evidence, interpretations and the title.
    public static func allStrings(_ record: ReviewRecord, format: ReviewFormat = ReviewFormat()) -> [String] {
        let content = build(record, format: format)
        return [content.title, content.dateRange] + content.pages.flatMap { [$0.headline] + $0.evidence + [$0.interpretation].compactMap { $0 } }
    }
}
