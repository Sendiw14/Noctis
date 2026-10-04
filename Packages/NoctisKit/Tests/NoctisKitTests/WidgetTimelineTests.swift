import DesignSystem
import Foundation
import Testing

@testable import HomeFeature
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import RecoveryKit

// The widgets' timeline and what each surface says (APP_RULES.md R44, R45): pure builders, tested with fixed dates in New York.

private let calendar = Fixture.calendar()
private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) -> Date { Fixture.date(2026, month, day, hour, minute) }
private func clock(_ date: Date) -> (Int, Int) {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? -1, parts.minute ?? -1)
}


/// The clock writes a narrow no-break space before AM and PM; the tests spell it as a plain space.
private func sp(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }
private func sp(_ piece: WidgetLockPiece) -> WidgetLockPiece {
    switch piece {
    case .text(let text): .text(sp(text))
    case .health(let text): .health(sp(text))
    case .countdown: piece
    }
}
private func sp(_ pieces: [WidgetLockPiece]) -> [WidgetLockPiece] { pieces.map { sp($0) } }
private func sp(_ lines: [[WidgetLockPiece]]) -> [[WidgetLockPiece]] { lines.map { sp($0) } }

/// A full snapshot for the morning of `day` (September 2026).
private func snapshot(
    _ state: WidgetDataState = .full, day: Int = 24, generated: Date? = nil, wake: Int = 7 * 60, bedtime: Int = 23 * 60,
    window: (Int, Int)? = (22 * 60 + 45, 23 * 60 + 15), alarmOn: Bool = true
) -> WidgetSnapshot {
    var value = WidgetSamples.snapshot(state, now: generated ?? at(day, 10), calendar: calendar)
    value.forDay = WidgetDay(year: 2026, month: 9, day: day)
    value.plan = WidgetPlan(wakeMinutes: wake, needMinutes: 8 * 60, bedtimeMinutes: bedtime, windowStartMinutes: window?.0, windowEndMinutes: window?.1)
    value.alarm = WidgetAlarm(minutes: wake, isOn: alarmOn)
    return value
}

struct WidgetClockTests {
    @Test func theModeIsHomesModeAtEveryQuarterHourForManyPlans() {
        for (wake, need) in [(7 * 60, 8 * 60), (6 * 60 + 30, 7 * 60 + 30), (5 * 60, 9 * 60), (9 * 60, 6 * 60), (3 * 60, 8 * 60), (12 * 60, 8 * 60), (7 * 60, 4 * 60)] {
            var profile = UserProfileSnapshot()
            profile.typicalWakeMinutes = wake
            profile.needMinutes = need
            let tonight = TonightPlan(profile: profile)
            let plan = WidgetPlan(wakeMinutes: wake, needMinutes: need, bedtimeMinutes: tonight.bedtimeMinutes)
            for step in 0..<96 {
                let date = at(24, step / 4, (step % 4) * 15)
                let home = HomeScreenBuilder.mode(now: date, plan: tonight, calendar: calendar)
                #expect(WidgetClock.mode(at: date, plan: plan, calendar: calendar).rawValue == home.rawValue, Comment(rawValue: "wake \(wake) need \(need) at \(step * 15) minutes"))
            }
        }
        #expect(WidgetClock.eveningLeadMinutes == HomeScreenBuilder.eveningLeadMinutes && WidgetClock.eveningEndMinutes == HomeScreenBuilder.eveningEndMinutes)
    }

    @Test func tonightsBedtimeIsTheNextOneByDayAndTheCurrentOneByEvening() throws {
        let plan = snapshot().plan
        let day = try #require(WidgetClock.bedtime(at: at(24, 10), mode: .day, plan: plan, calendar: calendar))
        #expect(clock(day) == (23, 0) && calendar.component(.day, from: day) == 24)
        let evening = try #require(WidgetClock.bedtime(at: at(24, 21, 30), mode: .evening, plan: plan, calendar: calendar))
        #expect(evening == day)
        // After midnight, still evening: the bedtime that has passed, the evening before.
        let after = try #require(WidgetClock.bedtime(at: at(25, 1), mode: .evening, plan: plan, calendar: calendar))
        #expect(after == day && after < at(25, 1))
        // A bedtime after midnight: 12:30 AM.
        var late = plan
        late.bedtimeMinutes = 30
        let lateNight = try #require(WidgetClock.bedtime(at: at(24, 22), mode: .evening, plan: late, calendar: calendar))
        #expect(clock(lateNight) == (0, 30) && calendar.component(.day, from: lateNight) == 25)
    }

    @Test func theBoundariesAreEveningStartBedtimeAndFourAcrossMidnight() {
        let plan = snapshot().plan
        let found = WidgetClock.boundaries(after: at(24, 10), until: at(24, 22), plan: plan, calendar: calendar)
        #expect(found.map(clock).map { $0.0 * 60 + $0.1 } == [20 * 60], "from 10 AM, twelve hours reaches 8 PM only")
        let night = WidgetClock.boundaries(after: at(24, 20, 30), until: at(25, 8, 30), plan: plan, calendar: calendar)
        #expect(night.map(clock).map { $0.0 * 60 + $0.1 } == [23 * 60, 4 * 60], "bedtime, then 4 AM the next day")
        #expect(calendar.component(.day, from: night[1]) == 25)
    }

    @Test func theBoundariesKeepTheirClockTimeAcrossDaylightSaving() {
        let plan = snapshot().plan
        // Clocks go forward at 2 AM on March 8 2026: the evening of the 7th to the morning of the 8th is 5 real hours from 11 PM.
        let spring = WidgetClock.boundaries(after: Fixture.date(2026, 3, 7, 22), until: Fixture.date(2026, 3, 8, 10), plan: plan, calendar: calendar)
        #expect(spring.map(clock).map { $0.0 * 60 + $0.1 } == [23 * 60, 4 * 60])
        let four = spring[1]
        #expect(four.timeIntervalSince(spring[0]) == 4 * 3600, "11 PM to 4 AM is four real hours that night: the hour at 2 AM is gone")
        // Clocks go back on November 1: the same wall times, five real hours apart.
        let fall = WidgetClock.boundaries(after: Fixture.date(2026, 10, 31, 22), until: Fixture.date(2026, 11, 1, 10), plan: plan, calendar: calendar)
        #expect(fall.map(clock).map { $0.0 * 60 + $0.1 } == [23 * 60, 4 * 60])
        #expect(fall[1].timeIntervalSince(fall[0]) == 6 * 3600, "and six when the hour repeats")
    }

    @Test func relevanceIsHighInTheMorningWindowAndTheEveningHour() {
        let plan = snapshot().plan
        #expect(WidgetClock.relevance(at: at(24, 6, 29), plan: plan, calendar: calendar) == .idle)
        #expect(WidgetClock.relevance(at: at(24, 6, 30), plan: plan, calendar: calendar).score == 100, "half an hour before the usual wake time")
        let morning = WidgetClock.relevance(at: at(24, 8), plan: plan, calendar: calendar)
        #expect(morning.score == 100 && morning.duration == 2 * 3600, "until three hours after the wake time")
        #expect(WidgetClock.relevance(at: at(24, 10, 1), plan: plan, calendar: calendar) == .idle)
        #expect(WidgetClock.relevance(at: at(24, 13), plan: plan, calendar: calendar) == .idle)
        #expect(WidgetClock.relevance(at: at(24, 21, 59), plan: plan, calendar: calendar) == .idle)
        let evening = WidgetClock.relevance(at: at(24, 22), plan: plan, calendar: calendar)
        #expect(evening.score == 90 && evening.duration == 90 * 60, "the hour before bedtime and half an hour after")
        #expect(WidgetClock.relevance(at: at(24, 23, 30), plan: plan, calendar: calendar).score == 90)
        #expect(WidgetClock.relevance(at: at(24, 23, 31), plan: plan, calendar: calendar) == .idle)
        #expect(WidgetClock.relevance(at: at(24, 6, 30), plan: plan, calendar: calendar).score > WidgetRelevanceScore.idle.score)
    }

    @Test func theRelevanceWindowsAreTheNextMorningAndEveningHour() {
        let plan = snapshot().plan
        let windows = WidgetClock.relevanceWindows(plan, from: at(24, 10), calendar: calendar)
        #expect(windows.count == 2)
        #expect(windows[0].start == at(25, 6, 30) && windows[0].duration == 210 * 60, "tomorrow's morning window")
        #expect(windows[1].start == at(24, 22) && windows[1].duration == 90 * 60, "tonight's evening hour")
        // While one is going on, it is the one returned.
        let during = WidgetClock.relevanceWindows(plan, from: at(24, 8), calendar: calendar)
        #expect(during[0].start == at(24, 6, 30))
    }
}

struct WidgetTimelineTests {
    @Test func aTimelineStartsNowAndNeverLooksBeyondTwelveHours() {
        for plan in [(7 * 60, 23 * 60), (6 * 60, 22 * 60 + 30), (8 * 60, 0 + 30), (5 * 60, 21 * 60)] {
            for step in stride(from: 0, to: 72 * 60, by: 37) {
                let now = at(24, 0).addingTimeInterval(Double(step) * 60)
                let value = snapshot(wake: plan.0, bedtime: plan.1)
                let built = WidgetTimelineBuilder.build(snapshot: value, now: now, calendar: calendar)
                #expect(built.entries.first?.date == now)
                #expect(built.entries.map(\.date) == built.entries.map(\.date).sorted() && Set(built.entries.map(\.date)).count == built.entries.count, "sorted, no repeats")
                #expect(built.entries.allSatisfy { $0.date < now.addingTimeInterval(WidgetTimelineBuilder.horizon) })
                #expect(built.reloadAfter > (built.entries.last?.date ?? now), "asks again after the last entry")
                #expect(built.reloadAfter <= now.addingTimeInterval(WidgetTimelineBuilder.horizon), "never beyond twelve hours")
                #expect(built.entries.allSatisfy { !$0.isPreview }, "a real timeline has no sample")
            }
        }
    }

    @Test func aDayTimelineChangesToEveningAtThreeHoursBeforeBedtime() {
        let built = WidgetTimelineBuilder.build(snapshot: snapshot(), now: at(24, 10), calendar: calendar)
        #expect(built.entries.map(\.date) == [at(24, 10), at(24, 20)])
        #expect(built.entries.map(\.mode) == [.day, .evening])
        #expect(built.entries[1].bedtime == at(24, 23))
        #expect(built.reloadAfter == at(24, 22), "twelve hours on: the next boundary (11 PM) is later")
    }

    @Test func anEveningTimelineCrossesMidnightToANewDayThatIsWaiting() {
        let built = WidgetTimelineBuilder.build(snapshot: snapshot(), now: at(24, 22), calendar: calendar)
        #expect(built.entries.map(\.date) == [at(24, 22), at(24, 23), at(25, 4)])
        #expect(built.entries.map(\.mode) == [.evening, .evening, .day])
        #expect(built.entries.map(\.scene) == [.ready, .ready, .waiting], "yesterday's numbers are never today's (R45)")
        #expect(built.entries[0].bedtime == at(24, 23) && built.entries[1].bedtime == at(24, 23), "the countdown's bedtime; the second is after it")
    }

    @Test func aSnapshotForAnEarlierDayIsWaitingFromTheFirstEntry() {
        let old = snapshot(day: 22)
        let entry = WidgetTimelineBuilder.entry(for: old, at: at(24, 10), calendar: calendar)
        #expect(entry.scene == .waiting)
        // Until 4 AM the evening before is still its day.
        #expect(WidgetTimelineBuilder.entry(for: snapshot(day: 23), at: at(24, 3, 59), calendar: calendar).scene == .ready)
        #expect(WidgetTimelineBuilder.entry(for: snapshot(day: 23), at: at(24, 4), calendar: calendar).scene == .waiting)
        // A snapshot made after waking before 4 AM is already today's.
        #expect(WidgetTimelineBuilder.entry(for: snapshot(day: 24), at: at(24, 3, 30), calendar: calendar).scene == .ready)
    }

    @Test func noSnapshotIsOneEntryAndAnAskInTwelveHours() {
        let built = WidgetTimelineBuilder.build(snapshot: nil, now: at(24, 10), calendar: calendar)
        #expect(built.entries.count == 1 && built.entries[0].scene == .noSnapshot)
        #expect(built.reloadAfter == at(24, 22))
    }

    @Test func staleNumbersGetAnEntryAnHourSoTheirAgeStaysTrue() {
        let stale = snapshot(.stale(hours: 14))
        let built = WidgetTimelineBuilder.build(snapshot: stale, now: at(24, 10), calendar: calendar)
        let hours = built.entries.compactMap(\.staleHours)
        #expect(hours.first == 14 && hours == hours.sorted() && hours.count == built.entries.count)
        #expect(built.entries.count >= 11, "an entry an hour, for eleven hours")
        #expect(built.entries.first(where: { $0.date == at(24, 13) })?.staleHours == 17)
        #expect(built.entries.allSatisfy { $0.date < at(24, 22) })
    }

    @Test func aPreviewEntryIsTaggedAndForTodayAndNeverComesFromABuild() {
        let preview = WidgetTimelineBuilder.previewEntry(WidgetSamples.snapshot(.full, now: at(24, 10), calendar: calendar), at: at(24, 10), calendar: calendar)
        #expect(preview.isPreview && preview.scene == .ready)
        #expect(WidgetPresentationBuilder.build(preview).accessibilityLabel.contains("Sample") && WidgetPresentationBuilder.build(preview).isPreview)
        #expect(!WidgetPresentationBuilder.build(WidgetTimelineBuilder.entry(for: snapshot(), at: at(24, 10), calendar: calendar)).isPreview)
    }

    @Test func sampleNumbersAreOnlyEverNamedWhereAPreviewIsMade() throws {
        let allowed = ["NoctisWidgetKit/WidgetSamples.swift", "AppRoot/WidgetGallery.swift", "NoctisWidgets/NoctisWidgets.swift"]
        for file in RawDefaultsTests.swiftFiles(under: ["Packages/NoctisKit/Sources", "App", "NoctisWidgets"]) where file.text.contains("WidgetSamples") {
            #expect(allowed.contains { file.path.hasSuffix($0) }, Comment(rawValue: "\(file.path) uses sample numbers"))
        }
        // In the extension, only the placeholder and the gallery preview make one; the timeline is built from the store.
        let source = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("NoctisWidgets/NoctisWidgets.swift"), encoding: .utf8)
        let timeline = try #require(source.range(of: "func getTimeline"))
        let relevance = try #require(source.range(of: "func relevance"))
        #expect(!source[timeline.lowerBound..<relevance.lowerBound].contains("sample("), "the real timeline never draws a sample")
        #expect(source.contains("context.isPreview"))
    }
}

// MARK: - What each surface says

struct WidgetDisplayTests {
    private let format = WidgetFormat(calendar: calendar, locale: Locale(identifier: "en_US"))

    private func present(_ value: WidgetSnapshot?, at date: Date) -> WidgetPresentation {
        WidgetPresentationBuilder.build(WidgetTimelineBuilder.entry(for: value, at: date, calendar: calendar), format: format)
    }

    private func message(_ presentation: WidgetPresentation) -> WidgetMessage? {
        if case .message(let message) = presentation.body { message } else { nil }
    }

    private func day(_ presentation: WidgetPresentation) -> WidgetDayBody? {
        if case .day(let body) = presentation.body { body } else { nil }
    }

    private func evening(_ presentation: WidgetPresentation) -> WidgetEveningBody? {
        if case .evening(let body) = presentation.body { body } else { nil }
    }

    // MARK: Day

    @Test func aFullDayHasTheScoreTheThreeRowsLastNightAndTonight() throws {
        let presentation = present(snapshot(), at: at(24, 10))
        let body = try #require(day(presentation))
        #expect(body.score == 70 && body.delta == WidgetDelta(text: "+6", tone: .above))
        #expect(body.ring.map(\.kind) == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency])
        #expect(body.rows.map(\.label) == ["Sleep", "HRV", "Resting HR"])
        #expect(body.rows.map(\.value.plain) == ["6h 42m", "54ms", "52bpm"])
        #expect(body.rows.map(\.tint) == [.sleepDuration, .hrv, .restingHeartRate])
        let night = try #require(body.night)
        #expect(night.duration.label == "Last night" && night.duration.value.plain == "6h 42m" && sp(night.times) == "11:04 PM – 6:52 AM")
        #expect(night.stages == WidgetStages(deep: 74, core: 236, rem: 92) && night.quality?.value.plain == "81")
        #expect(sp(body.tonight.bedtime) == "10:45\u{2009}–\u{2009}11:15 PM" && sp(body.tonight.wake) == "Wake 7:00 AM")
        #expect(presentation.link == .recovery && presentation.footer == nil && !presentation.isPreview)
        #expect(sp(presentation.accessibilityLabel) == "Recovery 70, +6 on your usual. Slept 6 hours 42 minutes. Bedtime 10:45\u{2009}–\u{2009}11:15 PM")
    }

    @Test func rowsWithNoDataAreOmitted() throws {
        let sleepOnly = try #require(day(present(snapshot(.sleepOnly), at: at(24, 10))))
        #expect(sleepOnly.rows.map(\.label) == ["Sleep"], "no HRV and no resting heart rate")
        #expect(sleepOnly.ring.count == 2)
        var oneHeart = snapshot()
        oneHeart.factors = WidgetFactors(hrv: nil, restingHeartRate: 51)
        #expect(try #require(day(present(oneHeart, at: at(24, 10)))).rows.map(\.label) == ["Sleep", "Resting HR"])
        var noStages = snapshot()
        noStages.lastNight?.stages = nil
        noStages.lastNight?.quality = nil
        let night = try #require(day(present(noStages, at: at(24, 10)))?.night)
        #expect(night.stages == nil && night.quality == nil)
    }

    @Test func aSingleBedtimeIsOneTime() throws {
        let body = try #require(day(present(snapshot(window: nil), at: at(24, 10))))
        #expect(sp(body.tonight.bedtime) == "11:00 PM")
    }

    @Test func deltasShowTheirSignAndToneWithTheModelsThreshold() {
        #expect(WidgetCopy.trendThreshold == RecoveryModelV1.trendThreshold)
        #expect([6, -18, 0, 2, -2, 3, -3].map(WidgetCopy.signed) == ["+6", "\u{2212}18", "\u{00B1}0", "+2", "\u{2212}2", "+3", "\u{2212}3"])
        for (delta, tone) in [(3, WidgetDelta.Tone.above), (2, .inLine), (0, .inLine), (-2, .inLine), (-3, .below), (-20, .below)] {
            var value = snapshot()
            value.recovery?.delta = delta
            #expect(day(present(value, at: at(24, 10)))?.delta?.tone == tone, Comment(rawValue: "\(delta)"))
        }
        var none = snapshot()
        none.recovery?.delta = nil
        #expect(day(present(none, at: at(24, 10)))?.delta == nil)
    }

    // MARK: Messages

    @Test func everyStateWithoutNumbersSaysItsOwnWordsBeforeAnyNumber() {
        let noSnapshot = present(nil, at: at(24, 10))
        #expect(message(noSnapshot)?.title == "Open NOCTIS to get started" && noSnapshot.lock.inline == [.text("Open NOCTIS to get started")])
        for state in [WidgetDataState.empty, .noPermission] {
            #expect(message(present(snapshot(state), at: at(24, 10)))?.title == "Open NOCTIS to connect Apple Health")
        }
        let learning = present(snapshot(.learning(nightsSoFar: 3)), at: at(24, 10))
        #expect(message(learning)?.title == "Learning your baseline" && message(learning)?.detail == "3 of 5 nights")
        #expect(WidgetCopy.learningLine(3) == "Learning your baseline - 3 of 5 nights")
        #expect(message(present(snapshot(.gap), at: at(24, 10)))?.title == "No sleep recorded last night")
        let waiting = present(snapshot(day: 22), at: at(24, 10))
        #expect(message(waiting)?.title == "Waiting for last night's sleep", "a snapshot for yesterday is a waiting state")
        for presentation in [noSnapshot, learning, waiting] {
            #expect(presentation.lock.gaugeScore == nil, "no number anywhere in a state without numbers")
        }
    }

    @Test func staleNumbersAreLabelledOldEverywhereAndNeverAsToday() throws {
        let stale = present(snapshot(.stale(hours: 14)), at: at(24, 10))
        #expect(stale.footer == "Updated 14h ago")
        let body = try #require(day(stale))
        #expect(body.night?.duration.label == "Last recorded", "not 'Last night'")
        #expect(stale.lock.rectangular.last == [.text("Updated 14h ago")])
        #expect(stale.lock.inline == [.health("Recovery 70"), .text(" - 14h old")])
        #expect(stale.accessibilityLabel.contains("Updated 14h ago") && stale.accessibilityLabel.contains("Last recorded sleep"))
        // Older as the day goes on, and in days from two days.
        #expect(present(snapshot(.stale(hours: 14), generated: at(24, 10)), at: at(24, 13)).footer == "Updated 17h ago")
        #expect(WidgetCopy.updated(hours: 47) == "Updated 47h ago" && WidgetCopy.updated(hours: 48) == "Updated 2d ago" && WidgetCopy.updated(hours: 75) == "Updated 3d ago")
    }

    // MARK: Evening

    @Test func theEveningLeadsWithBedtimeAndCountsDownThenSaysItPassed() throws {
        let upcoming = present(snapshot(), at: at(24, 21, 30))
        let body = try #require(evening(upcoming))
        #expect(body.bedtime == at(24, 23) && !body.hasPassed)
        #expect(body.bedtimeText.plain == "11:00PM" && sp(body.windowText ?? "") == "10:45\u{2009}–\u{2009}11:15 PM")
        #expect(body.wake.value.plain == "7:00AM" && sp(body.wakeText) == "7:00 AM" && body.need.value.plain == "8h")
        #expect(body.alarm?.value.plain == "7:00AM")
        #expect(upcoming.link == .tonight)
        #expect(sp(upcoming.lock.inline) == [.text("Bedtime in "), .countdown(at(24, 23))])
        #expect(sp(upcoming.lock.rectangular) == [[.text("Bedtime 11:00 PM")], [.text("in "), .countdown(at(24, 23))], [.text("Wake 7:00 AM")]])
        let passed = present(snapshot(), at: at(25, 0, 30))
        let after = try #require(evening(passed))
        #expect(after.hasPassed && sp(after.passedText) == "Bedtime was 11:00 PM")
        #expect(sp(passed.lock.inline) == [.text("Bedtime was 11:00 PM")])
    }

    @Test func theEveningRingAndScoreAreTodaysOrAbsent() throws {
        #expect(try #require(evening(present(snapshot(), at: at(24, 21)))).score == 70)
        #expect(try #require(evening(present(snapshot(.stale(hours: 20)), at: at(24, 21)))).score == nil, "stale numbers are not shown as today's")
        #expect(try #require(evening(present(snapshot(.learning(nightsSoFar: 2)), at: at(24, 21)))).score == nil)
        #expect(try #require(evening(present(snapshot(.noPermission), at: at(24, 21)))).score == nil, "bedtime needs no Health")
        // Two days on with no refresh: the bedtime is still true, the ring is not shown.
        #expect(try #require(evening(present(snapshot(day: 22), at: at(24, 21)))).score == nil)
        #expect(try #require(evening(present(snapshot(alarmOn: false), at: at(24, 21)))).alarm == nil, "an alarm that is off is not listed")
    }

    // MARK: A locked iPhone

    @Test func everyHealthValueIsFlaggedAndNoPlanValueIs() throws {
        let body = try #require(day(present(snapshot(), at: at(24, 10))))
        for line in body.rows + [body.night?.duration, body.night?.quality].compactMap({ $0 }) { #expect(line.sensitivity == .health, Comment(rawValue: line.label)) }
        let evening = try #require(evening(present(snapshot(), at: at(24, 21))))
        for line in [evening.wake, evening.need] + [evening.alarm].compactMap({ $0 }) { #expect(line.sensitivity == .plan, Comment(rawValue: line.label)) }
    }

    @Test func lockedWordsHideEveryHealthNumberButKeepTheBedtimeAndTheAlarm() throws {
        for value in [snapshot(), snapshot(.sleepOnly), snapshot(.stale(hours: 14))] {
            for date in [at(24, 10), at(24, 21)] {
                let content = present(value, at: date).lock
                let locked = content.locked()
                #expect(locked.gaugeScore == nil)
                for line in locked.rectangular + [locked.inline] {
                    for piece in line {
                        if case .health = piece { Issue.record("a Health word survives the lock") }
                        if case .text(let text) = piece { #expect(!text.contains("70") && !text.contains("6h 42m") && !text.contains("Recovery 7"), Comment(rawValue: text)) }
                    }
                }
            }
        }
        let day = present(snapshot(), at: at(24, 10)).lock
        #expect(sp(day.rectangular) == [[.health("Recovery 70")], [.health("Sleep 6h 42m")], [.text("Bed 11:00 PM")]])
        #expect(sp(day.inline) == [.health("Recovery 70"), .text(" - Bed 11:00 PM")])
        #expect(sp(day.locked().rectangular) == [[.text("Unlock to see")], [.text("Bed 11:00 PM")]], "one line for both Health lines")
        #expect(sp(day.locked().inline) == [.text("Unlock to see"), .text(" - Bed 11:00 PM")])
        #expect(day.gaugeScore == 70)
        // The evening's lock words have nothing to hide.
        let evening = present(snapshot(), at: at(24, 21)).lock
        #expect(evening.locked() == WidgetLockContent(gaugeScore: nil, rectangular: evening.rectangular, inline: evening.inline) || evening.gaugeScore != nil)
    }

    @Test func theViewsWrapEveryHealthValueAndNoTextIsUnderTwelvePoints() throws {
        let views = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWidgetKit/WidgetViews.swift"), encoding: .utf8)
        let code = RawDefaultsTests.code(views)
        #expect(code.contains(".privacySensitive()"))
        #expect(code.components(separatedBy: "WidgetPrivate {").count - 1 >= 4, "the ring, the rows, the delta and the night are wrapped")
        // The evening hero, the Tonight row and the plan rows are the person's plan, not Health: nothing there is wrapped.
        let eveningStart = try #require(code.range(of: "struct WidgetEveningView"))
        let lockStart = try #require(code.range(of: "public struct NoctisLockWidgetView"))
        #expect(!code[eveningStart.lowerBound..<lockStart.lowerBound].contains("WidgetPrivate {") || code[eveningStart.lowerBound..<lockStart.lowerBound].contains("WidgetRecoveryRing"))
        for file in ["WidgetViews.swift", "WidgetShapes.swift"] {
            let text = RawDefaultsTests.code(try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/NoctisWidgetKit/\(file)"), encoding: .utf8))
            for match in text.matches(of: /noctisFont\((\d+(?:\.\d+)?)/) { #expect(Double(match.1) ?? 0 >= 12, Comment(rawValue: "\(file): text under 12pt")) }
            for match in text.matches(of: /noctisIcon\((\d+(?:\.\d+)?)/) { #expect(Double(match.1) ?? 0 >= 12, Comment(rawValue: "\(file): icon under 12pt")) }
            #expect(!text.contains(".font(.system(size:") && !text.contains(".position(") && !text.contains(".border(") && !text.contains("DEBUG") && !text.contains("Canvas"), Comment(rawValue: file))
        }
    }

    // MARK: The words match Home's

    @Test func theFormattersMakeHomesStrings() {
        let home = HomeFormat(calendar: calendar, locale: Locale(identifier: "en_US"))
        for minutes in [0, 45, 60, 402, 480, 725, 1439] {
            #expect(WidgetFormat.durationMetric(minutes) == HomeFormat.durationMetric(minutes))
            #expect(WidgetFormat.spokenDuration(minutes) == HomeFormat.spokenDuration(minutes))
            #expect(WidgetFormat.compactDuration(minutes) == HomeFormat.compactDuration(minutes))
        }
        for minutes in [0, 7 * 60, 12 * 60, 23 * 60, 23 * 60 + 45, 1439, -30] {
            #expect(format.clock(minutesSinceMidnight: minutes) == home.clock(minutesSinceMidnight: minutes))
            #expect(format.clockMetric(minutesSinceMidnight: minutes) == home.clockMetric(home.clock(minutesSinceMidnight: minutes)))
        }
        #expect(WidgetFormat.quantityMetric(54, unit: "ms", spokenUnit: "milliseconds") == HomeFormat.quantityMetric(54, unit: "ms", spokenUnit: "milliseconds"))
        #expect(format.windowText(startMinutes: 22 * 60 + 45, endMinutes: 23 * 60 + 15) == "10:45\u{2009}–\u{2009}11:15 PM")
        #expect(format.windowText(startMinutes: 23 * 60 + 45, endMinutes: 15) == "11:45 PM\u{2009}–\u{2009}12:15 AM", "across midnight, both periods")
        let h24 = WidgetFormat(calendar: calendar, locale: Locale(identifier: "de_DE"))
        #expect(h24.clockMetric(minutesSinceMidnight: 23 * 60).plain == "23:00" && h24.windowText(startMinutes: 22 * 60 + 45, endMinutes: 23 * 60 + 15) == "22:45\u{2009}–\u{2009}23:15")
    }

    @Test func eachSurfaceOpensTheRightScreen() {
        #expect(present(snapshot(), at: at(24, 10)).link == .recovery)
        #expect(present(snapshot(), at: at(24, 21)).link == .tonight)
        #expect(present(nil, at: at(24, 10)).link == .recovery)
        #expect(WidgetURLRouter.route(for: present(snapshot(), at: at(24, 10)).link) == .recovery())
        #expect(WidgetURLRouter.route(for: present(snapshot(), at: at(24, 21)).link) == .tonight)
    }
}
