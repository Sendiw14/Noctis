import Foundation

/// What Siri and Shortcuts say (APP_RULES.md R47), built from the same snapshot, the same day rule and the same words as the
/// widgets (R44, R45): "Your recovery is 70. Sleep was 6 hours 42 minutes." Pure, so every state is a unit test and every sentence goes
/// through the banned-language lint.
///
/// It never pretends: with no snapshot it says to open NOCTIS, a snapshot for an earlier day is "waiting for last night's sleep" and
/// never yesterday's numbers as today's, and stale numbers are said to be old. Health numbers (recovery, sleep) come only from here, so
/// only the intents that speak them ask for the device to be unlocked; the bedtime is the person's plan, not Health.
public enum WidgetSpoken {
    /// "Your recovery is 70. Sleep was 6 hours 42 minutes."
    public static func recovery(_ snapshot: WidgetSnapshot?, now: Date, calendar: Calendar, format: WidgetFormat = WidgetFormat()) -> String {
        switch availability(snapshot, now: now, calendar: calendar) {
        case .message(let words): return words
        case .numbers(let snapshot, let staleHours):
            guard let recovery = snapshot.recovery else {
                // Stale and no score: only last night's sleep is known.
                return sleepSentence(snapshot, stale: staleHours, past: true) ?? "Apple Health has no recovery for you yet."
            }
            var sentences: [String] = []
            if let staleHours { sentences.append("The latest numbers are \(WidgetSpoken.hours(staleHours)) old.") }
            sentences.append(staleHours == nil ? "Your recovery is \(recovery.score)." : "Your recovery was \(recovery.score).")
            if let night = snapshot.lastNight { sentences.append("Sleep was \(WidgetFormat.spokenDuration(night.asleepMinutes)).") }
            return sentences.joined(separator: " ")
        }
    }

    /// "You slept 6 hours 42 minutes. Sleep quality was 81."
    public static func sleep(_ snapshot: WidgetSnapshot?, now: Date, calendar: Calendar, format: WidgetFormat = WidgetFormat()) -> String {
        switch availability(snapshot, now: now, calendar: calendar) {
        case .message(let words): return words
        case .numbers(let snapshot, let staleHours):
            return sleepSentence(snapshot, stale: staleHours, past: false) ?? "No sleep was recorded last night."
        }
    }

    /// "Your bedtime tonight is 11:00 PM." The bedtime only: it is the plan, not a Health value.
    public static func bedtime(_ snapshot: WidgetSnapshot?, format: WidgetFormat = WidgetFormat()) -> String {
        guard let snapshot else { return WidgetCopy.getStarted + "." }
        let time = format.clock(minutesSinceMidnight: snapshot.plan.bedtimeMinutes)
        return "Your bedtime tonight is \(time)."
    }

    /// "Alarm set for 6:30 AM."
    public static func alarmSet(minutes: Int, format: WidgetFormat = WidgetFormat()) -> String {
        "Alarm set for \(format.clock(minutesSinceMidnight: minutes))."
    }

    // MARK: Which numbers may be spoken

    private enum Availability {
        case message(String)
        /// Numbers for today, or the last known ones with their age.
        case numbers(WidgetSnapshot, staleHours: Int?)
    }

    private static func availability(_ snapshot: WidgetSnapshot?, now: Date, calendar: Calendar) -> Availability {
        guard let snapshot else { return .message(WidgetCopy.getStarted + ".") }
        // The widgets' rule (R45): a day starts at 4 AM; a snapshot for an earlier day is waiting, never today's.
        if snapshot.forDay < WidgetDay.today(at: now, calendar: calendar) {
            return .message("NOCTIS is waiting for last night's sleep.")
        }
        switch snapshot.state {
        case .noPermission, .empty: return .message(WidgetCopy.connectHealth + ".")
        case .learning(let nights): return .message("NOCTIS is still learning your baseline: \(WidgetCopy.nights(nights)) so far.")
        case .gap: return .message("No sleep was recorded last night.")
        case .full, .sleepOnly: return .numbers(snapshot, staleHours: nil)
        case .stale(let hours):
            let age = hours + max(Int(now.timeIntervalSince(snapshot.generatedAt) / 3600), 0)
            return .numbers(snapshot, staleHours: age)
        }
    }

    private static func sleepSentence(_ snapshot: WidgetSnapshot, stale: Int?, past: Bool) -> String? {
        guard let night = snapshot.lastNight else { return nil }
        var sentences: [String] = []
        if let stale { sentences.append("The latest numbers are \(hours(stale)) old.") }
        let duration = WidgetFormat.spokenDuration(night.asleepMinutes)
        sentences.append(stale == nil && !past ? "You slept \(duration)." : "The last recorded sleep was \(duration).")
        if let quality = night.quality { sentences.append("Sleep quality was \(quality).") }
        return sentences.joined(separator: " ")
    }

    /// "14 hours", "2 days".
    static func hours(_ hours: Int) -> String {
        hours < 48 ? "\(hours) \(hours == 1 ? "hour" : "hours")" : "\(hours / 24) days"
    }
}
