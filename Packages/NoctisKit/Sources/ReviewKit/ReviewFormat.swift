import Foundation
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
        let moment = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: wall / 60, minute: wall % 60)) ?? Date(timeIntervalSince1970: 0)
        return moment.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: Self.utc))
    }

    /// 6h 42m, 8h, 45m.
    public static func duration(_ minutes: Double) -> String {
        let total = max(Int(minutes.rounded()), 0)
        let hours = total / 60
        let rest = total % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// 14 min, 1h 5m: a difference, without a sign.
    public static func amount(_ minutes: Double) -> String {
        let total = Int(abs(minutes).rounded())
        return total >= 60 ? duration(Double(total)) : "\(total) min"
    }

    /// Whole minutes: 24 min.
    public static func minutes(_ value: Double) -> String { "\(Int(value.rounded())) min" }

    /// 54, or 7.5 when it is not a whole number.
    public static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }
}
