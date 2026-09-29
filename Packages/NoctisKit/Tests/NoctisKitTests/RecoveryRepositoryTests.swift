import Foundation
import Testing
@testable import DesignSystem
@testable import HealthProviding
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepKit

// Recovery's snapshot for every mock scenario, built end to end: mock
// provider → RecoveryRepository → engines → render model. The clock and
// zone are fixed: 10:00 AM on Thursday, Sep 24, 2026, New York.

private let now = Fixture.date(2026, 9, 24, 10)

private func mock(_ scenario: MockScenario = .full, authorized: Bool = true, available: Bool = true, fails: Bool = false) -> MockHealthKitProvider {
    MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: authorized, isHealthDataAvailable: available, failsQueries: fails)
}

private func repository(_ provider: some HealthDataProviding) -> RecoveryRepository {
    let clock = now
    return RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock })
}

private func snapshot(_ scenario: MockScenario = .full) async -> RecoverySnapshot {
    await repository(mock(scenario)).refresh(profile: UserProfileSnapshot())
}

struct RecoverySnapshotTests {
    @Test func theFullScenarioHasAQuarterOfScoredNightsAndEveryDerivedValue() async throws {
        let snap = await snapshot(.full)
        #expect(snap.dataState == .ready)
        #expect(snap.scores.count >= 90)
        for range in RecoveryHistoryRange.allCases {
            let history = try #require(snap.history(range))
            #expect(history.days.count == range.nights && history.series.count == range.nights)
        }
        #expect(snap.factorSeries.count == RecoveryFactorKind.allCases.count * RecoveryFactorRange.allCases.count)
        for kind in RecoveryFactorKind.allCases {
            for range in RecoveryFactorRange.allCases {
                let series = try #require(snap.series(kind, range))
                #expect(series.points.count == range.nights)
            }
        }
        let result = try #require(snap.result)
        let contributions = try #require(snap.contributions)
        #expect(contributions.score == result.score)
        #expect(snap.confidence?.tier == .high)
        #expect(snap.scores.last?.night == SleepNightKey(year: 2026, month: 9, day: 23))
    }

    @Test func todaysScoreIsExactlyHomes() async {
        let recovery = await snapshot(.full)
        let clock = now
        let home = await HomeRepository(provider: mock(.full), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        #expect(recovery.recovery == home.recovery)
        #expect(recovery.dataState == home.dataState)
        let sleepOnly = await snapshot(.sleepOnly)
        let homeSleepOnly = await HomeRepository(provider: mock(.sleepOnly), timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
        #expect(sleepOnly.recovery == homeSleepOnly.recovery)
    }

    @Test func theDipScenarioHasAFourNightDipAndThenARecovery() async throws {
        let snap = await snapshot(.recoveryDip)
        #expect(snap.dataState == .ready)
        let scores = snap.scores.map(\.score)
        // Nine to six nights before the last: the dip.
        let dip = Array(scores.suffix(9).prefix(4))
        let before = Array(scores.suffix(20).prefix(11))
        let after = Array(scores.suffix(5))
        let usual = Double(before.reduce(0, +)) / Double(before.count)
        #expect(dip.allSatisfy { Double($0) < usual - 15 }, "dip \(dip) against \(usual)")
        #expect(Double(after.reduce(0, +)) / Double(after.count) > usual - 10, "recovered: \(after)")
        let month = try #require(snap.history(.month))
        #expect(month.stats.low.map { dip.contains($0.score) } == true)
        // The full scenario has no such dip.
        let full = await snapshot(.full)
        #expect((full.history(.month)?.stats.low?.score ?? 0) > 60)
    }

    @Test func learningStaysAtThreeNightsWithNothingScored() async {
        let snap = await snapshot(.learning)
        #expect(snap.dataState == .learning(nightsSoFar: 3))
        #expect(snap.scores.isEmpty && snap.contributions == nil && snap.confidence == nil)
        #expect(snap.history(.week)?.days.isEmpty == true)
    }

    @Test func aGapNightHasNoScoreTodayAndTheHistoryEndsTheNightBefore() async throws {
        let snap = await snapshot(.gap)
        #expect(snap.dataState == .noSleepLastNight)
        #expect(snap.result == nil && snap.contributions == nil)
        let history = try #require(snap.history(.week))
        let last = try #require(history.days.last?.night)
        #expect(last < snap.anchorNight)
        #expect(history.stats.current != nil)
    }

    @Test func sleepOnlyScoresOnTwoFactorsAndSaysAWatchWouldAddTheRest() async throws {
        let snap = await snapshot(.sleepOnly)
        let contributions = try #require(snap.contributions)
        #expect(contributions.contributions.map(\.kind) == [.sleepDuration, .sleepConsistency])
        let report = try #require(snap.confidence)
        #expect(report.tier == .low)
        #expect(report.nextStep == .wearWatchToSleep(adding: [.hrv, .restingHeartRate]))
        // No HRV or resting heart rate series to draw.
        #expect(snap.series(.hrv, .fortnight)?.nightsRecorded == 0)
        #expect(snap.series(.sleepDuration, .fortnight)?.nightsRecorded == 14)
    }

    @Test func staleEmptyPermissionUnavailableAndFailureEachHaveTheirState() async {
        #expect(await snapshot(.empty).dataState == .empty)
        if case .stale = await snapshot(.stale).dataState {} else { Issue.record("expected stale") }
        #expect(await repository(mock(authorized: false)).refresh(profile: UserProfileSnapshot()).dataState == .permissionRequired)
        #expect(await repository(mock(available: false)).refresh(profile: UserProfileSnapshot()).dataState == .healthDataUnavailable)
        #expect(await repository(mock(fails: true)).refresh(profile: UserProfileSnapshot()).dataState == .failed)
        let none = await snapshot(.empty)
        #expect(none.scores.isEmpty && none.result == nil && none.factorSeries.isEmpty)
    }
}

struct RecoveryRenderModelTests {
    private func model(_ selection: RecoverySelection, _ scenario: MockScenario = .full) async throws -> RecoveryRenderModel {
        let repository = repository(mock(scenario))
        _ = await repository.refresh(profile: UserProfileSnapshot())
        return try #require(await repository.model(for: selection))
    }

    @Test func noModelBeforeASnapshotAndTheSameOneAfterwards() async throws {
        let repository = repository(mock())
        #expect(await repository.model(for: RecoverySelection()) == nil)
        _ = await repository.refresh(profile: UserProfileSnapshot())
        let first = try #require(await repository.model(for: RecoverySelection(segment: .month)))
        let second = try #require(await repository.model(for: RecoverySelection(segment: .month)))
        #expect(first == second)
        #expect(first.selection.segment == .month)
    }

    @Test func todayHasTheRingTheStackedBarAndTheSparklines() async throws {
        let snap = await snapshot(.full)
        let model = try await model(RecoverySelection())
        let today = try #require(model.today)
        #expect(today.ring.count == 4 && model.chart == nil)
        #expect(today.ring == RingRenderBuilder.build(try #require(snap.result)))
        #expect(today.bar.map(\.kind) == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency])
        // Each segment starts where the last ended, and they add up to the score before any cap.
        var expected = 0.0
        for segment in today.bar {
            #expect(abs(segment.start - expected) < 1e-12)
            expected += segment.width
        }
        #expect(abs(expected - (snap.contributions?.preCapScore ?? -1) / 100) < 1e-9)
        #expect(today.sparklines.count == 4)
        #expect(today.sparkline(.hrv)?.nights.count == 14)
    }

    @Test func aSleepOnlyBarHasTwoSegments() async throws {
        let model = try await model(RecoverySelection(), .sleepOnly)
        #expect(model.today?.bar.count == 2 && model.today?.ring.count == 2)
    }

    @Test func eachHistorySegmentDrawsItsDaysAsAColumnEach() async throws {
        for (segment, days) in [(RecoverySegment.week, 7), (.month, 30), (.quarter, 90)] {
            let model = try await model(RecoverySelection(segment: segment))
            let chart = try #require(model.chart)
            #expect(model.today == nil)
            #expect(chart.count == days && chart.line.count == days && chart.smoothed.count == days)
            #expect(chart.line.compactMap { $0 }.allSatisfy { (0...1).contains($0) })
            #expect(chart.todayIndex == days - 1)
            let baseline = try #require(chart.baseline)
            #expect((0...1).contains(baseline))
            #expect((chart.bandLow ?? 1) <= baseline && baseline <= (chart.bandHigh ?? 0))
            #expect(model.factorRows.map(\.kind) == [.sleepDuration, .hrv, .restingHeartRate, .sleepConsistency])
        }
    }

    @Test func aRangesWeeklyAveragesAreRunsOfSevenCountedBackFromTheNewestDay() async throws {
        let quarter = try #require(try await model(RecoverySelection(segment: .quarter)).chart)
        // 90 = 6 + 12 × 7: a short run first.
        #expect(quarter.weeks.map { $0.end - $0.start } == [6] + Array(repeating: 7, count: 12))
        #expect(quarter.weeks.last?.end == 90)
        #expect(quarter.weeks.allSatisfy { $0.fraction != nil })
        // Smoothing needs 3 scored days in the seven: the first two days have fewer.
        #expect(quarter.smoothed[0] == nil && quarter.smoothed[1] == nil && quarter.smoothed[2] != nil)
    }

    @Test func aShortHistoryDrawsOnlyWhatExists() async throws {
        let repository = repository(MockHealthKitProvider(scenario: .full, historyDays: 12, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true))
        _ = await repository.refresh(profile: UserProfileSnapshot())
        let chart = try #require(await repository.model(for: RecoverySelection(segment: .month))?.chart)
        #expect(chart.count == 8, "12 nights, the first four still learning")
        #expect(chart.line.allSatisfy { $0 != nil })
    }

    @Test func aFactorDetailChartScalesItsValuesAndBandIntoOneChart() async throws {
        let snap = await snapshot(.full)
        for range in RecoveryFactorRange.allCases {
            let model = try await model(RecoverySelection(segment: .today, factor: .hrv, factorRange: range))
            let line = try #require(model.factor)
            #expect(model.today == nil && model.chart == nil)
            #expect(line.values.count == range.nights)
            #expect(line.values.compactMap { $0 }.allSatisfy { (0...1).contains($0) })
            #expect((line.bandLow ?? -1) >= 0 && (line.bandHigh ?? 2) <= 1 && (line.bandLow ?? 1) < (line.bandHigh ?? 0))
            #expect(line.todayIndex == range.nights - 1)
            #expect(line.axisLow < line.axisHigh)
            #expect(line.ticks.allSatisfy { (0...1).contains($0.position) && $0.value >= line.axisLow && $0.value <= line.axisHigh })
            #expect((2...6).contains(line.ticks.count), "\(line.ticks.count) ticks")
            // The value at a position is the value of the night.
            let series = try #require(snap.series(.hrv, range))
            let last = try #require(series.points.last?.value)
            #expect(abs(line.axisLow + (line.values.last.flatMap { $0 } ?? 0) * (line.axisHigh - line.axisLow) - last) < 1e-9)
        }
    }

    @Test func aFactorsTicksAreRoundNumbersInItsOwnUnit() {
        #expect(RecoveryRenderModelBuilder.tickStep(.sleepDuration, span: 240) == 60)
        #expect(RecoveryRenderModelBuilder.tickStep(.sleepConsistency, span: 100) == 30)
        #expect(RecoveryRenderModelBuilder.tickStep(.hrv, span: 40) == 10)
        #expect(RecoveryRenderModelBuilder.tickStep(.restingHeartRate, span: 6) == 2)
        #expect(RecoveryRenderModelBuilder.tickStep(.hrv, span: 10_000) == 100)
    }

    @Test func aLearningOrEmptySnapshotHasNothingToDraw() async throws {
        let learning = try await model(RecoverySelection(), .learning)
        #expect(learning.today == nil)
        let empty = try await model(RecoverySelection(segment: .month), .empty)
        #expect(empty.chart?.count == 0 && empty.factorRows.isEmpty)
    }

    @Test func theSignpostsAreNamed() {
        let names = NoctisSignpost.Interval.allCases.map(\.rawValue)
        #expect(names.contains("RecoveryLoad") && names.contains("RecoveryModel"))
    }
}
