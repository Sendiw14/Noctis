import Foundation
import HealthProviding
import Testing
@testable import CoachFeature
@testable import CoachKit
@testable import HomeFeature
@testable import NoctisCore

struct CoachHistoryBuilderTests {
    private let format = HomeFormat(calendar: Fixture.calendar(), locale: CoachFixture.locale)
    private let now = Fixture.date(2026, 9, 30, 10)

    private func summary(_ title: String, turns: Int = 1, at date: Date) -> CoachConversationSummary {
        CoachConversationSummary(id: UUID(), updatedAt: date, firstQuestion: title, turns: turns)
    }

    @Test func noConversationsIsAnEmptyHistory() {
        let content = CoachHistoryBuilder.build([], now: now, format: format)
        #expect(content.isEmpty && content.conversationCount == 0 && content.days.isEmpty)
    }

    @Test func conversationsAreGroupedByDayNewestFirstWithTheirFirstQuestionAsTitle() {
        let items = [
            summary("Why is my recovery lower today?", at: Fixture.date(2026, 9, 30, 9, 41)),
            summary("When should I sleep?", at: Fixture.date(2026, 9, 30, 21, 5)),
            summary("What changed this week?", at: Fixture.date(2026, 9, 29, 22, 15)),
            summary("How can I improve consistency?", at: Fixture.date(2026, 9, 24, 8, 0)),
        ]
        let content = CoachHistoryBuilder.build(items, now: now, format: format)
        #expect(content.days.map(\.title) == ["Today", "Yesterday", "Thu, Sep 24"])
        #expect(content.days.map(\.id) == ["2026-09-30", "2026-09-29", "2026-09-24"])
        #expect(content.days[0].rows.map(\.title) == ["When should I sleep?", "Why is my recovery lower today?"], "newest first inside a day")
        #expect(content.conversationCount == 4)
    }

    @Test func aRowSaysHowManyQuestionsAndWhen() {
        let one = CoachHistoryBuilder.build([summary("Q", turns: 1, at: Fixture.date(2026, 9, 30, 21, 41))], now: now, format: format)
        #expect(one.days[0].rows[0].detail.plain == "1 question · 9:41 PM")
        let three = CoachHistoryBuilder.build([summary("Q", turns: 3, at: Fixture.date(2026, 9, 30, 9, 5))], now: now, format: format)
        #expect(three.days[0].rows[0].detail.plain == "3 questions · 9:05 AM")
        let german = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "de_DE"))
        #expect(CoachHistoryBuilder.build([summary("Q", turns: 2, at: Fixture.date(2026, 9, 30, 21, 41))], now: now, format: german).days[0].rows[0].detail.contains("21:41"))
    }

    @Test func aDayAcrossMidnightIsTheDayOfItsLastActivity() {
        let late = summary("Q", at: Fixture.date(2026, 9, 29, 23, 59))
        let early = summary("R", at: Fixture.date(2026, 9, 30, 0, 1))
        let content = CoachHistoryBuilder.build([late, early], now: now, format: format)
        #expect(content.days.map(\.title) == ["Today", "Yesterday"])
    }

    @Test func theFixedWordsAreTheseAndTheDeleteAllWarnsItCantBeUndone() {
        #expect(CoachHistoryContent.emptyTitle == "No conversations yet")
        #expect(CoachHistoryContent.deleteAllTitle == "Delete all conversations")
        #expect(CoachHistoryContent.deleteAllMessage.contains("can't be undone"))
        #expect(CoachHistoryContent.deleteAllMessage.contains("not affected"), "R37: it says what is not deleted too")
        #expect(CoachHistoryContent.emptyMessage.contains("this iPhone only"))
    }
}

@MainActor
struct CoachHistoryViewModelTests {
    private func store() throws -> CoachHistoryStore {
        CoachHistoryStore(modelContainer: try CoachHistoryContainer.make(inMemory: true))
    }

    private func model(history: CoachHistoryStore?, service: (any CoachAnswering)? = nil) async -> CoachViewModel {
        let defaults = UserDefaults(suiteName: "coach-tests-\(UUID().uuidString)")!
        let person = CoachFixture.profile
        let answering: any CoachAnswering
        if let service { answering = service } else {
            answering = AIService(
                format: CoachFixture.format, dataSource: StaticCoachDataSource(await CoachFixture.snapshots(.full)), profile: { person }, model: nil, history: history
            )
        }
        return CoachViewModel(
            service: answering, dataSource: StaticCoachDataSource(CoachSnapshots()), history: history, profile: { CoachFixture.profile },
            firstRun: CoachFirstRunGate(defaults: defaults), washGate: HomeIntroGate(defaults: defaults, key: CoachViewModel.washKey),
            clock: { CoachFixture.now }, calendar: Fixture.calendar(), locale: CoachFixture.locale, minimumLoading: .zero, reduceMotion: { true }
        )
    }

    private func ask(_ model: CoachViewModel, _ text: String) async {
        model.startConversation(asking: text)
        await coachWait { !model.isSending }
    }

    @Test func historyIsNilUntilItIsLoadedAndThenListsWhatWasKept() async throws {
        let store = try store()
        let model = await model(history: store)
        #expect(model.history == nil)
        await model.loadHistory()
        #expect(model.history?.isEmpty == true)
        await ask(model, "Why is my recovery lower today?")
        await model.loadHistory()
        #expect(model.history?.conversationCount == 1)
        #expect(model.history?.days.first?.rows.first?.title == "Why is my recovery lower today?")
    }

    @Test func historyReadsOnlyWhatIsStoredSoFixedRepliesNeverAppear() async throws {
        let store = try store()
        let model = await model(history: store)
        await ask(model, "do I have sleep apnea")
        await ask(model, "I want to die")
        await ask(model, "what's the weather")
        await model.loadHistory()
        #expect(model.history?.isEmpty == true, "medical, crisis and unknown replies are never kept, so no conversation was")
    }

    @Test func aStoredConversationOpensAsItWasKeptReadyForAFollowUp() async throws {
        let store = try store()
        let model = await model(history: store)
        await ask(model, "Why is my recovery lower today?")
        model.followUp(.bedtime)
        await coachWait { !model.isSending }
        let turn = try #require(model.turns.first)
        model.setFeedback(.helpful, for: turn.id)
        let conversation = try #require(model.conversationID)
        #expect(await waitFor { await store.turns(in: conversation).first?.feedback == .helpful }, "the feedback was kept")
        await model.loadHistory()
        let id = try #require(model.history?.days.first?.rows.first?.id)
        model.endConversation()
        #expect(model.turns.isEmpty)

        #expect(await model.openConversation(id))
        #expect(model.turns.map(\.question) == ["Why is my recovery lower today?", "When should I sleep?"])
        #expect(model.title == "Why is my recovery lower today?")
        #expect(model.turns.allSatisfy { $0.answer != nil && $0.revealed }, "an opened answer is simply there: no reveal")
        #expect(model.turns[0].feedback == .helpful)
        #expect(model.conversationID == id)
        #expect(model.followUpQuestions.count == 3)

        model.followUp("And my week?")
        await coachWait { !model.isSending }
        #expect(model.turns.count == 3 && model.conversationID == id, "the follow-up goes into the same conversation")
        await model.loadHistory()
        #expect(model.history?.conversationCount == 1)
        #expect(model.history?.days.first?.rows.first?.detail.hasPrefix("3 questions") == true)
    }

    @Test func aConversationThatIsGoneDoesNotOpen() async throws {
        let model = await model(history: try store())
        #expect(await model.openConversation(UUID()) == false)
        #expect(await self.model(history: nil).openConversation(UUID()) == false)
    }

    @Test func swipingAConversationAwayDeletesJustThatOne() async throws {
        let store = try store()
        let model = await model(history: store)
        await ask(model, "Why is my recovery lower today?")
        await ask(model, "When should I sleep?")
        await model.loadHistory()
        #expect(model.history?.conversationCount == 2)
        let doomed = try #require(model.history?.days.first?.rows.first { $0.title == "When should I sleep?" })
        await model.deleteConversation(doomed.id)
        #expect(model.history?.conversationCount == 1)
        #expect(model.history?.days.first?.rows.first?.title == "Why is my recovery lower today?")
        #expect(await store.turns(in: doomed.id).isEmpty)
    }

    @Test func deletingTheOpenConversationClosesIt() async throws {
        let store = try store()
        let model = await model(history: store)
        await ask(model, "Why is my recovery lower today?")
        let open = try #require(model.conversationID)
        await model.deleteConversation(open)
        #expect(model.turns.isEmpty && model.conversationID == nil)
        #expect(model.history?.isEmpty == true)
    }

    @Test func deleteAllLeavesNothingAndEndsTheConversation() async throws {
        let store = try store()
        let model = await model(history: store)
        await ask(model, "Why is my recovery lower today?")
        await ask(model, "When should I sleep?")
        await ask(model, "What changed this week?")
        await model.deleteAllConversations()
        #expect(model.history?.isEmpty == true)
        #expect(model.turns.isEmpty && model.conversationID == nil)
        #expect(await store.conversations().isEmpty)
        #expect(await store.messageCount() == 0)
    }

    @Test func withoutAStoreCoachKeepsNothingAndHidesHistory() async {
        let model = await model(history: nil)
        #expect(!model.keepsHistory)
        await model.loadHistory()
        #expect(model.history?.isEmpty == true)
    }

    @Test func aStoreMeansHistoryIsOffered() async throws {
        #expect(await model(history: try store()).keepsHistory)
    }
}
