import Foundation
import Testing
@testable import DesignSystem
@testable import HealthProviding
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepKit

// The Sleep snapshot, its render model and the repository.

private nonisolated let now: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10)) ?? Date()
}()

private func provider(_ scenario: MockScenario, at date: Date = now) -> MockHealthKitProvider {
    MockHealthKitProvider(scenario: scenario, referenceDate: date, calendar: Fixture.calendar(), startAuthorized: true)
}

private func snapshot(_ scenario: MockScenario, at date: Date = now) async -> SleepSnapshot {
    await SleepRepository(provider: provider(scenario, at: date), timeZone: Fixture.newYork, clock: { date }).refresh(profile: UserProfileSnapshot())
}

struct SleepSnapshotTests {
    @Test func aFullMonthKeepsThirtyNightsDerivedFromEachSession() async throws {
        let snap = await snapshot(.full)
        #expect(snap.dataState == .ready)
        #expect(snap.records.count == SleepSnapshotBuilder.retainedNights)
        for record in snap.records {
            #expect(record.metrics.night == record.night && record.quality.night == record.night)
            #expect(record.quality.modelVersion == "sleep-quality-v1")
        }
        #expect(snap.records.map(\.night) == snap.records.map(\.night).sorted())
        #expect(snap.balance?.minutes != nil)
        #expect(snap.consistency?.windows.count == 3)
        #expect(snap.timing?.suggested != nil)
        #expect(snap.hasStageData && snap.hasHeartData)
    }

    @Test func theStatesAreHomesInHomesOrder() async {
        #expect(await snapshot(.learning).dataState == .learning(nightsSoFar: 3))
        #expect(await snapshot(.empty).dataState == .empty)
        if case .stale = await snapshot(.stale).dataState {} else { Issue.record("expected stale") }
        #expect(await snapshot(.gap).dataState == .noSleepLastNight)
    }

    @Test func sleepOnlyHasStagesButNoHeartRate() async {
        let snap = await snapshot(.sleepOnly)
        #expect(snap.hasStageData)
        #expect(!snap.hasHeartData)
        #expect(snap.records.allSatisfy { $0.heart == nil })
    }

    @Test func aGapNightIsMissingAndTheDefaultNightIsTheOneThatShouldHaveBeenLast() async throws {
        let snap = await snapshot(.gap)
        let anchor = snap.anchorNight
        #expect(snap.record(anchor) == nil)
        #expect(snap.defaultNight == anchor)
        let week = snap.nights(endingAt: anchor, count: 7)
        #expect(week.count == 7)
        #expect(week.last?.record == nil)
        #expect(week.dropLast().allSatisfy { $0.record != nil })
        #expect(week.map(\.night) == week.map(\.night).sorted())
    }

    @Test func theWindowBeforeANightIsItsFourteenPriorNights() async throws {
        let snap = await snapshot(.full)
        let last = try #require(snap.records.last)
        let window = snap.window(before: last.night)
        #expect(window.count == 14)
        #expect(!window.contains { $0.night == last.night })
        #expect(window.allSatisfy { $0.night < last.night })
    }

    @Test func aRefreshWithoutPermissionOrHealthIsAPlaceholder() async {
        let unauthorized = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: false)
        let snap = await SleepRepository(provider: unauthorized, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        #expect(snap.dataState == .permissionRequired && snap.records.isEmpty)
        let unavailable = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true, isHealthDataAvailable: false)
        #expect(await SleepRepository(provider: unavailable, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot()).dataState == .healthDataUnavailable)
        let failing = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true, failsQueries: true)
        #expect(await SleepRepository(provider: failing, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot()).dataState == .failed)
    }
}

struct SleepRenderModelTests {
    private func model(_ selection: SleepSelection, scenario: MockScenario = .full) async throws -> (SleepSnapshot, SleepRenderModel) {
        let snap = await snapshot(scenario)
        return (snap, SleepRenderModelBuilder.build(snap, selection: selection))
    }

    @Test func aDayHasTheLandscapeTheRingTheStageRowsAndTheFactorBars() async throws {
        let snap = await snapshot(.full)
        let night = snap.defaultNight
        let day = try #require(SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: night)).day)
        let record = try #require(snap.record(night))
        #expect(day.night == NightRenderBuilder.build(record.session, heart: record.heart))
        let ring = try #require(day.ring)
        #expect(ring.fraction == Double(record.quality.score) / 100)
        #expect(ring.usual == record.quality.usual.map { $0 / 100 })
        #expect(ring.arc.tickDegrees != nil, "a baseline exists")
        #expect(day.stageRows.map(\.stage) == [.awake, .rem, .core, .deep])
        #expect(abs(day.stageRows.dropFirst().map(\.share).reduce(0, +) - 1) < 1e-9, "sleep stages share the time asleep")
        #expect(day.factorBars.map(\.kind) == record.quality.factorsUsed)
    }

    @Test func aNightWithNoSleepRecordedHasNothingToDraw() async throws {
        let snap = await snapshot(.gap)
        let day = try #require(SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.anchorNight)).day)
        #expect(day.night == nil && day.ring == nil && day.stageRows.isEmpty && day.factorBars.isEmpty)
    }

    @Test func aWeekIsSevenBarsSharingOneScaleAndTheNeedLine() async throws {
        let snap = await snapshot(.full)
        let model = SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.defaultNight, range: .week))
        let week = try #require(model.week)
        #expect(week.bars.bars.count == 7)
        let need = Double(snap.needMinutes)
        let top = week.bars.topMinutes
        #expect(abs(week.bars.needFraction - need / top) < 1e-12)
        for bar in week.bars.bars {
            let record = snap.record(bar.night)
            #expect(bar.fraction == record.map { $0.metrics.asleepMinutes / top })
            if let stages = bar.stages { #expect(abs(stages.deep + stages.core + stages.rem - 1) < 1e-9) }
        }
        #expect(week.consistency.rows.count == 7)
        #expect(week.consistency.rows.allSatisfy { ($0.bedtime ?? 0) >= 0 && ($0.bedtime ?? 0) <= 1 && ($0.wake ?? 0) <= 1 })
        #expect(week.consistency.axisEnd > week.consistency.axisStart)
        #expect(week.consistency.bedtimeBand != nil && week.consistency.wakeBand != nil)
        #expect(model.balance != nil && model.balanceRender != nil && model.consistency != nil && model.timing != nil)
    }

    @Test func aMonthIsThirtyBarsInWeekBlocksWithTheBestAndShortestNight() async throws {
        let snap = await snapshot(.full)
        let month = try #require(SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.defaultNight, range: .month)).month)
        #expect(month.bars.bars.count == 30)
        // Blocks of seven counted back from the last night; the first is short.
        #expect(month.blocks.map { $0.end - $0.start } == [2, 7, 7, 7, 7])
        #expect(month.blocks.first?.start == 0 && month.blocks.last?.end == 30)
        for (a, b) in zip(month.blocks, month.blocks.dropFirst()) { #expect(a.end == b.start) }
        let longest = try #require(month.longest)
        let shortest = try #require(month.shortest)
        let fractions = month.bars.bars.map { $0.fraction ?? -1 }
        #expect(fractions[longest] == fractions.max() && fractions[shortest] == fractions.filter { $0 >= 0 }.min())
        #expect(month.rhythm.bedtime.count == 30 && month.rhythm.wake.count == 30)
        #expect(month.rhythm.bedtime.compactMap { $0 }.allSatisfy { (0...1).contains($0) })
        #expect(month.quality.count == 30)
    }

    @Test func theQualityStripBandsAreEightyAndSixty() {
        #expect(QualityDotRender.band(for: 80) == .high && QualityDotRender.band(for: 79) == .middle)
        #expect(QualityDotRender.band(for: 60) == .middle && QualityDotRender.band(for: 59) == .low)
        #expect(QualityDotRender.band(for: 100) == .high && QualityDotRender.band(for: 0) == .low)
    }

    @Test func aGapLeavesAnEmptySlotInTheBarsAndTheStrip() async throws {
        let snap = await snapshot(.gap)
        let month = try #require(SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.anchorNight, range: .month)).month)
        #expect(month.bars.bars.last?.fraction == nil)
        #expect(month.quality.last?.score == nil && month.quality.last?.band == nil)
        #expect(month.rhythm.bedtime.last == .some(nil))
    }

    @Test func theBalanceRenderPutsZeroInsideTheChart() async throws {
        let snap = await snapshot(.full)
        let model = SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.defaultNight, range: .week))
        let render = try #require(model.balanceRender)
        #expect(render.points.count == 14)
        #expect((0...1).contains(render.zero))
        #expect(render.points.compactMap { $0 }.allSatisfy { (0...1).contains($0) })
    }

    @Test func timingAxesRunOnWholeHours() async throws {
        let snap = await snapshot(.full)
        let week = try #require(SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.defaultNight, range: .week)).week)
        #expect(week.consistency.axisStart.truncatingRemainder(dividingBy: 60) == 0)
        #expect(week.consistency.axisEnd.truncatingRemainder(dividingBy: 60) == 0)
        #expect(week.consistency.axisEnd - week.consistency.axisStart >= 240)
    }
}

struct SleepRepositoryActorTests {
    @Test func aSelectionsModelIsBuiltOnceAndKeptUntilTheNextSnapshot() async throws {
        let repository = SleepRepository(provider: provider(.full), timeZone: Fixture.newYork, clock: { now })
        #expect(await repository.model(for: SleepSelection(night: SleepNightKey(year: 2026, month: 9, day: 23))) == nil, "no snapshot yet")
        let snap = await repository.refresh(profile: UserProfileSnapshot())
        let selection = SleepSelection(night: snap.defaultNight, range: .week)
        let first = try #require(await repository.model(for: selection))
        #expect(first == SleepRenderModelBuilder.build(snap, selection: selection))
        #expect(await repository.model(for: selection) == first)
        #expect(first.selection == selection)
    }

    @Test func rangeQueriesReadTheCachedSnapshot() async throws {
        let repository = SleepRepository(provider: provider(.full), timeZone: Fixture.newYork, clock: { now })
        let snap = await repository.refresh(profile: UserProfileSnapshot())
        let night = snap.defaultNight
        #expect(await repository.night(night)?.night == night)
        #expect(await repository.nights(endingAt: night, count: 7).count == 7)
        #expect(await repository.nights(endingAt: night, count: 30).count == 30)
        #expect(await repository.cachedSnapshot == snap)
    }

    @Test func refreshesAreCoalesced() async {
        let repository = SleepRepository(provider: provider(.full), timeZone: Fixture.newYork, clock: { now })
        async let a = repository.refresh(profile: UserProfileSnapshot())
        async let b = repository.refresh(profile: UserProfileSnapshot())
        #expect(await a == b)
    }

    @Test func theSignpostIntervalsExist() {
        #expect(NoctisSignpost.Interval.allCases.map(\.rawValue).contains("SleepLoad"))
        #expect(NoctisSignpost.Interval.allCases.map(\.rawValue).contains("SleepModel"))
    }
}

struct SleepBarsAverageTests {
    @Test func theAverageIsTheMeanOfTheRecordedNightsAndItsFractionSharesTheBarsScale() async throws {
        let snap = await snapshot(.full)
        let model = SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.defaultNight, range: .week))
        let bars = try #require(model.week?.bars)
        let recorded = snap.nights(endingAt: snap.defaultNight, count: 7).compactMap { $0.record?.metrics.asleepMinutes }
        let mean = recorded.reduce(0, +) / Double(recorded.count)
        #expect(abs(try #require(bars.averageMinutes) - mean) < 1e-9)
        #expect(abs(try #require(bars.averageFraction) - mean / bars.topMinutes) < 1e-12)
    }

    @Test func aRangeWithNoNightsHasNoAverage() async throws {
        let snap = await snapshot(.empty)
        let bars = SleepRenderModelBuilder.bars(snap, night: snap.anchorNight, count: 7)
        #expect(bars.averageMinutes == nil && bars.averageFraction == nil)
        #expect(bars.bars.allSatisfy { $0.fraction == nil })
    }
}
