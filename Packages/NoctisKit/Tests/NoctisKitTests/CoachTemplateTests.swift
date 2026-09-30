import Foundation
import HealthProviding
import Testing
@testable import CoachKit
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore

/// The template provider: the same facts as sentences the app wrote in advance.
struct CoachTemplateTests {
    private let template = TemplateCoachProvider(locale: CoachFixture.locale)
    private static let questions: [(CoachIntent, CoachDirection?)] = CoachQuestionRouter.intentOrder.flatMap { intent in
        intent.hasDirection ? CoachDirection.allCases.map { (intent, Optional($0)) } + [(intent, nil)] : [(intent, nil)]
    }

    private func answer(_ intent: CoachIntent, _ direction: CoachDirection?, _ scenario: MockScenario) async -> (CoachAnswer, CoachAnswerDraft, CoachContext)? {
        let context = await CoachFixture.context(intent, direction, scenario: scenario)
        let draft = template.compose(intent: intent, context: context)
        guard let answer = CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: CoachFixture.locale) else { return nil }
        return (answer, draft, context)
    }

    // MARK: - Every answer is valid

    @Test func everyIntentAndDirectionInEveryScenarioPassesTheValidator() async throws {
        for scenario in CoachFixture.scenarios {
            let snapshots = await CoachFixture.snapshots(scenario)
            for (intent, direction) in Self.questions {
                let context = CoachContextBuilder(format: CoachFixture.format).build(intent: intent, direction: direction, snapshots: snapshots, profile: CoachFixture.profile)
                let draft = template.compose(intent: intent, context: context)
                let name = "\(scenario.rawValue)/\(intent.rawValue)/\(direction?.rawValue ?? "-")"
                #expect(CoachSafetyValidator.failures(draft, context: context).isEmpty, Comment(rawValue: "\(name): \(CoachSafetyValidator.failures(draft, context: context))"))
                #expect(CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: CoachFixture.locale) != nil, Comment(rawValue: name))
            }
        }
    }

    @Test func everyGeneratedStringPassesTheBannedLanguageLint() async {
        for scenario in CoachFixture.scenarios {
            for (intent, direction) in Self.questions {
                guard let (answer, draft, _) = await answer(intent, direction, scenario) else {
                    Issue.record("no answer for \(scenario.rawValue)/\(intent.rawValue)")
                    continue
                }
                let name = "\(scenario.rawValue)/\(intent.rawValue)"
                // The one line the spec makes the app write ("not proof of a cause") is exempt, as it is in Insights.
                for text in answer.allText where text != answer.patternNote {
                    #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: "\(name): \(text)"))
                }
                // The draft as the model would write it: no digit, percent sign or number word outside a token.
                for text in [draft.summary, draft.whatChanged, draft.whatToNotice] + [draft.tonightSuggestion, draft.pattern, draft.caution].compactMap({ $0 }) {
                    let written = CoachTokens.stripped(text)
                    #expect(!written.hasDigit && !written.contains("%"), Comment(rawValue: "\(name): \(text)"))
                    let words = written.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
                    #expect(!words.contains(where: CoachSafetyValidator.numberWords.contains), Comment(rawValue: "\(name): \(text)"))
                }
            }
        }
    }

    @Test func theWholeCatalogsTemplateCopyPassesTheLintToo() {
        let raw = allCatalogTemplateStrings()
        #expect(raw.count > 100)
        // Scripts and suggested questions are the app's own words (the spec's medical script says "diagnose"; a question says "should"),
        // the pattern note is the required "not proof of a cause" line, and the confidence line holds {level} and {nights}.
        let exempt = ["coach.script.", "coach.suggest.", "coach.pattern.note", "coach.confidence.line."]
        for (key, text) in raw where !exempt.contains(where: key.hasPrefix) {
            let written = CoachTokens.stripped(text)
            #expect(BannedLanguage.hits(in: written, of: BannedLanguage.coach).isEmpty, Comment(rawValue: "\(key): \(text)"))
            #expect(!CoachTokens.hasMalformedBraces(text), Comment(rawValue: key))
            if key.hasPrefix("coach.tpl.") || key.hasPrefix("coach.caution.") {
                #expect(!written.hasDigit && !written.contains("%"), Comment(rawValue: "\(key): \(text)"))
                let words = written.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
                #expect(!words.contains(where: CoachSafetyValidator.numberWords.contains), Comment(rawValue: "\(key): \(text)"))
            }
        }
    }

    @Test func everyTokenInTheCatalogNamesAFactTheBuilderCanProduce() {
        for (key, text) in allCatalogTemplateStrings() {
            for id in CoachTokens.ids(in: text) {
                #expect(CoachFactCatalog.allows(id) || id.hasPrefix("insight."), Comment(rawValue: "\(key): \(id)"))
            }
        }
    }

    @Test func noKeyIsMissingFromTheCatalog() async {
        // A missing key would come back as the key itself ("coach.tpl...").
        for scenario in CoachFixture.scenarios {
            for (intent, direction) in Self.questions {
                guard let (answer, _, _) = await answer(intent, direction, scenario) else { continue }
                for text in answer.allText { #expect(!text.contains("coach."), Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue): \(text)")) }
            }
        }
    }

    // MARK: - Determinism and honesty

    @Test func theSameFactsGiveTheSameAnswer() async {
        for scenario in [MockScenario.full, .learning, .recoveryDip] {
            for (intent, direction) in Self.questions {
                let context = await CoachFixture.context(intent, direction, scenario: scenario)
                #expect(template.compose(intent: intent, context: context) == template.compose(intent: intent, context: context))
            }
        }
    }

    @Test func aTemplateNeverNamesAFactItDoesNotHave() async {
        for scenario in CoachFixture.scenarios {
            for (intent, direction) in Self.questions {
                let context = await CoachFixture.context(intent, direction, scenario: scenario)
                let draft = template.compose(intent: intent, context: context)
                let texts = [draft.summary, draft.whatChanged, draft.whatToNotice] + [draft.tonightSuggestion, draft.pattern, draft.caution].compactMap { $0 } + draft.contributors.map(\.label)
                for id in texts.flatMap(CoachTokens.ids(in:)) + draft.contributors.map(\.factID) {
                    #expect(context.has(id), Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue) names \(id)"))
                }
            }
        }
    }

    @Test func aTemplateNeverClaimsMoreConfidenceThanTheDataHas() async {
        for scenario in CoachFixture.scenarios {
            for (intent, direction) in Self.questions {
                let context = await CoachFixture.context(intent, direction, scenario: scenario)
                let draft = template.compose(intent: intent, context: context)
                #expect(draft.confidence.map { $0 <= context.confidenceCeiling } == true, Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue)"))
                if draft.confidence != .high { #expect(draft.caution?.isEmpty == false, Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue)")) }
            }
        }
    }

    @Test func withNoDataOrTooFewNightsTheAnswerIsAnHonestNeedMoreNights() async throws {
        for (intent, direction) in Self.questions {
            let empty = try #require(await answer(intent, direction, .empty)).0
            #expect(empty.summary == "I don't have any sleep data to look at yet.")
            #expect(empty.contributors.isEmpty && empty.destinations.isEmpty && empty.tonightSuggestion == nil && empty.pattern == nil)
            #expect(empty.confidence == .low)

            let learning = try #require(await answer(intent, direction, .learning)).0
            #expect(learning.summary == "I need more nights before I can say much. So far I can see 3 of them.")
            #expect(learning.contributors.isEmpty && learning.tonightSuggestion == nil && learning.pattern == nil)
            #expect(learning.confidence == .low)
            #expect(!empty.allText.joined().hasDigit, "no number it doesn't have")
        }
    }

    @Test func aMissingNightIsSaidPlainly() async throws {
        let gap = try #require(await answer(.recoveryChange, .lower, .gap)).0
        #expect(gap.summary == "No sleep was recorded for last night, so I can't compare today with your usual.")
        let stale = try #require(await answer(.sleepChange, nil, .stale)).0
        #expect(stale.summary == "Apple Health hasn't updated in over a day, so I can't say how last night went.")
    }

    @Test func aQuestionThatLeansTheOtherWayThanTheDataSaysSo() async throws {
        // full: recovery is below usual; someone asking "why is it higher" is told the data points the other way.
        let (asked, _, context) = try #require(await answer(.recoveryChange, .higher, .full))
        let delta = try #require(context.fact("recovery.deltaVsUsual")?.value)
        #expect(delta <= -3)
        #expect(asked.whatToNotice.hasPrefix("Your data points a different way from the question"))
        let (agrees, _, _) = try #require(await answer(.recoveryChange, .lower, .full))
        #expect(!agrees.whatToNotice.contains("different way"))
        let (neutral, _, _) = try #require(await answer(.recoveryChange, nil, .full))
        #expect(!neutral.whatToNotice.contains("different way"))
    }

    @Test func theSummaryFollowsTheDataNotTheQuestion() async throws {
        let lower = try #require(await answer(.recoveryChange, .lower, .full)).0
        let higher = try #require(await answer(.recoveryChange, .higher, .full)).0
        #expect(lower.summary == higher.summary)
        #expect(lower.summary.contains("below your usual"))
    }

    // MARK: - Shape

    @Test func aRecoveryAnswerListsWhatTheScoreRestsOn() async throws {
        let (answer, _, context) = try #require(await answer(.recoveryChange, .lower, .full))
        #expect(!answer.contributors.isEmpty && answer.contributors.count <= 4)
        for contributor in answer.contributors { #expect(context.fact(contributor.factID)?.display == contributor.value) }
        #expect(answer.destinations.map(\.name) == ["recovery"])
        #expect(answer.sourceKind == .fromYourData)
        #expect(answer.footer == "Coach shares patterns from your data. It isn't medical advice.")
    }

    @Test func aPatternGetsTheAppsNoteAndOnlyAHedgedSentence() async throws {
        let (answer, draft, _) = try #require(await answer(.patterns, nil, .earlyBird))
        let pattern = try #require(answer.pattern)
        #expect(CoachSafetyValidator.hedges.contains { pattern.lowercased().contains($0) })
        #expect(answer.patternNote == "This is a pattern in your data, not proof of a cause.")
        #expect(draft.pattern?.contains("This is a pattern") == false, "the model doesn't write the note")
        #expect(answer.destinations.map(\.name).first == "insights")
        let others = try #require(await self.answer(.recoveryChange, nil, .full)).0
        #expect(others.pattern == nil && others.patternNote == nil)
    }

    @Test func theConfidenceLineIsTheAppsAndSaysHowManyNights() async throws {
        let full = try #require(await answer(.recoveryChange, nil, .full)).0
        #expect(full.confidenceLine == "High confidence · based on 111 nights")
        let learning = try #require(await answer(.recoveryChange, nil, .learning)).0
        #expect(learning.confidenceLine == "Low confidence · based on 3 nights")
        #expect(CoachAnswerAssembler.confidenceLine(.moderate, nights: 1, locale: CoachFixture.locale) == "Moderate confidence · based on 1 night")
        #expect(CoachAnswerAssembler.confidenceLine(.low, nights: 0, locale: CoachFixture.locale) == "Low confidence")
        #expect(CoachAnswerAssembler.confidenceLine(.high, nights: 1234, locale: CoachFixture.locale) == "High confidence · based on 1,234 nights")
        #expect(CoachAnswerAssembler.confidenceLine(.high, nights: 1234, locale: Locale(identifier: "de_DE")) == "High confidence · based on 1.234 nights")
    }

    @Test func sleepOnlyDataSaysHeartDataIsMissing() async throws {
        let (answer, _, _) = try #require(await answer(.recoveryChange, nil, .sleepOnly))
        #expect(answer.confidence != .high)
        #expect(answer.caution == "Heart data isn't included, so this leans on sleep alone.")
    }

    @Test func aNightsClausesAreOnlyThoseTheDataSupports() async throws {
        let (sleepOnly, _, _) = try #require(await answer(.recoveryChange, nil, .sleepOnly))
        #expect(!sleepOnly.whatChanged.contains("HRV") && !sleepOnly.whatChanged.contains("resting heart rate"))
        #expect(!sleepOnly.contributors.contains { $0.label == "HRV" })
        let (full, _, _) = try #require(await answer(.recoveryChange, nil, .full))
        #expect(full.whatChanged.contains("HRV") && full.whatChanged.contains("resting heart rate"))
    }

    // MARK: - Helpers

    /// Every key of the catalog that isn't a router pattern, with its English text.
    private func allCatalogTemplateStrings() -> [(String, String)] {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/CoachKit/Resources/Coach.xcstrings")
        guard let data = try? Data(contentsOf: catalog),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return [] }
        return strings.keys.sorted().filter { !$0.hasPrefix("coach.router.") }.map { ($0, CoachCopy.string($0)) }
    }
}

/// The template's exact words, per intent and scenario. If a golden changes, a sentence changed: read the new one before regenerating.
struct CoachTemplateGoldenTests {
    private let template = TemplateCoachProvider(locale: CoachFixture.locale)
    private static let scenarios: [MockScenario] = [.full, .sleepOnly, .learning, .gap, .recoveryDip, .earlyBird, .empty]

    private func rendered(_ intent: CoachIntent, _ direction: CoachDirection?, _ scenario: MockScenario) async throws -> String {
        let context = await CoachFixture.context(intent, direction, scenario: scenario)
        let draft = template.compose(intent: intent, context: context)
        let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: CoachFixture.locale))
        return CoachGolden.render(answer)
    }

    @Test func everyIntentInEveryScenarioIsWordForWordWhatWasReviewed() async throws {
        for scenario in Self.scenarios {
            for intent in CoachQuestionRouter.intentOrder {
                let key = "\(scenario.rawValue)/\(intent.rawValue)"
                let expected = try #require(CoachGoldens.template[key], Comment(rawValue: "no golden for \(key)"))
                #expect(try await rendered(intent, nil, scenario) == expected, Comment(rawValue: key))
            }
        }
    }

    @Test func aRecoveryQuestionInEachDirectionIsWordForWordWhatWasReviewed() async throws {
        for direction in CoachDirection.allCases {
            let key = "full/recoveryChange/\(direction.rawValue)"
            let expected = try #require(CoachGoldens.template[key], Comment(rawValue: "no golden for \(key)"))
            #expect(try await rendered(.recoveryChange, direction, .full) == expected, Comment(rawValue: key))
        }
    }

    @Test func thereIsAGoldenForEveryOneAndNoStrayOnes() {
        let expected = Set(Self.scenarios.flatMap { scenario in CoachQuestionRouter.intentOrder.map { "\(scenario.rawValue)/\($0.rawValue)" } }
            + CoachDirection.allCases.map { "full/recoveryChange/\($0.rawValue)" })
        #expect(Set(CoachGoldens.template.keys) == expected)
    }
}
