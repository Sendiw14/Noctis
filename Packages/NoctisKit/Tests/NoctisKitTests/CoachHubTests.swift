import Foundation
import HealthProviding
import Testing
@testable import CoachFeature
@testable import CoachKit
@testable import HomeFeature
@testable import NoctisCore

/// A service stand-in: answers as told, and can be made to wait.
nonisolated final class StubAnswering: CoachAnswering, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var asked: [(question: String, conversation: UUID?)] = []
    private var held = false
    var result: CoachResult
    var availability: CoachAvailability

    init(result: CoachResult = StubAnswering.answered("Your recovery is below your usual."), availability: CoachAvailability = .available) {
        self.result = result
        self.availability = availability
    }

    static func answered(_ summary: String, intent: CoachIntent = .recoveryChange, messageID: UUID? = nil) -> CoachResult {
        CoachResult(
            answer: CoachAnswer(sourceKind: .fromYourData, intent: intent, summary: summary, confidence: .high, footer: "Coach shares patterns from your data. It isn't medical advice."),
            outcome: .template(.modelUnavailable(.notConfigured)),
            messageID: messageID
        )
    }

    var questions: [String] { lock.withLock { asked.map(\.question) } }
    var conversations: [UUID?] { lock.withLock { asked.map(\.conversation) } }

    func hold() { lock.withLock { held = true } }

    func release() {
        let continuations = lock.withLock {
            held = false
            defer { waiting = [] }
            return waiting
        }
        for continuation in continuations { continuation.resume() }
    }

    func answer(to question: String, conversationID: UUID?) async -> CoachResult {
        lock.withLock { asked.append((question, conversationID)) }
        if lock.withLock({ held }) {
            await withCheckedContinuation { continuation in
                let resumeNow = lock.withLock {
                    if !held { return true }
                    waiting.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        return result
    }

    func modelAvailability() async -> CoachAvailability { availability }
}

/// Waits (briefly) for a condition the view model reaches on its own.
@MainActor
func coachWait(_ condition: () -> Bool) async {
    for _ in 0..<400 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

struct CoachHubBuilderTests {
    private func hub(
        _ state: HomeDataState?, availability: CoachAvailability = .available, firstRun: Bool = false,
        suggestions: [CoachSuggestion]? = nil, locale: String = "en_US"
    ) -> CoachHubContent {
        let ranked = suggestions ?? CoachSuggestionRanker.rank(facts: [], state: .ready, evening: false)
        return CoachHubBuilder.build(
            suggestions: ranked, dataState: state, availability: availability, showsFirstRun: firstRun, now: CoachFixture.now,
            format: HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: locale))
        )
    }

    @Test func aReadyHubHasSixEnabledCardsAndNoState() {
        let content = hub(.ready)
        #expect(content.cards.count == 6)
        #expect(content.cards.allSatisfy { $0.isEnabled })
        #expect(content.state == nil && content.questionsAreEnabled)
        #expect(content.learningNote == nil)
        #expect(content.dateCaption == "THURSDAY, SEPTEMBER 24")
    }

    @Test func theCardsFollowTheRankingAndAdaptToTheDirection() {
        let ranked = CoachSuggestionRanker.rank(
            facts: [CoachFixture.fact("recovery.deltaVsUsual", 12, .points), CoachFixture.fact("sleep.deltaVsBaseline", -80, .duration)],
            state: .ready, evening: false
        )
        let content = hub(.ready, suggestions: ranked)
        #expect(content.cards.first?.title == "Why was my sleep worse last night?")
        #expect(content.cards[1].title == "Why is my recovery higher today?")
        #expect(content.cards.map(\.question) == ranked.map(\.question))
        #expect(Set(content.cards.map(\.id)).count == 6)
    }

    @Test func everyCardHasASymbolATileAndTheCatalogsTitle() {
        for card in hub(.ready).cards {
            #expect(!card.symbol.isEmpty)
            #expect(card.title == CoachQuestionText.text(card.question))
        }
    }

    @Test func withoutPermissionTheHubAsksToConnectAndTheCardsAreOff() {
        let content = hub(.permissionRequired)
        #expect(content.state == .connect(title: "Coach needs a few nights to explain your patterns", message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true))
        #expect(content.cards.allSatisfy { !$0.isEnabled })
        #expect(!content.questionsAreEnabled)
    }

    @Test func withoutAHealthStoreThereIsNoButton() {
        #expect(hub(.healthDataUnavailable).state == .connect(title: "Coach needs a few nights to explain your patterns", message: "Apple Health isn't available on this device.", showsButton: false))
    }

    @Test func withNoSleepTheHubSaysSoAndTheCardsAreOff() {
        for state in [HomeDataState.empty, .learning(nightsSoFar: 0)] {
            let content = hub(state)
            guard case .noSleepData(let title, _)? = content.state else {
                Issue.record("expected the no-sleep state for \(state)")
                continue
            }
            #expect(title == "Coach needs a few nights to explain your patterns")
            #expect(content.cards.allSatisfy { !$0.isEnabled })
        }
    }

    @Test func aFailedReadHasATryAgain() {
        #expect(hub(.failed).state == .failed(message: "We couldn't read your latest sleep data."))
    }

    @Test func whileLearningTheQuestionsWorkAndTheHubSaysHowManyNights() {
        let content = hub(.learning(nightsSoFar: 3))
        #expect(content.state == nil)
        #expect(content.cards.allSatisfy { $0.isEnabled })
        #expect(content.learningNote == "Coach has 3 nights to read so far. Answers say when there isn't enough yet.")
        #expect(hub(.learning(nightsSoFar: 1)).learningNote == "Coach has 1 night to read so far. Answers say when there isn't enough yet.")
        #expect(hub(.ready).learningNote == nil)
    }

    @Test func staleDataAndAMissingNightStillAllowQuestions() {
        for state in [HomeDataState.stale(newestSample: CoachFixture.now), .noSleepLastNight] {
            let content = hub(state)
            #expect(content.state == nil && content.cards.allSatisfy { $0.isEnabled })
        }
    }

    @Test(arguments: [CoachAvailability.deviceNotEligible, .notEnabled, .modelNotReady, .unsupportedLanguage, .notConfigured])
    func withoutAppleIntelligenceTheHubSaysSoAndOffersSettingsOnlyWhenThatIsTheFix(_ availability: CoachAvailability) {
        let content = hub(.ready, availability: availability)
        #expect(content.appleIntelligenceUnavailable)
        #expect(content.showsTurnOnAppleIntelligence == (availability == .notEnabled))
        #expect(content.cards.allSatisfy { $0.isEnabled }, "answers still work through the template")
    }

    @Test func withAppleIntelligenceThereIsNoBanner() {
        let content = hub(.ready, availability: .available)
        #expect(!content.appleIntelligenceUnavailable && !content.showsTurnOnAppleIntelligence)
    }

    @Test func theFirstRunCardFollowsTheGate() {
        #expect(hub(.ready, firstRun: true).showsFirstRun)
        #expect(!hub(.ready, firstRun: false).showsFirstRun)
    }

    @Test func theFixedWordsAreTheSpecsWords() {
        #expect(CoachHubContent.summary == "Understand your patterns.")
        #expect(CoachHubContent.firstRunText == "Coach explains patterns in your own data. It isn't medical advice.")
        #expect(CoachHubContent.firstRunButton == "How Coach uses your data")
        #expect(CoachHubContent.withoutAppleIntelligence == "Answers are built from your data without Apple Intelligence")
        #expect(CoachHubContent.turnOnAppleIntelligence == "Turn on Apple Intelligence")
    }
}

@MainActor
struct CoachViewModelTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "coach-tests-\(UUID().uuidString)")!
    }

    private func viewModel(
        service: StubAnswering = StubAnswering(), snapshots: CoachSnapshots = CoachSnapshots(), history: CoachHistoryStore? = nil,
        defaults: UserDefaults? = nil, minimumLoading: Duration = .zero, connect: @escaping () async -> Void = {}
    ) -> CoachViewModel {
        let store = defaults ?? self.defaults()
        return CoachViewModel(
            service: service,
            dataSource: StaticCoachDataSource(snapshots),
            history: history,
            profile: { CoachFixture.profile },
            connectHealth: connect,
            firstRun: CoachFirstRunGate(defaults: store),
            washGate: HomeIntroGate(defaults: store, key: CoachViewModel.washKey),
            clock: { CoachFixture.now },
            calendar: Fixture.calendar(),
            locale: CoachFixture.locale,
            minimumLoading: minimumLoading,
            reduceMotion: { true }
        )
    }

    // MARK: - The hub

    @Test func theHubIsBuiltFromRealDataAndLeadsWithTheBiggestChange() async {
        let model = viewModel(snapshots: await CoachFixture.snapshots(.full))
        #expect(model.hub == nil)
        await model.onAppear()
        let hub = try? #require(model.hub)
        #expect(hub?.cards.first?.question == .recovery(.lower))
        #expect(hub?.cards.count == 6)
        #expect(hub?.state == nil)
    }

    @Test func theHubForNoDataIsTheEmptyStateWithDisabledQuestions() async {
        let model = viewModel(snapshots: await CoachFixture.snapshots(.empty))
        await model.onAppear()
        #expect(model.hub?.cards.allSatisfy { !$0.isEnabled } == true)
        if case .noSleepData? = model.hub?.state {} else { Issue.record("expected no-sleep state: \(String(describing: model.hub?.state))") }
    }

    @Test func theHubForLearningKeepsQuestionsOnAndSaysHowManyNights() async {
        let model = viewModel(snapshots: await CoachFixture.snapshots(.learning))
        await model.onAppear()
        #expect(model.hub?.cards.allSatisfy { $0.isEnabled } == true)
        #expect(model.hub?.learningNote?.contains("3 nights") == true)
    }

    @Test func withoutPermissionConnectingReadsAgain() async {
        let unauthorized = HomeSnapshotBuilder.placeholder(.permissionRequired, profile: CoachFixture.profile, now: CoachFixture.now, timeZone: Fixture.newYork)
        var connected = false
        let model = viewModel(snapshots: CoachSnapshots(home: unauthorized), connect: { connected = true })
        await model.onAppear()
        if case .connect(_, _, let showsButton)? = model.hub?.state { #expect(showsButton) } else { Issue.record("expected the connect state") }
        await model.connectAppleHealth()
        #expect(connected)
    }

    @Test func theHubKnowsWhetherAppleIntelligenceIsUnavailable() async {
        let model = viewModel(service: StubAnswering(availability: .notEnabled), snapshots: await CoachFixture.snapshots(.full))
        await model.onAppear()
        #expect(model.hub?.appleIntelligenceUnavailable == true && model.hub?.showsTurnOnAppleIntelligence == true)
    }

    // MARK: - The text field

    @Test func theDraftIsCappedAt200Characters() {
        let model = viewModel()
        model.setDraft(String(repeating: "a", count: 250))
        #expect(model.draft.count == 200 && CoachViewModel.maxLength == 200)
        model.setDraft(String(repeating: "b", count: 200))
        #expect(model.draft.count == 200)
        model.setDraft("short")
        #expect(model.draft == "short")
    }

    @Test func sendNeedsSomethingTypedAndNothingInFlight() async {
        let service = StubAnswering()
        let model = viewModel(service: service)
        #expect(!model.canSend)
        model.setDraft("   \n ")
        #expect(!model.canSend, "blank is empty")
        #expect(!model.startConversation(asking: model.draft))
        model.setDraft("Why is my recovery lower?")
        #expect(model.canSend)
        service.hold()
        #expect(model.startConversation(asking: model.draft))
        #expect(model.draft.isEmpty, "the field clears when the question is sent")
        model.setDraft("another")
        #expect(!model.canSend, "nothing more can be sent while one is on its way")
        service.release()
        await coachWait { !model.isSending }
        #expect(model.canSend)
    }

    // MARK: - Asking

    @Test func aQuestionCantBeSubmittedTwice() async {
        let service = StubAnswering()
        service.hold()
        let model = viewModel(service: service)
        #expect(model.startConversation(asking: .week))
        #expect(model.isSending)
        #expect(!model.startConversation(asking: .week))
        #expect(!model.followUp("What else?"))
        #expect(model.turns.count == 1)
        service.release()
        await coachWait { !model.isSending }
        #expect(service.questions == ["What changed this week?"], "the service was asked once")
    }

    @Test func aQuestionShowsLoadingThenItsAnswer() async {
        let service = StubAnswering(result: StubAnswering.answered("Your bedtime fits."))
        service.hold()
        let model = viewModel(service: service)
        model.startConversation(asking: .bedtime)
        #expect(model.turns.first?.phase == .loading)
        #expect(model.title == "When should I sleep?")
        service.release()
        await coachWait { !model.isSending }
        #expect(model.turns.first?.answer?.summary == "Your bedtime fits.")
        #expect(!model.isSending)
    }

    @Test func aQuestionFromTheHubIsANewConversation() async {
        let service = StubAnswering()
        let model = viewModel(service: service)
        model.startConversation(asking: .week)
        await coachWait { !model.isSending }
        model.startConversation(asking: .bedtime)
        await coachWait { !model.isSending }
        #expect(model.turns.map(\.question) == ["When should I sleep?"])
        #expect(model.title == "When should I sleep?")
    }

    @Test func aFollowUpContinuesTheConversationWithTheSameId() async throws {
        let store = CoachHistoryStore(modelContainer: try CoachHistoryContainer.make(inMemory: true))
        let service = StubAnswering()
        let model = viewModel(service: service, history: store)
        model.startConversation(asking: .recovery(.lower))
        await coachWait { !model.isSending }
        model.followUp(.bedtime)
        await coachWait { !model.isSending }
        #expect(model.turns.map(\.question) == ["Why is my recovery lower today?", "When should I sleep?"])
        #expect(model.title == "Why is my recovery lower today?", "the page is titled by the question that began it")
        let ids = service.conversations
        #expect(ids.count == 2 && ids[0] != nil && ids[0] == ids[1])
        #expect(model.conversationID == ids[0])
    }

    @Test func aFollowUpFromTheTextFieldClearsIt() async {
        let model = viewModel()
        model.startConversation(asking: .week)
        await coachWait { !model.isSending }
        model.setDraft("And my HRV?")
        #expect(model.followUp())
        #expect(model.draft.isEmpty)
        await coachWait { !model.isSending }
        #expect(model.turns.last?.question == "And my HRV?")
    }

    @Test func aQuestionIsTrimmedAndCapped() async {
        let service = StubAnswering()
        let model = viewModel(service: service)
        model.startConversation(asking: "  " + String(repeating: "x", count: 300) + "  ")
        await coachWait { !model.isSending }
        #expect(service.questions.first?.count == 200)
    }

    @Test func whenNothingCouldAnswerTheTurnFailsAndTryAgainAsksAgain() async {
        let failed = CoachResult(answer: CoachScriptedAnswers.answer(.unavailable), outcome: .unavailable)
        let service = StubAnswering(result: failed)
        let model = viewModel(service: service)
        model.startConversation(asking: .week)
        await coachWait { !model.isSending }
        #expect(model.turns.first?.phase == .failed)
        service.result = StubAnswering.answered("Here you go.")
        model.retry(model.turns[0].id)
        await coachWait { !model.isSending }
        #expect(model.turns.count == 1 && model.turns.first?.answer?.summary == "Here you go.")
        #expect(service.questions.count == 2)
    }

    @Test func tryAgainDoesNothingOnAnAnsweredTurnOrWhileSending() async {
        let service = StubAnswering()
        let model = viewModel(service: service)
        model.startConversation(asking: .week)
        await coachWait { !model.isSending }
        model.retry(model.turns[0].id)
        #expect(model.turns.count == 1 && service.questions.count == 1)
    }

    @Test func aFixedReplyIsAnAnswerTooWithNoMessageId() async {
        let medical = CoachResult(answer: CoachScriptedAnswers.answer(.medical), outcome: .scripted(.medical))
        let model = viewModel(service: StubAnswering(result: medical))
        model.startConversation(asking: "do I have sleep apnea")
        await coachWait { !model.isSending }
        #expect(model.turns.first?.answer?.sourceKind == .scripted)
        #expect(model.turns.first?.messageID == nil)
    }

    @Test func leavingTheConversationClearsIt() async {
        let model = viewModel()
        model.startConversation(asking: .week)
        await coachWait { !model.isSending }
        model.endConversation()
        #expect(model.turns.isEmpty && model.conversationID == nil && !model.isSending)
        #expect(model.title == "Coach")
    }

    // MARK: - First run and privacy

    @Test func theFirstRunCardShowsUntilItIsDealtWithAndNeverAgain() async {
        let store = defaults()
        let first = viewModel(snapshots: await CoachFixture.snapshots(.full), defaults: store)
        await first.onAppear()
        #expect(first.hub?.showsFirstRun == true)
        first.dismissFirstRun()
        #expect(first.hub?.showsFirstRun == false)
        let second = viewModel(snapshots: await CoachFixture.snapshots(.full), defaults: store)
        await second.onAppear()
        #expect(second.hub?.showsFirstRun == false, "shown once")
    }

    @Test func askingAQuestionAlsoUsesUpTheFirstRunCard() async {
        let store = defaults()
        let model = viewModel(defaults: store)
        model.startConversation(asking: .week)
        await coachWait { !model.isSending }
        #expect(CoachFirstRunGate(defaults: store).isSeen)
    }

    @Test func thePrivacyButtonOpensTheSheetAndUsesUpTheFirstRunCard() async {
        let store = defaults()
        let model = viewModel(snapshots: await CoachFixture.snapshots(.full), defaults: store)
        await model.onAppear()
        model.openPrivacy()
        #expect(model.showsPrivacy)
        #expect(model.hub?.showsFirstRun == false)
        #expect(CoachFirstRunGate(defaults: store).isSeen)
    }

    // MARK: - The field's wash

    @Test func theFieldWashesOnceADay() {
        let store = defaults()
        let first = viewModel(defaults: store)
        #expect(first.fieldEntrance == .wash)
        first.fieldEntered()
        #expect(first.fieldEntrance == .none)
        #expect(viewModel(defaults: store).fieldEntrance == .fade)
    }
}
