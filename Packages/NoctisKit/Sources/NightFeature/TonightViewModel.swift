import DesignSystem
import Foundation
import HealthProviding
import HomeFeature
import NightKit
import NoctisCore
import Observation
import SleepAnalysisKit
import SleepKit
import UIKit

/// Everything the Tonight screen reads (APP_RULES.md R20, R30): tonight's bedtime, built from
/// the same snapshot as the Sleep tab, and the wake alarm, from `AlarmService`. Nothing here
/// touches HealthKit or AlarmKit directly.
@Observable
public final class TonightViewModel {
    public private(set) var content: TonightContent?
    public private(set) var alarm: AlarmStatus?
    public private(set) var alarmCard: AlarmCardContent?
    /// The alarm sheet.
    public var isSheetPresented = false
    /// What the sheet is editing: a copy, so nothing changes until Save.
    public var draft: AlarmSettings
    /// An alarm request is with the system.
    public private(set) var isWorking = false

    private let sleep: SleepRepository
    private let alarmService: AlarmService
    private let profile: () -> UserProfileSnapshot
    private let format: HomeFormat
    private let timeZone: TimeZone
    private let clock: () -> Date
    private let isUnlocked: (Feature) -> Bool
    private let openSettingsAction: @MainActor () -> Void
    private var observing: Task<Void, Never>?

    public init(
        sleep: SleepRepository,
        alarm: AlarmService,
        profile: @escaping () -> UserProfileSnapshot,
        format: HomeFormat,
        timeZone: TimeZone = .autoupdatingCurrent,
        clock: @escaping () -> Date = { Date() },
        isUnlocked: @escaping (Feature) -> Bool = { _ in true },
        openSettings: @escaping @MainActor () -> Void = TonightViewModel.openAppSettings
    ) {
        self.sleep = sleep
        self.alarmService = alarm
        self.profile = profile
        self.format = format
        self.timeZone = timeZone
        self.clock = clock
        self.isUnlocked = isUnlocked
        self.openSettingsAction = openSettings
        self.draft = AlarmSettings(minutesSinceMidnight: profile().typicalWakeMinutes)
    }

    public static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Appearing

    /// Reads tonight's bedtime and the alarm, and follows the alarm while the screen is up.
    public func onAppear() async {
        async let bedtime: Void = refreshBedtime()
        async let status: Void = refreshAlarm()
        _ = await (bedtime, status)
        await startObserving()
    }

    public func onDisappear() {
        observing?.cancel()
        observing = nil
    }

    /// Tonight's window and the reasons for it are Premium; the free plan gets the one bedtime (APP_RULES.md R57, R59). Asked each time it is read,
    /// so a purchase or a lapse shows in the next `refreshBedtime`.
    public var showsWindow: Bool { isUnlocked(.tonightPersonalizedWindow) }

    /// "Start wind-down" is Premium: the free plan sees a lock glyph and the paywall (R58); a session already running finishes either way.
    public var windDownLocked: Bool { !isUnlocked(.windDownSession) }

    public func refreshBedtime() async {
        let current = profile()
        let snapshot = await sleep.refresh(profile: current)
        let now = clock()
        let personalized = showsWindow
        let recommendation = BedtimeInputsBuilder.recommendation(
            wakeMinutes: current.typicalWakeMinutes, needMinutes: current.needMinutes, timing: snapshot.timing, balance: snapshot.balance,
            consistency: snapshot.consistency, now: now, timeZone: timeZone, personalized: personalized
        )
        content = TonightBuilder.content(for: recommendation, now: now, timeZone: timeZone, format: format, personalized: personalized)
    }

    /// The tier changed while Tonight is open: the bedtime is built again for it.
    public func tierChanged() async {
        guard content != nil else { return }
        await refreshBedtime()
    }

    public func refreshAlarm() async {
        apply(await alarmService.status())
    }

    /// Subscribes to the system before it returns (and so before `onAppear` does): an alarm that rings right after the screen appears is not
    /// missed because a task had not started yet. The task then forwards the service's own updates, which begin with how the alarm is now.
    private func startObserving() async {
        guard observing == nil else { return }
        await alarmService.startObserving()
        guard observing == nil else { return }
        observing = Task { [weak self, alarmService] in
            for await status in await alarmService.updates() {
                self?.apply(status)
            }
        }
    }

    private func apply(_ status: AlarmStatus) {
        alarm = status
        alarmCard = AlarmBuilder.card(for: status, format: format)
        if !isSheetPresented { draft = status.settings }
    }

    // MARK: The alarm

    /// The card's toggle. Turning it on the first time, or while permission is missing, opens the
    /// sheet so the person is told what is being asked before the system asks.
    public func setAlarm(on: Bool) async {
        guard let status = alarm else { return }
        if on {
            guard status.authorization == .authorized || status.state.isActive else {
                openSheet()
                return
            }
            await enable(status.settings)
        } else {
            await disable()
        }
    }

    public func openSheet() {
        if let alarm { draft = alarm.settings }
        isSheetPresented = true
    }

    /// The sheet's "Turn on alarm": asks (once, if nobody has been asked), then schedules.
    public func turnOn() async {
        await enable(draft, closesSheet: true)
    }

    /// The sheet's "Save": an alarm that is on is scheduled again at the new time; one that is
    /// off just remembers it.
    public func save() async {
        guard !isWorking else { return }
        isWorking = true
        apply(await alarmService.update(draft))
        isWorking = false
        isSheetPresented = false
    }

    public func turnOff() async {
        await disable(closesSheet: true)
    }

    public func retry() async {
        guard !isWorking else { return }
        isWorking = true
        let status = await alarmService.retry()
        apply(status)
        isWorking = false
        if status.isOn { isSheetPresented = false }
    }

    public func openSettings() {
        openSettingsAction()
    }

    /// The draft's time as a date today, for the wheel picker (the date itself is never used).
    public var draftTime: Date {
        get {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar.date(bySettingHour: draft.minutesSinceMidnight / 60, minute: draft.minutesSinceMidnight % 60, second: 0, of: clock()) ?? clock()
        }
        set {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.hour, .minute], from: newValue)
            draft.minutesSinceMidnight = BedtimeClock.wrap((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
    }

    /// Whether the sheet's draft differs from the alarm as it is.
    public var hasChanges: Bool {
        guard let alarm else { return true }
        return !alarm.settings.sameAlarm(as: draft)
    }

    /// Whether the person has yet to be asked: the sheet explains first.
    public var explainsPermission: Bool {
        alarm?.authorization == .notDetermined
    }

    private func enable(_ settings: AlarmSettings, closesSheet: Bool = false) async {
        guard !isWorking else { return }
        isWorking = true
        let status = await alarmService.enable(settings)
        apply(status)
        isWorking = false
        if status.isOn {
            NoctisHaptics.soft()
            if closesSheet { isSheetPresented = false }
        }
    }

    private func disable(closesSheet: Bool = false) async {
        guard !isWorking else { return }
        isWorking = true
        apply(await alarmService.disable())
        isWorking = false
        NoctisHaptics.selection()
        if closesSheet { isSheetPresented = false }
    }
}
