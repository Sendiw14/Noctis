import Foundation

/// The system's alarms, as the service needs them. `AlarmKitBackend` is the real one; the
/// DEBUG `MockAlarmBackend` plays one for tests and launch arguments.
public protocol AlarmBackend: Sendable {
    func authorization() async -> AlarmAuthorization
    /// Asks the person, if they haven't been asked; returns their answer.
    func requestAuthorization() async throws -> AlarmAuthorization
    func schedule(id: UUID, settings: AlarmSettings) async throws
    /// Removes the alarm, wherever it is in its life.
    func cancel(id: UUID) async throws
    /// The alarms the system holds for this app. A one-shot alarm that has rung and been
    /// stopped is not among them.
    func alarms() async throws -> [BackendAlarm]
    /// Yields whenever the set of alarms, or one's state, changes.
    func alarmUpdates() -> AsyncStream<[BackendAlarm]>
    func authorizationUpdates() -> AsyncStream<AlarmAuthorization>
}

/// What the person may keep the alarm's data on: `AlarmConfiguration` (SwiftData) in the app.
public protocol AlarmSettingsStoring: Sendable {
    func load() async -> AlarmSettings?
    func save(_ settings: AlarmSettings) async
}
