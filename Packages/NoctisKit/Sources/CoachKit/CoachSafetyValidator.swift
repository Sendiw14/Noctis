import Foundation
import InsightsKit
import NoctisCore

/// Why a draft was turned away. Typed, never shown to the person, never
/// logged with the text that caused it: `code` is all a log line holds.
public enum CoachValidationFailure: Sendable, Equatable, Hashable {
    /// A required field is empty or absent ("summary", "whatChanged", "whatToNotice", "confidence").
    case missingField(String)
    /// A field is over its limit.
    case tooLong(field: String)
    case tooManyContributors
    case tooManyDestinations
    /// Confidence isn't high and there is no caution.
    case cautionRequired
    /// A digit, a percent sign or a number word outside a token.
    case digitInText(field: String)
    case percentInText(field: String)
    case numberWordInText(field: String)
    /// A token names a fact that isn't in the context, or a contributor points at one.
    case unknownToken(String)
    /// A `{{` or `}}` that isn't a whole token.
    case malformedToken(field: String)
    /// One of the words Coach never says.
    case bannedLanguage(term: String, field: String)
    /// A pattern that doesn't hedge.
    case patternWithoutHedge
    /// A destination that isn't an `AppRoute`.
    case unknownDestination(String)

    /// A stable word for logs: no text of the draft, no fact id.
    public var code: String {
        switch self {
        case .missingField: "missingField"
        case .tooLong: "tooLong"
        case .tooManyContributors: "tooManyContributors"
        case .tooManyDestinations: "tooManyDestinations"
        case .cautionRequired: "cautionRequired"
        case .digitInText: "digitInText"
        case .percentInText: "percentInText"
        case .numberWordInText: "numberWordInText"
        case .unknownToken: "unknownToken"
        case .malformedToken: "malformedToken"
        case .bannedLanguage: "bannedLanguage"
        case .patternWithoutHedge: "patternWithoutHedge"
        case .unknownDestination: "unknownDestination"
        }
    }
}

/// Checks a draft before anything of it reaches a person. Pure: the same
/// draft and context always give the same answer.
public enum CoachSafetyValidator {
    /// Longest summary, and longest of every other field, as a person will read it.
    public static let summaryLimit = 220
    public static let fieldLimit = 280
    public static let labelLimit = 60
    public static let maxContributors = 4
    public static let maxDestinations = 3

    /// Phrases that make a pattern a hedge, matched on lowercased text.
    public static let hedges = ["suggests", "has coincided with", "have coincided with", "coincided with", "compared with your recent baseline"]

    /// Words for numbers, matched as whole words on lowercased text.
    public static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen",
        "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty",
        "seventy", "eighty", "ninety", "hundred", "thousand", "million", "billion", "half", "dozen", "percent",
    ]

    /// The words no answer may contain: one list, shared with Insights.
    public static let bannedTerms = BannedLanguage.coach

    /// Every reason `draft` is turned away; empty when it is fine.
    public static func failures(_ draft: CoachAnswerDraft, context: CoachContext) -> [CoachValidationFailure] {
        var failures: [CoachValidationFailure] = []
        func add(_ failure: CoachValidationFailure) {
            if !failures.contains(failure) { failures.append(failure) }
        }
        let facts = Dictionary(context.facts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func blank(_ text: String?) -> Bool { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // Structure: every field there, none too long.
        let fields: [(name: String, text: String?, limit: Int, required: Bool)] = [
            ("summary", draft.summary, summaryLimit, true),
            ("whatChanged", draft.whatChanged, fieldLimit, true),
            ("whatToNotice", draft.whatToNotice, fieldLimit, true),
            ("tonightSuggestion", draft.tonightSuggestion, fieldLimit, false),
            ("pattern", draft.pattern, fieldLimit, false),
            ("caution", draft.caution, fieldLimit, false),
        ]
        for field in fields {
            if blank(field.text) && (field.required || field.text != nil) { add(.missingField(field.name)) }
            if CoachTokens.visibleLength(field.text ?? "", facts: facts) > field.limit { add(.tooLong(field: field.name)) }
        }
        if draft.contributors.count > maxContributors { add(.tooManyContributors) }
        for (index, contributor) in draft.contributors.enumerated() {
            if blank(contributor.label) { add(.missingField("contributors[\(index)]")) }
            if contributor.label.count > labelLimit { add(.tooLong(field: "contributors[\(index)]")) }
            if facts[contributor.factID] == nil { add(.unknownToken(contributor.factID)) }
        }
        if let confidence = draft.confidence {
            if confidence != .high && blank(draft.caution) { add(.cautionRequired) }
        } else {
            add(.missingField("confidence"))
        }

        // Words: what the model wrote, with the tokens taken out, holds no
        // number, no percent sign, no number word and none of the banned language.
        var written: [(name: String, text: String)] = fields.compactMap { field in field.text.map { (field.name, $0) } }
        for (index, contributor) in draft.contributors.enumerated() { written.append(("contributors[\(index)]", contributor.label)) }
        for (name, text) in written {
            for id in CoachTokens.ids(in: text) where facts[id] == nil { add(.unknownToken(id)) }
            if CoachTokens.hasMalformedBraces(text) { add(.malformedToken(field: name)) }
            let own = CoachTokens.stripped(text)
            if own.contains(where: \.isNumber) { add(.digitInText(field: name)) }
            if own.contains(where: { "%\u{FF05}\u{2030}\u{066A}".contains($0) }) { add(.percentInText(field: name)) }
            let words = own.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            if words.contains(where: numberWords.contains) { add(.numberWordInText(field: name)) }
            if let term = BannedLanguage.hits(in: own, of: bannedTerms).first { add(.bannedLanguage(term: term, field: name)) }
        }

        // A pattern must hedge.
        if let pattern = draft.pattern, !hedges.contains(where: pattern.lowercased().contains) { add(.patternWithoutHedge) }

        // Destinations are screens about the person's data that the app has: never Settings, which Coach has nothing to say about.
        if draft.destinations.count > maxDestinations { add(.tooManyDestinations) }
        for name in draft.destinations where AppRoute.coachDestination(named: name) == nil { add(.unknownDestination(name)) }
        return failures
    }

    /// The first reason, or nil when the draft is fine.
    public static func validate(_ draft: CoachAnswerDraft, context: CoachContext) -> CoachValidationFailure? {
        failures(draft, context: context).first
    }
}

extension AppRoute {
    /// The route a name stands for, if Coach may point at it: any screen but Settings (Coach answers about sleep and
    /// recovery; it never sends anyone to change a setting).
    public static func coachDestination(named name: String) -> AppRoute? {
        guard let route = AppRoute(name: name) else { return nil }
        if case .settings = route { return nil }
        return route
    }
}
