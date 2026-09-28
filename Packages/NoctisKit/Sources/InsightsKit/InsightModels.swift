import Foundation
import RecoveryKit
import SleepKit

public enum InsightKind: String, Sendable, CaseIterable, Codable {
    /// Last night's sleep duration differs from baseline by 30+ minutes.
    case sleepDurationShift
    /// Last night's bedtime differs from baseline by 30+ minutes.
    case bedtimeShift
    /// 5+ nights in a row, ending last night, within 30 minutes of the
    /// typical bedtime.
    case consistentBedtime
}

/// The numbers an insight rests on, all in minutes.
public struct InsightEvidence: Sendable, Equatable {
    public let night: SleepNightKey
    /// Last night's value: minutes asleep, or bedtime as minutes after
    /// noon (11:00 PM = 660).
    public let value: Double
    /// The baseline it's compared with, in the same unit.
    public let baseline: Double
    /// `value − baseline`.
    public let delta: Double
    /// Valid nights behind the baseline.
    public let baselineNights: Int
    /// For `.consistentBedtime`: the nights in a row.
    public let streakNights: Int?
    /// For `.consistentBedtime`: the last `InsightEngine.streakWindowNights`
    /// nights, oldest first — true within 30 minutes of the typical
    /// bedtime, false outside it, nil with no sleep recorded.
    public let recentNights: [Bool?]

    public init(
        night: SleepNightKey,
        value: Double,
        baseline: Double,
        delta: Double,
        baselineNights: Int,
        streakNights: Int? = nil,
        recentNights: [Bool?] = []
    ) {
        self.night = night
        self.value = value
        self.baseline = baseline
        self.delta = delta
        self.baselineNights = baselineNights
        self.streakNights = streakNights
        self.recentNights = recentNights
    }
}

/// One observation about last night against the person's own baseline:
/// what kind it is and the numbers it rests on. No sentences — Home words
/// it (and draws its evidence). Descriptive only: it never claims a cause.
public struct Insight: Sendable, Equatable {
    public let kind: InsightKind
    public let evidence: InsightEvidence

    public init(kind: InsightKind, evidence: InsightEvidence) {
        self.kind = kind
        self.evidence = evidence
    }
}
