import Foundation

// QA part 4 (QA-118): the one place a length of time and a clock time become text. `NoctisFormat` (DesignSystem), `ReviewFormat` (ReviewKit) and everything
// that prints "6h 42m", "6 hours 42 minutes" or "11:00 PM" go through these, so no two surfaces can round or word them differently.
// `NoctisFormatTests` fails if another function that does this work appears.

public nonisolated enum NoctisDurationText {
    /// "8h", "8h 15m", "45m"; with `minutesWord`, "45 min" when there are no hours.
    public static func compact(_ minutes: Int, minutesWord: Bool = false) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        let h = NoctisUnit.hour.symbol, m = NoctisUnit.minute.symbol
        if hours == 0 { return minutesWord ? minutesOnly(remainder) : "\(remainder)\(m)" }
        return remainder == 0 ? "\(hours)\(h)" : "\(hours)\(h) \(remainder)\(m)"
    }

    /// A number of minutes on its own: "24 min".
    public static func minutesOnly(_ minutes: Int) -> String { "\(minutes) \(NoctisUnit.minuteShort.symbol)" }

    /// "6 hours 42 minutes", "1 hour", "45 minutes".
    public static func spoken(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        var words: [String] = []
        if hours > 0 { words.append(NoctisCount.hours(hours)) }
        if remainder > 0 || hours == 0 { words.append(NoctisCount.minutes(remainder)) }
        return words.joined(separator: " ")
    }

    /// A length in minutes as it is rounded everywhere: to the nearest whole minute, never below zero.
    public static func wholeMinutes(_ minutes: Double) -> Int { max(Int(minutes.rounded()), 0) }
}

public nonisolated enum NoctisClockText {
    /// A clock time given as minutes since midnight, in `calendar`'s time zone and `locale`'s style: "11:00 PM", or "23:00" on a 24-hour clock.
    public static func string(minutesSinceMidnight minutes: Int, calendar: Calendar, locale: Locale) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: normalized / 60, minute: normalized % 60)
        guard let date = calendar.date(from: components) else { return "" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }
}

public nonisolated enum NoctisQuantityText {
    /// A quantity written in a sentence or a label: "48 ms", "54 bpm". The unit's symbol comes from the string catalog (`NoctisUnit`), never from the call site.
    public static func text(_ value: Int, _ unit: NoctisUnit) -> String { "\(value) \(unit.symbol)" }

    /// The same, from a number already written ("7.5").
    public static func text(_ number: String, _ unit: NoctisUnit) -> String { "\(number) \(unit.symbol)" }
}
