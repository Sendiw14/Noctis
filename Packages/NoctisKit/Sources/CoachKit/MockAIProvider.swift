#if DEBUG
import Foundation

/// DEBUG only: a provider that plays a script, for UI tests and for seeing
/// each failure the validator turns away (`-mockAI good|misbehaving|slow|unavailable`).
public final class MockAIProvider: AIProvider, @unchecked Sendable {
    public enum Mode: Sendable, Equatable {
        /// A good draft, as if the model wrote it.
        case good
        /// Each failure in turn, one per call.
        case misbehaving
        /// One failure, every call.
        case failing(Misbehavior)
        /// A good draft, after a long wait.
        case slow
        case unavailable
        /// Apple Intelligence is off in Settings (the one reason the person can fix).
        case notEnabled
        /// Throws.
        case throwing

        /// `-mockAI <value>`.
        public init?(launchValue: String) {
            switch launchValue {
            case "good": self = .good
            case "misbehaving": self = .misbehaving
            case "slow": self = .slow
            case "unavailable": self = .unavailable
            case "notEnabled": self = .notEnabled
            default: return nil
            }
        }
    }

    /// A way a model can go wrong, each one a validator rule.
    public enum Misbehavior: String, Sendable, CaseIterable {
        case diagnosis
        case causalClaim
        case digits
        case percentSign
        case numberWord
        case unknownToken
        case missingConfidence
        case missingCaution
        case overlong
        case unknownDestination
        case patternWithoutHedge
        case tooManyContributors
    }

    public let mode: Mode
    /// How long `.slow` waits.
    public let slowDuration: Duration
    private let template: TemplateCoachProvider
    private let lock = NSLock()
    private var calls = 0

    public init(mode: Mode, slowDuration: Duration = .seconds(60), locale: Locale = .current) {
        self.mode = mode
        self.slowDuration = slowDuration
        template = TemplateCoachProvider(locale: locale)
    }

    public var kind: CoachSourceKind { .appleIntelligence }
    public var availability: CoachAvailability {
        switch mode {
        case .unavailable: .deviceNotEligible
        case .notEnabled: .notEnabled
        default: .available
        }
    }

    /// How many drafts were asked for.
    public var callCount: Int { lock.withLock { calls } }

    public func draft(question: String, intent: CoachIntent, context: CoachContext) async throws -> CoachAnswerDraft {
        let index = lock.withLock {
            defer { calls += 1 }
            return calls
        }
        let good = template.compose(intent: intent, context: context)
        switch mode {
        case .good: return good
        case .unavailable: throw CoachProviderError.unavailable(.deviceNotEligible)
        case .notEnabled: throw CoachProviderError.unavailable(.notEnabled)
        case .throwing: throw CoachProviderError.failed
        case .slow:
            try await Task.sleep(for: slowDuration)
            return good
        case .misbehaving: return Self.spoil(good, Misbehavior.allCases[index % Misbehavior.allCases.count], context: context)
        case .failing(let kind): return Self.spoil(good, kind, context: context)
        }
    }

    /// `draft`, made wrong in one way.
    public static func spoil(_ draft: CoachAnswerDraft, _ kind: Misbehavior, context: CoachContext) -> CoachAnswerDraft {
        var bad = draft
        let factID = context.facts.first?.id ?? "recovery.score"
        switch kind {
        case .diagnosis: bad.summary = "This looks like insomnia."
        case .causalClaim: bad.whatChanged = "Your recovery is lower because you slept badly."
        case .digits: bad.summary = "You slept 7 hours last night."
        case .percentSign: bad.summary = "Your recovery is up by %."
        case .numberWord: bad.summary = "You slept for seven hours last night."
        case .unknownToken: bad.summary = "Your recovery is {{made.up.fact}} today."
        case .missingConfidence: bad.confidence = nil
        case .missingCaution:
            bad.confidence = .low
            bad.caution = nil
        case .overlong: bad.whatToNotice = String(repeating: "Notice how your energy holds up. ", count: 20)
        case .unknownDestination: bad.destinations = ["settings:secrets"]
        case .patternWithoutHedge: bad.pattern = "Late bedtimes go with lower recovery."
        case .tooManyContributors:
            bad.contributors = (0..<5).map { _ in CoachDraftContributor(label: "Factor", factID: factID) }
        }
        return bad
    }
}
#endif
