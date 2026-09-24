import Foundation
import Testing
@testable import SleepKit

struct SleepNightKeyTests {
    @Test func eveningTimesBelongToThatDaysNight() {
        let key = SleepNightKey(containing: Fixture.date(2026, 9, 1, 23), in: Fixture.newYork)
        #expect(key == SleepNightKey(year: 2026, month: 9, day: 1))
    }

    @Test func timesAfterMidnightBelongToThePreviousEvening() {
        #expect(SleepNightKey(containing: Fixture.date(2026, 9, 2, 0, 40), in: Fixture.newYork) == SleepNightKey(year: 2026, month: 9, day: 1))
        #expect(SleepNightKey(containing: Fixture.date(2026, 9, 2, 11, 59), in: Fixture.newYork) == SleepNightKey(year: 2026, month: 9, day: 1))
        #expect(SleepNightKey(containing: Fixture.date(2026, 9, 2, 12), in: Fixture.newYork) == SleepNightKey(year: 2026, month: 9, day: 2))
    }

    @Test func steppingCrossesMonthAndYearBoundaries() {
        #expect(SleepNightKey(year: 2026, month: 12, day: 31).adding(days: 1) == SleepNightKey(year: 2027, month: 1, day: 1))
        #expect(SleepNightKey(year: 2026, month: 3, day: 1).adding(days: -1) == SleepNightKey(year: 2026, month: 2, day: 28))
        #expect(SleepNightKey(year: 2026, month: 9, day: 23).days(from: SleepNightKey(year: 2026, month: 9, day: 9)) == 14)
    }

    @Test func stepsAcrossDSTChangesAreWholeDays() {
        let beforeSpring = SleepNightKey(year: 2026, month: 3, day: 7)
        #expect(beforeSpring.adding(days: 2) == SleepNightKey(year: 2026, month: 3, day: 9))
        #expect(SleepNightKey(year: 2026, month: 11, day: 2).days(from: SleepNightKey(year: 2026, month: 10, day: 31)) == 2)
    }

    @Test func clockMinutesAreCountedFromNoonOnTheEvening() {
        let night = SleepNightKey(year: 2026, month: 9, day: 1)
        #expect(night.minutesAfterNoon(of: Fixture.date(2026, 9, 1, 23), in: Fixture.newYork) == 660)
        #expect(night.minutesAfterNoon(of: Fixture.date(2026, 9, 2, 1), in: Fixture.newYork) == 780)
        #expect(night.minutesAfterNoon(of: Fixture.date(2026, 9, 2, 7), in: Fixture.newYork) == 1140)
    }

    @Test func clockMinutesIgnoreTheDSTJump() {
        // Spring forward on Mar 8, 2026: 7:00 AM is still 7:00 AM.
        let night = SleepNightKey(year: 2026, month: 3, day: 7)
        #expect(night.minutesAfterNoon(of: Fixture.date(2026, 3, 8, 7), in: Fixture.newYork) == 1140)
    }
}
