import DesignSystem
import Foundation
import Testing

@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisWatchKit
@testable import NoctisWidgetKit
@testable import ProfileFeature
@testable import RecoveryKit

// The Apple Watch app's pages (APP_RULES.md R50, R51): what every page says for every state, in the person's locale, with the privacy flags the views
// hide behind. Pure builders, so every sentence is a unit test and the lint holds the words to the banned-language list.

private nonisolated let ny: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return value
}()

private nonisolated func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    ny.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second)) ?? Date()
}

private let english = WidgetFormat(calendar: ny, locale: Locale(identifier: "en_US"))
private let german = WidgetFormat(calendar: ny, locale: Locale(identifier: "de_DE"))

private func sample(_ state: WidgetDataState = .full, day: Int = 24, generated: Date? = nil) -> WidgetSnapshot {
    var value = WidgetSamples.snapshot(state, now: generated ?? at(day, 10), calendar: ny)
    value.forDay = WidgetDay(year: 2026, month: 9, day: day)
    return value
}

private func input(_ snapshot: WidgetSnapshot?, now: Date = at(24, 10), received: Date? = nil, format: WidgetFormat = english) -> WatchPageInput {
    WatchPageInput(snapshot: snapshot, now: now, receivedAt: received, format: format)
}

private func sp(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ") }

// MARK: - Recovery

struct WatchRecoveryPageTests {
    @Test func aFullDayShowsTheScoreTheDeltaTheRingAndTheFourFactors() throws {
        let page = WatchPages.recovery(input(sample(.full)))
        #expect(page.message == nil && page.score == 70 && page.sensitivity == .health)
        #expect(page.delta == .init(text: "+6 vs your usual", tone: .above))
        #expect(page.ring.map(\.kind) == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency])
        #expect(page.factors.map(\.name) == ["Sleep", "HRV", "Resting HR", "Consistency"] && page.factors.map(\.score) == [82, 64, 71, 90])
        #expect(page.confidence == nil, "a high confidence says nothing")
        #expect(page.staleLine == nil && page.accessibilityLabel == "Recovery 70. +6 vs your usual")
    }

    @Test func aNegativeDeltaUsesTheTrueMinusAndTheConfidenceShowsOnlyWhenNotHigh() {
        var value = sample(.full)
        value.recovery?.delta = -18
        value.recovery?.confidence = .moderate
        let page = WatchPages.recovery(input(value))
        #expect(page.delta == .init(text: "\u{2212}18 vs your usual", tone: .below))
        #expect(page.confidence == "Moderate confidence")
        value.recovery?.confidence = .low
        value.recovery?.delta = 0
        let low = WatchPages.recovery(input(value))
        #expect(low.confidence == "Low confidence" && low.delta == .init(text: "\u{00B1}0 vs your usual", tone: .inLine))
        value.recovery?.delta = nil
        #expect(WatchPages.recovery(input(value)).delta == nil)
    }

    @Test func sleepOnlyShowsTheTwoFactorsItHas() {
        let page = WatchPages.recovery(input(sample(.sleepOnly)))
        #expect(page.score == 68 && page.factors.map(\.name) == ["Sleep", "Consistency"])
        #expect(page.confidence == "Moderate confidence")
    }

    @Test func staleNumbersAreTheLastKnownOnesWithTheirAgeAndNeverAreToday() {
        let stale = sample(.stale(hours: 14))
        let page = WatchPages.recovery(input(stale))
        #expect(page.score == 70 && page.staleLine == "Updated 14h ago")
        #expect(page.accessibilityLabel.hasSuffix("Updated 14h ago"))
        // Two hours on, it is older, not the same.
        #expect(WatchPages.recovery(input(stale, now: at(24, 12))).staleLine == "Updated 16h ago")
        #expect(WatchPages.recovery(input(sample(.stale(hours: 60)), now: at(24, 10))).staleLine == "Updated 2d ago")
    }

    @Test func everyStateWithoutNumbersSaysWhatIsMissingAndShowsNoScore() {
        let cases: [(WidgetSnapshot?, String)] = [
            (sample(.learning(nightsSoFar: 3)), "Learning your baseline - 3 of 5 nights"),
            (sample(.empty), "Open NOCTIS on your iPhone to connect Apple Health"),
            (sample(.noPermission), "Open NOCTIS on your iPhone to connect Apple Health"),
            (sample(.gap), "No sleep recorded last night"),
            (sample(.full, day: 23), "Waiting for last night's data"),
            (nil, "Open NOCTIS on your iPhone to get started"),
        ]
        for (value, words) in cases {
            let page = WatchPages.recovery(input(value))
            #expect(page.message?.title == words && page.score == nil && page.factors.isEmpty && page.ring.isEmpty, Comment(rawValue: words))
        }
    }

    @Test func noPageEverShowsYesterdaysNumbersAsTodays() {
        for state in [WidgetDataState.full, .sleepOnly, .stale(hours: 5)] {
            let yesterday = input(sample(state, day: 23))
            #expect(WatchPages.recovery(yesterday).score == nil && WatchPages.sleep(yesterday).duration == nil && WatchPages.heart(yesterday).tiles.isEmpty)
            #expect(WatchPages.recovery(yesterday).message?.title == "Waiting for last night's data")
        }
        // Until 4 AM the evening before is still its day: its numbers are still the latest.
        let evening = input(sample(.full, day: 23), now: at(24, 3, 59))
        #expect(WatchPages.recovery(evening).score == 70)
        #expect(WatchPages.recovery(input(sample(.full, day: 23), now: at(24, 4, 0))).score == nil)
    }
}

// MARK: - Sleep

struct WatchSleepPageTests {
    @Test func aNightShowsItsDurationItsHoursTheStagesAndTheQuality() throws {
        let page = WatchPages.sleep(input(sample(.full)))
        #expect(page.message == nil && page.caption == "Last night" && page.duration?.plain == "6h 42m" && page.duration?.spoken == "6 hours 42 minutes")
        let times = try #require(page.times)
        #expect(sp(times) == "11:04 PM – 6:52 AM")
        #expect(page.stages == WidgetStages(deep: 74, core: 236, rem: 92) && page.quality == "Sleep quality 81" && page.sensitivity == .health)
        #expect(page.accessibilityLabel == "Slept 6 hours 42 minutes. Sleep quality 81")
    }

    @Test func noQualityMeansNoQualityLineAndNoStagesMeansNoStrip() {
        var value = sample(.full)
        value.lastNight?.quality = nil
        value.lastNight?.stages = nil
        let page = WatchPages.sleep(input(value))
        #expect(page.quality == nil && page.stages == nil && page.duration != nil)
    }

    @Test func staleSleepIsTheLastRecordedNightWithItsAge() {
        let page = WatchPages.sleep(input(sample(.stale(hours: 30))))
        #expect(page.caption == "Last recorded" && page.staleLine == "Updated 30h ago" && page.accessibilityLabel.hasPrefix("Last recorded sleep"))
    }

    @Test func theStatesWithoutANightSaySo() {
        #expect(WatchPages.sleep(input(sample(.gap))).message?.title == "No sleep recorded last night")
        #expect(WatchPages.sleep(input(sample(.learning(nightsSoFar: 2)))).message?.title == "Learning your baseline - 2 of 5 nights")
        #expect(WatchPages.sleep(input(nil)).message?.title == "Open NOCTIS on your iPhone to get started")
        var none = sample(.full)
        none.lastNight = nil
        #expect(WatchPages.sleep(input(none)).message?.title == "No sleep recorded last night")
    }
}

// MARK: - Heart

struct WatchHeartPageTests {
    @Test func twoTilesWithTheIPhonesOwnSentence() {
        let page = WatchPages.heart(input(sample(.full)))
        #expect(page.tiles.map(\.name) == ["HRV", "Resting HR"])
        #expect(page.tiles.map(\.value.plain) == ["54ms", "52bpm"] && page.tiles.map(\.baseline) == ["baseline 61 ms", "baseline 50 bpm"])
        #expect(page.tiles.map(\.sentence) == ["Within your normal range", "Above your normal range"])
        #expect(page.sensitivity == .health && page.message == nil)
        #expect(page.accessibilityLabel.contains("HRV 54 milliseconds, within your normal range"))
    }

    @Test func theWordsAreTheIPhonesWords() {
        // Home's range sentence is made from the same words.
        for (range, widget) in [(RecoveryRange.within, WidgetFactorRange.within), (.above, .above), (.below, .below)] {
            let sentence = HomeScreenBuilder.rangeSentence(range, value: "48 ms", baseline: "50 ms")
            #expect(sentence.hasPrefix(WidgetCopy.rangePlace(widget) + ":"))
        }
    }

    @Test func aTileWithNoDataIsLeftOutAndNoDataAtAllSaysWhy() {
        var onlyHeartRate = sample(.full)
        onlyHeartRate.factors = WidgetFactors(hrv: nil, restingHeartRate: 55)
        #expect(WatchPages.heart(input(onlyHeartRate)).tiles.map(\.name) == ["Resting HR"])
        var noRange = sample(.full)
        noRange.recoveryFactors = []
        #expect(WatchPages.heart(input(noRange)).tiles.allSatisfy { $0.sentence == nil && $0.baseline == nil }, "no baseline and no range: nothing made up")
        // Sleep alone: no heart numbers at all.
        let sleepOnly = WatchPages.heart(input(sample(.sleepOnly)))
        #expect(sleepOnly.tiles.isEmpty && sleepOnly.message?.title == "No heart rate variability or resting heart rate was available for last night.")
    }

    @Test func staleHeartNumbersCarryTheirAge() {
        #expect(WatchPages.heart(input(sample(.stale(hours: 14)))).staleLine == "Updated 14h ago")
        #expect(WatchPages.heart(input(sample(.learning(nightsSoFar: 3)))).message?.title == "Learning your baseline - 3 of 5 nights")
    }
}

// MARK: - Tonight

struct WatchTonightPageTests {
    @Test func aDayShowsTheWindowTheWakeLineAndTheAlarmWithNoCountdown() throws {
        let page = WatchPages.tonight(input(sample(.full), now: at(24, 10)))
        let window = try #require(page.windowText)
        let wake = try #require(page.wakeLine)
        let alarm = try #require(page.alarmLine)
        #expect(sp(window) == "10:45 – 11:15 PM" && page.bedtime == nil)
        #expect(sp(wake) == "Wake 7:00 AM - 8h need" && sp(alarm) == "Alarm 7:00 AM")
        #expect(page.countdown == .none && page.sensitivity == .plan)
    }

    @Test func oneBedtimeIsAMetric() throws {
        var value = sample(.full)
        value.plan.windowStartMinutes = nil
        value.plan.windowEndMinutes = nil
        let page = WatchPages.tonight(input(value))
        let bedtime = try #require(page.bedtime)
        #expect(page.windowText == nil && sp(bedtime.plain) == "11:00PM")
    }

    @Test func noAlarmSaysNoAlarmSet() {
        var value = sample(.full)
        value.alarm = nil
        #expect(WatchPages.tonight(input(value)).alarmLine == "No alarm set")
        value.alarm = WidgetAlarm(minutes: 420, isOn: false)
        #expect(WatchPages.tonight(input(value)).alarmLine == "No alarm set", "an alarm that is off is not set")
    }

    @Test func theCountdownBoundaries() {
        let value = sample(.full)
        // The evening starts three hours before the bedtime: 8:00 PM for 11:00 PM.
        #expect(WatchPages.tonight(input(value, now: at(24, 19, 59, 59))).countdown == .none)
        #expect(WatchPages.tonight(input(value, now: at(24, 20, 0))).countdown == .until(at(24, 23, 0)))
        #expect(WatchPages.tonight(input(value, now: at(24, 22, 59, 59))).countdown == .until(at(24, 23, 0)))
        // At the bedtime itself it is over, and says so.
        guard case .passed(let over) = WatchPages.tonight(input(value, now: at(24, 23, 0))).countdown else {
            Issue.record("at the bedtime the countdown is over")
            return
        }
        #expect(sp(over) == "Bedtime was 11:00 PM")
        #expect(sp(WatchPages.tonight(input(value, now: at(25, 1, 30))).accessibilityLabel).hasPrefix("Bedtime was 11:00 PM"))
    }

    @Test func thePlanIsShownWhateverTheDataStateBecauseItIsThePersonsOwn() {
        for state in [WidgetDataState.learning(nightsSoFar: 1), .empty, .noPermission, .gap, .stale(hours: 20)] {
            let page = WatchPages.tonight(input(sample(state), now: at(24, 21)))
            #expect(page.message == nil && page.windowText != nil && page.sensitivity == .plan, Comment(rawValue: state.token))
        }
        #expect(WatchPages.tonight(input(nil)).message?.title == "Open NOCTIS on your iPhone to get started")
    }

    @Test func aTwentyFourHourLocaleHasNoPeriod() throws {
        let page = WatchPages.tonight(input(sample(.full), format: german))
        let window = try #require(page.windowText)
        // The digits are the locale's own (whether it pads 7:00 or not); what must hold is that there is no period and the line uses them.
        let wake = german.clock(minutesSinceMidnight: 420)
        #expect(window.contains("22:45") && page.wakeLine == "Wake \(wake) - 8h need")
        let sleep = WatchPages.sleep(input(sample(.full), format: german))
        let bed = german.clock(minutesSinceMidnight: 23 * 60 + 4), up = german.clock(minutesSinceMidnight: 6 * 60 + 52)
        #expect(sleep.times == "\(bed) – \(up)")
        for text in [window, wake, bed, up, sleep.times ?? ""] { #expect(!text.contains("AM") && !text.contains("PM"), Comment(rawValue: text)) }
    }
}

// MARK: - Settings

struct WatchSettingsPageTests {
    @Test func theStatusSaysWhatTheWatchHolds() {
        let received = at(24, 7)
        func status(_ value: WidgetSnapshot?) -> String { WatchPages.settings(input(value, received: received), version: "NOCTIS 1.0 (1)").status }
        #expect(status(sample(.full)) == "Recovery and sleep" && status(sample(.sleepOnly)) == "Sleep only")
        #expect(status(sample(.stale(hours: 14))) == "Last numbers, 14h ago")
        #expect(status(sample(.learning(nightsSoFar: 3))) == "Learning your baseline - 3 of 5 nights")
        #expect(status(sample(.full, day: 23)) == "Waiting for last night's data" && status(sample(.gap)) == "No sleep recorded last night")
        #expect(status(sample(.empty)) == "Apple Health isn't connected" && status(nil) == "Nothing received yet")
        let page = WatchPages.settings(input(sample(), received: received), version: "NOCTIS 1.0 (1)")
        #expect(page.about == "NOCTIS isn't a medical device and doesn't diagnose or treat any condition." && page.version == "NOCTIS 1.0 (1)")
    }

    @Test func updatedSaysHowLongSinceTheWatchReceivedItAndNeverHowOldTheNumbersAre() {
        let received = at(24, 7)
        func updated(after seconds: TimeInterval) -> String? { WatchCopy.updated(since: received, now: received.addingTimeInterval(seconds)) }
        #expect(updated(after: 0) == "Updated just now" && updated(after: 59) == "Updated just now")
        #expect(updated(after: 60) == "Updated 1m ago" && updated(after: 3599) == "Updated 59m ago")
        #expect(updated(after: 3600) == "Updated 1h ago" && updated(after: 3 * 3600) == "Updated 3h ago" && updated(after: 47 * 3600) == "Updated 47h ago")
        #expect(updated(after: 48 * 3600) == "Updated 2d ago")
        #expect(WatchCopy.updated(since: nil, now: received) == nil, "nothing received: no claim")
        #expect(
            WatchCopy.updated(since: received, now: received.addingTimeInterval(-30)) == "Updated just now", "a clock that moved back never says negative time")
    }
}

// MARK: - Privacy and wording

struct WatchPageWordingTests {
    @Test func everyHealthNumberIsMarkedHealthAndOnlyThePlanIsNot() {
        let value = input(sample(.full))
        #expect(
            WatchPages.recovery(value).sensitivity == .health && WatchPages.sleep(value).sensitivity == .health
                && WatchPages.heart(value).sensitivity == .health)
        #expect(WatchPages.tonight(value).sensitivity == .plan, "the bedtime, the wake time and the alarm are the person's settings")
    }

    @Test func theViewsHideEveryHealthValueBehindThePrivacyWrapper() throws {
        let views = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Watch/App/WatchViews.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(views)
        #expect(code.contains(".privacySensitive(") && code.contains("redactionReasons") && code.contains("lock.fill"))
        // Each page wraps what it shows of Health: the score, the factor scores, the delta, the duration, the strip, the quality, the heart tiles.
        let wraps = code.components(separatedBy: "WatchPrivate(").count - 1
        #expect(wraps >= 10, "\(wraps) uses")
        #expect(!code.contains("Text(\"\\(content.score"), "the score is only drawn inside the wrapper")
        // The pages' text is never smaller than 12pt.
        let sizes = code.matches(of: /noctisFont\((\d+(?:\.\d+)?)/).compactMap { Double($0.1) }
        #expect(sizes.count >= 15 && sizes.allSatisfy { $0 >= 12 })
        let metrics = code.matches(of: /size: (\d+)/).compactMap { Double($0.1) }
        #expect(metrics.allSatisfy { $0 >= 12 })
    }

    @Test func everySentenceIsFreeOfTheBannedLanguage() {
        let states: [WidgetSnapshot?] = [
            sample(.full), sample(.sleepOnly), sample(.learning(nightsSoFar: 3)), sample(.empty), sample(.noPermission), sample(.stale(hours: 14)),
            sample(.gap),
            sample(.full, day: 23), nil,
        ]
        var strings: [String] = [
            WatchCopy.unreachable, WatchCopy.asked, WatchCopy.askFailed, WatchCopy.askButton, WatchCopy.breathingTagline, WatchCopy.heartMissing,
        ]
        for value in states {
            for now in [at(24, 10), at(24, 21), at(25, 1)] {
                let page = input(value, now: now, received: at(24, 7))
                let recovery = WatchPages.recovery(page), sleep = WatchPages.sleep(page), heart = WatchPages.heart(page), tonight = WatchPages.tonight(page)
                strings += [recovery.accessibilityLabel, sleep.accessibilityLabel, heart.accessibilityLabel, tonight.accessibilityLabel]
                strings += [
                    recovery.message?.title, recovery.message?.detail, recovery.confidence, recovery.staleLine, recovery.delta?.text, sleep.quality,
                    sleep.staleLine,
                ].compactMap { $0 }
                strings +=
                    heart.tiles.compactMap { $0.sentence } + heart.tiles.compactMap { $0.baseline } + [tonight.wakeLine, tonight.alarmLine].compactMap { $0 }
                let settings = WatchPages.settings(page, version: "NOCTIS 1.0 (1)")
                strings += [settings.status] + [settings.updated].compactMap { $0 }
            }
        }
        #expect(strings.count > 150)
        for text in strings {
            #expect(
                BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty,
                Comment(rawValue: "\"\(text)\" has \(BannedLanguage.hits(in: text, of: BannedLanguage.coach))"))
        }
    }

    @Test func theAboutLineIsTheIPhonesDisclaimerAndTheOneSentenceThatMayNameDiagnosis() {
        // The scan above leaves it out on purpose: it is the sentence that denies a diagnosis, so it has to use the word.
        #expect(WatchCopy.about == AboutContent.medical)
    }

    @Test func theWatchSaysNothingTheIPhoneDoesNotSay() {
        // Every state's words come from the one place the widgets use, or the Watch's own short copy.
        #expect(WidgetCopy.learningLine(3) == "Learning your baseline - 3 of 5 nights")
        #expect(WatchCopy.noSleep == WidgetCopy.noSleep)
        #expect(WatchPageInput(snapshot: sample(.stale(hours: 14)), now: at(24, 10)).state.isStale)
    }
}
