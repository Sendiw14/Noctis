import Foundation
import InsightsKit
import NoctisCore

// Coach's vocabulary. The model never writes a number: it points at facts by
// id ({{recovery.score}}) and the app puts the real, formatted value in after
// the draft has been checked. Nothing here holds a name, an account id, a
// raw HealthKit sample, a time of any one sample, a journal line or the name
// of the app or device a sample came from.

/// What a question is about.
public enum CoachIntent: String, Sendable, CaseIterable, Codable, Hashable {
    case recoveryChange
    case sleepChange
    case weekChange
    case bedtimeAdvice
    case consistencyHelp
    case todayFocus
    case patterns
    /// Diagnoses, conditions, medication, symptoms: answered with a script.
    case medicalOutOfScope
    /// Self-harm: answered with a script, never stored, never logged.
    case crisis
    case unknown

    /// Answered from the person's data.
    public var usesData: Bool {
        switch self {
        case .recoveryChange, .sleepChange, .weekChange, .bedtimeAdvice, .consistencyHelp, .todayFocus, .patterns: true
        case .medicalOutOfScope, .crisis, .unknown: false
        }
    }

    /// Whether "higher / lower / same" is part of the question.
    public var hasDirection: Bool {
        switch self {
        case .recoveryChange, .sleepChange, .weekChange: true
        default: false
        }
    }
}

public enum CoachDirection: String, Sendable, CaseIterable, Codable, Hashable {
    case higher
    case lower
    case same
}

public enum CoachConfidence: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    case low
    case moderate
    case high

    var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }

    public static func < (lhs: CoachConfidence, rhs: CoachConfidence) -> Bool { lhs.rank < rhs.rank }
}

/// Who wrote the answer.
public enum CoachSourceKind: String, Sendable, Codable, Hashable {
    /// The on-device model wrote a draft that passed validation.
    case appleIntelligence
    /// The app composed it from the person's own data (no model).
    case fromYourData
    /// A fixed, app-written reply (out of scope, crisis, unknown).
    case scripted
    /// A remote model (off; not built).
    case remoteModel
}

public enum CoachUnit: String, Sendable, Codable, Hashable {
    /// A score or a change in score.
    case points
    /// "6h 42m".
    case duration
    /// "55 min".
    case minutes
    /// "11:08 PM".
    case clock
    case milliseconds
    case beatsPerMinute
    case percent
    case count
}

/// One number Coach may refer to, with the words that say what it is.
public struct CoachFact: Sendable, Equatable, Codable, Identifiable {
    /// "recovery.score", "sleep.deltaVsBaseline"...
    public let id: String
    /// "Recovery score today".
    public let label: String
    /// The number, signed where it is a difference.
    public let value: Double
    public let unit: CoachUnit
    /// What replaces the token: formatted for the locale, through the same
    /// formatters the app uses. A difference shows its size only ("1h 10m"):
    /// the sentence says which way.
    public let display: String
    /// The same, for VoiceOver.
    public let spoken: String
    /// The engine it came from: "RecoveryEngine".
    public let source: String

    public init(id: String, label: String, value: Double, unit: CoachUnit, display: String, spoken: String, source: String) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
        self.display = display
        self.spoken = spoken
        self.source = source
    }
}

/// How much there is to go on.
public enum CoachDataState: String, Sendable, Codable, Hashable {
    /// Enough nights, and last night is in.
    case ready
    /// Under `CoachContextBuilder.learningNights` nights.
    case learning
    /// Data is current, but no sleep was recorded last night.
    case noSleepLastNight
    /// Apple Health hasn't updated for over a day.
    case stale
    /// No Health data (no permission, none on the device, none yet, or a failed read).
    case noData
}

public enum CoachMissingReason: String, Sendable, Codable, Hashable {
    /// Fewer nights than a baseline needs.
    case needsMoreNights
    /// The person's sources don't provide it.
    case notProvided
    /// Not recorded last night.
    case notRecorded
}

public struct CoachMissingFactor: Sendable, Equatable, Codable {
    /// "hrv", "restingHeartRate", "sleepDuration", "sleepConsistency".
    public let factor: String
    public let reason: CoachMissingReason

    public init(factor: String, reason: CoachMissingReason) {
        self.factor = factor
        self.reason = reason
    }
}

/// A top insight, by id, with the facts that carry its numbers.
public struct CoachInsightBrief: Sendable, Equatable, Codable {
    public let id: String
    public let type: InsightType
    public let confidence: InsightConfidence
    /// Facts in the context, "insight.<type>.<name>".
    public let factIDs: [String]

    public init(id: String, type: InsightType, confidence: InsightConfidence, factIDs: [String]) {
        self.id = id
        self.type = type
        self.confidence = confidence
        self.factIDs = factIDs
    }
}

/// Everything a provider is allowed to know for one question.
public struct CoachContext: Sendable, Equatable, Codable {
    /// Most facts a context holds.
    public static let maxFacts = 40
    /// Most insights a context holds.
    public static let maxInsights = 3
    /// Most earlier turns a context holds.
    public static let maxTurns = 2

    public let intent: CoachIntent
    public let direction: CoachDirection?
    /// In priority order, at most `maxFacts`; an absent fact is simply not here (never 0, never a guess).
    public let facts: [CoachFact]
    public let insights: [CoachInsightBrief]
    /// Recovery's factors that have a value: "sleepDuration", "hrv"...
    public let availableFactors: [String]
    public let missingFactors: [CoachMissingFactor]
    public let nightsOfHistory: Int
    /// The nights today's baseline is built from: the number Recovery's "Based on 14 nights" and the confidence line both print.
    public let baselineNights: Int
    public let dataState: CoachDataState
    /// `PrimaryGoal` raw values ("betterSleep"), never a name.
    public let goalIDs: [String]
    public let sleepNeedMinutes: Int
    /// The most confidence an answer may claim.
    public let confidenceCeiling: CoachConfidence
    /// The last `maxTurns` turns of this conversation, as plain summaries
    /// (the question and the answer's summary, never a model's own words).
    /// Only the on-device model reads them; a remote request never does.
    public private(set) var recentTurns: [CoachTurnSummary]

    public init(
        intent: CoachIntent, direction: CoachDirection?, facts: [CoachFact], insights: [CoachInsightBrief], availableFactors: [String],
        missingFactors: [CoachMissingFactor], nightsOfHistory: Int, dataState: CoachDataState, goalIDs: [String], sleepNeedMinutes: Int,
        confidenceCeiling: CoachConfidence, recentTurns: [CoachTurnSummary] = [], baselineNights: Int? = nil
    ) {
        self.intent = intent
        self.direction = direction
        self.facts = Array(facts.prefix(Self.maxFacts))
        self.insights = Array(insights.prefix(Self.maxInsights))
        self.availableFactors = availableFactors
        self.missingFactors = missingFactors
        self.nightsOfHistory = nightsOfHistory
        self.baselineNights = baselineNights ?? min(nightsOfHistory, 14)
        self.dataState = dataState
        self.goalIDs = goalIDs
        self.sleepNeedMinutes = sleepNeedMinutes
        self.confidenceCeiling = confidenceCeiling
        self.recentTurns = Array(recentTurns.suffix(Self.maxTurns))
    }

    /// The same context with the conversation's last turns.
    public func withTurns(_ turns: [CoachTurnSummary]) -> CoachContext {
        var copy = self
        copy.recentTurns = Array(turns.suffix(Self.maxTurns))
        return copy
    }

    public func fact(_ id: String) -> CoachFact? {
        facts.first { $0.id == id }
    }

    public func has(_ id: String) -> Bool { fact(id) != nil }

    public var factIDs: Set<String> { Set(facts.map(\.id)) }
}

// MARK: - Answers

public struct CoachDraftContributor: Sendable, Equatable, Codable {
    public var label: String
    public var factID: String

    public init(label: String, factID: String) {
        self.label = label
        self.factID = factID
    }
}

/// What a provider returns. Every string may hold {{fact.id}} tokens and no
/// digits; nothing here has been checked yet.
public struct CoachAnswerDraft: Sendable, Equatable, Codable {
    public var summary: String
    public var contributors: [CoachDraftContributor]
    public var whatChanged: String
    public var whatToNotice: String
    public var tonightSuggestion: String?
    public var pattern: String?
    /// Optional so a draft that leaves it out can be told apart from one that says it.
    public var confidence: CoachConfidence?
    public var caution: String?
    /// Route names: "recovery", "recovery:7d", "sleep:week", "insights:sleep".
    public var destinations: [String]

    public init(
        summary: String, contributors: [CoachDraftContributor] = [], whatChanged: String, whatToNotice: String,
        tonightSuggestion: String? = nil, pattern: String? = nil, confidence: CoachConfidence?, caution: String? = nil, destinations: [String] = []
    ) {
        self.summary = summary
        self.contributors = contributors
        self.whatChanged = whatChanged
        self.whatToNotice = whatToNotice
        self.tonightSuggestion = tonightSuggestion
        self.pattern = pattern
        self.confidence = confidence
        self.caution = caution
        self.destinations = destinations
    }
}

public struct CoachContributor: Sendable, Equatable, Codable {
    /// "Sleep, shorter than usual by".
    public let label: String
    /// "1h 10m", the real value.
    public let value: String
    /// The same, for VoiceOver: "1 hour 10 minutes".
    public let spoken: String
    public let factID: String

    public init(label: String, value: String, spoken: String? = nil, factID: String) {
        self.label = label
        self.value = value
        self.spoken = spoken ?? value
        self.factID = factID
    }

    private enum CodingKeys: String, CodingKey {
        case label, value, spoken, factID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        value = try container.decode(String.self, forKey: .value)
        spoken = try container.decodeIfPresent(String.self, forKey: .spoken) ?? value
        factID = try container.decode(String.self, forKey: .factID)
    }
}

public struct CoachHelpLink: Sendable, Equatable, Codable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

/// What the person sees: validated, every token resolved.
public struct CoachAnswer: Sendable, Equatable, Codable {
    public let sourceKind: CoachSourceKind
    public let intent: CoachIntent
    public let summary: String
    public let contributors: [CoachContributor]
    /// The one number the summary is about, when its sentence names it: shown large beside the summary.
    public let keyNumber: CoachContributor?
    public let whatChanged: String
    public let whatToNotice: String
    public let tonightSuggestion: String?
    public let pattern: String?
    /// "This is a pattern in your data, not proof of a cause." when there is a pattern; written by the app.
    public let patternNote: String?
    public let confidence: CoachConfidence
    /// "Moderate confidence · based on 9 nights": written by the app.
    public let confidenceLine: String
    public let caution: String?
    public let destinations: [AppRoute]
    /// Questions to try (a scripted "I can help with..." reply).
    public let suggestions: [String]
    /// "Find help", for the crisis reply.
    public let helpLink: CoachHelpLink?
    /// "Coach shares patterns from your data. It isn't medical advice."
    public let footer: String

    public init(
        sourceKind: CoachSourceKind, intent: CoachIntent, summary: String, contributors: [CoachContributor] = [], keyNumber: CoachContributor? = nil,
        whatChanged: String = "",
        whatToNotice: String = "", tonightSuggestion: String? = nil, pattern: String? = nil, patternNote: String? = nil,
        confidence: CoachConfidence, confidenceLine: String = "", caution: String? = nil, destinations: [AppRoute] = [],
        suggestions: [String] = [], helpLink: CoachHelpLink? = nil, footer: String
    ) {
        self.sourceKind = sourceKind
        self.intent = intent
        self.summary = summary
        self.contributors = contributors
        self.keyNumber = keyNumber
        self.whatChanged = whatChanged
        self.whatToNotice = whatToNotice
        self.tonightSuggestion = tonightSuggestion
        self.pattern = pattern
        self.patternNote = patternNote
        self.confidence = confidence
        self.confidenceLine = confidenceLine
        self.caution = caution
        self.destinations = destinations
        self.suggestions = suggestions
        self.helpLink = helpLink
        self.footer = footer
    }

    /// Every sentence in the answer, for a lint.
    public var allText: [String] {
        [summary, whatChanged, whatToNotice, confidenceLine, footer]
            + contributors.flatMap { [$0.label, $0.value] }
            + [tonightSuggestion, pattern, patternNote, caution].compactMap { $0 }
            + suggestions
    }
}

/// A past turn, as a plain summary (never the model's own words).
public struct CoachTurnSummary: Sendable, Equatable, Codable {
    public let question: String
    public let answerSummary: String

    public init(question: String, answerSummary: String) {
        self.question = question
        self.answerSummary = answerSummary
    }
}

/// Whether a provider can answer right now.
public enum CoachAvailability: String, Sendable, Codable, Hashable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    /// The system model doesn't support the person's language.
    case unsupportedLanguage
    /// A provider that has nothing to talk to (the remote model: not built).
    case notConfigured
}
