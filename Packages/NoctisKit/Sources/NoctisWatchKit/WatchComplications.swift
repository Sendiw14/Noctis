import DesignSystem
import Foundation
import NoctisWidgetKit

// What each Apple Watch complication says, for every kind, family and state (APP_RULES.md R50, R51, R54): pure, built from the summary the iPhone sent and
// the clock, with the same states as the Watch's pages (`WatchState`), so every sentence is a unit test and the views only lay it out. A complication
// shows only today's numbers or the last known ones marked as old, never yesterday's as today's, and every Health value is marked so the views hide it
// while the Watch is locked. Bedtime is the person's own plan and is not hidden.

// MARK: - Where a tap goes

/// The pages a complication can open, as the only links the Watch app accepts (R54): `noctis://recovery`, nothing more. The same strictness as the
/// iPhone's `WidgetLink`: the scheme, one of four hosts, no path, query, fragment, port or credentials; anything else is nil.
public nonisolated enum WatchLink: String, Sendable, CaseIterable, Equatable {
    case recovery
    case sleep
    case heart
    case tonight

    public static let scheme = "noctis"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = rawValue
        return components.url ?? URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == Self.scheme,
            // The host as written, not as decoded: "%72ecovery" is not "recovery".
            let host = components.percentEncodedHost?.lowercased(),
            components.user == nil, components.password == nil, components.port == nil,
            components.query == nil, components.fragment == nil,
            components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/",
            let link = WatchLink(rawValue: host)
        else { return nil }
        self = link
    }

    /// The page it opens.
    public var page: WatchPage {
        switch self {
        case .recovery: .recovery
        case .sleep: .sleep
        case .heart: .heart
        case .tonight: .tonight
        }
    }
}

// MARK: - Kinds and families

/// The four complications. The raw value is the widget's `kind`, which never changes once shipped (a face keeps the complication by it).
public nonisolated enum WatchComplicationKind: String, Sendable, CaseIterable, Equatable {
    case recovery = "NoctisRecoveryWatch"
    case sleep = "NoctisSleepWatch"
    case bedtime = "NoctisBedtimeWatch"
    case quality = "NoctisQualityWatch"

    /// The name in the complication gallery on the Watch.
    public var displayName: String {
        switch self {
        case .recovery: "NOCTIS Recovery"
        case .sleep: "NOCTIS Sleep"
        case .bedtime: "NOCTIS Bedtime"
        case .quality: "NOCTIS Sleep quality"
        }
    }

    public var summary: String {
        switch self {
        case .recovery: "Your recovery score, and tonight's bedtime in the evening."
        case .sleep: "How long you slept last night."
        case .bedtime: "Tonight's bedtime, counting down in the evening."
        case .quality: "Last night's sleep quality."
        }
    }

    /// The curved text in a corner complication.
    public var cornerLabel: String {
        switch self {
        case .recovery: "Recovery"
        case .sleep: "Sleep"
        case .bedtime: "Bedtime"
        case .quality: "Quality"
        }
    }

    /// Whether the numbers are Health values (hidden while the Watch is locked): bedtime is the person's own plan.
    public var showsHealth: Bool { self != .bedtime }

    /// The page a tap opens by day (the evening's Recovery opens Tonight).
    public var link: WatchLink {
        switch self {
        case .recovery: .recovery
        case .sleep, .quality: .sleep
        case .bedtime: .tonight
        }
    }
}

public nonisolated enum WatchComplicationFamily: String, Sendable, CaseIterable, Equatable {
    case circular, rectangular, inline, corner
}

// MARK: - Content

public nonisolated struct WatchComplicationContent: Equatable, Sendable {
    public var kind: WatchComplicationKind
    /// The circular and corner gauge, 0 to 1; nil draws an empty track.
    public var gauge: Double?
    /// What sits in the middle of the gauge: "70", "6h42", "11:00", "78", or "" with a glyph.
    public var centerText: String
    /// An SF Symbol for the middle when there is no number (a message, the lock), and the moon on Bedtime's circle.
    public var centerGlyph: String?
    /// Whether `centerText` is a Health value.
    public var centerIsHealth: Bool
    /// The rectangular lines. Health words are `.health`.
    public var rectangular: [[WidgetLockPiece]]
    /// Sleep's flat stage strip under the first rectangular line.
    public var stages: WidgetStages?
    /// The inline line (about 28 characters).
    public var inline: [WidgetLockPiece]
    public var link: WatchLink
    /// One sentence for VoiceOver.
    public var accessibilityLabel: String
    /// The kind is Premium and the person's plan does not include it: a plain "Premium" state with no number (R62).
    public var isLocked = false

    public var cornerLabel: String { isLocked ? "Premium" : kind.cornerLabel }

    /// The content while the Watch is locked: every Health word becomes "Unlock to see" (once, the lines after the first collapse into it), the gauge
    /// and the stage strip have no number.
    public func locked() -> WatchComplicationContent {
        // A Premium state holds no Health value to hide.
        if isLocked { return self }
        func hidesHealth(_ pieces: [WidgetLockPiece]) -> Bool { pieces.contains { if case .health = $0 { true } else { false } } }
        var lines: [[WidgetLockPiece]] = []
        var shown = false
        for line in rectangular {
            if hidesHealth(line) {
                if !shown { lines.append([.text(WidgetCopy.unlock)]) }
                shown = true
            } else {
                lines.append(line)
            }
        }
        let inline = self.inline.map { piece -> WidgetLockPiece in
            if case .health = piece { return .text(WidgetCopy.unlock) }
            return piece
        }
        var copy = self
        if centerIsHealth {
            copy.gauge = nil
            copy.centerText = ""
            copy.centerGlyph = "lock.fill"
        }
        copy.rectangular = lines
        copy.stages = rectangular.contains(where: hidesHealth) ? nil : stages
        copy.inline = inline
        copy.accessibilityLabel = kind.showsHealth ? WidgetCopy.unlock : accessibilityLabel
        return copy
    }
}

// MARK: - The builder

public nonisolated enum WatchComplications {
    /// "6h42": the hours, the unit, the minutes with no unit (a circular complication is about fifty points wide); under an hour "42m".
    public static func circularDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours == 0 ? "\(remainder)m" : "\(hours)h" + (remainder < 10 ? "0\(remainder)" : "\(remainder)")
    }

    /// What `kind` says at `input.now`.
    public static func content(_ kind: WatchComplicationKind, input: WatchPageInput) -> WatchComplicationContent {
        let format = input.format
        let state = input.state
        let link = link(kind, input: input)
        // A summary with no plan to read: nothing for any kind.
        guard let snapshot = input.snapshot, state != .noSnapshotYet else {
            return message(
                kind, glyph: "iphone", lines: ["Open NOCTIS", "on your iPhone"], inline: "Open NOCTIS on iPhone", spoken: WatchCopy.getStarted, link: link)
        }
        // The kinds the person's plan does not include: a plain "Premium" state, whatever the numbers are (R62).
        if WatchGate.isLocked(kind, tier: snapshot.effectiveTier(at: input.now)) { return premium(kind, link: link) }
        if kind == .bedtime { return bedtime(snapshot: snapshot, input: input, link: link) }

        guard state.showsNumbers else {
            switch state {
            case .waitingForToday:
                return message(
                    kind, glyph: "hourglass", lines: ["Waiting for", "last night's sleep"], inline: "Waiting for sleep data", spoken: WatchCopy.waiting,
                    link: link)
            case .learning(let nights):
                return message(
                    kind, glyph: "chart.line.uptrend.xyaxis", lines: [WidgetCopy.learningTitle, WidgetCopy.nights(nights)],
                    inline: "Learning · \(WidgetCopy.nights(nights))",
                    spoken: WidgetCopy.learningLine(nights), link: link
                )
            case .gap:
                return message(
                    kind, glyph: "moon.zzz", lines: ["No sleep recorded", "last night"], inline: "No sleep last night", spoken: WatchCopy.noSleep, link: link)
            default:
                return message(
                    kind, glyph: "heart.text.square", lines: ["Open NOCTIS", "to connect Apple Health"], inline: "Open NOCTIS for Health",
                    spoken: WatchCopy.connectHealth, link: link)
            }
        }
        let age = input.staleLine
        switch kind {
        case .recovery: return recovery(snapshot: snapshot, input: input, age: age, link: link)
        case .sleep: return sleep(snapshot: snapshot, age: age, format: format, link: link)
        case .quality: return quality(snapshot: snapshot, age: age, format: format, link: link)
        case .bedtime: return bedtime(snapshot: snapshot, input: input, link: link)
        }
    }

    /// Where a tap goes: Recovery opens Tonight in the evening, like the iPhone's widget.
    static func link(_ kind: WatchComplicationKind, input: WatchPageInput) -> WatchLink {
        guard kind == .recovery, let snapshot = input.snapshot else { return kind.link }
        let entry = WidgetTimelineBuilder.entry(for: snapshot, at: input.now, calendar: input.format.calendar)
        return entry.mode == .evening ? .tonight : .recovery
    }

    // MARK: Premium

    /// What a complication the plan does not include says: a lock, "Premium" and a way to the app. Built from the kind alone, so no number can reach it.
    static func premium(_ kind: WatchComplicationKind, link: WatchLink) -> WatchComplicationContent {
        var content = message(
            kind, glyph: "lock.fill", lines: ["Premium", "Open NOCTIS"], inline: "Premium", spoken: "\(kind.displayName). Premium. Opens NOCTIS.", link: link
        )
        content.isLocked = true
        return content
    }

    // MARK: Messages

    private static func message(
        _ kind: WatchComplicationKind, glyph: String, lines: [String], inline: String, spoken: String, link: WatchLink
    ) -> WatchComplicationContent {
        WatchComplicationContent(
            kind: kind, gauge: nil, centerText: "", centerGlyph: glyph, centerIsHealth: false, rectangular: lines.map { [.text($0)] }, stages: nil,
            inline: [.text(inline)], link: link, accessibilityLabel: spoken
        )
    }

    // MARK: Recovery

    private static func recovery(snapshot: WidgetSnapshot, input: WatchPageInput, age: String?, link: WatchLink) -> WatchComplicationContent {
        let format = input.format
        let entry = WidgetTimelineBuilder.entry(for: snapshot, at: input.now, calendar: format.calendar)
        // The ring and score are today's only: not while old.
        let score = age == nil ? snapshot.recovery?.score : nil
        let bedTime = format.clock(minutesSinceMidnight: snapshot.plan.bedtimeMinutes)
        var rectangular: [[WidgetLockPiece]] = []
        var inline: [WidgetLockPiece]
        var spoken: [String] = []

        if entry.mode == .evening, let bedtime = entry.bedtime {
            // The evening: the bedtime counting down, with the score still on the gauge.
            if bedtime > input.now {
                rectangular = [[.text("Bedtime \(bedTime)")], [.text("in "), .countdown(bedtime)]]
                inline = [.text("Bedtime in "), .countdown(bedtime)]
                spoken = ["Bedtime \(bedTime)"]
            } else {
                rectangular = [[.text("Bedtime was \(bedTime)")]]
                inline = [.text("Bedtime was \(bedTime)")]
                spoken = ["Bedtime was \(bedTime)"]
            }
            if let score { rectangular.append([.health("Recovery \(score)")]) }
        } else {
            if let score { rectangular.append([.health("Recovery \(score)")]) }
            if let last = snapshot.lastNight { rectangular.append([.health("Sleep \(WidgetFormat.compactDuration(last.asleepMinutes))")]) }
            rectangular.append([.text(age ?? "Bed \(bedTime)")])
            if let score {
                inline = [.health("Recovery \(score)")] + (age.map { _ in [WidgetLockPiece.text(" - old")] } ?? [])
            } else if let last = snapshot.lastNight {
                inline = [.health("Sleep \(WidgetFormat.compactDuration(last.asleepMinutes))"), .text(" - \(age == nil ? "Bed \(bedTime)" : "old")")]
            } else {
                inline = [.text("Bed \(bedTime)")]
            }
            if let score { spoken.append("Recovery \(score)") }
            if let last = snapshot.lastNight {
                spoken.append("\(age == nil ? "Slept" : "Last recorded sleep") \(WidgetFormat.spokenDuration(last.asleepMinutes))")
            }
            if let age { spoken.append(age) }
        }
        if let score, entry.mode == .evening { spoken.insert("Recovery \(score)", at: 0) }
        if let age, entry.mode == .evening { spoken.append(age) }
        return WatchComplicationContent(
            kind: .recovery, gauge: score.map { Double($0) / 100 }, centerText: score.map(String.init) ?? "", centerGlyph: score == nil ? "bolt.heart" : nil,
            centerIsHealth: score != nil, rectangular: rectangular, stages: nil, inline: inline, link: link, accessibilityLabel: spoken.joined(separator: ". ")
        )
    }

    // MARK: Sleep

    private static func sleep(snapshot: WidgetSnapshot, age: String?, format: WidgetFormat, link: WatchLink) -> WatchComplicationContent {
        guard let night = snapshot.lastNight else {
            return message(
                .sleep, glyph: "moon.zzz", lines: ["No sleep recorded", "last night"], inline: "No sleep last night", spoken: WatchCopy.noSleep, link: link)
        }
        let duration = WidgetFormat.compactDuration(night.asleepMinutes)
        let caption = age == nil ? "Slept" : "Last slept"
        var lines: [[WidgetLockPiece]] = [[.health("\(caption) \(duration)")]]
        if let age { lines.append([.text(age)]) }
        let inline: [WidgetLockPiece] = [.health("Slept \(duration)")] + (age.map { _ in [WidgetLockPiece.text(" - old")] } ?? [])
        let spoken = "\(age == nil ? "Slept" : "Last recorded sleep") \(WidgetFormat.spokenDuration(night.asleepMinutes))" + (age.map { ". \($0)" } ?? "")
        return WatchComplicationContent(
            kind: .sleep, gauge: nil, centerText: circularDuration(night.asleepMinutes), centerGlyph: nil, centerIsHealth: true, rectangular: lines,
            stages: night.stages, inline: inline, link: link, accessibilityLabel: spoken
        )
    }

    // MARK: Quality

    private static func quality(snapshot: WidgetSnapshot, age: String?, format: WidgetFormat, link: WatchLink) -> WatchComplicationContent {
        guard let night = snapshot.lastNight else {
            return message(
                .quality, glyph: "moon.zzz", lines: ["No sleep recorded", "last night"], inline: "No sleep last night", spoken: WatchCopy.noSleep, link: link)
        }
        guard let score = night.quality else {
            // Numbers for the night, but no score for it: never one made up.
            return WatchComplicationContent(
                kind: .quality, gauge: nil, centerText: "–", centerGlyph: nil, centerIsHealth: false,
                rectangular: [[.text("Sleep quality")], [.text("No score for last night")]],
                stages: nil, inline: [.text("Sleep quality - none")], link: link, accessibilityLabel: "Sleep quality: no score for last night"
            )
        }
        let duration = WidgetFormat.compactDuration(night.asleepMinutes)
        let lines: [[WidgetLockPiece]] = [[.health("Sleep quality \(score)")], [.health(age ?? duration)]]
        let spoken = "Sleep quality \(score)" + (age.map { ". \($0)" } ?? "")
        return WatchComplicationContent(
            kind: .quality, gauge: Double(score) / 100, centerText: "\(score)", centerGlyph: nil, centerIsHealth: true, rectangular: lines, stages: nil,
            inline: [.health("Sleep quality \(score)")], link: link, accessibilityLabel: spoken
        )
    }

    // MARK: Bedtime

    private static func bedtime(snapshot: WidgetSnapshot, input: WatchPageInput, link: WatchLink) -> WatchComplicationContent {
        let format = input.format
        let entry = WidgetTimelineBuilder.entry(for: snapshot, at: input.now, calendar: format.calendar)
        let time = format.clock(minutesSinceMidnight: snapshot.plan.bedtimeMinutes)
        let wake = "Wake \(format.clock(minutesSinceMidnight: snapshot.plan.wakeMinutes))"
        // The circle's number is the time without its period ("11:00"): the period is the unit and has no room.
        let center = format.splitClock(time).time
        var rectangular: [[WidgetLockPiece]]
        var inline: [WidgetLockPiece]
        var spoken: String
        if entry.mode == .evening, let bedtime = entry.bedtime, bedtime > input.now {
            rectangular = [[.text("Bedtime \(time)")], [.text("in "), .countdown(bedtime)]]
            inline = [.text("Bedtime in "), .countdown(bedtime)]
            spoken = "Bedtime \(time)"
        } else if entry.mode == .evening {
            rectangular = [[.text("Bedtime was \(time)")], [.text(wake)]]
            inline = [.text("Bedtime was \(time)")]
            spoken = "Bedtime was \(time)"
        } else {
            rectangular = [[.text("Bedtime \(time)")], [.text(wake)]]
            inline = [.text("Bedtime \(time)")]
            spoken = "Bedtime \(time)"
        }
        return WatchComplicationContent(
            kind: .bedtime, gauge: nil, centerText: center, centerGlyph: "moon.stars.fill", centerIsHealth: false, rectangular: rectangular, stages: nil,
            inline: inline, link: link, accessibilityLabel: spoken
        )
    }
}

// MARK: - When it changes, and how much the Smart Stack wants it

public nonisolated enum WatchComplicationSchedule {
    /// The moments a complication changes from `now`: now, each mode boundary (evening starts, bedtime, 4 AM) in the next twelve hours, and, while the
    /// numbers are old, every hour so their age stays true. The countdown text counts by itself. The same dates the iPhone's widgets use.
    public static func dates(snapshot: WidgetSnapshot?, now: Date, calendar: Calendar) -> WidgetTimelinePlan {
        WidgetTimelineBuilder.build(snapshot: snapshot, now: now, calendar: calendar)
    }

    /// How much the Smart Stack should want `kind` at `date`: Recovery, Sleep and Sleep quality in the morning window (the wake time's half hour before to
    /// three hours after), Bedtime in the evening hour (the hour before bedtime and half an hour after); idle otherwise, and always idle with no summary.
    public static func relevance(_ kind: WatchComplicationKind, at date: Date, snapshot: WidgetSnapshot?, calendar: Calendar) -> WidgetRelevanceScore {
        guard let snapshot, !WatchGate.isLocked(kind, tier: snapshot.effectiveTier(at: date)) else { return .idle }
        switch kind {
        case .recovery, .sleep, .quality: return WidgetClock.morningRelevance(at: date, plan: snapshot.plan, calendar: calendar)
        case .bedtime: return WidgetClock.eveningRelevance(at: date, plan: snapshot.plan, calendar: calendar)
        }
    }

    /// The window the Smart Stack is told about for `kind` (its `RelevantContext`): the morning window or the evening hour, as dates.
    public static func window(_ kind: WatchComplicationKind, snapshot: WidgetSnapshot?, from date: Date, calendar: Calendar) -> DateInterval? {
        guard let snapshot, !WatchGate.isLocked(kind, tier: snapshot.effectiveTier(at: date)) else { return nil }
        switch kind {
        case .recovery, .sleep, .quality: return WidgetClock.morningWindow(snapshot.plan, from: date, calendar: calendar)
        case .bedtime: return WidgetClock.eveningWindow(snapshot.plan, from: date, calendar: calendar)
        }
    }
}
