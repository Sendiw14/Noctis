import DesignSystem
import NoctisCore
import SwiftUI

// MARK: - Night panel

/// Last night, always the darkest element on screen: a solid cocoa block
/// in Light, an inset near-black panel with a hairline in Dark. Taps open
/// the Sleep tab; scrubbing comes in Part B.
struct NightPanelView: View {
    let content: LastNightCardContent
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    NoctisCaption("LAST NIGHT", color: NoctisAppColor.nightInk.opacity(0.7))
                    Text(content.duration)
                        .noctisFont(48, .heavy, relativeTo: .largeTitle, maxScale: NoctisTypeScale.maxNumeralScale)
                        .foregroundStyle(NoctisAppColor.nightInk)
                    Text(content.timeRange)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.nightInk.opacity(0.7))
                }
                NightChartView(chart: content.chart)
                if let caption = content.chart.caption {
                    Text(caption)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisAppColor.nightInk.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
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
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("Opens the Sleep tab.")
        .accessibilityAddTraits(.isButton)
    }
}

/// Four lanes (Awake, REM, Core, Deep) with each stage span as a rounded
/// bar in its lane, 1pt connectors where the night changes lane, and the
/// start, midpoint and end times. Without stages: one sage bar in the
/// Core lane.
struct NightChartView: View {
    let chart: NightChartContent
    /// Lane height scales with the lane labels beside it (R4).
    @NoctisScaledLength(relativeTo: .caption2) private var laneHeight: CGFloat = 28

    private var ink: Color { NoctisAppColor.nightInk }

    var body: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.xs) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(NightLane.allCases, id: \.self) { lane in
                    Text(lane.name)
                        .noctisFont(11, .medium, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
                        .foregroundStyle(ink.opacity(0.7))
                        .frame(height: laneHeight)
                }
            }
            .fixedSize()
            VStack(spacing: NoctisSpacing.xxs) {
                Canvas { context, size in
                    draw(in: context, size: size)
                }
                .frame(height: laneHeight * CGFloat(NightLane.allCases.count))
                HStack {
                    ForEach(Array(chart.timeLabels.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer(minLength: NoctisSpacing.xxs) }
                        Text(label)
                            .noctisFont(11, relativeTo: .caption2, maxScale: NoctisTypeScale.maxIconScale)
                            .foregroundStyle(ink.opacity(0.7))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let lane = size.height / CGFloat(NightLane.allCases.count)
        let barHeight = max(lane * 0.5, 6)
        func centerY(_ nightLane: NightLane) -> CGFloat { lane * (CGFloat(nightLane.rawValue) + 0.5) }

        guard chart.hasStages else {
            let rect = CGRect(x: 0, y: centerY(.core) - barHeight / 2, width: size.width, height: barHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: barHeight / 2), with: .color(NoctisAppColor.sage))
            return
        }
        for connector in chart.connectors {
            let x = connector.position * size.width
            let top = min(centerY(connector.from), centerY(connector.to))
            let bottom = max(centerY(connector.from), centerY(connector.to))
            context.fill(Path(CGRect(x: x - 0.5, y: top, width: 1, height: bottom - top)), with: .color(ink.opacity(0.3)))
        }
        for span in chart.spans {
            let x = span.start * size.width
            let width = max((span.end - span.start) * size.width, 2)
            let rect = CGRect(x: x, y: centerY(span.stage.lane) - barHeight / 2, width: width, height: barHeight)
            let color = span.stage == .asleep ? NoctisAppColor.sage : span.stage.lane.tint
            context.fill(Path(roundedRect: rect, cornerRadius: min(barHeight, width) / 2), with: .color(color))
        }
    }
}

// MARK: - Color blocks

/// A solid, flat color block: 28pt corners, 20pt padding, no border.
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
    }
}

/// Day mode's Tonight: a lavender block with the plan.
struct TonightBlockView: View {
    let content: TonightCardContent

    var body: some View {
        ColorBlock(fill: NoctisAppColor.blockLavender) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                NoctisCaption("TONIGHT", color: NoctisAppColor.blockInk)
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

/// The insight: a butter block with a lightbulb in a 32pt dark circle.
struct InsightBlockView: View {
    let content: InsightCardContent

    var body: some View {
        ColorBlock(fill: NoctisAppColor.blockButter) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(NoctisAppColor.blockInk)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NoctisAppColor.blockButter)
                    )
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
        .accessibilityElement(children: .combine)
    }
}

// MARK: - This week

/// A white card (Dark: surface): sage bars, last night's bar cocoa in
/// Light and lavender in Dark, an orange dashed need line, weekday
/// initials of the mornings, and the average. Nights without data are an
/// empty track, never a zero-height bar.
struct WeekCardView: View {
    let content: WeekCardContent
    let open: () -> Void

    static let chartHeight: CGFloat = 110
    static let barWidth: CGFloat = 16

    var body: some View {
        Button(action: open) {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        NoctisCaption("THIS WEEK", color: NoctisAppColor.ink3)
                        Spacer(minLength: NoctisSpacing.xs)
                        HStack(spacing: 6) {
                            DashedLine()
                                .stroke(NoctisAppColor.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                .frame(width: 16, height: 1.5)
                            Text(content.needLabel)
                                .noctisFont(13, relativeTo: .footnote)
                                .foregroundStyle(NoctisAppColor.ink3)
                        }
                    }
                    chart
                    if let average = content.average {
                        Text(average)
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                    }
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityHint("Opens the Sleep tab.")
        .accessibilityAddTraits(.isButton)
    }

    private var chart: some View {
        VStack(spacing: NoctisSpacing.xs) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(content.bars.enumerated()), id: \.offset) { _, bar in
                        barView(bar).frame(maxWidth: .infinity)
                    }
                }
                DashedLine()
                    .stroke(NoctisAppColor.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(height: 1.5)
                    .padding(.bottom, Self.chartHeight * content.needFraction)
            }
            .frame(height: Self.chartHeight)
            HStack(spacing: 0) {
                ForEach(Array(content.bars.enumerated()), id: \.offset) { _, bar in
                    Text(bar.label)
                        .noctisFont(13, bar.isLastNight ? .semibold : .medium, relativeTo: .footnote)
                        .foregroundStyle(bar.isLastNight ? NoctisAppColor.ink : NoctisAppColor.ink3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func barView(_ bar: WeekBar) -> some View {
        ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(NoctisAppColor.track)
            if let fraction = bar.fraction {
                Capsule(style: .continuous)
                    .fill(bar.isLastNight ? NoctisAppColor.weekHighlight : NoctisAppColor.sage)
                    .frame(height: max(Self.chartHeight * fraction, Self.barWidth))
            }
        }
        .frame(width: Self.barWidth, height: Self.chartHeight)
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
