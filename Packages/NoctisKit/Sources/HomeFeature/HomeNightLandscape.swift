import DesignSystem
import NoctisCore
import SwiftUI

/// The sleep landscape as a component: the ribbon through the stage
/// lanes, the heart-rate strip, lane labels, the time axis and the stage
/// totals, with the scrub (a sideways drag: a line, a dot and a pill with
/// the time, stage, length and heart rate) and the lane focus (a tapped
/// lane label, or a stage total when `tapsTotals` is on, shows that stage
/// across the night and dims the rest). Home's night panel and the Sleep
/// tab both use it; `laneHeight` makes it taller.
public struct NightLandscapeView: View {
    private let chart: NightChartContent
    private let laneHeight: CGFloat?
    private let drawn: Double
    private let details: Double
    private let tapsTotals: Bool
    private let reservesPillRow: Bool
    @Binding private var laneFocus: NightLane?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The latest scrub reading, kept after release so the pill can fade.
    @State private var scrub: NightReading?
    @State private var scrubbing = false

    /// - Parameters:
    ///   - drawn: 0...1, how much of the ribbon has drawn (the reveal).
    ///   - details: 0...1, the heart strip and totals fading in after it.
    ///   - laneFocus: the stage highlighted across the night; owned by the
    ///     caller so a stage total elsewhere can set it too.
    public init(
        chart: NightChartContent,
        laneHeight: CGFloat? = nil,
        drawn: Double = 1,
        details: Double = 1,
        tapsTotals: Bool = false,
        reservesPillRow: Bool = false,
        laneFocus: Binding<NightLane?>
    ) {
        self.chart = chart
        self.laneHeight = laneHeight
        self.drawn = drawn
        self.details = details
        self.tapsTotals = tapsTotals
        self.reservesPillRow = reservesPillRow
        _laneFocus = laneFocus
    }

    public var body: some View {
        let focusLane: NightLane? = scrubbing ? scrub?.lane : (laneFocus ?? scrub?.lane)
        let laneTotal: String? = laneFocus.flatMap { total($0) }
        let pillText: String? = scrubbing ? scrub?.text : (laneTotal ?? scrub?.text)
        let pillPosition: Double = scrubbing || laneFocus == nil ? (scrub?.position ?? 0) : 0
        let toggleLane: ((NightLane) -> Void)? = chart.hasStages ? { toggle($0) } : nil
        NightChartView(
            chart: chart,
            drawn: drawn,
            details: details,
            focusLane: focusLane,
            focusActive: scrubbing || laneFocus != nil,
            line: scrub,
            showsLine: scrubbing,
            pillText: pillText,
            pillPosition: pillPosition,
            onScrub: chart.hasStages ? { scrubbed($0) } : nil,
            onLaneTap: toggleLane,
            onTotalTap: tapsTotals ? toggleLane : nil,
            laneHeightOverride: laneHeight,
            reservesPillRow: reservesPillRow
        )
        .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: scrubbing)
        .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: laneFocus)
        .modifier(NightChartAudioGraph(chart: chart, focus: laneFocus.flatMap(total)))
    }

    private func total(_ lane: NightLane) -> String? {
        chart.laneTotals.first { $0.lane == lane }?.text
    }

    /// The finger at `position` (0...1), or lifted (nil).
    private func scrubbed(_ position: Double?) {
        guard let position else {
            scrubbing = false
            NoctisSignpost.end(.scrub)
            return
        }
        NoctisSignpost.begin(.scrub)
        let reading = chart.reading(at: position)
        if scrubbing, let reading, reading.stage != scrub?.stage {
            NoctisHaptics.snapLight()
        }
        laneFocus = nil
        scrub = reading
        scrubbing = true
    }

    private func toggle(_ lane: NightLane) {
        laneFocus = laneFocus == lane ? nil : lane
    }
}
