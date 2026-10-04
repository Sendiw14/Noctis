import Foundation
import Testing
@testable import CoachKit
@testable import InsightsKit
@testable import NoctisCore

/// The safety validator, rule by rule.
struct CoachValidatorTests {
    private let context = CoachFixture.handmade(facts: [
        CoachFixture.fact("recovery.score", 72, .points),
        CoachFixture.fact("recovery.deltaVsUsual", -8, .points, magnitude: true),
        CoachFixture.fact("sleep.duration", 402, .duration),
        CoachFixture.fact("hrv.today", 48, .milliseconds),
        CoachFixture.fact("bedtime.usual", 660, .clock),
    ])

    private func good() -> CoachAnswerDraft {
        CoachAnswerDraft(
            summary: "Your recovery is {{recovery.score}} today, {{recovery.deltaVsUsual}} points below your usual.",
            contributors: [CoachDraftContributor(label: "HRV", factID: "hrv.today")],
            whatChanged: "Compared with your recent baseline, sleep was {{sleep.duration}}.",
            whatToNotice: "Notice how your energy holds up through the afternoon.",
            tonightSuggestion: "Keep tonight's bedtime near {{bedtime.usual}}.",
            pattern: "Your data suggests earlier bedtimes have coincided with higher recovery.",
            confidence: .high,
            caution: nil,
            destinations: ["recovery", "sleep:week"]
        )
    }

    private func failures(_ draft: CoachAnswerDraft) -> [CoachValidationFailure] {
        CoachSafetyValidator.failures(draft, context: context)
    }

    private func code(_ draft: CoachAnswerDraft) -> String? {
        CoachSafetyValidator.validate(draft, context: context)?.code
    }

    // MARK: - A good draft

    @Test func aGoodDraftPasses() {
        #expect(failures(good()).isEmpty)
        #expect(CoachSafetyValidator.validate(good(), context: context) == nil)
    }

    @Test func aDraftWithNoOptionalFieldsPasses() {
        var draft = good()
        draft.tonightSuggestion = nil
        draft.pattern = nil
        draft.contributors = []
        draft.destinations = []
        #expect(failures(draft).isEmpty)
    }

    // MARK: - Structure

    @Test func everyRequiredFieldMustBeThere() {
        var draft = good()
        draft.summary = ""
        #expect(failures(draft).contains(.missingField("summary")))
        draft = good()
        draft.whatChanged = "   \n"
        #expect(failures(draft).contains(.missingField("whatChanged")))
        draft = good()
        draft.whatToNotice = ""
        #expect(failures(draft).contains(.missingField("whatToNotice")))
        draft = good()
        draft.confidence = nil
        #expect(failures(draft).contains(.missingField("confidence")))
    }

    @Test func anOptionalFieldThatIsPresentMustNotBeBlank() {
        var draft = good()
        draft.tonightSuggestion = "  "
        #expect(failures(draft).contains(.missingField("tonightSuggestion")))
        draft = good()
        draft.pattern = ""
        #expect(failures(draft).contains(.missingField("pattern")))
    }

    @Test func aContributorNeedsALabel() {
        var draft = good()
        draft.contributors = [CoachDraftContributor(label: " ", factID: "hrv.today")]
        #expect(failures(draft).contains(.missingField("contributors[0]")))
    }

    @Test func theSummaryLimitIs220AndTheOthersAre280() {
        var draft = good()
        draft.summary = String(repeating: "a", count: 220)
        #expect(failures(draft).isEmpty)
        draft.summary = String(repeating: "a", count: 221)
        #expect(failures(draft) == [.tooLong(field: "summary")])

        for field in ["whatChanged", "whatToNotice", "tonightSuggestion", "pattern"] {
            var edge = good()
            let text = String(repeating: "a", count: 280)
            switch field {
            case "whatChanged": edge.whatChanged = text
            case "whatToNotice": edge.whatToNotice = text
            case "tonightSuggestion": edge.tonightSuggestion = text
            default: edge.pattern = "suggests " + String(repeating: "a", count: 271)
            }
            #expect(failures(edge).isEmpty, Comment(rawValue: field))
            switch field {
            case "whatChanged": edge.whatChanged += "a"
            case "whatToNotice": edge.whatToNotice += "a"
            case "tonightSuggestion": edge.tonightSuggestion? += "a"
            default: edge.pattern? += "a"
            }
            #expect(failures(edge) == [.tooLong(field: field)], Comment(rawValue: field))
        }
        var caution = good()
        caution.confidence = .moderate
        caution.caution = String(repeating: "a", count: 281)
        #expect(failures(caution) == [.tooLong(field: "caution")])
    }

    @Test func aTokenCountsAsTheLengthOfItsValue() {
        var draft = good()
        // "72 " is three characters a person sees, though the token is nineteen.
        draft.summary = String(repeating: "{{recovery.score}} ", count: 60)
        #expect(draft.summary.count > 1000)
        #expect(failures(draft).isEmpty)
        draft.summary = String(repeating: "{{recovery.score}} ", count: 80)
        #expect(failures(draft) == [.tooLong(field: "summary")])
    }

    @Test func noMoreThanFourContributors() {
        var draft = good()
        draft.contributors = (0..<4).map { _ in CoachDraftContributor(label: "HRV", factID: "hrv.today") }
        #expect(failures(draft).isEmpty)
        draft.contributors.append(CoachDraftContributor(label: "HRV", factID: "hrv.today"))
        #expect(failures(draft) == [.tooManyContributors])
    }

    @Test func aContributorMustPointAtAFactInTheContext() {
        var draft = good()
        draft.contributors = [CoachDraftContributor(label: "Resting heart rate", factID: "rhr.today")]
        #expect(failures(draft) == [.unknownToken("rhr.today")])
    }

    @Test(arguments: [CoachConfidence.moderate, .low])
    func cautionIsRequiredWhenConfidenceIsNotHigh(_ confidence: CoachConfidence) {
        var draft = good()
        draft.confidence = confidence
        #expect(failures(draft) == [.cautionRequired])
        draft.caution = "  "
        #expect(failures(draft).contains(.cautionRequired))
        draft.caution = "This rests on a short history, so treat it as a rough guide."
        #expect(failures(draft).isEmpty)
    }

    @Test func highConfidenceNeedsNoCaution() {
        var draft = good()
        draft.confidence = .high
        draft.caution = nil
        #expect(failures(draft).isEmpty)
    }

    // MARK: - Numbers

    @Test(arguments: ["You slept 7 hours.", "Recovery was 72.", "Up 3 points.", "About 7.5 hours.", "Room 101", "\u{0663} points", "\u{00BD} an hour", "about ٧ hours"])
    func aDigitOutsideATokenIsRejected(_ text: String) {
        var draft = good()
        draft.summary = text
        #expect(failures(draft).contains(.digitInText(field: "summary")), Comment(rawValue: text))
    }

    @Test(arguments: ["Recovery is up by %.", "Up \u{FF05}.", "a percent sign %", "10\u{2030}"])
    func aPercentSignIsRejected(_ text: String) {
        var draft = good()
        draft.whatChanged = text
        #expect(failures(draft).map(\.code).contains("percentInText"), Comment(rawValue: text))
    }

    @Test(arguments: Array(CoachSafetyValidator.numberWords))
    func everyNumberWordIsRejected(_ word: String) {
        var draft = good()
        draft.whatToNotice = "Notice how you feel after \(word) days."
        #expect(failures(draft).contains(.numberWordInText(field: "whatToNotice")), Comment(rawValue: word))
        draft.whatToNotice = "Notice how you feel after \(word.uppercased()) days."
        #expect(failures(draft).contains(.numberWordInText(field: "whatToNotice")), Comment(rawValue: word))
    }

    @Test func aNumberWordInsideAnotherWordIsNotANumberWord() {
        var draft = good()
        draft.whatToNotice = "Notice someone, anyone, often listening: onesie, tenant, weight, stone, fourth."
        #expect(!failures(draft).contains(.numberWordInText(field: "whatToNotice")))
    }

    @Test func aTokenIsNotADigit() {
        var draft = good()
        draft.summary = "{{recovery.score}}{{sleep.duration}} {{hrv.today}}"
        #expect(failures(draft).isEmpty)
    }

    @Test func digitsInAContributorLabelOrACautionOrAPatternAreRejectedToo() {
        var draft = good()
        draft.contributors = [CoachDraftContributor(label: "HRV 48", factID: "hrv.today")]
        #expect(failures(draft).contains(.digitInText(field: "contributors[0]")))
        draft = good()
        draft.confidence = .low
        draft.caution = "Only 3 nights."
        #expect(failures(draft).contains(.digitInText(field: "caution")))
        draft = good()
        draft.pattern = "Your data suggests a 20 minute shift."
        #expect(failures(draft).contains(.digitInText(field: "pattern")))
        draft = good()
        draft.tonightSuggestion = "Go to bed at 11."
        #expect(failures(draft).contains(.digitInText(field: "tonightSuggestion")))
    }

    // MARK: - Tokens

    @Test func aTokenMustNameAFactInTheContext() {
        var draft = good()
        draft.summary = "Your resting rate was {{rhr.today}}."
        #expect(failures(draft) == [.unknownToken("rhr.today")])
        draft.summary = "Your recovery is {{made.up}}."
        #expect(failures(draft) == [.unknownToken("made.up")])
    }

    @Test(arguments: ["{{recovery.score", "recovery.score}}", "{ {recovery.score} }", "{{ }}", "{{recovery score}}", "{{{recovery.score}}", "{{}}"])
    func aBrokenTokenIsRejected(_ text: String) {
        var draft = good()
        draft.summary = "Your recovery is \(text) today."
        let found = failures(draft)
        #expect(found.map(\.code).contains("malformedToken") || found.map(\.code).contains("unknownToken"), Comment(rawValue: text))
    }

    @Test func aTokenMayHaveSpacesInsideItsBraces() {
        var draft = good()
        draft.summary = "Your recovery is {{ recovery.score }} today."
        #expect(failures(draft).isEmpty)
    }

    // MARK: - Banned language

    @Test(arguments: BannedLanguage.coach)
    func everyBannedTermIsRejected(_ term: String) {
        var draft = good()
        draft.whatToNotice = "Your data shows \(term) today."
        // "because" holds "cause" and "unhealthy" holds "healthy": the first term of the list that matches is the one reported.
        #expect(failures(draft).map(\.code).contains("bannedLanguage"), Comment(rawValue: term))
        #expect(BannedLanguage.hits(in: draft.whatToNotice, of: BannedLanguage.coach).contains(term))
        draft.whatToNotice = "Your data shows \(term.uppercased()) today."
        #expect(failures(draft).map(\.code).contains("bannedLanguage"), Comment(rawValue: term))
    }

    @Test(arguments: [
        "This looks like insomnia.", "That could be sleep apnea.", "You are showing signs of depression.", "Your recovery is lower because you slept badly.",
        "Late coffee caused this.", "This is a poor night.", "You should go to bed earlier.", "You must sleep more.", "You have a sleep disorder.",
        "You are healthy.", "You are completely recovered.", "Definitely go to bed early.", "This is a bad sign.", "You are in sleep debt.",
        "There is danger here.", "A warning sign.", "Don't worry about it.", "Anxiety may be why.", "Ask about medication.", "A treatment might help.",
        "I guarantee it.", "This is unhealthy.",
    ])
    func diagnosisAndCausalAndAdviceWordingIsRejected(_ text: String) {
        var draft = good()
        draft.summary = text
        #expect(failures(draft).map(\.code).contains("bannedLanguage"), Comment(rawValue: text))
    }

    @Test func aFactIdIsNotTheModelsWord() {
        // The words are checked with the tokens taken out, so a fact id that happens to hold a banned stem isn't the model's.
        let odd = CoachFixture.handmade(facts: [CoachFixture.fact("sleep.disease", 1, .count)])
        let draft = CoachAnswerDraft(
            summary: "Look at {{sleep.disease}}.", whatChanged: "Nothing else.", whatToNotice: "Notice how you feel.", confidence: .high
        )
        #expect(CoachSafetyValidator.failures(draft, context: odd).isEmpty)
    }

    @Test func theBannedListIsTheSharedOneAndCoversTheSpec() {
        #expect(Set(BannedLanguage.insights).isSubset(of: Set(BannedLanguage.coach)))
        #expect(CoachSafetyValidator.bannedTerms == BannedLanguage.coach)
        let spec = [
            "diagnos", "disorder", "disease", "sick", "insomnia", "apnea", "depress", "anxiety", "treatment", "medication", "prescri", "cure", "you have",
            "healthy", "unhealthy", "completely recovered", "definitely", "guarantee", "cause", "caused", "because", "should", "must", "poor", "bad",
            "debt", "danger", "warning", "worry",
        ]
        for term in spec { #expect(BannedLanguage.coach.contains(term), Comment(rawValue: term)) }
        #expect(BannedLanguage.hits(in: "Because of the Warning", of: BannedLanguage.coach) == ["cause", "because", "warning"])
    }

    // MARK: - Patterns

    @Test(arguments: ["Your data suggests earlier bedtimes go with better nights.", "Earlier bedtimes have coincided with higher recovery.", "Late nights have coincided with lower recovery.", "Compared with your recent baseline, early nights scored higher.", "SUGGESTS a link"])
    func aPatternThatHedgesPasses(_ text: String) {
        var draft = good()
        draft.pattern = text
        #expect(failures(draft).isEmpty, Comment(rawValue: text))
    }

    @Test(arguments: ["Earlier bedtimes go with better nights.", "Late nights lead to lower recovery.", "Your recovery follows your bedtime."])
    func aPatternWithoutAHedgeIsRejected(_ text: String) {
        var draft = good()
        draft.pattern = text
        #expect(failures(draft) == [.patternWithoutHedge], Comment(rawValue: text))
    }

    @Test func aHedgeOnlyMattersForAPattern() {
        var draft = good()
        draft.pattern = nil
        draft.whatChanged = "Sleep was short."
        #expect(failures(draft).isEmpty)
    }

    // MARK: - Destinations

    @Test func coachNeverPointsAtSettings() {
        for name in ["settings", "settings:notifications", "settings:health-data"] {
            #expect(AppRoute.coachDestination(named: name) == nil, Comment(rawValue: name))
        }
        #expect(AppRoute.coachDestination(named: "profile") == .profile)
        #expect(AppRoute.coachDestination(named: "sleep:week") == .sleep(night: nil, range: .week))
    }

    @Test(arguments: ["settings", "settings:secrets", "insight", "insight:not an id", "http://evil.example", "noctis://recovery", "", "paywall", "export"])
    func aDestinationThatIsNotARouteIsRejected(_ name: String) {
        var draft = good()
        draft.destinations = [name]
        #expect(failures(draft).contains(.unknownDestination(name)), Comment(rawValue: name))
    }

    @Test(arguments: ["home", "sleep", "sleep:week", "sleep:month", "recovery", "recovery:30d", "insights", "insights:sleep", "coach", "profile", "insight:bedtimeShift-3fa9c2d1"])
    func everyRouteTheAppHasIsAllowed(_ name: String) {
        var draft = good()
        draft.destinations = [name]
        #expect(failures(draft).isEmpty, Comment(rawValue: name))
    }

    @Test func noMoreThanThreeDestinations() {
        var draft = good()
        draft.destinations = ["home", "sleep", "recovery", "insights"]
        #expect(failures(draft) == [.tooManyDestinations])
    }

    // MARK: - Reporting

    @Test func aDraftGetsEveryReasonAndTheFirstIsReported() {
        var draft = good()
        draft.summary = "You have insomnia, 7 hours."
        draft.confidence = nil
        let found = failures(draft)
        #expect(found.count >= 3)
        #expect(CoachSafetyValidator.validate(draft, context: context) == found.first)
        #expect(Set(found.map(\.code)).count == found.count || found.count > 3)
    }

    @Test func aReasonsCodeHoldsNoTextOfTheDraft() {
        let reasons: [CoachValidationFailure] = [
            .missingField("summary"), .tooLong(field: "summary"), .tooManyContributors, .tooManyDestinations, .cautionRequired, .digitInText(field: "summary"),
            .percentInText(field: "summary"), .numberWordInText(field: "summary"), .unknownToken("secret.fact"), .malformedToken(field: "summary"),
            .bannedLanguage(term: "insomnia", field: "summary"), .patternWithoutHedge, .unknownDestination("settings:secret"),
        ]
        #expect(Set(reasons.map(\.code)).count == reasons.count)
        for reason in reasons {
            #expect(reason.code.allSatisfy { $0.isLetter }, Comment(rawValue: reason.code))
            #expect(!reason.code.contains("secret") && !reason.code.contains("insomnia"))
        }
    }

    @Test func theValidatorIsPure() {
        let draft = good()
        #expect(failures(draft) == failures(draft))
        var bad = good()
        bad.summary = "You slept 7 hours because of coffee."
        #expect(failures(bad) == failures(bad))
    }
}
