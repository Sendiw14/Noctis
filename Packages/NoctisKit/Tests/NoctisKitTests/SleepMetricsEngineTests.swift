import Foundation
import HealthProviding
import Testing
@testable import SleepKit

struct SleepMetricsEngineTests {
    private let calendar = Calendar.current
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private func date(hour: Int, minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: reference)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// A single unbroken `.core` segment — simplest possible "night."
    private func plainSession(bedtimeHour: Int, totalHours: Double, dayOffset: Int = 0) -> SleepSession {
        let bedtime = date(hour: bedtimeHour, dayOffset: dayOffset)
        let wake = bedtime.addingTimeInterval(totalHours * 3600)
        let segment = SleepStageSegment(stage: .core, interval: DateInterval(start: bedtime, end: wake))
        return SleepSession(kind: .main, bedtime: bedtime, wakeTime: wake, segments: [segment], sourceName: "Test")
    }

    // MARK: - qualityBreakdown: duration

    @Test func durationScoreIsMaximumExactlyAtEightHourTarget() {
        let session = plainSession(bedtimeHour: 23, totalHours: 8.0)
        let breakdown = SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: [])
        #expect(breakdown.duration == 100)
    }

    @Test func durationScoreIsZeroAtToleranceBoundaryAndBeyond() {
        // target 8.0h, tolerance 2.4h → 10.4h deviation exactly equals tolerance.
        let atBoundary = plainSession(bedtimeHour: 23, totalHours: 10.4)
        let beyond = plainSession(bedtimeHour: 23, totalHours: 14.0)

        #expect(SleepMetricsEngine.qualityBreakdown(for: atBoundary, recentMainSessions: []).duration == 0)
        #expect(SleepMetricsEngine.qualityBreakdown(for: beyond, recentMainSessions: []).duration == 0)
    }

    // MARK: - qualityBreakdown: stage balance — never fabricated from absent data

    @Test func stageBalanceScoresLowWhenNoRemOrDeepDataExists() {
        // A single .core segment has zero REM/Deep — this must read as a
        // poor stage balance, not a fabricated "fine, we'll assume normal."
        let session = plainSession(bedtimeHour: 23, totalHours: 8.0)
        let breakdown = SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: [])
        #expect(breakdown.overall == 78)
        #expect(breakdown.duration == 100)
        #expect(breakdown.timing == 100)
        #expect(breakdown.continuity == 100)
        #expect(breakdown.consistency == 65)
    }

    @Test func stageBalanceScoresNearMaximumForIdealProportions() {
        let bedtime = date(hour: 23)
        let deepSeconds: TimeInterval = 0.18 * 8 * 3600
        let remSeconds: TimeInterval = 0.215 * 8 * 3600
        let coreSeconds: TimeInterval = 8 * 3600 - deepSeconds - remSeconds

        var cursor = bedtime
        let coreEnd = cursor.addingTimeInterval(coreSeconds)
        let coreSegment = SleepStageSegment(stage: .core, interval: DateInterval(start: cursor, end: coreEnd))
        cursor = coreEnd
        let deepEnd = cursor.addingTimeInterval(deepSeconds)
        let deepSegment = SleepStageSegment(stage: .deep, interval: DateInterval(start: cursor, end: deepEnd))
        cursor = deepEnd
        let remEnd = cursor.addingTimeInterval(remSeconds)
        let remSegment = SleepStageSegment(stage: .rem, interval: DateInterval(start: cursor, end: remEnd))

        let session = SleepSession(kind: .main, bedtime: bedtime, wakeTime: remEnd, segments: [coreSegment, deepSegment, remSegment], sourceName: "Test")
        let breakdown = SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: [])

        // Ideal proportions → stage-balance contribution is maximal, so with
        // duration also at target, overall should exceed the no-stage-data case.
        #expect(breakdown.overall > 78)
    }

    // MARK: - qualityBreakdown: consistency

    @Test func consistencyDefaultsToNeutralWithFewerThanThreeRecentSessions() {
        let session = plainSession(bedtimeHour: 23, totalHours: 8.0)
        let oneRecent = [plainSession(bedtimeHour: 23, totalHours: 8.0, dayOffset: -1)]
        #expect(SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: []).consistency == 65)
        #expect(SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: oneRecent).consistency == 65)
    }

    @Test func consistencyIsMaximumWithIdenticalRecentBedtimes() {
        let session = plainSession(bedtimeHour: 23, totalHours: 8.0)
        let recent = (1...5).map { plainSession(bedtimeHour: 23, totalHours: 8.0, dayOffset: -$0) }
        #expect(SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: recent).consistency == 100)
    }

    @Test func consistencyDropsToZeroPastTheDampingThreshold() {
        // Alternating bedtimes 3 hours apart (22:00 / 01:00) → stddev 90min,
        // which exceeds the engine's 75min full-penalty threshold.
        let session = plainSession(bedtimeHour: 23, totalHours: 8.0)
        let recent = [
            plainSession(bedtimeHour: 22, totalHours: 8.0, dayOffset: -1),
            plainSession(bedtimeHour: 1, totalHours: 8.0, dayOffset: -2),
            plainSession(bedtimeHour: 22, totalHours: 8.0, dayOffset: -3),
            plainSession(bedtimeHour: 1, totalHours: 8.0, dayOffset: -4),
        ]
        #expect(SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: recent).consistency == 0)
    }

    // MARK: - qualityBreakdown: continuity clamps, never goes negative

    @Test func continuityScoreClampsAtZeroWithManyAwakenings() {
        let bedtime = date(hour: 23)
        var segments: [SleepStageSegment] = []
        var cursor = bedtime
        for i in 0..<31 {
            let end = cursor.addingTimeInterval(600)
            segments.append(SleepStageSegment(stage: i == 0 ? .core : .awake, interval: DateInterval(start: cursor, end: end)))
            cursor = end
        }
        let session = SleepSession(kind: .main, bedtime: bedtime, wakeTime: cursor, segments: segments, sourceName: "Test")
        let breakdown = SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: [])
        #expect(breakdown.continuity == 0)
        #expect(breakdown.overall >= 0 && breakdown.overall <= 100)
    }

    // MARK: - qualityBreakdown: overall always stays in range

    @Test func overallScoreNeverLeavesZeroToOneHundredRange() {
        let extremeShort = plainSession(bedtimeHour: 23, totalHours: 0.1)
        let extremeLong = plainSession(bedtimeHour: 23, totalHours: 16.0)
        for session in [extremeShort, extremeLong] {
            let breakdown = SleepMetricsEngine.qualityBreakdown(for: session, recentMainSessions: [])
            for value in [breakdown.overall, breakdown.duration, breakdown.timing, breakdown.continuity, breakdown.consistency] {
                #expect(value >= 0 && value <= 100)
            }
        }
    }

    // MARK: - balance

    @Test func balanceReturnsNeedHoursDefaultsWithNoSessions() {
        let balance = SleepMetricsEngine.balance(recentMainSessions: [], needHours: 7.5)
        #expect(balance.balanceHours == 0)
        #expect(balance.rollingAverageHours == 7.5)
        #expect(balance.needHours == 7.5)
    }

    @Test func balanceComputesExactCumulativeDeficitAndAverage() {
        let sessions = [
            plainSession(bedtimeHour: 23, totalHours: 6.0, dayOffset: -3),
            plainSession(bedtimeHour: 23, totalHours: 7.0, dayOffset: -2),
            plainSession(bedtimeHour: 23, totalHours: 8.0, dayOffset: -1),
        ]
        let balance = SleepMetricsEngine.balance(recentMainSessions: sessions, needHours: 8.0)
        #expect(abs(balance.balanceHours - (-3.0)) < 0.0001)
        #expect(abs(balance.rollingAverageHours - 7.0) < 0.0001)
    }

    @Test func balanceRespectsWindowParameter() {
        // Array given oldest→newest, matching how AppModel passes mainSessions.
        let sessions = [
            plainSession(bedtimeHour: 23, totalHours: 8.0, dayOffset: -4),
            plainSession(bedtimeHour: 23, totalHours: 7.0, dayOffset: -3),
            plainSession(bedtimeHour: 23, totalHours: 6.0, dayOffset: -2),
            plainSession(bedtimeHour: 23, totalHours: 5.0, dayOffset: -1),
            plainSession(bedtimeHour: 23, totalHours: 4.0, dayOffset: 0),
        ]
        // window 2 → suffix keeps only the last two array elements: 5h, 4h.
        let balance = SleepMetricsEngine.balance(recentMainSessions: sessions, needHours: 8.0, window: 2)
        #expect(abs(balance.rollingAverageHours - 4.5) < 0.0001)
    }

    // MARK: - variability

    @Test func bedtimeVariabilityIsZeroWithFewerThanTwoSessions() {
        #expect(SleepMetricsEngine.bedtimeVariabilityMinutes(recentMainSessions: []) == 0)
        #expect(SleepMetricsEngine.bedtimeVariabilityMinutes(recentMainSessions: [plainSession(bedtimeHour: 23, totalHours: 8)]) == 0)
    }

    @Test func bedtimeVariabilityMatchesExactStandardDeviationForKnownOffsets() {
        let sessions = [
            plainSession(bedtimeHour: 22, totalHours: 8, dayOffset: -1),
            plainSession(bedtimeHour: 23, totalHours: 8, dayOffset: -2),
        ]
        let result = SleepMetricsEngine.bedtimeVariabilityMinutes(recentMainSessions: sessions)
        #expect(abs(result - 30.0) < 0.0001)
    }

    @Test func waketimeVariabilityMatchesExactStandardDeviationForKnownOffsets() {
        // wake times: bedtime 23:00 + 8h = 07:00; bedtime 23:00 + 9h = 08:00.
        let sessions = [
            plainSession(bedtimeHour: 23, totalHours: 8, dayOffset: -1),
            plainSession(bedtimeHour: 23, totalHours: 9, dayOffset: -2),
        ]
        let result = SleepMetricsEngine.waketimeVariabilityMinutes(recentMainSessions: sessions)
        #expect(abs(result - 30.0) < 0.0001)
    }
}
