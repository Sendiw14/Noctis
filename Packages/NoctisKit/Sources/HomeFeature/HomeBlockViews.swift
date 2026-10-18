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
    @State private var laneFocus: NightLane?
    /// VoiceOver's position when stepping through the night.
    @State private var spokenSegment: Int?

    private var chart: NightChartContent { content.chart }

    var body: some View {
        #if DEBUG
        let _ = HomeBodyProbe.hit("NightPanel")
        #endif
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
            HStack(alignment: .top, spacing: NoctisSpacing.sm) {
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
                // Sleep quality, when the Sleep tab has a score for the night.
                if let quality = content.sleepQuality {
                    VStack(alignment: .trailing, spacing: 0) {
                        NoctisMetric(quality, size: 34, tone: .nightPanel)
                            .lineLimit(1)
                        Text("Sleep quality")
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(.noctisNightInk2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.top, NoctisSpacing.md)
                }
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
        let drawIn: Animation? = reduceMotion ? nil : NoctisMotion.draw(HomeReveal.nightDuration).delay(HomeRevealPhase.contentDelay)
        return NightLandscapeView(
            chart: chart,
            drawn: reveal.holdsStart ? 0 : 1,
            details: reveal.holdsStart ? 0 : 1,
            laneFocus: $laneFocus
        )
        .animation(drawIn, value: reveal)
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
struct NightChartAudioGraph: ViewModifier {
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

/// Under the time axis: each stage's dot, name and time, in one row (a
/// 2×2 grid at accessibility sizes).
struct NightStageTotalsView: View {
    let totals: [NightLaneTotal]
    /// Sleep makes each total a button that highlights its stage across
    /// the night; on Home they're plain text.
    var onTap: ((NightLane) -> Void)?
    var focus: NightLane?
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
        // The night's own label already reads every total (unless they're
        // buttons of their own).
        .accessibilityHidden(onTap == nil)
    }

    @ViewBuilder
    private func stat(_ total: NightLaneTotal) -> some View {
        if let onTap {
            Button { onTap(total.lane) } label: {
                content(total)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(focus == nil || focus == total.lane ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(total.lane.name) \(total.duration.spoken)")
            .accessibilityHint(focus == total.lane ? "Stops highlighting it." : "Highlights it across the night.")
            .accessibilityAddTraits(focus == total.lane ? [.isButton, .isSelected] : .isButton)
        } else {
            content(total)
        }
    }

    private func content(_ total: NightLaneTotal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(total.lane.tint).frame(width: 7, height: 7)
                Text(total.lane.name)
                    .noctisFont(12, .medium, relativeTo: .caption2)
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
            HStack {
                NoctisCaption("TONIGHT", style: NoctisAppColor.blockInk)
                Spacer(minLength: 0)
                // The block is a button: it opens Tonight.
                Image(systemName: "chevron.forward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoctisAppColor.blockInk)
                    .accessibilityHidden(true)
            }
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
                    TonightCrescent()
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
    static let size = CGSize(width: 132, height: 96)

    /// The horizon and the moon, worked out once for the fixed size.
    private static let paths: (horizon: Path, moon: Path) = {
        // Low in the bottom-right corner, so the corner's curve cuts both
        // the horizon and the moon.
        let horizonY = size.height - 14
        let radius: CGFloat = 22
        let center = CGPoint(x: size.width - 14, y: horizonY - radius - 3)
        let moon = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        let bite = Path(ellipseIn: CGRect(x: center.x - radius * 0.45, y: center.y - radius * 1.25, width: radius * 1.9, height: radius * 1.9))
        return (Path(CGRect(x: 0, y: horizonY, width: size.width, height: 1)), moon.subtracting(bite))
    }()

    var body: some View {
        Canvas { context, _ in
            let ink = NoctisAppColor.blockCocoa.opacity(0.12)
            context.fill(Self.paths.horizon, with: .color(ink))
            context.fill(Self.paths.moon, with: .color(ink))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

/// The insight: a butter block with a lightbulb in a 32pt dark circle
/// that draws itself on as the block arrives, and a small flat chart of
/// the evidence. A long press (and, on iOS 27, a swipe) offers "Not
/// useful" and "Hide insights like this".
struct InsightBlockView: View {
    let content: InsightCardContent
    let open: () -> Void
    let dismiss: () -> Void
    let hide: () -> Void

    @Environment(\.homeReveal) private var reveal
    @Environment(\.homeLowPower) private var lowPower
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glyphShown = false

    var body: some View {
        Button(action: open) {
            ColorBlock(fill: NoctisAppColor.blockButter) {
                HStack(alignment: .top, spacing: 14) {
                    Circle()
                        .fill(NoctisAppColor.blockInk)
                        .frame(width: 32, height: 32)
                        .overlay {
                            if glyphShown || reduceMotion || lowPower {
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
        }
        .buttonStyle(NoctisCardButtonStyle())
        .contextMenu {
            Button("Open insight", systemImage: "arrow.up.forward.square", action: open)
            Button("Not useful", systemImage: "hand.thumbsdown", action: dismiss)
            Button("Hide insights like this", systemImage: "eye.slash", action: hide)
        }
        .modifier(InsightSwipeActions(dismiss: dismiss, hide: hide))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("Opens the insight.")
        .accessibilityAction(named: "Not useful", dismiss)
        .accessibilityAction(named: "Hide insights like this", hide)
        .accessibilityIdentifier("home.insight")
        .task {
            guard !reduceMotion, !lowPower, !glyphShown else { return }
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
                ZStack {
                    Rectangle().fill(cocoa.opacity(0.3)).frame(height: 1)
                    NoctisFractionLayout {
                        RoundedRectangle(cornerRadius: 1.5).fill(cocoa.opacity(0.3)).frame(width: 3, height: 12)
                            .noctisFraction(usual.position)
                        RoundedRectangle(cornerRadius: 1.5).fill(cocoa).frame(width: 3, height: 16)
                            .noctisFraction(lastNight.position)
                    }
                }
                .frame(height: 16)
                NoctisFractionLayout {
                    tickLabel(usual, emphasized: false).noctisFraction(usual.position)
                }
            }
        case .figures(let numbers, let join):
            HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                ForEach(Array(numbers.enumerated()), id: \.offset) { index, number in
                    if index > 0 {
                        Group {
                            if join == .arrow {
                                Image(systemName: "arrow.forward").font(.system(size: 14, weight: .semibold))
                            } else {
                                Text("vs").noctisFont(13, .semibold, relativeTo: .footnote)
                            }
                        }
                        .foregroundStyle(NoctisAppColor.blockInk)
                        .frame(height: 26)
                        .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        NoctisMetric(number.value, size: 22, relativeTo: .title3, tone: .block)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(number.label)
                            .noctisFont(12, .medium, relativeTo: .caption)
                            .foregroundStyle(NoctisAppColor.blockInk)
                    }
                }
            }
        case .nights(let dots, let caption):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, dot in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(dot.within == true ? cocoa : (dot.within == nil ? cocoa.opacity(0.12) : Color.clear))
                                .overlay(Circle().strokeBorder(dot.within == false ? cocoa.opacity(0.3) : Color.clear, lineWidth: 1.5))
                                .frame(width: 12, height: 12)
                            Text(dot.label)
                                .noctisFont(12, .medium, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
                                .foregroundStyle(NoctisAppColor.blockInk)
                        }
                    }
                }
                Text(caption)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(NoctisAppColor.blockInk)
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
            NoctisSpanLayout(to: bar.fraction, minimumWidth: 8) {
                Capsule().fill(fill)
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
/// without stages), fully saturated in both modes; an orange dashed need
/// line, weekday initials of the mornings (last night's bold, with a dot
/// under it), and the average. Nights without data are an empty track,
/// never a zero-height bar.
///
/// One drag gesture over the whole chart picks the night nearest the
/// finger: the selection follows it with a snap haptic at each bar, the
/// others dim to 45%, and "Tue · 7h 12m · Deep 1h 20m · REM 1h 50m" shows
/// in a pill that follows and clamps. The last selection stays until it's
/// tapped again. Any tap outside the chart opens the Sleep tab. The bars
/// grow from the baseline in the morning reveal.
struct WeekCardView: View {
    let content: WeekCardContent
    let open: () -> Void

    @Environment(\.homeReveal) private var reveal
    @Environment(\.homeLowPower) private var lowPower
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Int?
    @State private var tapWidth: CGFloat = 0
    /// The row the selection pill lives in, above the bars: reserved
    /// whether or not a night is selected, so nothing moves and the pill
    /// never covers a bar.
    @NoctisScaledLength(relativeTo: .footnote) private var pillRowHeight: CGFloat = 28
    static let chartHeight: CGFloat = 110
    /// The tap area runs this far out past the bars on each side: through
    /// the card's padding and the screen margin. Only the two outer
    /// columns use it.
    static let tapOutset = NoctisSpacing.lg + NoctisSpacing.lg

    private var barsWidth: CGFloat { tapWidth }
    private var barWidth: CGFloat { WeekColumns.barWidth(barsWidth: barsWidth, count: content.bars.count) }

    var body: some View {
        #if DEBUG
        let _ = HomeBodyProbe.hit("WeekCard")
        #endif
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                NoctisCaptionRow("THIS WEEK") {
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
                    // The label beside the figure; when a longer word for a unit (or a larger text size) leaves the figure no room, the figure
                    // goes under the label instead of being cut to its first digit.
                    ViewThatFits(in: .horizontal) {
                        averageLine(average, stacked: false)
                        averageLine(average, stacked: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if content.bars.contains(where: { $0.stages != nil }) {
                    stageLegend
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

    private func averageLine(_ average: NoctisMetricValue, stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
        return layout {
            Text("Avg")
                .noctisFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoctisAppColor.ink)
            NoctisMetric(average, size: 17, relativeTo: .body)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : NoctisMotion.settle, value: average)
        }
    }

    private var chart: some View {
        VStack(spacing: NoctisSpacing.xs) {
            selectionPill
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
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(content.bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 3) {
                        Text(bar.label)
                            .noctisFont(13, bar.isLastNight ? .bold : .medium, relativeTo: .footnote)
                            .foregroundStyle(bar.isLastNight ? NoctisInkStyle(.primary) : .noctisInk3)
                        // Last night: a 4pt dot (the others keep the room).
                        Circle()
                            .fill(NoctisAppColor.ink)
                            .frame(width: 4, height: 4)
                            .opacity(bar.isLastNight ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        // One gesture over the whole chart — the bars' columns, top to
        // bottom, and out past the card's padding into the screen margin
        // for the two outer ones. A tap on the chart picks a night rather
        // than opening Sleep; a sideways drag scrubs; an up-and-down drag
        // is the page's own scroll.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tapWidth = $0 }
        .columnScrub(count: content.bars.count, chartWidth: barsWidth, outset: Self.tapOutset, selected: $selected)
    }

    private func barView(_ bar: WeekBar, index: Int) -> some View {
        let width = barWidth
        let shape = RoundedRectangle(cornerRadius: WeekColumns.cornerRadius, style: .continuous)
        return ZStack(alignment: .bottom) {
            shape.fill(NoctisAppColor.track)
            if let fraction = bar.fraction {
                let height = max(Self.chartHeight * fraction, WeekColumns.cornerRadius * 2)
                WeekBarStack(stages: bar.stages, height: height, fill: NoctisAppColor.sage)
                    .frame(height: height)
                    .opacity(opacity(index))
                    // Grows from the baseline in the morning reveal.
                    .scaleEffect(x: 1, y: reveal.holdsStart ? 0.001 : 1, anchor: .bottom)
                    .animation(
                        reduceMotion ? nil : NoctisMotion.settle.delay(HomeRevealPhase.contentDelay + HomeReveal.weekDelay(index, lowPower: lowPower)),
                        value: reveal
                    )
            }
        }
        .frame(width: width, height: Self.chartHeight)
        .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: selected)
    }

    /// Fully saturated until one is selected; then the others dim.
    private func opacity(_ index: Int) -> Double {
        guard let selected else { return 1 }
        return selected == index ? 1 : WeekColumns.dimmedOpacity
    }

    /// One line: Deep, Core, REM at 12pt.
    private var stageLegend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoctisSpacing.md) { legendKeys }
            VStack(alignment: .leading, spacing: 4) { legendKeys }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var legendKeys: some View {
        ForEach([("Deep", NoctisAppColor.nightDeep), ("Core", NoctisAppColor.coreTint), ("REM", NoctisAppColor.sage)], id: \.0) { key in
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(key.1).frame(width: 10, height: 10)
                Text(key.0)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
            }
        }
    }

    /// The pill sits in its own row above the bars, centered over the
    /// selected night and kept inside the card; text too wide for the row
    /// (accessibility sizes) wraps and grows upward, never down over a bar.
    private var selectionPill: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let selected {
                NoctisFractionLayout(wraps: true) {
                    HomePill(text: content.bars[selected].detail)
                        .noctisFraction((Double(selected) + 0.5) / Double(max(content.bars.count, 1)))
                }
                .transition(.opacity)
            }
        }
        .frame(height: pillRowHeight, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

/// This week's columns: the bars' area split into equal columns, the
/// same ones the bars are centered in, with the outer two taking
/// everything past them. The night nearest a finger is its column's.
public nonisolated enum WeekColumns {
    /// The column at `x`, in a touch area that starts `outset` before the
    /// bars' area (`barsWidth` wide) and ends `outset` after it.
    public static func index(x: CGFloat, barsWidth: CGFloat, outset: CGFloat, count: Int) -> Int {
        guard count > 0, barsWidth > 0 else { return 0 }
        let column = Int(((x - outset) / (barsWidth / CGFloat(count))).rounded(.down))
        return min(max(column, 0), count - 1)
    }

    /// How wide each interior column is.
    public static func width(barsWidth: CGFloat, count: Int) -> CGFloat {
        count > 0 ? barsWidth / CGFloat(count) : 0
    }

    /// A bar is its column less 12pt, at most 24pt wide.
    public static func barWidth(barsWidth: CGFloat, count: Int) -> CGFloat {
        let column = width(barsWidth: barsWidth, count: count)
        return column > 0 ? min(column - 12, 24) : 24
    }

    public static let cornerRadius: CGFloat = 6
    /// The other bars while one is selected.
    public static let dimmedOpacity = 0.45
    /// A touch that moves less than this is a tap.
    public static let tapSlop: CGFloat = 10
    /// A drag more vertical than horizontal past this is the page scrolling.
    public static let scrollThreshold: CGFloat = 12
}

/// A week bar's stages, bottom to top Deep, Core, REM, as three rounded
/// segments (6pt corners each) with 2pt gaps of the card between them; one
/// sage bar without stages. Shared by Home's This week and Sleep's Week.
public struct WeekBarStack: View {
    public static let gap: CGFloat = 2

    private let stages: WeekBarStages?
    private let height: CGFloat
    private let fill: Color

    public init(stages: WeekBarStages?, height: CGFloat, fill: Color) {
        self.stages = stages
        self.height = height
        self.fill = fill
    }

    public var body: some View {
        if let stages {
            let parts: [(Color, Double)] = [
                (NoctisAppColor.sage, stages.rem),
                (NoctisAppColor.coreTint, stages.core),
                (NoctisAppColor.nightDeep, stages.deep),
            ].filter { $0.1 > 0 }
            let usable = max(height - Self.gap * CGFloat(max(parts.count - 1, 0)), 0)
            VStack(spacing: Self.gap) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    let segment = usable * part.1
                    RoundedRectangle(cornerRadius: min(WeekColumns.cornerRadius, segment / 2), style: .continuous)
                        .fill(part.0)
                        .frame(height: segment)
                }
            }
            .frame(height: height, alignment: .bottom)
            // The gaps are the card, not the bar's track behind.
            .background { RoundedRectangle(cornerRadius: WeekColumns.cornerRadius, style: .continuous).fill(NoctisAppColor.surface) }
        } else {
            RoundedRectangle(cornerRadius: WeekColumns.cornerRadius, style: .continuous).fill(fill)
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


// MARK: - Review cards

/// "Your weekly review": the dates, an icon tile in the review's color and a chevron, or a lock for what Premium holds. No badge, no count, no urgency, and it goes by
/// itself after three days (APP_RULES.md R63).
struct ReviewCardView: View {
    let card: HomeReviewCard
    let locked: Bool
    let open: () -> Void

    var body: some View {
        Button {
            NoctisHaptics.selection()
            open()
        } label: {
            NoctisAppCard {
                HStack(spacing: NoctisSpacing.sm) {
                    NoctisIconTile(
                        systemImage: "calendar", fill: card.kind == .weekly ? NoctisAppColor.blockLavender : NoctisAppColor.blockSage, foreground: NoctisAppColor.blockInk, size: 40
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(NoctisAppColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(card.detail)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: NoctisSpacing.xs)
                    if locked {
                        LockGlyph(size: 14).foregroundStyle(.noctisInk3)
                    } else {
                        NoctisRowChevron()
                    }
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(locked ? "\(card.accessibilityLabel), Premium" : card.accessibilityLabel)
        .accessibilityHint(locked ? "Opens what Premium includes." : "Opens your review.")
        .accessibilityIdentifier("home.review.\(card.kind.rawValue)")
    }
}
