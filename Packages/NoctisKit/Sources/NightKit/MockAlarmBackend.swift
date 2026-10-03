#if DEBUG
import Foundation
import os

/// A pretend alarm system, for tests and for `-mockAlarm` launch arguments. It behaves as the
/// real one is documented to: asking the person once, refusing to schedule once they said no,
/// deleting a one-shot alarm when it has rung and been stopped, and counting down a snooze.
public final class MockAlarmBackend: AlarmBackend, Sendable {
    public enum Mode: String, Sendable, CaseIterable {
        /// Already allowed.
        case authorized
        /// Not asked yet; the person will say yes.
        case notDetermined
        /// Not asked yet; the person will say no.
        case willDeny
        /// Already refused.
        case denied
        /// This device can't schedule alarms.
        case unavailable
        /// Allowed, but scheduling fails.
        case failing
        /// Allowed, but the system's alarm limit is reached.
        case limitReached

        public init?(launchValue: String) {
            self.init(rawValue: launchValue)
        }
    }

    private struct State: Sendable {
        var authorization: AlarmAuthorization
        var alarms: [UUID: (settings: AlarmSettings, state: BackendAlarmState)] = [:]
        var alarmContinuations: [UUID: AsyncStream<[BackendAlarm]>.Continuation] = [:]
        var authorizationContinuations: [UUID: AsyncStream<AlarmAuthorization>.Continuation] = [:]
        var scheduleCalls = 0
        var cancelCalls = 0
        var promptCount = 0
    }

    private let mode: Mode
    private let state: OSAllocatedUnfairLock<State>

    public init(mode: Mode = .authorized) {
        self.mode = mode
        let start: AlarmAuthorization = switch mode {
        case .authorized, .failing, .limitReached: .authorized
        case .notDetermined, .willDeny: .notDetermined
        case .denied: .denied
        case .unavailable: .unavailable
        }
        state = OSAllocatedUnfairLock(initialState: State(authorization: start))
    }

    // MARK: AlarmBackend

    public func authorization() async -> AlarmAuthorization { state.withLock { $0.authorization } }

    public func requestAuthorization() async throws -> AlarmAuthorization {
        let result = state.withLock { state -> AlarmAuthorization in
            if state.authorization == .notDetermined {
                state.promptCount += 1
                state.authorization = mode == .willDeny ? .denied : .authorized
            }
            return state.authorization
        }
        publishAuthorization()
        return result
    }

    public func schedule(id: UUID, settings: AlarmSettings) async throws {
        try state.withLock { state in
            state.scheduleCalls += 1
            guard state.authorization == .authorized else { throw AlarmBackendError.failed }
            switch mode {
            case .failing: throw AlarmBackendError.failed
            case .limitReached: throw AlarmBackendError.limitReached
            default: break
            }
            state.alarms[id] = (settings, .scheduled)
        }
        publishAlarms()
    }

    public func cancel(id: UUID) async throws {
        state.withLock { state in
            state.cancelCalls += 1
            state.alarms[id] = nil
        }
        publishAlarms()
    }

    public func alarms() async throws -> [BackendAlarm] { snapshot() }

    public func alarmUpdates() -> AsyncStream<[BackendAlarm]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[BackendAlarm]>.makeStream()
        state.withLock { $0.alarmContinuations[id] = continuation }
        continuation.onTermination = { [state] _ in state.withLock { $0.alarmContinuations[id] = nil } }
        return stream
    }

    public func authorizationUpdates() -> AsyncStream<AlarmAuthorization> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AlarmAuthorization>.makeStream()
        state.withLock { $0.authorizationContinuations[id] = continuation }
        continuation.onTermination = { [state] _ in state.withLock { $0.authorizationContinuations[id] = nil } }
        return stream
    }

    // MARK: What a test (or a person with a launch argument) can make happen

    public var scheduleCalls: Int { state.withLock { $0.scheduleCalls } }
    public var cancelCalls: Int { state.withLock { $0.cancelCalls } }
    public var promptCount: Int { state.withLock { $0.promptCount } }
    public var scheduledSettings: [AlarmSettings] { state.withLock { $0.alarms.values.map(\.settings) } }

    /// The alarm's time comes: it rings.
    public func fire(_ id: UUID) {
        move(id, to: .alerting)
    }

    /// The person chose Snooze while it rang.
    public func snooze(_ id: UUID) {
        move(id, to: .countdown)
    }

    /// The person stopped it: a one-shot alarm is deleted, a repeating one waits for its next day.
    public func stop(_ id: UUID) {
        state.withLock { state in
            guard let alarm = state.alarms[id] else { return }
            if alarm.settings.repeatDays.isEmpty {
                state.alarms[id] = nil
            } else {
                state.alarms[id] = (alarm.settings, .scheduled)
            }
        }
        publishAlarms()
    }

    /// The person changed the permission in Settings.
    public func setAuthorization(_ authorization: AlarmAuthorization) {
        state.withLock { $0.authorization = authorization }
        publishAuthorization()
    }

    // MARK: Plumbing

    private func move(_ id: UUID, to next: BackendAlarmState) {
        state.withLock { state in
            guard let alarm = state.alarms[id] else { return }
            state.alarms[id] = (alarm.settings, next)
        }
        publishAlarms()
    }

    private func snapshot() -> [BackendAlarm] {
        state.withLock { $0.alarms.map { BackendAlarm(id: $0.key, state: $0.value.state) } }
    }

    private func publishAlarms() {
        let (alarms, continuations) = state.withLock { ($0.alarms.map { BackendAlarm(id: $0.key, state: $0.value.state) }, Array($0.alarmContinuations.values)) }
        for continuation in continuations { continuation.yield(alarms) }
    }

    private func publishAuthorization() {
        let (value, continuations) = state.withLock { ($0.authorization, Array($0.authorizationContinuations.values)) }
        for continuation in continuations { continuation.yield(value) }
    }
}
#endif
