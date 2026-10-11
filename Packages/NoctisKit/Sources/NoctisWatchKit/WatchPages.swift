import DesignSystem
import Foundation
import NoctisWidgetKit
import NoctisText

// What each page of the Apple Watch app says, for every state (APP_RULES.md R50, R51): pure, built from the snapshot the iPhone sent and the clock, so
// every sentence is a unit test and the views only lay them out. The Watch works nothing out: a number on a page is a number in the snapshot, and a
// Health number is marked `.health` so the views hide it while the Watch is locked.

public enum WatchPage: String, CaseIterable, Sendable, Identifiable {
    case recovery, sleep, heart, tonight, settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .heart: "Heart"
        case .tonight: "Tonight"
        case .settings: "Settings"
        }
    }
}

/// The words for what the Watch cannot show, with a glyph.
public struct WatchMessage: Equatable, Sendable {
    public var glyph: String
    public var title: String
    public var detail: String?

    public init(glyph: String, title: String, detail: String? = nil) {
        self.glyph = glyph
        self.title = title
        self.detail = detail
    }
}

public nonisolated enum WatchCopy {
    public static let waiting = "Waiting for last night's data"
    public static let connectHealth = "Open NOCTIS on your iPhone to connect Apple Health"
    public static let getStarted = "Open NOCTIS on your iPhone to get started"
    public static let noSleep = "No sleep recorded last night"
    public static let unreachable = "Your iPhone isn't reachable right now"
    public static let asked = "Asked your iPhone"
    public static let askFailed = "Couldn't ask your iPhone"
    public static let askButton = "Ask iPhone to update"
    public static let about = "NOCTIS isn't a medical device and doesn't diagnose or treat any condition."
    public static let noAlarm = "No alarm set"
    public static let heartMissing = "No heart rate variability or resting heart rate was available for last night."
    public static let breathingTagline = "A slow breathing exercise."

    /// "Updated just now", "Updated 12m ago", "Updated 3h ago", "Updated 2d ago".
    public static func updated(since date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 { return "Updated just now" }
        if seconds < 3600 { return "Updated \(Int(seconds / 60))m ago" }
        return WidgetCopy.updated(hours: Int(seconds / 3600))
    }

    /// "Moderate confidence", only when it is not high.
    public static func confidence(_ value: WidgetConfidence) -> String? {
        switch value {
        case .high: nil
        case .moderate: "Moderate confidence"
        case .low: "Low confidence"
        }
    }

    public static func factorName(_ kind: WidgetFactorKind) -> String {
        switch kind {
        case .sleepDuration: "Sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting HR"
        case .sleepConsistency: "Consistency"
        }
    }
}

/// What the Watch knows when it draws a page.
public struct WatchPageInput: Sendable {
    public var snapshot: WidgetSnapshot?
    public var state: WatchState
    public var now: Date
    /// When the held snapshot arrived on the Watch.
    public var receivedAt: Date?
    public var format: WidgetFormat

    public init(snapshot: WidgetSnapshot?, now: Date, receivedAt: Date? = nil, format: WidgetFormat = WidgetFormat()) {
        self.snapshot = snapshot
        self.state = WatchState.map(snapshot, now: now, calendar: format.calendar)
        self.now = now
        self.receivedAt = receivedAt
        self.format = format
    }

    /// The states that carry no numbers say what is missing, in one place for every page (a page may add its own detail).
    func message(for page: WatchPage) -> WatchMessage? {
        switch state {
        case .ok, .sleepOnly, .stale: nil
        case .waitingForToday: WatchMessage(glyph: "hourglass", title: WatchCopy.waiting)
        case .learning(let nights): WatchMessage(glyph: "chart.line.uptrend.xyaxis", title: WidgetCopy.learningLine(nights))
        case .gap: WatchMessage(glyph: "moon.zzz", title: WatchCopy.noSleep)
        case .empty, .noPermission: WatchMessage(glyph: "heart.text.square", title: WatchCopy.connectHealth)
        case .noSnapshotYet: WatchMessage(glyph: "iphone", title: WatchCopy.getStarted)
        }
    }

    /// "Updated 14h ago" for numbers that are the last known ones (never as today's); nil for today's.
    var staleLine: String? {
        guard case .stale(let since) = state else { return nil }
        return WidgetCopy.updated(hours: max(Int(now.timeIntervalSince(since) / 3600), 0))
    }
}

// MARK: Recovery

public struct WatchRecoveryPage: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public var kind: WidgetFactorKind
        public var name: String
        public var score: Int
        public var id: Int { kind.rawValue }
    }

    public struct Delta: Equatable, Sendable {
        public var text: String
        public var tone: WidgetDelta.Tone
    }

    public var message: WatchMessage?
    public var score: Int?
    public var delta: Delta?
    public var ring: [WidgetRingSegment]
    public var factors: [Row]
    /// Only when it is not high.
    public var confidence: String?
    /// "Updated 14h ago", for the last known numbers.
    public var staleLine: String?
    public var sensitivity: WidgetSensitivity
    public var accessibilityLabel: String
}

// MARK: Sleep

public struct WatchSleepPage: Equatable, Sendable {
    public var message: WatchMessage?
    /// "Last night", or "Last recorded" for old numbers.
    public var caption: String
    public var duration: NoctisMetricValue?
    /// "11:04 PM – 6:52 AM".
    public var times: String?
    public var stages: WidgetStages?
    /// "Sleep quality 78".
    public var quality: String?
    public var staleLine: String?
    public var sensitivity: WidgetSensitivity
    public var accessibilityLabel: String
}

// MARK: Heart

public struct WatchHeartTile: Equatable, Sendable, Identifiable {
    public var kind: WidgetFactorKind
    public var name: String
    public var value: NoctisMetricValue
    /// "baseline 73 ms".
    public var baseline: String?
    /// "Within your normal range": the iPhone's own words.
    public var sentence: String?
    public var id: Int { kind.rawValue }
}

public struct WatchHeartPage: Equatable, Sendable {
    public var message: WatchMessage?
    public var tiles: [WatchHeartTile]
    public var staleLine: String?
    public var sensitivity: WidgetSensitivity
    public var accessibilityLabel: String
    /// The page is Premium and the person's plan does not include it: a locked card and no number (R62).
    public var locked: WatchLockedContent?
}

// MARK: Tonight

public struct WatchTonightPage: Equatable, Sendable {
    public enum Countdown: Equatable, Sendable {
        /// Counts down to the bedtime (the evening, before it).
        case until(Date)
        /// The bedtime has passed: "Bedtime was 11:00 PM".
        case passed(String)
        /// By day there is no countdown.
        case none
    }

    public var message: WatchMessage?
    /// "10:45 – 11:15 PM" or "11:00 PM".
    public var bedtime: NoctisMetricValue?
    public var windowText: String?
    /// "Wake 7:00 AM - 8h need".
    public var wakeLine: String?
    public var countdown: Countdown
    /// "Alarm 7:00 AM" or "No alarm set".
    public var alarmLine: String?
    public var sensitivity: WidgetSensitivity
    public var accessibilityLabel: String
    /// The page is Premium and the person's plan does not include it: a locked card and no plan (R62). Breathing, which is free and needs nothing from the iPhone,
    /// is still there below it.
    public var locked: WatchLockedContent?
}

// MARK: Settings

public struct WatchSettingsPage: Equatable, Sendable {
    /// What the Watch holds, in one line.
    public var status: String
    public var updated: String?
    public var about: String
    public var version: String
}

public nonisolated enum WatchPages {
    // MARK: Recovery

    public static func recovery(_ input: WatchPageInput) -> WatchRecoveryPage {
        guard input.state.showsNumbers, let snapshot = input.snapshot, let recovery = snapshot.recovery else {
            let message = input.message(for: .recovery) ?? (input.state == .sleepOnly || input.state.isStale ? WatchMessage(glyph: "heart.text.square", title: "No recovery score yet") : nil)
            return WatchRecoveryPage(
                message: message, score: nil, delta: nil, ring: [], factors: [], confidence: nil, staleLine: nil, sensitivity: .health,
                accessibilityLabel: message?.title ?? "Recovery"
            )
        }
        var delta: WatchRecoveryPage.Delta?
        if let value = recovery.delta {
            let tone: WidgetDelta.Tone = value >= WidgetCopy.trendThreshold ? .above : value <= -WidgetCopy.trendThreshold ? .below : .inLine
            delta = .init(text: "\(WidgetCopy.signed(value)) vs your usual", tone: tone)
        }
        // The four factors that were scored, in ring order; a v1-style snapshot with no factor list falls back to the ring's own arcs.
        let rows: [WatchRecoveryPage.Row] = snapshot.recoveryFactors.isEmpty
            ? recovery.ring.map { .init(kind: $0.kind, name: WatchCopy.factorName($0.kind), score: Int(($0.fraction * 100).rounded())) }
            : snapshot.recoveryFactors.map { .init(kind: $0.kind, name: WatchCopy.factorName($0.kind), score: $0.score) }
        let stale = input.staleLine
        var spoken = ["Recovery \(recovery.score)"]
        if let delta { spoken.append(delta.text) }
        if let confidence = WatchCopy.confidence(recovery.confidence) { spoken.append(confidence) }
        if let stale { spoken.append(stale) }
        return WatchRecoveryPage(
            message: nil, score: recovery.score, delta: delta, ring: recovery.ring, factors: rows, confidence: WatchCopy.confidence(recovery.confidence),
            staleLine: stale, sensitivity: .health, accessibilityLabel: spoken.joined(separator: ". ")
        )
    }

    // MARK: Sleep

    public static func sleep(_ input: WatchPageInput) -> WatchSleepPage {
        guard input.state.showsNumbers, let night = input.snapshot?.lastNight else {
            let message = input.message(for: .sleep) ?? WatchMessage(glyph: "moon.zzz", title: WatchCopy.noSleep)
            return WatchSleepPage(message: message, caption: "Last night", duration: nil, times: nil, stages: nil, quality: nil, staleLine: nil, sensitivity: .health, accessibilityLabel: message.title)
        }
        let format = input.format
        let stale = input.staleLine
        let times = "\(format.clock(minutesSinceMidnight: night.bedtimeMinutes)) – \(format.clock(minutesSinceMidnight: night.wakeMinutes))"
        var spoken = ["\(stale == nil ? "Slept" : "Last recorded sleep") \(WidgetFormat.spokenDuration(night.asleepMinutes))"]
        if let quality = night.quality { spoken.append("Sleep quality \(quality)") }
        if let stale { spoken.append(stale) }
        return WatchSleepPage(
            message: nil, caption: stale == nil ? "Last night" : "Last recorded", duration: WidgetFormat.durationMetric(night.asleepMinutes), times: times,
            stages: night.stages, quality: night.quality.map { "Sleep quality \($0)" }, staleLine: stale, sensitivity: .health, accessibilityLabel: spoken.joined(separator: ". ")
        )
    }

    // MARK: Heart

    public static func heart(_ input: WatchPageInput) -> WatchHeartPage {
        if WatchGate.isLocked(.heart, tier: input.snapshot?.tier) {
            let locked = WatchLockedContent(.heart)
            return WatchHeartPage(message: nil, tiles: [], staleLine: nil, sensitivity: .plan, accessibilityLabel: locked.accessibilityLabel, locked: locked)
        }
        guard input.state.showsNumbers, let snapshot = input.snapshot else {
            let message = input.message(for: .heart) ?? WatchMessage(glyph: "heart", title: WatchCopy.heartMissing)
            return WatchHeartPage(message: message, tiles: [], staleLine: nil, sensitivity: .health, accessibilityLabel: message.title)
        }
        var tiles: [WatchHeartTile] = []
        func tile(_ kind: WidgetFactorKind, value: Int?, unit: NoctisUnit) {
            guard let value else { return }
            let scored = snapshot.recoveryFactors.first { $0.kind == kind }
            let baseline = scored?.baseline.map { "baseline \(Int($0.rounded())) \(unit.symbol)" }
            tiles.append(
                WatchHeartTile(
                    kind: kind, name: WatchCopy.factorName(kind), value: WidgetFormat.quantityMetric(value, unit), baseline: baseline,
                    sentence: scored?.range.map(WidgetCopy.rangePlace)
                )
            )
        }
        tile(.hrv, value: snapshot.factors?.hrv, unit: .millisecond)
        tile(.restingHeartRate, value: snapshot.factors?.restingHeartRate, unit: .beatsPerMinute)
        guard !tiles.isEmpty else {
            let message = WatchMessage(glyph: "heart", title: WatchCopy.heartMissing)
            return WatchHeartPage(message: message, tiles: [], staleLine: input.staleLine, sensitivity: .health, accessibilityLabel: message.title)
        }
        let spoken = tiles.map { "\($0.name) \($0.value.spoken)" + ($0.sentence.map { ", \($0.lowercased())" } ?? "") } + [input.staleLine].compactMap { $0 }
        return WatchHeartPage(message: nil, tiles: tiles, staleLine: input.staleLine, sensitivity: .health, accessibilityLabel: spoken.joined(separator: ". "))
    }

    // MARK: Tonight

    public static func tonight(_ input: WatchPageInput) -> WatchTonightPage {
        if WatchGate.isLocked(.tonight, tier: input.snapshot?.tier) {
            let locked = WatchLockedContent(.tonight)
            return WatchTonightPage(
                message: nil, bedtime: nil, windowText: nil, wakeLine: nil, countdown: .none, alarmLine: nil, sensitivity: .plan, accessibilityLabel: locked.accessibilityLabel,
                locked: locked
            )
        }
        guard let snapshot = input.snapshot else {
            let message = WatchMessage(glyph: "iphone", title: WatchCopy.getStarted)
            return WatchTonightPage(message: message, bedtime: nil, windowText: nil, wakeLine: nil, countdown: .none, alarmLine: nil, sensitivity: .plan, accessibilityLabel: message.title)
        }
        let format = input.format
        // The plan is the person's own settings, not Health: it is shown whenever the Watch has a snapshot, as the widgets do.
        let entry = WidgetTimelineBuilder.entry(for: snapshot, at: input.now, calendar: format.calendar)
        let plan = snapshot.plan
        let window = plan.windowStartMinutes.flatMap { start in plan.windowEndMinutes.map { format.windowText(startMinutes: start, endMinutes: $0) } }
        let bedtimeText = format.clock(minutesSinceMidnight: plan.bedtimeMinutes)
        let wake = format.clock(minutesSinceMidnight: plan.wakeMinutes)
        var countdown = WatchTonightPage.Countdown.none
        if entry.mode == .evening, let bedtime = entry.bedtime {
            countdown = bedtime > input.now ? .until(bedtime) : .passed("Bedtime was \(bedtimeText)")
        }
        let alarm: String = snapshot.alarm.flatMap { $0.isOn ? "Alarm \(format.clock(minutesSinceMidnight: $0.minutes))" : nil } ?? WatchCopy.noAlarm
        let wakeLine = "Wake \(wake) - \(WidgetFormat.compactDuration(plan.needMinutes)) need"
        var spoken = ["Bedtime \(window ?? bedtimeText)", wakeLine, alarm]
        if case .passed(let text) = countdown { spoken.insert(text, at: 0) }
        return WatchTonightPage(
            message: nil, bedtime: window == nil ? format.clockMetric(minutesSinceMidnight: plan.bedtimeMinutes) : nil, windowText: window, wakeLine: wakeLine,
            countdown: countdown, alarmLine: alarm, sensitivity: .plan, accessibilityLabel: spoken.joined(separator: ". ")
        )
    }

    // MARK: Settings

    public static func settings(_ input: WatchPageInput, version: String) -> WatchSettingsPage {
        let status: String
        switch input.state {
        case .ok: status = "Recovery and sleep"
        case .sleepOnly: status = "Sleep only"
        case .stale(let since): status = "Last numbers, \(WidgetCopy.updated(hours: max(Int(input.now.timeIntervalSince(since) / 3600), 0)).replacingOccurrences(of: "Updated ", with: ""))"
        case .learning(let nights): status = WidgetCopy.learningLine(nights)
        case .waitingForToday: status = WatchCopy.waiting
        case .gap: status = WatchCopy.noSleep
        case .empty, .noPermission: status = "Apple Health isn't connected"
        case .noSnapshotYet: status = "Nothing received yet"
        }
        return WatchSettingsPage(status: status, updated: WatchCopy.updated(since: input.receivedAt, now: input.now), about: WatchCopy.about, version: version)
    }
}
