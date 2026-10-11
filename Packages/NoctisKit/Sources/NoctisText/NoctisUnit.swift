import Foundation

// QA part 3 (QA_COVERAGE.md 4, APP_RULES.md R68): the units NOCTIS prints beside a number and says aloud, in one place. Every symbol and every spoken
// form is read from this module's string catalog, so a translation changes them without touching a screen, and a language with more plural forms
// than English (Arabic has six) says "1 hour" and "11 hours" correctly. No other file spells a unit: `SourceHygieneTests` fails on `.unit("h")`.

public nonisolated enum NoctisUnit: Sendable, CaseIterable {
    case hour, minute, minuteShort, second, percent, beatsPerMinute, millisecond, point, pointShort, perWeek

    /// What is drawn small beside a number: "h", "m", "min", "s", "%", "bpm", "ms", "pts", "/ wk".
    public var symbol: String {
        #if DEBUG
        if let word = pseudoNoun.flatMap(NoctisPseudoScript.word) { return word }
        #endif
        return switch self {
        case .hour:
            String(localized: "unit.hour.symbol", defaultValue: "h", bundle: .module, comment: "The unit after a number of hours, drawn small beside it: '6h 42m'. As short as the language allows.")
        case .minute:
            String(localized: "unit.minute.symbol", defaultValue: "m", bundle: .module, comment: "The unit after a number of minutes beside hours: '6h 42m'. One letter where the language has one.")
        case .minuteShort:
            String(localized: "unit.minuteShort.symbol", defaultValue: "min", bundle: .module, comment: "The unit after a number of minutes on its own: '30 min'.")
        case .second:
            String(localized: "unit.second.symbol", defaultValue: "s", bundle: .module, comment: "The unit after a number of seconds: '20 s'.")
        case .percent:
            String(localized: "unit.percent.symbol", defaultValue: "%", bundle: .module, comment: "The percent sign after a number: '82%'. Keep the language's own spacing rule.")
        case .beatsPerMinute:
            String(localized: "unit.beatsPerMinute.symbol", defaultValue: "bpm", bundle: .module, comment: "The unit of a heart rate: '52 bpm'.")
        case .millisecond:
            String(localized: "unit.millisecond.symbol", defaultValue: "ms", bundle: .module, comment: "The unit of heart rate variability: '48 ms'.")
        case .point:
            String(localized: "unit.point.symbol", defaultValue: "points", bundle: .module, comment: "The unit after a number of recovery score points: '+4 points'.")
        case .pointShort:
            String(localized: "unit.pointShort.symbol", defaultValue: "pts", bundle: .module, comment: "The short unit after a number of recovery score points in a small tile: '62 pts'.")
        case .perWeek:
            String(localized: "unit.perWeek.symbol", defaultValue: "/ wk", bundle: .module, comment: "The unit of a rate of change per week: '+2 / wk'.")
        }
    }

    #if DEBUG
    private var pseudoNoun: String? {
        switch self {
        case .hour: "hour"
        case .minute, .minuteShort: "minute"
        case .second: "second"
        case .percent: "percent"
        case .beatsPerMinute: "beat"
        case .millisecond: nil
        case .point, .pointShort: "point"
        case .perWeek: "week"
        }
    }
    #endif

    /// What VoiceOver says for `count` of the unit: "1 hour", "11 hours".
    public func spoken(_ count: Int, locale: Locale = .current) -> String {
        #if DEBUG
        if let phrase = pseudoNoun.flatMap({ NoctisPseudoScript.phrase(count, $0) }) { return phrase }
        #endif
        return switch self {
        case .hour:
            String(localized: "unit.hour.spoken", defaultValue: "\(count) hours", bundle: .module, locale: locale, comment: "A number of hours, spoken. Has plural variations: '1 hour', '2 hours'.")
        case .minute, .minuteShort:
            String(localized: "unit.minute.spoken", defaultValue: "\(count) minutes", bundle: .module, locale: locale, comment: "A number of minutes, spoken. Has plural variations.")
        case .second:
            String(localized: "unit.second.spoken", defaultValue: "\(count) seconds", bundle: .module, locale: locale, comment: "A number of seconds, spoken. Has plural variations.")
        case .percent:
            String(localized: "unit.percent.spoken", defaultValue: "\(count) percent", bundle: .module, locale: locale, comment: "A percentage, spoken: '82 percent'.")
        case .beatsPerMinute:
            String(localized: "unit.beatsPerMinute.spoken", defaultValue: "\(count) beats per minute", bundle: .module, locale: locale, comment: "A heart rate, spoken. Has plural variations.")
        case .millisecond:
            String(localized: "unit.millisecond.spoken", defaultValue: "\(count) milliseconds", bundle: .module, locale: locale, comment: "Heart rate variability, spoken. Has plural variations.")
        case .point, .pointShort:
            String(localized: "unit.point.spoken", defaultValue: "\(count) points", bundle: .module, locale: locale, comment: "A number of recovery score points, spoken. Has plural variations.")
        case .perWeek:
            String(localized: "unit.perWeek.spoken", defaultValue: "\(count) per week", bundle: .module, locale: locale, comment: "A rate of change, spoken: '2 per week'.")
        }
    }
}
