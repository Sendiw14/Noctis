import DesignSystem
import NoctisCore
import SleepKit
import SwiftUI

// The sleep landscape: one continuous ribbon through last night's stage
// timeline, in four lanes. The night panel and the share card use it.

/// The chart's plot space: how positions along the night (0...1) and lanes
/// become points. The ribbon is 12pt thick (60% of a lane if that's
/// smaller), and the plot is inset by half of that at both ends so the
/// first and last caps stay inside.
nonisolated struct NightPlot: Equatable {
    let width: CGFloat
    let laneHeight: CGFloat

    static let maximumThickness: CGFloat = 12
    static let thicknessShare: CGFloat = 0.6
    /// A run is drawn at least this wide (before its half-thickness caps).
    static let minimumRunWidth: CGFloat = 4
    /// The notch that stands for a run under 3 minutes.
    static let notchSize: CGFloat = 6
    /// The reveal's head dot.
    static let headSize: CGFloat = 6

    var thickness: CGFloat { min(Self.maximumThickness, Self.thicknessShare * laneHeight) }
    var inset: CGFloat { thickness / 2 }

    /// x for a position along the night.
    func x(_ fraction: Double) -> CGFloat {
        inset + CGFloat(fraction) * max(width - 2 * inset, 0)
    }

    /// The position along the night for an x (clamped to the night).
    func fraction(x: CGFloat) -> Double {
        let span = width - 2 * inset
        guard span > 0 else { return 0 }
        return min(max(Double((x - inset) / span), 0), 1)
    }

    /// The center of a lane.
    func y(_ lane: NightLane) -> CGFloat {
        laneHeight * (CGFloat(lane.rawValue) + 0.5)
    }

    var lanesHeight: CGFloat { laneHeight * CGFloat(NightLane.allCases.count) }

    /// The ribbon's capsule for a run: its width (at least 4pt) plus half
    /// the thickness at each end, so neighboring runs overlap and joins
    /// merge.
    func runRect(_ run: StripSegment) -> CGRect {
        let center = (x(run.start) + x(run.end)) / 2
        let length = max(x(run.end) - x(run.start), Self.minimumRunWidth) + thickness
        return CGRect(x: center - length / 2, y: y(run.stage.lane) - thickness / 2, width: length, height: thickness)
    }

    /// The vertical capsule for a step: the ribbon's thickness wide, from
    /// the lane it leaves to the lane it enters, overlapping both runs.
    func stepRect(_ step: NightConnector) -> CGRect {
        let top = min(y(step.from), y(step.to)) - thickness / 2
        let bottom = max(y(step.from), y(step.to)) + thickness / 2
        return CGRect(x: x(step.position) - thickness / 2, y: top, width: thickness, height: bottom - top)
    }

    /// The 6pt notch for a run under 3 minutes.
    func notchRect(_ run: StripSegment) -> CGRect {
        let center = CGPoint(x: (x(run.start) + x(run.end)) / 2, y: y(run.stage.lane))
        return CGRect(x: center.x - Self.notchSize / 2, y: center.y - Self.notchSize / 2, width: Self.notchSize, height: Self.notchSize)
    }

    /// The stepped area under a run: from the ribbon down to the Deep
    /// lane's line.
    func areaRect(_ run: StripSegment) -> CGRect {
        let top = y(run.stage.lane)
        return CGRect(x: x(run.start), y: top, width: x(run.end) - x(run.start), height: max(y(.deep) - top, 0))
    }
}

nonisolated extension NightChartContent {
    /// The lane the ribbon is in at `position` (the run there, or the
    /// nearest before it), for the reveal's head dot.
    func ribbonLane(at position: Double) -> NightLane? {
        let runs = spans.filter { !$0.isNotch }
        guard let first = runs.first else { return nil }
        if position <= first.start { return first.stage.lane }
        return (runs.last { $0.start <= position } ?? first).stage.lane
    }
}

/// The ribbon's color for a run.
extension StripSegment {
    var ribbonColor: Color {
        stage == .asleep ? NoctisAppColor.sage : stage.lane.tint
    }
}

// MARK: - The chart

/// Four lanes (Awake, REM, Core, Deep) and, through them, one ribbon: a
/// capsule for each run, a vertical capsule for each lane change, a 6pt
/// notch for a run under 3 minutes, and a faint stepped area under it all.
/// Under the lanes: the heart-rate strip; then the times and each stage's
/// total. Without stages: one sage bar in the Core lane.
///
/// Three layers, so nothing repeats work: the ribbon (static; revealed by
/// a mask that grows left to right, with a head dot that travels with it),
/// the heart strip (static; fades in after the ribbon), and the scrub
/// overlay (line, dot and dimming; redrawn as a finger moves, never the
/// ribbon).
struct NightChartView: View {
    let chart: NightChartContent
    /// 0...1: how much of the ribbon has drawn (the morning reveal).
    var drawn: Double = 1
    /// 0...1: the heart strip and the totals, once the ribbon is in.
    var details: Double = 1
    var focusLane: NightLane?
    var focusActive = false
    var line: NightReading?
    var showsLine = false
    var pillText: String?
    var pillPosition: Double = 0
    var onScrub: ((Double?) -> Void)?
    var onLaneTap: ((NightLane) -> Void)?
    /// A fixed lane height (the share card); otherwise it scales with the
    /// lane labels (R4).
    var laneHeightOverride: CGFloat?

    @NoctisScaledLength(relativeTo: .caption2) private var scaledLaneHeight: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    static let heartHeight: CGFloat = 28
    static let heartGap: CGFloat = 8
    /// Every lane label's tap area is at least this tall (R10 targets).
    static let minimumTarget: CGFloat = 44

    private var laneHeight: CGFloat { laneHeightOverride ?? scaledLaneHeight }
    private var plot: NightPlot { NightPlot(width: width, laneHeight: laneHeight) }
    private var heartBlock: CGFloat { chart.heart == nil ? 0 : Self.heartGap + Self.heartHeight }
    private var targetOutset: CGFloat { max(Self.minimumTarget - laneHeight, 0) / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            HStack(alignment: .top, spacing: 0) {
                laneLabels
                VStack(spacing: NoctisSpacing.xxs) {
                    layers
                    HStack {
                        ForEach(Array(chart.timeLabels.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer(minLength: NoctisSpacing.xxs) }
                            Text(label)
                                .noctisFont(11, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
                                .foregroundStyle(.noctisNightInk2)
                        }
                    }
                }
            }
            if !chart.laneTotals.isEmpty {
                NightStageTotalsView(totals: chart.laneTotals)
                    .opacity(details)
                    .animation(fade, value: details)
            }
        }
        .accessibilityHidden(true)
    }

    /// The heart strip and totals fade in as the ribbon finishes.
    private var fade: Animation? {
        reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3).delay(HomeRevealPhase.contentDelay + HomeReveal.nightDuration - 0.2)
    }

    private var layers: some View {
        ZStack(alignment: .topLeading) {
            NightRibbonLayer(chart: chart, plot: plot)
                .frame(height: plot.lanesHeight)
                // Revealed left to right; the mask is a scaled rectangle,
                // so the animation costs no redraw of the ribbon.
                .mask(alignment: .leading) {
                    Rectangle().scaleEffect(x: max(drawn, 0.0001), y: 1, anchor: .leading)
                }
            if chart.hasStages {
                NightRevealHead(chart: chart, plot: plot, drawn: drawn)
                    .frame(height: plot.lanesHeight)
                    .allowsHitTesting(false)
            }
            if let heart = chart.heart {
                NightHeartLayer(heart: heart, plot: plot)
                    .frame(height: Self.heartHeight)
                    .offset(y: plot.lanesHeight + Self.heartGap)
                    .opacity(details)
                    .animation(fade, value: details)
            }
            NightDimOverlay(laneHeight: laneHeight, focus: focusLane, active: focusActive)
                .frame(height: plot.lanesHeight)
                .allowsHitTesting(false)
            NightScrubLine(plot: plot, reading: line, height: plot.lanesHeight + heartBlock)
                .opacity(showsLine ? 1 : 0)
                .frame(height: plot.lanesHeight + heartBlock)
                .allowsHitTesting(false)
        }
        .frame(height: plot.lanesHeight + heartBlock, alignment: .top)
        .overlay(alignment: .top) { pill }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(HorizontalScrubGesture(isEnabled: onScrub != nil) { x in
            onScrub?(x.map { plot.fraction(x: $0) })
        })
    }

    private var laneLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(NightLane.allCases, id: \.self) { lane in
                Text(lane.name)
                    .noctisFont(11, focusActive && focusLane == lane ? .bold : .medium, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
                    .foregroundStyle(.noctisNightInk2)
                    .frame(height: laneHeight)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    // A 44pt-tall target on a 28pt lane: padded out, made
                    // tappable, then the padding given back, so nothing
                    // moves (it overlaps its neighbors' by the difference).
                    .padding(.vertical, targetOutset)
                    .contentShape(Rectangle())
                    .onTapGesture { onLaneTap?(lane) }
                    .allowsHitTesting(onLaneTap != nil)
                    .padding(.vertical, -targetOutset)
            }
            if chart.heart != nil {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.noctisNightInk2)
                    .frame(height: Self.heartHeight)
                    .padding(.top, Self.heartGap)
                    .opacity(details)
                    .animation(fade, value: details)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, NoctisSpacing.xs)
    }

    /// The pill floats just above the chart, kept inside it.
    private var pill: some View {
        NoctisFractionLayout(wraps: true) {
            HomePill(text: pillText ?? "", onNightPanel: true)
                .noctisFraction(pillPosition)
        }
        .alignmentGuide(.top) { $0[.bottom] + 6 }
        .opacity(focusActive && pillText != nil ? 1 : 0)
        .allowsHitTesting(false)
    }
}

// MARK: - Layers

/// The static ribbon layer: guides, the stepped area, the steps, the
/// runs and the notches, in one `.drawingGroup` layer.
struct NightRibbonLayer: View {
    let chart: NightChartContent
    let plot: NightPlot

    var body: some View {
        Canvas { context, size in
            NightRibbonPainter.draw(in: context, size: size, chart: chart, plot: plot)
        }
        .drawingGroup()
    }
}

/// Draws the ribbon from `NightPlot`'s rectangles: no path building beyond
/// the shapes themselves.
enum NightRibbonPainter {
    static func draw(in context: GraphicsContext, size: CGSize, chart: NightChartContent, plot: NightPlot) {
        let ink = NoctisAppColor.nightInk
        // Faint lane guides, full width, under everything.
        for lane in NightLane.allCases {
            context.fill(Path(CGRect(x: 0, y: plot.y(lane) - 0.5, width: size.width, height: 1)), with: .color(ink.opacity(0.08)))
        }
        let radius = plot.thickness / 2
        guard chart.hasStages else {
            let rect = CGRect(x: plot.inset, y: plot.y(.core) - radius, width: max(size.width - 2 * plot.inset, 0), height: plot.thickness)
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(NoctisAppColor.sage))
            return
        }
        // The stepped area: each run's color at 10%, flat, from the
        // ribbon down to the Deep line.
        for run in chart.spans where !run.isNotch {
            let rect = plot.areaRect(run)
            guard rect.height > 0 else { continue }
            context.fill(Path(rect), with: .color(run.ribbonColor.opacity(0.10)))
        }
        // The steps, in the color entered, under the runs they join.
        for step in chart.connectors {
            let rect = plot.stepRect(step)
            let color = step.entered == .asleep ? NoctisAppColor.sage : step.entered.lane.tint
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
        }
        // The runs: capsules that overlap where they meet.
        for run in chart.spans where !run.isNotch {
            context.fill(Path(roundedRect: plot.runRect(run), cornerRadius: radius), with: .color(run.ribbonColor))
        }
        // A 6pt notch for anything under 3 minutes.
        for run in chart.spans where run.isNotch {
            context.fill(Path(roundedRect: plot.notchRect(run), cornerRadius: NightPlot.notchSize / 2), with: .color(run.ribbonColor))
        }
    }
}

/// The ivory head dot that travels with the reveal and fades at the end.
struct NightRevealHead: View, Animatable {
    let chart: NightChartContent
    let plot: NightPlot
    var drawn: Double

    var animatableData: Double {
        get { drawn }
        set { drawn = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            // Only while the ribbon is being drawn, fading over the last 6%.
            let visibility = min(max((0.94 - drawn) / 0.06 + 1, 0), 1)
            guard drawn > 0.002, drawn < 1, visibility > 0, let lane = chart.ribbonLane(at: drawn) else { return }
            let size = NightPlot.headSize
            let rect = CGRect(x: plot.x(drawn) - size / 2, y: plot.y(lane) - size / 2, width: size, height: size)
            context.fill(Path(ellipseIn: rect), with: .color(NoctisAppColor.nightInk.opacity(visibility)))
        }
    }
}

/// The heart-rate strip: a smoothed line through the night's heart rate
/// with its lowest point marked and labeled.
struct NightHeartLayer: View {
    let heart: NightHeartContent
    let plot: NightPlot

    var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .drawingGroup()
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let height = size.height
        let range = max(heart.high - heart.low, 1)
        func point(_ sample: NightHeartSeries.Point) -> CGPoint {
            CGPoint(x: plot.x(sample.position), y: height - CGFloat((sample.bpm - heart.low) / range) * height)
        }
        let points = heart.points.map(point)
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        // Catmull-Rom through the points: smooth, and it passes through
        // every real value.
        for index in 1..<points.count {
            let p0 = points[max(index - 2, 0)]
            let p1 = points[index - 1]
            let p2 = points[index]
            let p3 = points[min(index + 1, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        let ink = NoctisAppColor.nightInk
        context.stroke(path, with: .color(ink.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        let lowest = point(heart.lowest)
        context.fill(Path(ellipseIn: CGRect(x: lowest.x - 2.5, y: lowest.y - 2.5, width: 5, height: 5)), with: .color(ink))
        let label = context.resolve(
            Text(heart.lowestLabel).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(ink.opacity(0.8))
        )
        let labelSize = label.measure(in: CGSize(width: size.width, height: height))
        // Beside the point, on whichever side has room.
        let rightSide = lowest.x + 6 + labelSize.width <= size.width
        let x = max(rightSide ? lowest.x + 6 : lowest.x - 6 - labelSize.width, 0)
        let y = min(max(lowest.y - labelSize.height / 2, 0), height - labelSize.height)
        let rect = CGRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
        // A halo in the panel's color, so the line steps aside for the
        // glyphs without a box cut out of it.
        let halo = context.resolve(
            Text(heart.lowestLabel).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(NoctisAppColor.nightPanel)
        )
        for offset in [(-1.5, 0), (1.5, 0), (0, -1.5), (0, 1.5), (-1.1, -1.1), (1.1, -1.1), (-1.1, 1.1), (1.1, 1.1)] as [(CGFloat, CGFloat)] {
            context.draw(halo, in: rect.offsetBy(dx: offset.0, dy: offset.1))
        }
        context.draw(label, in: rect)
    }
}

/// While a lane is focused (a scrub, or a tapped label), the other lanes
/// step back to 40%: the panel's own color laid over them at 60%, which
/// reads the same as their content at 40% without redrawing any of it.
struct NightDimOverlay: View {
    let laneHeight: CGFloat
    let focus: NightLane?
    let active: Bool

    static let dimmedOpacity = 0.4

    var body: some View {
        VStack(spacing: 0) {
            ForEach(NightLane.allCases, id: \.self) { lane in
                NoctisAppColor.nightPanel
                    .opacity(active && focus != nil && focus != lane ? 1 - Self.dimmedOpacity : 0)
                    .frame(height: laneHeight)
            }
        }
        .animation(.easeOut(duration: 0.2), value: active)
        .animation(.easeOut(duration: 0.2), value: focus)
    }
}

/// The scrub's 1pt ivory line and the dot on its lane.
struct NightScrubLine: View {
    let plot: NightPlot
    let reading: NightReading?
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            guard let reading else { return }
            let x = plot.x(reading.position)
            context.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)), with: .color(NoctisAppColor.nightInk))
            let y = plot.y(reading.lane)
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(NoctisAppColor.nightInk))
        }
        .animation(.easeOut(duration: 0.2), value: reading != nil)
    }
}
