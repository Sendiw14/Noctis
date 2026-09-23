import Foundation
import HealthProviding
import InsightsKit
import RecoveryKit
import SleepKit

public struct TodaySnapshot: Sendable {
    public let session: SleepSession
    public let quality: SleepQualityBreakdown
    public let recovery: RecoveryScore
    public let balance: SleepBalance
    public let recoveryHistory: [RecoveryHistoryPoint]
    public let scoredSessions: [ScoredSession]
    public let nightHeartRateSamples: [HeartRateSample]
    public let nightRespiratoryRate: Double?
    public let generatedAt: Date

    public init(
        session: SleepSession,
        quality: SleepQualityBreakdown,
        recovery: RecoveryScore,
        balance: SleepBalance,
        recoveryHistory: [RecoveryHistoryPoint],
        scoredSessions: [ScoredSession],
        nightHeartRateSamples: [HeartRateSample] = [],
        nightRespiratoryRate: Double? = nil,
        generatedAt: Date = .now
    ) {
        self.session = session
        self.quality = quality
        self.recovery = recovery
        self.balance = balance
        self.recoveryHistory = recoveryHistory
        self.scoredSessions = scoredSessions
        self.nightHeartRateSamples = nightHeartRateSamples
        self.nightRespiratoryRate = nightRespiratoryRate
        self.generatedAt = generatedAt
    }

    public var mainSessions: [SleepSession] { scoredSessions.map(\.session) }
}
