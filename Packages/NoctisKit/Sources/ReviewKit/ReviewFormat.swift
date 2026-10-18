import Foundation
import NoctisText
import SleepKit

/// How a review writes a date, a clock time and a duration, in the person's own calendar and language. Dates are calendar dates (a `SleepNightKey`), so a time zone
/// never moves one; a clock time is minutes after noon on the evening, as the baselines count them.
public nonisolated struct ReviewFormat: Sendable {
    public let locale: Locale

    public init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    private static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    private func date(_ key: SleepNightKey) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    private func format(_ key: SleepNightKey, _ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = Self.utc
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date(key))
    }

    /// "Sep 20".
    public func day(_ key: SleepNightKey) -> String { format(key, "MMMd") }

    /// "Tue, Sep 22".
    public func weekdayDay(_ key: SleepNightKey) -> String { format(key, "EEEMMMd") }

    /// "M", "T": a weekday's first letter, for a column under a bar.
    public func narrowWeekday(_ key: SleepNightKey) -> String { format(key, "EEEEE") }

    /// "12": the day of the month, for a slim bar.
    public func dayNumber(_ key: SleepNightKey) -> String { String(key.day) }

    /// "September".
    public func monthName(_ key: SleepNightKey) -> String { format(key, "MMMM") }

    /// "September 2026".
    public func monthYear(_ key: SleepNightKey) -> String { format(key, "MMMMy") }

    /// "Sep 20 – 26", or "Sep 27 – Oct 3" across a month.
    public func range(_ first: SleepNightKey, _ last: SleepNightKey) -> String {
        if first.month == last.month, first.year == last.year { return "\(day(first)) \u{2013} \(last.day)" }
        return "\(day(first)) \u{2013} \(day(last))"
    }

    /// 11:08 PM, from minutes after noon on the evening (660).
    public func clock(minutesAfterNoon minutes: Double) -> String {
        let wall = Int((minutes.rounded() + 720).truncatingRemainder(dividingBy: 1440) + 1440) % 1440
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return NoctisClockText.string(minutesSinceMidnight: wall, calendar: calendar, locale: locale)
    }

    /// 6h 42m, 8h, 45m: the app's one duration (`NoctisDurationText`).
    public static func duration(_ minutes: Double) -> String { NoctisDurationText.compact(NoctisDurationText.wholeMinutes(minutes)) }

    /// "6 hours 42 minutes": the same length as it is spoken (VoiceOver reads "6h 42m" as letters).
    public static func spoken(_ minutes: Double) -> String { NoctisDurationText.spoken(NoctisDurationText.wholeMinutes(minutes)) }

    /// 14 min, 1h 5m: a difference, without a sign.
    public static func amount(_ minutes: Double) -> String {
        let total = Int(abs(minutes).rounded())
        return total >= 60 ? duration(Double(total)) : NoctisDurationText.minutesOnly(total)
    }

    /// Whole minutes: 24 min.
    public static func minutes(_ value: Double) -> String { NoctisDurationText.minutesOnly(Int(value.rounded())) }

    /// 54: a whole number (a recovery score, an HRV, a heart rate).
    public static func whole(_ value: Double) -> String { String(Int(value.rounded())) }

    /// 54, or 7.5 when it is not a whole number.
    public static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
}
