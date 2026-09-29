import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

// The Consistency, Balance and Timing cards (Week), the month's rhythm
// card, and the charts they and their detail sheets share. Each card is one
// button: a summary that opens the sheet with the whole story.

// MARK: - Card

/// A card that opens a detail sheet: its caption with a chevron, then the
/// summary.
struct SleepInsightCard<Content: View>: View {
    let title: String
    let label: String
    let identifier: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button {
            NoctisHaptics.light()
            action()
        } label: {
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    HStack {
                        NoctisCaption(title, style: .noctisInk3)
                        Spacer(minLength: NoctisSpacing.xs)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.noctisInk3)
                            .accessibilityHidden(true)
                    }
                    content
                }
            }
        }
        .buttonStyle(NoctisCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint("Opens the details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Consistency

struct SleepConsistencyCard: View {
    let content: SleepConsistencyContent
    let open: () -> Void

    var body: some View {
        SleepInsightCard(title: "CONSISTENCY", label: content.accessibilityLabel, identifier: "sleep.consistency", action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.headline)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(content.subline)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
            }
            .fixedSize(horizontal: false, vertical: true)
            SleepTimingDots(chart: content.chart, rowLabels: content.rowLabels, ticks: content.ticks)
            SleepTimingDotsKey(usualCaption: content.usualCaption)
        }
    }
}

/// A row a night, oldest at the top: a dot at the bedtime and one at
/// waking on one clock axis, joined by a track, over shaded bands where
/// your bedtime and wake time usually fall.
struct SleepTimingDots: View {
    let chart: TimingDotsRender
    let rowLabels: [String]
    let ticks: [SleepAxisTick]
    @Environment(\.dynamicTypeSize) private var typeSize
    @NoctisScaledLength(relativeTo: .caption) private var rowHeight: CGFloat = 24

    static let bedtimeTint = NoctisAppColor.nightDeep
    static let wakeTint = NoctisAppColor.orange

    var body: some View {
        let plotHeight = rowHeight * CGFloat(chart.rows.count)
        HStack(alignment: .top, spacing: NoctisSpacing.xs) {
            VStack(spacing: 0) {
                ForEach(Array(rowLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .noctisFont(12, .medium, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        .frame(minWidth: 14, minHeight: rowHeight)
                }
            }
            VStack(spacing: 4) {
                ZStack {
                    grid.frame(height: plotHeight)
                    bands.frame(height: plotHeight)
                    VStack(spacing: 0) {
                        ForEach(chart.rows, id: \.night) { row in
                            rowView(row).frame(height: rowHeight)
                        }
                    }
                }
                .frame(height: plotHeight)
                SleepClockAxis(ticks: ticks, thinned: typeSize.isAccessibilitySize)
            }
        }
    }

    private var grid: some View {
        ZStack {
            ForEach(ticks, id: \.position) { tick in
                NoctisSpanLayout(from: tick.position, to: tick.position, minimumWidth: 1) {
                    Rectangle().fill(NoctisAppColor.hairline)
                }
            }
        }
    }

    private var bands: some View {
        ZStack {
            if let band = chart.bedtimeBand {
                NoctisSpanLayout(from: band.lowerBound, to: band.upperBound, minimumWidth: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Self.bedtimeTint.opacity(0.14))
                }
            }
            if let band = chart.wakeBand {
                NoctisSpanLayout(from: band.lowerBound, to: band.upperBound, minimumWidth: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Self.wakeTint.opacity(0.14))
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: TimingDotsRender.Row) -> some View {
        ZStack {
            if let bedtime = row.bedtime, let wake = row.wake {
                NoctisSpanLayout(from: bedtime, to: wake) {
                    Capsule().fill(NoctisAppColor.track).frame(height: 4)
                }
                NoctisFractionLayout { dot(Self.bedtimeTint).noctisFraction(bedtime) }
                NoctisFractionLayout { dot(Self.wakeTint).noctisFraction(wake) }
            }
        }
    }

    private func dot(_ tint: Color) -> some View {
        Circle()
            .fill(tint)
            .overlay(Circle().strokeBorder(NoctisAppColor.ink.opacity(0.22), lineWidth: 0.5))
            .frame(width: 10, height: 10)
    }
}

/// The dots' key: bedtime, waking, and the shaded usual.
struct SleepTimingDotsKey: View {
    let usualCaption: String?

    var body: some View {
        SleepLegend {
            key(SleepTimingDots.bedtimeTint, "Bedtime")
            key(SleepTimingDots.wakeTint, "Wake")
            if usualCaption != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(NoctisAppColor.ink.opacity(0.14))
                        .frame(width: 14, height: 10)
                    Text("Your usual")
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                }
            }
        }
    }

    private func key(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title)
                .noctisFont(13, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
        }
    }
}

/// Hour labels under a clock axis.
struct SleepClockAxis: View {
    let ticks: [SleepAxisTick]
    /// Every other label, when the type is too large for all of them.
    let thinned: Bool

    var body: some View {
        NoctisFractionLayout {
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                if !thinned || index.isMultiple(of: 2) {
                    Text(tick.text)
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize()
                        .noctisFraction(tick.position)
                }
            }
        }
    }
}

// MARK: - Balance

struct SleepBalanceCard: View {
    let content: SleepBalanceContent
    let open: () -> Void

    var body: some View {
        SleepInsightCard(title: "BALANCE", label: content.accessibilityLabel, identifier: "sleep.balance", action: open) {
            SleepBalanceHeadline(content: content, size: 34)
            Text(content.caption)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(.noctisInk2)
                .fixedSize(horizontal: false, vertical: true)
            if let chart = content.chart, chart.points.contains(where: { $0 != nil }) {
                SleepBalanceLine(chart: chart, direction: content.direction, height: 56)
            }
        }
    }
}

/// "1h 10m behind": the size as a metric and the word beside it; or the
/// sentence when there's no size to give.
struct SleepBalanceHeadline: View {
    let content: SleepBalanceContent
    let size: CGFloat

    var body: some View {
        if let value = content.value, let word = content.directionWord {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                NoctisMetric(value, size: size, relativeTo: .title)
                Text(word)
                    .noctisFont(size >= 48 ? 22 : 17, .semibold, relativeTo: .body)
                    .foregroundStyle(.noctisInk2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(value.spoken) \(word)")
        } else {
            Text(content.headline)
                .noctisFont(size >= 48 ? 28 : 22, .bold, relativeTo: .title3)
                .foregroundStyle(NoctisAppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The balance as a smooth line around a dashed zero (your need), with a
/// dot on the latest night. Neutral ink, and the dot leans orange behind
/// and sage ahead: a place, never an alarm.
struct SleepBalanceLine: View {
    let chart: BalanceRender
    let direction: SleepBalanceContent.Direction
    let height: CGFloat

    var body: some View {
        ZStack {
            SleepRule(fraction: chart.zero)
                .stroke(NoctisAppColor.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            SleepSmoothLine(points: chart.points, bottomUp: true)
                .stroke(NoctisAppColor.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            SleepLastPoint(points: chart.points, bottomUp: true)
                .fill(tint)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        switch direction {
        case .behind: NoctisAppColor.orange
        case .ahead: NoctisAppColor.sage
        case .even, .unavailable: NoctisAppColor.ink
        }
    }
}

// MARK: - Timing

struct SleepTimingCard: View {
    let content: SleepTimingContent
    let open: () -> Void

    var body: some View {
        SleepInsightCard(title: "TIMING", label: content.accessibilityLabel, identifier: "sleep.timing", action: open) {
            SleepTimingSummary(content: content)
        }
    }
}

/// Typical bedtime and wake time, the midpoint and the recent shift.
struct SleepTimingSummary: View {
    let content: SleepTimingContent
    var metricSize: CGFloat = 28

    var body: some View {
        if content.isAvailable, let bedtime = content.typicalBedtime, let wake = content.typicalWake {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: NoctisSpacing.md) {
                        stat("Typical bedtime", bedtime)
                        stat("Typical wake time", wake)
                    }
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        stat("Typical bedtime", bedtime)
                        stat("Typical wake time", wake)
                    }
                }
                if let midpoint = content.midpoint {
                    Text("Sleep midpoint \(midpoint.spoken)")
                        .noctisFont(15, .medium, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                }
                if let shift = content.shift {
                    Text(shift)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(content.nightsLine)
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(.noctisInk2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stat(_ title: String, _ value: NoctisMetricValue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .noctisFont(13, .medium, relativeTo: .footnote)
                .foregroundStyle(.noctisInk3)
            NoctisMetric(value, size: metricSize)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Your typical night on a clock axis: bedtime to waking as one capsule,
/// the midpoint as a notch in it, and (once there are 14 nights) the
/// middle half of your own bedtimes and wake times as lighter bands
/// around each end.
struct SleepTimingWindowChart: View {
    let chart: TimingWindowRender
    let ticks: [SleepAxisTick]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                NoctisSpanLayout(to: 1) {
                    Capsule().fill(NoctisAppColor.track).frame(height: 14)
                }
                if let range = chart.bedtimeRange {
                    NoctisSpanLayout(from: range.lowerBound, to: range.upperBound, minimumWidth: 8) {
                        Capsule().fill(SleepTimingDots.bedtimeTint.opacity(0.28)).frame(height: 36)
                    }
                }
                if let range = chart.wakeRange {
                    NoctisSpanLayout(from: range.lowerBound, to: range.upperBound, minimumWidth: 8) {
                        Capsule().fill(SleepTimingDots.wakeTint.opacity(0.28)).frame(height: 36)
                    }
                }
                NoctisSpanLayout(from: chart.bedtime, to: chart.wake, minimumWidth: 8) {
                    Capsule().fill(SleepTimingDots.bedtimeTint).frame(height: 20)
                }
                NoctisFractionLayout {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(NoctisAppColor.bg)
                        .frame(width: 2, height: 20)
                        .noctisFraction(chart.midpoint)
                }
            }
            .frame(height: 36)
            SleepClockAxis(ticks: ticks, thinned: typeSize.isAccessibilitySize)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Rhythm (month)

struct SleepRhythmCard: View {
    let content: SleepRhythmContent
    let open: () -> Void

    var body: some View {
        SleepInsightCard(title: "TIMING RHYTHM", label: content.accessibilityLabel, identifier: "sleep.rhythm", action: open) {
            VStack(alignment: .leading, spacing: 2) {
                if let bedtime = content.bedtimeSummary {
                    Text(bedtime)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                }
                if let wake = content.wakeSummary {
                    Text(wake)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            SleepRhythmChart(content: content)
            SleepTimingDotsKey(usualCaption: content.usualCaption)
        }
    }
}

/// Bedtime and wake time over the month as two smooth lines: earlier
/// higher, later lower, with shaded bands where they usually fall.
struct SleepRhythmChart: View {
    let content: SleepRhythmContent
    @Environment(\.dynamicTypeSize) private var typeSize
    @NoctisScaledLength(relativeTo: .caption) private var tickWidth: CGFloat = 44

    static let height: CGFloat = 170

    var body: some View {
        let ticks = content.ticks.enumerated().filter { !typeSize.isAccessibilitySize || $0.offset.isMultiple(of: 2) }.map(\.element)
        HStack(alignment: .top, spacing: 6) {
            NoctisVerticalFractionLayout {
                ForEach(ticks, id: \.position) { tick in
                    Text(tick.text)
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        .frame(width: tickWidth, alignment: .trailing)
                        .noctisVerticalFraction(tick.position)
                }
            }
            .frame(width: tickWidth, height: Self.height)
            ZStack {
                ForEach(ticks, id: \.position) { tick in
                    NoctisVerticalSpanLayout(from: tick.position, to: tick.position, minimumLength: 1) {
                        Rectangle().fill(NoctisAppColor.hairline)
                    }
                }
                if let band = content.chart.bedtimeBand {
                    NoctisVerticalSpanLayout(from: band.lowerBound, to: band.upperBound, minimumLength: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(SleepTimingDots.bedtimeTint.opacity(0.14))
                    }
                }
                if let band = content.chart.wakeBand {
                    NoctisVerticalSpanLayout(from: band.lowerBound, to: band.upperBound, minimumLength: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(SleepTimingDots.wakeTint.opacity(0.14))
                    }
                }
                SleepSmoothLine(points: content.chart.bedtime, bottomUp: false)
                    .stroke(SleepTimingDots.bedtimeTint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                SleepSmoothLine(points: content.chart.wake, bottomUp: false)
                    .stroke(SleepTimingDots.wakeTint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .frame(height: Self.height)
        }
        .accessibilityHidden(true)
    }
}
