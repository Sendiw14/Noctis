import DesignSystem
import Foundation
import HomeFeature
import NightKit

// The wake alarm as the screen shows it: the card, and the words of the states around it.
// Built from `AlarmStatus` (what `AlarmService` knows); the views write nothing (R18, R20).

public nonisolated struct AlarmChip: Sendable, Equatable {
    public enum Tone: Sendable, Equatable {
        /// Scheduled, snoozed, ringing.
        case on
        case off
        /// Permission needed, an error, not available.
        case attention
    }

    public let text: String
    public let tone: Tone
}

public nonisolated struct AlarmCardContent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case normal
        case permissionDenied
        case unavailable
        case error
    }

    public let kind: Kind
    /// The alarm's time ("7:30 AM").
    public let time: NoctisMetricValue
    public let isOn: Bool
    /// "Once", "Weekdays", "Mon, Wed, Fri".
    public let repeatSummary: String
    public let chip: AlarmChip
    /// A calm sentence for the states that need one (permission, availability, an error).
    public let message: String?
    public let accessibilityLabel: String
}

public nonisolated enum AlarmBuilder {
    /// What the alarm's sheet says under the time: it is the honest claim, and nothing more.
    public static let honestyLine = "Rings at your set time, even in silent mode or Focus."

    /// Before the very first alarm, in plain words (the system asks once).
    public static let permissionExplanation = "NOCTIS asks your iPhone to schedule alarms so yours can ring at the time you set. Your iPhone will ask you to allow it. It asks once."

    public static let deniedMessage = "Alarms are turned off for NOCTIS. You can allow them in Settings."
    public static let unavailableMessage = "Alarms aren't available here. They need iOS 26 or later."

    public static func errorMessage(_ failure: AlarmFailure?) -> String {
        switch failure {
        case .limitReached: "Your iPhone has reached its limit for alarms. Remove one in another app, then try again."
        case .scheduleFailed, nil: "NOCTIS couldn't set the alarm. Try again."
        }
    }

    public static func card(for status: AlarmStatus, format: HomeFormat) -> AlarmCardContent {
        let time = format.clockMetric(format.clock(minutesSinceMidnight: status.settings.minutesSinceMidnight))
        let summary = repeatSummary(status.settings.repeatDays, format: format)
        let (kind, chip, message): (AlarmCardContent.Kind, AlarmChip, String?) = switch status.state {
        case .scheduled, .armed: (.normal, AlarmChip(text: "Scheduled", tone: .on), nil)
        case .snoozed: (.normal, AlarmChip(text: "Snoozed", tone: .on), nil)
        case .firing: (.normal, AlarmChip(text: "Ringing", tone: .on), nil)
        case .off, .cancelled, .dismissed: (.normal, AlarmChip(text: "Off", tone: .off), nil)
        case .permissionDenied: (.permissionDenied, AlarmChip(text: "Permission needed", tone: .attention), deniedMessage)
        case .unavailable: (.unavailable, AlarmChip(text: "Not available", tone: .attention), unavailableMessage)
        case .error: (.error, AlarmChip(text: "Couldn't set", tone: .attention), errorMessage(status.failure))
        }
        let label = ["Alarm", time.spoken, summary, chip.text, message].compactMap { $0 }.joined(separator: ". ")
        return AlarmCardContent(kind: kind, time: time, isOn: status.isOn, repeatSummary: summary, chip: chip, message: message, accessibilityLabel: label)
    }

    /// "Once", "Every day", "Weekdays", "Weekends", or the days: "Mon, Wed, Fri".
    public static func repeatSummary(_ days: Set<AlarmWeekday>, format: HomeFormat) -> String {
        if days.isEmpty { return "Once" }
        if days == AlarmWeekday.everyDay { return "Every day" }
        if days == AlarmWeekday.weekdays { return "Weekdays" }
        if days == AlarmWeekday.weekend { return "Weekends" }
        return AlarmWeekday.mondayFirst.filter(days.contains).map { dayName($0, width: .abbreviated, format: format) }.joined(separator: ", ")
    }

    /// "Mon", "M", "Monday", in the person's language.
    public static func dayName(_ day: AlarmWeekday, width: HomeFormat.WeekdayWidth, format: HomeFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = format.locale
        let symbols: [String] = switch width {
        case .narrow: formatter.veryShortWeekdaySymbols
        case .abbreviated: formatter.shortWeekdaySymbols
        case .wide: formatter.weekdaySymbols
        }
        return symbols[day.rawValue - 1]
    }
}
