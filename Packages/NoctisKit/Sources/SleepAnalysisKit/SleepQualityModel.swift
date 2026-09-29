import Foundation

/// Version 1 of the sleep quality model. Every weight and constant lives
/// here, so changing the model means a new version, never an edit
/// scattered through the engine.
///
/// It is a description of how a night compared with your need, your own
/// pattern and typical sleep: not a medical measurement, and it makes no
/// claim about your health.
public enum SleepQualityModelV1 {
    public static let version = "sleep-quality-v1"

    /// Points each factor carries before dropped factors are removed and
    /// the rest renormalized.
    public static let weights: [SleepQualityFactorKind: Double] = [
        .duration: 35,
        .continuity: 25,
        .consistency: 20,
        .stages: 20,
    ]

    // MARK: Duration

    /// 100 at or above need; loses this many points per 100% short of it
    /// (75% of need = 50, 50% = 0), the curve Recovery uses.
    public static let durationPointsPerShortfall: Double = 200

    // MARK: Continuity

    /// Time awake after falling asleep costs nothing up to this many
    /// minutes, then loses points until it reaches zero at `wasoZeroAtMinutes`.
    public static let wasoFreeMinutes: Double = 10
    public static let wasoZeroAtMinutes: Double = 60
    /// Awakenings cost nothing up to this many, then reach zero at
    /// `awakeningsZeroAt`.
    public static let awakeningsFree = 2
    public static let awakeningsZeroAt = 10

    // MARK: Consistency

    /// Bedtime on your baseline scores 100, and 0 this many minutes off it.
    public static let consistencyZeroAtMinutes: Double = 120

    // MARK: Stage balance

    /// With this many nights of stage data in the 14-night window, stage
    /// shares are judged against your own; below it, against typical ranges.
    public static let personalStageNights = 7
    /// Typical adult ranges, as shares of time asleep. Approximate
    /// reference values, labelled "typical range" wherever they appear.
    public static let typicalDeep: ClosedRange<Double> = 0.13...0.23
    public static let typicalCore: ClosedRange<Double> = 0.45...0.55
    public static let typicalREM: ClosedRange<Double> = 0.20...0.25
    /// Against typical ranges: a stage this far outside its range (as a
    /// share of sleep) scores 0.
    public static let typicalToleranceShare: Double = 0.10
    /// Against your own shares: your usual ± 1 SD is the range, the SD
    /// floored here; each SD outside it costs `personalPointsPerSD`.
    public static let personalShareFloor: Double = 0.03
    public static let personalPointsPerSD: Double = 50
    /// A night with less time asleep in stages than this has no stage
    /// balance (shares of a few minutes mean nothing).
    public static let minimumStageMinutes: Double = 60

    // MARK: "What changed?"

    /// Floor for the spread of time awake after sleep onset (minutes),
    /// so a very steady window can't make a small change look unusual.
    public static let wasoStandardDeviationFloor: Double = 10
}

public enum SleepQualityFactorKind: String, Sendable, CaseIterable, Hashable, Codable {
    case duration
    case continuity
    case consistency
    case stages
}
