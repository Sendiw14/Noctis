import DesignSystem
import Foundation
import HealthProviding
import InsightsKit
import NoctisCore
import RecoveryKit
import SleepKit

// Everything Home shows, as plain values: every string and number is
// decided here, from `HomeSnapshot`, so the views only lay it out
// (APP_RULES.md R18, R20). Built by `HomeScreenBuilder`.

/// Home's two modes, decided by `HomeScreenBuilder.mode` and never in a view.
public nonisolated enum HomeMode: String, Sendable, Equatable, CaseIterable {
    /// From 4 AM (including wake-up) until 3h before bedtime: the hero is
    /// Recovery.
    case day
    /// From 3h before bedtime until 4 AM: the hero is Tonight.
    case evening
}

/// Tonight's plan as real dates, for the evening countdown, the header
/// summary and the night strip's "now" marker. The view passes the
/// current minute in (a TimelineView); the date math stays here.
public nonisolated struct TonightTimes: Sendable, Equatable {
    public let bedtime: Date
    public let wake: Date
    /// "11:00 PM".
    public let bedtimeText: String
    /// The night strip runs 6 PM to 10 AM.
    public let windowStart: Date
    public let windowEnd: Date

    /// "in 2h 14m", rounded up to the minute; nil once bedtime has passed.
    public func countdown(at now: Date) -> String? {
        let seconds = bedtime.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return "in " + HomeFormat.compactDuration(Int((seconds / 60).rounded(.up)))
    }

    /// Minutes left, for `numericText` (nil after bedtime).
    public func minutesLeft(at now: Date) -> Int? {
        let seconds = bedtime.timeIntervalSince(now)
        return seconds > 0 ? Int((seconds / 60).rounded(.up)) : nil
    }

    /// The time left as a metric (after "in"); nil after bedtime.
    public func countdownMetric(at now: Date) -> NoctisMetricValue? {
        minutesLeft(at: now).map { HomeFormat.durationMetric($0) }
    }

    /// "Bedtime was 11:00 PM" — the hero's line once bedtime has passed.
    public var passedText: String { "Bedtime was \(bedtimeText)" }

    /// "Bedtime in 2h 14m." or, after bedtime, "Bedtime was 11:00 PM."
    public func summary(at now: Date) -> String {
        countdown(at: now).map { "Bedtime \($0)." } ?? passedText + "."
    }

    /// The collapsed bar and the tab bar accessory: "Bedtime 11:00 PM ·
    /// in 2h 14m", or after bedtime "Bedtime was 11:00 PM".
    public func status(at now: Date) -> String {
        countdown(at: now).map { "Bedtime \(bedtimeText) · \($0)" } ?? passedText
    }

    public var bedtimeFraction: Double { fraction(of: bedtime) ?? 0 }
    public var wakeFraction: Double { fraction(of: wake) ?? 1 }

    /// Where `now` falls on the strip, or nil outside 6 PM–10 AM.
    public func nowFraction(at now: Date) -> Double? { fraction(of: now) }

    private func fraction(of date: Date) -> Double? {
        let span = windowEnd.timeIntervalSince(windowStart)
        let value = date.timeIntervalSince(windowStart) / span
        return (0...1).contains(value) ? value : nil
    }
}

public nonisolated enum HeaderSummary: Sendable, Equatable {
    case text(String)
    /// Evening: counts down to bedtime, minute by minute.
    case bedtime(TonightTimes)

    public func text(at now: Date) -> String {
        switch self {
        case .text(let text): text
        case .bedtime(let times): times.summary(at: now)
        }
    }
}

public nonisolated struct HomeHeader: Sendable, Equatable {
    /// "Good morning." split so one word can be emphasized.
    public let greetingLead: String
    public let greetingEmphasis: String
    public let greetingTrail: String
    /// Orange in day mode, lavender in evening mode.
    public let mode: HomeMode
    /// "Thursday, September 24".
    public let date: String
    /// "THURSDAY, SEPTEMBER 24".
    public let dateCaption: String
    /// One sentence: "You slept 6h 42m. Recovery is 70."
    public let summary: HeaderSummary
    /// "Updated 2h ago" once the newest data is over an hour old.
    public let updated: String?

    public var greeting: String { greetingLead + greetingEmphasis + greetingTrail }
}

/// One ring segment: the factor's arc from the render model (its angles,
/// fill and the tick at your usual).
public nonisolated struct RingSegmentContent: Sendable, Equatable {
    public let arc: RingArc

    public var kind: RecoveryFactorKind { arc.kind }
    /// Renormalized weight (0...1): the segment's share of the ring.
    public var weight: Double { arc.weight }
    /// Factor score / 100.
    public var fraction: Double { arc.fraction }
    /// Your usual score for this factor / 100; nil without a baseline.
    public var usual: Double? { arc.usual }
}

public nonisolated enum DeltaTone: Sendable, Equatable {
    case above
    case inLine
    case below
}

public nonisolated struct DeltaChip: Sendable, Equatable {
    /// "+6", "−18", "±0" — the sign is always shown.
    public let text: String
    public let tone: DeltaTone
}

public nonisolated struct FactorCell: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    public let name: String
    public let score: Int
    /// Your usual score for this factor; nil without a baseline.
    public let usual: Int?

    /// "Sleep 67, usual 74", or "Sleep 67" without a baseline.
    public var spoken: String {
        usual.map { "\(name) \(score), usual \($0)" } ?? "\(name) \(score)"
    }
}

public nonisolated struct ScoredRecoveryContent: Sendable, Equatable {
    public let score: Int
    public let segments: [RingSegmentContent]
    public let chip: DeltaChip?
    /// Beside the chip: "vs your usual", "In line with your usual" when
    /// every factor is within its normal range, or (no chip) why not.
    public let comparisonPhrase: String
    /// Under the chip: "Mostly: sleep was 1h 10m shorter than usual"; nil
    /// when every factor is within its normal range.
    public let why: String?
    /// The engine's sentence, for detail: "Below your recent baseline."
    public let sentence: String
    /// The full confidence line, for detail.
    public let confidence: String
    /// Home shows the confidence line only when it isn't high.
    public let confidenceCaption: String?
    /// V3's heart cap, in plain words, when it applied.
    public let heartCapNote: String?
    public let factors: [FactorCell]
    /// The ring draws a tick at each factor's usual, with this caption
    /// under the capsules ("Tick = your usual"); nil when no factor has a
    /// baseline yet.
    public let usualCaption: String?
    public let accessibilityLabel: String
}

public nonisolated enum RecoveryCardContent: Sendable, Equatable {
    /// Health access never requested (or no Health on this device):
    /// "Your first night starts here."
    case connect(title: String, message: String, showsButton: Bool)
    /// Access already requested, but no sleep data: "No sleep data yet",
    /// with "Open Health".
    case noSleepData(title: String, message: String)
    /// "3 of 5 nights", shown with one dot per night needed.
    case learning(nights: Int, required: Int, text: String)
    case scored(ScoredRecoveryContent)
    /// Data is current, but no sleep was recorded last night.
    case noSleep(title: String, detail: String?)
    /// Apple Health hasn't synced for over a day.
    case stale(title: String, detail: String)
    case failed(message: String)
}

/// The insight, worded here from `InsightEngine`'s evidence, with a small
/// chart of that evidence.
public nonisolated struct InsightCardContent: Sendable, Equatable {
    public let title: String
    public let message: String
    public let chart: InsightChartContent
    /// The title, the message and the evidence in words.
    public let accessibilityLabel: String
}

/// The evidence behind an insight, as a small flat chart.
public nonisolated enum InsightChartContent: Sendable, Equatable {
    /// Two bars: last night against usual. Widths are shares of the longer.
    case comparison(lastNight: InsightBar, usual: InsightBar)
    /// A short time axis with two ticks, usual and last night.
    case timeline(usual: InsightTick, lastNight: InsightTick)
    /// One dot per recent night: filled within 30 minutes of the usual
    /// bedtime, open outside it, faint with no sleep recorded, with a
    /// caption under them ("Last 7 nights").
    case nights([InsightNightDot], caption: String)
}

public nonisolated struct InsightBar: Sendable, Equatable {
    /// "Last night", "Usual".
    public let label: String
    public let value: NoctisMetricValue
    /// 0...1.
    public let fraction: Double
}

public nonisolated struct InsightTick: Sendable, Equatable {
    /// "Usual", "Last night".
    public let label: String
    /// "11:08 PM".
    public let time: String
    /// 0...1 along the axis.
    public let position: Double
}

public nonisolated struct InsightNightDot: Sendable, Equatable {
    /// Weekday initial of the morning the night ended.
    public let label: String
    /// True within 30 minutes; false outside; nil with no sleep recorded.
    public let within: Bool?
}

public nonisolated struct TonightCardContent: Sendable, Equatable {
    /// "Bedtime around", then the time.
    public let bedtimeLead: String
    public let bedtime: NoctisMetricValue
    /// "Wake 7:00 AM · 8h need".
    public let detail: String
    /// "Bedtime around 11:00 PM".
    public var bedtimeText: String { "\(bedtimeLead) \(bedtime.spoken)" }
}

/// Evening mode's hero: tonight's bedtime, a countdown and the night strip.
public nonisolated struct EveningHeroContent: Sendable, Equatable {
    /// 11:00 PM, the period as a unit.
    public let time: NoctisMetricValue
    public let times: TonightTimes
    /// "Wake 7:00 AM · 8h need".
    public let detail: String
    /// Strip labels and where they sit: 6 PM, 12 AM, 6 AM, 10 AM.
    public let stripLabels: [StripLabel]
    /// "Tonight's sleep window, 11:00 PM to 7:00 AM."
    public let stripAccessibilityLabel: String

    public nonisolated struct StripLabel: Sendable, Equatable {
        public let text: String
        public let position: Double
    }
}

public nonisolated struct WeekBar: Sendable, Equatable {
    /// Weekday initial of the morning the night ended.
    public let label: String
    /// Bar height as a share of the chart (0...1); nil with no data.
    public let fraction: Double?
    /// Deep, Core and REM, bottom to top, as shares of the bar; nil for a
    /// night without stages (a solid sage bar).
    public let stages: WeekBarStages?
    public let isLastNight: Bool
    public let accessibilityLabel: String
    /// The pill when the bar is selected: "Tue · 7h 12m · Deep 1h 20m ·
    /// REM 1h 50m", "Tue · 7h 12m" without stages, or "Tue · No data".
    public let detail: String
}

public nonisolated struct WeekCardContent: Sendable, Equatable {
    public let bars: [WeekBar]
    /// Height of the dashed need line, as a share of the chart.
    public let needFraction: Double
    /// "8h need".
    public let needLabel: String
    /// The average (after "Avg"); nil when no night has data.
    public let average: NoctisMetricValue?
    public let accessibilityLabel: String
}

public nonisolated struct FactorDetailRow: Sendable, Equatable {
    public let kind: RecoveryFactorKind
    /// "HRV".
    public let name: String
    /// 48 ms.
    public let value: NoctisMetricValue
    /// A word after the value: "off" for consistency.
    public let valueSuffix: String?
    /// "baseline 44 ms".
    public let baseline: String
    public let score: Int
    public let sentence: String
    /// The last 14 nights against the normal range; nil under 5 nights.
    public let sparkline: SparklineContent?
    public let accessibilityLabel: String
}

/// A factor's 14 nights for Recovery detail: the normal range as a band,
/// a line through the nights, and today as a dot.
public nonisolated struct SparklineContent: Sendable, Equatable {
    /// 0...1 up the chart, oldest first; nil with no value that night.
    public let nights: [Double?]
    public let today: Double
    /// The band, 0...1 up the chart.
    public let band: ClosedRange<Double>
    /// "HRV has been within your normal range on 11 of 14 nights."
    public let accessibilityLabel: String
}

public nonisolated struct RecoveryDetailContent: Sendable, Equatable {
    public let recovery: ScoredRecoveryContent
    public let rows: [FactorDetailRow]
    /// "How this is calculated", paragraph by paragraph.
    public let calculation: [String]
    /// "Model recovery-v1".
    public let modelVersion: String
}

/// "Share today": the 1080×1350 card. HRV and heart rate appear only
/// when the person turns on "Include details" in the share preview.
public nonisolated struct ShareCardContent: Sendable, Equatable {
    /// Nil when there's no score today (the card shows the night only).
    public let recovery: ShareRecovery?
    /// Last night's time asleep (after "Last night").
    public let lastNight: NoctisMetricValue?
    public let chart: NightChartContent?
    /// "Thursday, September 24".
    public let date: String
    /// "HRV 48 ms · Resting HR 54 bpm"; nil when neither was recorded.
    public let details: String?
    /// The share sheet's title: "NOCTIS · Thursday, September 24".
    public let title: String
    /// "noctis-2026-09-24".
    public let fileName: String

    public nonisolated struct ShareRecovery: Sendable, Equatable {
        public let score: Int
        public let segments: [RingSegmentContent]
    }

    /// The night chart as the card shows it: the heart-rate strip (and
    /// its "min … bpm") only with "Include details".
    public func chart(includeDetails: Bool) -> NightChartContent? {
        includeDetails ? chart : chart?.removingHeart()
    }
}

public nonisolated struct HomeScreen: Sendable, Equatable {
    public let header: HomeHeader
    public let mode: HomeMode
    /// When the mode flips next (3h before bedtime, or 4 AM).
    public let nextModeChange: Date
    public let recovery: RecoveryCardContent
    public let lastNight: LastNightCardContent?
    public let insight: InsightCardContent?
    /// Day mode's Tonight block.
    public let tonight: TonightCardContent
    /// Evening mode's Tonight hero.
    public let evening: EveningHeroContent
    public let week: WeekCardContent?
    public let detail: RecoveryDetailContent?
    /// Nil when there's neither a score nor a night to share.
    public let share: ShareCardContent?
}

// MARK: - Builder

public nonisolated enum HomeScreenBuilder {
    /// Ring and factor-row order.
    public static let factorOrder = RingRenderBuilder.factorOrder
    /// "Updated … ago" appears once the newest data is older than this.
    public static let updatedCaptionAfter: TimeInterval = 3600
    /// Headroom above the tallest bar or the need line in This week.
    public static let weekHeadroom = WeekRenderBuilder.headroom

    public static func build(_ snapshot: HomeSnapshot, now: Date, calendar: Calendar, locale: Locale, modeOverride: HomeMode? = nil) -> HomeScreen {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let recovery = recoveryCard(snapshot, format: format)
        let mode = modeOverride ?? Self.mode(now: now, plan: snapshot.tonight, calendar: calendar)
        let times = tonightTimes(now: now, plan: snapshot.tonight, format: format)
        let summary: HeaderSummary = mode == .evening ? .bedtime(times) : .text(daySummary(snapshot, recovery: recovery))
        let showsDataCards: Bool = switch recovery {
        case .connect, .noSleepData, .failed: false
        case .learning, .scored, .noSleep, .stale: true
        }
        var detail: RecoveryDetailContent?
        if case .scored(let content) = recovery, case .scored(let result)? = snapshot.recovery {
            detail = recoveryDetail(result, content: content, needMinutes: snapshot.tonight.needMinutes, render: snapshot.render, format: format)
        }
        return HomeScreen(
            header: header(now: now, newestSample: snapshot.newestSample, mode: mode, summary: summary, format: format),
            mode: mode,
            nextModeChange: nextModeChange(after: now, plan: snapshot.tonight, calendar: calendar),
            recovery: recovery,
            lastNight: showsDataCards ? snapshot.lastNight.map { lastNightCard($0, heart: snapshot.lastNightHeart, quality: snapshot.lastNightSleepQuality, render: snapshot.render.night, format: format) } : nil,
            insight: showsDataCards ? snapshot.topInsight.map { insightCard($0, format: format) } : nil,
            tonight: tonightCard(snapshot.tonight, format: format),
            evening: eveningHero(times, plan: snapshot.tonight, format: format),
            week: showsDataCards ? weekCard(snapshot, format: format) : nil,
            detail: detail,
            share: showsDataCards ? shareCard(snapshot, recovery: recovery, now: now, format: format) : nil
        )
    }

    // MARK: Modes

    /// Evening starts this long before bedtime…
    public static let eveningLeadMinutes = 180
    /// …and ends at 4 AM.
    public static let eveningEndMinutes = 4 * 60

    /// Evening from 3h before bedtime until 4 AM; day otherwise (so the
    /// early hours from 4 AM to waking up read as day too).
    public static func mode(now: Date, plan: TonightPlan, calendar: Calendar) -> HomeMode {
        let clock = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        let start = eveningStartMinutes(plan)
        let end = eveningEndMinutes
        let inEvening = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
        return inEvening ? .evening : .day
    }

    static func eveningStartMinutes(_ plan: TonightPlan) -> Int {
        ((plan.bedtimeMinutes - eveningLeadMinutes) % 1440 + 1440) % 1440
    }

    /// The next moment the mode flips: 3h before bedtime or 4 AM,
    /// whichever comes first after `now`.
    public static func nextModeChange(after now: Date, plan: TonightPlan, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let candidates = [eveningStartMinutes(plan), eveningEndMinutes].flatMap { boundary in
            (0...1).compactMap { offset -> Date? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
                return calendar.date(bySettingHour: boundary / 60, minute: boundary % 60, second: 0, of: day)
            }
        }
        return candidates.filter { $0 > now }.min() ?? now.addingTimeInterval(24 * 3600)
    }

    /// Tonight's bedtime and wake as dates. "Tonight" belongs to the day
    /// that started at 4 AM, so after midnight it's still the same night;
    /// a bedtime before noon is the next calendar day.
    static func tonightTimes(now: Date, plan: TonightPlan, format: HomeFormat) -> TonightTimes {
        let calendar = format.calendar
        let day = calendar.startOfDay(for: now.addingTimeInterval(-Double(eveningEndMinutes) * 60))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let bedDay = plan.bedtimeMinutes >= 12 * 60 ? day : nextDay
        let bedtime = calendar.date(bySettingHour: plan.bedtimeMinutes / 60, minute: plan.bedtimeMinutes % 60, second: 0, of: bedDay) ?? now
        return TonightTimes(
            bedtime: bedtime,
            wake: bedtime.addingTimeInterval(Double(plan.needMinutes) * 60),
            bedtimeText: format.clock(minutesSinceMidnight: plan.bedtimeMinutes),
            windowStart: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day,
            windowEnd: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: nextDay) ?? nextDay
        )
    }

    static func eveningHero(_ times: TonightTimes, plan: TonightPlan, format: HomeFormat) -> EveningHeroContent {
        let labels: [(Int, Double)] = [(18 * 60, 0), (0, 6.0 / 16), (6 * 60, 12.0 / 16), (10 * 60, 1)]
        return EveningHeroContent(
            time: format.clockMetric(times.bedtimeText),
            times: times,
            detail: tonightCard(plan, format: format).detail,
            stripLabels: labels.map { EveningHeroContent.StripLabel(text: format.hour(minutesSinceMidnight: $0.0), position: $0.1) },
            stripAccessibilityLabel: "Tonight's sleep window, \(times.bedtimeText) to \(format.clock(minutesSinceMidnight: plan.wakeMinutes))."
        )
    }

    // MARK: Header

    /// The header before any data (loading): greeting and mode from the
    /// profile's plan.
    public static func loadingHeader(now: Date, plan: TonightPlan, calendar: Calendar, locale: Locale, modeOverride: HomeMode? = nil) -> HomeHeader {
        let format = HomeFormat(calendar: calendar, locale: locale)
        let mode = modeOverride ?? Self.mode(now: now, plan: plan, calendar: calendar)
        let summary: HeaderSummary = mode == .evening
            ? .bedtime(tonightTimes(now: now, plan: plan, format: format))
            : .text("Reading your sleep data.")
        return header(now: now, newestSample: nil, mode: mode, summary: summary, format: format)
    }

    public static func header(now: Date, newestSample: Date?, calendar: Calendar, locale: Locale) -> HomeHeader {
        header(now: now, newestSample: newestSample, mode: .day, summary: .text(""), format: HomeFormat(calendar: calendar, locale: locale))
    }

    /// Evening mode says "Good evening." (in lavender) until midnight and
    /// "Good night." from midnight to 4 AM; day mode follows the clock.
    static func header(now: Date, newestSample: Date?, mode: HomeMode, summary: HeaderSummary, format: HomeFormat) -> HomeHeader {
        let hour = format.calendar.component(.hour, from: now)
        let partOfDay = switch (mode, hour) {
        case (.evening, 0..<eveningEndMinutes / 60): "night"
        case (.evening, _): "evening"
        case (.day, 4..<12): "morning"
        case (.day, 12..<18): "afternoon"
        case (.day, _): "evening"
        }
        let date = format.longDate(now)
        return HomeHeader(
            greetingLead: "Good ",
            greetingEmphasis: partOfDay,
            greetingTrail: ".",
            mode: mode,
            date: date,
            dateCaption: date.uppercased(with: format.locale),
            summary: summary,
            updated: newestSample.flatMap { updatedCaption(age: now.timeIntervalSince($0)) }
        )
    }

    /// Day mode's one sentence: what happened, or which state we're in.
    static func daySummary(_ snapshot: HomeSnapshot, recovery: RecoveryCardContent) -> String {
        switch recovery {
        case .scored(let content):
            guard let lastNight = snapshot.lastNight else { return "Recovery is \(content.score)." }
            return "You slept \(HomeFormat.compactDuration(Int((lastNight.totals.asleep / 60).rounded()))). Recovery is \(content.score)."
        case .learning: return "We're still learning your pattern."
        case .noSleep: return "No sleep was recorded last night."
        case .stale: return "Apple Health hasn't synced recently."
        case .connect(_, _, let showsButton):
            return showsButton ? "Connect Apple Health to see your nights." : "Apple Health isn't available on this device."
        case .noSleepData: return "No sleep data yet."
        case .failed: return "We couldn't read your sleep data."
        }
    }

    /// "Updated 2h ago" past an hour, "Updated 3 days ago" from two days.
    static func updatedCaption(age: TimeInterval) -> String? {
        guard age > updatedCaptionAfter else { return nil }
        let hours = Int(age / 3600)
        return hours < 48 ? "Updated \(hours)h ago" : "Updated \(hours / 24) days ago"
    }

    // MARK: Recovery

    static func recoveryCard(_ snapshot: HomeSnapshot, format: HomeFormat) -> RecoveryCardContent {
        let title = "Your first night starts here."
        switch snapshot.dataState {
        case .healthDataUnavailable:
            return .connect(title: title, message: "Apple Health isn't available on this device.", showsButton: false)
        case .permissionRequired:
            // HealthKit's request status is `.shouldRequest`: never asked.
            return .connect(title: title, message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true)
        case .empty, .learning(nightsSoFar: 0):
            // Already asked (`.unnecessary`), yet no sleep: HealthKit never
            // says whether reading was allowed, so point to the source.
            return noSleepData
        case .failed:
            return .failed(message: "We couldn't read your latest sleep data.")
        case .stale(let newest):
            // Sync is behind; it doesn't mean the person didn't sleep.
            return .stale(
                title: "Apple Health hasn't updated since \(format.dayAndTime(newest)).",
                detail: "Open Health or pull to refresh."
            )
        case .learning, .noSleepLastNight, .ready:
            break
        }
        switch snapshot.recovery {
        case .learning(let nights)?:
            let required = RecoveryModelV2.learningNights
            return .learning(nights: nights, required: required, text: "\(nights) of \(required) nights")
        case .noSleepLastNight?:
            let detail = snapshot.latestSleep.map { "Last recorded night ended \(format.shortDate($0.wakeTime, in: $0.timeZone))." }
            return .noSleep(title: "No sleep recorded last night.", detail: detail)
        case .scored(let result)?:
            return .scored(scoredContent(result, ring: snapshot.render.ring))
        case nil:
            return .connect(title: title, message: "Connect Apple Health so NOCTIS can read your nights.", showsButton: true)
        }
    }

    static func scoredContent(_ result: RecoveryResult, ring: [RingArc]? = nil) -> ScoredRecoveryContent {
        let factors = factorOrder.compactMap { result.factor($0) }
        let chip = result.comparison.delta.map { delta in
            DeltaChip(text: signed(delta), tone: tone(result.comparison.trend))
        }
        let line = confidenceLine(result)
        let why = whyLine(result.topContributor)
        let phrase = switch (chip, why) {
        case (nil, _): "Not enough nights yet to compare."
        case (_, nil): "In line with your usual"
        default: "vs your usual"
        }
        return ScoredRecoveryContent(
            score: result.score,
            segments: (ring ?? RingRenderBuilder.build(result)).map(RingSegmentContent.init(arc:)),
            chip: chip,
            comparisonPhrase: phrase,
            why: why,
            sentence: result.comparison.sentence,
            confidence: line,
            confidenceCaption: result.confidence == .high ? nil : line,
            heartCapNote: result.heartCapApplied ? "Your heart rate and HRV are both well outside your normal range." : nil,
            factors: factors.map { FactorCell(kind: $0.kind, name: shortName($0.kind), score: $0.score, usual: $0.usual.map { Int($0.rounded()) }) },
            usualCaption: factors.contains { $0.usual != nil } ? "Tick = your usual" : nil,
            accessibilityLabel: accessibilitySummary(result, factors: factors)
        )
    }

    /// "Mostly: sleep was 1h 10m shorter than usual", "Mostly: HRV above
    /// your normal range", "Mostly: bedtime 45 min later than usual"; with
    /// `spoken`, durations in words.
    static func whyLine(_ contributor: RecoveryContributor?, spoken: Bool = false) -> String? {
        guard let contributor else { return nil }
        let above = contributor.direction == .above
        let minutes = Int(abs(contributor.difference).rounded())
        let amount = spoken ? HomeFormat.spokenDuration(minutes) : HomeFormat.compactDuration(minutes, minutesWord: true)
        let reason = switch contributor.measure {
        case .sleepDuration: "sleep was \(amount) \(above ? "longer" : "shorter") than usual"
        case .hrv: "HRV \(above ? "above" : "below") your normal range"
        case .restingHeartRate: "resting heart rate \(above ? "above" : "below") your normal range"
        case .bedtime: "bedtime \(amount) \(above ? "later" : "earlier") than usual"
        case .wakeTime: "wake-up \(amount) \(above ? "later" : "earlier") than usual"
        }
        return (spoken ? "Mostly, " : "Mostly: ") + reason
    }

    static let noSleepData = RecoveryCardContent.noSleepData(
        title: "No sleep data yet",
        message: "NOCTIS reads sleep from Apple Health. Track sleep with Apple Watch or set up Sleep in the Health app."
    )

    static func tone(_ trend: RecoveryTrend) -> DeltaTone {
        switch trend {
        case .above: .above
        case .below: .below
        case .inLine, .unknown: .inLine
        }
    }

    /// "+6", "−4" (a real minus sign), "±0".
    static func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\u{2212}\(-value)" }
        return "±0"
    }

    /// "Moderate confidence · sleep, heart rate, consistency", or for sleep
    /// alone "Low confidence · sleep only. HRV and heart rate aren't
    /// available from your sources."
    static func confidenceLine(_ result: RecoveryResult) -> String {
        let tier = switch result.confidence {
        case .high: "High confidence"
        case .moderate: "Moderate confidence"
        case .low: "Low confidence"
        }
        let used = factorOrder.filter { result.factorsUsed.contains($0) }
        let heartFactors: [RecoveryFactorKind] = [.hrv, .restingHeartRate]
        guard used.contains(where: heartFactors.contains) else {
            let reasons = gapSentences(heartFactors.compactMap { kind in result.missingFactors[kind].map { (kind, $0) } })
            return ([tier + " · sleep only."] + reasons).joined(separator: " ")
        }
        return tier + " · " + used.map(listName).joined(separator: ", ")
    }

    /// One sentence per kind of gap, naming the factors it covers.
    static func gapSentences(_ gaps: [(RecoveryFactorKind, RecoveryFactorGap)]) -> [String] {
        let order: [RecoveryFactorGap] = [.unavailable, .notRecorded, .buildingBaseline]
        return order.compactMap { gap in
            let names = gaps.filter { $0.1 == gap }.map { listName($0.0) }
            guard !names.isEmpty else { return nil }
            let plural = names.count > 1
            let subject = names.joined(separator: " and ")
            let sentence = switch gap {
            case .unavailable: "\(subject) \(plural ? "aren't" : "isn't") available from your sources."
            case .notRecorded: "\(subject) \(plural ? "weren't" : "wasn't") recorded last night."
            case .buildingBaseline: "\(subject) \(plural ? "baselines are" : "baseline is") still forming."
            }
            return sentence.prefix(1).uppercased() + sentence.dropFirst()
        }
    }

    /// "Recovery 82, 6 above your baseline, moderate confidence. Sleep 91,
    /// HRV 78, resting heart rate 85, consistency 74."
    static func accessibilitySummary(_ result: RecoveryResult, factors: [RecoveryFactor]) -> String {
        var lead = ["Recovery \(result.score)"]
        if let delta = result.comparison.delta {
            lead.append(delta == 0 ? "same as your usual" : "\(abs(delta)) \(delta > 0 ? "above" : "below") your usual")
        }
        lead.append("\(result.confidence.rawValue) confidence")
        let parts = factors.enumerated().map { index, factor in
            let name = spokenName(factor.kind)
            let usual = factor.usual.map { ", usual \(Int($0.rounded()))" } ?? ""
            return "\(index == 0 ? name.prefix(1).uppercased() + name.dropFirst() : name) \(factor.score)\(usual)"
        }
        let why = whyLine(result.topContributor, spoken: true).map { " \($0)." } ?? ""
        return lead.joined(separator: ", ") + "." + why + (parts.isEmpty ? "" : " " + parts.joined(separator: ", ") + ".")
    }

    static func shortName(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .sleepDuration: "Sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting HR"
        case .sleepConsistency: "Consistency"
        }
    }

    static func listName(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .sleepDuration: "sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "heart rate"
        case .sleepConsistency: "consistency"
        }
    }

    static func spokenName(_ kind: RecoveryFactorKind) -> String {
        switch kind {
        case .sleepDuration: "sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "resting heart rate"
        case .sleepConsistency: "consistency"
        }
    }

    // MARK: Recovery detail

    static func recoveryDetail(_ result: RecoveryResult, content: ScoredRecoveryContent, needMinutes: Int, render: HomeRenderModel? = nil, format: HomeFormat) -> RecoveryDetailContent {
        let rows = factorOrder.compactMap { result.factor($0) }.map { detailRow($0, result: result, needMinutes: needMinutes, render: render, format: format) }
        return RecoveryDetailContent(
            recovery: content,
            rows: rows,
            calculation: calculation(result, needMinutes: needMinutes),
            modelVersion: "Model \(result.modelVersion)"
        )
    }

    static func detailRow(_ factor: RecoveryFactor, result: RecoveryResult, needMinutes: Int, render: HomeRenderModel? = nil, format: HomeFormat) -> FactorDetailRow {
        let name = shortName(factor.kind)
        let value: NoctisMetricValue
        var suffix: String?
        let baseline: String
        let sentence: String
        switch factor.kind {
        case .sleepDuration:
            let slept = Int(factor.value.rounded())
            let need = HomeFormat.compactDuration(needMinutes)
            value = HomeFormat.durationMetric(slept)
            baseline = factor.baseline.map { "baseline \(HomeFormat.compactDuration(Int($0.rounded())))" } ?? "no baseline yet"
            sentence = slept >= needMinutes
                ? "You met your \(need) sleep need."
                : "You slept \(HomeFormat.compactDuration(slept)) of your \(need) need."
        case .hrv:
            let usual = factor.baseline ?? factor.value
            let ms = Int(factor.value.rounded())
            let percent = usual > 0 ? Int(((factor.value / usual - 1) * 100).rounded()) : 0
            let v1Sentence = percent == 0 ? "In line with your baseline." : "\(abs(percent))% \(percent > 0 ? "above" : "below") your baseline."
            value = HomeFormat.quantityMetric(ms, unit: "ms", spokenUnit: "milliseconds")
            baseline = "baseline \(Int(usual.rounded())) ms"
            sentence = factor.range.map { rangeSentence($0, value: "\(ms) ms", baseline: "\(Int(usual.rounded())) ms") } ?? v1Sentence
        case .restingHeartRate:
            let usual = factor.baseline ?? factor.value
            let bpm = Int(factor.value.rounded())
            let difference = bpm - Int(usual.rounded())
            let v1Sentence = difference == 0 ? "Same as your baseline." : "\(abs(difference)) bpm \(difference > 0 ? "above" : "below") your baseline."
            value = HomeFormat.quantityMetric(bpm, unit: "bpm", spokenUnit: "beats per minute")
            baseline = "baseline \(Int(usual.rounded())) bpm"
            sentence = factor.range.map { rangeSentence($0, value: "\(bpm) bpm", baseline: "\(Int(usual.rounded())) bpm") } ?? v1Sentence
        case .sleepConsistency:
            let minutes = Int(factor.value.rounded())
            value = HomeFormat.durationMetric(minutes)
            suffix = "off"
            if let bedtime = result.baselines.bedtime?.value, let wake = result.baselines.wakeTime?.value {
                baseline = "usual \(format.clock(minutesAfterNoon: bedtime)) – \(format.clock(minutesAfterNoon: wake))"
            } else {
                baseline = "no baseline yet"
            }
            sentence = minutes == 0
                ? "Right on your usual bedtime and wake time."
                : "Bedtime and wake time were \(HomeFormat.compactDuration(minutes, minutesWord: true)) from your usual, on average."
        }
        let sparkline = result.history(factor.kind).map { sparklineContent($0, render: render?.sparkline(factor.kind)) }
        let spokenValue = value.spoken + (suffix.map { " \($0)" } ?? "")
        let label = "\(name) \(spokenValue), \(baseline), score \(factor.score). \(sentence)" + (sparkline.map { " \($0.accessibilityLabel)" } ?? "")
        return FactorDetailRow(
            kind: factor.kind, name: name, value: value, valueSuffix: suffix, baseline: baseline,
            score: factor.score, sentence: sentence, sparkline: sparkline, accessibilityLabel: label
        )
    }

    /// The 14 nights, the normal range and today as the render model
    /// scaled them (0...1 up); consistency is drawn as bedtime.
    static func sparklineContent(_ history: RecoveryFactorHistory, render: SparklineRender? = nil) -> SparklineContent {
        let render = render ?? SparklineRenderBuilder.build(history)
        let subject = switch history.kind {
        case .sleepDuration: "Sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting heart rate"
        case .sleepConsistency: "Bedtime"
        }
        return SparklineContent(
            nights: render.nights,
            today: render.today,
            band: render.bandLow...render.bandHigh,
            accessibilityLabel: "\(subject) has been within your normal range on \(history.nightsWithin) of \(history.nightsRecorded) nights."
        )
    }

    /// "Within your normal range: 48 ms vs your 50 ms baseline."
    static func rangeSentence(_ range: RecoveryRange, value: String, baseline: String) -> String {
        let place = switch range {
        case .within: "Within your normal range"
        case .above: "Above your normal range"
        case .below: "Below your normal range"
        }
        return "\(place): \(value) vs your \(baseline) baseline."
    }

    static func calculation(_ result: RecoveryResult, needMinutes: Int) -> [String] {
        let model = RecoveryModel(rawValue: result.modelVersion) ?? .current
        func weight(_ kind: RecoveryFactorKind) -> String {
            "\(Int((model.weights[kind] ?? 0).rounded()))%"
        }
        var paragraphs = [
            "Recovery compares last night with your own last \(BaselineEngine.windowNights) nights. "
                + "Four signals count: sleep against your \(HomeFormat.compactDuration(needMinutes)) need (\(weight(.sleepDuration))), "
                + "HRV (\(weight(.hrv))), resting heart rate (\(weight(.restingHeartRate))) "
                + "and how close your bedtime and wake time were to usual (\(weight(.sleepConsistency)))."
                + (model != .v1
                    ? " HRV and resting heart rate are scored against how much they normally vary for you: a typical night scores about "
                        + "\(Int(RecoveryModelV2.variationCenter)), and each standard deviation better or worse moves the score "
                        + "\(Int(RecoveryModelV2.pointsPerStandardDeviation)) points."
                    : ""),
        ]
        if result.factors.count < RecoveryFactorKind.allCases.count {
            let today = factorOrder.compactMap { result.factor($0) }
                .map { "\(listName($0.kind)) \(Int(($0.weight * 100).rounded()))%" }
                .joined(separator: ", ")
            paragraphs.append("A signal without data, or without \(BaselineEngine.minimumNights) nights to compare with, is left out and the others share its weight. Today: \(today).")
        } else {
            paragraphs.append("Today all four signals count.")
        }
        paragraphs.append(
            "Confidence is high with all four signals and \(RecoveryModelV1.highConfidenceNights) nights of history, "
                + "moderate with at least \(RecoveryModelV1.moderateConfidenceFactors) signals \(model == .v1 ? "or" : "and") "
                + "\(RecoveryModelV1.moderateConfidenceNights) nights, and low otherwise."
        )
        if model == .v3 {
            paragraphs.append(
                "If HRV is \(RecoveryModelV3.heartCapStandardDeviations.formatted()) standard deviations or more below normal and resting heart rate "
                    + "\(RecoveryModelV3.heartCapStandardDeviations.formatted()) or more above it on the same morning, recovery is capped at "
                    + "\(RecoveryModelV3.heartCapScore), however well you slept."
            )
        }
        return paragraphs
    }

    // MARK: Tonight

    static func tonightCard(_ plan: TonightPlan, format: HomeFormat) -> TonightCardContent {
        TonightCardContent(
            bedtimeLead: "Bedtime around",
            bedtime: format.clockMetric(format.clock(minutesSinceMidnight: plan.bedtimeMinutes)),
            detail: "Wake \(format.clock(minutesSinceMidnight: plan.wakeMinutes)) · \(HomeFormat.compactDuration(plan.needMinutes)) need"
        )
    }

    // MARK: This week

    static func weekCard(_ snapshot: HomeSnapshot, format: HomeFormat) -> WeekCardContent {
        let render = snapshot.render.week.bars.count == snapshot.recentNights.count
            ? snapshot.render.week
            : WeekRenderBuilder.build(snapshot.recentNights, needMinutes: snapshot.tonight.needMinutes, lastNight: snapshot.lastNight?.night)
        let bars = snapshot.recentNights.enumerated().map { index, night -> WeekBar in
            let wakeDay = night.night.adding(days: 1)
            let dayName = format.weekday(wakeDay, width: .wide)
            let minutes = night.asleepMinutes.map { Int($0.rounded()) }
            // Deep and REM name the night's quality; Core is the rest.
            let stageParts: [(String, Int)] = night.stages.map { [("Deep", Int($0.deep.rounded())), ("REM", Int($0.rem.rounded()))] } ?? []
            let pill = [format.weekday(wakeDay, width: .abbreviated), minutes.map { HomeFormat.compactDuration($0) } ?? "No data"]
                + stageParts.map { "\($0.0) \(HomeFormat.compactDuration($0.1))" }
            let spoken = [dayName, minutes.map { HomeFormat.spokenDuration($0) } ?? "no data"]
                + stageParts.map { "\($0.0 == "Deep" ? "deep" : $0.0) \(HomeFormat.spokenDuration($0.1))" }
            return WeekBar(
                label: format.weekday(wakeDay, width: .narrow),
                fraction: render.bars[index].fraction,
                stages: render.bars[index].stages,
                isLastNight: render.bars[index].isLastNight,
                accessibilityLabel: spoken.joined(separator: ", "),
                detail: pill.joined(separator: " · ")
            )
        }
        let needLabel = "\(HomeFormat.compactDuration(snapshot.tonight.needMinutes)) need"
        let average = snapshot.weekAverageMinutes.map { HomeFormat.durationMetric(Int($0.rounded())) }
        let spokenAverage = average.map { ", average \($0.spoken)" } ?? ""
        let spokenNeed = "\(HomeFormat.spokenDuration(snapshot.tonight.needMinutes)) need"
        return WeekCardContent(
            bars: bars,
            needFraction: render.needFraction,
            needLabel: needLabel,
            average: average,
            accessibilityLabel: "This week\(spokenAverage), \(spokenNeed). " + bars.map(\.accessibilityLabel).joined(separator: "; ") + "."
        )
    }
}

// MARK: - Share

nonisolated extension HomeScreenBuilder {
    static func shareCard(_ snapshot: HomeSnapshot, recovery: RecoveryCardContent, now: Date, format: HomeFormat) -> ShareCardContent? {
        var shareRecovery: ShareCardContent.ShareRecovery?
        var details: String?
        if case .scored(let content) = recovery, case .scored(let result)? = snapshot.recovery {
            shareRecovery = .init(score: content.score, segments: content.segments)
            let hrv = result.factor(.hrv).map { "HRV \(Int($0.value.rounded())) ms" }
            let resting = result.factor(.restingHeartRate).map { "Resting HR \(Int($0.value.rounded())) bpm" }
            let parts = [hrv, resting].compactMap { $0 }
            details = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let session = snapshot.lastNight
        guard shareRecovery != nil || session != nil else { return nil }
        let date = format.longDate(now)
        let day = format.calendar.dateComponents([.year, .month, .day], from: now)
        return ShareCardContent(
            recovery: shareRecovery,
            lastNight: session.map { HomeFormat.durationMetric(Int(($0.totals.asleep / 60).rounded())) },
            chart: session.map { nightChart($0, heart: snapshot.lastNightHeart, render: snapshot.render.night, format: format) },
            date: date,
            details: details,
            title: "NOCTIS · \(date)",
            fileName: String(format: "noctis-%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        )
    }
}

// MARK: - Formatting

/// Locale-aware formatting with an explicit calendar, time zone and
/// locale, so every string is reproducible in tests.
public nonisolated struct HomeFormat: Sendable, Equatable {
    public let calendar: Calendar
    public let locale: Locale

    public init(calendar: Calendar, locale: Locale) {
        self.calendar = calendar
        self.locale = locale
    }

    /// "Thursday, September 24".
    public func longDate(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone ?? calendar.timeZone).weekday(.wide).month(.wide).day())
    }

    /// "Wed, Sep 23".
    public func shortDate(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone ?? calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Wed 7:02 AM", kept on one line (no-break spaces).
    public func dayAndTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated).hour().minute())
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// "11:02 PM" on the clock of `timeZone`.
    public func clock(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
    }

    /// A clock time given as minutes since midnight.
    public func clock(minutesSinceMidnight minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: normalized / 60, minute: normalized % 60)
        guard let date = calendar.date(from: components) else { return "" }
        return clock(date, in: calendar.timeZone)
    }

    /// "6 PM": the hour alone.
    public func hour(minutesSinceMidnight minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        let components = DateComponents(year: 2026, month: 1, day: 1, hour: normalized / 60, minute: normalized % 60)
        guard let date = calendar.date(from: components) else { return "" }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour())
    }

    /// "11:00 PM" → ("11:00", "PM"); 24-hour clocks have no period.
    public func splitClock(_ text: String) -> (time: String, period: String) {
        let formatter = DateFormatter()
        formatter.locale = locale
        for symbol in [formatter.amSymbol, formatter.pmSymbol] where !(symbol ?? "").isEmpty {
            guard let symbol, let range = text.range(of: symbol) else { continue }
            var time = text
            time.removeSubrange(range)
            return (time.trimmingCharacters(in: .whitespaces), symbol)
        }
        return (text, "")
    }

    /// A clock time given as minutes after noon (baselines' unit).
    public func clock(minutesAfterNoon: Double) -> String {
        clock(minutesSinceMidnight: Int(minutesAfterNoon.rounded()) + 720)
    }

    public enum WeekdayWidth { case narrow, abbreviated, wide }

    public func weekday(_ day: SleepNightKey, width: WeekdayWidth) -> String {
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        guard let date = calendar.date(from: components) else { return "" }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return switch width {
        case .narrow: date.formatted(style.weekday(.narrow))
        case .abbreviated: date.formatted(style.weekday(.abbreviated))
        case .wide: date.formatted(style.weekday(.wide))
        }
    }

    /// 6h 42m, 8h, 45m as a metric; VoiceOver hears "6 hours 42 minutes".
    public static func durationMetric(_ minutes: Int) -> NoctisMetricValue {
        let hours = minutes / 60
        let remainder = minutes % 60
        var parts: [NoctisMetricValue.Part] = []
        if hours > 0 { parts += [.number("\(hours)"), .unit("h")] }
        if remainder > 0 || hours == 0 {
            if !parts.isEmpty { parts.append(.space) }
            parts += [.number("\(remainder)"), .unit("m")]
        }
        return NoctisMetricValue(parts: parts, spoken: spokenDuration(minutes))
    }

    /// "6 hours 42 minutes", "1 hour", "45 minutes".
    public static func spokenDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        var words: [String] = []
        if hours > 0 { words.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if remainder > 0 || hours == 0 { words.append("\(remainder) \(remainder == 1 ? "minute" : "minutes")") }
        return words.joined(separator: " ")
    }

    /// 52 bpm, 48 ms as a metric.
    public static func quantityMetric(_ value: Int, unit: String, spokenUnit: String) -> NoctisMetricValue {
        NoctisMetricValue(parts: [.number("\(value)"), .unit(unit)], spoken: "\(value) \(spokenUnit)")
    }

    /// 11:00 PM as a metric: the period is the unit (none on 24-hour
    /// clocks).
    public func clockMetric(_ text: String) -> NoctisMetricValue {
        let (time, period) = splitClock(text)
        return NoctisMetricValue(parts: period.isEmpty ? [.number(time)] : [.number(time), .unit(period)], spoken: text)
    }

    /// "8h", "8h 15m", "45m" — or with `minutesWord`, "45 min".
    public static func compactDuration(_ minutes: Int, minutesWord: Bool = false) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return minutesWord ? "\(remainder) min" : "\(remainder)m" }
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
