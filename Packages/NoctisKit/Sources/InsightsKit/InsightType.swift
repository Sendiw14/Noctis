import Foundation

/// The chips on the Insights tab.
public enum InsightCategory: String, Sendable, CaseIterable, Codable, Hashable {
    case sleep
    case recovery
    case timing
    case consistency
    case heart
    case longTerm

    public var title: String {
        switch self {
        case .sleep: "Sleep"
        case .recovery: "Recovery"
        case .timing: "Timing"
        case .consistency: "Consistency"
        case .heart: "Heart"
        case .longTerm: "Long-term"
        }
    }
}

public enum InsightConfidence: String, Sendable, CaseIterable, Codable, Hashable, Comparable {
    case low
    case moderate
    case high

    var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        }
    }

    public static func < (lhs: InsightConfidence, rhs: InsightConfidence) -> Bool { lhs.rank < rhs.rank }
}

/// Every kind of insight `InsightEngineV2` can produce: one per rule, the
/// records and the heart signals each in their own type so a person can hide
/// one without the other.
public enum InsightType: String, Sendable, CaseIterable, Codable, Hashable {
    // 1-3: about last night, against your baseline.
    case sleepDurationShift
    case bedtimeShift
    case consistentBedtime
    // 4: a pattern over 60 nights.
    case earlierBedtimePattern
    // 5
    case recoveryDirection
    // 6
    case hrvBelowRange
    case restingHeartRateAboveRange
    // 7
    case consistencyChange
    // 8
    case sleepBalance
    // 9
    case weekendShift
    // 10
    case stageShare
    // 11
    case recordLongestNight
    case recordBestConsistency
    case recordHighestRecovery
    case recordLowestRestingHeartRate
    // 12
    case milestone

    /// The rule's number in `InsightEngineV2`.
    public var rule: Int {
        switch self {
        case .sleepDurationShift: 1
        case .bedtimeShift: 2
        case .consistentBedtime: 3
        case .earlierBedtimePattern: 4
        case .recoveryDirection: 5
        case .hrvBelowRange, .restingHeartRateAboveRange: 6
        case .consistencyChange: 7
        case .sleepBalance: 8
        case .weekendShift: 9
        case .stageShare: 10
        case .recordLongestNight, .recordBestConsistency, .recordHighestRecovery, .recordLowestRestingHeartRate: 11
        case .milestone: 12
        }
    }

    public var category: InsightCategory {
        switch self {
        case .sleepDurationShift, .sleepBalance, .stageShare: .sleep
        case .bedtimeShift, .earlierBedtimePattern, .weekendShift: .timing
        case .consistentBedtime, .consistencyChange: .consistency
        case .recoveryDirection: .recovery
        case .hrvBelowRange, .restingHeartRateAboveRange: .heart
        case .recordLongestNight, .recordBestConsistency, .recordHighestRecovery, .recordLowestRestingHeartRate, .milestone: .longTerm
        }
    }

    /// A pattern in the data: it always carries the "not proof of a cause"
    /// line.
    public var isPattern: Bool { self == .earlierBedtimePattern }

    /// Whether the insight offers one generic, safe thing to try (rules 1,
    /// 2, 3, 7 and 8 only).
    public var offersSomethingToTry: Bool {
        switch self {
        case .sleepDurationShift, .bedtimeShift, .consistentBedtime, .consistencyChange, .sleepBalance: true
        default: false
        }
    }

    public var isRecord: Bool {
        switch self {
        case .recordLongestNight, .recordBestConsistency, .recordHighestRecovery, .recordLowestRestingHeartRate: true
        default: false
        }
    }

    /// Information rather than a finding: ranks after everything else and
    /// is never a to-do.
    public var isInformational: Bool { self == .milestone }

    /// How much a person can do about it, 0...1, for ranking.
    public var actionability: Double {
        isInformational ? 0 : (offersSomethingToTry ? 0.8 : (isPattern ? 0.5 : 0.25))
    }
}

extension InsightKind {
    /// The v1 kind's place among the types.
    public var type: InsightType {
        switch self {
        case .sleepDurationShift: .sleepDurationShift
        case .bedtimeShift: .bedtimeShift
        case .consistentBedtime: .consistentBedtime
        }
    }
}
