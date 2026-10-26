import Foundation
import HealthProviding
import Testing

@testable import SleepKit

struct SleepSessionEngineTests {
    private let tz = Fixture.newYork
    private let now = Fixture.date(2026, 9, 10, 12)

    private func history(_ samples: [RawSleepSample], asOf now: Date? = nil, priority: SourcePriority = .unranked) -> SleepHistory {
        SleepSessionEngine.history(from: samples, asOf: now ?? self.now, timeZone: tz, priority: priority)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        Fixture.date(2026, 9, day, hour, minute, second)
    }

    // MARK: - Nights

    @Test func contiguousStagesAcrossMidnightAreOneMainSleep() throws {
        let samples = [
            Fixture.sample(at(1, 23), at(2, 1), .core),
            Fixture.sample(at(2, 1), at(2, 3), .deep),
            Fixture.sample(at(2, 3), at(2, 7), .rem),
        ]
        let result = history(samples)
        #expect(result.nights.count == 1)
        let night = try #require(result.nights.first)
        #expect(night.kind == .main)
        #expect(night.night == SleepNightKey(year: 2026, month: 9, day: 1))
        #expect(night.bedtime == at(1, 23))
        #expect(night.wakeTime == at(2, 7))
        #expect(night.timeline.map(\.stage) == [.core, .deep, .rem])
    }

    @Test func bedtimeAfterMidnightBelongsToThePreviousEvening() throws {
        let result = history([Fixture.sample(at(2, 0, 40), at(2, 8))])
        let night = try #require(result.nights.first)
        #expect(night.night == SleepNightKey(year: 2026, month: 9, day: 1))
        #expect(night.bedtimeMinutesAfterNoon == 760)
    }

    @Test func aNightSplitByADataGapIsStillOneMainSleep() throws {
        let samples = [
            Fixture.sample(at(1, 22), at(2, 1, 30)),
            Fixture.sample(at(2, 3, 30), at(2, 7, 30)),
        ]
        let result = history(samples)
        #expect(result.nights.count == 1)
        let night = try #require(result.nights.first)
        #expect(night.totals.asleep == 7.5 * 3600)
        #expect(night.bedtime == at(1, 22))
        #expect(night.wakeTime == at(2, 7, 30))
        #expect(night.awakenings == 1)
    }

    @Test func shortSleepOnTheSameNightIsANapKeptOutOfTheNight() throws {
        let samples = [
            Fixture.sample(at(1, 14), at(1, 14, 40)),
            Fixture.sample(at(1, 23), at(2, 7)),
        ]
        let result = history(samples)
        #expect(result.nights.count == 1)
        #expect(result.naps.count == 1)
        #expect(result.nights.first?.totals.asleep == 8.0 * 3600)
        #expect(result.naps.first?.kind == .nap)
        #expect(result.naps.first?.totals.asleep == 40.0 * 60)
    }

    @Test func aDayWithOnlyANapHasNoNight() {
        let result = history([Fixture.sample(at(3, 14), at(3, 14, 40))])
        #expect(result.nights.isEmpty)
        #expect(result.naps.count == 1)
    }

    @Test func onlyCompleteNightsCount() {
        let samples = Fixture.plainNight(september: 8) + Fixture.plainNight(september: 9)
        // At 3:00 AM on Sep 10 the Sep 9 night hasn't ended.
        let result = history(samples, asOf: at(10, 3))
        #expect(result.nights.map(\.night) == [SleepNightKey(year: 2026, month: 9, day: 8)])
    }

    @Test func lastNightMustHaveEndedWithin24Hours() {
        let samples = Fixture.plainNight(september: 8)
        #expect(history(samples).lastNight(asOf: at(9, 9)) != nil)
        #expect(history(samples).lastNight(asOf: at(10, 9)) == nil)
    }

    // MARK: - Sources

    @Test func overlappingSourcesResolveToTheRicherTracker() throws {
        let watch = [
            Fixture.sample(at(1, 23), at(2, 2), .core),
            Fixture.sample(at(2, 2), at(2, 4), .deep),
            Fixture.sample(at(2, 4), at(2, 7), .rem),
        ]
        let thirdParty = Fixture.sample(at(1, 22, 30), at(2, 7, 30), .unspecified, source: "SleepApp", bundle: "com.example.sleepapp")
        let night = try #require(history(watch + [thirdParty]).nights.first)
        #expect(night.totals.asleep == 8 * 3600)
        #expect(night.totals.unspecified == 0)
        #expect(night.sourceName == "Watch")
    }

    @Test func explicitPriorityOverridesTheRicherTracker() throws {
        let watch = [Fixture.sample(at(1, 23), at(2, 2), .core), Fixture.sample(at(2, 2), at(2, 7), .deep)]
        let thirdParty = Fixture.sample(at(1, 22, 30), at(2, 7, 30), .unspecified, source: "SleepApp", bundle: "com.example.sleepapp")
        let priority = SourcePriority(orderedHighestFirst: [SourceIdentity(name: "SleepApp", bundleID: "com.example.sleepapp")])
        let night = try #require(history(watch + [thirdParty], priority: priority).nights.first)
        #expect(night.totals.asleep == 9 * 3600)
        #expect(night.totals.unspecified == 9 * 3600)
    }

    @Test func exactDuplicatesCountOnce() throws {
        let samples = Fixture.plainNight(september: 1)
        let duplicated = samples + samples.map { Fixture.sample($0.start, $0.end, $0.stage) }
        let night = try #require(history(duplicated).nights.first)
        #expect(night.totals.asleep == 8 * 3600)
    }

    @Test func overlappingSamplesFromOneSourceAreNeverCountedTwice() throws {
        let samples = [Fixture.sample(at(1, 23), at(2, 3)), Fixture.sample(at(2, 2), at(2, 7))]
        let night = try #require(history(samples).nights.first)
        #expect(night.totals.asleep == 8 * 3600)
    }

    @Test func inBedFromAnotherSourceKeepsEveryStageAndSetsTimeInBed() throws {
        let stages = [
            Fixture.sample(at(1, 23), at(1, 23, 10), .awake),
            Fixture.sample(at(1, 23, 10), at(2, 7), .core),
        ]
        let inBed = Fixture.sample(at(1, 22, 50), at(2, 7, 10), .inBed, source: "iPhone", bundle: "com.example.iphone")
        let night = try #require(history(stages + [inBed]).nights.first)
        #expect(night.timeline.count == 2)
        #expect(night.totals.inBed == (8 * 60 + 20) * 60)
        #expect(night.completeness.hasInBedData)
        #expect(night.efficiency == night.totals.asleep / night.totals.inBed)
    }

    // MARK: - Totals

    @Test func unspecifiedCountsTowardTotalSleepButNoStage() throws {
        let samples = [Fixture.sample(at(1, 23), at(2, 2), .core), Fixture.sample(at(2, 2), at(2, 6), .unspecified)]
        let totals = try #require(history(samples).nights.first).totals
        #expect(totals.asleep == 7 * 3600)
        #expect(totals.core == 3 * 3600)
        #expect(totals.deep == 0)
        #expect(totals.rem == 0)
        #expect(totals.unspecified == 4 * 3600)
        #expect(totals.core + totals.deep + totals.rem == 3 * 3600)
    }

    @Test func efficiencyIsOnlyGivenWhenTheDataCanShowTimeAwake() throws {
        let asleepOnly = try #require(history([Fixture.sample(at(1, 23), at(2, 7))]).nights.first)
        #expect(asleepOnly.efficiency == nil)

        let withAwake = try #require(
            history([
                Fixture.sample(at(1, 23), at(2, 1), .core),
                Fixture.sample(at(2, 1), at(2, 2), .awake),
                Fixture.sample(at(2, 2), at(2, 7), .core),
            ]).nights.first)
        #expect(withAwake.efficiency == 7.0 / 8.0)
    }

    @Test func awakeningsAreBreaksOfAMinuteOrMoreBetweenAsleepStretches() throws {
        let samples = [
            Fixture.sample(at(1, 23), at(1, 23, 10), .awake),  // before sleep: not an awakening
            Fixture.sample(at(1, 23, 10), at(2, 1), .core),
            Fixture.sample(at(2, 1), at(2, 1, 5), .awake),  // 5 min: counts
            Fixture.sample(at(2, 1, 5), at(2, 3), .deep),
            Fixture.sample(at(2, 3), at(2, 3, 0, 30), .awake),  // 30 s: too short
            Fixture.sample(at(2, 3, 0, 30), at(2, 5), .rem),
            // 20-minute gap in the data: counts
            Fixture.sample(at(2, 5, 20), at(2, 7), .core),
            Fixture.sample(at(2, 7), at(2, 7, 10), .awake),  // after waking: not an awakening
        ]
        let night = try #require(history(samples).nights.first)
        #expect(night.awakenings == 2)
        #expect(night.bedtime == at(1, 23))
        #expect(night.wakeTime == at(2, 7))
    }

    @Test func completenessReportsCoverageAndStageDetail() throws {
        let gappy = try #require(
            history([
                Fixture.sample(at(1, 23), at(2, 3), .core),
                Fixture.sample(at(2, 4), at(2, 7), .deep),
            ]).nights.first)
        #expect(gappy.completeness.coverage == 7.0 / 8.0)
        #expect(gappy.completeness.hasStageDetail)
        #expect(!gappy.completeness.hasInBedData)

        let unstaged = try #require(history([Fixture.sample(at(1, 23), at(2, 7), .unspecified)]).nights.first)
        #expect(unstaged.completeness.coverage == 1)
        #expect(!unstaged.completeness.hasStageDetail)
    }

    // MARK: - Clocks

    @Test func dstSpringForwardNightIsSevenRealHours() throws {
        // Mar 8, 2026: New York clocks jump from 2:00 to 3:00 AM.
        let samples = [Fixture.sample(Fixture.date(2026, 3, 7, 23), Fixture.date(2026, 3, 8, 7))]
        let result = SleepSessionEngine.history(from: samples, asOf: Fixture.date(2026, 3, 8, 12), timeZone: tz)
        let night = try #require(result.nights.first)
        #expect(night.night == SleepNightKey(year: 2026, month: 3, day: 7))
        #expect(night.totals.asleep == 7 * 3600)
        #expect(night.bedtimeMinutesAfterNoon == 660)
        #expect(night.wakeMinutesAfterNoon == 1140)
    }

    @Test func dstFallBackNightIsNineRealHours() throws {
        // Nov 1, 2026: New York clocks fall back from 2:00 to 1:00 AM.
        let samples = [Fixture.sample(Fixture.date(2026, 10, 31, 23), Fixture.date(2026, 11, 1, 7))]
        let result = SleepSessionEngine.history(from: samples, asOf: Fixture.date(2026, 11, 1, 12), timeZone: tz)
        let night = try #require(result.nights.first)
        #expect(night.night == SleepNightKey(year: 2026, month: 10, day: 31))
        #expect(night.totals.asleep == 9 * 3600)
        #expect(night.wakeMinutesAfterNoon == 1140)
    }

    @Test func aNightRecordedAbroadKeepsItsLocalClock() throws {
        let tokyo = Fixture.tokyo
        let bedtime = Fixture.date(2026, 9, 5, 23, in: tokyo)
        let samples = [Fixture.sample(bedtime, bedtime.addingTimeInterval(8 * 3600), timeZone: tokyo)]
        // The phone's zone is New York, where that bedtime was 10:00 AM.
        let night = try #require(history(samples).nights.first)
        #expect(night.night == SleepNightKey(year: 2026, month: 9, day: 5))
        #expect(night.timeZone == tokyo)
        #expect(night.bedtimeMinutesAfterNoon == 660)
        #expect(night.wakeMinutesAfterNoon == 1140)
    }

    @Test func theSameSamplesAlwaysGiveTheSameHistory() {
        let samples = Fixture.plainNight(september: 1) + Fixture.plainNight(september: 2) + [Fixture.sample(at(3, 14), at(3, 14, 30))]
        #expect(history(samples) == history(samples.reversed()))
    }
}
