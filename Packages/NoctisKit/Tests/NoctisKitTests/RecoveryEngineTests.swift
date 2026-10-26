import Foundation
import Testing

@testable import RecoveryKit
@testable import SleepKit

/// RecoveryModelV1, pinned with `model: .v1` (V2 is the app default).
struct RecoveryEngineTests {
    private let lastNightKey = SleepNightKey(year: 2026, month: 9, day: 23)

    private func lastNight(asleep: Double = 420, bedtime: Double = 690, wake: Double = 1140, hrv: Double? = 55, resting: Double? = 57) -> NightMetrics {
        NightMetrics(
            night: lastNightKey, wakeTime: Fixture.date(2026, 9, 24, 7), asleepMinutes: asleep,
            bedtimeMinutes: bedtime, wakeMinutes: wake, hrv: hrv, restingHeartRate: resting)
    }

    private let fullBaselines = Baselines(
        sleepDuration: Baseline(value: 450, nights: 14),
        bedtime: Baseline(value: 660, nights: 14),
        wakeTime: Baseline(value: 1140, nights: 14),
        hrv: Baseline(value: 50, nights: 14),
        restingHeartRate: Baseline(value: 55, nights: 14)
    )

    /// `count` identical nights ending last night (Sep 23), with or
    /// without HRV and resting heart rate.
    private func history(count: Int, heartData: Bool = true) -> [NightMetrics] {
        Fixture.metrics(count: count) { _ in (asleep: 450, bedtime: 660, wake: 1140, hrv: heartData ? 50 : nil, resting: heartData ? 55 : nil) }
    }

    // MARK: - Model config

    @Test func weightsLiveInTheVersionedV1Config() {
        #expect(RecoveryModelV1.version == "recovery-v1")
        #expect(RecoveryModelV1.weights == [.sleepDuration: 35, .sleepConsistency: 20, .hrv: 25, .restingHeartRate: 20])
        #expect(RecoveryModelV1.weights.values.reduce(0, +) == 100)
    }

    // MARK: - Factor scores

    @Test func eachFactorScoresAgainstItsBaseline() throws {
        let result = RecoveryEngine.score(lastNight: lastNight(), baselines: fullBaselines, baselineNights: 14, needMinutes: 480, model: .v1)

        let duration = try #require(result.factor(.sleepDuration))
        #expect(duration.score == 75)  // 420 of 480 = 87.5% → 100 − 12.5% × 200
        #expect(duration.delta == -30)

        let consistency = try #require(result.factor(.sleepConsistency))
        #expect(consistency.score == 88)  // (30 + 0) / 2 = 15 min off → 87.5
        #expect(consistency.value == 15)
        #expect(consistency.delta == 30)

        let hrv = try #require(result.factor(.hrv))
        #expect(hrv.score == 75)  // +10% → 50 + 0.1 × 250
        #expect(hrv.delta == 5)

        let resting = try #require(result.factor(.restingHeartRate))
        #expect(resting.score == 30)  // +2 bpm → 50 − 20
        #expect(resting.delta == 2)

        // (75×35 + 87.5×20 + 75×25 + 30×20) / 100 = 68.5
        #expect(result.score == 69)
        #expect(result.factorsUsed == [.sleepDuration, .sleepConsistency, .hrv, .restingHeartRate])
        #expect(result.modelVersion == "recovery-v1")
    }

    @Test func sleepAtOrAboveNeedScoresFull() {
        let result = RecoveryEngine.score(lastNight: lastNight(asleep: 500), baselines: .none, baselineNights: 0, needMinutes: 480, model: .v1)
        #expect(result.factor(.sleepDuration)?.score == 100)
        #expect(result.factor(.sleepDuration)?.delta == nil)
    }

    @Test func factorScoresStayWithin0And100() {
        let high = RecoveryEngine.score(lastNight: lastNight(hrv: 200, resting: 30), baselines: fullBaselines, baselineNights: 14, needMinutes: 480, model: .v1)
        #expect(high.factor(.hrv)?.score == 100)
        #expect(high.factor(.restingHeartRate)?.score == 100)
        let low = RecoveryEngine.score(
            lastNight: lastNight(asleep: 60, bedtime: 900, hrv: 5, resting: 90), baselines: fullBaselines, baselineNights: 14, needMinutes: 480, model: .v1)
        #expect(low.factors.allSatisfy { $0.score == 0 })
        #expect(low.score == 0)
    }

    // MARK: - Renormalization

    @Test func missingFactorsAreDroppedAndWeightsRenormalized() throws {
        let result = RecoveryEngine.score(
            lastNight: lastNight(hrv: nil, resting: nil), baselines: fullBaselines, baselineNights: 14, needMinutes: 480, model: .v1)
        #expect(result.factorsUsed == [.sleepDuration, .sleepConsistency])
        #expect(try #require(result.factor(.sleepDuration)).weight == 35.0 / 55.0)
        #expect(try #require(result.factor(.sleepConsistency)).weight == 20.0 / 55.0)
        // (75×35 + 87.5×20) / 55 = 79.5…
        #expect(result.score == 80)
    }

    @Test func aFactorWithoutABaselineIsDropped() {
        let noHRVBaseline = Baselines(
            sleepDuration: fullBaselines.sleepDuration, bedtime: fullBaselines.bedtime,
            wakeTime: fullBaselines.wakeTime, hrv: nil, restingHeartRate: fullBaselines.restingHeartRate)
        let result = RecoveryEngine.score(lastNight: lastNight(), baselines: noHRVBaseline, baselineNights: 14, needMinutes: 480, model: .v1)
        #expect(result.factorsUsed == [.sleepDuration, .sleepConsistency, .restingHeartRate])
        // (75×35 + 87.5×20 + 30×20) / 75 = 66.3…
        #expect(result.score == 66)
    }

    @Test func durationAloneCarriesTheWholeWeight() {
        let result = RecoveryEngine.score(lastNight: lastNight(hrv: nil, resting: nil), baselines: .none, baselineNights: 0, needMinutes: 480, model: .v1)
        #expect(result.factorsUsed == [.sleepDuration])
        #expect(result.factor(.sleepDuration)?.weight == 1.0)
        #expect(result.score == 75)
    }

    @Test func weightsAlwaysSumToOne() {
        let result = RecoveryEngine.score(lastNight: lastNight(resting: nil), baselines: fullBaselines, baselineNights: 14, needMinutes: 480, model: .v1)
        #expect(abs(result.factors.map(\.weight).reduce(0, +) - 1) < 1e-12)
    }

    // MARK: - Confidence tiers

    @Test(arguments: [
        (4, 14, RecoveryConfidence.high),
        (4, 13, .moderate),
        (3, 0, .moderate),
        (2, 7, .moderate),
        (1, 7, .moderate),
        (2, 6, .low),
        (1, 0, .low),
    ])
    func confidenceTiers(factors: Int, nights: Int, expected: RecoveryConfidence) {
        #expect(RecoveryEngine.confidence(factorCount: factors, baselineNights: nights, model: .v1) == expected)
    }

    @Test func highConfidenceNeedsAllFourFactorsAndFourteenNights() throws {
        let state = RecoveryEngine.evaluate(history: history(count: 15), needMinutes: 480, asOf: Fixture.morningAfter, model: .v1)
        guard case .scored(let result) = state else {
            Issue.record("expected a score, got \(state)")
            return
        }
        #expect(result.factorsUsed.count == 4)
        #expect(result.baselineNights == 14)
        #expect(result.confidence == .high)
    }

    @Test func sleepOnlyWithAFullWindowIsModerate() throws {
        let state = RecoveryEngine.evaluate(history: history(count: 15, heartData: false), needMinutes: 480, asOf: Fixture.morningAfter, model: .v1)
        guard case .scored(let result) = state else {
            Issue.record("expected a score, got \(state)")
            return
        }
        #expect(result.factorsUsed == [.sleepDuration, .sleepConsistency])
        #expect(result.confidence == .moderate)
    }

    @Test func fourFactorsWithAShortWindowIsModerate() throws {
        let state = RecoveryEngine.evaluate(history: history(count: 6), needMinutes: 480, asOf: Fixture.morningAfter, model: .v1)
        guard case .scored(let result) = state else {
            Issue.record("expected a score, got \(state)")
            return
        }
        #expect(result.baselineNights == 5)
        #expect(result.factorsUsed.count == 4)
        #expect(result.confidence == .moderate)
    }

    @Test func fewFactorsAndAShortWindowIsLow() throws {
        let state = RecoveryEngine.evaluate(history: history(count: 6, heartData: false), needMinutes: 480, asOf: Fixture.morningAfter, model: .v1)
        guard case .scored(let result) = state else {
            Issue.record("expected a score, got \(state)")
            return
        }
        #expect(result.factorsUsed.count == 2)
        #expect(result.baselineNights == 5)
        #expect(result.confidence == .low)
    }

    // MARK: - States

    @Test func underFiveNightsIsLearning() {
        #expect(RecoveryEngine.evaluate(history: [], needMinutes: 480, asOf: Fixture.morningAfter, model: .v1) == .learning(nightsSoFar: 0))
        #expect(RecoveryEngine.evaluate(history: history(count: 4), needMinutes: 480, asOf: Fixture.morningAfter, model: .v1) == .learning(nightsSoFar: 4))
    }

    @Test func fiveNightsEndLearning() {
        let state = RecoveryEngine.evaluate(history: history(count: 5), needMinutes: 480, asOf: Fixture.morningAfter, model: .v1)
        guard case .scored(let result) = state else {
            Issue.record("expected a score, got \(state)")
            return
        }
        // Four nights before last night: no baselines yet, duration only.
        #expect(result.factorsUsed == [.sleepDuration])
        #expect(result.confidence == .low)
    }

    @Test func noScoreWithoutLastNightsSleep() {
        // The newest night woke at 7:00 AM on Sep 24; 30 hours later.
        let later = Fixture.date(2026, 9, 25, 13)
        #expect(RecoveryEngine.evaluate(history: history(count: 15), needMinutes: 480, asOf: later, model: .v1) == .noSleepLastNight)
    }

    @Test func nightsThatHaventEndedDoNotCount() {
        // At 6:00 AM on Sep 24, last night (waking at 7:00) isn't over.
        let early = Fixture.date(2026, 9, 24, 6)
        #expect(RecoveryEngine.evaluate(history: history(count: 5), needMinutes: 480, asOf: early, model: .v1) == .learning(nightsSoFar: 4))
    }

    @Test func theSameInputsAlwaysGiveTheSameResult() {
        let first = RecoveryEngine.evaluate(history: history(count: 15), needMinutes: 480, asOf: Fixture.morningAfter, model: .v1)
        let second = RecoveryEngine.evaluate(history: history(count: 15), needMinutes: 480, asOf: Fixture.morningAfter, model: .v1)
        #expect(first == second)
    }
}

/// Today's score against the recent baseline, and why factors are missing
/// (V1 numbers).
struct RecoveryComparisonTests {
    private func history(count: Int, lastAsleep: Double = 450, heartData: Bool = true, lastHRV: Double?? = .none) -> [NightMetrics] {
        Fixture.metrics(count: count) { index in
            let isLast = index == count - 1
            let hrv: Double? = isLast ? (lastHRV ?? (heartData ? 50 : nil)) : (heartData ? 50 : nil)
            return (asleep: isLast ? lastAsleep : 450, bedtime: 660, wake: 1140, hrv: hrv, resting: heartData ? 55 : nil)
        }
    }

    private func scored(_ history: [NightMetrics]) -> RecoveryResult? {
        if case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: Fixture.morningAfter, model: .v1) { return result }
        return nil
    }

    @Test func aSteadyWeekIsInLineWithItsBaseline() throws {
        // Every window night scores 73: (87.5×35 + 100×20 + 50×25 + 50×20) / 100.
        let result = try #require(scored(history(count: 20)))
        #expect(result.comparison.baseline == 73)
        #expect(result.comparison.nights == 14)
        #expect(result.comparison.delta == 0)
        #expect(result.comparison.trend == .inLine)
        #expect(result.comparison.sentence == "In line with your recent baseline.")
    }

    @Test func aBetterNightIsAboveAndAWorseOneBelow() throws {
        let better = try #require(scored(history(count: 20, lastAsleep: 480)))
        #expect(better.score == 78)
        #expect(better.comparison.delta == 5)
        #expect(better.comparison.trend == .above)
        #expect(better.comparison.sentence == "Above your recent baseline.")

        let worse = try #require(scored(history(count: 20, lastAsleep: 360)))
        #expect(worse.score == 60)
        #expect(worse.comparison.delta == -13)
        #expect(worse.comparison.trend == .below)
        #expect(worse.comparison.sentence == "Below your recent baseline.")
    }

    @Test func nightsStillLearningAreLeftOutOfTheRecoveryBaseline() throws {
        // 15 nights: the window's first four were still learning, so only
        // Sep 13 (duration only, 88) and nine full nights (73) count.
        let result = try #require(scored(history(count: 15)))
        #expect(result.comparison.nights == 10)
        #expect(result.comparison.baseline == 74.5)
    }

    @Test func noRecoveryBaselineUnderFiveScoredNights() {
        let comparison = RecoveryEngine.comparison(score: 80, windowScores: [70, 70, 70, 70])
        #expect(comparison.baseline == nil)
        #expect(comparison.delta == nil)
        #expect(comparison.trend == .unknown)
        #expect(comparison.sentence == "Not enough nights yet to compare with your baseline.")
        #expect(RecoveryEngine.comparison(score: 80, windowScores: [70, 70, 70, 70, 70]).delta == 10)
    }

    @Test(arguments: [(3, RecoveryTrend.above), (2, .inLine), (0, .inLine), (-2, .inLine), (-3, .below)])
    func trendThresholdsAreThreePoints(delta: Int, expected: RecoveryTrend) {
        #expect(RecoveryComparison(baseline: 70, nights: 14, delta: delta).trend == expected)
    }

    @Test func sourcesWithoutHeartDataAreUnavailable() throws {
        let result = try #require(scored(history(count: 15, heartData: false)))
        #expect(result.missingFactors == [.hrv: .unavailable, .restingHeartRate: .unavailable])
    }

    @Test func heartDataMissingOnlyLastNightWasNotRecorded() throws {
        let result = try #require(scored(history(count: 15, lastHRV: .some(nil))))
        #expect(result.missingFactors == [.hrv: .notRecorded])
    }

    @Test func factorsWithoutFiveNightsAreBuildingTheirBaseline() throws {
        let result = try #require(scored(history(count: 5)))
        #expect(result.missingFactors == [.sleepConsistency: .buildingBaseline, .hrv: .buildingBaseline, .restingHeartRate: .buildingBaseline])
    }

    @Test func theResultCarriesTheBaselinesItWasJudgedAgainst() throws {
        let result = try #require(scored(history(count: 15)))
        #expect(result.baselines.bedtime == Baseline(value: 660, nights: 14))
        #expect(result.baselines.hrv == Baseline(value: 50, nights: 14))
    }
}
