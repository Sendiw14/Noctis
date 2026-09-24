import Foundation
import HealthProviding

/// Turns raw HealthKit sleep samples into one main sleep per night plus
/// naps. Deterministic: the same samples, `now` and time zone always give
/// the same history.
///
/// 1. Resolve sources: stage samples and in-bed samples are resolved
///    separately by `DefaultSourceResolver` (exact duplicates removed; on
///    overlaps the higher-priority source wins; a source never overrides
///    itself).
/// 2. Cluster stage samples by contiguity: a gap of more than `joinGap`
///    starts a new cluster. Sessions are built by time, never by calendar
///    day, so a night that crosses midnight stays whole.
/// 3. Assign each cluster to the night of its first sample
///    (`SleepNightKey`, local clock of the sample's own time zone).
/// 4. Per night, every cluster with at least `mainSleepMinimum` asleep
///    joins the main sleep; everything else is a nap.
/// 5. Keep complete sessions only: wake time at or before `now`.
public enum SleepSessionEngine {
    /// Samples further apart than this start a new cluster.
    public static let joinGap: TimeInterval = 90 * 60
    /// A cluster with at least this much asleep time is main sleep.
    public static let mainSleepMinimum: TimeInterval = 3 * 3600
    /// Clusters with less asleep time than this are dropped as noise.
    public static let minimumAsleep: TimeInterval = 60
    /// Breaks between asleep stretches shorter than this aren't awakenings.
    public static let minimumAwakening: TimeInterval = 60

    public static func history(
        from samples: [RawSleepSample],
        asOf now: Date,
        timeZone: TimeZone = .current,
        priority: SourcePriority = .unranked
    ) -> SleepHistory {
        let valid = samples.filter { $0.end > $0.start }
        let resolver = DefaultSourceResolver(priority: priority)
        let stages = resolver.resolveSleepSamples(valid.filter { $0.stage != .inBed })
        let inBed = resolver.resolveSleepSamples(valid.filter { $0.stage == .inBed })

        let clusters = cluster(stages).filter { asleepDuration(of: $0) >= minimumAsleep }
        let byNight = Dictionary(grouping: clusters) { cluster -> SleepNightKey in
            let first = cluster[0]
            return SleepNightKey(containing: first.start, in: first.timeZone ?? timeZone)
        }

        var nights: [SleepSession] = []
        var naps: [SleepSession] = []
        for (night, nightClusters) in byNight {
            let mainClusters = nightClusters.filter { asleepDuration(of: $0) >= mainSleepMinimum }
            if !mainClusters.isEmpty {
                let merged = mainClusters.flatMap { $0 }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
                nights.append(session(.main, night: night, samples: merged, inBed: inBed, defaultTimeZone: timeZone))
            }
            for napCluster in nightClusters where asleepDuration(of: napCluster) < mainSleepMinimum {
                naps.append(session(.nap, night: night, samples: napCluster, inBed: inBed, defaultTimeZone: timeZone))
            }
        }

        return SleepHistory(
            nights: nights.filter { $0.wakeTime <= now }.sorted { $0.night < $1.night },
            naps: naps.filter { $0.wakeTime <= now }.sorted { $0.bedtime < $1.bedtime }
        )
    }

    // MARK: - Clustering

    private static func cluster(_ samples: [RawSleepSample]) -> [[RawSleepSample]] {
        let sorted = samples.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var clusters: [[RawSleepSample]] = []
        var current: [RawSleepSample] = []
        var currentEnd = Date.distantPast
        for sample in sorted {
            if !current.isEmpty, sample.start.timeIntervalSince(currentEnd) > joinGap {
                clusters.append(current)
                current = []
            }
            current.append(sample)
            currentEnd = current.count == 1 ? sample.end : max(currentEnd, sample.end)
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    private static func asleepDuration(of samples: [RawSleepSample]) -> TimeInterval {
        samples.filter(\.stage.isAsleep).reduce(0) { $0 + $1.duration }
    }

    // MARK: - Session

    private static func session(
        _ kind: SleepSessionKind,
        night: SleepNightKey,
        samples: [RawSleepSample],
        inBed: [RawSleepSample],
        defaultTimeZone: TimeZone
    ) -> SleepSession {
        let timeline = samples.map { SleepStageSegment(stage: $0.stage, interval: DateInterval(start: $0.start, end: $0.end)) }
        let spanStart = samples.map(\.start).min() ?? .distantPast
        let spanEnd = samples.map(\.end).max() ?? spanStart
        let asleepBlocks = union(samples.filter(\.stage.isAsleep).map { ($0.start, $0.end) })
        let wakeTime = asleepBlocks.last?.end ?? spanEnd

        func total(_ stage: SleepStageValue) -> TimeInterval {
            samples.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
        }
        let overlappingInBed = inBed.filter { $0.start < spanEnd && $0.end > spanStart }
        let inBedDuration = union([(spanStart, spanEnd)] + overlappingInBed.map { ($0.start, $0.end) })
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let totals = SleepTotals(
            asleep: asleepDuration(of: samples),
            inBed: inBedDuration,
            awake: total(.awake),
            core: total(.core),
            deep: total(.deep),
            rem: total(.rem),
            unspecified: total(.unspecified)
        )

        let awakenings = zip(asleepBlocks, asleepBlocks.dropFirst())
            .count { previous, next in next.start.timeIntervalSince(previous.end) >= minimumAwakening }
        let canShowWakefulness = totals.awake > 0 || !overlappingInBed.isEmpty
        let efficiency = canShowWakefulness && totals.inBed > 0 ? min(totals.asleep / totals.inBed, 1) : nil

        let span = spanEnd.timeIntervalSince(spanStart)
        let covered = union(samples.map { ($0.start, $0.end) }).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let completeness = SleepDataCompleteness(
            coverage: span > 0 ? min(covered / span, 1) : 0,
            hasStageDetail: samples.contains { [.core, .deep, .rem].contains($0.stage) },
            hasInBedData: !overlappingInBed.isEmpty
        )

        return SleepSession(
            kind: kind,
            night: night,
            bedtime: spanStart,
            wakeTime: wakeTime,
            timeZone: samples.first?.timeZone ?? defaultTimeZone,
            timeline: timeline,
            totals: totals,
            awakenings: awakenings,
            efficiency: efficiency,
            completeness: completeness,
            sourceName: samples.first?.sourceName ?? ""
        )
    }

    /// Merges intervals that overlap or touch, sorted by start.
    private static func union(_ intervals: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        var merged: [(start: Date, end: Date)] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
