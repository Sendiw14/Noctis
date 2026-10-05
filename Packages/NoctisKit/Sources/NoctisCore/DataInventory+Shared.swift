import Foundation
import NoctisWidgetKit
import PremiumKit

nonisolated extension DataInventory {
    /// What NOCTIS keeps. Hand-written, and held to the code by `DataInventoryTests` (APP_RULES.md R41): add a store, a
    /// defaults key or a network API and a test fails until it is described here.
    public static let shared = DataInventory(
        categories: [
            DataCategory(
                .appleHealth, name: "Apple Health data",
                summary: "Your sleep, heart rate, resting heart rate, heart rate variability and respiratory rate, which NOCTIS reads from Apple Health. It only reads: it never writes to Health, and it keeps no copy of the readings.",
                contents: ["Sleep, with its stages and times", "Heart rate", "Resting heart rate", "Heart rate variability", "Respiratory rate"],
                locations: [.system("Apple Health")],
                coach: .facts([
                    "Your recovery score today and what it's built from: sleep, HRV, resting heart rate and bedtime consistency.",
                    "Last night's sleep: how long, how well, and the share of deep and REM sleep.",
                    "Your usual bedtime and wake time.",
                    "This week's average night, your sleep balance and how much your bedtime varies.",
                ]),
                inBackup: false, protection: .appleManaged, deletion: .inApple("the Health app"),
                owner: "HealthProviding/HealthKitProvider.swift", holdsUserContent: false,
                export: .notStored("NOCTIS keeps no copy of your Health readings. They stay in Apple Health.")
            ),
            DataCategory(
                .cachedSummaries, name: "Cached summaries",
                summary: "The last numbers Home showed, kept so Home can draw before Apple Health answers. They are worked out from your Health data and rebuilt each time: no individual reading is kept.",
                contents: [
                    "Your recovery score and the numbers behind it", "Last night's summary and the shape of its chart",
                    "This week's sleep durations", "A smoothed heart rate curve",
                ],
                locations: [.file(.applicationSupport, "Noctis/home-snapshot.json")],
                inBackup: false, protection: .completeWhileLocked, deletion: .button("Cached summaries"),
                owner: "NoctisCore/HomeSnapshotStore.swift", holdsUserContent: false, export: .included("cachedSummaries")
            ),
            DataCategory(
                .widgetSnapshot, name: "Widget summary",
                summary: "A small file NOCTIS writes for its widgets and for your Apple Watch, so they can draw without opening the app: your recovery score and what it is built from, last night's sleep in brief, tonight's bedtime and your wake alarm. It holds worked-out numbers only: no Health reading, no time a reading was made, no name of a source, nothing from your Journal and nothing Coach said. Widgets on the Lock Screen hide the Health numbers while your iPhone is locked. It also holds one word saying whether you are on the free plan or Premium, so a widget or your Apple Watch can show what your plan includes without asking the App Store; nothing about a purchase is kept in it. If you have an Apple Watch with NOCTIS on it, the same summary is sent to it, and only to it.",
                contents: [
                    "Your recovery score, how it compares with your usual, and the four arcs of its ring", "How each of the four recovery factors scored, its value last night and your usual for it",
                    "Last night's sleep: how long, its stages and when it began and ended", "Your resting heart rate and heart rate variability for last night",
                    "Tonight's bedtime and your usual wake time", "Your wake alarm's time, and whether it is on",
                    "How many nights your usual is built from, and the time of your last \"Delete all NOCTIS data\"",
                "A free or Premium flag (goes only to your own Apple Watch)",
                ],
                locations: [.file(.appGroup, "WidgetSnapshot.json")],
                destination: .pairedWatch("to your own paired Apple Watch, over Bluetooth or Wi-Fi, through Apple's WatchConnectivity. It is never sent to a server."),
                inBackup: false, protection: .standard, deletion: .button("Cached summaries"),
                owner: "NoctisWidgetKit/WidgetSnapshotStore.swift", holdsUserContent: false, export: .included("widgetSnapshot")
            ),
            DataCategory(
                .watchSync, name: "Apple Watch status and settings",
                summary: "Small notes about your Apple Watch: when NOCTIS last sent it the summary, the day your Watch face's complication was last refreshed for, and, kept on the Watch itself, whether breathing on the Watch plays haptics. They hold no Health value.",
                contents: [
                    "When the summary was last sent to your Apple Watch", "Which day, and whether it had a recovery, the complication was last refreshed for",
                    "Whether breathing on your Apple Watch plays haptics (kept on the Watch, and reset when you delete all NOCTIS data)",
                ],
                locations: [.defaults([WatchSyncDefaults.lastSentAtKey, WatchSyncDefaults.complicationMarkKey, WatchPreferenceKeys.breathHaptics])],
                inBackup: true, protection: .standard, deletion: .button("Cached summaries"),
                owner: "NoctisCore/WatchSync/WatchSyncDefaults.swift", holdsUserContent: false, export: .included("watchSync")
            ),
            DataCategory(
                .sleepSoundsState, name: "Sleep sounds status",
                summary: "A tiny file NOCTIS writes for the Sleep sounds control in Control Center, so the control can show whether a sound is playing. It exists only while a sound plays, and when a sleep timer is set it holds the time the timer ends. It holds no sound name and nothing about what you played before, and it is removed as soon as the sound stops.",
                contents: ["That a sound is playing right now", "When the sleep timer ends, if one is set"],
                locations: [.file(.appGroup, "SleepSoundsState.json")],
                inBackup: false, protection: .standard,
                deletion: .automatic("It is removed when the sound stops, and when you delete all NOCTIS data."),
                owner: "NoctisWidgetKit/SleepSoundsState.swift", holdsUserContent: false, export: .included("sleepSoundsState")
            ),
            DataCategory(
                .insightHistory, name: "Insights history",
                summary: "The insights NOCTIS has found about your sleep and whether you have seen them: each one's type and the numbers behind it, worked out from your Health data.",
                contents: ["Each insight's type and its numbers", "Whether it is new, seen or dismissed"],
                locations: [.file(.applicationSupport, "Noctis/insights.json")],
                coach: .facts(["The insights NOCTIS has already found, as numbers."]),
                inBackup: false, protection: .completeWhileLocked, deletion: .button("Insights history"),
                owner: "NoctisCore/InsightStore.swift", holdsUserContent: false, export: .included("insightHistory")
            ),
            DataCategory(
                .reviews, name: "Reviews",
                summary: "The weekly and monthly reviews NOCTIS has made, worked out from your Health data: for each, its dates and the numbers behind it. They stay on this iPhone, and Coach cannot read them.",
                contents: [
                    "For each review: the dates it covers and the numbers it is made of (sleep, bedtimes, recovery, how the nights compare)", "Which insights it points to, by id",
                    "Whether you have opened it",
                ],
                locations: [.file(.applicationSupport, "Noctis/reviews.json")],
                inBackup: false, protection: .completeWhileLocked, deletion: .button("Reviews"),
                owner: "NoctisCore/ReviewStore.swift", holdsUserContent: false, export: .included("reviews")
            ),
            DataCategory(
                .memorySummaries, name: "Summaries in memory",
                summary: "The recovery, sleep, Home and insight summaries the app holds while it is open. They are rebuilt from Apple Health and are never written to disk.",
                contents: ["Recovery, sleep, Home and insight summaries, as they were last worked out"],
                locations: [.memory],
                inBackup: false, protection: .notOnDisk, deletion: .automatic("They are gone when the app is closed, and when you delete cached summaries."),
                owner: "NoctisCore/HomeRepository.swift", holdsUserContent: false,
                export: .notStored("They are held in memory only and are rebuilt from Apple Health.")
            ),
            DataCategory(
                .profile, name: "Your profile",
                summary: "What you told NOCTIS when you set it up, and what you have changed since.",
                contents: ["Your name, if you gave one", "Your sleep need and your usual wake time", "Your goals", "Whether setup is finished, and whether Apple Health has been asked"],
                locations: [.database(.applicationSupport, "default.store")], entities: ["UserProfileRecord"],
                coach: .facts(["Your sleep need, your usual wake time and your goals, to say when you should go to bed. Never your name."]),
                inBackup: true, protection: .standard, deletion: .withEverything,
                owner: "NoctisCore/UserProfileRecord.swift", holdsUserContent: true, export: .included("profile")
            ),
            DataCategory(
                .preferences, name: "Preferences",
                summary: "The choices you make in Settings.",
                contents: [
                    "Appearance and app haptics", "Wind-down length and sound", "Breathing pattern, length and haptics",
                    "Sleep sounds' starting volume and timer", "Which reminders are on, and when",
                ],
                locations: [.defaults([
                    "noctis.pref.appearance", "noctis.pref.appHaptics", "noctis.winddown.minutes", "noctis.winddown.sound",
                    "noctis.breathing.pattern", "noctis.breathing.minutes", "noctis.breathing.haptics", "noctis.pref.sounds.gainPercent",
                    "noctis.pref.sounds.timerMinutes", "noctis.pref.notifications.morning.on", "noctis.pref.notifications.morning.minutes",
                    "noctis.pref.notifications.winddown.on", "noctis.pref.notifications.winddown.lead", "noctis.pref.notifications.weekly.on",
                    "noctis.pref.notifications.weekly.weekday", "noctis.pref.notifications.weekly.time",
                ])],
                inBackup: true, protection: .standard, deletion: .button("Preferences and goals"),
                owner: "NoctisCore/AppPreferences.swift", holdsUserContent: true, export: .included("preferences")
            ),
            DataCategory(
                .soundSettings, name: "Sound and meditation choices",
                summary: "The volume you last used for each sleep sound, the sound you played last, and what you last chose in Meditation.",
                contents: ["Each sound's volume", "The sleep sound you played last", "The last meditation category, length and sound", "Whether spoken guidance is on"],
                locations: [.defaults([
                    "noctis.sounds.gains", "noctis.sounds.last", "noctis.meditation.category", "noctis.meditation.minutes", "noctis.meditation.sound", "noctis.meditation.spoken",
                ])],
                inBackup: true, protection: .standard, deletion: .button("Preferences and goals"),
                owner: "SoundKit/SoundPlayer.swift", holdsUserContent: true, export: .included("soundSettings")
            ),
            DataCategory(
                .appState, name: "Small app flags",
                summary: "Small markers so the app does a thing once a day or once ever: the day Home last played its opening animation, whether you have seen Coach's introduction, where you were in setup, which plan tier the App Store last reported (free or premium, one word), and how many of the free Coach questions you have used today (a count and a date, never a question).",
                contents: [
                    "The last day each tab played its opening animation", "Whether Coach's first-run card was seen", "Setup answers not yet saved",
                    "The plan tier the App Store last reported: free, premium or lapsed", "The date, and how many free Coach questions were used that day",
                ],
                locations: [.defaults([
                    "noctis.home.lastWashDay", "noctis.home.lastIntroDay", "noctis.sleep.lastWashDay", "noctis.sleep.lastIntroDay",
                    "noctis.recovery.lastWashDay", "noctis.recovery.lastIntroDay", "noctis.insights.lastWashDay", "noctis.insights.lastIntroDay",
                    "noctis.coach.lastWashDay", "noctis.coach.firstRunSeen", "noctis.onboarding.step", "noctis.onboarding.selectedGoals",
                    "noctis.onboarding.wakeMinutes", "noctis.onboarding.needMinutes", "noctis.onboarding.sleepGoalHours",
                    PremiumKeys.cachedTier, PremiumKeys.coachQuota,
                ])],
                inBackup: true, protection: .standard, deletion: .withEverything,
                owner: "HomeFeature/HomeViewModel.swift", holdsUserContent: false, export: .included("appState")
            ),
            DataCategory(
                .alarm, name: "Wake alarm",
                summary: "The wake alarm you set: its time, the days it repeats and its snooze. The alarm itself is held by iOS (AlarmKit) so it can ring when NOCTIS is closed.",
                contents: ["The alarm's time, repeat days and snooze", "Whether it is on"],
                locations: [.database(.applicationSupport, "default.store"), .system("AlarmKit")], entities: ["AlarmConfiguration"],
                inBackup: true, protection: .standard, deletion: .withEverything,
                owner: "NoctisCore/AlarmConfiguration.swift", holdsUserContent: true, export: .included("alarm")
            ),
            DataCategory(
                .windDownHistory, name: "Wind-down history",
                summary: "A record of the wind-downs you have done: when each started, how long it was planned for and whether you finished it.",
                contents: ["The start time of each wind-down", "Its planned length", "Whether it was completed"],
                locations: [.database(.applicationSupport, "default.store")], entities: ["WindDownSession"],
                inBackup: true, protection: .standard, deletion: .button("Wind-down history"),
                owner: "NoctisCore/WindDownSession.swift", holdsUserContent: true, export: .included("windDownHistory")
            ),
            DataCategory(
                .journal, name: "Journal",
                summary: "What you chose to note about a day: how you felt and what you wrote. It has a store of its own. Only the Journal's own screens read it, and \"Export my data\" when you ask for a copy.",
                contents: ["Each entry's date", "Your energy, mood and focus ratings, if you gave them", "What you wrote"],
                locations: [.database(.applicationSupport, "Noctis/Journal/journal.store")], entities: ["JournalEntry"],
                inBackup: false, protection: .completeWhileLocked, deletion: .button("Journal"),
                owner: "JournalKit/JournalStore.swift", holdsUserContent: true, export: .included("journal")
            ),
            DataCategory(
                .coachHistory, name: "Coach conversations",
                summary: "The questions you asked Coach and the answers it gave, so you can read them again.",
                contents: ["Each question you asked", "Coach's answer, and a short summary of it", "Whether you marked it helpful"],
                locations: [.database(.applicationSupport, "Noctis/CoachHistory/coach-history.store")], entities: ["AIConversation", "AIMessage"],
                inBackup: false, protection: .completeWhileLocked, deletion: .button("Coach history"),
                owner: "CoachKit/CoachHistory.swift", holdsUserContent: true, export: .included("coachHistory")
            ),
            DataCategory(
                .reminders, name: "Scheduled reminders",
                summary: "The reminders NOCTIS has asked iOS to show: the morning summary, the wind-down reminder, the weekly review and, during a free trial, a reminder before it ends. They say only generic words and never carry a number from Health.",
                contents: ["When each reminder fires", "Its generic words"],
                locations: [.system("the iOS notification centre")],
                notificationIdentifiers: [
                    "noctis.notification.morningSummary", "noctis.notification.windDown", "noctis.notification.weeklyReview",
                    "noctis.notification.trialEnding",
                ],
                inBackup: false, protection: .appleManaged, deletion: .withEverything,
                owner: "NoctisCore/NotificationScheduler.swift", holdsUserContent: false,
                export: .notStored("They are rebuilt from your preferences, your wake time and your bedtime.")
            ),
            DataCategory(
                .diagnosticLog, name: "Diagnostic log",
                summary: "Short lines NOCTIS writes to the iPhone's own log, such as \"paywall viewed\" or \"the alarm was scheduled\". They hold no Health value, no name and no text you wrote. They stay in the log on this iPhone, which only you can share, for example in a diagnostics report.",
                contents: ["Which screen or step happened (the paywall, onboarding, the alarm)", "A plan name when you choose a plan"],
                locations: [.system("the iPhone's unified log")],
                inBackup: false, protection: .appleManaged, deletion: .automatic("iOS clears its log by itself."),
                owner: "NoctisCore/Analytics/NoctisAnalytics.swift", holdsUserContent: false,
                export: .notStored("It is written to the iPhone's own log, not kept by NOCTIS.")
            ),
            DataCategory(
                .purchases, name: "Subscription",
                summary: "Whether you have Premium, and which plan. Apple's App Store keeps this, with your Apple Account. NOCTIS asks the App Store each time it opens; the only thing it keeps itself is one word, free or premium, in the small app flags, so the screens open the right way before the App Store has answered.",
                contents: ["Your plan and its dates, held by the App Store"],
                locations: [.system("the App Store")],
                destination: .apple("the App Store"),
                inBackup: false, protection: .appleManaged, deletion: .inApple("Manage subscription"),
                owner: "NoctisCore/Store/StoreManager.swift", holdsUserContent: false,
                export: .notStored("The App Store holds your subscription, not NOCTIS.")
            ),
            DataCategory(
                .systemFiles, name: "Files iOS makes for the app",
                summary: "Files Apple's frameworks and iOS keep for NOCTIS, not NOCTIS itself: a cache of compiled graphics shaders, the screen state iOS restores, and a small picture of the app's last screen for the app switcher. That picture can show whatever was on screen, such as your recovery score.",
                contents: ["A cache of compiled graphics shaders", "Saved screen state", "A picture of the app's last screen, for the app switcher"],
                locations: [.folder(.caches, "com.noctis.app"), .system("iOS (saved screen state and the app switcher's picture)")],
                inBackup: false, protection: .appleManaged, deletion: .automatic("iOS replaces or clears them by itself. \"Delete all NOCTIS data\" clears the cache folder, and deleting the app removes the rest."),
                owner: "NoctisCore/DataInventory.swift", holdsUserContent: false,
                export: .notStored("They are made and kept by iOS, not by NOCTIS.")
            ),
            DataCategory(
                .exportFile, name: "Export file",
                summary: "The file \"Export my data\" makes, when you ask for it. NOCTIS writes it to a temporary place and deletes it when you leave Data management and the next time it starts.",
                contents: ["A copy of what NOCTIS stores, in one JSON file"],
                locations: [.file(.temporary, "NOCTIS-export.json")],
                destination: .onlyIfYouSend("wherever you choose to share it"),
                inBackup: false, protection: .standard, deletion: .automatic("NOCTIS deletes it when you leave Data management, and the next time it starts."),
                owner: "NoctisCore/DataExport.swift", holdsUserContent: false,
                export: .notStored("It is the export itself.")
            ),
        ],
        flows: [
            DataFlow(
                id: "supportEmail", title: "Contact support",
                detail: "If you tap Contact support and send the email, your mail app sends it to NOCTIS's support address with the app's version, build number and iOS version, and what you write. NOCTIS does not add anything else.",
                trigger: .onlyWhenYouChoose, categories: []
            ),
            DataFlow(
                id: "exportFile", title: "Export my data",
                detail: "The export file stays on this iPhone unless you share it. Where it goes then is up to you.",
                trigger: .onlyWhenYouChoose, categories: [.exportFile]
            ),
            DataFlow(
                id: "shareCard", title: "Share this night",
                detail: "Home's share card makes a picture of a night's summary. It stays on this iPhone unless you share it.",
                trigger: .onlyWhenYouChoose, categories: [.cachedSummaries]
            ),
            DataFlow(
                id: "appStore", title: "Subscription",
                detail: "Buying, restoring and managing Premium happen through Apple's App Store with your Apple Account. NOCTIS sends it nothing about your sleep or health.",
                trigger: .byApple, categories: [.purchases]
            ),
            DataFlow(
                id: "appleWatch", title: "Apple Watch",
                detail: "A summary of your recovery and sleep is sent to your Apple Watch, if you have one with NOCTIS on it: your recovery score and what it is built from, last night's sleep in brief, tonight's bedtime and your alarm. It goes over Bluetooth or Wi-Fi to your own Watch, through Apple's WatchConnectivity, and never to a server. \"Delete all NOCTIS data\" wipes it from the Watch too.",
                trigger: .toYourWatch, categories: [.widgetSnapshot]
            ),
            DataFlow(
                id: "deviceBackup", title: "Device backups",
                detail: "If you back up this iPhone to iCloud or a computer, Apple's backup may include your profile, preferences, alarm and wind-down history. Cached summaries, insights, the Journal and Coach conversations are left out of backups.",
                trigger: .byApple, categories: [.profile, .preferences, .soundSettings, .appState, .alarm, .windDownHistory]
            ),
        ],
        networkUses: [
            NetworkUse(
                token: "import StoreKit", purpose: "Buying, restoring and managing Premium through Apple's App Store.",
                files: [
                    "NoctisCore/Store/StoreManager.swift", "NoctisCore/Store/EntitlementClient.swift", "OnboardingFeature/PaywallScreen.swift",
                    "ProfileFeature/SettingsPages.swift", "ProfileFeature/SettingsScreens.swift", "ProfileFeature/DataManagementViews.swift",
                ],
                categories: [.purchases]
            ),
            NetworkUse(
                token: "import WatchConnectivity", purpose: "Sending the summary to your own paired Apple Watch, and nowhere else: the Watch asks for an update, and the iPhone answers it.",
                files: ["NoctisCore/WatchSync/WCSessionDriver.swift", "NOCTISWatch/WatchSnapshotReceiver.swift"], categories: [.widgetSnapshot]
            ),
            NetworkUse(
                token: "import MessageUI", purpose: "The mail composer behind Contact support: it sends only if you send the email.",
                files: ["ProfileFeature/SettingsScreens.swift"], categories: []
            ),
        ],
        groups: [
            DeletableGroup(
                id: "journal", title: "Journal", verb: .delete, categories: [.journal],
                removes: "Every entry you have written in the Journal: its dates, ratings and words.",
                keeps: "Your sleep data, your Coach history and the rest of NOCTIS are not affected.", from: "this iPhone",
                question: "Delete your Journal?", confirm: "Delete Journal", done: "Journal deleted."
            ),
            DeletableGroup(
                id: "coach", title: "Coach history", verb: .delete, categories: [.coachHistory],
                removes: "Every question you asked Coach and every answer it gave.",
                keeps: "Your sleep data, your Journal and the rest of NOCTIS are not affected.", from: "this iPhone",
                question: "Delete Coach history?", confirm: "Delete Coach history", done: "Coach history deleted."
            ),
            DeletableGroup(
                id: "insights", title: "Insights history", verb: .delete, categories: [.insightHistory],
                removes: "The insights NOCTIS has found, and whether you have seen them. New ones are found again as new nights arrive.",
                keeps: "Your Health data, your Journal and the rest of NOCTIS are not affected.", from: "this iPhone",
                question: "Delete insights history?", confirm: "Delete insights history", done: "Insights history deleted."
            ),
            DeletableGroup(
                id: "reviews", title: "Reviews", verb: .delete, categories: [.reviews],
                removes: "Every weekly and monthly review NOCTIS has made, and whether you opened it. A recent one can be made again from your Health data when you ask for it.",
                keeps: "Your Health data, your Insights, your Journal and the rest of NOCTIS are not affected.", from: "this iPhone",
                question: "Delete your reviews?", confirm: "Delete reviews", done: "Reviews deleted."
            ),
            DeletableGroup(
                id: "windDown", title: "Wind-down history", verb: .delete, categories: [.windDownHistory],
                removes: "The record of the wind-downs you have done: when each started, its planned length and whether you finished it.",
                keeps: "Your Journal, your alarm and the rest of NOCTIS are not affected.", from: "this iPhone",
                question: "Delete wind-down history?", confirm: "Delete wind-down history", done: "Wind-down history deleted."
            ),
            DeletableGroup(
                id: "cache", title: "Cached summaries", verb: .delete, categories: [.cachedSummaries, .widgetSnapshot, .watchSync, .memorySummaries],
                removes: "The saved summary Home draws when it opens, the summary your widgets and your Apple Watch draw, and the summaries the app holds in memory. They are rebuilt from Apple Health.",
                keeps: "Your Health data is untouched, and so is the rest of NOCTIS.", from: "this iPhone",
                question: "Delete cached summaries?", confirm: "Delete cached summaries", done: "Cached summaries deleted."
            ),
            DeletableGroup(
                id: "preferences", title: "Preferences and goals", verb: .reset, categories: [.preferences, .soundSettings],
                removes: "Your preferences go back to their defaults: appearance, haptics, wind-down and sound defaults, and reminders. Your goals go back to Better sleep.",
                keeps: "Your name, sleep need, wake time, alarm, Journal and the rest of NOCTIS are kept.", from: "this iPhone",
                question: "Reset preferences and goals?", confirm: "Reset preferences and goals", done: "Preferences and goals reset."
            ),
        ],
        retiredKeys: ["noctis.insights.history"],
        facts: DataInventoryFacts(
            healthAccess: .readOnly, hasAccount: false, coachUsesRemoteModel: false,
            coachNeverSees: [
                "your name", "your Apple Account", "individual Health readings or when they were taken",
                "which app or device recorded them", "what you wrote in the Journal",
            ],
            survivesDeleteAll: [
                .init(
                    key: WatchSyncDefaults.dataEpochKey, what: "The time of your last \"Delete all NOCTIS data\", as one number.",
                    why: "So an Apple Watch that was away when you deleted can tell, when it connects again, that its copy is older than the delete and must be wiped. It holds nothing else."
                ),
            ],
            readsHealthInBackground: true
        )
    )
}
