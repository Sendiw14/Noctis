import Foundation
import Testing
@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepKit

private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

// MARK: - Why

/// What moved today's recovery most: the factor furthest outside its
/// normal range (usual ± 1 SD), by weight × SDs.
struct RecoveryWhyTests {
    /// Usual: 450 min asleep ± 30, 11:00 PM ± 20, 7:00 AM ± 20, HRV 50 ± 5,
    /// resting 55 ± 2.
    private let baselines = Baselines(
        sleepDuration: Baseline(value: 450, nights: 14, standardDeviation: 30),
        bedtime: Baseline(value: 660, nights: 14, standardDeviation: 20),
        wakeTime: Baseline(value: 1140, nights: 14, standardDeviation: 20),
        hrv: Baseline(value: 50, nights: 14, standardDeviation: 5),
        restingHeartRate: Baseline(value: 55, nights: 14, standardDeviation: 2)
    )

    private func night(asleep: Double = 450, bedtime: Double = 660, wake: Double = 1140, hrv: Double? = 50, resting: Double? = 55) -> NightMetrics {
        NightMetrics(night: SleepNightKey(year: 2026, month: 9, day: 23), wakeTime: Fixture.date(2026, 9, 24, 7),
                     asleepMinutes: asleep, bedtimeMinutes: bedtime, wakeMinutes: wake, hrv: hrv, restingHeartRate: resting)
    }

    private func result(_ night: NightMetrics, delta: Int = -8) -> RecoveryResult {
        RecoveryEngine.score(lastNight: night, baselines: baselines, baselineNights: 14, needMinutes: 480)
            .with(comparison: RecoveryComparison(baseline: 70, nights: 14, delta: delta))
    }

    private func why(_ night: NightMetrics) -> String? {
        HomeScreenBuilder.scoredContent(result(night)).why
    }

    @Test func allWithinTheirNormalRangeSaysNothingMore() {
        // Every factor within 1 SD (exactly 1 SD still counts as within).
        let steady = result(night(asleep: 480, bedtime: 680, wake: 1120, hrv: 45, resting: 57))
        #expect(steady.topContributor == nil)
        let content = HomeScreenBuilder.scoredContent(steady)
        #expect(content.why == nil)
        #expect(content.comparisonPhrase == "In line with your usual")
    }

    @Test func aShortNight() {
        let contributor = result(night(asleep: 380)).topContributor
        #expect(contributor?.measure == .sleepDuration)
        #expect(contributor?.direction == .below)
        #expect(why(night(asleep: 380)) == "Mostly: sleep was 1h 10m shorter than usual")
        #expect(HomeScreenBuilder.scoredContent(result(night(asleep: 380))).comparisonPhrase == "vs your usual")
    }

    @Test func aLongNight() {
        #expect(why(night(asleep: 520)) == "Mostly: sleep was 1h 10m longer than usual")
    }

    @Test func hrvAboveAndBelow() {
        #expect(why(night(hrv: 61)) == "Mostly: HRV above your normal range")
        #expect(why(night(hrv: 39)) == "Mostly: HRV below your normal range")
    }

    @Test func restingHeartRateAboveAndBelow() {
        #expect(why(night(resting: 59)) == "Mostly: resting heart rate above your normal range")
        #expect(why(night(resting: 51)) == "Mostly: resting heart rate below your normal range")
    }

    @Test func bedtimeLaterAndEarlier() {
        #expect(why(night(bedtime: 705)) == "Mostly: bedtime 45 min later than usual")
        #expect(why(night(bedtime: 615)) == "Mostly: bedtime 45 min earlier than usual")
    }

    @Test func wakeUpNamesItselfWhenItIsFurtherOff() {
        // Bedtime 25 min late (1.25 SD), wake-up 1h late (3 SD).
        let contributor = result(night(bedtime: 685, wake: 1200)).topContributor
        #expect(contributor?.measure == .wakeTime)
        #expect(why(night(bedtime: 685, wake: 1200)) == "Mostly: wake-up 1h later than usual")
        #expect(why(night(wake: 1080)) == "Mostly: wake-up 1h earlier than usual")
    }

    @Test func theLargestWeightedDeviationWins() {
        // Sleep −70 min: 2.33 SD × 35% = 0.82; HRV −10 ms: 2 SD × 25% = 0.5.
        #expect(result(night(asleep: 380, hrv: 40)).topContributor?.measure == .sleepDuration)
        // HRV −15 ms: 3 SD × 25% = 0.75; sleep −40 min: 1.33 SD × 35% = 0.47.
        #expect(result(night(asleep: 410, hrv: 35)).topContributor?.measure == .hrv)
    }

    @Test func spreadsAreFlooredSoATinyWindowDoesNotShout() {
        let steadyWindow = Baselines(
            sleepDuration: Baseline(value: 450, nights: 14, standardDeviation: 2),
            bedtime: Baseline(value: 660, nights: 14, standardDeviation: 1),
            wakeTime: Baseline(value: 1140, nights: 14, standardDeviation: 1),
            hrv: nil, restingHeartRate: nil
        )
        // 12 minutes off: under the 15-minute floors, so within.
        let scored = RecoveryEngine.score(lastNight: night(asleep: 462, bedtime: 672, hrv: nil, resting: nil),
                                          baselines: steadyWindow, baselineNights: 14, needMinutes: 480)
        #expect(scored.topContributor == nil)
    }

    @Test func theHeroReadsTheWhyAloud() {
        let label = HomeScreenBuilder.scoredContent(result(night(asleep: 380))).accessibilityLabel
        #expect(label.contains("Mostly, sleep was 1 hour 10 minutes shorter than usual."))
    }

    @Test func detailRangesUseTheSameNormalRange() {
        // 1 SD is the line everywhere: 55 ms (1 SD) is within, 56 is above.
        let within = result(night(hrv: 55)).factor(.hrv)
        let above = result(night(hrv: 56)).factor(.hrv)
        #expect(within?.range == .within)
        #expect(above?.range == .above)
    }
}

// MARK: - Sparklines

struct RecoveryHistoryTests {
    @Test func eachFactorKeepsFourteenNightsAgainstItsNormalRange() throws {
        // 14 nights alternating around 450 min / 11 PM / 50 ms / 55 bpm,
        // then last night.
        let history = Fixture.metrics(count: 15) { index in
            guard index < 14 else { return (asleep: 400, bedtime: 700, wake: 1140, hrv: 60, resting: 55) }
            let up = index.isMultiple(of: 2)
            return (asleep: up ? 440 : 460, bedtime: up ? 650 : 670, wake: up ? 1130 : 1150, hrv: up ? 45 : 55, resting: up ? 54 : 56)
        }
        guard case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: Fixture.morningAfter) else {
            Issue.record("expected a score")
            return
        }
        #expect(result.histories.map(\.kind) == [.sleepDuration, .sleepConsistency, .hrv, .restingHeartRate])
        let hrv = try #require(result.history(.hrv))
        #expect(hrv.values.count == 14)
        #expect(hrv.values.allSatisfy { $0 != nil })
        #expect(hrv.today == 60)
        #expect(hrv.usual == 50)
        // Every window night is within usual ± 1 SD (sample SD ≈ 5.19).
        #expect(hrv.nightsWithin == 14 && hrv.nightsRecorded == 14)
        let sleep = try #require(result.history(.sleepDuration))
        // Sample SD ≈ 10.4, floored to 15: 440 and 460 are within.
        #expect(sleep.standardDeviation == 15)
        #expect(sleep.nightsWithin == 14)
        // Consistency is drawn as bedtime.
        #expect(try #require(result.history(.sleepConsistency)).today == 700)
    }

    @Test func missingNightsStayEmptyAndFewerThanFiveMeansNoSparkline() throws {
        // HRV on only 3 window nights: no HRV baseline, so no HRV sparkline.
        let history = Fixture.metrics(count: 15) { index in
            (asleep: 450, bedtime: 660, wake: 1140, hrv: index >= 11 ? 50 : nil, resting: 55)
        }
        guard case .scored(let result) = RecoveryEngine.evaluate(history: history, needMinutes: 480, asOf: Fixture.morningAfter) else {
            Issue.record("expected a score")
            return
        }
        #expect(result.history(.hrv) == nil)
        #expect(result.history(.restingHeartRate) != nil)
    }

    @Test func theSparklineSaysHowManyNightsWereNormal() {
        let history = RecoveryFactorHistory(kind: .hrv, values: [50, 52, nil, 70, 48] + Array(repeating: 50, count: 9), today: 61, usual: 50, standardDeviation: 5)
        let content = HomeScreenBuilder.sparklineContent(history)
        #expect(content.accessibilityLabel == "HRV has been within your normal range on 12 of 13 nights.")
        #expect(content.nights.count == 14)
        #expect(content.nights[2] == nil)
        // Everything lands inside the chart, with the band in between.
        let values = content.nights.compactMap { $0 } + [content.today, content.band.lowerBound, content.band.upperBound]
        #expect(values.allSatisfy { (0...1).contains($0) })
        #expect(content.band.lowerBound < content.band.upperBound)
    }
}

// MARK: - Heart rate

struct NightHeartSeriesTests {
    private let start = Fixture.date(2026, 9, 23, 23)
    private let end = Fixture.date(2026, 9, 24, 7)

    private func sample(_ minutes: Double, _ bpm: Double) -> HeartRateSample {
        HeartRateSample(date: start.addingTimeInterval(minutes * 60), bpm: bpm, sourceName: "Watch")
    }

    @Test func noSamplesMeansNoStrip() {
        #expect(NightHeartSeries.build(samples: [], from: start, to: end) == nil)
        // Samples outside the night don't count.
        #expect(NightHeartSeries.build(samples: [sample(-30, 70), sample(500, 70)], from: start, to: end) == nil)
    }

    @Test func aFewSamplesAreKeptAsTheyAre() throws {
        let series = try #require(NightHeartSeries.build(samples: [sample(240, 48), sample(0, 60), sample(480, 58)], from: start, to: end))
        #expect(series.points.map(\.position) == [0, 0.5, 1])
        #expect(series.points.map(\.bpm) == [60, 48, 58])
        #expect(series.lowest == NightHeartSeries.Point(position: 0.5, bpm: 48))
    }

    @Test func aDenseNightIsAveragedDownTo120Points() throws {
        // A sample every minute: 481 samples.
        let samples = (0...480).map { sample(Double($0), 50 + Double($0 % 10)) }
        let series = try #require(NightHeartSeries.build(samples: samples, from: start, to: end))
        #expect(series.points.count == NightHeartSeries.maxPoints)
        #expect(series.points.allSatisfy { (50...59).contains($0.bpm) })
        #expect(zip(series.points, series.points.dropFirst()).allSatisfy { $0.position < $1.position })
    }

    @Test func heartRateIsReadBetweenPoints() throws {
        let series = try #require(NightHeartSeries.build(samples: [sample(0, 60), sample(240, 50)], from: start, to: end))
        #expect(series.bpm(at: 0.25) == 55)
        #expect(series.bpm(at: 0.75) == nil)
    }
}

// MARK: - Night chart

struct NightChartV3Tests {
    private let now = Fixture.date(2026, 9, 24, 10)
    private let locale = Locale(identifier: "en_US")

    private func chart(_ samples: [RawSleepSample], heart: [HeartRateSample] = []) throws -> NightChartContent {
        let snapshot = HomeSnapshotBuilder.build(HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: heart),
                                                 profile: UserProfileSnapshot(), now: now, timeZone: Fixture.newYork)
        let screen = HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: locale)
        return try #require(screen.lastNight?.chart)
    }

    @Test func oneStageInARowIsOneBarWhateverLiesBetween() throws {
        // Core, an in-bed-only gap, core again: one run.
        let chart = try chart([
            Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 1), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 1, 10), Fixture.date(2026, 9, 24, 3), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 3), Fixture.date(2026, 9, 24, 7), .deep),
        ])
        #expect(chart.spans.map(\.stage) == [.core, .deep])
        #expect(chart.spans[0].end == chart.spans[1].start)
        #expect(chart.connectors.count == 1)
    }

    @Test func aBriefAwakeningIsATick() throws {
        let chart = try chart([
            Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 2), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 2), Fixture.date(2026, 9, 24, 2, 2), .awake),
            Fixture.sample(Fixture.date(2026, 9, 24, 2, 2), Fixture.date(2026, 9, 24, 4), .rem),
            Fixture.sample(Fixture.date(2026, 9, 24, 4), Fixture.date(2026, 9, 24, 4, 10), .awake),
            Fixture.sample(Fixture.date(2026, 9, 24, 4, 10), Fixture.date(2026, 9, 24, 7), .core),
        ])
        #expect(chart.spans.map(\.isTick) == [false, true, false, false, false])
    }

    @Test func stepsJoinOnlyBarsThatTouch() throws {
        // A 30-minute hole between core and deep: no step across it.
        let chart = try chart([
            Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 1), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 1, 30), Fixture.date(2026, 9, 24, 7), .deep),
        ])
        #expect(chart.connectors.isEmpty)
        // A one-minute hole closes, and the step appears.
        let joined = try self.chart([
            Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 1), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 1, 1), Fixture.date(2026, 9, 24, 7), .deep),
        ])
        #expect(joined.connectors == [NightConnector(position: joined.spans[1].start, from: .core, to: .deep)])
        #expect(joined.spans[0].end == joined.spans[1].start)
    }

    @Test func stageTotalsAreMetrics() throws {
        let chart = try chart([
            Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 1), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 1), Fixture.date(2026, 9, 24, 2, 32), .rem),
            Fixture.sample(Fixture.date(2026, 9, 24, 2, 32), Fixture.date(2026, 9, 24, 7), .deep),
        ])
        #expect(chart.laneTotals.map(\.lane) == [.awake, .rem, .core, .deep])
        #expect(chart.laneTotals[1].duration.plain == "1h 32m")
        #expect(chart.laneTotals[1].duration.spoken == "1 hour 32 minutes")
        #expect(chart.laneTotals[1].text == "REM · 1h 32m")
    }

    @Test func thePillAddsHeartRateWhenThereIsSome() throws {
        let samples = [
            Fixture.sample(Fixture.date(2026, 9, 23, 23), Fixture.date(2026, 9, 24, 3), .core),
            Fixture.sample(Fixture.date(2026, 9, 24, 3), Fixture.date(2026, 9, 24, 7), .rem),
        ]
        let heart = [0, 120, 240, 360, 480].map { minutes in
            HeartRateSample(date: Fixture.date(2026, 9, 23, 23).addingTimeInterval(Double(minutes) * 60), bpm: minutes == 240 ? 48 : 56, sourceName: "Watch")
        }
        let chart = try chart(samples, heart: heart)
        let reading = try #require(chart.reading(at: 0.5))
        #expect(plain(reading.text) == "3:00 AM · REM · 4h · 48 bpm")
        #expect(plain(reading.spoken) == "3:00 AM, REM, 4 hours, 48 beats per minute")
        let strip = try #require(chart.heart)
        #expect(strip.lowestLabel == "min 48 bpm")
        #expect(strip.lowest.position == 0.5)
        #expect(strip.low < 48 && strip.high > 56)
        // Without heart rate the pill says nothing about it.
        #expect(try self.chart(samples).reading(at: 0.5).map { plain($0.text) } == "3:00 AM · REM · 4h")
        #expect(try self.chart(samples).heart == nil)
    }
}

// MARK: - Share card

struct ShareCardHeartRateTests {
    @Test func theShareCardShowsNoHeartRateUnlessDetailsAreOn() async throws {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let snapshot = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        let screen = HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        let share = try #require(screen.share)
        #expect(share.chart?.heart != nil, "the night has heart rate")
        #expect(share.chart(includeDetails: false)?.heart == nil)
        #expect(share.chart(includeDetails: true)?.heart != nil)
        // Everything else about the chart is the same either way.
        #expect(share.chart(includeDetails: false)?.spans == share.chart?.spans)
        #expect(share.chart(includeDetails: false)?.laneTotals == share.chart?.laneTotals)
    }
}

// MARK: - Week columns

struct WeekColumnTests {
    private let outset: CGFloat = 40

    /// A tap area for a phone `screen` points wide: 20pt margins, then
    /// 20pt card padding, then the bars.
    private func barsWidth(screen: CGFloat) -> CGFloat { screen - 2 * outset }

    @Test func tapsLandInTheColumnABarSitsIn() {
        let bars = barsWidth(screen: 390)
        let column = bars / 7
        for index in 0..<7 {
            // The middle of the bar's column, and both of its edges (just inside).
            for fraction in [0.05, 0.5, 0.95] {
                let x = outset + column * (CGFloat(index) + fraction)
                #expect(WeekColumns.index(x: x, barsWidth: bars, outset: outset, count: 7) == index, "column \(index) at \(fraction)")
            }
        }
    }

    @Test func theOuterColumnsTakeThePaddingAndTheMargin() {
        let bars = barsWidth(screen: 390)
        #expect(WeekColumns.index(x: 0, barsWidth: bars, outset: outset, count: 7) == 0)
        #expect(WeekColumns.index(x: 8, barsWidth: bars, outset: outset, count: 7) == 0)
        #expect(WeekColumns.index(x: outset + bars + outset, barsWidth: bars, outset: outset, count: 7) == 6)
        #expect(WeekColumns.index(x: outset + bars + 30, barsWidth: bars, outset: outset, count: 7) == 6)
    }

    @Test func aBarsRightEdgeNeverSelectsItsNeighbor() {
        // The bug this replaces: cells of card-width / 7 sat up to 5pt off
        // their bars, so the first bar's right edge picked the second.
        let bars = barsWidth(screen: 320)
        let column = bars / 7
        let firstBarRightEdge = outset + column * 0.5 + 8
        #expect(WeekColumns.index(x: firstBarRightEdge, barsWidth: bars, outset: outset, count: 7) == 0)
        let lastBarLeftEdge = outset + column * 6.5 - 8
        #expect(WeekColumns.index(x: lastBarLeftEdge, barsWidth: bars, outset: outset, count: 7) == 6)
    }

    @Test func interiorColumnWidthsAtRealScreenWidths() {
        // Seven bars in one card: 34pt columns at 320, 42pt on an SE (375),
        // 44pt from 390. The bars' spacing, not a choice.
        #expect(abs(WeekColumns.width(barsWidth: barsWidth(screen: 320), count: 7) - 34.29) < 0.01)
        #expect(abs(WeekColumns.width(barsWidth: barsWidth(screen: 375), count: 7) - 42.14) < 0.01)
        #expect(abs(WeekColumns.width(barsWidth: barsWidth(screen: 390), count: 7) - 44.29) < 0.01)
    }
}

// MARK: - Unit typography

struct NoctisMetricTests {
    @Test func durationsSplitIntoNumbersAndUnits() {
        #expect(HomeFormat.durationMetric(402).parts == [.number("6"), .unit("h"), .space, .number("42"), .unit("m")])
        #expect(HomeFormat.durationMetric(480).parts == [.number("8"), .unit("h")])
        #expect(HomeFormat.durationMetric(45).parts == [.number("45"), .unit("m")])
        #expect(HomeFormat.durationMetric(0).plain == "0m")
    }

    @Test func voiceOverHearsWords() {
        #expect(HomeFormat.durationMetric(402).spoken == "6 hours 42 minutes")
        #expect(HomeFormat.spokenDuration(60) == "1 hour")
        #expect(HomeFormat.spokenDuration(61) == "1 hour 1 minute")
        #expect(HomeFormat.spokenDuration(45) == "45 minutes")
        #expect(HomeFormat.quantityMetric(52, unit: "bpm", spokenUnit: "beats per minute").spoken == "52 beats per minute")
    }

    @Test func clockPeriodsAreUnits() {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        #expect(format.clockMetric(format.clock(minutesSinceMidnight: 23 * 60)).parts == [.number("11:00"), .unit("PM")])
        let twentyFour = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_GB"))
        #expect(twentyFour.clockMetric(twentyFour.clock(minutesSinceMidnight: 23 * 60)).parts == [.number("23:00")])
    }

    @Test func unitsAreHalfSizeAndOnePointAway() {
        #expect(NoctisMetric.unitScale == 0.5)
        #expect(NoctisMetric.unitGap == 1)
    }
}

// MARK: - Insight evidence

struct InsightCardWordingTests {
    private let format = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))

    private func history(lastAsleep: Double = 420, lastBedtime: Double = 660, bedtimes: ((Int) -> Double)? = nil) -> [NightMetrics] {
        Fixture.metrics(count: 15) { index in
            let isLast = index == 14
            return (asleep: isLast ? lastAsleep : 420, bedtime: isLast ? lastBedtime : (bedtimes?(index) ?? 660), wake: 1140, hrv: nil, resting: nil)
        }
    }

    private func card(_ history: [NightMetrics]) throws -> InsightCardContent {
        HomeScreenBuilder.insightCard(try #require(InsightEngine.topInsight(history: history, asOf: Fixture.morningAfter)), format: format)
    }

    @Test func aShorterNightComparesTwoBars() throws {
        let card = try card(history(lastAsleep: 350))
        #expect(card.title == "Shorter night than usual")
        #expect(card.message == "1h 10m less than your usual.")
        guard case .comparison(let lastNight, let usual) = card.chart else {
            Issue.record("expected bars")
            return
        }
        #expect(lastNight.label == "Last night" && lastNight.value.plain == "5h 50m")
        #expect(usual.label == "Usual" && usual.value.plain == "7h")
        #expect(usual.fraction == 1 && abs(lastNight.fraction - 350.0 / 420) < 1e-9)
        #expect(card.accessibilityLabel == "Shorter night than usual. Last night 5 hours 50 minutes; usual 7 hours.")
    }

    @Test func aLaterBedtimeMarksBothOnATimeAxis() throws {
        let card = try card(history(lastBedtime: 715))
        #expect(card.title == "Later bedtime than usual")
        #expect(card.message == "55 min later than your usual.")
        guard case .timeline(let usual, let lastNight) = card.chart else {
            Issue.record("expected a time axis")
            return
        }
        #expect(plain(usual.time) == "11:00 PM" && plain(lastNight.time) == "11:55 PM")
        // 10 PM to 1 AM: usual a third along, last night later.
        #expect(abs(usual.position - 1.0 / 3) < 1e-9)
        #expect(lastNight.position > usual.position)
        #expect(plain(card.accessibilityLabel) == "Later bedtime than usual. Last night 11:55 PM; usual 11:00 PM.")
    }

    @Test func aStreakIsARowOfNights() throws {
        let card = try card(history(bedtimes: { $0 < 10 ? ($0.isMultiple(of: 2) ? 615 : 705) : 660 }))
        #expect(card.title == "Steady bedtime")
        #expect(card.message == "5 nights in a row within 30 min of your usual bedtime.")
        guard case .nights(let dots) = card.chart else {
            Issue.record("expected dots")
            return
        }
        #expect(dots.map(\.within) == [false, false, true, true, true, true, true])
        // Mornings Fri Sep 18 … Thu Sep 24.
        #expect(dots.map(\.label) == ["F", "S", "S", "M", "T", "W", "T"])
        #expect(card.accessibilityLabel.hasSuffix("5 of the last 7 nights."))
    }

    @Test func noInsightClaimsACause() throws {
        let cards = try [
            card(history(lastAsleep: 300)), card(history(lastAsleep: 500)),
            card(history(lastBedtime: 740)), card(history(lastBedtime: 580)), card(history()),
        ]
        let causal = ["because", "caused", "cause", "due to", "led to", "leads to", "so you", "result", "thanks to", "helped", "made you"]
        for card in cards {
            let text = (card.title + " " + card.message + " " + card.accessibilityLabel).lowercased()
            for word in causal {
                #expect(!text.contains(word), "\"\(word)\" in: \(text)")
            }
        }
    }
}

// MARK: - Header, learning, reveal

struct HomeV3ScreenTests {
    private let locale = Locale(identifier: "en_US")

    @Test func eveningModeAlwaysSaysGoodEvening() {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
        for hour in [10, 15, 19, 1] {
            let header = HomeScreenBuilder.header(now: Fixture.date(2026, 9, 24, hour), newestSample: nil, mode: .evening, summary: .text(""), format: format)
            #expect(header.greeting == "Good evening.", "at \(hour):00")
        }
        let day = HomeScreenBuilder.header(now: Fixture.date(2026, 9, 24, 15), newestSample: nil, mode: .day, summary: .text(""), format: format)
        #expect(day.greeting == "Good afternoon.")
    }

    @Test func learningCountsNightsForTheDots() async {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = MockHealthKitProvider(scenario: .learning, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let snapshot = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        let screen = HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: locale)
        #expect(screen.recovery == .learning(nights: 3, required: 5, text: "3 of 5 nights"))
    }

    @Test func aTouchSkipsTheReveal() async {
        let store = UserDefaults(suiteName: "noctis.tests.\(UUID().uuidString)")!
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let model = HomeViewModel(repository: HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }),
                                  profile: { UserProfileSnapshot() }, introGate: HomeIntroGate(defaults: store), reduceMotion: { false },
                                  clock: { now }, calendar: Fixture.calendar(), locale: locale)
        await model.refresh()
        #expect(model.reveal == .pending)
        model.beginReveal()
        #expect(model.reveal == .playing)
        model.skipReveal()
        #expect(model.reveal == .none)
        #expect(model.revealSkips == 1)
        // Nothing to skip once it's over.
        model.skipReveal()
        #expect(model.revealSkips == 1)
        model.stopObserving()
    }
}
