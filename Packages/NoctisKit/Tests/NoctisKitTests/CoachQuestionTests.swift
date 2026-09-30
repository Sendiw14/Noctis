import Foundation
import HealthProviding
import SwiftData
import Testing
@testable import CoachKit
@testable import InsightsKit
@testable import NoctisCore

/// The questions Coach hands around: their words, their routes, their order.
struct CoachQuestionTests {
    private let router = CoachQuestionRouter()

    private static let allQuestions: [CoachQuestion] =
        [.recovery(nil), .recovery(.higher), .recovery(.lower), .sleep(nil), .sleep(.higher), .sleep(.lower), .week, .bedtime, .consistency, .focus]
        + InsightType.allCases.map(CoachQuestion.insight)

    // MARK: - Words

    @Test func theSixSuggestedQuestionsAreTheSpecsWords() {
        #expect(CoachQuestionText.text(.recovery(.higher)) == "Why is my recovery higher today?")
        #expect(CoachQuestionText.text(.recovery(.lower)) == "Why is my recovery lower today?")
        #expect(CoachQuestionText.text(.sleep(.higher)) == "Why was my sleep better last night?")
        #expect(CoachQuestionText.text(.sleep(.lower)) == "Why was my sleep worse last night?")
        #expect(CoachQuestionText.text(.week) == "What changed this week?")
        #expect(CoachQuestionText.text(.bedtime) == "When should I sleep?")
        #expect(CoachQuestionText.text(.consistency) == "How can I improve consistency?")
        #expect(CoachQuestionText.text(.focus) == "What should I focus on today?")
    }

    @Test func everyQuestionHasTextInTheCatalogAndNoneIsMissing() {
        for question in Self.allQuestions {
            let text = CoachQuestionText.text(question)
            #expect(!text.hasPrefix("coach."), Comment(rawValue: question.token))
            #expect(text.hasSuffix("?") || text.hasSuffix("."), Comment(rawValue: text))
            #expect(!text.hasDigit, "a question is words")
        }
        #expect(Set(Self.allQuestions.map { CoachQuestionText.text($0) }).count == Self.allQuestions.count, "no two questions share a sentence")
    }

    @Test func aQuestionsTextFitsTheInputAndDoesntTripTheGuards() {
        for question in Self.allQuestions {
            let text = CoachQuestionText.text(question)
            #expect(text.count <= 200, Comment(rawValue: text))
            let route = router.route(text)
            #expect(route.reply == nil, Comment(rawValue: "\(text) got a fixed reply"))
        }
    }

    // MARK: - Routing

    @Test func everyQuestionsTextRoutesToTheIntentItIsFor() {
        for question in Self.allQuestions {
            let text = CoachQuestionText.text(question)
            #expect(router.route(text).intent == CoachQuestionText.intent(of: question), Comment(rawValue: "\(text) → \(router.route(text).intent)"))
        }
    }

    @Test func aQuestionThatNamesADirectionRoutesWithThatDirection() {
        for (question, trend) in [(CoachQuestion.recovery(.higher), CoachDirection.higher), (.recovery(.lower), .lower), (.sleep(.higher), .higher), (.sleep(.lower), .lower)] {
            #expect(router.route(CoachQuestionText.text(question)).direction == trend, Comment(rawValue: question.token))
        }
        #expect(router.route(CoachQuestionText.text(.recovery(nil))).direction == nil)
        #expect(router.route(CoachQuestionText.text(.sleep(nil))).direction == nil)
    }

    @Test func everyInsightTypeHasAQuestionAndAnIntent() {
        for type in InsightType.allCases {
            let question = CoachQuestion.insight(type)
            #expect(CoachQuestionText.intent(of: question).usesData, Comment(rawValue: type.rawValue))
            #expect(CoachQuestionText.text(question).contains("my") || CoachQuestionText.text(question).contains("your"), Comment(rawValue: type.rawValue))
        }
    }

    // MARK: - Tokens and routes

    @Test func aQuestionsTokenRoundTrips() {
        for question in Self.allQuestions { #expect(CoachQuestion(token: question.token) == question, Comment(rawValue: question.token)) }
        #expect(CoachQuestion(token: "recovery.sideways") == .recovery(nil))
        for bad in ["", "nonsense", "insight", "insight.notAType", "week.lower"] {
            let parsed = CoachQuestion(token: bad)
            #expect(parsed == nil || parsed == .week, Comment(rawValue: bad))
        }
        #expect(CoachQuestion(token: "insight.notAType") == nil)
    }

    @Test func theCoachRouteCarriesItsQuestionThroughAURLAndAName() {
        for question in Self.allQuestions {
            let route = AppRoute.coach(question: question)
            #expect(AppRoute(url: route.url) == route, Comment(rawValue: question.token))
            #expect(route.url.absoluteString.hasPrefix("noctis://coach?question="))
            #expect(AppRoute(name: "coach:\(question.token)") == route, Comment(rawValue: question.token))
        }
        #expect(AppRoute.coach().url.absoluteString == "noctis://coach")
        #expect(AppRoute(url: URL(string: "noctis://coach")!) == .coach())
        #expect(AppRoute(url: URL(string: "noctis://coach?question=bogus")!) == .coach())
        #expect(AppRoute(name: "coach") == .coach())
        #expect(AppRoute.coach(question: .week).tab == .coach)
        #expect(AppRoute.coach(question: .week).name == "coach")
    }

    @Test func aCoachRouteRoundTripsThroughJSON() throws {
        let route = AppRoute.coach(question: .insight(.bedtimeShift))
        #expect(try JSONDecoder().decode(AppRoute.self, from: JSONEncoder().encode(route)) == route)
    }

    @Test func openingCoachHandsTheTabItsQuestionOnce() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        model.open(.coach(question: .recovery(.lower)))
        #expect(model.selectedTab == .coach)
        #expect(model.coachDestination?.question == .recovery(.lower))
        #expect(model.takeCoachDestination()?.question == .recovery(.lower))
        #expect(model.takeCoachDestination() == nil)
        model.coachPath = [.history, .conversation]
        model.open(.coach())
        #expect(model.coachPath.isEmpty, "opening Coach lands on the hub")
        #expect(model.takeCoachDestination()?.question == nil)
        model.open(.coach(question: .week))
        model.open(.coach(question: .week))
        #expect(model.coachDestination != nil, "the same question twice is still a change")
    }

    // MARK: - Follow-ups

    @Test func afterAnAnswerThereAreAtMostThreeOtherQuestions() {
        for intent in CoachQuestionRouter.intentOrder {
            let follow = CoachFollowUps.questions(after: intent)
            #expect(follow.count == 3, Comment(rawValue: intent.rawValue))
            #expect(follow.count <= CoachFollowUps.maximum)
            #expect(Set(follow).count == follow.count)
            #expect(!follow.map(CoachQuestionText.intent(of:)).contains(intent), "a follow-up isn't the question just answered")
        }
        for intent in [CoachIntent.medicalOutOfScope, .crisis, .unknown] { #expect(CoachFollowUps.questions(after: intent).isEmpty) }
    }

    // MARK: - Ranking

    private func fact(_ id: String, _ value: Double, _ unit: CoachUnit = .points) -> CoachFact { CoachFixture.fact(id, value, unit) }

    @Test func withNoChangeBehindThemTheSixKeepTheirFixedOrder() {
        let ranked = CoachSuggestionRanker.rank(facts: [], state: .ready, evening: false)
        #expect(ranked.map(\.question).count == 6 && Set(ranked.map(\.question)).count == 6)
        // Focus (0.3) and bedtime (0.15) are the only ones with any relevance: the rest follow in the fixed order.
        #expect(ranked.map(\.question) == [.focus, .bedtime, .recovery(nil), .sleep(nil), .week, .consistency])
    }

    @Test func theLargestRecentChangeComesFirstWithTheDirectionItMoved() {
        let facts = [fact("recovery.deltaVsUsual", -18), fact("sleep.deltaVsBaseline", -20, .duration), fact("week.avgSleepDelta", 30, .duration)]
        let ranked = CoachSuggestionRanker.rank(facts: facts, state: .ready, evening: false)
        #expect(ranked.first?.question == .recovery(.lower))
        #expect(ranked.first?.relevance == 1)
        #expect(ranked[1].question == .focus || ranked[1].question == .week || ranked[1].question == .sleep(.lower))
        let order = ranked.map(\.question)
        #expect(order.firstIndex(of: .week)! < order.firstIndex(of: .bedtime)!)
        #expect(order.contains(.sleep(.lower)), "the sleep question carries the direction of the data")
    }

    @Test func aHigherThanUsualNumberGivesAHigherQuestion() {
        let facts = [fact("recovery.deltaVsUsual", 12), fact("sleep.deltaVsBaseline", 45, .duration)]
        let ranked = CoachSuggestionRanker.rank(facts: facts, state: .ready, evening: false).map(\.question)
        #expect(ranked.contains(.recovery(.higher)))
        #expect(ranked.contains(.sleep(.higher)))
    }

    @Test func aChangeUnderTheFloorIsNeitherHigherNorLower() {
        let facts = [fact("recovery.deltaVsUsual", 2), fact("sleep.deltaVsBaseline", 10, .duration)]
        let ranked = CoachSuggestionRanker.rank(facts: facts, state: .ready, evening: false).map(\.question)
        #expect(ranked.contains(.recovery(nil)) && ranked.contains(.sleep(nil)))
        let atFloor = CoachSuggestionRanker.rank(facts: [fact("recovery.deltaVsUsual", -3)], state: .ready, evening: false).map(\.question)
        #expect(atFloor.contains(.recovery(.lower)))
    }

    @Test func relevanceScalesWithSizeAndCaps() {
        func relevance(_ id: String, _ value: Double, _ question: CoachQuestion, unit: CoachUnit = .points) -> Double {
            CoachSuggestionRanker.rank(facts: [fact(id, value, unit)], state: .ready, evening: false).first { $0.question == question }?.relevance ?? -1
        }
        #expect(relevance("recovery.deltaVsUsual", -7.5, .recovery(.lower)) == 0.5)
        #expect(relevance("recovery.deltaVsUsual", -40, .recovery(.lower)) == 1)
        #expect(relevance("sleep.deltaVsBaseline", 30, .sleep(.higher), unit: .duration) == 0.5)
        #expect(relevance("week.avgSleepDelta", -90, .week, unit: .duration) == 1)
        #expect(relevance("bedtime.deltaVsUsual", 30, .consistency, unit: .duration) == 0.5)
        #expect(relevance("consistency.bedtimeVarMin", 60, .consistency, unit: .minutes) == 0.5)
    }

    @Test func inTheEveningBedtimeLeadsUnlessSomethingChangedAsMuch() {
        let quiet = CoachSuggestionRanker.rank(facts: [], state: .ready, evening: true)
        #expect(quiet.first?.question == .bedtime && quiet.first?.relevance == 1)
        let loud = CoachSuggestionRanker.rank(facts: [fact("recovery.deltaVsUsual", -30)], state: .ready, evening: true)
        #expect(loud.first?.question == .recovery(.lower), "a tie goes to the fixed order")
        #expect(loud[1].question == .bedtime)
    }

    @Test func withNoDataEveryQuestionIsEquallyIrrelevantAndKeepsItsPlace() {
        let ranked = CoachSuggestionRanker.rank(facts: [fact("recovery.deltaVsUsual", -30)], state: .noData, evening: true)
        #expect(ranked.map(\.relevance) == Array(repeating: 0, count: 6))
        #expect(ranked.map(\.question) == [.recovery(.lower), .sleep(nil), .week, .bedtime, .consistency, .focus])
    }

    @Test func everyScenarioRanksAllSixOnceFromRealFacts() async {
        for scenario in CoachFixture.scenarios {
            let snapshots = await CoachFixture.snapshots(scenario)
            let facts = CoachContextBuilder(format: CoachFixture.format).allFacts(snapshots: snapshots, profile: CoachFixture.profile)
            let state = CoachContextBuilder.dataState(snapshots)
            let ranked = CoachSuggestionRanker.rank(facts: facts, state: state, evening: false)
            #expect(ranked.count == 6 && Set(ranked.map(\.id)).count == 6, Comment(rawValue: scenario.rawValue))
            #expect(ranked.map(\.relevance) == ranked.map(\.relevance).sorted(by: >), Comment(rawValue: scenario.rawValue))
            #expect(ranked.allSatisfy { (0...1).contains($0.relevance) })
        }
    }

    @Test func theFullScenariosBiggestChangeLeads() async throws {
        let snapshots = await CoachFixture.snapshots(.full)
        let facts = CoachContextBuilder(format: CoachFormatHolder.format).allFacts(snapshots: snapshots, profile: CoachFixture.profile)
        let ranked = CoachSuggestionRanker.rank(facts: facts, state: .ready, evening: false)
        // Recovery is 18 points under usual and sleep 70 minutes short: both are as relevant as a change gets; recovery is first in the fixed order.
        #expect(ranked[0].question == .recovery(.lower))
        #expect(ranked[1].question == .sleep(.lower))
    }
}

private enum CoachFormatHolder {
    static let format = CoachFixture.format
}
