import DesignSystem
import Foundation
import SwiftData
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import NightFeature
@testable import NightKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepKit

/// A clock string with its no-break spaces made plain, to compare with what is written here.
private nonisolated func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

private let tonightFormat = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))

/// An evening in New York: Thursday, September 24, 2026, 8 PM.
private let tonightNow = Fixture.date(2026, 9, 24, 20)

// MARK: - Routes

@MainActor
struct TonightRouteTests {
    private func makeModel() throws -> AppModel {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
    }

    @Test func theNightRoutesHaveURLsAndNames() throws {
        #expect(AppRoute.tonight.url.absoluteString == "noctis://tonight")
        #expect(AppRoute.windDown().url.absoluteString == "noctis://wind-down")
        #expect(AppRoute.windDown(autostart: true).url.absoluteString == "noctis://wind-down?autostart=1")
        #expect(AppRoute.sounds.url.absoluteString == "noctis://sounds")
        #expect(AppRoute.alarm.url.absoluteString == "noctis://alarm")
        #expect(AppRoute(url: try #require(URL(string: "noctis://wind-down?autostart=1"))) == .windDown(autostart: true))
        #expect(AppRoute(url: try #require(URL(string: "noctis://wind-down?autostart=0"))) == .windDown(autostart: false))
        #expect(AppRoute(url: try #require(URL(string: "noctis://wind-down"))) == .windDown(autostart: false))
        #expect(AppRoute(url: try #require(URL(string: "noctis://tonight?autostart=1"))) == .tonight)
    }

    @Test func theNightRoutesAreReadFromLaunchNames() {
        #expect(AppRoute(name: "tonight") == .tonight)
        #expect(AppRoute(name: "wind-down") == .windDown(autostart: false))
        #expect(AppRoute(name: "winddown") == .windDown(autostart: false))
        #expect(AppRoute(name: "winddown:autostart") == .windDown(autostart: true))
        #expect(AppRoute(name: "sounds") == .sounds)
        #expect(AppRoute(name: "alarm") == .alarm)
    }

    @Test func theyAllLiveOnHome() {
        for route in [AppRoute.tonight, .windDown(), .windDown(autostart: true), .sounds, .alarm] {
            #expect(route.tab == .home)
        }
    }

    @Test func tonightOpensOverHome() throws {
        let model = try makeModel()
        model.selectedTab = .coach
        model.open(.tonight)
        #expect(model.selectedTab == .home)
        #expect(model.homePath == [.tonight])
        model.open(.home)
        #expect(model.homePath.isEmpty)
    }

    @Test func windDownAndSoundsOpenOverTonight() throws {
        let model = try makeModel()
        model.open(.windDown(autostart: true))
        #expect(model.homePath == [.tonight, .windDown(autostart: true)])
        model.open(.windDown(autostart: false))
        #expect(model.homePath == [.tonight, .windDown(autostart: false)])
        model.open(.sounds)
        #expect(model.homePath == [.tonight, .sounds])
    }

    @Test func theAlarmOpensTonightAndAsksForItsSheetOnce() throws {
        let model = try makeModel()
        model.open(.alarm)
        #expect(model.homePath == [.tonight])
        #expect(model.takeAlarmDestination() != nil)
        #expect(model.takeAlarmDestination() == nil)
        model.open(.alarm)
        #expect(model.takeAlarmDestination() != nil)
    }

    @Test func theEveningNotificationOpensWindDownWithoutStartingIt() {
        #expect(NoctisNotification.route(for: "noctis.notification.windDown") == .windDown(autostart: false))
        #expect(NoctisNotification.route(for: NoctisNotification.windDown) == .windDown(autostart: false))
        #expect(NoctisNotification.route(for: NoctisNotification.morningSummary) == nil)
        #expect(NoctisNotification.route(for: NoctisNotification.weeklyReview) == nil)
        #expect(NoctisNotification.route(for: "noctis.notification.trialEnding") == nil)
        #expect(NoctisNotification.route(for: "somebody.else") == nil)
    }
}

// MARK: - The words of Tonight

struct TonightBuilderTests {
    private func recommend(
        wake: Int = clock(7), need: Int = clock(8), balance: Double? = nil, usual: Int? = nil, spread: Double? = nil, nights: Int = 14, change: Int = 0
    ) -> BedtimeRecommendation {
        BedtimeRecommendationEngine.recommend(
            BedtimeInputs(wakeMinutes: wake, needMinutes: need, balanceMinutes: balance, usualBedtimeMinutes: usual, bedtimeSpreadMinutes: spread, nights: nights, clockChangeMinutes: change)
        )
    }

    private func content(_ recommendation: BedtimeRecommendation) -> TonightContent {
        TonightBuilder.content(for: recommendation, now: tonightNow, timeZone: Fixture.newYork, format: tonightFormat)
    }

    @Test func aWindowIsSaidAsOne() {
        let c = content(recommend())
        #expect(plain(c.summary) == "Bedtime window 10:45 – 11:15 PM")
        #expect(c.isWindow)
        #expect(c.heroCaption == "BEDTIME WINDOW")
        #expect(plain(c.hero.plain) == "10:45 – 11:15PM")
        #expect(plain(c.hero.spoken) == "10:45 to 11:15 PM")
        #expect(plain(c.wakeLine) == "Wake 7:00 AM · 8h need")
        #expect(c.note == nil)
        #expect(c.dateCaption == "THURSDAY, SEPTEMBER 24")
    }

    @Test func aWindowAcrossNoonOrMidnightNamesBothPeriods() {
        let c = content(recommend(wake: clock(8, 5)))
        #expect(plain(c.summary) == "Bedtime window 11:50 PM – 12:20 AM")
        #expect(plain(c.hero.plain) == "11:50PM – 12:20AM")
        #expect(plain(c.hero.spoken) == "11:50 PM to 12:20 AM")
    }

    @Test func aSingleBedtimeIsAStartingPoint() {
        let c = content(recommend(nights: 3))
        #expect(plain(c.summary) == "Bedtime around 11:00 PM")
        #expect(!c.isWindow)
        #expect(c.heroCaption == "BEDTIME")
        #expect(plain(c.hero.plain) == "11:00PM")
        #expect(c.note == "A starting point. We're still learning your pattern.")
        #expect(c.confidence == nil)
        #expect(c.reasons.map { $0.kind } == [.sleepNeed, .wakeTime])
    }

    @Test func theConfidenceLineSaysWhatItRestsOn() {
        #expect(content(recommend(balance: -10, usual: clock(23), nights: 14)).confidence == "High confidence · built on 14 nights of your own sleep")
        #expect(content(recommend(balance: -10, usual: clock(23), nights: 12)).confidence == "Moderate confidence · built on 12 nights of your own sleep")
        #expect(content(recommend(nights: 9)).confidence == "Low confidence · it firms up as more nights arrive")
    }

    @Test func theStripRunsFromSixInTheEveningToTenInTheMorning() {
        let strip = content(recommend()).strip
        #expect(strip.windowStart == Double(clock(22, 45) - clock(18)) / 960)
        #expect(strip.windowEnd == Double(clock(23, 15) - clock(18)) / 960)
        #expect(strip.wake == Double(clock(7) + 1440 - clock(18)) / 960)
        #expect(strip.labels.map { plain($0.text) } == ["6 PM", "10 PM", "2 AM", "6 AM", "10 AM"])
        #expect(strip.labels.map { $0.position } == [0, 0.25, 0.5, 0.75, 1])
        #expect(strip.windowStart < strip.windowEnd && strip.windowEnd < strip.wake)
    }

    @Test func theStripFollowsAWindowAcrossMidnight() {
        let strip = content(recommend(wake: clock(8, 5))).strip
        #expect(strip.windowStart < strip.windowEnd)
        #expect(strip.windowStart == Double(clock(23, 50) - clock(18)) / 960)
        #expect(strip.windowEnd == Double(clock(0, 20) + 1440 - clock(18)) / 960)
    }

    @Test func aSingleBedtimeIsAPointOnTheStrip() {
        let strip = content(recommend(nights: 2)).strip
        #expect(strip.windowStart == strip.windowEnd)
    }

    @Test func everyFactIsARowWithItsValue() {
        let rows = content(recommend(balance: -70, usual: clock(23, 14), spread: 38)).reasons
        #expect(rows.map { $0.label } == ["Sleep need", "Wake time", "Usual bedtime", "Last 7 nights", "Bedtime consistency"])
        #expect(plain(rows[0].value.plain) == "8h")
        #expect(plain(rows[1].value.plain) == "7:00AM")
        #expect(plain(rows[2].value.plain) == "11:14PM")
        #expect(rows[3].value.plain == "1h 10m behind")
        #expect(rows[3].value.spoken == "1 hour 10 minutes behind")
        #expect(rows[3].detail == "Moved 20 min earlier to catch up.")
        #expect(rows[4].value.plain == "38m")
    }

    @Test func theBalanceIsBehindAheadOrEven() {
        func balanceRow(_ balance: Double) -> TonightReasonRow? {
            content(recommend(balance: balance)).reasons.first { $0.kind == .balance }
        }
        #expect(balanceRow(40)?.value.plain == "40m ahead")
        #expect(balanceRow(40)?.detail == nil)
        #expect(balanceRow(-30)?.value.plain == "30m behind")
        #expect(balanceRow(-30)?.detail == nil)
        #expect(balanceRow(4)?.value.plain == "Even with your need")
        #expect(balanceRow(-4)?.value.plain == "Even with your need")
    }

    @Test func movingGraduallyIsSaidSo() {
        let rows = content(recommend(usual: clock(1))).reasons
        #expect(rows.first { $0.kind == .usualBedtime }?.detail == "Moving toward your target gradually.")
        let plainRows = content(recommend(usual: clock(23, 10))).reasons
        #expect(plainRows.first { $0.kind == .usualBedtime }?.detail == nil)
    }

    @Test func theMethodNamesTheModelAndTheNumbersItUses() {
        let method = content(recommend()).method
        #expect(method.count == 4)
        #expect(method[0].contains("bedtime-v1"))
        #expect(method[1].contains("1h or more") && method[1].contains("30m") && method[1].contains("quarter"))
        #expect(method[2].contains("45m") && method[2].contains("gradually"))
        #expect(method[3].contains("15m") && method[3].contains("5m"))
    }

    @Test func theNightClocksChangeIsSaidAndExplained() {
        let forward = content(recommend(change: 60))
        #expect(forward.clockChange?.contains("go forward") == true)
        #expect(forward.method.count == 5)
        #expect(content(recommend(change: -60)).clockChange?.contains("go back") == true)
        #expect(content(recommend()).clockChange == nil)
    }

    @Test func nothingPressuresAndNothingDiagnoses() {
        let banned = ["should", "must", "debt", "warning", "danger", "poor", "bad", "diagnos", "cause", "sick", "disease", "smart wake"]
        let every = [
            recommend(), recommend(balance: -200, usual: clock(1), spread: 50), recommend(nights: 2), recommend(change: 60), recommend(balance: 40),
        ]
        for recommendation in every {
            let c = content(recommendation)
            let strings = [c.summary, c.heroCaption, c.wakeLine, c.note, c.confidence, c.clockChange, c.accessibilityLabel].compactMap { $0 }
                + c.method + c.reasons.flatMap { [$0.label, $0.value.plain, $0.detail].compactMap { $0 } }
            for text in strings {
                for word in banned {
                    #expect(!text.lowercased().contains(word), Comment(rawValue: "\"\(text)\" contains \(word)"))
                }
            }
        }
    }
}

// MARK: - The words of the alarm

struct AlarmBuilderTests {
    private func status(_ state: AlarmState, authorization: AlarmAuthorization = .authorized, failure: AlarmFailure? = nil, days: Set<AlarmWeekday> = []) -> AlarmStatus {
        AlarmStatus(
            settings: AlarmSettings(minutesSinceMidnight: clock(7, 30), repeatDays: days, lastState: state), state: state, authorization: authorization, failure: failure
        )
    }

    @Test(arguments: [
        (AlarmState.off, "Off", AlarmChip.Tone.off, false), (.cancelled, "Off", .off, false), (.dismissed, "Off", .off, false),
        (.scheduled, "Scheduled", .on, true), (.armed, "Scheduled", .on, true), (.snoozed, "Snoozed", .on, true), (.firing, "Ringing", .on, true),
    ])
    func theChipFollowsTheState(state: AlarmState, text: String, tone: AlarmChip.Tone, isOn: Bool) {
        let card = AlarmBuilder.card(for: status(state), format: tonightFormat)
        #expect(card.chip.text == text)
        #expect(card.chip.tone == tone)
        #expect(card.isOn == isOn)
        #expect(card.kind == .normal)
        #expect(card.message == nil)
    }

    @Test func theTimeIsTheAlarmsAndAlsoSpoken() {
        let card = AlarmBuilder.card(for: status(.armed), format: tonightFormat)
        #expect(plain(card.time.plain) == "7:30AM")
        #expect(plain(card.accessibilityLabel) == "Alarm. 7:30 AM. Once. Scheduled")
    }

    @Test func permissionNeededIsCalm() {
        let card = AlarmBuilder.card(for: status(.permissionDenied, authorization: .denied), format: tonightFormat)
        #expect(card.kind == .permissionDenied)
        #expect(card.chip.text == "Permission needed")
        #expect(card.chip.tone == .attention)
        #expect(card.message == "Alarms are turned off for NOCTIS. You can allow them in Settings.")
        #expect(!card.isOn)
    }

    @Test func anUnavailableSystemSaysItNeedsIOS26() {
        let card = AlarmBuilder.card(for: status(.unavailable, authorization: .unavailable), format: tonightFormat)
        #expect(card.kind == .unavailable)
        #expect(card.message == "Alarms aren't available here. They need iOS 26 or later.")
        #expect(!card.isOn)
    }

    @Test func anErrorSaysWhatToDo() {
        let generic = AlarmBuilder.card(for: status(.error, failure: .scheduleFailed), format: tonightFormat)
        #expect(generic.kind == .error)
        #expect(generic.chip.text == "Couldn't set")
        #expect(generic.message == "NOCTIS couldn't set the alarm. Try again.")
        let limit = AlarmBuilder.card(for: status(.error, failure: .limitReached), format: tonightFormat)
        #expect(limit.message?.contains("limit") == true)
    }

    @Test func theRepeatDaysAreSummarisedInPlainWords() {
        let format = tonightFormat
        #expect(AlarmBuilder.repeatSummary([], format: format) == "Once")
        #expect(AlarmBuilder.repeatSummary(AlarmWeekday.everyDay, format: format) == "Every day")
        #expect(AlarmBuilder.repeatSummary(AlarmWeekday.weekdays, format: format) == "Weekdays")
        #expect(AlarmBuilder.repeatSummary(AlarmWeekday.weekend, format: format) == "Weekends")
        #expect(AlarmBuilder.repeatSummary([.wednesday, .monday, .friday], format: format) == "Mon, Wed, Fri")
        #expect(AlarmBuilder.repeatSummary([.sunday, .monday], format: format) == "Mon, Sun")
    }

    @Test func dayNamesComeInThreeWidths() {
        #expect(AlarmBuilder.dayName(.monday, width: .narrow, format: tonightFormat) == "M")
        #expect(AlarmBuilder.dayName(.monday, width: .abbreviated, format: tonightFormat) == "Mon")
        #expect(AlarmBuilder.dayName(.monday, width: .wide, format: tonightFormat) == "Monday")
        #expect(AlarmBuilder.dayName(.sunday, width: .wide, format: tonightFormat) == "Sunday")
    }

    @Test func theSheetMakesOnlyTheClaimItCanKeep() {
        #expect(AlarmBuilder.honestyLine == "Rings at your set time, even in silent mode or Focus.")
        for text in [AlarmBuilder.honestyLine, AlarmBuilder.permissionExplanation, AlarmBuilder.deniedMessage, AlarmBuilder.unavailableMessage] {
            #expect(!text.lowercased().contains("smart"))
            #expect(!text.lowercased().contains("sleep stage"))
            #expect(!text.lowercased().contains("lightest"))
        }
    }
}

// MARK: - The screen's view model

@MainActor
struct TonightViewModelTests {
    /// Counts how often the person was sent to Settings.
    final class SettingsOpens {
        var count = 0
    }

    private func make(
        scenario: MockScenario = .full, alarm: MockAlarmBackend.Mode = .authorized, now: Date = tonightNow, stored: AlarmSettings? = nil
    ) -> (TonightViewModel, MockAlarmBackend, MemoryAlarmStore, SettingsOpens) {
        let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let sleep = SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { now })
        let backend = MockAlarmBackend(mode: alarm)
        let store = MemoryAlarmStore(stored)
        let service = AlarmService(backend: backend, store: store, defaultMinutes: { clock(7) })
        let opens = SettingsOpens()
        let model = TonightViewModel(
            sleep: sleep, alarm: service, profile: { UserProfileSnapshot(typicalWakeMinutes: clock(7), needMinutes: clock(8)) },
            format: tonightFormat, timeZone: Fixture.newYork, clock: { now }, openSettings: { opens.count += 1 }
        )
        return (model, backend, store, opens)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: Tonight

    @Test func nothingIsShownBeforeItIsRead() {
        let (model, _, _, _) = make()
        #expect(model.content == nil)
        #expect(model.alarm == nil)
        #expect(model.alarmCard == nil)
    }

    @Test func aFullMonthGivesAWindowBuiltFromTheSleepSnapshot() async {
        let (model, _, _, _) = make(scenario: .full)
        await model.onAppear()
        let moment = tonightNow
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: moment, calendar: Fixture.calendar(), startAuthorized: true)
        let snapshot = await SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { moment }).refresh(profile: UserProfileSnapshot())
        let inputs = BedtimeInputsBuilder.inputs(
            wakeMinutes: clock(7), needMinutes: clock(8), timing: snapshot.timing, balance: snapshot.balance, consistency: snapshot.consistency
        )
        let expected = TonightBuilder.content(for: BedtimeRecommendationEngine.recommend(inputs), now: tonightNow, timeZone: Fixture.newYork, format: tonightFormat)
        #expect(model.content == expected)
        #expect(model.content?.isWindow == true)
        model.onDisappear()
    }

    @Test func fewNightsGiveAStartingPoint() async {
        let (model, _, _, _) = make(scenario: .learning)
        await model.onAppear()
        #expect(model.content?.isWindow == false)
        #expect(model.content?.note == "A starting point. We're still learning your pattern.")
        #expect(plain(model.content?.summary ?? "") == "Bedtime around 11:00 PM")
        model.onDisappear()
    }

    @Test func noHealthDataStillGivesTheStartingPoint() async {
        let (model, _, _, _) = make(scenario: .empty)
        await model.onAppear()
        #expect(plain(model.content?.summary ?? "") == "Bedtime around 11:00 PM")
        model.onDisappear()
    }

    @Test func theNightTheClocksGoForwardIsEarlierOnTheClock() async {
        let (model, _, _, _) = make(scenario: .empty, now: Fixture.date(2026, 3, 7, 20))
        await model.onAppear()
        #expect(plain(model.content?.summary ?? "") == "Bedtime around 10:00 PM")
        #expect(model.content?.clockChange != nil)
        model.onDisappear()
    }

    @Test func theMorningAfterIsAboutTheNextNight() async {
        // Early on the 8th, the clocks have changed; the next bedtime is an ordinary one.
        let (model, _, _, _) = make(scenario: .empty, now: Fixture.date(2026, 3, 8, 9))
        await model.onAppear()
        #expect(model.content?.clockChange == nil)
        #expect(plain(model.content?.summary ?? "") == "Bedtime around 11:00 PM")
        model.onDisappear()
    }

    // MARK: The alarm

    @Test func theAlarmStartsOffAtTheWakeTime() async {
        let (model, _, _, _) = make()
        await model.onAppear()
        #expect(model.alarm?.state == .off)
        #expect(model.alarmCard?.isOn == false)
        #expect(model.alarmCard?.chip.text == "Off")
        #expect(plain(model.alarmCard?.time.plain ?? "") == "7:00AM")
        #expect(model.draft.minutesSinceMidnight == clock(7))
        model.onDisappear()
    }

    @Test func theCardsToggleTurnsAnAllowedAlarmOnAndOff() async {
        let (model, backend, store, _) = make(alarm: .authorized)
        await model.onAppear()
        await model.setAlarm(on: true)
        #expect(model.alarm?.state == .armed)
        #expect(model.alarmCard?.chip.text == "Scheduled")
        #expect(backend.scheduleCalls == 1)
        #expect(store.settings?.lastState == .armed)
        #expect(!model.isSheetPresented)
        await model.setAlarm(on: false)
        #expect(model.alarm?.state == .cancelled)
        #expect(model.alarmCard?.chip.text == "Off")
        #expect(backend.cancelCalls == 1)
        model.onDisappear()
    }

    @Test func theFirstTimeTheSheetExplainsBeforeAnythingIsAsked() async {
        let (model, backend, _, _) = make(alarm: .notDetermined)
        await model.onAppear()
        #expect(model.explainsPermission)
        await model.setAlarm(on: true)
        #expect(model.isSheetPresented)
        #expect(backend.promptCount == 0)
        #expect(backend.scheduleCalls == 0)
        await model.turnOn()
        #expect(backend.promptCount == 1)
        #expect(backend.scheduleCalls == 1)
        #expect(model.alarm?.state == .armed)
        #expect(!model.isSheetPresented)
        #expect(!model.explainsPermission)
        model.onDisappear()
    }

    @Test func sayingNoLeavesACalmCardAndTheToggleOff() async {
        let (model, backend, _, opens) = make(alarm: .willDeny)
        await model.onAppear()
        model.openSheet()
        await model.turnOn()
        #expect(model.alarm?.state == .permissionDenied)
        #expect(model.alarmCard?.kind == .permissionDenied)
        #expect(model.alarmCard?.isOn == false)
        #expect(model.isSheetPresented)
        #expect(backend.scheduleCalls == 0)
        model.openSettings()
        #expect(opens.count == 1)
        // The toggle can't force it on: it opens the sheet, which says why.
        model.isSheetPresented = false
        await model.setAlarm(on: true)
        #expect(model.isSheetPresented)
        #expect(model.alarm?.state == .permissionDenied)
        model.onDisappear()
    }

    @Test func anAlreadyRefusedPermissionShowsItAtOnce() async {
        let (model, _, _, _) = make(alarm: .denied)
        await model.onAppear()
        #expect(model.alarmCard?.kind == .permissionDenied)
        model.onDisappear()
    }

    @Test func aSystemWithoutAlarmsHidesTheToggleBehindANote() async {
        let (model, _, _, _) = make(alarm: .unavailable)
        await model.onAppear()
        #expect(model.alarmCard?.kind == .unavailable)
        #expect(model.alarmCard?.message == "Alarms aren't available here. They need iOS 26 or later.")
        model.onDisappear()
    }

    @Test func anErrorOffersAnotherTry() async {
        let (model, backend, _, _) = make(alarm: .failing)
        await model.onAppear()
        await model.setAlarm(on: true)
        #expect(model.alarmCard?.kind == .error)
        #expect(model.alarm?.failure == .scheduleFailed)
        await model.retry()
        #expect(backend.scheduleCalls == 2)
        #expect(model.alarmCard?.kind == .error)
        model.onDisappear()
    }

    @Test func theDraftIsACopyUntilSaved() async {
        let (model, backend, store, _) = make(alarm: .authorized)
        await model.onAppear()
        await model.setAlarm(on: true)
        model.openSheet()
        #expect(!model.hasChanges)
        model.draft.minutesSinceMidnight = clock(6, 45)
        model.draft.repeatDays = AlarmWeekday.weekdays
        model.draft.snoozeEnabled = true
        model.draft.snoozeMinutes = 10
        #expect(model.hasChanges)
        #expect(model.alarm?.settings.minutesSinceMidnight == clock(7))
        #expect(backend.scheduleCalls == 1)
        await model.save()
        #expect(!model.isSheetPresented)
        #expect(backend.scheduleCalls == 2)
        #expect(store.settings?.minutesSinceMidnight == clock(6, 45))
        #expect(store.settings?.repeatDays == AlarmWeekday.weekdays)
        #expect(store.settings?.snoozeMinutes == 10)
        #expect(model.alarmCard?.repeatSummary == "Weekdays")
        #expect(plain(model.alarmCard?.time.plain ?? "") == "6:45AM")
        model.onDisappear()
    }

    @Test func turningOffFromTheSheetClosesIt() async {
        let (model, _, _, _) = make(alarm: .authorized)
        await model.onAppear()
        await model.setAlarm(on: true)
        model.openSheet()
        await model.turnOff()
        #expect(model.alarm?.state == .cancelled)
        #expect(!model.isSheetPresented)
        model.onDisappear()
    }

    @Test func theWheelEditsTheDraftsMinutes() async {
        let (model, _, _, _) = make()
        await model.onAppear()
        model.draft.minutesSinceMidnight = clock(6, 45)
        let parts = Fixture.calendar().dateComponents([.hour, .minute], from: model.draftTime)
        #expect(parts.hour == 6 && parts.minute == 45)
        model.draftTime = Fixture.date(2026, 9, 24, 22, 5)
        #expect(model.draft.minutesSinceMidnight == clock(22, 5))
        model.onDisappear()
    }

    @Test func theCardFollowsTheSystemWhileTheScreenIsUp() async {
        let (model, backend, _, _) = make(alarm: .authorized)
        await model.onAppear()
        await model.setAlarm(on: true)
        let id = model.alarm?.settings.alarmKitID
        #expect(id != nil)
        backend.fire(id!)
        #expect(await waitUntil { model.alarmCard?.chip.text == "Ringing" })
        backend.stop(id!)
        #expect(await waitUntil { model.alarm?.state == .dismissed })
        #expect(model.alarmCard?.chip.text == "Off")
        model.onDisappear()
    }

    @Test func aSavedAlarmIsThereWhenTheScreenOpens() async {
        let saved = AlarmSettings(minutesSinceMidnight: clock(6, 30), repeatDays: AlarmWeekday.weekend, snoozeEnabled: true, snoozeMinutes: 5)
        let (model, _, _, _) = make(stored: saved)
        await model.onAppear()
        #expect(plain(model.alarmCard?.time.plain ?? "") == "6:30AM")
        #expect(model.alarmCard?.repeatSummary == "Weekends")
        #expect(model.draft.snoozeMinutes == 5)
        model.onDisappear()
    }
}
