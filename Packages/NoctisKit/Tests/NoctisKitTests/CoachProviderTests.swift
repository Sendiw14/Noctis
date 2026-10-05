import Foundation
import Testing
@testable import InsightsKit
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import AppRoot
@testable import CoachKit
@testable import HomeFeature
@testable import NoctisCore

/// A stand-in for the system model: records each call, answers as told.
nonisolated private final class FakeBackend: CoachModelBackend, @unchecked Sendable {
    struct Call: Sendable {
        let instructions: String
        let prompt: String
        let temperature: Double?
    }

    let availability: CoachAvailability
    private let draftResult: Result<CoachAnswerDraft, any Error>
    private let intentResult: Result<CoachIntent, any Error>
    private let lock = NSLock()
    private var recorded: [Call] = []

    init(
        availability: CoachAvailability = .available, draft: Result<CoachAnswerDraft, any Error> = .failure(CoachProviderError.failed),
        intent: Result<CoachIntent, any Error> = .success(.unknown)
    ) {
        self.availability = availability
        draftResult = draft
        intentResult = intent
    }

    var calls: [Call] { lock.withLock { recorded } }

    func generateDraft(instructions: String, prompt: String, temperature: Double) async throws -> CoachAnswerDraft {
        lock.withLock { recorded.append(Call(instructions: instructions, prompt: prompt, temperature: temperature)) }
        return try draftResult.get()
    }

    func classifyIntent(instructions: String, prompt: String) async throws -> CoachIntent {
        lock.withLock { recorded.append(Call(instructions: instructions, prompt: prompt, temperature: nil)) }
        return try intentResult.get()
    }
}

struct CoachFoundationModelsProviderTests {
    private let draft = CoachAnswerDraft(summary: "Your recovery is {{recovery.score}}.", whatChanged: "x", whatToNotice: "y", confidence: .high)

    // MARK: - The prompt

    @Test func theInstructionsHoldTheRulesTheBannedWordsAndTheAllowedFacts() async {
        let context = await CoachFixture.context(.recoveryChange, .lower)
        let text = CoachPrompt.instructions(context: context)
        #expect(text.contains("Explain patterns in the person's own data"))
        #expect(text.contains("never diagnose") || text.contains("Never diagnose"))
        #expect(text.contains("Never write digits"))
        #expect(text.contains("{{"))
        #expect(text.contains("your data suggests") && text.contains("has coincided with") && text.contains("compared with your recent baseline"))
        for term in BannedLanguage.coach { #expect(text.contains(term), Comment(rawValue: term)) }
        for fact in context.facts {
            #expect(text.contains("{{\(fact.id)}}: \(fact.label) = \(fact.display)"), Comment(rawValue: fact.id))
        }
        #expect(text.contains("can't be higher than \(context.confidenceCeiling.rawValue)"))
    }

    @Test func theInstructionsOnlyListFactsInTheContext() async {
        let context = await CoachFixture.context(.sleepChange)
        let text = CoachPrompt.instructions(context: context)
        #expect(!text.contains("{{recovery.score}}: "), "sleep's slice has no recovery score")
        #expect(text.contains("{{sleep.duration}}: "))
        let empty = CoachPrompt.instructions(context: await CoachFixture.context(.recoveryChange, scenario: .empty))
        #expect(empty.contains("There are no allowed facts"))
    }

    @Test func theInstructionsNeverHoldTheNameOrAGoalTitle() async {
        for intent in CoachQuestionRouter.intentOrder {
            let context = await CoachFixture.context(intent, nil)
            let all = CoachPrompt.instructions(context: context) + CoachPrompt.prompt(question: "q", intent: intent, context: context)
            #expect(!all.contains("Alex") && !all.contains("Tester"))
        }
    }

    @Test func thePromptHasTheQuestionTheTopicAndTheDirection() async {
        let context = await CoachFixture.context(.recoveryChange, .lower)
        let prompt = CoachPrompt.prompt(question: "Why is my recovery lower?", intent: .recoveryChange, context: context)
        #expect(prompt.contains("Question: Why is my recovery lower?"))
        #expect(prompt.contains("Topic: recoveryChange"))
        #expect(prompt.contains("lower"))
        #expect(!prompt.contains("Earlier in this conversation"))
    }

    @Test func onlyTheLastTwoTurnsGoIn() async {
        let turns = (1...5).map { CoachTurnSummary(question: "question-\($0)", answerSummary: "summary-\($0)") }
        let context = await CoachFixture.context(.weekChange).withTurns(turns)
        let prompt = CoachPrompt.prompt(question: "next", intent: .weekChange, context: context)
        #expect(prompt.contains("question-4") && prompt.contains("summary-4") && prompt.contains("question-5") && prompt.contains("summary-5"))
        #expect(!prompt.contains("question-3") && !prompt.contains("question-1"))
    }

    // MARK: - The provider

    @Test func eachDraftIsOneFreshSessionAtLowTemperature() async throws {
        let backend = FakeBackend(draft: .success(draft))
        let provider = FoundationModelsProvider(backend: backend)
        let context = await CoachFixture.context(.recoveryChange)
        let first = try await provider.draft(question: "one", intent: .recoveryChange, context: context)
        _ = try await provider.draft(question: "two", intent: .recoveryChange, context: context)
        #expect(first == draft)
        #expect(backend.calls.count == 2, "one backend call, so one session, per draft")
        #expect(backend.calls.map { $0.prompt.contains("Question: one") } == [true, false])
        #expect(backend.calls.allSatisfy { ($0.temperature ?? 1) <= 0.3 })
        #expect(backend.calls.allSatisfy { $0.instructions == backend.calls[0].instructions })
    }

    @Test func aDraftFromTheProviderIsOnlyADraft() async throws {
        // A model that writes a number, a diagnosis or an unknown token gets no further than the validator.
        let bad = CoachAnswerDraft(summary: "You slept 7 hours, which looks like insomnia {{made.up}}.", whatChanged: "a", whatToNotice: "b", confidence: .high)
        let provider = FoundationModelsProvider(backend: FakeBackend(draft: .success(bad)))
        let context = await CoachFixture.context(.sleepChange)
        let received = try await provider.draft(question: "q", intent: .sleepChange, context: context)
        let failures = CoachSafetyValidator.failures(received, context: context)
        #expect(failures.count >= 3)
    }

    @Test(arguments: [CoachAvailability.deviceNotEligible, .notEnabled, .modelNotReady, .unsupportedLanguage, .notConfigured])
    func anUnavailableModelIsNotAsked(_ availability: CoachAvailability) async {
        let backend = FakeBackend(availability: availability, draft: .success(draft))
        let provider = FoundationModelsProvider(backend: backend)
        #expect(provider.availability == availability)
        await #expect(throws: CoachProviderError.unavailable(availability)) {
            try await provider.draft(question: "q", intent: .recoveryChange, context: CoachFixture.handmade())
        }
        await #expect(throws: CoachProviderError.unavailable(availability)) { try await provider.classify(question: "q") }
        #expect(backend.calls.isEmpty)
    }

    @Test func theProviderIsAppleIntelligenceAndAvailableWhenTheBackendIs() {
        let provider = FoundationModelsProvider(backend: FakeBackend())
        #expect(provider.kind == .appleIntelligence)
        #expect(provider.availability == .available)
        #expect(provider.classifierAvailability == .available)
    }

    @Test func aBackendFailureSurfacesAsAnError() async {
        let provider = FoundationModelsProvider(backend: FakeBackend(draft: .failure(CoachProviderError.unusable)))
        await #expect(throws: CoachProviderError.unusable) {
            try await provider.draft(question: "q", intent: .recoveryChange, context: CoachFixture.handmade())
        }
    }

    // MARK: - Classification

    @Test func classificationIsOneCallWithTheClassifierInstructions() async throws {
        let backend = FakeBackend(intent: .success(.todayFocus))
        let provider = FoundationModelsProvider(backend: backend)
        let intent = try await provider.classify(question: "what now")
        #expect(intent == .todayFocus)
        #expect(backend.calls.count == 1)
        #expect(backend.calls[0].instructions == CoachPrompt.classifierInstructions)
        #expect(backend.calls[0].prompt.contains("what now"))
        #expect(backend.calls[0].instructions.contains("medicalOutOfScope") && backend.calls[0].instructions.contains("crisis"))
    }

    // MARK: - The real backend

    #if canImport(FoundationModels)
    @Test func theGeneratedIntentIsExactlyTheIntentEnum() {
        #expect(GeneratedIntent.allCases.map(\.rawValue) == CoachIntent.allCases.map(\.rawValue))
    }

    @Test func theGeneratedConfidenceIsExactlyTheConfidenceEnum() {
        #expect(Set(GeneratedConfidence.allCases.map(\.rawValue)) == Set(CoachConfidence.allCases.map(\.rawValue)))
    }

    @Test func aGeneratedDraftBecomesADraftFieldForField() {
        let generated = GeneratedCoachDraft(
            summary: "s", contributors: [GeneratedContributor(label: "HRV", factID: "hrv.today")], whatChanged: "c", whatToNotice: "n",
            tonightSuggestion: "t", pattern: "p", confidence: .moderate, caution: "k", destinations: ["sleep"]
        )
        #expect(generated.draft == CoachAnswerDraft(
            summary: "s", contributors: [CoachDraftContributor(label: "HRV", factID: "hrv.today")], whatChanged: "c", whatToNotice: "n",
            tonightSuggestion: "t", pattern: "p", confidence: .moderate, caution: "k", destinations: ["sleep"]
        ))
    }

    @Test func theSystemModelsAvailabilityMapsToOneOfTheCases() {
        let mapped = SystemLanguageModelBackend().availability
        let all: [CoachAvailability] = [.available, .deviceNotEligible, .notEnabled, .modelNotReady, .unsupportedLanguage]
        #expect(all.contains(mapped))
        switch SystemLanguageModel.default.availability {
        case .available: #expect(mapped == .available || mapped == .unsupportedLanguage)
        case .unavailable(.deviceNotEligible): #expect(mapped == .deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled): #expect(mapped == .notEnabled)
        case .unavailable(.modelNotReady): #expect(mapped == .modelNotReady)
        case .unavailable: #expect(mapped == .modelNotReady)
        }
    }

    /// Runs the real model when this machine has one, and says what happened.
    /// Passes either way: what it checks is that whatever the model does, the
    /// person gets a validated answer.
    @Test func theRealModelThroughTheServiceGivesAValidatedAnswerOrTheTemplate() async {
        let backend = SystemLanguageModelBackend()
        let person = CoachFixture.profile
        let provider = FoundationModelsProvider(backend: backend)
        let service = AIService(
            format: CoachFixture.format, dataSource: StaticCoachDataSource(await CoachFixture.snapshots(.full)), profile: { person },
            model: provider, timeout: .seconds(45)
        )
        let result = await service.answer(to: "Why is my recovery lower today?")
        print("COACH-FM availability=\(backend.availability.rawValue) outcome=\(result.outcome.code) source=\(result.answer.sourceKind.rawValue)")
        // The app's own pattern note ("not proof of a cause") is written by the app, not the model, and is the one sentence that has to say "cause".
        for text in result.answer.allText where text != result.answer.patternNote { #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: text)) }
        #expect(!result.answer.allText.joined().contains("{{"))
        switch result.outcome {
        case .model: #expect(result.answer.sourceKind == .appleIntelligence)
        case .template: #expect(result.answer.sourceKind == .fromYourData)
        default: Issue.record("unexpected outcome \(result.outcome.code)")
        }
    }
    #endif
}

// MARK: - Remote (a shape, and a filter)

nonisolated private struct EchoTransport: RemoteModelTransport {
    let response: RemoteModelResponse
    let sink: RequestSink

    func send(_ request: RemoteModelRequest) async throws -> RemoteModelResponse {
        sink.record(request)
        return response
    }
}

nonisolated private final class RequestSink: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [RemoteModelRequest] = []
    var all: [RemoteModelRequest] { lock.withLock { requests } }
    func record(_ request: RemoteModelRequest) { lock.withLock { requests.append(request) } }
}

struct CoachRemoteTests {
    @Test func theRemoteFlagIsOffAndAProviderWithoutATransportIsNotConfigured() async {
        #expect(CoachFeatureFlags().aiRemote == false)
        let provider = RemoteModelProvider()
        #expect(provider.kind == .remoteModel)
        #expect(provider.availability == .notConfigured)
        await #expect(throws: CoachProviderError.notConfigured) {
            try await provider.draft(question: "q", intent: .recoveryChange, context: CoachFixture.handmade())
        }
    }

    @Test func theFilterStripsEveryFactNotOnTheAllowedList() async throws {
        let allowed = CoachFixture.fact("recovery.score", 72, .points)
        let insight = CoachFixture.fact("insight.bedtimeShift.delta", 55, .duration, magnitude: true)
        let leaks = [
            CoachFixture.fact("user.name", 1, .count), CoachFixture.fact("profile.email", 1, .count), CoachFixture.fact("health.rawSamples", 1, .count),
            CoachFixture.fact("insight.", 1, .count), CoachFixture.fact("insight", 1, .count), CoachFixture.fact("sample.heartRate.2026-09-24T03:12", 1, .count),
            CoachFixture.fact("device.name", 1, .count), CoachFixture.fact("recovery.scoreRaw", 1, .count), CoachFixture.fact("RECOVERY.SCORE", 1, .count),
        ]
        let context = CoachFixture.handmade(facts: [allowed, insight] + leaks)
        let request = RemotePrivacyFilter.request(intent: .recoveryChange, context: context)
        #expect(request.facts.map(\.id) == ["recovery.score", "insight.bedtimeShift.delta"])
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        for leak in ["user.name", "email", "rawSamples", "device.name", "heartRate"] { #expect(!json.contains(leak), Comment(rawValue: leak)) }
    }

    @Test func aRequestCarriesNoQuestionNoTurnsNoGoalsAndNoName() async throws {
        let turns = [CoachTurnSummary(question: "my private question", answerSummary: "my private answer")]
        let context = await CoachFixture.context(.recoveryChange, .lower).withTurns(turns)
        let request = RemotePrivacyFilter.request(intent: .recoveryChange, context: context)
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(!json.contains("private") && !json.contains("Alex") && !json.contains("Tester"))
        #expect(!json.contains("betterRecovery") && !json.contains("goal") && !json.contains("recentTurns") && !json.contains("question"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["intent", "direction", "dataState", "confidenceCeiling", "nightsOfHistory", "facts"])
        for fact in try #require(object["facts"] as? [[String: Any]]) { #expect(Set(fact.keys) == ["id", "label", "display"]) }
    }

    @Test func everyFactTheBuilderProducesSurvivesTheFilter() async {
        for scenario in CoachFixture.scenarios {
            for intent in CoachQuestionRouter.intentOrder {
                let context = await CoachFixture.context(intent, nil, scenario: scenario)
                let request = RemotePrivacyFilter.request(intent: intent, context: context)
                #expect(request.facts.map(\.id) == context.facts.map(\.id), Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue)"))
            }
        }
    }

    @Test func aProviderWithATransportSendsTheFilteredRequestAndReturnsADraft() async throws {
        let sink = RequestSink()
        let response = RemoteModelResponse(
            summary: "Your recovery is {{recovery.score}}.", contributors: [.init(label: "HRV", factID: "hrv.today")], whatChanged: "c", whatToNotice: "n",
            tonightSuggestion: nil, pattern: nil, confidence: "high", caution: nil, destinations: ["recovery"]
        )
        let provider = RemoteModelProvider(transport: EchoTransport(response: response, sink: sink))
        #expect(provider.availability == .available)
        let context = CoachFixture.handmade(facts: [CoachFixture.fact("recovery.score", 72, .points), CoachFixture.fact("user.name", 1, .count)])
        let draft = try await provider.draft(question: "a private question", intent: .recoveryChange, context: context)
        #expect(draft.summary == "Your recovery is {{recovery.score}}." && draft.confidence == .high && draft.destinations == ["recovery"])
        #expect(draft.contributors == [CoachDraftContributor(label: "HRV", factID: "hrv.today")])
        #expect(sink.all.count == 1)
        #expect(sink.all[0].facts.map(\.id) == ["recovery.score"])
        #expect(!String(decoding: try JSONEncoder().encode(sink.all[0]), as: UTF8.self).contains("private"))
    }

    @Test func aRemoteDraftGoesThroughTheSameValidator() {
        let response = RemoteModelResponse(
            summary: "You have insomnia", contributors: [], whatChanged: "c", whatToNotice: "n", tonightSuggestion: nil, pattern: nil, confidence: "bogus",
            caution: nil, destinations: []
        )
        let draft = response.draft
        #expect(draft.confidence == nil)
        #expect(!CoachSafetyValidator.failures(draft, context: CoachFixture.handmade()).isEmpty)
    }

    @Test func theFactCatalogAllowsAnInsightsNumbersButNotABareInsightPrefix() {
        #expect(CoachFactCatalog.allows("insight.stageShare.deep.share"))
        #expect(CoachFactCatalog.allows("insight.bedtimeShift.delta"))
        #expect(!CoachFactCatalog.allows("insight."))
        #expect(!CoachFactCatalog.allows("insight.x"))
        #expect(!CoachFactCatalog.allows("user.name"))
    }
}

// MARK: - The DEBUG mock

struct CoachMockAITests {
    @Test func theLaunchValuesMapToModes() {
        #expect(MockAIProvider.Mode(launchValue: "good") == .good)
        #expect(MockAIProvider.Mode(launchValue: "misbehaving") == .misbehaving)
        #expect(MockAIProvider.Mode(launchValue: "slow") == .slow)
        #expect(MockAIProvider.Mode(launchValue: "unavailable") == .unavailable)
        #expect(MockAIProvider.Mode(launchValue: "nonsense") == nil)
    }

    @Test func theAppReadsMockAIFromItsLaunchArguments() {
        #expect(DebugLaunchOptions(arguments: ["-mockAI", "misbehaving"]).mockAI == .misbehaving)
        #expect(DebugLaunchOptions(arguments: ["-mockAI", "slow", "-mockScenario", "full"]).mockAI == .slow)
        #expect(DebugLaunchOptions(arguments: ["-mockAI"]).mockAI == nil)
        #expect(DebugLaunchOptions(arguments: ["-mockScenario", "full"]).mockAI == nil)
    }

    @Test func goodDraftsNameOnlyFactsInTheContextForEveryIntentAndScenario() async throws {
        let mock = MockAIProvider(mode: .good, locale: CoachFixture.locale)
        for scenario in CoachFixture.scenarios {
            for intent in CoachQuestionRouter.intentOrder {
                let context = await CoachFixture.context(intent, nil, scenario: scenario)
                let draft = try await mock.draft(question: "q", intent: intent, context: context)
                #expect(CoachSafetyValidator.failures(draft, context: context).isEmpty, Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue)"))
            }
        }
        #expect(mock.callCount == CoachFixture.scenarios.count * CoachQuestionRouter.intentOrder.count)
    }

    @Test func eachSpoiledDraftBreaksExactlyItsOwnRule() async throws {
        let context = await CoachFixture.context(.recoveryChange, .lower)
        let good = TemplateCoachProvider(locale: CoachFixture.locale).compose(intent: .recoveryChange, context: context)
        #expect(CoachSafetyValidator.failures(good, context: context).isEmpty)
        for kind in MockAIProvider.Misbehavior.allCases {
            let bad = MockAIProvider.spoil(good, kind, context: context)
            #expect(bad != good, Comment(rawValue: kind.rawValue))
            #expect(!CoachSafetyValidator.failures(bad, context: context).isEmpty, Comment(rawValue: kind.rawValue))
        }
    }

    @Test func aMockCanBeUnavailableThrowOrWait() async {
        let context = CoachFixture.handmade()
        let unavailable = MockAIProvider(mode: .unavailable)
        #expect(unavailable.availability == .deviceNotEligible)
        await #expect(throws: CoachProviderError.unavailable(.deviceNotEligible)) { try await unavailable.draft(question: "q", intent: .recoveryChange, context: context) }
        await #expect(throws: CoachProviderError.failed) { try await MockAIProvider(mode: .throwing).draft(question: "q", intent: .recoveryChange, context: context) }
        #expect(MockAIProvider(mode: .good).availability == .available)
    }
}
