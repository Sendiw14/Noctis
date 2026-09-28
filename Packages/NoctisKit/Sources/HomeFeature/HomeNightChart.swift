import DesignSystem
import Foundation
import HealthProviding
import NoctisCore
import SleepKit

// The night panel's content (and the share card's chart), built by
// `HomeScreenBuilder` from last night's session and its heart rate.

public nonisolated enum StripStage: String, Sendable, Equatable, CaseIterable {
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
/// are one bar, with no gaps inside it.
public nonisolated struct StripSegment: Sendable, Equatable {
    public let stage: StripStage
    /// Position along the night, 0...1.
    public let start: Double
    public let end: Double
    /// Awake for under `HomeScreenBuilder.briefAwakeMinutes`: drawn as a
    /// small tick rather than a bar.
    public let isTick: Bool

    public init(stage: StripStage, start: Double, end: Double, isTick: Bool = false) {
        self.stage = stage
        self.start = start
        self.end = end
        self.isTick = isTick
    }
}

/// The night panel's four lanes, top to bottom.
public nonisolated enum NightLane: Int, Sendable, Equatable, CaseIterable {
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

/// A step where the night moves from one bar straight into the next in
/// another lane: drawn from the end of one bar to the start of the next,
/// in the color of the stage being entered.
public nonisolated struct NightConnector: Sendable, Equatable {
    public let position: Double
    public let from: NightLane
    public let to: NightLane
}

/// The night panel's chart, drawn from SleepSessionEngine's timeline.
public nonisolated struct NightChartContent: Sendable, Equatable {
    /// Stage runs, 0...1 along the night; empty without stage data.
    public let spans: [StripSegment]
    public let connectors: [NightConnector]
    /// Start, midpoint and end clock times.
    public let timeLabels: [String]
    /// Without stage data: "Stages aren't available from your current
    /// sources." (the chart shows one sage bar in the Core lane).
    public let caption: String?
    /// Each lane's total, top to bottom; empty without stage data.
    public let laneTotals: [NightLaneTotal]
    /// Heart rate across the night; nil without samples.
    public let heart: NightHeartContent?
    /// The night's clock, for scrub readings; nil without stage data.
    let clock: NightClock?

    public var hasStages: Bool { caption == nil }

    /// The same chart without its heart-rate strip (the share card's
    /// default: heart rate shares only with "Include details").
    public func removingHeart() -> NightChartContent {
        NightChartContent(spans: spans, connectors: connectors, timeLabels: timeLabels, caption: caption, laneTotals: laneTotals, heart: nil, clock: clock)
    }

    /// What the scrub pill says with the finger at `position` (0...1
    /// across the chart): "3:41 AM · REM · 47 min · 52 bpm" — the clock
    /// time there, the stage run under it with its length, and the heart
    /// rate when there is one. Between runs, the nearest one.
    public func reading(at position: Double) -> NightReading? {
        guard let clock, !spans.isEmpty else { return nil }
        let position = min(max(position, 0), 1)
        let index = spans.firstIndex { position >= $0.start && position < $0.end }
            ?? spans.indices.min { distance(position, spans[$0]) < distance(position, spans[$1]) }
        guard let index else { return nil }
        return reading(segment: index, at: position, clock: clock)
    }

    /// Stepping through the night one run at a time (VoiceOver's
    /// adjustable action): the run's start, and the same text the pill
    /// shows there.
    public func reading(segment index: Int) -> NightReading? {
        guard let clock, spans.indices.contains(index) else { return nil }
        return reading(segment: index, at: spans[index].start, clock: clock)
    }

    /// Clock time at `position`, for the chart's Audio Graph axis.
    public func clockText(at position: Double) -> String {
        clock?.text(at: position) ?? ""
    }

    /// The night's length in minutes (the Audio Graph's x axis).
    public var minutes: Double { clock.map { $0.end.timeIntervalSince($0.start) / 60 } ?? 0 }

    private func reading(segment index: Int, at position: Double, clock: NightClock) -> NightReading {
        let span = spans[index]
        let length = Int(((span.end - span.start) * minutes).rounded())
        let time = clock.text(at: position)
        let bpm = heart?.bpm(at: position)
        let text = [time, span.stage.name, HomeFormat.compactDuration(length, minutesWord: true)] + (bpm.map { ["\($0) bpm"] } ?? [])
        let spoken = [time, span.stage.name, HomeFormat.spokenDuration(length)] + (bpm.map { ["\($0) beats per minute"] } ?? [])
        return NightReading(
            position: position,
            segment: index,
            stage: span.stage,
            text: text.joined(separator: " · "),
            spoken: spoken.joined(separator: ", ")
        )
    }

    private func distance(_ position: Double, _ span: StripSegment) -> Double {
        position < span.start ? span.start - position : max(position - span.end, 0)
    }
}

/// Where the scrub is and what the pill says there.
public nonisolated struct NightReading: Sendable, Equatable {
    /// 0...1 across the chart.
    public let position: Double
    /// Index into `NightChartContent.spans`.
    public let segment: Int
    public let stage: StripStage
    /// "3:41 AM · REM · 47 min · 52 bpm".
    public let text: String
    /// "3:41 AM, REM, 47 minutes, 52 beats per minute".
    public let spoken: String

    public var lane: NightLane { stage.lane }
}

/// A lane's total: "REM · 1h 32m" for the lane-label pill, and the
/// duration for the stage totals row.
public nonisolated struct NightLaneTotal: Sendable, Equatable {
    public let lane: NightLane
    /// "REM · 1h 32m".
    public let text: String
    public let duration: NoctisMetricValue
}

/// The heart-rate strip under the lanes: a line through the night's heart
/// rate (downsampled by `NightHeartSeries`), with its lowest point labeled.
public nonisolated struct NightHeartContent: Sendable, Equatable {
    /// 0...1 along the night, bpm.
    public let points: [NightHeartSeries.Point]
    /// The vertical range the strip draws (a little wider than the data).
    public let low: Double
    public let high: Double
    public let lowest: NightHeartSeries.Point
    /// "min 48 bpm".
    public let lowestLabel: String
    /// "Heart rate from 48 to 71 beats per minute."
    public let accessibilityLabel: String

    let series: NightHeartSeries

    /// Rounded heart rate at `position`, or nil outside the recorded part.
    public func bpm(at position: Double) -> Int? {
        series.bpm(at: position).map { Int($0.rounded()) }
    }
}

/// Turns a position along the night into a clock time, on the clock of
/// the time zone the night was recorded in.
nonisolated struct NightClock: Sendable, Equatable {
    let start: Date
    let end: Date
    let timeZone: TimeZone
    let format: HomeFormat

    func text(at position: Double) -> String {
        let date = start.addingTimeInterval(end.timeIntervalSince(start) * min(max(position, 0), 1))
        return format.clock(date, in: timeZone)
    }
}

public nonisolated struct LastNightCardContent: Sendable, Equatable {
    /// 8h 25m.
    public let duration: NoctisMetricValue
    /// "11:02 PM – 7:27 AM".
    public let timeRange: String
    public let chart: NightChartContent
    public let accessibilityLabel: String
}

// MARK: - Builder

nonisolated extension HomeScreenBuilder {
    /// Awake for less than this is a tick, not a bar.
    static let briefAwakeMinutes = 3.0
    /// Runs this close together (minutes) join: no gaps inside the night.
    static let joinGapMinutes = 2.0

    static func lastNightCard(_ session: SleepSession, heart: NightHeartSeries?, format: HomeFormat) -> LastNightCardContent {
        let minutes = Int((session.totals.asleep / 60).rounded())
        let bedtime = format.clock(session.bedtime, in: session.timeZone)
        let wake = format.clock(session.wakeTime, in: session.timeZone)
        let chart = nightChart(session, heart: heart, format: format)
        var spoken = "Last night, slept \(HomeFormat.spokenDuration(minutes)), \(bedtime) to \(wake)."
        if let caption = chart.caption {
            spoken += " " + caption
        } else {
            let present = Set(chart.spans.map(\.stage))
            let parts = StripStage.allCases.filter(present.contains).map { stage in
                "\(stage.name) \(HomeFormat.spokenDuration(Int((stageTotal(stage, session.totals) / 60).rounded())))"
            }
            spoken += " " + parts.joined(separator: ", ") + "."
        }
        if let heart = chart.heart {
            spoken += " " + heart.accessibilityLabel
        }
        return LastNightCardContent(
            duration: HomeFormat.durationMetric(minutes),
            timeRange: "\(bedtime) – \(wake)",
            chart: chart,
            accessibilityLabel: spoken
        )
    }

    /// The four-lane chart: one bar per run of a stage along the night
    /// (0...1), a step wherever the night moves straight into another
    /// lane, start, midpoint and end times, each lane's total, and the
    /// heart-rate line.
    static func nightChart(_ session: SleepSession, heart: NightHeartSeries?, format: HomeFormat) -> NightChartContent {
        let start = session.timeline.first?.interval.start ?? session.bedtime
        let end = session.timeline.map(\.interval.end).max() ?? session.wakeTime
        let span = max(end.timeIntervalSince(start), 1)
        let minutes = span / 60
        let labels = [start, start.addingTimeInterval(span / 2), end].map { format.clock($0, in: session.timeZone) }
        let heartContent = heart.map(heartContent)
        guard session.completeness.hasStageDetail else {
            return NightChartContent(
                spans: [], connectors: [], timeLabels: labels, caption: "Stages aren't available from your current sources.",
                laneTotals: [], heart: heartContent, clock: nil
            )
        }
        // Consecutive samples of one stage become one run, whatever lies
        // between them; runs a moment apart touch.
        let join = joinGapMinutes / minutes
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
                isTick: run.stage == .awake && (run.end - run.start) * minutes < briefAwakeMinutes
            )
        }
        let connectors = zip(spans, spans.dropFirst()).compactMap { previous, next -> NightConnector? in
            guard abs(next.start - previous.end) < 1e-9, previous.stage.lane != next.stage.lane else { return nil }
            return NightConnector(position: next.start, from: previous.stage.lane, to: next.stage.lane)
        }
        return NightChartContent(
            spans: spans,
            connectors: connectors,
            timeLabels: labels,
            caption: nil,
            laneTotals: laneTotals(session.totals),
            heart: heartContent,
            clock: NightClock(start: start, end: end, timeZone: session.timeZone, format: format)
        )
    }

    static func heartContent(_ series: NightHeartSeries) -> NightHeartContent {
        let lowest = series.lowest
        let highest = series.highest
        // A little headroom so the line never touches the strip's edges.
        let pad = max((highest.bpm - lowest.bpm) * 0.15, 2)
        let low = Int(lowest.bpm.rounded())
        let high = Int(highest.bpm.rounded())
        return NightHeartContent(
            points: series.points,
            low: lowest.bpm - pad,
            high: highest.bpm + pad,
            lowest: lowest,
            lowestLabel: "min \(low) bpm",
            accessibilityLabel: "Heart rate from \(low) to \(high) beats per minute.",
            series: series
        )
    }

    /// Each lane's total, top to bottom; unspecified sleep counts in Core,
    /// where it's drawn.
    static func laneTotals(_ totals: SleepTotals) -> [NightLaneTotal] {
        NightLane.allCases.map { lane in
            let seconds: TimeInterval = switch lane {
            case .awake: totals.awake
            case .rem: totals.rem
            case .core: totals.core + totals.unspecified
            case .deep: totals.deep
            }
            let minutes = Int((seconds / 60).rounded())
            return NightLaneTotal(
                lane: lane,
                text: "\(lane.name) · \(HomeFormat.compactDuration(minutes, minutesWord: true))",
                duration: HomeFormat.durationMetric(minutes)
            )
        }
    }

    static func stripStage(_ stage: SleepStageValue) -> StripStage? {
        switch stage {
        case .deep: .deep
        case .core: .core
        case .rem: .rem
        case .awake: .awake
        case .unspecified: .asleep
        case .inBed: nil
        }
    }

    static func stageTotal(_ stage: StripStage, _ totals: SleepTotals) -> TimeInterval {
        switch stage {
        case .deep: totals.deep
        case .core: totals.core
        case .rem: totals.rem
        case .awake: totals.awake
        case .asleep: totals.unspecified
        }
    }
}
