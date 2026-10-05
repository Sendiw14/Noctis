import Foundation
import PremiumKit
import UserNotifications

// The repeating reminders (APP_RULES.md R38): when each fires, what each says, and the actor that keeps the
// system's pending list matching the preferences, the wake time and the bedtime engine's centre. Pure plan,
// a seam over the notification centre, then the actor.

/// One reminder as the system will hold it: an identifier, its generic words, and a wall-clock trigger.
public nonisolated struct ScheduledNotification: Sendable, Equatable {
    public let identifier: String
    public let title: String
    public let body: String
    /// Hour and minute (and a weekday for the weekly one), no date: the system fires it at that clock time
    /// every day (or week) in whatever time zone the phone is in, across daylight saving.
    public let components: DateComponents
    public let repeats: Bool

    public init(identifier: String, title: String, body: String, components: DateComponents, repeats: Bool = true) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.components = components
        self.repeats = repeats
    }
}

/// What the reminders are and when they fire. Pure: the same inputs give the same plan, and nothing in it
/// knows what a `Date` is until `nextFire` is asked.
public nonisolated enum NotificationPlan {
    /// The three identifiers this plan owns; nothing else in the pending list is ever touched.
    public static let identifiers = [NoctisNotification.morningSummary, NoctisNotification.windDown, NoctisNotification.weeklyReview]

    public static let title = "NOCTIS"
    public static let morningBody = "Your morning summary is ready."
    public static let weeklyBody = "Your weekly review is ready."

    /// The evening reminder's words by plan (APP_RULES.md R61): Premium has the wind-down, so its reminder names it ("Your wind-down window starts in 20
    /// minutes."); the free plan's names the bedtime ("Your bedtime window starts in 20 minutes."). Generic either way: a number of minutes the person
    /// chose, never a value from Health.
    public static func windDownBody(leadMinutes: Int, tier: Tier) -> String {
        switch tier {
        case .premium: "Your wind-down window starts in \(leadMinutes) minutes."
        case .free: "Your bedtime window starts in \(leadMinutes) minutes."
        }
    }

    /// The reminders that are on, in a stable order.
    /// - `wakeMinutes`: the typical wake time, minutes since midnight.
    /// - `bedtimeCenterMinutes`: the bedtime engine's centre (the one bedtime, or the middle of the window).
    /// - `tier`: the person's plan, which picks the evening reminder's words. The morning and weekly reminders say the same on both.
    public static func make(preferences: NotificationPreferences, wakeMinutes: Int, bedtimeCenterMinutes: Int, tier: Tier = .free) -> [ScheduledNotification] {
        let preferences = preferences.normalized()
        var plan: [ScheduledNotification] = []
        if preferences.morningIsOn {
            plan.append(ScheduledNotification(
                identifier: NoctisNotification.morningSummary, title: title, body: morningBody,
                components: clock(wakeMinutes + preferences.morningMinutesAfterWake)
            ))
        }
        if preferences.windDownIsOn {
            plan.append(ScheduledNotification(
                identifier: NoctisNotification.windDown, title: title, body: windDownBody(leadMinutes: preferences.windDownLeadMinutes, tier: tier),
                components: clock(bedtimeCenterMinutes - preferences.windDownLeadMinutes)
            ))
        }
        if preferences.weeklyIsOn {
            var components = clock(preferences.weeklyMinutesSinceMidnight)
            components.weekday = preferences.weeklyWeekday
            plan.append(ScheduledNotification(identifier: NoctisNotification.weeklyReview, title: title, body: weeklyBody, components: components))
        }
        return plan
    }

    /// A clock time from minutes since midnight, wrapped into the day: 23:50 plus 30 minutes is 00:20, and a
    /// bedtime at 00:10 less a 30 minute lead is 23:40.
    public static func clock(_ minutesSinceMidnight: Int) -> DateComponents {
        let wrapped = ((minutesSinceMidnight % 1440) + 1440) % 1440
        var components = DateComponents()
        components.hour = wrapped / 60
        components.minute = wrapped % 60
        return components
    }

    /// When `notification` next fires after `date`, the way a repeating calendar trigger does: at that wall
    /// clock time, so a day with a clock change still fires at the same time on the wall. A time the clock
    /// skips (02:30 as clocks go forward) fires at the next time that exists.
    public static func nextFire(of notification: ScheduledNotification, after date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: date, matching: notification.components, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
}

// MARK: - The notification centre, as a seam

public nonisolated enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    /// Allowed (including provisional and ephemeral): reminders can be scheduled.
    case allowed

    public var canSchedule: Bool { self == .allowed }
}

/// What the scheduler needs from the system's notification centre.
public nonisolated protocol NotificationCentering: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Shows the system's question (once; it never shows again). True if allowed.
    func requestAuthorization() async -> Bool
    func pendingIdentifiers() async -> [String]
    func removePending(_ identifiers: [String]) async
    func add(_ notification: ScheduledNotification) async
    /// Every pending reminder, and every one already shown that is still in the notification centre (Data management).
    func removeEverything() async
}

/// The real thing, over `UNUserNotificationCenter`.
public nonisolated struct SystemNotificationCenter: NotificationCentering {
    public init() {}

    public func authorization() async -> NotificationAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .denied
        }
    }

    public func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    public func removePending(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeEverything() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    public func add(_ notification: ScheduledNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: notification.components, repeats: notification.repeats)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger))
    }
}

// MARK: - The scheduler

/// Keeps the system's pending reminders the same as the plan: removes the three it owns and adds the ones that
/// are on. It does nothing while the person hasn't allowed notifications (and leaves nothing of its own
/// pending), and never touches any other pending notification, like the trial's.
public actor NotificationScheduler {
    private let center: any NotificationCentering

    public init(center: any NotificationCentering = SystemNotificationCenter()) {
        self.center = center
    }

    public func authorization() async -> NotificationAuthorization {
        await center.authorization()
    }

    public func requestAuthorization() async -> Bool {
        await center.requestAuthorization()
    }

    /// Rebuilds the reminders. Returns what it scheduled (empty when notifications aren't allowed).
    @discardableResult
    public func rebuild(preferences: NotificationPreferences, wakeMinutes: Int, bedtimeCenterMinutes: Int, tier: Tier = .free) async -> [ScheduledNotification] {
        await center.removePending(NotificationPlan.identifiers)
        guard await center.authorization().canSchedule else { return [] }
        let plan = NotificationPlan.make(preferences: preferences, wakeMinutes: wakeMinutes, bedtimeCenterMinutes: bedtimeCenterMinutes, tier: tier)
        for notification in plan { await center.add(notification) }
        return plan
    }

    /// Removes every reminder NOCTIS has asked for, pending or shown, including the free trial's.
    public func removeEverything() async {
        await center.removeEverything()
    }

    /// The reminders the system holds now, of the three this owns.
    public func pending() async -> [String] {
        await center.pendingIdentifiers().filter { NotificationPlan.identifiers.contains($0) }
    }
}

// MARK: - A notification centre in memory

/// A notification centre that keeps its pending list in memory and answers how it is told to: for tests, and
/// for DEBUG launches (`-mockNotifications`), so a screenshot or a test never opens the system's question.
public nonisolated final class InMemoryNotificationCenter: NotificationCentering, @unchecked Sendable {
    private let lock = NSLock()
    private var status: NotificationAuthorization
    private let answer: Bool
    private var pending: [ScheduledNotification] = []
    private var removed: [[String]] = []

    /// `answer`: what the system's question gets back when it is asked (from `.notDetermined`).
    public init(authorization: NotificationAuthorization = .notDetermined, answer: Bool = true, pending: [ScheduledNotification] = []) {
        status = authorization
        self.answer = answer
        self.pending = pending
    }

    public func authorization() async -> NotificationAuthorization {
        lock.withLock { status }
    }

    public func requestAuthorization() async -> Bool {
        lock.withLock {
            if status == .notDetermined { status = answer ? .allowed : .denied }
            return status == .allowed
        }
    }

    public func pendingIdentifiers() async -> [String] {
        lock.withLock { pending.map(\.identifier) }
    }

    public func removePending(_ identifiers: [String]) async {
        lock.withLock {
            removed.append(identifiers)
            pending.removeAll { identifiers.contains($0.identifier) }
        }
    }

    public func removeEverything() async {
        lock.withLock {
            removed.append(pending.map(\.identifier))
            pending.removeAll()
        }
    }

    public func add(_ notification: ScheduledNotification) async {
        lock.withLock {
            pending.removeAll { $0.identifier == notification.identifier }
            pending.append(notification)
        }
    }

    // MARK: What a test looks at

    public var pendingNotifications: [ScheduledNotification] { lock.withLock { pending } }
    public var removals: [[String]] { lock.withLock { removed } }

    /// Settings, changed behind the app's back.
    public func setAuthorization(_ value: NotificationAuthorization) {
        lock.withLock { status = value }
    }
}
