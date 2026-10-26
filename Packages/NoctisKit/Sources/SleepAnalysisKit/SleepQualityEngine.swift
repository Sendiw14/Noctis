import Foundation
import RecoveryKit
import SleepKit

/// Why a factor isn't in a night's quality score.
public enum SleepQualityGap: String, Sendable, Equatable, Codable {
    /// The source doesn't record what the factor needs (no stages, no
    /// awake or in-bed records, no sleep need set).
    case unavailable
    /// Fewer than 5 nights to compare with.
    case buildingBaseline
}

public struct SleepQualityFactor: Sendable, Equatable, Codable {
    public let kind: SleepQualityFactorKind
    /// 0...100.
    public let score: Int
    /// This factor's share of the score after renormalization (0...1).
    public let weight: Double

    public init(kind: SleepQualityFactorKind, score: Int, weight: Double) {
        self.kind = kind
        self.score = score
        self.weight = weight
    }
}

/// One stage's share of a night against the range it is judged by.
public struct StageBalanceRow: Sendable, Equatable, Codable {
    public enum Stage: String, Sendable, Codable, CaseIterable {
        case deep, core, rem
    }

    public let stage: Stage
    /// Share of the time asleep, 0...1.
    public let share: Double
    /// The range judged against, as shares: your usual ± 1 SD, or the
    /// typical range.
    public let low: Double
    public let high: Double
    /// 0...100.
    public let score: Double

    public init(stage: Stage, share: Double, low: Double, high: Double, score: Double) {
        self.stage = stage
        self.share = share
        self.low = low
        self.high = high
        self.score = score
    }

    public var isWithinRange: Bool { share >= low && share <= high }
    /// Halfway through the range.
    public var usual: Double { (low + high) / 2 }
}

/// How the three sleep stages compared with the range they were judged by.
public struct StageBalance: Sendable, Equatable, Codable {
    public enum Basis: Sendable, Equatable, Codable {
        /// Against the person's own shares over this many nights.
        case personal(nights: Int)
        /// Against typical adult ranges ("typical range").
        case typical
    }

    public let basis: Basis
    public let rows: [StageBalanceRow]
    /// The mean of the rows' scores, 0...100.
    public let score: Double

    public init(basis: Basis, rows: [StageBalanceRow], score: Double) {
        self.basis = basis
        self.rows = rows
        self.score = score
    }

    public func row(_ stage: StageBalanceRow.Stage) -> StageBalanceRow? {
        rows.first { $0.stage == stage }
    }
}

/// What moved a night's quality most, for the one-sentence "What changed?":
/// of the measures outside your normal range (your usual ± 1 SD), the one
/// with the largest weighted deviation. The same structure as Recovery's
/// `RecoveryContributor`.
public struct SleepQualityContributor: Sendable, Equatable, Codable {
    public enum Measure: String, Sendable, Equatable, Codable {
        case duration
        case bedtime
        case awakeTime
        case deepShare
        case remShare
    }

    public let factor: SleepQualityFactorKind
    public let measure: Measure
    /// Last night minus usual, in the measure's unit: minutes for
    /// duration, bedtime and awake time; a share (0...1) for a stage.
    public let difference: Double
    /// `difference` in floored standard deviations.
    public let standardDeviations: Double
    /// The factor's weight × |standardDeviations|.
    public let weightedDeviation: Double

    public init(factor: SleepQualityFactorKind, measure: Measure, difference: Double, standardDeviations: Double, weightedDeviation: Double) {
        self.factor = factor
        self.measure = measure
        self.difference = difference
        self.standardDeviations = standardDeviations
        self.weightedDeviation = weightedDeviation
    }

    /// By value: more, later or larger (above) or less, earlier or smaller.
    public var isAbove: Bool { difference > 0 }
}

public struct SleepQualityResult: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    /// 0...100.
    public let score: Int
    public let factors: [SleepQualityFactor]
    public let confidence: RecoveryConfidence
    /// Nights with sleep in the 14-night window before this night.
    public let baselineNights: Int
    public let modelVersion: String
    public let missingFactors: [SleepQualityFactorKind: SleepQualityGap]
    /// Nil without stage data (the factor is dropped).
    public let stageBalance: StageBalance?
    public let topContributor: SleepQualityContributor?
    /// Your usual score: the mean of the window's scores, each scored as
    /// its own morning. Nil under 5 scored nights.
    public let usual: Double?

    public init(
        night: SleepNightKey, score: Int, factors: [SleepQualityFactor], confidence: RecoveryConfidence, baselineNights: Int,
        modelVersion: String, missingFactors: [SleepQualityFactorKind: SleepQualityGap], stageBalance: StageBalance?,
        topContributor: SleepQualityContributor?, usual: Double? = nil
    ) {
        self.night = night
        self.score = score
        self.factors = factors
        self.confidence = confidence
        self.baselineNights = baselineNights
        self.modelVersion = modelVersion
        self.missingFactors = missingFactors
        self.stageBalance = stageBalance
        self.topContributor = topContributor
        self.usual = usual
    }

    public var factorsUsed: [SleepQualityFactorKind] { factors.map(\.kind) }

    /// Whether any factor could be scored: without one there is no score
    /// to show (the number is 0 only because there was nothing to blend).
    public var isScored: Bool { !factors.isEmpty }

    public func factor(_ kind: SleepQualityFactorKind) -> SleepQualityFactor? {
        factors.first { $0.kind == kind }
    }

    func with(usual: Double?) -> SleepQualityResult {
        SleepQualityResult(
            night: night, score: score, factors: factors, confidence: confidence, baselineNights: baselineNights,
            modelVersion: modelVersion, missingFactors: missingFactors, stageBalance: stageBalance,
            topContributor: topContributor, usual: usual
        )
    }
}

/// Scores a night 0-100 from how long, how unbroken, how regular and how
/// balanced the sleep was (`SleepQualityModelV1`). Factors a night can't
/// support are dropped and the rest renormalized; nothing is invented.
public enum SleepQualityEngine {
    public typealias Model = SleepQualityModelV1

    /// `night` scored as its own morning: against the 14 nights before it
    /// in `history` (which may include `night` itself; it is never part of
    /// its own baseline).
    public static func score(night: SleepSession, history: [SleepSession], needMinutes: Double) -> SleepQualityResult {
        let window = self.window(for: night.night, in: history)
        return score(night: night, window: window, needMinutes: needMinutes)
    }

    /// Every main night in `history` scored as its own morning, oldest
    /// first, each with `usual` filled in from the window's scores.
    public static func series(history: [SleepSession], needMinutes: Double) -> [SleepQualityResult] {
        let ordered = history.filter { $0.kind == .main }.sorted { $0.night < $1.night }
        let raw = ordered.map { score(night: $0, history: ordered, needMinutes: needMinutes) }
        let byNight = Dictionary(raw.map { ($0.night, $0.score) }, uniquingKeysWith: { first, _ in first })
        return raw.map { result in
            let first = result.night.adding(days: -BaselineEngine.windowNights)
            let scores = byNight.filter { $0.key >= first && $0.key < result.night }.map { Double($0.value) }
            return result.with(usual: BaselineEngine.baseline(scores)?.value)
        }
    }

    // MARK: - One night

    static func window(for night: SleepNightKey, in history: [SleepSession]) -> [SleepSession] {
        let first = night.adding(days: -BaselineEngine.windowNights)
        return history.filter { $0.kind == .main && $0.night >= first && $0.night < night }
    }

    static func score(night: SleepSession, window: [SleepSession], needMinutes: Double) -> SleepQualityResult {
        let metrics = SleepMetricsEngine.metrics(for: night)
        let windowMetrics = window.map(SleepMetricsEngine.metrics(for:))
        let bedtimeBaseline = BaselineEngine.baseline(windowMetrics.map(\.bedtimeMinutes))

        var raw: [(kind: SleepQualityFactorKind, score: Double)] = []
        var gaps: [SleepQualityFactorKind: SleepQualityGap] = [:]

        // Duration.
        if needMinutes > 0 {
            let ratio = metrics.asleepMinutes / needMinutes
            let value = ratio >= 1 ? 100 : 100 - (1 - ratio) * Model.durationPointsPerShortfall
            raw.append((.duration, clamp(value)))
        } else {
            gaps[.duration] = .unavailable
        }

        // Continuity: time awake after sleep onset and awakenings.
        if let waso = metrics.awakeAfterOnsetMinutes {
            let wasoScore = clamp(100 - max(waso - Model.wasoFreeMinutes, 0) * 100 / (Model.wasoZeroAtMinutes - Model.wasoFreeMinutes))
            let awakeningScore = clamp(
                100 - Double(max(metrics.awakenings - Model.awakeningsFree, 0)) * 100 / Double(Model.awakeningsZeroAt - Model.awakeningsFree)
            )
            raw.append((.continuity, (wasoScore + awakeningScore) / 2))
        } else {
            gaps[.continuity] = .unavailable
        }

        // Consistency: how far bedtime is from your baseline.
        if let baseline = bedtimeBaseline {
            let deviation = abs(metrics.bedtimeMinutes - baseline.value)
            raw.append((.consistency, clamp(100 * (1 - deviation / Model.consistencyZeroAtMinutes))))
        } else {
            gaps[.consistency] = .buildingBaseline
        }

        // Stage balance.
        let balance = stageBalance(metrics, windowMetrics: windowMetrics)
        if let balance {
            raw.append((.stages, balance.score))
        } else {
            gaps[.stages] = .unavailable
        }

        let totalWeight = raw.reduce(0) { $0 + (Model.weights[$1.kind] ?? 0) }
        let factors = raw.map { factor in
            SleepQualityFactor(
                kind: factor.kind,
                score: Int(factor.score.rounded()),
                weight: totalWeight > 0 ? (Model.weights[factor.kind] ?? 0) / totalWeight : 0
            )
        }
        let weighted = raw.reduce(0) { $0 + $1.score * (Model.weights[$1.kind] ?? 0) }
        let overall = totalWeight > 0 ? weighted / totalWeight : 0

        return SleepQualityResult(
            night: night.night,
            score: Int(overall.rounded()),
            factors: factors,
            confidence: RecoveryEngine.confidence(factorCount: factors.count, baselineNights: window.count),
            baselineNights: window.count,
            modelVersion: Model.version,
            missingFactors: gaps,
            stageBalance: balance,
            topContributor: contributor(metrics, factors: factors, windowMetrics: windowMetrics, balance: balance)
        )
    }

    // MARK: - Stage balance

    static func stageBalance(_ metrics: SleepMetrics, windowMetrics: [SleepMetrics]) -> StageBalance? {
        guard let stages = metrics.stages, stages.asleep >= Model.minimumStageMinutes, let shares = stages.asleepShares else { return nil }
        let windowShares = windowMetrics.compactMap { $0.stages?.asleepShares }
        let today: [(StageBalanceRow.Stage, Double)] = [(.deep, shares.deep), (.core, shares.core), (.rem, shares.rem)]

        let basis: StageBalance.Basis
        var rows: [StageBalanceRow] = []
        if windowShares.count >= Model.personalStageNights {
            basis = .personal(nights: windowShares.count)
            for (stage, share) in today {
                let values = windowShares.map { $0[keyPath: keyPath(stage)] }
                let mean = values.reduce(0, +) / Double(values.count)
                let sd = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)).squareRoot()
                let spread = max(sd, Model.personalShareFloor)
                let low = mean - spread
                let high = mean + spread
                let outside = max(low - share, share - high, 0)
                rows.append(StageBalanceRow(stage: stage, share: share, low: low, high: high, score: clamp(100 - outside / spread * Model.personalPointsPerSD)))
            }
        } else {
            basis = .typical
            for (stage, share) in today {
                let range = typicalRange(stage)
                let outside = max(range.lowerBound - share, share - range.upperBound, 0)
                rows.append(
                    StageBalanceRow(
                        stage: stage, share: share, low: range.lowerBound, high: range.upperBound,
                        score: clamp(100 * (1 - outside / Model.typicalToleranceShare))
                    ))
            }
        }
        let score = rows.reduce(0) { $0 + $1.score } / Double(rows.count)
        return StageBalance(basis: basis, rows: rows, score: score)
    }

    public static func typicalRange(_ stage: StageBalanceRow.Stage) -> ClosedRange<Double> {
        switch stage {
        case .deep: Model.typicalDeep
        case .core: Model.typicalCore
        case .rem: Model.typicalREM
        }
    }

    private static func keyPath(_ stage: StageBalanceRow.Stage) -> KeyPath<(deep: Double, core: Double, rem: Double), Double> {
        switch stage {
        case .deep: \.deep
        case .core: \.core
        case .rem: \.rem
        }
    }

    // MARK: - What changed

    static func contributor(
        _ metrics: SleepMetrics, factors: [SleepQualityFactor], windowMetrics: [SleepMetrics], balance: StageBalance?
    ) -> SleepQualityContributor? {
        func weight(_ kind: SleepQualityFactorKind) -> Double { factors.first { $0.kind == kind }?.weight ?? 0 }
        func measure(
            _ factor: SleepQualityFactorKind, _ measure: SleepQualityContributor.Measure, value: Double?, values: [Double], floor: Double
        ) -> SleepQualityContributor? {
            guard let value, weight(factor) > 0, let baseline = BaselineEngine.baseline(values) else { return nil }
            let z = RecoveryNormalRange.standardDeviations(value, from: baseline, floor: floor)
            return SleepQualityContributor(
                factor: factor, measure: measure, difference: value - baseline.value,
                standardDeviations: z, weightedDeviation: weight(factor) * abs(z)
            )
        }

        var candidates: [SleepQualityContributor?] = [
            measure(
                .duration, .duration, value: metrics.asleepMinutes, values: windowMetrics.map(\.asleepMinutes),
                floor: RecoveryNormalRange.sleepDurationStandardDeviationFloor),
            measure(
                .consistency, .bedtime, value: metrics.bedtimeMinutes, values: windowMetrics.map(\.bedtimeMinutes),
                floor: RecoveryNormalRange.timingStandardDeviationFloor),
            measure(
                .continuity, .awakeTime, value: metrics.awakeAfterOnsetMinutes, values: windowMetrics.compactMap(\.awakeAfterOnsetMinutes),
                floor: Model.wasoStandardDeviationFloor),
        ]
        // Stage shares only against your own: a typical range isn't a usual.
        if case .personal? = balance?.basis, let shares = metrics.stages?.asleepShares {
            let history = windowMetrics.compactMap { $0.stages?.asleepShares }
            candidates.append(measure(.stages, .deepShare, value: shares.deep, values: history.map(\.deep), floor: Model.personalShareFloor))
            candidates.append(measure(.stages, .remShare, value: shares.rem, values: history.map(\.rem), floor: Model.personalShareFloor))
        }
        // `reduce` keeps the first of equals, so ties go to the measure listed first.
        return
            candidates
            .compactMap { $0 }
            .filter { !RecoveryNormalRange.contains(standardDeviations: $0.standardDeviations) }
            .reduce(nil) { best, next in
                guard let best else { return next }
                return next.weightedDeviation > best.weightedDeviation ? next : best
            }
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}
