import Foundation
import HealthProviding
import NoctisCore
import SwiftData

public struct AppContainer {
    public let model: AppModel
    public let storeManager: StoreManager
    public let modelContainer: ModelContainer

    public init() {
        self.storeManager = StoreManager()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: UserProfileRecord.self, InsightFatigueRecord.self)
        } catch {
            fatalError("Failed to initialize the local data store: \(error)")
        }
        self.modelContainer = container

        let context = ModelContext(container)
        let profileStore = ProfileStore(context: context)
        let insightFatigueStore = InsightFatigueStore(context: context)

        // The real HealthKit provider in every build. DEBUG builds can opt
        // into the mock (and its failure-injection flags) with
        // `-useMockHealth`; the mock doesn't exist in Release at all.
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let skipOnboarding = arguments.contains("-noctisSkipOnboarding")
        let provider: any HealthDataProviding
        if arguments.contains("-useMockHealth") {
            provider = MockHealthKitProvider(
                startAuthorized: skipOnboarding,
                isHealthDataAvailable: !arguments.contains("-noctisHealthUnavailable"),
                failsQueries: arguments.contains("-noctisHealthQueryFails")
            )
        } else {
            provider = HealthKitProvider()
        }
        self.model = AppModel(healthProvider: provider, profileStore: profileStore, insightFatigueStore: insightFatigueStore)
        // UI tests: behave like a fresh install (no onboarding draft, no
        // finished profile) without reinstalling the app between runs.
        if arguments.contains("-noctisResetState") {
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("noctis.") {
                defaults.removeObject(forKey: key)
            }
            model.updateProfile { $0 = UserProfileSnapshot() }
        }
        if skipOnboarding {
            model.updateProfile {
                $0.onboardingComplete = true
                $0.healthAuthorizationRequested = true
            }
        }
        if let tabIndex = arguments.firstIndex(of: "-noctisInitialTab"), arguments.count > tabIndex + 1,
           let tab = AppTab(rawValue: arguments[tabIndex + 1]) {
            model.selectedTab = tab
        }
        #else
        self.model = AppModel(healthProvider: HealthKitProvider(), profileStore: profileStore, insightFatigueStore: insightFatigueStore)
        #endif
    }
}
