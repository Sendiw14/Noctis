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
    /// The Recovery tab's navigation stack.
    public var recoveryPath: [RecoveryRoute] = []
    /// Where the Sleep tab should land, until it takes it (`takeSleepDestination`).
    public private(set) var sleepDestination: SleepDestination?
    /// The tab whose button was pressed while it was already showing.
    public private(set) var tabRetap: TabRetap?
    private var serial = 0

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
    /// it does from the avatar button; Sleep is handed the night and range.
    public func open(_ route: AppRoute) {
        selectedTab = route.tab
        switch route {
        case .profile: homePath = [.profile]
        case .home: homePath = []
        case .sleep(let night, let range):
            serial += 1
            sleepDestination = SleepDestination(night: night, range: range, serial: serial)
        case .recovery, .insights, .coach: break
        }
    }

    /// The Sleep destination waiting for the tab, once.
    public func takeSleepDestination() -> SleepDestination? {
        defer { sleepDestination = nil }
        return sleepDestination
    }

    /// A press on the tab that's already showing: each tab scrolls its own
    /// content back to the top.
    public func retap(_ tab: AppTab) {
        serial += 1
        tabRetap = TabRetap(tab: tab, serial: serial)
    }
}

/// Where in Sleep to land: a night (any moment of it) and a range. Each is
/// distinct, so opening the same place twice is still a change.
public nonisolated struct SleepDestination: Sendable, Equatable {
    public let night: Date?
    public let range: SleepRange
    let serial: Int
}

/// A press on the tab that was already showing.
public nonisolated struct TabRetap: Sendable, Equatable {
    public let tab: AppTab
    let serial: Int
}
