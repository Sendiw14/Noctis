import Foundation

// A remote model, as a shape and nothing more. There is no network code, no
// endpoint and no key in this file or anywhere in CoachKit; the `aiRemote`
// flag is off; and ROADMAP.md lists it as unbuilt. What exists is the part
// that has to be right before any remote model could be switched on: what a
// request may carry.

/// One fact, as a remote request carries it.
public struct RemoteFactDTO: Codable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let display: String
}

/// What a remote model would be sent: an intent and allowed facts, and
/// nothing else. Not the question the person typed, not earlier turns, not
/// goals, not the name of anything.
public struct RemoteModelRequest: Codable, Sendable, Equatable {
    public let intent: String
    public let direction: String?
    public let dataState: String
    public let confidenceCeiling: String
    public let nightsOfHistory: Int
    public let facts: [RemoteFactDTO]
}

/// What a remote model would send back: the fields of a draft.
public struct RemoteModelResponse: Codable, Sendable, Equatable {
    public struct Contributor: Codable, Sendable, Equatable {
        public let label: String
        public let factID: String
    }

    public let summary: String
    public let contributors: [Contributor]
    public let whatChanged: String
    public let whatToNotice: String
    public let tonightSuggestion: String?
    public let pattern: String?
    public let confidence: String?
    public let caution: String?
    public let destinations: [String]

    public init(
        summary: String, contributors: [Contributor], whatChanged: String, whatToNotice: String, tonightSuggestion: String?,
        pattern: String?, confidence: String?, caution: String?, destinations: [String]
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

    var draft: CoachAnswerDraft {
        CoachAnswerDraft(
            summary: summary,
            contributors: contributors.map { CoachDraftContributor(label: $0.label, factID: $0.factID) },
            whatChanged: whatChanged,
            whatToNotice: whatToNotice,
            tonightSuggestion: tonightSuggestion,
            pattern: pattern,
            confidence: confidence.flatMap(CoachConfidence.init(rawValue:)),
            caution: caution,
            destinations: destinations
        )
    }
}

/// What can leave the device, if a remote model is ever built: facts on the
/// allowed list (`CoachFactCatalog`), by id, label and display.
public enum RemotePrivacyFilter {
    public static func request(intent: CoachIntent, context: CoachContext) -> RemoteModelRequest {
        RemoteModelRequest(
            intent: intent.rawValue,
            direction: context.direction?.rawValue,
            dataState: context.dataState.rawValue,
            confidenceCeiling: context.confidenceCeiling.rawValue,
            nightsOfHistory: context.nightsOfHistory,
            facts: context.facts.filter { CoachFactCatalog.allows($0.id) }.map { RemoteFactDTO(id: $0.id, label: $0.label, display: $0.display) }
        )
    }
}

/// Something that could carry a `RemoteModelRequest` somewhere. Nothing in the
/// app conforms to it.
public protocol RemoteModelTransport: Sendable {
    func send(_ request: RemoteModelRequest) async throws -> RemoteModelResponse
}

/// The conformance, with no transport behind it: unavailable until one
/// exists, and never chosen while the `aiRemote` flag is off.
public struct RemoteModelProvider: AIProvider {
    private let transport: (any RemoteModelTransport)?

    public init(transport: (any RemoteModelTransport)? = nil) {
        self.transport = transport
    }

    public var kind: CoachSourceKind { .remoteModel }
    public var availability: CoachAvailability { transport == nil ? .notConfigured : .available }

    public func draft(question: String, intent: CoachIntent, context: CoachContext) async throws -> CoachAnswerDraft {
        guard let transport else { throw CoachProviderError.notConfigured }
        // The question is not sent: the intent and the allowed facts are all a remote model gets.
        return try await transport.send(RemotePrivacyFilter.request(intent: intent, context: context)).draft
    }
}
