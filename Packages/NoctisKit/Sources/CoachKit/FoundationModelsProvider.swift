import Foundation

/// What `FoundationModelsProvider` needs from the system model: one guided
/// generation per call, on a session made for that call. The real one is
/// `SystemLanguageModelBackend`; tests use a fake, so the provider's logic is
/// covered on machines that have no model.
public protocol CoachModelBackend: Sendable {
    var availability: CoachAvailability { get }
    /// A fresh session: `instructions`, one prompt, a draft as guided generation.
    func generateDraft(instructions: String, prompt: String, temperature: Double) async throws -> CoachAnswerDraft
    /// A fresh session that can only answer with a `CoachIntent` case.
    func classifyIntent(instructions: String, prompt: String) async throws -> CoachIntent
}

/// The on-device model (Apple Intelligence): guided generation into a
/// `CoachAnswerDraft`. A fresh, short session per turn; only the last two
/// turns go in, as plain summaries; low temperature. The draft is only a
/// draft: the validator decides whether anything of it is shown.
public struct FoundationModelsProvider: AIProvider, CoachIntentClassifying {
    /// Longest a turn may take before Coach answers from the template instead.
    public static let timeout: Duration = .seconds(15)
    public static let temperature = 0.2

    private let backend: any CoachModelBackend

    public init(backend: any CoachModelBackend) {
        self.backend = backend
    }

    public var kind: CoachSourceKind { .appleIntelligence }
    public var availability: CoachAvailability { backend.availability }
    public var classifierAvailability: CoachAvailability { backend.availability }

    public func draft(question: String, intent: CoachIntent, context: CoachContext) async throws -> CoachAnswerDraft {
        guard backend.availability == .available else { throw CoachProviderError.unavailable(backend.availability) }
        return try await backend.generateDraft(
            instructions: CoachPrompt.instructions(context: context),
            prompt: CoachPrompt.prompt(question: question, intent: intent, context: context),
            temperature: Self.temperature
        )
    }

    public func classify(question: String) async throws -> CoachIntent {
        guard backend.availability == .available else { throw CoachProviderError.unavailable(backend.availability) }
        return try await backend.classifyIntent(instructions: CoachPrompt.classifierInstructions, prompt: "Question: \(question)")
    }
}
