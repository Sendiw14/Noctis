import Foundation
import HealthProviding
import Observation
import InsightsKit
import RecoveryKit

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
    /// The Insights tab's navigation stack.
    public var insightsPath: [InsightsRoute] = []
    /// The Coach tab's navigation stack.
    public var coachPath: [CoachPage] = []
    /// Where the Sleep tab should land, until it takes it (`takeSleepDestination`).
    public private(set) var sleepDestination: SleepDestination?
    /// Where the Recovery tab should land, until it takes it.
    public private(set) var recoveryDestination: RecoveryDestination?
    /// Which chip the Insights tab should show, until it takes it.
    public private(set) var insightsDestination: InsightsDestination?
    /// The question the Coach tab should open on, until it takes it.
    public private(set) var coachDestination: CoachDestination?
    /// Whether Tonight should open the wake alarm's sheet, until it takes it.
    public private(set) var alarmDestination: AlarmDestination?
    /// The tab whose button was pressed while it was already showing.
    public private(set) var tabRetap: TabRetap?
    private var serial = 0
    /// Told after the profile changes (the wake time or the need moves the reminders).
    @ObservationIgnored public var onProfileChange: (() -> Void)?

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
        onProfileChange?()
    }

    public func updateProfile(_ transform: (inout UserProfileSnapshot) -> Void) {
        transform(&profile)
        profileStore.save(profile)
        onProfileChange?()
    }

    /// One edit from Profile: the name, the sleep need, the wake time or the goals.
    public func apply(_ edit: ProfileEdit) {
        updateProfile { edit.apply(to: &$0) }
    }

    /// Shows `route`: selects its tab. Profile opens on Home's stack, as
    /// it does from the avatar button; Sleep is handed the night and range.
    public func open(_ route: AppRoute) {
        selectedTab = route.tab
        switch route {
        case .profile: homePath = [.profile]
        case .home: homePath = []
        case .tonight: homePath = [.tonight]
        case .windDown(let autostart): homePath = [.tonight, .windDown(autostart: autostart)]
        case .sounds: homePath = [.tonight, .sounds]
        case .alarm:
            serial += 1
            alarmDestination = AlarmDestination(serial: serial)
            homePath = [.tonight]
        case .sleep(let night, let range):
            serial += 1
            sleepDestination = SleepDestination(night: night, range: range, serial: serial)
        case .recovery(let range, let factor):
            serial += 1
            recoveryDestination = RecoveryDestination(segment: range, factor: factor, serial: serial)
            // A factor's page is pushed over the tab's root.
            recoveryPath = factor.map { [.factor($0, range: range.factorRange)] } ?? []
        case .insights(let category):
            serial += 1
            insightsDestination = InsightsDestination(category: category, serial: serial)
            insightsPath = []
        case .insight(let id):
            // The page is pushed over the tab's root, on the chip it was on.
            insightsPath = [.insight(id: id)]
        case .coach(let question):
            serial += 1
            coachDestination = CoachDestination(question: question, serial: serial)
            coachPath = []
        }
    }

    /// Stacks `route` on whatever Home's stack is showing, so a screen's own way out returns to where the
    /// person was: the wind-down opened from Home goes back to Home, and from Tonight to Tonight. Unlike
    /// `open`, which builds the destination's own path (what a deep link or a notification wants). A second
    /// tap on the same route does nothing.
    public func push(_ route: HomeRoute) {
        selectedTab = .home
        guard homePath.last != route else { return }
        homePath.append(route)
    }

    /// Goes back to `route` where Home's stack already holds it (Settings' "Sleep profile" row returns to
    /// Profile), and pushes it where it doesn't.
    public func show(_ route: HomeRoute) {
        selectedTab = .home
        if let index = homePath.lastIndex(of: route) {
            homePath = Array(homePath[...index])
        } else {
            homePath.append(route)
        }
    }

    /// The wind-down is the screen showing: it is full-screen and dark on purpose, so nothing of the app's
    /// chrome (the tab bar, the bedtime pill above it) may sit over it.
    public var isWindDownShowing: Bool {
        guard selectedTab == .home, case .windDown? = homePath.last else { return false }
        return true
    }

    /// The alarm sheet request waiting for Tonight, once.
    public func takeAlarmDestination() -> AlarmDestination? {
        defer { alarmDestination = nil }
        return alarmDestination
    }

    /// The Coach destination waiting for the tab, once.
    public func takeCoachDestination() -> CoachDestination? {
        defer { coachDestination = nil }
        return coachDestination
    }

    /// The Insights destination waiting for the tab, once.
    public func takeInsightsDestination() -> InsightsDestination? {
        defer { insightsDestination = nil }
        return insightsDestination
    }

    /// The Recovery destination waiting for the tab, once.
    public func takeRecoveryDestination() -> RecoveryDestination? {
        defer { recoveryDestination = nil }
        return recoveryDestination
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

/// A request for Tonight to open the wake alarm's sheet. Each is distinct, so asking twice
/// is still a change.
public nonisolated struct AlarmDestination: Sendable, Equatable {
    let serial: Int
}

/// A press on the tab that was already showing.
public nonisolated struct TabRetap: Sendable, Equatable {
    public let tab: AppTab
    let serial: Int
}

/// Where in Recovery to land: a segment, and a factor's page when given.
public nonisolated struct RecoveryDestination: Sendable, Equatable {
    public let segment: RecoverySegment
    public let factor: RecoveryFactorKind?
    let serial: Int
}

/// Which chip Insights should show. Each is distinct, so opening the same
/// chip twice is still a change.
public nonisolated struct InsightsDestination: Sendable, Equatable {
    public let category: InsightCategory?
    let serial: Int
}
