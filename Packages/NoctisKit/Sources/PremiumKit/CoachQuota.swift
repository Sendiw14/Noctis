import Foundation

// The free Coach questions (APP_RULES.md R57, R60): three a day on the local calendar, counted only when a real answer is delivered. Pure: the day's key, the
// count and "now" in, the new count out, so the rollover at midnight, a daylight saving change and a change of time zone are unit tests.

public nonisolated struct CoachQuotaState: Sendable, Equatable {
    /// The local calendar day the count is for, "2026-09-24"; empty before any question.
    public var day: String
    public var used: Int

    public init(day: String = "", used: Int = 0) {
        self.day = day
        self.used = max(used, 0)
    }

    /// The stored form: "2026-09-24|2".
    public var stored: String { "\(day)|\(used)" }

    public init?(stored: String) {
        let parts = stored.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let used = Int(parts[1]), used >= 0 else { return nil }
        self.init(day: String(parts[0]), used: used)
    }
}

public nonisolated enum CoachQuota {
    /// The free questions a day.
    public static let freeQuestionsPerDay = 3

    /// The local calendar date of `now`, as a sortable key.
    public static func dayKey(_ now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The count for the day `now` falls in: a later day starts again at zero; an earlier one (the clock or the time zone went back) keeps the day already
    /// counted, so changing time zone is never a way to more questions.
    public static func current(_ state: CoachQuotaState, now: Date, calendar: Calendar) -> CoachQuotaState {
        let key = dayKey(now, calendar: calendar)
        if state.day.isEmpty || key > state.day { return CoachQuotaState(day: key, used: 0) }
        return state
    }

    public static func remaining(_ state: CoachQuotaState, now: Date, calendar: Calendar) -> Int {
        max(freeQuestionsPerDay - current(state, now: now, calendar: calendar).used, 0)
    }

    /// One more answer delivered.
    public static func recording(_ state: CoachQuotaState, now: Date, calendar: Calendar) -> CoachQuotaState {
        var next = current(state, now: now, calendar: calendar)
        next.used += 1
        return next
    }

    /// "2 of 3 free questions left today".
    public static func line(remaining: Int) -> String {
        "\(remaining) of \(freeQuestionsPerDay) free \(freeQuestionsPerDay == 1 ? "question" : "questions") left today"
    }

    public static let usedUpTitle = "You've used today's free questions."
    public static let usedUpDetail = "They reset at midnight."
}
