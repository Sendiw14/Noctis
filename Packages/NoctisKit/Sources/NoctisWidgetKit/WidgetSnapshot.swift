import Foundation

// The one thing widgets (and any other extension) read (APP_RULES.md R44): a small file the app writes after it has looked
// at Health. It holds the least that can draw the surfaces: derived numbers and clock times. No sample times, no source
// names, no Journal, no Coach text. An extension never touches HealthKit, SwiftData or Coach.

/// A calendar day on the person's own clock, written "2026-10-04".
public struct WidgetDay: Codable, Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day `date` falls on.
    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// A widget's day starts at 4 AM, the hour Home's evening ends, so the small hours still belong to the evening before.
    public static let startMinutes = 4 * 60

    /// The widgets' day at `date`: before 4 AM it is still yesterday's.
    public static func today(at date: Date, calendar: Calendar) -> WidgetDay {
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        guard minute < startMinutes, let earlier = calendar.date(byAdding: .day, value: -1, to: date) else { return WidgetDay(date, calendar: calendar) }
        return WidgetDay(earlier, calendar: calendar)
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (lhs: WidgetDay, rhs: WidgetDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a day: \(text)"))
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// How much the widgets have to go on. Written as one short word ("full", "learning:3", "stale:14").
public enum WidgetDataState: Equatable, Sendable, Codable {
    /// Recovery, last night and the heart factors.
    case full
    /// Recovery and last night from sleep alone: no HRV or resting heart rate.
    case sleepOnly
    /// Fewer than five nights so far: no score yet.
    case learning(nightsSoFar: Int)
    /// Health holds nothing NOCTIS can use yet.
    case empty
    /// Apple Health has not been connected.
    case noPermission
    /// The newest Health data is old; the numbers are the last known ones, `hours` old when the snapshot was made.
    case stale(hours: Int)
    /// Recent data, but no sleep ended last night.
    case gap

    public var token: String {
        switch self {
        case .full: "full"
        case .sleepOnly: "sleepOnly"
        case .learning(let nights): "learning:\(nights)"
        case .empty: "empty"
        case .noPermission: "noPermission"
        case .stale(let hours): "stale:\(hours)"
        case .gap: "gap"
        }
    }

    public init?(token: String) {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let number = parts.count == 2 ? Int(parts[1]) : nil
        switch (parts.first, number) {
        case ("full", nil): self = .full
        case ("sleepOnly", nil): self = .sleepOnly
        case ("learning", let nights?): self = .learning(nightsSoFar: max(nights, 0))
        case ("empty", nil): self = .empty
        case ("noPermission", nil): self = .noPermission
        case ("stale", let hours?): self = .stale(hours: max(hours, 0))
        case ("gap", nil): self = .gap
        default: return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let state = WidgetDataState(token: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a state: \(text)"))
        }
        self = state
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(token)
    }

    /// Whether the snapshot can show a recovery score.
    public var showsScore: Bool {
        switch self {
        case .full, .sleepOnly, .stale: true
        case .learning, .empty, .noPermission, .gap: false
        }
    }
}

/// A recovery factor, in the order the ring draws them.
public enum WidgetFactorKind: Int, Codable, Sendable, CaseIterable {
    case sleepDuration = 0
    case hrv = 1
    case restingHeartRate = 2
    case sleepConsistency = 3
}

public enum WidgetConfidence: Int, Codable, Sendable, Comparable {
    case low = 0
    case moderate = 1
    case high = 2

    public static func < (lhs: WidgetConfidence, rhs: WidgetConfidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One factor's arc of the ring: its share of the ring and how full it is.
public struct WidgetRingSegment: Codable, Equatable, Sendable {
    public var kind: WidgetFactorKind
    /// Share of the ring (0...1), the factor's renormalized weight.
    public var weight: Double
    /// How full the arc is (0...1): the factor's score over 100.
    public var fraction: Double

    public init(kind: WidgetFactorKind, weight: Double, fraction: Double) {
        self.kind = kind
        self.weight = (weight * 1000).rounded() / 1000
        self.fraction = (fraction * 1000).rounded() / 1000
    }

    enum CodingKeys: String, CodingKey { case kind = "k", weight = "w", fraction = "f" }
}

public struct WidgetRecovery: Codable, Equatable, Sendable {
    /// 0...100.
    public var score: Int
    /// Today's score less your usual, when there is a usual.
    public var delta: Int?
    public var confidence: WidgetConfidence
    /// The factors that were scored, in ring order.
    public var ring: [WidgetRingSegment]

    public init(score: Int, delta: Int?, confidence: WidgetConfidence, ring: [WidgetRingSegment]) {
        self.score = score
        self.delta = delta
        self.confidence = confidence
        self.ring = ring
    }

    enum CodingKeys: String, CodingKey { case score = "s", delta = "d", confidence = "c", ring = "r" }
}

/// Minutes asleep by stage, awake excluded.
public struct WidgetStages: Codable, Equatable, Sendable {
    public var deep: Int
    public var core: Int
    public var rem: Int

    public init(deep: Int, core: Int, rem: Int) {
        self.deep = deep
        self.core = core
        self.rem = rem
    }

    public var total: Int { deep + core + rem }
}

public struct WidgetNight: Codable, Equatable, Sendable {
    public var asleepMinutes: Int
    /// Nil when the night's sources gave no stages.
    public var stages: WidgetStages?
    /// Clock times, minutes since midnight.
    public var bedtimeMinutes: Int
    public var wakeMinutes: Int
    /// The Sleep tab's number for the same night; nil while learning or when nothing could be scored.
    public var quality: Int?

    public init(asleepMinutes: Int, stages: WidgetStages?, bedtimeMinutes: Int, wakeMinutes: Int, quality: Int?) {
        self.asleepMinutes = asleepMinutes
        self.stages = stages
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
        self.quality = quality
    }

    enum CodingKeys: String, CodingKey { case asleepMinutes = "a", stages = "st", bedtimeMinutes = "b", wakeMinutes = "w", quality = "q" }
}

/// Last night's two heart numbers, when Health had them.
public struct WidgetFactors: Codable, Equatable, Sendable {
    /// Heart rate variability (SDNN), milliseconds.
    public var hrv: Int?
    /// Resting heart rate, beats per minute.
    public var restingHeartRate: Int?

    public init(hrv: Int?, restingHeartRate: Int?) {
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
    }

    public var isEmpty: Bool { hrv == nil && restingHeartRate == nil }

    enum CodingKeys: String, CodingKey { case hrv, restingHeartRate = "rhr" }
}

/// Where a heart factor sits against the person's own normal range (by value, not by goodness): the iPhone's `RecoveryRange`.
public enum WidgetFactorRange: Int, Codable, Sendable, Equatable {
    case below = -1
    case within = 0
    case above = 1
}

/// One of the four recovery factors as the iPhone scored it, for the Watch (snapshot v2). Only the factors that exist are present.
public struct WidgetRecoveryFactor: Codable, Equatable, Sendable {
    public var kind: WidgetFactorKind
    /// 0...100.
    public var score: Int
    /// Last night's value: minutes asleep; minutes bedtime and wake were off usual; HRV in ms; resting heart rate in bpm.
    public var value: Double
    /// What `value` is compared with; nil when there is none yet (and for sleep consistency, which is already a distance).
    public var baseline: Double?
    /// Against the normal range: HRV and resting heart rate only, so the Watch uses the iPhone's words and never works the range out.
    public var range: WidgetFactorRange?

    public init(kind: WidgetFactorKind, score: Int, value: Double, baseline: Double?, range: WidgetFactorRange? = nil) {
        self.kind = kind
        self.score = min(max(score, 0), 100)
        self.value = (value * 10).rounded() / 10
        self.baseline = baseline.map { ($0 * 10).rounded() / 10 }
        self.range = range
    }

    enum CodingKeys: String, CodingKey { case kind = "k", score = "s", value = "v", baseline = "b", range = "r" }
}

/// What decides which surface is showing and when it changes.
public struct WidgetPlan: Codable, Equatable, Sendable {
    /// The usual wake time, minutes since midnight.
    public var wakeMinutes: Int
    public var needMinutes: Int
    /// The bedtime, or the middle of the window, minutes since midnight.
    public var bedtimeMinutes: Int
    /// The bedtime window's ends when there is one (a single bedtime has none).
    public var windowStartMinutes: Int?
    public var windowEndMinutes: Int?

    public init(wakeMinutes: Int, needMinutes: Int, bedtimeMinutes: Int, windowStartMinutes: Int? = nil, windowEndMinutes: Int? = nil) {
        self.wakeMinutes = wakeMinutes
        self.needMinutes = needMinutes
        self.bedtimeMinutes = bedtimeMinutes
        self.windowStartMinutes = windowStartMinutes
        self.windowEndMinutes = windowEndMinutes
    }

    public var hasWindow: Bool { windowStartMinutes != nil && windowEndMinutes != nil }

    enum CodingKeys: String, CodingKey {
        case wakeMinutes = "w", needMinutes = "n", bedtimeMinutes = "b", windowStartMinutes = "ws", windowEndMinutes = "we"
    }
}

public struct WidgetAlarm: Codable, Equatable, Sendable {
    /// When it rings, minutes since midnight.
    public var minutes: Int
    public var isOn: Bool

    public init(minutes: Int, isOn: Bool) {
        self.minutes = minutes
        self.isOn = isOn
    }

    enum CodingKeys: String, CodingKey { case minutes = "m", isOn = "on" }
}

/// Everything the widgets and the Apple Watch draw, versioned and under 3 KB.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Bump when a change would break an older reader. A reader that sees another version shows "Open NOCTIS". Version 2 added the four
    /// recovery factors, the nights of history and the data epoch, for the Watch (APP_RULES.md R50).
    public static let currentVersion = 2
    /// The most the store will write (a snapshot is well under half of it).
    public static let maximumBytes = 3072
    /// Nights of sleep before a recovery score (the model's `learningNights`; a test holds the two together).
    public static let learningNights = 5

    public var version: Int
    /// The morning date the night ended: the day these numbers are for. With no night, the day the snapshot was made for.
    public var forDay: WidgetDay
    public var generatedAt: Date
    public var plan: WidgetPlan
    public var state: WidgetDataState
    public var recovery: WidgetRecovery?
    public var lastNight: WidgetNight?
    public var factors: WidgetFactors?
    public var alarm: WidgetAlarm?
    /// The four recovery factors that were scored, with their values and baselines (v2; empty when there is no score).
    public var recoveryFactors: [WidgetRecoveryFactor]
    /// Nights of sleep in the baseline window, 0...14 (v2).
    public var nightsOfHistory: Int
    /// Unix seconds of the last "Delete all NOCTIS data", 0 if never (v2). A Watch that sees a greater one than it holds wipes its copy.
    public var dataEpoch: Int64

    public init(
        version: Int = WidgetSnapshot.currentVersion, forDay: WidgetDay, generatedAt: Date, plan: WidgetPlan, state: WidgetDataState,
        recovery: WidgetRecovery? = nil, lastNight: WidgetNight? = nil, factors: WidgetFactors? = nil, alarm: WidgetAlarm? = nil,
        recoveryFactors: [WidgetRecoveryFactor] = [], nightsOfHistory: Int = 0, dataEpoch: Int64 = 0
    ) {
        self.version = version
        self.forDay = forDay
        self.generatedAt = generatedAt
        self.plan = plan
        self.state = state
        self.recovery = recovery
        self.lastNight = lastNight
        self.factors = factors
        self.alarm = alarm
        self.recoveryFactors = recoveryFactors
        self.nightsOfHistory = min(max(nightsOfHistory, 0), 14)
        self.dataEpoch = max(dataEpoch, 0)
    }

    enum CodingKeys: String, CodingKey {
        case version = "v", forDay = "day", generatedAt = "at", plan = "p", state = "st", recovery = "rec", lastNight = "n", factors = "f", alarm = "al"
        case recoveryFactors = "rf", nightsOfHistory = "nh", dataEpoch = "de"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try values.decode(Int.self, forKey: .version), forDay: try values.decode(WidgetDay.self, forKey: .forDay),
            generatedAt: try values.decode(Date.self, forKey: .generatedAt), plan: try values.decode(WidgetPlan.self, forKey: .plan),
            state: try values.decode(WidgetDataState.self, forKey: .state), recovery: try values.decodeIfPresent(WidgetRecovery.self, forKey: .recovery),
            lastNight: try values.decodeIfPresent(WidgetNight.self, forKey: .lastNight), factors: try values.decodeIfPresent(WidgetFactors.self, forKey: .factors),
            alarm: try values.decodeIfPresent(WidgetAlarm.self, forKey: .alarm),
            recoveryFactors: try values.decodeIfPresent([WidgetRecoveryFactor].self, forKey: .recoveryFactors) ?? [],
            nightsOfHistory: try values.decodeIfPresent(Int.self, forKey: .nightsOfHistory) ?? 0,
            dataEpoch: try values.decodeIfPresent(Int64.self, forKey: .dataEpoch) ?? 0
        )
    }

    /// The same snapshot for the next epoch (delete-all), with everything else as it was: used only to stamp a snapshot.
    public func stamped(epoch: Int64) -> WidgetSnapshot {
        var copy = self
        copy.dataEpoch = max(epoch, 0)
        return copy
    }

    // MARK: Coding

    /// The bytes written to the file: sorted keys, the time as whole seconds.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int(date.timeIntervalSince1970.rounded()))
        }
        return try encoder.encode(self)
    }

    /// The snapshot in `data`; nil when it is not one, or is another version.
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            Date(timeIntervalSince1970: TimeInterval(try decoder.singleValueContainer().decode(Int.self)))
        }
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data), snapshot.version == currentVersion else { return nil }
        return snapshot
    }
}
