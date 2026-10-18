import DesignSystem
import HomeFeature
import SwiftUI

/// Where a chart is drawn, and how much of it.
public enum InsightChartStyle: Sendable, Equatable {
    /// The featured story's simplified chart, on the cocoa block.
    case featured
    /// The detail page's full-width chart, on the paper, with its axes.
    case detail
}

/// The colors a chart draws with, on the cocoa block or on the paper.
struct InsightChartPalette {
    let primary: Color
    let secondary: Color
    let band: Color
    let label: Color
    let grid: Color
    /// A point that stayed within its usual.
    let within: Color
    /// A point outside it.
    let outside: Color

    /// Butter on cocoa, ivory for everything else.
    static let featured = InsightChartPalette(
        primary: NoctisAppColor.butter, secondary: NoctisPaper.bg.opacity(0.55), band: NoctisPaper.bg.opacity(0.16),
        label: NoctisPaper.bg.opacity(0.75), grid: NoctisPaper.bg.opacity(0.14), within: NoctisAppColor.butter, outside: NoctisPaper.bg.opacity(0.4)
    )

    static let detail = InsightChartPalette(
        primary: NoctisAppColor.ink, secondary: NoctisAppColor.ink3, band: NoctisAppColor.butter.opacity(0.28),
        label: NoctisAppColor.ink2, grid: NoctisAppColor.hairline, within: NoctisAppColor.sage, outside: NoctisAppColor.orange
    )

    static func of(_ style: InsightChartStyle) -> InsightChartPalette { style == .featured ? .featured : .detail }
}

/// One chart, drawn from its unit-space content.
public struct InsightChartView: View {
    let content: InsightChartData
    let style: InsightChartStyle

    public init(content: InsightChartData, style: InsightChartStyle) {
        self.content = content
        self.style = style
    }

    public var body: some View {
        Group {
            switch content {
            case .bars(let chart): InsightBarsView(chart: chart, style: style)
            case .timeline(let chart): InsightTimelineView(chart: chart, style: style)
            case .dots(let chart): InsightDotsView(chart: chart, style: style)
            case .line(let chart): InsightLineView(chart: chart, style: style)
            case .groups(let chart): InsightGroupsView(chart: chart, style: style)
            }
        }
        // The card says it in words; the chart is a drawing of the same numbers.
        .accessibilityHidden(true)
    }
}

// MARK: - Bars

struct InsightBarsView: View {
    let chart: InsightBarsChart
    let style: InsightChartStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var palette: InsightChartPalette { .of(style) }

    var body: some View {
        if chart.bars.count <= 3 {
            rows
        } else {
            columns
        }
    }

    /// Two or three bars: a row each, label, bar and value. At accessibility sizes the label and value share a line and the bar sits under
    /// them, full width: in one row a 96pt label column and a value column left the bar 40pt and cut both words ("Last ni…", "6h 4…" at AX3).
    private var rows: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            ForEach(Array(chart.bars.enumerated()), id: \.offset) { _, bar in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            label(bar)
                            Spacer(minLength: NoctisSpacing.xs)
                            value(bar)
                        }
                        track(bar)
                    }
                } else {
                    HStack(spacing: NoctisSpacing.sm) {
                        label(bar)
                            .frame(width: style == .featured ? 76 : 96, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        track(bar)
                        value(bar)
                            .frame(minWidth: 52, alignment: .trailing)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func label(_ bar: InsightChartBar) -> some View {
        Text(bar.label)
            .noctisFont(13, .medium, relativeTo: .footnote)
            .foregroundStyle(palette.label)
    }

    private func value(_ bar: InsightChartBar) -> some View {
        Text(bar.valueText)
            .noctisFont(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(palette.label)
            .monospacedDigit()
    }

    private func track(_ bar: InsightChartBar) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(bar.emphasized ? palette.primary : palette.secondary.opacity(0.6))
                .frame(width: max(proxy.size.width * bar.fraction, 6), height: style == .featured ? 14 : 22)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: style == .featured ? 18 : 26)
    }

    /// A week of nights: a column each, with the need as a line across.
    private var columns: some View {
        let height: CGFloat = style == .featured ? 64 : 150
        return VStack(spacing: NoctisSpacing.xxs) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(chart.bars.enumerated()), id: \.offset) { _, bar in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(color(bar))
                            .frame(height: max(height * bar.fraction, bar.fraction > 0 ? 6 : 2))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: height, alignment: .bottom)
                if let reference = chart.reference {
                    Rectangle()
                        .fill(palette.label.opacity(0.6))
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .offset(y: -height * reference.position)
                        .overlay(alignment: .topTrailing) {
                            if style == .detail {
                                Text(reference.label)
                                    .noctisFont(12, .medium, relativeTo: .caption)
                                    .foregroundStyle(palette.label)
                                    .offset(y: -height * reference.position - 18)
                            }
                        }
                }
            }
            .frame(height: height)
            HStack(spacing: 6) {
                ForEach(Array(chart.bars.enumerated()), id: \.offset) { _, bar in
                    Text(bar.label)
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(palette.label)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func color(_ bar: InsightChartBar) -> Color {
        switch bar.reachesReference {
        case true?: style == .featured ? palette.primary : NoctisAppColor.sage
        case false?: style == .featured ? palette.secondary : NoctisAppColor.butter
        case nil: bar.emphasized ? palette.primary : palette.secondary.opacity(0.6)
        }
    }
}

// MARK: - Timeline

struct InsightTimelineView: View {
    let chart: InsightTimelineChart
    let style: InsightChartStyle
    private var palette: InsightChartPalette { .of(style) }

    var body: some View {
        let height: CGFloat = style == .featured ? 64 : 84
        VStack(spacing: NoctisSpacing.xxs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let axisY = height - 14
                ZStack(alignment: .topLeading) {
                    // The usual, as a band along the axis.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.band)
                        .frame(width: max(width * (chart.band.upperBound - chart.band.lowerBound), 6), height: 28)
                        .offset(x: width * chart.band.lowerBound, y: axisY - 14)
                    Rectangle()
                        .fill(palette.grid)
                        .frame(width: width, height: 2)
                        .offset(y: axisY - 1)
                    ForEach(Array(chart.ticks.enumerated()), id: \.offset) { _, tick in
                        Rectangle()
                            .fill(palette.grid)
                            .frame(width: 2, height: 10)
                            .offset(x: width * tick.position - 1, y: axisY - 5)
                    }
                    ForEach(Array(chart.marks.enumerated()), id: \.offset) { _, mark in
                        markView(mark)
                            .fixedSize()
                            .position(x: min(max(width * mark.position, 32), width - 32), y: axisY - (mark.emphasized ? 30 : 30))
                        Circle()
                            .fill(mark.emphasized ? palette.primary : palette.secondary)
                            .frame(width: mark.emphasized ? 14 : 10, height: mark.emphasized ? 14 : 10)
                            .position(x: width * mark.position, y: axisY)
                    }
                }
            }
            .frame(height: height)
            ZStack(alignment: .topLeading) {
                GeometryReader { proxy in
                    ForEach(Array(chart.ticks.enumerated()), id: \.offset) { _, tick in
                        Text(tick.label)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(palette.label)
                            .fixedSize()
                            .position(x: proxy.size.width * tick.position, y: 8)
                    }
                }
            }
            .frame(height: 16)
            if style == .detail {
                Text(chart.bandLabel)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(palette.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func markView(_ mark: InsightMark) -> some View {
        VStack(spacing: 0) {
            Text(mark.timeText)
                .noctisFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(mark.emphasized ? palette.primary : palette.label)
                .lineLimit(1)
            if style == .detail {
                Text(mark.label)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Dots

struct InsightDotsView: View {
    let chart: InsightDotsChart
    let style: InsightChartStyle
    private var palette: InsightChartPalette { .of(style) }

    var body: some View {
        let size: CGFloat = style == .featured ? 12 : 16
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            HStack(spacing: 0) {
                ForEach(Array(chart.dots.enumerated()), id: \.offset) { _, dot in
                    VStack(spacing: 4) {
                        dotShape(dot, size: size)
                        if style == .detail {
                            Text(dot.label)
                                .noctisFont(12, relativeTo: .caption)
                                .foregroundStyle(palette.label)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(chart.caption)
                .noctisFont(12, relativeTo: .caption)
                .foregroundStyle(palette.label)
        }
    }

    @ViewBuilder
    private func dotShape(_ dot: InsightDot, size: CGFloat) -> some View {
        switch dot.within {
        case true?:
            Circle().fill(palette.within).frame(width: size, height: size)
        case false?:
            Circle().strokeBorder(palette.outside, lineWidth: 2).frame(width: size, height: size)
        case nil:
            Circle().fill(palette.secondary.opacity(0.25)).frame(width: size * 0.5, height: size * 0.5).frame(width: size, height: size)
        }
    }
}

// MARK: - Line

/// The points of a series as a polyline over the unit square.
nonisolated struct InsightPolyline: Shape {
    let points: [InsightPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let position = CGPoint(x: rect.minX + rect.width * point.x, y: rect.maxY - rect.height * point.y)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        return path
    }
}

struct InsightLineView: View {
    let chart: InsightLineChart
    let style: InsightChartStyle
    private var palette: InsightChartPalette { .of(style) }

    var body: some View {
        let height: CGFloat = style == .featured ? 76 : 170
        HStack(alignment: .top, spacing: NoctisSpacing.xs) {
            if style == .detail {
                ZStack(alignment: .trailing) {
                    ForEach(Array(chart.yTicks.enumerated()), id: \.offset) { _, tick in
                        Text(tick.label)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(palette.label)
                            .monospacedDigit()
                            .position(x: 16, y: height * (1 - tick.position))
                    }
                }
                .frame(width: 34, height: height)
            }
            VStack(spacing: NoctisSpacing.xxs) {
                plot(height: height)
                if style == .detail, !chart.xTicks.isEmpty {
                    GeometryReader { proxy in
                        ForEach(Array(chart.xTicks.enumerated()), id: \.offset) { _, tick in
                            Text(tick.label)
                                .noctisFont(12, relativeTo: .caption)
                                .foregroundStyle(palette.label)
                                .fixedSize()
                                .position(x: min(max(proxy.size.width * tick.position, 22), proxy.size.width - 22), y: 8)
                        }
                    }
                    .frame(height: 16)
                }
                if style == .detail {
                    legend
                }
            }
        }
    }

    private func plot(height: CGFloat) -> some View {
        ZStack {
            if style == .detail {
                GeometryReader { proxy in
                    ForEach(Array(chart.yTicks.enumerated()), id: \.offset) { _, tick in
                        Rectangle()
                            .fill(palette.grid)
                            .frame(height: 1)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * (1 - tick.position))
                    }
                }
            }
            if let band = chart.band {
                Rectangle()
                    .fill(palette.band)
                    .frame(height: max(height * (band.upperBound - band.lowerBound), 2))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: -height * band.lowerBound)
            }
            if let divider = chart.divider {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(palette.grid)
                        .frame(width: 1.5)
                        .position(x: proxy.size.width * divider, y: proxy.size.height / 2)
                }
            }
            ForEach(Array(chart.segments.enumerated()), id: \.offset) { _, segment in
                InsightPolyline(points: segment)
                    .stroke(palette.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            InsightPolyline(points: chart.rolling)
                .stroke(palette.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            GeometryReader { proxy in
                ForEach(Array(chart.segments.flatMap { $0 }.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(point == chart.latest ? palette.primary : palette.secondary)
                        .frame(width: point == chart.latest ? 10 : 5, height: point == chart.latest ? 10 : 5)
                        .position(x: proxy.size.width * point.x, y: proxy.size.height * (1 - point.y))
                }
            }
        }
        .frame(height: height)
    }

    private var legend: some View {
        HStack(spacing: NoctisSpacing.md) {
            HStack(spacing: 6) {
                Capsule().fill(palette.primary).frame(width: 16, height: 3)
                Text(chart.rollingLabel).noctisFont(12, relativeTo: .caption).foregroundStyle(palette.label)
            }
            if let label = chart.bandLabel {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(palette.band).frame(width: 16, height: 10)
                    Text(label).noctisFont(12, relativeTo: .caption).foregroundStyle(palette.label)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Groups

struct InsightGroupsView: View {
    let chart: InsightGroupsChart
    let style: InsightChartStyle
    private var palette: InsightChartPalette { .of(style) }

    var body: some View {
        let height: CGFloat = style == .featured ? 84 : 190
        HStack(alignment: .top, spacing: NoctisSpacing.xs) {
            if style == .detail {
                ZStack(alignment: .trailing) {
                    ForEach(Array(chart.yTicks.enumerated()), id: \.offset) { _, tick in
                        Text(tick.label)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(palette.label)
                            .monospacedDigit()
                            .position(x: 16, y: height * (1 - tick.position))
                    }
                }
                .frame(width: 34, height: height)
            }
            HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                ForEach(Array(chart.groups.enumerated()), id: \.offset) { index, group in
                    column(group, primary: index == 0, height: height)
                }
            }
        }
    }

    private func column(_ group: InsightDotGroup, primary: Bool, height: CGFloat) -> some View {
        VStack(spacing: NoctisSpacing.xxs) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.band.opacity(style == .featured ? 0.6 : 0.5))
                    ForEach(Array(group.dots.enumerated()), id: \.offset) { _, dot in
                        Circle()
                            .fill(primary ? palette.primary : palette.secondary)
                            .frame(width: style == .featured ? 6 : 8, height: style == .featured ? 6 : 8)
                            .position(x: proxy.size.width * dot.x, y: proxy.size.height * (1 - dot.y))
                    }
                    Rectangle()
                        .fill(primary ? palette.primary : palette.label)
                        .frame(height: 2.5)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * (1 - group.meanY))
                }
            }
            .frame(height: height)
            Text(group.label)
                .noctisFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(group.countText) · \(group.meanText)")
                .noctisFont(12, relativeTo: .caption)
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
