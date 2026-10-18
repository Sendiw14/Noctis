import Foundation
import NoctisText

/// The one formatter: every duration, clock time, window, date and unit the app, its widgets, the Watch, Siri and Coach print or speak (QA part 4, QA-118). It
/// takes the calendar and locale as arguments so every string is reproducible. `HomeFormat` and `WidgetFormat` are aliases of it: a second copy of any of
/// these functions would let two surfaces disagree, so `NoctisFormatTests` fails if one comes back.
public nonisolated struct NoctisFormat: Sendable, Equatable {
    public let calendar: Calendar
    public let locale: Locale

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    /// "Thursday, September 24".
    public func longDate(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone ?? calendar.timeZone).weekday(.wide).month(.wide).day())
    }

    /// "Wed, Sep 23".
    public func shortDate(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone ?? calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Wed 7:02 AM", kept on one line (no-break spaces).
    public func dayAndTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).hour().minute())
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// "11:02 PM" on the clock of `timeZone`.
    public func clock(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
    }

    /// A clock time given as minutes since midnight.
    public func clock(minutesSinceMidnight minutes: Int) -> String {
        NoctisClockText.string(minutesSinceMidnight: minutes, calendar: calendar, locale: locale)
    }

    /// "6 PM": the hour alone.
    public func hour(minutesSinceMidnight minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: normalized / 60, minute: normalized % 60)
        guard let date = calendar.date(from: components) else { return "" }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour())
    }

    /// "11:00 PM" → ("11:00", "PM"); 24-hour clocks have no period.
    public func splitClock(_ text: String) -> (time: String, period: String) {
        let formatter = DateFormatter()
        formatter.locale = locale
        for symbol in [formatter.amSymbol, formatter.pmSymbol] where !(symbol ?? "").isEmpty {
            guard let symbol, let range = text.range(of: symbol) else { continue }
            var time = text
            time.removeSubrange(range)
            return (time.trimmingCharacters(in: .whitespaces), symbol)
        }
        return (text, "")
    }

    /// A clock time given as minutes after noon (baselines' unit).
    public func clock(minutesAfterNoon: Double) -> String {
        clock(minutesSinceMidnight: Int(minutesAfterNoon.rounded()) + 720)
    }

    public enum WeekdayWidth { case narrow, abbreviated, wide }

    /// 6h 42m, 8h, 45m as a metric; VoiceOver hears "6 hours 42 minutes".
    public static func durationMetric(_ minutes: Int) -> NoctisMetricValue {
        let hours = minutes / 60
        let remainder = minutes % 60
        var parts: [NoctisMetricValue.Part] = []
        if hours > 0 { parts += [.number("\(hours)"), .unit(NoctisUnit.hour.symbol)] }
        if remainder > 0 || hours == 0 {
            if !parts.isEmpty { parts.append(.space) }
            parts += [.number("\(remainder)"), .unit(NoctisUnit.minute.symbol)]
        }
        return NoctisMetricValue(parts: parts, spoken: spokenDuration(minutes))
    }

    /// "6 hours 42 minutes", "1 hour", "45 minutes".
    public static func spokenDuration(_ minutes: Int) -> String { NoctisDurationText.spoken(minutes) }

    /// 52 bpm, 48 ms as a metric: the unit's symbol beside the number and its spoken form (R68).
    public static func quantityMetric(_ value: Int, _ unit: NoctisUnit) -> NoctisMetricValue {
        NoctisMetricValue(parts: [.number("\(value)"), .unit(unit.symbol)], spoken: unit.spoken(value))
    }

    /// A score or a count with no unit: "62".
    public static func plainMetric(_ value: Int) -> NoctisMetricValue {
        NoctisMetricValue(parts: [.number("\(value)")], spoken: "\(value)")
    }

    /// 11:00 PM as a metric: the period is the unit (none on 24-hour
    /// clocks).
    /// "10:45 – 11:15 PM", or "11:45 PM – 12:15 AM" when the window crosses AM and PM.
    public func windowText(startMinutes: Int, endMinutes: Int) -> String {
        let start = clock(minutesSinceMidnight: startMinutes)
        let end = clock(minutesSinceMidnight: endMinutes)
        let (startTime, startPeriod) = splitClock(start)
        let (endTime, endPeriod) = splitClock(end)
        guard !startPeriod.isEmpty, startPeriod == endPeriod else { return "\(start) – \(end)" }
        return "\(startTime) – \(endTime) \(endPeriod)"
    }

    /// The window as one metric: the period is the unit. The dash and its spaces are set at the numbers' size, so "10:15 – 10:45 PM" reads as one thing.
    public func windowMetric(startMinutes: Int, endMinutes: Int) -> NoctisMetricValue {
        let start = splitClock(clock(minutesSinceMidnight: startMinutes))
        let end = splitClock(clock(minutesSinceMidnight: endMinutes))
        var parts: [NoctisMetricValue.Part] = []
        if !start.period.isEmpty, start.period != end.period {
            parts += [.number(start.time), .unit(start.period), .number(" – "), .number(end.time)]
        } else {
            parts.append(.number("\(start.time) – \(end.time)"))
        }
        if !end.period.isEmpty { parts.append(.unit(end.period)) }
        let spoken = windowText(startMinutes: startMinutes, endMinutes: endMinutes).replacingOccurrences(of: " – ", with: " to ")
        return NoctisMetricValue(parts: parts, spoken: spoken)
    }

    /// A clock time given as minutes since midnight, as a metric: the period is the unit (none on 24-hour clocks).
    public func clockMetric(minutesSinceMidnight minutes: Int) -> NoctisMetricValue {
        clockMetric(clock(minutesSinceMidnight: minutes))
    }

    public func clockMetric(_ text: String) -> NoctisMetricValue {
        let (time, period) = splitClock(text)
        return NoctisMetricValue(parts: period.isEmpty ? [.number(time)] : [.number(time), .unit(period)], spoken: text)
    }

    /// "8h", "8h 15m", "45m" — or with `minutesWord`, "45 min".
    public static func compactDuration(_ minutes: Int, minutesWord: Bool = false) -> String { NoctisDurationText.compact(minutes, minutesWord: minutesWord) }
}
