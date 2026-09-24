import Foundation
import SleepKit

public enum RecoveryFactorKind: String, Sendable, CaseIterable, Hashable {
    case sleepDuration
    case sleepConsistency
    case hrv
    case restingHeartRate
}

/// Version 1 of the recovery model. Every weight and scoring constant
/// lives here, so changing the model means a new version, never an edit
/// scattered through the engine.
public enum RecoveryModelV1 {
    public static let version = "recovery-v1"

    public static let weights: [RecoveryFactorKind: Double] = [
        .sleepDuration: 35,
        .sleepConsistency: 20,
        .hrv: 25,
        .restingHeartRate: 20,
    ]

    /// Sleep duration: 100 at or above need; loses `durationPointsPerShortfall`
    /// points per 100% short of it (75% of need = 50, 50% = 0).
    public static let durationPointsPerShortfall: Double = 200
    /// Consistency: 100 on baseline timing, 0 at this mean deviation
    /// (minutes) of bedtime and wake time from their baselines.
    public static let consistencyZeroAtMinutes: Double = 120
    /// HRV: 50 on baseline, ±`hrvPointsPerRatio` per 100% above/below
    /// (+20% = 100, −20% = 0).
    public static let hrvPointsPerRatio: Double = 250
    /// Resting HR: 50 on baseline, −`restingPointsPerBPM` per bpm above
    /// (−5 bpm = 100, +5 bpm = 0).
    public static let restingPointsPerBPM: Double = 10

    /// No score is given unless history holds at least this many nights.
    public static let learningNights = 5
    /// "Last night" must have ended within this long of now.
    public static let lastNightWindow: TimeInterval = 24 * 3600
    /// Confidence: high needs this many nights in the baseline window.
    public static let highConfidenceNights = 14
    /// Confidence: moderate with at least this many nights in the window.
    public static let moderateConfidenceNights = 7
    /// Confidence: moderate with at least this many factors.
    public static let moderateConfidenceFactors = 3
    /// Today's score counts as above or below the recent baseline at this
    /// many points or more.
    public static let trendThreshold = 3
}

public enum RecoveryConfidence: String, Sendable, Comparable, CaseIterable {
    case low
    case moderate
    case high

    public static func < (lhs: RecoveryConfidence, rhs: RecoveryConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }
}

public struct RecoveryFactor: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    /// 0...100.
    public let score: Int
    /// This factor's share of the score after renormalization (0...1).
    public let weight: Double
    /// Last night's value: minutes asleep; mean minutes bedtime and wake
    /// were off their baselines; HRV ms; resting bpm.
    public let value: Double
    /// The baseline `value` is compared with; nil for sleep duration
    /// before a baseline exists, and for consistency (which is already a
    /// distance from baseline).
    public let baseline: Double?
    /// `value − baseline` in the factor's unit. For consistency, the
    /// signed bedtime shift in minutes (later is positive).
    public let delta: Double?

    public init(kind: RecoveryFactorKind, score: Int, weight: Double, value: Double, baseline: Double?, delta: Double?) {
        self.kind = kind
        self.score = score
        self.weight = weight
        self.value = value
        self.baseline = baseline
        self.delta = delta
    }
}

/// Why a factor isn't in today's score.
public enum RecoveryFactorGap: String, Sendable, Equatable {
    /// No value last night and none in the baseline window: the person's
    /// sources don't provide it.
    case unavailable
    /// No value last night, though earlier nights have one.
    case notRecorded
    /// A value last night, but fewer than 5 nights to compare it with.
    case buildingBaseline
}

public enum RecoveryTrend: String, Sendable, Equatable {
    case above
    case inLine
    case below
    /// Fewer than 5 scored nights to compare with.
    case unknown
}

/// Today's score against the person's recent recovery: the mean score of
/// the nights in the 14-night window, each scored the same way.
public struct RecoveryComparison: Sendable, Equatable {
    /// Mean recovery score of the window's nights; nil under 5 nights.
    public let baseline: Double?
    /// Scored nights behind `baseline`.
    public let nights: Int
    /// Today's score minus `baseline`, rounded.
    public let delta: Int?

    public init(baseline: Double?, nights: Int, delta: Int?) {
        self.baseline = baseline
        self.nights = nights
        self.delta = delta
    }

    public static let unavailable = RecoveryComparison(baseline: nil, nights: 0, delta: nil)

    /// Above at +3 or more, below at −3 or less, in line otherwise.
    public var trend: RecoveryTrend {
        guard let delta else { return .unknown }
        if delta >= RecoveryModelV1.trendThreshold { return .above }
        if delta <= -RecoveryModelV1.trendThreshold { return .below }
        return .inLine
    }

    /// The one sentence Home shows under the ring.
    public var sentence: String {
        switch trend {
        case .above: "Above your recent baseline."
        case .inLine: "In line with your recent baseline."
        case .below: "Below your recent baseline."
        case .unknown: "Not enough nights yet to compare with your baseline."
        }
    }
}

public struct RecoveryResult: Sendable, Equatable {
    public let night: SleepNightKey
    /// 0...100.
    public let score: Int
    public let factors: [RecoveryFactor]
    public let confidence: RecoveryConfidence
    /// Nights with sleep in the 14-night baseline window (0...14).
    public let baselineNights: Int
    public let modelVersion: String
    /// The baselines last night was judged against.
    public let baselines: Baselines
    /// Every factor left out of the score, and why.
    public let missingFactors: [RecoveryFactorKind: RecoveryFactorGap]
    public let comparison: RecoveryComparison

    public init(
        night: SleepNightKey,
        score: Int,
        factors: [RecoveryFactor],
        confidence: RecoveryConfidence,
        baselineNights: Int,
        modelVersion: String,
        baselines: Baselines = .none,
        missingFactors: [RecoveryFactorKind: RecoveryFactorGap] = [:],
        comparison: RecoveryComparison = .unavailable
    ) {
        self.night = night
        self.score = score
        self.factors = factors
        self.confidence = confidence
        self.baselineNights = baselineNights
        self.modelVersion = modelVersion
        self.baselines = baselines
        self.missingFactors = missingFactors
        self.comparison = comparison
    }

    public var factorsUsed: [RecoveryFactorKind] { factors.map(\.kind) }

    func with(comparison: RecoveryComparison) -> RecoveryResult {
        RecoveryResult(
            night: night, score: score, factors: factors, confidence: confidence, baselineNights: baselineNights,
            modelVersion: modelVersion, baselines: baselines, missingFactors: missingFactors, comparison: comparison
        )
    }

    public func factor(_ kind: RecoveryFactorKind) -> RecoveryFactor? {
        factors.first { $0.kind == kind }
    }
}

public enum RecoveryState: Sendable, Equatable {
    /// Fewer than `RecoveryModelV1.learningNights` nights of history.
    case learning(nightsSoFar: Int)
    /// Enough history, but no main sleep ended in the last 24 hours.
    case noSleepLastNight
    case scored(RecoveryResult)
}
