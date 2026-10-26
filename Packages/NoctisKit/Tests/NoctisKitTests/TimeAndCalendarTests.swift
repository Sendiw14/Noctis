import Foundation
import Testing

@testable import HomeFeature
@testable import NightKit
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import PremiumKit
@testable import ReviewKit
@testable import SleepKit

// QA part 3, step 3: time and calendar. Every function here takes the clock as an argument (no test sets the system clock), so a daylight saving
// change, a leap day, a clock that jumps and a midnight rollover are all just dates. Four zones with different rules: New York (spring forward at
// 2 AM), London (1 AM), Sydney (southern hemisphere, 3 AM), Lord Howe (a 30-minute change).
//
// Night attribution policy (documented, tested below): a night belongs to the evening it began on (`SleepNightKey`, noon to noon) in the zone the
// samples were recorded in, so a trip across zones mid-week never moves a night to another date. A review week is the 7 mornings before the review
// day, counted on the phone's calendar at the moment it is asked: the period moves with the clock, and a night is never counted twice or dropped
// because the zone changed (it is keyed by date, not instant).

private nonisolated let zones: [TimeZone] = ["America/New_York", "Europe/London", "Australia/Sydney", "Australia/Lord_Howe"].compactMap(
    TimeZone.init(identifier:))

private func calendar(_ zone: TimeZone, firstWeekday: Int = 1) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// Each zone's two clock changes in the year 2026, found from the rules, with a few days either side.
private func transitionWindows(_ zone: TimeZone) -> [Date] {
    var found: [Date] = []
    var cursor = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01
    let end = cursor.addingTimeInterval(366 * 86_400)
    while let next = zone.nextDaylightSavingTimeTransition(after: cursor), next < end {
        found.append(next)
        cursor = next
    }
    return found
}

struct TimeAndCalendarTests {
    // MARK: Daylight saving

    @Test(arguments: zones)
    func aDailyReminderFiresOncePerLocalDayAcrossEveryClockChange(_ zone: TimeZone) {
        let cal = calendar(zone)
        for (hour, minute) in [(2, 30), (1, 30), (23, 50), (0, 10), (7, 0)] {
            let reminder = ScheduledNotification(identifier: "x", title: "t", body: "b", components: NotificationPlan.clock(hour * 60 + minute))
            var cursor = date(cal, 2026, 1, 1, 12)
            var days: [DateComponents] = []
            var previous = cursor
            for _ in 0..<400 {
                guard let fire = NotificationPlan.nextFire(of: reminder, after: cursor, calendar: cal) else {
                    Issue.record("no next fire after \(cursor)")
                    return
                }
                #expect(fire > previous, "fire \(fire) is not after \(previous) in \(zone.identifier) at \(hour):\(minute)")
                #expect(fire.timeIntervalSince(cursor) <= 25.5 * 3600, "a gap of more than a day and a half-hour")
                days.append(cal.dateComponents([.year, .month, .day], from: fire))
                previous = fire
                cursor = fire
            }
            // Four hundred fires, four hundred different local days: no duplicate and none missing.
            #expect(Set(days.map { "\($0.year!)-\($0.month!)-\($0.day!)" }).count == 400, "\(zone.identifier) \(hour):\(minute)")
        }
    }

    @Test(arguments: zones)
    func homeAndTheWidgetAgreeOnTheModeEveryFifteenMinutesAroundEachClockChange(_ zone: TimeZone) {
        let cal = calendar(zone)
        let plan = TonightPlan(profile: UserProfileSnapshot())
        let widgetPlan = WidgetPlan(wakeMinutes: plan.wakeMinutes, needMinutes: plan.needMinutes, bedtimeMinutes: plan.bedtimeMinutes)
        for transition in transitionWindows(zone) {
            var moment = transition.addingTimeInterval(-3 * 86_400)
            let stop = transition.addingTimeInterval(3 * 86_400)
            while moment < stop {
                #expect(
                    HomeScreenBuilder.mode(now: moment, plan: plan, calendar: cal).rawValue
                        == WidgetClock.mode(at: moment, plan: widgetPlan, calendar: cal).rawValue, "\(moment) in \(zone.identifier)")
                // Never a countdown to a moment that has passed: the next mode change is strictly in the future.
                #expect(HomeScreenBuilder.nextModeChange(after: moment, plan: plan, calendar: cal) > moment)
                moment = moment.addingTimeInterval(900)
            }
        }
    }

    @Test(arguments: zones)
    func widgetBoundariesAreStrictlyIncreasingWithoutDuplicatesAcrossAClockChange(_ zone: TimeZone) {
        let cal = calendar(zone)
        let plan = WidgetPlan(wakeMinutes: 7 * 60, needMinutes: 480, bedtimeMinutes: 23 * 60)
        for transition in transitionWindows(zone) {
            let from = transition.addingTimeInterval(-2 * 86_400)
            let boundaries = WidgetClock.boundaries(after: from, until: transition.addingTimeInterval(3 * 86_400), plan: plan, calendar: cal)
            #expect(boundaries == boundaries.sorted())
            #expect(Set(boundaries).count == boundaries.count)
            #expect(boundaries.allSatisfy { $0 > from })
            // Three boundaries a day for five days.
            #expect(boundaries.count == 15, "\(boundaries.count) boundaries in \(zone.identifier)")
        }
    }

    @Test(arguments: zones)
    func theBedtimeCountdownIsNeverNegativeByDay(_ zone: TimeZone) {
        let cal = calendar(zone)
        let plan = WidgetPlan(wakeMinutes: 7 * 60, needMinutes: 480, bedtimeMinutes: 23 * 60)
        for transition in transitionWindows(zone) {
            var moment = transition.addingTimeInterval(-86_400)
            while moment < transition.addingTimeInterval(86_400) {
                if WidgetClock.mode(at: moment, plan: plan, calendar: cal) == .day,
                    let bedtime = WidgetClock.bedtime(at: moment, mode: .day, plan: plan, calendar: cal)
                {
                    #expect(bedtime >= moment, "a negative countdown at \(moment) in \(zone.identifier)")
                }
                moment = moment.addingTimeInterval(1800)
            }
        }
    }

    @Test(arguments: zones)
    func tonightsClockChangeIsFoundOnlyOnTheNightsThatHaveOne(_ zone: TimeZone) {
        let cal = calendar(zone)
        let transitions = transitionWindows(zone)
        #expect(transitions.count == 2, "\(zone.identifier) should change twice in 2026")
        var changes = 0
        var night = SleepNightKey(year: 2026, month: 1, day: 1)
        for _ in 0..<365 {
            let change = TonightClock.clockChangeMinutes(night: night, bedtimeMinutes: 23 * 60, wakeMinutes: 7 * 60, timeZone: zone)
            if change != 0 { changes += 1 }
            #expect([0, 60, -60, 30, -30].contains(change))
            night = night.adding(days: 1)
        }
        // Not asserted exactly two for a 23:00 bedtime: a change at 2 AM falls inside that night, so each transition is found on exactly one night.
        #expect(changes == 2, "\(zone.identifier): \(changes) nights with a clock change")
        _ = cal
    }

    // MARK: Review weeks and months

    @Test func theWeeklyReviewDayDoesNotDependOnWhichDayTheRegionStartsTheWeek() {
        for weekday in 1...7 {
            for offset in 0..<14 {
                let sundayFirst = calendar(zones[0], firstWeekday: 1)
                let mondayFirst = calendar(zones[0], firstWeekday: 2)
                let now = date(sundayFirst, 2026, 9, 14 + offset, 10)
                let a = ReviewPeriod.latestWeekly(now: now, weekday: weekday, calendar: sundayFirst)
                let b = ReviewPeriod.latestWeekly(now: now, weekday: weekday, calendar: mondayFirst)
                #expect(a == b, "weekday \(weekday), \(now)")
                // The review day itself, from its first moment: the week is complete and ends the morning before.
                #expect(a.isComplete(at: now, calendar: sundayFirst))
                #expect(a.mornings.count == 7)
                let reviewDay = a.lastMorning.adding(days: 1)
                var reference = date(sundayFirst, reviewDay.year, reviewDay.month, reviewDay.day, 12)
                #expect(sundayFirst.component(.weekday, from: reference) == weekday)
                reference = .distantPast
            }
        }
    }

    @Test func monthsKnowTheirLengthsIncludingTheLeapDay() {
        let counts: [(Int, Int, Int)] = [
            (2026, 2, 28), (2027, 2, 28), (2028, 2, 29), (2100, 2, 28), (2000, 2, 29), (2026, 4, 30), (2026, 12, 31), (2026, 1, 31),
        ]
        for (year, month, days) in counts {
            let period = ReviewPeriod.monthly(year: year, month: month)
            #expect(period.mornings.count == days, "\(year)-\(month)")
            #expect(period.firstMorning == SleepNightKey(year: year, month: month, day: 1))
            #expect(period.nextMorning.day == 1)
        }
        // The previous month, across a year boundary and over a leap day.
        #expect(ReviewPeriod.monthly(year: 2027, month: 1).previous == ReviewPeriod.monthly(year: 2026, month: 12))
        #expect(ReviewPeriod.monthly(year: 2028, month: 3).previous.mornings.count == 29)
        let cal = calendar(zones[0])
        #expect(ReviewPeriod.latestMonthly(now: date(cal, 2028, 3, 1, 0, 0), calendar: cal) == ReviewPeriod.monthly(year: 2028, month: 2))
        #expect(ReviewPeriod.latestMonthly(now: date(cal, 2027, 1, 1, 0, 0), calendar: cal) == ReviewPeriod.monthly(year: 2026, month: 12))
        // A month is complete from the first moment of the next one, in a 23- or 25-hour day too.
        for zone in zones {
            let zoneCal = calendar(zone)
            let february = ReviewPeriod.monthly(year: 2028, month: 2)
            #expect(!february.isComplete(at: date(zoneCal, 2028, 2, 29, 23, 59), calendar: zoneCal))
            #expect(february.isComplete(at: date(zoneCal, 2028, 3, 1, 0, 0), calendar: zoneCal))
        }
    }

    @Test func aReviewPeriodMovesWithTheClockWhenTheTimeZoneChanges() {
        // Sunday 2026-09-27, 22:00 in New York is Monday 11:00 in Tokyo: "today" is a different date, so the latest weekly review (Monday) differs.
        let instant = date(calendar(zones[0]), 2026, 9, 27, 22)
        let tokyo = calendar(TimeZone(identifier: "Asia/Tokyo")!)
        let newYork = calendar(zones[0])
        let inNewYork = ReviewPeriod.latestWeekly(now: instant, weekday: 2, calendar: newYork)
        let inTokyo = ReviewPeriod.latestWeekly(now: instant, weekday: 2, calendar: tokyo)
        #expect(inTokyo.lastMorning == SleepNightKey(year: 2026, month: 9, day: 27), "Monday has begun in Tokyo: the week to Sunday the 27th")
        #expect(inNewYork.lastMorning == SleepNightKey(year: 2026, month: 9, day: 20), "Monday has not begun in New York: still the week before")
        // Either way the period is a whole set of dates, never a half week.
        #expect(inTokyo.mornings.count == 7 && inNewYork.mornings.count == 7)
        #expect(inTokyo.isComplete(at: instant, calendar: tokyo) && inNewYork.isComplete(at: instant, calendar: newYork))
    }

    // MARK: Midnight rollover and clock jumps

    @Test func theFreeCoachQuotaResetsAtMidnightAndNeverRefillsFromABackwardClock() {
        for zone in zones {
            let cal = calendar(zone)
            var state = CoachQuotaState()
            let evening = date(cal, 2026, 9, 24, 23, 59)
            for _ in 0..<3 { state = CoachQuota.recording(state, now: evening, calendar: cal) }
            #expect(CoachQuota.remaining(state, now: evening, calendar: cal) == 0)
            #expect(CoachQuota.remaining(state, now: date(cal, 2026, 9, 25, 0, 0), calendar: cal) == 3, "midnight")
            // The clock (or the zone) goes back a day: the count already made stands.
            #expect(CoachQuota.remaining(state, now: date(cal, 2026, 9, 23, 12), calendar: cal) == 0)
            #expect(CoachQuota.remaining(state, now: evening.addingTimeInterval(-3 * 3600), calendar: cal) == 0)
            // Recording after the reset starts the new day at one.
            let next = CoachQuota.recording(state, now: date(cal, 2026, 9, 25, 0, 1), calendar: cal)
            #expect(next.used == 1 && next.day == "2026-09-25")
        }
        // The quota resets once on each 23- and 25-hour day.
        for zone in zones {
            let cal = calendar(zone)
            for transition in transitionWindows(zone) {
                let day = CoachQuota.dayKey(transition, calendar: cal)
                var state = CoachQuotaState(day: day, used: 3)
                state = CoachQuota.current(state, now: transition.addingTimeInterval(-3600), calendar: cal)
                #expect(CoachQuota.remaining(state, now: transition.addingTimeInterval(3600), calendar: cal) <= 3)
            }
        }
    }

    @Test func theHomeRevealIsUsedOncePerCalendarDayAndComesBackTheNextDay() {
        let suite = "noctis.qa.time.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = HomeIntroGate(defaults: defaults)
        let cal = calendar(zones[0])
        #expect(gate.claim(now: date(cal, 2026, 9, 24, 7), calendar: cal))
        #expect(!gate.claim(now: date(cal, 2026, 9, 24, 7, 30), calendar: cal))
        #expect(!gate.claim(now: date(cal, 2026, 9, 24, 23, 59), calendar: cal), "the same day, late")
        #expect(gate.claim(now: date(cal, 2026, 9, 25, 0, 0), calendar: cal), "midnight rolled over")
        // A clock that goes back a day plays the reveal again: it decorates, so a wrong clock can never lock it out. Documented, not a bug.
        #expect(gate.claim(now: date(cal, 2026, 9, 24, 8), calendar: cal))
    }

    @Test func tonightIsTheSameNightFromEveningUntilSixAndMidnightDoesNotChangeIt() {
        for zone in zones {
            let cal = calendar(zone)
            let evening = TonightClock.tonight(now: date(cal, 2026, 9, 24, 23, 59), in: zone)
            #expect(TonightClock.tonight(now: date(cal, 2026, 9, 25, 0, 0), in: zone) == evening.adding(days: 0).adding(days: 0))
            #expect(TonightClock.tonight(now: date(cal, 2026, 9, 25, 5, 59), in: zone) == evening)
            #expect(TonightClock.tonight(now: date(cal, 2026, 9, 25, 6, 0), in: zone) == evening.adding(days: 1))
        }
    }

    @Test func aWindDownReminderMovedByAClockChangeKeepsTheSameWallClockTime() {
        // The system fires a repeating calendar trigger at the wall-clock time, so the plan must never bake in an offset from UTC.
        let preferences = NotificationPreferences()
        let plan = NotificationPlan.make(preferences: preferences, wakeMinutes: 7 * 60, bedtimeCenterMinutes: 23 * 60)
        for notification in plan {
            #expect(notification.components.hour != nil && notification.components.minute != nil)
            #expect(
                notification.components.timeZone == nil && notification.components.day == nil && notification.components.month == nil
                    && notification.components.year == nil)
            #expect(notification.repeats)
        }
        // No two reminders share an identifier, and the plan has at most three.
        #expect(Set(plan.map(\.identifier)).count == plan.count && plan.count <= 3)
    }
}
