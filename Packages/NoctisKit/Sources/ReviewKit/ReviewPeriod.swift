import Foundation
import SleepKit

// The periods a review covers (APP_RULES.md R39). Pure: calendar dates in, calendar dates out, so every boundary (daylight saving, a month's edge, a change of the review
// weekday, a change of time zone) is a unit test.
//
// A night belongs to the morning it ends on, as the Sleep tab labels it ("M 28" is the night that ended on Monday morning). A period is a run of those mornings:
// a week is the 7 mornings before the review's weekday begins, a month is the previous calendar month's mornings. Nights are still keyed by the evening they began
// (`SleepNightKey`), as everywhere else; `night(endingOn:)` is the one conversion. Dates are plain calendar dates (a `SleepNightKey` carries only a year, a month
// and a day), so a 23- or 25-hour day is one day and only the moment a period is complete (`completeAt`) reads the clock.

public nonisolated enum ReviewKind: String, Sendable, Codable, CaseIterable, Equatable {
    case weekly
    case monthly

    /// The nights a review needs before it says anything: 5 of the week's 7, 20 of the month's.
    public var minimumNights: Int {
        switch self {
        case .weekly: 5
        case .monthly: 20
        }
    }

    /// How many insights a review points to: one for a week, three for a month.
    public var topInsights: Int {
        switch self {
        case .weekly: 1
        case .monthly: 3
        }
    }
}

/// A review's identity: its kind and the date of the last morning it covers ("weekly-2026-09-26"). It never changes once the period exists.
public nonisolated struct ReviewID: Hashable, Sendable, Codable, CustomStringConvertible, Comparable {
    public let kind: ReviewKind
    public let lastMorning: SleepNightKey

    public init(kind: ReviewKind, lastMorning: SleepNightKey) {
        self.kind = kind
        self.lastMorning = lastMorning
    }

    public var description: String { "\(kind.rawValue)-\(lastMorning.description)" }

    /// "weekly-2026-09-26"; nil for anything else (an id from outside is never trusted).
    public init?(_ text: String) {
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let kind = ReviewKind(rawValue: parts[0]) else { return nil }
        let numbers = parts[1].split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard numbers.count == 3, numbers[0].count == 4, numbers[1].count == 2, numbers[2].count == 2,
            let year = Int(numbers[0]), let month = Int(numbers[1]), let day = Int(numbers[2]),
            (1...12).contains(month), (1...31).contains(day), (2000...2200).contains(year)
        else { return nil }
        let key = SleepNightKey(year: year, month: month, day: day)
        // A date that does not exist (the 31st of a short month) is no id.
        guard key.adding(days: 0) == key else { return nil }
        self.init(kind: kind, lastMorning: key)
    }

    public static func < (lhs: ReviewID, rhs: ReviewID) -> Bool {
        (lhs.lastMorning, lhs.kind.rawValue) < (rhs.lastMorning, rhs.kind.rawValue)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let id = ReviewID(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a review id: \(text)"))
        }
        self = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public nonisolated struct ReviewPeriod: Sendable, Equatable, Codable {
    public let kind: ReviewKind
    /// The first and last morning the period covers (calendar dates), inclusive.
    public let firstMorning: SleepNightKey
    public let lastMorning: SleepNightKey

    public init(kind: ReviewKind, firstMorning: SleepNightKey, lastMorning: SleepNightKey) {
        self.kind = kind
        self.firstMorning = firstMorning
        self.lastMorning = lastMorning
    }

    public var id: ReviewID { ReviewID(kind: kind, lastMorning: lastMorning) }

    /// Mornings in the period: 7 for a week, 28 to 31 for a month.
    public var morningCount: Int { lastMorning.days(from: firstMorning) + 1 }

    public var mornings: [SleepNightKey] { (0..<morningCount).map { firstMorning.adding(days: $0) } }

    /// The night (keyed by its evening) that ended on `morning`.
    public static func night(endingOn morning: SleepNightKey) -> SleepNightKey { morning.adding(days: -1) }

    /// The morning a night (keyed by its evening) ends on.
    public static func morning(ofNight night: SleepNightKey) -> SleepNightKey { night.adding(days: 1) }

    public func contains(morning: SleepNightKey) -> Bool { morning >= firstMorning && morning <= lastMorning }

    /// The first morning after the period.
    public var nextMorning: SleepNightKey { lastMorning.adding(days: 1) }

    /// The moment the period is complete: the start of the first morning after it, on `calendar`'s clock. A time zone that changes moves it with the clock, and a
    /// 23- or 25-hour day makes no difference to which day it is.
    public func completeAt(calendar: Calendar) -> Date {
        let components = DateComponents(year: nextMorning.year, month: nextMorning.month, day: nextMorning.day)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) } ?? .distantFuture
    }

    public func isComplete(at now: Date, calendar: Calendar) -> Bool { now >= completeAt(calendar: calendar) }

    /// The period of the same kind just before this one: the 7 mornings before a week's, the month before a month's.
    public var previous: ReviewPeriod {
        switch kind {
        case .weekly: Self.weekly(reviewDate: firstMorning)
        case .monthly:
            Self.monthly(
                year: firstMorning.month == 1 ? firstMorning.year - 1 : firstMorning.year, month: firstMorning.month == 1 ? 12 : firstMorning.month - 1)
        }
    }

    // MARK: Making a period

    /// The week reviewed on `reviewDate` (the date whose weekday the person chose): the 7 mornings before it.
    public static func weekly(reviewDate: SleepNightKey) -> ReviewPeriod {
        ReviewPeriod(kind: .weekly, firstMorning: reviewDate.adding(days: -7), lastMorning: reviewDate.adding(days: -1))
    }

    /// The whole of one calendar month's mornings.
    public static func monthly(year: Int, month: Int) -> ReviewPeriod {
        let first = SleepNightKey(year: year, month: month, day: 1)
        let following = month == 12 ? SleepNightKey(year: year + 1, month: 1, day: 1) : SleepNightKey(year: year, month: month + 1, day: 1)
        return ReviewPeriod(kind: .monthly, firstMorning: first, lastMorning: following.adding(days: -1))
    }

    /// Today's date on `calendar`'s clock.
    public static func today(_ now: Date, calendar: Calendar) -> SleepNightKey {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return SleepNightKey(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The most recent week whose review day (`weekday`, 1 = Sunday ... 7 = Saturday, as `Calendar` counts) has begun: the review day itself counts from its first moment,
    /// because every night in the week ended before it. Always complete by construction.
    public static func latestWeekly(now: Date, weekday: Int, calendar: Calendar) -> ReviewPeriod {
        let today = today(now, calendar: calendar)
        let wanted = min(max(weekday, 1), 7)
        let todayWeekday = calendar.component(.weekday, from: now)
        let back = ((todayWeekday - wanted) % 7 + 7) % 7
        return weekly(reviewDate: today.adding(days: -back))
    }

    /// The previous calendar month, as of `now`'s date.
    public static func latestMonthly(now: Date, calendar: Calendar) -> ReviewPeriod {
        let today = today(now, calendar: calendar)
        return monthly(year: today.month == 1 ? today.year - 1 : today.year, month: today.month == 1 ? 12 : today.month - 1)
    }

    /// The period `id` names, or nil when the id is well formed but names no period (the 15th as the last morning of a month): an id from outside is never trusted.
    public static func period(for id: ReviewID) -> ReviewPeriod? {
        let period = ReviewPeriod(id)
        return period.id == id ? period : nil
    }

    /// The period whose id this is.
    public init(_ id: ReviewID) {
        switch id.kind {
        case .weekly: self = ReviewPeriod(kind: .weekly, firstMorning: id.lastMorning.adding(days: -6), lastMorning: id.lastMorning)
        case .monthly: self = Self.monthly(year: id.lastMorning.year, month: id.lastMorning.month)
        }
    }
}
