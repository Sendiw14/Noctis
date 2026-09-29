import DesignSystem
import HomeFeature
import NoctisCore
import SwiftUI

/// The sheet behind the Consistency, Balance and Timing cards: the number,
/// a larger chart, the calculation in plain words, and a closing line that
/// keeps it in proportion.
struct SleepDetailSheet: View {
    let detail: SleepDetail
    let screen: SleepScreen
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoctisSpacing.md) {
                    if let insights = screen.insights {
                        switch detail {
                        case .consistency:
                            if let consistency = insights.consistency {
                                SleepConsistencySheetContent(content: consistency)
                            }
                        case .balance:
                            SleepBalanceSheetContent(content: insights.balance)
                        case .timing:
                            SleepTimingSheetContent(content: insights.timing)
                        }
                        Text(SleepInsightsContent.noFear)
                            .noctisFont(17, .semibold, relativeTo: .body)
                            .foregroundStyle(.noctisInk2)
                            .padding(.top, NoctisSpacing.xs)
                            .padding(.horizontal, NoctisSpacing.xxs)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("sleep.noFear")
                    }
                }
                .frame(maxWidth: SleepTabView.contentMaxWidth)
                .padding(.horizontal, NoctisSpacing.lg)
                .padding(.top, NoctisSpacing.xs)
                .padding(.bottom, NoctisSpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .background { PaperBackground(adaptive: true).ignoresSafeArea() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("sleep.detailSheet")
    }

    private var title: String {
        switch detail {
        case .consistency: "Consistency"
        case .balance: "Balance"
        case .timing: "Timing"
        }
    }
}

/// The calculation, paragraph by paragraph.
struct SleepCalculationCard: View {
    let paragraphs: [String]

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                NoctisCaption("HOW THIS IS CALCULATED", style: .noctisInk3)
                ForEach(paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(.noctisInk2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Balance

struct SleepBalanceSheetContent: View {
    let content: SleepBalanceContent

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption("THE LAST 7 NIGHTS", style: .noctisInk3)
                SleepBalanceHeadline(content: content, size: 56)
                Text(content.caption)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, NoctisSpacing.xxs)
            if let chart = content.chart, chart.points.contains(where: { $0 != nil }) {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        NoctisCaption("14 NIGHTS", style: .noctisInk3)
                        SleepBalanceLine(chart: chart, direction: content.direction, height: 150)
                        HStack {
                            Text(content.firstLabel)
                            Spacer(minLength: NoctisSpacing.xs)
                            Text(content.lastLabel)
                        }
                        .noctisFont(12, relativeTo: .caption)
                        .foregroundStyle(.noctisInk3)
                        HStack(spacing: 6) {
                            SleepDashedLine()
                                .stroke(NoctisAppColor.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 16, height: 1)
                            Text("Dashed line: right on your need")
                                .noctisFont(13, relativeTo: .footnote)
                                .foregroundStyle(.noctisInk3)
                        }
                    }
                }
            }
            SleepCalculationCard(paragraphs: content.explanation)
        }
        .accessibilityIdentifier("sleep.balanceSheet")
    }
}

// MARK: - Consistency

struct SleepConsistencySheetContent: View {
    let content: SleepConsistencyContent

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption("THE LAST 7 NIGHTS", style: .noctisInk3)
                if let spread = content.spread {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        NoctisMetric(spread, size: 56, relativeTo: .title)
                        Text("bedtime spread")
                            .noctisFont(22, .semibold, relativeTo: .body)
                            .foregroundStyle(.noctisInk2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Bedtime varied by \(spread.spoken)")
                } else {
                    Text(content.headline)
                        .noctisFont(28, .bold, relativeTo: .title3)
                        .foregroundStyle(NoctisAppColor.ink)
                }
                Text(content.subline)
                    .noctisFont(15, relativeTo: .subheadline)
                    .foregroundStyle(.noctisInk2)
                    .fixedSize(horizontal: false, vertical: true)
                if let midpoint = content.midpoint {
                    Text(midpoint)
                        .noctisFont(15, .medium, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink)
                }
            }
            .padding(.horizontal, NoctisSpacing.xxs)
            NoctisAppCard {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    NoctisCaption("EACH NIGHT", style: .noctisInk3)
                    SleepTimingDots(chart: content.chart, rowLabels: content.rowLabels, ticks: content.ticks)
                    SleepTimingDotsKey(usualCaption: content.usualCaption)
                }
            }
            if !content.windows.isEmpty {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        NoctisCaption("HOW MUCH IT VARIED", style: .noctisInk3)
                        ForEach(content.windows) { window in
                            windowRow(window)
                        }
                    }
                }
            }
            SleepCalculationCard(paragraphs: content.calculation)
        }
        .accessibilityIdentifier("sleep.consistencySheet")
    }

    private func windowRow(_ window: SleepConsistencyWindowContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .noctisFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoctisAppColor.ink)
                Spacer(minLength: NoctisSpacing.xs)
                Text(window.detail)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(.noctisInk3)
            }
            Text("Bedtime \(window.bedtime) · Wake \(window.wake) · Sleep length \(window.duration)")
                .noctisFont(15, relativeTo: .subheadline)
                .foregroundStyle(.noctisInk2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.accessibilityLabel)
    }
}

// MARK: - Timing

struct SleepTimingSheetContent: View {
    let content: SleepTimingContent

    var body: some View {
        VStack(alignment: .leading, spacing: NoctisSpacing.md) {
            VStack(alignment: .leading, spacing: NoctisSpacing.xs) {
                NoctisCaption("YOUR TYPICAL NIGHT", style: .noctisInk3)
                SleepTimingSummary(content: content, metricSize: 40)
                if content.isAvailable {
                    Text(content.nightsLine)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(.noctisInk3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, NoctisSpacing.xxs)
            if let chart = content.chart {
                NoctisAppCard {
                    VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                        NoctisCaption("ON THE CLOCK", style: .noctisInk3)
                        SleepTimingWindowChart(chart: chart, ticks: content.ticks)
                        if let suggested = content.suggested {
                            Text(suggested)
                                .noctisFont(15, relativeTo: .subheadline)
                                .foregroundStyle(.noctisInk2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            SleepCalculationCard(paragraphs: content.calculation)
        }
        .accessibilityIdentifier("sleep.timingSheet")
    }
}
