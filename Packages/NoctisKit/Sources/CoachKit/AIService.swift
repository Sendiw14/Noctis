import DesignSystem
import Foundation
import HomeFeature
import NoctisCore
import os

/// Coach's switches. `aiAppleIntelligence` is the kill switch for the
/// on-device model: off, every answer comes from the template.
public struct CoachFeatureFlags: Sendable, Equatable {
    public var aiCoach: Bool
    public var aiAppleIntelligence: Bool
    /// Off, and nothing in the app can turn it on: there is no remote model.
    public var aiRemote: Bool

    public init(aiCoach: Bool = true, aiAppleIntelligence: Bool = true, aiRemote: Bool = false) {
        self.aiCoach = aiCoach
        self.aiAppleIntelligence = aiAppleIntelligence
        self.aiRemote = aiRemote
    }
}

/// Why the template answered instead of a model.
public enum CoachFallbackReason: Sendable, Equatable, Hashable {
    /// No model, or not ready: the availability says why.
    case modelUnavailable(CoachAvailability)
    /// The `aiAppleIntelligence` flag is off.
    case modelSwitchedOff
    /// The model's draft was turned away (the validator's code, never its text).
    case validationFailed(String)
    /// The provider threw.
    case providerFailed
    /// The provider took longer than the timeout.
    case timedOut

    /// A word for a log line: nothing of any draft.
    public var code: String {
        switch self {
        case .modelUnavailable(let availability): "modelUnavailable.\(availability.rawValue)"
        case .modelSwitchedOff: "modelSwitchedOff"
        case .validationFailed(let code): "validationFailed.\(code)"
        case .providerFailed: "providerFailed"
        case .timedOut: "timedOut"
        }
    }
}

/// How an answer came to be, for logs and tests. Never any content.
public enum CoachOutcome: Sendable, Equatable {
    /// A fixed reply: no model, no data.
    case scripted(CoachScriptedReply)
    /// A model's draft passed validation.
    case model
    /// The template answered from the person's data.
    case template(CoachFallbackReason)
    /// Even the template's draft was turned away: a fixed apology.
    case unavailable

    public var code: String {
        switch self {
        case .scripted(let reply): "scripted.\(reply.rawValue)"
        case .model: "model"
        case .template(let reason): "template.\(reason.code)"
        case .unavailable: "unavailable"
        }
    }
}

public struct CoachResult: Sendable, Equatable {
    public let answer: CoachAnswer
    public let outcome: CoachOutcome
    /// The stored turn's id, when the exchange was kept (feedback is saved against it).
    public let messageID: UUID?

    public init(answer: CoachAnswer, outcome: CoachOutcome, messageID: UUID? = nil) {
        self.answer = answer
        self.outcome = outcome
        self.messageID = messageID
    }
}

/// Coach's one entry point: question in, validated answer out.
///
/// route → guards (crisis, medical, attempts to change the rules) → context →
/// a provider (the on-device model when it is available and its flag is on,
/// otherwise the template) → the safety validator → token resolution → a
/// `CoachAnswer`. When the model's draft is turned away, or it throws or is
/// too slow, the template answers instead, once. A model's raw text is never
/// displayed, streamed or logged: only a validated, resolved answer leaves.
public actor AIService {
    private let router: CoachQuestionRouter
    private let builder: CoachContextBuilder
    private let dataSource: any CoachDataSource
    private let profile: @Sendable () async -> UserProfileSnapshot
    private let model: (any AIProvider)?
    private let classifier: (any CoachIntentClassifying)?
    private let template: TemplateCoachProvider
    private let history: CoachHistoryStore?
    private let locale: Locale
    private let timeout: Duration
    public var flags: CoachFeatureFlags

    private let logger = Logger(subsystem: NoctisSignpost.subsystem, category: "Coach")
    private let signposter = OSSignposter(subsystem: NoctisSignpost.subsystem, category: "Coach")

    public init(
        router: CoachQuestionRouter = CoachQuestionRouter(),
        format: HomeFormat,
        dataSource: any CoachDataSource,
        profile: @escaping @Sendable () async -> UserProfileSnapshot,
        model: (any AIProvider)? = nil,
        classifier: (any CoachIntentClassifying)? = nil,
        history: CoachHistoryStore? = nil,
        flags: CoachFeatureFlags = CoachFeatureFlags(),
        timeout: Duration = FoundationModelsProvider.timeout
    ) {
        self.router = router
        builder = CoachContextBuilder(format: format)
        self.dataSource = dataSource
        self.profile = profile
        self.model = model
        self.classifier = classifier ?? (model as? any CoachIntentClassifying)
        template = TemplateCoachProvider(locale: format.locale)
        self.history = history
        locale = format.locale
        self.timeout = timeout
        self.flags = flags
    }

    /// The questions to suggest.
    public nonisolated var suggestedQuestions: [String] { router.suggestedQuestions }

    /// Answers `question`. With a `conversationID` (and a history store) the
    /// last two turns go into the context and the exchange is kept, unless it
    /// is a crisis exchange, which is never kept and never logged.
    public func answer(to question: String, conversationID: UUID? = nil) async -> CoachResult {
        let result = await resolve(question: question, conversationID: conversationID)
        // A crisis exchange is neither logged nor kept; a fixed reply is logged as its word and not kept.
        guard result.answer.intent != .crisis else { return result }
        log(result.outcome)
        guard result.answer.isStorable, let history, let conversationID,
              let id = await history.append(question: question, answer: result.answer, to: conversationID) else { return result }
        return CoachResult(answer: result.answer, outcome: result.outcome, messageID: id)
    }

    /// Whether the on-device model can answer right now (`.notConfigured`
    /// when the app has none): the hub says so when it can't.
    public func modelAvailability() -> CoachAvailability {
        guard flags.aiAppleIntelligence else { return .notConfigured }
        return model?.availability ?? .notConfigured
    }

    // MARK: - Steps

    private func resolve(question: String, conversationID: UUID?) async -> CoachResult {
        guard flags.aiCoach else { return scripted(.off) }
        let route = router.route(question)
        // Scripted routes never reach a model or the data.
        if let reply = route.reply, !route.mayClassify { return scripted(reply) }

        var intent = route.intent
        var direction = route.direction
        if route.mayClassify {
            switch await classify(question) {
            case .some(let classified) where classified.usesData:
                intent = classified
                direction = classified.hasDirection ? router.direction(of: CoachQuestionRouter.normalize(question)) : nil
            case .some(.crisis): return scripted(.crisis)
            case .some(.medicalOutOfScope): return scripted(.medical)
            default: return scripted(.unknown)
            }
        }

        let person = await profile()
        let snapshots = await dataSource.snapshots(profile: person)
        var context = builder.build(intent: intent, direction: direction, snapshots: snapshots, profile: person)
        if let history, let conversationID { context = context.withTurns(await history.recentTurns(in: conversationID)) }

        let interval = signposter.beginInterval("Answer")
        defer { signposter.endInterval("Answer", interval) }

        var reason: CoachFallbackReason
        if !flags.aiAppleIntelligence {
            reason = .modelSwitchedOff
        } else if let model, model.availability == .available {
            reason = .providerFailed
            let source = model.kind
            let asked = intent
            let raced = await CoachRace.run(timeout: timeout) { [context] in
                try await model.draft(question: question, intent: asked, context: context)
            }
            switch raced {
            case .value(let draft):
                switch assemble(draft, context: context, source: source) {
                case .success(let answer): return CoachResult(answer: answer, outcome: .model)
                case .failure(let failure): reason = .validationFailed(failure.code)
                }
            case .failed: reason = .providerFailed
            case .timedOut: reason = .timedOut
            }
        } else {
            reason = .modelUnavailable(model?.availability ?? .notConfigured)
        }

        // The template, once.
        let draft = template.compose(intent: intent, context: context)
        if case .success(let answer) = assemble(draft, context: context, source: template.kind) {
            return CoachResult(answer: answer, outcome: .template(reason))
        }
        return CoachResult(
            answer: CoachScriptedAnswers.answer(.unavailable, suggestions: router.suggestedQuestions), outcome: .unavailable
        )
    }

    /// The model's read on a question no pattern recognised, or nil.
    private func classify(_ question: String) async -> CoachIntent? {
        guard flags.aiAppleIntelligence, let classifier, classifier.classifierAvailability == .available else { return nil }
        let raced = await CoachRace.run(timeout: timeout) { try await classifier.classify(question: question) }
        if case .value(let intent) = raced { return intent }
        return nil
    }

    private func assemble(_ draft: CoachAnswerDraft, context: CoachContext, source: CoachSourceKind) -> Result<CoachAnswer, CoachAssemblyFailure> {
        if let failure = CoachSafetyValidator.validate(draft, context: context) { return .failure(.validation(failure)) }
        guard let answer = CoachAnswerAssembler.assemble(draft, context: context, source: source, locale: locale) else {
            return .failure(.unresolved)
        }
        return .success(answer)
    }

    private func scripted(_ reply: CoachScriptedReply) -> CoachResult {
        let suggestions = reply == .medical || reply == .crisis || reply == .off ? [] : router.suggestedQuestions
        return CoachResult(answer: CoachScriptedAnswers.answer(reply, suggestions: suggestions), outcome: .scripted(reply))
    }

    /// One line: an outcome word and nothing else.
    private func log(_ outcome: CoachOutcome) {
        logger.info("coach outcome \(outcome.code, privacy: .public)")
    }
}

enum CoachAssemblyFailure: Error {
    case validation(CoachValidationFailure)
    case unresolved

    var code: String {
        switch self {
        case .validation(let failure): failure.code
        case .unresolved: "unresolvedToken"
        }
    }
}

// MARK: - Timeout

enum CoachRaceResult<Value: Sendable>: Sendable {
    case value(Value)
    case failed
    case timedOut
}

/// Runs `work` against a clock. The first to finish wins; a provider that
/// ignores cancellation is left behind, never waited for, so the caller is
/// back within the timeout whatever the provider does.
enum CoachRace {
    static func run<Value: Sendable>(
        timeout: Duration, _ work: @escaping @Sendable () async throws -> Value
    ) async -> CoachRaceResult<Value> {
        await withCheckedContinuation { continuation in
            let box = Box(continuation)
            box.add(Task {
                do { box.finish(.value(try await work())) } catch { box.finish(.failed) }
            })
            box.add(Task {
                try? await Task.sleep(for: timeout)
                box.finish(.timedOut)
            })
        }
    }

    private final class Box<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<CoachRaceResult<Value>, Never>?
        private var tasks: [Task<Void, Never>] = []

        init(_ continuation: CheckedContinuation<CoachRaceResult<Value>, Never>) {
            self.continuation = continuation
        }

        func add(_ task: Task<Void, Never>) {
            let finished = lock.withLock {
                if continuation == nil { return true }
                tasks.append(task)
                return false
            }
            if finished { task.cancel() }
        }

        func finish(_ result: CoachRaceResult<Value>) {
            let (pending, running): (CheckedContinuation<CoachRaceResult<Value>, Never>?, [Task<Void, Never>]) = lock.withLock {
                defer {
                    continuation = nil
                    tasks = []
                }
                return (continuation, tasks)
            }
            guard let pending else { return }
            pending.resume(returning: result)
            for task in running { task.cancel() }
        }
    }
}

/// What the Coach screens need from the service, so a view model can be
/// driven by a stand-in in tests.
public protocol CoachAnswering: Sendable {
    func answer(to question: String, conversationID: UUID?) async -> CoachResult
    func modelAvailability() async -> CoachAvailability
}

extension AIService: CoachAnswering {}
