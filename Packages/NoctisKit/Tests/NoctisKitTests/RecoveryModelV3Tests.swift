import Foundation
import Testing

@testable import HomeFeature
@testable import RecoveryKit
@testable import SleepKit

/// Recovery v3 (the app's model): V2 plus a cap at 50 when HRV is 1.5 SD
/// or more below baseline and resting heart rate 1.5 SD or more above it
/// on the same morning.
struct RecoveryModelV3Tests {
    private let lastNightKey = SleepNightKey(year: 2026, month: 9, day: 23)

    private func night(asleep: Double = 450, hrv: Double? = 50, resting: Double? = 55) -> NightMetrics {
        NightMetrics(
            night: lastNightKey, wakeTime: Fixture.date(2026, 9, 24, 7), asleepMinutes: asleep,
            bedtimeMinutes: 660, wakeMinutes: 1140, hrv: hrv, restingHeartRate: resting)
    }

    /// HRV 50 ± 5 ms, resting 55 ± 2 bpm, an average 7h 30m night.
    private let baselines = Baselines(
        sleepDuration: Baseline(value: 450, nights: 14, standardDeviation: 20),
        bedtime: Baseline(value: 660, nights: 14, standardDeviation: 20),
        wakeTime: Baseline(value: 1140, nights: 14, standardDeviation: 15),
        hrv: Baseline(value: 50, nights: 14, standardDeviation: 5),
        restingHeartRate: Baseline(value: 55, nights: 14, standardDeviation: 2)
    )

    private func score(_ night: NightMetrics, model: RecoveryModel = .current) -> RecoveryResult {
        RecoveryEngine.score(lastNight: night, baselines: baselines, baselineNights: 14, needMinutes: 480, model: model)
    }

    @Test func theAppRunsV3() {
        #expect(RecoveryModel.current == .v3)
        #expect(RecoveryModelV3.version == "recovery-v3")
        #expect(RecoveryModelV3.weights == RecoveryModelV2.weights)
        #expect(score(night()).modelVersion == "recovery-v3")
    }

    @Test func bothHeartSignalsTwoDeviationsOffCapTheScoreAt50() {
        // HRV −2 SD (40 vs 50 ± 5), resting +2 SD (59 vs 55 ± 2), an
        // average night: V2 scores this 71.
        let v2 = score(night(hrv: 40, resting: 59), model: .v2)
        let v3 = score(night(hrv: 40, resting: 59))
        #expect(v2.score == 71)
        #expect(v3.score <= 50)
        #expect(v3.score == 50)
        #expect(v3.heartCapApplied)
        #expect(!v2.heartCapApplied)
    }

    @Test func oneSignalAloneDoesNotCap() {
        let hrvOnly = score(night(hrv: 40, resting: 55))
        let restingOnly = score(night(hrv: 50, resting: 59))
        #expect(!hrvOnly.heartCapApplied)
        #expect(!restingOnly.heartCapApplied)
        #expect(hrvOnly.score == score(night(hrv: 40, resting: 55), model: .v2).score)
        #expect(restingOnly.score > 50)
    }

    @Test func theCapStartsAtExactlyOneAndAHalfDeviations() {
        // 42.5 ms = −1.5 SD, 58 bpm = +1.5 SD: capped.
        #expect(score(night(hrv: 42.5, resting: 58)).heartCapApplied)
        // 43 ms = −1.4 SD: not.
        #expect(!score(night(hrv: 43, resting: 58)).heartCapApplied)
        // Good-direction deviations never cap.
        #expect(!score(night(hrv: 60, resting: 51)).heartCapApplied)
    }

    @Test func aScoreAlreadyUnder50StaysWhereItIs() {
        let short = score(night(asleep: 240, hrv: 40, resting: 59))
        #expect(short.heartCapApplied)
        #expect(short.score < 50)
        #expect(short.score == score(night(asleep: 240, hrv: 40, resting: 59), model: .v2).score)
    }

    @Test func missingHeartDataNeverCaps() {
        #expect(!score(night(hrv: nil, resting: 59)).heartCapApplied)
        #expect(!score(night(hrv: 40, resting: nil)).heartCapApplied)
    }

    @Test func v3KeepsV2sConfidence() {
        #expect(RecoveryEngine.confidence(factorCount: 2, baselineNights: 14, model: .v3) == .low)
        #expect(RecoveryEngine.confidence(factorCount: 3, baselineNights: 7, model: .v3) == .moderate)
    }

    @Test func detailSaysItPlainlyAndNamesTheModel() {
        let content = HomeScreenBuilder.scoredContent(score(night(hrv: 40, resting: 59)))
        #expect(content.heartCapNote == "Your heart rate and HRV are both well outside your normal range.")
        #expect(HomeScreenBuilder.scoredContent(score(night())).heartCapNote == nil)
        let calculation = HomeScreenBuilder.calculation(score(night(hrv: 40, resting: 59)), needMinutes: 480)
        #expect(calculation.last?.contains("capped at 50") == true)
    }
}
