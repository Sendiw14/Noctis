import Foundation
import RecoveryKit
import SleepKit

// The typed numbers behind each insight. Never a sentence: the words are
// written by `InsightScreenBuilder` from these, the same way every time.
// A record is also the safe context the AI Coach will read later, so it
// holds derived values only: no raw HealthKit sample, source or device.

/// The stage a stage-share insight is about.
public enum InsightStage: String, Sendable, Codable, Hashable, CaseIterable {
    case deep
    case rem
}

/// Which heart signal a streak is about.
public enum InsightHeartSignal: String, Sendable, Codable, Hashable {
    case hrv
    case restingHeartRate
}

/// Rule 4: nights split by bedtime, and how they went.
public struct PatternEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    /// The nights looked at (60).
    public let windowNights: Int
    /// The person's median bedtime over the window, minutes after noon.
    public let medianBedtime: Double
    /// Nights 30+ minutes earlier / later than the median.
    public let earlyNights: Int
    public let lateNights: Int
    /// Each night's outcome (the mean of the continuity, stage-balance and
    /// HRV scores it has), oldest first.
    public let earlyValues: [Double]
    public let lateValues: [Double]
    public let earlyMean: Double
    public let lateMean: Double
    /// `earlyMean − lateMean`: positive when earlier nights scored higher.
    public let difference: Double
    /// `difference` over the pooled standard deviation, capped at ±99.
    public let effectSize: Double
    public let pooledSD: Double

    public init(
        night: SleepNightKey, windowNights: Int, medianBedtime: Double, earlyNights: Int, lateNights: Int,
        earlyValues: [Double], lateValues: [Double], earlyMean: Double, lateMean: Double,
        difference: Double, effectSize: Double, pooledSD: Double
    ) {
        self.night = night
        self.windowNights = windowNights
        self.medianBedtime = medianBedtime
        self.earlyNights = earlyNights
        self.lateNights = lateNights
        self.earlyValues = earlyValues
        self.lateValues = lateValues
        self.earlyMean = earlyMean
        self.lateMean = lateMean
        self.difference = difference
        self.effectSize = effectSize
        self.pooledSD = pooledSD
    }
}

/// Rule 5: the Recovery trend has pointed one way for days.
public struct RecoveryDirectionEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    public let direction: RecoveryTrendDirection
    /// Days in a row, ending on `night`, on which the 7-night trend was this
    /// direction.
    public let consecutiveDays: Int
    public let pointsPerWeek: Double
    /// The 7-night window's first and last scores.
    public let startScore: Int
    public let latestScore: Int
    /// The last 14 days' scores, oldest first; nil where a day has none.
    public let recentScores: [Int?]

    public init(
        night: SleepNightKey, direction: RecoveryTrendDirection, consecutiveDays: Int, pointsPerWeek: Double,
        startScore: Int, latestScore: Int, recentScores: [Int?]
    ) {
        self.night = night
        self.direction = direction
        self.consecutiveDays = consecutiveDays
        self.pointsPerWeek = pointsPerWeek
        self.startScore = startScore
        self.latestScore = latestScore
        self.recentScores = recentScores
    }
}

/// Rule 6: HRV below, or resting heart rate above, its normal range for
/// several nights in a row.
public struct HeartSignalEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    public let signal: InsightHeartSignal
    public let consecutiveNights: Int
    /// Last night's value, and the baseline and normal range it is judged by
    /// (ms or bpm).
    public let value: Double
    public let baseline: Double
    public let rangeLow: Double
    public let rangeHigh: Double
    public let baselineNights: Int
    /// The last 14 nights' values, oldest first.
    public let recentValues: [Double?]

    public init(
        night: SleepNightKey, signal: InsightHeartSignal, consecutiveNights: Int, value: Double, baseline: Double,
        rangeLow: Double, rangeHigh: Double, baselineNights: Int, recentValues: [Double?]
    ) {
        self.night = night
        self.signal = signal
        self.consecutiveNights = consecutiveNights
        self.value = value
        self.baseline = baseline
        self.rangeLow = rangeLow
        self.rangeHigh = rangeHigh
        self.baselineNights = baselineNights
        self.recentValues = recentValues
    }
}

/// Rule 7: how steady bedtime was over the last 14 nights against the 14
/// before.
public struct ConsistencyChangeEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    /// Bedtime spread (sample SD, minutes).
    public let recentSD: Double
    public let previousSD: Double
    /// `recentSD − previousSD`: negative when steadier.
    public let delta: Double
    public let recentNights: Int
    public let previousNights: Int
    /// The last 28 bedtimes, oldest first (minutes after noon).
    public let bedtimes: [Double?]

    public init(
        night: SleepNightKey, recentSD: Double, previousSD: Double, delta: Double,
        recentNights: Int, previousNights: Int, bedtimes: [Double?]
    ) {
        self.night = night
        self.recentSD = recentSD
        self.previousSD = previousSD
        self.delta = delta
        self.recentNights = recentNights
        self.previousNights = previousNights
        self.bedtimes = bedtimes
    }
}

/// Rule 8: sleep against need over 7 nights.
public struct BalanceEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    /// Minutes asleep minus need, summed over the window: negative is behind.
    public let minutes: Double
    public let recordedNights: Int
    public let needMinutes: Double
    /// The last 7 nights' minutes asleep, oldest first.
    public let nightlyMinutes: [Double?]

    public init(night: SleepNightKey, minutes: Double, recordedNights: Int, needMinutes: Double, nightlyMinutes: [Double?]) {
        self.night = night
        self.minutes = minutes
        self.recordedNights = recordedNights
        self.needMinutes = needMinutes
        self.nightlyMinutes = nightlyMinutes
    }
}

/// Rule 9: weekend bedtimes against weekday ones.
public struct WeekendEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    public let windowNights: Int
    public let weekendMedian: Double
    public let weekdayMedian: Double
    /// `weekendMedian − weekdayMedian`.
    public let delta: Double
    public let weekendNights: Int
    public let weekdayNights: Int

    public init(night: SleepNightKey, windowNights: Int, weekendMedian: Double, weekdayMedian: Double, delta: Double, weekendNights: Int, weekdayNights: Int) {
        self.night = night
        self.windowNights = windowNights
        self.weekendMedian = weekendMedian
        self.weekdayMedian = weekdayMedian
        self.delta = delta
        self.weekendNights = weekendNights
        self.weekdayNights = weekdayNights
    }
}

/// Rule 10: a stage's share of last night against usual.
public struct StageShareEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    public let stage: InsightStage
    /// Shares of time asleep, 0...1.
    public let share: Double
    public let usual: Double
    /// `(share − usual) × 100`.
    public let deltaPoints: Double
    public let usualNights: Int

    public init(night: SleepNightKey, stage: InsightStage, share: Double, usual: Double, deltaPoints: Double, usualNights: Int) {
        self.night = night
        self.stage = stage
        self.share = share
        self.usual = usual
        self.deltaPoints = deltaPoints
        self.usualNights = usualNights
    }
}

/// Rule 11: last night beat every other night in the window.
public struct RecordEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    /// Minutes (longest night), bedtime spread in minutes (steadiest week),
    /// a score (recovery) or bpm (resting heart rate).
    public let value: Double
    /// The best of the other nights in the window, before this one.
    public let previousBest: Double
    /// 30 or 90 nights.
    public let scope: Int
    /// Nights with a value in the window.
    public let nightsInWindow: Int

    public init(night: SleepNightKey, value: Double, previousBest: Double, scope: Int, nightsInWindow: Int) {
        self.night = night
        self.value = value
        self.previousBest = previousBest
        self.scope = scope
        self.nightsInWindow = nightsInWindow
    }
}

/// Rule 12: the person has recorded enough nights to unlock a kind of
/// insight.
public struct MilestoneEvidence: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    /// 7, 14 or 30.
    public let milestone: Int
    public let nightsRecorded: Int

    public init(night: SleepNightKey, milestone: Int, nightsRecorded: Int) {
        self.night = night
        self.milestone = milestone
        self.nightsRecorded = nightsRecorded
    }
}

/// What an insight rests on, by rule.
public enum InsightEvidenceData: Sendable, Equatable, Codable {
    /// Rules 1-3: last night against the baseline (v1's evidence).
    case baseline(InsightEvidence)
    case pattern(PatternEvidence)
    case recoveryDirection(RecoveryDirectionEvidence)
    case heartSignal(HeartSignalEvidence)
    case consistencyChange(ConsistencyChangeEvidence)
    case balance(BalanceEvidence)
    case weekend(WeekendEvidence)
    case stageShare(StageShareEvidence)
    case record(RecordEvidence)
    case milestone(MilestoneEvidence)

    /// The night the evidence ends on.
    public var night: SleepNightKey {
        switch self {
        case .baseline(let e): e.night
        case .pattern(let e): e.night
        case .recoveryDirection(let e): e.night
        case .heartSignal(let e): e.night
        case .consistencyChange(let e): e.night
        case .balance(let e): e.night
        case .weekend(let e): e.night
        case .stageShare(let e): e.night
        case .record(let e): e.night
        case .milestone(let e): e.night
        }
    }

    /// The one number whose change makes an insight "different evidence"
    /// for fatigue: a shift's minutes, a streak's nights, a pattern's
    /// points, a trend's slope, a signal's distance from baseline, a
    /// spread's change, a balance's minutes, a weekend gap, a share's
    /// points, a record's value, a milestone's nights.
    public var magnitude: Double {
        switch self {
        case .baseline(let e): e.streakNights.map(Double.init) ?? abs(e.delta)
        case .pattern(let e): abs(e.difference)
        case .recoveryDirection(let e): abs(e.pointsPerWeek)
        case .heartSignal(let e): abs(e.value - e.baseline)
        case .consistencyChange(let e): abs(e.delta)
        case .balance(let e): abs(e.minutes)
        case .weekend(let e): abs(e.delta)
        case .stageShare(let e): abs(e.deltaPoints)
        case .record(let e): abs(e.value)
        case .milestone(let e): Double(e.milestone)
        }
    }

    /// The evidence's numbers as text, rounded, for the stable id.
    var canonical: String {
        func n(_ value: Double, _ places: Double = 0) -> String {
            let scale = pow(10, places)
            return String(Int((value * scale).rounded()))
        }
        func list(_ values: [Double?]) -> String { values.map { $0.map { n($0) } ?? "-" }.joined(separator: ",") }
        switch self {
        case .baseline(let e):
            return "baseline|\(e.night)|\(n(e.value))|\(n(e.baseline))|\(e.streakNights ?? 0)|\(e.recentNights.map { $0.map { $0 ? "1" : "0" } ?? "-" }.joined())"
        case .pattern(let e):
            return "pattern|\(e.night)|\(e.earlyNights)|\(e.lateNights)|\(n(e.earlyMean, 1))|\(n(e.lateMean, 1))|\(n(e.medianBedtime))"
        case .recoveryDirection(let e):
            return "recovery|\(e.night)|\(e.direction.rawValue)|\(e.consecutiveDays)|\(n(e.pointsPerWeek, 1))|\(e.startScore)|\(e.latestScore)"
        case .heartSignal(let e):
            return "heart|\(e.night)|\(e.signal.rawValue)|\(e.consecutiveNights)|\(n(e.value))|\(n(e.baseline))"
        case .consistencyChange(let e):
            return "consistency|\(e.night)|\(n(e.recentSD))|\(n(e.previousSD))"
        case .balance(let e):
            return "balance|\(e.night)|\(n(e.minutes))|\(e.recordedNights)"
        case .weekend(let e):
            return "weekend|\(e.night)|\(n(e.weekendMedian))|\(n(e.weekdayMedian))|\(e.weekendNights)"
        case .stageShare(let e):
            return "stage|\(e.night)|\(e.stage.rawValue)|\(n(e.share, 3))|\(n(e.usual, 3))"
        case .record(let e):
            return "record|\(e.night)|\(n(e.value, 1))|\(n(e.previousBest, 1))|\(e.scope)"
        case .milestone(let e):
            return "milestone|\(e.night)|\(e.milestone)|\(e.nightsRecorded)"
        }
    }
}

/// One generated insight: a type, the numbers it rests on and how much to
/// trust and feature it. Stable: the same evidence always has the same id.
public struct InsightRecord: Sendable, Equatable, Codable, Identifiable {
    /// The type and a hash of the evidence: "bedtimeShift-3fa9c2d1".
    public let id: String
    public let type: InsightType
    public let category: InsightCategory
    public let generatedAt: Date
    /// The newest night the evidence covers.
    public let night: SleepNightKey
    public let evidence: InsightEvidenceData
    public let confidence: InsightConfidence
    /// 0...1: how recent (1 for the newest night).
    public let relevance: Double
    /// 0...1: how long since this type was last featured (1 for never).
    public let novelty: Double
    /// 0...1: how much a person can do about it.
    public let actionability: Double
    /// Nights of the person's own data behind it.
    public let nightsUsed: Int

    public init(
        type: InsightType, generatedAt: Date, evidence: InsightEvidenceData, confidence: InsightConfidence,
        relevance: Double = 1, novelty: Double = 1, nightsUsed: Int
    ) {
        self.id = "\(type.rawValue)-\(InsightHash.hex(evidence.canonical))"
        self.type = type
        self.category = type.category
        self.generatedAt = generatedAt
        self.night = evidence.night
        self.evidence = evidence
        self.confidence = confidence
        self.relevance = relevance
        self.novelty = novelty
        self.actionability = type.actionability
        self.nightsUsed = nightsUsed
    }

    public var magnitude: Double { evidence.magnitude }

    func with(novelty: Double) -> InsightRecord {
        with(relevance: relevance, novelty: novelty)
    }

    func with(relevance: Double, novelty: Double) -> InsightRecord {
        InsightRecord(type: type, generatedAt: generatedAt, evidence: evidence, confidence: confidence, relevance: relevance, novelty: novelty, nightsUsed: nightsUsed)
    }

    /// The type, and for a stage-share the stage: what the Recent list keeps
    /// one of.
    public var kindKey: String {
        if case .stageShare(let e) = evidence { return "\(type.rawValue)|\(e.stage.rawValue)" }
        return type.rawValue
    }

    /// What makes two records "the same insight about the same night": a
    /// type's night, plus the stage for a stage-share. Generated once per
    /// slot; the stored one is never rewritten.
    public var slot: String {
        if case .stageShare(let e) = evidence { return "\(type.rawValue)|\(night)|\(e.stage.rawValue)" }
        return "\(type.rawValue)|\(night)"
    }
}

/// FNV-1a over a string: the same on every launch (Swift's `Hasher` is
/// seeded per process, so it can't name a stored record).
enum InsightHash {
    static func hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash ^ (hash >> 32)))
    }
}
