import Foundation
import HealthProviding
import Testing
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import SleepKit

/// Every word an insight can say, from every kind of evidence and every
/// mock scenario: descriptive, never a diagnosis, never a cause, never a
/// to-do (bar the one generic thing to try on five rules).
struct InsightLanguageTests {
    typealias R = InsightRecordFixture
    private let format = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
    private let now = Fixture.date(2026, 9, 24, 10)

    private func content(_ record: InsightRecord) -> InsightContent {
        InsightScreenBuilder.build(record, format: format)
    }

    /// Records the engine makes for every mock scenario.
    private func scenarioRecords() async throws -> [InsightRecord] {
        var all: [InsightRecord] = []
        for scenario in MockScenario.allCases {
            let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
            let start = now.addingTimeInterval(-110 * 86_400 - 18 * 3600)
            let inputs = InsightInputsBuilder.build(
                sleep: try await provider.fetchSleepSamples(from: start, to: now), hrv: try await provider.fetchHRVSamples(from: start, to: now),
                restingHeartRate: try await provider.fetchRestingHeartRate(from: start, to: now), needMinutes: 480, now: now, timeZone: Fixture.newYork
            )
            all += InsightEngineV2.generate(inputs)
        }
        return all
    }

    // MARK: - The banned list

    /// Every generated string, over every mock scenario and a hand-built record of every type and direction.
    @Test func noGeneratedStringHasABannedWord() async throws {
        let records = try await scenarioRecords() + R.everyVariant
        #expect(records.count > 40)
        var checked = 0
        for record in records {
            for string in InsightScreenBuilder.strings(content(record)) {
                // The one required line that has to say "cause" to say it isn't one.
                let text = string.replacingOccurrences(of: InsightScreenBuilder.notProofLine, with: "").lowercased()
                for word in InsightScreenBuilder.bannedWords {
                    #expect(!text.contains(word), "\"\(word)\" in \(record.type.rawValue): \(string)")
                }
                checked += 1
            }
        }
        #expect(checked > 500)
    }

    @Test func theBannedListIsTheOneTheBriefNames() {
        #expect(Set(InsightScreenBuilder.bannedWords) == [
            "cause", "because", "diagnos", "disease", "sick", "insomnia", "apnea", "should", "must", "poor", "bad", "debt", "danger", "warning", "worry",
        ])
    }

    @Test func theLintWouldCatchABannedWord() {
        let sentence = "You should worry because your sleep debt is bad."
        let hits = InsightScreenBuilder.bannedWords.filter { sentence.lowercased().contains($0) }
        #expect(Set(hits) == ["should", "worry", "because", "cause", "debt", "bad"])
    }

    // MARK: - Required phrasing

    @Test func everyInsightSaysItInTheRequiredVoice() async throws {
        for record in try await scenarioRecords() + R.everyVariant {
            let words = content(record)
            #expect(words.context.hasPrefix("Compared with"), "\(record.type.rawValue): \(words.context)")
            if !record.type.isRecord, record.type != .milestone {
                let usesBaseline = words.context.contains("recent baseline") || words.context.contains("sleep need")
                #expect(usesBaseline, "\(record.type.rawValue): \(words.context)")
            }
            #expect(
                words.interpretation.hasPrefix("Your recent data suggests") || words.interpretation.hasPrefix("This has coincided with"),
                "\(record.type.rawValue): \(words.interpretation)"
            )
        }
    }

    @Test func thePatternSaysItIsAPatternNotProof() {
        let words = content(R.pattern())
        #expect(words.notProofLine == "This is a pattern in your data, not proof of a cause.")
        #expect(words.interpretation.hasPrefix("This has coincided with"))
        #expect(words.whatYouCanTry == nil)
        for record in R.everyVariant where record.type != .earlierBedtimePattern {
            #expect(content(record).notProofLine == nil, "\(record.type.rawValue)")
        }
    }

    @Test func onlyRulesOneTwoThreeSevenAndEightOfferSomethingToTry() {
        for record in R.everyVariant {
            let words = content(record)
            #expect((words.whatYouCanTry != nil) == record.type.offersSomethingToTry, "\(record.type.rawValue)")
            #expect(record.type.offersSomethingToTry == [1, 2, 3, 7, 8].contains(record.type.rule))
        }
    }

    @Test func theThingToTryIsGenericAndCarriesTheUsualBedtime() {
        // The clock's own spacing (a narrow no-break space before PM) is the formatter's business.
        func plain(_ text: String?) -> String? { text?.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") }
        #expect(plain(content(R.bedtime(delta: 55)).whatYouCanTry) == "Keep tonight's bedtime within 30 minutes of 11:00 PM.")
        #expect(plain(content(R.streak()).whatYouCanTry) == "Keep tonight's bedtime within 30 minutes of 11:00 PM.")
        #expect(content(R.consistency()).whatYouCanTry?.hasPrefix("Keep tonight's bedtime within 30 minutes of") == true)
    }

    @Test func whatToNoticeIsOneSentence() async throws {
        for record in try await scenarioRecords() + R.everyVariant {
            let text = content(record).whatToNotice
            #expect(text.hasSuffix("."), Comment(rawValue: text))
            #expect(text.dropLast().filter { ".!?".contains($0) }.isEmpty, "one sentence: \(text)")
            #expect(text.count < 120)
        }
    }

    @Test func aMilestoneIsNeverAToDo() {
        for count in [7, 14, 30] {
            let words = content(R.milestone(count))
            #expect(words.whatYouCanTry == nil)
            #expect(words.comparison.count == 1)
        }
    }

    // MARK: - Every number comes from the evidence

    @Test func numbersInTheWordsAreTheEvidenceRounded() {
        let duration = content(R.duration(delta: -70))
        #expect(duration.rowLine == "5h 50m last night, 1h 10m less than your usual 7h.")
        #expect(duration.comparison.map(\.value.plain) == ["5h 50m", "7h"])
        #expect(duration.context.contains("7h") && duration.context.contains("1h 10m shorter"))
        let bedtime = content(R.bedtime(delta: 55))
        #expect(bedtime.comparison.map(\.value.plain) == ["11:55PM", "11:00PM"])
        #expect(bedtime.rowLine.contains("55 min later"))
        let balance = content(R.balance(behind: true))
        #expect(balance.rowLine == "2h 42m behind your sleep need over the last 7 nights.")
        let pattern = content(R.pattern())
        #expect(pattern.rowLine.contains("averaged 92") && pattern.rowLine.contains("averaged 66"))
        #expect(pattern.method.nights.contains("16 earlier and 17 later"))
    }

    @Test func theConfidenceLineNamesTheNightsUsed() {
        #expect(content(R.record(.sleepDurationShift, R.duration(delta: -70).evidence, confidence: .moderate, nights: 23)).confidenceLine == "Moderate confidence · based on 23 nights")
        #expect(content(R.record(.sleepDurationShift, R.duration(delta: -70).evidence, confidence: .low, nights: 1)).confidenceLine == "Low confidence · based on 1 night")
        #expect(content(R.pattern()).confidenceLine == "High confidence · based on 33 nights")
    }

    @Test func theSameRecordAlwaysReadsTheSame() {
        for record in R.everyVariant { #expect(content(record) == content(record)) }
    }

    @Test func everyInsightCarriesItsFieldsAndAMethod() async throws {
        for record in try await scenarioRecords() + R.everyVariant {
            let words = content(record)
            #expect(!words.title.isEmpty && !words.rowLine.isEmpty && !words.context.isEmpty && !words.interpretation.isEmpty)
            #expect(!words.evidenceLines.isEmpty)
            #expect(!words.method.rule.isEmpty && !words.method.thresholds.isEmpty && !words.method.nights.isEmpty)
            #expect(!words.accessibilityLabel.isEmpty)
            #expect(!words.comparison.isEmpty)
            let joined = InsightScreenBuilder.strings(words).joined(separator: " ")
            #expect(!joined.contains("\\("), "no unfilled placeholder in \(record.type.rawValue)")
            #expect(!joined.contains("nan") && !joined.contains("inf"), "no non-number in \(record.type.rawValue)")
        }
    }
}
