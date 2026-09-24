import Foundation
import HealthProviding
import RecoveryKit
import SleepKit

/// Shared, fully deterministic fixtures: fixed zones and fixed dates.
enum Fixture {
    static let newYork = TimeZone(identifier: "America/New_York")!
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    static func calendar(_ timeZone: TimeZone = newYork) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// A local wall-clock time in `timeZone`.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, in timeZone: TimeZone = newYork) -> Date {
        calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func sample(
        _ start: Date,
        _ end: Date,
        _ stage: SleepStageValue = .core,
        source: String = "Watch",
        bundle: String = "com.example.watch",
        timeZone: TimeZone? = nil
    ) -> RawSleepSample {
        RawSleepSample(start: start, end: end, stage: stage, sourceName: source, sourceBundleID: bundle, timeZone: timeZone)
    }

    /// A plain 11 PM–7 AM core night for the evening of `day` (Sep 2026).
    static func plainNight(september day: Int, bedHour: Int = 23, hours: Double = 8) -> [RawSleepSample] {
        let bedtime = date(2026, 9, day, bedHour)
        return [sample(bedtime, bedtime.addingTimeInterval(hours * 3600))]
    }

    /// Nightly metrics for `count` consecutive nights ending on the
    /// evening of `last`, each waking at 7:00 AM New York time the next
    /// morning, with per-night values from `values(index)`.
    static func metrics(
        count: Int,
        endingOn last: SleepNightKey = SleepNightKey(year: 2026, month: 9, day: 23),
        values: (Int) -> (asleep: Double, bedtime: Double, wake: Double, hrv: Double?, resting: Double?)
    ) -> [NightMetrics] {
        (0..<count).map { index in
            let night = last.adding(days: index - (count - 1))
            let value = values(index)
            let wakeDay = night.adding(days: 1)
            return NightMetrics(
                night: night,
                wakeTime: date(wakeDay.year, wakeDay.month, wakeDay.day, 7),
                asleepMinutes: value.asleep,
                bedtimeMinutes: value.bedtime,
                wakeMinutes: value.wake,
                hrv: value.hrv,
                restingHeartRate: value.resting
            )
        }
    }

    /// 9:00 AM on Sep 24, 2026, New York: two hours after the last fixture
    /// night's 7:00 AM wake-up.
    static let morningAfter = date(2026, 9, 24, 9)
}
