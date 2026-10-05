import Foundation
import Testing

@testable import InsightsKit
@testable import RecoveryKit
@testable import ReviewKit
@testable import SleepAnalysisKit
@testable import SleepKit

// The review engines (APP_RULES.md R39, R18): the periods (daylight saving, a month's edge, a changed review weekday, a changed time zone), the minimum nights, every
// section of a record, the 0.5 rule, the direction rules, the previous-period guard, the next focus, determinism, and the language of every sentence.

private nonisolated func zone(_ id: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: id) ?? .gmt
    return calendar
}

private nonisolated let ny = zone("America/New_York")
private nonisolated let tokyo = zone("Asia/Tokyo")

private nonisolated func key(_ year: Int, _ month: Int, _ day: Int) -> SleepNightKey { SleepNightKey(year: year, month: month, day: day) }

private nonisolated func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0, in calendar: Calendar = ny) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
}

/// A night that ended on `morning`, with values a test can bend.
private nonisolated func night(
    _ morning: SleepNightKey, asleep: Double = 420, bedtime: Double = 660, wake: Double = 1140, recovery: Int? = nil, hrv: Double? = nil, rhr: Double? = nil, stages: ReviewStages? = nil
) -> ReviewNightInput {
    ReviewNightInput(night: ReviewPeriod.night(endingOn: morning), asleepMinutes: asleep, stages: stages, bedtimeMinutes: bedtime, wakeMinutes: wake, recoveryScore: recovery, hrv: hrv, restingHeartRate: rhr)
}

/// Every morning of `period`, with the values `make` gives for its index and date.
private nonisolated func fill(_ period: ReviewPeriod, count: Int? = nil, _ make: (Int, SleepNightKey) -> ReviewNightInput) -> [ReviewNightInput] {
    period.mornings.prefix(count ?? period.morningCount).enumerated().map { make($0.offset, $0.element) }
}

private nonisolated let week = ReviewPeriod.weekly(reviewDate: key(2026, 9, 27))
private nonisolated let reviewNow = moment(2026, 9, 27, 9)

private nonisolated func build(
    _ period: ReviewPeriod, _ nights: [ReviewNightInput], need: Int = 480, insights: [ReviewInsightInput] = [], now: Date = reviewNow
) -> ReviewResult {
    ReviewEngine.build(period: period, nights: nights, needMinutes: need, insights: insights, now: now, calendar: ny)
}

private nonisolated func build(_ nights: [ReviewNightInput], need: Int = 480, insights: [ReviewInsightInput] = [], now: Date = reviewNow) -> ReviewResult {
    build(week, nights, need: need, insights: insights, now: now)
}

private nonisolated func record(_ result: ReviewResult) -> ReviewRecord? {
    if case .record(let value) = result { value } else { nil }
}

/// A steady week, the week before it and the four weeks before that: the same every night.
private nonisolated func steadyNights(
    for period: ReviewPeriod = week, asleep: Double = 420, bedtime: Double = 660, recovery: Int? = nil
) -> [ReviewNightInput] {
    let earlier = ReviewPeriod(kind: period.kind, firstMorning: period.firstMorning.adding(days: -ReviewModel.priorNights - period.morningCount), lastMorning: period.firstMorning.adding(days: -1))
    return fill(earlier) { _, morning in night(morning, asleep: asleep, bedtime: bedtime, recovery: recovery) } + fill(period) { _, morning in night(morning, asleep: asleep, bedtime: bedtime, recovery: recovery) }
}

// MARK: - Periods

struct ReviewPeriodTests {
    @Test func aWeekIsTheSevenMorningsBeforeTheReviewDaysBegins() {
        // Sunday 27 September 2026, the default review day.
        let period = ReviewPeriod.latestWeekly(now: moment(2026, 9, 27, 9), weekday: 1, calendar: ny)
        #expect(period.firstMorning == key(2026, 9, 20) && period.lastMorning == key(2026, 9, 26) && period.morningCount == 7)
        #expect(period.id.description == "weekly-2026-09-26")
        #expect(period.mornings.count == 7 && period.mornings.first == period.firstMorning && period.mornings.last == period.lastMorning)
        #expect(period.nextMorning == key(2026, 9, 27))
        // The nights are the evenings before those mornings.
        #expect(ReviewPeriod.night(endingOn: period.firstMorning) == key(2026, 9, 19) && ReviewPeriod.night(endingOn: period.lastMorning) == key(2026, 9, 25))
    }

    @Test func theWeekHoldsUntilTheNextReviewDayBegins() {
        // Mid-week it is still last Sunday's week; Saturday 23:59:59 is; Sunday 00:00:00 starts the next.
        let sunday = ReviewPeriod.latestWeekly(now: moment(2026, 9, 30, 15), weekday: 1, calendar: ny)
        #expect(sunday.lastMorning == key(2026, 9, 26))
        let lateSaturday = ReviewPeriod.latestWeekly(now: ny.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 23, minute: 59, second: 59)) ?? Date(), weekday: 1, calendar: ny)
        #expect(lateSaturday.lastMorning == key(2026, 9, 26))
        let midnight = ReviewPeriod.latestWeekly(now: ny.date(from: DateComponents(year: 2026, month: 10, day: 4)) ?? Date(), weekday: 1, calendar: ny)
        #expect(midnight.lastMorning == key(2026, 10, 3) && midnight.firstMorning == key(2026, 9, 27))
    }

    @Test func aChangedReviewWeekdayMovesTheWeekAndNeverOverlapsTheNeighbours() {
        let now = moment(2026, 9, 30, 12)
        for weekday in 1...7 {
            let period = ReviewPeriod.latestWeekly(now: now, weekday: weekday, calendar: ny)
            #expect(period.morningCount == 7 && ny.component(.weekday, from: ny.date(from: DateComponents(year: period.nextMorning.year, month: period.nextMorning.month, day: period.nextMorning.day)) ?? now) == weekday)
            #expect(period.previous.nextMorning == period.firstMorning, "weeks tile with no gap and no overlap")
            #expect(period.previous.lastMorning.adding(days: 1) == period.firstMorning)
        }
        #expect(ReviewPeriod.latestWeekly(now: now, weekday: 2, calendar: ny).lastMorning == key(2026, 9, 27), "Monday the 28th: the 7 mornings before it")
        // A weekday that is not one is the nearest that is.
        #expect(ReviewPeriod.latestWeekly(now: now, weekday: 0, calendar: ny) == ReviewPeriod.latestWeekly(now: now, weekday: 1, calendar: ny))
        #expect(ReviewPeriod.latestWeekly(now: now, weekday: 99, calendar: ny) == ReviewPeriod.latestWeekly(now: now, weekday: 7, calendar: ny))
    }

    @Test func aWeekCanCrossAMonthAndAYear() {
        let across = ReviewPeriod.latestWeekly(now: moment(2026, 10, 4, 9), weekday: 1, calendar: ny)
        #expect(across.firstMorning == key(2026, 9, 27) && across.lastMorning == key(2026, 10, 3))
        #expect(ReviewFormat(locale: Locale(identifier: "en_US")).range(across.firstMorning, across.lastMorning) == "Sep 27 \u{2013} Oct 3")
        #expect(ReviewFormat(locale: Locale(identifier: "en_US")).range(week.firstMorning, week.lastMorning) == "Sep 20 \u{2013} 26")
        let newYear = ReviewPeriod.latestWeekly(now: moment(2027, 1, 3, 9), weekday: 1, calendar: ny)
        #expect(newYear.firstMorning == key(2026, 12, 27) && newYear.lastMorning == key(2027, 1, 2))
    }

    @Test func daylightSavingDoesNotMoveADayOrShortenAWeek() {
        // Clocks go back on Sunday 1 November 2026: that Sunday has 25 hours.
        let autumn = ReviewPeriod.latestWeekly(now: moment(2026, 11, 1, 9), weekday: 1, calendar: ny)
        #expect(autumn.firstMorning == key(2026, 10, 25) && autumn.lastMorning == key(2026, 10, 31) && autumn.morningCount == 7)
        #expect(autumn.completeAt(calendar: ny) == ny.startOfDay(for: moment(2026, 11, 1, 12)))
        let following = ReviewPeriod.latestWeekly(now: moment(2026, 11, 8, 9), weekday: 1, calendar: ny)
        #expect(following.firstMorning == key(2026, 11, 1) && following.morningCount == 7, "the week that holds the 25-hour day is still 7 mornings")
        // Clocks go forward on Sunday 8 March 2026 (a 23-hour day).
        let spring = ReviewPeriod.latestWeekly(now: moment(2026, 3, 15, 9), weekday: 1, calendar: ny)
        #expect(spring.firstMorning == key(2026, 3, 8) && spring.lastMorning == key(2026, 3, 14) && spring.morningCount == 7)
        #expect(spring.previous.lastMorning == key(2026, 3, 7))
    }

    @Test func aPeriodIsCompleteFromTheFirstMomentOfTheMorningAfterItAndNotBefore() {
        let complete = week.completeAt(calendar: ny)
        #expect(complete == ny.startOfDay(for: moment(2026, 9, 27, 12)))
        #expect(week.isComplete(at: complete, calendar: ny) && !week.isComplete(at: complete.addingTimeInterval(-1), calendar: ny))
        // The same period in another zone completes at that zone's midnight.
        #expect(week.completeAt(calendar: tokyo) == tokyo.startOfDay(for: moment(2026, 9, 27, 12, in: tokyo)) && week.completeAt(calendar: tokyo) != complete)
    }

    @Test func aChangeOfTimeZoneChangesWhichDayItIsAndNothingElse() {
        // 23:30 on Saturday in New York is already Sunday 12:30 in Tokyo: the review day has begun there, not here.
        let instant = moment(2026, 9, 26, 23, 30, in: ny)
        #expect(ReviewPeriod.latestWeekly(now: instant, weekday: 1, calendar: ny).lastMorning == key(2026, 9, 19))
        #expect(ReviewPeriod.latestWeekly(now: instant, weekday: 1, calendar: tokyo).lastMorning == key(2026, 9, 26))
        // A period is plain dates: its length and its ids do not depend on the zone it is read in.
        #expect(week.morningCount == 7 && week.id.description == "weekly-2026-09-26")
    }

    @Test func aMonthIsThePreviousCalendarMonthsMornings() {
        let september = ReviewPeriod.latestMonthly(now: moment(2026, 10, 5, 9), calendar: ny)
        #expect(september.firstMorning == key(2026, 9, 1) && september.lastMorning == key(2026, 9, 30) && september.morningCount == 30)
        #expect(september.id.description == "monthly-2026-09-30" && september.nextMorning == key(2026, 10, 1))
        #expect(ReviewPeriod.latestMonthly(now: moment(2026, 10, 1, 0, 30), calendar: ny) == september, "from the first moment of the month")
        #expect(ReviewPeriod.latestMonthly(now: moment(2026, 9, 30, 23, 59), calendar: ny).lastMorning == key(2026, 8, 31))
        #expect(ReviewPeriod.monthly(year: 2028, month: 2).morningCount == 29 && ReviewPeriod.monthly(year: 2027, month: 2).morningCount == 28, "leap years")
        #expect(ReviewPeriod.monthly(year: 2026, month: 12).lastMorning == key(2026, 12, 31))
        let december = ReviewPeriod.latestMonthly(now: moment(2027, 1, 3, 9), calendar: ny)
        #expect(december.firstMorning == key(2026, 12, 1) && december.lastMorning == key(2026, 12, 31), "across the year")
        #expect(december.previous.firstMorning == key(2026, 11, 1) && december.previous.lastMorning == key(2026, 11, 30))
        #expect(ReviewPeriod.monthly(year: 2027, month: 1).previous.lastMorning == key(2026, 12, 31))
    }

    @Test func aPeriodComesBackFromItsId() throws {
        for period in [week, ReviewPeriod.monthly(year: 2026, month: 9), ReviewPeriod.weekly(reviewDate: key(2026, 10, 4))] {
            let id = try #require(ReviewID(period.id.description))
            #expect(id == period.id && ReviewPeriod(id) == period)
        }
    }

    @Test func anIdThatNamesNoPeriodIsNoPeriod() throws {
        // Well formed, and still not a period: a month ends on its last day; a week can end on any.
        #expect(ReviewPeriod.period(for: try #require(ReviewID("monthly-2026-09-15"))) == nil)
        #expect(ReviewPeriod.period(for: try #require(ReviewID("monthly-2026-09-30"))) == ReviewPeriod.monthly(year: 2026, month: 9))
        #expect(ReviewPeriod.period(for: try #require(ReviewID("weekly-2026-09-15"))) == ReviewPeriod.weekly(reviewDate: key(2026, 9, 16)))
    }

    @Test func anIdFromOutsideIsNeverTrusted() {
        let bad = [
            "", "weekly", "weekly-", "weekly-2026-09", "weekly-2026-9-26", "weekly-2026-09-6", "daily-2026-09-26", "Weekly-2026-09-26", "weekly-2026-02-30",
            "weekly-2026-13-01", "weekly-2026-00-10", "monthly-2026-04-31", "weekly-1999-09-26", "weekly-2026-09-26-extra", "weekly--2026-09-26", "weekly-2026-09-26\n",
            "weekly-../../2026", "monthly-2026-09-30 ", String(repeating: "a", count: 4000),
        ]
        for text in bad { #expect(ReviewID(text) == nil, Comment(rawValue: text.prefix(40).description)) }
    }
}

// MARK: - The minimum

struct ReviewMinimumTests {
    @Test func aWeekNeedsFiveOfItsSevenNights() {
        for count in [0, 3, 4] {
            #expect(build(fill(week, count: count) { _, m in night(m) }) == .notEnoughNights(have: count, need: 5), Comment(rawValue: "\(count)"))
        }
        for count in [5, 6, 7] { #expect(record(build(fill(week, count: count) { _, m in night(m) })) != nil, Comment(rawValue: "\(count)")) }
    }

    @Test func aMonthNeedsTwentyNights() {
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        #expect(build(month, fill(month, count: 19) { _, m in night(m) }, now: moment(2026, 10, 2)) == .notEnoughNights(have: 19, need: 20))
        #expect(record(build(month, fill(month, count: 20) { _, m in night(m) }, now: moment(2026, 10, 2))) != nil)
        #expect(ReviewKind.weekly.minimumNights == 5 && ReviewKind.monthly.minimumNights == 20)
    }

    @Test func nightsOutsideThePeriodNeverCountTowardIt() {
        let others = fill(week.previous) { _, m in night(m) } + fill(ReviewPeriod.weekly(reviewDate: key(2026, 10, 4))) { _, m in night(m) }
        #expect(build(fill(week, count: 4) { _, m in night(m) } + others) == .notEnoughNights(have: 4, need: 5))
    }

    @Test func aNightRepeatedIsOneNight() {
        let nights = fill(week, count: 4) { _, m in night(m) }
        #expect(build(nights + nights) == .notEnoughNights(have: 4, need: 5))
    }
}

// MARK: - The sections

struct ReviewSectionTests {
    private func weekRecord(_ nights: [ReviewNightInput], need: Int = 480) throws -> ReviewRecord {
        try #require(record(build(nights, need: need)))
    }

    @Test func sleepIsTheAverageTheNightsThatMetTheNeedAndTheChange() throws {
        let nights = fill(week.previous) { _, m in night(m, asleep: 400) } + fill(week) { index, m in night(m, asleep: [480, 500, 400, 420, 470, 480, 450][index]) }
        let result = try weekRecord(nights)
        #expect(abs(result.sleep.averageMinutes - 457.142857) < 0.001)
        #expect(result.sleep.nightsReachedNeed == 3 && result.sleep.needMinutes == 480)
        let delta = try #require(result.sleep.deltaMinutes)
        #expect(abs(delta - 57.142857) < 0.001)
        #expect(result.nightsRecorded == 7 && result.nightsInPeriod == 7 && result.hasComparison)
        #expect(result.nights.count == 7 && result.nights.map(\.asleepMinutes) == [480, 500, 400, 420, 470, 480, 450])
    }

    @Test func consistencyIsTheBaselineEnginesDeviation() throws {
        let bedtimes: [Double] = [660, 690, 720, 650, 700, 640, 680]
        let nights = fill(week) { index, m in night(m, bedtime: bedtimes[index], wake: 1140 + Double(index * 5)) }
        let result = try weekRecord(nights)
        let expected = try #require(BaselineEngine.baseline(bedtimes)).standardDeviation
        #expect(result.consistency.bedtimeSD == expected)
        #expect(result.consistency.wakeSD == (try #require(BaselineEngine.baseline((0..<7).map { 1140 + Double($0 * 5) }))).standardDeviation)
        #expect(result.consistency.bedtimeSDDelta == nil && !result.hasComparison, "no previous week: nothing to compare")
    }

    @Test func timingIsTheMedianAndTheShiftFromTheWeekBefore() throws {
        let nights = fill(week.previous) { _, m in night(m, bedtime: 660, wake: 1140) } + fill(week) { index, m in night(m, bedtime: [700, 705, 710, 715, 720, 900, 690][index], wake: 1150) }
        let result = try weekRecord(nights)
        #expect(result.timing.medianBedtimeMinutes == 710 && result.timing.medianWakeMinutes == 1150)
        #expect(result.timing.bedtimeShift == 50 && result.timing.wakeShift == 10)
        // An even month has the mean of its two middle nights.
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        let monthRecord = try #require(record(build(month, fill(month) { index, m in night(m, bedtime: Double(600 + index)) }, now: moment(2026, 10, 2))))
        #expect(monthRecord.timing.medianBedtimeMinutes == 614.5)
    }

    @Test func recoveryIsTheScoredNightsWithTheirHighAndLowAndTheLaterNightWinsATie() throws {
        let scores = [70, 82, 82, 60, 60, 75, 70]
        let nights = fill(week.previous) { _, m in night(m, recovery: 65) } + fill(week) { index, m in night(m, recovery: scores[index]) }
        let recovery = try #require(try weekRecord(nights).recovery)
        #expect(abs(recovery.average - 71.285714) < 0.001 && recovery.scoredNights == 7)
        #expect(recovery.high == ReviewExtreme(value: 82, morning: week.mornings[2], alsoOn: 1), "the 82 on the later of the two nights")
        #expect(recovery.low == ReviewExtreme(value: 60, morning: week.mornings[4], alsoOn: 1))
        #expect(abs(try #require(recovery.delta) - 6.285714) < 0.001)
    }

    @Test func theRecoveryTrendIsTheHistoryEnginesAndNeedsFiveScoredNights() throws {
        let rising = try #require(try weekRecord(fill(week) { index, m in night(m, recovery: 60 + index * 3) }).recovery)
        #expect(rising.trend?.direction == .rising)
        let falling = try #require(try weekRecord(fill(week) { index, m in night(m, recovery: 80 - index * 3) }).recovery)
        #expect(falling.trend?.direction == .lower)
        let flat = try #require(try weekRecord(fill(week) { _, m in night(m, recovery: 70) }).recovery)
        #expect(flat.trend?.direction == .steady)
        let points = (0..<7).map { (day: $0, score: Double(60 + $0 * 3)) }
        #expect(rising.trend == RecoveryHistoryEngine.trend(points: points), "the same trend, not a second one")
        // Four scored nights is not enough for a recovery section at all.
        #expect(try weekRecord(fill(week) { index, m in night(m, recovery: index < 4 ? 70 : nil) }).recovery == nil)
    }

    @Test func heartNumbersAreAveragesOfFiveOrMoreNights() throws {
        let nights = fill(week.previous) { _, m in night(m, hrv: 50, rhr: 56) } + fill(week) { index, m in night(m, hrv: index < 5 ? 55 : nil, rhr: index < 4 ? 54 : nil) }
        let heart = try weekRecord(nights).heart
        #expect(heart.hrvAverage == 55 && heart.hrvDelta == 5)
        #expect(heart.restingHeartRateAverage == nil && heart.restingHeartRateDelta == nil, "four nights: no average")
    }

    @Test func theNightsKeepOnlyDerivedValues() throws {
        let stages = ReviewStages(deep: 74, core: 236, rem: 92)
        let result = try weekRecord(fill(week) { _, m in night(m, asleep: 402, recovery: 70, stages: stages) })
        #expect(result.nights.allSatisfy { $0.stages == stages && $0.asleepMinutes == 402 && $0.recoveryScore == 70 })
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self).lowercased()
        for word in ["sample", "source", "bundle", "journal", "coach", "device", "uuid"] { #expect(!json.contains(word), Comment(rawValue: word)) }
    }

    @Test func aMonthHasItsExtrasAndAWeekDoesNot() throws {
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        let nights = fill(month) { index, m in night(m, asleep: [420, 450, 500, 500, 430][index % 5], recovery: index % 4 == 3 ? nil : 60 + index) }
        let result = try #require(record(build(month, nights, now: moment(2026, 10, 2))))
        let extras = try #require(result.monthly)
        #expect(extras.longestNight.value == 500 && extras.longestNight.alsoOn >= 1, "ties are counted, and the latest night with the value is the date")
        #expect(extras.longestNight.morning == nights.last { $0.asleepMinutes == 500 }?.morning)
        #expect(extras.highestRecovery?.value == 89, "the 30th: 60 + 29")
        #expect(extras.recoveryRolling.count > 20 && extras.recoveryRolling.allSatisfy { $0.value >= 60 })
        #expect(try weekRecord(fill(week) { _, m in night(m, recovery: 70) }).monthly == nil)
        let unscored = try #require(record(build(month, fill(month) { _, m in night(m) }, now: moment(2026, 10, 2))))
        #expect(unscored.monthly?.highestRecovery == nil && unscored.monthly?.recoveryRolling.isEmpty == true)
    }

    @Test func aRollingAverageNeedsFourScoresInItsSevenMornings() throws {
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        // Scores only on the first three mornings of each ten: no seven-morning window has four.
        let sparse = fill(month) { index, m in night(m, recovery: index % 10 < 3 ? 70 : nil) }
        #expect(try #require(record(build(month, sparse, now: moment(2026, 10, 2)))).monthly?.recoveryRolling.isEmpty == true)
    }
}

// MARK: - The previous period

struct ReviewPreviousPeriodTests {
    @Test func nothingIsComparedWithAPreviousWeekOfFewerThanFiveNights() throws {
        for count in [0, 4] {
            let nights = fill(week.previous, count: count) { _, m in night(m, asleep: 300, recovery: 40, hrv: 30, rhr: 70) } + fill(week) { _, m in night(m, recovery: 70, hrv: 50, rhr: 55) }
            let result = try #require(record(build(nights)))
            #expect(!result.hasComparison, Comment(rawValue: "\(count)"))
            #expect(result.sleep.deltaMinutes == nil && result.consistency.bedtimeSDDelta == nil && result.consistency.wakeSDDelta == nil)
            #expect(result.timing.bedtimeShift == nil && result.timing.wakeShift == nil)
            #expect(result.recovery?.delta == nil && result.heart.hrvDelta == nil && result.heart.restingHeartRateDelta == nil)
            #expect(result.biggestImprovement == .noComparison && result.biggestChange == .noComparison, "never 'steady' without a comparison")
        }
    }

    @Test func fiveNightsBeforeIsEnoughToCompareAndFourIsNot() throws {
        func nights(_ before: Int) -> [ReviewNightInput] {
            fill(week.previous, count: before) { _, m in night(m, asleep: 400, recovery: 60) } + fill(week) { _, m in night(m, asleep: 440, recovery: 70) }
        }
        #expect(try #require(record(build(nights(5)))).sleep.deltaMinutes == 40)
        #expect(try #require(record(build(nights(4)))).sleep.deltaMinutes == nil)
        // A month: 20 before is enough, 19 is not.
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        func monthNights(_ before: Int) -> [ReviewNightInput] {
            fill(month.previous, count: before) { _, m in night(m, asleep: 400) } + fill(month) { _, m in night(m, asleep: 440) }
        }
        #expect(try #require(record(build(month, monthNights(20), now: moment(2026, 10, 2)))).sleep.deltaMinutes == 40)
        #expect(try #require(record(build(month, monthNights(19), now: moment(2026, 10, 2)))).sleep.deltaMinutes == nil)
    }
}

// MARK: - The 0.5 rule and the direction rules

struct ReviewHighlightTests {
    /// The 28 mornings before a period, as the engine reads the person's own variation: the previous period is among them.
    private func priorRange(_ period: ReviewPeriod = week) -> Range<SleepNightKey> {
        period.firstMorning.adding(days: -ReviewModel.priorNights)..<period.firstMorning
    }

    private func spread(of nights: [ReviewNightInput], _ value: (ReviewNightInput) -> Double?) throws -> Double {
        let range = priorRange()
        let values = nights.filter { range.contains($0.morning) }.compactMap(value)
        return try #require(BaselineEngine.baseline(values)).standardDeviation
    }

    private var older: [ReviewNightInput] {
        // The 28 mornings before the previous week: they alternate between 380 and 460 minutes.
        let range = ReviewPeriod(kind: .weekly, firstMorning: week.previous.firstMorning.adding(days: -ReviewModel.priorNights), lastMorning: week.previous.firstMorning.adding(days: -1))
        return fill(range) { index, m in night(m, asleep: index % 2 == 0 ? 380 : 460) }
    }

    /// The nights before the week alternate 380 and 460 (so the person's own variation in sleep is known), the week before is constant at `before`, and the week itself is
    /// constant at `step` of that variation above it. Everything else stays still.
    private func duration(step: Double, before: Double = 420, need: Int = 480) throws -> ReviewRecord {
        let history = older + fill(week.previous) { _, m in night(m, asleep: before) }
        let own = try spread(of: history) { $0.asleepMinutes }
        #expect(own > ReviewModel.floor(.duration), "the person's own variation, above the floor")
        return try #require(record(build(history + fill(week) { _, m in night(m, asleep: before + step * own) }, need: need)))
    }

    @Test func halfOfThePersonsOwnVariationIsAChangeAndJustUnderIsNot() throws {
        for (step, moves) in [(0.49, false), (0.5, true), (0.51, true), (-0.49, false), (-0.5, true)] {
            let result = try duration(step: step)
            if moves {
                guard case .change(let change) = result.biggestChange else { Issue.record("\(step) should be a change"); continue }
                #expect(change.metric == .duration && abs(abs(change.normalized) - abs(step)) < 1e-9, Comment(rawValue: "\(step)"))
            } else {
                #expect(result.biggestChange == .steady && result.biggestImprovement == .steady, Comment(rawValue: "\(step)"))
            }
        }
        #expect(ReviewEngine.passes(0.5) && !ReviewEngine.passes(0.49) && ReviewEngine.passes(-0.5) && !ReviewEngine.passes(-0.4994) && ReviewEngine.passes(0.9996))
    }

    @Test func moreSleepIsAnImprovementOnlyWhileTheSleepWasBelowTheNeed() throws {
        let belowNeed = try duration(step: 0.6, before: 420, need: 480)
        guard case .change(let improved) = belowNeed.biggestImprovement else { Issue.record("below the need, more sleep is an improvement"); return }
        #expect(improved.metric == .duration && improved.goodness > 0)
        // The same step from nights that already met the need: a change, but not an improvement.
        let metNeed = try duration(step: 0.6, before: 500, need: 480)
        #expect(metNeed.biggestImprovement == .steady)
        guard case .change(let change) = metNeed.biggestChange else { Issue.record("it is still the biggest change"); return }
        #expect(change.metric == .duration)
        // Less sleep is never an improvement.
        #expect(try duration(step: -0.8, before: 420, need: 480).biggestImprovement == .steady)
    }

    @Test func aSteadierBedtimeIsAnImprovementBecauseLowerIsBetter() throws {
        func alternating(_ range: ReviewPeriod) -> [ReviewNightInput] { fill(range) { index, m in night(m, bedtime: index % 2 == 0 ? 630 : 690) } }
        let range = ReviewPeriod(kind: .weekly, firstMorning: week.previous.firstMorning.adding(days: -ReviewModel.priorNights), lastMorning: week.previous.firstMorning.adding(days: -1))
        let steadier = try #require(record(build(alternating(range) + alternating(week.previous) + fill(week) { _, m in night(m, bedtime: 660) })))
        guard case .change(let change) = steadier.biggestImprovement else { Issue.record("a steadier bedtime is an improvement"); return }
        #expect(change.metric == .bedtimeVariation && change.normalized < 0 && change.goodness > 0)
        // And a less steady one is a change, not an improvement.
        let worse = try #require(record(build(alternating(range) + fill(week.previous) { _, m in night(m, bedtime: 660) } + alternating(week))))
        #expect(worse.biggestImprovement == .steady)
        guard case .change(let biggest) = worse.biggestChange else { Issue.record("it is the biggest change"); return }
        #expect(biggest.metric == .bedtimeVariation && biggest.goodness < 0)
    }

    @Test func aLowerRestingHeartRateIsAnImprovementAndTheBiggestChangeCanBeTheOtherWay() throws {
        let range = ReviewPeriod(kind: .weekly, firstMorning: week.previous.firstMorning.adding(days: -ReviewModel.priorNights), lastMorning: week.previous.firstMorning.adding(days: -1))
        let nights = fill(range) { index, m in night(m, recovery: index % 2 == 0 ? 66 : 74, rhr: index % 2 == 0 ? 54 : 58) }
            + fill(week.previous) { _, m in night(m, recovery: 72, rhr: 58) } + fill(week) { _, m in night(m, recovery: 60, rhr: 55.5) }
        let result = try #require(record(build(nights)))
        // Resting heart rate fell 2.5 bpm against a spread under 2; recovery fell 12 points against a spread near 4.
        guard case .change(let improvement) = result.biggestImprovement, case .change(let biggest) = result.biggestChange else { Issue.record("both exist"); return }
        #expect(improvement.metric == .restingHeartRate && improvement.goodness > 0)
        #expect(biggest.metric == .recovery && biggest.delta < 0, "the largest move was a fall in recovery, said as a change and not as an improvement")
    }

    @Test func theBiggestOfSeveralIsDecidedBySizeAgainstTheirOwnVariation() throws {
        let range = ReviewPeriod(kind: .weekly, firstMorning: week.previous.firstMorning.adding(days: -ReviewModel.priorNights), lastMorning: week.previous.firstMorning.adding(days: -1))
        let nights = fill(range) { index, m in night(m, asleep: index % 2 == 0 ? 400 : 440, recovery: index % 2 == 0 ? 60 : 80, hrv: index % 2 == 0 ? 40 : 60) }
            + fill(week.previous) { _, m in night(m, asleep: 420, recovery: 70, hrv: 50) } + fill(week) { _, m in night(m, asleep: 430, recovery: 85, hrv: 52) }
        let result = try #require(record(build(nights)))
        // Duration +10 against a spread near 18; recovery +15 against a spread near 9; HRV +2 against a spread near 9.
        guard case .change(let biggest) = result.biggestChange, case .change(let improvement) = result.biggestImprovement else { Issue.record("recovery moved most"); return }
        #expect(biggest.metric == .recovery && improvement.metric == .recovery)
    }

    @Test func aVeryStillPersonIsNeverDividedByNothing() throws {
        // Every night alike: the variation is zero, the floor stands in, and a small step cannot become a huge one.
        func steadyThenSteps(_ step: Double) -> [ReviewNightInput] {
            steadyNights(asleep: 420).map { $0.morning >= week.firstMorning ? night($0.morning, asleep: 420 + step) : $0 }
        }
        #expect(try #require(record(build(steadyThenSteps(4)))).biggestChange == .steady, "4 minutes against a floor of 15 is 0.27")
        guard case .change(let change) = try #require(record(build(steadyThenSteps(15)))).biggestChange else { Issue.record("15 against a floor of 15 is 1"); return }
        #expect(abs(change.normalized - 1) < 1e-9 && change.normalized.isFinite)
    }

    @Test func aMetricWithoutFiveNightsOfItsOwnBeforeIsLeftOutNotGuessed() throws {
        // Recovery has four scored nights before the week and seven in it: no variation can be known for it, so it is not compared; sleep still is.
        let before = fill(week.previous) { index, m in night(m, asleep: 400, recovery: index < 4 ? 60 : nil) }
        let inWeek = fill(week) { _, m in night(m, asleep: 440, recovery: 90) }
        let changes = ReviewEngine.changes(inPeriod: inWeek, before: before, prior: before)
        #expect(changes.map(\.metric) == [.duration, .bedtimeVariation])
        let result = try #require(record(build(before + inWeek)))
        #expect(result.recovery?.delta == nil, "four scored nights before: no recovery change is stated either")
        #expect(result.sleep.deltaMinutes == 40, "the plain difference in sleep is still true and still said")
    }

    @Test func steadyIsOnlySaidWhenSomethingWasComparedAndNothingMoved() throws {
        let result = try #require(record(build(steadyNights(recovery: 70))))
        #expect(result.hasComparison && result.biggestChange == .steady && result.biggestImprovement == .steady)
    }
}

// MARK: - Next focus

struct ReviewFocusTests {
    private let steadyConsistency = ReviewConsistency(bedtimeSD: 20, wakeSD: 20, bedtimeSDDelta: nil, wakeSDDelta: nil)
    private let steadyTiming = ReviewTiming(medianBedtimeMinutes: 660, medianWakeMinutes: 1140, bedtimeShift: 0, wakeShift: 0)

    private func recovery(trend: RecoveryTrendDirection?, scored: Int = 7) -> ReviewRecovery {
        ReviewRecovery(
            average: 60, scoredNights: scored, high: ReviewExtreme(value: 70, morning: week.lastMorning, alsoOn: 0), low: ReviewExtreme(value: 50, morning: week.firstMorning, alsoOn: 0),
            trend: trend.map { RecoveryHistoryTrend(direction: $0, pointsPerWeek: $0 == .lower ? -3 : 0) }, delta: nil
        )
    }

    private func focus(
        consistency: ReviewConsistency? = nil, timing: ReviewTiming? = nil, recovery: ReviewRecovery? = nil, asleep: Double = 480, need: Int = 480
    ) -> ReviewFocus {
        ReviewEngine.focus(
            period: week, inPeriod: fill(week) { _, m in night(m, asleep: asleep) }, consistency: consistency ?? steadyConsistency, timing: timing ?? steadyTiming, recovery: recovery, needMinutes: need
        )
    }

    @Test func nothingStandingOutIsKeepGoing() {
        #expect(focus() == .keepGoing)
    }

    @Test func aBedtimeThatVariedByMoreThanFortyFiveMinutesIsFirst() {
        #expect(focus(consistency: ReviewConsistency(bedtimeSD: 45.01, wakeSD: 10, bedtimeSDDelta: nil, wakeSDDelta: nil)) == .steadyBedtime(minutes: 45.01))
        #expect(focus(consistency: ReviewConsistency(bedtimeSD: 45, wakeSD: 10, bedtimeSDDelta: nil, wakeSDDelta: nil)) == .keepGoing, "over 45, not 45")
        // It outranks every other thing a week can say.
        let everything = focus(
            consistency: ReviewConsistency(bedtimeSD: 60, wakeSD: 10, bedtimeSDDelta: nil, wakeSDDelta: nil), timing: ReviewTiming(medianBedtimeMinutes: 700, medianWakeMinutes: 1140, bedtimeShift: 90, wakeShift: 0),
            recovery: recovery(trend: .lower), asleep: 300
        )
        #expect(everything == .steadyBedtime(minutes: 60))
    }

    @Test func sevenNightsSixtyMinutesOrMoreBehindTheNeedIsSecond() {
        // 7 nights of 8h51m against an 8h need are 9 minutes ahead each; 7 of 7h51 are 9 behind each = 63.
        #expect(focus(asleep: 471) == .sleepNeed(minutesBehind: 63))
        #expect(focus(asleep: 471.5) == .keepGoing, "59.5 behind is under 60")
        let exactlySixty = ReviewEngine.focus(
            period: week, inPeriod: fill(week) { index, m in night(m, asleep: index == 0 ? 420 : 480) }, consistency: steadyConsistency, timing: steadyTiming, recovery: nil, needMinutes: 480
        )
        #expect(exactlySixty == .sleepNeed(minutesBehind: 60), "60 or more")
        // It outranks a later bedtime and a lower recovery.
        let both = focus(timing: ReviewTiming(medianBedtimeMinutes: 700, medianWakeMinutes: 1140, bedtimeShift: 60, wakeShift: 0), recovery: recovery(trend: .lower), asleep: 400)
        #expect(both == .sleepNeed(minutesBehind: 560))
    }

    @Test func theBalanceNeedsFiveRecordedNightsOfTheLastSeven() {
        // Five nights, each 90 behind: counted. Four: no balance, so it is not said.
        let five = ReviewEngine.focus(period: week, inPeriod: fill(week, count: 5) { _, m in night(m, asleep: 390) }, consistency: steadyConsistency, timing: steadyTiming, recovery: nil, needMinutes: 480)
        #expect(five == .sleepNeed(minutesBehind: 450))
        // The last seven nights: five early ones that do not fall in the last seven leave only two.
        let spread = fill(week) { index, m in night(m, asleep: 300) }.enumerated().filter { $0.offset < 4 }.map(\.element)
        #expect(ReviewEngine.focus(period: week, inPeriod: spread, consistency: steadyConsistency, timing: steadyTiming, recovery: nil, needMinutes: 480) == .keepGoing)
    }

    @Test func aMedianBedtimeFortyFiveMinutesOrMoreLaterIsThird() {
        #expect(focus(timing: ReviewTiming(medianBedtimeMinutes: 700, medianWakeMinutes: 1140, bedtimeShift: 45, wakeShift: 0)) == .gentleShiftBack(minutesLater: 45))
        #expect(focus(timing: ReviewTiming(medianBedtimeMinutes: 700, medianWakeMinutes: 1140, bedtimeShift: 44.9, wakeShift: 0)) == .keepGoing)
        #expect(focus(timing: ReviewTiming(medianBedtimeMinutes: 600, medianWakeMinutes: 1140, bedtimeShift: -80, wakeShift: 0)) == .keepGoing, "earlier is not a thing to move back")
        #expect(focus(timing: ReviewTiming(medianBedtimeMinutes: 700, medianWakeMinutes: 1140, bedtimeShift: nil, wakeShift: nil)) == .keepGoing, "no previous week, no shift")
        let withRecovery = focus(timing: ReviewTiming(medianBedtimeMinutes: 700, medianWakeMinutes: 1140, bedtimeShift: 60, wakeShift: 0), recovery: recovery(trend: .lower))
        #expect(withRecovery == .gentleShiftBack(minutesLater: 60), "it outranks a lower recovery")
    }

    @Test func recoveryLowerOverFiveOrMoreNightsIsLast() {
        #expect(focus(recovery: recovery(trend: .lower, scored: 5)) == .recentNights(nights: 5))
        #expect(focus(recovery: recovery(trend: .lower, scored: 7)) == .recentNights(nights: 7))
        #expect(focus(recovery: recovery(trend: .steady)) == .keepGoing && focus(recovery: recovery(trend: .rising)) == .keepGoing)
        #expect(focus(recovery: recovery(trend: nil, scored: 4)) == .keepGoing, "under five scored nights there is no trend to read")
    }
}

// MARK: - Insights

struct ReviewInsightTests {
    private func insight(_ id: String, _ score: Double, _ moment: Date) -> ReviewInsightInput { ReviewInsightInput(id: id, generatedAt: moment, score: score) }

    @Test func aWeekPointsToTheBestRankedInsightGeneratedInsideIt() throws {
        let inside = moment(2026, 9, 23, 8)
        let list = [
            insight("b", 0.7, inside), insight("a", 0.9, inside), insight("early", 0.99, moment(2026, 9, 19, 23, 59)), insight("late", 0.99, moment(2026, 9, 27, 0, 1)),
            insight("c", 0.8, moment(2026, 9, 20, 0, 0)),
        ]
        let result = try #require(record(build(fill(week) { _, m in night(m) }, insights: list)))
        #expect(result.topInsightIDs == ["a"], "the edges are the period's: the 20th at midnight is in, the 19th and the 27th are not")
        let ties = [insight("z", 0.5, inside), insight("m", 0.5, inside), insight("m", 0.5, inside)]
        #expect(try #require(record(build(fill(week) { _, m in night(m) }, insights: ties))).topInsightIDs == ["m"], "equal scores go to the smaller id, and one id is one insight")
        #expect(try #require(record(build(fill(week) { _, m in night(m) }))).topInsightIDs.isEmpty)
    }

    @Test func aMonthPointsToTheThreeBest() throws {
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        let list = (0..<5).map { insight("i\($0)", Double($0) / 10, moment(2026, 9, 10 + $0, 8)) } + [insight("outside", 1, moment(2026, 10, 2))]
        let result = try #require(record(build(month, fill(month) { _, m in night(m) }, insights: list, now: moment(2026, 10, 2))))
        #expect(result.topInsightIDs == ["i4", "i3", "i2"])
    }

    @Test func theInsightsOwnRankingIsWhatSetsTheScore() {
        let ranked = InsightRanking.score(confidence: .high, relevance: 1, novelty: 1, actionability: 0.8)
        #expect(ranked > InsightRanking.score(confidence: .low, relevance: 1, novelty: 1, actionability: 0.8))
    }
}

// MARK: - Determinism and the record

struct ReviewRecordTests {
    private func scenario() -> [ReviewNightInput] {
        let prior = ReviewPeriod(kind: .weekly, firstMorning: week.previous.firstMorning.adding(days: -ReviewModel.priorNights), lastMorning: week.previous.firstMorning.adding(days: -1))
        return fill(prior) { index, m in night(m, asleep: 400 + Double(index % 5) * 8, bedtime: 650 + Double(index % 4) * 10, recovery: 60 + index % 9, hrv: 45 + Double(index % 6), rhr: 55 + Double(index % 3)) }
            + fill(week.previous) { index, m in night(m, asleep: 410 + Double(index) * 4, bedtime: 660, recovery: 66, hrv: 48, rhr: 56) }
            + fill(week) { index, m in night(m, asleep: 440 + Double(index) * 3, bedtime: 640, recovery: 72 + index, hrv: 53, rhr: 54, stages: ReviewStages(deep: 70, core: 240, rem: 90)) }
    }

    @Test func theSameNightsGiveTheSameRecordWhateverTheirOrder() throws {
        let nights = scenario()
        let first = try #require(record(build(nights)))
        #expect(first == (try #require(record(build(nights)))))
        #expect(first == (try #require(record(build(nights.reversed())))))
        var shuffled = nights
        var generator = SystemRandomNumberGenerator()
        shuffled.shuffle(using: &generator)
        #expect(first == (try #require(record(build(shuffled)))))
        #expect(first.generatedAt == reviewNow && first.version == ReviewRecord.currentVersion && first.id == week.id)
    }

    @Test func aRecordRoundTripsThroughJSON() throws {
        let original = try #require(record(build(scenario(), insights: [ReviewInsightInput(id: "bedtimeShift-3fa9c2d1", generatedAt: moment(2026, 9, 22), score: 0.8)])))
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ReviewRecord.self, from: data) == original)
        #expect(original.topInsightIDs == ["bedtimeShift-3fa9c2d1"])
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        let monthly = try #require(record(build(month, fill(month) { index, m in night(m, asleep: 400 + Double(index), recovery: 60 + index) }, now: moment(2026, 10, 2))))
        #expect(try JSONDecoder().decode(ReviewRecord.self, from: try JSONEncoder().encode(monthly)) == monthly)
    }

    @Test func theRecordSaysWhichPeriodItIsFor() throws {
        let result = try #require(record(build(scenario())))
        #expect(result.period == week && result.kind == .weekly && result.nightsInPeriod == 7)
        #expect(ReviewRecord.currentVersion == 2 && ReviewModel.version == "review-v2")
    }
}

// MARK: - The words

struct ReviewLanguageTests {
    private let format = ReviewFormat(locale: Locale(identifier: "en_US"))

    private func prior(_ period: ReviewPeriod) -> ReviewPeriod {
        ReviewPeriod(kind: period.kind, firstMorning: period.previous.firstMorning.adding(days: -ReviewModel.priorNights), lastMorning: period.previous.firstMorning.adding(days: -1))
    }

    /// Records for every situation a review can be in: improved, steady, nothing to compare, each next focus, a month, ties, no recovery.
    private func records() throws -> [(String, ReviewRecord)] {
        func make(_ name: String, _ period: ReviewPeriod, _ nights: [ReviewNightInput], need: Int = 480, insights: [ReviewInsightInput] = []) throws -> (String, ReviewRecord) {
            (name, try #require(record(ReviewEngine.build(period: period, nights: nights, needMinutes: need, insights: insights, now: reviewNow, calendar: ny))))
        }
        let alternating = fill(prior(week)) { index, m in night(m, asleep: index % 2 == 0 ? 380 : 460, bedtime: index % 2 == 0 ? 630 : 690, recovery: index % 2 == 0 ? 62 : 74, hrv: index % 2 == 0 ? 44 : 56, rhr: index % 2 == 0 ? 54 : 58) }
        let month = ReviewPeriod.monthly(year: 2026, month: 9)
        let monthPrior = ReviewPeriod(kind: .monthly, firstMorning: month.previous.firstMorning.adding(days: -ReviewModel.priorNights), lastMorning: month.previous.firstMorning.adding(days: -1))
        let monthAlternating = fill(monthPrior) { index, m in night(m, asleep: index % 2 == 0 ? 380 : 460, bedtime: index % 2 == 0 ? 630 : 690, recovery: index % 2 == 0 ? 62 : 74, hrv: index % 2 == 0 ? 44 : 56) }
        let stages = ReviewStages(deep: 70, core: 240, rem: 90)
        let insights = [ReviewInsightInput(id: "bedtimeShift-3fa9c2d1", generatedAt: moment(2026, 9, 22), score: 0.9)]
        return [
            try make("improved", week, alternating + fill(week.previous) { _, m in night(m, asleep: 400, bedtime: 630, recovery: 66, hrv: 48, rhr: 58) } + fill(week) { _, m in night(m, asleep: 470, bedtime: 660, recovery: 76, hrv: 55, rhr: 55, stages: stages) }, insights: insights),
            try make("worse", week, alternating + fill(week.previous) { _, m in night(m, asleep: 470, bedtime: 660, recovery: 76, hrv: 55, rhr: 55) } + fill(week) { index, m in night(m, asleep: 380, bedtime: index % 2 == 0 ? 630 : 740, recovery: 60, hrv: 44, rhr: 60) }),
            try make("steady", week, steadyNights(recovery: 70)),
            try make("noComparison", week, fill(week) { _, m in night(m, recovery: 70, hrv: 50, rhr: 55) }),
            try make("steadyBedtime", week, fill(week) { index, m in night(m, bedtime: [600, 720, 610, 740, 590, 730, 650][index]) }),
            try make("sleepNeed", week, fill(week) { _, m in night(m, asleep: 380) }),
            try make("gentleShift", week, steadyNights(asleep: 480, bedtime: 600).map { $0.morning >= week.firstMorning ? night($0.morning, asleep: 480, bedtime: 700) : $0 }),
            try make("recent", week, fill(week) { index, m in night(m, asleep: 480, recovery: 80 - index * 4) }),
            try make("keepGoing", week, fill(week) { _, m in night(m, asleep: 480) }),
            try make("tied", week, fill(week) { _, m in night(m, asleep: 480, recovery: 70) }),
            try make("monthImproved", month, monthAlternating + fill(month.previous) { _, m in night(m, asleep: 400, bedtime: 630, recovery: 66, hrv: 48) } + fill(month) { index, m in night(m, asleep: 470, bedtime: 660, recovery: 70 + index % 5, hrv: 55) }, insights: insights),
            try make("monthSparse", month, fill(month, count: 20) { _, m in night(m) }),
        ]
    }

    @Test func everyStringAReviewCanSayIsFreeOfTheBannedLanguage() throws {
        var strings: [String] = []
        for (_, record) in try records() { strings += ReviewScreenBuilder.allStrings(record, format: format) }
        let period = ReviewPeriod.latestWeekly(now: reviewNow, weekday: 1, calendar: ny)
        let notReady = ReviewScreenBuilder.notReady(period: period, have: 4, need: 5, format: format)
        strings += [notReady.title, notReady.count, notReady.detail, notReady.dateRange]
        strings += [ReviewScreenBuilder.title(kind: .weekly), ReviewScreenBuilder.title(kind: .monthly)]
        #expect(strings.count > 150, "the scan found the sentences")
        let extra = [
            "streak", "miss", "fail", "lazy", "guilt", "shame", "worse", "wrong", "only", "!", "behind your", "should", "need to", "have to", "try harder",
            "because", "caused", "due to", "led to", "leads to", "as a result", "diagnos", "symptom", "disorder",
        ]
        for text in strings {
            #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: "\"\(text)\" has \(BannedLanguage.hits(in: text, of: BannedLanguage.coach))"))
            for word in extra { #expect(!text.lowercased().contains(word), Comment(rawValue: "\"\(text)\" has \(word)")) }
        }
    }

    @Test func everySituationBuildsItsPagesFromTheNumbers() throws {
        var kinds: Set<ReviewPageContent.Kind> = []
        for (name, record) in try records() {
            let content = ReviewScreenBuilder.build(record, format: format)
            #expect(content.pages.first?.kind == .cover && content.pages.last?.kind == .nextFocus, Comment(rawValue: name))
            #expect(content.pages.allSatisfy { !$0.headline.isEmpty }, Comment(rawValue: name))
            #expect(Set(content.pages.map(\.id)).count == content.pages.count, "one page of each kind")
            kinds.formUnion(content.pages.map(\.kind))
        }
        #expect(kinds == Set(ReviewPageContent.Kind.allCases), "the scenarios reach every page")
    }

    @Test func theCoverStatesOnlyWhatTheDataSupports() throws {
        let all = try records()
        func cover(_ name: String) throws -> ReviewPageContent {
            let record = try #require(all.first { $0.0 == name }?.1)
            return try #require(ReviewScreenBuilder.build(record, format: format).page(.cover))
        }
        #expect(try cover("improved").headline.hasPrefix("Compared with the week before, "))
        #expect(try cover("steady").headline == "A steady week." && cover("steady").evidence.first == "Compared with the week before, nothing moved by much.")
        let none = try cover("noComparison")
        #expect(none.headline == "Here is your week." && none.evidence.first == "There weren't enough nights in the week before to compare it with.")
        #expect(!none.headline.contains("steady") && !none.evidence.joined().contains("improv"), "no comparison, no claim")
        // A fall is a change, said as a number, never as an improvement.
        let worse = try cover("worse")
        #expect(worse.headline == "Here is your week." && !worse.headline.contains("improv") && !worse.headline.contains("steady"))
        #expect(worse.evidence.contains { $0.hasPrefix("The biggest change was") })
        #expect(try cover("improved").evidence.contains { $0.contains("up from") || $0.contains("down from") })
    }

    @Test func aPageSaysCoincidedOnlyWhenTwoNumbersBothMoved() throws {
        let all = try records()
        let worse = try #require(all.first { $0.0 == "worse" }?.1)
        let content = ReviewScreenBuilder.build(worse, format: format)
        for page in content.pages { if let line = page.interpretation { #expect(line.contains("coincided"), Comment(rawValue: line)) } }
        let steady = try #require(all.first { $0.0 == "steady" }?.1)
        #expect(ReviewScreenBuilder.build(steady, format: format).pages.allSatisfy { $0.interpretation == nil }, "nothing moved: nothing is tied to anything")
    }

    @Test func thePlaceholderForTooFewNightsShowsTheRealCount() {
        let period = ReviewPeriod.latestWeekly(now: reviewNow, weekday: 1, calendar: ny)
        let content = ReviewScreenBuilder.notReady(period: period, have: 4, need: 5, format: format)
        #expect(content.title == "Not enough nights yet" && content.count == "4 of 5 nights so far" && content.dateRange == "Sep 20 \u{2013} 26")
        let month = ReviewScreenBuilder.notReady(period: ReviewPeriod.monthly(year: 2026, month: 9), have: 19, need: 20, format: format)
        #expect(month.count == "19 of 20 nights so far" && month.dateRange == "September 2026" && month.detail == "Your monthly review appears once there are at least 20.")
    }

    @Test func theFormatWritesDurationsDatesAndClocksInTheLanguageOfTheDay() {
        #expect(ReviewFormat.duration(402) == "6h 42m" && ReviewFormat.duration(480) == "8h" && ReviewFormat.duration(45) == "45m" && ReviewFormat.amount(-14) == "14 min" && ReviewFormat.amount(65) == "1h 5m")
        #expect(ReviewFormat.number(54) == "54" && ReviewFormat.number(7.46) == "7.5" && ReviewFormat.minutes(23.6) == "24 min")
        #expect(format.clock(minutesAfterNoon: 660).replacingOccurrences(of: "\u{202F}", with: " ") == "11:00 PM")
        #expect(format.clock(minutesAfterNoon: 1140).replacingOccurrences(of: "\u{202F}", with: " ") == "7:00 AM")
        #expect(format.day(key(2026, 9, 20)) == "Sep 20" && format.monthName(key(2026, 9, 1)) == "September" && format.monthYear(key(2026, 9, 1)) == "September 2026")
        let twentyFour = ReviewFormat(locale: Locale(identifier: "en_GB"))
        #expect(twentyFour.clock(minutesAfterNoon: 660) == "23:00")
    }
}

// MARK: - A month's major changes

struct ReviewMajorChangesTests {
    private func change(_ metric: ReviewMetric, _ normalized: Double) -> ReviewChange {
        ReviewChange(metric: metric, value: 10 + normalized, previous: 10, normalized: normalized)
    }

    @Test func theLargestChangesThatCountAreKeptThreeAtMostAndInTheMetricsOwnOrderWhenEqual() {
        let candidates = [change(.duration, 0.4), change(.bedtimeVariation, -0.5), change(.recovery, 0.5), change(.hrv, -0.9), change(.restingHeartRate, 1.2)]
        let major = ReviewEngine.majorChanges(candidates)
        #expect(major.map(\.metric) == [.restingHeartRate, .hrv, .bedtimeVariation], "1.2, 0.9, then the first of the two that are 0.5; 0.4 is not a change")
        #expect(ReviewEngine.majorChanges([change(.duration, 0.49), change(.recovery, -0.4994)]).isEmpty, "under half of the person's own variation is nothing")
        #expect(ReviewEngine.majorChanges([change(.duration, 0.5)]).count == 1 && ReviewEngine.majorChanges([]).isEmpty)
    }

    @Test func aMonthsRecordHoldsThemAndAPeriodWithNothingToCompareHoldsNone() throws {
        let nights = (0..<(28 + 62)).map { index -> ReviewNightInput in
            let morning = key(2026, 6, 1).adding(days: index)
            // Sleep gets steadily longer, so August is longer than July and the person's own variation is small.
            return ReviewNightInput(
                night: ReviewPeriod.night(endingOn: morning), asleepMinutes: 380 + Double(index) * 1.2 + Double(index % 3) * 3, bedtimeMinutes: 660, wakeMinutes: 1140,
                recoveryScore: 60 + index / 3, hrv: 40 + Double(index) / 4, restingHeartRate: 60 - Double(index) / 10
            )
        }
        let month = ReviewPeriod.monthly(year: 2026, month: 8)
        guard case .record(let record) = ReviewEngine.build(period: month, nights: nights, needMinutes: 480, now: moment(2026, 9, 2), calendar: ny) else { Issue.record("a record"); return }
        #expect(record.hasComparison && !record.topChanges.isEmpty && record.topChanges.count <= 3)
        #expect(record.topChanges.allSatisfy { ReviewEngine.passes($0.normalized) })
        #expect(record.topChanges.map { abs($0.normalized) } == record.topChanges.map { abs($0.normalized) }.sorted(by: >))
        // Without a previous month of its own, nothing is compared and nothing is listed.
        let alone = nights.filter { month.contains(morning: ReviewPeriod.morning(ofNight: $0.night)) }
        guard case .record(let first) = ReviewEngine.build(period: month, nights: alone, needMinutes: 480, now: moment(2026, 9, 2), calendar: ny) else { Issue.record("a record"); return }
        #expect(!first.hasComparison && first.topChanges.isEmpty)
    }
}
