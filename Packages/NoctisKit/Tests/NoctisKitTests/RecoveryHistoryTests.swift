import Foundation
import Testing

@testable import HealthProviding
@testable import RecoveryKit
@testable import SleepKit

// Recovery's history engines: one score per night on its own morning,
// the stats of a window, each factor's share of the score, how far to trust
// it, and the factor series. All deterministic, from fixtures.

private let lastNight = SleepNightKey(year: 2026, month: 9, day: 23)
/// The morning after the last fixture night.
private let now = Fixture.morningAfter
private let later = Fixture.date(2026, 12, 1, 12)

/// A small deterministic generator for varied nights.
private struct Generator {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// `count` varied nights ending on Sep 23, with or without HRV and resting
/// heart rate.
private func varied(count: Int, seed: UInt64 = 7, heart: Bool = true) -> [NightMetrics] {
    var rng = Generator(state: seed)
    return Fixture.metrics(count: count) { _ in
        (
            asleep: 380 + rng.next() * 140, bedtime: 640 + rng.next() * 70, wake: 1120 + rng.next() * 50,
            hrv: heart ? 40 + rng.next() * 20 : nil, resting: heart ? 52 + rng.next() * 8 : nil
        )
    }
}

/// `count` identical nights.
private func steady(count: Int, hrv: Double? = 50, resting: Double? = 55) -> [NightMetrics] {
    Fixture.metrics(count: count) { _ in (asleep: 480, bedtime: 660, wake: 1140, hrv: hrv, resting: resting) }
}

private func scores(_ history: [NightMetrics], need: Double = 480, asOf: Date = now) -> [RecoveryDayScore] {
    RecoveryHistoryEngine.scores(history: history, needMinutes: need, asOf: asOf)
}

/// A scored day by hand, for stats.
private func day(_ index: Int, _ score: Int) -> RecoveryDayScore {
    let night = SleepNightKey(year: 2026, month: 8, day: 1).adding(days: index)
    return RecoveryDayScore(
        night: night, date: Fixture.date(2026, 8, 2, 7).addingTimeInterval(Double(index) * 86400), score: score, confidence: .high, factorScores: [],
        capApplied: false, asleepMinutes: 450)
}

// MARK: - One score per night

struct RecoveryHistoryScoresTests {
    @Test func everyNightAfterTheLearningPhaseHasOneScoreAndTheEarlyOnesHaveNone() throws {
        let history = varied(count: 12)
        let result = scores(history)
        // The first four nights were learning (under 5 up to and including them).
        #expect(result.count == 8)
        #expect(result.first?.night == history[4].night)
        #expect(result.last?.night == lastNight)
        #expect(result.map(\.night) == result.map(\.night).sorted())
        #expect(Set(result.map(\.night)).count == result.count)
    }

    @Test func aNightWhoseScoreWasTodaysIsTheSameScore() throws {
        let history = varied(count: 30)
        let today = try #require(
            { () -> RecoveryResult? in
                if case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: now) { return result }
                return nil
            }())
        let last = try #require(scores(history).last)
        #expect(last.score == today.score)
        #expect(last.factorScores.map(\.kind) == RecoveryFactorKind.allCases.filter { today.factor($0) != nil })
        #expect(last.factorScores.allSatisfy { today.factor($0.kind)?.score == $0.score })
        #expect(last.capApplied == today.heartCapApplied)
        #expect(last.confidence == today.confidence)
    }

    @Test func addingLaterNightsNeverChangesAnEarlierNightsScore() {
        let all = varied(count: 40)
        let first30 = Array(all.prefix(30))
        let early = scores(first30, asOf: later)
        let full = scores(all, asOf: later)
        #expect(early.count == 26)
        #expect(Array(full.prefix(early.count)) == early)
        // And the other direction: a night from the future isn't there yet.
        let untilThen = scores(all, asOf: first30.last?.wakeTime ?? now)
        #expect(untilThen == early)
    }

    @Test func aNightStillInProgressHasNoScore() {
        let history = varied(count: 10)
        let beforeWake = Fixture.date(2026, 9, 24, 6)
        let result = scores(history, asOf: beforeWake)
        #expect(result.last?.night == lastNight.adding(days: -1))
    }

    @Test func aSteadyPersonScoresTheSameEveryNight() {
        // Duration at need (100), consistency on baseline (100), heart signals on
        // baseline (75 each): 0.35·100 + 0.2·100 + 0.25·75 + 0.2·75 = 88.75.
        let result = scores(steady(count: 20))
        #expect(result.count == 16)
        // The first scored night has only four before it: no baselines yet, so
        // only its duration counts.
        #expect(result.first?.factorScores.map(\.kind) == [.sleepDuration])
        #expect(Set(result.dropFirst().map(\.score)) == [89])
    }

    @Test func aSleepOnlyHistoryScoresOnTwoFactors() throws {
        let result = scores(varied(count: 20, heart: false))
        let last = try #require(result.last)
        #expect(last.factorScores.map(\.kind) == [.sleepDuration, .sleepConsistency])
        #expect(last.confidence == .low)
    }

    @Test func nightsAcrossADaylightSavingChangeAreConsecutiveAndScoredOnTheClock() throws {
        // 11:00 PM to 6:30 AM by the clock every night, October 20 to November 10
        // in New York; the clocks go back on November 1.
        let zone = Fixture.newYork
        var samples: [RawSleepSample] = []
        for offset in 0..<22 {
            let night = SleepNightKey(year: 2026, month: 10, day: 20).adding(days: offset)
            let wake = night.adding(days: 1)
            samples.append(Fixture.sample(Fixture.date(night.year, night.month, night.day, 23), Fixture.date(wake.year, wake.month, wake.day, 6, 30)))
        }
        let sessions = SleepSessionEngine.history(from: samples, asOf: Fixture.date(2026, 11, 12, 12), timeZone: zone)
        let metrics = NightMetricsBuilder.metrics(for: sessions, hrv: [], restingHeartRate: [])
        #expect(metrics.count == 22)
        let keys = metrics.map(\.night)
        #expect(zip(keys, keys.dropFirst()).allSatisfy { $1.days(from: $0) == 1 }, "no night is skipped or doubled")
        #expect(metrics.allSatisfy { $0.bedtimeMinutes == 660 && $0.wakeMinutes == 1110 }, "clock times don't move with the extra hour")
        // The night of the change is an hour longer; a need under both keeps duration at 100.
        let result = RecoveryHistoryEngine.scores(history: metrics, needMinutes: 400, asOf: Fixture.date(2026, 11, 12, 12))
        #expect(result.count == 18)
        #expect(Set(result.map(\.score)) == [100])
    }
}

// MARK: - Windows and stats

struct RecoveryHistoryWindowTests {
    @Test func eachRangeIsItsNumberOfNightsEndingOnTheNewest() {
        let all = scores(varied(count: 120))
        for range in RecoveryHistoryRange.allCases {
            let history = RecoveryHistoryEngine.history(scores: all, range: range)
            #expect(history.days.count == range.nights)
            #expect(history.days.last?.night == lastNight)
            #expect(history.days.allSatisfy { $0.score != nil })
            #expect(!history.isPartial)
            #expect(history.series.count == range.nights)
        }
    }

    @Test func aRangeLongerThanTheHistoryDrawsWhatExists() {
        let all = scores(varied(count: 12))
        #expect(all.count == 8)
        let week = RecoveryHistoryEngine.history(scores: all, range: .week)
        #expect(week.days.count == 7 && !week.isPartial)
        let month = RecoveryHistoryEngine.history(scores: all, range: .month)
        #expect(month.isPartial)
        #expect(month.spanNights == 8 && month.series.count == 8)
        #expect(month.days.first?.night == all.first?.night)
        let quarter = RecoveryHistoryEngine.history(scores: all, range: .quarter)
        #expect(quarter.spanNights == 8)
    }

    @Test func aGapInsideTheWindowIsADayWithoutAScore() {
        let history = varied(count: 30)
        let holes = history.enumerated().filter { $0.offset != 20 }.map(\.element)
        let result = RecoveryHistoryEngine.history(scores: scores(holes), range: .month)
        let gap = result.days.first { $0.night == history[20].night }
        #expect(gap?.score == nil)
        #expect(result.days.count == 26, "from the first scored night")
        #expect(result.series.count == 25)
    }

    @Test func noScoresIsAnEmptyHistory() {
        let result = RecoveryHistoryEngine.history(scores: [], range: .week)
        #expect(result.days.isEmpty && result.series.isEmpty)
        #expect(result.stats.current == nil && result.stats.average == nil && result.stats.scoredDays == 0)
    }

    @Test func theStatsCarryTheCurrentAverageHighLowAndTheirDates() throws {
        let all = (0..<10).map { day($0, [70, 70, 70, 70, 70, 70, 66, 80, 62, 75][$0]) }
        let stats = RecoveryHistoryEngine.history(scores: all, range: .week).stats
        #expect(stats.current?.score == 75)
        // The last seven: 70, 66, 80, 62, 75 and the two 70s before them.
        let window = Array(all.suffix(7)).map(\.score)
        #expect(abs((stats.average ?? 0) - Double(window.reduce(0, +)) / 7) < 1e-9)
        #expect(stats.high?.score == 80 && stats.high?.night == all[7].night && stats.high?.date == all[7].date)
        #expect(stats.low?.score == 62 && stats.low?.night == all[8].night)
        #expect(stats.scoredDays == 7)
    }

    @Test func aTieForHighestOrLowestGoesToTheLaterNight() {
        let all = [70, 80, 60, 80, 60, 70, 70].enumerated().map { day($0.offset, $0.element) }
        let stats = RecoveryHistoryEngine.history(scores: all, range: .week).stats
        #expect(stats.high?.night == all[3].night)
        #expect(stats.low?.night == all[4].night)
    }

    @Test func theBaselineIsTheFourteenNightsBeforeTheNewestAndNeedsFiveNights() throws {
        // 14 steady 70s, then a 75.
        let all = (0..<15).map { day($0, $0 < 14 ? 70 : 75) }
        let stats = RecoveryHistoryEngine.history(scores: all, range: .quarter).stats
        let baseline = try #require(stats.baseline)
        #expect(baseline.value == 70 && baseline.nights == 14 && baseline.standardDeviation == 0)
        // Under 5 nights before the newest: none.
        let short = (0..<5).map { day($0, 70) }
        #expect(RecoveryHistoryEngine.history(scores: short, range: .week).stats.baseline == nil)
        #expect(RecoveryHistoryEngine.history(scores: short, range: .week).stats.usualRange == nil)
        #expect(RecoveryHistoryEngine.history(scores: short + [day(5, 70)], range: .week).stats.baseline != nil)
    }

    @Test func daysInTheUsualRangeCountsTheWindowsDaysInsideBaselinePlusOrMinusOneSD() throws {
        // Baseline 70 with no spread: the floor (3) makes the range 67...73.
        let all = (0..<15).map { day($0, $0 < 14 ? 70 : 75) }
        let week = RecoveryHistoryEngine.history(scores: all, range: .week).stats
        #expect(week.usualRange == 67...73)
        #expect(week.daysInUsualRange == 6, "six 70s, and today's 75 is outside")
        let quarter = RecoveryHistoryEngine.history(scores: all, range: .quarter).stats
        #expect(quarter.daysInUsualRange == 14)
        // A real spread: 60 and 80 alternating around 70 (SD ≈ 10.5).
        let wide = (0..<15).map { day($0, $0 < 14 ? ($0.isMultiple(of: 2) ? 60 : 80) : 84) }
        let stats = RecoveryHistoryEngine.history(scores: wide, range: .quarter).stats
        let baseline = try #require(stats.baseline)
        let spread = max(baseline.standardDeviation, RecoveryHistoryModel.scoreSpreadFloor)
        #expect(stats.usualRange == (baseline.value - spread)...(baseline.value + spread))
        #expect(stats.daysInUsualRange == wide.filter { abs(Double($0.score) - baseline.value) <= spread }.count)
    }
}

// MARK: - Trend

struct RecoveryTrendTests {
    @Test func theThresholdsAreExactlyPlusAndMinusOnePointFivePerWeek() {
        #expect(RecoveryHistoryEngine.trend(pointsPerWeek: 1.5).direction == .rising)
        #expect(RecoveryHistoryEngine.trend(pointsPerWeek: -1.5).direction == .lower)
        #expect(RecoveryHistoryEngine.trend(pointsPerWeek: 1.49).direction == .steady)
        #expect(RecoveryHistoryEngine.trend(pointsPerWeek: -1.49).direction == .steady)
        #expect(RecoveryHistoryEngine.trend(pointsPerWeek: 1.4949).direction == .steady)
        #expect(RecoveryHistoryEngine.trend(pointsPerWeek: 0).direction == .steady)
        #expect(RecoveryHistoryEngine.trend(pointsPerWeek: 12).direction == .rising)
        #expect(RecoveryHistoryEngine.trend(pointsPerWeek: -12).direction == .lower)
    }

    @Test func aLineOfExactlyOnePointFivePerWeekIsRisingAndItsNegativeIsLower() throws {
        let rising = (0..<10).map { (day: $0, score: 60 + Double($0) * 1.5 / 7) }
        let slope = try #require(RecoveryHistoryEngine.slopePerWeek(points: rising))
        #expect(abs(slope - 1.5) < 1e-9)
        #expect(RecoveryHistoryEngine.trend(points: rising)?.direction == .rising)
        let falling = (0..<10).map { (day: $0, score: 80 - Double($0) * 1.5 / 7) }
        #expect(RecoveryHistoryEngine.trend(points: falling)?.direction == .lower)
        let barely = (0..<10).map { (day: $0, score: 60 + Double($0) * 1.4 / 7) }
        #expect(RecoveryHistoryEngine.trend(points: barely)?.direction == .steady)
    }

    @Test func theSlopeUsesCalendarDaysSoAGapDoesNotStretchIt() throws {
        // A point a day for 3 days, a gap, then two more: 5 points on days 0, 1, 2, 5, 6.
        let points = [(0, 60.0), (1, 61.0), (2, 62.0), (5, 65.0), (6, 66.0)].map { (day: $0.0, score: $0.1) }
        let slope = try #require(RecoveryHistoryEngine.slopePerWeek(points: points))
        #expect(abs(slope - 7) < 1e-9, "one point a day is seven a week")
    }

    @Test func underFiveScoredDaysThereIsNoTrend() {
        #expect(RecoveryHistoryEngine.trend(points: (0..<4).map { (day: $0, score: 60 + Double($0) * 5) }) == nil)
        #expect(RecoveryHistoryEngine.trend(points: (0..<5).map { (day: $0, score: 60 + Double($0) * 5) }) != nil)
        #expect(RecoveryHistoryEngine.trend(points: []) == nil)
        // Five points on one day have no slope.
        #expect(RecoveryHistoryEngine.slopePerWeek(points: Array(repeating: (day: 3, score: 70.0), count: 5)) == nil)
    }

    @Test func aWindowsStatsCarryItsTrend() throws {
        let rising = (0..<14).map { day($0, 60 + $0) }
        let stats = RecoveryHistoryEngine.history(scores: rising, range: .month).stats
        let trend = try #require(stats.trend)
        #expect(trend.direction == .rising && abs(trend.pointsPerWeek - 7) < 1e-9)
        #expect(RecoveryHistoryEngine.history(scores: (0..<14).map { day($0, 80 - $0) }, range: .month).stats.trend?.direction == .lower)
        #expect(RecoveryHistoryEngine.history(scores: (0..<14).map { day($0, 70) }, range: .month).stats.trend?.direction == .steady)
        #expect(RecoveryHistoryEngine.history(scores: (0..<4).map { day($0, 70) }, range: .month).stats.trend == nil)
    }
}
