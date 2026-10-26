import ActivityKit
import AlarmKit
import AlarmShared
import Foundation
import SwiftUI
import os

/// The real alarm system. Everything here was checked against the iOS SDK's AlarmKit
/// interface (see APP_RULES.md R30 for what differs from what one would assume):
///
/// - There is no "update": changing an alarm is a cancel and a new schedule.
/// - A snooze is AlarmKit's countdown state: a secondary "Snooze" button whose behavior is
///   `.countdown`, and a post-alert countdown duration. The system draws the countdown with
///   the app's alarm widget extension (`NoctisAlarmWidget`).
/// - Without a snooze there is no countdown presentation and no countdown duration; the
///   system refuses to schedule a countdown presentation without a duration.
/// - A relative schedule follows the device's time zone: a wake alarm is exactly that.
/// - The Info.plist key `NSAlarmKitUsageDescription` must be present, or scheduling fails.
public struct AlarmKitBackend: AlarmBackend {
    public init() {}

    public func authorization() async -> AlarmAuthorization {
        Self.map(AlarmManager.shared.authorizationState)
    }

    public func requestAuthorization() async throws -> AlarmAuthorization {
        do {
            return Self.map(try await AlarmManager.shared.requestAuthorization())
        } catch {
            throw AlarmBackendError.failed
        }
    }

    public func schedule(id: UUID, settings: AlarmSettings) async throws {
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: Self.configuration(for: settings))
        } catch let error as AlarmManager.AlarmError where error == .maximumLimitReached {
            throw AlarmBackendError.limitReached
        } catch {
            // The system's error domain and code (constants), never its description and never the person's data.
            let reported = error as NSError
            Logger(subsystem: "com.noctis.app", category: "alarm").error(
                "AlarmKit schedule threw \(reported.domain, privacy: .public) \(reported.code, privacy: .public)")
            throw AlarmBackendError.failed
        }
    }

    public func cancel(id: UUID) async throws {
        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            throw AlarmBackendError.failed
        }
    }

    public func alarms() async throws -> [BackendAlarm] {
        do {
            return try AlarmManager.shared.alarms.map { BackendAlarm(id: $0.id, state: Self.map($0.state)) }
        } catch {
            throw AlarmBackendError.failed
        }
    }

    public func alarmUpdates() -> AsyncStream<[BackendAlarm]> {
        let (stream, continuation) = AsyncStream<[BackendAlarm]>.makeStream()
        let task = Task {
            for await alarms in AlarmManager.shared.alarmUpdates {
                continuation.yield(alarms.map { BackendAlarm(id: $0.id, state: Self.map($0.state)) })
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func authorizationUpdates() -> AsyncStream<AlarmAuthorization> {
        let (stream, continuation) = AsyncStream<AlarmAuthorization>.makeStream()
        let task = Task {
            for await state in AlarmManager.shared.authorizationUpdates {
                continuation.yield(Self.map(state))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: Mapping

    static func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorization {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        @unknown default: .denied
        }
    }

    static func map(_ state: Alarm.State) -> BackendAlarmState {
        switch state {
        case .scheduled: .scheduled
        case .countdown: .countdown
        case .paused: .paused
        case .alerting: .alerting
        @unknown default: .scheduled
        }
    }

    static func weekday(_ day: AlarmWeekday) -> Locale.Weekday {
        switch day {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        }
    }

    /// The schedule for `settings`: a time on the device's clock, once or on its days.
    static func schedule(for settings: AlarmSettings) -> Alarm.Schedule {
        let time = Alarm.Schedule.Relative.Time(hour: settings.minutesSinceMidnight / 60, minute: settings.minutesSinceMidnight % 60)
        let days = settings.repeatDays.sorted().map(weekday)
        let recurrence: Alarm.Schedule.Relative.Recurrence = days.isEmpty ? .never : .weekly(days)
        return .relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
    }

    /// How the alarm presents itself. The word is "Alarm": it rings at a set time, and that is
    /// all it claims.
    static func presentation(for settings: AlarmSettings) -> AlarmPresentation {
        let snooze = AlarmButton(text: "Snooze", textColor: .white, systemImageName: "bed.double.fill")
        // iOS 26.1 draws Stop itself, so the alert names only the secondary button.
        let alert = AlarmPresentation.Alert(
            title: "Alarm", secondaryButton: settings.snoozeEnabled ? snooze : nil,
            secondaryButtonBehavior: settings.snoozeEnabled ? .countdown : nil
        )
        let countdown = settings.snoozeEnabled ? AlarmPresentation.Countdown(title: "Snoozed") : nil
        return AlarmPresentation(alert: alert, countdown: countdown, paused: nil)
    }

    static func configuration(for settings: AlarmSettings) -> AlarmManager.AlarmConfiguration<NoctisAlarmMetadata> {
        let attributes = AlarmAttributes<NoctisAlarmMetadata>(
            presentation: presentation(for: settings), metadata: NoctisAlarmMetadata(), tintColor: Color(red: 0.627, green: 0.549, blue: 0.922)
        )
        let snooze = settings.snoozeEnabled ? Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(settings.snoozeMinutes * 60)) : nil
        return AlarmManager.AlarmConfiguration(
            countdownDuration: snooze, schedule: schedule(for: settings), attributes: attributes, stopIntent: nil, secondaryIntent: nil, sound: .default
        )
    }
}
