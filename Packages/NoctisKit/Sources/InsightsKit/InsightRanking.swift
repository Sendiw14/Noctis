import Foundation
import SleepKit

/// The order insights are shown in: deterministic, from four numbers and the
/// id, so the same data always gives the same list.
///
/// `score = 0.35 × confidence + 0.30 × relevance + 0.20 × novelty + 0.15 × actionability`
/// - confidence: high 1, moderate 0.6, low 0.3.
/// - relevance: 1 for the newest night, less 1/14 per night older, never
///   below 0.
/// - novelty: 1 if the type was never featured, otherwise the nights since
///   it was featured over 14, at most 1.
/// - actionability: 0.8 with something generic to try, 0.5 for a pattern, 0.25
///   otherwise (`InsightType.actionability`).
/// Scores are rounded to 1e-6 (so float noise can't reorder a tie). A tie
/// puts the two baseline shifts (duration and bedtime) first, the larger one
/// in minutes leading and duration an equal one, as in v1; every other tie
/// goes to the smaller id. A learning milestone is information, not a
/// finding: it ranks after every insight, whatever its score.
public enum InsightRanking {
    public static let confidenceWeight = 0.35
    public static let relevanceWeight = 0.30
    public static let noveltyWeight = 0.20
    public static let actionabilityWeight = 0.15
    public static let relevanceNights = 14
    public static let noveltyNights = 14

    public static func confidence(_ confidence: InsightConfidence) -> Double {
        switch confidence {
        case .high: 1
        case .moderate: 0.6
        case .low: 0.3
        }
    }

    public static func relevance(of night: SleepNightKey, on today: SleepNightKey) -> Double {
        let age = max(0, today.days(from: night))
        return max(0, 1 - Double(age) / Double(relevanceNights))
    }

    /// 1 for a type never featured; otherwise it grows back over two weeks.
    public static func novelty(of type: InsightType, on night: SleepNightKey, history: InsightHistory) -> Double {
        guard let last = history.lastFeatured(type) else { return 1 }
        return min(max(Double(night.days(from: last.night)), 0) / Double(noveltyNights), 1)
    }

    public static func score(confidence: InsightConfidence, relevance: Double, novelty: Double, actionability: Double) -> Double {
        let raw = confidenceWeight * Self.confidence(confidence) + relevanceWeight * relevance + noveltyWeight * novelty + actionabilityWeight * actionability
        return (raw * 1_000_000).rounded() / 1_000_000
    }

    /// `records` re-scored as of `night` (their relevance and novelty are
    /// recomputed, so a stored record ages) and ordered best first.
    public static func ranked(_ records: [InsightRecord], on night: SleepNightKey, history: InsightHistory = InsightHistory()) -> [InsightRecord] {
        records
            .map { $0.with(relevance: relevance(of: $0.night, on: night), novelty: novelty(of: $0.type, on: night, history: history)) }
            .sorted { lhs, rhs in
                if lhs.type.isInformational != rhs.type.isInformational { return !lhs.type.isInformational }
                let (a, b) = (score(lhs), score(rhs))
                if a != b { return a > b }
                let (shiftA, shiftB) = (isShift(lhs), isShift(rhs))
                if shiftA != shiftB { return shiftA }
                if shiftA, lhs.magnitude != rhs.magnitude { return lhs.magnitude > rhs.magnitude }
                if shiftA, lhs.type != rhs.type { return lhs.type == .sleepDurationShift }
                return lhs.id < rhs.id
            }
    }

    /// The two baseline shifts, which lead any tie (a strict order: shifts
    /// first, by size, then by id).
    static func isShift(_ record: InsightRecord) -> Bool {
        record.type == .sleepDurationShift || record.type == .bedtimeShift
    }

    public static func score(_ record: InsightRecord) -> Double {
        score(confidence: record.confidence, relevance: record.relevance, novelty: record.novelty, actionability: record.actionability)
    }
}
