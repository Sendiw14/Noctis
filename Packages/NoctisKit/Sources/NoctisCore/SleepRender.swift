import DesignSystem
import Foundation
import RecoveryKit
import SleepAnalysisKit
import SleepKit

// The Sleep tab's render model: every piece of geometry a chart needs for
// one selection (a night, a week or a month), worked out once on
// `SleepRepository`'s actor in the space the views scale into (shares of a
// chart, positions along a clock axis, 0...1). Views multiply and draw;
// nothing is sorted, dated or built in a `body` (APP_RULES.md R23).

// MARK: - Day

/// The Sleep quality ring: one segment, and a tick where your usual is.
public nonisolated struct SleepRingRender: Sendable, Equatable {
    /// Score / 100.
    public let fraction: Double
    /// Your usual score / 100; nil without a baseline.
    public let usual: Double?
    public let arc: NoctisRingArc
}

/// One row of the stage breakdown, in lane order (Awake, REM, Core, Deep).
public nonisolated struct SleepStageRowRender: Sendable, Equatable {
    public let stage: StripStage
    public let minutes: Double
    /// A sleep stage's share of the time asleep; Awake's share of the time
    /// the stages cover. 0...1.
    public let share: Double
    /// Your usual share of the same; nil without 5 nights to compare.
    public let usual: Double?
}

public nonisolated struct SleepFactorBarRender: Sendable, Equatable {
    public let kind: SleepQualityFactorKind
    /// Score / 100.
    public let fraction: Double
}

public nonisolated struct SleepDayRender: Sendable, Equatable {
    /// The night's landscape; nil for a night with nothing recorded.
    public let night: NightRender?
    public let ring: SleepRingRender?
    /// Empty without stage data.
    public let stageRows: [SleepStageRowRender]
    public let factorBars: [SleepFactorBarRender]
}

// MARK: - Week and month

public nonisolated struct SleepBarRender: Sendable, Equatable {
    public let night: SleepNightKey
    /// Height as a share of the chart (0...1); nil with no data.
    public let fraction: Double?
    /// Deep, Core and REM as shares of the bar; nil without stages.
    public let stages: WeekBarStages?
    public let quality: Int?
}

/// The bars of a week or a month and the lines across them.
public nonisolated struct SleepBarsRender: Sendable, Equatable {
    public let bars: [SleepBarRender]
    /// The minutes at the top of the chart.
    public let topMinutes: Double
    /// The need line's height as a share of the chart.
    public let needFraction: Double
    /// The average over the recorded nights, as a share of the chart; nil
    /// with none.
    public let averageFraction: Double?
    /// The average in minutes asleep; nil with none.
    public let averageMinutes: Double?
}

/// Bedtimes and wake times on one clock axis, a row per night.
public nonisolated struct TimingDotsRender: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let night: SleepNightKey
        /// Positions along the axis, 0...1; nil when the night has no sleep.
        public let bedtime: Double?
        public let wake: Double?
    }

    /// The axis, in minutes after noon (11:00 PM = 660), on whole hours.
    public let axisStart: Double
    public let axisEnd: Double
    public let rows: [Row]
    /// Your usual bedtime and wake time (mean ± 1 SD, floored), as
    /// positions along the axis; nil without 5 nights to compare.
    public let bedtimeBand: ClosedRange<Double>?
    public let wakeBand: ClosedRange<Double>?
}

/// The 14-night balance as a line around zero.
public nonisolated struct BalanceRender: Sendable, Equatable {
    /// Height up the chart (0 bottom, 1 top) per night; nil where the
    /// window had too few nights.
    public let points: [Double?]
    /// Where zero sits.
    public let zero: Double
}

/// A run of nights that share one average line.
public nonisolated struct SleepWeekBlock: Sendable, Equatable {
    /// Indices into the bars, `start` up to (not including) `end`.
    public let start: Int
    public let end: Int
    /// The block's average as a share of the chart; nil under 3 recorded
    /// nights.
    public let averageFraction: Double?
}

/// Bedtime and wake time over the month as two lines, with your usual
/// bands.
public nonisolated struct RhythmRender: Sendable, Equatable {
    /// One position per night up the chart (0 top = earliest, 1 bottom =
    /// latest); nil where nothing was recorded.
    public let bedtime: [Double?]
    public let wake: [Double?]
    public let bedtimeBand: ClosedRange<Double>?
    public let wakeBand: ClosedRange<Double>?
    /// The axis in minutes after noon, on whole hours.
    public let axisStart: Double
    public let axisEnd: Double
}

/// Your typical night on one clock axis: bedtime to waking, the midpoint,
/// and (with 14 nights) the middle half of your own bedtimes and wake times.
public nonisolated struct TimingWindowRender: Sendable, Equatable {
    /// Positions along the axis, 0...1.
    public let bedtime: Double
    public let wake: Double
    public let midpoint: Double
    public let bedtimeRange: ClosedRange<Double>?
    public let wakeRange: ClosedRange<Double>?
    /// The axis in minutes after noon, on whole hours.
    public let axisStart: Double
    public let axisEnd: Double
}

public nonisolated struct QualityDotRender: Sendable, Equatable {
    public enum Band: String, Sendable, Equatable {
        /// 80 and up.
        case high
        /// 60 to 79.
        case middle
        /// Under 60.
        case low
    }

    public let night: SleepNightKey
    public let score: Int?
    public let band: Band?

    public static func band(for score: Int) -> Band {
        score >= 80 ? .high : score >= 60 ? .middle : .low
    }
}

public nonisolated struct SleepWeekRender: Sendable, Equatable {
    public let bars: SleepBarsRender
    public let consistency: TimingDotsRender
    /// Indices of the longest and the shortest recorded night; nil under
    /// two recorded nights.
    public let longest: Int?
    public let shortest: Int?
}

public nonisolated struct SleepMonthRender: Sendable, Equatable {
    public let bars: SleepBarsRender
    public let blocks: [SleepWeekBlock]
    /// Indices of the longest and the shortest recorded night; nil under
    /// two recorded nights.
    public let longest: Int?
    public let shortest: Int?
    public let rhythm: RhythmRender
    public let quality: [QualityDotRender]
}

/// Everything one selection draws, and the engine results its sentences
/// are built from.
public nonisolated struct SleepRenderModel: Sendable, Equatable {
    public let selection: SleepSelection
    public let day: SleepDayRender?
    public let week: SleepWeekRender?
    public let month: SleepMonthRender?
    /// The balance, consistency and timing as of the selected night.
    public let balance: SleepBalanceResult?
    public let balanceRender: BalanceRender?
    public let consistency: ConsistencyResult?
    public let timing: SleepTimingResult?
    public let timingRender: TimingWindowRender?
}

public nonisolated enum SleepRenderModelBuilder {
    /// Headroom above the tallest bar or the need line.
    public static let headroom = WeekRenderBuilder.headroom

    public static func build(_ snapshot: SleepSnapshot, selection: SleepSelection) -> SleepRenderModel {
        let sessions = snapshot.records.map(\.session)
        let need = Double(snapshot.needMinutes)
        let balance = SleepBalanceEngine.balance(history: sessions, needMinutes: need, endingAt: selection.night)
        let consistency = ConsistencyEngine.consistency(history: sessions, endingAt: selection.night)
        let timing = SleepTimingEngine.timing(history: sessions, endingAt: selection.night)
        return SleepRenderModel(
            selection: selection,
            day: selection.range == .day ? day(snapshot, night: selection.night) : nil,
            week: selection.range == .week ? week(snapshot, night: selection.night) : nil,
            month: selection.range == .month ? month(snapshot, night: selection.night) : nil,
            balance: balance,
            balanceRender: balance.map(balanceRender),
            consistency: consistency,
            timing: timing,
            timingRender: timing.flatMap(timingWindow)
        )
    }

    // MARK: Day

    static func day(_ snapshot: SleepSnapshot, night: SleepNightKey) -> SleepDayRender {
        guard let record = snapshot.record(night) else {
            return SleepDayRender(night: nil, ring: nil, stageRows: [], factorBars: [])
        }
        let window = snapshot.window(before: night)
        let usual = record.quality.usual.map { $0 / 100 }
        let weights = [1.0]
        let arc = NoctisRecoveryRingLayout.arcs(weights: weights).first ?? (start: 0, end: 360)
        let ring = SleepRingRender(
            fraction: Double(record.quality.score) / 100,
            usual: usual,
            arc: NoctisRingArc(
                startDegrees: arc.start, endDegrees: arc.end,
                tickDegrees: usual.flatMap { NoctisRecoveryRingLayout.tickAngle(weights: weights, index: 0, usual: $0) }
            )
        )
        return SleepDayRender(
            night: NightRenderBuilder.build(record.session, heart: record.heart),
            ring: ring,
            stageRows: stageRows(record, window: window),
            factorBars: record.quality.factors.map { SleepFactorBarRender(kind: $0.kind, fraction: Double($0.score) / 100) }
        )
    }

    static func stageRows(_ record: SleepNightRecord, window: [SleepNightRecord]) -> [SleepStageRowRender] {
        guard let stages = record.metrics.stages, let shares = stages.asleepShares else { return [] }
        let history = window.compactMap { $0.metrics.stages }
        func usual(_ value: (SleepStageBreakdown) -> Double?) -> Double? {
            BaselineEngine.baseline(history.compactMap(value))?.value
        }
        return [
            SleepStageRowRender(stage: .awake, minutes: stages.awake, share: stages.awakeShare ?? 0, usual: usual { $0.awakeShare }),
            SleepStageRowRender(stage: .rem, minutes: stages.rem, share: shares.rem, usual: usual { $0.asleepShares?.rem }),
            SleepStageRowRender(stage: .core, minutes: stages.core, share: shares.core, usual: usual { $0.asleepShares?.core }),
            SleepStageRowRender(stage: .deep, minutes: stages.deep, share: shares.deep, usual: usual { $0.asleepShares?.deep }),
        ]
    }

    // MARK: Week and month

    static func bars(_ snapshot: SleepSnapshot, night: SleepNightKey, count: Int) -> SleepBarsRender {
        let nights = snapshot.nights(endingAt: night, count: count)
        let need = Double(snapshot.needMinutes)
        let asleep = nights.compactMap { $0.record?.metrics.asleepMinutes }
        let top = max(need, asleep.max() ?? 0) * headroom
        let bars = nights.map { entry -> SleepBarRender in
            let stages = entry.record?.metrics.stages
            var shares: WeekBarStages?
            if let stages, stages.asleep > 0 {
                shares = WeekBarStages(deep: stages.deep / stages.asleep, core: stages.core / stages.asleep, rem: stages.rem / stages.asleep)
            }
            return SleepBarRender(
                night: entry.night,
                fraction: entry.record.map { top > 0 ? $0.metrics.asleepMinutes / top : 0 },
                stages: shares,
                quality: entry.record?.quality.score
            )
        }
        let average = asleep.isEmpty ? nil : asleep.reduce(0, +) / Double(asleep.count)
        return SleepBarsRender(
            bars: bars, topMinutes: top, needFraction: top > 0 ? need / top : 0,
            averageFraction: average.map { top > 0 ? $0 / top : 0 }, averageMinutes: average
        )
    }

    static func week(_ snapshot: SleepSnapshot, night: SleepNightKey) -> SleepWeekRender {
        let nights = snapshot.nights(endingAt: night, count: 7)
        let (longest, shortest) = extremes(nights)
        return SleepWeekRender(
            bars: bars(snapshot, night: night, count: 7),
            consistency: timingDots(snapshot, night: night, count: 7),
            longest: longest,
            shortest: shortest
        )
    }

    /// The longest and the shortest recorded night among `nights` (indices);
    /// nil under two recorded nights, and no shortest when it is the longest.
    static func extremes(_ nights: [(night: SleepNightKey, record: SleepNightRecord?)]) -> (longest: Int?, shortest: Int?) {
        let recorded = nights.enumerated().compactMap { index, entry in entry.record.map { (index, $0.metrics.asleepMinutes) } }
        let longest = recorded.count >= 2 ? recorded.max { $0.1 < $1.1 }?.0 : nil
        let shortest = recorded.count >= 2 ? recorded.min { $0.1 < $1.1 }?.0 : nil
        return (longest, shortest == longest ? nil : shortest)
    }

    static func month(_ snapshot: SleepSnapshot, night: SleepNightKey) -> SleepMonthRender {
        let nights = snapshot.nights(endingAt: night, count: 30)
        let bars = bars(snapshot, night: night, count: 30)
        // Blocks of seven counted back from the last night; the first may
        // be short.
        var blocks: [SleepWeekBlock] = []
        var end = nights.count
        while end > 0 {
            let start = max(end - 7, 0)
            let recorded = nights[start..<end].compactMap { $0.record?.metrics.asleepMinutes }
            let top = bars.topMinutes
            blocks.insert(
                SleepWeekBlock(
                    start: start, end: end,
                    averageFraction: recorded.count >= 3 && top > 0 ? recorded.reduce(0, +) / Double(recorded.count) / top : nil
                ),
                at: 0
            )
            end = start
        }
        let (longest, shortest) = extremes(nights)
        return SleepMonthRender(
            bars: bars,
            blocks: blocks,
            longest: longest,
            shortest: shortest,
            rhythm: rhythm(snapshot, night: night),
            quality: nights.map { entry in
                QualityDotRender(night: entry.night, score: entry.record?.quality.score, band: entry.record.map { QualityDotRender.band(for: $0.quality.score) })
            }
        )
    }

    // MARK: Clock axes

    /// Whole-hour axis bounds (minutes after noon) that hold `values` with
    /// half an hour to spare.
    static func axis(_ values: [Double]) -> (start: Double, end: Double) {
        guard let low = values.min(), let high = values.max() else { return (540, 1260) }
        let start = ((low - 30) / 60).rounded(.down) * 60
        var end = ((high + 30) / 60).rounded(.up) * 60
        if end - start < 240 { end = start + 240 }
        return (start, end)
    }

    /// Your usual ± 1 SD (spread floored) of `values`; nil under 5 nights.
    static func usualBand(_ values: [Double]) -> ClosedRange<Double>? {
        guard let baseline = BaselineEngine.baseline(values) else { return nil }
        let spread = max(baseline.standardDeviation, RecoveryNormalRange.timingStandardDeviationFloor)
        return (baseline.value - spread)...(baseline.value + spread)
    }

    static func timingDots(_ snapshot: SleepSnapshot, night: SleepNightKey, count: Int) -> TimingDotsRender {
        let nights = snapshot.nights(endingAt: night, count: count)
        let window = snapshot.window(before: night).map(\.metrics)
        let bedBand = usualBand(window.map(\.bedtimeMinutes))
        let wakeBand = usualBand(window.map(\.wakeMinutes))
        let values = nights.compactMap { $0.record }.flatMap { [$0.metrics.bedtimeMinutes, $0.metrics.wakeMinutes] }
            + [bedBand?.lowerBound, bedBand?.upperBound, wakeBand?.lowerBound, wakeBand?.upperBound].compactMap { $0 }
        let bounds = axis(values)
        let span = max(bounds.end - bounds.start, 1)
        func position(_ minutes: Double) -> Double { min(max((minutes - bounds.start) / span, 0), 1) }
        func band(_ range: ClosedRange<Double>?) -> ClosedRange<Double>? {
            range.map { position($0.lowerBound)...position($0.upperBound) }
        }
        return TimingDotsRender(
            axisStart: bounds.start, axisEnd: bounds.end,
            rows: nights.map { entry in
                TimingDotsRender.Row(
                    night: entry.night,
                    bedtime: entry.record.map { position($0.metrics.bedtimeMinutes) },
                    wake: entry.record.map { position($0.metrics.wakeMinutes) }
                )
            },
            bedtimeBand: band(bedBand),
            wakeBand: band(wakeBand)
        )
    }

    static func rhythm(_ snapshot: SleepSnapshot, night: SleepNightKey) -> RhythmRender {
        let nights = snapshot.nights(endingAt: night, count: 30)
        let metrics = nights.compactMap { $0.record?.metrics }
        let bedBand = usualBand(metrics.map(\.bedtimeMinutes))
        let wakeBand = usualBand(metrics.map(\.wakeMinutes))
        let bounds = axis(metrics.flatMap { [$0.bedtimeMinutes, $0.wakeMinutes] } + [bedBand?.lowerBound, bedBand?.upperBound, wakeBand?.lowerBound, wakeBand?.upperBound].compactMap { $0 })
        let span = max(bounds.end - bounds.start, 1)
        func position(_ minutes: Double) -> Double { min(max((minutes - bounds.start) / span, 0), 1) }
        func band(_ range: ClosedRange<Double>?) -> ClosedRange<Double>? {
            range.map { position($0.lowerBound)...position($0.upperBound) }
        }
        return RhythmRender(
            bedtime: nights.map { $0.record.map { position($0.metrics.bedtimeMinutes) } },
            wake: nights.map { $0.record.map { position($0.metrics.wakeMinutes) } },
            bedtimeBand: band(bedBand), wakeBand: band(wakeBand), axisStart: bounds.start, axisEnd: bounds.end
        )
    }

    static func timingWindow(_ timing: SleepTimingResult) -> TimingWindowRender? {
        guard let bedtime = timing.typicalBedtime, let wake = timing.typicalWake, let midpoint = timing.typicalMidpoint else { return nil }
        let ranges = [timing.suggested?.bedtime, timing.suggested?.wake].compactMap { $0 }
        let bounds = axis([bedtime, wake] + ranges.flatMap { [$0.lowerBound, $0.upperBound] })
        let span = max(bounds.end - bounds.start, 1)
        func position(_ minutes: Double) -> Double { min(max((minutes - bounds.start) / span, 0), 1) }
        func band(_ range: ClosedRange<Double>?) -> ClosedRange<Double>? {
            range.map { position($0.lowerBound)...position($0.upperBound) }
        }
        return TimingWindowRender(
            bedtime: position(bedtime), wake: position(wake), midpoint: position(midpoint),
            bedtimeRange: band(timing.suggested?.bedtime), wakeRange: band(timing.suggested?.wake),
            axisStart: bounds.start, axisEnd: bounds.end
        )
    }

    // MARK: Balance

    static func balanceRender(_ result: SleepBalanceResult) -> BalanceRender {
        let values = result.series.compactMap(\.minutes)
        let low = min(values.min() ?? 0, 0)
        let high = max(values.max() ?? 0, 0)
        let pad = max((high - low) * 0.1, 15)
        let bottom = low - pad
        let top = high + pad
        let range = max(top - bottom, 1)
        return BalanceRender(points: result.series.map { $0.minutes.map { ($0 - bottom) / range } }, zero: (0 - bottom) / range)
    }
}
