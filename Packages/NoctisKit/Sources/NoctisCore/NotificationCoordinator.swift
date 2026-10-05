import Foundation
import Observation
import PremiumKit
import SwiftUI

/// Keeps the reminders matching what the person has chosen (APP_RULES.md R38). It reads the preferences, the
/// wake time and sleep need, and the bedtime engine's centre, and asks the scheduler to rebuild. It runs when
/// any of those change, when the app comes back to the front (the centre moves a little as nights come in), and
/// once permission is given. Rebuilds run one after another, so a slow one can never land after a newer one.
@MainActor
@Observable
public final class NotificationCoordinator {
    /// What the system says about notifications, as of the last look.
    public private(set) var authorization: NotificationAuthorization = .notDetermined
    /// What the last rebuild scheduled.
    public private(set) var scheduled: [ScheduledNotification] = []

    @ObservationIgnored private let scheduler: NotificationScheduler
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let profile: () -> UserProfileSnapshot
    /// The bedtime engine's centre for a wake time and a sleep need, in minutes since midnight.
    @ObservationIgnored private let bedtimeCenter: (Int, Int) async -> Int
    /// The person's plan: it picks the evening reminder's words, and the reminders are rebuilt when it changes.
    @ObservationIgnored private let tier: () -> Tier
    @ObservationIgnored private var chain: Task<Void, Never>?

    public init(
        scheduler: NotificationScheduler, preferences: AppPreferences, profile: @escaping () -> UserProfileSnapshot,
        bedtimeCenter: @escaping (Int, Int) async -> Int, tier: @escaping () -> Tier = { .free }
    ) {
        self.scheduler = scheduler
        self.preferences = preferences
        self.profile = profile
        self.bedtimeCenter = bedtimeCenter
        self.tier = tier
    }

    /// Looks at the system's answer again (Settings may have changed it behind the app's back).
    public func refreshAuthorization() async {
        authorization = await scheduler.authorization()
    }

    /// Asks the system, once, then rebuilds if the answer was yes. The system never asks twice.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        let granted = await scheduler.requestAuthorization()
        authorization = await scheduler.authorization()
        if granted { reschedule() }
        return granted
    }

    /// Rebuilds the reminders. The wake time and need can be given where the profile doesn't hold them yet
    /// (onboarding, before it completes).
    public func reschedule(wakeMinutes: Int? = nil, needMinutes: Int? = nil) {
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            await self?.rebuild(wakeMinutes: wakeMinutes, needMinutes: needMinutes)
        }
    }

    /// Waits for the rebuilds in flight (for tests).
    public func settled() async {
        await chain?.value
    }

    private func rebuild(wakeMinutes: Int?, needMinutes: Int?) async {
        let current = profile()
        let wake = wakeMinutes ?? current.typicalWakeMinutes
        let need = needMinutes ?? current.needMinutes
        let center = await bedtimeCenter(wake, need)
        scheduled = await scheduler.rebuild(preferences: preferences.values.notifications, wakeMinutes: wake, bedtimeCenterMinutes: center, tier: tier())
        authorization = await scheduler.authorization()
    }
}

private struct NotificationCoordinatorKey: EnvironmentKey {
    static let defaultValue: NotificationCoordinator? = nil
}

extension EnvironmentValues {
    /// The reminders' coordinator, where the app has put it; nil in a preview or a test that has not.
    public var notificationCoordinator: NotificationCoordinator? {
        get { self[NotificationCoordinatorKey.self] }
        set { self[NotificationCoordinatorKey.self] = newValue }
    }
}
