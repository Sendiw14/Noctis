import DesignSystem
import HomeFeature
import NoctisCore
import ReviewKit
import SwiftUI

// The charts a review story draws, from the unit-space values `ReviewStoryBuilder` made (APP_RULES.md R63). They only place and draw what the page says, with system layouts,
// shapes and a canvas (R8: no absolute positioning). Flat fills. The week's bars are Home's and Sleep's own stage-stacked bar (2pt gaps, coreTint), and every chart has a
// spoken description so nothing depends on seeing it.

// MARK: - Shapes

/// A horizontal rule across a chart at a share of its height (0 = bottom).
nonisolated struct ReviewRule: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.minY + rect.height * (1 - min(max(fraction, 0), 1))
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        return path
    }
}

/// A smooth line through unit-space points (0 at the bottom, 1 at the top), one per column, `nil` where there is none: the line breaks there, and a lone point is a dot.
nonisolated struct ReviewSmoothLine: Shape {
    let points: [Double?]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var run: [CGPoint] = []
        for (index, value) in points.enumerated() {
            guard let value else {
                Self.add(run, to: &path)
                run = []
                continue
            }
            run.append(CGPoint(x: rect.minX + rect.width * (Double(index) + 0.5) / Double(max(points.count, 1)), y: rect.minY + rect.height * (1 - value)))
        }
        Self.add(run, to: &path)
        return path
    }

    private static func add(_ run: [CGPoint], to path: inout Path) {
        guard let first = run.first else { return }
        if run.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4))
            return
        }
        path.move(to: first)
        for index in 1..<run.count {
            let p0 = run[max(index - 2, 0)], p1 = run[index - 1], p2 = run[index], p3 = run[min(index + 1, run.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
    }
}

/// A dot on every recorded point of a `ReviewSmoothLine`.
nonisolated struct ReviewPointDots: Shape {
    let points: [Double?]
    var radius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, value) in points.enumerated() {
            guard let value else { continue }
            let center = CGPoint(x: rect.minX + rect.width * (Double(index) + 0.5) / Double(max(points.count, 1)), y: rect.minY + rect.height * (1 - value))
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}

// MARK: - Sleep bars

/// A week's seven stage-stacked bars (Home's `WeekBarStack`), or a month's slim ones, with the need line and, for a month, the average. Bars rise 40ms apart when `revealed`
/// turns true.
struct ReviewBarsChart: View {
    let page: ReviewBarsPage
    let revealed: Bool
    /// The share card's: shorter, with no keys under it.
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var weekHeight: CGFloat = 150

    private var height: CGFloat { compact ? 84 : (page.slim ? weekHeight * 0.8 : weekHeight) }

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: page.slim ? 2 : 0) {
                    ForEach(Array(page.bars.enumerated()), id: \.element.id) { index, bar in
                        column(bar, index: index)
                    }
                }
                ReviewRule(fraction: page.needFraction)
                    .stroke(NoctisAppColor.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                if let fraction = page.averageFraction {
                    ReviewRule(fraction: fraction).stroke(NoctisAppColor.ink2, style: StrokeStyle(lineWidth: 1.5))
                }
            }
            .frame(height: height)
            labels
            if !compact { keys }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([page.headline] + page.bars.map(\.spoken)).joined(separator: ". "))
    }

    @ViewBuilder
    private func column(_ bar: ReviewBar, index: Int) -> some View {
        Group {
            if let fraction = bar.fraction {
                let target = max(height * fraction, WeekColumns.cornerRadius * 2)
                let shown = revealed || reduceMotion ? target : 2
                if page.slim {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(bar.reachedNeed ? NoctisAppColor.sage : NoctisAppColor.coreTint)
                        .frame(height: shown)
                } else {
                    WeekBarStack(
                        stages: bar.stages.map { WeekBarStages(deep: $0.deep, core: $0.core, rem: $0.rem) }, height: shown,
                        fill: bar.reachedNeed ? NoctisAppColor.sage : NoctisAppColor.coreTint
                    )
                    .frame(maxWidth: 24)
                }
            } else {
                // A night with no sleep recorded: a dot on the baseline, never a bar.
                Circle().fill(NoctisAppColor.track).frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: height, alignment: .bottom)
        .animation(reduceMotion ? nil : NoctisMotion.draw(0.6).delay(0.04 * Double(index)), value: revealed)
    }

    private var labels: some View {
        HStack(spacing: page.slim ? 2 : 0) {
            ForEach(Array(page.bars.enumerated()), id: \.element.id) { index, bar in
                // A week labels every bar with its weekday; a month, every seventh day.
                Text(!page.slim || index % 7 == 0 ? bar.label : "")
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var keys: some View {
        HStack(spacing: NoctisSpacing.md) {
            HStack(spacing: 6) {
                ReviewRule(fraction: 0.5).stroke(NoctisAppColor.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(width: 16, height: 8)
                Text(page.needText).noctisFont(12, relativeTo: .caption).foregroundStyle(.noctisInk3)
            }
            if let average = page.averageText {
                HStack(spacing: 6) {
                    ReviewRule(fraction: 0.5).stroke(NoctisAppColor.ink2, style: StrokeStyle(lineWidth: 1.5)).frame(width: 16, height: 8)
                    Text(average).noctisFont(12, relativeTo: .caption).foregroundStyle(.noctisInk3)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Bedtime and wake time

private let bedtimeColor = NoctisAppColor.nightDeep
private let wakeColor = NoctisAppColor.orange

/// Bedtimes and wake times on one clock axis, with the band they usually fall in. A week is a row a night; a month is a column a night.
struct ReviewTimingChart: View {
    let page: ReviewTimingPage
    let revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            if page.rows.count <= 7 { rowsChart } else { columnsChart }
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.spoken)
        .onChange(of: revealed, initial: true) {
            withAnimation(reduceMotion ? nil : NoctisMotion.draw(0.9)) { progress = revealed ? 1 : 0 }
        }
    }

    private var rowsChart: some View {
        VStack(spacing: 6) {
            ForEach(Array(page.rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: NoctisSpacing.xs) {
                    Text(row.label)
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        // Capped with the chart's other ticks: the 16pt column cut "M" to "N" and "W" to "V" at AX3 and AX5.
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .frame(width: 16)
                    ZStack {
                        NoctisSpanLayout(from: page.bedtimeBand.start, to: page.bedtimeBand.end, minimumWidth: 8) { band }
                        NoctisSpanLayout(from: page.wakeBand.start, to: page.wakeBand.end, minimumWidth: 8) { band }
                        NoctisFractionLayout {
                            dot(bedtimeColor, index: index).noctisFraction(row.bedtime)
                            dot(wakeColor, index: index).noctisFraction(row.wake)
                        }
                    }
                    .frame(height: 20)
                }
            }
            HStack(spacing: NoctisSpacing.xs) {
                Color.clear.frame(width: 16, height: 1)
                NoctisFractionLayout {
                    ForEach(Array(page.ticks.enumerated()), id: \.offset) { _, tick in
                        Text(tick.label)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(.noctisInk3)
                            // "12:00 AM", "4:00 AM" and "8:00 AM" overprinted at AX3 ("12:00 AM4:00 AM8:00 AM"): the three fixed positions
                            // along a 280pt strip are the chart; the time is also in the sentence under it.
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .fixedSize()
                            .noctisFraction(tick.position)
                    }
                }
            }
        }
    }

    private var band: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(NoctisAppColor.track)
    }

    private func dot(_ color: Color, index: Int) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .opacity(revealed || reduceMotion ? 1 : 0)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.4)
            .animation(reduceMotion ? nil : NoctisMotion.draw(0.5).delay(0.04 * Double(index)), value: revealed)
    }

    /// A month: the nights are columns, the clock runs down, and the dots come in left to right.
    private var columnsChart: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.xs) {
            NoctisVerticalFractionLayout {
                ForEach(Array(page.ticks.enumerated()), id: \.offset) { _, tick in
                    Text(tick.label)
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .fixedSize()
                        .noctisVerticalFraction(tick.position)
                }
            }
            .frame(height: 170)
            ReviewTimingColumns(page: page, progress: progress)
                .frame(height: 170)
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoctisSpacing.md) { keys }
            VStack(alignment: .leading, spacing: 6) { keys }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var keys: some View {
        key(Circle().fill(bedtimeColor).frame(width: 10, height: 10), "Bedtime")
        key(Circle().fill(wakeColor).frame(width: 10, height: 10), "Wake time")
        key(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NoctisAppColor.track).frame(width: 14, height: 10), "Usual")
    }

    private func key(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 6) {
            mark
            Text(text).noctisFont(12, relativeTo: .caption).foregroundStyle(.noctisInk3)
        }
    }
}

/// A month's nights as columns of two dots, drawn on a canvas; `progress` brings them in left to right.
private struct ReviewTimingColumns: View, Animatable {
    let page: ReviewTimingPage
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            func band(_ band: ReviewBand) {
                let top = size.height * band.start
                let rect = CGRect(x: 0, y: top, width: size.width, height: max(size.height * (band.end - band.start), 6))
                context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(NoctisAppColor.track))
            }
            band(page.bedtimeBand)
            band(page.wakeBand)
            let count = max(page.rows.count, 1)
            let shown = Int((progress * Double(count)).rounded(.up))
            for (index, row) in page.rows.enumerated() where index < shown {
                let x = size.width * (Double(index) + 0.5) / Double(count)
                for (position, color) in [(row.bedtime, bedtimeColor), (row.wake, wakeColor)] {
                    let rect = CGRect(x: x - 3, y: size.height * position - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}

// MARK: - A line over the mornings

/// The recovery line (the history chart's style: a smooth line with its dots, a gap where a morning has no score) and its axis. It draws itself in once.
struct ReviewLineChart: View {
    let page: ReviewLinePage
    let revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 140

    var body: some View {
        HStack(alignment: .top, spacing: NoctisSpacing.xs) {
            NoctisVerticalFractionLayout {
                ForEach(Array(page.axis.enumerated()), id: \.offset) { _, tick in
                    Text(tick.label)
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize()
                        .noctisVerticalFraction(1 - tick.position)
                }
            }
            .frame(height: chartHeight)
            ZStack {
                ForEach(Array(page.axis.enumerated()), id: \.offset) { _, tick in
                    ReviewRule(fraction: tick.position).stroke(NoctisAppColor.hairline, lineWidth: 1)
                }
                ReviewSmoothLine(points: page.points)
                    .trim(from: 0, to: revealed || reduceMotion ? 1 : 0)
                    .stroke(NoctisAppColor.sectionLavender, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .animation(reduceMotion ? nil : NoctisMotion.draw(0.9), value: revealed)
                if page.points.count <= 10 {
                    ReviewPointDots(points: page.points)
                        .fill(NoctisAppColor.sectionLavender)
                        .opacity(revealed || reduceMotion ? 1 : 0)
                        .animation(reduceMotion ? nil : NoctisMotion.draw(0.5).delay(0.4), value: revealed)
                }
            }
            .frame(height: chartHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.spoken)
    }
}

/// An arrow for a direction: plain ink, never red or green.
struct ReviewArrowGlyph: View {
    let arrow: ReviewArrow
    var size: CGFloat = 17

    var body: some View {
        Image(systemName: symbol)
            .noctisIcon(size, .bold)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch arrow {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }
}
