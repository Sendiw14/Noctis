import Foundation
import HealthProviding
import HomeFeature
import NoctisCore
import SwiftData

public struct AppContainer {
    public let model: AppModel
    public let homeViewModel: HomeViewModel
    public let storeManager: StoreManager
    public let modelContainer: ModelContainer

    public init() {
        self.storeManager = StoreManager()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: UserProfileRecord.self)
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
        self.homeViewModel = HomeViewModel(
            repository: HomeRepository(provider: provider),
            profile: { model.profile },
            // "Connect Apple Health" reuses onboarding's authorization flow.
            connectHealth: { await model.requestHealthAuthorization() },
            modeOverride: modeOverride
        )
        #if DEBUG
        if debug.logHomeSnapshot {
            homeViewModel.debugLogsSnapshots = true
        }
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
        initialRoute = value(after: "-noctisInitialRoute").flatMap(AppRoute.init(rawValue:))
        logHomeSnapshot = arguments.contains("-noctisLogHomeSnapshot")
        unauthorized = arguments.contains("-mockUnauthorized")
        mockLatency = .seconds(value(after: "-mockLatency").flatMap(Double.init) ?? 0)
        homeMode = value(after: "-homeMode").flatMap(HomeMode.init(rawValue:))
    }
}
#endif
