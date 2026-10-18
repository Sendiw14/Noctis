import DesignSystem
import Foundation
import HealthProviding
import HomeFeature
import NightFeature
import NightKit
import NoctisCore
import SleepAnalysisKit
import SleepKit
import NoctisText

/// One of the three status rows on Profile: where it opens, and the one word or phrase it carries.
public nonisolated struct ProfileStatusRow: Sendable, Equatable, Identifiable {
    public let page: SettingsPage
    public let title: String
    public let value: String
    public let systemImage: String

    public var id: SettingsPage { page }
}

/// Everything Profile says, as words: built from the profile, the Sleep tab's engines, the alarm and the
/// status of Health, notifications and the subscription. Pure, so each sentence can be tested.
public nonisolated struct ProfileContent: Sendable, Equatable {
    /// "WEDNESDAY, SEPTEMBER 30".
    public let dateCaption: String
    /// "Sam, your sleep profile and settings." or "Your sleep profile and settings."
    public let summary: String
    public let name: String
    /// "Sam", or "Add your name".
    public let nameValue: String
    /// Tonight's bedtime, from the same recommendation as Tonight and the evening reminder.
    public let bedtime: TonightContent
    /// "8h".
    public let needValue: String
    /// "7:00 AM".
    public let wakeValue: String
    /// "11:10 PM", or "Still learning".
    public let typicalBedtime: String
    public let typicalWake: String
    /// What "Still learning" is waiting for; nil once the typical times are known.
    public let learningNote: String?
    public let goals: [PrimaryGoal]
    /// "Better sleep, More energy".
    public let goalsValue: String
    /// While a wake alarm is on: it keeps its own time, whatever the wake time says.
    public let alarmLine: String?
    public let status: [ProfileStatusRow]
}

public nonisolated enum ProfileBuilder {
    /// The inputs Profile reads, gathered so the builder is a plain function of them.
    public struct Inputs: Sendable {
        public var profile: UserProfileSnapshot
        public var timing: SleepTimingResult?
        public var balance: SleepBalanceResult?
        public var consistency: ConsistencyResult?
        public var alarm: AlarmStatus?
        /// nil until the first look at Health has come back.
        public var health: HealthDataStatus?
        public var notifications: NotificationAuthorization
        public var reminderPreferences: NotificationPreferences
        public var isPremium: Bool

        public init(
            profile: UserProfileSnapshot, timing: SleepTimingResult? = nil, balance: SleepBalanceResult? = nil,
            consistency: ConsistencyResult? = nil, alarm: AlarmStatus? = nil, health: HealthDataStatus? = nil,
            notifications: NotificationAuthorization = .notDetermined, reminderPreferences: NotificationPreferences = NotificationPreferences(),
            isPremium: Bool = false
        ) {
            self.profile = profile
            self.timing = timing
            self.balance = balance
            self.consistency = consistency
            self.alarm = alarm
            self.health = health
            self.notifications = notifications
            self.reminderPreferences = reminderPreferences
            self.isPremium = isPremium
        }
    }

    public static func content(_ inputs: Inputs, now: Date, timeZone: TimeZone, format: HomeFormat) -> ProfileContent {
        let profile = inputs.profile
        let name = ProfileEdit.cleaned(name: profile.name)
        let recommendation = BedtimeInputsBuilder.recommendation(
            wakeMinutes: profile.typicalWakeMinutes, needMinutes: profile.needMinutes, timing: inputs.timing, balance: inputs.balance,
            consistency: inputs.consistency, now: now, timeZone: timeZone, personalized: inputs.isPremium
        )
        let bedtime = TonightBuilder.content(for: recommendation, now: now, timeZone: timeZone, format: format, personalized: inputs.isPremium)
        let nights = inputs.timing?.nights ?? 0
        let known = nights >= BedtimeInputsBuilder.usualBedtimeMinimumNights
        let typicalBedtime = known ? inputs.timing?.typicalBedtime.map { format.clock(minutesAfterNoon: $0) } : nil
        let typicalWake = known ? inputs.timing?.typicalWake.map { format.clock(minutesAfterNoon: $0) } : nil
        let goals = goals(of: profile)
        return ProfileContent(
            dateCaption: bedtime.dateCaption,
            summary: name.isEmpty ? "Your sleep profile and settings." : "\(name), your sleep profile and settings.",
            name: name,
            nameValue: name.isEmpty ? "Add your name" : name,
            bedtime: bedtime,
            needValue: HomeFormat.compactDuration(profile.needMinutes),
            wakeValue: format.clock(minutesSinceMidnight: profile.typicalWakeMinutes),
            typicalBedtime: typicalBedtime ?? "Still learning",
            typicalWake: typicalWake ?? "Still learning",
            learningNote: typicalBedtime == nil || typicalWake == nil ? learningNote(nights: nights) : nil,
            goals: goals,
            goalsValue: goals.isEmpty ? "None chosen" : goals.map(\.displayName).joined(separator: ", "),
            alarmLine: alarmLine(inputs.alarm, format: format),
            status: [
                ProfileStatusRow(page: .healthData, title: "Health data", value: healthValue(inputs.health), systemImage: "heart.text.square"),
                ProfileStatusRow(
                    page: .notifications, title: "Notifications", value: notificationsValue(inputs.notifications, inputs.reminderPreferences),
                    systemImage: "bell"
                ),
                ProfileStatusRow(page: .subscription, title: "Subscription", value: inputs.isPremium ? "Premium" : "Free", systemImage: "star"),
            ]
        )
    }

    /// The goals, in the order they were chosen (a profile saved before they were kept as a list has a primary
    /// and maybe a secondary).
    public static func goals(of profile: UserProfileSnapshot) -> [PrimaryGoal] {
        if !profile.selectedGoals.isEmpty { return ProfileEdit.limited(profile.selectedGoals) }
        return ProfileEdit.limited([profile.primaryGoal] + (profile.secondaryGoal.map { [$0] } ?? []))
    }

    static func learningNote(nights: Int) -> String {
        let needed = BedtimeInputsBuilder.usualBedtimeMinimumNights
        let have = min(nights, needed)
        return "Your typical times appear after \(needed) recorded nights. \(have) so far."
    }

    /// One line, only while an alarm is on: the alarm has its own time, and moving the wake time doesn't move it.
    static func alarmLine(_ alarm: AlarmStatus?, format: HomeFormat) -> String? {
        guard let alarm, alarm.isOn else { return nil }
        return "Your wake alarm keeps its own time, \(format.clock(minutesSinceMidnight: alarm.settings.minutesSinceMidnight)). Change it from Tonight."
    }

    static func healthValue(_ health: HealthDataStatus?) -> String {
        guard let health else { return "Checking" }
        if health.isUnavailable { return "Not available" }
        if health.hasAllData { return "Data found" }
        return health.hasAnyData ? "Some data found" : "No data found"
    }

    static func notificationsValue(_ authorization: NotificationAuthorization, _ preferences: NotificationPreferences) -> String {
        switch authorization {
        case .denied: return "Off in Settings"
        case .notDetermined: return "Not turned on"
        case .allowed:
            let count = [preferences.morningIsOn, preferences.windDownIsOn, preferences.weeklyIsOn].filter { $0 }.count
            return count == 0 ? "All reminders off" : NoctisCount.remindersOn(count)
        }
    }
}
