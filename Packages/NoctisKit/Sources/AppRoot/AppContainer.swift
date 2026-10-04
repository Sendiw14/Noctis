import CoachFeature
import CoachKit
import DesignSystem
import Foundation
import HealthProviding
import HomeFeature
import InsightsFeature
import JournalKit
import NightFeature
import NightKit
import NoctisCore
import NoctisIntentKit
import NoctisWidgetKit
import ProfileFeature
import RecoveryFeature
import SleepFeature
import SoundKit
import SwiftData
import UserNotifications
import WidgetKit

public struct AppContainer {
    public let model: AppModel
    public let homeViewModel: HomeViewModel
    public let sleepViewModel: SleepViewModel
    public let recoveryViewModel: RecoveryViewModel
    public let insightsViewModel: InsightsViewModel
    /// The insights kept on this device and the repository that fills them:
    /// Home and the Insights tab both read them.
    public let insightStore: InsightStore
    public let insightsRepository: InsightsRepository
    /// Coach's front door: question in, validated answer out. There is no
    /// Coach UI yet (ROADMAP.md); the tab will read this and nothing else.
    public let coachService: AIService
    /// The Coach tab's view model.
    public let coachViewModel: CoachViewModel
    /// The wake alarm: authorization, schedule and what the system says about it.
    public let alarmService: AlarmService
    /// What the Tonight screen reads.
    public let tonightViewModel: TonightViewModel
    public let profileViewModel: ProfileViewModel
    public let settingsViewModel: SettingsViewModel
    /// Data management: what NOCTIS keeps, one kind at a time or all of it, and a copy to take away.
    public let dataManager: DataManager
    /// A new one each time the app starts over (after "Delete all NOCTIS data"), so the screens are made again.
    public let generation = UUID()
    /// The sleep sounds: the one player that holds the audio engine, and what the Sounds screen reads.
    public let soundPlayer: SoundPlayer
    public let soundsViewModel: SoundsViewModel
    /// The wind-down session.
    public let windDownViewModel: WindDownViewModel
    /// The breathing exercise, opened from the wind-down.
    public let breathingViewModel: BreathingViewModel
    /// The meditation, opened from the wind-down.
    public let meditationViewModel: MeditationViewModel
    /// Reflect and the Journal: kept in a store of their own, on this device only.
    public let journalViewModel: JournalViewModel
    /// The typed preferences (R38) and the reminders built from them.
    public let preferences: AppPreferences
    public let notificationCoordinator: NotificationCoordinator
    /// Opens Wind-down when the evening notification is tapped.
    private let notificationRouter: NotificationRouter
    public let storeManager: StoreManager
    public let modelContainer: ModelContainer

    /// `restarted`: the app starts over after "Delete all NOCTIS data", as a first launch would (a DEBUG launch flag that skips or
    /// resets onboarding no longer applies).
    public init(restarted: Bool = false) {
        NoctisDataRegistry.shared.reset()
        // The launch budgets start counting here.
        NoctisSignpost.begin(.launchToFirstFrame)
        NoctisSignpost.begin(.launchToPopulated)
        self.storeManager = StoreManager()
        let container: ModelContainer
        do {
            // Never synced: the profile, the alarm and the wind-down record stay on this device.
            container = try ModelContainer(
                for: UserProfileRecord.self, AlarmConfiguration.self, WindDownSession.self,
                configurations: ModelConfiguration(groupContainer: .none, cloudKitDatabase: .none)
            )
        } catch {
            fatalError("Failed to initialize the local data store: \(error)")
        }
        self.modelContainer = container

        let profileStore = ProfileStore(context: ModelContext(container))

        // The real HealthKit provider in every build. DEBUG builds can opt
        // into the mock (and its failure-injection flags) with
        // `-useMockHealth` or `-mockScenario <name>`; the mock doesn't
        // exist in Release at all.
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let debug = DebugLaunchOptions(arguments: arguments)
        let provider: any HealthDataProviding
        if let scenario = debug.mockScenario {
            provider = MockHealthKitProvider(
                scenario: scenario,
                // The mock forgets its permission between launches; a
                // finished onboarding already granted it.
                startAuthorized: !debug.unauthorized
                    && ((debug.skipOnboarding && !restarted) || (profileStore.load().healthAuthorizationRequested && !debug.resetState)),
                isHealthDataAvailable: !debug.healthUnavailable,
                failsQueries: debug.healthQueryFails,
                latency: debug.mockLatency
            )
        } else {
            provider = HealthKitProvider()
        }
        self.model = AppModel(healthProvider: provider, profileStore: profileStore)
        // UI tests: behave like a fresh install (no onboarding draft, no
        // finished profile) without reinstalling the app between runs.
        if debug.resetState && !restarted {
            let defaults = NoctisUserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("noctis.") {
                defaults.removeObject(forKey: key)
            }
            model.updateProfile { $0 = UserProfileSnapshot() }
        }
        if debug.skipOnboarding && !restarted {
            model.updateProfile {
                $0.onboardingComplete = true
                $0.healthAuthorizationRequested = true
            }
        }
        if let route = debug.initialRoute, !restarted {
            model.open(route)
        }
        #else
        let provider = HealthKitProvider()
        self.model = AppModel(healthProvider: provider, profileStore: profileStore)
        #endif

        let model = self.model
        #if DEBUG
        let modeOverride = debug.homeMode
        #else
        let modeOverride: HomeMode? = nil
        #endif

        // What NOCTIS keeps that comes from Health, each registered so Data
        // Management (ROADMAP.md) can erase it. The saved Home snapshot
        // lets the next launch draw Home in its first frame; the mock
        // provider (DEBUG) skips it unless `-noctisSnapshotCache` asks.
        #if DEBUG
        // Before the view model reads Low Power Mode for the first time.
        if debug.lowPowerMode { HomeViewModel.debugForcesLowPower = true }
        #endif
        // The v1 insight history (UserDefaults) is gone: the stored insights hold it now.
        NoctisUserDefaults.standard.removeObject(forKey: "noctis.insights.history")
        #if DEBUG
        let keepsSnapshot = debug.mockScenario == nil || debug.snapshotCache
        let snapshotStore: HomeSnapshotStore? = keepsSnapshot ? HomeSnapshotStore() : nil
        #else
        let snapshotStore: HomeSnapshotStore? = HomeSnapshotStore()
        #endif
        if let snapshotStore { NoctisDataRegistry.shared.register(snapshotStore) }
        #if DEBUG
        // UI tests: a fresh install has no saved snapshot either. (Before
        // the repository reads it.)
        if debug.resetState { snapshotStore?.erase() }
        #endif
        // The insights: derived numbers only, complete file protection,
        // excluded from backups, and erased with the rest. UI tests start
        // clean with `-noctisResetState`.
        let insightFile = InsightFileStore()
        NoctisDataRegistry.shared.register(insightFile)
        #if DEBUG
        if debug.resetState { insightFile.erase() }
        #endif
        let insightStore = InsightStore(file: insightFile)
        self.insightStore = insightStore
        let insightsRepo = InsightsRepository(provider: provider, store: insightStore)
        self.insightsRepository = insightsRepo
        // The widgets' summary (R44): one small file in the App Group, written after every refresh of Home's data. It is
        // erased with the rest; UI tests start without one.
        let widgetStore = WidgetSnapshotStore()
        #if DEBUG
        if debug.resetState && !restarted { widgetStore?.delete() }
        #endif
        let widgetInputs = WidgetInputSource(profile: { await MainActor.run { model.profile } })
        let widgetPublisher = WidgetPublisher(store: widgetStore, inputs: widgetInputs, reload: { WidgetCenter.shared.reloadAllTimelines() })
        // The repositories the tabs read: Coach reads the same snapshots (R20).
        let homeRepository = HomeRepository(provider: provider, insights: insightsRepository, store: snapshotStore, widgets: widgetPublisher)
        let sleepRepository = SleepRepository(provider: provider)
        let recoveryRepository = RecoveryRepository(provider: provider)
        self.homeViewModel = HomeViewModel(
            repository: homeRepository,
            profile: { model.profile },
            // "Connect Apple Health" reuses onboarding's authorization flow.
            connectHealth: { await model.requestHealthAuthorization() },
            modeOverride: modeOverride
        )
        self.sleepViewModel = SleepViewModel(
            repository: sleepRepository,
            profile: { model.profile },
            connectHealth: { await model.requestHealthAuthorization() }
        )
        self.recoveryViewModel = RecoveryViewModel(
            repository: recoveryRepository,
            profile: { model.profile },
            connectHealth: { await model.requestHealthAuthorization() }
        )
        self.insightsViewModel = InsightsViewModel(
            repository: insightsRepository,
            profile: { model.profile },
            connectHealth: { await model.requestHealthAuthorization() }
        )

        // Coach (R29). Its history is local only, protected, out of backups and
        // registered so Data Management can erase it; if it can't be opened,
        // Coach still answers, it just keeps nothing.
        let coachHistory: CoachHistoryStore?
        if let container = try? CoachHistoryContainer.make() {
            let erasure = CoachHistoryErasure(container: container)
            NoctisDataRegistry.shared.register(erasure)
            #if DEBUG
            if debug.resetState { erasure.erase() }
            #endif
            coachHistory = CoachHistoryStore(modelContainer: container)
        } else {
            coachHistory = nil
        }
        #if DEBUG
        // `-mockAI good|misbehaving|slow|unavailable` plays a script; a mock
        // Health scenario without it answers from the template alone, so a
        // test's answer never depends on whether this Mac has a model.
        let coachModel: (any AIProvider)? = debug.mockAI.map { MockAIProvider(mode: $0) } ?? (debug.mockScenario == nil ? Self.systemModel() : nil)
        #else
        let coachModel: (any AIProvider)? = Self.systemModel()
        #endif
        let coachData = RepositoryCoachDataSource(home: homeRepository, sleep: sleepRepository, recovery: recoveryRepository, insights: insightsRepository)
        let coachService = AIService(
            format: HomeFormat(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent),
            dataSource: coachData,
            profile: { await MainActor.run { model.profile } },
            model: coachModel,
            history: coachHistory
        )
        self.coachService = coachService
        let coachVM = CoachViewModel(
            service: coachService,
            dataSource: coachData,
            history: coachHistory,
            profile: { model.profile },
            connectHealth: { await model.requestHealthAuthorization() }
        )
        self.coachViewModel = coachVM
        // The wake alarm (R30): the record is local, the system's alarms are AlarmKit's. A mock
        // Health scenario gets a pretend alarm system too, so a screenshot or a test never opens
        // a system prompt; `-mockAlarm real` asks for the real one anyway.
        let alarmStore = AlarmConfigurationStore(context: ModelContext(container))
        #if DEBUG
        if debug.resetState { alarmStore.erase() }
        let alarmBackend: any AlarmBackend = debug.alarmBackend()
        #else
        let alarmBackend: any AlarmBackend = AlarmKitBackend()
        #endif
        let alarmService = AlarmService(backend: alarmBackend, store: alarmStore, defaultMinutes: { await MainActor.run { model.profile.typicalWakeMinutes } })
        self.alarmService = alarmService
        self.tonightViewModel = TonightViewModel(
            sleep: sleepRepository, alarm: alarmService, profile: { model.profile },
            format: HomeFormat(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
        )
        // The preferences (R38). Read after `-noctisResetState` has cleared what a fresh install would not have.
        let preferences = AppPreferences()
        self.preferences = preferences
        NoctisHaptics.isEnabled = preferences.values.appHaptics
        // The reminders: the system's centre (a scripted one in DEBUG when a mock scenario or flag asks), the
        // bedtime engine's centre for the wind-down reminder, rebuilt whenever something they depend on changes.
        #if DEBUG
        let notificationCenter: any NotificationCentering = debug.makeNotificationCenter()
        #else
        let notificationCenter: any NotificationCentering = SystemNotificationCenter()
        #endif
        let coordinator = NotificationCoordinator(
            scheduler: NotificationScheduler(center: notificationCenter), preferences: preferences, profile: { model.profile },
            bedtimeCenter: { wake, need in
                let snapshot = await sleepRepository.refresh(profile: model.profile)
                return BedtimeInputsBuilder.recommendation(
                    wakeMinutes: wake, needMinutes: need, timing: snapshot.timing, balance: snapshot.balance,
                    consistency: snapshot.consistency, now: Date(), timeZone: .autoupdatingCurrent
                ).centerMinutes
            }
        )
        self.notificationCoordinator = coordinator
        model.onProfileChange = {
            coordinator.reschedule()
            Task { await widgetPublisher.republish() }
        }
        // Background updates (R46): Apple Health wakes the app when new sleep data arrives; the refresh writes the widgets' summary
        // and reloads their timelines. Best-effort: iOS decides when. Nothing runs before setup is finished or without access.
        let backgroundRefresher = BackgroundRefresher(
            isOnboarded: { await MainActor.run { model.profile.onboardingComplete } },
            isAuthorized: { await provider.authorizationStatus() == .authorized },
            refresh: { _ = await homeRepository.refresh(profile: await MainActor.run { model.profile }) }
        )
        let background = provider as? any HealthBackgroundDelivering
        let startBackgroundUpdates: @Sendable () async -> Void = {
            await background?.startBackgroundDelivery { done in
                Task {
                    _ = await backgroundRefresher.handleWake()
                    done()
                }
            }
        }
        model.onHealthAuthorizationRequested = { await startBackgroundUpdates() }
        // A launch (including one Health started in the background) registers again: the observers live only as long as the process.
        if model.profile.onboardingComplete { Task { await startBackgroundUpdates() } }
        // The widgets show tonight's bedtime and the alarm: the recommendation Tonight shows (from the Sleep tab's last
        // numbers, so no extra read of Health) and the alarm as it stands, redrawn when either changes.
        widgetInputs.setBedtime { profile in
            guard let snapshot = await sleepRepository.cachedSnapshot else { return nil }
            return BedtimeInputsBuilder.recommendation(
                wakeMinutes: profile.typicalWakeMinutes, needMinutes: profile.needMinutes, timing: snapshot.timing, balance: snapshot.balance,
                consistency: snapshot.consistency, now: Date(), timeZone: .autoupdatingCurrent
            )
        }
        widgetInputs.setAlarm { WidgetSnapshotMaker.alarm(await alarmService.status().settings) }
        Task {
            for await _ in await alarmService.updates() { await widgetPublisher.republish() }
        }
        // Profile (R36): the person's own words about their sleep, and the state of Health, reminders and the plan.
        self.profileViewModel = ProfileViewModel(
            sleep: sleepRepository, alarm: alarmService, health: HealthDataStatusReader(provider: provider), profile: { model.profile },
            edit: { model.apply($0) }, notifications: coordinator, preferences: preferences,
            entitlements: storeManager.entitlementManager, format: HomeFormat(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
        )
        // Sleep sounds (R31): the real engine, or in DEBUG a silent one that still renders the real
        // sounds for the meter, so a screenshot or a UI test makes no noise.
        #if DEBUG
        let soundPlayer = debug.makeSoundPlayer()
        #else
        let soundPlayer = SoundPlayer(
            engine: AVSoundEngineDriver(), session: AVSoundSession(), nowPlaying: MediaNowPlaying(), defaults: NoctisUserDefaults.standard
        )
        #endif
        soundPlayer.setDefaultGain(preferences.values.soundsGain)
        self.soundPlayer = soundPlayer
        self.soundsViewModel = SoundsViewModel(player: soundPlayer, defaultTimer: { preferences.values.soundsTimer })
        // The Sleep sounds control (R48) is told what the one player does, so it shows what is true. At launch nothing plays: a record left by a
        // process the system ended is removed by the first state it sees.
        let sleepSoundsPublisher = SleepSoundsPublisher(store: SleepSoundsStore(), reload: { ControlCenter.shared.reloadControls(ofKind: ControlKind.sleepSounds) })
        soundPlayer.observe { sleepSoundsPublisher.apply($0) }
        sleepSoundsPublisher.apply(soundPlayer.state)
        let windDownStore = WindDownSessionStore(context: ModelContext(container))
        let windDown = WindDownViewModel(
            player: soundPlayer, alarm: alarmService, store: windDownStore, idle: ApplicationIdleTimer(),
            preferences: preferences
        )
        self.windDownViewModel = windDown
        #if DEBUG
        let breathingHaptics = debug.makeBreathingHaptics()
        #else
        let breathingHaptics: any BreathingHapticsPlaying = CoreHapticsBreathing()
        #endif
        let breathing = BreathingViewModel(haptics: breathingHaptics, preferences: preferences)
        self.breathingViewModel = breathing
        #if DEBUG
        let meditationAudio = debug.makeMeditationAudio(soundPlayer: soundPlayer)
        #else
        let meditationAudio: any MeditationAudioPlaying = SystemMeditationAudio(isSoundActive: { soundPlayer.state.isLoaded })
        #endif
        let meditation = MeditationViewModel(audio: meditationAudio, player: soundPlayer)
        self.meditationViewModel = meditation
        // The journal (R35): its own store, opened when first needed, and registered so Data Management reaches it.
        #if DEBUG
        let journalProvider = debug.makeJournalProvider()
        let journalStore = debug.makeJournalStore(provider: journalProvider)
        #else
        let journalProvider = JournalContainerProvider()
        let journalStore: any JournalStoring = JournalStore(provider: journalProvider)
        #endif
        NoctisDataRegistry.shared.register(JournalErasure(provider: journalProvider))
        let journal = JournalViewModel(store: journalStore)
        self.journalViewModel = journal
        #if DEBUG
        debug.applySoundScript(to: soundPlayer)
        debug.applyWindDownScript(to: windDown)
        debug.applyBreathingScript(to: breathing)
        debug.applyMeditationScript(to: meditation)
        debug.applyJournalScript(to: journal)
        #endif
        // What a change of preference has to touch.
        preferences.onChange = { change in
            switch change {
            case .notifications: coordinator.reschedule()
            case .haptics: NoctisHaptics.isEnabled = preferences.values.appHaptics
            case .sounds: soundPlayer.setDefaultGain(preferences.values.soundsGain)
            case .appearance, .windDown, .breathing: break
            }
        }
        // A tap on the evening notification opens Wind-down.
        let router = NotificationRouter(model: model)
        self.notificationRouter = router
        UNUserNotificationCenter.current().delegate = router

        // Siri, Shortcuts and the controls (R47): the intents ask this running app, through the objects the screens use. Installed at start,
        // so an intent that launches the app in the background finds it.
        IntentRuntime.shared.install(
            AppIntentHost(model: model, preferences: preferences, player: soundPlayer, sounds: self.soundsViewModel, alarm: alarmService, controls: sleepSoundsPublisher)
        )

        // Data management (R41, R42): every store given an eraser and an exporter, and "Delete all NOCTIS data" its steps.
        let dataManager = DataWiring.manager(DataWiringInputs(
            model: model, preferences: preferences, defaults: NoctisUserDefaults.standard, profileStore: profileStore, alarmService: alarmService,
            alarmStore: alarmStore, windDownStore: windDownStore, journal: journalStore, coachHistory: coachHistory, insightFile: insightFile,
            snapshotStore: snapshotStore, notifications: NotificationScheduler(center: notificationCenter),
            appVersion: {
                let info = Bundle.main.infoDictionary
                return "NOCTIS \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
            },
            stopAudio: {
                soundPlayer.stop()
                if meditation.isActive { meditation.end() }
                breathing.end()
            },
            endWindDown: { windDown.end() },
            silenceReminders: {
                preferences.onChange = nil
                model.onProfileChange = nil
                Task { await widgetPublisher.suspend() }
            },
            settleReminders: { await coordinator.settled() },
            afterJournalDeleted: { journal.load() },
            afterCoachDeleted: { await coachVM.loadHistory() },
            clearMemory: {
                await homeRepository.clearCache()
                await sleepRepository.clearCache()
                await recoveryRepository.clearCache()
                await insightsRepo.clearCache()
            },
            forgetSoundChoices: {
                soundPlayer.forgetSavedGains()
                meditation.forgetChoices()
            },
            widgets: widgetPublisher,
            reloadWidgets: { WidgetCenter.shared.reloadAllTimelines() },
            sleepSounds: sleepSoundsPublisher,
            reloadControls: { ControlCenter.shared.reloadAllControls() },
            endLiveActivities: { await LiveActivities.endAll() },
            stopBackgroundUpdates: {
                model.onHealthAuthorizationRequested = nil
                await background?.stopBackgroundDelivery()
            }
        ))
        self.dataManager = dataManager
        // Settings (R36): the preferences, the system's answers and the store, each row wired to something that works.
        #if DEBUG
        if let summary = debug.subscriptionSummary() { storeManager.entitlementManager.debugSet(summary) }
        #endif
        self.settingsViewModel = SettingsViewModel(
            preferences: preferences, notifications: coordinator, store: storeManager, health: HealthDataStatusReader(provider: provider),
            alarm: alarmService, profile: { model.profile }, connectHealth: { await model.requestHealthAuthorization() },
            hapticsAvailable: { breathing.hapticsAvailable }, format: HomeFormat(calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent),
            data: dataManager
        )

        #if DEBUG
        if debug.logHomeSnapshot {
            homeViewModel.debugLogsSnapshots = true
        }
        if let seconds = debug.homeModeFlipIn {
            homeViewModel.debugFlipMode(after: seconds)
        }
        #endif
    }
}

extension AppContainer {
    /// The on-device model (Apple Intelligence), where this OS has it.
    static func systemModel() -> (any AIProvider)? {
        #if canImport(FoundationModels)
        FoundationModelsProvider(backend: SystemLanguageModelBackend())
        #else
        nil
        #endif
    }
}

#if DEBUG
/// DEBUG-only launch arguments (UI tests and simulator checks).
struct DebugLaunchOptions {
    let mockScenario: MockScenario?
    let skipOnboarding: Bool
    let resetState: Bool
    let healthUnavailable: Bool
    let healthQueryFails: Bool
    let initialRoute: AppRoute?
    let logHomeSnapshot: Bool
    /// `-mockUnauthorized`: Health access not granted (Home's connect card).
    let unauthorized: Bool
    /// `-mockLatency <seconds>`: slow mock sleep queries (Home's skeleton).
    let mockLatency: Duration
    /// `-homeMode day|evening`: pin Home's mode instead of the clock's.
    let homeMode: HomeMode?
    /// `-homeModeFlipIn <seconds>`: flip Home day ↔ evening once, after
    /// that long (the mode morph on demand).
    let homeModeFlipIn: Double?
    /// `-noctisSnapshotCache`: keep and restore the saved Home snapshot
    /// with the mock provider too (it's off for mocks so UI tests don't
    /// see each other's data).
    let snapshotCache: Bool
    /// `-noctisLowPowerMode`: Home behaves as under Low Power Mode, which
    /// the simulator can't turn on.
    let lowPowerMode: Bool
    /// `-mockAI good|misbehaving|slow|unavailable`: Coach's model plays a script.
    let mockAI: MockAIProvider.Mode?
    /// `-mockAlarm authorized|notDetermined|willDeny|denied|unavailable|failing|limitReached`: the
    /// alarm system plays a script; `real` is AlarmKit itself.
    let mockAlarm: MockAlarmBackend.Mode?
    let realAlarm: Bool
    /// `-mockSound silent|playing:rain|interrupted:ocean|timer:rain:30|real:wind`.
    let mockSound: MockSoundScript?
    /// `-mockWindDown prestart|running:0.3|running:0.5:reduce|finished`, and `:sounds` or `:breathing` on
    /// the end of a `running` one opens that over the session.
    let mockWindDown: String?
    /// `-mockBreathing prestart[:box][:haptics]|running:calm:5[:paused][:2min][:haptics]|finished`.
    let mockBreathing: String?
    /// `-mockMeditation prestart[:bodyScan][:10min][:spoken]|running:bodyScan:10:80[:paused]|finished[:quietMind]`.
    let mockMeditation: String?
    /// `-mockNotifications granted|denied|notDetermined|willDeny`: the notification centre plays a script
    /// (a mock Health scenario with no flag gets one that is already allowed), so the system's question never opens.
    let mockNotifications: String?
    /// `-mockSubscription free|monthly|yearly|trial|ending|grace`: a fixed subscription state (the simulator has no purchase).
    let mockSubscription: String?
    /// `-mockJournal empty|filled|unavailable[:journal][:draft]`: an in-memory journal, with or without entries; `:journal` opens on the list, `:draft` fills in the form.
    let mockJournal: String?

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let name = value(after: "-mockScenario") {
            mockScenario = MockScenario(rawValue: name) ?? .full
        } else {
            mockScenario = arguments.contains("-useMockHealth") ? .full : nil
        }
        skipOnboarding = arguments.contains("-noctisSkipOnboarding")
        resetState = arguments.contains("-noctisResetState")
        healthUnavailable = arguments.contains("-noctisHealthUnavailable")
        healthQueryFails = arguments.contains("-noctisHealthQueryFails")
        initialRoute = value(after: "-noctisInitialRoute").flatMap { AppRoute(name: $0) }
        logHomeSnapshot = arguments.contains("-noctisLogHomeSnapshot")
        unauthorized = arguments.contains("-mockUnauthorized")
        mockLatency = .seconds(value(after: "-mockLatency").flatMap(Double.init) ?? 0)
        homeMode = value(after: "-homeMode").flatMap(HomeMode.init(rawValue:))
        homeModeFlipIn = value(after: "-homeModeFlipIn").flatMap(Double.init)
        snapshotCache = arguments.contains("-noctisSnapshotCache")
        lowPowerMode = arguments.contains("-noctisLowPowerMode")
        mockAI = value(after: "-mockAI").flatMap(MockAIProvider.Mode.init(launchValue:))
        mockAlarm = value(after: "-mockAlarm").flatMap(MockAlarmBackend.Mode.init(launchValue:))
        realAlarm = value(after: "-mockAlarm") == "real"
        mockSound = value(after: "-mockSound").flatMap(MockSoundScript.init(argument:))
        mockWindDown = value(after: "-mockWindDown")
        mockBreathing = value(after: "-mockBreathing")
        mockMeditation = value(after: "-mockMeditation")
        mockJournal = value(after: "-mockJournal")
        mockNotifications = value(after: "-mockNotifications")
        mockSubscription = value(after: "-mockSubscription")
    }

    /// The summary the flag names, for the Subscription page's every state.
    func subscriptionSummary() -> SubscriptionSummary? {
        guard let mockSubscription else { return nil }
        let ends = Calendar.current.date(byAdding: .day, value: 23, to: Date())
        switch mockSubscription {
        case "monthly": return SubscriptionSummary(isPremium: true, plan: .monthly, willRenew: true, endDate: ends)
        case "yearly": return SubscriptionSummary(isPremium: true, plan: .yearly, willRenew: true, endDate: ends)
        case "trial": return SubscriptionSummary(isPremium: true, plan: .yearly, isTrial: true, willRenew: true, endDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()))
        case "ending": return SubscriptionSummary(isPremium: true, plan: .yearly, willRenew: false, endDate: ends)
        case "grace": return SubscriptionSummary(isPremium: true, plan: .monthly, willRenew: true, endDate: ends, isInGracePeriod: true)
        default: return .free
        }
    }

    /// A session already in the state the flag names, so every state can be looked at.
    @MainActor
    func applyWindDownScript(to model: WindDownViewModel) {
        guard let script = mockWindDown else { return }
        let parts = script.split(separator: ":").map(String.init)
        switch parts.first {
        case "running":
            model.debugBegin(
                progress: parts.dropFirst().first.flatMap(Double.init) ?? 0, reducedMotion: parts.contains("reduce"),
                opening: parts
            )
        case "finished":
            model.debugFinish()
        default:
            break
        }
    }

    /// Real Core Haptics, or (with `:haptics`) a silent stand-in that says it has them, so the switch can
    /// be looked at on a simulator.
    @MainActor
    func makeBreathingHaptics() -> any BreathingHapticsPlaying {
        if let script = mockBreathing, script.split(separator: ":").contains("haptics") { return SilentBreathingHaptics(available: true) }
        return CoreHapticsBreathing()
    }

    /// Silent whenever a mock scenario or a `-mockMeditation` script is on, so a screenshot or a UI test makes no
    /// sound; `spoken` in the script says there is a voice to offer.
    @MainActor
    func makeMeditationAudio(soundPlayer: SoundPlayer) -> any MeditationAudioPlaying {
        if mockMeditation != nil || mockScenario != nil {
            return SilentMeditationAudio(canSpeak: mockMeditation?.split(separator: ":").contains("spoken") ?? false)
        }
        return SystemMeditationAudio(isSoundActive: { soundPlayer.state.isLoaded })
    }

    /// The notification centre: the system's, or a scripted one in memory.
    func makeNotificationCenter() -> any NotificationCentering {
        guard mockNotifications != nil || mockScenario != nil else { return SystemNotificationCenter() }
        switch mockNotifications {
        case "denied": return InMemoryNotificationCenter(authorization: .denied)
        case "notDetermined": return InMemoryNotificationCenter(authorization: .notDetermined)
        case "willDeny": return InMemoryNotificationCenter(authorization: .notDetermined, answer: false)
        default: return InMemoryNotificationCenter(authorization: .allowed)
        }
    }

    /// Memory, never disk, whenever a mock scenario or a `-mockJournal` script is on.
    func makeJournalProvider() -> JournalContainerProvider {
        JournalContainerProvider(inMemory: mockJournal != nil || mockScenario != nil)
    }

    @MainActor
    func makeJournalStore(provider: JournalContainerProvider) -> any JournalStoring {
        guard mockJournal != nil || mockScenario != nil else { return JournalStore(provider: provider) }
        let words = mockJournal?.split(separator: ":").map(String.init) ?? []
        let store = MemoryJournalStore(words.contains("filled") ? Self.sampleJournal() : [])
        store.failing = words.contains("unavailable")
        return store
    }

    /// A few entries over the last days, for a screenshot.
    @MainActor
    static func sampleJournal() -> [JournalEntrySnapshot] {
        let now = Date()
        func entry(_ daysAgo: Double, hour: Int, energy: Int?, mood: Int?, focus: Int?, _ text: String) -> JournalEntrySnapshot {
            let day = now.addingTimeInterval(-daysAgo * 86_400)
            let date = Calendar.current.date(bySettingHour: hour, minute: 40, second: 0, of: day) ?? day
            return JournalEntrySnapshot(id: UUID(), date: date, energy: energy, mood: mood, focus: focus, text: text)
        }
        return [
            entry(0, hour: 22, energy: 3, mood: 4, focus: 2, "A slow day. Walked in the evening."),
            entry(1, hour: 23, energy: 2, mood: 3, focus: nil, ""),
            entry(2, hour: 22, energy: nil, mood: nil, focus: nil, "Long day, early start tomorrow."),
            entry(4, hour: 21, energy: 5, mood: 5, focus: 4, "Felt clear all afternoon."),
        ]
    }

    /// The journal as the flag says.
    @MainActor
    func applyJournalScript(to model: JournalViewModel) {
        guard let script = mockJournal else { return }
        let words = script.split(separator: ":")
        if words.contains("draft") { model.debugFillDraft() }
        if words.contains("journal") { model.debugOpenJournal() }
    }

    /// A meditation already in the state the flag names.
    @MainActor
    func applyMeditationScript(to model: MeditationViewModel) {
        guard let script = mockMeditation else { return }
        let parts = script.split(separator: ":").map(String.init)
        let category = parts.compactMap(MeditationCategory.init(rawValue:)).first ?? .bodyScan
        let minutes = parts.compactMap { $0.hasSuffix("min") ? Int($0.dropLast(3)) : nil }.first
        switch parts.first {
        case "running":
            let numbers = parts.compactMap(Double.init)
            model.debugBegin(category: category, minutes: Int(numbers.first ?? 10), seconds: numbers.dropFirst().first ?? 0, paused: parts.contains("paused"))
        case "finished":
            model.debugBegin(category: category, minutes: minutes ?? 5, seconds: 100_000)
        case "prestart":
            model.choose(category: category)
            if let minutes { model.choose(minutes: minutes) }
        default:
            break
        }
    }

    /// An exercise already in the state the flag names.
    @MainActor
    func applyBreathingScript(to model: BreathingViewModel) {
        guard let script = mockBreathing else { return }
        let parts = script.split(separator: ":").map(String.init)
        let pattern = parts.compactMap(BreathingPattern.ID.init(rawValue:)).first
        let minutes = parts.compactMap { $0.hasSuffix("min") ? Int($0.dropLast(3)) : nil }.first ?? BreathingSchedule.defaultMinutes
        switch parts.first {
        case "running":
            let seconds = parts.dropFirst(2).first.flatMap(Double.init) ?? 0
            model.debugBegin(pattern: pattern ?? .calm, seconds: seconds, minutes: minutes, paused: parts.contains("paused"))
        case "finished":
            model.debugBegin(pattern: pattern ?? .calm, seconds: 100_000, minutes: minutes)
        case "prestart":
            if let pattern { model.choose(pattern: pattern) }
            model.choose(minutes: minutes)
        default:
            break
        }
    }

    /// The silent engine unless `-mockSound real:` asked for the real one; with a mock Health
    /// scenario and no flag it is silent too.
    @MainActor
    func makeSoundPlayer() -> SoundPlayer {
        let useReal = mockSound?.mode == .real || (mockSound == nil && mockScenario == nil)
        let defaults = NoctisUserDefaults.standard
        if useReal {
            return SoundPlayer(engine: AVSoundEngineDriver(), session: AVSoundSession(), nowPlaying: MediaNowPlaying(), defaults: defaults)
        }
        return SoundPlayer(engine: SilentSoundEngine(), session: SilentSoundSession(), nowPlaying: SilentNowPlaying(), defaults: defaults)
    }

    /// Starts what the script says: a sound playing, interrupted, on a timer, or the real engine at a whisper.
    @MainActor
    func applySoundScript(to player: SoundPlayer) {
        guard let script = mockSound else { return }
        switch script.mode {
        case .silent:
            break
        case .playing:
            player.play(script.kind)
        case .interrupted:
            player.play(script.kind)
            player.simulateInterruption()
        case .timer:
            player.play(script.kind)
            player.setTimer(SleepTimerChoice(rawValue: script.minutes) ?? .minutes30)
        case .real:
            // A whisper: this is for looking at the process's CPU, not for hearing.
            player.setGain(0.02, for: script.kind)
            player.play(script.kind)
        }
    }

    /// The alarm system for this launch: a script if asked, a permissive pretend one with a mock
    /// Health scenario, AlarmKit otherwise.
    func alarmBackend() -> any AlarmBackend {
        if realAlarm { return AlarmKitBackend() }
        if let mockAlarm { return MockAlarmBackend(mode: mockAlarm) }
        return mockScenario == nil ? AlarmKitBackend() : MockAlarmBackend(mode: .authorized)
    }
}
#endif
