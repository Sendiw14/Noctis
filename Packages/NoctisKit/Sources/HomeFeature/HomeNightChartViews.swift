import DesignSystem
import NoctisCore
import SleepKit
import SwiftUI

// The sleep landscape: one continuous ribbon through last night's stage
// timeline, in four lanes. The night panel and the share card use it.

/// The chart's plot space: how positions along the night (0...1) and lanes
/// become points. A run is 8pt thick (60% of a lane if that's smaller) and a
/// connector between lanes is 3pt wide at 70%; the plot is inset by half a
/// run's thickness at both ends so the first and last caps stay inside.
nonisolated struct NightPlot: Equatable {
    let width: CGFloat
    let laneHeight: CGFloat

    static let maximumThickness: CGFloat = 8
    static let thicknessShare: CGFloat = 0.6
    /// A connector between two lanes: thin, and a little quieter than a run.
    static let connectorWidth: CGFloat = 3
    static let connectorOpacity = 0.7
    /// Where a connector crosses another run, that run keeps this much of
    /// the panel's color around it.
    static let crossingGap: CGFloat = 2
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

    /// The vertical capsule for a step: 3pt wide, from the lane it leaves to
    /// the lane it enters, overlapping both runs.
    func stepRect(_ step: NightConnector) -> CGRect {
        let top = min(y(step.from), y(step.to)) - thickness / 2
        let bottom = max(y(step.from), y(step.to)) + thickness / 2
        return CGRect(x: x(step.position) - Self.connectorWidth / 2, y: top, width: Self.connectorWidth, height: bottom - top)
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

/// The ribbon's color for a stage.
extension StripStage {
    public var ribbonColor: Color {
        self == .asleep ? NoctisAppColor.sage : lane.tint
    }
}

extension StripSegment {
    var ribbonColor: Color { stage.ribbonColor }
}

// MARK: - Resolved paths

/// A path and the stage whose color fills it.
struct StagePath {
    let path: Path
    let stage: StripStage
}

/// Everything the night chart's Canvas layers draw, built once per
/// (render model, plot) and never inside a `body` or a `Canvas` closure.
struct NightPaths: Equatable {
    let key: NightPathsKey
    /// The four lane guides, full width.
    let guides: Path
    /// The stepped area under each run.
    let area: [StagePath]
    /// The steps between lanes, then the panel-colored gaps around any run a
    /// step crosses, then the runs, then the notches: the order they're
    /// painted in.
    let steps: [StagePath]
    let knockouts: [Path]
    let runs: [StagePath]
    let notches: [StagePath]
    /// Without stages: one sage bar in the Core lane.
    let stageless: Path?
    /// The heart strip, in the strip's own coordinates.
    let heartLine: Path?
    let heartLowest: CGPoint?
    /// The 5pt dot on the lowest point.
    let heartLowestDot: Path?

    static func == (lhs: NightPaths, rhs: NightPaths) -> Bool { lhs.key == rhs.key }
}

/// What a set of paths was built for.
struct NightPathsKey: Equatable {
    let plot: NightPlot
    let heartHeight: CGFloat
    let render: NightRender
}

enum NightPathBuilder {
    static func build(_ key: NightPathsKey) -> NightPaths {
        let plot = key.plot
        let render = key.render
        let radius = plot.thickness / 2
        var guides = Path()
        for lane in NightLane.allCases {
            guides.addRect(CGRect(x: 0, y: plot.y(lane) - 0.5, width: plot.width, height: 1))
        }
        var stageless: Path?
        var area: [StagePath] = []
        var steps: [StagePath] = []
        var knockouts: [Path] = []
        var runs: [StagePath] = []
        var notches: [StagePath] = []
        if render.hasStages {
            // The stepped area: from each ribbon run down to the Deep line.
            for run in render.runs where !run.isNotch {
                let rect = plot.areaRect(run)
                guard rect.height > 0 else { continue }
                area.append(StagePath(path: Path(rect), stage: run.stage))
            }
            // The steps, in the color entered, under the runs they join.
            for step in render.steps {
                let rect = plot.stepRect(step)
                steps.append(StagePath(path: Path(roundedRect: rect, cornerRadius: NightPlot.connectorWidth / 2), stage: step.entered))
                // A run in a lane the step passes through (not the two it joins)
                // keeps a 2pt gap of the panel's color, so the step reads as
                // passing behind it.
                let low = min(step.from.rawValue, step.to.rawValue), high = max(step.from.rawValue, step.to.rawValue)
                for run in render.runs where run.stage.lane.rawValue > low && run.stage.lane.rawValue < high {
                    let runRect = run.isNotch ? plot.notchRect(run) : plot.runRect(run)
                    guard runRect.intersects(rect) else { continue }
                    let gap = NightPlot.crossingGap
                    knockouts.append(Path(roundedRect: runRect.insetBy(dx: -gap, dy: -gap), cornerRadius: runRect.height / 2 + gap))
                }
            }
            for run in render.runs {
                if run.isNotch {
                    notches.append(StagePath(path: Path(roundedRect: plot.notchRect(run), cornerRadius: NightPlot.notchSize / 2), stage: run.stage))
                } else {
                    runs.append(StagePath(path: Path(roundedRect: plot.runRect(run), cornerRadius: radius), stage: run.stage))
                }
            }
        } else {
            let rect = CGRect(x: plot.inset, y: plot.y(.core) - radius, width: max(plot.width - 2 * plot.inset, 0), height: plot.thickness)
            stageless = Path(roundedRect: rect, cornerRadius: radius)
        }
        var heartLine: Path?
        var heartLowest: CGPoint?
        var heartLowestDot: Path?
        if let heart = render.heart {
            let points = heart.points.map { CGPoint(x: plot.x($0.x), y: key.heartHeight - CGFloat($0.y) * key.heartHeight) }
            if let first = points.first {
                var line = Path()
                line.move(to: first)
                // Catmull-Rom through the points: smooth, and it passes
                // through every real value.
                for index in 1..<max(points.count, 1) {
                    let p0 = points[max(index - 2, 0)]
                    let p1 = points[index - 1]
                    let p2 = points[index]
                    let p3 = points[min(index + 1, points.count - 1)]
                    let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                    let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                    line.addCurve(to: p2, control1: c1, control2: c2)
                }
                heartLine = line
                let lowest = CGPoint(x: plot.x(heart.lowest.x), y: key.heartHeight - CGFloat(heart.lowest.y) * key.heartHeight)
                heartLowest = lowest
                heartLowestDot = Path(ellipseIn: CGRect(x: lowest.x - 2.5, y: lowest.y - 2.5, width: 5, height: 5))
            }
        }
        return NightPaths(
            key: key, guides: guides, area: area, steps: steps, knockouts: knockouts, runs: runs, notches: notches,
            stageless: stageless, heartLine: heartLine, heartLowest: heartLowest, heartLowestDot: heartLowestDot
        )
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
    /// Sleep's stage totals are buttons too.
    var onTotalTap: ((NightLane) -> Void)?
    /// A fixed lane height (the share card); otherwise it scales with the
    /// lane labels (R4).
    var laneHeightOverride: CGFloat?
    /// The pill gets its own row above the lanes, so it never covers the
    /// caption above the chart (Sleep); otherwise it floats over the top
    /// of the chart.
    var reservesPillRow = false

    @NoctisScaledLength(relativeTo: .caption2) private var scaledLaneHeight: CGFloat = 34
    @NoctisScaledLength(relativeTo: .footnote) private var pillRowHeight: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    /// The ribbon's and heart line's paths, resolved when the width, the
    /// lane height or the night changes.
    @State private var paths: NightPaths?

    static let heartHeight: CGFloat = 28
    static let heartGap: CGFloat = 8
    /// Room under the strip for "min 46 bpm": the label sits under the line's lowest point, never on the line (QA part 5).
    static let heartLabelRoom: CGFloat = 14
    /// Every lane label's tap area is at least this tall (R10 targets).
    static let minimumTarget: CGFloat = 44

    private var laneHeight: CGFloat { laneHeightOverride ?? scaledLaneHeight }
    private var plot: NightPlot { NightPlot(width: width, laneHeight: laneHeight) }
    private var heartBlock: CGFloat { chart.heart == nil ? 0 : Self.heartGap + Self.heartHeight + Self.heartLabelRoom }
    private var pathsKey: NightPathsKey { NightPathsKey(plot: plot, heartHeight: Self.heartHeight, render: chart.render) }
    private var targetOutset: CGFloat { max(Self.minimumTarget - laneHeight, 0) / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            HStack(alignment: .top, spacing: 0) {
                laneLabels
                    .padding(.top, reservesPillRow ? pillRowHeight + NoctisSpacing.xxs : 0)
                VStack(spacing: NoctisSpacing.xxs) {
                    if reservesPillRow { pillRow }
                    layers
                    HStack {
                        ForEach(Array(chart.timeLabels.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer(minLength: NoctisSpacing.xxs) }
                            Text(label)
                                .noctisFont(12, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
                                .foregroundStyle(.noctisNightInk2)
                        }
                    }
                }
            }
            if !chart.laneTotals.isEmpty {
                NightStageTotalsView(totals: chart.laneTotals, onTap: onTotalTap, focus: focusActive ? focusLane : nil)
                    .opacity(details)
                    .animation(fade, value: details)
            }
        }
        .accessibilityHidden(true)
    }

    /// The heart strip and totals fade in as the ribbon finishes.
    private var fade: Animation? {
        reduceMotion ? NoctisMotion.reduced : NoctisMotion.fade.delay(HomeRevealPhase.contentDelay + HomeReveal.nightDuration - 0.2)
    }

    private var layers: some View {
        ZStack(alignment: .topLeading) {
            if let paths {
                NightRibbonLayer(paths: paths)
                    .equatable()
                    .frame(height: plot.lanesHeight)
                    // Revealed left to right; the mask is a scaled rectangle,
                    // so the animation costs no redraw of the ribbon.
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: max(drawn, 0.0001), y: 1, anchor: .leading)
                    }
            }
            if chart.hasStages {
                NightRevealHead(render: chart.render, plot: plot, drawn: drawn)
                    .frame(height: plot.lanesHeight)
                    .allowsHitTesting(false)
            }
            if let heart = chart.heart, let paths {
                NightHeartLayer(paths: paths, label: heart.lowestLabel)
                    .equatable()
                    .frame(height: Self.heartHeight + Self.heartLabelRoom)
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
        .overlay(alignment: .top) { if !reservesPillRow { pill } }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: pathsKey, initial: true) { _, key in
            guard key.plot.width > 0 else { return }
            paths = NightPathBuilder.build(key)
        }
        .gesture(HorizontalScrubGesture(isEnabled: onScrub != nil) { x in
            onScrub?(x.map { plot.fraction(x: $0) })
        })
    }

    private var laneLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(NightLane.allCases, id: \.self) { lane in
                Text(lane.name)
                    .noctisFont(12, focusActive && focusLane == lane ? .bold : .medium, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
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
                    .font(.system(size: 12, weight: .semibold))
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

    /// The pill's own row above the lanes: always there, so nothing moves
    /// when it appears; text too wide for it wraps and grows upward.
    private var pillRow: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            NoctisFractionLayout(wraps: true) {
                HomePill(text: pillText ?? "", onNightPanel: true)
                    .noctisFraction(pillPosition)
            }
            .opacity(focusActive && pillText != nil ? 1 : 0)
        }
        .frame(height: pillRowHeight, alignment: .bottom)
        .allowsHitTesting(false)
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

/// The static ribbon layer: guides, the stepped area, the steps, the runs
/// and the notches, in one `.drawingGroup` layer. It draws paths that were
/// built ahead of time, and is `Equatable`, so nothing above it (a scrub,
/// a lane focus, a pill) makes it draw again.
struct NightRibbonLayer: View, Equatable {
    let paths: NightPaths
    @Environment(\.colorScheme) private var colorScheme

    static func == (lhs: NightRibbonLayer, rhs: NightRibbonLayer) -> Bool { lhs.paths == rhs.paths }

    var body: some View {
        // The adaptive colors resolve when this draws: a change of
        // appearance draws it again.
        let _ = colorScheme
        Canvas { context, _ in
            context.fill(paths.guides, with: .color(NoctisAppColor.nightInk.opacity(0.08)))
            if let bar = paths.stageless {
                context.fill(bar, with: .color(NoctisAppColor.sage))
                return
            }
            for item in paths.area { context.fill(item.path, with: .color(item.stage.ribbonColor.opacity(0.10))) }
            for item in paths.steps { context.fill(item.path, with: .color(item.stage.ribbonColor.opacity(NightPlot.connectorOpacity))) }
            for gap in paths.knockouts { context.fill(gap, with: .color(NoctisAppColor.nightPanel)) }
            for item in paths.runs { context.fill(item.path, with: .color(item.stage.ribbonColor)) }
            for item in paths.notches { context.fill(item.path, with: .color(item.stage.ribbonColor)) }
        }
        .drawingGroup()
    }
}

/// The ivory head dot that travels with the reveal and fades at the end.
/// A plain view, not a canvas: its position is a lookup and an offset.
struct NightRevealHead: View, Animatable {
    let render: NightRender
    let plot: NightPlot
    var drawn: Double

    var animatableData: Double {
        get { drawn }
        set { drawn = newValue }
    }

    var body: some View {
        // Only while the ribbon is being drawn, fading over the last 6%.
        let visibility = min(max((0.94 - drawn) / 0.06 + 1, 0), 1)
        let lane = render.lane(at: drawn)
        ZStack(alignment: .topLeading) {
            if drawn > 0.002, drawn < 1, visibility > 0, let lane {
                Circle()
                    .fill(NoctisAppColor.nightInk.opacity(visibility))
                    .frame(width: NightPlot.headSize, height: NightPlot.headSize)
                    .offset(x: plot.x(drawn) - NightPlot.headSize / 2, y: plot.y(lane) - NightPlot.headSize / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The heart-rate strip: a smoothed line through the night's heart rate
/// with its lowest point marked and labeled. The line is a resolved path;
/// only the label is laid out here.
struct NightHeartLayer: View, Equatable {
    let paths: NightPaths
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    static func == (lhs: NightHeartLayer, rhs: NightHeartLayer) -> Bool {
        lhs.paths == rhs.paths && lhs.label == rhs.label
    }

    var body: some View {
        let _ = colorScheme
        Canvas { context, size in
            guard let line = paths.heartLine, let lowest = paths.heartLowest, let dot = paths.heartLowestDot else { return }
            let height = size.height
            let ink = NoctisAppColor.nightInk
            context.stroke(line, with: .color(ink.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            context.fill(dot, with: .color(ink))
            let text = context.resolve(
                Text(label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(ink.opacity(0.8))
            )
            let labelSize = text.measure(in: CGSize(width: size.width, height: height))
            // Under the point: the lowest point is the line's own minimum, so the strip below it is clear.
            let x = min(max(lowest.x - labelSize.width / 2, 0), max(size.width - labelSize.width, 0))
            let y = min(lowest.y + 4, height - labelSize.height)
            let rect = CGRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
            // A halo in the panel's color, so the line steps aside for the
            // glyphs without a box cut out of it.
            let halo = context.resolve(
                Text(label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(NoctisAppColor.nightPanel)
            )
            for offset in [(-1.5, 0), (1.5, 0), (0, -1.5), (0, 1.5), (-1.1, -1.1), (1.1, -1.1), (-1.1, 1.1), (1.1, 1.1)] as [(CGFloat, CGFloat)] {
                context.draw(halo, in: rect.offsetBy(dx: offset.0, dy: offset.1))
            }
            context.draw(text, in: rect)
        }
        .drawingGroup()
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
        .animation(NoctisMotion.select, value: active)
        .animation(NoctisMotion.select, value: focus)
    }
}

/// The scrub's 1pt ivory line and the dot on its lane: two plain views, so
/// a finger moving redraws these and never the ribbon.
struct NightScrubLine: View {
    let plot: NightPlot
    let reading: NightReading?
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let reading {
                let x = plot.x(reading.position)
                Rectangle()
                    .fill(NoctisAppColor.nightInk)
                    .frame(width: 1, height: height)
                    .offset(x: x - 0.5)
                Circle()
                    .fill(NoctisAppColor.nightInk)
                    .frame(width: 8, height: 8)
                    .offset(x: x - 4, y: plot.y(reading.lane) - 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(NoctisMotion.fade, value: reading != nil)
    }
}
