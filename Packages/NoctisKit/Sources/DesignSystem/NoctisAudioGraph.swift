import Accessibility
import SwiftUI

/// One point of a series read by Audio Graph: where it sits (`x`, what the axis calls it), how high (`y`, nil for a night with nothing recorded)
/// and what VoiceOver says when it lands on it.
public nonisolated struct NoctisGraphPoint: Sendable, Equatable {
    public let x: String
    public let y: Double?
    public let spoken: String

    public init(x: String, y: Double?, spoken: String) {
        self.x = x
        self.y = y
        self.spoken = spoken
    }
}

/// Audio Graph for a chart of many points (QA part 3, R67): the rotor's "Audio Graph" plays the series as a tone and reads each point. The chart
/// is still one adjustable element for swiping through its nights; this is the second way in, for a person who wants the shape (QA_LEDGER.md).
public struct NoctisAudioGraph: AXChartDescriptorRepresentable {
    public let title: String
    public let summary: String
    public let xTitle: String
    public let yTitle: String
    public let points: [NoctisGraphPoint]
    public let yRange: ClosedRange<Double>
    public let yDescription: @Sendable (Double) -> String

    public init(
        title: String, summary: String, xTitle: String, yTitle: String, points: [NoctisGraphPoint], yRange: ClosedRange<Double>,
        yDescription: @escaping @Sendable (Double) -> String
    ) {
        self.title = title
        self.summary = summary
        self.xTitle = xTitle
        self.yTitle = yTitle
        self.points = points
        self.yRange = yRange
        self.yDescription = yDescription
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        let names = points.map(\.x)
        let last = Double(max(points.count - 1, 1))
        let xAxis = AXNumericDataAxisDescriptor(title: xTitle, range: 0...last, gridlinePositions: []) { value in
            let index = Int(value.rounded())
            return names.indices.contains(index) ? names[index] : ""
        }
        let yAxis = AXNumericDataAxisDescriptor(title: yTitle, range: yRange, gridlinePositions: []) { [yDescription] value in yDescription(value) }
        let data = points.enumerated().map { index, point in
            AXDataPoint(x: Double(index), y: point.y, additionalValues: [], label: point.spoken)
        }
        return AXChartDescriptor(
            title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: title, isContinuous: false, dataPoints: data)]
        )
    }
}
