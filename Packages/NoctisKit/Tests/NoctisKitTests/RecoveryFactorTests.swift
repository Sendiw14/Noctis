import Foundation
import Testing
@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import NoctisCore
@testable import RecoveryFeature
@testable import RecoveryKit
@testable import SleepKit

// A factor's page: the wording around its chart, the resampled curve that
// morphs between ranges, and the animatable pieces the chart is drawn from.

private let now = Fixture.date(2026, 9, 24, 10)
private let locale = Locale(identifier: "en_US")

private func snapshot(_ scenario: MockScenario = .full) async -> RecoverySnapshot {
    let provider = MockHealthKitProvider(scenario: scenario, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
    let clock = now
    return await RecoveryRepository(provider: provider, timeZone: Fixture.newYork, clock: { clock }).refresh(profile: UserProfileSnapshot())
}

private func content(_ snap: RecoverySnapshot, _ kind: RecoveryFactorKind, _ range: RecoveryFactorRange = .fortnight) -> RecoveryFactorContent? {
    let selection = RecoverySelection(segment: .today, factor: kind, factorRange: range)
    let model = RecoveryRenderModelBuilder.build(snap, selection: selection)
    return RecoveryScreenBuilder.factorContent(snap, model: model, selection: selection, calendar: Fixture.calendar(), locale: locale)
}

struct RecoveryFactorContentTests {
    @Test func aPageForEachFactorWithHomesValueBaselineAndSentence() async throws {
        let snap = await snapshot(.full)
        for kind in RecoveryFactorKind.allCases {
            let page = try #require(content(snap, kind))
            let row = HomeScreenBuilder.detailRow(
                try #require(snap.result?.factor(kind)), result: try #require(snap.result), needMinutes: snap.needMinutes,
                format: HomeFormat(calendar: Fixture.calendar(), locale: locale)
            )
            #expect(page.value == row.value && page.baseline == row.baseline && page.sentence == row.sentence)
            #expect(page.name == HomeScreenBuilder.shortName(kind))
        }
    }

    @Test func oneChartPointPerNightWithAPillThatSaysWhatTheNightWas() async throws {
        let snap = await snapshot(.full)
        let page = try #require(content(snap, .hrv))
        let series = try #require(snap.series(.hrv, .fortnight))
        #expect(page.points.count == 14)
        #expect(page.points.map(\.night) == series.points.map(\.night))
        let last = try #require(series.points.last)
        let value = Int(try #require(last.value).rounded())
        let score = try #require(last.score)
        let detail = try #require(page.points.last?.detail)
        #expect(detail.hasSuffix("· \(value) ms · Score \(score)"), Comment(rawValue: detail))
        // Two weeks name the weekday; a month names the date.
        let month = try #require(content(snap, .hrv, .month))
        #expect(month.points.count == 30)
        #expect(month.points.last?.detail.contains(",") == true)
        #expect(page.points.last?.accessibilityLabel.contains("HRV") == true)
    }

    @Test func aNightWithNoValueIsNoDataInThePill() async throws {
        let snap = await snapshot(.gap)
        // The gap scenario has no scored today; build from a sleep-only page instead.
        #expect(content(snap, .hrv) == nil, "no score today, no page")
        let sleepOnly = await snapshot(.sleepOnly)
        #expect(content(sleepOnly, .hrv) == nil, "HRV isn't in a sleep-only score")
        let series = try #require(sleepOnly.series(.sleepDuration, .quarter))
        #expect(series.points.count == 90)
    }

    @Test func valuesAreSaidInEachFactorsOwnUnit() {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
        #expect(RecoveryScreenBuilder.valueText(.sleepDuration, 402, format: format) == "6h 42m")
        #expect(RecoveryScreenBuilder.valueText(.hrv, 48.4, format: format) == "48 ms")
        #expect(RecoveryScreenBuilder.valueText(.restingHeartRate, 53.6, format: format) == "54 bpm")
        #expect(RecoveryScreenBuilder.valueText(.sleepConsistency, 660, format: format) == format.clock(minutesSinceMidnight: 23 * 60))
        #expect(RecoveryScreenBuilder.spokenValue(.hrv, 48, format: format) == "48 milliseconds")
        #expect(RecoveryScreenBuilder.axisText(.sleepDuration, 420, format: format) == "7h")
        #expect(RecoveryScreenBuilder.axisText(.hrv, 50, format: format) == "50")
        #expect(RecoveryScreenBuilder.axisText(.sleepConsistency, 660, format: format) == format.hour(minutesSinceMidnight: 23 * 60))
        #expect(RecoveryScreenBuilder.rangeMetric(HomeFormat.durationMetric(350), HomeFormat.durationMetric(500)).plain == "5h 50m – 8h 20m")
        #expect(RecoveryScreenBuilder.rangeMetric(HomeFormat.durationMetric(350), HomeFormat.durationMetric(500)).spoken == "5 hours 50 minutes to 8 hours 20 minutes")
    }

    @Test func todayBaselineRangeAndTheFactorsPointsAreTheEnginesNumbers() async throws {
        let snap = await snapshot(.full)
        let page = try #require(content(snap, .restingHeartRate, .month))
        let series = try #require(snap.series(.restingHeartRate, .month))
        #expect(page.tiles.map(\.id) == ["today", "baseline", "range", "points"])
        let format = HomeFormat(calendar: Fixture.calendar(), locale: locale)
        #expect(page.tiles[0].value == RecoveryScreenBuilder.valueMetric(.restingHeartRate, try #require(series.today), format: format))
        #expect(page.tiles[1].value == RecoveryScreenBuilder.valueMetric(.restingHeartRate, try #require(series.usual), format: format))
        let low = try #require(series.minimum), high = try #require(series.maximum)
        #expect(page.tiles[2].value.plain == "\(Int(low.rounded()))bpm – \(Int(high.rounded()))bpm")
        #expect(page.tiles[2].value.spoken == "\(Int(low.rounded())) beats per minute to \(Int(high.rounded())) beats per minute")
        let points = try #require(snap.contributions?.contribution(.restingHeartRate)).wholePoints
        #expect(page.tiles[3].value.spoken == "\(points) points")
        #expect(page.tiles[3].value.plain == "+\(points) points")
        #expect(page.tiles[3].note?.hasPrefix("vs usual: ") == true)
    }

    @Test func consistencyIsChartedAsBedtimeAndSaysSo() async throws {
        let snap = await snapshot(.full)
        let page = try #require(content(snap, .sleepConsistency))
        #expect(page.measure == "Bedtime")
        #expect(page.tiles.first?.title == "Today's bedtime" && page.tiles[1].title == "Usual bedtime")
        #expect(page.valueSuffix == "off", "the headline is how far off, as on the card")
        #expect(page.explanation.last?.text.contains("The chart shows your bedtime; the score counts your wake time too.") == true)
    }

    @Test func theAxesAreLabeledAndTheBandIsNamed() async throws {
        let snap = await snapshot(.full)
        let page = try #require(content(snap, .hrv, .quarter))
        #expect(page.yLabels.count >= 2 && page.yLabels.allSatisfy { (0...1).contains($0.position) })
        // Positions run down from the top: the highest label is first.
        #expect(page.yLabels.map(\.position) == page.yLabels.map(\.position).sorted(by: >))
        #expect(page.xLabels.map(\.position) == [0, 0.5, 1])
        #expect(page.bandCaption?.hasPrefix("The shaded band is your normal range: ") == true)
        #expect(page.bandCaption?.hasSuffix(" ms.") == true)
        #expect(page.emptyNote == nil)
    }

    @Test func aFactorWithNoValuesInTheWindowSaysSoAndDrawsNothing() async throws {
        // A sleep-only history: HRV has no values, and no page.
        let sleepOnly = await snapshot(.sleepOnly)
        #expect(sleepOnly.series(.hrv, .fortnight)?.nightsRecorded == 0)
        let series = try #require(sleepOnly.series(.hrv, .fortnight))
        #expect(RecoveryRenderModelBuilder.factorLine(series) == nil)
    }

    @Test func eachFactorExplainsHowItIsScoredAndWhyItCountsFromTheModelsConstants() {
        for kind in RecoveryFactorKind.allCases {
            let blocks = RecoveryScreenBuilder.explanation(kind, needMinutes: 480)
            #expect(blocks.map(\.title) == ["How it's scored", "Why it counts"])
            let weight = Int(RecoveryModelV3.weights[kind] ?? 0)
            #expect(blocks[1].text.contains("\(weight)% of your recovery score"), "\(kind)")
        }
        let sleep = RecoveryScreenBuilder.explanation(.sleepDuration, needMinutes: 480)[0].text
        #expect(sleep.contains("8h need") && sleep.contains("each 1% under it takes off 2 points"))
        #expect(RecoveryScreenBuilder.explanation(.hrv, needMinutes: 480)[0].text.contains("each standard deviation above it adds 15 points"))
        #expect(RecoveryScreenBuilder.explanation(.sleepConsistency, needMinutes: 480)[0].text.contains("falls to 0 at 120 minutes"))
    }

    @Test func nothingOnAFactorPageJudgesANightOrAdvisesRest() async {
        for scenario in [MockScenario.full, .recoveryDip, .lateBedtime] {
            let snap = await snapshot(scenario)
            for kind in RecoveryFactorKind.allCases {
                for range in RecoveryFactorRange.allCases {
                    let text = String(describing: content(snap, kind, range)).lowercased()
                    for word in ["poor", "bad", "should rest", "you should", "you are recovered", "warning", "danger", "unhealthy"] {
                        #expect(!text.contains(word), "\(scenario) \(kind) \(range): \"\(word)\"")
                    }
                }
            }
        }
    }
}

struct RecoveryCurveTests {
    @Test func aCurveIsAlwaysTheSameLengthWhateverTheRange() async throws {
        let snap = await snapshot(.full)
        for range in RecoveryFactorRange.allCases {
            let series = try #require(snap.series(.hrv, range))
            let line = try #require(RecoveryRenderModelBuilder.factorLine(series))
            #expect(line.curve.count == FactorLineRender.curveSamples)
            #expect(line.curve.allSatisfy { (0...1).contains($0) })
            // It starts on the first night and ends on the last.
            #expect(abs(line.curve[0] - (line.values.compactMap { $0 }.first ?? -1)) < 1e-12)
            #expect(abs(line.curve[line.curve.count - 1] - (line.values.compactMap { $0 }.last ?? -1)) < 1e-12)
        }
    }

    @Test func aCurveRunsStraightBetweenRecordedNightsAndBridgesAGap() {
        let values: [Double?] = [0, nil, nil, 1, 0.5]
        let curve = RecoveryRenderModelBuilder.curve(values)
        let n = FactorLineRender.curveSamples
        #expect(curve.count == n)
        // Position 0 is the first night; position 3 is the fourth; the gap between is a straight line.
        #expect(abs(curve[0] - 0) < 1e-12)
        let third = curve[Int((3.0 / 4.0 * Double(n - 1)).rounded())]
        #expect(abs(third - 1) < 0.02)
        let half = curve[Int((1.5 / 4.0 * Double(n - 1)).rounded())]
        #expect(abs(half - 0.5) < 0.02, "halfway across the gap is halfway between the values")
        #expect(abs(curve[n - 1] - 0.5) < 1e-12)
    }

    @Test func nothingRecordedIsAFlatLineInTheMiddleAndOneNightIsFlatAtItsValue() {
        #expect(Set(RecoveryRenderModelBuilder.curve([nil, nil, nil])) == [0.5])
        #expect(Set(RecoveryRenderModelBuilder.curve([0.3])) == [0.3])
        #expect(Set(RecoveryRenderModelBuilder.curve([nil, 0.7, nil])) == [0.7], "held flat before and after the only value")
    }
}

struct RecoveryAnimatableTests {
    @Test func aVectorMovesEachValueTowardItsCounterpartAndPadsTheShorterWithZeros() {
        var a = AnimatableVector(values: [1, 2, 3])
        let b = AnimatableVector(values: [3, 6, 9])
        let difference = b - a
        #expect(difference.values == [2, 4, 6])
        var halfway = difference
        halfway.scale(by: 0.5)
        a = a + halfway
        #expect(a.values == [2, 4, 6])
        #expect((AnimatableVector(values: [1]) + AnimatableVector(values: [1, 2])).values == [2, 2])
        #expect(AnimatableVector.zero.magnitudeSquared == 0)
        #expect(AnimatableVector(values: [3, 4]).magnitudeSquared == 25)
    }

    @Test func theCurveShapeHoldsItsSamplesThenTheNumberOfNightsAndDrawsAcrossTheRect() {
        let curve = FactorCurve(samples: [0, 0.5, 1], nights: 3)
        #expect(curve.animatableData.values == [0, 0.5, 1, 3])
        let path = curve.path(in: CGRect(x: 0, y: 0, width: 300, height: 100))
        // A night sits mid-column: the curve runs from a sixth of the way in to a sixth from the end.
        #expect(abs(path.boundingRect.minX - 50) < 0.001 && abs(path.boundingRect.maxX - 250) < 0.001)
        #expect(abs(path.boundingRect.minY - 0) < 0.001 && abs(path.boundingRect.maxY - 100) < 0.001)
        #expect(FactorCurve(samples: [], nights: 0).path(in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
    }
}

struct RecoveryFactorAxisTests {
    @Test func aBedtimeTickOnTheHalfHourSaysSoSoNoTwoTicksReadTheSame() {
        let format = HomeFormat(calendar: Fixture.calendar(), locale: Locale(identifier: "en_US"))
        // Minutes after noon: 660 is 11:00 PM, 690 is 11:30 PM (the system may use a narrow no-break space).
        func text(_ value: Double) -> String {
            RecoveryScreenBuilder.axisText(.sleepConsistency, value, format: format)
                .replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        #expect(text(660) == "11 PM")
        #expect(text(690) == "11:30 PM")
        #expect(text(720) == "12 AM")
        #expect(text(660) != text(690))
    }
}
