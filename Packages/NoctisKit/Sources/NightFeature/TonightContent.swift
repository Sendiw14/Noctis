import DesignSystem
import Foundation
import HomeFeature
import NightKit
import RecoveryKit
import SleepAnalysisKit
import SleepKit

// What the Tonight screen shows, built from the bedtime engine's numbers by `TonightBuilder`.
// Views lay it out; they never do date math or write a sentence (APP_RULES.md R18, R20, R30).

/// The evening strip: 6 PM to 10 AM, the bedtime window, the wake marker.
public nonisolated struct TonightStrip: Sendable, Equatable {
    public struct Label: Sendable, Equatable {
        public let position: Double
        public let text: String
    }

    /// Where the window starts and ends, 0...1 along the strip. For one bedtime they're both there.
    public let windowStart: Double
    public let windowEnd: Double
    public let wake: Double
    public let labels: [Label]
    public let accessibilityLabel: String
}

/// How a reason's tile is colored: the color of the thing it is about (R26's tokens).
public nonisolated enum TonightTone: Sendable, Equatable {
    case sage
    case lavender
    case orange
    case butter
}

public nonisolated struct TonightReasonRow: Sendable, Equatable, Identifiable {
    public let kind: BedtimeReasonKind
    public let label: String
    public let value: NoctisMetricValue
    /// What this fact did to the time, in words; nil when it did nothing.
    public let detail: String?
    public let systemImage: String
    public let tone: TonightTone

    public var id: BedtimeReasonKind { kind }

    public var accessibilityLabel: String {
        [label, value.spoken, detail].compactMap { $0 }.joined(separator: ". ")
    }
}

public nonisolated struct TonightContent: Sendable, Equatable {
    /// "WEDNESDAY, SEPTEMBER 30".
    public let dateCaption: String
    /// "Bedtime window 10:45 – 11:15 PM", or "Bedtime around 11:00 PM".
    public let summary: String
    public let isWindow: Bool
    /// The bedtime is built on the person's own nights (Premium); false is the free plan's one bedtime from the wake time and the need
    /// (APP_RULES.md R57), which has no window and no "why".
    public let isPersonalized: Bool
    /// "BEDTIME WINDOW" or "BEDTIME".
    public let heroCaption: String
    /// The window, or the one bedtime, as a metric.
    public let hero: NoctisMetricValue
    /// "Wake 7:00 AM · 8h need".
    public let wakeLine: String
    /// "A starting point. We're still learning your pattern." for one bedtime.
    public let note: String?
    public let strip: TonightStrip
    public let reasons: [TonightReasonRow]
    /// "High confidence · built on 14 nights of your own sleep"; nil for one bedtime.
    public let confidence: String?
    /// Tonight is the night the clocks change.
    public let clockChange: String?
    /// "How this is calculated": the paragraphs.
    public let method: [String]
    public let accessibilityLabel: String
}

public nonisolated enum TonightBuilder {
    // MARK: Tonight

    public static func content(
        for recommendation: BedtimeRecommendation, now: Date, timeZone: TimeZone, format: HomeFormat, personalized: Bool = true
    ) -> TonightContent {
        let wakeText = format.clock(minutesSinceMidnight: recommendation.wakeMinutes)
        let needText = HomeFormat.compactDuration(recommendation.needMinutes)
        let wakeLine = "Wake \(wakeText) · \(needText) need"
        let isWindow = recommendation.kind == .window
        let hero: NoctisMetricValue
        let summary: String
        if let window = recommendation.window {
            hero = windowMetric(window, format: format)
            summary = "Bedtime window \(windowText(window, format: format))"
        } else {
            let text = format.clock(minutesSinceMidnight: recommendation.centerMinutes)
            hero = format.clockMetric(text)
            summary = "Bedtime around \(text)"
        }
        let strip = strip(for: recommendation, format: format)
        let confidence = isWindow ? confidenceLine(recommendation) : nil
        let note = isWindow ? nil : (personalized ? "A starting point. We're still learning your pattern." : "Your wake time less the sleep you need.")
        let clockChange = clockChangeNote(recommendation.clockChangeMinutes)
        let caption = isWindow ? "Bedtime window" : "Bedtime"
        let label = [caption + ". " + hero.spoken, wakeLine, note, confidence, clockChange].compactMap { $0 }.joined(separator: ". ")
        return TonightContent(
            dateCaption: format.longDate(now, in: timeZone).uppercased(format.locale), summary: summary, isWindow: isWindow, isPersonalized: personalized,
            heroCaption: caption.uppercased(format.locale), hero: hero, wakeLine: wakeLine, note: note, strip: strip,
            reasons: reasons(for: recommendation, format: format), confidence: confidence, clockChange: clockChange,
            method: method(for: recommendation), accessibilityLabel: label + ". " + strip.accessibilityLabel
        )
    }

    // MARK: Words

    /// "10:45 – 11:15 PM", or "11:45 PM – 12:15 AM" when the window crosses AM and PM.
    public static func windowText(_ window: BedtimeWindow, format: HomeFormat) -> String {
        format.windowText(startMinutes: window.startMinutes, endMinutes: window.endMinutes)
    }

    /// The window as one metric: the period is the unit (Home draws the same one).
    public static func windowMetric(_ window: BedtimeWindow, format: HomeFormat) -> NoctisMetricValue {
        format.windowMetric(startMinutes: window.startMinutes, endMinutes: window.endMinutes)
    }

    static func confidenceLine(_ recommendation: BedtimeRecommendation) -> String {
        let word = recommendation.confidence.rawValue.capitalized
        switch recommendation.confidence {
        case .high, .moderate: return "\(word) confidence · built on \(recommendation.nights) nights of your own sleep"
        case .low: return "\(word) confidence · it firms up as more nights arrive"
        }
    }

    static func clockChangeNote(_ change: Int) -> String? {
        switch change {
        case 1...: "The clocks go forward tonight, so this is earlier on the clock to leave the same time asleep."
        case ..<0: "The clocks go back tonight, so this is later on the clock to leave the same time asleep."
        default: nil
        }
    }

    // MARK: The strip

    /// The strip runs 6 PM to 10 AM: 960 minutes.
    static let stripStartMinutes = 18 * 60
    static let stripLength = 16 * 60

    static func fraction(_ minutesSinceMidnight: Int) -> Double {
        let along = BedtimeClock.forward(from: stripStartMinutes, to: minutesSinceMidnight)
        return min(Double(along) / Double(stripLength), 1)
    }

    static func strip(for recommendation: BedtimeRecommendation, format: HomeFormat) -> TonightStrip {
        let start = recommendation.window?.startMinutes ?? recommendation.centerMinutes
        let end = recommendation.window?.endMinutes ?? recommendation.centerMinutes
        let labels = [0, 4, 8, 12, 16].map { step in
            TonightStrip.Label(position: Double(step) / 16, text: format.hour(minutesSinceMidnight: stripStartMinutes + step * 60))
        }
        let what =
            recommendation.kind == .window
            ? "Bedtime window \(windowText(recommendation.window ?? BedtimeWindow(startMinutes: start, endMinutes: end), format: format))"
            : "Bedtime \(format.clock(minutesSinceMidnight: start))"
        return TonightStrip(
            windowStart: fraction(start), windowEnd: max(fraction(end), fraction(start)), wake: fraction(recommendation.wakeMinutes), labels: labels,
            accessibilityLabel: "\(what), wake \(format.clock(minutesSinceMidnight: recommendation.wakeMinutes)), on a strip from 6 PM to 10 AM"
        )
    }

    // MARK: Why this time

    static func reasons(for recommendation: BedtimeRecommendation, format: HomeFormat) -> [TonightReasonRow] {
        recommendation.reasons.map { reason in
            switch reason.kind {
            case .sleepNeed:
                TonightReasonRow(
                    kind: .sleepNeed, label: "Sleep need", value: HomeFormat.durationMetric(Int(reason.value)), detail: nil,
                    systemImage: "moon.zzz", tone: .sage
                )
            case .wakeTime:
                TonightReasonRow(
                    kind: .wakeTime, label: "Wake time", value: format.clockMetric(format.clock(minutesSinceMidnight: Int(reason.value))), detail: nil,
                    systemImage: "sun.max", tone: .butter
                )
            case .usualBedtime:
                TonightReasonRow(
                    kind: .usualBedtime, label: "Usual bedtime", value: format.clockMetric(format.clock(minutesSinceMidnight: Int(reason.value))),
                    detail: recommendation.isGradual ? "Moving toward your target gradually." : nil, systemImage: "bed.double", tone: .orange
                )
            case .balance:
                balanceRow(reason, recommendation: recommendation)
            case .consistency:
                TonightReasonRow(
                    kind: .consistency, label: "Bedtime consistency", value: HomeFormat.durationMetric(max(Int(reason.value.rounded()), 0)),
                    detail: "How much your bedtime varies.", systemImage: "repeat", tone: .butter
                )
            }
        }
    }

    /// "1h 10m behind", "40m ahead", or "Even with your need" under 5 minutes (as the Sleep tab says it).
    static func balanceRow(_ reason: BedtimeReason, recommendation: BedtimeRecommendation) -> TonightReasonRow {
        let size = Int(abs(reason.value).rounded())
        let moved = reason.shiftMinutes < 0 ? "Moved \(abs(reason.shiftMinutes)) min earlier to catch up." : nil
        guard size >= 5 else {
            return TonightReasonRow(
                kind: .balance, label: "Last \(SleepBalanceEngine.windowNights) nights",
                value: NoctisMetricValue(parts: [.unit("Even with your need")], spoken: "Even with your need"),
                detail: nil, systemImage: "calendar", tone: .lavender
            )
        }
        let word = reason.value < 0 ? "behind" : "ahead"
        let duration = HomeFormat.durationMetric(size)
        let value = NoctisMetricValue(parts: duration.parts + [.space, .unit(word)], spoken: "\(duration.spoken) \(word)")
        return TonightReasonRow(
            kind: .balance, label: "Last \(SleepBalanceEngine.windowNights) nights", value: value, detail: moved, systemImage: "calendar", tone: .lavender)
    }

    // MARK: How this is calculated

    static func method(for recommendation: BedtimeRecommendation) -> [String] {
        let p = BedtimeModel.current.parameters
        let compact = { (minutes: Int) in HomeFormat.compactDuration(minutes) }
        var paragraphs = [
            "Your bedtime is your wake time minus your sleep need. This is model \(recommendation.model).",
            "When the last \(SleepBalanceEngine.windowNights) nights add up to \(compact(Int(p.catchUpBehindMinutes))) or more under your need, it moves earlier by a quarter of the gap, never by more than \(compact(p.catchUpLimitMinutes)). Ahead of your need or in line with it, nothing changes.",
            "Once \(p.minimumNights) nights are recorded, it stays within \(compact(p.gradualStepMinutes)) of your usual bedtime, so it moves toward your target gradually. Before that it is one starting bedtime.",
            "The window is \(compact(p.windowHalfWidthMinutes)) either side of that time, to the nearest \(compact(p.roundingMinutes)). It describes your own pattern; it isn't a medical measurement.",
        ]
        if recommendation.clockChangeMinutes != 0 {
            paragraphs.append("On the night the clocks change, an hour of the clock isn't an hour of sleep, so the time is corrected by it.")
        }
        return paragraphs
    }
}

extension String {
    nonisolated func uppercased(_ locale: Locale) -> String {
        uppercased(with: locale)
    }
}
