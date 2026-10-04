import DesignSystem
import Foundation
import NightKit
import Observation
import SoundKit
import SwiftUI

// The app's preferences (APP_RULES.md R38): every setting a person can change, typed, in one place, and
// the only file in the project allowed to name `UserDefaults.standard` (`JournalPrivacyTests`-style source
// scan: `RawDefaultsTests`). What a person's profile says (name, goals, sleep need, wake time) stays in the
// profile record, where Home, Tonight and Coach already read it; this holds everything else.

/// The one place the shared user defaults are named. Everything that remembers something small takes a
/// `UserDefaults` (so a test can hand it a throwaway suite) and, in the app, is given this.
public nonisolated enum NoctisUserDefaults {
    /// `UserDefaults` is documented thread-safe but the SDK does not say `Sendable`; this is the one handle.
    public nonisolated(unsafe) static let standard: UserDefaults = .standard
}

/// System, Light or Dark for the whole main app. Onboarding stays light whatever this says.
public nonisolated enum AppAppearance: String, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What `preferredColorScheme` takes: nil follows the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The scheme the whole window is asked for: onboarding is always light; the main app follows the choice.
    public static func scheme(showingMain: Bool, appearance: AppAppearance) -> ColorScheme? {
        showingMain ? appearance.colorScheme : .light
    }
}

/// The three repeating reminders and when each fires. Their words are generic and never carry a number from
/// Health (R13); `NotificationPlan` builds them.
public nonisolated struct NotificationPreferences: Sendable, Equatable {
    /// How long after the wake time the morning summary comes.
    public static let morningOffsets = [0, 15, 30, 45, 60]
    /// How long before bedtime the wind-down reminder comes.
    public static let windDownLeads = [10, 20, 30, 45]

    public var morningIsOn = true
    public var morningMinutesAfterWake = 15
    public var windDownIsOn = true
    public var windDownLeadMinutes = 20
    public var weeklyIsOn = true
    /// 1 is Sunday ... 7 is Saturday, as `DateComponents.weekday`.
    public var weeklyWeekday = 1
    public var weeklyMinutesSinceMidnight = 9 * 60

    public init() {}

    /// Anything outside what the screens offer goes back to its default.
    public func normalized() -> NotificationPreferences {
        var result = self
        if !Self.morningOffsets.contains(result.morningMinutesAfterWake) { result.morningMinutesAfterWake = 15 }
        if !Self.windDownLeads.contains(result.windDownLeadMinutes) { result.windDownLeadMinutes = 20 }
        if !(1...7).contains(result.weeklyWeekday) { result.weeklyWeekday = 1 }
        result.weeklyMinutesSinceMidnight = min(max(result.weeklyMinutesSinceMidnight, 0), 1439)
        return result
    }

    /// Whether any reminder is on.
    public var anyIsOn: Bool { morningIsOn || windDownIsOn || weeklyIsOn }

    /// Every reminder off: what "Not now" in onboarding means.
    public static var allOff: NotificationPreferences {
        var result = NotificationPreferences()
        result.morningIsOn = false
        result.windDownIsOn = false
        result.weeklyIsOn = false
        return result
    }
}

/// Everything in the preferences, as plain values.
public nonisolated struct PreferenceValues: Sendable, Equatable {
    public var appearance = AppAppearance.system
    /// The app's own taps and confirmations. It can only quiet them further: the system's haptics setting
    /// is never overridden.
    public var appHaptics = true
    public var windDownMinutes = 20
    /// The sound the wind-down starts with; nil for none.
    public var windDownSound: SoundKind?
    public var breathingPattern = BreathingPattern.defaultID
    public var breathingMinutes = BreathingSchedule.defaultMinutes
    public var breathingHaptics = false
    /// Where a sleep sound's volume starts until its own slider moves: 0 to 100.
    public var soundsGainPercent = 40
    /// The timer a sound starts with from the Sounds screen.
    public var soundsTimer = SleepTimerChoice.off
    public var notifications = NotificationPreferences()

    public init() {}

    public func normalized() -> PreferenceValues {
        var result = self
        if !WindDownClock.options.contains(result.windDownMinutes) { result.windDownMinutes = WindDownClock.defaultMinutes }
        if !BreathingSchedule.durations.contains(result.breathingMinutes) { result.breathingMinutes = BreathingSchedule.defaultMinutes }
        result.soundsGainPercent = min(max(result.soundsGainPercent, 0), 100)
        result.notifications = result.notifications.normalized()
        return result
    }

    /// `soundsGainPercent` as the player takes it.
    public var soundsGain: Float { Float(soundsGainPercent) / 100 }
}

/// Which group of preferences changed, for whoever has to react.
public nonisolated enum PreferenceChange: Sendable, Equatable {
    case appearance
    case haptics
    case windDown
    case breathing
    case sounds
    case notifications
}

/// The typed preferences. One observable `values` struct is what screens read and write, so a change
/// anywhere updates everything showing it; each change is written through to the defaults at once.
@MainActor
@Observable
public final class AppPreferences {
    public enum Key {
        public static let appearance = "noctis.pref.appearance"
        public static let appHaptics = "noctis.pref.appHaptics"
        /// Kept under their old names: the wind-down and Breathing already remembered these.
        public static let windDownMinutes = "noctis.winddown.minutes"
        public static let windDownSound = "noctis.winddown.sound"
        public static let breathingPattern = "noctis.breathing.pattern"
        public static let breathingMinutes = "noctis.breathing.minutes"
        public static let breathingHaptics = "noctis.breathing.haptics"
        public static let soundsGain = "noctis.pref.sounds.gainPercent"
        public static let soundsTimer = "noctis.pref.sounds.timerMinutes"
        public static let morningOn = "noctis.pref.notifications.morning.on"
        public static let morningMinutes = "noctis.pref.notifications.morning.minutes"
        public static let windDownReminderOn = "noctis.pref.notifications.winddown.on"
        public static let windDownLead = "noctis.pref.notifications.winddown.lead"
        public static let weeklyOn = "noctis.pref.notifications.weekly.on"
        public static let weeklyWeekday = "noctis.pref.notifications.weekly.weekday"
        public static let weeklyTime = "noctis.pref.notifications.weekly.time"
    }

    public private(set) var values: PreferenceValues

    /// Told after every change, with what changed.
    @ObservationIgnored public var onChange: (@MainActor (PreferenceChange) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = NoctisUserDefaults.standard) {
        self.defaults = defaults
        values = Self.load(from: defaults)
    }

    // MARK: Changing

    /// Changes the preferences, keeps them inside what is offered, writes what changed and says so.
    public func update(_ change: (inout PreferenceValues) -> Void) {
        let before = values
        var after = before
        change(&after)
        after = after.normalized()
        guard after != before else { return }
        values = after
        Self.write(after, before: before, to: defaults)
        for kind in Self.changes(from: before, to: after) { onChange?(kind) }
    }

    /// One value by its key path.
    public func set<Value>(_ keyPath: WritableKeyPath<PreferenceValues, Value>, to value: Value) {
        update { $0[keyPath: keyPath] = value }
    }

    // MARK: Reading

    static func load(from defaults: UserDefaults) -> PreferenceValues {
        var values = PreferenceValues()
        func int(_ key: String) -> Int? { defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key) }
        func bool(_ key: String) -> Bool? { defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key) }
        values.appearance = defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        values.appHaptics = bool(Key.appHaptics) ?? true
        values.windDownMinutes = int(Key.windDownMinutes) ?? WindDownClock.defaultMinutes
        values.windDownSound = defaults.string(forKey: Key.windDownSound).flatMap(SoundKind.init(rawValue:))
        values.breathingPattern = defaults.string(forKey: Key.breathingPattern).flatMap(BreathingPattern.ID.init(rawValue:)) ?? BreathingPattern.defaultID
        values.breathingMinutes = int(Key.breathingMinutes) ?? BreathingSchedule.defaultMinutes
        values.breathingHaptics = bool(Key.breathingHaptics) ?? false
        values.soundsGainPercent = int(Key.soundsGain) ?? 40
        values.soundsTimer = int(Key.soundsTimer).flatMap(SleepTimerChoice.init(rawValue:)) ?? .off
        var notifications = NotificationPreferences()
        notifications.morningIsOn = bool(Key.morningOn) ?? true
        notifications.morningMinutesAfterWake = int(Key.morningMinutes) ?? 15
        notifications.windDownIsOn = bool(Key.windDownReminderOn) ?? true
        notifications.windDownLeadMinutes = int(Key.windDownLead) ?? 20
        notifications.weeklyIsOn = bool(Key.weeklyOn) ?? true
        notifications.weeklyWeekday = int(Key.weeklyWeekday) ?? 1
        notifications.weeklyMinutesSinceMidnight = int(Key.weeklyTime) ?? 9 * 60
        values.notifications = notifications
        return values.normalized()
    }

    // MARK: Writing

    private static func write(_ values: PreferenceValues, before: PreferenceValues, to defaults: UserDefaults) {
        if values.appearance != before.appearance { defaults.set(values.appearance.rawValue, forKey: Key.appearance) }
        if values.appHaptics != before.appHaptics { defaults.set(values.appHaptics, forKey: Key.appHaptics) }
        if values.windDownMinutes != before.windDownMinutes { defaults.set(values.windDownMinutes, forKey: Key.windDownMinutes) }
        if values.windDownSound != before.windDownSound { defaults.set(values.windDownSound?.rawValue ?? "none", forKey: Key.windDownSound) }
        if values.breathingPattern != before.breathingPattern { defaults.set(values.breathingPattern.rawValue, forKey: Key.breathingPattern) }
        if values.breathingMinutes != before.breathingMinutes { defaults.set(values.breathingMinutes, forKey: Key.breathingMinutes) }
        if values.breathingHaptics != before.breathingHaptics { defaults.set(values.breathingHaptics, forKey: Key.breathingHaptics) }
        if values.soundsGainPercent != before.soundsGainPercent { defaults.set(values.soundsGainPercent, forKey: Key.soundsGain) }
        if values.soundsTimer != before.soundsTimer { defaults.set(values.soundsTimer.rawValue, forKey: Key.soundsTimer) }
        let n = values.notifications, o = before.notifications
        if n.morningIsOn != o.morningIsOn { defaults.set(n.morningIsOn, forKey: Key.morningOn) }
        if n.morningMinutesAfterWake != o.morningMinutesAfterWake { defaults.set(n.morningMinutesAfterWake, forKey: Key.morningMinutes) }
        if n.windDownIsOn != o.windDownIsOn { defaults.set(n.windDownIsOn, forKey: Key.windDownReminderOn) }
        if n.windDownLeadMinutes != o.windDownLeadMinutes { defaults.set(n.windDownLeadMinutes, forKey: Key.windDownLead) }
        if n.weeklyIsOn != o.weeklyIsOn { defaults.set(n.weeklyIsOn, forKey: Key.weeklyOn) }
        if n.weeklyWeekday != o.weeklyWeekday { defaults.set(n.weeklyWeekday, forKey: Key.weeklyWeekday) }
        if n.weeklyMinutesSinceMidnight != o.weeklyMinutesSinceMidnight { defaults.set(n.weeklyMinutesSinceMidnight, forKey: Key.weeklyTime) }
    }

    static func changes(from before: PreferenceValues, to after: PreferenceValues) -> [PreferenceChange] {
        var result: [PreferenceChange] = []
        if after.appearance != before.appearance { result.append(.appearance) }
        if after.appHaptics != before.appHaptics { result.append(.haptics) }
        if after.windDownMinutes != before.windDownMinutes || after.windDownSound != before.windDownSound { result.append(.windDown) }
        if after.breathingPattern != before.breathingPattern || after.breathingMinutes != before.breathingMinutes
            || after.breathingHaptics != before.breathingHaptics { result.append(.breathing) }
        if after.soundsGainPercent != before.soundsGainPercent || after.soundsTimer != before.soundsTimer { result.append(.sounds) }
        if after.notifications != before.notifications { result.append(.notifications) }
        return result
    }
}

// MARK: - Where the views find it

private struct AppPreferencesKey: EnvironmentKey {
    static let defaultValue: AppPreferences? = nil
}

extension EnvironmentValues {
    /// The app's preferences, where the app has put them; nil in a preview or a test that has not.
    public var appPreferences: AppPreferences? {
        get { self[AppPreferencesKey.self] }
        set { self[AppPreferencesKey.self] = newValue }
    }
}
