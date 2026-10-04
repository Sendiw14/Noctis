import DesignSystem
import Foundation
import SwiftData
import Testing

@testable import HealthProviding
@testable import HomeFeature
@testable import NightFeature
@testable import NightKit
@testable import NoctisCore
@testable import ProfileFeature
@testable import SleepAnalysisKit
@testable import SleepKit

private let profileFormat = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
/// An evening in New York: Thursday, September 24, 2026, 8 PM.
private let profileNow = Fixture.date(2026, 9, 24, 20)

private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

private nonisolated func minutes(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

// MARK: - The edits

struct ProfileEditTests {
    @Test func theSleepNeedIsSavedAsMinutesAndAsHours() {
        var profile = UserProfileSnapshot()
        ProfileEdit.need(minutes: 450).apply(to: &profile)
        #expect(profile.needMinutes == 450)
        #expect(profile.sleepGoalHours == 7.5)
    }

    @Test func theWakeTimeIsSaved() {
        var profile = UserProfileSnapshot()
        ProfileEdit.wake(minutes: minutes(6, 30)).apply(to: &profile)
        #expect(profile.typicalWakeMinutes == 390)
    }

    @Test func theNameIsTrimmedOnOneLineAndCapped() {
        #expect(ProfileEdit.cleaned(name: "  Sam  ") == "Sam")
        #expect(ProfileEdit.cleaned(name: "Sam\nLee") == "Sam Lee")
        #expect(ProfileEdit.cleaned(name: "   ") == "")
        let long = String(repeating: "a", count: 80)
        #expect(ProfileEdit.cleaned(name: long).count == ProfileEdit.nameLimit)
        var profile = UserProfileSnapshot(name: "Sam")
        ProfileEdit.name("").apply(to: &profile)
        #expect(profile.name == "", "clearing the field removes the name")
    }

    @Test func atMostTwoGoalsAreKeptInTheOrderChosen() {
        var profile = UserProfileSnapshot()
        ProfileEdit.goals([.moreEnergy, .betterFocus, .betterRecovery]).apply(to: &profile)
        #expect(profile.selectedGoals == [.moreEnergy, .betterFocus])
        #expect(profile.primaryGoal == .moreEnergy && profile.secondaryGoal == .betterFocus)
        ProfileEdit.goals([.betterRecovery]).apply(to: &profile)
        #expect(profile.primaryGoal == .betterRecovery && profile.secondaryGoal == nil)
        ProfileEdit.goals([.betterRecovery, .betterRecovery]).apply(to: &profile)
        #expect(profile.selectedGoals == [.betterRecovery], "no repeats")
    }

    @Test func aThirdGoalReplacesTheOldestAndATapOnAChosenGoalRemovesIt() {
        var goals: [PrimaryGoal] = []
        goals = ProfileEdit.toggled(.betterSleep, in: goals)
        goals = ProfileEdit.toggled(.moreEnergy, in: goals)
        #expect(goals == [.betterSleep, .moreEnergy])
        goals = ProfileEdit.toggled(.betterFocus, in: goals)
        #expect(goals == [.moreEnergy, .betterFocus])
        goals = ProfileEdit.toggled(.moreEnergy, in: goals)
        #expect(goals == [.betterFocus])
    }
}

// MARK: - What the profile keeps

@MainActor
struct ProfileStoreRoundTripTests {
    private func makeStore() throws -> ProfileStore {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ProfileStore(context: ModelContext(container))
    }

    /// The record keeps hours and a primary and a secondary goal; what is read back is what was saved. (It used
    /// to come back as 8 hours and no goals, so a 7.5 hour need was lost at the next launch.)
    @Test func theNeedAndTheGoalsComeBackAsTheyWereSaved() throws {
        let store = try makeStore()
        var profile = store.load()
        ProfileEdit.need(minutes: 450).apply(to: &profile)
        ProfileEdit.wake(minutes: minutes(6, 15)).apply(to: &profile)
        ProfileEdit.goals([.betterFocus, .moreEnergy]).apply(to: &profile)
        ProfileEdit.name("Sam").apply(to: &profile)
        store.save(profile)
        let back = store.load()
        #expect(back.needMinutes == 450 && back.sleepGoalHours == 7.5)
        #expect(back.typicalWakeMinutes == 375)
        #expect(back.selectedGoals == [.betterFocus, .moreEnergy])
        #expect(back.primaryGoal == .betterFocus && back.secondaryGoal == .moreEnergy)
        #expect(back.name == "Sam")
    }

    @Test func aProfileEditSavesAndTellsTheReminders() throws {
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        var told = 0
        model.onProfileChange = { told += 1 }
        model.apply(.wake(minutes: minutes(6)))
        model.apply(.need(minutes: minutes(7, 45)))
        #expect(told == 2)
        #expect(model.profile.typicalWakeMinutes == 360 && model.profile.needMinutes == 465)
        let reloaded = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        #expect(reloaded.profile.needMinutes == 465, "after a relaunch")
    }
}

// MARK: - The words

@MainActor
struct ProfileBuilderTests {
    private func timing(nights: Int) -> SleepTimingResult {
        SleepTimingResult(
            typicalBedtime: 11 * 60 - 30, typicalWake: 19 * 60 + 5, nights: nights, recentShift: nil, suggested: nil,
            night: SleepNightKey(year: 2026, month: 9, day: 23)
        )
    }

    private func content(_ inputs: ProfileBuilder.Inputs) -> ProfileContent {
        ProfileBuilder.content(inputs, now: profileNow, timeZone: Fixture.newYork, format: profileFormat)
    }

    private let profile = UserProfileSnapshot(name: "", primaryGoal: .betterSleep, typicalWakeMinutes: minutes(7), needMinutes: minutes(8))

    @Test func theSummaryNamesThePersonOnlyWhenThereIsAName() {
        #expect(content(.init(profile: profile)).summary == "Your sleep profile and settings.")
        var named = profile
        named.name = " Sam "
        let result = content(.init(profile: named))
        #expect(result.summary == "Sam, your sleep profile and settings.")
        #expect(result.nameValue == "Sam" && result.name == "Sam")
        #expect(content(.init(profile: profile)).nameValue == "Add your name")
    }

    @Test func theSleepNeedAndWakeTimeAreInTheirOwnWords() {
        let result = content(.init(profile: profile))
        #expect(result.needValue == "8h")
        #expect(plain(result.wakeValue) == "7:00 AM")
        #expect(result.dateCaption == "THURSDAY, SEPTEMBER 24")
    }

    @Test func theTypicalTimesAreStillLearningUnderSevenNights() {
        for nights in [0, 3, 6] {
            let result = content(.init(profile: profile, timing: timing(nights: nights)))
            #expect(result.typicalBedtime == "Still learning" && result.typicalWake == "Still learning", "\(nights) nights")
            #expect(result.learningNote == "Your typical times appear after 7 recorded nights. \(nights) so far.")
        }
        let none = content(.init(profile: profile, timing: nil))
        #expect(none.typicalBedtime == "Still learning" && none.learningNote?.contains("0 so far") == true)
    }

    @Test func theTypicalTimesShowFromSevenNights() {
        let result = content(.init(profile: profile, timing: timing(nights: 7)))
        #expect(plain(result.typicalBedtime) == "10:30 PM", "minutes after noon 630")
        #expect(plain(result.typicalWake) == "7:05 AM")
        #expect(result.learningNote == nil)
    }

    @Test func tonightsBedtimeFollowsTheWakeTimeAndTheNeedAtOnce() {
        var earlier = profile
        earlier.typicalWakeMinutes = minutes(6)
        #expect(content(.init(profile: profile)).bedtime.hero.spoken != content(.init(profile: earlier)).bedtime.hero.spoken)
        var shorter = profile
        shorter.needMinutes = minutes(7)
        #expect(plain(content(.init(profile: profile)).bedtime.summary) == "Bedtime around 11:00 PM")
        #expect(plain(content(.init(profile: shorter)).bedtime.summary) == "Bedtime around 12:00 AM")
    }

    @Test func theAlarmLineAppearsOnlyWhileAnAlarmIsOnAndNamesItsOwnTime() {
        let off = AlarmStatus(settings: AlarmSettings(minutesSinceMidnight: minutes(6, 30)), state: .off, authorization: .authorized)
        let on = AlarmStatus(settings: AlarmSettings(minutesSinceMidnight: minutes(6, 30), lastState: .armed), state: .armed, authorization: .authorized)
        #expect(content(.init(profile: profile, alarm: nil)).alarmLine == nil)
        #expect(content(.init(profile: profile, alarm: off)).alarmLine == nil)
        let line = plain(content(.init(profile: profile, alarm: on)).alarmLine ?? "")
        #expect(line == "Your wake alarm keeps its own time, 6:30 AM. Change it from Tonight.")
    }

    @Test func theGoalsReadInTheOrderChosenAndFallBackToThePrimaryAndSecondary() {
        var chosen = profile
        chosen.selectedGoals = [.betterFocus, .moreEnergy]
        #expect(content(.init(profile: chosen)).goalsValue == "Clearer focus, More energy")
        var legacy = profile
        legacy.selectedGoals = []
        legacy.primaryGoal = .betterRecovery
        legacy.secondaryGoal = .betterConsistency
        #expect(content(.init(profile: legacy)).goalsValue == "Faster recovery, Steady routine")
        #expect(ProfileBuilder.goals(of: legacy) == [.betterRecovery, .betterConsistency])
    }

    @Test func theStatusRowsSayWhatIsTrueAndOpenTheirPages() {
        let rows = content(.init(profile: profile)).status
        #expect(rows.map(\.page) == [.healthData, .notifications, .subscription])
        #expect(rows.map(\.title) == ["Health data", "Notifications", "Subscription"])
        #expect(rows.map(\.value) == ["Checking", "Not turned on", "Free"])
        #expect(content(.init(profile: profile, isPremium: true)).status[2].value == "Premium")
    }

    @Test func theNotificationRowFollowsThePermissionAndThePreferences() {
        var preferences = NotificationPreferences()
        #expect(ProfileBuilder.notificationsValue(.denied, preferences) == "Off in Settings")
        #expect(ProfileBuilder.notificationsValue(.notDetermined, preferences) == "Not turned on")
        #expect(ProfileBuilder.notificationsValue(.allowed, preferences) == "3 reminders on")
        preferences.weeklyIsOn = false
        #expect(ProfileBuilder.notificationsValue(.allowed, preferences) == "2 reminders on")
        preferences.windDownIsOn = false
        #expect(ProfileBuilder.notificationsValue(.allowed, preferences) == "1 reminder on")
        preferences.morningIsOn = false
        #expect(ProfileBuilder.notificationsValue(.allowed, preferences) == "All reminders off")
    }

    @Test func theHealthRowSaysOnlyWhetherDataIsThere() {
        func status(_ present: [Bool], unavailable: Bool = false) -> HealthDataStatus {
            HealthDataStatus(
                kinds: zip(HealthDataKind.allCases, present).map { HealthKindStatus(kind: $0, lastSample: $1 ? profileNow : nil) },
                lastNightSource: nil, isUnavailable: unavailable
            )
        }
        #expect(ProfileBuilder.healthValue(nil) == "Checking")
        #expect(ProfileBuilder.healthValue(status([true, true, true, true, true])) == "Data found")
        #expect(ProfileBuilder.healthValue(status([true, false, false, true, false])) == "Some data found")
        #expect(ProfileBuilder.healthValue(status([false, false, false, false, false])) == "No data found")
        #expect(ProfileBuilder.healthValue(status([false, false, false, false, false], unavailable: true)) == "Not available")
    }
}

// MARK: - The status of Health

@MainActor
struct HealthDataStatusTests {
    private func read(_ scenario: MockScenario, available: Bool = true, failing: Bool = false) async -> HealthDataStatus {
        let provider = MockHealthKitProvider(
            scenario: scenario, referenceDate: profileNow, calendar: Fixture.calendar(), startAuthorized: true, isHealthDataAvailable: available,
            failsQueries: failing
        )
        return await HealthDataStatusReader(provider: provider).read(now: profileNow, calendar: Fixture.calendar())
    }

    @Test func thereIsOneRowForEveryKindTheAuthorizationListHolds() async {
        let status = await read(.full)
        #expect(status.kinds.map(\.kind) == HealthDataKind.allCases)
    }

    @Test func aFullHistoryHasDataForEveryKindWithTheNewestSampleDate() async {
        let status = await read(.full)
        #expect(status.hasAllData && status.hasAnyData && status.missing.isEmpty)
        for row in status.kinds {
            let last = row.lastSample
            #expect(last != nil && last! <= profileNow && last! > profileNow.addingTimeInterval(-3 * 86_400), "\(row.kind)")
        }
    }

    @Test func noDataIsNoDataAndNeverDenied() async {
        let status = await read(.empty)
        #expect(!status.hasAnyData && status.kinds.allSatisfy { !$0.hasData && !$0.couldNotCheck })
        #expect(status.lastNightSource == nil)
    }

    @Test func aSleepOnlyHistoryFindsSleepAndNothingElse() async {
        let status = await read(.sleepOnly)
        #expect(status.kinds.first { $0.kind == .sleepAnalysis }?.hasData == true)
        #expect(status.kinds.filter { $0.kind != .sleepAnalysis }.allSatisfy { !$0.hasData })
        #expect(status.hasAnyData && !status.hasAllData)
    }

    @Test func aFailedQueryIsReportedAsNotChecked() async {
        // The mock fails its sleep query only; the other kinds still answer.
        let status = await read(.full, failing: true)
        let sleep = status.kinds.first { $0.kind == .sleepAnalysis }
        #expect(sleep?.couldNotCheck == true && sleep?.hasData == false)
        #expect(status.kinds.filter { $0.kind != .sleepAnalysis }.allSatisfy { !$0.couldNotCheck && $0.hasData })
    }

    @Test func healthBeingUnavailableIsItsOwnState() async {
        let status = await read(.full, available: false)
        #expect(status.isUnavailable && !status.hasAnyData)
    }

    @Test func lastNightsSourceIsTheOneTheResolverChoseAndOnlyForANightInTheLastTwoDays() {
        let end = profileNow.addingTimeInterval(-12 * 3600)
        let night = Fixture.sample(end.addingTimeInterval(-7 * 3600), end, .core, source: "Apple Watch", bundle: "com.apple.health")
        #expect(HealthDataStatusReader.lastNightSource([night], resolver: DefaultSourceResolver(), now: profileNow) == "Apple Watch")
        let old = Fixture.sample(end.addingTimeInterval(-4 * 86_400), end.addingTimeInterval(-4 * 86_400 + 7 * 3600), .core, source: "Apple Watch", bundle: "com.apple.health")
        #expect(HealthDataStatusReader.lastNightSource([old], resolver: DefaultSourceResolver(), now: profileNow) == nil)
        let awake = Fixture.sample(end.addingTimeInterval(-1800), end, .awake, source: "Apple Watch", bundle: "com.apple.health")
        #expect(HealthDataStatusReader.lastNightSource([awake], resolver: DefaultSourceResolver(), now: profileNow) == nil, "only time asleep counts")
        let unnamed = Fixture.sample(end.addingTimeInterval(-7 * 3600), end, .core, source: "", bundle: "x")
        #expect(HealthDataStatusReader.lastNightSource([unnamed], resolver: DefaultSourceResolver(), now: profileNow) == nil)
        #expect(HealthDataStatusReader.lastNightSource([], resolver: DefaultSourceResolver(), now: profileNow) == nil)
    }
}

// MARK: - The view model

@MainActor
struct ProfileViewModelTests {
    final class Bench {
        var profile = UserProfileSnapshot(name: "", primaryGoal: .betterSleep, selectedGoals: [.betterSleep], typicalWakeMinutes: minutes(7), needMinutes: minutes(8))
        var edits: [ProfileEdit] = []
        let center = InMemoryNotificationCenter(authorization: .allowed)
        let preferences: AppPreferences
        let entitlements = EntitlementManager()
        let alarmBackend = MockAlarmBackend(mode: .authorized)
        let alarmStore = MemoryAlarmStore()
        var viewModel: ProfileViewModel!

        init(scenario: MockScenario = .full) {
            let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? NoctisUserDefaults.standard
            preferences = AppPreferences(defaults: defaults)
            let now = profileNow
            let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
            let sleep = SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { now })
            let service = AlarmService(backend: alarmBackend, store: alarmStore, defaultMinutes: { minutes(7) })
            let coordinator = NotificationCoordinator(
                scheduler: NotificationScheduler(center: center), preferences: preferences, profile: { UserProfileSnapshot() }, bedtimeCenter: { _, _ in minutes(23) }
            )
            viewModel = ProfileViewModel(
                sleep: sleep, alarm: service, health: HealthDataStatusReader(provider: provider), profile: { [unowned self] in profile },
                edit: { [unowned self] edit in
                    edits.append(edit)
                    edit.apply(to: &profile)
                },
                notifications: coordinator, preferences: preferences, entitlements: entitlements, format: profileFormat, timeZone: Fixture.newYork,
                clock: { now }
            )
        }
    }

    @Test func openingAnEditorLoadsTheCurrentValueAndSavingAppliesIt() {
        let bench = Bench()
        let model = bench.viewModel!
        model.open(.need)
        #expect(model.sheet == .need && model.needDraft == 480 && !model.hasChanges)
        model.needDraft = 450
        #expect(model.hasChanges)
        model.save()
        #expect(bench.edits == [.need(minutes: 450)] && model.sheet == nil)
        #expect(bench.profile.needMinutes == 450)

        model.open(.wake)
        #expect(model.wakeDraft == 420)
        model.wakeDraft = minutes(6, 30)
        model.save()
        #expect(bench.edits.last == .wake(minutes: 390))
    }

    @Test func cancellingChangesNothing() {
        let bench = Bench()
        let model = bench.viewModel!
        model.open(.wake)
        model.wakeDraft = minutes(5)
        model.cancel()
        #expect(bench.edits.isEmpty && model.sheet == nil && bench.profile.typicalWakeMinutes == 420)
    }

    @Test func theNameEditorSavesATrimmedNameOrClearsIt() {
        let bench = Bench()
        let model = bench.viewModel!
        model.open(.name)
        #expect(!model.hasChanges)
        model.nameDraft = "  Sam "
        #expect(model.hasChanges)
        model.save()
        #expect(bench.profile.name == "Sam")
        model.open(.name)
        #expect(model.nameDraft == "Sam")
        model.nameDraft = "Sam   "
        #expect(!model.hasChanges, "trailing spaces are not a change")
        model.nameDraft = ""
        #expect(model.hasChanges)
        model.save()
        #expect(bench.profile.name == "")
    }

    @Test func theGoalsEditorKeepsToTwoAndCannotSaveNone() {
        let bench = Bench()
        let model = bench.viewModel!
        model.open(.goals)
        #expect(model.goalsDraft == [.betterSleep])
        model.toggle(goal: .moreEnergy)
        model.toggle(goal: .betterFocus)
        #expect(model.goalsDraft == [.moreEnergy, .betterFocus])
        #expect(model.hasChanges)
        model.toggle(goal: .moreEnergy)
        model.toggle(goal: .betterFocus)
        #expect(model.goalsDraft.isEmpty && !model.hasChanges, "Save stays off with nothing chosen")
        model.toggle(goal: .betterRecovery)
        model.save()
        #expect(bench.profile.primaryGoal == .betterRecovery && bench.profile.secondaryGoal == nil)
    }

    @Test func thePreviewBedtimeUsesTheDraftAndTheOtherSavedValue() {
        let bench = Bench()
        let model = bench.viewModel!
        let saved = plain(model.content.bedtime.summary)
        model.open(.need)
        model.needDraft = minutes(7)
        let preview = plain(model.previewBedtime.summary)
        #expect(preview != saved)
        #expect(plain(model.content.bedtime.summary) == saved, "nothing is saved until Save")
        model.save()
        #expect(plain(model.content.bedtime.summary) == preview, "the saved profile gives the preview's bedtime")
        model.open(.wake)
        model.wakeDraft = minutes(6)
        #expect(plain(model.previewBedtime.summary) != preview)
    }

    @Test func theContentFollowsTheProfileAfterAnEditWithNothingToRefresh() {
        let bench = Bench()
        let model = bench.viewModel!
        #expect(model.content.needValue == "8h")
        model.open(.need)
        model.needDraft = 450
        model.save()
        #expect(model.content.needValue == "7h 30m")
    }

    @Test func appearingReadsTheTimingTheAlarmAndHealth() async {
        let bench = Bench()
        let model = bench.viewModel!
        #expect(model.content.typicalBedtime == "Still learning" && model.content.status[0].value == "Checking")
        await model.onAppear()
        let content = model.content
        #expect(content.typicalBedtime != "Still learning" && content.learningNote == nil, "a full history gives typical times")
        #expect(content.status[0].value == "Data found")
        #expect(content.status[1].value == "3 reminders on")
        #expect(content.alarmLine == nil, "no alarm is set")
    }

    @Test func aNewcomersTypicalTimesAreStillLearning() async {
        let bench = Bench(scenario: .learning)
        await bench.viewModel.onAppear()
        let content = bench.viewModel.content
        #expect(content.typicalBedtime == "Still learning" && content.typicalWake == "Still learning")
        #expect(content.learningNote?.hasPrefix("Your typical times appear after 7 recorded nights.") == true)
    }

    @Test func anEmptyHealthIsNoDataFound() async {
        let bench = Bench(scenario: .empty)
        await bench.viewModel.onAppear()
        #expect(bench.viewModel.content.status[0].value == "No data found")
    }

    @Test func aWakeTimeEditMovesTheEveningReminderThroughTheAppsHook() async throws {
        // The app saves the profile and the coordinator rebuilds from it: the bedtime centre moves the reminder.
        let container = try ModelContainer(for: Schema([UserProfileRecord.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let model = AppModel(healthProvider: MockHealthKitProvider(scenario: .empty), profileStore: ProfileStore(context: ModelContext(container)))
        let center = InMemoryNotificationCenter(authorization: .allowed)
        let defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? NoctisUserDefaults.standard
        let coordinator = NotificationCoordinator(
            scheduler: NotificationScheduler(center: center), preferences: AppPreferences(defaults: defaults), profile: { model.profile },
            bedtimeCenter: { wake, need in ((wake - need) % 1440 + 1440) % 1440 }
        )
        model.onProfileChange = { coordinator.reschedule() }
        model.apply(.wake(minutes: minutes(7)))
        model.apply(.need(minutes: minutes(8)))
        await coordinator.settled()
        func fire(_ identifier: String) -> DateComponents? { center.pendingNotifications.first { $0.identifier == identifier }?.components }
        #expect(fire(NoctisNotification.morningSummary)?.hour == 7 && fire(NoctisNotification.morningSummary)?.minute == 15)
        #expect(fire(NoctisNotification.windDown)?.hour == 22 && fire(NoctisNotification.windDown)?.minute == 40, "11 PM less 20 minutes")
        model.apply(.wake(minutes: minutes(6)))
        await coordinator.settled()
        #expect(fire(NoctisNotification.morningSummary)?.hour == 6 && fire(NoctisNotification.morningSummary)?.minute == 15)
        #expect(fire(NoctisNotification.windDown)?.hour == 21 && fire(NoctisNotification.windDown)?.minute == 40, "10 PM less 20 minutes")
    }
}

// MARK: - The sand field

struct ProfileSandTests {
    @Test func theFieldIsTheSpecifiedSandInBothModes() {
        #expect(NoctisAppPalette.light.fieldSand == "E6D9BF")
        #expect(NoctisAppPalette.dark.fieldSand == "BFA97F")
    }
}
