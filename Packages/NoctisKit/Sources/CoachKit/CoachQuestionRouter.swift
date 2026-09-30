import Foundation
import NoctisCore

/// What the router decided about a question.
public struct CoachRoute: Sendable, Equatable {
    public let intent: CoachIntent
    public let direction: CoachDirection?
    /// A fixed reply, when the question is not one the model or the data
    /// answers: out of scope, crisis, an attempt to change Coach's rules, a
    /// request for exact readings, or nothing Coach knows about.
    public let reply: CoachScriptedReply?

    public init(intent: CoachIntent, direction: CoachDirection? = nil, reply: CoachScriptedReply? = nil) {
        self.intent = intent
        self.direction = direction
        self.reply = reply
    }

    /// Only a question no pattern recognised may be sent to the model to
    /// classify; every scripted route stays scripted.
    public var mayClassify: Bool { intent == .unknown && reply == .unknown }
}

/// The fixed replies.
public enum CoachScriptedReply: String, Sendable, Codable, Hashable, CaseIterable {
    /// "I can help with questions about your sleep and recovery."
    case unknown
    case medical
    case crisis
    /// Asked to change the rules or play a role.
    case refused
    /// "What's my exact heart rate": Coach explains patterns, not readings.
    case exactReadings
    /// Nothing could be put together (a failure that even the template could not answer).
    case unavailable
    /// Coach is off (the aiCoach flag).
    case off
}

/// A deterministic keyword and pattern router. Every pattern and every word
/// of every scripted reply lives in the String Catalog (English now), so a
/// translation is a catalog change, not a code change. Nothing here calls a
/// model.
///
/// Order of precedence: crisis, medical, attempts to change the rules,
/// requests for exact readings, then the seven intents (a specific ask before
/// a general one).
public final class CoachQuestionRouter: @unchecked Sendable {
    private struct Rule {
        let intent: CoachIntent
        let regexes: [NSRegularExpression]
    }

    private let copy: @Sendable (String) -> String
    private let crisis: [NSRegularExpression]
    private let medical: [NSRegularExpression]
    private let injection: [NSRegularExpression]
    private let exact: [NSRegularExpression]
    private let rules: [Rule]
    private let higher: [NSRegularExpression]
    private let lower: [NSRegularExpression]
    private let same: [NSRegularExpression]

    /// The seven intents in the order they are tried.
    public static let intentOrder: [CoachIntent] = [
        .bedtimeAdvice, .consistencyHelp, .todayFocus, .patterns, .recoveryChange, .weekChange, .sleepChange,
    ]

    public init(copy: @escaping @Sendable (String) -> String = { CoachCopy.string($0) }) {
        self.copy = copy
        func compile(_ key: String) -> [NSRegularExpression] {
            copy(key).split(separator: "\n").compactMap { try? NSRegularExpression(pattern: String($0), options: [.caseInsensitive]) }
        }
        crisis = compile("coach.router.crisis")
        medical = compile("coach.router.medical")
        injection = compile("coach.router.injection")
        exact = compile("coach.router.exact")
        rules = Self.intentOrder.map { Rule(intent: $0, regexes: compile("coach.router.\($0.rawValue)")) }
        higher = compile("coach.router.direction.higher")
        lower = compile("coach.router.direction.lower")
        same = compile("coach.router.direction.same")
    }

    /// Lowercased words only: apostrophes and punctuation gone, spaces
    /// collapsed ("What's my  exact HR?" → "whats my exact hr").
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var out = ""
        for scalar in folded.unicodeScalars {
            if scalar == "'" || scalar == "\u{2019}" || scalar == "\u{2018}" || scalar == "`" { continue }
            out.unicodeScalars.append(CharacterSet.alphanumerics.contains(scalar) ? scalar : " ")
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    public func route(_ question: String) -> CoachRoute {
        let text = Self.normalize(question)
        guard !text.isEmpty else { return CoachRoute(intent: .unknown, reply: .unknown) }
        if matches(crisis, text) { return CoachRoute(intent: .crisis, reply: .crisis) }
        if matches(medical, text) { return CoachRoute(intent: .medicalOutOfScope, reply: .medical) }
        if matches(injection, text) { return CoachRoute(intent: .unknown, reply: .refused) }
        if matches(exact, text) { return CoachRoute(intent: .unknown, reply: .exactReadings) }
        for rule in rules where matches(rule.regexes, text) {
            return CoachRoute(intent: rule.intent, direction: rule.intent.hasDirection ? direction(of: text) : nil)
        }
        return CoachRoute(intent: .unknown, reply: .unknown)
    }

    /// Which way the question leans: nil when it doesn't, or leans both ways.
    public func direction(of text: String) -> CoachDirection? {
        let isHigher = matches(higher, text)
        let isLower = matches(lower, text)
        if isHigher != isLower { return isHigher ? .higher : .lower }
        if !isHigher && matches(same, text) { return .same }
        return nil
    }

    /// The six questions Coach suggests, and the intent each is read as.
    public static let suggestedIntents: [CoachIntent] = CoachQuestion.suggested.map(CoachQuestionText.intent(of:))

    /// The six questions Coach suggests, in order (neutral: no direction).
    public var suggestedQuestions: [String] {
        CoachQuestion.suggested.map { CoachQuestionText.text($0, copy: copy) }
    }

    private func matches(_ regexes: [NSRegularExpression], _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regexes.contains { $0.firstMatch(in: text, options: [], range: range) != nil }
    }
}

/// The fixed replies, as answers.
public enum CoachScriptedAnswers {
    public static func answer(
        _ reply: CoachScriptedReply, suggestions: [String] = [], copy: (String) -> String = { CoachCopy.string($0) }
    ) -> CoachAnswer {
        let key: String
        var intent = CoachIntent.unknown
        var help: CoachHelpLink?
        var suggested: [String] = []
        switch reply {
        case .unknown, .refused:
            key = "coach.script.unknown"
            suggested = suggestions
        case .exactReadings:
            key = "coach.script.exact"
            suggested = suggestions
        case .medical:
            key = "coach.script.medical"
            intent = .medicalOutOfScope
        case .crisis:
            key = "coach.script.crisis"
            intent = .crisis
            if let url = URL(string: copy("coach.script.crisis.help.url")) {
                help = CoachHelpLink(title: copy("coach.script.crisis.help.title"), url: url)
            }
        case .unavailable:
            key = "coach.script.unavailable"
            suggested = suggestions
        case .off:
            key = "coach.script.off"
        }
        return CoachAnswer(
            sourceKind: .scripted, intent: intent, summary: copy(key), confidence: .high,
            suggestions: suggested, helpLink: help, footer: copy("coach.footer")
        )
    }
}
