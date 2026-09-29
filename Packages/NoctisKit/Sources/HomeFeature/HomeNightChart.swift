import DesignSystem
import Foundation
import HealthProviding
import NoctisCore
import SleepKit

// The night panel's content (and the share card's chart), built by
// `HomeScreenBuilder` from last night's session and its heart rate.

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
    /// The geometry the chart draws (positions along the night, lanes and
    /// the heart line in the strip's own space), from the snapshot.
    public let render: NightRender

    public var hasStages: Bool { caption == nil }

    /// The same chart without its heart-rate strip (the share card's
    /// default: heart rate shares only with "Include details").
    public func removingHeart() -> NightChartContent {
        NightChartContent(spans: spans, connectors: connectors, timeLabels: timeLabels, caption: caption, laneTotals: laneTotals, heart: nil, clock: clock, render: render.removingHeart())
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
    /// The line in the strip's own space, for drawing.
    public let line: NightHeartRender

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
    static func lastNightCard(_ session: SleepSession, heart: NightHeartSeries?, render: NightRender? = nil, format: HomeFormat) -> LastNightCardContent {
        let minutes = Int((session.totals.asleep / 60).rounded())
        let bedtime = format.clock(session.bedtime, in: session.timeZone)
        let wake = format.clock(session.wakeTime, in: session.timeZone)
        let chart = nightChart(session, heart: heart, render: render, format: format)
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

    /// The four-lane chart's words and readings: start, midpoint and end
    /// times, each lane's total, the heart-rate label. Its geometry (runs,
    /// steps, the heart line) comes from `render`, which the snapshot
    /// carries; without one it's worked out here.
    public static func nightChart(_ session: SleepSession, heart: NightHeartSeries?, render: NightRender? = nil, format: HomeFormat) -> NightChartContent {
        let render = render ?? NightRenderBuilder.build(session, heart: heart)
        let labels = [render.start, render.start.addingTimeInterval(render.end.timeIntervalSince(render.start) / 2), render.end]
            .map { format.clock($0, in: session.timeZone) }
        let heartContent = heart.flatMap { series in render.heart.map { heartContent(series, line: $0) } }
        guard render.hasStages else {
            return NightChartContent(
                spans: [], connectors: [], timeLabels: labels, caption: "Stages aren't available from your current sources.",
                laneTotals: [], heart: heartContent, clock: nil, render: render
            )
        }
        return NightChartContent(
            spans: render.runs,
            connectors: render.steps,
            timeLabels: labels,
            caption: nil,
            laneTotals: laneTotals(session.totals),
            heart: heartContent,
            clock: NightClock(start: render.start, end: render.end, timeZone: session.timeZone, format: format),
            render: render
        )
    }

    static func heartContent(_ series: NightHeartSeries, line: NightHeartRender) -> NightHeartContent {
        let lowest = series.lowest
        let highest = series.highest
        let low = Int(lowest.bpm.rounded())
        let high = Int(highest.bpm.rounded())
        return NightHeartContent(
            points: series.points,
            low: line.low,
            high: line.high,
            lowest: lowest,
            lowestLabel: "min \(low) bpm",
            accessibilityLabel: "Heart rate from \(low) to \(high) beats per minute.",
            series: series,
            line: line
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
