import Foundation

/// The evening a night belongs to, as a plain calendar date with no time
/// and no time zone. A night runs from noon on this date to noon the next
/// day on the local clock, so a sleep that starts at 12:40 AM belongs to
/// the previous evening (onboarding's rule: the night of `bedtime − 12h`).
///
/// Keys compare and step by whole calendar days, so they are unaffected by
/// DST changes (a 23- or 25-hour day is still one night) and by travel.
public struct SleepNightKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The night that `date` falls in, read on the local clock of
    /// `timeZone`: its local date, or the day before when the local time
    /// is before noon.
    public init(containing date: Date, in timeZone: TimeZone) {
        let local = Self.gregorian(timeZone).dateComponents([.year, .month, .day, .hour], from: date)
        let key = SleepNightKey(year: local.year ?? 1970, month: local.month ?? 1, day: local.day ?? 1)
        self = (local.hour ?? 0) < 12 ? key.adding(days: -1) : key
    }

    public func adding(days: Int) -> SleepNightKey {
        let calendar = Self.gregorian(Self.utc)
        let shifted = calendar.date(byAdding: .day, value: days, to: noonUTC) ?? noonUTC
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        return SleepNightKey(year: components.year ?? year, month: components.month ?? month, day: components.day ?? day)
    }

    /// Whole nights from `other` to `self` (positive when `self` is later).
    public func days(from other: SleepNightKey) -> Int {
        Self.gregorian(Self.utc).dateComponents([.day], from: other.noonUTC, to: noonUTC).day ?? 0
    }

    /// Minutes from noon on this night's evening to `date`, on the local
    /// clock of `timeZone`: 11:00 PM is 660, 1:00 AM the next day is 780,
    /// 7:00 AM the next day is 1140. Read from clock components, so DST
    /// never shifts a clock time by an hour.
    public func minutesAfterNoon(of date: Date, in timeZone: TimeZone) -> Double {
        let local = Self.gregorian(timeZone).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let localDay = SleepNightKey(year: local.year ?? year, month: local.month ?? month, day: local.day ?? day)
        let clock = Double(local.hour ?? 0) * 60 + Double(local.minute ?? 0) + Double(local.second ?? 0) / 60
        return Double(localDay.days(from: self)) * 1440 + clock - 720
    }

    public static func < (lhs: SleepNightKey, rhs: SleepNightKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Private

    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current

    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private var noonUTC: Date {
        Self.gregorian(Self.utc).date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }
}
