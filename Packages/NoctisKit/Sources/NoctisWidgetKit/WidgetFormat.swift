import DesignSystem
import Foundation
import NoctisText

/// The words and numbers the widgets show, made the way Home makes them (a test holds the two to the same strings), with the
/// calendar and locale passed in so every string is reproducible.
public nonisolated struct WidgetFormat: Sendable, Equatable {
    public let calendar: Calendar
    public let locale: Locale

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    /// A clock time given as minutes since midnight: "11:00 PM".
    public func clock(minutesSinceMidnight minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: normalized / 60, minute: normalized % 60)
        guard let date = calendar.date(from: components) else { return "" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
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

    /// A clock time as a metric: the period is the unit (none on 24-hour clocks).
    public func clockMetric(minutesSinceMidnight minutes: Int) -> NoctisMetricValue {
        let text = clock(minutesSinceMidnight: minutes)
        let (time, period) = splitClock(text)
        return NoctisMetricValue(parts: period.isEmpty ? [.number(time)] : [.number(time), .unit(period)], spoken: text)
    }

    /// "10:45 – 11:15 PM", or "10:45 PM – 12:15 AM" when the periods differ.
    public func windowText(startMinutes: Int, endMinutes: Int) -> String {
        let start = splitClock(clock(minutesSinceMidnight: startMinutes))
        let end = splitClock(clock(minutesSinceMidnight: endMinutes))
        if start.period.isEmpty || start.period == end.period { return "\(start.time)\u{2009}–\u{2009}\(end.time) \(end.period)".trimmingCharacters(in: .whitespaces) }
        return "\(start.time) \(start.period)\u{2009}–\u{2009}\(end.time) \(end.period)"
    }

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
    public static func spokenDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        var words: [String] = []
        if hours > 0 { words.append(NoctisCount.hours(hours)) }
        if remainder > 0 || hours == 0 { words.append(NoctisCount.minutes(remainder)) }
        return words.joined(separator: " ")
    }

    /// "8h", "8h 15m", "45m".
    public static func compactDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        let h = NoctisUnit.hour.symbol, m = NoctisUnit.minute.symbol
        if hours == 0 { return "\(remainder)\(m)" }
        return remainder == 0 ? "\(hours)\(h)" : "\(hours)\(h) \(remainder)\(m)"
    }

    /// 52 bpm, 48 ms as a metric: the unit's symbol beside the number and its spoken form (R68).
    public static func quantityMetric(_ value: Int, _ unit: NoctisUnit) -> NoctisMetricValue {
        NoctisMetricValue(parts: [.number("\(value)"), .unit(unit.symbol)], spoken: unit.spoken(value))
    }
}
