import DesignSystem
import Foundation
import HealthProviding
import HomeFeature
import NightFeature
import NightKit
import NoctisCore
import Observation
import SleepAnalysisKit

/// Everything Profile reads and changes (APP_RULES.md R20, R36): the profile and what it says about tonight's
/// bedtime, the alarm, and the status of Health, notifications and the subscription. Edits go through one
/// `ProfileEdit`, which saves the profile, and the app's profile hook reschedules the reminders from it.
@Observable
public final class ProfileViewModel {
    /// The editors Profile opens over itself.
    public enum Sheet: String, Identifiable, Equatable, Sendable {
        case name, need, wake, goals
        public var id: String { rawValue }
    }

    public var sheet: Sheet?
    /// What the open editor holds: a copy, so nothing changes until Save.
    public var nameDraft = ""
    public var needDraft = 8 * 60
    public var wakeDraft = 7 * 60
    public var goalsDraft: [PrimaryGoal] = []

    private(set) var timing: SleepTimingResult?
    private(set) var balance: SleepBalanceResult?
    private(set) var consistency: ConsistencyResult?
    private(set) var alarm: AlarmStatus?
    private(set) var health: HealthDataStatus?

    private let sleep: SleepRepository
    private let alarmService: AlarmService
    private let healthReader: HealthDataStatusReader
    private let profile: () -> UserProfileSnapshot
    private let edit: (ProfileEdit) -> Void
    private let notifications: NotificationCoordinator
    private let preferences: AppPreferences
    private let entitlements: EntitlementManager
    private let format: HomeFormat
    private let timeZone: TimeZone
    private let clock: () -> Date

    public init(
        sleep: SleepRepository, alarm: AlarmService, health: HealthDataStatusReader, profile: @escaping () -> UserProfileSnapshot,
        edit: @escaping (ProfileEdit) -> Void, notifications: NotificationCoordinator, preferences: AppPreferences,
        entitlements: EntitlementManager, format: HomeFormat, timeZone: TimeZone = .autoupdatingCurrent, clock: @escaping () -> Date = { Date() }
    ) {
        self.sleep = sleep
        self.alarmService = alarm
        self.healthReader = health
        self.profile = profile
        self.edit = edit
        self.notifications = notifications
        self.preferences = preferences
        self.entitlements = entitlements
        self.format = format
        self.timeZone = timeZone
        self.clock = clock
    }

    // MARK: What the screen says

    /// Built from the live profile, notification and subscription state each time it is read, so an edit shows
    /// at once (the bedtime included) with nothing to refresh.
    public var content: ProfileContent {
        ProfileBuilder.content(inputs(for: profile()), now: clock(), timeZone: timeZone, format: format)
    }

    /// Tonight's bedtime for a wake time and need that are not saved yet: the editor's preview, from the same
    /// recommendation as everything else.
    public func bedtime(wakeMinutes: Int, needMinutes: Int) -> TonightContent {
        let now = clock()
        let recommendation = BedtimeInputsBuilder.recommendation(
            wakeMinutes: wakeMinutes, needMinutes: needMinutes, timing: timing, balance: balance, consistency: consistency, now: now, timeZone: timeZone,
            personalized: entitlements.hasActivePremium
        )
        return TonightBuilder.content(for: recommendation, now: now, timeZone: timeZone, format: format, personalized: entitlements.hasActivePremium)
    }

    /// The bedtime the open wake time or sleep need editor would give, the other value as it is saved.
    public var previewBedtime: TonightContent {
        let current = profile()
        return bedtime(wakeMinutes: sheet == .wake ? wakeDraft : current.typicalWakeMinutes, needMinutes: sheet == .need ? needDraft : current.needMinutes)
    }

    public var clockFormat: HomeFormat { format }

    private func inputs(for profile: UserProfileSnapshot) -> ProfileBuilder.Inputs {
        ProfileBuilder.Inputs(
            profile: profile, timing: timing, balance: balance, consistency: consistency, alarm: alarm, health: health,
            notifications: notifications.authorization, reminderPreferences: preferences.values.notifications, isPremium: entitlements.hasActivePremium
        )
    }

    // MARK: Appearing

    /// Reads what is not already in hand: the Sleep tab's timing for the typical times and the bedtime, the
    /// alarm, the system's answer about notifications, and whether Health has data.
    public func onAppear() async {
        let current = profile()
        let now = clock()
        async let snapshot = sleep.refresh(profile: current)
        async let status = alarmService.status()
        async let authorization: Void = notifications.refreshAuthorization()
        async let healthStatus = healthReader.read(now: now)
        let fresh = await snapshot
        timing = fresh.timing
        balance = fresh.balance
        consistency = fresh.consistency
        alarm = await status
        _ = await authorization
        health = await healthStatus
        await entitlements.refresh()
    }

    // MARK: Editing

    public func open(_ sheet: Sheet) {
        let current = profile()
        switch sheet {
        case .name: nameDraft = current.name
        case .need: needDraft = current.needMinutes
        case .wake: wakeDraft = current.typicalWakeMinutes
        case .goals: goalsDraft = ProfileBuilder.goals(of: current)
        }
        self.sheet = sheet
    }

    public func cancel() {
        sheet = nil
    }

    /// Signed in with Apple from here: Apple's given name goes in the name field only if there is no name yet (APP_RULES.md R69).
    public func offerName(_ given: String?) {
        if let name = AccountStore.prefilledName(existing: profile().name, given: given) { edit(.name(name)) }
    }

    /// The profile's name today.
    public var currentName: String { profile().name }

    /// Applies the open editor's draft to the profile and closes it. The change saves the profile; the app then
    /// moves the reminders to the new bedtime and wake time. An alarm that is on keeps its own time.
    public func save() {
        guard let sheet else { return }
        switch sheet {
        case .name: edit(.name(nameDraft))
        case .need: edit(.need(minutes: needDraft))
        case .wake: edit(.wake(minutes: wakeDraft))
        case .goals: edit(.goals(goalsDraft))
        }
        NoctisHaptics.soft()
        self.sheet = nil
    }

    /// A tap on a goal in the editor.
    public func toggle(goal: PrimaryGoal) {
        goalsDraft = ProfileEdit.toggled(goal, in: goalsDraft)
    }

    /// Whether Save changes anything.
    public var hasChanges: Bool {
        let current = profile()
        switch sheet {
        case .name?: return ProfileEdit.cleaned(name: nameDraft) != ProfileEdit.cleaned(name: current.name)
        case .need?: return needDraft != current.needMinutes
        case .wake?: return wakeDraft != current.typicalWakeMinutes
        case .goals?: return goalsDraft != ProfileBuilder.goals(of: current) && !goalsDraft.isEmpty
        case nil: return false
        }
    }
}
