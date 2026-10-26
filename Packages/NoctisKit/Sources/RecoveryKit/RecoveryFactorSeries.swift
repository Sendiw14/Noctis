import Foundation
import SleepKit

/// The ranges a factor's chart offers, in nights.
public enum RecoveryFactorRange: Int, Sendable, CaseIterable, Hashable, Codable {
    case fortnight = 14
    case month = 30
    case quarter = 90

    public var nights: Int { rawValue }
}

/// One night of a factor's series.
public struct RecoveryFactorPoint: Sendable, Equatable, Codable {
    /// With more nights than `RecoveryHistoryModel.maximumChartPoints`, the
    /// last night of the run this point stands for.
    public let night: SleepNightKey
    /// The night's value: minutes asleep, bedtime (minutes after noon), HRV
    /// ms, resting bpm. Nil where the night has no value. A mean when the
    /// point stands for several nights.
    public let value: Double?
    /// The factor's 0...100 score that morning; nil where it had none.
    public let score: Int?

    public init(night: SleepNightKey, value: Double?, score: Int?) {
        self.night = night
        self.value = value
        self.score = score
    }
}

/// A factor over 14, 30 or 90 nights against its normal range.
public struct RecoveryFactorSeries: Sendable, Equatable, Codable {
    public let kind: RecoveryFactorKind
    public let range: RecoveryFactorRange
    /// Oldest first; calendar-aligned unless the run was downsampled.
    public let points: [RecoveryFactorPoint]
    /// Your usual and the floored spread the normal range is drawn with,
    /// as of the newest night; nil under 5 nights of that factor.
    public let usual: Double?
    public let standardDeviation: Double?
    /// The newest night's value.
    public let today: Double?
    /// The lowest and highest values in the window.
    public let minimum: Double?
    public let maximum: Double?
    /// More nights than the chart draws: points are means of runs.
    public let isDownsampled: Bool

    public init(
        kind: RecoveryFactorKind, range: RecoveryFactorRange, points: [RecoveryFactorPoint], usual: Double?, standardDeviation: Double?,
        today: Double?, minimum: Double?, maximum: Double?, isDownsampled: Bool
    ) {
        self.kind = kind
        self.range = range
        self.points = points
        self.usual = usual
        self.standardDeviation = standardDeviation
        self.today = today
        self.minimum = minimum
        self.maximum = maximum
        self.isDownsampled = isDownsampled
    }

    /// Your usual ± 1 SD.
    public var normalRange: ClosedRange<Double>? {
        guard let usual, let standardDeviation else { return nil }
        let spread = standardDeviation * RecoveryNormalRange.standardDeviations
        return (usual - spread)...(usual + spread)
    }

    /// Window nights with a value.
    public var nightsRecorded: Int { points.compactMap(\.value).count }
}

public enum RecoveryFactorSeriesBuilder {
    /// The `range.nights` nights ending on `endingAt` (the newest night
    /// in `history` by default) for one factor. Each night's score is the
    /// one it had on its own morning.
    public static func series(
        _ kind: RecoveryFactorKind,
        range: RecoveryFactorRange,
        history: [NightMetrics],
        needMinutes: Double,
        asOf now: Date,
        endingAt night: SleepNightKey? = nil,
        model: RecoveryModel = .current
    ) -> RecoveryFactorSeries {
        let complete = history.filter { $0.wakeTime <= now }
        let byNight = Dictionary(complete.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        guard let end = night ?? complete.map(\.night).max() else {
            return RecoveryFactorSeries(
                kind: kind, range: range, points: [], usual: nil, standardDeviation: nil, today: nil, minimum: nil, maximum: nil, isDownsampled: false)
        }
        let keys = (0..<range.nights).reversed().map { end.adding(days: -$0) }
        let points = keys.map { key -> RecoveryFactorPoint in
            guard let metrics = byNight[key] else { return RecoveryFactorPoint(night: key, value: nil, score: nil) }
            let result = RecoveryEngine.scoreResultAsOfThatMorning(metrics, complete: complete, needMinutes: needMinutes, model: model)
            return RecoveryFactorPoint(night: key, value: value(kind, metrics), score: result?.factor(kind)?.score)
        }
        let values = points.compactMap(\.value)
        let (usual, spread) = normal(kind, baselines: BaselineEngine.baselines(for: end, history: complete))
        let sampled = downsample(points)
        return RecoveryFactorSeries(
            kind: kind, range: range, points: sampled, usual: usual, standardDeviation: spread,
            today: byNight[end].flatMap { value(kind, $0) },
            minimum: values.min(), maximum: values.max(), isDownsampled: sampled.count != points.count
        )
    }

    /// A night's value for a factor; consistency is bedtime.
    static func value(_ kind: RecoveryFactorKind, _ night: NightMetrics) -> Double? {
        switch kind {
        case .sleepDuration: night.asleepMinutes
        case .sleepConsistency: night.bedtimeMinutes
        case .hrv: night.hrv
        case .restingHeartRate: night.restingHeartRate
        }
    }

    /// The baseline's mean and floored spread for a factor.
    static func normal(_ kind: RecoveryFactorKind, baselines: Baselines) -> (usual: Double?, spread: Double?) {
        let baseline: Baseline?
        let floor: Double
        switch kind {
        case .sleepDuration:
            baseline = baselines.sleepDuration
            floor = RecoveryNormalRange.sleepDurationStandardDeviationFloor
        case .sleepConsistency:
            baseline = baselines.bedtime
            floor = RecoveryNormalRange.timingStandardDeviationFloor
        case .hrv:
            baseline = baselines.hrv
            floor = RecoveryModelV2.hrvStandardDeviationFloor
        case .restingHeartRate:
            baseline = baselines.restingHeartRate
            floor = RecoveryModelV2.restingStandardDeviationFloor
        }
        guard let baseline else { return (nil, nil) }
        return (baseline.value, max(baseline.standardDeviation, floor))
    }

    /// At most `maximumChartPoints` points: runs of equal length (the
    /// newest run may be shorter) become their mean, dated by their last
    /// night. A series that already fits is returned as it is.
    public static func downsample(_ points: [RecoveryFactorPoint], maximum: Int = RecoveryHistoryModel.maximumChartPoints) -> [RecoveryFactorPoint] {
        guard points.count > maximum, maximum > 0 else { return points }
        let size = Int((Double(points.count) / Double(maximum)).rounded(.up))
        return stride(from: 0, to: points.count, by: size).map { start in
            let run = Array(points[start..<min(start + size, points.count)])
            let values = run.compactMap(\.value)
            let scores = run.compactMap(\.score)
            return RecoveryFactorPoint(
                night: run[run.count - 1].night,
                value: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                score: scores.isEmpty ? nil : Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
            )
        }
    }
}
