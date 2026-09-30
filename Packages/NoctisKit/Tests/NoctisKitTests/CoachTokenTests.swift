import Foundation
import Testing
@testable import CoachKit
@testable import NoctisCore
@testable import HomeFeature

/// Tokens: how a draft points at a number, and how the app puts it in.
struct CoachTokenTests {
    private func facts(_ locale: String = "en_US") -> [String: CoachFact] {
        let f = CoachFactFormatter(format: HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: locale)))
        let all = [
            f.fact("recovery.score", "Recovery", 72, .points, source: "E"),
            f.fact("sleep.duration", "Sleep", 402, .duration, source: "E"),
            f.fact("sleep.deltaVsBaseline", "Delta", -70, .duration, source: "E", magnitude: true),
            f.fact("bedtime.usual", "Bedtime", 660, .clock, source: "E"),
            f.fact("hrv.today", "HRV", 48, .milliseconds, source: "E"),
            f.fact("rhr.today", "RHR", 52, .beatsPerMinute, source: "E"),
            f.fact("deep.share", "Deep", 21.4, .percent, source: "E"),
            f.fact("consistency.bedtimeVarMin", "Var", 36, .minutes, source: "E"),
            f.fact("history.nights", "Nights", 1234, .count, source: "E"),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    // MARK: - Finding them

    @Test func tokensAreFoundInOrder() {
        #expect(CoachTokens.ids(in: "a {{x.y}} b {{ z }} c {{x.y}}") == ["x.y", "z", "x.y"])
        #expect(CoachTokens.ids(in: "no tokens here").isEmpty)
        #expect(CoachTokens.ids(in: "{{a.b_c.d9}}") == ["a.b_c.d9"])
    }

    @Test func strippingLeavesTheModelsWordsApart() {
        #expect(CoachTokens.stripped("up {{a.b}}down") == "up  down")
        #expect(CoachTokens.stripped("plain") == "plain")
    }

    @Test func malformedBracesAreCaught() {
        for text in ["{{a.b", "a.b}}", "{a.b}", "{{a b}}", "{{}}", "{{{a.b}}", "{{a.b}}}"] { #expect(CoachTokens.hasMalformedBraces(text), Comment(rawValue: text)) }
        for text in ["{{a.b}}", "{{ a.b }}", "{{a.b}} and {{c.d}}", "none"] { #expect(!CoachTokens.hasMalformedBraces(text), Comment(rawValue: text)) }
    }

    // MARK: - Resolving them

    @Test func eachTokenBecomesItsFactsDisplay() {
        let resolved = CoachTokens.resolve(
            "Recovery {{recovery.score}}, sleep {{sleep.duration}} ({{sleep.deltaVsBaseline}} short), bedtime {{bedtime.usual}}, HRV {{hrv.today}}, resting {{rhr.today}}, deep {{deep.share}}, spread {{consistency.bedtimeVarMin}}, {{history.nights}} nights.",
            facts: facts()
        )
        #expect(resolved?.plain == "Recovery 72, sleep 6h 42m (1h 10m short), bedtime 11:00 PM, HRV 48 ms, resting 52 bpm, deep 21%, spread 36 min, 1,234 nights.")
    }

    @Test func locale() {
        #expect(CoachTokens.resolve("{{bedtime.usual}} {{history.nights}}", facts: facts("en_US"))?.plain == "11:00 PM 1,234")
        #expect(CoachTokens.resolve("{{bedtime.usual}} {{history.nights}}", facts: facts("de_DE"))?.plain == "23:00 1.234")
        #expect(CoachTokens.resolve("{{recovery.score}}", facts: facts("ar_EG")) == "\u{0667}\u{0662}")
        #expect(CoachTokens.resolve("{{history.nights}}", facts: facts("fr_FR"))?.hasPrefix("1") == true)
    }

    @Test func anUnknownTokenResolvesToNothingAtAll() {
        #expect(CoachTokens.resolve("Recovery {{recovery.score}} and {{made.up}}", facts: facts()) == nil)
        #expect(CoachTokens.resolve("{{}}", facts: facts()) == "{{}}")
    }

    @Test func textWithNoTokenIsUnchanged() {
        #expect(CoachTokens.resolve("Nothing to see.", facts: facts()) == "Nothing to see.")
        #expect(CoachTokens.resolve("", facts: facts()) == "")
    }

    @Test func aDraftWithAnUnknownTokenIsNeverAssembled() {
        let context = CoachFixture.handmade(facts: [CoachFixture.fact("recovery.score", 72, .points)])
        let bad = CoachAnswerDraft(summary: "It is {{nope}}.", whatChanged: "a", whatToNotice: "b", confidence: .high)
        #expect(CoachAnswerAssembler.assemble(bad, context: context, source: .appleIntelligence, locale: CoachFixture.locale) == nil)
        var contributor = CoachAnswerDraft(summary: "It is {{recovery.score}}.", whatChanged: "a", whatToNotice: "b", confidence: .high)
        contributor.contributors = [CoachDraftContributor(label: "X", factID: "nope")]
        #expect(CoachAnswerAssembler.assemble(contributor, context: context, source: .appleIntelligence, locale: CoachFixture.locale) == nil)
    }

    @Test func noDigitReachesAnAnswerThatDidntComeFromAFact() async throws {
        for scenario in CoachFixture.scenarios {
            for intent in CoachQuestionRouter.intentOrder {
                let context = await CoachFixture.context(intent, nil, scenario: scenario)
                let draft = TemplateCoachProvider(locale: CoachFixture.locale).compose(intent: intent, context: context)
                let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .fromYourData, locale: CoachFixture.locale))
                // Take out every value the answer was given (longest first), and no digit is left in what the model wrote.
                var text = [answer.summary, answer.whatChanged, answer.whatToNotice, answer.tonightSuggestion, answer.pattern, answer.caution].compactMap { $0 }.joined(separator: "\n")
                for fact in context.facts.sorted(by: { $0.display.count > $1.display.count }) { text = text.replacingOccurrences(of: fact.display, with: "") }
                #expect(!text.hasDigit, Comment(rawValue: "\(scenario.rawValue)/\(intent.rawValue): \(text)"))
                #expect(!text.contains("{{") && !text.contains("}}"))
            }
        }
    }

    @Test func contributorsShowTheFactsDisplayNotTheModelsValue() throws {
        let context = CoachFixture.handmade(facts: [CoachFixture.fact("hrv.today", 48, .milliseconds)])
        var draft = CoachAnswerDraft(summary: "s", whatChanged: "a", whatToNotice: "b", confidence: .high)
        draft.contributors = [CoachDraftContributor(label: "HRV", factID: "hrv.today")]
        let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .appleIntelligence, locale: CoachFixture.locale))
        #expect(answer.contributors == [CoachContributor(label: "HRV", value: "48 ms", factID: "hrv.today")])
    }

    // MARK: - Held to what the data allows

    @Test func theConfidenceIsNeverMoreThanTheCeiling() throws {
        let context = CoachFixture.handmade(state: .ready, nights: 9, ceiling: .moderate)
        let draft = CoachAnswerDraft(summary: "s", whatChanged: "a", whatToNotice: "b", confidence: .high)
        let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .appleIntelligence, locale: CoachFixture.locale))
        #expect(answer.confidence == .moderate)
        #expect(answer.caution != nil, "the app supplies the caution the model didn't need to")
        #expect(answer.confidenceLine == "Moderate confidence · based on 9 nights")
    }

    @Test func aModelThatHedgesMoreThanTheDataRequiresKeepsItsOwnConfidenceAndCaution() throws {
        let context = CoachFixture.handmade(ceiling: .high)
        let draft = CoachAnswerDraft(summary: "s", whatChanged: "a", whatToNotice: "b", confidence: .low, caution: "Only a rough guide.")
        let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .appleIntelligence, locale: CoachFixture.locale))
        #expect(answer.confidence == .low)
        #expect(answer.caution == "Only a rough guide.")
    }

    @Test func aPatternGetsTheAppsNoteAndOtherFieldsGetNone() throws {
        let context = CoachFixture.handmade()
        var draft = CoachAnswerDraft(summary: "s", whatChanged: "a", whatToNotice: "b", confidence: .high)
        #expect(try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .appleIntelligence, locale: CoachFixture.locale)).patternNote == nil)
        draft.pattern = "Your data suggests a link."
        let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .appleIntelligence, locale: CoachFixture.locale))
        #expect(answer.patternNote == "This is a pattern in your data, not proof of a cause.")
        #expect(answer.footer == "Coach shares patterns from your data. It isn't medical advice.")
    }

    @Test func destinationsBecomeRoutes() throws {
        let context = CoachFixture.handmade()
        let draft = CoachAnswerDraft(summary: "s", whatChanged: "a", whatToNotice: "b", confidence: .high, destinations: ["recovery", "sleep:week"])
        let answer = try #require(CoachAnswerAssembler.assemble(draft, context: context, source: .appleIntelligence, locale: CoachFixture.locale))
        #expect(answer.destinations.map(\.name) == ["recovery", "sleep"])
    }

    @Test func anAnswerRoundTripsThroughJSON() throws {
        let answer = CoachScriptedAnswers.answer(.crisis)
        let decoded = try JSONDecoder().decode(CoachAnswer.self, from: JSONEncoder().encode(answer))
        #expect(decoded == answer)
        let route = CoachAnswer(sourceKind: .fromYourData, intent: .weekChange, summary: "s", confidence: .high, destinations: [.sleep(night: nil, range: .week), .recovery(range: .month, factor: .hrv)], footer: "f")
        #expect(try JSONDecoder().decode(CoachAnswer.self, from: JSONEncoder().encode(route)) == route)
    }
}
