import DesignSystem
import HomeFeature
import NoctisCore
import RecoveryKit
import SwiftUI

/// A factor's page: its value today, a large chart of it over 14, 30 or 90
/// nights against your normal range (a scrub pill follows the finger; the
/// line morphs between ranges), what it is, its range and its part in
/// today's score, and how it's scored and why it counts. A page in a
/// navigation stack, not a sheet.
struct RecoveryFactorScreen: View {
    let viewModel: RecoveryViewModel
    let kind: RecoveryFactorKind
    let range: RecoveryFactorRange

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                if let content = viewModel.factor, content.kind == kind {
                    RecoveryFactorHeader(content: content, viewModel: viewModel)
                    RecoveryFactorChartCard(content: content, line: viewModel.model?.factor, tint: kind.tint)
                    if !content.tiles.isEmpty {
                        RecoveryFactorTiles(tiles: content.tiles)
                    }
                    ForEach(content.explanation, id: \.title) { block in
                        RecoveryExplanationCard(block: block)
                    }
                } else if viewModel.screen != nil {
                    Text("This factor isn't available right now.")
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink2)
                        .padding(NoctisSpacing.xl)
                } else {
                    RecoverySkeletonView(charts: true)
                }
            }
            .frame(maxWidth: RecoveryScreen.contentMaxWidth)
            .padding(.horizontal, NoctisSpacing.lg)
            .padding(.top, NoctisSpacing.xs)
            .padding(.bottom, NoctisSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        .navigationTitle(HomeScreenBuilder.shortName(kind))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.onAppear()
            viewModel.select(factor: kind, range: range)
        }
        .onDisappear {
            viewModel.onDisappear()
            viewModel.select(factor: nil, range: .fortnight)
        }
        .accessibilityIdentifier("recovery.factorScreen")
    }
}

/// Today's value, the baseline, the sentence, and the range toggle.
struct RecoveryFactorHeader: View {
    let content: RecoveryFactorContent
    let viewModel: RecoveryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                NoctisCaption("TODAY", style: .noctisInk3)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    NoctisMetric(content.value, size: 56, relativeTo: .title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let suffix = content.valueSuffix {
                        Text(suffix)
                            .noctisFont(22, .semibold, relativeTo: .body)
                            .foregroundStyle(.noctisInk2)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(content.name) \(content.value.spoken)\(content.valueSuffix.map { " \($0)" } ?? "")")
                Text(content.baseline)
                    .noctisFont(15, .medium, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(content.sentence)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, NoctisSpacing.xxs)
            Picker("Range", selection: rangeBinding) {
                ForEach(RecoveryFactorRange.allCases, id: \.self) { range in
                    Text(RecoveryFactorContent.rangeTitles[range] ?? "\(range.nights)").tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("recovery.factorRange")
        }
    }

    private var rangeBinding: Binding<RecoveryFactorRange> {
        Binding {
            content.range
        } set: { range in
            NoctisHaptics.snapLight()
            viewModel.select(factor: content.kind, range: range)
        }
    }
}

/// The large chart: the line, your normal range as a band, a dot for each
/// night up to 30, today's dot, and a scrub. Dragging sideways (or a tap)
/// picks a night; the pill says what it was.
struct RecoveryFactorChartCard: View {
    let content: RecoveryFactorContent
    let line: FactorLineRender?
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: Int?
    @State private var plotWidth: CGFloat = 0
    @NoctisScaledLength(relativeTo: .caption) private var axisWidth: CGFloat = 40

    static let height: CGFloat = 240
    static let outset = NoctisSpacing.lg + NoctisSpacing.lg

    private var count: Int { max(content.points.count, 1) }
    private var current: Int? { selected.flatMap { $0 < content.points.count ? $0 : nil } }
    private var morph: Animation { NoctisMotion.adaptive(NoctisMotion.flow, reduceMotion: reduceMotion) }

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    NoctisCaption("\(content.measure.uppercased()) · \(content.range.nights) NIGHTS", style: .noctisInk3)
                }
                RecoveryPillRow(
                    text: current.map { content.points[$0].detail },
                    fraction: current.map { (Double($0) + 0.5) / Double(count) } ?? 0.5
                )
                HStack(alignment: .top, spacing: 6) {
                    yAxis
                    VStack(spacing: 4) {
                        plot
                        xAxis
                    }
                }
                if let band = content.bandCaption {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(NoctisAppColor.track).frame(width: 14, height: 10)
                        Text(band)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(.noctisInk3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let note = content.emptyNote {
                    Text(note)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                }
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
        .accessibilityIdentifier("recovery.factorChart")
    }

    // MARK: Axes

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
        .animation(morph, value: content.range)
    }

    private var xAxis: some View {
        NoctisFractionLayout {
            ForEach(Array(content.xLabels.enumerated()), id: \.offset) { _, label in
                Text(label.text)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
                    .fixedSize()
                    .noctisFraction(label.position)
            }
        }
    }

    // MARK: Plot

    @ViewBuilder
    private var plot: some View {
        if let line {
            ZStack {
                ForEach(line.ticks, id: \.value) { tick in
                    NoctisVerticalSpanLayout(from: 1 - tick.position, to: 1 - tick.position, minimumLength: 1) {
                        Rectangle().fill(NoctisAppColor.hairline)
                    }
                }
                if let low = line.bandLow, let high = line.bandHigh {
                    NoctisVerticalSpanLayout(from: 1 - high, to: 1 - low, minimumLength: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(NoctisAppColor.track)
                    }
                }
                ColumnRule(count: count, index: current)
                    .stroke(NoctisAppColor.ink3.opacity(0.6), lineWidth: 1)
                FactorCurve(samples: line.curve, nights: line.values.count)
                    .stroke(NoctisAppColor.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if line.values.count <= 30 {
                    FactorDots(values: line.values, radius: 2.5)
                        .fill(NoctisAppColor.ink)
                        .transition(.opacity)
                }
                FactorMarker(values: line.values, index: line.todayIndex, radius: 5.5)
                    .fill(tint)
                    .overlay(FactorMarker(values: line.values, index: line.todayIndex, radius: 5.5).stroke(NoctisAppColor.ink, lineWidth: 1.5))
                FactorMarker(values: line.values, index: current, radius: 6.5)
                    .fill(NoctisAppColor.ink)
            }
            .frame(height: Self.height)
            .animation(morph, value: content.range)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { plotWidth = $0 }
            .columnScrub(count: content.points.count, chartWidth: plotWidth, outset: Self.outset, selected: $selected)
        } else {
            Color.clear.frame(height: Self.height)
        }
    }
}

/// Today, baseline, range and the part in today's score, two to a row.
struct RecoveryFactorTiles: View {
    let tiles: [RecoveryFactorTile]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: NoctisSpacing.sm, alignment: .top),
                GridItem(.flexible(), spacing: NoctisSpacing.sm, alignment: .top),
            ],
            spacing: NoctisSpacing.sm
        ) {
            ForEach(tiles) { tile in
                RecoveryFactorTileView(tile: tile)
            }
        }
        .accessibilityIdentifier("recovery.factorTiles")
    }
}

struct RecoveryFactorTileView: View {
    let tile: RecoveryFactorTile
    @NoctisScaledLength(relativeTo: .body) private var minHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.title)
                .noctisFont(13, .medium, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
            NoctisMetric(tile.value, size: 26)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let note = tile.note {
                Text(note)
                    .noctisFont(12, relativeTo: .caption)
                    .foregroundStyle(.noctisInk3)
            }
        }
        .padding(NoctisSpacing.md)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous)
                .fill(NoctisAppColor.surface)
                .overlay(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.title) \(tile.value.spoken)" + (tile.note.map { ", \($0)" } ?? ""))
    }
}

struct RecoveryExplanationCard: View {
    let block: RecoveryExplanationBlock

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption(block.title.uppercased(), style: .noctisInk3)
                Text(block.text)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
