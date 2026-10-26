import Foundation
import RecoveryKit
import SleepAnalysisKit
import SleepKit

/// The thresholds behind every insight rule: one place, so changing what
/// fires means editing here and its tests.
public enum InsightModelV2 {
    public static let version = "insights-v2"

    // 1-2: last night against the baseline (v1's).
    public static let shiftMinutes = InsightEngine.shiftThresholdMinutes
    // 3: a steady bedtime.
    public static let streakMinutes = InsightEngine.streakToleranceMinutes
    public static let streakNights = InsightEngine.minimumStreakNights
    /// The nights the streak's dots draw.
    public static let streakDots = 14

    // 4: the earlier-bedtime pattern.
    public static let patternWindowNights = 60
    /// Nights this far from the median bedtime are early or late.
    public static let patternGroupMinutes: Double = 30
    /// Nights with an outcome needed in each group.
    public static let patternMinimumPerGroup = 5
    public static let patternMinimumDifference: Double = 6
    public static let patternMinimumEffect: Double = 0.5
    /// High confidence needs this many per group and this effect.
    public static let patternHighPerGroup = 10
    public static let patternHighEffect: Double = 0.8

    // 5: recovery direction.
    public static let directionConsecutiveDays = 5
    public static let directionWindow = RecoveryHistoryRange.week

    // 6: a heart signal outside its normal range.
    public static let heartConsecutiveNights = 3

    // 7: a change in bedtime spread.
    public static let consistencyWindowNights = 14
    public static let consistencyDeltaMinutes: Double = 15

    // 8: balance.
    public static let balanceMinutes: Double = 120

    // 9: weekends.
    public static let weekendWindowNights = 28
    public static let weekendDeltaMinutes: Double = 45
    public static let weekendMinimumWeekendNights = 3
    public static let weekendMinimumWeekdayNights = 5

    // 10: a stage's share.
    public static let stagePoints: Double = 5

    // 11: records.
    public static let recordShortWindow = 30
    public static let recordLongWindow = 90
    /// Nights with a value the window needs before a record counts.
    public static let recordMinimumShort = 14
    public static let recordMinimumLong = 45
    /// Nothing is said until this many nights are recorded: the Insights tab
    /// is still learning (and the first milestone unlocks).
    public static var learningNights: Int { milestones[0] }

    // 12: milestones, shown for a week after they unlock.
    public static let milestones = [7, 14, 30]
    public static let milestoneShownNights = 7
}

/// Insight v2: twelve deterministic rules, each with its evidence, a
/// minimum of data, a threshold and a confidence. Every rule is about the
/// most recent night (which must have ended within 24 hours); nothing fires
/// without the nights it needs. Descriptive only: no rule claims a cause.
public enum InsightEngineV2 {
    /// Every insight the data supports, in rule order. `history` decides only
    /// how novel each one is.
    public static func generate(_ inputs: InsightInputs, history: InsightHistory = InsightHistory()) -> [InsightRecord] {
        guard let last = inputs.lastNight, inputs.complete.count >= InsightModelV2.learningNights else { return [] }
        var records: [InsightRecord] = []
        records += baselineInsights(inputs, last: last)
        records += pattern(inputs, last: last)
        records += recoveryDirection(inputs, last: last)
        records += heartSignals(inputs, last: last)
        records += consistencyChange(inputs, last: last)
        records += balance(inputs, last: last)
        records += weekendShift(inputs, last: last)
        records += stageShares(inputs, last: last)
        records += recordInsights(inputs, last: last)
        records += milestones(inputs, last: last)
        return records.map { $0.with(novelty: InsightRanking.novelty(of: $0.type, on: last.night, history: history)) }
    }

    // MARK: - 1-3: against your baseline

    static func baselineInsights(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        let complete = inputs.complete.map(\.metrics)
        let baselines = BaselineEngine.baselines(for: last.night, history: complete)
        let byNight = Dictionary(inputs.complete.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        return InsightEngine.candidates(lastNight: last.metrics, baselines: baselines, history: complete).map { insight in
            var evidence = insight.evidence
            if insight.kind == .consistentBedtime {
                // The detail page draws 14 nights, twice what Home's card does.
                let within = (0..<InsightModelV2.streakDots).reversed().map { offset -> Bool? in
                    byNight[last.night.adding(days: -offset)].map { abs($0.bedtimeMinutes - evidence.baseline) <= InsightModelV2.streakMinutes }
                }
                evidence = InsightEvidence(
                    night: evidence.night, value: evidence.value, baseline: evidence.baseline, delta: evidence.delta,
                    baselineNights: evidence.baselineNights, streakNights: evidence.streakNights, recentNights: within
                )
            }
            let nights = evidence.baselineNights
            let confidence: InsightConfidence
            switch insight.kind {
            case .consistentBedtime:
                confidence = (evidence.streakNights ?? 0) >= 7 && nights >= BaselineEngine.windowNights ? .high : .moderate
            default:
                confidence = nights >= RecoveryModelV1.highConfidenceNights ? .high : (nights >= RecoveryModelV1.moderateConfidenceNights ? .moderate : .low)
            }
            return InsightRecord(type: insight.kind.type, generatedAt: inputs.asOf, evidence: .baseline(evidence), confidence: confidence, nightsUsed: nights)
        }
    }

    // MARK: - 4: the earlier-bedtime pattern

    /// The outcome the pattern rule judges a night by: the mean of the
    /// continuity, stage-balance and HRV scores it has. It reads nothing
    /// else, because duration, consistency and the overall quality score are
    /// computed from bedtime and would make the result circular.
    public static func patternOutcome(continuity: Int?, stage: Int?, hrv: Int?) -> Double? {
        let scores = [continuity, stage, hrv].compactMap { $0.map(Double.init) }
        return InsightStats.mean(scores)
    }

    static func outcome(_ night: InsightNightInput) -> Double? {
        patternOutcome(continuity: night.continuityScore, stage: night.stageScore, hrv: night.hrvScore)
    }

    /// The two groups' comparison, before any thresholds.
    public struct PatternResult: Sendable, Equatable {
        public let earlyMean: Double
        public let lateMean: Double
        public let difference: Double
        public let pooledSD: Double
        public let effectSize: Double
    }

    /// Compares two groups of outcomes: nil unless each has the minimum.
    public static func comparePatternGroups(early: [Double], late: [Double]) -> PatternResult? {
        guard early.count >= InsightModelV2.patternMinimumPerGroup, late.count >= InsightModelV2.patternMinimumPerGroup,
            let earlyMean = InsightStats.mean(early), let lateMean = InsightStats.mean(late),
            let pooled = InsightStats.pooledSD(early, late)
        else { return nil }
        let difference = earlyMean - lateMean
        return PatternResult(
            earlyMean: earlyMean, lateMean: lateMean, difference: difference, pooledSD: pooled,
            effectSize: InsightStats.effectSize(difference: difference, pooledSD: pooled)
        )
    }

    /// Whether a comparison is big enough to say anything about.
    public static func patternFires(_ result: PatternResult) -> Bool {
        abs(result.difference) >= InsightModelV2.patternMinimumDifference && abs(result.effectSize) >= InsightModelV2.patternMinimumEffect
    }

    public static func patternConfidence(early: Int, late: Int, effectSize: Double) -> InsightConfidence {
        early >= InsightModelV2.patternHighPerGroup && late >= InsightModelV2.patternHighPerGroup && abs(effectSize) >= InsightModelV2.patternHighEffect
            ? .high : .moderate
    }

    static func pattern(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        let first = last.night.adding(days: -(InsightModelV2.patternWindowNights - 1))
        let window = inputs.complete.filter { $0.night >= first && $0.night <= last.night }
        guard let median = InsightStats.median(window.map(\.bedtimeMinutes)) else { return [] }
        let step = InsightModelV2.patternGroupMinutes
        var early: [Double] = [], late: [Double] = []
        for night in window {
            guard let outcome = outcome(night) else { continue }
            if median - night.bedtimeMinutes >= step { early.append(outcome) }
            if night.bedtimeMinutes - median >= step { late.append(outcome) }
        }
        guard let result = comparePatternGroups(early: early, late: late), patternFires(result) else { return [] }
        let evidence = PatternEvidence(
            night: last.night, windowNights: InsightModelV2.patternWindowNights, medianBedtime: median,
            earlyNights: early.count, lateNights: late.count, earlyValues: early, lateValues: late,
            earlyMean: result.earlyMean, lateMean: result.lateMean, difference: result.difference,
            effectSize: result.effectSize, pooledSD: result.pooledSD
        )
        return [
            InsightRecord(
                type: .earlierBedtimePattern, generatedAt: inputs.asOf, evidence: .pattern(evidence),
                confidence: patternConfidence(early: early.count, late: late.count, effectSize: result.effectSize),
                nightsUsed: early.count + late.count
            )
        ]
    }

    // MARK: - 5: recovery direction

    static func recoveryDirection(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        let scores = inputs.recoveryScores
        guard scores.contains(where: { $0.night == last.night }) else { return [] }
        func trend(_ night: SleepNightKey) -> RecoveryHistoryTrend? {
            RecoveryHistoryEngine.history(scores: scores, range: InsightModelV2.directionWindow, endingAt: night).stats.trend
        }
        guard let latest = trend(last.night), latest.direction != .steady else { return [] }
        var days = 1
        var night = last.night.adding(days: -1)
        let earliest = scores.first?.night ?? last.night
        while night >= earliest, trend(night)?.direction == latest.direction {
            days += 1
            night = night.adding(days: -1)
        }
        guard days >= InsightModelV2.directionConsecutiveDays else { return [] }
        let window = RecoveryHistoryEngine.history(scores: scores, range: InsightModelV2.directionWindow, endingAt: last.night)
        let series = window.days.compactMap(\.score)
        guard let start = series.first, let latestScore = series.last else { return [] }
        let byNight = Dictionary(scores.map { ($0.night, $0.score) }, uniquingKeysWith: { first, _ in first })
        let recent = (0..<14).reversed().map { byNight[last.night.adding(days: -$0)] }
        let evidence = RecoveryDirectionEvidence(
            night: last.night, direction: latest.direction, consecutiveDays: days, pointsPerWeek: latest.pointsPerWeek,
            startScore: start.score, latestScore: latestScore.score, recentScores: recent
        )
        return [
            InsightRecord(
                type: .recoveryDirection, generatedAt: inputs.asOf, evidence: .recoveryDirection(evidence),
                confidence: days >= 7 ? .high : .moderate, nightsUsed: series.count
            )
        ]
    }

    // MARK: - 6: a heart signal outside its normal range

    static func heartSignals(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        let complete = inputs.complete.map(\.metrics)
        let byNight = Dictionary(inputs.complete.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        var records: [InsightRecord] = []
        for signal in [InsightHeartSignal.hrv, .restingHeartRate] {
            func value(_ night: InsightNightInput) -> Double? { signal == .hrv ? night.hrv : night.restingHeartRate }
            func baseline(_ night: SleepNightKey) -> Baseline? {
                let baselines = BaselineEngine.baselines(for: night, history: complete)
                return signal == .hrv ? baselines.hrv : baselines.restingHeartRate
            }
            let floor = signal == .hrv ? RecoveryModelV2.hrvStandardDeviationFloor : RecoveryModelV2.restingStandardDeviationFloor
            /// Outside the range on the wrong side: below for HRV, above for resting heart rate.
            func outside(_ night: InsightNightInput) -> Bool {
                guard let value = value(night), let baseline = baseline(night.night) else { return false }
                let z = RecoveryNormalRange.standardDeviations(value, from: baseline, floor: floor)
                return signal == .hrv ? z < -RecoveryNormalRange.standardDeviations : z > RecoveryNormalRange.standardDeviations
            }
            var count = 0
            var key = last.night
            while let night = byNight[key], outside(night) {
                count += 1
                key = key.adding(days: -1)
            }
            guard count >= InsightModelV2.heartConsecutiveNights, let current = value(last), let base = baseline(last.night) else { continue }
            let spread = max(base.standardDeviation, floor)
            let recent = (0..<BaselineEngine.windowNights).reversed().map { byNight[last.night.adding(days: -$0)].flatMap(value) }
            let evidence = HeartSignalEvidence(
                night: last.night, signal: signal, consecutiveNights: count, value: current, baseline: base.value,
                rangeLow: base.value - spread, rangeHigh: base.value + spread, baselineNights: base.nights, recentValues: recent
            )
            records.append(
                InsightRecord(
                    type: signal == .hrv ? .hrvBelowRange : .restingHeartRateAboveRange, generatedAt: inputs.asOf, evidence: .heartSignal(evidence),
                    confidence: base.nights < RecoveryModelV1.moderateConfidenceNights
                        ? .low : (count >= 5 && base.nights >= BaselineEngine.windowNights ? .high : .moderate),
                    nightsUsed: base.nights
                ))
        }
        return records
    }

    // MARK: - 7: a change in bedtime spread

    static func consistencyChange(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        let span = InsightModelV2.consistencyWindowNights
        let byNight = Dictionary(inputs.complete.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        func bedtimes(offsets: Range<Int>) -> [Double] {
            offsets.compactMap { byNight[last.night.adding(days: -$0)]?.bedtimeMinutes }
        }
        let recent = bedtimes(offsets: 0..<span)
        let previous = bedtimes(offsets: span..<(2 * span))
        guard let recentBaseline = BaselineEngine.baseline(recent), let previousBaseline = BaselineEngine.baseline(previous) else { return [] }
        let delta = recentBaseline.standardDeviation - previousBaseline.standardDeviation
        guard abs(delta).rounded() >= InsightModelV2.consistencyDeltaMinutes else { return [] }
        let series = (0..<(2 * span)).reversed().map { byNight[last.night.adding(days: -$0)]?.bedtimeMinutes }
        let evidence = ConsistencyChangeEvidence(
            night: last.night, recentSD: recentBaseline.standardDeviation, previousSD: previousBaseline.standardDeviation, delta: delta,
            recentNights: recent.count, previousNights: previous.count, bedtimes: series
        )
        let smaller = min(recent.count, previous.count)
        return [
            InsightRecord(
                type: .consistencyChange, generatedAt: inputs.asOf, evidence: .consistencyChange(evidence),
                confidence: smaller >= 10 ? .high : .moderate, nightsUsed: recent.count + previous.count
            )
        ]
    }

    // MARK: - 8: balance

    static func balance(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        guard let balance = inputs.balance, let minutes = balance.minutes, balance.night == last.night,
            abs(minutes).rounded() >= InsightModelV2.balanceMinutes
        else { return [] }
        let byNight = Dictionary(inputs.complete.map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        let nightly = (0..<SleepBalanceEngine.windowNights).reversed().map { byNight[last.night.adding(days: -$0)]?.asleepMinutes }
        let evidence = BalanceEvidence(
            night: last.night, minutes: minutes, recordedNights: balance.recordedNights, needMinutes: inputs.needMinutes, nightlyMinutes: nightly
        )
        return [
            InsightRecord(
                type: .sleepBalance, generatedAt: inputs.asOf, evidence: .balance(evidence),
                confidence: balance.recordedNights >= 7 ? .high : (balance.recordedNights >= 6 ? .moderate : .low), nightsUsed: balance.recordedNights
            )
        ]
    }

    // MARK: - 9: weekends

    /// Friday and Saturday evenings begin the weekend's nights.
    static func isWeekendNight(_ night: SleepNightKey) -> Bool {
        night.weekday == 6 || night.weekday == 7
    }

    static func weekendShift(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        let first = last.night.adding(days: -(InsightModelV2.weekendWindowNights - 1))
        let window = inputs.complete.filter { $0.night >= first && $0.night <= last.night }
        let weekend = window.filter { isWeekendNight($0.night) }.map(\.bedtimeMinutes)
        let weekday = window.filter { !isWeekendNight($0.night) }.map(\.bedtimeMinutes)
        guard weekend.count >= InsightModelV2.weekendMinimumWeekendNights, weekday.count >= InsightModelV2.weekendMinimumWeekdayNights,
            let weekendMedian = InsightStats.median(weekend), let weekdayMedian = InsightStats.median(weekday)
        else { return [] }
        let delta = weekendMedian - weekdayMedian
        guard abs(delta).rounded() >= InsightModelV2.weekendDeltaMinutes else { return [] }
        let evidence = WeekendEvidence(
            night: last.night, windowNights: InsightModelV2.weekendWindowNights, weekendMedian: weekendMedian, weekdayMedian: weekdayMedian,
            delta: delta, weekendNights: weekend.count, weekdayNights: weekday.count
        )
        return [
            InsightRecord(
                type: .weekendShift, generatedAt: inputs.asOf, evidence: .weekend(evidence),
                confidence: weekend.count >= 8 ? .high : (weekend.count >= 5 ? .moderate : .low), nightsUsed: weekend.count + weekday.count
            )
        ]
    }

    // MARK: - 10: a stage's share

    static func stageShares(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        let first = last.night.adding(days: -BaselineEngine.windowNights)
        let window = inputs.complete.filter { $0.night >= first && $0.night < last.night }
        var records: [InsightRecord] = []
        for stage in InsightStage.allCases {
            func share(_ night: InsightNightInput) -> Double? { stage == .deep ? night.deepShare : night.remShare }
            guard let current = share(last), let usual = BaselineEngine.baseline(window.compactMap(share)) else { continue }
            let points = (current - usual.value) * 100
            guard abs(points).rounded() >= InsightModelV2.stagePoints else { continue }
            let evidence = StageShareEvidence(
                night: last.night, stage: stage, share: current, usual: usual.value, deltaPoints: points, usualNights: usual.nights)
            records.append(
                InsightRecord(
                    type: .stageShare, generatedAt: inputs.asOf, evidence: .stageShare(evidence),
                    confidence: usual.nights >= 10 ? .high : (usual.nights >= RecoveryModelV1.moderateConfidenceNights ? .moderate : .low),
                    nightsUsed: usual.nights
                ))
        }
        return records
    }

    // MARK: - 11: records

    /// Whether `value` is strictly better than every one of `others`. A tie
    /// is not a record.
    static func isStrictBest(_ value: Double, others: [Double], higherIsBetter: Bool) -> Bool {
        !others.isEmpty && others.allSatisfy { higherIsBetter ? $0 < value : $0 > value }
    }

    /// The best `others` value, for the evidence.
    static func best(_ others: [Double], higherIsBetter: Bool) -> Double? {
        higherIsBetter ? others.max() : others.min()
    }

    /// The window a record is set in, widest first: 90 nights when the person
    /// has 45 of them recorded, otherwise 30 nights with 14 recorded.
    static func recordScopes() -> [(scope: Int, minimum: Int)] {
        [(InsightModelV2.recordLongWindow, InsightModelV2.recordMinimumLong), (InsightModelV2.recordShortWindow, InsightModelV2.recordMinimumShort)]
    }

    static func recordInsights(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        var records: [InsightRecord] = []

        /// One record type over `values` (night → value): set last night when it
        /// strictly beats every other night in a scope's window.
        func record(_ type: InsightType, value: Double?, series: [SleepNightKey: Double], higherIsBetter: Bool) {
            guard let value else { return }
            for (scope, minimum) in recordScopes() {
                let first = last.night.adding(days: -(scope - 1))
                let others = series.filter { $0.key >= first && $0.key < last.night }.map(\.value)
                guard others.count + 1 >= minimum else { continue }
                guard isStrictBest(value, others: others, higherIsBetter: higherIsBetter), let previous = best(others, higherIsBetter: higherIsBetter) else {
                    continue
                }
                let evidence = RecordEvidence(night: last.night, value: value, previousBest: previous, scope: scope, nightsInWindow: others.count + 1)
                records.append(
                    InsightRecord(
                        type: type, generatedAt: inputs.asOf, evidence: .record(evidence),
                        confidence: scope == InsightModelV2.recordLongWindow ? .high : .moderate, nightsUsed: others.count + 1
                    ))
                return
            }
        }

        let nights = inputs.complete
        record(
            .recordLongestNight, value: last.asleepMinutes, series: Dictionary(nights.map { ($0.night, $0.asleepMinutes) }, uniquingKeysWith: { a, _ in a }),
            higherIsBetter: true)
        record(.recordBestConsistency, value: weekSpread(nights, endingAt: last.night), series: weekSpreads(nights, upTo: last.night), higherIsBetter: false)
        let recovery = Dictionary(inputs.recoveryScores.map { ($0.night, Double($0.score)) }, uniquingKeysWith: { a, _ in a })
        record(.recordHighestRecovery, value: recovery[last.night], series: recovery, higherIsBetter: true)
        let resting = Dictionary(nights.compactMap { night in night.restingHeartRate.map { (night.night, $0) } }, uniquingKeysWith: { a, _ in a })
        record(.recordLowestRestingHeartRate, value: last.restingHeartRate, series: resting, higherIsBetter: false)
        return records
    }

    /// The bedtime spread (sample SD, minutes) over the 7 nights ending on
    /// `night`, needing 5 recorded, like every baseline.
    static func weekSpread(_ nights: [InsightNightInput], endingAt night: SleepNightKey) -> Double? {
        let first = night.adding(days: -6)
        return BaselineEngine.baseline(nights.filter { $0.night >= first && $0.night <= night }.map(\.bedtimeMinutes))?.standardDeviation
    }

    /// Every 7-night spread that has a value, keyed by the night it ends on.
    static func weekSpreads(_ nights: [InsightNightInput], upTo night: SleepNightKey) -> [SleepNightKey: Double] {
        var result: [SleepNightKey: Double] = [:]
        for entry in nights where entry.night <= night {
            if let spread = weekSpread(nights, endingAt: entry.night) { result[entry.night] = spread }
        }
        return result
    }

    /// The standing records over the last 90 nights: the longest night, the
    /// steadiest week, the highest recovery and the lowest resting heart
    /// rate, each with the night it was set on. A record needs 45 nights of
    /// its own values to stand for anything.
    public static func standingRecords(_ inputs: InsightInputs) -> [StandingRecord] {
        guard let last = inputs.lastNight else { return [] }
        let first = last.night.adding(days: -(InsightModelV2.recordLongWindow - 1))
        let nights = inputs.complete.filter { $0.night >= first && $0.night <= last.night }
        var records: [StandingRecord] = []
        func standing(_ type: InsightType, series: [(SleepNightKey, Double)], higherIsBetter: Bool) {
            guard series.count >= InsightModelV2.recordMinimumLong else { return }
            // Later nights win a tie (`max` and `min` keep the first): the newest holder.
            let ordered = series.sorted { $0.0 > $1.0 }
            let holder = higherIsBetter ? ordered.max { $0.1 < $1.1 } : ordered.min { $0.1 < $1.1 }
            if let holder { records.append(StandingRecord(type: type, night: holder.0, value: holder.1, nightsInWindow: series.count)) }
        }
        standing(.recordLongestNight, series: nights.map { ($0.night, $0.asleepMinutes) }, higherIsBetter: true)
        let spreads = weekSpreads(nights, upTo: last.night)
        // A week's spread only counts once its whole week is inside the window.
        standing(.recordBestConsistency, series: spreads.filter { $0.key >= first.adding(days: 6) }.map { ($0.key, $0.value) }, higherIsBetter: false)
        standing(
            .recordHighestRecovery, series: inputs.recoveryScores.filter { $0.night >= first && $0.night <= last.night }.map { ($0.night, Double($0.score)) },
            higherIsBetter: true)
        standing(.recordLowestRestingHeartRate, series: nights.compactMap { night in night.restingHeartRate.map { (night.night, $0) } }, higherIsBetter: false)
        return records
    }

    // MARK: - 12: milestones

    static func milestones(_ inputs: InsightInputs, last: InsightNightInput) -> [InsightRecord] {
        let recorded = inputs.complete.filter { $0.night <= last.night }.count
        guard let milestone = InsightModelV2.milestones.filter({ recorded >= $0 }).max(),
            recorded - milestone < InsightModelV2.milestoneShownNights
        else { return [] }
        let evidence = MilestoneEvidence(night: last.night, milestone: milestone, nightsRecorded: recorded)
        return [InsightRecord(type: .milestone, generatedAt: inputs.asOf, evidence: .milestone(evidence), confidence: .high, nightsUsed: recorded)]
    }
}

/// A record that stands in the last 90 nights, with the night it was set.
public struct StandingRecord: Sendable, Equatable, Codable {
    public let type: InsightType
    public let night: SleepNightKey
    /// Minutes, bedtime spread in minutes, a score or bpm, by type.
    public let value: Double
    public let nightsInWindow: Int

    public init(type: InsightType, night: SleepNightKey, value: Double, nightsInWindow: Int) {
        self.type = type
        self.night = night
        self.value = value
        self.nightsInWindow = nightsInWindow
    }
}
