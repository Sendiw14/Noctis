import Foundation
import HealthProviding
import Testing
@testable import SleepKit

struct SleepSessionEngineTests {
    @Test func mergesContiguousSegmentsAcrossMidnightIntoOneSession() {
        let bedtime = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            RawSleepSample(start: bedtime, end: bedtime.addingTimeInterval(3600), stage: .core, sourceName: "Test", sourceBundleID: "test"),
            RawSleepSample(start: bedtime.addingTimeInterval(3600), end: bedtime.addingTimeInterval(3 * 3600), stage: .deep, sourceName: "Test", sourceBundleID: "test"),
            RawSleepSample(start: bedtime.addingTimeInterval(3 * 3600), end: bedtime.addingTimeInterval(8 * 3600), stage: .rem, sourceName: "Test", sourceBundleID: "test"),
        ]

        let sessions = SleepSessionEngine.buildSessions(from: samples)

        #expect(sessions.count == 1)
        #expect(sessions.first?.kind == .main)
        #expect(sessions.first?.wakeTime == bedtime.addingTimeInterval(8 * 3600))
    }

    @Test func gapLargerThanThresholdSplitsIntoSeparateSessions() {
        let night1Start = Date(timeIntervalSince1970: 1_700_000_000)
        let night2Start = night1Start.addingTimeInterval(20 * 3600)

        let samples = [
            RawSleepSample(start: night1Start, end: night1Start.addingTimeInterval(7 * 3600), stage: .core, sourceName: "Test", sourceBundleID: "test"),
            RawSleepSample(start: night2Start, end: night2Start.addingTimeInterval(7 * 3600), stage: .core, sourceName: "Test", sourceBundleID: "test"),
        ]

        let sessions = SleepSessionEngine.buildSessions(from: samples)

        #expect(sessions.count == 2)
    }

    @Test func shortRunsClassifyAsNapsNotMainSessions() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            RawSleepSample(start: start, end: start.addingTimeInterval(25 * 60), stage: .core, sourceName: "Test", sourceBundleID: "test"),
        ]

        let sessions = SleepSessionEngine.buildSessions(from: samples)

        #expect(sessions.first?.kind == .nap)
    }
}
