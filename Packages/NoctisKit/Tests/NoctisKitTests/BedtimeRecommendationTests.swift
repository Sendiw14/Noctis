import Foundation
import RecoveryKit
import SleepAnalysisKit
import SleepKit
import Testing

@testable import NightKit

/// A clock time as minutes since midnight: `clock(23, 30)` is 11:30 PM.
nonisolated func clock(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

/// The bedtime model (APP_RULES.md R30): the base, the catch-up, the gradual shift, the window,
/// the single bedtime under 7 nights, the confidence tiers, midnight and the night the clocks change.
struct BedtimeRecommendationTests {
    /// 14 nights, nothing else, unless a test says so.
    private func recommend(
        wake: Int = 7 * 60, need: Int = 8 * 60, balance: Double? = nil, usual: Int? = nil, spread: Double? = nil, nights: Int = 14, change: Int = 0
    ) -> BedtimeRecommendation {
        BedtimeRecommendationEngine.recommend(
            BedtimeInputs(wakeMinutes: wake, needMinutes: need, balanceMinutes: balance, usualBedtimeMinutes: usual, bedtimeSpreadMinutes: spread, nights: nights, clockChangeMinutes: change)
        )
    }

    // MARK: - The model

    @Test func theModelIsOneVersionedConfig() {
        #expect(BedtimeModel.current == .v1)
        #expect(BedtimeModel.current.version == "bedtime-v1")
        let p = BedtimeModel.v1.parameters
        #expect(p.minimumNights == 7)
        #expect(p.highConfidenceNights == 14)
        #expect(p.catchUpBehindMinutes == 60)
        #expect(p.catchUpShareDivisor == 4)
        #expect(p.catchUpLimitMinutes == 30)
        #expect(p.gradualDistanceMinutes == 45)
        #expect(p.gradualStepMinutes == 45)
        #expect(p.windowHalfWidthMinutes == 15)
        #expect(p.roundingMinutes == 5)
        #expect(recommend().model == "bedtime-v1")
    }

    // MARK: - The clock

    @Test func clockArithmeticWrapsAroundMidnight() {
        #expect(BedtimeClock.wrap(-30) == 1410)
        #expect(BedtimeClock.wrap(1440) == 0)
        #expect(BedtimeClock.wrap(1500) == 60)
        #expect(BedtimeClock.forward(from: clock(23), to: clock(7)) == 480)
        #expect(BedtimeClock.forward(from: clock(7), to: clock(23)) == 960)
        #expect(BedtimeClock.signedDistance(from: clock(23, 50), to: clock(0, 20)) == 30)
        #expect(BedtimeClock.signedDistance(from: clock(0, 20), to: clock(23, 50)) == -30)
        #expect(BedtimeClock.signedDistance(from: clock(22), to: clock(23)) == 60)
        #expect(BedtimeClock.rounded(17.5, to: 5) == 20)
        #expect(BedtimeClock.rounded(17.4, to: 5) == 15)
        #expect(BedtimeClock.rounded(-14, to: 5) == -15)
    }

    // MARK: - The base: wake minus need

    @Test(arguments: [
        (clock(7), clock(8), clock(23)), (clock(6, 30), clock(7, 30), clock(23)), (clock(5, 30), clock(8), clock(21, 30)), (clock(7), clock(9), clock(22)),
        (clock(4), clock(8, 30), clock(19, 30)), (clock(0, 30), clock(8), clock(16, 30)), (clock(9), clock(7, 30), clock(1, 30)), (clock(8, 15), clock(8), clock(0, 15)),
    ])
    func theBaseIsTheWakeTimeMinusTheNeed(wake: Int, need: Int, expected: Int) {
        let result = recommend(wake: wake, need: need)
        #expect(result.centerMinutes == expected)
        #expect(result.expectedSleepMinutes == need)
        #expect(result.kind == .window)
    }

    // MARK: - Catch-up

    @Test(arguments: [
        // Behind by 59: no change. By 60: a quarter, 15. Then a quarter to the nearest 5, capped at 30.
        (-59.0, 0), (-60.0, 15), (-61.0, 15), (-70.0, 20), (-80.0, 20), (-100.0, 25), (-118.0, 30), (-120.0, 30), (-121.0, 30), (-400.0, 30),
    ])
    func behindByAnHourOrMoreMovesTheCenterEarlier(balance: Double, shift: Int) {
        let result = recommend(balance: balance)
        #expect(result.catchUpMinutes == shift, Comment(rawValue: "balance \(balance)"))
        #expect(result.centerMinutes == clock(23) - shift)
        #expect(result.reason(.balance)?.shiftMinutes == -shift)
        #expect(result.reason(.balance)?.value == balance)
    }

    @Test(arguments: [0.0, 5, 90, 600])
    func aheadOrInLineChangesNothing(balance: Double) {
        let result = recommend(balance: balance)
        #expect(result.catchUpMinutes == 0)
        #expect(result.centerMinutes == clock(23))
    }

    @Test func catchUpCrossesMidnight() {
        // Wake 8:30 AM with 8h need is 12:30 AM; 30 minutes earlier is midnight.
        let result = recommend(wake: clock(8, 30), balance: -240)
        #expect(result.centerMinutes == 0)
        let crossing = recommend(wake: clock(8, 15), balance: -120)
        #expect(crossing.centerMinutes == BedtimeClock.wrap(clock(0, 15) - 30))
        #expect(crossing.centerMinutes == clock(23, 45))
    }

    // MARK: - Gradual shift

    @Test func aCenterWithin45MinutesOfTheUsualBedtimeStays() {
        // Center 11:00 PM, usual 11:45 PM: exactly 45 away.
        let later = recommend(usual: clock(23, 45))
        #expect(later.centerMinutes == clock(23))
        #expect(!later.isGradual)
        // Usual 10:15 PM: exactly 45 away the other way.
        let earlier = recommend(usual: clock(22, 15))
        #expect(earlier.centerMinutes == clock(23))
        #expect(!earlier.isGradual)
    }

    @Test func aCenter46MinutesFromTheUsualBedtimeMovesToward45() {
        // Usual 11:46 PM: the target is 46 earlier, so the center is held at usual minus 45.
        let later = recommend(usual: clock(23, 46))
        #expect(later.centerMinutes == clock(23, 1))
        #expect(later.isGradual)
        #expect(later.reason(.usualBedtime)?.shiftMinutes == 1)
        // Usual 10:14 PM: the target is 46 later.
        let earlier = recommend(usual: clock(22, 14))
        #expect(earlier.centerMinutes == clock(22, 59))
        #expect(earlier.isGradual)
        #expect(earlier.reason(.usualBedtime)?.shiftMinutes == -1)
    }

    @Test func aLargeGapIsClosedOnly45MinutesFromTheUsualBedtime() {
        // Someone who goes to bed at 1:00 AM and is told 11:00 PM goes to 12:15 AM first.
        let result = recommend(usual: clock(1))
        #expect(result.centerMinutes == clock(0, 15))
        #expect(result.isGradual)
        // Usual 10:00 PM, target 11:00 PM: 60 away, so 10:45 PM.
        let toward = recommend(usual: clock(22))
        #expect(toward.centerMinutes == clock(22, 45))
        // Usual 12:30 AM, target 11:00 PM (90 earlier): 11:45 PM.
        let acrossMidnight = recommend(usual: clock(0, 30))
        #expect(acrossMidnight.centerMinutes == clock(23, 45))
    }

    @Test func catchUpComesFirstThenTheGradualLimit() {
        // Base 11:00 PM; 2h behind pulls it to 10:30 PM; the usual 11:30 PM is 60 away from that,
        // so the center is held at usual minus 45: 10:45 PM.
        let result = recommend(balance: -120, usual: clock(23, 30))
        #expect(result.catchUpMinutes == 30)
        #expect(result.isGradual)
        #expect(result.centerMinutes == clock(22, 45))
    }

    // MARK: - Under 7 nights

    @Test(arguments: [0, 1, 5, 6])
    func underSevenNightsIsOneStartingBedtime(nights: Int) {
        let result = recommend(balance: -200, usual: clock(1), spread: 40, nights: nights)
        #expect(result.kind == .single)
        #expect(result.window == nil)
        #expect(result.centerMinutes == clock(23))
        #expect(result.expectedSleepMinutes == clock(8))
        #expect(result.confidence == .low)
        #expect(result.catchUpMinutes == 0)
        #expect(!result.isGradual)
        #expect(result.reasons.map { $0.kind } == [.sleepNeed, .wakeTime])
    }

    @Test func sevenNightsGivesAWindow() {
        let result = recommend(nights: 7)
        #expect(result.kind == .window)
        #expect(result.window != nil)
    }

    // MARK: - Rounding and the window

    @Test func theWindowIsTheCenterPlusAndMinus15Rounded() {
        let plain = recommend()
        #expect(plain.window == BedtimeWindow(startMinutes: clock(22, 45), endMinutes: clock(23, 15)))
        #expect(plain.window?.lengthMinutes == 30)
        // 7:03 AM wake: the center is 11:03 PM; its ends are 10:48 and 11:18, rounded to 10:50 and 11:20.
        let odd = recommend(wake: clock(7, 3))
        #expect(odd.centerMinutes == clock(23, 3))
        #expect(odd.window == BedtimeWindow(startMinutes: clock(22, 50), endMinutes: clock(23, 20)))
        // 7:02 AM: 10:47 and 11:17 round to 10:45 and 11:15.
        let other = recommend(wake: clock(7, 2))
        #expect(other.window == BedtimeWindow(startMinutes: clock(22, 45), endMinutes: clock(23, 15)))
    }

    @Test func theWindowCrossesMidnight() {
        let result = recommend(wake: clock(8, 5))
        #expect(result.centerMinutes == clock(0, 5))
        #expect(result.window == BedtimeWindow(startMinutes: clock(23, 50), endMinutes: clock(0, 20)))
        #expect(result.window?.lengthMinutes == 30)
    }

    @Test func expectedSleepIsMeasuredFromTheCenter() {
        // Catch-up of 15 puts the center at 10:45 PM: 8h 15m before 7:00 AM.
        let result = recommend(balance: -60)
        #expect(result.centerMinutes == clock(22, 45))
        #expect(result.expectedSleepMinutes == clock(8, 15))
    }

    // MARK: - Daylight saving

    @Test func clocksGoingForwardMeanAnEarlierBedtimeOnTheClock() {
        // The clock jumps an hour between bedtime and waking: 8 hours of sleep needs 9 hours of clock.
        let result = recommend(change: 60)
        #expect(result.centerMinutes == clock(22))
        #expect(result.expectedSleepMinutes == clock(8))
        #expect(result.window == BedtimeWindow(startMinutes: clock(21, 45), endMinutes: clock(22, 15)))
        #expect(result.clockChangeMinutes == 60)
    }

    @Test func clocksGoingBackMeanALaterBedtimeOnTheClock() {
        let result = recommend(change: -60)
        #expect(result.centerMinutes == clock(0))
        #expect(result.expectedSleepMinutes == clock(8))
        #expect(result.window == BedtimeWindow(startMinutes: clock(23, 45), endMinutes: clock(0, 15)))
    }

    @Test func theClockChangeCountsInTheExpectedSleepAfterACatchUp() {
        // Spring forward, 2h behind: the center is 9:30 PM; 9.5 hours on the clock is 8.5 hours of sleep.
        let result = recommend(balance: -120, change: 60)
        #expect(result.centerMinutes == clock(21, 30))
        #expect(result.expectedSleepMinutes == clock(8, 30))
    }

    @Test func aSingleBedtimeOnTheNightClocksChangeStillGivesTheNeed() {
        let result = recommend(nights: 3, change: 60)
        #expect(result.kind == .single)
        #expect(result.centerMinutes == clock(22))
        #expect(result.expectedSleepMinutes == clock(8))
    }

    // MARK: - Confidence (Recovery's tiers)

    @Test func everyInputAndFourteenNightsIsHigh() {
        #expect(recommend(balance: -30, usual: clock(23), nights: 14).confidence == .high)
        #expect(recommend(balance: -30, usual: clock(23), nights: 30).confidence == .high)
    }

    @Test func thirteenNightsOrAMissingInputIsModerate() {
        #expect(recommend(balance: -30, usual: clock(23), nights: 13).confidence == .moderate)
        #expect(recommend(balance: -30, usual: nil, nights: 14).confidence == .moderate)
        #expect(recommend(balance: nil, usual: clock(23), nights: 14).confidence == .moderate)
        #expect(recommend(balance: -30, usual: nil, nights: 7).confidence == .moderate)
    }

    @Test func onlyTheNeedAndTheWakeTimeIsLow() {
        #expect(recommend(balance: nil, usual: nil, nights: 14).confidence == .low)
        #expect(recommend(balance: nil, usual: nil, nights: 7).confidence == .low)
    }

    // MARK: - Reasons

    @Test func everyFactWithItsValue() {
        let result = recommend(balance: -70, usual: clock(23, 14), spread: 38)
        #expect(result.reasons.map { $0.kind } == [.sleepNeed, .wakeTime, .usualBedtime, .balance, .consistency])
        #expect(result.reason(.sleepNeed)?.value == 480)
        #expect(result.reason(.wakeTime)?.value == 420)
        #expect(result.reason(.usualBedtime)?.value == Double(clock(23, 14)))
        #expect(result.reason(.balance)?.value == -70)
        #expect(result.reason(.balance)?.shiftMinutes == -20)
        #expect(result.reason(.consistency)?.value == 38)
        #expect(result.reason(.consistency)?.shiftMinutes == 0)
    }

    @Test func theSameInputsGiveTheSameRecommendation() {
        let a = recommend(balance: -95, usual: clock(23, 40), spread: 22)
        let b = recommend(balance: -95, usual: clock(23, 40), spread: 22)
        #expect(a == b)
    }
}

/// From the engines' results to the inputs, and tonight on a calendar.
struct BedtimeInputsTests {
    private func timing(bedtimeAfterNoon: Double?, nights: Int) -> SleepTimingResult {
        SleepTimingResult(
            typicalBedtime: bedtimeAfterNoon, typicalWake: 1140, nights: nights, recentShift: nil, suggested: nil,
            night: SleepNightKey(year: 2026, month: 9, day: 29)
        )
    }

    private func balance(_ minutes: Double?) -> SleepBalanceResult {
        SleepBalanceResult(minutes: minutes, night: SleepNightKey(year: 2026, month: 9, day: 29), recordedNights: 7, series: [])
    }

    @Test func engineMinutesAfterNoonBecomeMinutesSinceMidnight() {
        #expect(BedtimeInputsBuilder.sinceMidnight(minutesAfterNoon: 660) == 23 * 60)
        #expect(BedtimeInputsBuilder.sinceMidnight(minutesAfterNoon: 750) == 30)
        #expect(BedtimeInputsBuilder.sinceMidnight(minutesAfterNoon: 0) == 12 * 60)
        #expect(BedtimeInputsBuilder.sinceMidnight(minutesAfterNoon: 705.4) == 23 * 60 + 45)
    }

    @Test func theUsualBedtimeNeedsSevenNights() {
        let six = BedtimeInputsBuilder.inputs(wakeMinutes: 420, needMinutes: 480, timing: timing(bedtimeAfterNoon: 674, nights: 6), balance: nil, consistency: nil)
        #expect(six.usualBedtimeMinutes == nil)
        #expect(six.nights == 6)
        let seven = BedtimeInputsBuilder.inputs(wakeMinutes: 420, needMinutes: 480, timing: timing(bedtimeAfterNoon: 674, nights: 7), balance: nil, consistency: nil)
        #expect(seven.usualBedtimeMinutes == 23 * 60 + 14)
        #expect(seven.nights == 7)
    }

    @Test func noTimingMeansNoNights() {
        let inputs = BedtimeInputsBuilder.inputs(wakeMinutes: 420, needMinutes: 480, timing: nil, balance: nil, consistency: nil)
        #expect(inputs.nights == 0)
        #expect(inputs.usualBedtimeMinutes == nil)
        #expect(inputs.balanceMinutes == nil)
        #expect(BedtimeRecommendationEngine.recommend(inputs).kind == .single)
    }

    @Test func theBalanceAndTheSpreadAreCarriedAsTheyAre() {
        let window = ConsistencyWindow(days: 14, nights: 14, bedtimeSD: 38.5, wakeSD: 20, durationSD: 30, bedtimeMean: 660, wakeMean: 1140, midpointMinutes: 900)
        let consistency = ConsistencyResult(windows: [window], night: SleepNightKey(year: 2026, month: 9, day: 29), lastMidpointMinutes: 900)
        let inputs = BedtimeInputsBuilder.inputs(
            wakeMinutes: 420, needMinutes: 480, timing: timing(bedtimeAfterNoon: 660, nights: 14), balance: balance(-70), consistency: consistency
        )
        #expect(inputs.balanceMinutes == -70)
        #expect(inputs.bedtimeSpreadMinutes == 38.5)
        #expect(inputs.usualBedtimeMinutes == 23 * 60)
    }
}

struct TonightClockTests {
    private func zone(_ name: String) -> TimeZone { TimeZone(identifier: name)! }

    private func parts(_ date: Date, _ timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test func aBedtimeInTheEveningIsOnTheNightsOwnDate() {
        let tz = zone("America/New_York")
        let dates = TonightClock.dates(night: SleepNightKey(year: 2026, month: 9, day: 30), bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: tz)
        let bed = parts(dates.bedtime, tz)
        let wake = parts(dates.wake, tz)
        #expect((bed.month, bed.day, bed.hour, bed.minute) == (9, 30, 23, 0))
        #expect((wake.month, wake.day, wake.hour, wake.minute) == (10, 1, 7, 0))
    }

    @Test func aBedtimeAfterMidnightIsTheNextCalendarDay() {
        let tz = zone("America/New_York")
        let dates = TonightClock.dates(night: SleepNightKey(year: 2026, month: 9, day: 30), bedtimeMinutes: 30, wakeMinutes: 8 * 60, timeZone: tz)
        let bed = parts(dates.bedtime, tz)
        let wake = parts(dates.wake, tz)
        #expect((bed.month, bed.day, bed.hour, bed.minute) == (10, 1, 0, 30))
        #expect((wake.month, wake.day, wake.hour) == (10, 1, 8))
    }

    @Test func theNightIsTheOneThatContainsNow() {
        let tz = zone("America/New_York")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 21))!
        let smallHours = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 1))!
        #expect(TonightClock.night(containing: evening, in: tz) == SleepNightKey(year: 2026, month: 9, day: 30))
        #expect(TonightClock.night(containing: smallHours, in: tz) == SleepNightKey(year: 2026, month: 9, day: 30))
    }

    @Test func tonightIsTheNightThatStartsThisEveningOrIsStillGoing() {
        let tz = zone("America/New_York")
        func tonight(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> SleepNightKey {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = tz
            return TonightClock.tonight(now: calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!, in: tz)
        }
        // From 6 AM to midnight, tonight is today's evening.
        #expect(tonight(9, 30, 6) == SleepNightKey(year: 2026, month: 9, day: 30))
        #expect(tonight(9, 30, 9) == SleepNightKey(year: 2026, month: 9, day: 30))
        #expect(tonight(9, 30, 21) == SleepNightKey(year: 2026, month: 9, day: 30))
        #expect(tonight(9, 30, 23, 59) == SleepNightKey(year: 2026, month: 9, day: 30))
        // After midnight and before 6 AM, the night that started yesterday is still tonight.
        #expect(tonight(10, 1, 0, 5) == SleepNightKey(year: 2026, month: 9, day: 30))
        #expect(tonight(10, 1, 5, 59) == SleepNightKey(year: 2026, month: 9, day: 30))
        // And across a month's end.
        #expect(tonight(10, 1, 2) == SleepNightKey(year: 2026, month: 9, day: 30))
    }

    @Test func anOrdinaryNightHasNoClockChange() {
        #expect(TonightClock.clockChangeMinutes(night: SleepNightKey(year: 2026, month: 9, day: 30), bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: zone("America/New_York")) == 0)
        #expect(TonightClock.clockChangeMinutes(night: SleepNightKey(year: 2026, month: 3, day: 9), bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: zone("America/New_York")) == 0)
    }

    @Test func theNightClocksGoForwardIsPlus60() {
        // US 2026: clocks go forward at 2:00 AM on Sunday March 8.
        let night = SleepNightKey(year: 2026, month: 3, day: 7)
        #expect(TonightClock.clockChangeMinutes(night: night, bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: zone("America/New_York")) == 60)
        #expect(TonightClock.clockChangeMinutes(night: night, bedtimeMinutes: 30, wakeMinutes: 7 * 60, timeZone: zone("America/New_York")) == 60)
        // A bedtime after the change on the new day has nothing between it and waking.
        #expect(TonightClock.clockChangeMinutes(night: night, bedtimeMinutes: 3 * 60 + 30, wakeMinutes: 10 * 60, timeZone: zone("America/New_York")) == 0)
        // Europe's change that year is on March 29.
        #expect(TonightClock.clockChangeMinutes(night: SleepNightKey(year: 2026, month: 3, day: 28), bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: zone("Europe/London")) == 60)
    }

    @Test func theNightClocksGoBackIsMinus60() {
        // US 2026: clocks go back at 2:00 AM on Sunday November 1.
        let night = SleepNightKey(year: 2026, month: 10, day: 31)
        #expect(TonightClock.clockChangeMinutes(night: night, bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: zone("America/New_York")) == -60)
    }

    @Test func aPlaceWithoutDaylightSavingNeverChanges() {
        for (year, month, day) in [(2026, 3, 7), (2026, 10, 31), (2026, 6, 15)] {
            #expect(TonightClock.clockChangeMinutes(night: SleepNightKey(year: year, month: month, day: day), bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: zone("Asia/Tokyo")) == 0)
        }
    }

    @Test func theClockChangeFeedsTheRecommendationEndToEnd() {
        let tz = zone("America/New_York")
        let change = TonightClock.clockChangeMinutes(night: SleepNightKey(year: 2026, month: 3, day: 7), bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: tz)
        let result = BedtimeRecommendationEngine.recommend(BedtimeInputs(wakeMinutes: 7 * 60, needMinutes: 8 * 60, nights: 14, clockChangeMinutes: change))
        #expect(result.centerMinutes == 22 * 60)
        #expect(result.expectedSleepMinutes == 8 * 60)
    }
}
