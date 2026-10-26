import Foundation
import Testing

@testable import CoachKit
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import NoctisText
@testable import RecoveryFeature
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepFeature
@testable import SleepKit

// QA part 5, step 1 and 2: "your usual bedtime" is one number (the BaselineEngine's: the mean of the 14 nights before the night, never the night
// itself), and how late a night was is the same on Home's insight, Sleep's Consistency row, Insights, Coach, the Timing card and Profile. Coach's
// "based on N nights" is the number Recovery prints.
struct UsualTimesConsistencyTests {
    private let format = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))

    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ")
    }

    @Test func everySurfaceUsesTheBaselineEnginesUsualBedtimeAndWake() async throws {
        var checked = 0
        for scenario in CoachFixture.scenarios {
            let snapshots = await CoachFixture.snapshots(scenario)
            guard let sleep = snapshots.sleep, let last = sleep.records.last(where: { $0.night == sleep.defaultNight }) else { continue }
            let window = sleep.window(before: last.night)
            guard let bedtime = BaselineEngine.baseline(window.map(\.metrics.bedtimeMinutes)),
                let wake = BaselineEngine.baseline(window.map(\.metrics.wakeMinutes))
            else { continue }
            let tag = Comment(rawValue: scenario.rawValue)
            let lateness = last.metrics.bedtimeMinutes - bedtime.value

            // The Timing card and Profile read SleepTimingEngine's typical times.
            let timing = try #require(sleep.timing, tag)
            #expect(abs(try #require(timing.typicalBedtime, tag) - bedtime.value) < 0.001, tag)
            #expect(abs(try #require(timing.typicalWake, tag) - wake.value) < 0.001, tag)

            // Coach.
            let context = CoachContextBuilder(format: format).build(intent: .bedtimeAdvice, direction: nil, snapshots: snapshots, profile: CoachFixture.profile)
            let usual = try #require(context.facts.first { $0.id == "bedtime.usual" }, tag)
            #expect(plain(usual.display) == plain(format.clock(minutesAfterNoon: bedtime.value)), tag)
            let wakeUsual = try #require(context.facts.first { $0.id == "wake.usual" }, tag)
            #expect(plain(wakeUsual.display) == plain(format.clock(minutesAfterNoon: wake.value)), tag)
            let sleepContext = CoachContextBuilder(format: format).build(
                intent: .sleepChange, direction: nil, snapshots: snapshots, profile: CoachFixture.profile)
            if let delta = sleepContext.facts.first(where: { $0.id == "bedtime.deltaVsUsual" }) {
                #expect(abs(abs(delta.value) - abs(lateness)) < 0.001, tag)
            }

            // Sleep's Consistency row prints the same time and the same minutes.
            let sentence = SleepScreenBuilder.consistencySentence(last.metrics, window: window.map(\.metrics), format: format)
            #expect(plain(sentence).contains(plain(format.clock(minutesAfterNoon: bedtime.value))), Comment(rawValue: "\(scenario.rawValue): \(sentence)"))
            if abs(lateness.rounded()) >= 10 {
                #expect(
                    plain(sentence).contains(HomeFormat.compactDuration(Int(abs(lateness).rounded()), minutesWord: true)),
                    Comment(rawValue: "\(scenario.rawValue): \(sentence)"))
            }

            // Home's and Insights' bedtime insight: its baseline and its lateness for that night.
            if let record = snapshots.home?.topInsight, record.type == .bedtimeShift, case .baseline(let evidence) = record.evidence,
                let insightNight = sleep.records.first(where: { $0.night == evidence.night })
            {
                let insightBaseline = BaselineEngine.baseline(sleep.window(before: insightNight.night).map(\.metrics.bedtimeMinutes))
                #expect(abs(evidence.baseline - (insightBaseline?.value ?? -1)) < 0.001, tag)
                #expect(abs(evidence.delta - (insightNight.metrics.bedtimeMinutes - evidence.baseline)) < 0.001, tag)
            }
            checked += 1
        }
        #expect(checked >= 6, "the check ran on the scenarios that have a baseline")
    }

    @Test func coachSaysBasedOnTheNightsRecoveryUses() async throws {
        var checked = 0
        for scenario in CoachFixture.scenarios {
            let snapshots = await CoachFixture.snapshots(scenario)
            guard let result = snapshots.recovery?.result ?? CoachContextBuilder.result(snapshots.home) else { continue }
            let context = CoachContextBuilder(format: format).build(
                intent: .recoveryChange, direction: nil, snapshots: snapshots, profile: CoachFixture.profile)
            #expect(context.baselineNights == result.baselineNights, Comment(rawValue: scenario.rawValue))
            let line = CoachAnswerAssembler.confidenceLine(.high, nights: context.baselineNights, locale: Locale(identifier: "en_US"))
            #expect(line.hasSuffix("based on \(NoctisCount.nights(result.baselineNights))"), Comment(rawValue: line))
            checked += 1
        }
        #expect(checked >= 4)
    }
}
