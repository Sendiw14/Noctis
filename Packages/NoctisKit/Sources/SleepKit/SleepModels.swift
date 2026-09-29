import Foundation
import HealthProviding

/// One stretch of the resolved stage timeline. Timelines never overlap.
public struct SleepStageSegment: Sendable, Identifiable, Equatable {
    public let stage: SleepStageValue
    public let interval: DateInterval

    public init(stage: SleepStageValue, interval: DateInterval) {
        self.stage = stage
        self.interval = interval
    }

    public var id: Date { interval.start }
}

public enum SleepSessionKind: Sendable, Equatable {
    /// The one main sleep of a night.
    case main
    /// Any other sleep, kept separate from the night's totals.
    case nap
}

/// Durations for one session, in seconds. `asleep` is core + deep + REM +
/// unspecified: unspecified asleep time counts toward total sleep but
/// toward no stage.
public struct SleepTotals: Sendable, Equatable, Codable {
    public let asleep: TimeInterval
    public let inBed: TimeInterval
    public let awake: TimeInterval
    public let core: TimeInterval
    public let deep: TimeInterval
    public let rem: TimeInterval
    public let unspecified: TimeInterval

    public init(asleep: TimeInterval, inBed: TimeInterval, awake: TimeInterval, core: TimeInterval, deep: TimeInterval, rem: TimeInterval, unspecified: TimeInterval) {
        self.asleep = asleep
        self.inBed = inBed
        self.awake = awake
        self.core = core
        self.deep = deep
        self.rem = rem
        self.unspecified = unspecified
    }
}

/// How much of a session the data actually covers.
public struct SleepDataCompleteness: Sendable, Equatable, Codable {
    /// Share (0...1) of the session's span, first sample to last, that
    /// some stage sample covers. Below 1 means the source left gaps.
    public let coverage: Double
    /// The source recorded sleep stages (core, deep or REM), not only
    /// "asleep".
    public let hasStageDetail: Bool
    /// An in-bed sample overlaps the session.
    public let hasInBedData: Bool

    public init(coverage: Double, hasStageDetail: Bool, hasInBedData: Bool) {
        self.coverage = coverage
        self.hasStageDetail = hasStageDetail
        self.hasInBedData = hasInBedData
    }
}

/// One sleep, built by `SleepSessionEngine` from resolved samples.
public struct SleepSession: Sendable, Identifiable, Equatable {
    public let kind: SleepSessionKind
    public let night: SleepNightKey
    /// Start of the first stage sample (including time awake before
    /// falling asleep).
    public let bedtime: Date
    /// End of the last asleep sample.
    public let wakeTime: Date
    /// The zone the session was recorded in; clock times are read in it.
    public let timeZone: TimeZone
    public let timeline: [SleepStageSegment]
    public let totals: SleepTotals
    /// Breaks of a minute or more between asleep stretches (an awake
    /// stage or a gap in the data).
    public let awakenings: Int
    /// Asleep ÷ in bed. Only valid when the data can show time awake (an
    /// awake stage or in-bed samples); nil otherwise, since a source that
    /// records only "asleep" would always read 100%.
    public let efficiency: Double?
    public let completeness: SleepDataCompleteness
    public let sourceName: String

    public init(
        kind: SleepSessionKind,
        night: SleepNightKey,
        bedtime: Date,
        wakeTime: Date,
        timeZone: TimeZone,
        timeline: [SleepStageSegment],
        totals: SleepTotals,
        awakenings: Int,
        efficiency: Double?,
        completeness: SleepDataCompleteness,
        sourceName: String
    ) {
        self.kind = kind
        self.night = night
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.timeZone = timeZone
        self.timeline = timeline
        self.totals = totals
        self.awakenings = awakenings
        self.efficiency = efficiency
        self.completeness = completeness
        self.sourceName = sourceName
    }

    public var id: Date { bedtime }

    /// Bedtime as minutes after noon on the night's evening, local clock.
    public var bedtimeMinutesAfterNoon: Double { night.minutesAfterNoon(of: bedtime, in: timeZone) }
    /// Wake time as minutes after noon on the night's evening, local clock.
    public var wakeMinutesAfterNoon: Double { night.minutesAfterNoon(of: wakeTime, in: timeZone) }
}

/// Everything `SleepSessionEngine` found: complete main sleeps (one per
/// night) and complete naps.
public struct SleepHistory: Sendable, Equatable {
    /// One main sleep per night, oldest first.
    public let nights: [SleepSession]
    /// Every other sleep, oldest first.
    public let naps: [SleepSession]

    public init(nights: [SleepSession], naps: [SleepSession]) {
        self.nights = nights
        self.naps = naps
    }

    public static let empty = SleepHistory(nights: [], naps: [])

    public func night(_ key: SleepNightKey) -> SleepSession? {
        nights.first { $0.night == key }
    }

    /// "Last night": the most recent main sleep that ended no more than
    /// `window` before `now`. Nil when the newest night is older — a
    /// missed night never falls back to an earlier one.
    public func lastNight(asOf now: Date, within window: TimeInterval = 24 * 3600) -> SleepSession? {
        guard let newest = nights.filter({ $0.wakeTime <= now }).max(by: { $0.wakeTime < $1.wakeTime }) else { return nil }
        return now.timeIntervalSince(newest.wakeTime) <= window ? newest : nil
    }
}
