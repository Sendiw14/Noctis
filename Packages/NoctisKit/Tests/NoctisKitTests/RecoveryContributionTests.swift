import Foundation
import Testing

@testable import HealthProviding
@testable import RecoveryKit
@testable import SleepKit

// Recovery's contribution, confidence and factor-series engines.

private let lastNight = SleepNightKey(year: 2026, month: 9, day: 23)
private let now = Fixture.morningAfter

private struct Generator {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

private func varied(count: Int, seed: UInt64 = 11, heart: Bool = true) -> [NightMetrics] {
    var rng = Generator(state: seed)
    return Fixture.metrics(count: count) { _ in
        (
            asleep: 380 + rng.next() * 140, bedtime: 640 + rng.next() * 70, wake: 1120 + rng.next() * 50,
            hrv: heart ? 40 + rng.next() * 20 : nil, resting: heart ? 52 + rng.next() * 8 : nil
        )
    }
}

private func steady(count: Int, endingOn last: SleepNightKey = lastNight, hrv: Double? = 50, resting: Double? = 55) -> [NightMetrics] {
    Fixture.metrics(count: count, endingOn: last) { _ in (asleep: 480, bedtime: 660, wake: 1140, hrv: hrv, resting: resting) }
}

private func today(_ history: [NightMetrics], need: Double = 480) throws -> RecoveryResult {
    guard case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: need, asOf: now) else {
        throw TestFailure("expected a score")
    }
    return result
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Contributions

struct RecoveryContributionTests {
    @Test func theFactorsPointsAddUpToTheScoreBeforeAnyCap() throws {
        let history = varied(count: 60)
        var checked = 0
        for night in history.dropFirst(5) {
            let result = try #require(RecoveryEngine.scoreResultAsOfThatMorning(night, complete: history, needMinutes: 480, model: .current))
            let parts = RecoveryContributionEngine.contributions(for: result)
            let sum = parts.contributions.reduce(0) { $0 + $1.points }
            #expect(abs(sum - parts.preCapScore) < 1e-9)
            if result.heartCapApplied {
                #expect(parts.score == RecoveryModelV3.heartCapScore)
                #expect(parts.preCapScore > Double(RecoveryModelV3.heartCapScore) - 0.5)
            } else {
                #expect(parts.score == Int(parts.preCapScore.rounded()), "the points are the score's own arithmetic")
                #expect(parts.contributions.reduce(0) { $0 + $1.wholePoints } == result.score)
            }
            #expect(parts.contributions.allSatisfy { abs(Double($0.wholePoints) - $0.points) < 1 })
            checked += 1
        }
        #expect(checked == 55)
    }

    @Test func eachContributionIsItsWeightTimesItsScoreInRingOrder() throws {
        let result = try today(varied(count: 30))
        let parts = RecoveryContributionEngine.contributions(for: result)
        #expect(parts.contributions.map(\.kind) == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency])
        #expect(abs(parts.contributions.reduce(0) { $0 + $1.weight } - 1) < 1e-9)
        for item in parts.contributions {
            let factor = try #require(result.factor(item.kind))
            #expect(item.weight == factor.weight)
            #expect(abs(item.score - factor.score.asDouble) <= 0.5)
            #expect(abs(item.points - item.weight * item.score) < 1e-12)
        }
    }

    @Test func theChangeFromUsualIsInPointsAndMissingWithoutAUsual() throws {
        let result = try today(varied(count: 30))
        let parts = RecoveryContributionEngine.contributions(for: result)
        for item in parts.contributions {
            let usual = try #require(result.factor(item.kind)?.usual)
            #expect(abs((item.usualPoints ?? 0) - item.weight * usual) < 1e-9)
            #expect(abs((item.deltaPoints ?? 0) - (item.points - item.weight * usual)) < 1e-9)
        }
        // Six nights: today has a 5-night window but no scored nights to average.
        let young = try today(varied(count: 6))
        let none = RecoveryContributionEngine.contributions(for: young)
        #expect(none.contributions.allSatisfy { $0.usualPoints == nil && $0.deltaPoints == nil })
    }

    @Test func aResultWithoutUnroundedScoresStillAddsUpFromItsRoundedOnes() {
        let factors = [
            RecoveryFactor(kind: .sleepDuration, score: 80, weight: 0.6, value: 450, baseline: 450, delta: 0),
            RecoveryFactor(kind: .sleepConsistency, score: 60, weight: 0.4, value: 10, baseline: nil, delta: 0),
        ]
        let result = RecoveryResult(night: lastNight, score: 72, factors: factors, confidence: .low, baselineNights: 5, modelVersion: "recovery-v3")
        let parts = RecoveryContributionEngine.contributions(for: result)
        #expect(parts.preCapScore == 72)
        #expect(parts.contributions.map(\.points) == [48, 24])
        #expect(parts.contributions.map(\.wholePoints) == [48, 24])
    }

    @Test func wholePointsAreLargestRemainderAndAlwaysAddUp() {
        #expect(RecoveryContributionEngine.wholePoints([24.5, 24.5, 21.0], total: 70) == [25, 24, 21], "a tie goes to the earlier factor")
        #expect(RecoveryContributionEngine.wholePoints([10.9, 20.1, 39.0], total: 70) == [11, 20, 39])
        #expect(RecoveryContributionEngine.wholePoints([33.4, 33.3, 33.3], total: 100) == [34, 33, 33])
        #expect(RecoveryContributionEngine.wholePoints([], total: 0) == [])
        for total in 60...80 {
            let values = [Double(total) * 0.35, Double(total) * 0.25, Double(total) * 0.2, Double(total) * 0.2]
            #expect(RecoveryContributionEngine.wholePoints(values, total: total).reduce(0, +) == total)
        }
    }

    @Test func aSleepOnlyScoreSplitsItsWeightBetweenTheTwoFactorsItHas() throws {
        let result = try today(varied(count: 30, heart: false))
        let parts = RecoveryContributionEngine.contributions(for: result)
        #expect(parts.contributions.map(\.kind) == [.sleepDuration, .sleepConsistency])
        #expect(abs(parts.contributions[0].weight - 35.0 / 55.0) < 1e-12)
        #expect(abs(parts.contributions[1].weight - 20.0 / 55.0) < 1e-12)
        #expect(abs(parts.contributions.reduce(0) { $0 + $1.points } - parts.preCapScore) < 1e-9)
    }

    @Test func whenTheHeartCapAppliesTheReportSaysWhyAndKeepsThePreCapScore() throws {
        // 20 steady nights, then last night's HRV far below and resting heart rate far above.
        var history = steady(count: 19, endingOn: lastNight.adding(days: -1))
        history.append(
            NightMetrics(
                night: lastNight, wakeTime: Fixture.date(2026, 9, 24, 7), asleepMinutes: 480, bedtimeMinutes: 660, wakeMinutes: 1140,
                hrv: 40, restingHeartRate: 62
            ))
        let result = try today(history)
        #expect(result.heartCapApplied && result.score == 50)
        let parts = RecoveryContributionEngine.contributions(for: result)
        let cap = try #require(parts.capApplied)
        #expect(cap.cap == 50 && cap.reason == .heartSignalsBothFarOff)
        #expect(cap.preCapScore == parts.preCapScore && cap.preCapScore > 50)
        #expect((cap.hrvStandardDeviations ?? 0) <= -RecoveryModelV3.heartCapStandardDeviations)
        #expect((cap.restingStandardDeviations ?? 0) <= -RecoveryModelV3.heartCapStandardDeviations)
        #expect(parts.score == 50, "the score shown is the capped one")
        #expect(abs(parts.contributions.reduce(0) { $0 + $1.points } - cap.preCapScore) < 1e-9)
        // Without the cap the report has none.
        #expect(RecoveryContributionEngine.contributions(for: try today(steady(count: 20))).capApplied == nil)
    }
}

private extension Int {
    var asDouble: Double { Double(self) }
}

// MARK: - Confidence

struct RecoveryConfidenceReportTests {
    @Test func aFullFortnightIsHighWithEveryFactorAndNothingToAdd() throws {
        let report = RecoveryConfidenceReportBuilder.report(for: try today(varied(count: 30)))
        #expect(report.tier == .high)
        #expect(report.factorsUsed == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency])
        #expect(report.factorsMissing.isEmpty)
        #expect(report.nights == 14)
        #expect(report.nextStep == nil)
    }

    @Test func theTierFollowsTheSameRulesAsTheEngine() throws {
        for count in [6, 8, 10, 15, 30] {
            let result = try today(varied(count: count))
            #expect(
                RecoveryConfidenceReportBuilder.report(for: result).tier
                    == RecoveryEngine.confidence(factorCount: result.factors.count, baselineNights: result.baselineNights))
        }
    }

    @Test func fewerThanAFortnightOfFourFactorsPointsAtTheNightsStillToCome() throws {
        let result = try today(varied(count: 10))
        let report = RecoveryConfidenceReportBuilder.report(for: result)
        #expect(report.tier == .moderate)
        #expect(report.nights == 9)
        #expect(report.nextStep == .reachHigh(nightsNeeded: 5))
    }

    @Test func aSleepOnlyHistoryIsLowAndSaysAWatchWouldAddTheHeartSignals() throws {
        let report = RecoveryConfidenceReportBuilder.report(for: try today(varied(count: 30, heart: false)))
        #expect(report.tier == .low)
        #expect(report.factorsUsed == [.sleepDuration, .sleepConsistency])
        #expect(
            report.factorsMissing == [
                .init(kind: .hrv, reason: .unavailable), .init(kind: .restingHeartRate, reason: .unavailable),
            ])
        #expect(report.nextStep == .wearWatchToSleep(adding: [.hrv, .restingHeartRate]))
    }

    @Test func aFactorNotRecordedLastNightIsTheSmallestStepAndBeatsAWatch() throws {
        // Twenty nights of HRV and resting heart rate, but last night has no HRV.
        var history = steady(count: 19, endingOn: lastNight.adding(days: -1))
        history.append(
            NightMetrics(
                night: lastNight, wakeTime: Fixture.date(2026, 9, 24, 7), asleepMinutes: 480, bedtimeMinutes: 660, wakeMinutes: 1140, hrv: nil,
                restingHeartRate: 55))
        let report = RecoveryConfidenceReportBuilder.report(for: try today(history))
        #expect(report.factorsMissing == [.init(kind: .hrv, reason: .notRecorded)])
        #expect(report.nextStep == .recordAgain(factors: [.hrv]))
        #expect(report.tier == .high || report.tier == .moderate)
    }

    @Test func aBaselineStillFormingSaysHowManyMoreNightsAFactorNeeds() throws {
        // HRV recorded only on the last three nights before today, and today.
        var history = steady(count: 20, hrv: nil, resting: 55)
        for index in 16..<20 {
            let night = history[index]
            history[index] = NightMetrics(
                night: night.night, wakeTime: night.wakeTime, asleepMinutes: night.asleepMinutes, bedtimeMinutes: night.bedtimeMinutes,
                wakeMinutes: night.wakeMinutes, hrv: 50, restingHeartRate: 55
            )
        }
        let report = RecoveryConfidenceReportBuilder.report(for: try today(history))
        #expect(report.factorsMissing == [.init(kind: .hrv, reason: .buildingBaseline)])
        // Three earlier nights have HRV: two more make five.
        #expect(report.nextStep == .keepTracking(nightsNeeded: 2))
    }

    @Test func aShortHistoryHasNothingToCompareWithAndSaysSo() throws {
        let report = RecoveryConfidenceReportBuilder.report(for: try today(varied(count: 5)))
        #expect(report.tier == .low)
        #expect(report.nights == 4)
        #expect(report.factorsMissing.map(\.reason).allSatisfy { $0 == .buildingBaseline })
        #expect(report.nextStep == .keepTracking(nightsNeeded: 1))
    }
}

// MARK: - Factor series

struct RecoveryFactorSeriesTests {
    @Test func eachRangeIsItsNumberOfCalendarNightsOldestFirstEndingOnTheNewest() {
        let history = varied(count: 120)
        for range in RecoveryFactorRange.allCases {
            let series = RecoveryFactorSeriesBuilder.series(.hrv, range: range, history: history, needMinutes: 480, asOf: now)
            #expect(series.points.count == range.nights)
            #expect(series.points.last?.night == lastNight)
            #expect(series.points.first?.night == lastNight.adding(days: -(range.nights - 1)))
            #expect(!series.isDownsampled)
            #expect(series.points.allSatisfy { $0.value != nil && $0.score != nil })
        }
    }

    @Test func aFactorsValueIsItsOwnUnitAndConsistencyIsBedtime() {
        let history = varied(count: 30)
        let last = history[history.count - 1]
        func series(_ kind: RecoveryFactorKind) -> RecoveryFactorSeries {
            RecoveryFactorSeriesBuilder.series(kind, range: .fortnight, history: history, needMinutes: 480, asOf: now)
        }
        #expect(series(.sleepDuration).today == last.asleepMinutes)
        #expect(series(.sleepConsistency).today == last.bedtimeMinutes)
        #expect(series(.hrv).today == last.hrv)
        #expect(series(.restingHeartRate).today == last.restingHeartRate)
    }

    @Test func theNormalBandIsUsualPlusOrMinusOneFlooredSD() throws {
        let history = steady(count: 30)
        let hrv = RecoveryFactorSeriesBuilder.series(.hrv, range: .month, history: history, needMinutes: 480, asOf: now)
        #expect(hrv.usual == 50)
        #expect(hrv.standardDeviation == RecoveryModelV2.hrvStandardDeviationFloor)
        #expect(hrv.normalRange == 47...53)
        let resting = RecoveryFactorSeriesBuilder.series(.restingHeartRate, range: .month, history: history, needMinutes: 480, asOf: now)
        #expect(resting.normalRange == 54...56)
        let duration = RecoveryFactorSeriesBuilder.series(.sleepDuration, range: .month, history: history, needMinutes: 480, asOf: now)
        #expect(duration.standardDeviation == RecoveryNormalRange.sleepDurationStandardDeviationFloor)
        let real = varied(count: 30)
        let baseline = try #require(BaselineEngine.baselines(for: lastNight, history: real).hrv)
        let series = RecoveryFactorSeriesBuilder.series(.hrv, range: .fortnight, history: real, needMinutes: 480, asOf: now)
        #expect(series.usual == baseline.value)
        #expect(series.standardDeviation == max(baseline.standardDeviation, RecoveryModelV2.hrvStandardDeviationFloor))
    }

    @Test func eachPointsScoreIsTheOneThatNightHadOnItsOwnMorning() throws {
        let history = varied(count: 40)
        let series = RecoveryFactorSeriesBuilder.series(.hrv, range: .fortnight, history: history, needMinutes: 480, asOf: now)
        let byNight = Dictionary(
            RecoveryHistoryEngine.scores(history: history, needMinutes: 480, asOf: now).map { ($0.night, $0) }, uniquingKeysWith: { first, _ in first })
        for point in series.points {
            #expect(point.score == byNight[point.night]?.factorScore(.hrv))
        }
    }

    @Test func aNightWithoutAValueIsAGapAndTheWindowHoldsWhatExists() {
        let history = varied(count: 30)
        let holes = history.enumerated().filter { $0.offset != 25 }.map(\.element)
        let series = RecoveryFactorSeriesBuilder.series(.hrv, range: .fortnight, history: holes, needMinutes: 480, asOf: now)
        #expect(series.points.count == 14)
        #expect(series.points.first { $0.night == history[25].night }?.value == nil)
        #expect(series.nightsRecorded == 13)
        // Fewer nights than the range: 90 points, most of them empty.
        let young = RecoveryFactorSeriesBuilder.series(.sleepDuration, range: .quarter, history: varied(count: 5), needMinutes: 480, asOf: now)
        #expect(young.points.count == 90 && young.nightsRecorded == 5)
        #expect(young.minimum != nil && young.maximum != nil)
        #expect(young.usual == nil, "under 5 nights of baseline")
    }

    @Test func theMinimumAndMaximumAreTheWindowsRangeOfValues() {
        let history = varied(count: 30)
        let series = RecoveryFactorSeriesBuilder.series(.restingHeartRate, range: .fortnight, history: history, needMinutes: 480, asOf: now)
        let window = history.suffix(14).compactMap(\.restingHeartRate)
        #expect(series.minimum == window.min() && series.maximum == window.max())
    }

    @Test func aSeriesNeverDrawsMoreThan120PointsAndKeepsShortOnesAsTheyAre() {
        let points = (0..<200).map { RecoveryFactorPoint(night: lastNight.adding(days: $0 - 199), value: Double($0), score: $0 % 100) }
        let sampled = RecoveryFactorSeriesBuilder.downsample(points)
        #expect(sampled.count == 100)
        #expect(sampled.count <= RecoveryHistoryModel.maximumChartPoints)
        #expect(sampled.last?.night == lastNight, "dated by the last night of each run")
        #expect(sampled[0].value == 0.5, "the mean of the run's values")
        let odd = RecoveryFactorSeriesBuilder.downsample((0..<121).map { RecoveryFactorPoint(night: lastNight.adding(days: $0 - 120), value: 1, score: 50) })
        #expect(odd.count == 61 && odd.count <= 120)
        let fits = (0..<90).map { RecoveryFactorPoint(night: lastNight.adding(days: $0 - 89), value: 1, score: 50) }
        #expect(RecoveryFactorSeriesBuilder.downsample(fits) == fits)
        // A run of empty nights stays empty.
        let empty = (0..<240).map { RecoveryFactorPoint(night: lastNight.adding(days: $0 - 239), value: nil, score: nil) }
        #expect(RecoveryFactorSeriesBuilder.downsample(empty).allSatisfy { $0.value == nil && $0.score == nil })
    }
}
