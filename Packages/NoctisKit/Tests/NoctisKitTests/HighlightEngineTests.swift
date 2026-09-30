import Foundation
import Testing
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepKit

/// Personal highlights are only ever true: enough nights to compare with,
/// and a strict win (a tie is not a record).
struct SleepHighlightsEngineTests {
    private let last = SleepNightKey(year: 2026, month: 9, day: 29)

    /// `count` nights ending on `last`, oldest first.
    private func nights(
        count: Int,
        asleep: (Int) -> Double = { _ in 420 },
        bedtime: (Int) -> Double = { _ in 660 },
        deep: ((Int) -> Double?)? = { _ in 60 }
    ) -> [SleepMetrics] {
        (0..<count).map { index in
            let night = last.adding(days: -(count - 1 - index))
            let slept = asleep(index)
            let stages = deep?(index).map { SleepStageBreakdown(deep: $0, core: slept - $0 - 90, rem: 90, awake: 10) }
            return SleepMetrics(
                night: night, asleepMinutes: slept, timeInBedMinutes: slept + 15, efficiency: nil, awakenings: 1,
                awakeAfterOnsetMinutes: nil, onsetLatencyMinutes: nil, stages: stages,
                bedtimeMinutes: bedtime(index), wakeMinutes: bedtime(index) + slept
            )
        }
    }

    @Test func theLongestNightInThirtyIsOnlyClaimedOnAStrictWin() {
        let history = nights(count: 30, asleep: { $0 == 29 ? 480 : 420 + Double($0 % 5) })
        #expect(SleepHighlightsEngine.highlights(metrics: history, endingAt: last).contains(.longestNight))
        // Tied with another night: not a record.
        let tied = nights(count: 30, asleep: { $0 == 29 || $0 == 10 ? 480 : 420 })
        #expect(!SleepHighlightsEngine.highlights(metrics: tied, endingAt: last).contains(.longestNight))
        // Not the longest.
        let shorter = nights(count: 30, asleep: { $0 == 20 ? 500 : ($0 == 29 ? 480 : 420) })
        #expect(!SleepHighlightsEngine.highlights(metrics: shorter, endingAt: last).contains(.longestNight))
    }

    @Test func aHighlightNeedsEnoughNightsToCompareWith() {
        // 13 nights: one short of the minimum.
        let few = nights(count: 13, asleep: { $0 == 12 ? 480 : 420 })
        #expect(SleepHighlightsEngine.highlights(metrics: few, endingAt: last).isEmpty)
        let enough = nights(count: 14, asleep: { $0 == 13 ? 480 : 420 })
        #expect(SleepHighlightsEngine.highlights(metrics: enough, endingAt: last).contains(.longestNight))
    }

    @Test func aNightOnlyCompetesWithinItsThirtyNights() {
        // A longer night 31 nights back doesn't count against last night.
        let history = nights(count: 40, asleep: { $0 == 39 ? 480 : ($0 == 8 ? 600 : 420 + Double($0 % 3)) })
        #expect(SleepHighlightsEngine.highlights(metrics: history, endingAt: last).contains(.longestNight))
    }

    @Test func bestDeepSleepIsAmongTheNightsThatHaveStagesAndNeedsStrictlyMore() {
        let history = nights(count: 30, deep: { $0 == 29 ? 110 : 60 + Double($0 % 7) })
        #expect(SleepHighlightsEngine.highlights(metrics: history, endingAt: last).contains(.bestDeepSleep))
        let tied = nights(count: 30, deep: { $0 == 29 || $0 == 3 ? 110 : 60 })
        #expect(!SleepHighlightsEngine.highlights(metrics: tied, endingAt: last).contains(.bestDeepSleep))
        // Nights without stages aren't compared, and too few staged nights claim nothing.
        let unstaged = nights(count: 30, deep: { $0 == 29 ? 110 : ($0 < 20 ? nil : 60) })
        #expect(!SleepHighlightsEngine.highlights(metrics: unstaged, endingAt: last).contains(.bestDeepSleep), "only 10 staged nights")
        let noStagesTonight = nights(count: 30, deep: { $0 == 29 ? nil : 60 })
        #expect(!SleepHighlightsEngine.highlights(metrics: noStagesTonight, endingAt: last).contains(.bestDeepSleep))
    }

    @Test func theMostConsistentWeekYetIsTheSteadiestBedtimeOfAnyWeekSoFar() {
        // Weeks of ±30 minutes, then a final week that is steady.
        let history = nights(count: 40, bedtime: { $0 >= 33 ? 660 : 660 + ($0 % 2 == 0 ? 30 : -30) })
        #expect(SleepHighlightsEngine.mostConsistentWeek(metrics: history, endingAt: last))
        #expect(SleepHighlightsEngine.highlights(metrics: history, endingAt: last).contains(.mostConsistentWeek))
        // A steady week earlier makes an equally steady one not "yet".
        let twice = nights(count: 40, bedtime: { ($0 >= 33 || ($0 >= 12 && $0 < 19)) ? 660 : 660 + ($0 % 2 == 0 ? 30 : -30) })
        #expect(!SleepHighlightsEngine.mostConsistentWeek(metrics: twice, endingAt: last), "tied with an earlier week")
    }

    @Test func aWeekNeedsEnoughEarlierWeeksAndFiveRecordedNights() {
        // 15 nights measure 8 earlier whole weeks (ending 1 to 8 nights back): exactly enough.
        let enough = nights(count: 15, bedtime: { $0 >= 8 ? 660 : 660 + ($0 % 2 == 0 ? 30 : -30) })
        #expect(SleepHighlightsEngine.mostConsistentWeek(metrics: enough, endingAt: last))
        let fewer = nights(count: 14, bedtime: { $0 >= 7 ? 660 : 660 + ($0 % 2 == 0 ? 30 : -30) })
        #expect(!SleepHighlightsEngine.mostConsistentWeek(metrics: fewer, endingAt: last), "7 earlier weeks")
        // Under 5 recorded nights in the week: no spread, no claim.
        let gaps = nights(count: 30, bedtime: { $0 >= 20 ? 660 : 660 + ($0 % 2 == 0 ? 30 : -30) }).enumerated().filter { !(20...25).contains($0.offset) }.map(\.element)
        #expect(SleepHighlightsEngine.bedtimeSpread(metrics: gaps, endingAt: last) == nil)
        #expect(!SleepHighlightsEngine.mostConsistentWeek(metrics: gaps, endingAt: last))
    }

    @Test func noRecordedNightMeansNoHighlights() {
        let history = nights(count: 30, asleep: { $0 == 29 ? 480 : 420 })
        let missing = SleepNightKey(year: 2026, month: 10, day: 3)
        #expect(SleepHighlightsEngine.highlights(metrics: history, endingAt: missing).isEmpty)
    }
}

struct RecoveryHighlightEngineTests {
    private let last = SleepNightKey(year: 2026, month: 9, day: 29)

    private func days(count: Int, scores: (Int) -> Int?) -> [RecoveryHistoryDay] {
        (0..<count).map { index in
            let night = last.adding(days: -(count - 1 - index))
            let score = scores(index).map {
                RecoveryDayScore(night: night, date: Date(timeIntervalSince1970: 1_790_000_000 + Double(index) * 86_400), score: $0, confidence: .high, factorScores: [], capApplied: false)
            }
            return RecoveryHistoryDay(night: night, score: score)
        }
    }

    @Test func highestInThirtyDaysNeedsAStrictWin() {
        #expect(RecoveryHighlightEngine.highlight(days: days(count: 30) { $0 == 29 ? 96 : 80 + $0 % 10 }) == .highestIn30Days)
        // Tied with another day.
        #expect(RecoveryHighlightEngine.highlight(days: days(count: 30) { $0 == 29 || $0 == 4 ? 96 : 80 }) == nil)
        // Not the highest.
        #expect(RecoveryHighlightEngine.highlight(days: days(count: 30) { $0 == 29 ? 90 : ($0 == 7 ? 95 : 80) }) == nil)
    }

    @Test func itNeedsEnoughScoredDaysAndAScoreToday() {
        #expect(RecoveryHighlightEngine.highlight(days: days(count: 13) { $0 == 12 ? 96 : 80 }) == nil, "13 days")
        #expect(RecoveryHighlightEngine.highlight(days: days(count: 14) { $0 == 13 ? 96 : 80 }) == .highestIn30Days)
        // Gaps count against the minimum: 20 days, only 9 scored.
        #expect(RecoveryHighlightEngine.highlight(days: days(count: 20) { $0 == 19 ? 96 : ($0 % 2 == 0 ? 80 : nil) }) == nil)
        // No score today.
        #expect(RecoveryHighlightEngine.highlight(days: days(count: 30) { $0 == 29 ? nil : 80 }) == nil)
        #expect(RecoveryHighlightEngine.highlight(days: []) == nil)
    }

    @Test func onlyThirtyDaysCount() {
        // A higher day 31 days back is outside the window.
        let history = days(count: 45) { $0 == 44 ? 96 : ($0 == 10 ? 99 : 80) }
        #expect(RecoveryHighlightEngine.highlight(days: history) == .highestIn30Days)
    }
}
