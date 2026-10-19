import Foundation
import HealthProviding
import Testing
@testable import CoachKit
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepKit

/// The slice of the person's data a question may use.
struct CoachContextTests {
    private func builder(_ locale: Locale = CoachFixture.locale) -> CoachContextBuilder {
        CoachContextBuilder(format: HomeFormat(calendar: Fixture.calendar(), locale: locale))
    }

    // MARK: - Nothing personal, nothing raw

    @Test func theContextHoldsNoNameNoAccountAndNoSourceName() async throws {
        let snapshots = await CoachFixture.snapshots(.full)
        let sources = Set(snapshots.sleep?.records.map(\.session.sourceName) ?? [])
        #expect(!sources.isEmpty, "the check has something to look for")
        for intent in CoachIntent.allCases {
            let context = builder().build(intent: intent, direction: .lower, snapshots: snapshots, profile: CoachFixture.profile)
            let json = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
            #expect(!json.contains("Alex"), Comment(rawValue: intent.rawValue))
            #expect(!json.contains("Tester"))
            for source in sources { #expect(!json.contains(source), Comment(rawValue: "source \(source)")) }
            #expect(!json.lowercased().contains("icloud") && !json.contains("@"))
        }
    }

    @Test func theContextHasNoFieldForASampleATimeAJournalOrAName() async throws {
        let context = await CoachFixture.context(.recoveryChange)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
        let allowed: Set<String> = [
            "intent", "direction", "facts", "insights", "availableFactors", "missingFactors", "nightsOfHistory", "baselineNights", "dataState", "goalIDs",
            "sleepNeedMinutes", "confidenceCeiling", "recentTurns",
        ]
        #expect(Set(object.keys).isSubset(of: allowed), Comment(rawValue: "\(Set(object.keys).subtracting(allowed))"))
        let facts = try #require(object["facts"] as? [[String: Any]])
        for fact in facts { #expect(Set(fact.keys) == ["id", "label", "value", "unit", "display", "spoken", "source"]) }
        let briefs = try #require(object["insights"] as? [[String: Any]])
        for brief in briefs { #expect(Set(brief.keys) == ["id", "type", "confidence", "factIDs"]) }
    }

    @Test func everyFactIsOnTheAllowedListAndHasAnEnginesName() async {
        for scenario in CoachFixture.scenarios {
            let snapshots = await CoachFixture.snapshots(scenario)
            for intent in CoachContextBuilder.prefixesIntents {
                let context = builder().build(intent: intent, direction: nil, snapshots: snapshots, profile: CoachFixture.profile)
                for fact in context.facts {
                    #expect(CoachFactCatalog.allows(fact.id), Comment(rawValue: "\(scenario.rawValue) \(fact.id)"))
                    #expect(fact.value.isFinite)
                    #expect(!fact.source.isEmpty && !fact.label.isEmpty && !fact.display.isEmpty && !fact.spoken.isEmpty)
                }
                #expect(Set(context.facts.map(\.id)).count == context.facts.count, "no fact twice")
            }
        }
    }

    @Test func goalsAreRawIdsNeverTheNameOrTheTitle() async {
        let context = await CoachFixture.context(.todayFocus)
        #expect(context.goalIDs == ["betterRecovery", "betterConsistency"])
        #expect(context.sleepNeedMinutes == 480)
        let single = builder().build(intent: .todayFocus, direction: nil, snapshots: CoachSnapshots(), profile: UserProfileSnapshot(name: "Sam", primaryGoal: .moreEnergy))
        #expect(single.goalIDs == ["moreEnergy"])
    }

    // MARK: - Absent means absent

    @Test func withoutHeartDataThereAreNoHeartFactsAndTheReasonIsNotProvided() async {
        let context = await CoachFixture.context(.recoveryChange, scenario: .sleepOnly)
        #expect(!context.has("hrv.today") && !context.has("hrv.baseline") && !context.has("rhr.today") && !context.has("rhr.baseline"))
        #expect(context.has("recovery.score") && context.has("sleep.duration"))
        #expect(context.availableFactors.contains("sleepDuration"))
        #expect(!context.availableFactors.contains("hrv") && !context.availableFactors.contains("restingHeartRate"))
        #expect(context.missingFactors.contains(CoachMissingFactor(factor: "hrv", reason: .notProvided)))
        #expect(context.missingFactors.contains(CoachMissingFactor(factor: "restingHeartRate", reason: .notProvided)))
    }

    @Test func whileLearningThereIsNoRecoveryNoBaselineAndEveryFactorNeedsMoreNights() async {
        let context = await CoachFixture.context(.recoveryChange, scenario: .learning)
        #expect(context.dataState == .learning)
        #expect(context.nightsOfHistory == 3)
        for id in ["recovery.score", "recovery.usual", "recovery.deltaVsUsual", "sleep.baseline", "sleep.deltaVsBaseline", "hrv.baseline", "bedtime.usual", "week.avgSleepDelta"] {
            #expect(!context.has(id), Comment(rawValue: id))
        }
        #expect(context.availableFactors.isEmpty)
        #expect(context.missingFactors.count == RecoveryFactorKind.allCases.count)
        #expect(context.missingFactors.allSatisfy { $0.reason == .needsMoreNights })
        #expect(context.confidenceCeiling == .low)
    }

    @Test func withNoDataThereAreNoHealthFactsForAnIntentThatReadsThem() async {
        for intent in [CoachIntent.recoveryChange, .sleepChange, .weekChange, .consistencyHelp, .patterns] {
            let context = await CoachFixture.context(intent, scenario: .empty)
            #expect(context.dataState == .noData)
            // Only what the person set themselves (their sleep need, wake time and the bedtime they give) can be there.
            #expect(Set(context.facts.map(\.id)).isSubset(of: ["sleep.need", "wake.typical", "bedtime.suggested"]), Comment(rawValue: "\(intent.rawValue): \(context.facts.map(\.id))"))
            #expect(context.nightsOfHistory == 0)
            #expect(context.insights.isEmpty && context.availableFactors.isEmpty && context.missingFactors.isEmpty)
            #expect(context.confidenceCeiling == .low)
        }
    }

    @Test func aMissingNightIsNotZero() async {
        let context = await CoachFixture.context(.sleepChange, scenario: .gap)
        #expect(context.dataState == .noSleepLastNight)
        #expect(!context.has("sleep.duration") && !context.has("sleep.quality") && !context.has("bedtime.last") && !context.has("recovery.score"))
        #expect(context.missingFactors.allSatisfy { $0.reason == .notRecorded })
    }

    @Test func staleDataSaysSoAndClaimsLittle() async {
        let context = await CoachFixture.context(.recoveryChange, scenario: .stale)
        #expect(context.dataState == .stale)
        #expect(context.confidenceCeiling == .low)
        #expect(!context.has("recovery.score"))
    }

    @Test func noSnapshotsAtAllIsNoData() {
        let context = builder().build(intent: .weekChange, direction: nil, snapshots: CoachSnapshots(), profile: CoachFixture.profile)
        #expect(context.dataState == .noData)
        #expect(context.facts.isEmpty)
        #expect(context.nightsOfHistory == 0)
    }

    // MARK: - The cap

    @Test func aContextNeverHoldsMoreThan40Facts() {
        let many = (0..<75).map { CoachFixture.fact("history.fact\($0)", Double($0), .count) }
        let context = CoachFixture.handmade(facts: many)
        #expect(context.facts.count == CoachContext.maxFacts && CoachContext.maxFacts == 40)
        #expect(context.facts.first?.id == "history.fact0" && context.facts.last?.id == "history.fact39")
        #expect(CoachContextBuilder.slice(many, for: .patterns).count <= 40)
        #expect(CoachContextBuilder.slice(many, for: .recoveryChange).count <= 40)
    }

    @Test func theSliceIsCappedForEveryIntentInEveryScenario() async {
        for scenario in CoachFixture.scenarios {
            let snapshots = await CoachFixture.snapshots(scenario)
            for intent in CoachIntent.allCases {
                let context = builder().build(intent: intent, direction: nil, snapshots: snapshots, profile: CoachFixture.profile)
                #expect(context.facts.count <= 40)
                #expect(context.insights.count <= CoachContext.maxInsights)
            }
        }
    }

    @Test func aContextHoldsAtMostTwoEarlierTurns() {
        let turns = (0..<5).map { CoachTurnSummary(question: "q\($0)", answerSummary: "a\($0)") }
        let context = CoachFixture.handmade().withTurns(turns)
        #expect(context.recentTurns.map(\.question) == ["q3", "q4"])
        #expect(CoachContext(intent: .patterns, direction: nil, facts: [], insights: [], availableFactors: [], missingFactors: [], nightsOfHistory: 0, dataState: .noData, goalIDs: [], sleepNeedMinutes: 480, confidenceCeiling: .low, recentTurns: turns).recentTurns.count == 2)
    }

    // MARK: - Slices by intent

    @Test func eachIntentSeesItsOwnSlice() async {
        let snapshots = await CoachFixture.snapshots(.full)
        func ids(_ intent: CoachIntent) -> Set<String> {
            Set(builder().build(intent: intent, direction: nil, snapshots: snapshots, profile: CoachFixture.profile).facts.map(\.id))
        }
        let recovery = ids(.recoveryChange)
        #expect(recovery.isSuperset(of: ["recovery.score", "recovery.usual", "recovery.deltaVsUsual", "hrv.today", "hrv.baseline", "rhr.today", "rhr.baseline", "sleep.duration", "bedtime.last"]))
        #expect(!recovery.contains("week.avgSleep") && !recovery.contains("consistency.bedtimeVarMin"))

        let sleep = ids(.sleepChange)
        #expect(sleep.isSuperset(of: ["sleep.duration", "sleep.deltaVsBaseline", "sleep.quality", "deep.share", "rem.share", "bedtime.last"]))
        #expect(!sleep.contains("recovery.score") && !sleep.contains("hrv.today"))

        let week = ids(.weekChange)
        #expect(week.isSuperset(of: ["week.avgSleep", "week.avgSleepDelta", "week.avgRecovery", "week.recoveryTrend", "sleep.balance"]))
        #expect(!week.contains("hrv.today") && !week.contains("sleep.quality"))

        let bedtime = ids(.bedtimeAdvice)
        #expect(bedtime.isSuperset(of: ["bedtime.suggested", "bedtime.usual", "wake.typical", "sleep.need"]))
        #expect(!bedtime.contains("recovery.score") && !bedtime.contains("hrv.today"))

        let consistency = ids(.consistencyHelp)
        #expect(consistency.isSuperset(of: ["consistency.bedtimeVarMin", "consistency.toleranceMin", "bedtime.usual"]))
        #expect(!consistency.contains("recovery.score"))

        let today = ids(.todayFocus)
        #expect(today.isSuperset(of: ["recovery.score", "bedtime.suggested", "sleep.balance"]))
        #expect(!today.contains("deep.share"))

        let patterns = ids(.patterns)
        #expect(patterns.allSatisfy { $0.hasPrefix("insight.") || $0.hasPrefix("week.") || $0.hasPrefix("history.") })
        #expect(patterns.contains { $0.hasPrefix("insight.") })
    }

    @Test func medicalCrisisAndUnknownGetNothing() async {
        for intent in [CoachIntent.medicalOutOfScope, .crisis, .unknown] {
            let context = await CoachFixture.context(intent)
            #expect(context.facts.isEmpty && context.insights.isEmpty, Comment(rawValue: intent.rawValue))
        }
    }

    @Test func theInsightsAreTheTopThreeAndTheirFactsAreInTheContext() async {
        let context = await CoachFixture.context(.patterns)
        #expect(!context.insights.isEmpty && context.insights.count <= 3)
        for brief in context.insights {
            #expect(!brief.factIDs.isEmpty)
            for id in brief.factIDs { #expect(context.has(id), Comment(rawValue: id)) }
        }
        let confidences = context.insights.map(\.confidence)
        #expect(confidences == confidences.sorted(by: >))
    }

    @Test func theEarlyBirdPatternCarriesItsNumbers() async throws {
        let context = await CoachFixture.context(.patterns, scenario: .earlyBird)
        let pattern = try #require(context.insights.first { $0.type == .earlierBedtimePattern })
        #expect(pattern.confidence == .high)
        #expect(context.has("insight.earlierBedtimePattern.earlyMean") && context.has("insight.earlierBedtimePattern.lateMean"))
    }

    // MARK: - The numbers are the engines' numbers

    @Test func todaysRecoveryIsHomesAndRecoveryAndSleepAreTheSleepTabs() async throws {
        let snapshots = await CoachFixture.snapshots(.full)
        let context = builder().build(intent: .recoveryChange, direction: nil, snapshots: snapshots, profile: CoachFixture.profile)
        let result = try #require(snapshots.recovery?.result)
        #expect(context.fact("recovery.score")?.value == Double(result.score))
        #expect(context.fact("recovery.score")?.display == "\(result.score)")
        #expect(context.fact("recovery.deltaVsUsual")?.value == result.comparison.delta.map(Double.init))
        let hrv = try #require(result.factor(.hrv))
        #expect(context.fact("hrv.today")?.value == hrv.value)
        #expect(context.fact("hrv.baseline")?.value == hrv.baseline)

        let last = try #require(snapshots.home?.lastNight)
        let record = try #require(snapshots.sleep?.record(last.night))
        #expect(context.fact("sleep.duration")?.value == record.metrics.asleepMinutes)
        #expect(context.fact("sleep.duration")?.display == HomeFormat.compactDuration(Int(record.metrics.asleepMinutes.rounded())))
        #expect(context.fact("sleep.quality")?.value == Double(record.quality.score))
        #expect(context.fact("bedtime.last")?.value == record.metrics.bedtimeMinutes)
    }

    @Test func aDifferenceKeepsItsSignInTheValueAndShowsItsSizeOnly() async throws {
        let context = await CoachFixture.context(.recoveryChange)
        let sleepDelta = try #require(context.fact("sleep.deltaVsBaseline"))
        #expect(sleepDelta.value < 0)
        #expect(!sleepDelta.display.contains("-") && !sleepDelta.display.contains("\u{2212}"))
        let recovery = try #require(context.fact("recovery.deltaVsUsual"))
        #expect(!recovery.display.hasPrefix("-") && !recovery.display.hasPrefix("+"))
    }

    // MARK: - Confidence

    @Test func theCeilingFollowsTheData() async {
        #expect(await CoachFixture.context(.recoveryChange, scenario: .full).confidenceCeiling == .high)
        #expect(await CoachFixture.context(.recoveryChange, scenario: .sleepOnly).confidenceCeiling < .high)
        #expect(await CoachFixture.context(.recoveryChange, scenario: .learning).confidenceCeiling == .low)
        #expect(await CoachFixture.context(.recoveryChange, scenario: .empty).confidenceCeiling == .low)
        #expect(CoachContextBuilder.ceiling(state: .ready, result: nil, nights: 5) == .low)
        #expect(CoachContextBuilder.ceiling(state: .ready, result: nil, nights: 7) == .moderate)
        #expect(CoachContextBuilder.ceiling(state: .ready, result: nil, nights: 14) == .high)
        #expect(CoachContextBuilder.ceiling(state: .stale, result: nil, nights: 90) == .low)
        #expect(CoachContextBuilder.ceiling(state: .noSleepLastNight, result: nil, nights: 90) == .low)
    }

    // MARK: - Locale

    @Test func numbersAndTimesFollowTheLocale() async {
        let snapshots = await CoachFixture.snapshots(.full)
        func fact(_ id: String, _ locale: String) -> String? {
            builder(Locale(identifier: locale)).build(intent: .bedtimeAdvice, direction: nil, snapshots: snapshots, profile: CoachFixture.profile).fact(id)?.display
        }
        #expect(fact("bedtime.suggested", "en_US")?.plain == "11:00 PM")
        #expect(fact("bedtime.suggested", "de_DE") == "23:00")
        #expect(fact("wake.typical", "en_US")?.plain == "7:00 AM")
        #expect(fact("wake.typical", "de_DE") == "7:00")
    }

    @Test func aFactFormatsEachUnit() {
        let f = CoachFactFormatter(format: CoachFixture.format)
        #expect(f.fact("a", "A", 72.4, .points, source: "E").display == "72")
        #expect(f.fact("a", "A", 402, .duration, source: "E").display == "6h 42m")
        #expect(f.fact("a", "A", 402, .duration, source: "E").spoken == "6 hours 42 minutes")
        #expect(f.fact("a", "A", -70, .duration, source: "E", magnitude: true).display == "1h 10m")
        #expect(f.fact("a", "A", 36, .minutes, source: "E").display == "36 min")
        #expect(f.fact("a", "A", 660, .clock, source: "E").display.plain == "11:00 PM")
        #expect(f.fact("a", "A", 480, .clock, source: "E").display.plain == "8:00 PM")
        #expect(f.fact("a", "A", 48, .milliseconds, source: "E").display == "48 ms")
        #expect(f.fact("a", "A", 48, .milliseconds, source: "E").spoken == "48 milliseconds")
        #expect(f.fact("a", "A", 52, .beatsPerMinute, source: "E").display == "52 bpm")
        #expect(f.fact("a", "A", 31.4, .percent, source: "E").display == "31%")
        #expect(f.fact("a", "A", 1234, .count, source: "E").display == "1,234")
        let german = CoachFactFormatter(format: HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "de_DE")))
        #expect(german.fact("a", "A", 1234, .count, source: "E").display == "1.234")
        let arabic = CoachFactFormatter(format: HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "ar_EG")))
        #expect(arabic.fact("a", "A", 72, .points, source: "E").display == "\u{0667}\u{0662}")
    }

    @Test func minutesAfterNoonAndMinutesSinceMidnightAgree() {
        #expect(CoachFactFormatter.afterNoon(sinceMidnight: 23 * 60) == 660)
        #expect(CoachFactFormatter.afterNoon(sinceMidnight: 7 * 60) == 19 * 60)
        #expect(CoachFactFormatter.afterNoon(sinceMidnight: 0) == 720)
        #expect(CoachFactFormatter.afterNoon(sinceMidnight: 12 * 60) == 0)
    }
}

extension CoachContextBuilder {
    /// The seven intents that read data.
    static var prefixesIntents: [CoachIntent] { CoachQuestionRouter.intentOrder }
}
