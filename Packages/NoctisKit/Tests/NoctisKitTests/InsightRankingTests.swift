import Foundation
import Testing
@testable import InsightsKit
@testable import SleepKit

struct InsightRankingTests {
    typealias R = InsightRecordFixture
    private let today = InsightFixture.last

    // MARK: - The score

    @Test func theScoreIsTheWeightedSumOfFourNumbers() {
        // high 1 · relevance 1 · novelty 1 · actionability 0.8
        #expect(InsightRanking.score(confidence: .high, relevance: 1, novelty: 1, actionability: 0.8) == 0.97)
        // moderate 0.6 · 0.5 · 0.5 · 0.25 = 0.21 + 0.15 + 0.10 + 0.0375
        #expect(InsightRanking.score(confidence: .moderate, relevance: 0.5, novelty: 0.5, actionability: 0.25) == 0.4975)
        // low 0.3
        #expect(InsightRanking.score(confidence: .low, relevance: 0, novelty: 0, actionability: 0) == 0.105)
        #expect(abs(InsightRanking.confidenceWeight + InsightRanking.relevanceWeight + InsightRanking.noveltyWeight + InsightRanking.actionabilityWeight - 1) < 1e-12)
    }

    @Test func relevanceFallsAwayOverTwoWeeks() {
        #expect(InsightRanking.relevance(of: today, on: today) == 1)
        #expect(InsightRanking.relevance(of: today.adding(days: -7), on: today) == 0.5)
        #expect(InsightRanking.relevance(of: today.adding(days: -14), on: today) == 0)
        #expect(InsightRanking.relevance(of: today.adding(days: -30), on: today) == 0, "never negative")
        #expect(InsightRanking.relevance(of: today.adding(days: 2), on: today) == 1, "a night in the future is not more relevant than the newest")
    }

    @Test func noveltyReturnsAsATypeStaysOutOfTheFeatured() {
        var history = InsightHistory()
        #expect(InsightRanking.novelty(of: .bedtimeShift, on: today, history: history) == 1, "never featured")
        history.recordFeatured(R.bedtime(delta: 55), on: today.adding(days: -3))
        #expect(InsightRanking.novelty(of: .bedtimeShift, on: today, history: history) == 3.0 / 14)
        #expect(InsightRanking.novelty(of: .sleepDurationShift, on: today, history: history) == 1, "another type")
        history.recordFeatured(R.bedtime(delta: 55), on: today.adding(days: -20))
        #expect(InsightRanking.novelty(of: .bedtimeShift, on: today, history: history) == 1, "capped")
    }

    @Test func actionabilityFollowsWhatAPersonCanDoAboutIt() {
        #expect(R.duration(delta: -70).actionability == 0.8)
        #expect(R.pattern().actionability == 0.5)
        #expect(R.heart(.hrv).actionability == 0.25)
        #expect(R.milestone(7).actionability == 0)
    }

    // MARK: - The order

    @Test func higherConfidenceOutranksLower() {
        let ranked = InsightRanking.ranked([R.duration(delta: -70, confidence: .low), R.duration(delta: -71, confidence: .high)], on: today)
        #expect(ranked.map(\.confidence) == [.high, .low])
    }

    @Test func aMoreRecentNightOutranksAnOlderOne() {
        // The same type and confidence, so relevance alone decides.
        let ranked = InsightRanking.ranked([R.balance(behind: true, on: today.adding(days: -6)), R.balance(behind: false, on: today)], on: today)
        #expect(ranked.first?.night == today)
    }

    @Test func aTypeNotFeaturedRecentlyOutranksOneThatWas() {
        var history = InsightHistory()
        history.recordFeatured(R.bedtime(delta: 40), on: today.adding(days: -1))
        let ranked = InsightRanking.ranked([R.bedtime(delta: 55), R.duration(delta: -70)], on: today, history: history)
        #expect(ranked.first?.type == .sleepDurationShift, "same confidence and actionability; duration hasn't been featured")
    }

    @Test func aTieGoesToTheSmallerIdWhateverTheInputOrder() {
        let a = R.balance(behind: true)
        let b = R.balance(behind: false)
        #expect(InsightRanking.score(a) == InsightRanking.score(b))
        let expected = [a, b].map(\.id).sorted()
        #expect(InsightRanking.ranked([a, b], on: today).map(\.id) == expected)
        #expect(InsightRanking.ranked([b, a], on: today).map(\.id) == expected)
    }

    @Test func theLargerOfTwoShiftsLeadsAndDurationWinsAnEqualOne() {
        let duration = R.duration(delta: -70)
        let bedtime = R.bedtime(delta: 55)
        #expect(InsightRanking.score(duration) == InsightRanking.score(bedtime), "the same score, so the shifts' own order decides")
        #expect(InsightRanking.ranked([bedtime, duration], on: today).map(\.type) == [.sleepDurationShift, .bedtimeShift])
        #expect(InsightRanking.ranked([R.duration(delta: -40), R.bedtime(delta: 55)], on: today).map(\.type) == [.bedtimeShift, .sleepDurationShift])
        #expect(InsightRanking.ranked([R.bedtime(delta: 50), R.duration(delta: -50)], on: today).map(\.type) == [.sleepDurationShift, .bedtimeShift])
    }

    @Test func theShiftsLeadAnyTieWithAnotherKindAtTheSameScore() {
        // A sleep balance has the same confidence and actionability as a shift; the shifts go first.
        let balance = R.balance(behind: true)
        #expect(InsightRanking.score(balance) == InsightRanking.score(R.duration(delta: -70)))
        let ranked = InsightRanking.ranked([balance, R.duration(delta: -70), R.bedtime(delta: 55)], on: today)
        #expect(ranked.map(\.type) == [.sleepDurationShift, .bedtimeShift, .sleepBalance])
    }

    @Test func aLearningMilestoneRanksAfterEveryInsight() {
        // Even a low-confidence insight scores under a high-confidence milestone.
        let weak = R.record(.recoveryDirection, R.recovery().evidence, confidence: .low, nights: 7)
        let ranked = InsightRanking.ranked([R.milestone(7), weak], on: today)
        #expect(ranked.map(\.type) == [.recoveryDirection, .milestone])
        #expect(InsightRanking.score(R.milestone(7).with(relevance: 1, novelty: 1)) > InsightRanking.score(weak.with(relevance: 1, novelty: 1)))
    }

    @Test func theSameRecordsInAnyOrderGiveTheSameList() {
        let records = R.everyVariant
        let expected = InsightRanking.ranked(records, on: today).map(\.id)
        #expect(InsightRanking.ranked(records.reversed(), on: today).map(\.id) == expected)
        for shift in [1, 5, 11] {
            let rotated = Array(records[shift...] + records[..<shift])
            #expect(InsightRanking.ranked(rotated, on: today).map(\.id) == expected)
        }
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<5 { #expect(InsightRanking.ranked(records.shuffled(using: &generator), on: today).map(\.id) == expected) }
    }

    @Test func rankingRescoresStoredRecordsAsTheyAge() {
        let stored = R.duration(delta: -70, on: today)
        let later = InsightRanking.ranked([stored], on: today.adding(days: 7)).first
        #expect(later?.relevance == 0.5)
        #expect(stored.relevance == 1, "the stored record is untouched")
    }

    @Test func scoresAreRoundedSoFloatNoiseCannotReorderATie() {
        let a = InsightRanking.score(confidence: .moderate, relevance: 1.0 / 3, novelty: 1.0 / 3, actionability: 0.25)
        #expect(a == (a * 1_000_000).rounded() / 1_000_000)
    }
}
