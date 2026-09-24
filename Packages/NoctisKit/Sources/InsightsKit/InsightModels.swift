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

    public init(night: SleepNightKey, value: Double, baseline: Double, delta: Double, baselineNights: Int, streakNights: Int? = nil) {
        self.night = night
        self.value = value
        self.baseline = baseline
        self.delta = delta
        self.baselineNights = baselineNights
        self.streakNights = streakNights
    }
}

/// One observation about last night, stated against the person's own
/// baseline. Descriptive only: it never claims a cause.
public struct Insight: Sendable, Equatable {
    public let kind: InsightKind
    public let title: String
    public let message: String
    public let evidence: InsightEvidence

    public init(kind: InsightKind, title: String, message: String, evidence: InsightEvidence) {
        self.kind = kind
        self.title = title
        self.message = message
        self.evidence = evidence
    }
}
