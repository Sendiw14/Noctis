import Foundation
import HomeFeature
import InsightsKit
import SleepKit

// The evidence charts, in unit space (R23): every position is 0...1 across
// the plot (x from the left, y from the bottom), so a view only scales and
// draws. Built off the main thread from a record's numbers; nothing here
// reads Health.

/// A label at a place on an axis.
public nonisolated struct InsightAxisTick: Sendable, Equatable {
    public let label: String
    public let position: Double

    public init(label: String, position: Double) {
        self.label = label
        self.position = position
    }
}

public nonisolated struct InsightChartBar: Sendable, Equatable {
    public let label: String
    public let valueText: String
    /// 0...1 of the plot's height.
    public let fraction: Double
    /// The bar the chart is about (last night, now).
    public let emphasized: Bool
    /// Whether the bar reached the chart's reference line (a sleep need).
    public let reachesReference: Bool?

    public init(label: String, valueText: String, fraction: Double, emphasized: Bool = false, reachesReference: Bool? = nil) {
        self.label = label
        self.valueText = valueText
        self.fraction = fraction
        self.emphasized = emphasized
        self.reachesReference = reachesReference
    }
}

/// Bars: last night against usual, the last week's nights against the need,
/// a record against the best before it.
public nonisolated struct InsightBarsChart: Sendable, Equatable {
    public let bars: [InsightChartBar]
    /// A horizontal line (the sleep need), when there is one.
    public let reference: InsightAxisTick?
}

public nonisolated struct InsightMark: Sendable, Equatable {
    public let label: String
    public let timeText: String
    public let position: Double
    public let emphasized: Bool
}

/// A bedtime axis: hour ticks, the usual as a band and the times marked on it.
public nonisolated struct InsightTimelineChart: Sendable, Equatable {
    public let ticks: [InsightAxisTick]
    /// The usual, give or take 30 minutes, as positions on the axis.
    public let band: ClosedRange<Double>
    public let bandLabel: String
    public let marks: [InsightMark]
}

public nonisolated struct InsightDot: Sendable, Equatable {
    /// Narrow weekday, "M".
    public let label: String
    /// True within the tolerance, false outside it, nil with no sleep.
    public let within: Bool?
}

/// The nights of a streak, one dot each.
public nonisolated struct InsightDotsChart: Sendable, Equatable {
    public let dots: [InsightDot]
    public let caption: String
}

public nonisolated struct InsightPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let valueText: String
}

/// A series over the last nights or days: its points, a rolling average, and
/// the range it is judged against.
public nonisolated struct InsightLineChart: Sendable, Equatable {
    /// The raw points, joined where the nights are consecutive.
    public let segments: [[InsightPoint]]
    public let rolling: [InsightPoint]
    public let rollingLabel: String
    /// The usual or normal range, as y positions.
    public let band: ClosedRange<Double>?
    public let bandLabel: String?
    public let yTicks: [InsightAxisTick]
    public let xTicks: [InsightAxisTick]
    /// The newest point, drawn larger.
    public let latest: InsightPoint?
    /// A vertical divider between two fortnights.
    public let divider: Double?
}

public nonisolated struct InsightDotGroup: Sendable, Equatable {
    public let label: String
    public let countText: String
    public let meanText: String
    public let meanY: Double
    /// Each night's outcome, spread across the column by a fixed sequence.
    public let dots: [InsightPoint]
}

/// The pattern: two columns of dots with a mean line each and the sample size
/// labeled.
public nonisolated struct InsightGroupsChart: Sendable, Equatable {
    public let groups: [InsightDotGroup]
    public let yTicks: [InsightAxisTick]
}

public nonisolated enum InsightChartData: Sendable, Equatable {
    case bars(InsightBarsChart)
    case timeline(InsightTimelineChart)
    case dots(InsightDotsChart)
    case line(InsightLineChart)
    case groups(InsightGroupsChart)
}

/// One chart per kind of evidence.
public nonisolated enum InsightChartBuilder {
    public static func chart(for record: InsightRecord, format: HomeFormat) -> InsightChartData? {
        switch record.evidence {
        case .baseline(let e):
            switch record.type {
            case .sleepDurationShift: durationBars(e)
            case .bedtimeShift: bedtimeTimeline(e, format)
            default: streakDots(e, format)
            }
        case .pattern(let e): patternGroups(e)
        case .recoveryDirection(let e): recoveryLine(e, format)
        case .heartSignal(let e): heartLine(e, format)
        case .consistencyChange(let e): consistencyLine(e, format)
        case .balance(let e): balanceBars(e, format)
        case .weekend(let e): weekendTimeline(e, format)
        case .stageShare(let e): stageBars(e)
        case .record(let e): recordBars(record.type, e)
        case .milestone: nil
        }
    }

    // MARK: Bars

    static func durationBars(_ e: InsightEvidence) -> InsightChartData {
        let longest = max(e.value, e.baseline, 1)
        return .bars(InsightBarsChart(
            bars: [
                InsightChartBar(label: "Last night", valueText: HomeFormat.compactDuration(Int(e.value.rounded())), fraction: e.value / longest, emphasized: true),
                InsightChartBar(label: "Usual", valueText: HomeFormat.compactDuration(Int(e.baseline.rounded())), fraction: e.baseline / longest),
            ],
            reference: nil
        ))
    }

    static func balanceBars(_ e: BalanceEvidence, _ format: HomeFormat) -> InsightChartData {
        let top = max(e.needMinutes, e.nightlyMinutes.compactMap { $0 }.max() ?? 0, 1) * 1.1
        let count = e.nightlyMinutes.count
        let bars = e.nightlyMinutes.enumerated().map { index, minutes -> InsightChartBar in
            let night = e.night.adding(days: index - count + 1)
            let label = format.weekday(night, width: .narrow)
            guard let minutes else { return InsightChartBar(label: label, valueText: "No data", fraction: 0, reachesReference: nil) }
            return InsightChartBar(
                label: label, valueText: HomeFormat.compactDuration(Int(minutes.rounded())), fraction: minutes / top,
                emphasized: index == count - 1, reachesReference: minutes >= e.needMinutes
            )
        }
        return .bars(InsightBarsChart(
            bars: bars, reference: InsightAxisTick(label: "Need \(HomeFormat.compactDuration(Int(e.needMinutes.rounded())))", position: e.needMinutes / top)
        ))
    }

    static func stageBars(_ e: StageShareEvidence) -> InsightChartData {
        let top = max(e.share, e.usual, 0.01)
        return .bars(InsightBarsChart(
            bars: [
                InsightChartBar(label: "Last night", valueText: "\(Int((e.share * 100).rounded()))%", fraction: e.share / top, emphasized: true),
                InsightChartBar(label: "Usual", valueText: "\(Int((e.usual * 100).rounded()))%", fraction: e.usual / top),
            ],
            reference: nil
        ))
    }

    static func recordBars(_ type: InsightType, _ e: RecordEvidence) -> InsightChartData {
        func text(_ value: Double) -> String {
            switch type {
            case .recordLongestNight: HomeFormat.compactDuration(Int(value.rounded()))
            case .recordBestConsistency: "\(Int(value.rounded())) min"
            case .recordHighestRecovery: "\(Int(value.rounded()))"
            default: "\(Int(value.rounded())) bpm"
            }
        }
        let top = max(e.value, e.previousBest, 1)
        return .bars(InsightBarsChart(
            bars: [
                InsightChartBar(label: "Now", valueText: text(e.value), fraction: e.value / top, emphasized: true),
                InsightChartBar(label: "Previous best", valueText: text(e.previousBest), fraction: e.previousBest / top),
            ],
            reference: nil
        ))
    }

    // MARK: Timelines

    /// Whole hours around every time in `minutes` (after noon), at least half
    /// an hour of room on each side.
    static func axis(around minutes: [Double], _ format: HomeFormat) -> (start: Double, end: Double, ticks: [InsightAxisTick]) {
        let low = ((minutes.min() ?? 660) - 30) / 60
        let high = ((minutes.max() ?? 660) + 30) / 60
        let start = low.rounded(.down) * 60
        let end = high.rounded(.up) * 60
        let span = max(end - start, 1)
        var ticks: [InsightAxisTick] = []
        var hour = start
        while hour <= end {
            ticks.append(InsightAxisTick(label: format.hour(minutesSinceMidnight: Int(hour) + 720), position: (hour - start) / span))
            hour += 60
        }
        return (start, end, ticks)
    }

    static func timeline(usual: Double, others: [(label: String, minutes: Double)], usualLabel: String, _ format: HomeFormat) -> InsightChartData {
        let axis = axis(around: [usual] + others.map(\.minutes), format)
        let span = max(axis.end - axis.start, 1)
        func position(_ minutes: Double) -> Double { (minutes - axis.start) / span }
        var marks = [InsightMark(label: usualLabel, timeText: format.clock(minutesAfterNoon: usual), position: position(usual), emphasized: false)]
        marks += others.map { InsightMark(label: $0.label, timeText: format.clock(minutesAfterNoon: $0.minutes), position: position($0.minutes), emphasized: true) }
        let tolerance = InsightEngine.streakToleranceMinutes
        return .timeline(InsightTimelineChart(
            ticks: axis.ticks,
            band: position(usual - tolerance)...position(usual + tolerance),
            bandLabel: "Usual ± \(Int(tolerance)) min",
            marks: marks
        ))
    }

    static func bedtimeTimeline(_ e: InsightEvidence, _ format: HomeFormat) -> InsightChartData {
        timeline(usual: e.baseline, others: [("Last night", e.value)], usualLabel: "Usual", format)
    }

    static func weekendTimeline(_ e: WeekendEvidence, _ format: HomeFormat) -> InsightChartData {
        timeline(usual: e.weekdayMedian, others: [("Weekends", e.weekendMedian)], usualLabel: "Weekdays", format)
    }

    // MARK: Dots

    static func streakDots(_ e: InsightEvidence, _ format: HomeFormat) -> InsightChartData {
        let count = e.recentNights.count
        let dots = e.recentNights.enumerated().map { index, within in
            InsightDot(label: format.weekday(e.night.adding(days: index - count + 1), width: .narrow), within: within)
        }
        return .dots(InsightDotsChart(dots: dots, caption: "Last \(count) nights"))
    }

    // MARK: Lines

    /// The chart's y positions for `values` between `low` and `high`.
    static func scale(low: Double, high: Double) -> (Double) -> Double {
        let span = max(high - low, 1e-9)
        return { min(max(($0 - low) / span, 0), 1) }
    }

    /// Runs of consecutive non-nil values, as points.
    static func segments(_ series: [Double?], y: (Double) -> Double, text: (Double) -> String) -> [[InsightPoint]] {
        let count = max(series.count - 1, 1)
        var result: [[InsightPoint]] = []
        var current: [InsightPoint] = []
        for (index, value) in series.enumerated() {
            if let value {
                current.append(InsightPoint(x: Double(index) / Double(count), y: y(value), valueText: text(value)))
            } else if !current.isEmpty {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// A trailing average over `window` points, from where a window is full
    /// enough (at least half of it present).
    static func rolling(_ series: [Double?], window: Int, y: (Double) -> Double, text: (Double) -> String) -> [InsightPoint] {
        let count = max(series.count - 1, 1)
        var points: [InsightPoint] = []
        for index in series.indices {
            let values = series[max(0, index - window + 1)...index].compactMap { $0 }
            guard values.count * 2 >= window, series[index] != nil, let mean = InsightStats.mean(values) else { continue }
            points.append(InsightPoint(x: Double(index) / Double(count), y: y(mean), valueText: text(mean)))
        }
        return points
    }

    static func niceRange(_ values: [Double], including extra: [Double] = [], step: Double, pad: Double = 0) -> (low: Double, high: Double) {
        let all = values + extra
        guard let low = all.min(), let high = all.max() else { return (0, 1) }
        let floor = ((low - pad) / step).rounded(.down) * step
        var ceiling = ((high + pad) / step).rounded(.up) * step
        if ceiling <= floor { ceiling = floor + step }
        return (floor, ceiling)
    }

    static func ticks(_ range: (low: Double, high: Double), step: Double, label: (Double) -> String) -> [InsightAxisTick] {
        var result: [InsightAxisTick] = []
        var value = range.low
        while value <= range.high + 1e-9 {
            result.append(InsightAxisTick(label: label(value), position: (value - range.low) / max(range.high - range.low, 1e-9)))
            value += step
        }
        return result
    }

    static func recoveryLine(_ e: RecoveryDirectionEvidence, _ format: HomeFormat) -> InsightChartData {
        let series = e.recentScores.map { $0.map(Double.init) }
        let range = niceRange(series.compactMap { $0 }, step: 10, pad: 2)
        let y = scale(low: range.low, high: range.high)
        let text: (Double) -> String = { "\(Int($0.rounded()))" }
        let segs = segments(series, y: y, text: text)
        return .line(InsightLineChart(
            segments: segs, rolling: rolling(series, window: 3, y: y, text: text), rollingLabel: "3-day average", band: nil, bandLabel: nil,
            yTicks: ticks(range, step: max((range.high - range.low) / 3, 1).rounded(), label: { "\(Int($0.rounded()))" }),
            xTicks: dayTicks(count: series.count, ending: e.night, format), latest: segs.last?.last, divider: nil
        ))
    }

    static func heartLine(_ e: HeartSignalEvidence, _ format: HomeFormat) -> InsightChartData {
        let unit = e.signal == .hrv ? "ms" : "bpm"
        let range = niceRange(e.recentValues.compactMap { $0 }, including: [e.rangeLow, e.rangeHigh], step: e.signal == .hrv ? 10 : 5, pad: 1)
        let y = scale(low: range.low, high: range.high)
        let text: (Double) -> String = { "\(Int($0.rounded())) \(unit)" }
        let segs = segments(e.recentValues, y: y, text: text)
        return .line(InsightLineChart(
            segments: segs, rolling: rolling(e.recentValues, window: 3, y: y, text: text), rollingLabel: "3-night average",
            band: y(e.rangeLow)...y(e.rangeHigh), bandLabel: "Normal range",
            yTicks: ticks(range, step: e.signal == .hrv ? 10 : 5, label: { "\(Int($0.rounded()))" }),
            xTicks: dayTicks(count: e.recentValues.count, ending: e.night, format), latest: segs.last?.last, divider: nil
        ))
    }

    static func consistencyLine(_ e: ConsistencyChangeEvidence, _ format: HomeFormat) -> InsightChartData {
        let range = niceRange(e.bedtimes.compactMap { $0 }, step: 30, pad: 5)
        let y = scale(low: range.low, high: range.high)
        let text: (Double) -> String = { format.clock(minutesAfterNoon: $0) }
        let segs = segments(e.bedtimes, y: y, text: text)
        return .line(InsightLineChart(
            segments: segs, rolling: rolling(e.bedtimes, window: 7, y: y, text: text), rollingLabel: "7-night average", band: nil, bandLabel: nil,
            yTicks: ticks(range, step: 60, label: { format.hour(minutesSinceMidnight: Int($0) + 720) }),
            xTicks: dayTicks(count: e.bedtimes.count, ending: e.night, format), latest: segs.last?.last, divider: 0.5
        ))
    }

    /// The first, middle and last night of a series ending on `night`.
    static func dayTicks(count: Int, ending night: SleepNightKey, _ format: HomeFormat) -> [InsightAxisTick] {
        guard count > 1 else { return [] }
        return [0, count / 2, count - 1].map { index in
            InsightAxisTick(label: format.monthDay(night.adding(days: index - count + 1)), position: Double(index) / Double(count - 1))
        }
    }

    // MARK: Groups

    static func patternGroups(_ e: PatternEvidence) -> InsightChartData {
        let all = e.earlyValues + e.lateValues
        let range = niceRange(all, step: 10, pad: 2)
        let y = scale(low: range.low, high: range.high)
        func group(_ label: String, _ values: [Double], mean: Double) -> InsightDotGroup {
            let dots = values.enumerated().map { index, value -> InsightPoint in
                // A fixed sequence spreads the dots across the column: the same every time.
                let spread = (Double(index) * 0.6180339887).truncatingRemainder(dividingBy: 1)
                return InsightPoint(x: 0.15 + 0.7 * spread, y: y(value), valueText: "\(Int(value.rounded()))")
            }
            return InsightDotGroup(
                label: label, countText: "\(values.count) \(values.count == 1 ? "night" : "nights")",
                meanText: "Average \(Int(mean.rounded()))", meanY: y(mean), dots: dots
            )
        }
        return .groups(InsightGroupsChart(
            groups: [group("Earlier nights", e.earlyValues, mean: e.earlyMean), group("Later nights", e.lateValues, mean: e.lateMean)],
            yTicks: ticks(range, step: 10, label: { "\(Int($0.rounded()))" })
        ))
    }
}
