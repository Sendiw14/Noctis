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

/// The recovery line on a card: a flat lavender .35 area under a cocoa
/// (ivory in Dark) line, your baseline dashed, your usual range a butter
/// band, and score dots colored by where they sit against it (sage above,
/// butter within, orange below; the number is always in the pill). 7D dots every day; 30D is the line; 90D is a 7-day smoothed
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

    /// Whole: the word does not break ("Recover / y" on an SE at AX5).
    private var legendWord: some View {
        Text("Recovery")
            .noctisFont(13, relativeTo: .footnote)
            .foregroundStyle(.noctisInk3)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                // Side by side when they fit; the word under the date range when the range would wrap beside it ("SEP 13 / - OCT / 12" in a
                // third of an SE at AX5, with a gap of white under it).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        NoctisCaption(content.caption, style: .noctisInk3)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: NoctisSpacing.xs)
                        legendWord
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        NoctisCaption(content.caption, style: .noctisInk3)
                            .fixedSize(horizontal: false, vertical: true)
                        legendWord
                    }
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
        .accessibilityChartDescriptor(NoctisAudioGraph(
            title: content.accessibilityLabel, summary: "One point a day, its recovery score from 0 to 100. Swipe up or down on the chart to go through the days.",
            xTitle: "Day", yTitle: "Recovery score",
            points: content.points.enumerated().map { index, point in NoctisGraphPoint(x: "Day \(index + 1)", y: point.score.map(Double.init), spoken: point.accessibilityLabel) },
            yRange: 0...100, yDescription: { "score \(Int($0.rounded()))" }
        ))
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
                    .lineLimit(1)
                    .frame(width: axisWidth, alignment: .trailing)
                    .noctisVerticalFraction(label.position)
            }
        }
        .frame(width: axisWidth, height: Self.height)
        // The axis ticks stop growing at a large standard size: the chart is a fixed height, and at AX5 "100" was cut to "10" over "75" and the
        // date labels overprinted each other ("Sep 13 Sep 28 Oct 12" became one smear). The values are also in the pill and in the stat tiles.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.noctisUsualBand)
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
                    .fill(NoctisAppColor.lavender.opacity(0.35))
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
                    ForEach([RecoveryUsualPosition?.some(.above), .some(.within), .some(.below), nil], id: \.self) { position in
                        scoreDots(chart.line, position: position, radius: 3.5)
                            .opacity(drawn)
                            .animation(land, value: reveal)
                    }
                }
                if content.isSmoothed, let today = chart.todayIndex {
                    ColumnSpan(count: count, index: today, from: chart.smoothed[today], to: chart.line[today])
                        .stroke(NoctisAppColor.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(height: Self.height)
                        .opacity(drawn)
                        .animation(land, value: reveal)
                }
                todayDot(chart)
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

    /// The score color for where a day sits against the usual range.
    private func tint(_ position: RecoveryUsualPosition?) -> Color {
        switch position {
        case .above: NoctisAppColor.sage
        case .within: NoctisAppColor.butter
        case .below: NoctisAppColor.orange
        case nil: NoctisAppColor.ink3
        }
    }

    /// The days at one position, as dots with a thin ink edge so a butter or
    /// sage dot holds on the lavender area.
    private func scoreDots(_ line: [Double?], position: RecoveryUsualPosition?, radius: CGFloat) -> some View {
        let values: [Double?] = zip(line, content.points).map { $1.position == position ? $0 : nil }
        return FactorDots(values: values, radius: radius)
            .fill(tint(position))
            .overlay(FactorDots(values: values, radius: radius).stroke(NoctisAppColor.ink, lineWidth: 1.25))
            .frame(height: Self.height)
    }

    /// Today's dot, larger, in its own position's color.
    private func todayDot(_ chart: RecoveryChartRender) -> some View {
        let position = chart.todayIndex.flatMap { content.points.indices.contains($0) ? content.points[$0].position : nil }
        return FactorMarker(values: chart.line, index: chart.todayIndex, radius: 5.5)
            .fill(tint(position))
            .overlay(FactorMarker(values: chart.line, index: chart.todayIndex, radius: 5.5).stroke(NoctisAppColor.ink, lineWidth: 2))
            .frame(height: Self.height)
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
        VStack(alignment: .leading, spacing: 6) {
            RecoveryLegend {
                if content.bandCaption != nil {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.noctisUsualBand).frame(width: 14, height: 10)
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
            if content.bandCaption != nil {
                RecoveryLegend {
                    ForEach([RecoveryUsualPosition.above, .within, .below], id: \.self) { position in
                        HStack(spacing: 6) {
                            Circle().fill(tint(position)).overlay(Circle().strokeBorder(NoctisAppColor.ink, lineWidth: 1.25)).frame(width: 10, height: 10)
                            Text(position.word)
                                .noctisFont(13, relativeTo: .footnote)
                                .foregroundStyle(.noctisInk3)
                        }
                    }
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
    @Environment(\.featureGate) private var gate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let sparkHeight: CGFloat = 36

    private var name: some View {
        Text(row.name)
            .noctisFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(NoctisAppColor.ink)
    }

    @ViewBuilder
    private var average: some View {
        if let average = row.average {
            Text("avg")
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
            NoctisMetric(average, size: 17, relativeTo: .body)
        }
    }

    @ViewBuilder
    private var trailingGlyph: some View {
        if gate.isUnlocked(.recoveryFactorDetail) {
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.noctisInk3)
                .accessibilityHidden(true)
        } else {
            LockGlyph(size: 13).foregroundStyle(.noctisInk3)
        }
    }

    /// At accessibility sizes: the tile and the chevron on one line, the name under them on a line of its own and whole (scaled down to fit its
    /// word, never below half), the average under that. Beside a tile and a chevron "Consistency" had 110pt and broke ("Consiste / ncy").
    private var accessibilityHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                NoctisIconTile(systemImage: row.kind.symbol, fill: row.kind.tint, foreground: NoctisAppColor.onFill, size: 40)
                Spacer(minLength: NoctisSpacing.xs)
                trailingGlyph
            }
            name.lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 4) { average }
        }
    }

    @ViewBuilder
    private func header(stacked: Bool) -> some View {
        HStack(alignment: .center, spacing: NoctisSpacing.sm) {
            NoctisIconTile(systemImage: row.kind.symbol, fill: row.kind.tint, foreground: NoctisAppColor.onFill, size: 40)
            if stacked {
                VStack(alignment: .leading, spacing: 2) {
                    name.fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) { average }
                }
                Spacer(minLength: NoctisSpacing.xs)
            } else {
                name.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: NoctisSpacing.xs)
                average
            }
            trailingGlyph
        }
    }

    var body: some View {
        Button {
            NoctisHaptics.light()
            open()
        } label: {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                    // The name stays on one line, whole: when it and the average do not both fit (the iPhone SE's width, an accessibility
                    // text size), the average goes under the name instead of the name breaking inside a word (QA_LEDGER.md).
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibilityHeader
                    } else {
                        ViewThatFits(in: .horizontal) {
                            header(stacked: false)
                            header(stacked: true)
                        }
                    }
                    if let line {
                        ZStack {
                            if let low = line.bandLow, let high = line.bandHigh {
                                NoctisVerticalSpanLayout(from: 1 - high, to: 1 - low, minimumLength: 3) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(row.kind.tint.opacity(0.16))
                                }
                            }
                            FactorCurve(samples: line.curve, nights: line.values.count)
                                .stroke(row.kind.lineTint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
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
        .accessibilityHint(gate.isUnlocked(.recoveryFactorDetail) ? "Opens the details." : "Premium. Opens what Premium includes.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("recovery.historyFactor.\(row.kind.rawValue)")
    }
}
