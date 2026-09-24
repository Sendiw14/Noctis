import Foundation
import HealthProviding
import Observation

/// App-wide state: the profile, Health authorization and navigation.
/// Health data for the main app flows through `HomeRepository` instead.
@Observable
public final class AppModel {
    public private(set) var profile: UserProfileSnapshot
    public private(set) var healthAuthorization: HealthAuthorizationStatus = .notDetermined
    public var selectedTab: AppTab = .home
    /// The Home tab's navigation stack.
    public var homePath: [HomeRoute] = []

    let healthProvider: any HealthDataProviding
    private let profileStore: ProfileStore

    public init(healthProvider: any HealthDataProviding, profileStore: ProfileStore) {
        self.healthProvider = healthProvider
        self.profileStore = profileStore
        self.profile = profileStore.load()
    }

    public var isOnboarded: Bool { profile.onboardingComplete }
    public var healthSourceName: String { healthProvider.sourceName }
    public var isHealthDataAvailable: Bool { healthProvider.isHealthDataAvailable }

    public func requestHealthAuthorization(for kinds: [HealthDataKind] = HealthDataKind.allCases) async {
        healthAuthorization = await healthProvider.requestAuthorization(for: kinds)
        profile.healthAuthorizationRequested = true
        profileStore.save(profile)
    }

    public func completeOnboarding(_ snapshot: UserProfileSnapshot) async {
        var updated = snapshot
        updated.onboardingComplete = true
        profile = updated
        profileStore.save(updated)
    }

    public func updateProfile(_ transform: (inout UserProfileSnapshot) -> Void) {
        transform(&profile)
        profileStore.save(profile)
    }

    /// Shows `route`: selects its tab. Profile opens on Home's stack, as
    /// it does from the avatar button.
    public func open(_ route: AppRoute) {
        selectedTab = route.tab
        switch route {
        case .profile: homePath = [.profile]
        case .home: homePath = []
        case .sleep, .recovery, .insights, .coach: break
        }
    }
}
