import Foundation
import Testing

@testable import InsightsKit
@testable import RecoveryKit
@testable import SleepAnalysisKit
@testable import SleepKit

/// Insight v2's twelve rules, each at its exact boundary and its minimum of
/// data. Hand-built nights (`InsightFixture`) so every number is known.
struct InsightEngineV2Tests {
    typealias Row = InsightFixture.Row

    // MARK: - The frame: last night, learning, freshness

    @Test func nothingFiresWithoutAnyNights() {
        #expect(InsightEngineV2.generate(InsightFixture.inputs(count: 0)).isEmpty)
    }

    @Test func nothingFiresUnderSevenNights() {
        // 6 nights, the last 90 minutes short: the rules would fire, but the tab is still learning.
        let inputs = InsightFixture.inputs(count: 6) { index, _ in Row(asleep: index == 5 ? 330 : 420) }
        #expect(InsightEngineV2.generate(inputs).isEmpty)
    }

    @Test func aNightOlderThanADayIsNotLastNight() {
        // Last night's wake-up was 7:00 AM Sep 24: exactly 24 hours on is still last night, a second later isn't.
        let wake = Fixture.date(2026, 9, 24, 7)
        func generated(_ offset: TimeInterval) -> [InsightRecord] {
            InsightEngineV2.generate(
                InsightFixture.inputs(count: 15, asOf: wake.addingTimeInterval(offset)) { index, _ in Row(asleep: index == 14 ? 330 : 420) })
        }
        #expect(!generated(24 * 3600).isEmpty)
        #expect(generated(24 * 3600 + 1).isEmpty)
        #expect(!generated(-1).contains { $0.night == InsightFixture.last }, "a night that hasn't ended yet isn't complete: the one before it is last night")
    }

    // MARK: - 1, 2, 3: against your baseline (v1's rules, on InsightRecord)

    private func baselineInputs(lastAsleep: Double = 420, lastBedtime: Double = 660, count: Int = 15) -> InsightInputs {
        InsightFixture.inputs(count: count) { index, _ in
            index == count - 1 ? Row(asleep: lastAsleep, bedtime: lastBedtime) : Row()
        }
    }

    @Test func durationShiftFiresAtExactlyThirtyMinutes() throws {
        let record = try #require(InsightFixture.records(baselineInputs(lastAsleep: 390), .sleepDurationShift).first)
        guard case .baseline(let evidence) = record.evidence else {
            Issue.record("expected baseline evidence")
            return
        }
        #expect(evidence.delta == -30)
        #expect(evidence.value == 390)
        #expect(evidence.baseline == 420)
        #expect(evidence.baselineNights == 14)
        #expect(record.confidence == .high, "a full 14-night baseline")
        #expect(record.nightsUsed == 14)
    }

    @Test func durationShiftBoundaryRoundsLikeTheRestOfTheApp() {
        #expect(InsightFixture.records(baselineInputs(lastAsleep: 420 - 29.4), .sleepDurationShift).isEmpty, "29.4 rounds to 29")
        #expect(InsightFixture.records(baselineInputs(lastAsleep: 420 - 29.5), .sleepDurationShift).count == 1, "29.5 rounds to 30")
        #expect(InsightFixture.records(baselineInputs(lastAsleep: 420 + 30), .sleepDurationShift).count == 1, "longer counts too")
    }

    @Test func bedtimeShiftFiresAtExactlyThirtyMinutes() throws {
        #expect(InsightFixture.records(baselineInputs(lastBedtime: 690), .bedtimeShift).count == 1)
        #expect(InsightFixture.records(baselineInputs(lastBedtime: 630), .bedtimeShift).count == 1, "earlier counts too")
        #expect(InsightFixture.records(baselineInputs(lastBedtime: 689.4), .bedtimeShift).isEmpty)
    }

    @Test func baselineRulesNeedFiveBaselineNights() {
        // 5 baseline nights + last night = 6 recorded: still learning, so nothing.
        #expect(InsightEngineV2.generate(baselineInputs(lastAsleep: 300, count: 6)).isEmpty)
        // 6 baseline nights + last night = 7 recorded: rule fires with 6 baseline nights, moderate... low under 7.
        let seven = InsightFixture.records(baselineInputs(lastAsleep: 300, count: 7), .sleepDurationShift)
        #expect(seven.first?.nightsUsed == 6)
        #expect(seven.first?.confidence == .low, "6 baseline nights is under the 7 a moderate confidence needs")
    }

    @Test func confidenceFollowsTheBaselineLength() {
        // 8 nights: 7 baseline nights = moderate. 15 nights: 14 = high.
        #expect(InsightFixture.records(baselineInputs(lastAsleep: 300, count: 8), .sleepDurationShift).first?.confidence == .moderate)
        #expect(InsightFixture.records(baselineInputs(lastAsleep: 300, count: 15), .sleepDurationShift).first?.confidence == .high)
    }

    @Test func aSteadyBedtimeStreakFiresAtFiveNights() throws {
        // Nights 0-9 swing 45 minutes either side; the last five sit on 11:00 PM.
        func inputs(streak: Int) -> InsightInputs {
            InsightFixture.inputs(count: 15) { index, _ in
                index >= 15 - streak ? Row() : Row(bedtime: index % 2 == 0 ? 705 : 615)
            }
        }
        let record = try #require(InsightFixture.records(inputs(streak: 5), .consistentBedtime).first)
        guard case .baseline(let evidence) = record.evidence else {
            Issue.record("expected baseline evidence")
            return
        }
        #expect(evidence.streakNights == 5)
        #expect(evidence.recentNights.count == InsightModelV2.streakDots, "the detail page's 14 dots")
        #expect(evidence.recentNights.last == true)
        #expect(InsightFixture.records(inputs(streak: 4), .consistentBedtime).isEmpty)
    }

    // MARK: - 4: the earlier-bedtime pattern

    /// 60 nights whose median bedtime is 660: `early` nights at 660 − `offset`,
    /// `late` at 660 + `offset`, the rest on 660, and an outcome per group
    /// (continuity, stage and HRV scores all equal to it).
    private func patternInputs(early: Int, late: Int, offset: Double = 30, earlyScore: Int = 90, lateScore: Int = 70, jitter: Bool = true) -> InsightInputs {
        InsightFixture.inputs(count: 60) { index, _ in
            var row = Row()
            let fromEnd = 59 - index
            // The nights at the very end stay on the median so last night is ordinary.
            if fromEnd >= 3 && fromEnd < 3 + early {
                row.bedtime = 660 - offset
                row.continuity = earlyScore + (jitter ? index % 3 - 1 : 0)
                row.stage = earlyScore + (jitter ? index % 3 - 1 : 0)
                row.hrvScore = earlyScore + (jitter ? index % 3 - 1 : 0)
            } else if fromEnd >= 3 + early && fromEnd < 3 + early + late {
                row.bedtime = 660 + offset
                row.continuity = lateScore + (jitter ? index % 3 - 1 : 0)
                row.stage = lateScore + (jitter ? index % 3 - 1 : 0)
                row.hrvScore = lateScore + (jitter ? index % 3 - 1 : 0)
            }
            return row
        }
    }

    @Test func thePatternFiresWithFiveNightsInEachGroup() throws {
        let record = try #require(InsightFixture.records(patternInputs(early: 5, late: 5), .earlierBedtimePattern).first)
        guard case .pattern(let evidence) = record.evidence else {
            Issue.record("expected pattern evidence")
            return
        }
        #expect(evidence.earlyNights == 5 && evidence.lateNights == 5)
        #expect(evidence.medianBedtime == 660)
        #expect(evidence.difference > 15 && evidence.difference < 25)
        #expect(record.confidence == .moderate, "5 per group is under the 10 a high confidence needs")
        #expect(record.category == .timing)
    }

    @Test func aGroupUnderFiveNightsIsNotEnough() {
        #expect(InsightFixture.records(patternInputs(early: 4, late: 9), .earlierBedtimePattern).isEmpty)
        #expect(InsightFixture.records(patternInputs(early: 9, late: 4), .earlierBedtimePattern).isEmpty)
    }

    @Test func aNightIsOnlyEarlyOrLateFromThirtyMinutesOut() {
        // 29 minutes from the median is neither: the groups stay empty.
        #expect(InsightFixture.records(patternInputs(early: 8, late: 8, offset: 29), .earlierBedtimePattern).isEmpty)
        #expect(InsightFixture.records(patternInputs(early: 8, late: 8, offset: 30), .earlierBedtimePattern).count == 1)
    }

    @Test func highConfidenceNeedsTenNightsPerGroupAndAnEffectOfPointEight() throws {
        let ten = try #require(InsightFixture.records(patternInputs(early: 10, late: 10), .earlierBedtimePattern).first)
        #expect(ten.confidence == .high)
        let nine = try #require(InsightFixture.records(patternInputs(early: 9, late: 10), .earlierBedtimePattern).first)
        #expect(nine.confidence == .moderate)
        // The rule the engine uses, at its exact edges.
        #expect(InsightEngineV2.patternConfidence(early: 10, late: 10, effectSize: 0.8) == .high)
        #expect(InsightEngineV2.patternConfidence(early: 10, late: 10, effectSize: 0.79) == .moderate)
        #expect(InsightEngineV2.patternConfidence(early: 10, late: 10, effectSize: -0.8) == .high, "either direction")
        #expect(InsightEngineV2.patternConfidence(early: 9, late: 10, effectSize: 3) == .moderate)
    }

    @Test func thePatternNeedsSixPointsAndAnEffectOfHalf() {
        func result(difference: Double, effect: Double) -> InsightEngineV2.PatternResult {
            InsightEngineV2.PatternResult(earlyMean: 80, lateMean: 80 - difference, difference: difference, pooledSD: 1, effectSize: effect)
        }
        #expect(InsightEngineV2.patternFires(result(difference: 6, effect: 0.5)))
        #expect(!InsightEngineV2.patternFires(result(difference: 5.99, effect: 0.5)))
        #expect(!InsightEngineV2.patternFires(result(difference: 6, effect: 0.49)))
        #expect(InsightEngineV2.patternFires(result(difference: -6, effect: -0.5)), "later nights being higher is just as much a pattern")
    }

    @Test func groupComparisonNeedsFiveEachAndReportsThePooledEffect() throws {
        #expect(InsightEngineV2.comparePatternGroups(early: [1, 2, 3, 4], late: [1, 2, 3, 4, 5]) == nil)
        #expect(InsightEngineV2.comparePatternGroups(early: [1, 2, 3, 4, 5], late: [1, 2, 3, 4]) == nil)
        let result = try #require(InsightEngineV2.comparePatternGroups(early: [90, 92, 88, 91, 89], late: [70, 72, 68, 71, 69]))
        #expect(result.earlyMean == 90 && result.lateMean == 70 && result.difference == 20)
        // Both groups have a sample SD of √2.5, so the pooled SD is √2.5 and d = 20/√2.5.
        #expect(abs(result.pooledSD - 2.5.squareRoot()) < 1e-9)
        #expect(abs(result.effectSize - 20 / 2.5.squareRoot()) < 1e-9)
    }

    @Test func aGroupWithNoSpreadHasABoundedEffect() throws {
        let result = try #require(InsightEngineV2.comparePatternGroups(early: [90, 90, 90, 90, 90], late: [70, 70, 70, 70, 70]))
        #expect(result.effectSize == 99, "capped, so it can be stored")
    }

    @Test func theOutcomeIsTheMeanOfWhatIsAvailable() {
        #expect(InsightEngineV2.patternOutcome(continuity: 90, stage: 60, hrv: 30) == 60)
        #expect(InsightEngineV2.patternOutcome(continuity: 90, stage: nil, hrv: 70) == 80)
        #expect(InsightEngineV2.patternOutcome(continuity: nil, stage: nil, hrv: nil) == nil)
    }

    @Test func nightsWithNoOutcomeAreLeftOutOfTheGroups() {
        // Early nights with no scores at all: nothing to compare.
        let inputs = InsightFixture.inputs(count: 60) { index, _ in
            let fromEnd = 59 - index
            if fromEnd >= 3, fromEnd < 13 { return Row(bedtime: 630) }
            if fromEnd >= 13, fromEnd < 23 { return Row(bedtime: 690, continuity: 60, stage: 60, hrvScore: 60) }
            return Row()
        }
        #expect(InsightFixture.records(inputs, .earlierBedtimePattern).isEmpty)
    }

    /// The circularity guard: the outcome is built from continuity, stage
    /// balance and HRV only. Duration, consistency and the overall quality
    /// are all computed from bedtime or duration, so a rule about bedtime must
    /// never read them: changing them changes nothing.
    @Test func theOutcomeNeverReadsDurationConsistencyOrQuality() throws {
        func inputs(scramble: Bool) -> InsightInputs {
            InsightFixture.inputs(count: 60) { index, _ in
                var row = Row()
                let fromEnd = 59 - index
                if fromEnd >= 3 && fromEnd < 13 {
                    row = Row(bedtime: 630, continuity: 90, stage: 88, hrvScore: 92)
                } else if fromEnd >= 13 && fromEnd < 23 {
                    row = Row(bedtime: 690, continuity: 70, stage: 72, hrvScore: 68)
                }
                if scramble {
                    // Every score a bedtime rule must not read, and the duration itself.
                    row.asleep = Double(300 + (index * 37) % 200)
                    row.duration = (index * 13) % 100
                    row.consistency = (index * 29) % 100
                    row.quality = (index * 41) % 100
                }
                return row
            }
        }
        func pattern(_ inputs: InsightInputs) throws -> PatternEvidence {
            let record = try #require(InsightFixture.records(inputs, .earlierBedtimePattern).first)
            guard case .pattern(let evidence) = record.evidence else { throw CocoaError(.coderInvalidValue) }
            return evidence
        }
        let plain = try pattern(inputs(scramble: false))
        let scrambled = try pattern(inputs(scramble: true))
        #expect(plain.earlyValues == scrambled.earlyValues)
        #expect(plain.lateValues == scrambled.lateValues)
        #expect(plain.difference == scrambled.difference)
        #expect(plain.effectSize == scrambled.effectSize)
        // ...and what it does read matters.
        #expect(plain.earlyMean == (90 + 88 + 92) / 3.0)
    }

    @Test func bedtimeAndOutcomeMovingTogetherIsAlsoFoundTheOtherWayRound() throws {
        let record = try #require(InsightFixture.records(patternInputs(early: 8, late: 8, earlyScore: 60, lateScore: 85), .earlierBedtimePattern).first)
        guard case .pattern(let evidence) = record.evidence else {
            Issue.record("expected pattern evidence")
            return
        }
        #expect(evidence.difference < 0, "later nights scored higher")
    }

    // MARK: - 5: recovery direction

    /// Flat at 60, then rising 4 points a day for `ramp` days.
    private func rampInputs(ramp: Int, falling: Bool = false) -> InsightInputs {
        let scores = InsightFixture.recoveryScores(count: 40) { index in
            let step = index - (40 - ramp - 1)
            return step > 0 ? 60 + (falling ? -4 : 4) * step : 60
        }
        return InsightFixture.inputs(count: 40, recovery: scores)
    }

    @Test func recoveryDirectionFiresAtFiveDaysInARow() throws {
        let record = try #require(InsightFixture.records(rampInputs(ramp: 5), .recoveryDirection).first)
        guard case .recoveryDirection(let evidence) = record.evidence else {
            Issue.record("expected recovery evidence")
            return
        }
        #expect(evidence.direction == .rising)
        #expect(evidence.consecutiveDays == 5)
        #expect(evidence.recentScores.count == 14)
        #expect(evidence.latestScore == 60 + 4 * 5)
        #expect(record.category == .recovery)
    }

    @Test func fourDaysInARowIsNotEnough() {
        #expect(InsightFixture.records(rampInputs(ramp: 4), .recoveryDirection).isEmpty)
    }

    @Test func aFallingTrendIsLower() throws {
        let record = try #require(InsightFixture.records(rampInputs(ramp: 6, falling: true), .recoveryDirection).first)
        guard case .recoveryDirection(let evidence) = record.evidence else {
            Issue.record("expected recovery evidence")
            return
        }
        #expect(evidence.direction == .lower)
        #expect(evidence.pointsPerWeek < 0)
    }

    @Test func aSteadyTrendSaysNothing() {
        #expect(InsightFixture.records(rampInputs(ramp: 0), .recoveryDirection).isEmpty)
    }

    @Test func recoveryDirectionNeedsLastNightScored() {
        let scores = InsightFixture.recoveryScores(count: 39, endingOn: InsightFixture.last.adding(days: -1)) { index in 60 + 4 * max(index - 33, 0) }
        #expect(InsightFixture.records(InsightFixture.inputs(count: 40, recovery: scores), .recoveryDirection).isEmpty)
    }

    // MARK: - 6: a heart signal outside its normal range

    /// 14 nights on `usual` (a hair of variation, so the range floor of 3 applies), then `values`.
    private func heartInputs(signal: InsightHeartSignal, usual: Double, tail: [Double]) -> InsightInputs {
        let count = 14 + tail.count
        return InsightFixture.inputs(count: count) { index, _ in
            let value = index < 14 ? usual : tail[index - 14]
            return signal == .hrv ? Row(hrv: value) : Row(resting: value)
        }
    }

    @Test func hrvBelowRangeFiresAtThreeNightsInARow() throws {
        let record = try #require(InsightFixture.records(heartInputs(signal: .hrv, usual: 50, tail: [40, 40, 40]), .hrvBelowRange).first)
        guard case .heartSignal(let evidence) = record.evidence else {
            Issue.record("expected heart evidence")
            return
        }
        #expect(evidence.signal == .hrv)
        #expect(evidence.consecutiveNights == 3)
        #expect(evidence.value == 40)
        #expect(evidence.baselineNights == 14)
        #expect(evidence.baseline - evidence.rangeLow == evidence.rangeHigh - evidence.baseline, "the range is the baseline give or take one spread")
        #expect(evidence.baseline - evidence.rangeLow >= RecoveryModelV2.hrvStandardDeviationFloor, "never narrower than the floor")
        #expect(record.category == .heart)
    }

    @Test func twoNightsIsNotEnough() {
        #expect(InsightFixture.records(heartInputs(signal: .hrv, usual: 50, tail: [50, 40, 40]), .hrvBelowRange).isEmpty)
    }

    @Test func aValueExactlyOnTheEdgeOfTheRangeIsWithinIt() {
        // Night 15 sits 3 ms under 50 (exactly one floored SD): within. So only nights 16 and 17 are outside: 2 in a row.
        #expect(InsightFixture.records(heartInputs(signal: .hrv, usual: 50, tail: [47, 40, 40]), .hrvBelowRange).isEmpty)
        // A hair under the edge, and there are three.
        #expect(InsightFixture.records(heartInputs(signal: .hrv, usual: 50, tail: [46.9, 40, 40]), .hrvBelowRange).count == 1)
    }

    @Test func aHighHRVIsNeverBelowRange() {
        #expect(InsightFixture.records(heartInputs(signal: .hrv, usual: 50, tail: [60, 60, 60]), .hrvBelowRange).isEmpty)
    }

    @Test func restingHeartRateAboveRangeFiresAtThreeNights() throws {
        let record = try #require(
            InsightFixture.records(heartInputs(signal: .restingHeartRate, usual: 55, tail: [62, 62, 62]), .restingHeartRateAboveRange).first)
        guard case .heartSignal(let evidence) = record.evidence else {
            Issue.record("expected heart evidence")
            return
        }
        #expect(evidence.signal == .restingHeartRate)
        #expect(evidence.rangeHigh == evidence.baseline + 1 || evidence.rangeHigh > evidence.baseline, "resting heart rate's floor is 1 bpm")
        // A low resting heart rate is not a signal.
        #expect(InsightFixture.records(heartInputs(signal: .restingHeartRate, usual: 55, tail: [48, 48, 48]), .restingHeartRateAboveRange).isEmpty)
        // Two nights isn't three.
        #expect(InsightFixture.records(heartInputs(signal: .restingHeartRate, usual: 55, tail: [55, 62, 62]), .restingHeartRateAboveRange).isEmpty)
    }

    @Test func heartSignalsNeedABaseline() {
        // 4 nights of usual, then 3 low: 4 baseline nights is under the 5 a baseline needs.
        let inputs = InsightFixture.inputs(count: 7) { index, _ in Row(hrv: index < 4 ? 50 : 30) }
        #expect(InsightFixture.records(inputs, .hrvBelowRange).isEmpty)
    }

    // MARK: - 7: a change in bedtime spread

    /// The two 14-night windows: the 14 before have bedtimes alternating ±`before` around
    /// 660, the last 14 alternate ±`after`. A sample SD of alternating ±a over 14 nights is a·√(14/13).
    private func spreadInputs(before: Double, after: Double, missingRecent: Int = 0) -> InsightInputs {
        InsightFixture.inputs(count: 28) { index, _ in
            let sign = index % 2 == 0 ? 1.0 : -1.0
            return Row(bedtime: 660 + sign * (index < 14 ? before : after))
        }
    }

    private static let sdFactor = (14.0 / 13.0).squareRoot()

    @Test func aSteadierFortnightFiresAtFifteenMinutes() throws {
        // Δ = 30·factor − 15·factor = 15·1.0377 = 15.57 → fires.
        let record = try #require(InsightFixture.records(spreadInputs(before: 30, after: 15), .consistencyChange).first)
        guard case .consistencyChange(let evidence) = record.evidence else {
            Issue.record("expected consistency evidence")
            return
        }
        #expect(evidence.delta < 0)
        #expect(abs(evidence.recentSD - 15 * Self.sdFactor) < 1e-9)
        #expect(abs(evidence.previousSD - 30 * Self.sdFactor) < 1e-9)
        #expect(evidence.bedtimes.count == 28)
        #expect(record.category == .consistency)
    }

    @Test func theSpreadBoundaryIsFifteenMinutesRounded() {
        // recent all on 660 (SD 0): Δ = −a·factor. Δ of 14.49 rounds to 14, 14.51 to 15.
        let below = 14.49 / Self.sdFactor
        let at = 14.51 / Self.sdFactor
        #expect(InsightFixture.records(spreadInputs(before: below, after: 0), .consistencyChange).isEmpty)
        #expect(InsightFixture.records(spreadInputs(before: at, after: 0), .consistencyChange).count == 1)
    }

    @Test func aLessSteadyFortnightFiresToo() throws {
        let record = try #require(InsightFixture.records(spreadInputs(before: 5, after: 30), .consistencyChange).first)
        guard case .consistencyChange(let evidence) = record.evidence else {
            Issue.record("expected consistency evidence")
            return
        }
        #expect(evidence.delta > 0)
    }

    @Test func bothFortnightsNeedFiveNights() {
        // Only 3 bedtimes in the earlier fortnight.
        let inputs = InsightFixture.inputs(count: 17) { index, _ in Row(bedtime: 660 + (index % 2 == 0 ? 40.0 : -40)) }
        #expect(InsightFixture.records(inputs, .consistencyChange).isEmpty)
    }

    // MARK: - 8: sleep balance

    @Test func balanceFiresAtTwoHoursEitherWay() throws {
        let behind = try #require(InsightFixture.records(InsightFixture.inputs(count: 10, balance: InsightFixture.balance(minutes: -120)), .sleepBalance).first)
        guard case .balance(let evidence) = behind.evidence else {
            Issue.record("expected balance evidence")
            return
        }
        #expect(evidence.minutes == -120)
        #expect(evidence.nightlyMinutes.count == 7)
        #expect(InsightFixture.records(InsightFixture.inputs(count: 10, balance: InsightFixture.balance(minutes: 120)), .sleepBalance).count == 1)
        #expect(InsightFixture.records(InsightFixture.inputs(count: 10, balance: InsightFixture.balance(minutes: -119.4)), .sleepBalance).isEmpty)
        #expect(InsightFixture.records(InsightFixture.inputs(count: 10, balance: InsightFixture.balance(minutes: -119.5)), .sleepBalance).count == 1)
    }

    @Test func balanceNeedsARecordedBalanceForLastNight() {
        #expect(InsightFixture.records(InsightFixture.inputs(count: 10, balance: InsightFixture.balance(minutes: nil, recorded: 4)), .sleepBalance).isEmpty)
        #expect(InsightFixture.records(InsightFixture.inputs(count: 10), .sleepBalance).isEmpty)
        // A balance for another night is not last night's.
        let other = SleepBalanceResult(minutes: -300, night: InsightFixture.last.adding(days: -1), recordedNights: 7, series: [])
        #expect(InsightFixture.records(InsightFixture.inputs(count: 10, balance: other), .sleepBalance).isEmpty)
    }

    @Test func balanceConfidenceFollowsTheNightsRecorded() {
        func confidence(_ recorded: Int) -> InsightConfidence? {
            InsightFixture.records(InsightFixture.inputs(count: 10, balance: InsightFixture.balance(minutes: -200, recorded: recorded)), .sleepBalance).first?
                .confidence
        }
        #expect(confidence(7) == .high)
        #expect(confidence(6) == .moderate)
        #expect(confidence(5) == .low)
    }

    // MARK: - 9: weekends

    /// Fridays and Saturdays `weekend` bedtime, the rest 660; `count` nights ending Wed Sep 23.
    private func weekendInputs(count: Int = 28, weekend: Double) -> InsightInputs {
        InsightFixture.inputs(count: count) { _, night in
            Row(bedtime: night.weekday == 6 || night.weekday == 7 ? weekend : 660)
        }
    }

    @Test func weekendBedtimesFireAtFortyFiveMinutes() throws {
        let record = try #require(InsightFixture.records(weekendInputs(weekend: 705), .weekendShift).first)
        guard case .weekend(let evidence) = record.evidence else {
            Issue.record("expected weekend evidence")
            return
        }
        #expect(evidence.delta == 45)
        #expect(evidence.weekendNights == 8 && evidence.weekdayNights == 20)
        #expect(InsightFixture.records(weekendInputs(weekend: 615), .weekendShift).count == 1, "earlier weekends count too")
        #expect(InsightFixture.records(weekendInputs(weekend: 704.4), .weekendShift).isEmpty)
        #expect(InsightFixture.records(weekendInputs(weekend: 704.5), .weekendShift).count == 1)
    }

    @Test func weekendsNeedThreeWeekendNights() {
        // 12 nights ending Sep 23 hold Sat 12, Fri 18, Sat 19: exactly 3.
        #expect(InsightFixture.records(weekendInputs(count: 12, weekend: 720), .weekendShift).count == 1)
        // 11 nights hold only Fri 18 and Sat 19.
        #expect(InsightFixture.records(weekendInputs(count: 11, weekend: 720), .weekendShift).isEmpty)
    }

    @Test func thisWeekIsFridayAndSaturdayNights() {
        #expect(SleepNightKey(year: 2026, month: 9, day: 18).weekday == 6)
        #expect(SleepNightKey(year: 2026, month: 9, day: 19).weekday == 7)
        #expect(InsightEngineV2.isWeekendNight(SleepNightKey(year: 2026, month: 9, day: 18)))
        #expect(InsightEngineV2.isWeekendNight(SleepNightKey(year: 2026, month: 9, day: 19)))
        #expect(!InsightEngineV2.isWeekendNight(SleepNightKey(year: 2026, month: 9, day: 20)), "Sunday evening is the night before Monday")
    }

    // MARK: - 10: stage shares

    private func stageInputs(deep: Double?, rem: Double? = 0.21, usualDeep: Double = 0.17) -> InsightInputs {
        InsightFixture.inputs(count: 15) { index, _ in
            index == 14 ? Row(deep: deep, rem: rem) : Row(deep: usualDeep, rem: 0.21)
        }
    }

    @Test func aStageShareFiresAtFivePoints() throws {
        let record = try #require(InsightFixture.records(stageInputs(deep: 0.22), .stageShare).first)
        guard case .stageShare(let evidence) = record.evidence else {
            Issue.record("expected stage evidence")
            return
        }
        #expect(evidence.stage == .deep)
        #expect(abs(evidence.deltaPoints - 5) < 1e-9)
        #expect(InsightFixture.records(stageInputs(deep: 0.12), .stageShare).count == 1, "less counts too")
        #expect(InsightFixture.records(stageInputs(deep: 0.2149), .stageShare).isEmpty, "4.49 points rounds to 4")
        #expect(InsightFixture.records(stageInputs(deep: 0.2151), .stageShare).count == 1, "5.01 points")
    }

    @Test func remIsJudgedTheSameWay() throws {
        let inputs = InsightFixture.inputs(count: 15) { index, _ in Row(deep: 0.17, rem: index == 14 ? 0.27 : 0.21) }
        let record = try #require(InsightFixture.records(inputs, .stageShare).first)
        guard case .stageShare(let evidence) = record.evidence else {
            Issue.record("expected stage evidence")
            return
        }
        #expect(evidence.stage == .rem)
    }

    @Test func stageSharesNeedStageData() {
        #expect(InsightFixture.records(stageInputs(deep: nil, rem: nil), .stageShare).isEmpty)
        // No stage data on the baseline nights either.
        let inputs = InsightFixture.inputs(count: 15) { index, _ in index == 14 ? Row(deep: 0.30, rem: 0.30) : Row() }
        #expect(InsightFixture.records(inputs, .stageShare).isEmpty)
    }

    // MARK: - 11: records

    private func recordInputs(count: Int, lastAsleep: Double, previousBest: Double = 480) -> InsightInputs {
        InsightFixture.inputs(count: count) { index, _ in
            index == count - 1 ? Row(asleep: lastAsleep) : Row(asleep: index == 3 ? previousBest : 420)
        }
    }

    @Test func aLongestNightBeatsEveryOtherNight() throws {
        let record = try #require(InsightFixture.records(recordInputs(count: 20, lastAsleep: 481), .recordLongestNight).first)
        guard case .record(let evidence) = record.evidence else {
            Issue.record("expected record evidence")
            return
        }
        #expect(evidence.value == 481)
        #expect(evidence.previousBest == 480)
        #expect(evidence.scope == 30, "under 45 nights: the 30-night scope")
        #expect(evidence.nightsInWindow == 20)
        #expect(record.category == .longTerm)
    }

    @Test func aTieIsNotARecord() {
        #expect(InsightFixture.records(recordInputs(count: 20, lastAsleep: 480), .recordLongestNight).isEmpty)
        #expect(InsightFixture.records(recordInputs(count: 20, lastAsleep: 479.9), .recordLongestNight).isEmpty)
    }

    @Test func recordsNeedFourteenNightsForThirtyAndFortyFiveForNinety() throws {
        #expect(InsightFixture.records(recordInputs(count: 13, lastAsleep: 500), .recordLongestNight).isEmpty)
        #expect(InsightFixture.records(recordInputs(count: 14, lastAsleep: 500), .recordLongestNight).first.map { $0.confidence } == .moderate)
        let ninety = try #require(InsightFixture.records(recordInputs(count: 45, lastAsleep: 500), .recordLongestNight).first)
        guard case .record(let evidence) = ninety.evidence else {
            Issue.record("expected record evidence")
            return
        }
        #expect(evidence.scope == 90)
        #expect(ninety.confidence == .high)
    }

    @Test func aBetterNightOutsideTheWindowDoesNotCount() throws {
        // A 9-hour night 100 nights ago is outside 90 nights (and 30).
        let inputs = InsightFixture.inputs(count: 120) { index, _ in
            index == 119 ? Row(asleep: 500) : Row(asleep: index == 5 ? 540 : 420)
        }
        let record = try #require(InsightFixture.records(inputs, .recordLongestNight).first)
        guard case .record(let evidence) = record.evidence else {
            Issue.record("expected record evidence")
            return
        }
        #expect(evidence.scope == 90)
        #expect(evidence.previousBest == 420)
    }

    @Test func aBetterNightInsideTheWindowMeansNoRecordThere() throws {
        // 40 nights back: inside both 30... no, outside 30 (nights 0-29) but inside 90: a 30-night record only.
        let outside30 = InsightFixture.inputs(count: 120) { index, _ in
            index == 119 ? Row(asleep: 500) : Row(asleep: index == 79 ? 540 : 420)
        }
        let record = try #require(InsightFixture.records(outside30, .recordLongestNight).first)
        guard case .record(let evidence) = record.evidence else {
            Issue.record("expected record evidence")
            return
        }
        #expect(evidence.scope == 30, "beaten in the last 30 nights, but not the last 90")
        #expect(record.confidence == .moderate)
        // 10 nights back: inside both windows, so no record at all.
        let inside30 = InsightFixture.inputs(count: 120) { index, _ in
            index == 119 ? Row(asleep: 500) : Row(asleep: index == 109 ? 540 : 420)
        }
        #expect(InsightFixture.records(inside30, .recordLongestNight).isEmpty)
    }

    @Test func theLowestRestingHeartRateIsARecord() throws {
        let inputs = InsightFixture.inputs(count: 20) { index, _ in Row(resting: index == 19 ? 50 : (index == 7 ? 51 : 56)) }
        let record = try #require(InsightFixture.records(inputs, .recordLowestRestingHeartRate).first)
        guard case .record(let evidence) = record.evidence else {
            Issue.record("expected record evidence")
            return
        }
        #expect(evidence.value == 50 && evidence.previousBest == 51)
        // A tie at 51 is not a record.
        let tie = InsightFixture.inputs(count: 20) { index, _ in Row(resting: index == 19 ? 51 : (index == 7 ? 51 : 56)) }
        #expect(InsightFixture.records(tie, .recordLowestRestingHeartRate).isEmpty)
    }

    @Test func theHighestRecoveryIsARecord() throws {
        func inputs(last: Int) -> InsightInputs {
            InsightFixture.inputs(count: 20, recovery: InsightFixture.recoveryScores(count: 20) { $0 == 19 ? last : ($0 == 4 ? 88 : 70) })
        }
        let record = try #require(InsightFixture.records(inputs(last: 89), .recordHighestRecovery).first)
        guard case .record(let evidence) = record.evidence else {
            Issue.record("expected record evidence")
            return
        }
        #expect(evidence.value == 89 && evidence.previousBest == 88)
        #expect(InsightFixture.records(inputs(last: 88), .recordHighestRecovery).isEmpty, "a tie is not a record")
    }

    @Test func theBestConsistencyStretchIsTheSteadiestWeek() throws {
        // Weeks of ±40 minute bedtimes, then a steady last week.
        let inputs = InsightFixture.inputs(count: 30) { index, _ in Row(bedtime: index >= 23 ? 660 + Double(index % 2) : 660 + (index % 2 == 0 ? 40 : -40)) }
        let record = try #require(InsightFixture.records(inputs, .recordBestConsistency).first)
        guard case .record(let evidence) = record.evidence else {
            Issue.record("expected record evidence")
            return
        }
        #expect(evidence.value < 1, "0.5-minute spread")
        #expect(evidence.previousBest > 10)
    }

    @Test func standingRecordsCoverTheLastNinetyNightsAndNeedFortyFive() throws {
        let inputs = InsightFixture.inputs(count: 100, recovery: InsightFixture.recoveryScores(count: 100) { 60 + $0 % 7 }) { index, _ in
            Row(asleep: index == 70 ? 540 : 420, resting: index == 80 ? 48 : 56)
        }
        let standing = InsightEngineV2.standingRecords(inputs)
        let byType = Dictionary(uniqueKeysWithValues: standing.map { ($0.type, $0) })
        #expect(byType[.recordLongestNight]?.value == 540)
        #expect(byType[.recordLongestNight]?.night == InsightFixture.last.adding(days: -(99 - 70)))
        #expect(byType[.recordLowestRestingHeartRate]?.value == 48)
        #expect(byType[.recordHighestRecovery]?.value == 66)
        // 44 nights is not enough.
        #expect(InsightEngineV2.standingRecords(InsightFixture.inputs(count: 44)).isEmpty)
        #expect(!InsightEngineV2.standingRecords(InsightFixture.inputs(count: 45)).isEmpty)
    }

    @Test func aTieForAStandingRecordGoesToTheNewestNight() {
        let inputs = InsightFixture.inputs(count: 60) { index, _ in Row(asleep: index == 10 || index == 40 ? 500 : 420) }
        let longest = InsightEngineV2.standingRecords(inputs).first { $0.type == .recordLongestNight }
        #expect(longest?.night == InsightFixture.last.adding(days: -(59 - 40)))
    }

    // MARK: - 12: learning milestones

    @Test func milestonesUnlockAtSevenFourteenAndThirtyNights() throws {
        func milestone(_ count: Int) -> Int? {
            guard let record = InsightFixture.records(InsightFixture.inputs(count: count), .milestone).first,
                case .milestone(let evidence) = record.evidence
            else { return nil }
            return evidence.milestone
        }
        #expect(milestone(6) == nil)
        #expect(milestone(7) == 7)
        #expect(milestone(13) == 7, "shown for a week after it unlocks")
        #expect(milestone(14) == 14)
        #expect(milestone(20) == 14)
        #expect(milestone(21) == nil, "the 14-night milestone has been shown for a week")
        #expect(milestone(29) == nil)
        #expect(milestone(30) == 30)
        #expect(milestone(36) == 30)
        #expect(milestone(37) == nil)
    }

    @Test func aMilestoneIsInformationOnly() throws {
        let record = try #require(InsightFixture.records(InsightFixture.inputs(count: 7), .milestone).first)
        #expect(record.type.isInformational)
        #expect(!record.type.offersSomethingToTry)
        #expect(record.actionability == 0)
        #expect(record.category == .longTerm)
    }

    // MARK: - Determinism

    @Test func theSameDataGivesTheSameRecordsEveryTime() {
        let inputs = patternInputs(early: 12, late: 12)
        let first = InsightEngineV2.generate(inputs)
        #expect(!first.isEmpty)
        for _ in 0..<5 { #expect(InsightEngineV2.generate(inputs) == first) }
    }

    @Test func theIdIsTheTypeAndAHashOfTheEvidence() throws {
        let a = try #require(InsightFixture.records(baselineInputs(lastAsleep: 390), .sleepDurationShift).first)
        let b = try #require(InsightFixture.records(baselineInputs(lastAsleep: 390), .sleepDurationShift).first)
        let c = try #require(InsightFixture.records(baselineInputs(lastAsleep: 380), .sleepDurationShift).first)
        #expect(a.id == b.id)
        #expect(a.id != c.id)
        #expect(a.id.hasPrefix("sleepDurationShift-"))
        #expect(a.id.count == "sleepDurationShift-".count + 8)
    }

    @Test func noveltyComesFromTheHistory() throws {
        var history = InsightHistory()
        let fresh = try #require(InsightFixture.records(baselineInputs(lastAsleep: 390), .sleepDurationShift).first)
        #expect(fresh.novelty == 1)
        history.recordFeatured(fresh, on: InsightFixture.last.adding(days: -7))
        let later = try #require(InsightFixture.records(baselineInputs(lastAsleep: 390), .sleepDurationShift, history: history).first)
        #expect(later.novelty == 0.5, "7 nights of 14")
    }

    @Test func recordsHoldDerivedValuesAndRoundTrip() throws {
        let records = InsightEngineV2.generate(patternInputs(early: 12, late: 12))
        let data = try JSONEncoder().encode(records)
        #expect(try JSONDecoder().decode([InsightRecord].self, from: data) == records)
    }
}
