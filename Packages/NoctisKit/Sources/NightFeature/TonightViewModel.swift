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
    private let openSettingsAction: @MainActor () -> Void
    private var observing: Task<Void, Never>?

    public init(
        sleep: SleepRepository,
        alarm: AlarmService,
        profile: @escaping () -> UserProfileSnapshot,
        format: HomeFormat,
        timeZone: TimeZone = .autoupdatingCurrent,
        clock: @escaping () -> Date = { Date() },
        openSettings: @escaping @MainActor () -> Void = TonightViewModel.openAppSettings
    ) {
        self.sleep = sleep
        self.alarmService = alarm
        self.profile = profile
        self.format = format
        self.timeZone = timeZone
        self.clock = clock
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
        startObserving()
    }

    public func onDisappear() {
        observing?.cancel()
        observing = nil
    }

    public func refreshBedtime() async {
        let current = profile()
        let snapshot = await sleep.refresh(profile: current)
        let now = clock()
        let wake = current.typicalWakeMinutes
        let need = current.needMinutes
        let base = BedtimeClock.wrap(wake - need)
        let change = TonightClock.clockChangeMinutes(
            night: TonightClock.tonight(now: now, in: timeZone), bedtimeMinutes: base, wakeMinutes: wake, timeZone: timeZone
        )
        let inputs = BedtimeInputsBuilder.inputs(
            wakeMinutes: wake, needMinutes: need, timing: snapshot.timing, balance: snapshot.balance,
            consistency: snapshot.consistency, clockChangeMinutes: change
        )
        content = TonightBuilder.content(for: BedtimeRecommendationEngine.recommend(inputs), now: now, timeZone: timeZone, format: format)
    }

    public func refreshAlarm() async {
        apply(await alarmService.status())
    }

    private func startObserving() {
        guard observing == nil else { return }
        observing = Task { [weak self, alarmService] in
            await alarmService.startObserving()
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
