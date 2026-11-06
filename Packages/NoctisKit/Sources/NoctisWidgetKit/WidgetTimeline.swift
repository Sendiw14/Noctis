import Foundation

// What the widgets show and when it changes (APP_RULES.md R44, R45). Pure: a snapshot, a date and a calendar in, entries out.
// No `Date()`, no I/O, so every boundary, the midnight crossing and a daylight saving change are unit tests.

/// Day or evening, the way Home decides it: evening from three hours before bedtime until 4 AM.
public enum WidgetMode: String, Sendable, Equatable {
    case day
    case evening
}

/// What an entry is about, before any wording.
public enum WidgetScene: Equatable, Sendable {
    /// No snapshot (the app has not run, or the file is another version's).
    case noSnapshot
    /// The snapshot is for an earlier day: yesterday's numbers are never shown as today's (R45).
    case waiting
    /// Numbers for today (or for the evening of today), in the snapshot's own state.
    case ready
}

/// How much the Smart Stack should want this entry (`TimelineEntryRelevance`): the score and for how long.
public struct WidgetRelevanceScore: Equatable, Sendable {
    public var score: Float
    public var duration: TimeInterval

    public init(score: Float, duration: TimeInterval) {
        self.score = score
        self.duration = duration
    }

    /// The score when nothing is going on.
    public static let idle = WidgetRelevanceScore(score: 10, duration: 0)
}

/// One moment of a widget's timeline, resolved: the snapshot, what it means at this date, and the real times a countdown needs.
public struct WidgetEntryModel: Equatable, Sendable {
    public var date: Date
    public var mode: WidgetMode
    public var scene: WidgetScene
    public var snapshot: WidgetSnapshot?
    /// The bedtime this entry counts toward (day) or from (evening, after it has passed).
    public var bedtime: Date?
    /// Hours old, when the snapshot is stale: its own age plus the time since it was made.
    public var staleHours: Int?
    public var relevance: WidgetRelevanceScore
    /// The widget gallery's preview: sample numbers, tagged "Sample" (an explicit R13 exception; never a real timeline).
    public var isPreview: Bool

    public init(
        date: Date, mode: WidgetMode, scene: WidgetScene, snapshot: WidgetSnapshot?, bedtime: Date? = nil, staleHours: Int? = nil,
        relevance: WidgetRelevanceScore = .idle, isPreview: Bool = false
    ) {
        self.date = date
        self.mode = mode
        self.scene = scene
        self.snapshot = snapshot
        self.bedtime = bedtime
        self.staleHours = staleHours
        self.relevance = relevance
        self.isPreview = isPreview
    }
}

/// The widgets' clock: which mode it is, where tonight's bedtime falls, and when the mode changes next.
public enum WidgetClock {
    /// Evening starts this long before bedtime.
    public static let eveningLeadMinutes = 180
    /// Evening ends here (4 AM), and a new day starts.
    public static let eveningEndMinutes = WidgetDay.startMinutes

    static func wrap(_ minutes: Int) -> Int { ((minutes % 1440) + 1440) % 1440 }

    public static func eveningStartMinutes(_ plan: WidgetPlan) -> Int { wrap(plan.bedtimeMinutes - eveningLeadMinutes) }

    static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        return (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
    }

    static func components(_ minutes: Int) -> DateComponents {
        DateComponents(hour: wrap(minutes) / 60, minute: wrap(minutes) % 60, second: 0)
    }

    /// Evening from three hours before bedtime until 4 AM; day otherwise. The same rule as Home's, which a test holds it to.
    public static func mode(at date: Date, plan: WidgetPlan, calendar: Calendar) -> WidgetMode {
        let minute = minuteOfDay(date, calendar)
        let start = eveningStartMinutes(plan)
        let end = eveningEndMinutes
        let inEvening = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
        return inEvening ? .evening : .day
    }

    /// The first moment at or after `date` when the clock reads `minutes`.
    static func next(_ minutes: Int, onOrAfter date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: date.addingTimeInterval(-1), matching: components(minutes), matchingPolicy: .nextTime)
    }

    /// The latest moment at or before `date` when the clock reads `minutes`.
    static func previous(_ minutes: Int, onOrBefore date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: date.addingTimeInterval(1), matching: components(minutes), matchingPolicy: .nextTime, direction: .backward)
    }

    /// The bedtime an entry at `date` is about. By day, the next one; in the evening, the one this evening is leading to (it may have
    /// passed, until 4 AM).
    public static func bedtime(at date: Date, mode: WidgetMode, plan: WidgetPlan, calendar: Calendar) -> Date? {
        switch mode {
        case .day:
            return next(plan.bedtimeMinutes, onOrAfter: date, calendar: calendar)
        case .evening:
            guard let start = previous(eveningStartMinutes(plan), onOrBefore: date, calendar: calendar) else { return nil }
            return next(plan.bedtimeMinutes, onOrAfter: start, calendar: calendar)
        }
    }

    /// The moments the surface changes, in order: evening starts, bedtime, a new day at 4 AM. Those after `date`, up to `horizon`.
    public static func boundaries(after date: Date, until horizon: Date, plan: WidgetPlan, calendar: Calendar) -> [Date] {
        let minutes = [eveningStartMinutes(plan), plan.bedtimeMinutes, eveningEndMinutes]
        var found: [Date] = []
        for minute in minutes {
            var cursor = date
            // A boundary can fall twice in a long horizon; collect each one inside it.
            while let moment = calendar.nextDate(after: cursor, matching: components(minute), matchingPolicy: .nextTime), moment <= horizon {
                found.append(moment)
                cursor = moment
            }
        }
        return Array(Set(found)).sorted()
    }

    /// How much the Smart Stack should want the widget at `date`: high in the morning window (from half an hour before the usual wake
    /// time to three hours after it) and in the evening hour (the hour before bedtime and half an hour after it).
    public static func relevance(at date: Date, plan: WidgetPlan, calendar: Calendar) -> WidgetRelevanceScore {
        let morning = morningRelevance(at: date, plan: plan, calendar: calendar)
        if morning != .idle { return morning }
        return eveningRelevance(at: date, plan: plan, calendar: calendar)
    }

    /// 100 in the morning window (from half an hour before the usual wake time to three hours after it), for as long as it lasts; idle otherwise.
    public static func morningRelevance(at date: Date, plan: WidgetPlan, calendar: Calendar) -> WidgetRelevanceScore {
        let minute = minuteOfDay(date, calendar)
        let offset = ((minute - plan.wakeMinutes + 720 + 1440) % 1440) - 720
        guard (-30...180).contains(offset) else { return .idle }
        return WidgetRelevanceScore(score: 100, duration: TimeInterval((180 - offset) * 60))
    }

    /// 90 in the evening hour (the hour before bedtime and half an hour after it), for as long as it lasts; idle otherwise.
    public static func eveningRelevance(at date: Date, plan: WidgetPlan, calendar: Calendar) -> WidgetRelevanceScore {
        let minute = minuteOfDay(date, calendar)
        let offset = ((minute - plan.bedtimeMinutes + 720 + 1440) % 1440) - 720
        guard (-60...30).contains(offset) else { return .idle }
        return WidgetRelevanceScore(score: 90, duration: TimeInterval((30 - offset) * 60))
    }
}

extension WidgetClock {
    /// The morning window and the evening hour, as dates, for the Smart Stack's `RelevantContext`: the next of each (or the one
    /// that is going on now), from half an hour before the usual wake time to three hours after it, and from an hour before
    /// bedtime to half an hour after it.
    public static func relevanceWindows(_ plan: WidgetPlan, from date: Date, calendar: Calendar) -> [DateInterval] {
        [morningWindow(plan, from: date, calendar: calendar), eveningWindow(plan, from: date, calendar: calendar)].compactMap { $0 }
    }

    /// The morning window: the one going on now, or the next one.
    public static func morningWindow(_ plan: WidgetPlan, from date: Date, calendar: Calendar) -> DateInterval? {
        window(start: plan.wakeMinutes - 30, length: 210 * 60, from: date, calendar: calendar)
    }

    /// The evening hour: the one going on now, or the next one.
    public static func eveningWindow(_ plan: WidgetPlan, from date: Date, calendar: Calendar) -> DateInterval? {
        window(start: plan.bedtimeMinutes - 60, length: 90 * 60, from: date, calendar: calendar)
    }

    private static func window(start minutes: Int, length: TimeInterval, from date: Date, calendar: Calendar) -> DateInterval? {
        if let began = previous(minutes, onOrBefore: date, calendar: calendar), began.addingTimeInterval(length) > date {
            return DateInterval(start: began, duration: length)
        }
        return next(minutes, onOrAfter: date, calendar: calendar).map { DateInterval(start: $0, duration: length) }
    }
}

/// A widget's timeline: entries to show and when to ask for more.
public struct WidgetTimelinePlan: Equatable, Sendable {
    public var entries: [WidgetEntryModel]
    /// When the system should ask again (`.after`): never beyond `WidgetTimelineBuilder.horizon` from `now`.
    public var reloadAfter: Date

    public init(entries: [WidgetEntryModel], reloadAfter: Date) {
        self.entries = entries
        self.reloadAfter = reloadAfter
    }
}

public enum WidgetTimelineBuilder {
    /// The longest a timeline looks ahead, and the longest before the system is asked again.
    public static let horizon: TimeInterval = 12 * 3600

    /// One entry as it reads at `date`: which scene, which mode, the countdown's real bedtime, how stale.
    public static func entry(for snapshot: WidgetSnapshot?, at date: Date, calendar: Calendar, isPreview: Bool = false) -> WidgetEntryModel {
        guard let snapshot else {
            return WidgetEntryModel(date: date, mode: .day, scene: .noSnapshot, snapshot: nil, isPreview: isPreview)
        }
        let mode = WidgetClock.mode(at: date, plan: snapshot.plan, calendar: calendar)
        // A snapshot for an earlier day is waiting for this one (a day starts at 4 AM). One for a later day (the person woke before
        // 4 AM) is already today's.
        let isCurrent = isPreview || snapshot.forDay >= WidgetDay.today(at: date, calendar: calendar)
        var staleHours: Int?
        if case .stale(let hours) = snapshot.state {
            staleHours = hours + max(Int(date.timeIntervalSince(snapshot.generatedAt) / 3600), 0)
        }
        return WidgetEntryModel(
            date: date, mode: mode, scene: isCurrent ? .ready : .waiting, snapshot: snapshot,
            bedtime: WidgetClock.bedtime(at: date, mode: mode, plan: snapshot.plan, calendar: calendar), staleHours: staleHours,
            relevance: WidgetClock.relevance(at: date, plan: snapshot.plan, calendar: calendar), isPreview: isPreview
        )
    }

    /// The timeline from `now`: an entry now, one at every mode boundary in the next twelve hours (evening starts, bedtime, 4 AM),
    /// and, while the numbers are stale, one an hour so their age stays true. The countdown text counts by itself.
    public static func build(snapshot: WidgetSnapshot?, now: Date, calendar: Calendar) -> WidgetTimelinePlan {
        let limit = now.addingTimeInterval(horizon)
        var dates = [now]
        var nextBoundary: Date?
        if let snapshot {
            dates += WidgetClock.boundaries(after: now, until: limit, plan: snapshot.plan, calendar: calendar)
            if case .stale = snapshot.state {
                dates += (1...11).map { now.addingTimeInterval(Double($0) * 3600) }
            }
            // A plan that runs out inside the horizon locks the widget at that moment, with the app closed (S1B-C01). Beyond it the next reload looks again.
            if let lock = snapshot.premiumLockDate, lock > now, lock < limit { dates.append(lock) }
            let last = dates.filter { $0 < limit }.max() ?? now
            nextBoundary = WidgetClock.boundaries(after: last, until: last.addingTimeInterval(36 * 3600), plan: snapshot.plan, calendar: calendar).first
        }
        let unique = Array(Set(dates.filter { $0 < limit })).sorted()
        let entries = unique.map { entry(for: snapshot, at: $0, calendar: calendar) }
        // Ask again at the next boundary after the last entry, but never later than the horizon, and never at or before the last entry.
        let lastEntry = unique.last ?? now
        let reload = min(max(min(nextBoundary ?? limit, limit), lastEntry.addingTimeInterval(60)), limit)
        return WidgetTimelinePlan(entries: entries, reloadAfter: reload)
    }

    /// The gallery's own entry: sample numbers, tagged. Never part of a real timeline.
    public static func previewEntry(_ snapshot: WidgetSnapshot, at date: Date, calendar: Calendar) -> WidgetEntryModel {
        var sample = snapshot
        sample.forDay = WidgetDay.today(at: date, calendar: calendar)
        sample.generatedAt = date
        return entry(for: sample, at: date, calendar: calendar, isPreview: true)
    }
}
