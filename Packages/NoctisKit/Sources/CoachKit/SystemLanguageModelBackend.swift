import Foundation

#if canImport(FoundationModels)
import FoundationModels

// The shapes the system model fills in. Plain strings and one enum: the app
// checks every word of them before a person sees any.

@Generable(description: "How much the data supports the answer")
enum GeneratedConfidence: String, CaseIterable {
    case high
    case moderate
    case low
}

@Generable(description: "One thing an answer rests on")
struct GeneratedContributor {
    @Guide(description: "A short label with no digits")
    var label: String
    @Guide(description: "The id of an allowed fact, without braces")
    var factID: String
}

@Generable(description: "An answer that explains a pattern in the person's own sleep and recovery data")
struct GeneratedCoachDraft {
    @Guide(description: "One or two hedged sentences that answer the question. Numbers only as tokens.")
    var summary: String
    @Guide(description: "What the answer rests on", .maximumCount(4))
    var contributors: [GeneratedContributor]
    @Guide(description: "What changed compared with the person's recent baseline. One short paragraph.")
    var whatChanged: String
    @Guide(description: "What the person could notice over the next days. One short paragraph.")
    var whatToNotice: String
    @Guide(description: "A gentle suggestion for tonight, if the data supports one")
    var tonightSuggestion: String?
    @Guide(description: "A hedged pattern in the data, if there is one")
    var pattern: String?
    var confidence: GeneratedConfidence
    @Guide(description: "Why confidence isn't high, when it isn't")
    var caution: String?
    @Guide(description: "Where in the app to look: recovery, sleep, sleep:week or insights", .maximumCount(3))
    var destinations: [String]

    var draft: CoachAnswerDraft {
        CoachAnswerDraft(
            summary: summary,
            contributors: contributors.map { CoachDraftContributor(label: $0.label, factID: $0.factID) },
            whatChanged: whatChanged,
            whatToNotice: whatToNotice,
            tonightSuggestion: tonightSuggestion,
            pattern: pattern,
            confidence: CoachConfidence(rawValue: confidence.rawValue),
            caution: caution,
            destinations: destinations
        )
    }
}

@Generable(description: "The topic of a question")
enum GeneratedIntent: String, CaseIterable {
    case recoveryChange
    case sleepChange
    case weekChange
    case bedtimeAdvice
    case consistencyHelp
    case todayFocus
    case patterns
    case medicalOutOfScope
    case crisis
    case unknown
}

/// The system language model (Apple Intelligence), one fresh session per call.
public struct SystemLanguageModelBackend: CoachModelBackend {
    public init() {}

    public var availability: CoachAvailability {
        Self.map(SystemLanguageModel.default)
    }

    static func map(_ model: SystemLanguageModel) -> CoachAvailability {
        switch model.availability {
        case .available:
            return model.supportsLocale() ? .available : .unsupportedLanguage
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .modelNotReady
        }
    }

    public func generateDraft(instructions: String, prompt: String, temperature: Double) async throws -> CoachAnswerDraft {
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt, generating: GeneratedCoachDraft.self, options: GenerationOptions(temperature: temperature)
            )
            return response.content.draft
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Guardrails, a refusal, a decoding failure, a context that is too
            // large: none of it is worth its own message. The caller answers
            // from the template.
            throw CoachProviderError.unusable
        }
    }

    public func classifyIntent(instructions: String, prompt: String) async throws -> CoachIntent {
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt, generating: GeneratedIntent.self, options: GenerationOptions(temperature: 0)
            )
            return CoachIntent(rawValue: response.content.rawValue) ?? .unknown
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CoachProviderError.unusable
        }
    }
}
#endif
