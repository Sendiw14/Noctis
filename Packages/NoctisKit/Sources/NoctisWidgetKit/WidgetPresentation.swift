import DesignSystem
import Foundation

// What each surface says for each entry, as data (APP_RULES.md R45): the words, the numbers, which of them are Health values (and so
// hidden on a locked iPhone) and which are not. The views only lay it out, so every state's wording, every omission and every
// sensitivity flag is a unit test.

/// Whether a value may be shown on a locked iPhone.
public enum WidgetSensitivity: Sendable, Equatable {
    /// Worked out from Health: hidden while the device is locked.
    case health
    /// The plan (bedtime, wake time, need, the alarm): the person's own settings, not Health.
    case plan
}

/// The words every surface uses.
public enum WidgetCopy {
    public static let getStarted = "Open NOCTIS to get started"
    public static let connectHealth = "Open NOCTIS to connect Apple Health"
    public static let learningTitle = "Learning your baseline"
    public static let noSleep = "No sleep recorded last night"
    public static let waitingTitle = "Waiting for last night's sleep"
    public static let waitingDetail = "NOCTIS shows it once Apple Health has it."
    public static let unlock = "Unlock to see"
    public static let sample = "Sample"

    /// "3 of 5 nights".
    public static func nights(_ so: Int) -> String { "\(so) of \(WidgetSnapshot.learningNights) nights" }

    /// "Learning your baseline - 3 of 5 nights", on one line.
    public static func learningLine(_ so: Int) -> String { "\(learningTitle) - \(nights(so))" }

    /// "Updated 14h ago", or in days from two days on.
    public static func updated(hours: Int) -> String {
        hours < 48 ? "Updated \(max(hours, 0))h ago" : "Updated \(hours / 24)d ago"
    }

    /// "+6", "−18", "±0": the sign is always shown.
    public static func signed(_ delta: Int) -> String {
        delta > 0 ? "+\(delta)" : delta < 0 ? "\u{2212}\(-delta)" : "\u{00B1}0"
    }

    /// "Within your normal range", "Above your normal range", "Below your normal range": the iPhone's own words (Home's range sentence is made from
    /// this), so the Watch says what the iPhone says.
    public static func rangePlace(_ range: WidgetFactorRange) -> String {
        switch range {
        case .within: "Within your normal range"
        case .above: "Above your normal range"
        case .below: "Below your normal range"
        }
    }

    /// A delta is above at +3 or more and below at −3 or less (the recovery model's threshold, which a test holds this to).
    public static let trendThreshold = 3
}

public struct WidgetLine: Equatable, Sendable {
    public var label: String
    public var value: NoctisMetricValue
    public var sensitivity: WidgetSensitivity
    /// The factor's color, for the dot beside the row.
    public var tint: WidgetFactorKind?

    public init(label: String, value: NoctisMetricValue, sensitivity: WidgetSensitivity, tint: WidgetFactorKind? = nil) {
        self.label = label
        self.value = value
        self.sensitivity = sensitivity
        self.tint = tint
    }
}

public struct WidgetMessage: Equatable, Sendable {
    /// An SF Symbol.
    public var glyph: String
    public var title: String
    public var detail: String?

    public init(glyph: String, title: String, detail: String? = nil) {
        self.glyph = glyph
        self.title = title
        self.detail = detail
    }
}

public struct WidgetDelta: Equatable, Sendable {
    public enum Tone: Sendable, Equatable { case above, inLine, below }
    public var text: String
    public var tone: Tone
}

public struct WidgetNightBody: Equatable, Sendable {
    /// "Last night", or "Last recorded" when the numbers are stale.
    public var duration: WidgetLine
    public var stages: WidgetStages?
    public var quality: WidgetLine?
    /// "11:04 PM – 6:52 AM".
    public var times: String
}

public struct WidgetTonight: Equatable, Sendable {
    /// "10:45 – 11:15 PM" for a window, "11:00 PM" for one bedtime.
    public var bedtime: String
    public var wake: String
}

/// Recovery by day: the ring and score, last night and tonight.
public struct WidgetDayBody: Equatable, Sendable {
    public var score: Int?
    public var delta: WidgetDelta?
    public var ring: [WidgetRingSegment]
    /// Sleep, HRV and resting heart rate, each only if there is a number.
    public var rows: [WidgetLine]
    public var night: WidgetNightBody?
    public var tonight: WidgetTonight
}

/// Tonight by evening: the bedtime, counting down.
public struct WidgetEveningBody: Equatable, Sendable {
    public var bedtime: Date
    public var bedtimeText: NoctisMetricValue
    /// "10:45 – 11:15 PM" when there is a window.
    public var windowText: String?
    /// True once bedtime has passed: "Bedtime was 11:00 PM" and no countdown.
    public var hasPassed: Bool
    public var passedText: String
    public var wake: WidgetLine
    /// "7:00 AM", as the clock writes it (the metric's plain text drops the space before AM or PM).
    public var wakeText: String
    public var need: WidgetLine
    /// The wake alarm, when it is on.
    public var alarm: WidgetLine?
    /// The small recovery ring on medium and large, when there is a score.
    public var score: Int?
    public var ring: [WidgetRingSegment]
}

public enum WidgetBody: Equatable, Sendable {
    case message(WidgetMessage)
    case day(WidgetDayBody)
    case evening(WidgetEveningBody)
}

/// A piece of a Lock Screen line.
public enum WidgetLockPiece: Equatable, Sendable {
    case text(String)
    /// A Health value in words: hidden on a locked iPhone.
    case health(String)
    /// Time to (or since) a moment, counted by the system with no reload.
    case countdown(Date)
}

public struct WidgetLockContent: Equatable, Sendable {
    /// The circular gauge's score; nil draws an empty gauge with a glyph.
    public var gaugeScore: Int?
    public var rectangular: [[WidgetLockPiece]]
    public var inline: [WidgetLockPiece]
}

public struct WidgetPresentation: Equatable, Sendable {
    public var mode: WidgetMode
    public var body: WidgetBody
    public var lock: WidgetLockContent
    /// "Updated 14h ago" under stale numbers.
    public var footer: String?
    public var isPreview: Bool
    /// Where a tap goes: Recovery by day, Tonight in the evening.
    public var link: WidgetLink
    /// One sentence for VoiceOver.
    public var accessibilityLabel: String
}

public enum WidgetPresentationBuilder {
    public static func build(_ entry: WidgetEntryModel, format: WidgetFormat = WidgetFormat()) -> WidgetPresentation {
        let link: WidgetLink = entry.mode == .evening ? .tonight : .recovery
        guard let snapshot = entry.snapshot else {
            return message(entry, WidgetMessage(glyph: "moon.stars", title: WidgetCopy.getStarted), lock: ["Open NOCTIS", "to get started"], inline: WidgetCopy.getStarted, link: .recovery)
        }
        let footer = entry.staleHours.map(WidgetCopy.updated(hours:))
        switch entry.mode {
        case .evening:
            return evening(entry, snapshot: snapshot, format: format, footer: footer)
        case .day:
            return day(entry, snapshot: snapshot, format: format, footer: footer, link: link)
        }
    }

    // MARK: Messages

    /// `lock` is the Lock Screen's rectangular lines; `inline` its one line, shorter than the title because it has about 28 characters.
    private static func message(
        _ entry: WidgetEntryModel, _ message: WidgetMessage, lock: [String], inline: String, link: WidgetLink, footer: String? = nil
    ) -> WidgetPresentation {
        WidgetPresentation(
            mode: entry.mode, body: .message(message),
            lock: WidgetLockContent(gaugeScore: nil, rectangular: lock.map { [.text($0)] }, inline: [.text(inline)]),
            footer: footer, isPreview: entry.isPreview, link: link,
            accessibilityLabel: [message.title, message.detail].compactMap { $0 }.joined(separator: ". ")
        )
    }

    // MARK: Day

    private static func day(_ entry: WidgetEntryModel, snapshot: WidgetSnapshot, format: WidgetFormat, footer: String?, link: WidgetLink) -> WidgetPresentation {
        if entry.scene == .waiting {
            return message(
                entry, WidgetMessage(glyph: "hourglass", title: WidgetCopy.waitingTitle, detail: WidgetCopy.waitingDetail),
                lock: ["Waiting for", "last night's sleep"], inline: "Waiting for sleep data", link: link
            )
        }
        switch snapshot.state {
        case .noPermission, .empty:
            return message(entry, WidgetMessage(glyph: "heart.text.square", title: WidgetCopy.connectHealth), lock: ["Open NOCTIS", "to connect Apple Health"], inline: "Open NOCTIS for Health", link: link)
        case .learning(let nights):
            return message(
                entry, WidgetMessage(glyph: "chart.line.uptrend.xyaxis", title: WidgetCopy.learningTitle, detail: WidgetCopy.nights(nights)),
                lock: [WidgetCopy.learningTitle, WidgetCopy.nights(nights)], inline: "Learning · \(WidgetCopy.nights(nights))", link: link
            )
        case .gap:
            return message(entry, WidgetMessage(glyph: "moon.zzz", title: WidgetCopy.noSleep), lock: ["No sleep recorded", "last night"], inline: "No sleep last night", link: link)
        case .full, .sleepOnly, .stale:
            return numbers(entry, snapshot: snapshot, format: format, footer: footer, link: link)
        }
    }

    private static func numbers(_ entry: WidgetEntryModel, snapshot: WidgetSnapshot, format: WidgetFormat, footer: String?, link: WidgetLink) -> WidgetPresentation {
        let isStale = entry.staleHours != nil
        let recovery = snapshot.recovery
        var delta: WidgetDelta?
        if let value = recovery?.delta {
            let tone: WidgetDelta.Tone = value >= WidgetCopy.trendThreshold ? .above : value <= -WidgetCopy.trendThreshold ? .below : .inLine
            delta = WidgetDelta(text: WidgetCopy.signed(value), tone: tone)
        }

        var rows: [WidgetLine] = []
        if let night = snapshot.lastNight {
            rows.append(WidgetLine(label: "Sleep", value: WidgetFormat.durationMetric(night.asleepMinutes), sensitivity: .health, tint: .sleepDuration))
        }
        if let hrv = snapshot.factors?.hrv {
            rows.append(WidgetLine(label: "HRV", value: WidgetFormat.quantityMetric(hrv, unit: "ms", spokenUnit: "milliseconds"), sensitivity: .health, tint: .hrv))
        }
        if let heart = snapshot.factors?.restingHeartRate {
            rows.append(WidgetLine(label: "Resting HR", value: WidgetFormat.quantityMetric(heart, unit: "bpm", spokenUnit: "beats per minute"), sensitivity: .health, tint: .restingHeartRate))
        }

        var night: WidgetNightBody?
        if let last = snapshot.lastNight {
            let quality = last.quality.map {
                WidgetLine(label: "Sleep quality", value: NoctisMetricValue(parts: [.number("\($0)")], spoken: "\($0)"), sensitivity: .health)
            }
            night = WidgetNightBody(
                duration: WidgetLine(label: isStale ? "Last recorded" : "Last night", value: WidgetFormat.durationMetric(last.asleepMinutes), sensitivity: .health, tint: .sleepDuration),
                stages: last.stages, quality: quality,
                times: "\(format.clock(minutesSinceMidnight: last.bedtimeMinutes)) – \(format.clock(minutesSinceMidnight: last.wakeMinutes))"
            )
        }

        let tonight = WidgetTonight(bedtime: bedtimeText(snapshot.plan, format: format), wake: "Wake \(format.clock(minutesSinceMidnight: snapshot.plan.wakeMinutes))")
        let body = WidgetDayBody(score: recovery?.score, delta: delta, ring: recovery?.ring ?? [], rows: rows, night: night, tonight: tonight)

        // Lock Screen: Recovery 70, Sleep 6h 42m, Bed 11:00 PM; the Health words are hidden while locked.
        // Stale numbers say how old they are on the Lock Screen too, in place of the bedtime (R45).
        let bed = "Bed \(format.clock(minutesSinceMidnight: snapshot.plan.bedtimeMinutes))"
        let tail = entry.staleHours.map { WidgetCopy.updated(hours: $0) } ?? bed
        let inlineTail = entry.staleHours.map { hours in hours < 48 ? "\(hours)h old" : "\(hours / 24)d old" } ?? bed
        var rectangular: [[WidgetLockPiece]] = []
        if let score = recovery?.score { rectangular.append([.health("Recovery \(score)")]) }
        if let last = snapshot.lastNight { rectangular.append([.health("Sleep \(WidgetFormat.compactDuration(last.asleepMinutes))")]) }
        rectangular.append([.text(tail)])
        var inline: [WidgetLockPiece] = []
        if let score = recovery?.score {
            inline = [.health("Recovery \(score)"), .text(" - \(inlineTail)")]
        } else if let last = snapshot.lastNight {
            inline = [.health("Sleep \(WidgetFormat.compactDuration(last.asleepMinutes))"), .text(" - \(inlineTail)")]
        } else {
            inline = [.text(bed)]
        }

        var spoken: [String] = []
        if let score = recovery?.score {
            spoken.append("Recovery \(score)" + (delta.map { ", \($0.text) on your usual" } ?? ""))
        }
        if let last = snapshot.lastNight { spoken.append("\(isStale ? "Last recorded sleep" : "Slept") \(WidgetFormat.spokenDuration(last.asleepMinutes))") }
        spoken.append("Bedtime \(tonight.bedtime)")
        if let footer { spoken.append(footer) }
        if entry.isPreview { spoken.append("Sample") }

        return WidgetPresentation(
            mode: .day, body: .day(body), lock: WidgetLockContent(gaugeScore: recovery?.score, rectangular: rectangular, inline: inline),
            footer: footer, isPreview: entry.isPreview, link: link, accessibilityLabel: spoken.joined(separator: ". ")
        )
    }

    // MARK: Evening

    private static func evening(_ entry: WidgetEntryModel, snapshot: WidgetSnapshot, format: WidgetFormat, footer: String?) -> WidgetPresentation {
        let plan = snapshot.plan
        let bedtimeDate = entry.bedtime ?? entry.date
        let hasPassed = bedtimeDate <= entry.date
        let timeText = format.clock(minutesSinceMidnight: plan.bedtimeMinutes)
        // The ring and score only when they are today's: not while waiting for a new day, and not when stale.
        let showsScore = entry.scene == .ready && entry.staleHours == nil && snapshot.state.showsScore
        let score = showsScore ? snapshot.recovery?.score : nil
        let body = WidgetEveningBody(
            bedtime: bedtimeDate, bedtimeText: format.clockMetric(minutesSinceMidnight: plan.bedtimeMinutes),
            windowText: plan.windowStartMinutes.flatMap { start in plan.windowEndMinutes.map { format.windowText(startMinutes: start, endMinutes: $0) } },
            hasPassed: hasPassed, passedText: "Bedtime was \(timeText)",
            wake: WidgetLine(label: "Wake", value: format.clockMetric(minutesSinceMidnight: plan.wakeMinutes), sensitivity: .plan),
            wakeText: format.clock(minutesSinceMidnight: plan.wakeMinutes),
            need: WidgetLine(label: "Need", value: WidgetFormat.durationMetric(plan.needMinutes), sensitivity: .plan),
            alarm: snapshot.alarm.flatMap { $0.isOn ? WidgetLine(label: "Alarm", value: format.clockMetric(minutesSinceMidnight: $0.minutes), sensitivity: .plan) : nil },
            score: score, ring: score == nil ? [] : (snapshot.recovery?.ring ?? [])
        )

        var rectangular: [[WidgetLockPiece]]
        var inline: [WidgetLockPiece]
        if hasPassed {
            rectangular = [[.text("Bedtime was \(timeText)")], [.text("Wake \(format.clock(minutesSinceMidnight: plan.wakeMinutes))")]]
            inline = [.text("Bedtime was \(timeText)")]
        } else {
            rectangular = [[.text("Bedtime \(timeText)")], [.text("in "), .countdown(bedtimeDate)], [.text("Wake \(format.clock(minutesSinceMidnight: plan.wakeMinutes))")]]
            inline = [.text("Bedtime in "), .countdown(bedtimeDate)]
        }

        var spoken = hasPassed ? ["Bedtime was \(timeText)"] : ["Bedtime \(timeText)"]
        spoken.append("Wake \(format.clock(minutesSinceMidnight: plan.wakeMinutes))")
        if let footer { spoken.append(footer) }
        if entry.isPreview { spoken.append("Sample") }
        return WidgetPresentation(
            mode: .evening, body: .evening(body), lock: WidgetLockContent(gaugeScore: score, rectangular: rectangular, inline: inline),
            footer: footer, isPreview: entry.isPreview, link: .tonight, accessibilityLabel: spoken.joined(separator: ". ")
        )
    }

    /// "10:45 – 11:15 PM" with a window, "11:00 PM" with one bedtime.
    static func bedtimeText(_ plan: WidgetPlan, format: WidgetFormat) -> String {
        if let start = plan.windowStartMinutes, let end = plan.windowEndMinutes { return format.windowText(startMinutes: start, endMinutes: end) }
        return format.clock(minutesSinceMidnight: plan.bedtimeMinutes)
    }
}
