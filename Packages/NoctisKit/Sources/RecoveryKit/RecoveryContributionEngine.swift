import Foundation
import SleepKit

/// One factor's part of a night's recovery score.
public struct RecoveryContribution: Sendable, Equatable, Codable {
    public let kind: RecoveryFactorKind
    /// The factor's share of the score after renormalization (0...1).
    public let weight: Double
    /// The factor's 0...100 score, unrounded.
    public let score: Double
    /// weight × score: how many of the overall points this factor is.
    public let points: Double
    /// `points` in whole numbers that add up to the score's whole number
    /// (largest remainder), for showing.
    public let wholePoints: Int
    /// What the factor usually contributes: weight × its usual score. Nil
    /// under 5 nights to compare with.
    public let usualPoints: Double?
    /// `points` − `usualPoints`: how many points more or fewer than usual.
    public let deltaPoints: Double?

    public init(kind: RecoveryFactorKind, weight: Double, score: Double, points: Double, wholePoints: Int, usualPoints: Double?, deltaPoints: Double?) {
        self.kind = kind
        self.weight = weight
        self.score = score
        self.points = points
        self.wholePoints = wholePoints
        self.usualPoints = usualPoints
        self.deltaPoints = deltaPoints
    }
}

/// Why a score was held down.
public struct RecoveryCapReport: Sendable, Equatable, Codable {
    public enum Reason: String, Sendable, Equatable, Codable {
        /// HRV well below and resting heart rate well above the person's
        /// normal on the same morning.
        case heartSignalsBothFarOff
    }

    /// The highest score allowed.
    public let cap: Int
    /// What the score would have been.
    public let preCapScore: Double
    public let reason: Reason
    /// The two signals, in standard deviations from usual in the good
    /// direction (negative = lower HRV, higher resting heart rate).
    public let hrvStandardDeviations: Double?
    public let restingStandardDeviations: Double?

    public init(cap: Int, preCapScore: Double, reason: Reason, hrvStandardDeviations: Double?, restingStandardDeviations: Double?) {
        self.cap = cap
        self.preCapScore = preCapScore
        self.reason = reason
        self.hrvStandardDeviations = hrvStandardDeviations
        self.restingStandardDeviations = restingStandardDeviations
    }
}

public struct RecoveryContributions: Sendable, Equatable, Codable {
    public let night: SleepNightKey
    /// The score shown, after any cap.
    public let score: Int
    /// The sum of the contributions' points: the score before any cap.
    public let preCapScore: Double
    /// In factor order (the ring's), the factors that were scored.
    public let contributions: [RecoveryContribution]
    /// Set when the cap held the score down.
    public let capApplied: RecoveryCapReport?

    public init(night: SleepNightKey, score: Int, preCapScore: Double, contributions: [RecoveryContribution], capApplied: RecoveryCapReport?) {
        self.night = night
        self.score = score
        self.preCapScore = preCapScore
        self.contributions = contributions
        self.capApplied = capApplied
    }

    public func contribution(_ kind: RecoveryFactorKind) -> RecoveryContribution? {
        contributions.first { $0.kind == kind }
    }
}

/// How a night's recovery score is made of its factors: each factor's
/// share of the score in points, and how far each is from its usual. The
/// points add up to the score before any cap, exactly.
public enum RecoveryContributionEngine {
    /// The ring's and the rows' order.
    public static let factorOrder: [RecoveryFactorKind] = [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency]

    public static func contributions(for result: RecoveryResult) -> RecoveryContributions {
        let factors = factorOrder.compactMap { result.factor($0) }
        // The unrounded scores when the result has them: then the points
        // are the score's own arithmetic.
        let exact = factors.map { factor -> (factor: RecoveryFactor, score: Double, points: Double) in
            let score = factor.unroundedScore ?? Double(factor.score)
            return (factor, score, factor.weight * score)
        }
        let preCap = exact.reduce(0) { $0 + $1.points }
        let wholes = wholePoints(exact.map(\.points), total: Int(preCap.rounded()))
        let contributions = exact.enumerated().map { index, item -> RecoveryContribution in
            let usualPoints = item.factor.usual.map { item.factor.weight * $0 }
            return RecoveryContribution(
                kind: item.factor.kind,
                weight: item.factor.weight,
                score: item.score,
                points: item.points,
                wholePoints: wholes[index],
                usualPoints: usualPoints,
                deltaPoints: usualPoints.map { item.points - $0 }
            )
        }
        var cap: RecoveryCapReport?
        if result.heartCapApplied {
            cap = RecoveryCapReport(
                cap: RecoveryModelV3.heartCapScore,
                preCapScore: preCap,
                reason: .heartSignalsBothFarOff,
                hrvStandardDeviations: result.factor(.hrv)?.standardScore,
                restingStandardDeviations: result.factor(.restingHeartRate)?.standardScore
            )
        }
        return RecoveryContributions(night: result.night, score: result.score, preCapScore: preCap, contributions: contributions, capApplied: cap)
    }

    /// `values` as whole numbers that add up to `total`: each rounded
    /// down, then the leftover points go to the largest fractions (the
    /// earlier factor wins a tie).
    static func wholePoints(_ values: [Double], total: Int) -> [Int] {
        var wholes = values.map { Int($0.rounded(.down)) }
        var leftover = total - wholes.reduce(0, +)
        let order = values.indices.sorted { lhs, rhs in
            let left = values[lhs] - values[lhs].rounded(.down)
            let right = values[rhs] - values[rhs].rounded(.down)
            return left == right ? lhs < rhs : left > right
        }
        var cursor = 0
        while leftover > 0, !order.isEmpty {
            wholes[order[cursor % order.count]] += 1
            leftover -= 1
            cursor += 1
        }
        return wholes
    }
}
