import Foundation
import Testing
@testable import InsightsKit
@testable import RecoveryKit
@testable import SleepKit

struct InsightEngineTests {
    /// 14 steady nights (7h asleep, 11:00 PM bedtime) and then last night.
    private func history(lastAsleep: Double = 420, lastBedtime: Double = 660, bedtimes: ((Int) -> Double)? = nil) -> [NightMetrics] {
        Fixture.metrics(count: 15) { index in
            let isLast = index == 14
            let bedtime = isLast ? lastBedtime : (bedtimes?(index) ?? 660)
            return (asleep: isLast ? lastAsleep : 420, bedtime: bedtime, wake: 1140, hrv: nil, resting: nil)
        }
    }

    private func top(_ history: [NightMetrics]) -> Insight? {
        InsightEngine.candidates(history: history, asOf: Fixture.morningAfter).first
    }

    // MARK: - Duration

    @Test func sleepThirtyMinutesShorterThanBaselineFires() throws {
        let insight = try #require(top(history(lastAsleep: 390)))
        #expect(insight.kind == .sleepDurationShift)
        #expect(insight.evidence.value == 390)
        #expect(insight.evidence.baseline == 420)
        #expect(insight.evidence.delta == -30)
        #expect(insight.evidence.baselineNights == 14)
    }

    @Test func sleepLongerThanBaselineFires() throws {
        let insight = try #require(top(history(lastAsleep: 490)))
        #expect(insight.kind == .sleepDurationShift)
    }

    @Test func underThirtyMinutesDoesNotFire() {
        // 25 minutes short: no shift, so the steady-bedtime streak shows.
        #expect(top(history(lastAsleep: 395))?.kind == .consistentBedtime)
        #expect(top(history(lastBedtime: 685))?.kind == .consistentBedtime)
    }

    // MARK: - Bedtime

    @Test func laterBedtimeFires() throws {
        let insight = try #require(top(history(lastBedtime: 715)))
        #expect(insight.kind == .bedtimeShift)
        #expect(insight.evidence.delta == 55)
    }

    @Test func earlierBedtimeFires() throws {
        let insight = try #require(top(history(lastBedtime: 600)))
        #expect(insight.kind == .bedtimeShift)
    }

    // MARK: - Streak

    @Test func fiveSteadyNightsInARowFire() throws {
        // Nights 0–9 alternate 45 minutes either side of 11:00 PM; nights
        // 10–14 (ending last night) sit on it. Only the last five are
        // within 30 minutes of the baseline.
        let history = history(bedtimes: { $0 < 10 ? ($0.isMultiple(of: 2) ? 615 : 705) : 660 })
        let insight = try #require(top(history))
        #expect(insight.kind == .consistentBedtime)
        #expect(insight.evidence.streakNights == 5)
    }

    @Test func fourSteadyNightsDoNotFire() {
        let history = history(bedtimes: { $0 < 11 ? ($0.isMultiple(of: 2) ? 705 : 615) : 660 })
        #expect(top(history) == nil)
    }

    @Test func aMissingNightBreaksTheStreak() {
        var history = history()
        history.remove(at: 11)
        // Nights 12–14: three in a row.
        #expect(top(history) == nil)
    }

    @Test func aLongSteadyRunCountsEveryNight() throws {
        let insight = try #require(top(history()))
        #expect(insight.kind == .consistentBedtime)
        #expect(insight.evidence.streakNights == 15)
    }

    // MARK: - Priority

    @Test func aShiftOutranksTheStreak() throws {
        #expect(try #require(top(history(lastAsleep: 360))).kind == .sleepDurationShift)
    }

    @Test func theLargerShiftWins() throws {
        #expect(try #require(top(history(lastAsleep: 380, lastBedtime: 720))).kind == .bedtimeShift)
        #expect(try #require(top(history(lastAsleep: 350, lastBedtime: 715))).kind == .sleepDurationShift)
    }

    @Test func durationWinsATie() throws {
        #expect(try #require(top(history(lastAsleep: 380, lastBedtime: 700))).kind == .sleepDurationShift)
    }

    // MARK: - Honesty

    @Test func nothingFiresWithoutABaseline() {
        let short = Fixture.metrics(count: 5) { index in (asleep: index == 4 ? 300 : 420, bedtime: 660, wake: 1140, hrv: nil, resting: nil) }
        #expect(top(short) == nil)
    }

    @Test func nothingFiresWithoutLastNight() {
        let later = Fixture.date(2026, 9, 25, 13)
        #expect(InsightEngine.candidates(history: history(lastAsleep: 300), asOf: later).isEmpty)
    }

    @Test func everyKindCarriesItsEvidence() throws {
        let insights = try [
            #require(top(history(lastAsleep: 300))),
            #require(top(history(lastAsleep: 500))),
            #require(top(history(lastBedtime: 740))),
            #require(top(history(lastBedtime: 580))),
            #require(top(history())),
        ]
        #expect(Set(insights.map(\.kind)) == Set(InsightKind.allCases))
        for insight in insights {
            #expect(insight.evidence.baselineNights == 14)
            #expect(insight.evidence.delta == insight.evidence.value - insight.evidence.baseline)
        }
    }

    @Test func aStreakShowsTheLastSevenNights() throws {
        // Nights 0–9 alternate 45 minutes either side; 10–14 sit on 11 PM.
        let insight = try #require(top(history(bedtimes: { $0 < 10 ? ($0.isMultiple(of: 2) ? 615 : 705) : 660 })))
        #expect(insight.evidence.recentNights.count == InsightEngine.streakWindowNights)
        // Nights 8 and 9 were 45 min off; 10–14 within.
        #expect(insight.evidence.recentNights == [false, false, true, true, true, true, true])
    }

    @Test func theSameHistoryAlwaysGivesTheSameInsight() {
        #expect(top(history(lastAsleep: 350)) == top(history(lastAsleep: 350)))
    }
}
