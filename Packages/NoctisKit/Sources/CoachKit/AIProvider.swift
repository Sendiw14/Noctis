import Foundation

/// Something that can write a draft answer: the on-device model, the
/// template, a remote model (off), or a DEBUG mock. A provider only ever
/// returns a `CoachAnswerDraft`; nothing it writes reaches a person until the
/// safety validator has passed it and the app has put the numbers in.
public protocol AIProvider: Sendable {
    /// Who wrote what this provider returns.
    var kind: CoachSourceKind { get }
    /// Whether it can answer right now.
    var availability: CoachAvailability { get }
    func draft(question: String, intent: CoachIntent, context: CoachContext) async throws -> CoachAnswerDraft
}

/// Why a provider gave nothing.
public enum CoachProviderError: Error, Sendable, Equatable {
    case unavailable(CoachAvailability)
    case notConfigured
    /// The model answered in a way that can't be a draft (guardrails, refusal, decoding).
    case unusable
    case failed
}

/// A model that can classify a question no pattern recognised, restricted to
/// `CoachIntent`'s cases.
public protocol CoachIntentClassifying: Sendable {
    var classifierAvailability: CoachAvailability { get }
    func classify(question: String) async throws -> CoachIntent
}
