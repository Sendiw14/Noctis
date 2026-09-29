import DesignSystem
import HomeFeature
import NoctisCore
import RecoveryKit
import SwiftUI

/// 7D, 30D or 90D: the recovery line against your usual, the stats of the
/// window, how many days were in your usual range, and a row per factor.
struct RecoveryHistoryView: View {
    let history: RecoveryHistoryContent
    let viewModel: RecoveryViewModel
    let openFactor: (RecoveryFactorKind, RecoveryFactorRange) -> Void

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            RecoveryHistoryChartCard(content: history, chart: viewModel.model?.chart, reveal: viewModel.reveal)
            if !history.tiles.isEmpty {
                RecoveryHistoryTiles(tiles: history.tiles)
            }
            if let line = history.usualLine {
                Text(line)
                    .noctisFont(15, .medium, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NoctisSpacing.xxs)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recovery.usualLine")
            }
            VStack(spacing: NoctisSpacing.sm) {
                ForEach(history.factorRows) { row in
                    RecoveryHistoryFactorRowView(row: row, line: viewModel.model?.factorRow(row.kind)) {
                        openFactor(row.kind, row.factorRange)
                    }
                }
            }
        }
    }
}

// MARK: - Chart

/// The recovery line on a card: a flat .10 area under a cocoa (ivory in
/// Dark) line, your baseline dashed, your usual range shaded, today a
/// filled dot. 7D dots every day; 30D is the line; 90D is a 7-day smoothed
/// line with each week's average. Dragging sideways (or a tap) picks a day
/// and the pill says what it was; the line draws in on the day's first
/// visit.
struct RecoveryHistoryChartCard: View {
    let content: RecoveryHistoryContent
    let chart: RecoveryChartRender?
    let reveal: HomeRevealPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Int?
    @State private var plotWidth: CGFloat = 0
    @NoctisScaledLength(relativeTo: .caption) private var axisWidth: CGFloat = 32

    static let height: CGFloat = 220
    static let outset = NoctisSpacing.lg + NoctisSpacing.lg

    private var count: Int { max(content.points.count, 1) }
    private var current: Int? { selected.flatMap { $0 < content.points.count ? $0 : nil } }
    private var drawn: Double { reveal.holdsStart ? 0 : 1 }
    private var draw: Animation? { reduceMotion ? nil : NoctisMotion.draw(HomeReveal.ringDuration).delay(0.1) }
    /// The dots arrive as the line reaches them, not before; a skipped
    /// reveal (which is no longer playing) shows them at once.
    private var land: Animation? {
        guard !reduceMotion else { return nil }
        return reveal == .playing ? NoctisMotion.fade.delay(HomeReveal.ringDuration * 0.75) : NoctisMotion.fade
    }

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    NoctisCaption(content.caption, style: .noctisInk3)
                    Spacer(minLength: NoctisSpacing.xs)
                    Text("Recovery")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                }
                RecoveryPillRow(
                    text: current.map { content.points[$0].detail },
                    fraction: current.map { (Double($0) + 0.5) / Double(count) } ?? 0.5,
                    resting: content.partialNote
                )
                HStack(alignment: .top, spacing: 6) {
                    yAxis
                    VStack(spacing: 4) {
                        plot
                        xAxis
                    }
                }
                legend
            }
        }
        .onChange(of: content.range) { _, _ in selected = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityValue(current.map { content.points[$0].accessibilityLabel } ?? "")
        .accessibilityHint("Swipe up or down to go through the nights.")
        .accessibilityAdjustableAction { direction in
            let last = content.points.count - 1
            switch direction {
            case .increment: selected = min((current ?? -1) + 1, last)
            case .decrement: selected = max((current ?? last + 1) - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("recovery.historyChart")
    }

    private var yAxis: some View {
        NoctisVerticalFractionLayout {
            ForEach(Array(content.yLabels.enumerated()), id: \.offset) { _, label in
                Text(label.text)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
                    .frame(width: axisWidth, alignment: .trailing)
                    .noctisVerticalFraction(label.position)
            }
        }
        .frame(width: axisWidth, height: Self.height)
    }

    private var xAxis: some View {
        NoctisFractionLayout {
            ForEach(Array(content.xLabels.enumerated()), id: \.offset) { _, label in
                Text(label.text)
                    .noctisFont(12, content.showsDots ? .medium : .regular, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
                    .fixedSize()
                    .noctisFraction(label.position)
            }
        }
        .frame(minHeight: 16)
    }

    // MARK: Plot

    @ViewBuilder
    private var plot: some View {
        if let chart {
            let line = content.isSmoothed ? chart.smoothed : chart.line
            ZStack(alignment: .bottom) {
                grid
                if let low = chart.bandLow, let high = chart.bandHigh {
                    NoctisVerticalSpanLayout(from: 1 - high, to: 1 - low, minimumLength: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(NoctisAppColor.track)
                    }
                    .frame(height: Self.height)
                }
                if let baseline = chart.baseline {
                    RecoveryDashedRule()
                        .stroke(NoctisAppColor.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(height: 1.5)
                        .padding(.bottom, Self.height * baseline - 0.75)
                }
                ColumnRule(count: count, index: current)
                    .stroke(NoctisAppColor.ink3.opacity(0.6), lineWidth: 1)
                    .frame(height: Self.height)
                SeriesLine(values: line, area: true)
                    .fill(NoctisAppColor.ink.opacity(0.10))
                    .frame(height: Self.height)
                    // The area appears with the line, left to right.
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: max(drawn, 0.0001), y: 1, anchor: .leading)
                    }
                    .animation(draw, value: reveal)
                SeriesLine(values: line)
                    .trim(from: 0, to: max(drawn, 0.0001))
                    .stroke(NoctisAppColor.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(height: Self.height)
                    .animation(draw, value: reveal)
                if content.isSmoothed {
                    ForEach(chart.weeks, id: \.start) { week in
                        if let fraction = week.fraction {
                            NoctisSpanLayout(from: Double(week.start) / Double(count), to: Double(week.end) / Double(count)) {
                                Capsule().fill(NoctisAppColor.ink.opacity(0.75)).frame(height: 1.5)
                            }
                            .frame(height: 1.5)
                            .padding(.bottom, Self.height * fraction - 0.75)
                            .opacity(drawn)
                            .animation(land, value: reveal)
                        }
                    }
                }
                if content.showsDots {
                    FactorDots(values: chart.line, radius: 3)
                        .fill(NoctisAppColor.ink)
                        .frame(height: Self.height)
                        .opacity(drawn)
                        .animation(land, value: reveal)
                }
                if content.isSmoothed, let today = chart.todayIndex {
                    ColumnSpan(count: count, index: today, from: chart.smoothed[today], to: chart.line[today])
                        .stroke(NoctisAppColor.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(height: Self.height)
                        .opacity(drawn)
                        .animation(land, value: reveal)
                }
                FactorMarker(values: chart.line, index: chart.todayIndex, radius: 5.5)
                    .fill(NoctisAppColor.ink)
                    .frame(height: Self.height)
                    .opacity(drawn)
                    .animation(land, value: reveal)
                FactorMarker(values: chart.line, index: current, radius: 6.5)
                    .stroke(NoctisAppColor.ink, lineWidth: 2)
                    .background(FactorMarker(values: chart.line, index: current, radius: 6.5).fill(NoctisAppColor.surface))
                    .frame(height: Self.height)
            }
            .frame(height: Self.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { plotWidth = $0 }
            .columnScrub(count: content.points.count, chartWidth: plotWidth, outset: Self.outset, selected: $selected)
        } else {
            Color.clear.frame(height: Self.height)
        }
    }

    private var grid: some View {
        ZStack {
            ForEach(content.yLabels, id: \.position) { label in
                NoctisVerticalSpanLayout(from: label.position, to: label.position, minimumLength: 1) {
                    Rectangle().fill(NoctisAppColor.hairline)
                }
            }
        }
        .frame(height: Self.height)
    }

    private var legend: some View {
        RecoveryLegend {
            if content.bandCaption != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NoctisAppColor.track).frame(width: 14, height: 10)
                    Text("Your usual range")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                }
                HStack(spacing: 6) {
                    RecoveryDashedRule()
                        .stroke(NoctisAppColor.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 16, height: 1.5)
                    Text("Baseline")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                }
            }
            if content.isSmoothed {
                HStack(spacing: 6) {
                    Capsule().fill(NoctisAppColor.ink.opacity(0.75)).frame(width: 12, height: 2)
                    Text("Weekly average")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                }
            }
        }
    }
}

// MARK: - Stats

/// Current, Average, Baseline, High, Low and Trend, two to a row.
struct RecoveryHistoryTiles: View {
    let tiles: [RecoveryHistoryTile]

    /// Two to a row.
    private var rows: [[RecoveryHistoryTile]] {
        stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
    }

    /// One lavender block, the six tiles separated by cocoa .12 lines. The
    /// tiles carry 12pt of padding of their own, so the stack reaches that
    /// far into the block's padding and their text lines up with the
    /// block's other content.
    var body: some View {
        NoctisColorBlock(fill: NoctisAppColor.blockLavender) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, pair in
                    if index > 0 {
                        NoctisBlockRule(.horizontal)
                    }
                    HStack(alignment: .top, spacing: 0) {
                        RecoveryHistoryTileView(tile: pair[0])
                        NoctisBlockRule(.vertical)
                        if pair.count > 1 {
                            RecoveryHistoryTileView(tile: pair[1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, -NoctisSpacing.sm)
        }
        .accessibilityIdentifier("recovery.stats")
    }
}

struct RecoveryHistoryTileView: View {
    let tile: RecoveryHistoryTile
    @NoctisScaledLength(relativeTo: .body) private var minHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.title)
                .noctisFont(13, .medium, relativeTo: .footnote)
                .foregroundStyle(.noctisFieldInk2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                NoctisMetric(tile.value, size: 32, tone: .block)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let symbol = tile.symbol {
                    // Never a warning color: the arrow is ink like the number.
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.noctisFieldInk)
                        .accessibilityHidden(true)
                }
            }
            if let note = tile.note {
                Text(note)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisFieldInk2)
            }
        }
        .padding(.horizontal, NoctisSpacing.sm)
        .padding(.vertical, NoctisSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel + (tile.note.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("recovery.stat.\(tile.id)")
    }
}

// MARK: - Factor rows

/// A factor over the range: its dot and name, its average, and a small
/// line against its normal band. The whole row opens that factor's page.
struct RecoveryHistoryFactorRowView: View {
    let row: RecoveryHistoryFactorRow
    let line: FactorLineRender?
    let open: () -> Void

    static let sparkHeight: CGFloat = 36

    var body: some View {
        Button {
            NoctisHaptics.light()
            open()
        } label: {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    HStack(alignment: .center, spacing: NoctisSpacing.sm) {
                        NoctisIconTile(systemImage: row.kind.symbol, fill: row.kind.tint, foreground: NoctisAppColor.onFill, size: 40)
                        Text(row.name)
                            .noctisFont(15, .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink)
                        Spacer(minLength: NoctisSpacing.xs)
                        if let average = row.average {
                            Text("avg")
                                .noctisFont(13, relativeTo: .footnote)
                                .foregroundStyle(.noctisInk3)
                            NoctisMetric(average, size: 17, relativeTo: .body)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.noctisInk3)
                            .accessibilityHidden(true)
                    }
                    if let line {
                        ZStack {
                            if let low = line.bandLow, let high = line.bandHigh {
                                NoctisVerticalSpanLayout(from: 1 - high, to: 1 - low, minimumLength: 3) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NoctisAppColor.track)
                                }
                            }
                            FactorCurve(samples: line.curve, nights: line.values.count)
                                .stroke(NoctisAppColor.ink3, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            FactorMarker(values: line.values, index: line.todayIndex, radius: 3.5)
                                .fill(row.kind.tint)
                        }
                        .frame(height: Self.sparkHeight)
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityHint("Opens the details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("recovery.historyFactor.\(row.kind.rawValue)")
    }
}
