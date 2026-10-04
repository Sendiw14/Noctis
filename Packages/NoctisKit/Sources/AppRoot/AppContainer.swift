import CoachFeature
import CoachKit
import DesignSystem
import Foundation
import HealthProviding
import HomeFeature
import InsightsFeature
import NightFeature
import NightKit
import NoctisCore
import RecoveryFeature
import SleepFeature
import SoundKit
import SwiftData
import UserNotifications

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
    /// The sleep sounds: the one player that holds the audio engine, and what the Sounds screen reads.
    public let soundPlayer: SoundPlayer
    public let soundsViewModel: SoundsViewModel
    /// Opens Wind-down when the evening notification is tapped.
    private let notificationRouter: NotificationRouter
    public let storeManager: StoreManager
    public let modelContainer: ModelContainer

    public init() {
        // The launch budgets start counting here.
        NoctisSignpost.begin(.launchToFirstFrame)
        NoctisSignpost.begin(.launchToPopulated)
        self.storeManager = StoreManager()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: UserProfileRecord.self, AlarmConfiguration.self)
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
                    && (debug.skipOnboarding || (profileStore.load().healthAuthorizationRequested && !debug.resetState)),
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
        if debug.resetState {
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("noctis.") {
                defaults.removeObject(forKey: key)
            }
            model.updateProfile { $0 = UserProfileSnapshot() }
        }
        if debug.skipOnboarding {
            model.updateProfile {
                $0.onboardingComplete = true
                $0.healthAuthorizationRequested = true
            }
        }
        if let route = debug.initialRoute {
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
        UserDefaults.standard.removeObject(forKey: "noctis.insights.history")
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
        self.insightsRepository = InsightsRepository(provider: provider, store: insightStore)
        // The repositories the tabs read: Coach reads the same snapshots (R20).
        let homeRepository = HomeRepository(provider: provider, insights: insightsRepository, store: snapshotStore)
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
        self.coachViewModel = CoachViewModel(
            service: coachService,
            dataSource: coachData,
            history: coachHistory,
            profile: { model.profile },
            connectHealth: { await model.requestHealthAuthorization() }
        )
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
        // Sleep sounds (R31): the real engine, or in DEBUG a silent one that still renders the real
        // sounds for the meter, so a screenshot or a UI test makes no noise.
        #if DEBUG
        let soundPlayer = debug.makeSoundPlayer()
        #else
        let soundPlayer = SoundPlayer(engine: AVSoundEngineDriver(), session: AVSoundSession(), nowPlaying: MediaNowPlaying())
        #endif
        self.soundPlayer = soundPlayer
        self.soundsViewModel = SoundsViewModel(player: soundPlayer)
        #if DEBUG
        debug.applySoundScript(to: soundPlayer)
        #endif
        // A tap on the evening notification opens Wind-down.
        let router = NotificationRouter(model: model)
        self.notificationRouter = router
        UNUserNotificationCenter.current().delegate = router

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
    }

    /// The silent engine unless `-mockSound real:` asked for the real one; with a mock Health
    /// scenario and no flag it is silent too.
    @MainActor
    func makeSoundPlayer() -> SoundPlayer {
        let useReal = mockSound?.mode == .real || (mockSound == nil && mockScenario == nil)
        let defaults = UserDefaults.standard
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
