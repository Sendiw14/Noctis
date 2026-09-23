import Foundation
import HealthProviding
import Testing
@testable import InsightsKit
@testable import SleepKit

struct InsightEngineTests {
    private let calendar = Calendar.current
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(hour: Int, minute: Int = 0, dayOffset: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: reference)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func scoredSession(bedtimeHour: Int, bedtimeMinute: Int = 0, dayOffset: Int, totalAsleepHours: Double, qualityOverall: Int) -> ScoredSession {
        let bedtime = date(hour: bedtimeHour, minute: bedtimeMinute, dayOffset: dayOffset)
        let wake = bedtime.addingTimeInterval(totalAsleepHours * 3600)
        let segment = SleepStageSegment(stage: .core, interval: DateInterval(start: bedtime, end: wake))
        let session = SleepSession(kind: .main, bedtime: bedtime, wakeTime: wake, segments: [segment], sourceName: "Test")
        let quality = SleepQualityBreakdown(overall: qualityOverall, duration: qualityOverall, timing: qualityOverall, continuity: qualityOverall, consistency: qualityOverall)
        return ScoredSession(session: session, quality: quality)
    }

    // MARK: - No fabrication

    @Test func emptyInputProducesNoInsights() {
        let insights = InsightEngine.generate(scoredSessions: [], recoveryHistory: [])
        #expect(insights.isEmpty)
    }

    @Test func insufficientHistoryProducesNoInsights() {
        // 5 sessions: below every detector's minimum (10/14/28/14).
        let sessions = (0..<5).map { scoredSession(bedtimeHour: 23, dayOffset: $0, totalAsleepHours: 8, qualityOverall: 80) }
        let insights = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: [])
        #expect(insights.isEmpty)
    }

    // MARK: - Bedtime / quality correlation

    @Test func bedtimeQualityInsightFiresOnClearSplit() {
        var sessions: [ScoredSession] = []
        for day in 0..<10 {
            sessions.append(scoredSession(bedtimeHour: 22, dayOffset: day, totalAsleepHours: 8, qualityOverall: 90))
        }
        for day in 10..<20 {
            sessions.append(scoredSession(bedtimeHour: 0, bedtimeMinute: 30, dayOffset: day, totalAsleepHours: 8, qualityOverall: 70))
        }

        let insight = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: []).first { $0.kind == "bedtimeQuality" }

        #expect(insight != nil)
        #expect(insight?.confidence == .high)
        #expect(insight?.evidence.count == 2)
    }

    @Test func bedtimeQualityInsightDoesNotFireWhenDifferenceIsSmall() {
        var sessions: [ScoredSession] = []
        for day in 0..<6 {
            sessions.append(scoredSession(bedtimeHour: 22, dayOffset: day, totalAsleepHours: 8, qualityOverall: 81))
        }
        for day in 6..<12 {
            sessions.append(scoredSession(bedtimeHour: 0, bedtimeMinute: 30, dayOffset: day, totalAsleepHours: 8, qualityOverall: 79))
        }

        let insight = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: []).first { $0.kind == "bedtimeQuality" }
        #expect(insight == nil)
    }

    // MARK: - Duration trend

    @Test func durationTrendInsightFiresAboveThreshold() {
        var sessions: [ScoredSession] = []
        for day in 0..<7 {
            sessions.append(scoredSession(bedtimeHour: 23, dayOffset: day, totalAsleepHours: 7.0, qualityOverall: 75))
        }
        for day in 7..<14 {
            sessions.append(scoredSession(bedtimeHour: 23, dayOffset: day, totalAsleepHours: 8.0, qualityOverall: 75))
        }

        let insight = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: []).first { $0.kind == "durationTrend" }

        #expect(insight != nil)
        #expect(insight?.title.contains("increased") == true)
    }

    @Test func durationTrendInsightDoesNotFireBelowThreshold() {
        var sessions: [ScoredSession] = []
        for day in 0..<7 {
            sessions.append(scoredSession(bedtimeHour: 23, dayOffset: day, totalAsleepHours: 7.9, qualityOverall: 75))
        }
        for day in 7..<14 {
            sessions.append(scoredSession(bedtimeHour: 23, dayOffset: day, totalAsleepHours: 8.0, qualityOverall: 75))
        }

        let insight = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: []).first { $0.kind == "durationTrend" }
        #expect(insight == nil)
    }

    // MARK: - Consistency trend

    @Test func consistencyTrendInsightFiresWhenVariabilityImproves() {
        var sessions: [ScoredSession] = []
        // Older 14: wildly varying bedtimes (high stddev).
        for day in 0..<14 {
            let hour = day.isMultiple(of: 2) ? 21 : 1
            sessions.append(scoredSession(bedtimeHour: hour, dayOffset: day, totalAsleepHours: 8, qualityOverall: 75))
        }
        // Recent 14: identical bedtime (near-zero stddev).
        for day in 14..<28 {
            sessions.append(scoredSession(bedtimeHour: 23, dayOffset: day, totalAsleepHours: 8, qualityOverall: 75))
        }

        let insight = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: []).first { $0.kind == "consistencyTrend" }
        #expect(insight != nil)
    }

    @Test func consistencyTrendInsightDoesNotFireWithFewerThan28Sessions() {
        var sessions: [ScoredSession] = []
        for day in 0..<14 {
            let hour = day.isMultiple(of: 2) ? 21 : 1
            sessions.append(scoredSession(bedtimeHour: hour, dayOffset: day, totalAsleepHours: 8, qualityOverall: 75))
        }
        for day in 14..<27 {
            sessions.append(scoredSession(bedtimeHour: 23, dayOffset: day, totalAsleepHours: 8, qualityOverall: 75))
        }

        let insight = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: []).first { $0.kind == "consistencyTrend" }
        #expect(insight == nil)
    }

    // MARK: - Recovery trend

    @Test func recoveryTrendInsightFiresAboveThreshold() {
        var history: [RecoveryHistoryPoint] = []
        for day in 0..<7 {
            history.append(RecoveryHistoryPoint(date: date(hour: 7, dayOffset: day), score: 60))
        }
        for day in 7..<14 {
            history.append(RecoveryHistoryPoint(date: date(hour: 7, dayOffset: day), score: 75))
        }

        let insight = InsightEngine.generate(scoredSessions: [], recoveryHistory: history).first { $0.kind == "recoveryTrend" }

        #expect(insight != nil)
        #expect(insight?.title.contains("improved") == true)
    }

    @Test func recoveryTrendInsightDoesNotFireBelowThreshold() {
        var history: [RecoveryHistoryPoint] = []
        for day in 0..<7 {
            history.append(RecoveryHistoryPoint(date: date(hour: 7, dayOffset: day), score: 70))
        }
        for day in 7..<14 {
            history.append(RecoveryHistoryPoint(date: date(hour: 7, dayOffset: day), score: 74))
        }

        let insight = InsightEngine.generate(scoredSessions: [], recoveryHistory: history).first { $0.kind == "recoveryTrend" }
        #expect(insight == nil)
    }

    // MARK: - Determinism

    @Test func generateIsDeterministicAcrossRepeatedCalls() {
        var sessions: [ScoredSession] = []
        for day in 0..<10 {
            sessions.append(scoredSession(bedtimeHour: 22, dayOffset: day, totalAsleepHours: 8, qualityOverall: 90))
        }
        for day in 10..<20 {
            sessions.append(scoredSession(bedtimeHour: 0, bedtimeMinute: 30, dayOffset: day, totalAsleepHours: 8, qualityOverall: 70))
        }

        let first = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: [])
        let second = InsightEngine.generate(scoredSessions: sessions, recoveryHistory: [])

        #expect(first.map(\.kind) == second.map(\.kind))
        #expect(first.map(\.title) == second.map(\.title))
        #expect(first.map { $0.evidence.map(\.value) } == second.map { $0.evidence.map(\.value) })
    }
}
