import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

/// Sleep, Week and Month. One `SleepBarsCard` serves both, so switching
/// the segmented control regroups the same bars (a night keeps its bar and
/// the bars around it come and go) instead of rebuilding the chart.
struct SleepRangeView: View {
    let screen: SleepScreen
    let viewModel: SleepViewModel

    var body: some View {
        VStack(spacing: NoctisSpacing.md) {
            if let bars = screen.bars {
                SleepBarsCard(content: bars, range: screen.selection.range, month: screen.month)
            }
            if screen.selection.range == .week, let insights = screen.insights {
                if let consistency = insights.consistency {
                    SleepConsistencyCard(content: consistency) { viewModel.detail = .consistency }
                }
                SleepBalanceCard(content: insights.balance) { viewModel.detail = .balance }
                SleepTimingCard(content: insights.timing) { viewModel.detail = .timing }
            }
            if let month = screen.month {
                SleepRhythmCard(content: month.rhythm) { viewModel.detail = .timing }
                SleepQualityStripCard(content: month.quality)
            }
        }
    }
}

// MARK: - Bars

/// A card of one bar per night: a week's, split into Deep, Core and REM
/// (each 220pt tall and fully saturated), or a month's, thirty slim solid
/// ones with a thin average over each run of seven nights. An orange
/// dashed line marks the need; nights with nothing recorded are an empty
/// track, never a zero-height bar.
///
/// One drag gesture over the whole chart picks the night nearest the
/// finger (a snap haptic at each), the others dim to 45%, and a pill in
/// its own row above the bars says what the night was. The last selection
/// stays until it's tapped again.
struct SleepBarsCard: View {
    let content: SleepBarsContent
    let range: SleepRange
    let month: SleepMonthContent?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Int?
    @State private var chartWidth: CGFloat = 0
    @NoctisScaledLength(relativeTo: .footnote) private var labelRowHeight: CGFloat = 24

    static let chartHeight: CGFloat = 220

    private var isWeek: Bool { range == .week }
    private var count: Int { max(content.bars.count, 1) }
    /// The selection, if the bars still reach it (a switch can shorten them).
    private var current: Int? { selected.flatMap { $0 < content.bars.count ? $0 : nil } }
    private var radius: CGFloat { isWeek ? WeekColumns.cornerRadius : 3 }
    private var barWidth: CGFloat {
        isWeek
            ? WeekColumns.barWidth(barsWidth: chartWidth, count: count)
            : max(WeekColumns.width(barsWidth: chartWidth, count: count) - 3, 3)
    }

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    NoctisCaption(content.caption, style: .noctisInk3)
                    Spacer(minLength: NoctisSpacing.xs)
                    HStack(spacing: 6) {
                        SleepDashedLine()
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
                legend
                if let note = content.stagesNote {
                    Text(note)
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let month, month.longest != nil || month.shortest != nil {
                    markers(month)
                }
            }
        }
        .onChange(of: content.bars.count) { _, _ in selected = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityValue(current.map { content.bars[$0].accessibilityLabel } ?? "")
        .accessibilityHint("Swipe up or down to go through the nights.")
        .accessibilityAdjustableAction { direction in
            let last = content.bars.count - 1
            switch direction {
            case .increment: selected = min((current ?? -1) + 1, last)
            case .decrement: selected = max((current ?? last + 1) - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("sleep.bars")
    }

    // MARK: Chart

    private var chart: some View {
        VStack(spacing: NoctisSpacing.xs) {
            SleepPillRow(
                text: current.map { content.bars[$0].detail },
                fraction: current.map { (Double($0) + 0.5) / Double(count) } ?? 0.5
            )
            ZStack(alignment: .bottom) {
                separators
                bars
                lines
                if let note = content.emptyNote {
                    Text(note)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk3)
                        .multilineTextAlignment(.center)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(height: Self.chartHeight)
            labelRow
        }
        .sleepScrub(count: content.bars.count, chartWidth: chartWidth, selected: $selected)
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(content.bars.enumerated()), id: \.element.night) { index, bar in
                barView(bar, index: index)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.animation(NoctisMotion.adaptive(NoctisMotion.fade, reduceMotion: reduceMotion)))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
        .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: current)
    }

    private func barView(_ bar: SleepBarContent, index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack(alignment: .bottom) {
            shape.fill(NoctisAppColor.track)
            if let fraction = bar.fraction {
                let height = max(Self.chartHeight * fraction, radius * 2)
                fill(bar, height: height)
                    .frame(height: height)
                    .clipShape(shape)
                    .opacity(opacity(index))
                if let kind = markerKind(index) {
                    markerGlyph(kind)
                        .padding(.bottom, height + 5)
                        .opacity(opacity(index))
                }
            }
        }
        .frame(width: barWidth, height: Self.chartHeight)
    }

    /// Deep, Core, REM from the bottom in a week; one sage bar without
    /// stages, and always in a month.
    @ViewBuilder
    private func fill(_ bar: SleepBarContent, height: CGFloat) -> some View {
        if isWeek, let stages = bar.stages {
            VStack(spacing: 0) {
                NoctisAppColor.sage.frame(height: height * stages.rem)
                NoctisAppColor.orange.frame(height: height * stages.core)
                NoctisAppColor.nightDeep.frame(height: height * stages.deep)
            }
        } else {
            NoctisAppColor.sage
        }
    }

    /// Fully saturated until one is selected; then the others dim.
    private func opacity(_ index: Int) -> Double {
        guard let current else { return 1 }
        return current == index ? 1 : WeekColumns.dimmedOpacity
    }

    private func markerKind(_ index: Int) -> SleepBarMarker.Kind? {
        guard let month else { return nil }
        if month.longest?.index == index { return .longest }
        if month.shortest?.index == index { return .shortest }
        return nil
    }

    /// A filled dot over the longest night, a ring over the shortest.
    @ViewBuilder
    private func markerGlyph(_ kind: SleepBarMarker.Kind) -> some View {
        switch kind {
        case .longest: Circle().fill(NoctisAppColor.ink).frame(width: 6, height: 6)
        case .shortest: Circle().strokeBorder(NoctisAppColor.ink, lineWidth: 1.5).frame(width: 6, height: 6)
        }
    }

    // MARK: Lines

    /// The need line, and the average: across a week's bars, over each run
    /// of seven in a month.
    private var lines: some View {
        ZStack(alignment: .bottom) {
            SleepDashedLine()
                .stroke(NoctisAppColor.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(height: 1.5)
                .padding(.bottom, Self.chartHeight * content.needFraction)
            if isWeek, let average = content.averageFraction {
                Capsule().fill(NoctisAppColor.ink.opacity(0.75))
                    .frame(height: 1.5)
                    .padding(.bottom, Self.chartHeight * average)
                    .transition(.opacity)
            }
            if !isWeek, let month {
                ForEach(month.blocks, id: \.start) { block in
                    if let average = block.averageFraction {
                        NoctisSpanLayout(from: Double(block.start) / Double(count), to: Double(block.end) / Double(count)) {
                            Capsule().fill(NoctisAppColor.ink.opacity(0.75)).frame(height: 1.5)
                        }
                        .frame(height: 1.5)
                        .padding(.bottom, Self.chartHeight * average - 0.75)
                        .transition(.opacity)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Hairlines between the runs of seven nights.
    private var separators: some View {
        ZStack {
            if !isWeek, let month {
                ForEach(month.blocks.filter { $0.start > 0 }, id: \.start) { block in
                    let position = Double(block.start) / Double(count)
                    NoctisSpanLayout(from: position, to: position, minimumWidth: 1) {
                        Rectangle().fill(NoctisAppColor.hairline)
                    }
                    .frame(height: Self.chartHeight)
                    .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Labels

    /// Weekday initials under a week's bars (the newest night's bold, with
    /// a dot); dates over the runs of a month.
    @ViewBuilder
    private var labelRow: some View {
        Group {
            if isWeek {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(content.bars, id: \.night) { bar in
                        VStack(spacing: 3) {
                            Text(bar.label)
                                .noctisFont(13, bar.isNewest ? .bold : .medium, relativeTo: .footnote)
                                .foregroundStyle(bar.isNewest ? NoctisInkStyle(.primary) : .noctisInk3)
                            Circle()
                                .fill(NoctisAppColor.ink)
                                .frame(width: 4, height: 4)
                                .opacity(bar.isNewest ? 1 : 0)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .transition(.opacity)
            } else if let month {
                NoctisFractionLayout {
                    ForEach(month.labels, id: \.index) { label in
                        Text(label.text)
                            .noctisFont(12, .medium, relativeTo: .caption)
                            .foregroundStyle(.noctisInk3)
                            .fixedSize()
                            .noctisFraction((Double(label.index) + 0.5) / Double(count))
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(height: labelRowHeight, alignment: .top)
    }

    // MARK: Legend and markers

    private var legend: some View {
        SleepLegend {
            if isWeek && content.hasStages {
                key(NoctisAppColor.nightDeep, "Deep")
                key(NoctisAppColor.orange, "Core")
                key(NoctisAppColor.sage, "REM")
                lineKey("Average")
            } else if isWeek {
                key(NoctisAppColor.sage, "Slept")
                lineKey("Average")
            } else {
                key(NoctisAppColor.sage, "Slept")
                lineKey("Weekly average")
            }
        }
    }

    private func lineKey(_ title: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(NoctisAppColor.ink.opacity(0.75)).frame(width: 12, height: 2)
            Text(title)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func key(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 10, height: 10)
            Text(title)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
        }
    }

    /// The month's longest and shortest nights, named: pressing one selects
    /// its bar.
    private func markers(_ month: SleepMonthContent) -> some View {
        HStack(alignment: .top, spacing: NoctisSpacing.sm) {
            ForEach([month.longest, month.shortest].compactMap { $0 }, id: \.index) { marker in
                Button {
                    NoctisHaptics.snapLight()
                    withAnimation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion)) { selected = marker.index }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            markerGlyph(marker.kind)
                            Text(marker.title)
                                .noctisFont(13, .medium, relativeTo: .footnote)
                                .foregroundStyle(.noctisInk3)
                        }
                        NoctisMetric(marker.value, size: 22, relativeTo: .title3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(marker.date)
                            .noctisFont(12, relativeTo: .caption)
                            .foregroundStyle(.noctisInk3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(NoctisSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous)
                            .fill(NoctisAppColor.bg)
                            .overlay(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous).strokeBorder(NoctisAppColor.hairline, lineWidth: 1))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: NoctisRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(marker.accessibilityLabel)
                .accessibilityHint("Selects this night on the chart.")
            }
        }
    }
}

// MARK: - Quality strip

/// Thirty dots, one a night, in a row: sage from 80, butter from 60,
/// orange under 60, an empty ring for a night with nothing recorded. The
/// number is always in the pill (a color never carries it alone), and the
/// strip scrubs like the bars.
struct SleepQualityStripCard: View {
    let content: SleepQualityStripContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Int?
    @State private var chartWidth: CGFloat = 0

    private var count: Int { max(content.dots.count, 1) }
    private var current: Int? { selected.flatMap { $0 < content.dots.count ? $0 : nil } }

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    NoctisCaption("SLEEP QUALITY", style: .noctisInk3)
                    Spacer(minLength: NoctisSpacing.xs)
                    Text("Last 30 nights")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                }
                VStack(spacing: NoctisSpacing.xs) {
                    SleepPillRow(
                        text: current.map { content.dots[$0].detail },
                        fraction: current.map { (Double($0) + 0.5) / Double(count) } ?? 0.5,
                        resting: content.average
                    )
                    strip
                }
                .sleepScrub(count: content.dots.count, chartWidth: chartWidth, selected: $selected)
                SleepLegend {
                    ForEach(content.legend, id: \.band) { item in
                        HStack(spacing: 6) {
                            dot(item.band, size: 10)
                            Text(item.text)
                                .noctisFont(13, relativeTo: .footnote)
                                .foregroundStyle(.noctisInk3)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityValue(current.map { content.dots[$0].accessibilityLabel } ?? "")
        .accessibilityHint("Swipe up or down to go through the nights.")
        .accessibilityAdjustableAction { direction in
            let last = content.dots.count - 1
            switch direction {
            case .increment: selected = min((current ?? -1) + 1, last)
            case .decrement: selected = max((current ?? last + 1) - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("sleep.qualityStrip")
    }

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(Array(content.dots.enumerated()), id: \.element.night) { index, item in
                let size = min(max(WeekColumns.width(barsWidth: chartWidth, count: count) - 2, 4), 10)
                dot(item.band, size: size)
                    .scaleEffect(current == index ? 1.5 : 1)
                    .opacity(current == nil || current == index ? 1 : WeekColumns.dimmedOpacity)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 32)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
        .animation(NoctisMotion.adaptive(NoctisMotion.select, reduceMotion: reduceMotion), value: current)
    }

    /// A band's dot, or an empty ring for no band.
    @ViewBuilder
    private func dot(_ band: QualityDotRender.Band?, size: CGFloat) -> some View {
        if let band {
            Circle()
                .fill(band.tint)
                .overlay(Circle().strokeBorder(NoctisAppColor.ink.opacity(0.22), lineWidth: 0.5))
                .frame(width: size, height: size)
        } else {
            Circle()
                .strokeBorder(NoctisAppColor.track, lineWidth: 1.5)
                .frame(width: size, height: size)
        }
    }
}

extension QualityDotRender.Band {
    var tint: Color {
        switch self {
        case .high: NoctisAppColor.sage
        case .middle: NoctisAppColor.butter
        case .low: NoctisAppColor.orange
        }
    }
}
