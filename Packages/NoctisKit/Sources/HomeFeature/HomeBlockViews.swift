import Accessibility
import DesignSystem
import NoctisCore
import SwiftUI

// MARK: - Night panel

/// Last night, always the darkest element on screen: a solid cocoa block
/// in Light, an inset near-black panel with a hairline in Dark.
///
/// Dragging sideways across the chart scrubs it: a 1pt ivory line, a dot
/// on the active lane and a pill ("3:41 AM · REM · 47 min"), the other
/// lanes at 40%, a light tick at each change of stage; it all fades on
/// release. Tapping a lane label shows that stage's total until tapped
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
            // its segments), then the chart for Audio Graph. On one
            // element, Audio Graph's rotor would take over the swipes.
            .accessibilityElement(children: .contain)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                NoctisCaption("LAST NIGHT", style: .noctisNightInk2)
                Text(content.duration)
                    .noctisFont(48, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
                    .foregroundStyle(NoctisAppColor.nightInk)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : NoctisMotion.settle, value: content.duration)
                Text(content.timeRange)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisNightInk2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(content.accessibilityLabel)
            .accessibilityValue(spokenSegment.flatMap { chart.reading(segment: $0)?.text } ?? "")
            .accessibilityHint(chart.hasStages ? "Opens the Sleep tab. Swipe up or down to step through the night." : "Opens the Sleep tab.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .accessibilityAction(named: "Open Sleep", open)
            .accessibilityAction(named: "Share this night", share)
            .modifier(NightStepping(chart: chart, segment: $spokenSegment))
            chartView
                .modifier(NightChartAudioGraph(chart: chart))
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

/// VoiceOver: step through the night's segments, reading the same text
/// as the scrub pill.
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

/// The chart as its own element, for Audio Graph.
private struct NightChartAudioGraph: ViewModifier {
    let chart: NightChartContent

    func body(content: Content) -> some View {
        if chart.hasStages {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep stages chart")
                .accessibilityHint("Use Audio Graph from the rotor to hear it.")
                .accessibilityChartDescriptor(NightChartDescriptor(chart: chart))
        } else {
            content.accessibilityHidden(true)
        }
    }
}

/// Audio Graph: time across, stage up (Deep lowest, Awake highest), one
/// point per segment, read with the pill's text.
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
            return AXDataPoint(x: chart.spans[index].start * minutes, y: height, additionalValues: [], label: reading.text)
        }
        return AXChartDescriptor(
            title: "Last night's sleep stages",
            summary: "Stages from bedtime to wake-up.",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "Stages", isContinuous: false, dataPoints: points)]
        )
    }
}

/// Four lanes (Awake, REM, Core, Deep) with each stage span as a rounded
/// bar in its lane, 1pt connectors where the night changes lane, and the
/// start, midpoint and end times. Without stages: one sage bar in the
/// Core lane. Draws left to right as `drawn` goes 0 → 1; the scrub and
/// lane focus dim every other lane to 40%.
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

    /// Lane height scales with the lane labels beside it (R4).
    @NoctisScaledLength(relativeTo: .caption2) private var laneHeight: CGFloat = 28
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var width: CGFloat = 0

    /// The label column's tap area reaches this far into the panel's
    /// padding, without moving anything.
    private static let labelReach: CGFloat = 12

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            laneLabels
            VStack(spacing: NoctisSpacing.xxs) {
                NightChartCanvas(
                    chart: chart,
                    drawn: drawn,
                    emphasis: focusActive ? 1 : 0,
                    lane: focusLane,
                    connectorOpacity: contrast == .increased ? 0.6 : 0.3
                )
                .frame(height: laneHeight * CGFloat(NightLane.allCases.count))
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
        .accessibilityHidden(true)
    }

    private var laneLabels: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(NightLane.allCases, id: \.self) { lane in
                Text(lane.name)
                    .noctisFont(11, focusActive && focusLane == lane ? .bold : .medium, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
                    .foregroundStyle(.noctisNightInk2)
                    .frame(height: laneHeight)
            }
        }
        .fixedSize()
        // The gap to the chart belongs to the labels' tap area.
        .padding(.trailing, NoctisSpacing.xs)
        .padding(.leading, Self.labelReach)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            guard let onLaneTap else { return }
            let index = min(max(Int(location.y / laneHeight), 0), NightLane.allCases.count - 1)
            onLaneTap(NightLane.allCases[index])
        }
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

/// The chart's bars and connectors, animatable over how much has drawn
/// and how far the other lanes have dimmed.
struct NightChartCanvas: View, Animatable {
    let chart: NightChartContent
    var drawn: Double
    var emphasis: Double
    let lane: NightLane?
    let connectorOpacity: Double

    static let dimmedOpacity = 0.4

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
        var context = context
        context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * min(max(drawn, 0), 1), height: size.height)))
        let laneHeight = size.height / CGFloat(NightLane.allCases.count)
        let barHeight = max(laneHeight * 0.5, 6)
        let ink = NoctisAppColor.nightInk
        let dimmed = 1 - (1 - Self.dimmedOpacity) * min(max(emphasis, 0), 1)
        func centerY(_ nightLane: NightLane) -> CGFloat { laneHeight * (CGFloat(nightLane.rawValue) + 0.5) }

        guard chart.hasStages else {
            let rect = CGRect(x: 0, y: centerY(.core) - barHeight / 2, width: size.width, height: barHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: barHeight / 2), with: .color(NoctisAppColor.sage))
            return
        }
        for connector in chart.connectors {
            let x = connector.position * size.width
            let top = min(centerY(connector.from), centerY(connector.to))
            let bottom = max(centerY(connector.from), centerY(connector.to))
            var connectorContext = context
            if lane != nil { connectorContext.opacity = dimmed }
            connectorContext.fill(Path(CGRect(x: x - 0.5, y: top, width: 1, height: bottom - top)), with: .color(ink.opacity(connectorOpacity)))
        }
        for span in chart.spans {
            let x = span.start * size.width
            let width = max((span.end - span.start) * size.width, 2)
            let rect = CGRect(x: x, y: centerY(span.stage.lane) - barHeight / 2, width: width, height: barHeight)
            let color = span.stage == .asleep ? NoctisAppColor.sage : span.stage.lane.tint
            var spanContext = context
            if let lane, lane != span.stage.lane { spanContext.opacity = dimmed }
            spanContext.fill(Path(roundedRect: rect, cornerRadius: min(barHeight, width) / 2), with: .color(color))
        }
    }
}

/// The night panel's long-press preview: the panel with each stage's total.
struct NightPanelPreview: View {
    let content: LastNightCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                NoctisCaption("LAST NIGHT", style: .noctisNightInk2)
                Text(content.duration)
                    .noctisFont(48, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
                    .foregroundStyle(NoctisAppColor.nightInk)
                Text(content.timeRange)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisNightInk2)
            }
            NightChartView(chart: content.chart)
            if !content.chart.laneTotals.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: NoctisSpacing.md, verticalSpacing: NoctisSpacing.xxs) {
                    GridRow {
                        ForEach(content.chart.laneTotals.prefix(2), id: \.lane) { total in totalText(total) }
                    }
                    GridRow {
                        ForEach(content.chart.laneTotals.dropFirst(2), id: \.lane) { total in totalText(total) }
                    }
                }
            }
        }
        .padding(NoctisSpacing.lg)
        .frame(width: 340, alignment: .leading)
        .background(NoctisAppColor.nightPanel)
    }

    private func totalText(_ total: NightLaneTotal) -> some View {
        HStack(spacing: 6) {
            Circle().fill(total.lane.tint).frame(width: 8, height: 8)
            Text(total.text)
                .noctisFont(13, .medium, relativeTo: .footnote)
                .foregroundStyle(NoctisAppColor.nightInk)
        }
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

/// Day mode's Tonight: a lavender block with the plan.
struct TonightBlockView: View {
    let content: TonightCardContent

    var body: some View {
        ColorBlock(fill: NoctisAppColor.blockLavender) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                NoctisCaption("TONIGHT", style: NoctisAppColor.blockInk)
                Text(content.bedtime)
                    .noctisFont(22, .semibold, relativeTo: .title3)
                    .foregroundStyle(NoctisAppColor.blockInk)
                Text(content.detail)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.blockInk)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The insight: a butter block with a lightbulb in a 32pt dark circle
/// that draws itself on as the block arrives. A long press (and, on iOS
/// 27, a swipe) offers "Not useful" and "Hide insights like this".
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
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    Text(content.title)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.blockInk)
                    Text(content.message)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.blockInk)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contextMenu {
            Button("Not useful", systemImage: "hand.thumbsdown", action: dismiss)
            Button("Hide insights like this", systemImage: "eye.slash", action: hide)
        }
        .modifier(InsightSwipeActions(dismiss: dismiss, hide: hide))
        .accessibilityElement(children: .combine)
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

/// A white card (Dark: surface): sage bars, last night's bar cocoa in
/// Light and lavender in Dark, an orange dashed need line, weekday
/// initials of the mornings, and the average. Nights without data are an
/// empty track, never a zero-height bar.
///
/// Tapping a bar selects it (the others dim to 40%) and shows "Tue · 7h
/// 12m · Recovery 76"; tapping it again clears. Any other tap opens the
/// Sleep tab. The bars grow from the baseline in the morning reveal.
struct WeekCardView: View {
    let content: WeekCardContent
    let open: () -> Void

    @Environment(\.homeReveal) private var reveal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Int?

    static let chartHeight: CGFloat = 110
    static let barWidth: CGFloat = 16

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
                    Text(average)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : NoctisMotion.settle, value: average)
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
                            .frame(height: Self.chartHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { select(index) }
                    }
                }
                DashedLine()
                    .stroke(NoctisAppColor.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(height: 1.5)
                    .padding(.bottom, Self.chartHeight * content.needFraction)
                    .allowsHitTesting(false)
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
    }

    private func barView(_ bar: WeekBar, index: Int) -> some View {
        ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(NoctisAppColor.track)
            if let fraction = bar.fraction {
                Capsule(style: .continuous)
                    .fill(bar.isLastNight ? NoctisAppColor.weekHighlight : NoctisAppColor.sage)
                    .frame(height: max(Self.chartHeight * fraction, Self.barWidth))
                    // Grows from the baseline in the morning reveal.
                    .scaleEffect(x: 1, y: reveal.holdsStart ? 0.001 : 1, anchor: .bottom)
                    .animation(
                        reduceMotion ? nil : NoctisMotion.settle.delay(HomeRevealPhase.contentDelay + HomeReveal.weekStagger * Double(index)),
                        value: reveal
                    )
            }
        }
        .frame(width: Self.barWidth, height: Self.chartHeight)
        .opacity(selected == nil || selected == index ? 1 : 0.4)
        .animation(.easeOut(duration: 0.2), value: selected)
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

nonisolated struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
