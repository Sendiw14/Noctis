import Foundation
import HealthProviding

/// Turns raw HealthKit-shaped samples into sessions by contiguity in time,
/// never by calendar day — an 11:30 PM to 7:30 AM night must stay one
/// session regardless of the midnight boundary crossed inside it.
public enum SleepSessionEngine {
    public static func buildSessions(
        from samples: [RawSleepSample],
        mainSessionThreshold: TimeInterval = 3 * 3600,
        mergeGap: TimeInterval = 45 * 60
    ) -> [SleepSession] {
        let sorted = samples.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var runs: [[RawSleepSample]] = []
        var current: [RawSleepSample] = []

        for sample in sorted {
            if let last = current.last, sample.start.timeIntervalSince(last.end) > mergeGap {
                runs.append(current)
                current = [sample]
            } else {
                current.append(sample)
            }
        }
        if !current.isEmpty { runs.append(current) }

        return runs.compactMap { run in
            guard let first = run.first else { return nil }
            let latestEnd = run.map(\.end).max() ?? first.end
            let segments = run
                .sorted { $0.start < $1.start }
                .map { SleepStageSegment(stage: $0.stage, interval: DateInterval(start: $0.start, end: $0.end)) }

            let asleepDuration = segments
                .filter { $0.stage != .awake }
                .reduce(0.0) { $0 + $1.interval.duration }
            guard asleepDuration > 60 else { return nil }

            let kind: SleepSessionKind = asleepDuration >= mainSessionThreshold ? .main : .nap
            return SleepSession(kind: kind, bedtime: first.start, wakeTime: latestEnd, segments: segments, sourceName: first.sourceName)
        }
    }

    public static func mostRecentMainSession(in sessions: [SleepSession], asOf date: Date = .now) -> SleepSession? {
        sessions
            .filter { $0.kind == .main && $0.wakeTime <= date }
            .max { $0.wakeTime < $1.wakeTime }
    }

    public static func mainSessions(in sessions: [SleepSession]) -> [SleepSession] {
        sessions.filter { $0.kind == .main }.sorted { $0.bedtime < $1.bedtime }
    }
}
