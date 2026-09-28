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

/// Version 2: HRV and resting heart rate are scored against the person's
/// own night-to-night variation instead of raw differences. Everything
/// else (weights, the sleep duration and consistency curves, learning and
/// last-night rules) is V1's. Confidence is stricter: moderate needs 3+
/// factors AND 7+ nights.
public enum RecoveryModelV2 {
    public static let version = "recovery-v2"
    public static let weights = RecoveryModelV1.weights
    public static let learningNights = RecoveryModelV1.learningNights

    /// A factor exactly on its baseline scores this.
    public static let variationCenter: Double = 75
    /// Points per standard deviation away from baseline, in the good
    /// direction (higher HRV, lower resting heart rate).
    public static let pointsPerStandardDeviation: Double = 15
    /// Standard deviation floors, so a very steady window can't turn a
    /// tiny change into a large swing.
    public static let hrvStandardDeviationFloor: Double = 3
    public static let restingStandardDeviationFloor: Double = 1
}

/// "Your normal range": your usual ± 1 standard deviation of your own last
/// 14 nights. One definition for the detail sentences, Home's "why" line
/// and the sparklines. Spreads are floored so a very steady window can't
/// make a tiny change look unusual.
public enum RecoveryNormalRange {
    public static let standardDeviations: Double = 1
    /// Floors for the spreads the models don't already floor.
    public static let sleepDurationStandardDeviationFloor: Double = 15
    public static let timingStandardDeviationFloor: Double = 15

    /// `value` against `baseline`, in floored standard deviations (by value:
    /// positive = more, later, higher).
    public static func standardDeviations(_ value: Double, from baseline: Baseline, floor: Double) -> Double {
        (value - baseline.value) / max(baseline.standardDeviation, floor)
    }

    public static func contains(standardDeviations z: Double) -> Bool {
        abs(z) <= standardDeviations
    }
}

/// Version 3: V2 plus one rule. When HRV is 1.5 SD or more below its
/// baseline AND resting heart rate is 1.5 SD or more above its baseline on
/// the same morning, recovery is capped at 50, however well you slept.
public enum RecoveryModelV3 {
    public static let version = "recovery-v3"
    public static let weights = RecoveryModelV2.weights
    /// Both heart signals this many SDs on the wrong side trigger the cap.
    public static let heartCapStandardDeviations: Double = 1.5
    public static let heartCapScore = 50
}

/// The recovery models the engine can run. `current` is what the app shows.
public enum RecoveryModel: String, Sendable, CaseIterable {
    case v1 = "recovery-v1"
    case v2 = "recovery-v2"
    case v3 = "recovery-v3"

    public static let current: RecoveryModel = .v3

    public var version: String { rawValue }

    public var weights: [RecoveryFactorKind: Double] {
        switch self {
        case .v1: RecoveryModelV1.weights
        case .v2: RecoveryModelV2.weights
        case .v3: RecoveryModelV3.weights
        }
    }

    /// V2 and V3 score HRV and resting heart rate against variation.
    var scoresVariation: Bool { self != .v1 }
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
    /// V2, HRV and resting heart rate only: standard deviations from
    /// baseline in the good direction (positive = higher HRV or lower
    /// resting heart rate).
    public let standardScore: Double?

    public init(kind: RecoveryFactorKind, score: Int, weight: Double, value: Double, baseline: Double?, delta: Double?, standardScore: Double? = nil) {
        self.kind = kind
        self.score = score
        self.weight = weight
        self.value = value
        self.baseline = baseline
        self.delta = delta
        self.standardScore = standardScore
    }

    /// Where the value sits against the person's normal range (V2 only).
    public var range: RecoveryRange? {
        guard let standardScore, let delta else { return nil }
        if RecoveryNormalRange.contains(standardDeviations: standardScore) { return .within }
        return delta > 0 ? .above : .below
    }
}

/// A value's place against the person's own variation: within ±1 SD of
/// baseline (`RecoveryNormalRange`), or above or below it (by value, not
/// by goodness).
public enum RecoveryRange: String, Sendable, Equatable {
    case within
    case above
    case below
}

/// What moved today's recovery most: of the factors outside their normal
/// range, the one with the largest weighted deviation (its share of the
/// score × how many standard deviations it is from usual). Nil when every
/// factor is within its normal range.
public struct RecoveryContributor: Sendable, Equatable {
    /// What was measured. Consistency reports whichever of bedtime and
    /// wake time was further from usual.
    public enum Measure: String, Sendable, Equatable {
        case sleepDuration
        case hrv
        case restingHeartRate
        case bedtime
        case wakeTime
    }

    public let factor: RecoveryFactorKind
    public let measure: Measure
    /// Last night minus usual, in the measure's unit (minutes, ms, bpm):
    /// positive is longer, higher or later.
    public let difference: Double
    /// `difference` in floored standard deviations.
    public let standardDeviations: Double
    /// The factor's weight × |standardDeviations|.
    public let weightedDeviation: Double

    public init(factor: RecoveryFactorKind, measure: Measure, difference: Double, standardDeviations: Double, weightedDeviation: Double) {
        self.factor = factor
        self.measure = measure
        self.difference = difference
        self.standardDeviations = standardDeviations
        self.weightedDeviation = weightedDeviation
    }

    /// By value: above (longer, higher, later) or below.
    public var direction: RecoveryRange { difference > 0 ? .above : .below }
}

/// One factor's last 14 nights against its normal range, for a sparkline.
/// Consistency is shown as bedtime (minutes after noon).
public struct RecoveryFactorHistory: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    /// The 14 calendar nights before last night, oldest first; nil where a
    /// night has no value.
    public let values: [Double?]
    /// Last night's value.
    public let today: Double
    public let usual: Double
    /// The floored spread the normal range is drawn with.
    public let standardDeviation: Double

    public init(kind: RecoveryFactorKind, values: [Double?], today: Double, usual: Double, standardDeviation: Double) {
        self.kind = kind
        self.values = values
        self.today = today
        self.usual = usual
        self.standardDeviation = standardDeviation
    }

    public var normalRange: ClosedRange<Double> {
        let spread = standardDeviation * RecoveryNormalRange.standardDeviations
        return (usual - spread)...(usual + spread)
    }

    /// Window nights with a value.
    public var nightsRecorded: Int { values.compactMap { $0 }.count }
    /// Window nights inside the normal range.
    public var nightsWithin: Int { values.compactMap { $0 }.filter { normalRange.contains($0) }.count }
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
    /// V3: both heart signals were far enough off to cap the score at 50.
    public let heartCapApplied: Bool
    /// The factor furthest outside its normal range; nil when all are within.
    public let topContributor: RecoveryContributor?
    /// Each scored factor's 14 nights against its normal range, in factor
    /// order; a factor without a baseline has none.
    public let histories: [RecoveryFactorHistory]

    public init(
        night: SleepNightKey,
        score: Int,
        factors: [RecoveryFactor],
        confidence: RecoveryConfidence,
        baselineNights: Int,
        modelVersion: String,
        baselines: Baselines = .none,
        missingFactors: [RecoveryFactorKind: RecoveryFactorGap] = [:],
        comparison: RecoveryComparison = .unavailable,
        heartCapApplied: Bool = false,
        topContributor: RecoveryContributor? = nil,
        histories: [RecoveryFactorHistory] = []
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
        self.heartCapApplied = heartCapApplied
        self.topContributor = topContributor
        self.histories = histories
    }

    public var factorsUsed: [RecoveryFactorKind] { factors.map(\.kind) }

    func with(comparison: RecoveryComparison) -> RecoveryResult {
        RecoveryResult(
            night: night, score: score, factors: factors, confidence: confidence, baselineNights: baselineNights,
            modelVersion: modelVersion, baselines: baselines, missingFactors: missingFactors, comparison: comparison,
            heartCapApplied: heartCapApplied, topContributor: topContributor, histories: histories
        )
    }

    func with(histories: [RecoveryFactorHistory]) -> RecoveryResult {
        RecoveryResult(
            night: night, score: score, factors: factors, confidence: confidence, baselineNights: baselineNights,
            modelVersion: modelVersion, baselines: baselines, missingFactors: missingFactors, comparison: comparison,
            heartCapApplied: heartCapApplied, topContributor: topContributor, histories: histories
        )
    }

    public func factor(_ kind: RecoveryFactorKind) -> RecoveryFactor? {
        factors.first { $0.kind == kind }
    }

    public func history(_ kind: RecoveryFactorKind) -> RecoveryFactorHistory? {
        histories.first { $0.kind == kind }
    }
}

public enum RecoveryState: Sendable, Equatable {
    /// Fewer than `RecoveryModelV1.learningNights` nights of history.
    case learning(nightsSoFar: Int)
    /// Enough history, but no main sleep ended in the last 24 hours.
    case noSleepLastNight
    case scored(RecoveryResult)
}
