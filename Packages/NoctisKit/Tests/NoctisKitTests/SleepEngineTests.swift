import Foundation
import Testing
@testable import HealthProviding
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepKit

// Sleep engines: metrics, quality (sleep-quality-v1), balance, consistency
// and timing. Sessions come from real samples through `SleepSessionEngine`.

enum SleepFixture {
    static let zone = Fixture.newYork
    /// 9:00 AM after the last fixture night.
    static let now = Fixture.date(2026, 9, 24, 9)

    /// The samples of one night: consecutive `blocks` (stage, minutes)
    /// from `bedtime`, plus an in-bed record spanning them when asked.
    static func samples(
        bedtime: Date, blocks: [(SleepStageValue, Double)], inBed: Bool = false,
        source: String = "Watch", bundle: String = "com.example.watch"
    ) -> [RawSleepSample] {
        var cursor = bedtime
        var result: [RawSleepSample] = []
        for (stage, minutes) in blocks {
            let end = cursor.addingTimeInterval(minutes * 60)
            result.append(Fixture.sample(cursor, end, stage, source: source, bundle: bundle))
            cursor = end
        }
        if inBed {
            result.append(Fixture.sample(bedtime.addingTimeInterval(-5 * 60), cursor.addingTimeInterval(5 * 60), .inBed, source: "Phone", bundle: "com.example.phone"))
        }
        return result
    }

    /// A typical staged night: core, deep, core, REM, core, deep, REM, core
    /// (`asleep` minutes in all, whole minutes so sums are exact), with an
    /// awake stretch after each of the first blocks from `awakeAfterOnset`.
    static func staged(asleep: Double = 450, deep: Double = 0.18, rem: Double = 0.22, awakeAfterOnset: [Double] = []) -> [(SleepStageValue, Double)] {
        let deepMinutes = (asleep * deep).rounded()
        let remMinutes = (asleep * rem).rounded()
        let coreMinutes = asleep - deepMinutes - remMinutes
        let core1 = (coreMinutes * 0.3).rounded()
        let core2 = (coreMinutes * 0.3).rounded()
        let core3 = (coreMinutes * 0.2).rounded()
        let core4 = coreMinutes - core1 - core2 - core3
        let deep1 = (deepMinutes * 0.6).rounded()
        let rem1 = (remMinutes * 0.4).rounded()
        let blocks: [(SleepStageValue, Double)] = [
            (.core, core1), (.deep, deep1), (.core, core2), (.rem, rem1),
            (.core, core3), (.deep, deepMinutes - deep1), (.rem, remMinutes - rem1), (.core, core4),
        ]
        var result: [(SleepStageValue, Double)] = []
        var awake = awakeAfterOnset.makeIterator()
        for (index, block) in blocks.enumerated() {
            result.append(block)
            // Awake stretches after blocks 0, 2, 4 and 6: always between two sleeping stretches.
            if index % 2 == 0, index < blocks.count - 1, let minutes = awake.next() { result.append((.awake, minutes)) }
        }
        return result
    }

    /// One night on the evening of `night` at `hour`:`minute` (an hour past
    /// midnight is 24, 25…).
    static func night(_ night: SleepNightKey, hour: Double = 23, blocks: [(SleepStageValue, Double)], inBed: Bool = false) -> [RawSleepSample] {
        let evening = Fixture.date(night.year, night.month, night.day, 12)
        let bedtime = evening.addingTimeInterval((hour - 12) * 3600)
        return samples(bedtime: bedtime, blocks: blocks, inBed: inBed)
    }

    /// The sessions of `samples`, oldest first; every night in the fixtures
    /// is complete by the end of Sep 24.
    static func sessions(_ samples: [RawSleepSample], asOf: Date = Fixture.date(2026, 9, 24, 23)) -> [SleepSession] {
        SleepSessionEngine.history(from: samples, asOf: asOf, timeZone: zone).nights
    }

    /// `count` nights ending on Sep 23, each from `values(index)` (bedtime
    /// hour, asleep minutes, stage shares).
    static func history(
        count: Int, endingOn last: SleepNightKey = SleepNightKey(year: 2026, month: 9, day: 23),
        bedtime: (Int) -> Double = { _ in 23 }, asleep: (Int) -> Double = { _ in 450 },
        deep: (Int) -> Double = { _ in 0.18 }, rem: (Int) -> Double = { _ in 0.22 },
        awakeAfterOnset: (Int) -> [Double] = { _ in [] }, inBed: Bool = true
    ) -> [SleepSession] {
        let samples = (0..<count).flatMap { index -> [RawSleepSample] in
            let key = last.adding(days: index - (count - 1))
            return night(key, hour: bedtime(index), blocks: staged(asleep: asleep(index), deep: deep(index), rem: rem(index), awakeAfterOnset: awakeAfterOnset(index)), inBed: inBed)
        }
        return sessions(samples)
    }
}

// MARK: - Metrics

struct SleepMetricsEngineTests {
    private let key = SleepNightKey(year: 2026, month: 9, day: 23)

    private func metrics(_ blocks: [(SleepStageValue, Double)], inBed: Bool = false, hour: Double = 23) throws -> SleepMetrics {
        let session = try #require(SleepFixture.sessions(SleepFixture.night(key, hour: hour, blocks: blocks, inBed: inBed)).first)
        return SleepMetricsEngine.metrics(for: session)
    }

    @Test func efficiencyExistsOnlyWithAnInBedRecord() throws {
        let blocks: [(SleepStageValue, Double)] = [(.awake, 10), (.core, 300), (.deep, 60), (.rem, 90)]
        let without = try metrics(blocks)
        #expect(without.efficiency == nil, "The span of the stage samples isn't an in-bed time.")
        let with = try metrics(blocks, inBed: true)
        // Asleep 450 min; in bed 460 (the stages) + 5 before + 5 after = 470.
        #expect(abs(try #require(with.efficiency) - 450.0 / 470.0) < 1e-9)
        #expect(with.timeInBedMinutes == 470)
        #expect(with.asleepMinutes == 450)
    }

    @Test func awakeningsTimeAwakeAfterOnsetAndLatency() throws {
        let m = try metrics([(.awake, 10), (.core, 60), (.awake, 8), (.core, 60), (.awake, 4), (.rem, 40), (.deep, 200)])
        #expect(m.awakenings == 2)
        #expect(m.awakeAfterOnsetMinutes == 12, "8 + 4: the 10 before falling asleep aren't after onset")
        #expect(m.onsetLatencyMinutes == 10)
    }

    @Test func latencyIsOnlyKnownWhenTheNightStartsAwake() throws {
        let m = try metrics([(.core, 200), (.awake, 6), (.deep, 200)])
        #expect(m.onsetLatencyMinutes == nil)
        #expect(m.awakeAfterOnsetMinutes == 6)
    }

    @Test func awakeTimeIsUnknownWhenTheSourceCannotShowWakefulness() throws {
        // Only asleep stages, no awake and no in-bed record: nothing says
        // the person was ever awake, so nothing is claimed.
        let m = try metrics([(.core, 250), (.deep, 100), (.rem, 100)])
        #expect(m.awakeAfterOnsetMinutes == nil)
        #expect(m.efficiency == nil)
        // An in-bed record makes it observable: 0 minutes awake.
        let withInBed = try metrics([(.core, 250), (.deep, 100), (.rem, 100)], inBed: true)
        #expect(withInBed.awakeAfterOnsetMinutes == 0)
    }

    @Test func stageMinutesAndSharesAddUpWithUnspecifiedCountedAsCore() throws {
        let m = try metrics([(.awake, 20), (.core, 180), (.unspecified, 20), (.deep, 80), (.rem, 120)])
        let stages = try #require(m.stages)
        #expect(stages.core == 200, "unspecified sleep sits in Core")
        #expect(stages.asleep == 400)
        let shares = try #require(stages.asleepShares)
        #expect(abs(shares.deep - 0.2) < 1e-9 && abs(shares.core - 0.5) < 1e-9 && abs(shares.rem - 0.3) < 1e-9)
        #expect(abs(shares.deep + shares.core + shares.rem - 1) < 1e-9)
        #expect(abs(try #require(stages.awakeShare) - 20.0 / 420) < 1e-9)
    }

    @Test func aNightWithoutStagesHasNoBreakdown() throws {
        let m = try metrics([(.unspecified, 420)])
        #expect(m.stages == nil)
        #expect(m.asleepMinutes == 420)
    }

    @Test func clockTimesAreMinutesAfterNoonAndTheMidpointIsHalfway() throws {
        let m = try metrics([(.core, 480)], hour: 23)
        #expect(m.bedtimeMinutes == 660 && m.wakeMinutes == 1140)
        #expect(m.midpointMinutes == 900)
    }

    @Test func aBedtimeAfterMidnightBelongsToTheEveningBefore() throws {
        // 12:30 AM on Sep 24 is night Sep 23, 750 minutes after noon.
        let session = try #require(SleepFixture.sessions(SleepFixture.night(key, hour: 24.5, blocks: [(.core, 420)])).first)
        #expect(session.night == key)
        let m = SleepMetricsEngine.metrics(for: session)
        #expect(m.bedtimeMinutes == 750)
        #expect(m.wakeMinutes == 750 + 420)
    }

    @Test func aSpringForwardNightReadsBedtimeAndWakeOnTheClockNotTheElapsedHours() throws {
        // Mar 7 → 8, 2026: clocks jump 2 AM → 3 AM. 11 PM to 7 AM is
        // 7 real hours of sleep, and still 660 / 1140 on the clock.
        let night = SleepNightKey(year: 2026, month: 3, day: 7)
        let bedtime = Fixture.date(2026, 3, 7, 23)
        let samples = SleepFixture.samples(bedtime: bedtime, blocks: [(.core, 420)])
        let session = try #require(SleepFixture.sessions(samples, asOf: Fixture.date(2026, 3, 8, 12)).first)
        #expect(session.night == night)
        let m = SleepMetricsEngine.metrics(for: session)
        #expect(m.asleepMinutes == 420)
        #expect(m.bedtimeMinutes == 660)
        #expect(m.wakeMinutes == 1140, "7:00 AM on the clock, not 6:00 AM after the missing hour")
    }

    @Test func aFallBackNightHasTheExtraHourInItsDuration() throws {
        // Nov 1, 2026: 1 AM happens twice. 11 PM to 7 AM is 9 real hours.
        let bedtime = Fixture.date(2026, 10, 31, 23)
        let end = Fixture.date(2026, 11, 1, 7)
        let samples = [Fixture.sample(bedtime, end, .core)]
        let session = try #require(SleepFixture.sessions(samples, asOf: Fixture.date(2026, 11, 1, 12)).first)
        let m = SleepMetricsEngine.metrics(for: session)
        #expect(m.asleepMinutes == 540)
        #expect(m.bedtimeMinutes == 660 && m.wakeMinutes == 1140)
    }

    @Test func overlappingSourcesDoNotDoubleCountTheNight() throws {
        var samples = SleepFixture.night(key, blocks: [(.core, 240), (.deep, 60), (.rem, 100)])
        // The phone also says asleep for the same eight hours.
        let bedtime = Fixture.date(2026, 9, 23, 23)
        samples.append(Fixture.sample(bedtime, bedtime.addingTimeInterval(400 * 60), .unspecified, source: "Phone", bundle: "com.example.phone"))
        let session = try #require(SleepFixture.sessions(samples).first)
        #expect(SleepMetricsEngine.metrics(for: session).asleepMinutes <= 400, "asleep never exceeds the night's span")
    }
}

// MARK: - Quality

struct SleepQualityEngineTests {
    private typealias Model = SleepQualityModelV1
    private let need = 480.0

    /// A steady 14-night window plus `last`, all through the engine.
    private func result(
        priorNights: Int = 14, last: (asleep: Double, bedtime: Double, deep: Double, rem: Double, awake: [Double]) = (480, 23, 0.18, 0.22, []),
        inBed: Bool = true, staged: Bool = true, need: Double = 480
    ) throws -> SleepQualityResult {
        let lastKey = SleepNightKey(year: 2026, month: 9, day: 23)
        var samples = (0..<priorNights).flatMap { index -> [RawSleepSample] in
            let key = lastKey.adding(days: index - priorNights)
            let asleep = 480 + Double(index % 3) * 6
            let blocks: [(SleepStageValue, Double)] = staged
                ? SleepFixture.staged(asleep: asleep, deep: 0.18 + Double(index % 3) * 0.01, rem: 0.22 + Double(index % 2) * 0.01)
                : [(.unspecified, asleep)]
            return SleepFixture.night(key, hour: 23 + Double(index % 3) * 0.1, blocks: blocks, inBed: inBed)
        }
        let blocks: [(SleepStageValue, Double)] = staged
            ? SleepFixture.staged(asleep: last.asleep, deep: last.deep, rem: last.rem, awakeAfterOnset: last.awake)
            : [(.unspecified, last.asleep)]
        samples += SleepFixture.night(lastKey, hour: last.bedtime, blocks: blocks, inBed: inBed)
        let sessions = SleepFixture.sessions(samples)
        let session = try #require(sessions.last)
        return SleepQualityEngine.score(night: session, history: sessions, needMinutes: need)
    }

    @Test func theWeightsAre35_25_20_20InOneVersionedConfig() {
        #expect(Model.version == "sleep-quality-v1")
        #expect(Model.weights == [.duration: 35, .continuity: 25, .consistency: 20, .stages: 20])
        #expect(Model.weights.values.reduce(0, +) == 100)
    }

    @Test func aGoodNightOnItsBaselineScoresHigh() throws {
        let r = try result()
        #expect(r.modelVersion == "sleep-quality-v1")
        #expect(r.factorsUsed == [.duration, .continuity, .consistency, .stages])
        #expect(r.score >= 95)
        // All four factors carry their own weights.
        #expect(r.factors.map(\.weight).map { ($0 * 100).rounded() } == [35, 25, 20, 20])
        #expect(r.missingFactors.isEmpty)
    }

    @Test func durationLosesTwoHundredPointsPerHundredPercentShort() throws {
        #expect(try result(last: (360, 23, 0.18, 0.22, [])).factor(.duration)?.score == 50)
        #expect(try result(last: (240, 23, 0.18, 0.22, [])).factor(.duration)?.score == 0)
        #expect(try result(last: (600, 23, 0.18, 0.22, [])).factor(.duration)?.score == 100, "sleeping over need is not rewarded past 100")
        // Half of need is the floor.
        #expect(try result(last: (480, 23, 0.18, 0.22, []), need: 960).factor(.duration)?.score == 0)
    }

    @Test func continuityCombinesTimeAwakeAndAwakenings() throws {
        // 35 min awake after onset over 3 awakenings: waso (35−10)*2 = 50 lost → 50; awakenings 3 → (3−2)*12.5 = 12.5 lost → 87.5; mean 68.75.
        let r = try result(last: (450, 23, 0.18, 0.22, [15, 10, 10]))
        #expect(r.factor(.continuity)?.score == 69)
        // Unbroken: 100.
        #expect(try result().factor(.continuity)?.score == 100)
    }

    @Test func consistencyIsBedtimeAgainstYourBaseline() throws {
        // The window sits at about 11:00 PM; an hour late is half of 120.
        let r = try result(last: (480, 24, 0.18, 0.22, []))
        let score = try #require(r.factor(.consistency)?.score)
        #expect((45...55).contains(score), "\(score)")
        #expect(try result(last: (480, 27, 0.18, 0.22, [])).factor(.consistency)?.score == 0)
    }

    @Test func stagesAreJudgedAgainstTypicalRangesUntilSevenNightsOfYourOwn() throws {
        let typical = try result(priorNights: 6)
        #expect(typical.stageBalance?.basis == .typical)
        let personal = try result(priorNights: 14)
        guard case .personal(let nights)? = personal.stageBalance?.basis else { Issue.record("expected personal"); return }
        #expect(nights == 14)
        let seven = try result(priorNights: 7)
        #expect(seven.stageBalance?.basis == .personal(nights: 7))
    }

    @Test func typicalRangesScoreFullInsideAndFallToZeroTenPointsOutside() throws {
        // Deep 18%, REM 22%, Core 60%: core is 5 points over its 45–55% range: half.
        let r = try result(priorNights: 3, last: (480, 23, 0.18, 0.22, []))
        let balance = try #require(r.stageBalance)
        #expect(balance.row(.deep)?.isWithinRange == true)
        #expect(balance.row(.rem)?.isWithinRange == true)
        #expect(balance.row(.core)?.isWithinRange == false)
        #expect(abs(try #require(balance.row(.core)).score - 50) < 1)
        #expect(abs(try #require(balance.row(.deep)).score - 100) < 1e-9)
        #expect(Model.typicalDeep == 0.13...0.23 && Model.typicalREM == 0.20...0.25 && Model.typicalCore == 0.45...0.55)
    }

    @Test func ownSharesUseYourUsualPlusOrMinusOneSpread() throws {
        let r = try result(priorNights: 14, last: (480, 23, 0.32, 0.22, []))
        let deep = try #require(r.stageBalance?.row(.deep))
        #expect(!deep.isWithinRange)
        #expect(deep.share > deep.high)
        #expect(deep.score < 100)
    }

    // Renormalization: each factor missing, in turn.

    @Test func withoutStagesTheRestRenormalizeOver80() throws {
        let r = try result(staged: false)
        #expect(!r.factorsUsed.contains(.stages))
        #expect(r.missingFactors[.stages] == .unavailable)
        #expect(r.stageBalance == nil)
        // Unstaged sources record only "asleep"; the in-bed record still makes wakefulness visible.
        #expect(r.factorsUsed == [.duration, .continuity, .consistency])
        #expect(r.factors.map { ($0.weight * 100).rounded(.toNearestOrEven) } == [44, 31, 25])
        #expect(abs(r.factors.reduce(0) { $0 + $1.weight } - 1) < 1e-9)
    }

    @Test func withoutWakefulnessContinuityIsDroppedAndTheRestRenormalizeOver75() throws {
        let r = try result(inBed: false, staged: true)
        // No awake stage and no in-bed record: continuity can't be judged.
        #expect(r.missingFactors[.continuity] == .unavailable)
        #expect(r.factorsUsed == [.duration, .consistency, .stages])
        #expect(abs(r.factors[0].weight - 35.0 / 75) < 1e-9)
        #expect(abs(r.factors[1].weight - 20.0 / 75) < 1e-9)
        #expect(abs(r.factors[2].weight - 20.0 / 75) < 1e-9)
    }

    @Test func withoutFiveNightsConsistencyIsDroppedAndTheRestRenormalizeOver80() throws {
        let r = try result(priorNights: 4)
        #expect(r.missingFactors[.consistency] == .buildingBaseline)
        #expect(r.factorsUsed == [.duration, .continuity, .stages])
        #expect(abs(r.factors[0].weight - 35.0 / 80) < 1e-9)
        #expect(abs(r.factors[1].weight - 25.0 / 80) < 1e-9)
        #expect(abs(r.factors[2].weight - 20.0 / 80) < 1e-9)
    }

    @Test func withOnlyDurationItCarriesAllTheWeight() throws {
        let r = try result(priorNights: 2, inBed: false, staged: false)
        #expect(r.factorsUsed == [.duration])
        #expect(r.factors[0].weight == 1)
        #expect(r.score == r.factors[0].score)
    }

    @Test func noSleepNeedDropsTheDurationFactor() throws {
        let r = try result(need: 0)
        #expect(r.missingFactors[.duration] == .unavailable)
        #expect(!r.factorsUsed.contains(.duration))
    }

    @Test func theScoreIsTheWeightedMeanOfTheFactors() throws {
        let r = try result(last: (380, 24, 0.18, 0.22, [20, 15]))
        let expected = r.factors.reduce(0.0) { $0 + Double($1.score) * $1.weight }
        #expect(abs(Double(r.score) - expected) <= 1.5, "rounded factor scores differ from the score by less than a point and a half")
    }

    @Test func confidenceUsesRecoverysTiers() throws {
        #expect(try result(priorNights: 14).confidence == .high)
        #expect(try result(priorNights: 8).confidence == .moderate)
        #expect(try result(priorNights: 4).confidence == .low)
        // Three factors and seven nights: moderate; two factors: low.
        #expect(try result(priorNights: 8, staged: false).confidence == .moderate)
        #expect(try result(priorNights: 8, inBed: false, staged: false).confidence == .low)
    }

    @Test func whatChangedNamesTheLargestDeviationOfYourOwnPattern() throws {
        // Two hours short of a steady 8h: the duration is what moved.
        let r = try result(last: (360, 23, 0.18, 0.22, []))
        let top = try #require(r.topContributor)
        #expect(top.measure == .duration)
        #expect(!top.isAbove)
        #expect(top.difference < -100)
        #expect(top.weightedDeviation > 0)
        // A night like every other has nothing to name.
        #expect(try result().topContributor == nil)
    }

    @Test func aLateBedtimeIsWhatChangedWhenNothingElseMoved() throws {
        let r = try result(last: (480, 25, 0.18, 0.22, []))
        #expect(r.topContributor?.measure == .bedtime)
        #expect(r.topContributor?.isAbove == true)
    }

    @Test func seriesScoresEachNightAsItsOwnMorningWithAUsual() throws {
        let sessions = SleepFixture.history(count: 20)
        let series = SleepQualityEngine.series(history: sessions, needMinutes: need)
        #expect(series.count == 20)
        #expect(series.map(\.night) == sessions.map(\.night))
        // The 6th night has 5 before it: a usual; the 5th has 4: none.
        #expect(series[4].usual == nil)
        #expect(series[5].usual != nil)
        // Each night's own baseline never includes itself.
        #expect(series[0].baselineNights == 0 && series[19].baselineNights == 14)
    }

    @Test func napsNeverEnterTheSeries() throws {
        let nap = SleepFixture.samples(bedtime: Fixture.date(2026, 9, 22, 14), blocks: [(.core, 60)])
        let nights = SleepFixture.history(count: 6)
        let history = SleepHistory(nights: nights, naps: SleepSessionEngine.history(from: nap, asOf: SleepFixture.now, timeZone: SleepFixture.zone).naps)
        #expect(!history.naps.isEmpty)
        let series = SleepQualityEngine.series(history: history.nights + history.naps, needMinutes: need)
        #expect(series.count == 6)
    }
}

// MARK: - Balance

struct SleepBalanceEngineTests {
    private let need = 480.0

    @Test func behindIsNegativeAndAheadIsPositive() {
        let behind = SleepFixture.history(count: 10, asleep: { _ in 420 })
        #expect(SleepBalanceEngine.balance(history: behind, needMinutes: need)?.minutes == -60.0 * 7)
        let ahead = SleepFixture.history(count: 10, asleep: { _ in 510 })
        #expect(SleepBalanceEngine.balance(history: ahead, needMinutes: need)?.minutes == 30.0 * 7)
    }

    @Test func itAddsUpTheLastSevenNightsOnly() {
        // Older nights were short; the last seven are on need.
        let history = SleepFixture.history(count: 14, asleep: { $0 < 7 ? 300 : 480 })
        let result = SleepBalanceEngine.balance(history: history, needMinutes: need)
        #expect(result?.minutes == 0.0)
        #expect(result?.recordedNights == 7)
    }

    @Test func aMixedWeekIsTheSignedSum() {
        let asleep: [Double] = [500, 400, 480, 450, 470, 430, 490]
        let history = SleepFixture.history(count: 7, asleep: { asleep[$0] })
        #expect(SleepBalanceEngine.balance(history: history, needMinutes: need)?.minutes == asleep.reduce(0.0) { $0 + $1 - need })
    }

    @Test func missingNightsAreLeftOutButFewerThanFiveGivesNoBalance() {
        let full = SleepFixture.history(count: 7, asleep: { _ in 420 })
        // Drop two nights: five remain, the balance sums five.
        let five = full.enumerated().filter { ![2, 4].contains($0.offset) }.map(\.element)
        let result = SleepBalanceEngine.balance(history: five, needMinutes: need)
        #expect(result?.recordedNights == 5)
        #expect(result?.minutes == -60.0 * 5)
        let four = full.enumerated().filter { ![2, 4, 5].contains($0.offset) }.map(\.element)
        #expect(SleepBalanceEngine.balance(history: four, needMinutes: need)?.minutes == nil)
    }

    @Test func theSeriesIsFourteenNightsOldestFirstAndEachIsItsOwnSevenNightBalance() throws {
        let history = SleepFixture.history(count: 20, asleep: { 400 + Double($0) * 5 })
        let result = try #require(SleepBalanceEngine.balance(history: history, needMinutes: need))
        #expect(result.series.count == 14)
        #expect(result.series.map(\.night) == history.suffix(14).map(\.night))
        #expect(result.series.last?.minutes == result.minutes)
        // Each point sums its own 7 nights.
        let byNight = Dictionary(uniqueKeysWithValues: history.map { ($0.night, $0.totals.asleep / 60) })
        for point in result.series {
            let expected = (0..<7).map { byNight[point.night.adding(days: -$0)]! - need }.reduce(0, +)
            #expect(point.minutes == expected)
        }
    }

    @Test func aSeriesPointIsNilWhereTheWindowHadTooFewNights() throws {
        let history = SleepFixture.history(count: 8)
        let result = try #require(SleepBalanceEngine.balance(history: history, needMinutes: need))
        #expect(result.series.prefix(6).allSatisfy { $0.minutes == nil }, "before five nights exist")
        #expect(result.series.last?.minutes != nil)
    }

    @Test func napsAreNotNights() throws {
        let nap = SleepFixture.samples(bedtime: Fixture.date(2026, 9, 22, 14), blocks: [(.core, 90)])
        let napSessions = SleepSessionEngine.history(from: nap, asOf: SleepFixture.now, timeZone: SleepFixture.zone).naps
        let history = SleepFixture.history(count: 7, asleep: { _ in 480 })
        #expect(SleepBalanceEngine.balance(history: history + napSessions, needMinutes: need)?.minutes == 0.0)
    }

    @Test func noNightsGiveNoResult() {
        #expect(SleepBalanceEngine.balance(history: [], needMinutes: need) == nil)
    }
}

// MARK: - Consistency

struct ConsistencyEngineTests {
    /// Sample standard deviation (n − 1).
    private func sd(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)).squareRoot()
    }

    @Test func bedtimeWakeAndDurationSpreadOverSevenNights() throws {
        let bedtimes: [Double] = [23, 23.5, 22.5, 23, 24, 22, 23]
        let asleep: [Double] = [450, 480, 430, 470, 400, 500, 460]
        let history = SleepFixture.history(count: 7, bedtime: { bedtimes[$0] }, asleep: { asleep[$0] })
        let result = try #require(ConsistencyEngine.consistency(history: history))
        let window = try #require(result.window(days: 7))
        let metrics = history.map(SleepMetricsEngine.metrics(for:))
        #expect(window.nights == 7)
        #expect(abs(window.bedtimeSD - sd(metrics.map(\.bedtimeMinutes))) < 1e-9)
        #expect(abs(window.wakeSD - sd(metrics.map(\.wakeMinutes))) < 1e-9)
        #expect(abs(window.durationSD - sd(asleep)) < 1e-9)
        #expect(abs(window.bedtimeMean - 660) < 1e-9)
        #expect(abs(window.midpointMinutes - (window.bedtimeMean + window.wakeMean) / 2) < 1e-9)
    }

    @Test func aPerfectlyRegularWeekHasNoSpread() throws {
        let history = SleepFixture.history(count: 7)
        let window = try #require(ConsistencyEngine.consistency(history: history)?.window(days: 7))
        #expect(window.bedtimeSD == 0 && window.wakeSD == 0 && window.durationSD == 0)
    }

    @Test func windowsAppearOnlyWithFiveRecordedNights() throws {
        #expect(ConsistencyEngine.consistency(history: SleepFixture.history(count: 4))?.windows.isEmpty == true)
        let ten = try #require(ConsistencyEngine.consistency(history: SleepFixture.history(count: 10)))
        #expect(ten.windows.map(\.days) == [7, 14, 30], "5+ recorded nights fill every window that reaches them")
        #expect(ten.window(days: 7)?.nights == 7)
        #expect(ten.window(days: 14)?.nights == 10)
        #expect(ten.window(days: 30)?.nights == 10)
    }

    @Test func eachWindowUsesOnlyItsOwnNights() throws {
        // The last 7 nights are steady; the 8 before them are all over.
        let history = SleepFixture.history(count: 15, bedtime: { $0 < 8 ? 21 + Double($0 % 4) * 1.5 : 23 })
        let result = try #require(ConsistencyEngine.consistency(history: history))
        #expect(result.window(days: 7)?.bedtimeSD == 0)
        #expect((result.window(days: 14)?.bedtimeSD ?? 0) > 30)
    }

    @Test func theMidpointIsHalfwayBetweenBedtimeAndWaking() throws {
        // 11:00 PM to 7:00 AM: the middle is 3:00 AM, 900 minutes after noon.
        let history = SleepFixture.history(count: 7, asleep: { _ in 480 })
        let result = try #require(ConsistencyEngine.consistency(history: history))
        #expect(result.lastMidpointMinutes == 900)
        #expect(result.window(days: 7)?.midpointMinutes == 900)
    }

    @Test func aWindowCanEndOnAnEarlierNight() throws {
        let history = SleepFixture.history(count: 12)
        let earlier = history[8].night
        #expect(ConsistencyEngine.consistency(history: history, endingAt: earlier)?.night == earlier)
        #expect(ConsistencyEngine.consistency(history: history, endingAt: earlier)?.window(days: 7)?.nights == 7)
    }
}

// MARK: - Timing

struct SleepTimingEngineTests {
    @Test func medianOfOddAndEvenCounts() {
        #expect(SleepTimingEngine.median([3, 1, 2]) == 2)
        #expect(SleepTimingEngine.median([4, 1, 3, 2]) == 2.5)
        #expect(SleepTimingEngine.median([]) == nil)
    }

    @Test func usualBedtimeAndWakeAreTheBaselineOfTheFourteenNightsBeforeLastNightWithFiveNeeded() throws {
        let bedtimes: [Double] = [23, 23, 23.5, 0.5 + 24, 23, 23, 22.5]
        let history = SleepFixture.history(count: 7, bedtime: { bedtimes[$0] })
        let timing = try #require(SleepTimingEngine.timing(history: history))
        // The mean of the six nights before the last one (the late night, 12:30 AM, is among them): 11:20 PM.
        #expect(abs(try #require(timing.typicalBedtime) - 680) < 0.001, "the baseline, never the last night itself")
        #expect(timing.nights == 6)
        #expect(SleepTimingEngine.timing(history: SleepFixture.history(count: 4))?.typicalBedtime == nil)
    }

    @Test func theRecentShiftIsTheLastSevenAgainstTheFourteenBefore() throws {
        // 14 nights at 11:00 PM, then 7 at 11:30 PM, sleeping 30 minutes
        // less: bedtime moved, waking didn't.
        let history = SleepFixture.history(count: 21, bedtime: { $0 < 14 ? 23 : 23.5 }, asleep: { $0 < 14 ? 480 : 450 })
        let shift = try #require(SleepTimingEngine.timing(history: history)?.recentShift)
        #expect(shift.bedtimeMinutes == 30.0)
        #expect(shift.wakeMinutes == 0.0, "the wake time didn't move")
    }

    @Test func noShiftWithoutFiveNightsInBothWindows() throws {
        #expect(SleepTimingEngine.timing(history: SleepFixture.history(count: 10))?.recentShift == nil)
    }

    @Test func aSuggestedRangeNeedsFourteenNightsInTheLastThirty() throws {
        #expect(SleepTimingEngine.timing(history: SleepFixture.history(count: 13))?.suggested == nil)
        let timing = try #require(SleepTimingEngine.timing(history: SleepFixture.history(count: 14)))
        let suggested = try #require(timing.suggested)
        // A perfectly regular sleeper: the range is the 30-minute minimum, around their time.
        #expect(abs((suggested.bedtime.upperBound - suggested.bedtime.lowerBound) - 30) < 1e-9)
        #expect(suggested.bedtime.contains(660))
    }

    @Test func theSuggestedRangeIsTheMiddleHalfOfYourOwnNights() throws {
        // 16 nights spread evenly ±60 min around 11:00 PM: the middle half is about ±30.
        let offsets = (0..<16).map { Double($0) / 15 * 2 - 1 }
        let history = SleepFixture.history(count: 16, bedtime: { 23 + offsets[$0] })
        let range = try #require(SleepTimingEngine.timing(history: history)?.suggested?.bedtime)
        #expect(range.upperBound - range.lowerBound > 30)
        #expect(range.upperBound - range.lowerBound < 120)
        #expect(abs((range.lowerBound + range.upperBound) / 2 - 660) < 5)
    }

    @Test func percentilesInterpolate() {
        #expect(SleepTimingEngine.percentile([1, 2, 3, 4, 5], 0.25) == 2)
        #expect(SleepTimingEngine.percentile([1, 2, 3, 4], 0.5) == 2.5)
        #expect(SleepTimingEngine.percentile([], 0.5) == nil)
    }
}
