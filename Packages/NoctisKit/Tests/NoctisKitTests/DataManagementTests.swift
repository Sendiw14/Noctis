import Foundation
import SwiftData
import Testing

@testable import AppRoot
@testable import CoachKit
@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import JournalKit
@testable import NightKit
@testable import NoctisCore
@testable import NoctisWidgetKit
@testable import ProfileFeature

private let shared = DataInventory.shared

// MARK: - What the confirmations say (APP_RULES.md R37)

struct DataManagementCopyTests {
    @Test func everyDeleteSaysWhatGoesWhatStaysWhereFromAndThatItCannotBeUndone() {
        for group in shared.groups {
            let message = DataManagementCopy.message(for: group)
            #expect(message.contains("can't be undone"), Comment(rawValue: "\(group.id) does not say it can't be undone"))
            #expect(message.contains(group.from) && message.contains("this iPhone"), Comment(rawValue: "\(group.id) does not say where it goes from"))
            #expect(message.contains(group.removes), Comment(rawValue: "\(group.id) does not say what is removed"))
            #expect(message.contains(group.keeps), Comment(rawValue: "\(group.id) does not say what is kept"))
            #expect(group.keeps.contains("not affected") || group.keeps.contains("untouched") || group.keeps.contains("kept"), Comment(rawValue: group.id))
            #expect(!group.question.isEmpty && group.question.hasSuffix("?") && !group.confirm.isEmpty && group.done.hasSuffix("."), Comment(rawValue: group.id))
        }
        #expect(shared.groups.map(\.id) == ["journal", "coach", "insights", "windDown", "cache", "preferences"])
    }

    @Test func aResetSaysItIsAResetAndADeleteSaysItIsDeleted() {
        let reset = DataManagementCopy.message(for: shared.groups.first { $0.id == "preferences" }!)
        #expect(reset.contains("is reset on this iPhone") && reset.contains("Your goals go back to Better sleep"))
        #expect(DataManagementCopy.message(for: shared.groups[0]).contains("is deleted from this iPhone"))
    }

    @Test func theDeleteAllSheetListsWhatGoesFromTheInventoryAndWhatStays() {
        let removes = DataManagementCopy.deleteAllRemoves(shared)
        #expect(removes.lead == "Everything NOCTIS stores on this iPhone:")
        for name in ["Your profile", "Preferences", "Wake alarm", "Wind-down history", "Journal", "Coach conversations", "Insights history", "Cached summaries", "Scheduled reminders"] {
            #expect(removes.items.contains(name), Comment(rawValue: name))
        }
        #expect(!removes.items.contains("Apple Health data") && !removes.items.contains("Subscription"), "what is not NOCTIS's to delete")
        #expect(DataManagementCopy.deleteAllKeeps == ["Your Apple Health data is untouched.", "Your subscription isn't canceled; manage it in Settings."])
        #expect(DataManagementCopy.manageSubscription == "Manage subscription" && DataManagementCopy.deleteAllClosing.contains("can't be undone"))
        #expect(DataManagementCopy.exportNote().contains("raw Apple Health readings") && DataManagementCopy.exportNote().contains("stays on this iPhone unless you share it"))
    }

    @Test func theResultLineSaysWhatHappened() {
        let group = shared.groups[0]
        #expect(DataManagementCopy.result(DeletionReport(entries: [.init(id: "journal", title: "Journal", failure: nil)]), group: group) == "Journal deleted.")
        let failed = DeletionReport(entries: [.init(id: "journal", title: "Journal", failure: "unavailable")])
        #expect(DataManagementCopy.result(failed, group: group) == "Journal couldn't be deleted: unavailable.")
    }

    @Test func thePagesAreRoutedAndTheDeleteColorsExist() {
        #expect(SettingsPage(token: "data-management") == .dataManagement && SettingsPage(token: "privacy-center") == .privacyCenter)
        #expect(AppRoute(url: AppRoute.settings(section: .dataManagement).url) == .settings(section: .dataManagement))
        #expect(NoctisAppPalette.light.destructive == "B3261E" && NoctisAppPalette.dark.destructive == "FF8A80")
    }
}

// MARK: - The runner

@MainActor
struct DeletionRunnerTests {
    struct Boom: Error, CustomStringConvertible { var description: String { "boom" } }

    @Test func everyStepRunsInOrderAndAFailureDoesNotStopTheRest() async {
        var ran: [String] = []
        var heard: [String] = []
        let steps = [
            DeleteStep(id: "a", title: "A") { ran.append("a") },
            DeleteStep(id: "b", title: "B") { ran.append("b"); throw Boom() },
            DeleteStep(id: "c", title: "C") { ran.append("c") },
        ]
        let report = await DeletionRunner.run(steps) { id, finished, failure in heard.append("\(id)\(finished ? "+" : "")\(failure.map { ":\($0)" } ?? "")") }
        #expect(ran == ["a", "b", "c"], "the step after the failure still ran")
        #expect(report.entries.map(\.id) == ["a", "b", "c"] && !report.succeeded)
        #expect(report.failures.map(\.id) == ["b"] && report.failures.first?.failure == "boom")
        #expect(heard == ["a", "a+", "b", "b+:boom", "c", "c+"])
        #expect(await DeletionRunner.run([]).succeeded, "nothing to do is nothing wrong")
    }
}

// MARK: - The wiring, against real stores in memory

@MainActor
final class DataBench {
    let model: AppModel
    let profileStore: ProfileStore
    let container: ModelContainer
    let preferences: AppPreferences
    let defaults: UserDefaults
    let center: InMemoryNotificationCenter
    let backend = MockAlarmBackend(mode: .authorized)
    let alarmStore: AlarmConfigurationStore
    let alarmService: AlarmService
    let windDownStore: WindDownSessionStore
    let journal = MemoryJournalStore()
    let coachHistory: CoachHistoryStore
    let insightFile: InsightFileStore
    let snapshotStore: HomeSnapshotStore
    let root: URL
    let roots: DataRoots
    var calls: [String] = []
    lazy var sleepSounds = SleepSoundsPublisher(store: SleepSoundsStore(directory: roots.url(.appGroup)), reload: { [unowned self] in calls.append("control") })
    var manager: DataManager!
    var failJournal = false

    init() throws {
        root = URL.temporaryDirectory.appending(path: "noctis-data-\(UUID().uuidString)", directoryHint: .isDirectory)
        let support = root.appending(path: "support", directoryHint: .isDirectory)
        let caches = root.appending(path: "caches", directoryHint: .isDirectory)
        let temporary = root.appending(path: "tmp", directoryHint: .isDirectory)
        let group = root.appending(path: "group", directoryHint: .isDirectory)
        for folder in [support.appending(path: "Noctis"), caches.appending(path: "com.noctis.app/com.apple.metal"), temporary, group] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        defaults = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)") ?? NoctisUserDefaults.standard
        roots = DataRoots(directories: [.applicationSupport: support, .caches: caches, .temporary: temporary, .appGroup: group], defaults: defaults)
        container = try ModelContainer(
            for: UserProfileRecord.self, AlarmConfiguration.self, WindDownSession.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        profileStore = ProfileStore(context: ModelContext(container))
        model = AppModel(healthProvider: MockHealthKitProvider(scenario: .full), profileStore: profileStore)
        preferences = AppPreferences(defaults: defaults)
        center = InMemoryNotificationCenter(authorization: .allowed)
        alarmStore = AlarmConfigurationStore(context: ModelContext(container))
        alarmService = AlarmService(backend: backend, store: alarmStore, defaultMinutes: { 7 * 60 })
        windDownStore = WindDownSessionStore(context: ModelContext(container))
        coachHistory = CoachHistoryStore(modelContainer: try CoachHistoryContainer.make(inMemory: true))
        insightFile = InsightFileStore(directory: support.appending(path: "Noctis", directoryHint: .isDirectory))
        snapshotStore = HomeSnapshotStore(directory: support.appending(path: "Noctis", directoryHint: .isDirectory))
    }

    func wire() {
        manager = DataWiring.manager(DataWiringInputs(
            model: model, preferences: preferences, defaults: defaults, profileStore: profileStore, alarmService: alarmService, alarmStore: alarmStore,
            windDownStore: windDownStore, journal: failJournal ? FailingJournal() : journal, coachHistory: coachHistory, insightFile: insightFile,
            snapshotStore: snapshotStore, notifications: NotificationScheduler(center: center), roots: roots, appVersion: { "NOCTIS 1.0 (7)" },
            stopAudio: { [unowned self] in calls.append("audio") }, endWindDown: { [unowned self] in calls.append("windDown") },
            silenceReminders: { [unowned self] in
                calls.append("silence")
                preferences.onChange = nil
                model.onProfileChange = nil
            },
            settleReminders: { [unowned self] in calls.append("settle") },
            afterJournalDeleted: { [unowned self] in calls.append("journalReload") },
            afterCoachDeleted: { [unowned self] in calls.append("coachReload") },
            clearMemory: { [unowned self] in calls.append("memory") },
            forgetSoundChoices: { [unowned self] in calls.append("soundChoices") },
            reloadWidgets: { [unowned self] in calls.append("widgets") }, sleepSounds: sleepSounds,
            reloadControls: { [unowned self] in calls.append("controls") }, endLiveActivities: { [unowned self] in calls.append("liveActivities") },
            stopBackgroundUpdates: { [unowned self] in calls.append("background") }
        ))
    }

    /// The widgets' summary, in the (test) App Group.
    var widgetFile: URL { roots.url(.appGroup).appending(path: WidgetSnapshotStore.fileName, directoryHint: .notDirectory) }

    /// The Sleep sounds control's status, in the (test) App Group.
    var controlsFile: URL { roots.url(.appGroup).appending(path: SleepSoundsStore.fileName, directoryHint: .notDirectory) }

    /// Something in every place NOCTIS keeps anything.
    func fill() async throws {
        model.updateProfile {
            $0.name = "Sam"
            $0.onboardingComplete = true
            $0.healthAuthorizationRequested = true
            $0.selectedGoals = [.moreEnergy, .betterFocus]
            $0.primaryGoal = .moreEnergy
            $0.secondaryGoal = .betterFocus
            $0.needMinutes = 450
            $0.sleepGoalHours = 7.5
        }
        preferences.update { $0.appearance = .dark; $0.windDownMinutes = 30; $0.notifications.weeklyIsOn = false; $0.soundsGainPercent = 70 }
        for key in shared[.soundSettings].defaultsKeys + shared[.appState].defaultsKeys { defaults.set("x", forKey: key) }
        defaults.set(true, forKey: "noctis.stray.key")
        _ = await alarmService.enable(AlarmSettings(minutesSinceMidnight: 6 * 60 + 30))
        _ = await windDownStore.begin(start: Date(), plannedMinutes: 20)
        _ = try journal.add(JournalDraft(energy: 4, mood: 3, focus: 5, text: "A good day"), at: Date())
        let conversation = await coachHistory.startConversation()
        await coachHistory.append(question: "How did I sleep?", answer: CoachFixtureAnswer.storable, to: conversation)
        insightFile.save(InsightLibrary())
        try Data("{\"saved\":true}".utf8).write(to: snapshotStore.fileURL)
        try Data("{\"v\":1}".utf8).write(to: widgetFile)
        _ = sleepSounds
        SleepSoundsStore(directory: roots.url(.appGroup)).save(SleepSoundsState())
        try Data(count: 64).write(to: roots.url(.caches).appending(path: "com.noctis.app/com.apple.metal/functions.data"))
        try Data(count: 16).write(to: roots.url(.temporary).appending(path: DataExport.fileName))
        let schedule = ScheduledNotification(identifier: NoctisNotification.morningSummary, title: "NOCTIS", body: "x", components: DateComponents(hour: 7))
        await center.add(schedule)
        for id in ["noctis.notification.windDown", "noctis.notification.weeklyReview", "noctis.notification.trialEnding"] {
            await center.add(ScheduledNotification(identifier: id, title: "NOCTIS", body: "x", components: DateComponents(hour: 8)))
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

/// A journal that cannot be opened: the one step that fails.
@MainActor
final class FailingJournal: JournalStoring {
    func entries() throws -> [JournalEntrySnapshot] { throw JournalError.unavailable }
    func add(_ draft: JournalDraft, at date: Date) throws -> JournalEntrySnapshot? { throw JournalError.unavailable }
    func delete(id: UUID) throws { throw JournalError.unavailable }
    func deleteAll() throws { throw JournalError.unavailable }
}

/// An answer Coach would keep.
enum CoachFixtureAnswer {
    static var storable: CoachAnswer {
        CoachAnswer(
            sourceKind: .fromYourData, intent: .recoveryChange, summary: "Your recovery is 72 today.", confidence: .high,
            footer: "Coach shares patterns from your data. It isn't medical advice."
        )
    }
}

@MainActor
struct DataManagementIntegrationTests {
    @Test func deleteAllLeavesNothingBehindAndStartsOverAtOnboarding() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        let coachBefore = await bench.coachHistory.messageCount()
        #expect(bench.profileStore.recordCount == 1 && !bench.journal.stored.isEmpty && coachBefore == 1)
        #expect((try? Data(contentsOf: bench.snapshotStore.fileURL)) != nil && bench.insightFile.load() != nil)
        #expect(FileManager.default.fileExists(atPath: bench.widgetFile.path) && FileManager.default.fileExists(atPath: bench.controlsFile.path))
        #expect(await bench.center.pendingIdentifiers().count == 4)
        #expect(await bench.alarmService.status().isOn)

        let report = await bench.manager.deleteEverything()

        #expect(report.succeeded, Comment(rawValue: "failures: \(report.failures.map { "\($0.title): \($0.failure ?? "")" })"))
        // Every place that held something is empty.
        #expect(bench.profileStore.recordCount == 0, "the profile record is deleted")
        #expect(bench.journal.stored.isEmpty)
        let coachAfter = await bench.coachHistory.messageCount()
        let conversationsAfter = await bench.coachHistory.conversations()
        #expect(coachAfter == 0 && conversationsAfter.isEmpty)
        #expect(bench.insightFile.load() == nil && !FileManager.default.fileExists(atPath: bench.insightFile.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: bench.snapshotStore.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: bench.widgetFile.path), "the widgets' summary is deleted")
        #expect(!FileManager.default.fileExists(atPath: bench.controlsFile.path), "the Sleep sounds control's status is deleted")
        #expect(bench.calls.contains("widgets") && bench.calls.contains("controls") && bench.calls.contains("liveActivities"), "the widgets and controls are told to redraw and no Live Activity is left")
        #expect(bench.calls.contains("background"), "Health stops waking the app")
        #expect(!FileManager.default.fileExists(atPath: bench.roots.url(.caches).appending(path: "com.noctis.app").path), "iOS's cache folder is cleared")
        #expect(!FileManager.default.fileExists(atPath: bench.roots.url(.temporary).appending(path: DataExport.fileName).path))
        #expect(bench.windDownStore.sessions().isEmpty)
        #expect(await bench.alarmStore.load() == nil)
        // The alarm is cancelled in the system, and the reminders are really gone.
        let alarmOn = await bench.alarmService.status().isOn
        #expect(!alarmOn && bench.backend.cancelCalls >= 1)
        #expect(await bench.center.pendingIdentifiers().isEmpty, "no reminder is left pending, the trial's included")
        // Preferences and every flag are gone.
        for category in shared.categories { for key in category.defaultsKeys { #expect(bench.defaults.object(forKey: key) == nil, Comment(rawValue: key)) } }
        #expect(bench.defaults.object(forKey: "noctis.stray.key") == nil, "anything left under NOCTIS's prefix goes too")
        #expect(bench.preferences.values == PreferenceValues())
        // Nothing may rebuild the reminders afterwards.
        #expect(bench.preferences.onChange == nil && bench.model.onProfileChange == nil)
        #expect(bench.calls.first == "silence" && bench.calls.contains("audio") && bench.calls.contains("windDown") && bench.calls.contains("soundChoices"))
        // The app starts over: a new model on the emptied store is at the beginning of onboarding.
        #expect(!bench.model.isOnboarded && bench.model.profile == UserProfileSnapshot())
        let restarted = AppModel(healthProvider: MockHealthKitProvider(scenario: .full), profileStore: ProfileStore(context: ModelContext(bench.container)))
        #expect(!restarted.isOnboarded && restarted.profile.name.isEmpty && !restarted.profile.healthAuthorizationRequested)
    }

    @Test func theStepsRunInTheSpecifiedOrder() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        _ = await bench.manager.deleteEverything()
        let order = bench.manager.steps.map(\.id)
        #expect(order.prefix(5) == ["silence", "audio", "windDown", "cancelAlarm", "reminders"])
        #expect(order.suffix(2) == ["preferences", "setup"])
        let stores = Array(order.dropFirst(5).dropLast(2))
        #expect(stores.contains("databases") && stores.contains("journal") && stores.contains("coachHistory") && stores.contains("profile") && stores.contains("cachedSummaries") && stores.contains("systemFiles"))
        #expect(!stores.contains("appleHealth") && !stores.contains("purchases") && !stores.contains("diagnosticLog"), "not NOCTIS's to delete")
        #expect(bench.manager.steps.allSatisfy { $0.state == .done })
        #expect(bench.manager.deleteAllReport?.succeeded == true)
    }

    @Test func theDatabaseFilesThemselvesAreRemovedAndNothingElseIs() async throws {
        let bench = try DataBench()
        bench.wire()
        let support = bench.roots.url(.applicationSupport)
        let files = [
            "default.store", "default.store-wal", "default.store-shm", ".default_SUPPORT/_EXTERNAL_DATA/x", "Noctis/Journal/journal.store", "Noctis/Journal/journal.store-wal",
            "Noctis/CoachHistory/coach-history.store", "Noctis/CoachHistory/coach-history.store-shm",
        ]
        for file in files {
            let url = support.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(count: 32).write(to: url)
        }
        let stranger = support.appending(path: "Noctis/not-noctis-registered.txt")
        try Data(count: 8).write(to: stranger)
        _ = await bench.manager.deleteEverything()
        for file in files { #expect(!FileManager.default.fileExists(atPath: support.appending(path: file).path), Comment(rawValue: "\(file) is still there")) }
        #expect(FileManager.default.fileExists(atPath: stranger.path), "a file no category owns is not NOCTIS's to delete")
    }

    @Test func aFailingStepIsReportedAndEveryOtherStepStillRuns() async throws {
        let bench = try DataBench()
        bench.failJournal = true
        bench.wire()
        try await bench.fill()
        let report = await bench.manager.deleteEverything()
        #expect(!report.succeeded && report.failures.map(\.id) == ["journal"])
        #expect(report.entries.count == bench.manager.steps.count, "every step ran")
        let coachLeft = await bench.coachHistory.messageCount()
        let pending = await bench.center.pendingIdentifiers()
        #expect(bench.profileStore.recordCount == 0 && coachLeft == 0 && bench.windDownStore.sessions().isEmpty, "the rest were deleted")
        #expect(pending.isEmpty && bench.insightFile.load() == nil)
        if case .failed = bench.manager.steps.first(where: { $0.id == "journal" })?.state { } else { Issue.record("the sheet shows the failed step") }
    }

    @Test func deletingOneKindLeavesTheRest() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        let journal = shared.groups.first { $0.id == "journal" }!
        let report = await bench.manager.delete(journal)
        #expect(report.succeeded && bench.journal.stored.isEmpty && bench.calls.contains("journalReload"))
        let coachKept = await bench.coachHistory.messageCount()
        #expect(coachKept == 1 && bench.profileStore.recordCount == 1 && bench.insightFile.load() != nil)
        #expect(bench.manager.lastDeleted?.id == "journal")

        _ = await bench.manager.delete(shared.groups.first { $0.id == "coach" }!)
        let coachGone = await bench.coachHistory.messageCount()
        #expect(coachGone == 0 && bench.calls.contains("coachReload"))
        _ = await bench.manager.delete(shared.groups.first { $0.id == "insights" }!)
        #expect(bench.insightFile.load() == nil && bench.windDownStore.sessions().count == 1)
        _ = await bench.manager.delete(shared.groups.first { $0.id == "windDown" }!)
        #expect(bench.windDownStore.sessions().isEmpty)
        _ = await bench.manager.delete(shared.groups.first { $0.id == "cache" }!)
        #expect(!FileManager.default.fileExists(atPath: bench.snapshotStore.fileURL.path) && bench.calls.contains("memory"))
        #expect(bench.model.profile.name == "Sam" && bench.profileStore.recordCount == 1, "the profile is not touched by any single delete")
    }

    @Test func resettingPreferencesAndGoalsKeepsTheNameNeedAndWakeTime() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        let report = await bench.manager.delete(shared.groups.first { $0.id == "preferences" }!)
        #expect(report.succeeded)
        #expect(bench.preferences.values == PreferenceValues())
        for key in shared[.preferences].defaultsKeys + shared[.soundSettings].defaultsKeys { #expect(bench.defaults.object(forKey: key) == nil, Comment(rawValue: key)) }
        #expect(bench.model.profile.selectedGoals == [.betterSleep] && bench.model.profile.primaryGoal == .betterSleep && bench.model.profile.secondaryGoal == nil)
        #expect(bench.model.profile.name == "Sam" && bench.model.profile.needMinutes == 450 && bench.model.profile.onboardingComplete)
        #expect(bench.defaults.object(forKey: shared[.appState].defaultsKeys[0]) != nil, "flags are not preferences")
        #expect(bench.calls.contains("soundChoices"))
    }

    @Test func sizesFollowWhatIsDeleted() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        let cache = shared.groups.first { $0.id == "cache" }!
        #expect(bench.manager.sizeText(for: cache).contains("B") || bench.manager.sizeText(for: cache).contains("Less"))
        _ = await bench.manager.delete(cache)
        #expect(bench.manager.sizeText(for: cache) == "Nothing stored")
        #expect(bench.manager.sizeText(for: shared.groups.first { $0.id == "windDown" }!) == "Kept with your profile" || bench.manager.sizeText(for: shared.groups.first { $0.id == "windDown" }!).hasSuffix("B"))
    }
}

// MARK: - Export

@MainActor
struct DataExportTests {
    private func exported(_ bench: DataBench) async throws -> [String: Any] {
        let url = try await bench.manager.exportFile()
        defer { bench.manager.discardExport() }
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func anExportLeftBehindByAnEarlierRunIsRemovedWhenTheAppStarts() throws {
        let bench = try DataBench()
        let leftover = bench.roots.url(.temporary).appending(path: DataExport.fileName, directoryHint: .notDirectory)
        try Data("{}".utf8).write(to: leftover)
        #expect(FileManager.default.fileExists(atPath: leftover.path))
        bench.wire()
        #expect(!FileManager.default.fileExists(atPath: leftover.path), "the inventory says the export is deleted the next time NOCTIS starts")
    }

    @Test func theExportHoldsEveryCategoryThatHoldsUserContentAndWhatIsDerived() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        let document = try await exported(bench)
        #expect(document["app"] as? String == "NOCTIS 1.0 (7)" && (document["about"] as? String)?.contains("never holds raw Apple Health readings") == true)
        #expect(document["exportedAt"] is String)
        let categories = try #require(document["categories"] as? [String: Any])
        for category in shared.categories {
            guard case .included(let key) = category.export else {
                continue
            }
            #expect(categories[key] != nil, Comment(rawValue: "\(category.id) (\(key)) is not in the export"))
        }
        for category in shared.categories where category.holdsUserContent { if case .included(let key) = category.export { #expect(categories[key] != nil) } }
        let profile = try #require(categories["profile"] as? [String: Any])
        #expect(profile["name"] as? String == "Sam" && profile["sleepNeedMinutes"] as? Int == 450 && (profile["goals"] as? [String]) == ["moreEnergy", "betterFocus"])
        let journal = try #require(categories["journal"] as? [[String: Any]])
        #expect(journal.first?["text"] as? String == "A good day" && journal.first?["mood"] as? Int == 3)
        let coach = try #require(categories["coachHistory"] as? [[String: Any]])
        let turns = try #require(coach.first?["turns"] as? [[String: Any]])
        #expect(turns.first?["question"] as? String == "How did I sleep?")
        let preferences = try #require(categories["preferences"] as? [String: Any])
        #expect(preferences["noctis.pref.appearance"] as? String == "dark")
        let alarm = try #require(categories["alarm"] as? [String: Any])
        #expect(alarm["minutesSinceMidnight"] as? Int == 390)
        #expect((categories["windDownHistory"] as? [[String: Any]])?.count == 1)
        #expect(categories["cachedSummaries"] != nil && categories["insightHistory"] != nil)
    }

    @Test func theExportHoldsNoRawHealthSampleAndNothingNotStoredByNOCTIS() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        let url = try await bench.manager.exportFile()
        defer { bench.manager.discardExport() }
        let text = try String(contentsOf: url, encoding: .utf8)
        for forbidden in ["sourceBundleID", "sourceName", "sdnnMilliseconds", "HKQuantity", "HKCategory", "RawSleepSample", "HeartRateSample", "\"stage\"", "respiratoryRate\""] {
            #expect(!text.contains(forbidden), Comment(rawValue: "the export holds \(forbidden)"))
        }
        // Categories NOCTIS does not store are not in it, and say why in the inventory.
        let categories = try #require((try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["categories"] as? [String: Any])
        let keys = Set(categories.keys)
        for category in shared.categories {
            if case .notStored(let why) = category.export { #expect(!why.isEmpty && !keys.contains(category.id.rawValue), Comment(rawValue: "\(category.id)")) }
        }
        #expect(!text.contains("noctis.stray"), "only what the inventory registers")
    }

    @Test func theExportFileIsWrittenToTheTemporaryFolderAndDiscarded() async throws {
        let bench = try DataBench()
        bench.wire()
        let url = try await bench.manager.exportFile()
        #expect(url.lastPathComponent == "NOCTIS-export.json" && url.path.hasPrefix(bench.roots.url(.temporary).path))
        #expect(FileManager.default.fileExists(atPath: url.path))
        bench.manager.discardExport()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func twoExportsOfTheSameDataAreTheSameText() async throws {
        let bench = try DataBench()
        bench.wire()
        try await bench.fill()
        let first = try await bench.manager.exportFile()
        let a = try Data(contentsOf: first)
        let second = try await bench.manager.exportFile()
        let b = try Data(contentsOf: second)
        defer { bench.manager.discardExport() }
        let left = try #require(try JSONSerialization.jsonObject(with: a) as? [String: Any])["categories"] as? NSDictionary
        let right = try #require(try JSONSerialization.jsonObject(with: b) as? [String: Any])["categories"] as? NSDictionary
        #expect(left == right)
    }

    @Test func aCategoryWithNoProviderIsAnErrorNotASilentGap() async throws {
        await #expect(throws: DataExportError.missingProvider(.cachedSummaries)) {
            try await DataExport.build(inventory: shared, providers: [:], app: "x")
        }
        // And every included category in the inventory has a provider in the app's wiring.
        let bench = try DataBench()
        bench.wire()
        _ = try await bench.manager.exportFile()
        bench.manager.discardExport()
    }
}

// MARK: - The app starts over

struct RestartTests {
    @Test func theAppRestartsAfterDeleteAllWithAFreshContainerAndNoDebugSkip() throws {
        let app = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("App/NoctisApp.swift"), encoding: .utf8)
        #expect(app.contains("AppContainer(restarted: true)") && app.contains(".id(container.generation)"))
        let container = try String(contentsOf: RawDefaultsTests.root.appendingPathComponent("Packages/NoctisKit/Sources/AppRoot/AppContainer.swift"), encoding: .utf8)
        #expect(container.contains("public init(restarted: Bool = false)") && container.contains("NoctisDataRegistry.shared.reset()"))
        for flag in ["debug.skipOnboarding && !restarted", "debug.resetState && !restarted", "let route = debug.initialRoute, !restarted"] {
            #expect(container.contains(flag), Comment(rawValue: "a restart still honours \(flag)"))
        }
    }
}
