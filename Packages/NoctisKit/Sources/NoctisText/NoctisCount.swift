import Foundation

// QA part 3 (QA_COVERAGE.md 4, APP_RULES.md R68): a count and what it counts, with the language's plural: "1 night", "2 nights". Each phrase is one key of
// this module's string catalog with plural variations (one, other; a language adds few, many, zero, two), so no screen decides that 1 is singular.
// Phrases that sit inside a sentence ("other nights", "minutes left") are their own keys: a translator reorders the sentence, not a suffix.

public nonisolated enum NoctisCount: Sendable {
    /// "1 night", "7 nights".
    public static func nights(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "night") { return phrase }
        #endif
        return String(localized: "count.nights", defaultValue: "\(count) nights", bundle: .module, locale: locale, comment: "A number of nights, as in '14 nights'. Plural variations: one, other.")
    }

    /// "1 hour", "8 hours".
    public static func hours(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "hour") { return phrase }
        #endif
        return String(localized: "count.hours", defaultValue: "\(count) hours", bundle: .module, locale: locale, comment: "A number of hours, as in '8 hours'. Plural variations: one, other.")
    }

    /// "1 minute", "45 minutes".
    public static func minutes(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "minute") { return phrase }
        #endif
        return String(localized: "count.minutes", defaultValue: "\(count) minutes", bundle: .module, locale: locale, comment: "A number of minutes, as in '45 minutes'. Plural variations: one, other.")
    }

    /// "1 second", "20 seconds".
    public static func seconds(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "second") { return phrase }
        #endif
        return String(localized: "count.seconds", defaultValue: "\(count) seconds", bundle: .module, locale: locale, comment: "A number of seconds, as in '20 seconds'. Plural variations: one, other.")
    }

    /// "1 day", "30 days".
    public static func days(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "day") { return phrase }
        #endif
        return String(localized: "count.days", defaultValue: "\(count) days", bundle: .module, locale: locale, comment: "A number of days, as in '30 days'. Plural variations: one, other.")
    }

    /// "1 insight", "5 insights".
    public static func insights(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "insight") { return phrase }
        #endif
        return String(localized: "count.insights", defaultValue: "\(count) insights", bundle: .module, locale: locale, comment: "A number of insights, as in '5 insights'. Plural variations: one, other.")
    }

    /// "1 question", "3 questions".
    public static func questions(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "question") { return phrase }
        #endif
        return String(localized: "count.questions", defaultValue: "\(count) questions", bundle: .module, locale: locale, comment: "A number of questions asked of Coach, as in '3 questions'. Plural variations: one, other.")
    }

    /// "1 awakening", "3 awakenings".
    public static func awakenings(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "awakening") { return phrase }
        #endif
        return String(localized: "count.awakenings", defaultValue: "\(count) awakenings", bundle: .module, locale: locale, comment: "A number of times the person woke in the night, as in '3 awakenings'. Plural variations: one, other.")
    }

    /// "1 value", "4 values".
    public static func values(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "value") { return phrase }
        #endif
        return String(localized: "count.values", defaultValue: "\(count) values", bundle: .module, locale: locale, comment: "A number of saved settings, as in '4 values'. Plural variations: one, other.")
    }

    /// "1 reminder on", "3 reminders on".
    public static func remindersOn(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "reminder") { return phrase }
        #endif
        return String(localized: "count.remindersOn", defaultValue: "\(count) reminders on", bundle: .module, locale: locale, comment: "How many reminders are switched on, as in '3 reminders on'. Plural variations: one, other.")
    }

    /// "1 other night", "2 other nights": a record that was equalled on other nights.
    public static func otherNights(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "night") { return phrase }
        #endif
        return String(localized: "count.otherNights", defaultValue: "\(count) other nights", bundle: .module, locale: locale, comment: "A number of other nights, inside a sentence about a record that was equalled: 'Equalled on 2 other nights'. Plural variations: one, other.")
    }

    /// "1 more night", "4 more nights": what is still needed before something is ready.
    public static func moreNights(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "night") { return phrase }
        #endif
        return String(localized: "count.moreNights", defaultValue: "\(count) more nights", bundle: .module, locale: locale, comment: "A number of further nights still needed, inside a sentence: '3 more nights of tracking'. Plural variations: one, other.")
    }

    /// "1 minute left", "9 minutes left".
    public static func minutesLeft(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "minute") { return phrase }
        #endif
        return String(localized: "count.minutesLeft", defaultValue: "\(count) minutes left", bundle: .module, locale: locale, comment: "Time remaining in minutes: '9 minutes left'. Plural variations: one, other.")
    }

    /// "1 second left", "20 seconds left".
    public static func secondsLeft(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "second") { return phrase }
        #endif
        return String(localized: "count.secondsLeft", defaultValue: "\(count) seconds left", bundle: .module, locale: locale, comment: "Time remaining in seconds: '20 seconds left'. Plural variations: one, other.")
    }

    /// "1 free question", "3 free questions".
    public static func freeQuestions(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = NoctisPseudoScript.phrase(count, "question") { return phrase }
        #endif
        return String(localized: "count.freeQuestions", defaultValue: "\(count) free questions", bundle: .module, locale: locale, comment: "A number of free Coach questions in a day: '3 free questions'. Plural variations: one, other.")
    }

    /// A length of time a subscription offer is made in.
    public enum Period: Sendable { case day, month, year }

    /// "7 days", "1 month", "1 year".
    public static func period(_ count: Int, _ period: Period, locale: Locale = .current) -> String {
        switch period {
        case .day: days(count, locale: locale)
        case .month: String(localized: "count.months", defaultValue: "\(count) months", bundle: .module, locale: locale, comment: "A number of months, as in '3 months'. Plural variations: one, other.")
        case .year: String(localized: "count.years", defaultValue: "\(count) years", bundle: .module, locale: locale, comment: "A number of years, as in '1 year'. Plural variations: one, other.")
        }
    }

    /// "7-day", "1-month": a length of time used as an adjective ("a 7-day free trial").
    public static func adjective(_ count: Int, _ period: Period, locale: Locale = .current) -> String {
        switch period {
        case .day: String(localized: "count.adjective.days", defaultValue: "\(count)-day", bundle: .module, locale: locale, comment: "A number of days as an adjective before a noun: 'a 7-day free trial'.")
        case .month: String(localized: "count.adjective.months", defaultValue: "\(count)-month", bundle: .module, locale: locale, comment: "A number of months as an adjective before a noun: 'a 1-month free trial'.")
        case .year: String(localized: "count.adjective.years", defaultValue: "\(count)-year", bundle: .module, locale: locale, comment: "A number of years as an adjective before a noun: 'a 1-year plan'.")
        }
    }

    /// The monthly review's insights page headline, which names no number: "An insight from this month." or "Insights from this month."
    public static func insightsFromThisMonth(_ count: Int, locale: Locale = .current) -> String {
        count == 1
            ? String(localized: "review.insights.headline.one", defaultValue: "An insight from this month.", bundle: .module, locale: locale, comment: "The headline of the monthly review's insights page when exactly one insight is shown.")
            : String(localized: "review.insights.headline.other", defaultValue: "Insights from this month.", bundle: .module, locale: locale, comment: "The headline of the monthly review's insights page when more than one insight is shown.")
    }

    /// The small caption over a review's insights: "Insight" or "Insights".
    public static func insightCaption(_ count: Int, locale: Locale = .current) -> String {
        count == 1
            ? String(localized: "review.insight.caption.one", defaultValue: "Insight", bundle: .module, locale: locale, comment: "A caption over exactly one insight in a review story.")
            : String(localized: "review.insight.caption.other", defaultValue: "Insights", bundle: .module, locale: locale, comment: "A caption over several insights in a review story.")
    }
}
