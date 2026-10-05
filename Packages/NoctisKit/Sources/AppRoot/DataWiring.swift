import CoachKit
import Foundation
import JournalKit
import NightKit
import NoctisCore
import NoctisIntentKit
import NoctisWidgetKit

/// What Data management needs from the app: every store, and what to tell the screens once something is gone.
public struct DataWiringInputs {
    public var model: AppModel
    public var preferences: AppPreferences
    public var defaults: UserDefaults
    public var profileStore: ProfileStore
    public var alarmService: AlarmService
    public var alarmStore: AlarmConfigurationStore
    public var windDownStore: WindDownSessionStore
    public var journal: any JournalStoring
    public var coachHistory: CoachHistoryStore?
    public var insightFile: InsightFileStore
    /// The reviews' file (R39); nil where there is none (a test).
    public var reviewFile: ReviewFileStore?
    public var snapshotStore: HomeSnapshotStore?
    public var notifications: NotificationScheduler
    public var roots: DataRoots
    public var appVersion: () -> String
    /// Stops whatever is playing: the sleep sound, the meditation's voice, the breathing's haptics.
    public var stopAudio: @MainActor () -> Void
    /// Ends a wind-down session that is running.
    public var endWindDown: @MainActor () -> Void
    /// Stops the reminders from being rebuilt while their data is deleted (they would put back what was just removed).
    public var silenceReminders: @MainActor () -> Void
    /// Waits for a reminder rebuild that is already running.
    public var settleReminders: @MainActor () async -> Void
    public var afterJournalDeleted: @MainActor () -> Void
    public var afterCoachDeleted: @MainActor () async -> Void
    public var clearMemory: @MainActor () async -> Void
    public var forgetSoundChoices: @MainActor () -> Void
    /// The widgets' summary: told to forget it (the file is removed by the inventory's own location as well).
    public var widgets: WidgetPublisher?
    /// Asks the system to redraw the widgets, which now have no summary and say "Open NOCTIS".
    public var reloadWidgets: @MainActor () -> Void
    /// The Apple Watch's link: told to wipe the Watch's copy and bump the data epoch (R52).
    public var watch: WatchSyncService?
    /// The Sleep sounds control's status: told to forget it, and to stop writing it (R48).
    public var sleepSounds: SleepSoundsPublisher?
    /// Asks the system to redraw the controls, which now say nothing is playing.
    public var reloadControls: @MainActor () -> Void
    /// Ends every Live Activity NOCTIS has started. None is started by NOCTIS itself yet (the alarm's is AlarmKit's, ended with the alarm).
    public var endLiveActivities: @MainActor () async -> Void
    /// Stops Apple Health from waking the app in the background (R46).
    public var stopBackgroundUpdates: @MainActor () async -> Void

    public init(
        model: AppModel, preferences: AppPreferences, defaults: UserDefaults, profileStore: ProfileStore, alarmService: AlarmService,
        alarmStore: AlarmConfigurationStore, windDownStore: WindDownSessionStore, journal: any JournalStoring, coachHistory: CoachHistoryStore?,
        insightFile: InsightFileStore, snapshotStore: HomeSnapshotStore?, notifications: NotificationScheduler, roots: DataRoots = DataRoots(),
        appVersion: @escaping () -> String = { "NOCTIS" }, stopAudio: @escaping @MainActor () -> Void = {}, endWindDown: @escaping @MainActor () -> Void = {},
        silenceReminders: @escaping @MainActor () -> Void = {}, settleReminders: @escaping @MainActor () async -> Void = {},
        afterJournalDeleted: @escaping @MainActor () -> Void = {}, afterCoachDeleted: @escaping @MainActor () async -> Void = {},
        clearMemory: @escaping @MainActor () async -> Void = {}, forgetSoundChoices: @escaping @MainActor () -> Void = {},
        widgets: WidgetPublisher? = nil, reloadWidgets: @escaping @MainActor () -> Void = {},
        watch: WatchSyncService? = nil, sleepSounds: SleepSoundsPublisher? = nil, reloadControls: @escaping @MainActor () -> Void = {}, endLiveActivities: @escaping @MainActor () async -> Void = {},
        stopBackgroundUpdates: @escaping @MainActor () async -> Void = {}, reviewFile: ReviewFileStore? = nil
    ) {
        self.model = model
        self.preferences = preferences
        self.defaults = defaults
        self.profileStore = profileStore
        self.alarmService = alarmService
        self.alarmStore = alarmStore
        self.windDownStore = windDownStore
        self.journal = journal
        self.coachHistory = coachHistory
        self.insightFile = insightFile
        self.reviewFile = reviewFile
        self.snapshotStore = snapshotStore
        self.notifications = notifications
        self.roots = roots
        self.appVersion = appVersion
        self.stopAudio = stopAudio
        self.endWindDown = endWindDown
        self.silenceReminders = silenceReminders
        self.settleReminders = settleReminders
        self.afterJournalDeleted = afterJournalDeleted
        self.afterCoachDeleted = afterCoachDeleted
        self.clearMemory = clearMemory
        self.forgetSoundChoices = forgetSoundChoices
        self.widgets = widgets
        self.reloadWidgets = reloadWidgets
        self.watch = watch
        self.sleepSounds = sleepSounds
        self.reloadControls = reloadControls
        self.endLiveActivities = endLiveActivities
        self.stopBackgroundUpdates = stopBackgroundUpdates
    }
}

/// What the Watch step said, for the sheet's line under it.
@MainActor
private final class WatchLineBox {
    var text: String?
}

/// Wires Data management to the app's stores (APP_RULES.md R41, R42). An eraser and an exporter for each inventory category, and the
/// steps of "Delete all NOCTIS data" in the order that keeps it from putting back what it removes.
@MainActor
public enum DataWiring {
    public static func manager(_ i: DataWiringInputs, inventory: DataInventory = .shared) -> DataManager {
        let erasers = erasers(i, inventory: inventory)
        return DataManager(
            inventory: inventory, roots: i.roots, erasers: erasers, providers: providers(i), deleteAllSteps: deleteAllSteps(i, erasers: erasers, inventory: inventory),
            appVersion: i.appVersion
        )
    }

    // MARK: Deleting one kind

    static func erasers(_ i: DataWiringInputs, inventory: DataInventory) -> [DataCategoryID: DataManager.Eraser] {
        func remove(keys: [String]) { for key in keys { i.defaults.removeObject(forKey: key) } }
        return [
            .journal: {
                try i.journal.deleteAll()
                i.afterJournalDeleted()
            },
            .coachHistory: {
                await i.coachHistory?.deleteAll()
                await i.afterCoachDeleted()
            },
            .insightHistory: { i.insightFile.erase() },
            .reviews: { i.reviewFile?.erase() },
            .cachedSummaries: { i.snapshotStore?.erase() },
            .widgetSnapshot: {
                await i.widgets?.forget()
                try? FileManager.default.removeItem(at: i.roots.url(.appGroup).appending(path: WidgetSnapshotStore.fileName, directoryHint: .notDirectory))
                i.reloadWidgets()
            },
            .sleepSoundsState: {
                i.sleepSounds?.forget()
                try? FileManager.default.removeItem(at: i.roots.url(.appGroup).appending(path: SleepSoundsStore.fileName, directoryHint: .notDirectory))
                i.reloadControls()
            },
            .watchSync: {
                await i.watch?.forget()
                remove(keys: inventory[.watchSync].defaultsKeys)
            },
            .memorySummaries: { await i.clearMemory() },
            .profile: { i.profileStore.eraseAll() },
            // "Preferences and goals": the preferences back to their defaults, and the goals to Better sleep.
            .preferences: {
                i.preferences.reset()
                i.model.apply(.goals([.betterSleep]))
            },
            .soundSettings: {
                remove(keys: inventory[.soundSettings].defaultsKeys)
                i.forgetSoundChoices()
            },
            .appState: { remove(keys: inventory[.appState].defaultsKeys) },
            .alarm: { i.alarmStore.erase() },
            .windDownHistory: { i.windDownStore.eraseAll() },
            .reminders: {
                await i.settleReminders()
                await i.notifications.removeEverything()
            },
            .systemFiles: {
                for case .folder(let directory, let path) in inventory[.systemFiles].locations {
                    try? FileManager.default.removeItem(at: i.roots.url(directory).appending(path: path, directoryHint: .isDirectory))
                }
            },
            .exportFile: {
                try? FileManager.default.removeItem(at: i.roots.url(.temporary).appending(path: DataExport.fileName, directoryHint: .notDirectory))
            },
        ]
    }

    // MARK: Deleting everything

    /// In order: sound, the wind-down session, the alarm, the reminders; every store, cache and file, from the inventory; the preferences;
    /// setup. A reminder rebuild is switched off first, or clearing the preferences would schedule the defaults again.
    static func deleteAllSteps(_ i: DataWiringInputs, erasers: [DataCategoryID: DataManager.Eraser], inventory: DataInventory) -> [DeleteStep] {
        var steps = [
            DeleteStep(id: "silence", title: "Pausing reminders") { i.silenceReminders() },
            DeleteStep(id: "audio", title: "Stopping sounds") {
                // The control's status is not written again while everything is deleted (a sound that fades out would write it).
                i.sleepSounds?.suspend()
                i.stopAudio()
            },
            DeleteStep(id: "windDown", title: "Ending any wind-down") { i.endWindDown() },
            DeleteStep(id: "cancelAlarm", title: "Cancelling your wake alarm") { _ = await i.alarmService.disable() },
        ]
        if let reminders = erasers[.reminders] { steps.append(DeleteStep(id: DataCategoryID.reminders.rawValue, title: "Removing reminders", run: reminders)) }
        // Every store, cache and file, by the inventory's own list.
        let handledElsewhere: Set<DataCategoryID> = [.reminders, .preferences, .soundSettings, .appState]
        for category in inventory.categories where !handledElsewhere.contains(category.id) {
            guard let eraser = erasers[category.id] else { continue }
            steps.append(DeleteStep(id: category.id.rawValue, title: "Deleting \(category.name.lowercasedFirst)", run: eraser))
        }
        // The Apple Watch: the data epoch becomes now (the one value that stays) and the Watch is sent it with nothing else, so it wipes its copy; if it is
        // away, it wipes when it connects. The sheet says which.
        let watchLine = WatchLineBox()
        steps.append(DeleteStep(id: "watch", title: "Telling your Apple Watch", note: { watchLine.text }) {
            watchLine.text = await i.watch?.wipe().line
        })
        // The database files themselves, so what the rows held is not left behind in a file's free pages.
        steps.append(DeleteStep(id: "databases", title: "Removing database files") {
            for category in inventory.categories {
                for case .database(let directory, let path) in category.locations {
                    let store = i.roots.url(directory).appending(path: path, directoryHint: .notDirectory)
                    let folder = store.deletingLastPathComponent()
                    let relativeFolder = (path as NSString).deletingLastPathComponent
                    for entry in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                        let relative = relativeFolder.isEmpty ? entry : relativeFolder + "/" + entry
                        if inventory.category(forFile: relative, in: directory) == category.id {
                            try? FileManager.default.removeItem(at: folder.appending(path: entry))
                        }
                    }
                }
            }
        })
        // The widgets redraw without their summary, and no Live Activity is left running.
        steps.append(DeleteStep(id: "widgets", title: "Updating widgets") {
            i.reloadWidgets()
            i.reloadControls()
            await i.endLiveActivities()
        })
        // Health stops waking the app, so a deleted app does not start itself in the night.
        steps.append(DeleteStep(id: "backgroundUpdates", title: "Stopping background updates") { await i.stopBackgroundUpdates() })
        steps.append(DeleteStep(id: "preferences", title: "Clearing preferences") {
            i.preferences.reset()
            for id in [DataCategoryID.preferences, .soundSettings, .appState] { for key in inventory[id].defaultsKeys { i.defaults.removeObject(forKey: key) } }
            // Anything else NOCTIS has left under its own prefix.
            for key in i.defaults.dictionaryRepresentation().keys where key.hasPrefix("noctis.") { i.defaults.removeObject(forKey: key) }
            i.forgetSoundChoices()
        })
        steps.append(DeleteStep(id: "setup", title: "Resetting setup") { i.model.forgetProfileInMemory() })
        return steps
    }

    // MARK: Export

    static func providers(_ i: DataWiringInputs) -> [DataCategoryID: DataExport.Provider] {
        [
            .cachedSummaries: {
                guard let url = i.snapshotStore?.fileURL else { return [String: Any]() }
                return DataExport.fileObject(at: url)
            },
            .widgetSnapshot: { DataExport.fileObject(at: i.roots.url(.appGroup).appending(path: WidgetSnapshotStore.fileName, directoryHint: .notDirectory)) },
            .sleepSoundsState: { DataExport.fileObject(at: i.roots.url(.appGroup).appending(path: SleepSoundsStore.fileName, directoryHint: .notDirectory)) },
            .watchSync: {
                var object: [String: Any] = [:]
                if let sent = WatchSyncDefaults(defaults: i.defaults).lastSentAt { object["lastSentAt"] = ISO8601DateFormatter().string(from: sent) }
                return object
            },
            .insightHistory: { i.insightFile.load().map { (try? DataExport.object(from: $0)) ?? [String: Any]() } ?? [String: Any]() },
            .reviews: { i.reviewFile?.load().map { (try? DataExport.object(from: $0)) ?? [String: Any]() } ?? [String: Any]() },
            .profile: {
                let profile = i.model.profile
                var object: [String: Any] = [
                    "sleepNeedMinutes": profile.needMinutes, "wakeMinutes": profile.typicalWakeMinutes,
                    "goals": profile.selectedGoals.map(\.rawValue), "setupFinished": profile.onboardingComplete,
                    "healthAccessAsked": profile.healthAuthorizationRequested,
                ]
                if !profile.name.isEmpty { object["name"] = profile.name }
                return object
            },
            .preferences: { DataExport.defaultsObject(keys: i.defaults.dictionaryRepresentation().keys.filter { AppPreferences.allKeys.contains($0) }, defaults: i.defaults) },
            .soundSettings: { DataExport.defaultsObject(keys: inventory(.soundSettings).defaultsKeys, defaults: i.defaults) },
            .appState: { DataExport.defaultsObject(keys: inventory(.appState).defaultsKeys, defaults: i.defaults) },
            .alarm: {
                guard let settings = await i.alarmStore.load() else { return [String: Any]() }
                return try DataExport.object(from: settings)
            },
            .windDownHistory: {
                let format = ISO8601DateFormatter()
                return i.windDownStore.sessions().map { ["start": format.string(from: $0.start), "plannedMinutes": $0.plannedMinutes, "completed": $0.completed] as [String: Any] }
            },
            .journal: { try JournalExport.object(from: i.journal) },
            .coachHistory: {
                guard let data = await i.coachHistory?.exportJSON() else { return [Any]() }
                return try JSONSerialization.jsonObject(with: data)
            },
        ]
    }

    private static func inventory(_ id: DataCategoryID) -> DataCategory { DataInventory.shared[id] }
}

private extension String {
    /// "Journal" → "journal"; "Coach conversations" → "coach conversations".
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
