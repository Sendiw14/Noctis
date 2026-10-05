import Foundation
import RecoveryKit
import SleepKit

/// Makes a review story from a record (APP_RULES.md R63): every page, its numbers and its words, from the record alone. A page whose data does not exist is left out, never
/// filled; "steady" is said only when something was compared and nothing moved. Calm, plain words: no cause, no medical wording, no streak, no shame, and nothing red.
public nonisolated enum ReviewStoryBuilder {
    public static func build(_ record: ReviewRecord, format: ReviewFormat = ReviewFormat()) -> ReviewStory {
        let words = Words(kind: record.kind)
        let cover = cover(record, words, format)
        var pages: [ReviewStoryPage] = [ReviewStoryPage(kind: .cover, tint: .apricot, content: .cover(cover))]
        var bars: ReviewBarsPage?

        switch record.kind {
        case .weekly:
            let sleep = weekBars(record, format)
            bars = sleep
            pages.append(ReviewStoryPage(kind: .sleep, tint: .sage, content: .bars(sleep)))
            pages.append(ReviewStoryPage(kind: .consistency, tint: .butter, content: .timing(timing(record, words, format))))
            if let page = recoveryWeek(record, words, format) { pages.append(ReviewStoryPage(kind: .recovery, tint: .lavender, content: .line(page))) }
            if let page = changes(record, words, major: false) { pages.append(ReviewStoryPage(kind: .changes, tint: .sand, content: .changes(page))) }
            if let id = record.topInsightIDs.first {
                pages.append(ReviewStoryPage(kind: .insight, tint: .cocoa, content: .insights(ReviewInsightsPage(headline: "An insight from this week.", insightIDs: [id]))))
            }
            pages.append(ReviewStoryPage(kind: .focus, tint: .paper, content: .focus(focus(record, words))))
        case .monthly:
            // A month's pages come with the monthly review.
            break
        }

        let title = record.kind == .weekly ? "Your week" : "Your month"
        let share = ReviewShareContent(
            title: title, dateRange: cover.dateRange, cover: cover, bars: bars, details: details(record),
            fileName: "NOCTIS-\(record.kind == .weekly ? "week" : "month")-\(record.lastMorning.description)"
        )
        return ReviewStory(
            id: record.id, title: title, dateRange: cover.dateRange, pages: pages, nightsRecorded: record.nightsRecorded, nightsInPeriod: record.nightsInPeriod, fullShare: share
        )
    }

    /// Every string a story can say, for the lint: the visible words of every page.
    public static func allStrings(_ story: ReviewStory) -> [String] {
        var strings: [String] = [story.title, story.dateRange]
        for page in story.pages {
            switch page.content {
            case .cover(let cover): strings += [cover.title, cover.dateRange, cover.deltaText, cover.context, cover.spokenAverage]
            case .bars(let bars): strings += [bars.headline, bars.needText] + bars.lines + [bars.averageText].compactMap { $0 } + bars.bars.map(\.spoken)
            case .timing(let timing): strings += [timing.headline, timing.spoken] + timing.lines + timing.ticks.map(\.label)
            case .line(let line): strings += [line.headline, line.spoken] + line.lines + [line.direction].compactMap { $0 } + line.axis.map(\.label)
            case .changes(let changes):
                strings += [changes.headline] + [changes.steadySentence].compactMap { $0 }
                for tile in changes.tiles { strings += [tile.caption, tile.metric, tile.from, tile.to, tile.summary] }
            case .insights(let insights): strings.append(insights.headline)
            case .focus(let focus): strings += [focus.headline] + focus.lines
            case .records(let records):
                strings.append(records.headline)
                for block in records.blocks { strings += [block.title, block.date, block.spoken] + [block.tie].compactMap { $0 } }
            case .locked: break
            }
        }
        if let details = story.fullShare.details { strings.append(details) }
        return strings
    }

    // MARK: Words that depend on the kind

    private struct Words {
        let kind: ReviewKind
        var period: String { kind == .weekly ? "week" : "month" }
        var before: String { "the \(period) before" }
    }

    // MARK: Cover

    private static func cover(_ record: ReviewRecord, _ words: Words, _ format: ReviewFormat) -> ReviewCoverPage {
        let average = Int(record.sleep.averageMinutes.rounded())
        let delta = record.sleep.deltaMinutes
        let text: String
        var arrow: ReviewArrow?
        if let delta {
            if abs(delta) < 1 {
                text = "The same as \(words.before)"
                arrow = .flat
            } else {
                text = "\(delta > 0 ? "+" : "\u{2212}")\(ReviewFormat.amount(delta)) vs \(words.before)"
                arrow = delta > 0 ? .up : .down
            }
        } else {
            text = "Not enough nights in \(words.before) to compare"
        }
        return ReviewCoverPage(
            title: record.kind == .weekly ? "Your week" : "Your month", dateRange: ReviewScreenBuilder.dateRange(record.period, format), averageMinutes: average, deltaText: text, deltaArrow: arrow,
            context: "\(record.nightsRecorded) of \(record.nightsInPeriod) nights were recorded.", spokenAverage: "\(ReviewFormat.duration(Double(average))) on average"
        )
    }

    // MARK: Sleep bars

    private static func stageShares(_ stages: ReviewStages?) -> ReviewBarStages? {
        guard let stages, stages.total > 0 else { return nil }
        let total = Double(stages.total)
        return ReviewBarStages(deep: Double(stages.deep) / total, core: Double(stages.core) / total, rem: Double(stages.rem) / total)
    }

    private static func bars(_ record: ReviewRecord, label: (SleepNightKey) -> String, spokenDay: (SleepNightKey) -> String) -> (bars: [ReviewBar], top: Double) {
        let need = Double(record.sleep.needMinutes)
        let byMorning = Dictionary(record.nights.map { ($0.morning, $0) }, uniquingKeysWith: { first, _ in first })
        let longest = record.nights.map { Double($0.asleepMinutes) }.max() ?? 0
        // Room above the tallest bar or the need line, in half hours.
        let top = max((max(longest, need) * 1.1 / 30).rounded(.up) * 30, 60)
        let built = record.period.mornings.map { morning -> ReviewBar in
            guard let night = byMorning[morning] else {
                return ReviewBar(morning: morning, label: label(morning), minutes: nil, fraction: nil, stages: nil, reachedNeed: false, spoken: "\(spokenDay(morning)): no sleep recorded")
            }
            let minutes = Double(night.asleepMinutes)
            return ReviewBar(
                morning: morning, label: label(morning), minutes: minutes, fraction: minutes / top, stages: stageShares(night.stages), reachedNeed: minutes >= need,
                spoken: "\(spokenDay(morning)): \(ReviewFormat.duration(minutes))"
            )
        }
        return (built, top)
    }

    private static func weekBars(_ record: ReviewRecord, _ format: ReviewFormat) -> ReviewBarsPage {
        let (bars, top) = bars(record, label: { format.narrowWeekday($0) }, spokenDay: { format.weekdayDay($0) })
        let need = Double(record.sleep.needMinutes)
        var lines = ["On average a night was \(ReviewFormat.duration(record.sleep.averageMinutes))."]
        let staged = record.nights.compactMap(\.stages)
        if staged.count >= ReviewModel.minimumValues {
            let count = Double(staged.count)
            let deep = Double(staged.reduce(0) { $0 + $1.deep }) / count
            let core = Double(staged.reduce(0) { $0 + $1.core }) / count
            let rem = Double(staged.reduce(0) { $0 + $1.rem }) / count
            lines.append("On average a night had \(ReviewFormat.duration(deep)) deep, \(ReviewFormat.duration(core)) core and \(ReviewFormat.duration(rem)) REM sleep.")
        }
        return ReviewBarsPage(
            headline: "Reached your need on \(record.sleep.nightsReachedNeed) of \(record.nightsRecorded) nights", lines: lines, bars: bars, topMinutes: top, needFraction: need / top,
            needText: "\(ReviewFormat.duration(need)) need", averageFraction: nil, averageText: nil, slim: false
        )
    }

    // MARK: Timing and consistency

    private static func timing(_ record: ReviewRecord, _ words: Words, _ format: ReviewFormat) -> ReviewTimingPage {
        let nights = record.nights.sorted { $0.morning < $1.morning }
        let values = nights.flatMap { [Double($0.bedtimeMinutes), Double($0.wakeMinutes)] }
        var low = ((values.min() ?? 600) - 30) / 60
        var high = ((values.max() ?? 1200) + 30) / 60
        low = low.rounded(.down) * 60
        high = high.rounded(.up) * 60
        if high - low < 240 {
            let extra = (240 - (high - low)) / 2
            low -= extra
            high += extra
        }
        let span = high - low
        func position(_ minutes: Double) -> Double { min(max((minutes - low) / span, 0), 1) }
        let step: Double = span > 480 ? 240 : 120
        var ticks: [ReviewAxisTick] = []
        var tick = (low / step).rounded(.up) * step
        while tick <= high {
            ticks.append(ReviewAxisTick(position: position(tick), label: format.clock(minutesAfterNoon: tick)))
            tick += step
        }
        let consistency = record.consistency
        let timing = record.timing
        func band(_ median: Double, _ spread: Double) -> ReviewBand { ReviewBand(start: position(median - spread), end: position(median + spread)) }
        let rows = nights.map {
            ReviewTimingRow(morning: $0.morning, label: record.kind == .weekly ? format.narrowWeekday($0.morning) : format.dayNumber($0.morning), bedtime: position(Double($0.bedtimeMinutes)), wake: position(Double($0.wakeMinutes)))
        }
        var lines: [String] = []
        if let delta = consistency.bedtimeSDDelta {
            lines.append(abs(delta) < 1 ? "Bedtime varied about as much as \(words.before)." : "Bedtime varied \(ReviewFormat.amount(delta)) \(delta < 0 ? "less" : "more") than \(words.before).")
        }
        lines.append("Wake time varied by \(ReviewFormat.minutes(consistency.wakeSD)).")
        if record.kind == .monthly, let shift = timing.bedtimeShift {
            lines.append(abs(shift) < 1 ? "Your median bedtime was the same as \(words.before)." : "Your median bedtime was \(ReviewFormat.amount(shift)) \(shift > 0 ? "later" : "earlier") than \(words.before).")
        }
        lines.append("Your median bedtime was \(format.clock(minutesAfterNoon: timing.medianBedtimeMinutes)) and your median wake time \(format.clock(minutesAfterNoon: timing.medianWakeMinutes)).")
        let headline = "Bedtime varied by \(ReviewFormat.minutes(consistency.bedtimeSD))"
        return ReviewTimingPage(
            headline: headline, lines: lines, rows: rows, ticks: ticks, bedtimeBand: band(timing.medianBedtimeMinutes, consistency.bedtimeSD),
            wakeBand: band(timing.medianWakeMinutes, consistency.wakeSD),
            spoken: "\(headline). Wake time varied by \(ReviewFormat.minutes(consistency.wakeSD))."
        )
    }

    // MARK: Recovery

    /// 10-point steps around the values, between 0 and 100, at least 20 apart.
    private static func scoreAxis(_ values: [Double]) -> (low: Double, high: Double, ticks: [Double]) {
        var low = max(((values.min() ?? 50) - 5) / 10, 0).rounded(.down) * 10
        var high = min(((values.max() ?? 50) + 5) / 10, 10).rounded(.up) * 10
        if high - low < 20 {
            high = min(low + 20, 100)
            low = max(high - 20, 0)
        }
        return (low, high, [low, (low + high) / 2, high])
    }

    private static func extremeText(_ label: String, _ value: ReviewExtreme, _ format: ReviewFormat) -> String {
        let also = value.alsoOn > 0 ? ", and equalled on \(value.alsoOn) other night\(value.alsoOn == 1 ? "" : "s")" : ""
        return "\(label) \(ReviewFormat.whole(value.value)), on \(format.weekdayDay(value.morning))\(also)."
    }

    private static func recoveryWeek(_ record: ReviewRecord, _ words: Words, _ format: ReviewFormat) -> ReviewLinePage? {
        guard let recovery = record.recovery else { return nil }
        let byMorning = Dictionary(record.nights.map { ($0.morning, $0.recoveryScore) }, uniquingKeysWith: { first, _ in first })
        let values = record.period.mornings.map { byMorning[$0] ?? nil }.map { $0.map(Double.init) }
        let axis = scoreAxis(values.compactMap { $0 })
        let span = axis.high - axis.low
        let direction: (text: String, arrow: ReviewArrow)? = recovery.trend.map {
            switch $0.direction {
            case .rising: ("Rising", .up)
            case .steady: ("Steady", .flat)
            case .lower: ("Lower than earlier", .down)
            }
        }
        var lines = [extremeText("Highest", recovery.high, format), extremeText("Lowest", recovery.low, format)]
        if let delta = recovery.delta {
            lines.append(abs(delta) < 0.5 ? "About the same as \(words.before)." : "\(ReviewFormat.whole(abs(delta))) points \(delta > 0 ? "higher" : "lower") than \(words.before).")
        }
        let headline = "Recovery averaged \(ReviewFormat.whole(recovery.average))"
        return ReviewLinePage(
            headline: headline, lines: lines, points: values.map { $0.map { ($0 - axis.low) / span } },
            axis: axis.ticks.map { ReviewAxisTick(position: ($0 - axis.low) / span, label: ReviewFormat.number($0)) }, direction: direction?.text, directionArrow: direction?.arrow,
            spoken: ([headline + "."] + lines + [direction.map { $0.text + "." }].compactMap { $0 }).joined(separator: " ")
        )
    }

    // MARK: What changed

    private static func metricTitle(_ metric: ReviewMetric) -> String {
        switch metric {
        case .duration: "Average sleep"
        case .bedtimeVariation: "How much your bedtime varied"
        case .recovery: "Average recovery"
        case .hrv: "Average HRV"
        case .restingHeartRate: "Average resting heart rate"
        }
    }

    private static func valueText(_ metric: ReviewMetric, _ value: Double) -> String {
        switch metric {
        case .duration: ReviewFormat.duration(value)
        case .bedtimeVariation: ReviewFormat.minutes(value)
        case .recovery: ReviewFormat.whole(value)
        case .hrv: "\(ReviewFormat.whole(value)) ms"
        case .restingHeartRate: "\(ReviewFormat.whole(value)) bpm"
        }
    }

    private static func tile(_ caption: String, _ change: ReviewChange, _ words: Words) -> ReviewChangeTile {
        let arrow: ReviewArrow = change.value > change.previous ? .up : (change.value < change.previous ? .down : .flat)
        let from = valueText(change.metric, change.previous)
        let to = valueText(change.metric, change.value)
        return ReviewChangeTile(
            caption: caption, metric: metricTitle(change.metric), from: from, to: to, arrow: arrow,
            summary: "\(metricTitle(change.metric)) was \(to), \(arrow == .up ? "up" : "down") from \(from) in \(words.before)."
        )
    }

    private static func changes(_ record: ReviewRecord, _ words: Words, major: Bool) -> ReviewChangesPage? {
        // Nothing was compared: nothing is said, and no page is made.
        guard record.hasComparison else { return nil }
        var tiles: [ReviewChangeTile] = []
        switch (record.biggestImprovement, record.biggestChange) {
        case (.change(let improvement), .change(let change)):
            if improvement == change {
                tiles = [tile("Biggest improvement", improvement, words)]
            } else {
                tiles = [tile("Biggest improvement", improvement, words), tile("Biggest change", change, words)]
            }
        case (.change(let improvement), _): tiles = [tile("Biggest improvement", improvement, words)]
        case (_, .change(let change)): tiles = [tile("Biggest change", change, words)]
        default: break
        }
        if tiles.isEmpty {
            // Compared, and nothing moved by half the person's own variation: one calm tile and a sentence, no highlight.
            return ReviewChangesPage(headline: "A steady \(words.period)", tiles: [], steadySentence: "Compared with \(words.before), nothing moved by much.")
        }
        return ReviewChangesPage(headline: "Compared with \(words.before)", tiles: tiles, steadySentence: nil)
    }

    // MARK: Next focus

    private static func focus(_ record: ReviewRecord, _ words: Words) -> ReviewFocusPage {
        let topic: ReviewCoachTopic?
        switch record.nextFocus {
        case .steadyBedtime: topic = .consistency
        case .sleepNeed, .gentleShiftBack: topic = .bedtime
        case .recentNights: topic = .recovery
        case .keepGoing: topic = nil
        }
        let text = ReviewScreenBuilder.build(record).page(.nextFocus)
        return ReviewFocusPage(headline: text?.headline ?? "Nothing stands out to work on.", lines: text?.evidence ?? [], coachTopic: topic)
    }

    // MARK: Details, only on request

    /// The heart numbers, said only if the person flips "Include details" in the share preview.
    private static func details(_ record: ReviewRecord) -> String? {
        var parts: [String] = []
        if let recovery = record.recovery { parts.append("Recovery \(ReviewFormat.whole(recovery.average))") }
        if let hrv = record.heart.hrvAverage { parts.append("HRV \(ReviewFormat.whole(hrv)) ms") }
        if let rate = record.heart.restingHeartRateAverage { parts.append("Resting heart rate \(ReviewFormat.whole(rate)) bpm") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}
