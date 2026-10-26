import Foundation
import HealthProviding
import SwiftData
import Testing

@testable import CoachKit
@testable import HomeFeature
@testable import InsightsFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import SleepFeature

/// How the other tabs hand a question to Coach.
struct CoachRoutingTests {
    // MARK: - The matching question

    @Test func recoveryQuestionFollowsHowTodaysScoreMoved() {
        #expect(CoachQuestion.recovery(delta: -18) == .recovery(.lower))
        #expect(CoachQuestion.recovery(delta: -3) == .recovery(.lower))
        #expect(CoachQuestion.recovery(delta: -2) == .recovery(nil))
        #expect(CoachQuestion.recovery(delta: 0) == .recovery(nil))
        #expect(CoachQuestion.recovery(delta: 2) == .recovery(nil))
        #expect(CoachQuestion.recovery(delta: 3) == .recovery(.higher))
        #expect(CoachQuestion.recovery(delta: 12) == .recovery(.higher))
        #expect(CoachQuestion.recovery(delta: nil) == .recovery(nil))
    }

    @Test func sleepQuestionFollowsHowLastNightMovedFromUsual() {
        #expect(CoachQuestion.sleep(deltaMinutes: -70) == .sleep(.lower))
        #expect(CoachQuestion.sleep(deltaMinutes: -15) == .sleep(.lower))
        #expect(CoachQuestion.sleep(deltaMinutes: -14.9) == .sleep(nil))
        #expect(CoachQuestion.sleep(deltaMinutes: 14.9) == .sleep(nil))
        #expect(CoachQuestion.sleep(deltaMinutes: 15) == .sleep(.higher))
        #expect(CoachQuestion.sleep(deltaMinutes: nil) == .sleep(nil))
    }

    @Test func theSameThresholdsAreTheHubsAndTheAnswersOwn() {
        #expect(CoachSuggestionRanker.recoveryThreshold == CoachQuestion.recoveryThreshold)
        #expect(CoachSuggestionRanker.sleepThreshold == CoachQuestion.sleepThresholdMinutes)
        #expect(TemplateCoachProvider.recoveryThreshold == CoachQuestion.recoveryThreshold)
        #expect(TemplateCoachProvider.minorMinutes == CoachQuestion.sleepThresholdMinutes)
    }

    @Test func aRoutedQuestionReadsAsTheSameIntentAndDirectionTheAnswerWillUse() async throws {
        // The question a button hands over is answered in the direction the data really moved, so it never says "points the other way".
        let context = await CoachFixture.context(.recoveryChange, CoachDirection.lower, scenario: .full)
        let draft = TemplateCoachProvider(locale: CoachFixture.locale).compose(intent: .recoveryChange, context: context)
        let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: CoachFixture.locale))
        #expect(!answer.whatToNotice.contains("different way"))
    }

    // MARK: - Recovery

    @Test func recoveryTodaysButtonAsksTheQuestionThatMatchesItsScore() async throws {
        let snapshots = await CoachFixture.snapshots(.full)
        let result = try #require(snapshots.recovery?.result)
        let content = HomeScreenBuilder.scoredContent(result)
        #expect(content.coachQuestion == .recovery(delta: result.comparison.delta))
        #expect(content.coachQuestion == .recovery(.lower), "the full scenario's recovery is well under its usual")
        #expect(CoachQuestionText.text(content.coachQuestion) == "Why is my recovery lower today?")
    }

    @Test func aScoreThatIsInLineAsksTheNeutralQuestion() async throws {
        let snapshots = await CoachFixture.snapshots(.steady)
        let result = try #require(snapshots.recovery?.result)
        let content = HomeScreenBuilder.scoredContent(result)
        let delta = try #require(result.comparison.delta)
        #expect(content.coachQuestion == .recovery(delta: delta))
        if abs(delta) < 3 { #expect(content.coachQuestion == .recovery(nil)) }
    }

    // MARK: - Sleep

    @Test func sleepDaysButtonAsksTheQuestionThatMatchesLastNight() async throws {
        let snapshots = await CoachFixture.snapshots(.full)
        let sleep = try #require(snapshots.sleep)
        let record = try #require(sleep.records.last)
        let card = SleepScreenBuilder.qualityCard(record, snapshot: sleep, format: CoachFixture.format)
        #expect(card.coachQuestion == .sleep(.lower), "6h 42m against a usual of 7h 52m")
        #expect(CoachQuestionText.text(card.coachQuestion) == "Why was my sleep worse last night?")
    }

    @Test func aNightWithNoBaselineAsksTheNeutralQuestion() async throws {
        let snapshots = await CoachFixture.snapshots(.learning)
        let sleep = try #require(snapshots.sleep)
        let record = try #require(sleep.records.last)
        let card = SleepScreenBuilder.qualityCard(record, snapshot: sleep, format: CoachFixture.format)
        #expect(card.coachQuestion == .sleep(nil))
    }

    // MARK: - An insight

    @Test func everyInsightTypeCanBeAskedAbout() {
        for type in InsightType.allCases {
            let route = AppRoute.coach(question: .insight(type))
            #expect(AppRoute(url: route.url) == route, Comment(rawValue: type.rawValue))
            #expect(route.tab == .coach)
            let text = CoachQuestionText.text(.insight(type))
            #expect(!text.hasPrefix("coach."), Comment(rawValue: type.rawValue))
            #expect(CoachQuestionRouter().route(text).intent == CoachQuestionText.intent(of: .insight(type)))
        }
    }

    // MARK: - Opening Coach from another tab

    @Test func aButtonOpensCoachOnItsQuestionWithTheHubUnderneath() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.selectedTab = .recovery
        model.coachPath = [.conversation, .history]
        model.open(.coach(question: .recovery(.lower)))
        #expect(model.selectedTab == .coach)
        #expect(model.coachPath.isEmpty, "the tab lands on its hub; the conversation is pushed once the question is taken")
        #expect(model.takeCoachDestination()?.question == .recovery(.lower))
    }

    @Test func theTabsRetapLeavesAConversationForTheHub() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.retap(.coach)
        #expect(model.tabRetap?.tab == .coach)
        let first = model.tabRetap
        model.retap(.coach)
        #expect(model.tabRetap != first, "each press is its own event")
    }

    // MARK: - Nothing keeps a question or an answer in a route

    @Test func aRouteCarriesOnlyWhichQuestionItIsNeverItsWords() {
        for question in CoachQuestion.suggested + [.recovery(.lower), .sleep(.higher), .insight(.hrvBelowRange)] {
            let url = AppRoute.coach(question: question).url.absoluteString
            #expect(!url.contains("%20") && !url.contains("?%"), Comment(rawValue: url))
            #expect(url.hasPrefix("noctis://coach"))
            #expect(!url.lowercased().contains("recovery is") && !url.contains("Why"))
        }
    }
}
