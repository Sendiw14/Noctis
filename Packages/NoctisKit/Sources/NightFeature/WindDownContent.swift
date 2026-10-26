import DesignSystem
import Foundation
import NightKit
import NoctisText
import SoundKit

/// The Wind-down screen's fixed words (APP_RULES.md R32). Calm and plain: no streak, no score, no
/// shame, and nothing about what any of it does for anyone's sleep or health.
public nonisolated enum WindDownCopy {
    public static let title = "Wind down"
    public static let line = "It's time to relax."
    public static let preStartLine = "A few quiet minutes before bed."
    public static let begin = "Begin"
    public static let end = "End"
    public static let pause = "Pause"
    public static let resume = "Resume"
    public static let finishTitle = "Sleep well."
    public static let done = "Done"
    public static let setAlarm = "Set alarm"
    public static let notNow = "Not now"
    public static let soundOn = "Sound on"
    public static let soundOff = "Sound off"
}

/// The countdown: whole minutes until the last minute, then seconds.
public nonisolated enum WindDownCountdown {
    public static func metric(remaining: TimeInterval) -> NoctisMetricValue {
        let seconds = max(Int(remaining.rounded(.up)), 0)
        if seconds > 60 {
            let minutes = (seconds + 59) / 60
            return NoctisMetricValue(parts: [.number("\(minutes)"), .unit(NoctisUnit.minuteShort.symbol)], spoken: NoctisCount.minutes(minutes))
        }
        return NoctisMetricValue(parts: [.number("\(seconds)"), .unit(NoctisUnit.second.symbol)], spoken: NoctisCount.seconds(seconds))
    }
}

/// What the finish card says about the alarm: "Alarm set for 7:00 AM", or nothing, and a button to set one.
public nonisolated struct WindDownFinishContent: Sendable, Equatable {
    public let alarmLine: String?
    public let showsSetAlarm: Bool

    public static func make(alarm: AlarmStatus?, clock: (Int) -> String) -> WindDownFinishContent {
        guard let alarm, alarm.isOn else { return WindDownFinishContent(alarmLine: nil, showsSetAlarm: alarm?.state != .unavailable) }
        return WindDownFinishContent(alarmLine: "Alarm set for \(clock(alarm.settings.minutesSinceMidnight))", showsSetAlarm: false)
    }
}
