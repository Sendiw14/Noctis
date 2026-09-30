import DesignSystem
import Foundation
import InsightsKit
import SleepKit

/// One side of a featured insight's two-number comparison.
public nonisolated struct InsightNumber: Sendable, Equatable {
    public let label: String
    public let value: NoctisMetricValue

    public init(label: String, value: NoctisMetricValue) {
        self.label = label
        self.value = value
    }
}

/// What sits between the two numbers of a comparison: an arrow for a change
/// over time (usual to last night), "vs" for two groups side by side (which
/// must not read as one leading to the other).
public nonisolated enum InsightComparisonJoin: Sendable, Equatable {
    case arrow
    case versus
}

/// How an insight was found, in plain words: the rule, its thresholds and
/// the nights behind it.
public nonisolated struct InsightMethod: Sendable, Equatable {
    public let rule: String
    public let thresholds: [String]
    public let nights: String

    public init(rule: String, thresholds: [String], nights: String) {
        self.rule = rule
        self.thresholds = thresholds
        self.nights = nights
    }
}

/// Every word of one insight, written from its numbers (never stored).
public nonisolated struct InsightContent: Sendable, Equatable, Identifiable {
    public let id: String
    public let type: InsightType
    public let category: InsightCategory
    public let confidence: InsightConfidence
    public let title: String
    /// The night the insight is about, "Sat, Sep 12".
    public let dateLine: String
    /// A few short "label · value" lines under the chart.
    public let evidenceLines: [String]
    /// One line for a list row and the featured card.
    public let rowLine: String
    /// "Compared with your recent baseline..."
    public let context: String
    /// "Your recent data suggests..." or "This has coincided with..."
    public let interpretation: String
    /// One sentence.
    public let whatToNotice: String
    /// Rules 1, 2, 3, 7 and 8 only: one generic, safe thing to try.
    public let whatYouCanTry: String?
    /// "Moderate confidence · based on 23 nights".
    public let confidenceLine: String
    /// Patterns only: "This is a pattern in your data, not proof of a cause."
    public let notProofLine: String?
    public let method: InsightMethod
    /// The big two-number comparison, from the reference to now (a
    /// milestone has one number).
    public let comparison: [InsightNumber]
    public let comparisonJoin: InsightComparisonJoin
    public let accessibilityLabel: String
}

/// Writes insights: every string comes from an `InsightRecord`'s numbers, the
/// same way every time, in one voice: descriptive, never a diagnosis, never a
/// cause, never a to-do (except the one generic thing to try on rules 1, 2,
/// 3, 7 and 8). Required phrasing: "Compared with your recent baseline...",
/// "Your recent data suggests..." and "This has coincided with...".
public nonisolated enum InsightScreenBuilder {
    public static let notProofLine = "This is a pattern in your data, not proof of a cause."
    /// Words no generated sentence may contain (the language lint).
    public static let bannedWords = [
        "cause", "because", "diagnos", "disease", "sick", "insomnia", "apnea", "should", "must", "poor", "bad", "debt", "danger", "warning", "worry",
    ]

    public static func build(_ record: InsightRecord, format: HomeFormat) -> InsightContent {
        let words = words(for: record, format: format)
        let confidence = "\(record.confidence.rawValue.capitalized) confidence · based on \(record.nightsUsed) \(record.nightsUsed == 1 ? "night" : "nights")"
        let spokenNumbers = words.comparison.map { "\($0.label) \($0.value.spoken)" }.joined(separator: "; ")
        return InsightContent(
            id: record.id, type: record.type, category: record.category, confidence: record.confidence,
            title: words.title, dateLine: format.weekdayMonthDay(record.night), evidenceLines: words.evidence, rowLine: words.row,
            context: words.context, interpretation: words.interpretation, whatToNotice: words.notice,
            whatYouCanTry: record.type.offersSomethingToTry ? words.attempt : nil,
            confidenceLine: confidence, notProofLine: record.type.isPattern ? notProofLine : nil, method: words.method,
            comparison: words.comparison, comparisonJoin: words.join,
            accessibilityLabel: [words.title + ".", spokenNumbers.isEmpty ? nil : spokenNumbers + ".", words.row].compactMap { $0 }.joined(separator: " ")
        )
    }

    /// Every sentence and label an insight can show, for the language lint.
    public static func strings(_ content: InsightContent) -> [String] {
        [content.title, content.rowLine, content.context, content.interpretation, content.whatToNotice, content.confidenceLine, content.method.rule, content.method.nights, content.accessibilityLabel]
            + content.evidenceLines + content.method.thresholds + [content.whatYouCanTry, content.notProofLine].compactMap { $0 } + content.comparison.map(\.label)
    }

    // MARK: - Wording

    private struct Words {
        var title: String
        var row: String
        var evidence: [String]
        var context: String
        var interpretation: String
        var notice: String
        var attempt: String
        var method: InsightMethod
        var comparison: [InsightNumber]
        var join = InsightComparisonJoin.arrow
    }

    /// "45 min" under an hour, "1h 10m" from an hour.
    private static func amount(_ minutes: Double) -> String {
        HomeFormat.compactDuration(Int(abs(minutes).rounded()), minutesWord: true)
    }

    private static func duration(_ minutes: Double) -> String {
        HomeFormat.compactDuration(Int(minutes.rounded()))
    }

    private static func durationNumber(_ label: String, _ minutes: Double) -> InsightNumber {
        InsightNumber(label: label, value: HomeFormat.durationMetric(Int(minutes.rounded())))
    }

    private static func clockNumber(_ label: String, _ minutesAfterNoon: Double, _ format: HomeFormat) -> InsightNumber {
        InsightNumber(label: label, value: format.clockMetric(format.clock(minutesAfterNoon: minutesAfterNoon)))
    }

    private static func number(_ label: String, _ value: Double, unit: String, spoken: String) -> InsightNumber {
        InsightNumber(label: label, value: HomeFormat.quantityMetric(Int(value.rounded()), unit: unit, spokenUnit: spoken))
    }

    private static func nights(_ count: Int) -> String {
        "\(count) \(count == 1 ? "night" : "nights")"
    }

    private static func tonightBedtime(_ minutesAfterNoon: Double, _ format: HomeFormat) -> String {
        "Keep tonight's bedtime within \(Int(InsightEngine.streakToleranceMinutes)) minutes of \(format.clock(minutesAfterNoon: minutesAfterNoon))."
    }

    private static func words(for record: InsightRecord, format: HomeFormat) -> Words {
        switch record.evidence {
        case .baseline(let e): baseline(record.type, e, format)
        case .pattern(let e): pattern(e, format)
        case .recoveryDirection(let e): recoveryDirection(e)
        case .heartSignal(let e): heartSignal(e)
        case .consistencyChange(let e): consistencyChange(e, format)
        case .balance(let e): balance(e)
        case .weekend(let e): weekend(e, format)
        case .stageShare(let e): stageShare(e)
        case .record(let e): standingRecord(record.type, e, format)
        case .milestone(let e): milestone(e)
        }
    }

    // Rules 1-3

    private static func baseline(_ type: InsightType, _ e: InsightEvidence, _ format: HomeFormat) -> Words {
        let span = "your last \(nights(e.baselineNights))"
        switch type {
        case .sleepDurationShift:
            let less = e.delta < 0
            return Words(
                title: less ? "Shorter night than usual" : "Longer night than usual",
                row: "\(duration(e.value)) last night, \(amount(e.delta)) \(less ? "less" : "more") than your usual \(duration(e.baseline)).",
                evidence: ["Last night · \(duration(e.value))", "Your usual · \(duration(e.baseline))", "Difference · \(amount(e.delta)) \(less ? "less" : "more")"],
                context: "Compared with your recent baseline of \(duration(e.baseline)) (the average of \(span)), last night was \(amount(e.delta)) \(less ? "shorter" : "longer").",
                interpretation: "Your recent data suggests last night ran \(less ? "shorter" : "longer") than your usual range.",
                notice: "Notice whether today feels different from your usual days.",
                attempt: less ? "Leave a little extra room for sleep tonight, if your evening allows." : "Keep tonight's routine the same as usual.",
                method: InsightMethod(
                    rule: "We compare last night's time asleep with the average of your previous 14 nights.",
                    thresholds: ["Shown when last night is \(Int(InsightModelV2.shiftMinutes)) minutes or more away from your usual."],
                    nights: "Your usual is built from \(nights(e.baselineNights))."
                ),
                comparison: [durationNumber("Usual", e.baseline), durationNumber("Last night", e.value)]
            )
        case .bedtimeShift:
            let later = e.delta > 0
            return Words(
                title: later ? "Later bedtime than usual" : "Earlier bedtime than usual",
                row: "\(format.clock(minutesAfterNoon: e.value)) last night, \(amount(e.delta)) \(later ? "later" : "earlier") than your usual \(format.clock(minutesAfterNoon: e.baseline)).",
                evidence: [
                    "Last night · \(format.clock(minutesAfterNoon: e.value))", "Your usual · \(format.clock(minutesAfterNoon: e.baseline))",
                    "Difference · \(amount(e.delta)) \(later ? "later" : "earlier")",
                ],
                context: "Compared with your recent baseline of \(format.clock(minutesAfterNoon: e.baseline)) (the average of \(span)), last night's bedtime was \(amount(e.delta)) \(later ? "later" : "earlier").",
                interpretation: "Your recent data suggests a shift in when you went to bed.",
                notice: "Notice whether waking up felt different after \(later ? "a later" : "an earlier") night.",
                attempt: tonightBedtime(e.baseline, format),
                method: InsightMethod(
                    rule: "We compare last night's bedtime with the average of your previous 14 bedtimes.",
                    thresholds: ["Shown when last night is \(Int(InsightModelV2.shiftMinutes)) minutes or more away from your usual."],
                    nights: "Your usual is built from \(nights(e.baselineNights))."
                ),
                comparison: [clockNumber("Usual", e.baseline, format), clockNumber("Last night", e.value, format)]
            )
        default:
            let streak = e.streakNights ?? 0
            let tolerance = Int(InsightEngine.streakToleranceMinutes)
            return Words(
                title: "Steady bedtime",
                row: "\(streak) nights in a row within \(tolerance) min of your usual bedtime.",
                evidence: ["Streak · \(streak) nights", "Your usual · \(format.clock(minutesAfterNoon: e.baseline))", "Last night · \(format.clock(minutesAfterNoon: e.value))"],
                context: "Compared with your recent baseline of \(format.clock(minutesAfterNoon: e.baseline)) (the average of \(span)), each of your last \(streak) bedtimes fell within \(tolerance) minutes of it.",
                interpretation: "Your recent data suggests a steady bedtime.",
                notice: "Notice how regular evenings feel compared with the rest of your week.",
                attempt: tonightBedtime(e.baseline, format),
                method: InsightMethod(
                    rule: "We count the nights in a row, ending last night, whose bedtime was close to your usual.",
                    thresholds: ["Shown from \(InsightModelV2.streakNights) nights in a row, each within \(tolerance) minutes of your usual."],
                    nights: "Your usual is built from \(nights(e.baselineNights))."
                ),
                comparison: [clockNumber("Usual", e.baseline, format), clockNumber("Last night", e.value, format)]
            )
        }
    }

    // Rule 4

    private static func pattern(_ e: PatternEvidence, _ format: HomeFormat) -> Words {
        let earlier = e.difference > 0
        let early = Int(e.earlyMean.rounded())
        let late = Int(e.lateMean.rounded())
        let median = format.clock(minutesAfterNoon: e.medianBedtime)
        let step = Int(InsightModelV2.patternGroupMinutes)
        let points = Int(abs(e.difference).rounded())
        return Words(
            title: earlier ? "Earlier bedtimes, higher sleep scores" : "Later bedtimes, higher sleep scores",
            row: "Nights \(step)+ min earlier than \(median) averaged \(early); later ones averaged \(late).",
            evidence: [
                "Earlier nights · \(e.earlyNights) nights, average \(early)", "Later nights · \(e.lateNights) nights, average \(late)",
                "Difference · \(points) points", "Your usual bedtime · \(median)",
            ],
            context: "Compared with your recent baseline bedtime of \(median), your \(e.earlyNights) earlier nights averaged \(early) and your \(e.lateNights) later nights averaged \(late) on sleep continuity, stage balance and HRV over the last \(e.windowNights) nights.",
            interpretation: "This has coincided with \(earlier ? "higher" : "lower") scores on the nights you went to bed earlier.",
            notice: "Notice how you feel after earlier and later nights.",
            attempt: "",
            method: InsightMethod(
                rule: "We split your last \(e.windowNights) nights into those \(step)+ minutes earlier and \(step)+ minutes later than your median bedtime, then compare the average of three scores: sleep continuity, stage balance and HRV. Duration and consistency are left out: both follow from bedtime itself.",
                thresholds: [
                    "Each group needs at least \(InsightModelV2.patternMinimumPerGroup) nights.",
                    "Shown when the groups differ by \(Int(InsightModelV2.patternMinimumDifference)) points or more and the effect size is at least \(String(format: "%.1f", InsightModelV2.patternMinimumEffect)).",
                    "High confidence needs \(InsightModelV2.patternHighPerGroup)+ nights in each group and an effect size of \(String(format: "%.1f", InsightModelV2.patternHighEffect)) or more.",
                ],
                nights: "\(e.earlyNights) earlier and \(e.lateNights) later nights (effect size \(String(format: "%.1f", abs(e.effectSize))))."
            ),
            comparison: [
                InsightNumber(label: "Earlier nights", value: HomeFormat.quantityMetric(early, unit: "pts", spokenUnit: "points")),
                InsightNumber(label: "Later nights", value: HomeFormat.quantityMetric(late, unit: "pts", spokenUnit: "points")),
            ],
            join: .versus
        )
    }

    // Rule 5

    private static func recoveryDirection(_ e: RecoveryDirectionEvidence) -> Words {
        let rising = e.direction == .rising
        let slope = String(format: "%+.1f", e.pointsPerWeek)
        return Words(
            title: rising ? "Recovery trending higher" : "Recovery trending lower",
            row: "\(e.consecutiveDays) days of a \(rising ? "rising" : "lower") trend, about \(slope) points a week.",
            evidence: ["Trend · \(slope) points a week", "Days in a row · \(e.consecutiveDays)", "Seven days ago · \(e.startScore)", "Latest · \(e.latestScore)"],
            context: "Compared with your recent baseline, your Recovery score has moved from \(e.startScore) to \(e.latestScore) over the last 7 days.",
            interpretation: "Your recent data suggests a \(rising ? "rising" : "lower") trend for \(e.consecutiveDays) days in a row.",
            notice: "Notice how your energy through the day lines up with these scores.",
            attempt: "",
            method: InsightMethod(
                rule: "We draw a straight line through your last 7 daily Recovery scores. Its slope, in points a week, says which way they are heading.",
                thresholds: [
                    "Rising at +\(String(format: "%.1f", RecoveryHistoryDirectionThreshold.pointsPerWeek)) points a week or more, lower at -\(String(format: "%.1f", RecoveryHistoryDirectionThreshold.pointsPerWeek)) or less.",
                    "Shown when the same direction holds for \(InsightModelV2.directionConsecutiveDays) or more days in a row.",
                ],
                nights: "Based on the last \(e.consecutiveDays) days of scores."
            ),
            comparison: [
                InsightNumber(label: "7 days ago", value: HomeFormat.quantityMetric(e.startScore, unit: "", spokenUnit: "")),
                InsightNumber(label: "Latest", value: HomeFormat.quantityMetric(e.latestScore, unit: "", spokenUnit: "")),
            ].map(scoreNumber)
        )
    }

    private static func scoreNumber(_ number: InsightNumber) -> InsightNumber {
        let plain = number.value.plain
        return InsightNumber(label: number.label, value: NoctisMetricValue(parts: [.number(plain)], spoken: "\(plain) out of 100"))
    }

    // Rule 6

    private static func heartSignal(_ e: HeartSignalEvidence) -> Words {
        let isHRV = e.signal == .hrv
        let unit = isHRV ? "ms" : "bpm"
        let spoken = isHRV ? "milliseconds" : "beats per minute"
        let name = isHRV ? "HRV" : "Resting heart rate"
        let low = Int(e.rangeLow.rounded())
        let high = Int(e.rangeHigh.rounded())
        let value = Int(e.value.rounded())
        let usual = Int(e.baseline.rounded())
        return Words(
            title: isHRV ? "HRV below your normal range" : "Resting heart rate above your normal range",
            row: "\(name) was \(value) \(unit) last night, \(isHRV ? "under" : "over") your normal range of \(low)–\(high) \(unit).",
            evidence: ["Last night · \(value) \(unit)", "Your usual · \(usual) \(unit)", "Normal range · \(low)–\(high) \(unit)", "Nights in a row · \(e.consecutiveNights)"],
            context: "Compared with your recent baseline of \(usual) \(unit), \(name) has been \(isHRV ? "below" : "above") your normal range for \(e.consecutiveNights) nights in a row.",
            interpretation: "Your recent data suggests a few nights \(isHRV ? "lower" : "higher") than your usual on this measure, which varies naturally from night to night.",
            notice: "Notice how you feel, and how much rest the next few nights bring.",
            attempt: "",
            method: InsightMethod(
                rule: "We compare each night's \(name) with your normal range: your average over the 14 nights before it, give or take one standard deviation.",
                thresholds: ["Shown when \(name) is \(isHRV ? "below" : "above") that range for \(InsightModelV2.heartConsecutiveNights) or more nights in a row."],
                nights: "Your normal range is built from \(nights(e.baselineNights))."
            ),
            comparison: [
                number("Usual", e.baseline, unit: unit, spoken: spoken),
                number("Last night", e.value, unit: unit, spoken: spoken),
            ]
        )
    }

    // Rule 7

    private static func consistencyChange(_ e: ConsistencyChangeEvidence, _ format: HomeFormat) -> Words {
        let steadier = e.delta < 0
        let recent = Int(e.recentSD.rounded())
        let previous = Int(e.previousSD.rounded())
        let usualBedtime = InsightStats.median(e.bedtimes.suffix(InsightModelV2.consistencyWindowNights).compactMap { $0 }) ?? 0
        return Words(
            title: steadier ? "Bedtimes are steadier" : "Bedtimes are less steady",
            row: "Bedtime varied by \(recent) min over the last 14 nights, \(steadier ? "down" : "up") from \(previous) min.",
            evidence: ["Last 14 nights · varied by \(recent) min", "The 14 before · varied by \(previous) min", "Change · \(amount(e.delta)) \(steadier ? "steadier" : "less steady")"],
            context: "Compared with your recent baseline (the 14 nights before), how much your bedtime varied went from \(previous) min to \(recent) min.",
            interpretation: "Your recent data suggests your bedtimes have become \(steadier ? "steadier" : "less regular").",
            notice: "Notice whether a steadier or looser routine changes how your mornings feel.",
            attempt: tonightBedtime(usualBedtime, format),
            method: InsightMethod(
                rule: "We measure how much your bedtime varied over the last 14 nights and over the 14 before, and compare the two.",
                thresholds: ["Shown when the two differ by \(Int(InsightModelV2.consistencyDeltaMinutes)) minutes or more."],
                nights: "\(e.recentNights) recent and \(e.previousNights) earlier bedtimes."
            ),
            comparison: [
                number("The 14 before", e.previousSD, unit: "min", spoken: "minutes"),
                number("Last 14 nights", e.recentSD, unit: "min", spoken: "minutes"),
            ]
        )
    }

    // Rule 8

    private static func balance(_ e: BalanceEvidence) -> Words {
        let behind = e.minutes < 0
        let average = InsightStats.mean(e.nightlyMinutes.compactMap { $0 }) ?? 0
        return Words(
            title: behind ? "Behind your sleep need this week" : "Ahead of your sleep need this week",
            row: "\(amount(e.minutes)) \(behind ? "behind" : "ahead of") your sleep need over the last \(e.recordedNights) nights.",
            evidence: ["Average night · \(duration(average))", "Your sleep need · \(duration(e.needMinutes))", "Over \(nights(e.recordedNights)) · \(amount(e.minutes)) \(behind ? "behind" : "ahead")"],
            context: "Compared with your sleep need of \(duration(e.needMinutes)) a night, your last \(nights(e.recordedNights)) added up to \(amount(e.minutes)) \(behind ? "less" : "more") sleep in total.",
            interpretation: "Your recent data suggests you have been sleeping \(behind ? "under" : "over") your need lately.",
            notice: "Notice how the balance moves as your nights change.",
            attempt: behind ? "A little extra sleep over the next few nights would close the gap gradually." : "Keep the routine that has been working for you.",
            method: InsightMethod(
                rule: "We add up, over your last 7 nights, how much you slept more or less than the sleep need you set.",
                thresholds: ["Shown when the total is \(Int(InsightModelV2.balanceMinutes / 60)) hours or more either way."],
                nights: "Based on \(nights(e.recordedNights)) with sleep recorded."
            ),
            comparison: [durationNumber("Average night", average), durationNumber("Your need", e.needMinutes)],
            join: .versus
        )
    }

    // Rule 9

    private static func weekend(_ e: WeekendEvidence, _ format: HomeFormat) -> Words {
        let later = e.delta > 0
        return Words(
            title: later ? "Later bedtimes on weekends" : "Earlier bedtimes on weekends",
            row: "Weekend bedtimes run \(amount(e.delta)) \(later ? "later" : "earlier") than weekdays (\(format.clock(minutesAfterNoon: e.weekendMedian)) and \(format.clock(minutesAfterNoon: e.weekdayMedian))).",
            evidence: [
                "Weekend nights · \(format.clock(minutesAfterNoon: e.weekendMedian))", "Other nights · \(format.clock(minutesAfterNoon: e.weekdayMedian))",
                "Difference · \(amount(e.delta)) \(later ? "later" : "earlier")",
            ],
            context: "Compared with your recent baseline of weekday bedtimes (\(format.clock(minutesAfterNoon: e.weekdayMedian))), your Friday and Saturday bedtimes were \(amount(e.delta)) \(later ? "later" : "earlier") over the last \(e.windowNights) nights.",
            interpretation: "Your recent data suggests your bedtime shifts on weekends.",
            notice: "Notice how the start of the week feels after \(later ? "later" : "earlier") weekends.",
            attempt: "",
            method: InsightMethod(
                rule: "We compare the median bedtime on Friday and Saturday nights with the median on the other nights of the last \(e.windowNights).",
                thresholds: ["Needs \(InsightModelV2.weekendMinimumWeekendNights)+ weekend nights and \(InsightModelV2.weekendMinimumWeekdayNights)+ other nights.", "Shown when the medians differ by \(Int(InsightModelV2.weekendDeltaMinutes)) minutes or more."],
                nights: "\(e.weekendNights) weekend and \(e.weekdayNights) other nights."
            ),
            comparison: [clockNumber("Weekdays", e.weekdayMedian, format), clockNumber("Weekends", e.weekendMedian, format)],
            join: .versus
        )
    }

    // Rule 10

    private static func stageShare(_ e: StageShareEvidence) -> Words {
        let deep = e.stage == .deep
        let name = deep ? "Deep sleep" : "REM sleep"
        let more = e.deltaPoints > 0
        let points = Int(abs(e.deltaPoints).rounded())
        let share = Int((e.share * 100).rounded())
        let usual = Int((e.usual * 100).rounded())
        return Words(
            title: "\(more ? "More" : "Less") \(deep ? "deep" : "REM") sleep than usual",
            row: "\(name) was \(share)% of last night, \(points) points \(more ? "above" : "below") your usual \(usual)%.",
            evidence: ["Last night · \(share)%", "Your usual · \(usual)%", "Difference · \(points) points \(more ? "above" : "below")"],
            context: "Compared with your recent baseline of \(usual)%, \(name.lowercased()) made up \(share)% of your time asleep last night.",
            interpretation: "Your recent data suggests a night with a \(more ? "larger" : "smaller") share of \(name.lowercased()) than usual.",
            notice: "Notice that stage estimates from a watch are approximate and vary from night to night.",
            attempt: "",
            method: InsightMethod(
                rule: "We compare the share of your sleep spent in \(name.lowercased()) last night with your average share over the previous 14 nights.",
                thresholds: ["Needs stage data from your watch.", "Shown when the share differs by \(Int(InsightModelV2.stagePoints)) percentage points or more."],
                nights: "Your usual is built from \(nights(e.usualNights))."
            ),
            comparison: [
                number("Usual", Double(usual), unit: "%", spoken: "percent"),
                number("Last night", Double(share), unit: "%", spoken: "percent"),
            ]
        )
    }

    // Rule 11

    private static func standingRecord(_ type: InsightType, _ e: RecordEvidence, _ format: HomeFormat) -> Words {
        let days = e.scope
        let title: String
        let value: (Double) -> String
        let label: String
        let spoken: (Double) -> NoctisMetricValue
        switch type {
        case .recordLongestNight:
            title = "Your longest night in \(days) days"
            label = "night"
            value = { duration($0) }
            spoken = { HomeFormat.durationMetric(Int($0.rounded())) }
        case .recordBestConsistency:
            title = "Your steadiest week in \(days) days"
            label = "spread of bedtimes"
            value = { "\(Int($0.rounded())) min" }
            spoken = { HomeFormat.quantityMetric(Int($0.rounded()), unit: "min", spokenUnit: "minutes") }
        case .recordHighestRecovery:
            title = "Your highest Recovery in \(days) days"
            label = "Recovery score"
            value = { "\(Int($0.rounded()))" }
            spoken = { scoreNumber(InsightNumber(label: "", value: HomeFormat.quantityMetric(Int($0.rounded()), unit: "", spokenUnit: ""))).value }
        default:
            title = "Your lowest resting heart rate in \(days) days"
            label = "resting heart rate"
            value = { "\(Int($0.rounded())) bpm" }
            spoken = { HomeFormat.quantityMetric(Int($0.rounded()), unit: "bpm", spokenUnit: "beats per minute") }
        }
        let higher = type == .recordLongestNight || type == .recordHighestRecovery
        return Words(
            title: title,
            row: "\(value(e.value)) \(higher ? "beats" : "is under") your previous best of \(value(e.previousBest)).",
            evidence: ["Now · \(value(e.value))", "Previous best · \(value(e.previousBest))", "Window · last \(days) days"],
            context: "Compared with your other nights over the last \(days) days, this is your \(higher ? "highest" : "lowest") \(label): \(value(e.value)), against a previous best of \(value(e.previousBest)).",
            interpretation: "Your recent data suggests a standout night in your last \(days) days.",
            notice: "Notice how a record night compares with how you felt the next day.",
            attempt: "",
            method: InsightMethod(
                rule: "We look for last night's value being \(higher ? "higher" : "lower") than every other night in the window. A tie is not a record.",
                thresholds: ["Looks back \(days) nights, needing at least \(days == InsightModelV2.recordLongWindow ? InsightModelV2.recordMinimumLong : InsightModelV2.recordMinimumShort) with a value."],
                nights: "Compared with \(nights(e.nightsInWindow - 1))."
            ),
            comparison: [
                InsightNumber(label: "Previous best", value: spoken(e.previousBest)),
                InsightNumber(label: "Now", value: spoken(e.value)),
            ]
        )
    }

    // Rule 12

    private static func milestone(_ e: MilestoneEvidence) -> Words {
        let unlocked: String
        switch e.milestone {
        case 7: unlocked = "timing insights"
        case 14: unlocked = "patterns"
        default: unlocked = "long-term trends"
        }
        return Words(
            title: "\(e.milestone) nights recorded",
            row: "\(e.nightsRecorded) nights recorded, enough to start on \(unlocked).",
            evidence: ["Nights recorded · \(e.nightsRecorded)", "Unlocked · \(unlocked)"],
            context: "Compared with the first nights you recorded, there is now enough history to look at \(unlocked).",
            interpretation: "Your recent data suggests your insights will keep getting more reliable as nights add up.",
            notice: "Insights start small and grow as your nights add up.",
            attempt: "",
            method: InsightMethod(
                rule: "Timing insights unlock at 7 nights, patterns at 14 and long-term trends at 30.",
                thresholds: ["Shown for a week after each one unlocks."],
                nights: "Based on \(nights(e.nightsRecorded)) recorded."
            ),
            comparison: [InsightNumber(label: "Nights recorded", value: NoctisMetricValue(parts: [.number("\(e.nightsRecorded)")], spoken: "\(e.nightsRecorded) nights"))]
        )
    }
}

/// The Recovery trend's threshold, as the engine holds it.
private nonisolated enum RecoveryHistoryDirectionThreshold {
    static let pointsPerWeek = 1.5
}
