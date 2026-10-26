import Foundation
import NightKit
import SwiftData

/// The wake alarm's own record (APP_RULES.md R30): the time, the days it repeats, the snooze,
/// the id AlarmKit knows it by and the last state it was seen in. The system deletes a
/// one-shot alarm the moment it has rung, so this is how the app knows it did.
///
/// It lives beside the profile in the same local store. There is no CloudKit path in the app
/// today (the profile isn't synced either), so it isn't synced; if the profile ever is, this
/// record is built to follow it (every attribute has a default, none is unique).
@Model
public final class AlarmConfiguration {
    /// When it rings, minutes since midnight. Starts as the profile's wake time.
    public var minutesSinceMidnight: Int = 7 * 60
    /// `AlarmWeekday` raw values (1 is Sunday); empty rings once.
    public var repeatDaysRaw: [Int] = []
    public var snoozeEnabled: Bool = false
    public var snoozeMinutes: Int = AlarmSettings.defaultSnoozeMinutes
    public var alarmKitID: UUID?
    public var lastStateRaw: String = AlarmState.off.rawValue
    public var updatedAt: Date = Date.now

    public init() {}

    public func apply(_ settings: AlarmSettings) {
        minutesSinceMidnight = settings.minutesSinceMidnight
        repeatDaysRaw = settings.repeatDays.map(\.rawValue).sorted()
        snoozeEnabled = settings.snoozeEnabled
        snoozeMinutes = settings.snoozeMinutes
        alarmKitID = settings.alarmKitID
        lastStateRaw = settings.lastState.rawValue
        updatedAt = Date.now
    }

    public var settings: AlarmSettings {
        AlarmSettings(
            minutesSinceMidnight: minutesSinceMidnight, repeatDays: Set(repeatDaysRaw.compactMap(AlarmWeekday.init(rawValue:))),
            snoozeEnabled: snoozeEnabled, snoozeMinutes: snoozeMinutes, alarmKitID: alarmKitID,
            lastState: AlarmState(rawValue: lastStateRaw) ?? .off
        )
    }
}

/// Reads and writes the one `AlarmConfiguration`, for `AlarmService`.
@MainActor
public final class AlarmConfigurationStore: AlarmSettingsStoring {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// The saved alarm; nil before the person has ever set one.
    public func load() async -> AlarmSettings? {
        (try? context.fetch(FetchDescriptor<AlarmConfiguration>()))?.first?.settings
    }

    public func save(_ settings: AlarmSettings) async {
        let record =
            (try? context.fetch(FetchDescriptor<AlarmConfiguration>()))?.first
            ?? {
                let new = AlarmConfiguration()
                context.insert(new)
                return new
            }()
        record.apply(settings)
        try? context.save()
    }

    /// Forgets the alarm (Data Management will call this along with cancelling it).
    public func erase() {
        for record in (try? context.fetch(FetchDescriptor<AlarmConfiguration>())) ?? [] {
            context.delete(record)
        }
        try? context.save()
    }
}
