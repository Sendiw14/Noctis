import Foundation
import HealthProviding
import Observation
import InsightsKit
import PremiumKit
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
    /// What is free and what is Premium, where the app has put it (nil in a test that does not care: everything is open).
    @ObservationIgnored public var featureGate: FeatureGate?
    /// Whether a wind-down session is running (the app says). A session that began while the plan included it always finishes, so a lapse never blocks it.
    @ObservationIgnored public var isWindDownRunning: () -> Bool = { false }
    /// The paywall, while it is open: only after a tap on a locked element or on "What Premium includes", never on launch or on entering a tab (R58).
    public var paywall: PaywallContext?
    private var serial = 0
    /// Told after the profile changes (the wake time or the need moves the reminders).
    @ObservationIgnored public var onProfileChange: (() -> Void)?
    /// Told after the person has answered Apple Health's question, so background delivery can start (APP_RULES.md R46).
    @ObservationIgnored public var onHealthAuthorizationRequested: (() async -> Void)?

    let healthProvider: any HealthDataProviding
    private let profileStore: ProfileStore

    public init(healthProvider: any HealthDataProviding, profileStore: ProfileStore) {
        self.healthProvider = healthProvider
        self.profileStore = profileStore
        self.profile = profileStore.load()
    }

    /// The person's plan (Premium with no gate: a test that does not care sees everything).
    public var tier: Tier { featureGate?.tier ?? .premium }

    /// Whether `feature` is shown in full (always, with no gate).
    public func isUnlocked(_ feature: Feature) -> Bool { featureGate?.isUnlocked(feature) ?? true }

    /// A factor's detail from a card on Recovery (the tab's stack) or Home: Premium. A free person gets the paywall, saying what it unlocks, and nothing is pushed (R58).
    public func openRecoveryFactorOnTab(_ kind: RecoveryFactorKind, range: RecoveryFactorRange) {
        guard isUnlocked(.recoveryFactorDetail) else { return presentPaywall(for: .recoveryFactorDetail) }
        recoveryPath.append(.factor(kind, range: range))
    }

    public func openRecoveryFactorOverHome(_ kind: RecoveryFactorKind, range: RecoveryFactorRange) {
        guard isUnlocked(.recoveryFactorDetail) else { return presentPaywall(for: .recoveryFactorDetail) }
        homePath.append(.recoveryFactor(kind, range: range))
    }

    /// The wind-down session is Premium; a running one is never shut out.
    private var mayOpenWindDown: Bool { isUnlocked(.windDownSession) || isWindDownRunning() }

    /// A locked thing was tapped: the paywall opens over the screen, saying what it unlocks.
    public func presentPaywall(_ context: PaywallContext) { paywall = context }

    public func presentPaywall(for feature: Feature) { paywall = PaywallContext(feature: feature) }

    /// What a link from outside opens (a locked widget, the Watch, Siri: R62). A screen opens as it always did. The paywall sheet opens only after setup is finished and
    /// only for a person who is not Premium (a Premium person who taps a stale locked widget lands on Home); it never starts a purchase.
    public func open(_ destination: WidgetURLRouter.Destination) {
        switch destination {
        case .screen(let route): open(route)
        case .paywall(let context):
            guard isOnboarded else { return }
            if tier == .premium {
                open(.home)
            } else {
                presentPaywall(context)
            }
        }
    }

    public func dismissPaywall() { paywall = nil }

    public var isOnboarded: Bool { profile.onboardingComplete }
    public var isHealthDataAvailable: Bool { healthProvider.isHealthDataAvailable }

    public func requestHealthAuthorization(for kinds: [HealthDataKind] = HealthDataKind.allCases) async {
        healthAuthorization = await healthProvider.requestAuthorization(for: kinds)
        profile.healthAuthorizationRequested = true
        profileStore.save(profile)
        await onHealthAuthorizationRequested?()
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

    /// Forgets the profile in memory only, after its record has been deleted: setup is not finished and nothing is told or saved.
    public func forgetProfileInMemory() {
        profile = UserProfileSnapshot()
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
        // Back from a page goes to Settings, then Profile, then Home.
        case .settings(let section): homePath = section == .root ? [.profile, .settings(.root)] : [.profile, .settings(.root), .settings(section)]
        case .home: homePath = []
        case .tonight: homePath = [.tonight]
        // A link or a notification never opens the Premium session for a free person: it lands on Tonight, where the button is marked (no paywall: nothing was tapped).
        case .windDown(let autostart): homePath = mayOpenWindDown ? [.tonight, .windDown(autostart: autostart)] : [.tonight]
        case .sounds: homePath = [.tonight, .sounds]
        case .alarm:
            serial += 1
            alarmDestination = AlarmDestination(serial: serial)
            homePath = [.tonight]
        case .sleep(let night, let range):
            serial += 1
            sleepDestination = SleepDestination(night: night, range: range, serial: serial)
        case .recovery(let requested, let requestedFactor):
            // A link never opens what is Premium for a free person: 30 and 90 days fall back to 7, a factor's detail to the tab (no paywall: nothing was tapped).
            let range: RecoverySegment = switch requested {
            case .month: isUnlocked(.recovery30D) ? .month : .week
            case .quarter: isUnlocked(.recovery90D) ? .quarter : .week
            default: requested
            }
            let factor = isUnlocked(.recoveryFactorDetail) ? requestedFactor : nil
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
        case .reviews:
            insightsPath = [.reviews]
        case .review(let kind, let id):
            // The story decides what a plan sees: a free person's weekly review is its cover, and their monthly review is one calm locked page (no paywall: nothing was tapped).
            insightsPath = [.review(kind: kind, id: id)]
        case .coach(let question):
            serial += 1
            coachDestination = CoachDestination(question: question, serial: serial)
            coachPath = []
        }
    }

    /// Opens Coach on a question given as text (an App Intent): the same path as `open(.coach)`, with the words held in memory until the
    /// tab takes them. Coach's own limit on a question's length applies there; nothing here keeps the text.
    public func askCoach(_ text: String) {
        selectedTab = AppRoute.coach().tab
        serial += 1
        coachDestination = CoachDestination(question: nil, text: text, serial: serial)
        coachPath = []
    }

    /// Stacks `route` on whatever Home's stack is showing, so a screen's own way out returns to where the
    /// person was: the wind-down opened from Home goes back to Home, and from Tonight to Tonight. Unlike
    /// `open`, which builds the destination's own path (what a deep link or a notification wants). A second
    /// tap on the same route does nothing.
    public func push(_ route: HomeRoute) {
        selectedTab = .home
        if case .windDown = route, !mayOpenWindDown { return presentPaywall(.windDown) }
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

    /// A review's story is the screen showing: it is full-screen on purpose, so nothing of the app's chrome (the tab bar, the bedtime pill above it) may sit over it.
    public var isReviewStoryShowing: Bool {
        guard selectedTab == .insights, case .review? = insightsPath.last else { return false }
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
