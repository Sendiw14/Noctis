import Foundation

@testable import InsightsKit
@testable import RecoveryKit
@testable import SleepKit

/// Hand-built records, one for every kind of evidence and each direction it
/// can point, for the wording, ranking and library tests.
enum InsightRecordFixture {
    static let night = InsightFixture.last
    static let generatedAt = InsightFixture.asOf

    static func record(_ type: InsightType, _ evidence: InsightEvidenceData, confidence: InsightConfidence = .high, nights: Int = 30) -> InsightRecord {
        InsightRecord(type: type, generatedAt: generatedAt, evidence: evidence, confidence: confidence, nightsUsed: nights)
    }

    static func duration(delta: Double, on night: SleepNightKey = night, confidence: InsightConfidence = .high) -> InsightRecord {
        record(
            .sleepDurationShift, .baseline(InsightEvidence(night: night, value: 420 + delta, baseline: 420, delta: delta, baselineNights: 14)),
            confidence: confidence, nights: 14)
    }

    static func bedtime(delta: Double, on night: SleepNightKey = night) -> InsightRecord {
        record(.bedtimeShift, .baseline(InsightEvidence(night: night, value: 660 + delta, baseline: 660, delta: delta, baselineNights: 14)), nights: 14)
    }

    static func streak(nights: Int = 6, on night: SleepNightKey = night) -> InsightRecord {
        record(
            .consistentBedtime,
            .baseline(
                InsightEvidence(
                    night: night, value: 665, baseline: 660, delta: 5, baselineNights: 14, streakNights: nights,
                    recentNights: Array(repeating: true, count: 14).enumerated().map { $0.offset < 14 - nights ? false : true }
                )), nights: 14)
    }

    static func pattern(earlier: Bool = true, early: Int = 16, late: Int = 17, on night: SleepNightKey = night) -> InsightRecord {
        let hi = 92.0, lo = 66.0
        return record(
            .earlierBedtimePattern,
            .pattern(
                PatternEvidence(
                    night: night, windowNights: 60, medianBedtime: 660, earlyNights: early, lateNights: late,
                    earlyValues: Array(repeating: earlier ? hi : lo, count: early), lateValues: Array(repeating: earlier ? lo : hi, count: late),
                    earlyMean: earlier ? hi : lo, lateMean: earlier ? lo : hi, difference: earlier ? hi - lo : lo - hi, effectSize: earlier ? 2.4 : -2.4,
                    pooledSD: 10.8
                )), nights: early + late)
    }

    static func recovery(rising: Bool = true, on night: SleepNightKey = night) -> InsightRecord {
        record(
            .recoveryDirection,
            .recoveryDirection(
                RecoveryDirectionEvidence(
                    night: night, direction: rising ? .rising : .lower, consecutiveDays: 6, pointsPerWeek: rising ? 3.2 : -3.2,
                    startScore: rising ? 61 : 78, latestScore: rising ? 74 : 63, recentScores: []
                )), nights: 7)
    }

    static func heart(_ signal: InsightHeartSignal, on night: SleepNightKey = night) -> InsightRecord {
        let hrv = signal == .hrv
        return record(
            hrv ? .hrvBelowRange : .restingHeartRateAboveRange,
            .heartSignal(
                HeartSignalEvidence(
                    night: night, signal: signal, consecutiveNights: 3, value: hrv ? 41 : 63, baseline: hrv ? 52 : 57,
                    rangeLow: hrv ? 47 : 55, rangeHigh: hrv ? 57 : 59, baselineNights: 14, recentValues: []
                )), confidence: .moderate, nights: 14)
    }

    static func consistency(steadier: Bool = true, on night: SleepNightKey = night) -> InsightRecord {
        record(
            .consistencyChange,
            .consistencyChange(
                ConsistencyChangeEvidence(
                    night: night, recentSD: steadier ? 18 : 44, previousSD: steadier ? 44 : 18, delta: steadier ? -26 : 26,
                    recentNights: 14, previousNights: 14, bedtimes: (0..<28).map { Double(650 + $0 % 5 * 10) }
                )), nights: 28)
    }

    static func balance(behind: Bool = true, on night: SleepNightKey = night) -> InsightRecord {
        record(
            .sleepBalance,
            .balance(
                BalanceEvidence(
                    night: night, minutes: behind ? -162 : 150, recordedNights: 7, needMinutes: 480,
                    nightlyMinutes: (0..<7).map { _ in behind ? 457 : 500 }
                )), nights: 7)
    }

    static func weekend(later: Bool = true, on night: SleepNightKey = night) -> InsightRecord {
        record(
            .weekendShift,
            .weekend(
                WeekendEvidence(
                    night: night, windowNights: 28, weekendMedian: later ? 725 : 610, weekdayMedian: 665, delta: later ? 60 : -55, weekendNights: 8,
                    weekdayNights: 20
                )), nights: 28)
    }

    static func stage(_ stage: InsightStage, more: Bool = false, on night: SleepNightKey = night) -> InsightRecord {
        record(
            .stageShare,
            .stageShare(
                StageShareEvidence(
                    night: night, stage: stage, share: more ? 0.24 : 0.11, usual: 0.17, deltaPoints: more ? 7 : -6, usualNights: 14
                )), nights: 14)
    }

    static func standingRecord(_ type: InsightType, scope: Int = 90, on night: SleepNightKey = night) -> InsightRecord {
        let value: Double
        let previous: Double
        switch type {
        case .recordLongestNight: (value, previous) = (510, 492)
        case .recordBestConsistency: (value, previous) = (9, 12)
        case .recordHighestRecovery: (value, previous) = (91, 88)
        default: (value, previous) = (49, 51)
        }
        return record(type, .record(RecordEvidence(night: night, value: value, previousBest: previous, scope: scope, nightsInWindow: scope)), nights: scope)
    }

    static func milestone(_ milestone: Int, on night: SleepNightKey = night) -> InsightRecord {
        record(.milestone, .milestone(MilestoneEvidence(night: night, milestone: milestone, nightsRecorded: milestone)), nights: milestone)
    }

    /// Every type, in every direction the wording has a branch for.
    static var everyVariant: [InsightRecord] {
        var all: [InsightRecord] = [
            duration(delta: -70), duration(delta: 45), bedtime(delta: 55), bedtime(delta: -40), streak(),
            pattern(earlier: true), pattern(earlier: false), recovery(rising: true), recovery(rising: false),
            heart(.hrv), heart(.restingHeartRate), consistency(steadier: true), consistency(steadier: false),
            balance(behind: true), balance(behind: false), weekend(later: true), weekend(later: false),
            stage(.deep, more: false), stage(.deep, more: true), stage(.rem, more: false), stage(.rem, more: true),
        ]
        for type in [InsightType.recordLongestNight, .recordBestConsistency, .recordHighestRecovery, .recordLowestRestingHeartRate] {
            all += [standingRecord(type, scope: 90), standingRecord(type, scope: 30)]
        }
        all += [milestone(7), milestone(14), milestone(30)]
        return all
    }
}
