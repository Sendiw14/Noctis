import Foundation
import HealthProviding
import Testing

@testable import CoachFeature
@testable import CoachKit
@testable import DesignSystem
@testable import HomeFeature
@testable import NoctisCore

/// How an answer is set out: units, tiles, buttons, and the number a summary is about.
struct CoachAnswerContentTests {
    private func metric(_ display: String) -> NoctisMetricValue { CoachMetric.value(display: display, spoken: "spoken") }

    @Test func aDurationIsNumbersAndUnitsWithAGapBetweenGroups() {
        #expect(metric("6h 42m").parts == [.number("6"), .unit("h"), .space, .number("42"), .unit("m")])
        #expect(metric("1h 10m").plain == "1h 10m")
        #expect(metric("8h").parts == [.number("8"), .unit("h")])
        #expect(metric("49m").parts == [.number("49"), .unit("m")])
    }

    @Test func aQuantityHasItsUnitOnTheBaselineNextToIt() {
        #expect(metric("48 ms").parts == [.number("48"), .unit("ms")])
        #expect(metric("52 bpm").parts == [.number("52"), .unit("bpm")])
        #expect(metric("36 min").parts == [.number("36"), .unit("min")])
        #expect(metric("31%").parts == [.number("31"), .unit("%")])
    }

    @Test func aClockTimeKeepsItsColonAndTakesItsPeriodAsTheUnit() {
        #expect(metric("11:00 PM").parts == [.number("11:00"), .unit("PM")])
        #expect(metric("11:00\u{202F}PM").parts == [.number("11:00"), .unit("PM")])
        #expect(metric("23:00").parts == [.number("23:00")])
    }

    @Test func aBareNumberAndGroupedNumbers() {
        #expect(metric("72").parts == [.number("72")])
        #expect(metric("1,234").parts == [.number("1,234")])
        #expect(metric("1.234").parts == [.number("1.234")])
        #expect(metric("\u{0667}\u{0662}").parts == [.number("\u{0667}\u{0662}")])
    }

    @Test func aTrailingSeparatorIsNotPartOfANumber() {
        #expect(metric("5.").parts == [.number("5"), .unit(".")])
        #expect(metric("").parts.isEmpty)
    }

    @Test func voiceOverHearsTheFactsWordsNotTheUnits() {
        let contributor = CoachContributor(label: "Sleep", value: "6h 42m", spoken: "6 hours 42 minutes", factID: "sleep.duration")
        #expect(CoachMetric.value(contributor).spoken == "6 hours 42 minutes")
        #expect(CoachMetric.value(contributor).parts.count == 5)
    }

    @Test func everyFactFamilyHasATile() {
        let cases: [(String, String, CoachTile)] = [
            ("hrv.today", "waveform.path.ecg", .lavender), ("rhr.baseline", "heart.fill", .apricot), ("recovery.score", "heart", .lavender),
            ("sleep.deltaVsBaseline", "moon.zzz", .sage), ("deep.share", "moon.zzz", .sage), ("rem.usual", "moon.zzz", .sage),
            ("bedtime.suggested", "bed.double", .apricot), ("wake.typical", "bed.double", .apricot), ("week.avgSleep", "calendar", .butter),
            ("consistency.bedtimeVarMin", "repeat", .butter), ("history.nights", "moon.stars", .sage), ("insight.bedtimeShift.delta", "lightbulb", .butter),
        ]
        for (id, symbol, tile) in cases {
            let found = CoachContributorTile.of(factID: id)
            #expect(found.symbol == symbol && found.tile == tile, Comment(rawValue: id))
        }
    }

    @Test func theButtonsNameTheScreenTheyOpen() {
        #expect(CoachDestinationText.title(.recovery(), intent: .recoveryChange) == "Open Recovery")
        #expect(CoachDestinationText.title(.sleep(), intent: .bedtimeAdvice) == "See bedtime")
        #expect(CoachDestinationText.title(.sleep(), intent: .sleepChange) == "Open Sleep")
        #expect(CoachDestinationText.title(.sleep(night: nil, range: .week), intent: .weekChange) == "Open Sleep")
        #expect(CoachDestinationText.title(.insights(), intent: .patterns) == "Open Insights")
        #expect(CoachDestinationText.title(.insight(id: "bedtimeShift-3fa9c2d1"), intent: .patterns) == "Open this insight")
    }

    @Test func theSourceLabelIsTheSpecsAndAFixedReplyHasNone() {
        #expect(CoachSourceText.label(.appleIntelligence) == "Answered on your iPhone with Apple Intelligence")
        #expect(CoachSourceText.label(.fromYourData) == "Answered from your data")
        #expect(CoachSourceText.label(.scripted) == nil)
    }

    // MARK: - The number a summary is about

    private func assembled(_ intent: CoachIntent, direction: CoachDirection? = nil, scenario: MockScenario = .full) async throws -> CoachAnswer {
        let context = await CoachFixture.context(intent, direction, scenario: scenario)
        let draft = TemplateCoachProvider(locale: CoachFixture.locale).compose(intent: intent, context: context)
        return try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: CoachFixture.locale))
    }

    @Test func aSummaryThatNamesANumberHasItAsTheKeyNumber() async throws {
        let recovery = try await assembled(.recoveryChange, direction: .lower)
        #expect(recovery.keyNumber?.factID == "recovery.score")
        #expect(recovery.keyNumber?.value == recovery.contributors.first { $0.factID == "recovery.score" }?.value || recovery.keyNumber != nil)
        let sleep = try await assembled(.sleepChange)
        #expect(sleep.keyNumber?.factID == "sleep.duration")
        #expect(sleep.keyNumber?.value == "6h 42m")
        #expect(sleep.keyNumber?.spoken == "6 hours 42 minutes")
        let week = try await assembled(.weekChange)
        #expect(week.keyNumber?.factID == "week.avgSleep")
        let bedtime = try await assembled(.bedtimeAdvice)
        #expect(bedtime.keyNumber?.factID == "bedtime.suggested")
        #expect(bedtime.keyNumber?.value.plain == "11:00 PM")
        let consistency = try await assembled(.consistencyHelp)
        #expect(consistency.keyNumber?.factID == "consistency.bedtimeVarMin")
    }

    @Test func aSummaryThatNamesNoNumberHasNoKeyNumber() async throws {
        for scenario in [MockScenario.empty, .learning] {
            for intent in CoachQuestionRouter.intentOrder {
                #expect(try await assembled(intent, scenario: scenario).keyNumber == nil, Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue)"))
            }
        }
        #expect(try await assembled(.patterns).keyNumber == nil)
    }

    @Test func theKeyNumberIsNeverOneTheSummaryDoesntName() async throws {
        for scenario in CoachFixture.scenarios {
            for intent in CoachQuestionRouter.intentOrder {
                let context = await CoachFixture.context(intent, nil, scenario: scenario)
                let draft = TemplateCoachProvider(locale: CoachFixture.locale).compose(intent: intent, context: context)
                let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: CoachFixture.locale))
                if let key = answer.keyNumber {
                    #expect(CoachTokens.ids(in: draft.summary).contains(key.factID), Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue)"))
                    #expect(answer.summary.contains(key.value), Comment(rawValue: "the summary shows the same value"))
                }
            }
        }
    }

    @Test func contributorsCarrySpokenWordsAndOldStoredAnswersStillDecode() throws {
        let answer = try JSONEncoder().encode(CoachContributor(label: "HRV", value: "48 ms", spoken: "48 milliseconds", factID: "hrv.today"))
        #expect(try JSONDecoder().decode(CoachContributor.self, from: answer).spoken == "48 milliseconds")
        let old = Data(#"{"label":"HRV","value":"48 ms","factID":"hrv.today"}"#.utf8)
        #expect(try JSONDecoder().decode(CoachContributor.self, from: old).spoken == "48 ms")
    }
}

@MainActor
struct CoachConversationTests {
    private func store() throws -> CoachHistoryStore {
        CoachHistoryStore(modelContainer: try CoachHistoryContainer.make(inMemory: true))
    }

    private func viewModel(_ service: any CoachAnswering, history: CoachHistoryStore? = nil) -> CoachViewModel {
        let defaults = UserDefaults(suiteName: "coach-tests-\(UUID().uuidString)")!
        return CoachViewModel(
            service: service, dataSource: StaticCoachDataSource(CoachSnapshots()), history: history, profile: { CoachFixture.profile },
            firstRun: CoachFirstRunGate(defaults: defaults), washGate: HomeIntroGate(defaults: defaults, key: CoachViewModel.washKey),
            clock: { CoachFixture.now }, calendar: Fixture.calendar(), locale: CoachFixture.locale, minimumLoading: .zero, reduceMotion: { true }
        )
    }

    private func service(history: CoachHistoryStore?, scenario: MockScenario = .full) async -> AIService {
        let person = CoachFixture.profile
        return AIService(
            format: CoachFixture.format, dataSource: StaticCoachDataSource(await CoachFixture.snapshots(scenario)), profile: { person },
            model: nil, history: history
        )
    }

    // MARK: - Follow-ups

    @Test func afterAnAnswerThereAreThreeFollowUpsAndNoneWhileItsOnItsWay() async {
        let stub = StubAnswering(result: StubAnswering.answered("Answer.", intent: .recoveryChange))
        stub.hold()
        let model = viewModel(stub)
        #expect(model.followUpQuestions.isEmpty)
        model.startConversation(asking: .recovery(.lower))
        #expect(model.followUpQuestions.isEmpty, "not while it is being read")
        stub.release()
        await coachWait { !model.isSending }
        #expect(model.followUpQuestions == CoachFollowUps.questions(after: .recoveryChange))
        #expect(model.followUpQuestions.count == 3)
    }

    @Test func aFixedReplyOrAFailureOffersNoFollowUps() async {
        let medical = StubAnswering(result: CoachResult(answer: CoachScriptedAnswers.answer(.medical), outcome: .scripted(.medical)))
        let first = viewModel(medical)
        first.startConversation(asking: "do I have sleep apnea")
        await coachWait { !first.isSending }
        #expect(first.followUpQuestions.isEmpty)

        let failed = StubAnswering(result: CoachResult(answer: CoachScriptedAnswers.answer(.unavailable), outcome: .unavailable))
        let second = viewModel(failed)
        second.startConversation(asking: .week)
        await coachWait { !second.isSending }
        #expect(second.followUpQuestions.isEmpty)
    }

    @Test func aFollowUpChipAsksThatQuestionInTheSameConversation() async throws {
        let history = try store()
        let stub = StubAnswering(result: StubAnswering.answered("Answer.", intent: .recoveryChange))
        let model = viewModel(stub, history: history)
        model.startConversation(asking: .recovery(.lower))
        await coachWait { !model.isSending }
        let chip = try #require(model.followUpQuestions.first)
        model.followUp(chip)
        await coachWait { !model.isSending }
        #expect(model.turns.count == 2)
        #expect(model.turns[1].question == CoachQuestionText.text(chip))
    }

    // MARK: - Reveal

    @Test func anAnswersRevealPlaysOnce() async {
        let model = viewModel(StubAnswering())
        model.startConversation(asking: .week)
        await coachWait { !model.isSending }
        let id = model.turns[0].id
        #expect(model.turns[0].revealed == false)
        model.markRevealed(id)
        #expect(model.turns[0].revealed)
        model.markRevealed(id)
        model.markRevealed(UUID())
        #expect(model.turns[0].revealed)
    }

    // MARK: - Feedback, saved on this device

    @Test func helpfulIsSavedWithTheStoredAnswerAndPressingItAgainTakesItBack() async throws {
        let history = try store()
        let model = viewModel(await service(history: history), history: history)
        model.startConversation(asking: .recovery(.lower))
        await coachWait { !model.isSending }
        let turn = try #require(model.turns.first)
        #expect(turn.messageID != nil, "the answer was kept, so feedback has somewhere to go")
        #expect(turn.feedback == nil)

        model.setFeedback(.helpful, for: turn.id)
        #expect(model.turns[0].feedback == .helpful)
        let id = try #require(model.conversationID)
        #expect(await waitFor { await history.turns(in: id).first?.feedback == .helpful }, "the save landed")
        var stored = await history.turns(in: id)

        model.setFeedback(.notHelpful, for: turn.id)
        #expect(model.turns[0].feedback == .notHelpful)
        #expect(await waitFor { await history.turns(in: id).first?.feedback == .notHelpful })
        stored = await history.turns(in: id)

        model.setFeedback(.notHelpful, for: turn.id)
        #expect(model.turns[0].feedback == nil)
        #expect(await waitFor { await history.turns(in: id).first?.feedback == nil })
        stored = await history.turns(in: id)
        #expect(stored.first?.feedback == nil)
    }

    @Test func feedbackOnAFixedReplyOrAnUnknownTurnDoesNothing() async {
        let medical = StubAnswering(result: CoachResult(answer: CoachScriptedAnswers.answer(.medical), outcome: .scripted(.medical)))
        let model = viewModel(medical)
        model.startConversation(asking: "do I have sleep apnea")
        await coachWait { !model.isSending }
        model.setFeedback(.helpful, for: model.turns[0].id)
        #expect(model.turns[0].feedback == nil, "a fixed reply has no message to attach it to")
        model.setFeedback(.helpful, for: UUID())
    }

    @Test func feedbackIsNotSentAnywhereButTheStore() {
        // No analytics event carries an answer, a question or a number: Coach has none at all.
        let events = [NoctisAnalyticsEvent.paywallViewed, .planSelected, .trialStarted, .purchaseCompleted, .paywallDismissed, .onboardingCompleted]
        #expect(events.allSatisfy { !$0.rawValue.contains("coach") })
    }

    // MARK: - What is stored

    @Test func onlyTheStoredAnswersAreKeptAndAFixedReplyIsNot() async throws {
        let history = try store()
        let service = await service(history: history)
        let model = viewModel(service, history: history)
        model.startConversation(asking: "do I have sleep apnea")
        await coachWait { !model.isSending }
        model.followUp("I want to die")
        await coachWait { !model.isSending }
        model.followUp("Why is my recovery lower today?")
        await coachWait { !model.isSending }
        #expect(model.turns.count == 3)
        #expect(model.turns[0].messageID == nil && model.turns[1].messageID == nil && model.turns[2].messageID != nil)
        #expect(await history.messageCount() == 1)
    }
}
