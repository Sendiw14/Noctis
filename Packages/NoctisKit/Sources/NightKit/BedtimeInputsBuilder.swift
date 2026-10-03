import Foundation
import SleepAnalysisKit
import SleepKit

/// Turns the engines' results into the recommendation's inputs, and reads tonight's clock:
/// the only place a bedtime meets a calendar.
public enum BedtimeInputsBuilder {
    /// The usual bedtime needs this many recorded nights of the last 14 (the timing engine
    /// itself would give one from 5).
    public static let usualBedtimeMinimumNights = 7

    /// The recommendation's inputs from the profile and the Sleep tab's engines.
    /// `clockChangeMinutes` comes from `TonightClock`.
    public static func inputs(
        wakeMinutes: Int, needMinutes: Int, timing: SleepTimingResult?, balance: SleepBalanceResult?,
        consistency: ConsistencyResult?, clockChangeMinutes: Int = 0
    ) -> BedtimeInputs {
        let nights = timing?.nights ?? 0
        return BedtimeInputs(
            wakeMinutes: wakeMinutes, needMinutes: needMinutes, balanceMinutes: balance?.minutes,
            usualBedtimeMinutes: nights >= usualBedtimeMinimumNights ? timing?.typicalBedtime.map { sinceMidnight(minutesAfterNoon: $0) } : nil,
            bedtimeSpreadMinutes: consistency?.window(days: SleepTimingEngine.typicalWindowNights)?.bedtimeSD,
            nights: nights, clockChangeMinutes: clockChangeMinutes
        )
    }

    /// Engines count clock times in minutes after noon (11:00 PM is 660); the recommendation
    /// counts from midnight (11:00 PM is 1380).
    public static func sinceMidnight(minutesAfterNoon: Double) -> Int {
        BedtimeClock.wrap(Int(minutesAfterNoon.rounded()) + 720)
    }
}

/// Tonight on a calendar: which night it is, the real dates of its bedtime and waking, and
/// how far the clock jumps between them (DST).
public enum TonightClock {
    /// The night that contains `now` (noon to noon, `SleepNightKey`).
    public static func night(containing now: Date, in timeZone: TimeZone) -> SleepNightKey {
        SleepNightKey(containing: now, in: timeZone)
    }

    /// The night "Tonight" is about: the one that starts this evening. Before 6 AM the night
    /// that is still going counts as tonight; from 6 AM on, a night that has ended doesn't.
    public static func tonight(now: Date, in timeZone: TimeZone) -> SleepNightKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let local = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let today = SleepNightKey(year: local.year ?? 1970, month: local.month ?? 1, day: local.day ?? 1)
        return (local.hour ?? 0) < 6 ? today.adding(days: -1) : today
    }

    /// The dates of `night`'s bedtime and waking: the bedtime clock time on the night's evening
    /// (or after midnight, the next calendar day), and the first wake clock time after it.
    public static func dates(night: SleepNightKey, bedtimeMinutes: Int, wakeMinutes: Int, timeZone: TimeZone) -> (bedtime: Date, wake: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let bedtimeClock = BedtimeClock.wrap(bedtimeMinutes)
        let bedtimeDayOffset = bedtimeClock < 720 ? 1 : 0
        let bedtime = date(night: night, dayOffset: bedtimeDayOffset, minutes: bedtimeClock, calendar: calendar)
        let wakeClock = BedtimeClock.wrap(wakeMinutes)
        let wakeDayOffset = bedtimeDayOffset + (wakeClock > bedtimeClock ? 0 : 1)
        let wake = date(night: night, dayOffset: wakeDayOffset, minutes: wakeClock, calendar: calendar)
        return (bedtime, wake)
    }

    /// How far the clock jumps between bedtime and waking: +60 when clocks go forward that
    /// night, -60 when they go back, 0 on every other night.
    public static func clockChangeMinutes(night: SleepNightKey, bedtimeMinutes: Int, wakeMinutes: Int, timeZone: TimeZone) -> Int {
        let (bedtime, wake) = dates(night: night, bedtimeMinutes: bedtimeMinutes, wakeMinutes: wakeMinutes, timeZone: timeZone)
        return (timeZone.secondsFromGMT(for: wake) - timeZone.secondsFromGMT(for: bedtime)) / 60
    }

    private static func date(night: SleepNightKey, dayOffset: Int, minutes: Int, calendar: Calendar) -> Date {
        let day = night.adding(days: dayOffset)
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: minutes / 60, minute: minutes % 60)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}
