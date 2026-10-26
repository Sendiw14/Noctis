import Foundation
import SleepKit

/// The minutes in each stage of one night. Unspecified sleep counts as
/// Core, where the night panel draws it.
public struct SleepStageBreakdown: Sendable, Equatable, Codable {
    public let deep: Double
    public let core: Double
    public let rem: Double
    /// All time in the awake stage, before falling asleep and after waking
    /// included.
    public let awake: Double

    public init(deep: Double, core: Double, rem: Double, awake: Double) {
        self.deep = deep
        self.core = core
        self.rem = rem
        self.awake = awake
    }

    /// Deep, Core and REM together.
    public var asleep: Double { deep + core + rem }

    /// Each sleep stage's share of the time asleep (they add to 1); nil
    /// with no time asleep in any stage.
    public var asleepShares: (deep: Double, core: Double, rem: Double)? {
        guard asleep > 0 else { return nil }
        return (deep / asleep, core / asleep, rem / asleep)
    }

    /// The awake stage's share of all the time the stages cover.
    public var awakeShare: Double? {
        let total = asleep + awake
        return total > 0 ? awake / total : nil
    }
}

/// Everything derived from one night's session, in minutes after noon for
/// clock times (11:00 PM = 660).
public struct SleepMetrics: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    public let asleepMinutes: Double
    public let timeInBedMinutes: Double
    /// Asleep ÷ in bed. Nil unless an in-bed record backs the in-bed time:
    /// without one, "in bed" is only the span of the sleep samples.
    public let efficiency: Double?
    /// Breaks of a minute or more between asleep stretches.
    public let awakenings: Int
    /// Time awake between falling asleep and the last moment asleep. Nil
    /// when the source can't show wakefulness (no awake stage and no
    /// in-bed record).
    public let awakeAfterOnsetMinutes: Double?
    /// Time from the first sample to falling asleep. Nil unless the night
    /// begins with a stretch marked awake (the only case where it can be
    /// told).
    public let onsetLatencyMinutes: Double?
    /// Nil when the source recorded no stages.
    public let stages: SleepStageBreakdown?
    public let bedtimeMinutes: Double
    public let wakeMinutes: Double

    /// The middle of the night, halfway between bedtime and waking.
    public var midpointMinutes: Double { (bedtimeMinutes + wakeMinutes) / 2 }

    public init(
        night: SleepNightKey, asleepMinutes: Double, timeInBedMinutes: Double, efficiency: Double?, awakenings: Int,
        awakeAfterOnsetMinutes: Double?, onsetLatencyMinutes: Double?, stages: SleepStageBreakdown?,
        bedtimeMinutes: Double, wakeMinutes: Double
    ) {
        self.night = night
        self.asleepMinutes = asleepMinutes
        self.timeInBedMinutes = timeInBedMinutes
        self.efficiency = efficiency
        self.awakenings = awakenings
        self.awakeAfterOnsetMinutes = awakeAfterOnsetMinutes
        self.onsetLatencyMinutes = onsetLatencyMinutes
        self.stages = stages
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
    }
}

/// Turns a night's session into its metrics. Pure and deterministic.
public enum SleepMetricsEngine {
    public static func metrics(for session: SleepSession) -> SleepMetrics {
        let totals = session.totals
        let asleep = totals.asleep / 60
        let inBed = totals.inBed / 60

        let efficiency: Double? = session.completeness.hasInBedData && inBed > 0 ? min(asleep / inBed, 1) : nil

        // Wakefulness can only be read from an awake stage or an in-bed
        // record; a source that says only "asleep" has none to show.
        let canShowWakefulness = totals.awake > 0 || session.completeness.hasInBedData
        let asleepBlocks = union(session.timeline.filter(\.stage.isAsleep).map(\.interval))
        var afterOnset: Double?
        if canShowWakefulness, let first = asleepBlocks.first, let last = asleepBlocks.last {
            let period = last.end.timeIntervalSince(first.start)
            let asleepInside = asleepBlocks.reduce(0) { $0 + $1.duration }
            afterOnset = max(period - asleepInside, 0) / 60
        }

        var latency: Double?
        if let firstSegment = session.timeline.min(by: { $0.interval.start < $1.interval.start }),
            firstSegment.stage == .awake,
            let onset = asleepBlocks.first?.start
        {
            latency = max(onset.timeIntervalSince(firstSegment.interval.start), 0) / 60
        }

        var stages: SleepStageBreakdown?
        if session.completeness.hasStageDetail {
            stages = SleepStageBreakdown(
                deep: totals.deep / 60,
                core: (totals.core + totals.unspecified) / 60,
                rem: totals.rem / 60,
                awake: totals.awake / 60
            )
        }

        return SleepMetrics(
            night: session.night,
            asleepMinutes: asleep,
            timeInBedMinutes: inBed,
            efficiency: efficiency,
            awakenings: session.awakenings,
            awakeAfterOnsetMinutes: afterOnset,
            onsetLatencyMinutes: latency,
            stages: stages,
            bedtimeMinutes: session.bedtimeMinutesAfterNoon,
            wakeMinutes: session.wakeMinutesAfterNoon
        )
    }

    /// Merges intervals that overlap or touch, sorted by start.
    static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
