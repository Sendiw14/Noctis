import Accessibility
import Testing

@testable import DesignSystem

// QA part 3 (QA_COVERAGE.md 3.7): a chart of many points can be read by Audio Graph, and a night with nothing recorded is a gap, not a zero.

struct AudioGraphTests {
    @Test func aSeriesBecomesOneDescribedSeriesWithAGapWhereNothingWasRecorded() throws {
        let graph = NoctisAudioGraph(
            title: "Sleep this week", summary: "One bar a night.", xTitle: "Night", yTitle: "Time asleep",
            points: [
                NoctisGraphPoint(x: "M", y: 0.8, spoken: "Monday, 7 hours"),
                NoctisGraphPoint(x: "T", y: nil, spoken: "Tuesday, no sleep recorded"),
                NoctisGraphPoint(x: "W", y: 0.6, spoken: "Wednesday, 5 hours"),
            ],
            yRange: 0...1, yDescription: { "\(Int(($0 * 100).rounded())) percent" }
        )
        let descriptor = graph.makeChartDescriptor()
        let series = try #require(descriptor.series.first)
        #expect(descriptor.series.count == 1)
        #expect(series.dataPoints.count == 3)
        #expect(series.dataPoints[0].yValue != nil)
        #expect(series.dataPoints[1].yValue == nil, "a night with nothing recorded is a gap")
        #expect(series.dataPoints[2].label == "Wednesday, 5 hours")
        #expect(descriptor.title == "Sleep this week")
        let axis = try #require(descriptor.xAxis as? AXNumericDataAxisDescriptor)
        #expect(axis.valueDescriptionProvider(2) == "W")
        let yAxis = try #require(descriptor.yAxis)
        #expect(yAxis.valueDescriptionProvider(0.5) == "50 percent")
    }

    @Test func aSingleOrEmptySeriesStillMakesADescriptor() {
        let one = NoctisAudioGraph(title: "t", summary: "s", xTitle: "x", yTitle: "y", points: [NoctisGraphPoint(x: "a", y: 1, spoken: "a")], yRange: 0...1) { _ in "" }
        #expect(one.makeChartDescriptor().series.first?.dataPoints.count == 1)
        let none = NoctisAudioGraph(title: "t", summary: "s", xTitle: "x", yTitle: "y", points: [], yRange: 0...1) { _ in "" }
        #expect(none.makeChartDescriptor().series.first?.dataPoints.isEmpty == true)
    }
}
