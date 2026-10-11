import AlarmKit
import Foundation
import Testing

@testable import NightKit

/// An in-memory record for the service to keep its settings in.
nonisolated final class MemoryAlarmStore: AlarmSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: AlarmSettings?
    private(set) var saveCount = 0

    init(_ settings: AlarmSettings? = nil) { saved = settings }

    var settings: AlarmSettings? { lock.withLock { saved } }

    func load() async -> AlarmSettings? { lock.withLock { saved } }

    func save(_ settings: AlarmSettings) async {
        lock.withLock {
            saved = settings
            saveCount += 1
        }
    }
}

/// The wake alarm service against the pretend alarm system (APP_RULES.md R30): permission,
/// scheduling, changing, cancelling, and what the system says afterwards.
@Suite(.serialized)
struct AlarmServiceTests {
    private let wake = 7 * 60 + 30

    private func make(_ mode: MockAlarmBackend.Mode = .authorized, stored: AlarmSettings? = nil) -> (AlarmService, MockAlarmBackend, MemoryAlarmStore) {
        let backend = MockAlarmBackend(mode: mode)
        let store = MemoryAlarmStore(stored)
        let wake = self.wake
        return (AlarmService(backend: backend, store: store, defaultMinutes: { wake }), backend, store)
    }

    private func settings(days: Set<AlarmWeekday> = [], snooze: Bool = false, minutes: Int = 7 * 60 + 30) -> AlarmSettings {
        AlarmSettings(minutesSinceMidnight: minutes, repeatDays: days, snoozeEnabled: snooze, snoozeMinutes: 9)
    }

    /// The first status from `service` that `matches`, or nil after a minute (a backstop).
    private func wait(for service: AlarmService, _ matches: @escaping @Sendable (AlarmStatus) -> Bool) async -> AlarmStatus? {
        await withTaskGroup(of: AlarmStatus?.self) { group in
            let updates = await service.updates()
            group.addTask {
                for await status in updates where matches(status) { return status }
                return nil
            }
            group.addTask {
                // A backstop for a status that never comes, not an expectation: the first match returns at once.
                try? await Task.sleep(for: .seconds(60))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Asking again changes nothing

    /// QA found 40.6 million writes of the one alarm row in the app's database: whoever follows `updates()` and asks `status()` on each one (the widgets'
    /// publisher does) made the service reconcile, write and publish again, which was an update, which asked again, without end.
    @Test func followingTheUpdatesAndAskingForTheStatusOnEachOneEndsAndWritesNothingMore() async {
        let (service, _, store) = make(stored: settings(snooze: true))
        let updates = await service.updates()
        let consumer = Task {
            for await _ in updates { _ = await service.status() }
        }
        _ = await service.status()
        for _ in 0..<300 { await Task.yield() }
        let writes = store.saveCount
        for _ in 0..<300 { await Task.yield() }
        consumer.cancel()
        #expect(store.saveCount == writes, "it is still writing")
        #expect(writes == 0, "the record is as it was stored: nothing to write")
    }

    @Test func askingForTheStatusAgainWritesAndSaysNothing() async {
        let (service, _, store) = make()
        _ = await service.enable(settings(snooze: true))
        let afterEnable = store.saveCount
        let updates = await service.updates()
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()   // how it is now
        for _ in 0..<25 { _ = await service.status() }
        #expect(store.saveCount == afterEnable, "25 asks, no write")
        _ = await service.disable()
        let next = await iterator.next()
        #expect(next?.state == .off || next?.state == .dismissed || next?.state == .cancelled, "the next thing said is the change, not an echo: \(String(describing: next?.state))")
    }

    @Test func peekReadsWithoutAskingTheSystem() async {
        let (service, backend, _) = make()
        _ = await service.enable(settings())
        let calls = backend.scheduleCalls
        let seen = await service.peek()
        #expect(seen.state.isActive && backend.scheduleCalls == calls)
    }

    // MARK: - Starting out

    @Test func theAlarmStartsAtTheProfilesWakeTimeAndOff() async {
        let (service, _, _) = make()
        let status = await service.status()
        #expect(status.settings.minutesSinceMidnight == wake)
        #expect(status.settings.repeatDays.isEmpty)
        #expect(!status.settings.snoozeEnabled)
        #expect(status.settings.snoozeMinutes == 9)
        #expect(status.state == .off)
        #expect(!status.isOn)
    }

    @Test func aSavedAlarmIsNotOverwrittenByTheDefault() async {
        let saved = AlarmSettings(minutesSinceMidnight: 6 * 60, repeatDays: [.monday], snoozeEnabled: true, snoozeMinutes: 5)
        let (service, _, _) = make(stored: saved)
        let status = await service.status()
        #expect(status.settings.minutesSinceMidnight == 6 * 60)
        #expect(status.settings.repeatDays == [.monday])
        #expect(status.settings.snoozeMinutes == 5)
    }

    // MARK: - Turning it on

    @Test func turningItOnSchedulesItAndTheSystemConfirmsIt() async {
        let (service, backend, store) = make()
        let status = await service.enable(settings())
        #expect(status.state == .armed)
        #expect(status.isOn)
        #expect(status.authorization == .authorized)
        #expect(backend.scheduleCalls == 1)
        #expect(backend.promptCount == 0)
        #expect(status.settings.alarmKitID != nil)
        #expect(store.settings?.alarmKitID == status.settings.alarmKitID)
        #expect(store.settings?.lastState == .armed)
        #expect(backend.scheduledSettings.first?.minutesSinceMidnight == wake)
    }

    @Test func theFirstTimeAsksOnceAndThenSchedules() async {
        let (service, backend, _) = make(.notDetermined)
        let first = await service.enable(settings())
        #expect(backend.promptCount == 1)
        #expect(first.state == .armed)
        _ = await service.disable()
        let second = await service.enable(settings())
        #expect(backend.promptCount == 1)
        #expect(second.state == .armed)
    }

    @Test func sayingNoLeavesTheAlarmOffAndAsksNoMore() async {
        let (service, backend, store) = make(.willDeny)
        let status = await service.enable(settings())
        #expect(status.state == .permissionDenied)
        #expect(status.authorization == .denied)
        #expect(!status.isOn)
        #expect(backend.scheduleCalls == 0)
        #expect(store.settings?.lastState == .permissionDenied)
        let again = await service.enable(settings())
        #expect(again.state == .permissionDenied)
        #expect(backend.promptCount == 1)
        #expect(backend.scheduleCalls == 0)
    }

    @Test func anAlreadyRefusedPermissionIsNeverAsked() async {
        let (service, backend, _) = make(.denied)
        let status = await service.enable(settings())
        #expect(status.state == .permissionDenied)
        #expect(backend.promptCount == 0)
        #expect(backend.scheduleCalls == 0)
    }

    @Test func aDeviceWithoutAlarmsSaysSo() async {
        let (service, backend, _) = make(.unavailable)
        let status = await service.enable(settings())
        #expect(status.state == .unavailable)
        #expect(status.authorization == .unavailable)
        #expect(!status.isOn)
        #expect(backend.scheduleCalls == 0)
    }

    @Test func aFailedScheduleIsAnErrorWithItsReason() async {
        let (failing, _, _) = make(.failing)
        let failed = await failing.enable(settings())
        #expect(failed.state == .error)
        #expect(failed.failure == .scheduleFailed)
        #expect(!failed.isOn)
        let (limited, _, _) = make(.limitReached)
        let atLimit = await limited.enable(settings())
        #expect(atLimit.state == .error)
        #expect(atLimit.failure == .limitReached)
    }

    @Test func tryingAgainSchedulesAgain() async {
        let (service, backend, _) = make(.failing)
        _ = await service.enable(settings())
        let retried = await service.retry()
        #expect(backend.scheduleCalls == 2)
        #expect(retried.state == .error)
    }

    @Test func twoRequestsAtOnceScheduleOnce() async {
        let (service, backend, _) = make()
        async let first = service.enable(settings())
        async let second = service.enable(settings())
        _ = await (first, second)
        #expect(backend.scheduleCalls == 1)
    }

    // MARK: - Changing it

    @Test func changingAPendingAlarmCancelsAndSchedulesAgain() async {
        let (service, backend, store) = make()
        let first = await service.enable(settings())
        let changed = await service.update(settings(days: [.monday, .friday], snooze: true, minutes: 6 * 60 + 45))
        #expect(changed.state == .armed)
        #expect(backend.cancelCalls == 1)
        #expect(backend.scheduleCalls == 2)
        #expect(changed.settings.alarmKitID != nil)
        #expect(changed.settings.alarmKitID != first.settings.alarmKitID)
        #expect(store.settings?.minutesSinceMidnight == 6 * 60 + 45)
        #expect(backend.scheduledSettings.count == 1)
        #expect(backend.scheduledSettings.first?.repeatDays == [.monday, .friday])
        #expect(backend.scheduledSettings.first?.snoozeEnabled == true)
    }

    @Test func changingNothingSchedulesNothing() async {
        let (service, backend, _) = make()
        _ = await service.enable(settings())
        _ = await service.update(settings())
        #expect(backend.scheduleCalls == 1)
        #expect(backend.cancelCalls == 0)
    }

    @Test func changingAnAlarmThatIsOffOnlyRemembers() async {
        let (service, backend, store) = make()
        let status = await service.update(settings(days: [.sunday], minutes: 9 * 60))
        #expect(status.state == .off)
        #expect(status.settings.minutesSinceMidnight == 9 * 60)
        #expect(store.settings?.repeatDays == [.sunday])
        #expect(backend.scheduleCalls == 0)
        #expect(backend.cancelCalls == 0)
    }

    // MARK: - Turning it off

    @Test func turningItOffCancelsIt() async {
        let (service, backend, store) = make()
        _ = await service.enable(settings())
        let status = await service.disable()
        #expect(status.state == .cancelled)
        #expect(!status.isOn)
        #expect(backend.cancelCalls == 1)
        #expect(status.settings.alarmKitID == nil)
        #expect(store.settings?.lastState == .cancelled)
        let backAgain = await service.enable(settings())
        #expect(backAgain.state == .armed)
    }

    // MARK: - What the system does

    @Test func anAlarmThatRingsIsFiring() async {
        let (service, backend, _) = make()
        let armed = await service.enable(settings())
        backend.fire(armed.settings.alarmKitID!)
        #expect(await service.status().state == .firing)
    }

    @Test func snoozingThenStoppingAOneShotAlarmEndsItDismissed() async {
        let (service, backend, store) = make()
        let id = await service.enable(settings(snooze: true)).settings.alarmKitID!
        backend.fire(id)
        #expect(await service.status().state == .firing)
        backend.snooze(id)
        #expect(await service.status().state == .snoozed)
        backend.fire(id)
        #expect(await service.status().state == .firing)
        backend.stop(id)
        let end = await service.status()
        #expect(end.state == .dismissed)
        #expect(!end.isOn)
        #expect(store.settings?.lastState == .dismissed)
    }

    @Test func stoppingARepeatingAlarmGoesBackToWaiting() async {
        let (service, backend, _) = make()
        let id = await service.enable(settings(days: AlarmWeekday.weekdays)).settings.alarmKitID!
        backend.fire(id)
        #expect(await service.status().state == .firing)
        backend.stop(id)
        let status = await service.status()
        #expect(status.state == .armed)
        #expect(status.isOn)
    }

    @Test func anAlarmTheSystemLostIsDismissed() async {
        // The record says armed; the system holds nothing: it rang and was stopped while the app was closed.
        var saved = settings()
        saved.alarmKitID = UUID()
        saved.lastState = .armed
        let (service, _, _) = make(stored: saved)
        #expect(await service.status().state == .dismissed)
    }

    @Test func anAlarmTheSystemStillHoldsIsArmed() async {
        let (first, backend, store) = make()
        _ = await first.enable(settings())
        // A new launch: another service, the same record and the same system.
        let second = AlarmService(backend: backend, store: store, defaultMinutes: { 7 * 60 })
        let status = await second.status()
        #expect(status.state == .armed)
        #expect(status.settings.alarmKitID == store.settings?.alarmKitID)
    }

    @Test func permissionTakenAwayInSettingsStopsTheAlarm() async {
        let (service, backend, _) = make()
        _ = await service.enable(settings())
        backend.setAuthorization(.denied)
        let denied = await service.status()
        #expect(denied.state == .permissionDenied)
        #expect(!denied.isOn)
        backend.setAuthorization(.authorized)
        let allowed = await service.status()
        #expect(allowed.state == .off)
        #expect(allowed.authorization == .authorized)
    }

    // MARK: - Following the system

    @Test func updatesFollowTheSystem() async {
        let (service, backend, _) = make()
        let id = await service.enable(settings(snooze: true)).settings.alarmKitID!
        await service.startObserving()
        backend.fire(id)
        let firing = await wait(for: service) { $0.state == .firing }
        #expect(firing?.state == .firing)
        backend.snooze(id)
        let snoozed = await wait(for: service) { $0.state == .snoozed }
        #expect(snoozed?.state == .snoozed)
        backend.fire(id)
        backend.stop(id)
        let dismissed = await wait(for: service) { $0.state == .dismissed }
        #expect(dismissed?.state == .dismissed)
        await service.stopObserving()
    }

    @Test func updatesFollowPermissionInSettings() async {
        let (service, backend, _) = make()
        _ = await service.enable(settings())
        await service.startObserving()
        backend.setAuthorization(.denied)
        let denied = await wait(for: service) { $0.state == .permissionDenied }
        #expect(denied?.authorization == .denied)
        await service.stopObserving()
    }
}

/// What AlarmKit is asked for (the real thing can't ring on a test runner, so the request is
/// checked here).
struct AlarmKitBackendTests {
    @Test func aOneShotAlarmIsAtItsTimeAndNeverRepeats() throws {
        let schedule = AlarmKitBackend.schedule(for: AlarmSettings(minutesSinceMidnight: 7 * 60 + 5))
        guard case .relative(let relative) = schedule else { Issue.record("not a relative schedule"); return }
        #expect(relative.time.hour == 7)
        #expect(relative.time.minute == 5)
        #expect(relative.repeats == .never)
    }

    @Test func aRepeatingAlarmRepeatsWeeklyOnItsDays() throws {
        let schedule = AlarmKitBackend.schedule(for: AlarmSettings(minutesSinceMidnight: 6 * 60, repeatDays: [.monday, .wednesday, .sunday]))
        guard case .relative(let relative) = schedule, case .weekly(let days) = relative.repeats else { Issue.record("not weekly"); return }
        #expect(Set(days) == [.monday, .wednesday, .sunday])
        #expect(relative.time.hour == 6)
    }

    @Test func everyWeekdayMapsToItself() {
        #expect(AlarmWeekday.allCases.map { AlarmKitBackend.weekday($0) }.count == 7)
        #expect(AlarmKitBackend.weekday(.sunday) == .sunday)
        #expect(AlarmKitBackend.weekday(.saturday) == .saturday)
        #expect(Set(AlarmWeekday.allCases.map { AlarmKitBackend.weekday($0) }).count == 7)
    }

    @Test func withoutASnoozeThereIsNoCountdown() {
        let presentation = AlarmKitBackend.presentation(for: AlarmSettings(minutesSinceMidnight: 420))
        #expect(presentation.countdown == nil)
        #expect(presentation.paused == nil)
        #expect(presentation.alert.secondaryButton == nil)
        #expect(presentation.alert.secondaryButtonBehavior == nil)
    }

    @Test func aSnoozeIsACountdownButton() {
        let presentation = AlarmKitBackend.presentation(for: AlarmSettings(minutesSinceMidnight: 420, snoozeEnabled: true, snoozeMinutes: 10))
        #expect(presentation.countdown != nil)
        #expect(presentation.alert.secondaryButton != nil)
        #expect(presentation.alert.secondaryButtonBehavior == .countdown)
    }

    @Test func theAlarmCallsItselfAnAlarm() {
        let presentation = AlarmKitBackend.presentation(for: AlarmSettings(minutesSinceMidnight: 420))
        #expect(String(localized: presentation.alert.title) == "Alarm")
    }

    @Test func snoozeMinutesAreOneOfTheChoices() {
        #expect(AlarmSettings.snoozeChoices == [5, 9, 10])
        #expect(AlarmSettings(minutesSinceMidnight: 420, snoozeMinutes: 7).snoozeMinutes == 9)
        #expect(AlarmSettings(minutesSinceMidnight: 420, snoozeMinutes: 5).snoozeMinutes == 5)
        #expect(AlarmSettings(minutesSinceMidnight: 420, snoozeMinutes: 10).snoozeMinutes == 10)
    }
}
