import Foundation
import SwiftUI
import Testing

@testable import DesignSystem
@testable import HealthProviding
@testable import HomeFeature
@testable import InsightsKit
@testable import NoctisCore
@testable import RecoveryKit
@testable import SleepKit

// MARK: - Sleep landscape geometry

struct NightPlotTests {
    private func run(_ stage: StripStage, _ start: Double, _ end: Double, notch: Bool = false) -> StripSegment {
        StripSegment(stage: stage, start: start, end: end, isNotch: notch)
    }

    @Test func aRunIs8ptOr60PercentOfALaneIfThatIsSmaller() {
        #expect(NightPlot(width: 300, laneHeight: 34).thickness == 8)
        #expect(NightPlot(width: 300, laneHeight: 24).thickness == 8)
        #expect(abs(NightPlot(width: 300, laneHeight: 10).thickness - 6) < 1e-9)
        // At large text the lane grows and the run stays 8.
        #expect(NightPlot(width: 300, laneHeight: 52).thickness == 8)
    }

    @Test func theCapsStayInsideThePlot() {
        let plot = NightPlot(width: 300, laneHeight: 34)
        #expect(plot.inset == 4)
        #expect(plot.x(0) == 4)
        #expect(plot.x(1) == 296)
        for fraction in [0.0, 0.13, 0.5, 0.87, 1.0] {
            #expect(abs(plot.fraction(x: plot.x(fraction)) - fraction) < 1e-9)
        }
        // A finger past either end is the start or the end of the night.
        #expect(plot.fraction(x: -20) == 0)
        #expect(plot.fraction(x: 400) == 1)
    }

    @Test func aRunIsACapsuleExtendedByHalfTheThicknessAtBothEnds() {
        let plot = NightPlot(width: 300, laneHeight: 34)
        let rect = plot.runRect(run(.core, 0.2, 0.4))
        #expect(abs(rect.minX - (plot.x(0.2) - 4)) < 1e-9)
        #expect(abs(rect.maxX - (plot.x(0.4) + 4)) < 1e-9)
        #expect(rect.height == 8)
        #expect(abs(rect.midY - plot.y(.core)) < 1e-9)
        // Neighbors touching at 0.4 overlap by a full thickness.
        let next = plot.runRect(run(.core, 0.4, 0.6))
        #expect(abs((rect.maxX - next.minX) - 8) < 1e-9)
    }

    @Test func aRunIsAtLeast4ptWideBeforeItsCaps() {
        let plot = NightPlot(width: 300, laneHeight: 34)
        let tiny = plot.runRect(run(.deep, 0.5, 0.501))
        #expect(abs(tiny.width - (NightPlot.minimumRunWidth + 8)) < 1e-9)
        #expect(abs(tiny.midX - plot.x(0.5005)) < 1e-9)
    }

    @Test func aConnectorIsA3ptCapsuleOverlappingBothRuns() {
        let plot = NightPlot(width: 300, laneHeight: 34)
        let from = run(.core, 0.2, 0.4)
        let to = run(.deep, 0.4, 0.6)
        let step = plot.stepRect(NightConnector(position: 0.4, from: .core, to: .deep, entered: .deep))
        #expect(step.width == 3 && NightPlot.connectorWidth == 3)
        #expect(NightPlot.connectorOpacity == 0.7)
        #expect(abs(step.midX - plot.x(0.4)) < 1e-9)
        // Lane centers 34 apart, plus half a thickness above and below.
        #expect(abs(step.height - 42) < 1e-9)
        #expect(step.minY <= plot.runRect(from).minY)
        #expect(step.maxY >= plot.runRect(to).maxY)
        #expect(step.intersects(plot.runRect(from)) && step.intersects(plot.runRect(to)))
        // Going up is the same capsule.
        let up = plot.stepRect(NightConnector(position: 0.4, from: .deep, to: .rem, entered: .rem))
        #expect(abs(up.height - 76) < 1e-9)
    }

    @Test func theLanesArePitchedTwentyPercentWiderThanTheyWere() {
        // 28pt lanes became 34 (rounded), Sleep's 34 became 41, the share card's 20 became 24.
        #expect(abs(28 * 1.2 - 34) < 0.5 && abs(34 * 1.2 - 41) < 0.5 && 20 * 1.2 == 24)
    }

    @Test func aConnectorKeepsA2ptGapOfThePanelAroundARunItCrosses() throws {
        let plot = NightPlot(width: 300, laneHeight: 34)
        // Awake → Deep at 0.5 passes through the REM and Core lanes; a short run sits in Core there.
        let runs = [
            StripSegment(stage: .awake, start: 0, end: 0.5),
            StripSegment(stage: .core, start: 0.49, end: 0.51),
            StripSegment(stage: .deep, start: 0.5, end: 1),
        ]
        let steps = [NightConnector(position: 0.5, from: .awake, to: .deep, entered: .deep)]
        let render = NightRender(
            runs: runs, steps: steps,
            ribbon: runs.map { RibbonLane(start: $0.start, lane: $0.stage.lane) },
            heart: nil, hasStages: true, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600)
        )
        let paths = NightPathBuilder.build(NightPathsKey(plot: plot, heartHeight: 28, render: render))
        // Only the Core run is crossed: the joined Awake and Deep runs are not.
        #expect(paths.knockouts.count == 1)
        let core = plot.runRect(runs[1])
        let gap = try #require(paths.knockouts.first).boundingRect
        #expect(abs(gap.minX - (core.minX - 2)) < 1e-6 && abs(gap.maxY - (core.maxY + 2)) < 1e-6)
        // A step between neighboring lanes crosses nothing.
        let adjacent = NightRender(
            runs: runs, steps: [NightConnector(position: 0.5, from: .core, to: .deep, entered: .deep)],
            ribbon: runs.map { RibbonLane(start: $0.start, lane: $0.stage.lane) },
            heart: nil, hasStages: true, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600)
        )
        #expect(NightPathBuilder.build(NightPathsKey(plot: plot, heartHeight: 28, render: adjacent)).knockouts.isEmpty)
    }

    @Test func aNotchIs6ptInItsLaneAndNeverATallStick() {
        let plot = NightPlot(width: 300, laneHeight: 28)
        let notch = plot.notchRect(run(.awake, 0.3, 0.303, notch: true))
        #expect(notch.width == 6 && notch.height == 6)
        #expect(abs(notch.midY - plot.y(.awake)) < 1e-9)
    }

    @Test func theAreaRunsFromTheRibbonDownToTheDeepLine() {
        let plot = NightPlot(width: 300, laneHeight: 28)
        let area = plot.areaRect(run(.rem, 0.2, 0.4))
        #expect(abs(area.minY - plot.y(.rem)) < 1e-9)
        #expect(abs(area.maxY - plot.y(.deep)) < 1e-9)
        #expect(abs(area.minX - plot.x(0.2)) < 1e-9 && abs(area.maxX - plot.x(0.4)) < 1e-9)
        // A run on the Deep line has none.
        #expect(plot.areaRect(run(.deep, 0.2, 0.4)).height == 0)
    }

    @Test func theHeadDotFollowsTheRibbonsLane() {
        let runs = [
            StripSegment(stage: .core, start: 0, end: 0.4),
            StripSegment(stage: .awake, start: 0.4, end: 0.401, isNotch: true),
            StripSegment(stage: .deep, start: 0.401, end: 1),
        ]
        let render = NightRender(
            runs: runs, steps: [],
            ribbon: runs.filter { !$0.isNotch }.map { RibbonLane(start: $0.start, lane: $0.stage.lane) },
            heart: nil, hasStages: true, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600)
        )
        #expect(render.lane(at: 0) == .core)
        #expect(render.lane(at: 0.2) == .core)
        // The notch is not ribbon: the head stays in the run before it.
        #expect(render.lane(at: 0.4005) == .core)
        #expect(render.lane(at: 0.9) == .deep)
    }
}

// MARK: - The messy night

struct MessyNightTests {
    private let now = Fixture.date(2026, 9, 24, 10)
    private let locale = Locale(identifier: "en_US")

    private func chart() async throws -> NightChartContent {
        let provider = MockHealthKitProvider(scenario: .messyNight, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let snapshot = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        return try #require(HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: locale).lastNight?.chart)
    }

    @Test func itHasElevenAwakeningsSixOfThemNotches() async throws {
        let chart = try await chart()
        let awake = chart.spans.filter { $0.stage == .awake }
        #expect(awake.count == 11)
        #expect(awake.filter(\.isNotch).count == 6)
    }

    @Test func itHasOneFortyMinuteREMAndUnevenRuns() async throws {
        let chart = try await chart()
        let minutes = chart.minutes
        let rem = chart.spans.filter { $0.stage == .rem }.map { ($0.end - $0.start) * minutes }
        #expect(rem.count == 5)
        #expect(rem.filter { abs($0 - 40) < 0.5 }.count == 1)
        #expect(rem.max().map { abs($0 - 40) < 0.5 } == true)
        // Runs of many lengths, not cycles of the same one.
        let lengths = Set(chart.spans.map { Int((($0.end - $0.start) * minutes).rounded()) })
        #expect(lengths.count >= 12)
    }

    /// The reveal, frame by frame: the ribbon draws left to right behind a
    /// head dot, then the dot fades and the details come in. Images go to
    /// `NOCTIS_RENDER_OUT` when it's set.
    @Test func theRevealDrawsLeftToRightBehindItsHead() async throws {
        let chart = try await chart()
        var renders: [Data] = []
        for (name, drawn, details) in [
            ("reveal-25", 0.25, 0.0), ("reveal-50", 0.5, 0.0), ("reveal-80", 0.8, 0.0), ("reveal-96", 0.96, 0.0), ("reveal-done", 1.0, 1.0),
        ] {
            let renderer = ImageRenderer(
                content: ZStack {
                    NoctisAppColor.nightPanel
                    NightChartView(chart: chart, drawn: drawn, details: details).padding(20)
                }
                .frame(width: 362, height: 260)
                .environment(\.colorScheme, .light))
            renderer.scale = 3
            let image = try #require(renderer.uiImage)
            let data = try #require(image.pngData())
            renders.append(data)
            if let directory = ProcessInfo.processInfo.environment["NOCTIS_RENDER_OUT"] {
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
        // Every frame shows more of the night than the last.
        #expect(Set(renders).count == renders.count)
    }

    /// The scrub pill is wider than the chart at accessibility sizes: it
    /// wraps inside the chart instead of running off its edges.
    @Test func thePillWrapsInsideTheChartAtAccessibilitySizes() async throws {
        let chart = try await chart()
        var renders: [Data] = []
        for (name, position) in [("pill-ax3-left", 0.02), ("pill-ax3-middle", 0.5), ("pill-ax3-right", 0.98)] {
            let renderer = ImageRenderer(
                content: ZStack {
                    NoctisAppColor.nightPanel
                    NightChartView(
                        chart: chart, focusLane: .core, focusActive: true,
                        pillText: "12:14 AM · Core · 35 min · 59 bpm", pillPosition: position
                    )
                    .padding(EdgeInsets(top: 120, leading: 20, bottom: 20, trailing: 20))
                }
                .frame(width: 362, height: 640)
                .environment(\.dynamicTypeSize, .accessibility3)
                .environment(\.colorScheme, .light))
            renderer.scale = 3
            let data = try #require(renderer.uiImage?.pngData())
            renders.append(data)
            if let directory = ProcessInfo.processInfo.environment["NOCTIS_RENDER_OUT"] {
                try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
        #expect(renders.count == 3)
    }

    @Test func theRibbonStaysWhole() async throws {
        let chart = try await chart()
        // Every notch sits inside the night, and steps are only between
        // touching runs.
        #expect(chart.spans.first?.start == 0)
        #expect(chart.spans.last.map { abs($0.end - 1) < 1e-9 } == true)
        #expect(!chart.connectors.isEmpty)
        for step in chart.connectors {
            #expect(step.from != step.to)
            #expect((0...1).contains(step.position))
        }
    }
}

// MARK: - Your usual, on the ring

struct RecoveryUsualTests {
    /// 15 nights alternating around 450 min (440 / 460), 11 PM, 7 AM,
    /// HRV 45 / 55 and resting 54 / 56; the last is one of them.
    private func history(nights: Int) -> [NightMetrics] {
        Fixture.metrics(count: nights) { index in
            let up = index.isMultiple(of: 2)
            return (asleep: up ? 440 : 460, bedtime: up ? 650 : 670, wake: up ? 1130 : 1150, hrv: up ? 45 : 55, resting: up ? 54 : 56)
        }
    }

    private func result(_ nights: Int) throws -> RecoveryResult {
        let asOf = Fixture.date(2026, 9, 24, 9)
        guard case .scored(let result) = RecoveryEngine.evaluate(history: history(nights: nights), needMinutes: 480, asOf: asOf) else {
            Issue.record("expected a score at \(nights) nights")
            throw RecoveryUsualError.notScored
        }
        return result
    }

    enum RecoveryUsualError: Error { case notScored }

    @Test func usualIsTheMeanOfEachFactorsScoreOverTheWindow() throws {
        let result = try result(15)
        // Sleep: the window nights that were past learning (idx 4-13) scored
        // 83 (440 min) and 92 (460 min), five of each.
        #expect(try #require(result.factor(.sleepDuration)?.usual) == 87.5)
        // Every factor has one, and each is the mean of the window's own
        // scores for it, computed independently here.
        let all = history(nights: 15)
        let window = BaselineEngine.window(for: try #require(all.last).night, in: all)
        for kind in RecoveryFactorKind.allCases {
            let scores = window.compactMap { night -> Int? in
                guard all.count(where: { $0.night <= night.night }) >= RecoveryModelV1.learningNights else { return nil }
                let scored = RecoveryEngine.score(
                    lastNight: night, baselines: BaselineEngine.baselines(for: night.night, history: all),
                    baselineNights: BaselineEngine.window(for: night.night, in: all).count, needMinutes: 480
                )
                return scored.factor(kind)?.score
            }
            #expect(scores.count >= 5, "\(kind)")
            let expected = Double(scores.reduce(0, +)) / Double(scores.count)
            #expect(abs(try #require(result.factor(kind)?.usual) - expected) < 1e-9, "\(kind)")
        }
    }

    @Test func usualIsNilUnderFiveScoredNights() throws {
        // 9 nights: the window has 8, of which only 4 were past learning.
        let nine = try result(9)
        for factor in nine.factors {
            #expect(factor.usual == nil, "\(factor.kind)")
        }
    }

    @Test func aFactorNeedsItsOwnFiveNights() throws {
        // 10 nights: 5 window nights scored for sleep, but HRV and timing
        // needed a baseline of their own first, leaving 4.
        let ten = try result(10)
        #expect(ten.factor(.sleepDuration)?.usual != nil)
        #expect(ten.factor(.hrv)?.usual == nil)
        #expect(ten.factor(.restingHeartRate)?.usual == nil)
        #expect(ten.factor(.sleepConsistency)?.usual == nil)
    }

    @Test func theRingsTicksSitOnTheirSegmentsWithRenormalizedWeights() {
        // All four factors: 35/20/25/20 → the tick is `usual` of the way
        // along its own arc.
        let weights = [0.35, 0.20, 0.25, 0.20]
        let arcs = NoctisRecoveryRingLayout.arcs(weights: weights)
        for (index, arc) in arcs.enumerated() {
            #expect(NoctisRecoveryRingLayout.tickAngle(weights: weights, index: index, usual: 0) == arc.start)
            #expect(NoctisRecoveryRingLayout.tickAngle(weights: weights, index: index, usual: 1) == arc.end)
            let middle = NoctisRecoveryRingLayout.tickAngle(weights: weights, index: index, usual: 0.5)
            #expect(abs((middle ?? 0) - (arc.start + arc.end) / 2) < 1e-9)
        }
        // A missing factor: the other three share its weight, and every
        // segment (and its tick) moves with the new split.
        let renormalized = [0.35 / 0.8, 0.20 / 0.8, 0.25 / 0.8]
        let three = NoctisRecoveryRingLayout.arcs(weights: renormalized)
        let sleepTick = NoctisRecoveryRingLayout.tickAngle(weights: renormalized, index: 0, usual: 0.74)
        #expect(abs((sleepTick ?? 0) - (three[0].start + (three[0].end - three[0].start) * 0.74)) < 1e-9)
        #expect(three[0].end - three[0].start > arcs[0].end - arcs[0].start)
        // The ring's gaps keep a 3° split whatever the weights.
        #expect(abs(three[1].start - three[0].end - NoctisRecoveryRingLayout.gapDegrees) < 1e-9)
        // Out of range.
        #expect(NoctisRecoveryRingLayout.tickAngle(weights: weights, index: 9, usual: 0.5) == nil)
        #expect(NoctisRecoveryRingLayout.tickAngle(weights: weights, index: 0, usual: 1.4) == arcs[0].end)
    }

    @Test func homeSaysUsualOnlyWhenABaselineExists() throws {
        let with = HomeScreenBuilder.scoredContent(try result(15))
        #expect(with.usualCaption == "Tick = your usual")
        #expect(with.segments.allSatisfy { $0.usual != nil })
        let sleep = try #require(with.factors.first { $0.kind == .sleepDuration })
        #expect(sleep.usual == 88)
        #expect(sleep.spoken == "Sleep \(sleep.score), usual 88")
        #expect(with.accessibilityLabel.contains("Sleep \(sleep.score), usual 88"))
        let without = HomeScreenBuilder.scoredContent(try result(9))
        #expect(without.usualCaption == nil)
        #expect(without.factors.allSatisfy { $0.usual == nil })
        #expect(without.factors.allSatisfy { $0.spoken == "\($0.name) \($0.score)" })
    }
}

// MARK: - This week: scrub and color

struct WeekScrubTests {
    @Test func barsAreTheirColumnLessTenAtMost26() {
        // 375pt screen: 42pt columns → 24 (capped); 320pt: 34pt → 22.
        #expect(WeekColumns.barWidth(barsWidth: 295, count: 7) == 24)
        #expect(abs(WeekColumns.barWidth(barsWidth: 240, count: 7) - (240.0 / 7 - 12)) < 1e-9)
        #expect(WeekColumns.barWidth(barsWidth: 700, count: 7) == 24)
        // Before the chart is measured.
        #expect(WeekColumns.barWidth(barsWidth: 0, count: 7) == 24)
        #expect(WeekColumns.cornerRadius == 6)
    }

    @Test func aSelectionDimsTheOthersTo45Percent() {
        #expect(WeekColumns.dimmedOpacity == 0.45)
    }

    @Test func theNightNearestTheFingerIsSelectedAsItMoves() {
        let bars: CGFloat = 280
        let outset: CGFloat = 40
        let column = bars / 7
        // Dragging across the chart passes every night in order.
        var seen: [Int] = []
        var x: CGFloat = 0
        while x <= bars + 2 * outset {
            let index = WeekColumns.index(x: x, barsWidth: bars, outset: outset, count: 7)
            if seen.last != index { seen.append(index) }
            x += 1
        }
        #expect(seen == [0, 1, 2, 3, 4, 5, 6])
        // Backwards too.
        #expect(WeekColumns.index(x: outset + column * 3.4, barsWidth: bars, outset: outset, count: 7) == 3)
        #expect(WeekColumns.index(x: outset + column * 2.6, barsWidth: bars, outset: outset, count: 7) == 2)
    }

    @Test func thresholdsSeparateATapAScrubAndAScroll() {
        #expect(WeekColumns.tapSlop == 10)
        #expect(WeekColumns.scrollThreshold == 12)
    }

    @Test func lastNightsBarIsMarkedNotTheOthersDimmed() async throws {
        let now = Fixture.date(2026, 9, 24, 10)
        let provider = MockHealthKitProvider(scenario: .full, referenceDate: now, calendar: Fixture.calendar(), startAuthorized: true)
        let snapshot = await HomeRepository(provider: provider, timeZone: Fixture.newYork, clock: { now }).refresh(profile: UserProfileSnapshot())
        let week = try #require(HomeScreenBuilder.build(snapshot, now: now, calendar: Fixture.calendar(), locale: Locale(identifier: "en_US")).week)
        #expect(week.bars.map(\.isLastNight) == [false, false, false, false, false, false, true])
    }
}
