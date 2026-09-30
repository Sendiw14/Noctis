import Foundation
import Testing
@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepFeature
@testable import SleepKit

// The Week and Month content: the bars and their pills, the consistency,
// balance and timing wording, the month's labels, markers and quality strip.
// Every number is one the engines produced; these tests pin how it's said.

private let locale = Locale(identifier: "en_US")
private let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
private let lastNight = SleepNightKey(year: 2026, month: 9, day: 23)

/// A snapshot of `count` nights ending on Sep 23 (`skipping` some of them),
/// every one staged, on an 8h need.
private func snapshot(
    count: Int, skipping: Set<Int> = [], bedtime: (Int) -> Double = { _ in 23 }, asleep: (Int) -> Double = { _ in 450 }
) -> SleepSnapshot {
    let samples = (0..<count).filter { !skipping.contains($0) }.flatMap { index -> [RawSleepSample] in
        let key = lastNight.adding(days: index - (count - 1))
        return SleepFixture.night(key, hour: bedtime(index), blocks: SleepFixture.staged(asleep: asleep(index)), inBed: true)
    }
    return SleepSnapshotBuilder.build(
        HomeHealthInputs(sleep: samples, hrv: [], restingHeartRate: [], heartRate: []),
        profile: UserProfileSnapshot(), now: SleepFixture.now, timeZone: SleepFixture.zone
    )
}

private func screen(_ snap: SleepSnapshot, night: SleepNightKey? = nil, range: SleepRange) -> SleepScreen {
    let selection = SleepSelection(night: night ?? snap.defaultNight, range: range)
    let model = SleepRenderModelBuilder.build(snap, selection: selection)
    return SleepScreenBuilder.build(snap, model: model, selection: selection, now: SleepFixture.now, calendar: Fixture.calendar(), locale: locale)
}

/// A week of nights where the last one differs: `last` minutes asleep, the
/// rest on the 8h need.
private func week(lastAsleep last: Double) -> SleepScreen {
    screen(snapshot(count: 7, asleep: { $0 == 6 ? last : 480 }), range: .week)
}

// MARK: - Balance

struct SleepBalanceWordingTests {
    @Test func behindAndAheadAreSaidInHoursAndTwoDigitMinutes() throws {
        let behind = try #require(week(lastAsleep: 355).insights?.balance)
        #expect(behind.direction == .behind)
        #expect(behind.headline == "2h 05m behind")
        #expect(behind.value?.spoken == "2 hours 5 minutes")
        #expect(behind.directionWord == "behind")

        let ahead = try #require(week(lastAsleep: 550).insights?.balance)
        #expect(ahead.direction == .ahead)
        #expect(ahead.headline == "1h 10m ahead")
        #expect(ahead.value?.spoken == "1 hour 10 minutes")
    }

    @Test func aBalanceUnderAnHourHasNoHoursAndAWholeHourHasNoMinutes() throws {
        #expect(try #require(week(lastAsleep: 435).insights?.balance).headline == "45m behind")
        #expect(try #require(week(lastAsleep: 360).insights?.balance).headline == "2h behind")
    }

    @Test func withinAFewMinutesOfTheNeedItIsEvenNotBehindOrAhead() throws {
        let even = try #require(week(lastAsleep: 477).insights?.balance)
        #expect(even.direction == .even)
        #expect(even.headline == "Even with your need")
        #expect(even.value == nil && even.directionWord == nil)
    }

    @Test func fewerThanFiveRecordedNightsGivesNoBalanceAndSaysSo() throws {
        let content = try #require(screen(snapshot(count: 4), range: .week).insights?.balance)
        #expect(content.direction == .unavailable)
        #expect(content.headline == "Not enough nights yet")
        #expect(content.caption == "A balance needs 5 recorded nights out of the last 7.")
    }

    @Test func theCaptionNamesTheNeedTheBalanceIsAgainst() throws {
        let content = try #require(week(lastAsleep: 355).insights?.balance)
        #expect(content.caption == "Over the last 7 nights, against your 8h need.")
    }

    @Test func theExplanationSaysItComparesActualSleepWithYourNeedOverSevenNights() throws {
        let content = try #require(week(lastAsleep: 355).insights?.balance)
        let text = content.explanation.joined(separator: " ")
        #expect(text.contains("sleep you actually got with your sleep need over 7 nights"))
        #expect(text.contains("time asleep minus your 8h need"))
        #expect(text.contains("not counted as zero"))
        #expect(text.contains("isn't a medical measure"))
    }

    @Test func nothingAboutABalanceSaysDebt() throws {
        for asleep in [355.0, 550, 477] {
            let content = try #require(week(lastAsleep: asleep).insights?.balance)
            let words = ([content.headline, content.caption, content.accessibilityLabel] + content.explanation).joined(separator: " ").lowercased()
            #expect(!words.contains("debt") && !words.contains("owe") && !words.contains("deficit"))
        }
    }

    @Test func theMetricPadsMinutesNextToHours() {
        #expect(SleepScreenBuilder.balanceValue(125).plain == "2h 05m")
        #expect(SleepScreenBuilder.balanceValue(70).plain == "1h 10m")
        #expect(SleepScreenBuilder.balanceValue(45).plain == "45m")
        #expect(SleepScreenBuilder.balanceValue(120).plain == "2h")
    }

    @Test func theSparklineCarriesFourteenNightsAndWhereZeroSits() throws {
        let snap = snapshot(count: 21, asleep: { $0 < 14 ? 420 : 500 })
        let model = SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.defaultNight, range: .week))
        let chart = try #require(model.balanceRender)
        #expect(chart.points.count == 14)
        #expect((0.0...1.0).contains(chart.zero))
        // Behind, then ahead: the line ends above where zero sits.
        let end = try #require(chart.points.last ?? nil)
        #expect(end > chart.zero)
    }
}

// MARK: - Consistency

struct SleepConsistencyWordingTests {
    @Test func bedtimeVariedByTheWeeksStandardDeviation() throws {
        // Bedtimes 11:00 and 11:30 PM alternating: a sample SD of 16 minutes.
        let snap = snapshot(count: 7, bedtime: { $0.isMultiple(of: 2) ? 23 : 23.5 })
        let content = try #require(screen(snap, range: .week).insights?.consistency)
        #expect(content.isAvailable)
        #expect(content.headline == "Bedtime varied by 16 min")
        #expect(content.subline.hasPrefix("Wake time varied by "))
        #expect(content.subline.hasSuffix("over the last 7 nights."))
        #expect(content.accessibilityLabel.contains("Bedtime varied by 16 minutes"))
    }

    @Test func aSteadyWeekVariedByNothing() throws {
        let content = try #require(screen(snapshot(count: 7), range: .week).insights?.consistency)
        #expect(content.headline == "Bedtime varied by 0 min")
    }

    @Test func aLongSpreadIsSaidInHoursAndMinutes() {
        #expect(SleepScreenBuilder.spreadText(74) == "1h 14m")
        #expect(SleepScreenBuilder.spreadText(32.4) == "32 min")
    }

    @Test func underFiveRecordedNightsSaysWhatItNeeds() throws {
        let content = try #require(screen(snapshot(count: 4), range: .week).insights?.consistency)
        #expect(!content.isAvailable)
        #expect(content.headline == "Consistency needs 5 recorded nights")
        #expect(content.spread == nil)
    }

    @Test func theSheetListsEachWindowThatHasEnoughNights() throws {
        let content = try #require(screen(snapshot(count: 30), range: .week).insights?.consistency)
        #expect(content.windows.map(\.title) == ["Last 7 nights", "Last 14 nights", "Last 30 nights"])
        #expect(content.windows.allSatisfy { !$0.bedtime.isEmpty && !$0.wake.isEmpty && !$0.duration.isEmpty })
        #expect(content.midpoint?.hasPrefix("Sleep midpoint ") == true)
    }

    @Test func aRowPerNightWithTheWeekdayInitialAndTheUsualBandOnceThereAreFiveNights() throws {
        let content = try #require(screen(snapshot(count: 10), range: .week).insights?.consistency)
        #expect(content.rowLabels == ["F", "S", "S", "M", "T", "W", "T"])
        #expect(content.chart.rows.count == 7)
        #expect(content.usualCaption == "Shaded: your usual bedtime and wake time")
        #expect(content.chart.bedtimeBand != nil && content.chart.wakeBand != nil)
        let none = try #require(screen(snapshot(count: 4), range: .week).insights?.consistency)
        #expect(none.usualCaption == nil)
    }
}

// MARK: - Timing

struct SleepTimingWordingTests {
    @Test func typicalTimesAndTheMidpointAreTheMediansOfTheLastFourteenNights() throws {
        let timing = try #require(screen(snapshot(count: 14), range: .week).insights?.timing)
        #expect(timing.isAvailable)
        #expect(timing.typicalBedtime?.spoken == format.clock(minutesSinceMidnight: 23 * 60))
        // 450 minutes after 11:00 PM.
        #expect(timing.typicalWake?.spoken == format.clock(minutesSinceMidnight: 6 * 60 + 30))
        #expect(timing.midpoint?.spoken == format.clock(minutesSinceMidnight: 2 * 60 + 45))
        #expect(timing.nightsLine == "Medians of your last 14 nights · 14 recorded")
    }

    @Test func aRecentShiftIsWordedAgainstTheFourteenNightsBefore() throws {
        let snap = snapshot(count: 21, bedtime: { $0 >= 14 ? 23.5 : 23 })
        let timing = try #require(screen(snap, range: .week).insights?.timing)
        #expect(timing.shift == "Over the last 7 nights: bedtime 30 min later, wake time 30 min later, compared with the 14 nights before.")
    }

    @Test func aSmallShiftIsAboutTheSame() {
        let text = SleepScreenBuilder.shiftText(SleepTimingShift(bedtimeMinutes: 6, wakeMinutes: -25))
        #expect(text == "Over the last 7 nights: bedtime about the same, wake time 25 min earlier, compared with the 14 nights before.")
    }

    @Test func aSuggestedRangeNeedsFourteenNightsAndIsNeverATarget() throws {
        let few = try #require(screen(snapshot(count: 10), range: .week).insights?.timing)
        #expect(few.suggested == nil)
        let enough = try #require(screen(snapshot(count: 16), range: .week).insights?.timing)
        let text = try #require(enough.suggested)
        #expect(text.hasPrefix("Bedtime "))
        #expect(text.contains("isn't a target"))
        #expect(enough.chart?.bedtimeRange != nil && enough.chart?.wakeRange != nil)
    }

    @Test func underFiveNightsSaysWhatItNeeds() throws {
        let timing = try #require(screen(snapshot(count: 3), range: .week).insights?.timing)
        #expect(!timing.isAvailable)
        #expect(timing.nightsLine == "Typical times need 5 recorded nights in the last 14.")
        #expect(timing.typicalBedtime == nil && timing.chart == nil)
    }

    @Test func theSheetsExplainTheCalculationAndCloseKindly() throws {
        let timing = try #require(screen(snapshot(count: 14), range: .week).insights?.timing)
        let text = timing.calculation.joined(separator: " ")
        #expect(text.contains("medians of your last 14 nights"))
        #expect(text.contains("it isn't a target"))
        #expect(SleepInsightsContent.noFear == "Patterns matter more than perfect nights.")
    }
}

// MARK: - Week

struct SleepWeekContentTests {
    @Test func sevenBarsWithWeekdayInitialsAndThePillsWording() throws {
        let bars = try #require(screen(snapshot(count: 14), range: .week).week?.bars)
        #expect(bars.bars.count == 7)
        #expect(bars.bars.map(\.label) == ["F", "S", "S", "M", "T", "W", "T"])
        #expect(bars.bars.map(\.isNewest) == [false, false, false, false, false, false, true])
        // The night of Sep 23 ends on Thursday: 7h 30m, of it 1h 21m deep and 1h 39m REM.
        #expect(bars.bars.last?.detail == "Thu · 7h 30m · Deep 1h 21m · REM 1h 39m")
        #expect(bars.bars.last?.accessibilityLabel == "Thursday, 7 hours 30 minutes, deep 1 hour 21 minutes, REM 1 hour 39 minutes")
    }

    @Test func theNeedLineAndTheAverageAreTheEnginesNumbers() throws {
        let content = try #require(screen(snapshot(count: 14), range: .week).week?.bars)
        #expect(content.needLabel == "8h need")
        #expect(content.average?.spoken == "7 hours 30 minutes")
        #expect(content.needFraction > 0 && content.needFraction < 1)
        let average = try #require(content.averageFraction)
        #expect(average < content.needFraction, "7h 30m sits under the 8h need line")
        #expect(content.emptyNote == nil)
    }

    @Test func aNightWithNothingRecordedIsNoDataNotAZeroBar() throws {
        let bars = try #require(screen(snapshot(count: 14, skipping: [11]), range: .week).week?.bars)
        let gap = try #require(bars.bars.first { $0.fraction == nil })
        #expect(gap.detail.hasSuffix("· No data"))
        #expect(gap.accessibilityLabel.hasSuffix("no data"))
        #expect(gap.stages == nil)
        // The average is over the recorded nights only.
        #expect(bars.average?.spoken == "7 hours 30 minutes")
    }

    @Test func aWeekWithNothingSaysSoInsteadOfDrawingZeroes() throws {
        let snap = snapshot(count: 14)
        let bars = try #require(screen(snap, night: SleepNightKey(year: 2026, month: 8, day: 1), range: .week).week?.bars)
        #expect(bars.emptyNote == "No sleep recorded in this period.")
        #expect(bars.average == nil && bars.averageFraction == nil)
        #expect(bars.bars.allSatisfy { $0.fraction == nil })
    }

    @Test func aWeekWithoutStageDataIsOneBarWithAnHonestCaptionAndNoStageLegend() throws {
        let unstaged = (0..<7).flatMap { index in
            SleepFixture.night(lastNight.adding(days: index - 6), blocks: [(.unspecified, 420)], inBed: true)
        }
        let snap = SleepSnapshotBuilder.build(
            HomeHealthInputs(sleep: unstaged, hrv: [], restingHeartRate: [], heartRate: []),
            profile: UserProfileSnapshot(), now: SleepFixture.now, timeZone: SleepFixture.zone
        )
        let bars = try #require(screen(snap, range: .week).week?.bars)
        #expect(!bars.hasStages)
        #expect(bars.stagesNote == "Stages aren't available from your current sources.")
        #expect(bars.bars.allSatisfy { $0.stages == nil && $0.fraction != nil })
        // A week with stages says nothing of the kind.
        let staged = try #require(screen(snapshot(count: 14), range: .week).week?.bars)
        #expect(staged.hasStages && staged.stagesNote == nil)
    }

    @Test func theCaptionIsTheDatesTheWeekCovers() throws {
        let bars = try #require(screen(snapshot(count: 14), range: .week).week?.bars)
        #expect(bars.caption == "SEP 18 – SEP 24")
    }

    @Test func theWeekEndsOnTheSelectedNight() throws {
        let snap = snapshot(count: 14)
        let earlier = lastNight.adding(days: -3)
        let bars = try #require(screen(snap, night: earlier, range: .week).week?.bars)
        #expect(bars.bars.last?.night == earlier)
        #expect(bars.caption == "SEP 15 – SEP 21")
    }
}

// MARK: - Month

struct SleepMonthContentTests {
    @Test func thirtySlimBarsAndTheWeeklyRunsCountedBackFromTheLastNight() throws {
        let month = try #require(screen(snapshot(count: 30), range: .month).month)
        #expect(month.bars.bars.count == 30)
        #expect(month.bars.bars.allSatisfy { $0.label.isEmpty })
        // 30 = 2 + 4 × 7: a short run first, then four whole weeks.
        #expect(month.blocks.map { $0.end - $0.start } == [2, 7, 7, 7, 7])
        #expect(month.blocks.last?.end == 30)
        // Only whole-enough runs are dated.
        #expect(month.labels.map(\.index) == [2, 9, 16, 23])
        #expect(month.labels.first?.text == "Aug 28")
    }

    @Test func aMonthsPillsHaveTheDateAndTheDuration() throws {
        let bars = try #require(screen(snapshot(count: 30), range: .month).month?.bars)
        #expect(bars.bars.last?.detail == "Thu, Sep 24 · 7h 30m")
        #expect(bars.bars.last?.accessibilityLabel == "Thursday, September 24, 7 hours 30 minutes")
        #expect(bars.caption == "AUG 26 – SEP 24")
    }

    @Test func theLongestAndTheShortestNightAreNamed() throws {
        // Each night 3 minutes longer than the one before.
        let month = try #require(screen(snapshot(count: 30, asleep: { 400 + Double($0) * 3 }), range: .month).month)
        let longest = try #require(month.longest)
        let shortest = try #require(month.shortest)
        #expect(longest.index == 29 && shortest.index == 0)
        #expect(longest.title == "Longest" && shortest.title == "Shortest")
        #expect(longest.value.spoken == "8 hours 7 minutes")
        #expect(shortest.value.spoken == "6 hours 40 minutes")
        #expect(longest.date == "Thu, Sep 24")
        #expect(month.bars.accessibilityLabel.contains("Longest night, Thursday, September 24, 8 hours 7 minutes"))
        #expect(month.bars.accessibilityLabel.contains("Shortest night"))
    }

    @Test func aNightThatReachedTheNeedIsMarkedSoAndOneUnderItIsNot() throws {
        // Nights of 6h40 up to 8h07 against the default 8h need: the last few reach it.
        let bars = try #require(screen(snapshot(count: 30, asleep: { 400 + Double($0) * 3 }), range: .month).month?.bars)
        for bar in bars.bars {
            #expect((bar.reachedNeed ?? false) == ((bar.fraction ?? 0) >= bars.needFraction), "\(bar.night)")
        }
        #expect(bars.bars.first?.reachedNeed == false && bars.bars.last?.reachedNeed == true)
    }

    @Test func fewerThanTwoRecordedNightsNamesNoBestOrWorst() throws {
        let month = try #require(screen(snapshot(count: 1), range: .month).month)
        #expect(month.longest == nil && month.shortest == nil)
    }

    @Test func theSummaryStripHasTheAverageAndTheLongestAndShortestNightOfTheRange() throws {
        // Each night 3 minutes longer than the one before.
        let asleep: (Int) -> Double = { 400 + Double($0) * 3 }
        let month = screen(snapshot(count: 30, asleep: asleep), range: .month)
        let summary = try #require(month.summary)
        #expect(summary.average == month.bars?.average)
        #expect(summary.longest?.index == 29 && summary.shortest?.index == 0)
        #expect(summary.accessibilityLabel == "Average \(summary.average.spoken)")
        // A week names its own extremes, among its seven bars.
        let week = screen(snapshot(count: 30, asleep: asleep), range: .week)
        let weekSummary = try #require(week.summary)
        let weekLongest = try #require(weekSummary.longest)
        let weekShortest = try #require(weekSummary.shortest)
        #expect(weekLongest.index == 6 && weekShortest.index == 0)
        #expect(weekLongest.title == "Longest" && weekShortest.title == "Shortest")
        #expect(weekLongest.value.spoken == "8 hours 7 minutes")
        #expect(weekShortest.value.spoken == "7 hours 49 minutes")
        #expect(week.week?.bars.accessibilityLabel.contains("Longest night") == true)
    }

    @Test func aRangeWithNothingRecordedHasNoSummary() {
        let empty = screen(snapshot(count: 0), range: .week)
        #expect(empty.summary == nil)
        // One recorded night has an average and no extremes to name.
        let one = screen(snapshot(count: 1), range: .week)
        #expect(one.summary?.longest == nil && one.summary?.shortest == nil)
    }

    @Test func theQualityStripHasANightPerDotAndTheNumberInEveryPill() throws {
        let snap = snapshot(count: 30, skipping: [12])
        let month = try #require(screen(snap, range: .month).month)
        let strip = month.quality
        #expect(strip.dots.count == 30)
        #expect(strip.legend.map(\.text) == ["80 and up", "60–79", "Under 60"])
        for (index, dot) in strip.dots.enumerated() {
            let record = snap.record(dot.night)
            if let record {
                #expect(dot.detail.hasSuffix("· \(record.quality.score)"))
                #expect(dot.band == QualityDotRender.band(for: record.quality.score))
            } else {
                #expect(index == 12 && dot.band == nil && dot.detail.hasSuffix("· no sleep"))
            }
        }
        let scores = snap.records.map(\.quality.score)
        let average = Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        #expect(strip.average == "30-night average \(average)")
    }

    @Test func theBandsBreakAtSixtyAndEighty() {
        #expect(QualityDotRender.band(for: 80) == .high)
        #expect(QualityDotRender.band(for: 79) == .middle)
        #expect(QualityDotRender.band(for: 60) == .middle)
        #expect(QualityDotRender.band(for: 59) == .low)
    }

    @Test func theRhythmSaysWhenYouUsuallyGoToBedAndWake() throws {
        let rhythm = try #require(screen(snapshot(count: 30), range: .month).month?.rhythm)
        #expect(rhythm.bedtimeSummary == "Bedtime usually \(format.clock(minutesSinceMidnight: 23 * 60))")
        #expect(rhythm.wakeSummary == "Wake time usually \(format.clock(minutesSinceMidnight: 6 * 60 + 30))")
        #expect(rhythm.chart.bedtime.count == 30 && rhythm.chart.wake.count == 30)
        #expect(rhythm.usualCaption == "Shaded: your usual bedtime and wake time")
    }

    @Test func aMonthShowsTheTimingSheetsNumbersToo() throws {
        let screen = screen(snapshot(count: 30), range: .month)
        #expect(screen.insights?.timing.isAvailable == true)
        #expect(screen.insights?.consistency == nil, "consistency's dots are the week's")
        #expect(screen.week == nil && screen.bars == screen.month?.bars)
    }
}

// MARK: - Axes

struct SleepAxisTests {
    @Test func aShortAxisLabelsEveryHourAndALongOneEveryTwoOrThreeButNeverMoreThanSix() {
        let short = SleepScreenBuilder.axisTicks(start: 600, end: 840, format: format)
        #expect(short.count == 5)
        #expect(short.map(\.position) == [0, 0.25, 0.5, 0.75, 1])
        #expect(short.first?.text == format.hour(minutesSinceMidnight: 600 + 720))
        let medium = SleepScreenBuilder.axisTicks(start: 600, end: 1080, format: format)
        #expect(medium.count == 5, "an 8-hour axis in twos")
        let long = SleepScreenBuilder.axisTicks(start: 540, end: 1260, format: format)
        #expect(long.count == 5, "9 PM to 9 AM in threes")
        #expect(long.map(\.position) == [0, 0.25, 0.5, 0.75, 1])
    }

    @Test func theRenderModelsAxisesFallOnWholeHours() throws {
        let snap = snapshot(count: 30, bedtime: { 22.5 + Double($0 % 4) * 0.25 })
        let model = SleepRenderModelBuilder.build(snap, selection: SleepSelection(night: snap.defaultNight, range: .month))
        let rhythm = try #require(model.month?.rhythm)
        #expect(rhythm.axisStart.truncatingRemainder(dividingBy: 60) == 0 && rhythm.axisEnd.truncatingRemainder(dividingBy: 60) == 0)
        for value in (rhythm.bedtime + rhythm.wake).compactMap({ $0 }) { #expect((0.0...1.0).contains(value)) }
        let window = try #require(model.timingRender)
        #expect(window.bedtime < window.midpoint && window.midpoint < window.wake)
    }
}

// MARK: - Highlights

struct SleepHighlightContentTests {
    @Test func theLongestNightOfThirtyIsNamedOnDayInCalmWords() throws {
        let day = screen(snapshot(count: 30, asleep: { $0 == 29 ? 520 : 450 }), range: .day)
        let texts = day.highlights.map(\.text)
        #expect(texts.contains("Longest night this month"))
        #expect(day.highlights.allSatisfy { $0.id.hasPrefix("Day-") })
        // Words a person could read as a nudge or a streak are never used.
        for text in texts {
            for word in ["streak", "record", "best ever", "keep it up", "don't", "beat"] {
                #expect(!text.lowercased().contains(word), Comment(rawValue: text))
            }
        }
    }

    @Test func aTiedOrOrdinaryNightGetsNoHighlight() {
        #expect(screen(snapshot(count: 30), range: .day).highlights.isEmpty)
        // An earlier night, with a longer one after it in its window.
        let snap = snapshot(count: 30, asleep: { $0 == 29 ? 520 : 450 })
        let earlier = snap.defaultNight.adding(days: -3)
        #expect(screen(snap, night: earlier, range: .day).highlights.isEmpty)
    }

    @Test func aWeekNamesTheMostConsistentWeekYetAndAMonthNamesNothing() {
        let steadyEnd: (Int) -> Double = { $0 >= 33 ? 23 : 23 + ($0 % 2 == 0 ? 0.5 : -0.5) }
        let snap = snapshot(count: 40, bedtime: steadyEnd)
        #expect(screen(snap, range: .week).highlights.map(\.text) == ["Most consistent week yet"])
        #expect(screen(snap, range: .month).highlights.isEmpty)
        // On Day, the week's mark isn't shown.
        #expect(!screen(snap, range: .day).highlights.map(\.text).contains("Most consistent week yet"))
    }

    @Test func aStateOrAnEmptyNightShowsNone() {
        #expect(screen(snapshot(count: 0), range: .day).highlights.isEmpty)
    }
}

struct SleepHighsScenarioTests {
    @Test func theHighsScenarioEarnsTheLongestNightAndTheBestDeepSleep() async throws {
        let now = SleepFixture.now
        let provider = MockHealthKitProvider(scenario: .highs, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let snap = await SleepRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        let selection = SleepSelection(night: snap.defaultNight, range: .day)
        let model = SleepRenderModelBuilder.build(snap, selection: selection)
        #expect(Set(model.highlights).isSuperset(of: [.longestNight, .bestDeepSleep]))
    }
}
