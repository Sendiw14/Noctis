import Foundation
import Testing

@testable import RecoveryKit
@testable import SleepKit

/// Recovery v2 (pinned with `model: .v2`; the app runs V3): HRV and
/// resting heart rate against the person's own
/// variation, score = clamp(75 + 15·z), and moderate confidence needing
/// 3+ factors AND 7+ nights.
struct RecoveryModelV2Tests {
    private let lastNightKey = SleepNightKey(year: 2026, month: 9, day: 23)

    private func night(asleep: Double = 450, bedtime: Double = 660, wake: Double = 1140, hrv: Double? = 50, resting: Double? = 55) -> NightMetrics {
        NightMetrics(
            night: lastNightKey, wakeTime: Fixture.date(2026, 9, 24, 7), asleepMinutes: asleep,
            bedtimeMinutes: bedtime, wakeMinutes: wake, hrv: hrv, restingHeartRate: resting)
    }

    /// Baselines with realistic spread: HRV 50 ± 5 ms, resting 55 ± 2 bpm.
    private func baselines(hrvSD: Double = 5, restingSD: Double = 2) -> Baselines {
        Baselines(
            sleepDuration: Baseline(value: 450, nights: 14, standardDeviation: 20),
            bedtime: Baseline(value: 660, nights: 14, standardDeviation: 20),
            wakeTime: Baseline(value: 1140, nights: 14, standardDeviation: 15),
            hrv: Baseline(value: 50, nights: 14, standardDeviation: hrvSD),
            restingHeartRate: Baseline(value: 55, nights: 14, standardDeviation: restingSD)
        )
    }

    private func score(_ night: NightMetrics, _ baselines: Baselines) -> RecoveryResult {
        RecoveryEngine.score(lastNight: night, baselines: baselines, baselineNights: 14, needMinutes: 480, model: .v2)
    }

    // MARK: - Model

    @Test func v2KeepsV1sWeights() {
        #expect(RecoveryModelV2.version == "recovery-v2")
        #expect(RecoveryModelV2.weights == RecoveryModelV1.weights)
        #expect(score(night(), baselines()).modelVersion == "recovery-v2")
    }

    @Test func standardDeviationIsTheSampleSpreadOfTheWindow() throws {
        let baseline = try #require(BaselineEngine.baseline([45, 55, 45, 55, 50]))
        #expect(baseline.value == 50)
        #expect(abs(baseline.standardDeviation - (100.0 / 4).squareRoot()) < 1e-9)
    }

    // MARK: - The spec's cases

    @Test func hrvFourPercentBelowWithATypicalSpreadScoresAtLeast65() throws {
        // 48 vs 50 ms, SD 5: z = −0.4 → 69.
        let hrv = try #require(score(night(hrv: 48), baselines()).factor(.hrv))
        #expect(hrv.score >= 65)
        #expect(hrv.score == 69)
    }

    @Test func restingOneBeatBelowBaselineScoresAbove75() throws {
        // 54 vs 55 bpm, SD 2: z = +0.5 → 82.5.
        let resting = try #require(score(night(resting: 54), baselines()).factor(.restingHeartRate))
        #expect(resting.score > 75)
        #expect(resting.score == 83)
    }

    @Test func aNightWithEveryFactorWithinHalfAStandardDeviationScores70To85() throws {
        // 14 nights alternating around 450 min, 11:00 PM, 7:00 AM,
        // 50 ms and 55 bpm; last night inside ±0.5 SD on every factor.
        let history = Fixture.metrics(count: 15) { index in
            guard index < 14 else { return (asleep: 453, bedtime: 663, wake: 1143, hrv: 49, resting: 55.4) }
            let up = index.isMultiple(of: 2)
            return (asleep: up ? 440 : 460, bedtime: up ? 650 : 670, wake: up ? 1130 : 1150, hrv: up ? 45 : 55, resting: up ? 54 : 56)
        }
        guard case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: Fixture.morningAfter, model: .v2) else {
            Issue.record("expected a score")
            return
        }
        for factor in result.factors where factor.standardScore != nil {
            #expect(abs(factor.standardScore ?? 99) <= 0.5)
            #expect(factor.range == .within)
        }
        #expect((70...85).contains(result.score), "score \(result.score)")
    }

    @Test func heavyDeviationPullsBothHeartFactorsUnder50() throws {
        // HRV −2 SD (40 vs 50 ± 5) and resting +2 SD (59 vs 55 ± 2).
        let result = score(night(hrv: 40, resting: 59), baselines())
        let hrv = try #require(result.factor(.hrv))
        let resting = try #require(result.factor(.restingHeartRate))
        #expect(hrv.score == 45 && hrv.score < 50)
        #expect(resting.score == 45 && resting.score < 50)
        #expect(hrv.range == .below)
        #expect(resting.range == .above)
        // With an average night's sleep the overall stays near 71: sleep
        // carries 55% of the weight (see the report).
        #expect(result.score == 71)
    }

    @Test func heavyDeviationOnAShortNightScoresUnder50() {
        // Same heart readings after 5h 30m of an 8h need (duration 37.5)
        // and a bedtime 90 minutes late (consistency 62.5):
        // (37.5×35 + 62.5×20 + 45×25 + 45×20) / 100 = 45.9.
        let result = score(night(asleep: 330, bedtime: 750, hrv: 40, resting: 59), baselines())
        #expect(result.score == 46)
    }

    @Test func spreadFloorsStopTinyChangesFromSwinging() throws {
        // A very steady window (SD 1 ms, 0.2 bpm) uses the 3 ms and 1 bpm floors.
        let result = score(night(hrv: 47, resting: 56), baselines(hrvSD: 1, restingSD: 0.2))
        #expect(try #require(result.factor(.hrv)).score == 60)
        #expect(try #require(result.factor(.restingHeartRate)).score == 60)
    }

    @Test func scoresClampTo0And100() throws {
        let result = score(night(hrv: 200, resting: 20), baselines())
        #expect(try #require(result.factor(.hrv)).score == 100)
        #expect(try #require(result.factor(.restingHeartRate)).score == 100)
        let worst = score(night(hrv: 1, resting: 120), baselines())
        #expect(try #require(worst.factor(.hrv)).score == 0)
    }

    @Test func rangesFollowTheValueNotTheScore() throws {
        #expect(try #require(score(night(hrv: 52), baselines()).factor(.hrv)).range == .within)
        #expect(try #require(score(night(hrv: 60), baselines()).factor(.hrv)).range == .above)
        #expect(try #require(score(night(resting: 58), baselines()).factor(.restingHeartRate)).range == .above)
        #expect(try #require(score(night(resting: 52), baselines()).factor(.restingHeartRate)).range == .below)
    }

    @Test func sleepCurvesAreUnchangedFromV1() throws {
        let v1 = RecoveryEngine.score(lastNight: night(asleep: 420, bedtime: 690), baselines: baselines(), baselineNights: 14, needMinutes: 480, model: .v1)
        let v2 = score(night(asleep: 420, bedtime: 690), baselines())
        #expect(v1.factor(.sleepDuration)?.score == v2.factor(.sleepDuration)?.score)
        #expect(v1.factor(.sleepConsistency)?.score == v2.factor(.sleepConsistency)?.score)
    }

    // MARK: - Confidence

    @Test(arguments: [
        (4, 14, RecoveryConfidence.high),
        (4, 13, .moderate),
        (3, 7, .moderate),
        (3, 6, .low),
        (2, 14, .low),
        (4, 6, .low),
        (1, 0, .low),
    ])
    func moderateNeedsThreeFactorsAndSevenNights(factors: Int, nights: Int, expected: RecoveryConfidence) {
        #expect(RecoveryEngine.confidence(factorCount: factors, baselineNights: nights, model: .v2) == expected)
    }

    @Test func sleepOnlyIsLowConfidence() {
        let history = Fixture.metrics(count: 15) { _ in (asleep: 450, bedtime: 660, wake: 1140, hrv: nil, resting: nil) }
        guard case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: Fixture.morningAfter, model: .v2) else {
            Issue.record("expected a score")
            return
        }
        #expect(result.factorsUsed == [.sleepDuration, .sleepConsistency])
        #expect(result.confidence == .low)
    }

    // MARK: - Recovery baseline

    @Test func theRecoveryBaselineIsRebuiltFromV2Scores() {
        let history = Fixture.metrics(count: 20) { _ in (asleep: 450, bedtime: 660, wake: 1140, hrv: 50, resting: 55) }
        func comparison(_ model: RecoveryModel) -> RecoveryComparison? {
            if case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: Fixture.morningAfter, model: model) {
                return result.comparison
            }
            return nil
        }
        // Steady nights: V1 scores each 73, V2 each 84
        // ((87.5×35 + 100×20 + 75×25 + 75×20) / 100 = 84.4).
        #expect(comparison(.v1)?.baseline == 73)
        #expect(comparison(.v2)?.baseline == 84)
        #expect(comparison(.v2)?.delta == 0)
    }
}
