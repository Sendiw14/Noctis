import Foundation
import Testing

@testable import InsightsKit
@testable import NoctisWatchKit
@testable import NoctisWidgetKit

// The Apple Watch complications (APP_RULES.md R50, R51, R54): what each of the four kinds says in each of the four families for every state, the
// moments they change, how much the Smart Stack wants them, which words are Health values (hidden while the Watch is locked), and the one strict link
// they carry. Pure builders, so every sentence is a unit test.

private nonisolated let ny: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return value
}()

private nonisolated func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    ny.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second)) ?? Date()
}

private let english = WidgetFormat(calendar: ny, locale: Locale(identifier: "en_US"))

private func sample(_ state: WidgetDataState = .full, day: Int = 24) -> WidgetSnapshot {
    var value = WidgetSamples.snapshot(state, now: at(day, 10), calendar: ny)
    value.forDay = WidgetDay(year: 2026, month: 9, day: day)
    return value
}

private func content(_ kind: WatchComplicationKind, _ snapshot: WidgetSnapshot?, now: Date = at(24, 10)) -> WatchComplicationContent {
    WatchComplications.content(kind, input: WatchPageInput(snapshot: snapshot, now: now, format: english))
}

private func sp(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{2009}", with: " ") }

/// The words of a line, the way the view writes them (a countdown as "<timer>").
private func words(_ pieces: [WidgetLockPiece]) -> String {
    sp(pieces.map { piece -> String in
        switch piece {
        case .text(let string), .health(let string): string
        case .countdown: "<timer>"
        }
    }.joined())
}

private func lines(_ content: WatchComplicationContent) -> [String] { content.rectangular.map(words) }

private func hasHealth(_ pieces: [WidgetLockPiece]) -> Bool { pieces.contains { if case .health = $0 { true } else { false } } }

// MARK: - Recovery

struct WatchRecoveryComplicationTests {
    @Test func byDayItIsTheScoreOnAGaugeWithSleepAndBedtimeBelow() {
        let made = content(.recovery, sample())
        #expect(made.gauge == 0.7 && made.centerText == "70" && made.centerIsHealth && made.centerGlyph == nil)
        #expect(lines(made) == ["Recovery 70", "Sleep 6h 42m", "Bed 11:00 PM"])
        #expect(words(made.inline) == "Recovery 70" && made.link == .recovery)
        #expect(made.accessibilityLabel == "Recovery 70. Slept 6 hours 42 minutes")
        #expect(made.cornerLabel == "Recovery")
    }

    @Test func inTheEveningItCountsDownToTheBedtimeAndTheLinkOpensTonight() {
        let made = content(.recovery, sample(), now: at(24, 21, 30))
        #expect(lines(made) == ["Bedtime 11:00 PM", "in <timer>", "Recovery 70"])
        #expect(words(made.inline) == "Bedtime in <timer>" && made.link == .tonight)
        guard case .countdown(let date) = made.rectangular[1][1] else { Issue.record("a countdown"); return }
        #expect(date == at(24, 23))
        #expect(made.gauge == 0.7, "the score stays on the gauge")
        let passed = content(.recovery, sample(), now: at(25, 0, 30))
        #expect(lines(passed).first == "Bedtime was 11:00 PM" && words(passed.inline) == "Bedtime was 11:00 PM")
    }

    @Test func oldNumbersCarryTheirAgeAndNoScoreOnTheGauge() {
        let made = content(.recovery, sample(.stale(hours: 14)))
        #expect(made.gauge == nil && made.centerText == "" && made.centerGlyph == "bolt.heart" && !made.centerIsHealth)
        #expect(lines(made) == ["Sleep 6h 42m", "Updated 14h ago"])
        #expect(words(made.inline) == "Sleep 6h 42m - old")
        #expect(made.accessibilityLabel.contains("Last recorded sleep 6 hours 42 minutes") && made.accessibilityLabel.contains("Updated 14h ago"))
    }

    @Test func sleepAloneStillGivesAScoreAndAGauge() {
        let made = content(.recovery, sample(.sleepOnly))
        #expect(made.gauge == 0.68 && made.centerText == "68")
    }
}

// MARK: - Sleep

struct WatchSleepComplicationTests {
    @Test func theCircleSaysTheHoursAndMinutesWithOneUnit() {
        #expect(WatchComplications.circularDuration(402) == "6h42" && WatchComplications.circularDuration(365) == "6h05")
        #expect(WatchComplications.circularDuration(480) == "8h00" && WatchComplications.circularDuration(45) == "45m" && WatchComplications.circularDuration(0) == "0m")
    }

    @Test func itIsTheDurationAndAFlatStageStripAndTheLineIsWords() {
        let made = content(.sleep, sample())
        #expect(made.centerText == "6h42" && made.gauge == nil && made.centerIsHealth)
        #expect(lines(made) == ["Slept 6h 42m"] && made.stages == WidgetStages(deep: 74, core: 236, rem: 92))
        #expect(words(made.inline) == "Slept 6h 42m" && made.link == .sleep)
        #expect(made.accessibilityLabel == "Slept 6 hours 42 minutes")
    }

    @Test func oldNumbersSayLastSleptAndHowOld() {
        let made = content(.sleep, sample(.stale(hours: 14)))
        #expect(lines(made) == ["Last slept 6h 42m", "Updated 14h ago"] && words(made.inline) == "Slept 6h 42m - old")
    }

    @Test func noStagesMeansNoStripNotAMadeUpOne() {
        var value = sample()
        value.lastNight?.stages = nil
        #expect(content(.sleep, value).stages == nil)
    }
}

// MARK: - Bedtime

struct WatchBedtimeComplicationTests {
    @Test func byDayItIsTheBedtimeAndTheWakeTimeAndNotAHealthValue() {
        let made = content(.bedtime, sample())
        #expect(made.centerText == "11:00" && made.centerGlyph == "moon.stars.fill" && !made.centerIsHealth && made.gauge == nil)
        #expect(lines(made) == ["Bedtime 11:00 PM", "Wake 7:00 AM"] && words(made.inline) == "Bedtime 11:00 PM" && made.link == .tonight)
        #expect(made.rectangular.allSatisfy { !hasHealth($0) } && !hasHealth(made.inline))
    }

    @Test func inTheEveningItCountsDownAndAfterwardsSaysItPassed() {
        let evening = content(.bedtime, sample(), now: at(24, 21))
        #expect(lines(evening) == ["Bedtime 11:00 PM", "in <timer>"] && words(evening.inline) == "Bedtime in <timer>")
        let boundary = content(.bedtime, sample(), now: at(24, 23))
        #expect(lines(boundary) == ["Bedtime was 11:00 PM", "Wake 7:00 AM"], "at the bedtime itself it is over")
    }

    @Test func theBedtimeIsTheOwnersPlanSoItShowsWhateverTheHealthStateIs() {
        for state in [WidgetDataState.learning(nightsSoFar: 2), .empty, .noPermission, .gap, .stale(hours: 20)] {
            #expect(words(content(.bedtime, sample(state)).inline) == "Bedtime 11:00 PM", Comment(rawValue: state.token))
        }
        // The summary is for yesterday: the plan is still the plan.
        #expect(words(content(.bedtime, sample(day: 23)).inline) == "Bedtime 11:00 PM")
    }
}

// MARK: - Sleep quality

struct WatchQualityComplicationTests {
    @Test func itIsTheScoreOnAGaugeWithTheDurationBelow() {
        let made = content(.quality, sample())
        #expect(made.gauge == 0.81 && made.centerText == "81" && made.centerIsHealth)
        #expect(lines(made) == ["Sleep quality 81", "6h 42m"] && words(made.inline) == "Sleep quality 81" && made.link == .sleep)
    }

    @Test func aNightWithNoScoreIsSaidSoAndNeverGivesANumber() {
        var value = sample()
        value.lastNight?.quality = nil
        let made = content(.quality, value)
        #expect(made.gauge == nil && made.centerText == "–" && !made.centerIsHealth)
        #expect(lines(made) == ["Sleep quality", "No score for last night"] && words(made.inline) == "Sleep quality - none")
    }

    @Test func oldNumbersShowTheirAge() {
        #expect(lines(content(.quality, sample(.stale(hours: 14)))) == ["Sleep quality 81", "Updated 14h ago"])
    }
}

// MARK: - The states every health kind shares

struct WatchComplicationStateTests {
    private let healthKinds: [WatchComplicationKind] = [.recovery, .sleep, .quality]

    @Test func withNoSummaryEveryKindSaysToOpenNOCTISOnTheIPhone() {
        for kind in WatchComplicationKind.allCases {
            let made = content(kind, nil)
            #expect(lines(made) == ["Open NOCTIS", "on your iPhone"] && words(made.inline) == "Open NOCTIS on iPhone", Comment(rawValue: kind.rawValue))
            #expect(made.gauge == nil && made.centerText == "" && made.centerGlyph == "iphone" && !made.centerIsHealth)
        }
    }

    @Test func asummaryForYesterdayIsNeverShownAsToday() {
        let yesterday = sample(day: 23)
        for kind in healthKinds {
            let made = content(kind, yesterday)
            #expect(lines(made) == ["Waiting for", "last night's sleep"] && words(made.inline) == "Waiting for sleep data", Comment(rawValue: kind.rawValue))
            #expect(made.gauge == nil && made.centerText == "" && made.stages == nil && made.centerGlyph == "hourglass")
            let everything = (made.rectangular + [made.inline]).map(words).joined(separator: " ") + made.accessibilityLabel
            for number in ["70", "6h", "81", "402", "78"] { #expect(!everything.contains(number), Comment(rawValue: "\(kind.rawValue) shows \(number)")) }
        }
    }

    @Test func learningGapAndNoHealthEachHaveTheirOwnShortWords() {
        for kind in healthKinds {
            #expect(lines(content(kind, sample(.learning(nightsSoFar: 3)))) == ["Learning your baseline", "3 of 5 nights"])
            #expect(words(content(kind, sample(.learning(nightsSoFar: 3))).inline) == "Learning · 3 of 5 nights")
            #expect(lines(content(kind, sample(.gap))) == ["No sleep recorded", "last night"] && words(content(kind, sample(.gap)).inline) == "No sleep last night")
            for state in [WidgetDataState.empty, .noPermission] {
                #expect(lines(content(kind, sample(state))) == ["Open NOCTIS", "to connect Apple Health"] && words(content(kind, sample(state)).inline) == "Open NOCTIS for Health")
            }
        }
    }

    @Test func noMessageIsAHealthValue() {
        for kind in WatchComplicationKind.allCases {
            for state in [WidgetDataState.learning(nightsSoFar: 3), .gap, .empty, .noPermission] {
                let made = content(kind, sample(state))
                guard kind != .bedtime else { continue }
                #expect(!made.centerIsHealth && made.rectangular.allSatisfy { !hasHealth($0) } && !hasHealth(made.inline), Comment(rawValue: "\(kind.rawValue) \(state.token)"))
            }
        }
    }
}

// MARK: - Privacy

struct WatchComplicationPrivacyTests {
    @Test func everyHealthWordIsMarkedAndALockedWatchSeesNoneOfThem() {
        for kind in [WatchComplicationKind.recovery, .sleep, .quality] {
            let open = content(kind, sample())
            #expect(open.centerIsHealth && open.rectangular.contains(where: hasHealth) && hasHealth(open.inline), Comment(rawValue: kind.rawValue))
            let locked = open.locked()
            #expect(locked.gauge == nil && locked.centerText == "" && locked.centerGlyph == "lock.fill" && locked.stages == nil, Comment(rawValue: kind.rawValue))
            #expect(!locked.rectangular.contains(where: hasHealth) && !hasHealth(locked.inline))
            #expect(locked.accessibilityLabel == WidgetCopy.unlock)
            let everything = (locked.rectangular + [locked.inline]).map(words).joined(separator: " ") + locked.accessibilityLabel
            for number in ["70", "6h", "81", "42m"] { #expect(!everything.contains(number), Comment(rawValue: "\(kind.rawValue) leaks \(number)")) }
        }
    }

    @Test func theLinesAfterTheFirstHealthLineCollapseIntoOneUnlockLine() {
        let locked = content(.recovery, sample()).locked()
        #expect(lines(locked) == ["Unlock to see", "Bed 11:00 PM"] && words(locked.inline) == "Unlock to see")
    }

    @Test func bedtimeIsThePersonsOwnPlanAndStaysWhileLocked() {
        let open = content(.bedtime, sample())
        #expect(open.locked() == open && !WatchComplicationKind.bedtime.showsHealth)
        #expect(WatchComplicationKind.allCases.filter(\.showsHealth).count == 3)
    }
}

// MARK: - The timeline and the Smart Stack

struct WatchComplicationScheduleTests {
    @Test func theTimelineChangesAtEachBoundaryAndNeverLooksPastTwelveHours() {
        let now = at(24, 16)
        let plan = WatchComplicationSchedule.dates(snapshot: sample(), now: now, calendar: ny)
        let dates = plan.entries.map(\.date)
        #expect(dates == [at(24, 16), at(24, 20), at(24, 23)], "now, when the evening starts, and the bedtime; 4 AM is the horizon")
        #expect(dates.allSatisfy { $0 < now.addingTimeInterval(WidgetTimelineBuilder.horizon) } && plan.reloadAfter <= now.addingTimeInterval(WidgetTimelineBuilder.horizon))
        #expect(plan.reloadAfter > dates.last ?? now)
        #expect(WatchComplicationSchedule.dates(snapshot: nil, now: now, calendar: ny).entries.map(\.date) == [now])
    }

    @Test func oldNumbersGetAnEntryAnHourSoTheirAgeStaysTrue() {
        let plan = WatchComplicationSchedule.dates(snapshot: sample(.stale(hours: 14)), now: at(24, 10), calendar: ny)
        #expect(plan.entries.count >= 11)
        let ages = plan.entries.map { content(.recovery, sample(.stale(hours: 14)), now: $0.date).accessibilityLabel }
        #expect(ages.first?.contains("Updated 14h ago") == true && ages.contains { $0.contains("Updated 15h ago") })
    }

    @Test func theMorningKindsAreWantedInTheMorningWindowAndBedtimeInTheEveningHour() {
        let value = sample()
        func score(_ kind: WatchComplicationKind, _ date: Date) -> Float { WatchComplicationSchedule.relevance(kind, at: date, snapshot: value, calendar: ny).score }
        for kind in [WatchComplicationKind.recovery, .sleep, .quality] {
            #expect(score(kind, at(24, 6, 30)) == 100 && score(kind, at(24, 8)) == 100 && score(kind, at(24, 10)) == 100, Comment(rawValue: kind.rawValue))
            #expect(score(kind, at(24, 10, 1)) == 10 && score(kind, at(24, 6, 29)) == 10 && score(kind, at(24, 22, 30)) == 10, "idle outside it, even at bedtime")
        }
        #expect(score(.bedtime, at(24, 22)) == 90 && score(.bedtime, at(24, 23, 30)) == 90)
        #expect(score(.bedtime, at(24, 21, 59)) == 10 && score(.bedtime, at(24, 23, 31)) == 10 && score(.bedtime, at(24, 8)) == 10, "idle in the morning")
        #expect(WatchComplicationSchedule.relevance(.recovery, at: at(24, 8), snapshot: nil, calendar: ny) == .idle)
    }

    @Test func theMorningWindowRunsForTheRestOfIt() {
        let relevance = WatchComplicationSchedule.relevance(.recovery, at: at(24, 8), snapshot: sample(), calendar: ny)
        #expect(relevance.duration == 2 * 3600, "until ten")
        let evening = WatchComplicationSchedule.relevance(.bedtime, at: at(24, 22), snapshot: sample(), calendar: ny)
        #expect(evening.duration == 90 * 60)
    }

    @Test func theSmartStackIsToldTheWindowForEachKind() {
        let value = sample()
        let morning = WatchComplicationSchedule.window(.recovery, snapshot: value, from: at(24, 12), calendar: ny)
        #expect(morning == DateInterval(start: at(25, 6, 30), end: at(25, 10)))
        let evening = WatchComplicationSchedule.window(.bedtime, snapshot: value, from: at(24, 12), calendar: ny)
        #expect(evening == DateInterval(start: at(24, 22), end: at(24, 23, 30)))
        #expect(WatchComplicationSchedule.window(.sleep, snapshot: value, from: at(24, 7), calendar: ny) == DateInterval(start: at(24, 6, 30), end: at(24, 10)), "the one going on now")
        #expect(WatchComplicationSchedule.window(.recovery, snapshot: nil, from: at(24, 12), calendar: ny) == nil)
    }

    @Test func theIPhonesWidgetsKeepTheirRelevanceAfterTheSplit() {
        let plan = sample().plan
        for hour in 0..<24 {
            let date = at(24, hour, 15)
            let combined = WidgetClock.relevance(at: date, plan: plan, calendar: ny)
            let morning = WidgetClock.morningRelevance(at: date, plan: plan, calendar: ny)
            let evening = WidgetClock.eveningRelevance(at: date, plan: plan, calendar: ny)
            #expect(combined == (morning != .idle ? morning : evening), Comment(rawValue: "\(hour):15"))
        }
        #expect(WidgetClock.relevanceWindows(plan, from: at(24, 12), calendar: ny).count == 2)
    }
}

// MARK: - The links

struct WatchLinkTests {
    @Test func eachPageHasOneShortURLAndEveryKindOpensTheMatchingPage() {
        #expect(WatchLink.allCases.map(\.rawValue) == ["recovery", "sleep", "heart", "tonight"])
        for link in WatchLink.allCases {
            #expect(link.url.absoluteString == "noctis://\(link.rawValue)" && WatchLink(url: link.url) == link)
            #expect(link.page.rawValue == link.rawValue)
        }
        #expect(WatchComplicationKind.recovery.link == .recovery && WatchComplicationKind.sleep.link == .sleep)
        #expect(WatchComplicationKind.quality.link == .sleep && WatchComplicationKind.bedtime.link == .tonight)
    }

    @Test func nothingButTheFourLinksIsAccepted() {
        let rejected = [
            "noctis://coach", "noctis://insights", "noctis://settings", "noctis://settings?section=notifications", "noctis://wind-down", "noctis://bedtime",
            "noctis://recovery?range=30d", "noctis://sleep?night=2026-09-28", "noctis://tonight?x=1", "noctis://heart?autostart=1",
            "noctis://recovery/coach", "noctis://recovery/../coach", "noctis://recovery#section", "noctis://user@recovery", "noctis://user:pw@recovery", "noctis://recovery:8080",
            "noctis:recovery", "noctis:///recovery", "noctis://", "noctis", "https://recovery", "http://noctis/recovery", "noctisx://recovery", "xnoctis://recovery",
            "noctis://%72ecovery", "noctis://recovery%00", "noctis://recovery%20", "noctis://r\u{0435}covery", "noctis://RECOVERY.evil.example", "noctis://recovery.evil.example",
            "noctis://recovery//", "noctis://recovery/x", "noctis://" + String(repeating: "a", count: 5000), "noctis://recovery?" + String(repeating: "a", count: 5000),
        ]
        for text in rejected {
            guard let url = URL(string: text) else { continue }
            #expect(WatchLink(url: url) == nil, Comment(rawValue: "\(text.prefix(60)) is accepted as a link"))
        }
    }

    @Test func caseAndATrailingSlashDoNotMatter() {
        for text in ["NOCTIS://RECOVERY", "Noctis://Sleep", "noctis://tonight/", "noctis://Heart"] {
            #expect(URL(string: text).flatMap(WatchLink.init(url:)) != nil, Comment(rawValue: text))
        }
    }

    @Test func recoveryOpensTonightInTheEveningAndTheRestKeepTheirPage() {
        #expect(content(.recovery, sample()).link == .recovery && content(.recovery, sample(), now: at(24, 21)).link == .tonight)
        #expect(content(.sleep, sample(), now: at(24, 21)).link == .sleep && content(.bedtime, sample()).link == .tonight)
    }
}

// MARK: - The words

struct WatchComplicationWordingTests {
    @Test func everySentenceIsFreeOfTheBannedLanguage() {
        var strings: [String] = WatchComplicationKind.allCases.flatMap { [$0.displayName, $0.summary, $0.cornerLabel] }
        let states: [WidgetSnapshot?] = [
            sample(), sample(.sleepOnly), sample(.learning(nightsSoFar: 3)), sample(.empty), sample(.noPermission), sample(.stale(hours: 14)), sample(.gap), sample(day: 23), nil,
        ]
        for value in states {
            for now in [at(24, 10), at(24, 21), at(25, 1)] {
                for kind in WatchComplicationKind.allCases {
                    let made = content(kind, value, now: now)
                    strings += made.rectangular.map(words) + [words(made.inline), made.accessibilityLabel, made.centerText]
                }
            }
        }
        #expect(strings.count > 400)
        for text in strings { #expect(BannedLanguage.hits(in: text, of: BannedLanguage.coach).isEmpty, Comment(rawValue: "\"\(text)\" has \(BannedLanguage.hits(in: text, of: BannedLanguage.coach))")) }
    }

    @Test func theFourKindsKeepTheirIdentifiersBecauseAFaceKeepsAComplicationByThem() {
        #expect(WatchComplicationKind.allCases.map(\.rawValue) == ["NoctisRecoveryWatch", "NoctisSleepWatch", "NoctisBedtimeWatch", "NoctisQualityWatch"])
        #expect(WatchComplicationFamily.allCases.count == 4)
    }

    @Test func noLineIsLongerThanItsFamilyHasRoomFor() {
        for kind in WatchComplicationKind.allCases {
            for value in [sample(), sample(.stale(hours: 14)), sample(.learning(nightsSoFar: 3)), sample(day: 23), nil] {
                for now in [at(24, 10), at(24, 21), at(25, 1)] {
                    let made = content(kind, value, now: now)
                    // About 28 characters inline, about 22 on a rectangular line, a handful in a circle.
                    #expect(words(made.inline).count <= 28, Comment(rawValue: "\(kind.rawValue) inline: \(words(made.inline))"))
                    for line in made.rectangular { #expect(words(line).count <= 24, Comment(rawValue: "\(kind.rawValue) line: \(words(line))")) }
                    #expect(made.centerText.count <= 5, Comment(rawValue: "\(kind.rawValue) center: \(made.centerText)"))
                }
            }
        }
    }
}
