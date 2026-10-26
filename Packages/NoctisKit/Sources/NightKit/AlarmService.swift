import Foundation
import os

/// The wake alarm: authorization, schedule, update, cancel, and what the system says
/// about it afterwards. It wraps an `AlarmBackend` (AlarmKit in the app), keeps the
/// alarm's own record in an `AlarmSettingsStoring` (the system deletes a one-shot alarm the
/// moment it has rung, so this record is how we know it did), and runs every change through
/// `AlarmStateMachine`.
///
/// State changes happen in synchronous methods, one after another, so an `await` on the
/// system never leaves the alarm half-changed; a second request while one is running is
/// answered with the picture as it is.
public actor AlarmService {
    private let backend: any AlarmBackend
    private let store: any AlarmSettingsStoring
    private let defaultMinutes: @Sendable () async -> Int
    private var settings: AlarmSettings?
    private var state: AlarmState = .off
    private var authorization: AlarmAuthorization = .notDetermined
    private var failure: AlarmFailure?
    private var busy = false
    private var subscribers: [UUID: AsyncStream<AlarmStatus>.Continuation] = [:]
    private var observers: [Task<Void, Never>] = []
    /// What was last written and what was last said, so asking again changes nothing and says nothing: `status()` is asked on every update by
    /// whoever follows them (the widgets' publisher does), and a write and an update for each ask made a loop with no end (QA_LEDGER.md).
    private var lastPersisted: AlarmSettings?
    private var lastPublished: AlarmStatus?

    /// `defaultMinutes` is the wake time to start from, minutes since midnight (the profile's).
    public init(backend: any AlarmBackend, store: any AlarmSettingsStoring, defaultMinutes: @escaping @Sendable () async -> Int) {
        self.backend = backend
        self.store = store
        self.defaultMinutes = defaultMinutes
    }

    // MARK: Reading

    /// The alarm as it is now, checked against the system. Nothing is written and nothing is said unless the answer changed.
    public func status() async -> AlarmStatus {
        await load()
        await reconcile()
        return current()
    }

    /// The alarm as the service holds it, without asking the system: for whoever redraws something on every update.
    public func peek() async -> AlarmStatus {
        await load()
        return current()
    }

    /// Every change to the alarm, starting with how it is now.
    public func updates() -> AsyncStream<AlarmStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AlarmStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        if settings != nil { continuation.yield(current()) }
        return stream
    }

    /// Starts following the system: an alarm that rings, is snoozed or is stopped, and a change of
    /// permission in Settings. Safe to call twice.
    public func startObserving() {
        guard observers.isEmpty else { return }
        // Subscribe now, so nothing that happens right after this returns is missed.
        let alarms = backend.alarmUpdates()
        let authorizations = backend.authorizationUpdates()
        observers = [
            Task { [weak self] in
                // Whatever the system did before this subscription began: the system's sequence need not replay it.
                await self?.catchUp()
                for await update in alarms {
                    await self?.apply(update)
                }
            },
            Task { [weak self] in
                for await update in authorizations {
                    await self?.apply(update)
                }
            },
        ]
    }

    public func stopObserving() {
        for task in observers { task.cancel() }
        observers = []
    }

    // MARK: Changing

    /// Turns the alarm on with `new`: asks for permission first if nobody has been asked, then
    /// schedules it (cancelling an earlier schedule of it, if any).
    public func enable(_ new: AlarmSettings) async -> AlarmStatus {
        await load()
        guard !busy else { return current() }
        busy = true
        defer { busy = false }
        failure = nil
        keep(new)

        authorization = await backend.authorization()
        if authorization == .notDetermined {
            do {
                authorization = try await backend.requestAuthorization()
            } catch {
                return await finish(.scheduleFailed, failure: .scheduleFailed)
            }
        }
        switch authorization {
        case .denied: return await finish(.authorizationDenied)
        case .unavailable: return await finish(.alarmsUnavailable)
        case .notDetermined, .authorized: break
        }
        return await schedule()
    }

    /// Changes the alarm. A pending alarm is cancelled and scheduled again (AlarmKit has no
    /// "update"); one that is off just remembers the change.
    public func update(_ new: AlarmSettings) async -> AlarmStatus {
        await load()
        guard let existing = settings else { return current() }
        guard state.isActive else {
            keep(new)
            await persist()
            publish()
            return current()
        }
        guard !busy else { return current() }
        busy = true
        defer { busy = false }
        guard !existing.sameAlarm(as: new) else { return current() }
        failure = nil
        keep(new)
        return await schedule()
    }

    /// Turns the alarm off.
    public func disable() async -> AlarmStatus {
        await load()
        guard !busy else { return current() }
        busy = true
        defer { busy = false }
        if let id = settings?.alarmKitID {
            // The system may already have forgotten it; either way it is not going to ring.
            try? await backend.cancel(id: id)
        }
        settings?.alarmKitID = nil
        failure = nil
        return await finish(.cancelRequested)
    }

    /// After an error: forgets it and tries again with the same settings.
    public func retry() async -> AlarmStatus {
        await load()
        guard let settings else { return current() }
        apply(.reset)
        return await enable(settings)
    }

    // MARK: Following the system

    private func apply(_ alarms: [BackendAlarm]) async {
        await load()
        react(to: alarms)
        await persist()
        publish()
    }

    private func apply(_ new: AlarmAuthorization) async {
        await load()
        authorization = new
        switch new {
        case .denied: apply(.authorizationDenied)
        case .unavailable: apply(.alarmsUnavailable)
        case .authorized: apply(.authorizationGranted)
        case .notDetermined: break
        }
        await persist()
        publish()
    }

    /// Compares what we believe with what the system holds.
    private func reconcile() async {
        authorization = await backend.authorization()
        switch authorization {
        case .denied: apply(.authorizationDenied)
        case .unavailable: apply(.alarmsUnavailable)
        case .authorized: apply(.authorizationGranted)
        case .notDetermined: break
        }
        if state.isActive, let alarms = try? await backend.alarms() {
            react(to: alarms)
        }
        await persist()
        publish()
    }

    /// One look at the system's alarms, for an observer that started after something happened.
    private func catchUp() async {
        guard state.isActive, let alarms = try? await backend.alarms() else { return }
        react(to: alarms)
        await persist()
        publish()
    }

    private func react(to alarms: [BackendAlarm]) {
        guard state.isActive, let id = settings?.alarmKitID else { return }
        guard let alarm = alarms.first(where: { $0.id == id }) else {
            apply(.systemGone)
            return
        }
        switch alarm.state {
        case .scheduled: apply(.systemScheduled)
        case .countdown: apply(.systemCountdown)
        case .alerting: apply(.systemAlerting)
        case .paused: break
        }
    }

    // MARK: Plumbing

    private func load() async {
        guard settings == nil else { return }
        let stored = await store.load()
        // Another request may have loaded while this one waited.
        guard settings == nil else { return }
        let minutes = await defaultMinutes()
        let loaded = stored ?? AlarmSettings(minutesSinceMidnight: minutes)
        guard settings == nil else { return }
        settings = loaded
        state = loaded.lastState
        // What the store handed over is already on disk.
        if stored != nil { lastPersisted = loaded }
    }

    /// Takes the person's choices, keeping the bookkeeping.
    private func keep(_ new: AlarmSettings) {
        var next = new
        next.alarmKitID = settings?.alarmKitID
        next.lastState = state
        settings = next
    }

    /// Cancels the earlier schedule and asks the system for the new one.
    private func schedule() async -> AlarmStatus {
        guard var next = settings else { return current() }
        if let old = next.alarmKitID {
            try? await backend.cancel(id: old)
        }
        let id = UUID()
        do {
            try await backend.schedule(id: id, settings: next)
        } catch AlarmBackendError.limitReached {
            Self.log.error("alarm schedule refused: limit reached")
            return await finish(.scheduleFailed, failure: .limitReached)
        } catch {
            Self.log.error("alarm schedule failed")
            return await finish(.scheduleFailed, failure: .scheduleFailed)
        }
        next.alarmKitID = id
        settings = next
        apply(.scheduleAccepted)
        await reconcile()
        return current()
    }

    private func apply(_ event: AlarmEvent) {
        let before = state
        let transition = AlarmStateMachine.reduce(state, event)
        state = transition.state
        settings?.lastState = state
        // The state and the event, by name: nothing about the person or their nights.
        if transition.changed {
            Self.log.notice(
                "alarm \(before.rawValue, privacy: .public) -> \(self.state.rawValue, privacy: .public) on \(String(describing: event), privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "com.noctis.app", category: "alarm")

    private func finish(_ event: AlarmEvent, failure new: AlarmFailure? = nil) async -> AlarmStatus {
        failure = new
        apply(event)
        await persist()
        publish()
        return current()
    }

    private func persist() async {
        guard let settings, settings != lastPersisted else { return }
        lastPersisted = settings
        await store.save(settings)
    }

    private func current() -> AlarmStatus {
        AlarmStatus(
            settings: settings ?? AlarmSettings(minutesSinceMidnight: 7 * 60), state: state, authorization: authorization,
            failure: state == .error ? failure : nil
        )
    }

    private func publish() {
        let status = current()
        guard status != lastPublished else { return }
        lastPublished = status
        for continuation in subscribers.values { continuation.yield(status) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
