import Accessibility
import DesignSystem
import NoctisCore
import SleepKit
import SwiftUI

// MARK: - Night panel

/// Last night, always the darkest element on screen: a solid cocoa block
/// in Light, an inset near-black panel with a hairline in Dark.
///
/// Dragging sideways across the chart scrubs it: a 1pt ivory line, a dot
/// on the active lane and a pill ("3:41 AM · REM · 47 min · 52 bpm"), the
/// other lanes at 40%, a light tick at each change of stage; it all fades
/// on release. Tapping a lane label shows that stage's total until tapped
/// again. Any other tap opens the Sleep tab; a long press offers Open
/// Sleep and Share this night over a preview.
struct NightPanelView: View {
    let content: LastNightCardContent
    let open: () -> Void
    let share: () -> Void

    @Environment(\.homeReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The latest scrub reading, kept after release so the pill can fade.
    @State private var scrub: NightReading?
    @State private var scrubbing = false
    @State private var laneFocus: NightLane?
    /// VoiceOver's position when stepping through the night.
    @State private var spokenSegment: Int?

    private var chart: NightChartContent { content.chart }

    var body: some View {
        panel
            .contentShape(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
            .onTapGesture(perform: open)
            .contextMenu {
                Button("Open Sleep", systemImage: "moon.zzz", action: open)
                Button("Share this night", systemImage: "square.and.arrow.up", action: share)
            } preview: {
                NightPanelPreview(content: content)
            }
            // Two VoiceOver stops: the night (a button that steps through
            // its runs), then the chart for Audio Graph. On one element,
            // Audio Graph's rotor would take over the swipes.
            .accessibilityElement(children: .contain)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                NoctisCaption("LAST NIGHT", style: .noctisNightInk2)
                NoctisMetric(content.duration, size: 48, tone: .nightPanel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : NoctisMotion.settle, value: content.duration)
                Text(content.timeRange)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisNightInk2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(content.accessibilityLabel)
            .accessibilityValue(spokenSegment.flatMap { chart.reading(segment: $0)?.spoken } ?? "")
            .accessibilityHint(chart.hasStages ? "Opens the Sleep tab. Swipe up or down to step through the night." : "Opens the Sleep tab.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .accessibilityAction(named: "Open Sleep", open)
            .accessibilityAction(named: "Share this night", share)
            .modifier(NightStepping(chart: chart, segment: $spokenSegment))
            chartView
                .modifier(NightChartAudioGraph(chart: chart, focus: laneFocus.flatMap(total)))
            if let caption = chart.caption {
                Text(caption)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisNightInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    // Already in the night's label.
                    .accessibilityHidden(true)
            }
        }
        .padding(NoctisSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                .fill(NoctisAppColor.nightPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous)
                .strokeBorder(NoctisAppColor.nightBorder, lineWidth: 1)
        )
        .noctisContrastBorder()
    }

    private var chartView: some View {
        let drawIn: Animation? = reduceMotion ? nil : .easeOut(duration: HomeReveal.nightDuration).delay(HomeRevealPhase.contentDelay)
        let focusLane: NightLane? = scrubbing ? scrub?.lane : (laneFocus ?? scrub?.lane)
        let laneTotal: String? = laneFocus.flatMap { total($0) }
        let pillText: String? = scrubbing ? scrub?.text : (laneTotal ?? scrub?.text)
        let pillPosition: Double = scrubbing || laneFocus == nil ? (scrub?.position ?? 0) : 0
        let onScrub: ((Double?) -> Void)? = chart.hasStages ? { scrubbed($0) } : nil
        let onLaneTap: ((NightLane) -> Void)? = chart.hasStages ? { toggle($0) } : nil
        return NightChartView(
            chart: chart,
            drawn: reveal.holdsStart ? 0 : 1,
            focusLane: focusLane,
            focusActive: scrubbing || laneFocus != nil,
            line: scrub,
            showsLine: scrubbing,
            pillText: pillText,
            pillPosition: pillPosition,
            onScrub: onScrub,
            onLaneTap: onLaneTap
        )
        .animation(drawIn, value: reveal)
        .animation(.easeOut(duration: 0.2), value: scrubbing)
        .animation(.easeOut(duration: 0.2), value: laneFocus)
    }

    private func total(_ lane: NightLane) -> String? {
        chart.laneTotals.first { $0.lane == lane }?.text
    }

    /// The finger at `position` (0...1), or lifted (nil).
    private func scrubbed(_ position: Double?) {
        guard let position else {
            scrubbing = false
            return
        }
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

/// VoiceOver: step through the night's runs, reading the same text as the
/// scrub pill.
private struct NightStepping: ViewModifier {
    let chart: NightChartContent
    @Binding var segment: Int?

    func body(content: Content) -> some View {
        if chart.hasStages {
            content
                .accessibilityAdjustableAction { direction in
                    let last = chart.spans.count - 1
                    switch direction {
                    case .increment: segment = min((segment ?? -1) + 1, last)
                    case .decrement: segment = max((segment ?? last + 1) - 1, 0)
                    @unknown default: break
                    }
                }
        } else {
            content
        }
    }
}

/// The chart as its own element, for Audio Graph; its value is the lane
/// total a tapped label is showing.
private struct NightChartAudioGraph: ViewModifier {
    let chart: NightChartContent
    let focus: String?

    func body(content: Content) -> some View {
        if chart.hasStages {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep stages chart")
                .accessibilityValue(focus ?? "")
                .accessibilityHint("Use Audio Graph from the rotor to hear it.")
                .accessibilityChartDescriptor(NightChartDescriptor(chart: chart))
        } else {
            content.accessibilityHidden(true)
        }
    }
}

/// Audio Graph: time across, stage up (Deep lowest, Awake highest), one
/// point per run, read with the pill's text.
struct NightChartDescriptor: AXChartDescriptorRepresentable {
    let chart: NightChartContent

    func makeChartDescriptor() -> AXChartDescriptor {
        let minutes = max(chart.minutes, 1)
        let chart = chart
        let lanes = NightLane.allCases
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: 0...minutes,
            gridlinePositions: []
        ) { value in chart.clockText(at: value / minutes) }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Stage",
            range: 0...Double(lanes.count - 1),
            gridlinePositions: []
        ) { value in
            let index = lanes.count - 1 - Int(value.rounded())
            return lanes.indices.contains(index) ? lanes[index].name : ""
        }
        let points = chart.spans.indices.compactMap { index -> AXDataPoint? in
            guard let reading = chart.reading(segment: index) else { return nil }
            let height = Double(lanes.count - 1 - reading.lane.rawValue)
            return AXDataPoint(x: chart.spans[index].start * minutes, y: height, additionalValues: [], label: reading.spoken)
        }
        return AXChartDescriptor(
            title: "Last night's sleep stages",
            summary: "Stages from bedtime to wake-up." + (chart.heart.map { " " + $0.accessibilityLabel } ?? ""),
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "Stages", isContinuous: false, dataPoints: points)]
        )
    }
}

/// Four lanes (Awake, REM, Core, Deep) with one rounded bar per run of a
/// stage, a step connector where the night moves straight into another
/// lane, the heart-rate strip, start, midpoint and end times, and each
/// stage's total. Without stages: one sage bar in the Core lane. Draws
/// left to right as `drawn` goes 0 → 1; the scrub and lane focus dim
/// every other lane to 40%. The share card uses it too.
struct NightChartView: View {
    let chart: NightChartContent
    var drawn: Double = 1
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
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var width: CGFloat = 0

    static let heartHeight: CGFloat = 28
    static let heartGap: CGFloat = 8
    /// The label column's tap area reaches this far into the panel's
    /// padding, without moving anything.
    private static let labelReach: CGFloat = 12
    /// Every lane label's tap area is at least this tall (R10 targets).
    static let minimumTarget: CGFloat = 44

    private var laneHeight: CGFloat { laneHeightOverride ?? scaledLaneHeight }
    private var targetOutset: CGFloat { max(Self.minimumTarget - laneHeight, 0) / 2 }
    private var lanesHeight: CGFloat { laneHeight * CGFloat(NightLane.allCases.count) }
    private var heartBlock: CGFloat { chart.heart == nil ? 0 : Self.heartGap + Self.heartHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            HStack(alignment: .top, spacing: 0) {
                laneLabels
                VStack(spacing: NoctisSpacing.xxs) {
                    NightChartCanvas(
                        chart: chart,
                        drawn: drawn,
                        emphasis: focusActive ? 1 : 0,
                        lane: focusLane,
                        connectorOpacity: contrast == .increased ? 1 : 0.5,
                        lanesHeight: lanesHeight
                    )
                    .frame(height: lanesHeight + heartBlock)
                    .overlay { scrubLine }
                    .overlay(alignment: .top) { pill }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    .gesture(HorizontalScrubGesture(isEnabled: onScrub != nil) { x in
                        onScrub?(x.map { width > 0 ? Double($0 / width) : 0 })
                    })
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
            }
        }
        .accessibilityHidden(true)
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
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        // The gap to the chart and a strip of the panel's padding belong to
        // the labels' tap area.
        .padding(.trailing, NoctisSpacing.xs)
        .padding(.leading, Self.labelReach)
        .padding(.leading, -Self.labelReach)
    }

    /// The scrub's 1pt ivory line and the dot on its lane.
    private var scrubLine: some View {
        Canvas { context, size in
            guard let line else { return }
            let x = line.position * size.width
            context.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)), with: .color(NoctisAppColor.nightInk))
            let y = laneHeight * (CGFloat(line.lane.rawValue) + 0.5)
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(NoctisAppColor.nightInk))
        }
        .opacity(showsLine ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// The pill floats just above the chart, kept inside it.
    private var pill: some View {
        NoctisFractionLayout {
            HomePill(text: pillText ?? "", onNightPanel: true)
                .noctisFraction(pillPosition)
        }
        .alignmentGuide(.top) { $0[.bottom] + 6 }
        .opacity(focusActive && pillText != nil ? 1 : 0)
        .allowsHitTesting(false)
    }
}

/// The chart's lanes and heart-rate strip, animatable over how much has
/// drawn and how far the other lanes have dimmed.
struct NightChartCanvas: View, Animatable {
    let chart: NightChartContent
    var drawn: Double
    var emphasis: Double
    let lane: NightLane?
    let connectorOpacity: Double
    /// The lanes' part of the canvas; the heart strip sits below it.
    let lanesHeight: CGFloat

    static let dimmedOpacity = 0.4
    /// Bars fill this share of their lane's height.
    static let barShare: CGFloat = 0.7
    static let minimumBarWidth: CGFloat = 4
    static let tickWidth: CGFloat = 3
    static let connectorWidth: CGFloat = 2

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(drawn, emphasis) }
        set {
            drawn = newValue.first
            emphasis = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        // Redrawn every frame of the draw-in and the scrub.
        .drawingGroup()
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let laneHeight = lanesHeight / CGFloat(NightLane.allCases.count)
        let barHeight = laneHeight * Self.barShare
        let ink = NoctisAppColor.nightInk
        let dimmed = 1 - (1 - Self.dimmedOpacity) * min(max(emphasis, 0), 1)
        func centerY(_ nightLane: NightLane) -> CGFloat { laneHeight * (CGFloat(nightLane.rawValue) + 0.5) }

        // Faint lane guides, under everything and never clipped.
        for guide in NightLane.allCases {
            context.fill(Path(CGRect(x: 0, y: centerY(guide) - 0.5, width: size.width, height: 1)), with: .color(ink.opacity(0.08)))
        }

        var context = context
        context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * min(max(drawn, 0), 1), height: size.height)))

        if chart.hasStages {
            // Steps go under the bars: each leaves the bar being left,
            // turns, runs to the next lane and turns into the bar entered,
            // so it always joins two bars. Its horizontal stubs run only
            // as far as the bars are wide, so a thin bar or a tick never
            // has one poking out of its far side.
            for connector in chart.connectors {
                let x = connector.position * size.width
                let from = centerY(connector.from)
                let to = centerY(connector.to)
                // The stub leaving a bar can only lie over the run itself
                // (a thin bar is drawn wider than its run); the one entering
                // a bar lies over the bar as drawn.
                let leaving = run(endingAt: connector.position, in: connector.from).map { ($0.end - $0.start) * size.width }
                let entering = run(startingAt: connector.position, in: connector.to).map { drawnWidth(of: $0, in: size.width) }
                let stubIn = min(barHeight / 2, leaving ?? Self.minimumBarWidth)
                let stubOut = min(barHeight / 2, entering ?? Self.minimumBarWidth)
                let turn = min(6, stubIn, stubOut, abs(to - from) / 2)
                let direction: CGFloat = to > from ? 1 : -1
                var step = Path()
                step.move(to: CGPoint(x: x - stubIn, y: from))
                step.addLine(to: CGPoint(x: x - turn, y: from))
                step.addQuadCurve(to: CGPoint(x: x, y: from + direction * turn), control: CGPoint(x: x, y: from))
                step.addLine(to: CGPoint(x: x, y: to - direction * turn))
                step.addQuadCurve(to: CGPoint(x: x + turn, y: to), control: CGPoint(x: x, y: to))
                step.addLine(to: CGPoint(x: x + stubOut, y: to))
                var connectorContext = context
                connectorContext.opacity = (lane == nil || lane == connector.to ? 1 : dimmed)
                connectorContext.stroke(
                    step,
                    with: .color(connector.to.tint.opacity(connectorOpacity)),
                    style: StrokeStyle(lineWidth: Self.connectorWidth, lineCap: .round, lineJoin: .round)
                )
            }
            for span in chart.spans {
                var spanContext = context
                if let lane, lane != span.stage.lane { spanContext.opacity = dimmed }
                let color = span.stage == .asleep ? NoctisAppColor.sage : span.stage.lane.tint
                let x = span.start * size.width
                if span.isTick {
                    let tick = CGRect(x: x, y: centerY(.awake) - barHeight * 0.4, width: Self.tickWidth, height: barHeight * 0.8)
                    spanContext.fill(Path(roundedRect: tick, cornerRadius: Self.tickWidth / 2), with: .color(color))
                    continue
                }
                let width = max((span.end - span.start) * size.width, Self.minimumBarWidth)
                let rect = CGRect(x: x, y: centerY(span.stage.lane) - barHeight / 2, width: width, height: barHeight)
                spanContext.fill(Path(roundedRect: rect, cornerRadius: min(barHeight, width) / 2), with: .color(color))
            }
        } else {
            let rect = CGRect(x: 0, y: centerY(.core) - barHeight / 2, width: size.width, height: barHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: barHeight / 2), with: .color(NoctisAppColor.sage))
        }

        if let heart = chart.heart {
            drawHeart(heart, in: context, top: lanesHeight + NightChartView.heartGap, width: size.width)
        }
    }

    /// The run in `lane` that ends at `position`.
    private func run(endingAt position: Double, in lane: NightLane) -> StripSegment? {
        chart.spans.first { $0.stage.lane == lane && abs($0.end - position) < 1e-9 }
    }

    /// The run in `lane` that starts at `position`.
    private func run(startingAt position: Double, in lane: NightLane) -> StripSegment? {
        chart.spans.first { $0.stage.lane == lane && abs($0.start - position) < 1e-9 }
    }

    /// How wide `span`'s bar (or tick) is drawn.
    private func drawnWidth(of span: StripSegment, in width: CGFloat) -> CGFloat {
        span.isTick ? Self.tickWidth : max((span.end - span.start) * width, Self.minimumBarWidth)
    }

    /// A smoothed line through the night's heart rate, with its lowest
    /// point marked and labeled.
    private func drawHeart(_ heart: NightHeartContent, in context: GraphicsContext, top: CGFloat, width: CGFloat) {
        let height = NightChartView.heartHeight
        let range = max(heart.high - heart.low, 1)
        func point(_ sample: NightHeartSeries.Point) -> CGPoint {
            CGPoint(x: sample.position * width, y: top + height - CGFloat((sample.bpm - heart.low) / range) * height)
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
        let labelSize = label.measure(in: CGSize(width: width, height: height))
        // Beside the point, on whichever side has room.
        let rightSide = lowest.x + 6 + labelSize.width <= width
        let x = max(rightSide ? lowest.x + 6 : lowest.x - 6 - labelSize.width, 0)
        let y = min(max(lowest.y - labelSize.height / 2, top), top + height - labelSize.height)
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

/// Under the time axis: each stage's dot, name and time, in one row (a
/// 2×2 grid at accessibility sizes).
struct NightStageTotalsView: View {
    let totals: [NightLaneTotal]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Grid(alignment: .leading, horizontalSpacing: NoctisSpacing.md, verticalSpacing: NoctisSpacing.sm) {
                    GridRow { ForEach(totals.prefix(2), id: \.lane) { stat($0) } }
                    GridRow { ForEach(totals.dropFirst(2), id: \.lane) { stat($0) } }
                }
            } else {
                HStack(alignment: .top, spacing: NoctisSpacing.xs) {
                    ForEach(totals, id: \.lane) { stat($0).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
        }
        // The night's own label already reads every total.
        .accessibilityHidden(true)
    }

    private func stat(_ total: NightLaneTotal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(total.lane.tint).frame(width: 7, height: 7)
                Text(total.lane.name)
                    .noctisFont(11, .medium, relativeTo: .caption2)
                    .foregroundStyle(.noctisNightInk2)
            }
            NoctisMetric(total.duration, size: 17, relativeTo: .body, tone: .nightPanel)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// The night panel's long-press preview: the panel as it is at rest.
struct NightPanelPreview: View {
    let content: LastNightCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                NoctisCaption("LAST NIGHT", style: .noctisNightInk2)
                NoctisMetric(content.duration, size: 48, tone: .nightPanel)
                Text(content.timeRange)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisNightInk2)
            }
            NightChartView(chart: content.chart)
        }
        .padding(NoctisSpacing.lg)
        .frame(width: 340, alignment: .leading)
        .background(NoctisAppColor.nightPanel)
    }
}

// MARK: - Color blocks

/// A solid, flat color block: 28pt corners, 20pt padding, no border
/// (Increase Contrast adds one).
struct ColorBlock<Content: View>: View {
    let fill: Color
    let content: Content

    init(fill: Color, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .padding(NoctisSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
            .noctisContrastBorder()
    }
}

/// Day mode's Tonight: a lavender block with the plan, and at its right
/// edge a faint crescent resting on a horizon line, cut by the block's
/// corner (static; hidden at accessibility sizes).
struct TonightBlockView: View {
    let content: TonightCardContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
            NoctisCaption("TONIGHT", style: NoctisAppColor.blockInk)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { bedtimeLine }
                VStack(alignment: .leading, spacing: 0) { bedtimeLine }
            }
            Text(content.detail)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(NoctisAppColor.blockInk)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(NoctisSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The crescent sits on the block's fill, under the text, and the
        // block's corner cuts it.
        .background {
            ZStack(alignment: .bottomTrailing) {
                NoctisAppColor.blockLavender
                if !dynamicTypeSize.isAccessibilitySize {
                    TonightCrescent().frame(width: 132, height: 96)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
        }
        .noctisContrastBorder()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tonight. \(content.bedtimeText). \(content.detail)")
    }

    @ViewBuilder
    private var bedtimeLine: some View {
        Text(content.bedtimeLead)
            .noctisFont(22, .semibold, relativeTo: .title3)
            .foregroundStyle(NoctisAppColor.blockInk)
        NoctisMetric(content.bedtime, size: 22, relativeTo: .title3, tone: .block)
    }
}

/// A cocoa .12 crescent sitting just above a 1pt horizon line. Drawn past
/// the right edge so the block's corner cuts it.
struct TonightCrescent: View {
    var body: some View {
        Canvas { context, size in
            let ink = NoctisAppColor.blockCocoa.opacity(0.12)
            // Low in the bottom-right corner, so the corner's curve cuts
            // both the horizon and the moon.
            let horizonY = size.height - 14
            context.fill(Path(CGRect(x: 0, y: horizonY, width: size.width, height: 1)), with: .color(ink))
            let radius: CGFloat = 22
            let center = CGPoint(x: size.width - 14, y: horizonY - radius - 3)
            let moon = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            let bite = Path(ellipseIn: CGRect(x: center.x - radius * 0.45, y: center.y - radius * 1.25, width: radius * 1.9, height: radius * 1.9))
            context.fill(moon.subtracting(bite), with: .color(ink))
        }
        .accessibilityHidden(true)
    }
}

/// The insight: a butter block with a lightbulb in a 32pt dark circle
/// that draws itself on as the block arrives, and a small flat chart of
/// the evidence. A long press (and, on iOS 27, a swipe) offers "Not
/// useful" and "Hide insights like this".
struct InsightBlockView: View {
    let content: InsightCardContent
    let dismiss: () -> Void
    let hide: () -> Void

    @Environment(\.homeReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glyphShown = false

    var body: some View {
        ColorBlock(fill: NoctisAppColor.blockButter) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(NoctisAppColor.blockInk)
                    .frame(width: 32, height: 32)
                    .overlay {
                        if glyphShown || reduceMotion {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(NoctisAppColor.blockButter)
                                .transition(.symbolEffect(.drawOn))
                        }
                    }
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    Text(content.title)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.blockInk)
                    Text(content.message)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.blockInk)
                    InsightEvidenceChart(chart: content.chart)
                        .padding(.top, NoctisSpacing.xs)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contextMenu {
            Button("Not useful", systemImage: "hand.thumbsdown", action: dismiss)
            Button("Hide insights like this", systemImage: "eye.slash", action: hide)
        }
        .modifier(InsightSwipeActions(dismiss: dismiss, hide: hide))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityAction(named: "Not useful", dismiss)
        .accessibilityAction(named: "Hide insights like this", hide)
        .task {
            guard !reduceMotion, !glyphShown else { return }
            // With the morning reveal, the glyph draws on as the content does.
            try? await Task.sleep(for: .seconds(reveal.holdsStart ? HomeRevealPhase.contentDelay : 0.15))
            withAnimation { glyphShown = true }
        }
    }
}

/// The evidence as a small flat chart in cocoa and cocoa .3.
struct InsightEvidenceChart: View {
    let chart: InsightChartContent

    private var cocoa: Color { NoctisAppColor.blockCocoa }

    var body: some View {
        switch chart {
        case .comparison(let lastNight, let usual):
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                bar(lastNight, fill: cocoa)
                bar(usual, fill: cocoa.opacity(0.3))
            }
        case .timeline(let usual, let lastNight):
            VStack(spacing: NoctisSpacing.xxs) {
                NoctisFractionLayout {
                    tickLabel(lastNight, emphasized: true).noctisFraction(lastNight.position)
                }
                Canvas { context, size in
                    let y = size.height / 2
                    context.fill(Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)), with: .color(cocoa.opacity(0.3)))
                    for (tick, strong) in [(usual, false), (lastNight, true)] {
                        let x = min(max(tick.position * size.width, 1.5), size.width - 1.5)
                        let tickHeight: CGFloat = strong ? 16 : 12
                        let rect = CGRect(x: x - 1.5, y: y - tickHeight / 2, width: 3, height: tickHeight)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(strong ? cocoa : cocoa.opacity(0.3)))
                    }
                }
                .frame(height: 16)
                NoctisFractionLayout {
                    tickLabel(usual, emphasized: false).noctisFraction(usual.position)
                }
            }
        case .nights(let dots):
            HStack(spacing: 10) {
                ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(dot.within == true ? cocoa : (dot.within == nil ? cocoa.opacity(0.12) : Color.clear))
                            .overlay(Circle().strokeBorder(dot.within == false ? cocoa.opacity(0.3) : Color.clear, lineWidth: 1.5))
                            .frame(width: 12, height: 12)
                        Text(dot.label)
                            .noctisFont(11, .medium, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
                            .foregroundStyle(NoctisAppColor.blockInk)
                    }
                }
            }
        }
    }

    private func bar(_ bar: InsightBar, fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(bar.label)
                    .noctisFont(13, .medium, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.blockInk)
                Spacer(minLength: NoctisSpacing.xs)
                NoctisMetric(bar.value, size: 15, relativeTo: .subheadline, tone: .block)
            }
            Canvas { context, size in
                let width = max(size.width * min(max(bar.fraction, 0), 1), size.height)
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: size.height), cornerRadius: size.height / 2), with: .color(fill))
            }
            .frame(height: 8)
        }
    }

    private func tickLabel(_ tick: InsightTick, emphasized: Bool) -> some View {
        Text("\(tick.label) \(tick.time)")
            .noctisFont(12, emphasized ? .semibold : .regular, relativeTo: .caption)
            .foregroundStyle(NoctisAppColor.blockInk)
            .lineLimit(1)
            .fixedSize()
    }
}

/// iOS 27: the same two actions behind a swipe (the Home scroll view is the
/// swipe actions container). iOS 26 keeps the long press only.
private struct InsightSwipeActions: ViewModifier {
    let dismiss: () -> Void
    let hide: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Hide similar", systemImage: "eye.slash", action: hide)
                    .tint(NoctisAppColor.ink2)
                Button("Not useful", systemImage: "hand.thumbsdown", action: dismiss)
                    .tint(NoctisAppColor.ink)
            } onPresentationChanged: { _ in }
        } else {
            content
        }
    }
}

// MARK: - This week

/// A white card (Dark: surface) of stage-stacked bars: each night's time
/// asleep split bottom to top into Deep, Core and REM (a solid sage bar
/// without stages), last night at full strength and the others at 60%;
/// an orange dashed need line, weekday initials of the mornings, and the
/// average. Nights without data are an empty track, never a zero-height
/// bar.
///
/// Tapping a column (its full width, into the card's padding) selects it —
/// the others dim to 40% — and shows "Tue · 7h 12m · Deep 1h 20m · REM
/// 1h 50m"; tapping it again clears. Any other tap opens the Sleep tab.
/// The bars grow from the baseline in the morning reveal.
struct WeekCardView: View {
    let content: WeekCardContent
    let open: () -> Void

    @Environment(\.homeReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Int?
    @State private var tapWidth: CGFloat = 0

    static let chartHeight: CGFloat = 110
    static let barWidth: CGFloat = 16
    static let restingOpacity = 0.6
    /// The tap area runs this far out past the bars on each side: through
    /// the card's padding and the screen margin. Only the two outer
    /// columns use it.
    static let tapOutset = NoctisSpacing.lg + NoctisSpacing.lg

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    NoctisCaption("THIS WEEK", style: .noctisInk3)
                    Spacer(minLength: NoctisSpacing.xs)
                    HStack(spacing: 6) {
                        DashedLine()
                            .stroke(NoctisAppColor.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            .frame(width: 16, height: 1.5)
                        Text(content.needLabel)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                    }
                }
                chart
                if let average = content.average {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("Avg")
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                        NoctisMetric(average, size: 17, relativeTo: .body)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : NoctisMotion.settle, value: average)
                    }
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: NoctisRadius.lg, style: .continuous))
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityValue(selected.map { content.bars[$0].detail } ?? "")
        .accessibilityHint("Opens the Sleep tab. Swipe up or down to go through the nights.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityAdjustableAction { direction in
            let last = content.bars.count - 1
            switch direction {
            case .increment: selected = min((selected ?? -1) + 1, last)
            case .decrement: selected = max((selected ?? last + 1) - 1, 0)
            @unknown default: break
            }
        }
    }

    private var chart: some View {
        VStack(spacing: NoctisSpacing.xs) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(content.bars.enumerated()), id: \.offset) { index, bar in
                        barView(bar, index: index)
                            .frame(maxWidth: .infinity)
                    }
                }
                DashedLine()
                    .stroke(NoctisAppColor.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(height: 1.5)
                    .padding(.bottom, Self.chartHeight * content.needFraction)
            }
            .frame(height: Self.chartHeight)
            .overlay(alignment: .top) { selectionPill }
            HStack(spacing: 0) {
                ForEach(Array(content.bars.enumerated()), id: \.offset) { _, bar in
                    Text(bar.label)
                        .noctisFont(13, bar.isLastNight ? .semibold : .medium, relativeTo: .footnote)
                        .foregroundStyle(bar.isLastNight ? NoctisInkStyle(.primary) : .noctisInk3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        // Each column's tap area is its full column: the width the bar is
        // centered in, top to bottom (the two outer ones run out past the
        // card's padding into the screen margin).
        .padding(.horizontal, Self.tapOutset)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tapWidth = $0 }
        .onTapGesture(coordinateSpace: .local) { location in
            guard tapWidth > 0, !content.bars.isEmpty else { return }
            select(WeekColumns.index(x: location.x, barsWidth: tapWidth - 2 * Self.tapOutset, outset: Self.tapOutset, count: content.bars.count))
        }
        .padding(.horizontal, -Self.tapOutset)
    }

    private func barView(_ bar: WeekBar, index: Int) -> some View {
        ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(NoctisAppColor.track)
            if let fraction = bar.fraction {
                let height = max(Self.chartHeight * fraction, Self.barWidth)
                stack(bar.stages, height: height)
                    .frame(height: height)
                    .clipShape(Capsule(style: .continuous))
                    .opacity(opacity(for: bar, index: index))
                    // Grows from the baseline in the morning reveal.
                    .scaleEffect(x: 1, y: reveal.holdsStart ? 0.001 : 1, anchor: .bottom)
                    .animation(
                        reduceMotion ? nil : NoctisMotion.settle.delay(HomeRevealPhase.contentDelay + HomeReveal.weekStagger * Double(index)),
                        value: reveal
                    )
            }
        }
        .frame(width: Self.barWidth, height: Self.chartHeight)
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    /// Deep, Core, REM from the bottom; one sage bar without stages.
    @ViewBuilder
    private func stack(_ stages: WeekBarStages?, height: CGFloat) -> some View {
        if let stages {
            VStack(spacing: 0) {
                NoctisAppColor.sage.frame(height: height * stages.rem)
                NoctisAppColor.orange.frame(height: height * stages.core)
                NoctisAppColor.nightDeep.frame(height: height * stages.deep)
            }
        } else {
            NoctisAppColor.sage
        }
    }

    private func opacity(for bar: WeekBar, index: Int) -> Double {
        if let selected { return selected == index ? 1 : 0.4 }
        return bar.isLastNight ? 1 : Self.restingOpacity
    }

    /// Floats just above the bars, over the selected night.
    @ViewBuilder
    private var selectionPill: some View {
        if let selected {
            NoctisFractionLayout {
                HomePill(text: content.bars[selected].detail)
                    .noctisFraction((Double(selected) + 0.5) / Double(max(content.bars.count, 1)))
            }
            .alignmentGuide(.top) { $0[.bottom] + 6 }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    private func select(_ index: Int) {
        NoctisHaptics.selectionTick()
        withAnimation(.easeOut(duration: 0.2)) {
            selected = selected == index ? nil : index
        }
    }
}

/// This week's tap columns: the bars' area split into equal columns, the
/// same ones the bars are centered in, with the outer two taking
/// everything past them.
nonisolated enum WeekColumns {
    /// The column at `x`, in a tap area that starts `outset` before the
    /// bars' area (`barsWidth` wide) and ends `outset` after it.
    static func index(x: CGFloat, barsWidth: CGFloat, outset: CGFloat, count: Int) -> Int {
        guard count > 0, barsWidth > 0 else { return 0 }
        let column = Int(((x - outset) / (barsWidth / CGFloat(count))).rounded(.down))
        return min(max(column, 0), count - 1)
    }

    /// How wide each interior column is.
    static func width(barsWidth: CGFloat, count: Int) -> CGFloat {
        count > 0 ? barsWidth / CGFloat(count) : 0
    }
}

nonisolated struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
