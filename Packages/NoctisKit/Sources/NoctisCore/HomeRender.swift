import DesignSystem
import Foundation
import HealthProviding
import RecoveryKit
import SleepKit

// Home's render model: every piece of geometry a chart or ring needs,
// computed once per snapshot on `HomeRepository`'s actor, in the space
// the views scale into (positions along the night 0...1, angles in
// degrees, shares of a chart). Views turn it into points with one
// multiplication and only draw: no sorting, date math or path building
// happens in a `body` or a `Canvas` closure (APP_RULES.md R23).

// MARK: - The night

public nonisolated enum StripStage: String, Sendable, Equatable, CaseIterable, Codable {
    case deep
    case core
    case rem
    case awake
    /// Asleep without a stage ("unspecified").
    case asleep

    public var name: String {
        switch self {
        case .deep: "Deep"
        case .core: "Core"
        case .rem: "REM"
        case .awake: "Awake"
        case .asleep: "Asleep"
        }
    }
}

/// One continuous run of a stage: consecutive samples of the same stage
/// are one run, with no gaps inside it.
public nonisolated struct StripSegment: Sendable, Equatable, Codable {
    public let stage: StripStage
    /// Position along the night, 0...1.
    public let start: Double
    public let end: Double
    /// A run under `NightRenderBuilder.notchMinutes`, of any stage: drawn
    /// as a small rounded notch in its lane instead of a piece of the
    /// ribbon, so a brief awakening is never a tall stick.
    public let isNotch: Bool

    public init(stage: StripStage, start: Double, end: Double, isNotch: Bool = false) {
        self.stage = stage
        self.start = start
        self.end = end
        self.isNotch = isNotch
    }
}

/// The night panel's four lanes, top to bottom.
public nonisolated enum NightLane: Int, Sendable, Equatable, CaseIterable, Codable {
    case awake
    case rem
    case core
    case deep

    public var name: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        }
    }
}

nonisolated extension StripStage {
    /// Unspecified sleep sits in the Core lane.
    public var lane: NightLane {
        switch self {
        case .awake: .awake
        case .rem: .rem
        case .core, .asleep: .core
        case .deep: .deep
        }
    }
}

/// Where the ribbon moves from one lane to another: a vertical capsule
/// from the lane it leaves to the lane it enters, in the color of the
/// stage entered. Only between runs that touch (a notch between them
/// doesn't break the ribbon), never across missing data.
public nonisolated struct NightConnector: Sendable, Equatable, Codable {
    /// 0...1 along the night: where the two runs meet.
    public let position: Double
    public let from: NightLane
    public let to: NightLane
    /// The stage the ribbon enters (it colors the step).
    public let entered: StripStage

    public init(position: Double, from: NightLane, to: NightLane, entered: StripStage) {
        self.position = position
        self.from = from
        self.to = to
        self.entered = entered
    }
}

/// The heart-rate line in the strip's own space: x along the night, y up
/// the strip (0 at the strip's low, 1 at its high, a little wider than the
/// data), so the view scales it and never touches a bpm.
public nonisolated struct NightHeartRender: Sendable, Equatable, Codable {
    public struct Point: Sendable, Equatable, Codable {
        /// 0...1 along the night.
        public let x: Double
        /// 0...1 up the strip.
        public let y: Double
    }

    public let points: [Point]
    public let lowest: Point
    /// The bpm at the strip's bottom and top.
    public let low: Double
    public let high: Double

    public init(_ series: NightHeartSeries) {
        let lowestPoint = series.lowest
        let highestPoint = series.highest
        // A little headroom so the line never touches the strip's edges.
        let pad = max((highestPoint.bpm - lowestPoint.bpm) * 0.15, 2)
        let bottom = lowestPoint.bpm - pad
        let top = highestPoint.bpm + pad
        let range = max(top - bottom, 1)
        func unit(_ point: NightHeartSeries.Point) -> Point {
            Point(x: point.position, y: (point.bpm - bottom) / range)
        }
        low = bottom
        high = top
        points = series.points.map(unit)
        lowest = unit(lowestPoint)
    }
}

/// Which lane the ribbon is in from a position on.
public nonisolated struct RibbonLane: Sendable, Equatable, Codable {
    public let start: Double
    public let lane: NightLane
}

/// Last night's chart geometry: the stage runs (0...1 along the night),
/// the steps between lanes, where the ribbon is at any position (for the
/// reveal's head dot), and the heart-rate line.
public nonisolated struct NightRender: Sendable, Equatable, Codable {
    /// Stage runs; empty without stage data.
    public let runs: [StripSegment]
    public let steps: [NightConnector]
    /// The lane of each ribbon run (notches excluded) from its start.
    public let ribbon: [RibbonLane]
    public let heart: NightHeartRender?
    public let hasStages: Bool
    /// The night's length, first stage sample to last.
    public let start: Date
    public let end: Date

    public var minutes: Double { end.timeIntervalSince(start) / 60 }

    /// The same geometry without the heart-rate line (the share card's
    /// default).
    public func removingHeart() -> NightRender {
        NightRender(runs: runs, steps: steps, ribbon: ribbon, heart: nil, hasStages: hasStages, start: start, end: end)
    }

    /// The lane the ribbon is in at `position` (the run there, or the
    /// nearest before it): a binary search, so the reveal's head dot costs
    /// nothing per frame.
    public func lane(at position: Double) -> NightLane? {
        guard let first = ribbon.first else { return nil }
        if position <= first.start { return first.lane }
        var low = 0
        var high = ribbon.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if ribbon[middle].start <= position { low = middle } else { high = middle - 1 }
        }
        return ribbon[low].lane
    }
}

public nonisolated enum NightRenderBuilder {
    /// A run shorter than this (any stage) is a notch, not ribbon.
    public static let notchMinutes = 3.0
    /// Runs this close together (minutes) join: no gaps inside the night.
    public static let joinGapMinutes = 2.0

    public static func build(_ session: SleepSession, heart: NightHeartSeries?) -> NightRender {
        let start = session.timeline.first?.interval.start ?? session.bedtime
        let end = session.timeline.map(\.interval.end).max() ?? session.wakeTime
        let heartRender = heart.map(NightHeartRender.init)
        guard session.completeness.hasStageDetail else {
            return NightRender(runs: [], steps: [], ribbon: [], heart: heartRender, hasStages: false, start: start, end: end)
        }
        let span = max(end.timeIntervalSince(start), 1)
        // Consecutive samples of one stage become one run, whatever lies
        // between them; runs a moment apart touch.
        let join = joinGapMinutes / (span / 60)
        var runs: [(stage: StripStage, start: Double, end: Double)] = []
        for segment in session.timeline.sorted(by: { $0.interval.start < $1.interval.start }) {
            guard let stage = stripStage(segment.stage) else { continue }
            let from = segment.interval.start.timeIntervalSince(start) / span
            let to = segment.interval.end.timeIntervalSince(start) / span
            if let last = runs.last, last.stage == stage {
                runs[runs.count - 1].end = max(last.end, to)
            } else {
                if let last = runs.last, from - last.end <= join, from > last.end {
                    runs[runs.count - 1].end = from
                }
                runs.append((stage, from, to))
            }
        }
        let spans = runs.map { run in
            StripSegment(
                stage: run.stage, start: run.start, end: run.end,
                // Whole seconds, so exactly 3 minutes is a run, not a notch.
                isNotch: ((run.end - run.start) * span).rounded() < notchMinutes * 60
            )
        }
        return NightRender(
            runs: spans,
            steps: ribbonSteps(spans),
            ribbon: spans.filter { !$0.isNotch }.map { RibbonLane(start: $0.start, lane: $0.stage.lane) },
            heart: heartRender,
            hasStages: true,
            start: start,
            end: end
        )
    }

    /// The ribbon's lane changes: between each pair of runs that touch
    /// (any notches between them included) in different lanes, at the
    /// middle of whatever notches sit between.
    public static func ribbonSteps(_ spans: [StripSegment]) -> [NightConnector] {
        var steps: [NightConnector] = []
        var previous: StripSegment?
        var lastEnd = 0.0
        var intact = false
        for span in spans {
            intact = intact && abs(span.start - lastEnd) < 1e-6
            lastEnd = span.end
            guard !span.isNotch else { continue }
            if let previous, intact, previous.stage.lane != span.stage.lane {
                steps.append(NightConnector(
                    position: (previous.end + span.start) / 2, from: previous.stage.lane, to: span.stage.lane, entered: span.stage
                ))
            }
            previous = span
            intact = true
        }
        return steps
    }

    public static func stripStage(_ stage: SleepStageValue) -> StripStage? {
        switch stage {
        case .deep: .deep
        case .core: .core
        case .rem: .rem
        case .awake: .awake
        case .unspecified: .asleep
        case .inBed: nil
        }
    }
}

// MARK: - The ring

/// One factor's slice of the recovery ring, with its angles: the arc it
/// covers (degrees, 0 = top, clockwise, with the ring's 3° gaps) and where
/// your usual sits on it.
public nonisolated struct RingArc: Sendable, Equatable, Codable {
    public let kind: RecoveryFactorKind
    /// Renormalized weight (0...1): the segment's share of the ring.
    public let weight: Double
    /// Factor score / 100.
    public let fraction: Double
    /// Your usual score / 100; nil without a baseline.
    public let usual: Double?
    public let startDegrees: Double
    public let endDegrees: Double
    /// The "usual" tick's angle; nil without a baseline.
    public let tickDegrees: Double?

}

public nonisolated enum RingRenderBuilder {
    /// Ring and factor-row order.
    public static let factorOrder: [RecoveryFactorKind] = [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency]

    public static func build(_ result: RecoveryResult) -> [RingArc] {
        let factors = factorOrder.compactMap { result.factor($0) }
        let weights = factors.map(\.weight)
        let arcs = NoctisRecoveryRingLayout.arcs(weights: weights)
        guard arcs.count == factors.count else { return [] }
        return factors.enumerated().map { index, factor in
            let usual = factor.usual.map { $0 / 100 }
            return RingArc(
                kind: factor.kind,
                weight: factor.weight,
                fraction: Double(factor.score) / 100,
                usual: usual,
                startDegrees: arcs[index].start,
                endDegrees: arcs[index].end,
                tickDegrees: usual.flatMap { NoctisRecoveryRingLayout.tickAngle(weights: weights, index: index, usual: $0) }
            )
        }
    }
}

// MARK: - This week

/// Deep, Core and REM as shares of a week bar, bottom to top.
public nonisolated struct WeekBarStages: Sendable, Equatable, Codable {
    public let deep: Double
    public let core: Double
    public let rem: Double

    public init(deep: Double, core: Double, rem: Double) {
        self.deep = deep
        self.core = core
        self.rem = rem
    }
}

public nonisolated struct WeekBarRender: Sendable, Equatable, Codable {
    /// Bar height as a share of the chart (0...1); nil with no data.
    public let fraction: Double?
    /// Nil for a night without stages (a solid sage bar).
    public let stages: WeekBarStages?
    public let isLastNight: Bool
}

public nonisolated struct WeekRender: Sendable, Equatable, Codable {
    public let bars: [WeekBarRender]
    /// Height of the dashed need line, as a share of the chart.
    public let needFraction: Double

    public static let empty = WeekRender(bars: [], needFraction: 0)
}

public nonisolated enum WeekRenderBuilder {
    /// Headroom above the tallest bar or the need line.
    public static let headroom = 1.12

    public static func build(_ nights: [NightDuration], needMinutes: Int, lastNight: SleepNightKey?) -> WeekRender {
        let need = Double(needMinutes)
        let longest = nights.compactMap(\.asleepMinutes).max() ?? 0
        let top = max(need, longest) * headroom
        let bars = nights.map { night -> WeekBarRender in
            var stages: WeekBarStages?
            if let split = night.stages, split.deep + split.core + split.rem > 0 {
                let total = split.deep + split.core + split.rem
                stages = WeekBarStages(deep: split.deep / total, core: split.core / total, rem: split.rem / total)
            }
            return WeekBarRender(
                fraction: night.asleepMinutes.map { top > 0 ? $0 / top : 0 },
                stages: stages,
                isLastNight: night.night == lastNight
            )
        }
        return WeekRender(bars: bars, needFraction: top > 0 ? need / top : 0)
    }
}

// MARK: - Sparklines

/// A factor's 14 nights for Recovery detail, scaled to one chart (0...1
/// up): the normal range as a band, a line through the nights, and today.
public nonisolated struct SparklineRender: Sendable, Equatable, Codable {
    public let kind: RecoveryFactorKind
    /// Oldest first; nil with no value that night.
    public let nights: [Double?]
    public let today: Double
    public let bandLow: Double
    public let bandHigh: Double
}

public nonisolated enum SparklineRenderBuilder {
    /// The 14 nights, the normal range and today, scaled to one chart
    /// (0...1 up); consistency is drawn as bedtime.
    public static func build(_ history: RecoveryFactorHistory) -> SparklineRender {
        let range = history.normalRange
        let all = history.values.compactMap { $0 } + [history.today, range.lowerBound, range.upperBound]
        let low = all.min() ?? 0
        let high = all.max() ?? 1
        let pad = max((high - low) * 0.1, 0.5)
        let (bottom, top) = (low - pad, high + pad)
        func scaled(_ value: Double) -> Double { (value - bottom) / (top - bottom) }
        return SparklineRender(
            kind: history.kind,
            nights: history.values.map { $0.map(scaled) },
            today: scaled(history.today),
            bandLow: scaled(range.lowerBound),
            bandHigh: scaled(range.upperBound)
        )
    }
}

// MARK: - The model

/// Everything Home draws, as geometry. Built with the snapshot, so it is
/// never worked out on the main thread.
public nonisolated struct HomeRenderModel: Sendable, Equatable, Codable {
    /// The scored ring's arcs; empty without a score.
    public let ring: [RingArc]
    public let night: NightRender?
    public let week: WeekRender
    /// One per factor with 5 nights of history, in factor order.
    public let sparklines: [SparklineRender]

    public static let empty = HomeRenderModel(ring: [], night: nil, week: .empty, sparklines: [])

    public func sparkline(_ kind: RecoveryFactorKind) -> SparklineRender? {
        sparklines.first { $0.kind == kind }
    }
}

public nonisolated enum HomeRenderModelBuilder {
    public static func build(
        recovery: RecoveryState?,
        lastNight: SleepSession?,
        heart: NightHeartSeries?,
        recentNights: [NightDuration],
        needMinutes: Int
    ) -> HomeRenderModel {
        var ring: [RingArc] = []
        var sparklines: [SparklineRender] = []
        if case .scored(let result)? = recovery {
            ring = RingRenderBuilder.build(result)
            sparklines = RingRenderBuilder.factorOrder.compactMap { kind in
                result.history(kind).map(SparklineRenderBuilder.build)
            }
        }
        return HomeRenderModel(
            ring: ring,
            night: lastNight.map { NightRenderBuilder.build($0, heart: heart) },
            week: WeekRenderBuilder.build(recentNights, needMinutes: needMinutes, lastNight: lastNight?.night),
            sparklines: sparklines
        )
    }
}
