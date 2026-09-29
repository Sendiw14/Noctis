import Foundation
import SleepKit

/// The smallest thing that would firm up the score, worked out only from
/// what the report knows. Never advice about health.
public enum RecoveryNextStep: Sendable, Equatable, Codable {
    /// These factors weren't recorded last night, though earlier nights
    /// had them: record them again.
    case recordAgain(factors: [RecoveryFactorKind])
    /// A factor has a value but under 5 nights to compare it with: this
    /// many more nights of tracking.
    case keepTracking(nightsNeeded: Int)
    /// Your sources don't provide these: an Apple Watch worn to sleep
    /// would add them.
    case wearWatchToSleep(adding: [RecoveryFactorKind])
    /// Every factor is in; the baseline is under a full 14 nights.
    case reachHigh(nightsNeeded: Int)
}

/// How far to trust today's score, and why: the tier (the same rules as
/// `RecoveryEngine.confidence`), which factors it used and which it
/// couldn't and why, how many nights it is built on, and the one next step
/// that would firm it up.
public struct RecoveryConfidenceReport: Sendable, Equatable, Codable {
    public struct Missing: Sendable, Equatable, Codable {
        public let kind: RecoveryFactorKind
        public let reason: RecoveryFactorGap

        public init(kind: RecoveryFactorKind, reason: RecoveryFactorGap) {
            self.kind = kind
            self.reason = reason
        }
    }

    public let tier: RecoveryConfidence
    /// In factor order.
    public let factorsUsed: [RecoveryFactorKind]
    /// In factor order, each with the engine's reason.
    public let factorsMissing: [Missing]
    /// Nights with sleep in the 14-night baseline window.
    public let nights: Int
    public let nextStep: RecoveryNextStep?

    public init(tier: RecoveryConfidence, factorsUsed: [RecoveryFactorKind], factorsMissing: [Missing], nights: Int, nextStep: RecoveryNextStep?) {
        self.tier = tier
        self.factorsUsed = factorsUsed
        self.factorsMissing = factorsMissing
        self.nights = nights
        self.nextStep = nextStep
    }
}

public enum RecoveryConfidenceReportBuilder {
    public static let factorOrder = RecoveryContributionEngine.factorOrder

    public static func report(for result: RecoveryResult) -> RecoveryConfidenceReport {
        let used = factorOrder.filter { result.factor($0) != nil }
        let missing = factorOrder.compactMap { kind in
            result.missingFactors[kind].map { RecoveryConfidenceReport.Missing(kind: kind, reason: $0) }
        }
        return RecoveryConfidenceReport(
            tier: result.confidence,
            factorsUsed: used,
            factorsMissing: missing,
            nights: result.baselineNights,
            nextStep: nextStep(result, missing: missing)
        )
    }

    /// The smallest step first: a factor that just wasn't recorded last
    /// night; then a baseline that's a few nights short; then a source
    /// that doesn't provide a signal at all; then the last nights up to 14.
    static func nextStep(_ result: RecoveryResult, missing: [RecoveryConfidenceReport.Missing]) -> RecoveryNextStep? {
        let notRecorded = missing.filter { $0.reason == .notRecorded }.map(\.kind)
        if !notRecorded.isEmpty { return .recordAgain(factors: notRecorded) }

        let forming = missing.filter { $0.reason == .buildingBaseline }
        if !forming.isEmpty {
            let needed = forming.map { entry -> Int in
                let have: Int = switch entry.kind {
                case .hrv: result.baselines.hrvNights
                case .restingHeartRate: result.baselines.restingHeartRateNights
                case .sleepDuration, .sleepConsistency: result.baselineNights
                }
                return max(BaselineEngine.minimumNights - have, 1)
            }
            return .keepTracking(nightsNeeded: needed.max() ?? 1)
        }

        let unavailable = missing.filter { $0.reason == .unavailable }.map(\.kind)
        if !unavailable.isEmpty { return .wearWatchToSleep(adding: unavailable) }

        if result.confidence != .high, result.baselineNights < RecoveryModelV1.highConfidenceNights {
            return .reachHigh(nightsNeeded: RecoveryModelV1.highConfidenceNights - result.baselineNights)
        }
        return nil
    }
}
