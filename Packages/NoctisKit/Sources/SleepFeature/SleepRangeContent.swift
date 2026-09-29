import DesignSystem
import Foundation
import HomeFeature
import NoctisCore
import RecoveryKit
import SleepAnalysisKit
import SleepKit

// The Week and Month content: bars, the consistency, balance and timing
// cards and their detail sheets, the month's rhythm and quality strip. Built
// by `SleepScreenBuilder` from the render model (geometry) and the engine
// results (numbers); the views lay out what's here and add nothing
// (APP_RULES.md R18, R20, R23). Wording describes how nights compare with
// the person's own need and pattern: it never claims to measure health,
// diagnose or warn, and a balance is "behind" or "ahead", never a debt.

// MARK: - Shared

/// A label on an axis: where along it (0...1) and what it says ("11 PM").
public nonisolated struct SleepAxisTick: Sendable, Equatable {
    public let position: Double
    public let text: String
}

public nonisolated struct SleepBarContent: Sendable, Equatable {
    public let night: SleepNightKey
    /// Under the bar: the weekday initial in a week, empty in a month.
    public let label: String
    /// Height as a share of the chart; nil for a night with nothing recorded.
    public let fraction: Double?
    public let stages: WeekBarStages?
    /// Whether the night reached the sleep need; nil for a night with
    /// nothing recorded. A month's bars are sage when it did, butter under.
    public let reachedNeed: Bool?
    /// The newest night of the range.
    public let isNewest: Bool
    public let accessibilityLabel: String
    /// The selection pill: "Tue · 7h 12m · Deep 1h 20m · REM 1h 50m".
    public let detail: String
}

/// The bars of a week or a month, the need line and the average.
public nonisolated struct SleepBarsContent: Sendable, Equatable {
    /// "SEP 23 – SEP 29".
    public let caption: String
    public let bars: [SleepBarContent]
    public let needFraction: Double
    /// "8h need".
    public let needLabel: String
    public let average: NoctisMetricValue?
    public let averageFraction: Double?
    /// Whether any bar is split into Deep, Core and REM.
    public let hasStages: Bool
    /// What to say when stages are missing: for every night ("Stages aren't
    /// available from your current sources."), or for some of them.
    public let stagesNote: String?
    /// "No sleep recorded in this period." when every night is empty.
    public let emptyNote: String?
    public let accessibilityLabel: String
}

// MARK: - Consistency, balance, timing

public nonisolated struct SleepConsistencyWindowContent: Sendable, Equatable, Identifiable {
    /// "Last 7 nights".
    public let title: String
    /// "6 recorded".
    public let detail: String
    /// "32 min".
    public let bedtime: String
    public let wake: String
    public let duration: String
    public let accessibilityLabel: String

    public var id: String { title }
}

public nonisolated struct SleepConsistencyContent: Sendable, Equatable {
    /// "Bedtime varied by 32 min", or "Consistency needs 5 recorded nights".
    public let headline: String
    /// "Wake time varied by 21 min over the last 7 nights."
    public let subline: String
    public let isAvailable: Bool
    /// How much bedtime varied over the last 7 nights ("32m"), for the sheet's headline.
    public let spread: NoctisMetricValue?
    /// A night per row: bedtime and wake dots on one time axis.
    public let chart: TimingDotsRender
    /// The weekday initial of each row.
    public let rowLabels: [String]
    public let ticks: [SleepAxisTick]
    /// "Shaded: your usual bedtime and wake time".
    public let usualCaption: String?
    public let windows: [SleepConsistencyWindowContent]
    /// "Sleep midpoint 3:05 AM".
    public let midpoint: String?
    public let calculation: [String]
    public let accessibilityLabel: String
}

public nonisolated struct SleepBalanceContent: Sendable, Equatable {
    public enum Direction: Sendable, Equatable {
        case behind
        case ahead
        /// Within a few minutes of the need.
        case even
        case unavailable
    }

    public let direction: Direction
    /// The size of the balance ("1h 10m"); nil when even or unavailable.
    public let value: NoctisMetricValue?
    /// "behind" or "ahead"; nil when even or unavailable.
    public let directionWord: String?
    /// "1h 10m behind", "Even with your need", "Not enough nights yet".
    public let headline: String
    /// "Over the last 7 nights, against your 8h need."
    public let caption: String
    public let chart: BalanceRender?
    /// The first and last night of the 14-night line ("Sep 16", "Sep 29").
    public let firstLabel: String
    public let lastLabel: String
    public let explanation: [String]
    public let accessibilityLabel: String
}

public nonisolated struct SleepTimingContent: Sendable, Equatable {
    public let typicalBedtime: NoctisMetricValue?
    public let typicalWake: NoctisMetricValue?
    public let midpoint: NoctisMetricValue?
    /// "Medians of your last 14 nights · 9 recorded", or what's missing.
    public let nightsLine: String
    /// "Over the last 7 nights: bedtime 18 min later, wake time about the same, compared with the 14 nights before."
    public let shift: String?
    /// "Bedtime 10:48 PM – 11:20 PM · Wake 6:50 AM – 7:30 AM: …"
    public let suggested: String?
    public let chart: TimingWindowRender?
    public let ticks: [SleepAxisTick]
    public let isAvailable: Bool
    public let calculation: [String]
    public let accessibilityLabel: String
}

public nonisolated struct SleepInsightsContent: Sendable, Equatable {
    /// Week only: it needs the week's nights.
    public let consistency: SleepConsistencyContent?
    public let balance: SleepBalanceContent
    public let timing: SleepTimingContent

    /// Closes every detail sheet.
    public static let noFear = "Patterns matter more than perfect nights."
}

// MARK: - Week

public nonisolated struct SleepWeekContent: Sendable, Equatable {
    public let bars: SleepBarsContent
    public let longest: SleepBarMarker?
    public let shortest: SleepBarMarker?
}

/// The strip at the top of Week and Month: the average, and the longest
/// and the shortest night of the range.
public nonisolated struct SleepSummaryContent: Sendable, Equatable {
    public let average: NoctisMetricValue
    /// "Average" and how many nights it is over, for VoiceOver.
    public let accessibilityLabel: String
    public let longest: SleepBarMarker?
    public let shortest: SleepBarMarker?
}

// MARK: - Month

public nonisolated struct SleepMonthLabel: Sendable, Equatable {
    /// The bar the label sits over.
    public let index: Int
    public let text: String
}

/// The longest or the shortest night of the month.
public nonisolated struct SleepBarMarker: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case longest
        case shortest
    }

    public let kind: Kind
    /// The bar it names.
    public let index: Int
    /// "Longest".
    public let title: String
    public let value: NoctisMetricValue
    /// "Sat, Sep 12".
    public let date: String
    public let accessibilityLabel: String
}

public nonisolated struct SleepRhythmContent: Sendable, Equatable {
    public let chart: RhythmRender
    /// Down the chart: earliest at the top.
    public let ticks: [SleepAxisTick]
    /// "Bedtime usually 11:05 PM".
    public let bedtimeSummary: String?
    public let wakeSummary: String?
    /// "Shaded: your usual bedtime and wake time".
    public let usualCaption: String?
    public let accessibilityLabel: String
}

public nonisolated struct SleepQualityDotContent: Sendable, Equatable {
    public let night: SleepNightKey
    public let band: QualityDotRender.Band?
    /// "Tue, Sep 8 · 82": the number is always in the pill.
    public let detail: String
    public let accessibilityLabel: String
}

public nonisolated struct SleepQualityLegendItem: Sendable, Equatable {
    public let band: QualityDotRender.Band
    /// "80 and up", "60–79", "Under 60".
    public let text: String
}

public nonisolated struct SleepQualityStripContent: Sendable, Equatable {
    public let dots: [SleepQualityDotContent]
    public let legend: [SleepQualityLegendItem]
    /// "30-night average 78"; nil with nothing scored.
    public let average: String?
    public let accessibilityLabel: String
}

public nonisolated struct SleepMonthContent: Sendable, Equatable {
    public let bars: SleepBarsContent
    /// Runs of seven nights and the average across each.
    public let blocks: [SleepWeekBlock]
    /// The date over the first bar of each run.
    public let labels: [SleepMonthLabel]
    public let longest: SleepBarMarker?
    public let shortest: SleepBarMarker?
    public let rhythm: SleepRhythmContent
    public let quality: SleepQualityStripContent
}

// MARK: - Builders

nonisolated extension SleepScreenBuilder {
    // MARK: Week and month

    static func weekContent(_ snapshot: SleepSnapshot, model: SleepRenderModel, render: SleepWeekRender, format: HomeFormat) -> SleepWeekContent {
        let nights = snapshot.nights(endingAt: model.selection.night, count: SleepRange.week.nights).map { $0.night }
        let longest = render.longest.map { marker(.longest, index: $0, night: nights[$0], snapshot: snapshot, format: format) }
        let shortest = render.shortest.map { marker(.shortest, index: $0, night: nights[$0], snapshot: snapshot, format: format) }
        return SleepWeekContent(
            bars: barsContent(
                render.bars, snapshot: snapshot, night: model.selection.night, range: .week, format: format,
                notes: [longest, shortest].compactMap { $0?.accessibilityLabel }
            ),
            longest: longest,
            shortest: shortest
        )
    }

    static func monthContent(_ snapshot: SleepSnapshot, model: SleepRenderModel, render: SleepMonthRender, format: HomeFormat) -> SleepMonthContent {
        let nights = snapshot.nights(endingAt: model.selection.night, count: SleepRange.month.nights).map { $0.night }
        let longest = render.longest.map { marker(.longest, index: $0, night: nights[$0], snapshot: snapshot, format: format) }
        let shortest = render.shortest.map { marker(.shortest, index: $0, night: nights[$0], snapshot: snapshot, format: format) }
        let bars = barsContent(
            render.bars, snapshot: snapshot, night: model.selection.night, range: .month, format: format,
            notes: [longest, shortest].compactMap { $0?.accessibilityLabel }
        )
        let labels = render.blocks.filter { $0.end - $0.start >= 4 }.map { block in
            SleepMonthLabel(index: block.start, text: format.monthDay(nights[block.start].adding(days: 1)))
        }
        return SleepMonthContent(
            bars: bars,
            blocks: render.blocks,
            labels: labels,
            longest: longest,
            shortest: shortest,
            rhythm: rhythmContent(render.rhythm, timing: model.timing, format: format),
            quality: qualityStrip(render.quality, format: format)
        )
    }

    /// The bars of a week (a weekday under each, stages in each) or of a
    /// month (slim, solid).
    static func barsContent(
        _ render: SleepBarsRender, snapshot: SleepSnapshot, night: SleepNightKey, range: SleepRange, format: HomeFormat, notes: [String] = []
    ) -> SleepBarsContent {
        let count = range.nights
        let entries = snapshot.nights(endingAt: night, count: count)
        let bars = zip(entries, render.bars).enumerated().map { index, pair -> SleepBarContent in
            let (entry, bar) = pair
            let wake = entry.night.adding(days: 1)
            let minutes = entry.record.map { Int($0.metrics.asleepMinutes.rounded()) }
            let stages = entry.record?.metrics.stages
            let day = range == .week ? format.weekday(wake, width: .abbreviated) : format.weekdayMonthDay(wake)
            var pill = [day, minutes.map { HomeFormat.compactDuration($0) } ?? "No data"]
            var spoken = [range == .week ? format.weekday(wake, width: .wide) : format.wideDate(wake), minutes.map { HomeFormat.spokenDuration($0) } ?? "no data"]
            if range == .week, let stages {
                let deep = Int(stages.deep.rounded())
                let rem = Int(stages.rem.rounded())
                pill += ["Deep \(HomeFormat.compactDuration(deep))", "REM \(HomeFormat.compactDuration(rem))"]
                spoken += ["deep \(HomeFormat.spokenDuration(deep))", "REM \(HomeFormat.spokenDuration(rem))"]
            }
            return SleepBarContent(
                night: entry.night,
                label: range == .week ? format.weekday(wake, width: .narrow) : "",
                fraction: bar.fraction,
                stages: bar.stages,
                reachedNeed: entry.record.map { $0.metrics.asleepMinutes >= Double(snapshot.needMinutes) },
                isNewest: index == count - 1,
                accessibilityLabel: spoken.joined(separator: ", "),
                detail: pill.joined(separator: " · ")
            )
        }
        let average = render.averageMinutes.map { HomeFormat.durationMetric(Int($0.rounded())) }
        let first = entries.first.map { format.monthDay($0.night.adding(days: 1)) } ?? ""
        let last = entries.last.map { format.monthDay($0.night.adding(days: 1)) } ?? ""
        let need = "\(HomeFormat.compactDuration(snapshot.needMinutes)) need"
        let title = range == .week ? "The week" : "The last 30 nights"
        var label = "\(title), \(first) to \(last)"
        if let average { label += ", average \(average.spoken)" }
        label += ", \(HomeFormat.spokenDuration(snapshot.needMinutes)) need."
        if range == .week { label += " " + bars.map(\.accessibilityLabel).joined(separator: "; ") + "." }
        if !notes.isEmpty { label += " " + notes.joined(separator: ". ") + "." }
        let recorded = bars.filter { $0.fraction != nil }
        let hasStages = bars.contains { $0.stages != nil }
        var stagesNote: String?
        if range == .week, !recorded.isEmpty {
            if !hasStages {
                stagesNote = "Stages aren't available from your current sources."
            } else if recorded.contains(where: { $0.stages == nil }) {
                stagesNote = "Nights without stage detail are drawn as one bar."
            }
        }
        return SleepBarsContent(
            caption: "\(first) – \(last)".uppercased(),
            bars: bars,
            needFraction: render.needFraction,
            needLabel: need,
            average: average,
            averageFraction: render.averageFraction,
            hasStages: hasStages,
            stagesNote: stagesNote,
            emptyNote: bars.allSatisfy({ $0.fraction == nil }) ? "No sleep recorded in this period." : nil,
            accessibilityLabel: label
        )
    }

    static func marker(_ kind: SleepBarMarker.Kind, index: Int, night: SleepNightKey, snapshot: SleepSnapshot, format: HomeFormat) -> SleepBarMarker {
        let minutes = Int((snapshot.record(night)?.metrics.asleepMinutes ?? 0).rounded())
        let title = kind == .longest ? "Longest" : "Shortest"
        let date = format.weekdayMonthDay(night.adding(days: 1))
        return SleepBarMarker(
            kind: kind, index: index, title: title, value: HomeFormat.durationMetric(minutes), date: date,
            accessibilityLabel: "\(title) night, \(format.wideDate(night.adding(days: 1))), \(HomeFormat.spokenDuration(minutes))"
        )
    }

    // MARK: Rhythm and quality

    static func rhythmContent(_ chart: RhythmRender, timing: SleepTimingResult?, format: HomeFormat) -> SleepRhythmContent {
        let bedtime = timing?.typicalBedtime.map { "Bedtime usually \(format.clock(minutesAfterNoon: $0))" }
        let wake = timing?.typicalWake.map { "Wake time usually \(format.clock(minutesAfterNoon: $0))" }
        let hasBands = chart.bedtimeBand != nil || chart.wakeBand != nil
        var label = "Bedtime and wake time over the last 30 nights."
        if let bedtime, let wake { label += " \(bedtime). \(wake)." }
        return SleepRhythmContent(
            chart: chart,
            ticks: axisTicks(start: chart.axisStart, end: chart.axisEnd, format: format),
            bedtimeSummary: bedtime,
            wakeSummary: wake,
            usualCaption: hasBands ? "Shaded: your usual bedtime and wake time" : nil,
            accessibilityLabel: label
        )
    }

    static func qualityStrip(_ dots: [QualityDotRender], format: HomeFormat) -> SleepQualityStripContent {
        let content = dots.map { dot -> SleepQualityDotContent in
            let date = format.weekdayMonthDay(dot.night.adding(days: 1))
            let number = dot.score.map { "\($0)" } ?? "no sleep"
            return SleepQualityDotContent(
                night: dot.night, band: dot.band,
                detail: "\(date) · \(number)",
                accessibilityLabel: "\(format.wideDate(dot.night.adding(days: 1))), " + (dot.score.map { "sleep quality \($0)" } ?? "no sleep recorded")
            )
        }
        let scores = dots.compactMap(\.score)
        let average = scores.isEmpty ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        return SleepQualityStripContent(
            dots: content,
            legend: [
                SleepQualityLegendItem(band: .high, text: "80 and up"),
                SleepQualityLegendItem(band: .middle, text: "60–79"),
                SleepQualityLegendItem(band: .low, text: "Under 60"),
            ],
            average: average.map { "30-night average \($0)" },
            accessibilityLabel: "Sleep quality over the last 30 nights" + (average.map { ", average \($0)" } ?? "") + "."
        )
    }

    /// Whole-hour labels along a clock axis given in minutes after noon:
    /// every hour up to a 5-hour axis, every two up to 8, then every three
    /// (six labels at most on the axes the charts use, so none crowd).
    static func axisTicks(start: Double, end: Double, format: HomeFormat) -> [SleepAxisTick] {
        let span = max(end - start, 1)
        let step: Double = span <= 300 ? 60 : span <= 480 ? 120 : 180
        var ticks: [SleepAxisTick] = []
        var minute = start
        while minute <= end + 0.5 {
            ticks.append(SleepAxisTick(position: (minute - start) / span, text: format.hour(minutesSinceMidnight: Int(minute.rounded()) + 720)))
            minute += step
        }
        return ticks
    }

    // MARK: Insights

    static func insightsContent(_ snapshot: SleepSnapshot, model: SleepRenderModel, format: HomeFormat) -> SleepInsightsContent {
        SleepInsightsContent(
            consistency: model.week.map { consistencyContent(model.consistency, render: $0.consistency, format: format) },
            balance: balanceContent(model, need: snapshot.needMinutes, format: format),
            timing: timingContent(model, format: format)
        )
    }

    // MARK: Consistency

    /// "32 min" (or "1h 14m") for a spread in minutes.
    static func spreadText(_ minutes: Double) -> String {
        HomeFormat.compactDuration(Int(minutes.rounded()), minutesWord: true)
    }

    static func consistencyContent(_ result: ConsistencyResult?, render: TimingDotsRender, format: HomeFormat) -> SleepConsistencyContent {
        let week = result?.window(days: ConsistencyEngine.windowDays[0])
        let headline: String
        let subline: String
        let spoken: String
        if let week {
            headline = "Bedtime varied by \(spreadText(week.bedtimeSD))"
            subline = "Wake time varied by \(spreadText(week.wakeSD)) over the last \(week.days) nights."
            spoken = "Consistency. Bedtime varied by \(HomeFormat.spokenDuration(Int(week.bedtimeSD.rounded()))). Wake time varied by \(HomeFormat.spokenDuration(Int(week.wakeSD.rounded()))) over the last \(week.days) nights."
        } else {
            headline = "Consistency needs 5 recorded nights"
            subline = "It's worked out once 5 of the last 7 nights are recorded."
            spoken = "Consistency. \(headline). \(subline)"
        }
        let windows = (result?.windows ?? []).map { window in
            SleepConsistencyWindowContent(
                title: "Last \(window.days) nights",
                detail: "\(window.nights) recorded",
                bedtime: spreadText(window.bedtimeSD),
                wake: spreadText(window.wakeSD),
                duration: spreadText(window.durationSD),
                accessibilityLabel: "Last \(window.days) nights, \(window.nights) recorded. Bedtime varied by \(HomeFormat.spokenDuration(Int(window.bedtimeSD.rounded()))), wake time by \(HomeFormat.spokenDuration(Int(window.wakeSD.rounded()))), sleep length by \(HomeFormat.spokenDuration(Int(window.durationSD.rounded())))."
            )
        }
        return SleepConsistencyContent(
            headline: headline,
            subline: subline,
            isAvailable: week != nil,
            spread: week.map { HomeFormat.durationMetric(Int($0.bedtimeSD.rounded())) },
            chart: render,
            rowLabels: render.rows.map { format.weekday($0.night.adding(days: 1), width: .narrow) },
            ticks: axisTicks(start: render.axisStart, end: render.axisEnd, format: format),
            usualCaption: render.bedtimeBand != nil || render.wakeBand != nil ? "Shaded: your usual bedtime and wake time" : nil,
            windows: windows,
            midpoint: (week ?? result?.windows.first).map { "Sleep midpoint \(format.clock(minutesAfterNoon: $0.midpointMinutes))" },
            calculation: [
                "Consistency is how much your bedtime, wake time and sleep length varied over a run of nights, measured as a standard deviation: the typical distance from your own average. Smaller means more regular.",
                "Each window (7, 14 and 30 nights) needs at least \(BaselineEngine.minimumNights) recorded nights. The sleep midpoint is halfway between falling asleep and waking.",
                "It compares you with your own pattern, not with anyone else.",
            ],
            accessibilityLabel: spoken
        )
    }

    // MARK: Balance

    /// "2h 05m": minutes are two digits next to hours.
    static func balanceValue(_ minutes: Int) -> NoctisMetricValue {
        let hours = minutes / 60
        let remainder = minutes % 60
        var parts: [NoctisMetricValue.Part] = []
        if hours > 0 {
            parts += [.number("\(hours)"), .unit("h")]
            if remainder > 0 { parts += [.space, .number(remainder < 10 ? "0\(remainder)" : "\(remainder)"), .unit("m")] }
        } else {
            parts += [.number("\(remainder)"), .unit("m")]
        }
        return NoctisMetricValue(parts: parts, spoken: HomeFormat.spokenDuration(minutes))
    }

    static func balanceContent(_ model: SleepRenderModel, need: Int, format: HomeFormat) -> SleepBalanceContent {
        let needText = HomeFormat.compactDuration(need)
        let series = model.balance?.series ?? []
        let firstLabel = series.first.map { format.monthDay($0.night.adding(days: 1)) } ?? ""
        let lastLabel = series.last.map { format.monthDay($0.night.adding(days: 1)) } ?? ""
        let explanation = [
            "Balance compares the sleep you actually got with your sleep need over 7 nights. Each night adds its time asleep minus your \(needText) need, and the total is your balance.",
            "Behind means the last 7 nights added up to less than your need; ahead means more. Nights with nothing recorded are left out, not counted as zero, and a balance needs at least \(SleepBalanceEngine.minimumNights) recorded nights.",
            "The line shows the balance as it stood at the end of each of the last 14 nights. It isn't a medical measure, and it says nothing about your health.",
        ]
        guard let balance = model.balance, let minutes = balance.minutes else {
            return SleepBalanceContent(
                direction: .unavailable, value: nil, directionWord: nil, headline: "Not enough nights yet",
                caption: "A balance needs 5 recorded nights out of the last 7.",
                chart: model.balanceRender, firstLabel: firstLabel, lastLabel: lastLabel, explanation: explanation,
                accessibilityLabel: "Balance. Not enough nights yet. A balance needs 5 recorded nights out of the last 7."
            )
        }
        let size = Int(abs(minutes).rounded())
        let caption = "Over the last 7 nights, against your \(needText) need."
        if size < 5 {
            return SleepBalanceContent(
                direction: .even, value: nil, directionWord: nil, headline: "Even with your need", caption: caption,
                chart: model.balanceRender, firstLabel: firstLabel, lastLabel: lastLabel, explanation: explanation,
                accessibilityLabel: "Balance. Even with your need. \(caption)"
            )
        }
        let direction: SleepBalanceContent.Direction = minutes < 0 ? .behind : .ahead
        let word = direction == .behind ? "behind" : "ahead"
        let value = balanceValue(size)
        return SleepBalanceContent(
            direction: direction, value: value, directionWord: word, headline: "\(value.plain) \(word)", caption: caption,
            chart: model.balanceRender, firstLabel: firstLabel, lastLabel: lastLabel, explanation: explanation,
            accessibilityLabel: "Balance. \(value.spoken) \(word). \(caption)"
        )
    }

    // MARK: Timing

    static func timingContent(_ model: SleepRenderModel, format: HomeFormat) -> SleepTimingContent {
        let calculation = [
            "Your typical bedtime and wake time are the medians of your last \(SleepTimingEngine.typicalWindowNights) nights, once \(SleepTimingEngine.minimumNights) are recorded. The midpoint is halfway between them.",
            "The recent shift compares the last \(SleepTimingEngine.recentNights) nights with the \(SleepTimingEngine.priorNights) nights before them.",
            "Once \(SleepTimingEngine.suggestionMinimumNights) of the last \(SleepTimingEngine.suggestionWindowNights) nights are recorded, the range is the middle half of your own bedtimes and wake times, never narrower than \(Int(SleepTimingEngine.minimumRangeWidth)) minutes. It describes your pattern; it isn't a target.",
        ]
        guard let timing = model.timing, let bedtime = timing.typicalBedtime, let wake = timing.typicalWake, let midpoint = timing.typicalMidpoint else {
            let line = "Typical times need \(SleepTimingEngine.minimumNights) recorded nights in the last \(SleepTimingEngine.typicalWindowNights)."
            return SleepTimingContent(
                typicalBedtime: nil, typicalWake: nil, midpoint: nil, nightsLine: line, shift: nil, suggested: nil,
                chart: nil, ticks: [], isAvailable: false, calculation: calculation, accessibilityLabel: "Timing. \(line)"
            )
        }
        let bedText = format.clock(minutesAfterNoon: bedtime)
        let wakeText = format.clock(minutesAfterNoon: wake)
        let midText = format.clock(minutesAfterNoon: midpoint)
        let shift = timing.recentShift.map { shiftText($0) }
        var suggested: String?
        if let range = timing.suggested {
            suggested = "Bedtime \(clockRange(range.bedtime, format: format)) · Wake \(clockRange(range.wake, format: format)). This is the middle half of your own nights: it describes your pattern, it isn't a target."
        }
        var label = "Timing. Typical bedtime \(bedText). Typical wake time \(wakeText). Midpoint \(midText)."
        if let shift { label += " " + shift }
        return SleepTimingContent(
            typicalBedtime: format.clockMetric(bedText),
            typicalWake: format.clockMetric(wakeText),
            midpoint: format.clockMetric(midText),
            nightsLine: "Medians of your last \(SleepTimingEngine.typicalWindowNights) nights · \(timing.nights) recorded",
            shift: shift,
            suggested: suggested,
            chart: model.timingRender,
            ticks: model.timingRender.map { axisTicks(start: $0.axisStart, end: $0.axisEnd, format: format) } ?? [],
            isAvailable: true,
            calculation: calculation,
            accessibilityLabel: label
        )
    }

    static func clockRange(_ range: ClosedRange<Double>, format: HomeFormat) -> String {
        "\(format.clock(minutesAfterNoon: range.lowerBound)) – \(format.clock(minutesAfterNoon: range.upperBound))"
    }

    /// "Over the last 7 nights: bedtime 18 min later, wake time about the same, compared with the 14 nights before."
    static func shiftText(_ shift: SleepTimingShift) -> String {
        func phrase(_ name: String, _ minutes: Double) -> String {
            let size = Int(abs(minutes).rounded())
            if size < 10 { return "\(name) about the same" }
            return "\(name) \(HomeFormat.compactDuration(size, minutesWord: true)) \(minutes > 0 ? "later" : "earlier")"
        }
        return "Over the last \(SleepTimingEngine.recentNights) nights: \(phrase("bedtime", shift.bedtimeMinutes)), \(phrase("wake time", shift.wakeMinutes)), compared with the \(SleepTimingEngine.priorNights) nights before."
    }
}
