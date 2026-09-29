import Foundation
import RecoveryKit
import SleepKit

// Recovery's render model: every piece of geometry a chart, bar or ring
// needs for one selection, worked out once on `RecoveryRepository`'s actor
// in the space the views scale into (shares of a chart, 0...1 up, angles
// in degrees). Views multiply and draw; nothing is sorted, dated or built
// in a `body` (APP_RULES.md R23).

/// One factor's segment of the "how today's score was built" bar, as
/// shares of a 100-point scale.
public nonisolated struct RecoveryBarSegmentRender: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    /// Where the segment starts (points / 100).
    public let start: Double
    /// How wide it is (its points / 100).
    public let width: Double
}

public nonisolated struct RecoveryTodayRender: Sendable, Equatable {
    /// The scored ring's arcs, in ring order.
    public let ring: [RingArc]
    /// The stacked bar, one segment per scored factor, in ring order.
    public let bar: [RecoveryBarSegmentRender]
    /// One per factor with a baseline: the last 14 nights against the
    /// normal range and today.
    public let sparklines: [SparklineRender]

    public func sparkline(_ kind: RecoveryFactorKind) -> SparklineRender? {
        sparklines.first { $0.kind == kind }
    }
}

/// A run of seven nights and its average, as a share of the chart.
public nonisolated struct RecoveryWeekAverage: Sendable, Equatable {
    /// Indices into the chart's days: `start` up to (not including) `end`.
    public let start: Int
    public let end: Int
    /// Nil under 3 scored nights.
    public let fraction: Double?
}

/// The recovery line over a window: score / 100 up the chart, a day to a
/// column, and the lines and bands around it.
public nonisolated struct RecoveryChartRender: Sendable, Equatable {
    /// Days the chart spans (fewer than the range with a short history).
    public let count: Int
    /// score / 100 per day; nil where no score exists.
    public let line: [Double?]
    /// The mean of the score over the day and the six before it (needing 3
    /// scored days), for a smoothed line.
    public let smoothed: [Double?]
    /// Your recovery baseline as a share of the chart; nil under 5 nights.
    public let baseline: Double?
    public let bandLow: Double?
    public let bandHigh: Double?
    /// The newest scored day: today's dot.
    public let todayIndex: Int?
    /// Runs of seven counted back from the newest day (the first may be
    /// short), each with its average.
    public let weeks: [RecoveryWeekAverage]
}

/// A factor's nights as a line: 0...1 up, its normal band and today.
public nonisolated struct FactorLineRender: Sendable, Equatable {
    public struct Tick: Sendable, Equatable {
        /// 0...1 up the chart.
        public let position: Double
        /// In the factor's unit: minutes, minutes after noon, ms, bpm.
        public let value: Double
    }

    public let kind: RecoveryFactorKind
    /// One per point, oldest first; nil where a night has no value.
    public let values: [Double?]
    public let bandLow: Double?
    public let bandHigh: Double?
    /// The newest point when it has a value.
    public let todayIndex: Int?
    /// The values at the chart's bottom and top.
    public let axisLow: Double
    public let axisHigh: Double
    /// Round values to label, inside the axis.
    public let ticks: [Tick]
    /// The line as `curveSamples` evenly spaced values (0...1 up), gaps
    /// bridged, so ranges of any length can morph into one another.
    public let curve: [Double]

    /// How many values `curve` holds.
    public static let curveSamples = 120
}

public nonisolated struct RecoveryRenderModel: Sendable, Equatable {
    public let selection: RecoverySelection
    /// Today's ring, bar and sparklines; set for the Today segment.
    public let today: RecoveryTodayRender?
    /// The line for a history segment.
    public let chart: RecoveryChartRender?
    /// A mini line per factor over the history segment's range.
    public let factorRows: [FactorLineRender]
    /// The factor detail's chart, when one is open.
    public let factor: FactorLineRender?

    public func factorRow(_ kind: RecoveryFactorKind) -> FactorLineRender? {
        factorRows.first { $0.kind == kind }
    }
}

public nonisolated enum RecoveryRenderModelBuilder {
    /// The mean covers this many days.
    public static let smoothingDays = 7

    public static func build(_ snapshot: RecoverySnapshot, selection: RecoverySelection) -> RecoveryRenderModel {
        if let kind = selection.factor {
            return RecoveryRenderModel(
                selection: selection, today: nil, chart: nil, factorRows: [],
                factor: snapshot.series(kind, selection.factorRange).flatMap { factorLine($0) }
            )
        }
        guard let range = selection.segment.historyRange else {
            return RecoveryRenderModel(selection: selection, today: today(snapshot), chart: nil, factorRows: [], factor: nil)
        }
        let history = snapshot.history(range)
        return RecoveryRenderModel(
            selection: selection, today: nil,
            chart: history.map(chart),
            factorRows: RecoveryContributionEngine.factorOrder.compactMap { kind in
                snapshot.series(kind, .fortnight).flatMap { rowSeries(kind, range: range, snapshot: snapshot, fortnight: $0) }
            },
            factor: nil
        )
    }

    // MARK: Today

    static func today(_ snapshot: RecoverySnapshot) -> RecoveryTodayRender? {
        guard let result = snapshot.result, let contributions = snapshot.contributions else { return nil }
        var start = 0.0
        let bar = contributions.contributions.map { item -> RecoveryBarSegmentRender in
            defer { start += item.points / 100 }
            return RecoveryBarSegmentRender(kind: item.kind, start: start, width: item.points / 100)
        }
        return RecoveryTodayRender(
            ring: RingRenderBuilder.build(result),
            bar: bar,
            sparklines: RingRenderBuilder.factorOrder.compactMap { kind in result.history(kind).map(SparklineRenderBuilder.build) }
        )
    }

    // MARK: History

    static func chart(_ history: RecoveryHistory) -> RecoveryChartRender {
        let scores = history.days.map { $0.score.map { Double($0.score) } }
        var smoothed: [Double?] = []
        for index in scores.indices {
            let window = scores[max(index - (smoothingDays - 1), 0)...index].compactMap { $0 }
            smoothed.append(window.count >= 3 ? window.reduce(0, +) / Double(window.count) / 100 : nil)
        }
        var weeks: [RecoveryWeekAverage] = []
        var end = scores.count
        while end > 0 {
            let start = max(end - 7, 0)
            let recorded = scores[start..<end].compactMap { $0 }
            weeks.insert(
                RecoveryWeekAverage(start: start, end: end, fraction: recorded.count >= 3 ? recorded.reduce(0, +) / Double(recorded.count) / 100 : nil),
                at: 0
            )
            end = start
        }
        func unit(_ value: Double) -> Double { min(max(value / 100, 0), 1) }
        return RecoveryChartRender(
            count: scores.count,
            line: scores.map { $0.map { $0 / 100 } },
            smoothed: smoothed,
            baseline: history.stats.baseline.map { unit($0.value) },
            bandLow: history.stats.usualRange.map { unit($0.lowerBound) },
            bandHigh: history.stats.usualRange.map { unit($0.upperBound) },
            todayIndex: scores.lastIndex { $0 != nil },
            weeks: weeks
        )
    }

    /// The row's line over the history range: the last 7 nights of the
    /// 14-night series for 7D, otherwise the series that covers the range.
    static func rowSeries(_ kind: RecoveryFactorKind, range: RecoveryHistoryRange, snapshot: RecoverySnapshot, fortnight: RecoveryFactorSeries) -> FactorLineRender? {
        switch range {
        case .week: factorLine(fortnight, last: 7)
        case .month: snapshot.series(kind, .month).flatMap { factorLine($0) }
        case .quarter: snapshot.series(kind, .quarter).flatMap { factorLine($0) }
        }
    }

    // MARK: Factors

    /// `series` (or its last `last` points) scaled to one chart. Nil
    /// without a single value.
    static func factorLine(_ series: RecoveryFactorSeries, last: Int? = nil) -> FactorLineRender? {
        let points = last.map { Array(series.points.suffix($0)) } ?? series.points
        let values = points.map(\.value)
        let band = series.normalRange
        let all = values.compactMap { $0 } + (band.map { [$0.lowerBound, $0.upperBound] } ?? [])
        guard let low = all.min(), let high = all.max() else { return nil }
        let pad = max((high - low) * 0.1, series.kind == .hrv || series.kind == .restingHeartRate ? 0.5 : 5)
        let bottom = low - pad
        let top = high + pad
        let span = max(top - bottom, 1)
        func scaled(_ value: Double) -> Double { (value - bottom) / span }
        let step = tickStep(series.kind, span: span)
        var ticks: [FactorLineRender.Tick] = []
        var tick = (bottom / step).rounded(.up) * step
        while tick <= top {
            ticks.append(FactorLineRender.Tick(position: scaled(tick), value: tick))
            tick += step
        }
        let unit = values.map { $0.map(scaled) }
        return FactorLineRender(
            kind: series.kind,
            values: unit,
            bandLow: band.map { scaled($0.lowerBound) },
            bandHigh: band.map { scaled($0.upperBound) },
            todayIndex: values.last.flatMap { $0 } != nil ? values.count - 1 : nil,
            axisLow: bottom,
            axisHigh: top,
            ticks: ticks,
            curve: curve(unit)
        )
    }

    /// `values` resampled to `FactorLineRender.curveSamples` evenly spaced
    /// points along the run: straight between recorded nights, held flat
    /// before the first and after the last.
    static func curve(_ values: [Double?]) -> [Double] {
        let recorded = values.enumerated().compactMap { index, value in value.map { (index: index, value: $0) } }
        let count = FactorLineRender.curveSamples
        guard let first = recorded.first, let last = recorded.last else { return Array(repeating: 0.5, count: count) }
        let span = Double(max(values.count - 1, 0))
        var next = 0
        return (0..<count).map { sample in
            let position = count > 1 ? Double(sample) / Double(count - 1) * span : 0
            if position <= Double(first.index) { return first.value }
            if position >= Double(last.index) { return last.value }
            while next + 1 < recorded.count, Double(recorded[next + 1].index) < position { next += 1 }
            let low = recorded[next]
            let high = recorded[min(next + 1, recorded.count - 1)]
            guard high.index > low.index else { return low.value }
            let t = (position - Double(low.index)) / Double(high.index - low.index)
            return low.value + (high.value - low.value) * min(max(t, 0), 1)
        }
    }

    /// A round step for the labels: whole hours for minutes, 1, 2, 5, 10…
    /// for ms and bpm, giving at most five labels.
    static func tickStep(_ kind: RecoveryFactorKind, span: Double) -> Double {
        let candidates: [Double] = switch kind {
        case .sleepDuration, .sleepConsistency: [30, 60, 120, 180, 240, 360]
        case .hrv, .restingHeartRate: [1, 2, 5, 10, 20, 50, 100]
        }
        let wanted = span / 5
        return candidates.first { $0 >= wanted } ?? candidates[candidates.count - 1]
    }
}
