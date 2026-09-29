import DesignSystem
import NoctisCore
import RecoveryKit
import SwiftUI

/// Recovery in detail, zooming out of Home's ring: the ring at 240pt,
/// one row per factor (today, baseline, score, one plain sentence), and
/// how the score is calculated. Reads `HomeViewModel.screen?.detail` only.
/// Opened from a factor capsule, it scrolls to that factor's row.
struct RecoveryDetailView: View {
    let viewModel: HomeViewModel
    var focus: RecoveryFactorKind?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let detail = viewModel.screen?.detail {
                    content(detail)
                        // R21: one centered column, never wider than 680pt.
                        .frame(maxWidth: HomeContent.compactMaxWidth)
                        .padding(.horizontal, NoctisSpacing.lg)
                        .padding(.top, NoctisSpacing.xs)
                        .padding(.bottom, NoctisSpacing.xl)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Recovery isn't available right now.")
                        .noctisFont(17, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink2)
                        .padding(NoctisSpacing.xl)
                }
            }
            .task {
                guard let focus else { return }
                proxy.scrollTo(focus, anchor: .top)
            }
        }
        .scrollClipDisabled()
        .background { PaperBackground(adaptive: true).ignoresSafeArea() }
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ detail: RecoveryDetailContent) -> some View {
        VStack(spacing: NoctisSpacing.md) {
            summary(detail.recovery)
            ForEach(detail.rows, id: \.kind) { row in
                FactorDetailRowView(row: row)
                    .id(row.kind)
            }
            CalculationCardView(paragraphs: detail.calculation, modelVersion: detail.modelVersion)
        }
    }

    private func summary(_ recovery: ScoredRecoveryContent) -> some View {
        VStack(spacing: NoctisSpacing.md) {
            NoctisRingLayout(maxDiameter: 240, centerWidth: 0.67, centerHeight: 0.52) {
                NoctisRecoveryRing(
                    segments: recovery.segments.map(\.ringSegment),
                    diameter: 240,
                    lineWidth: 20
                )
                VStack(spacing: 0) {
                    Text("\(recovery.score)")
                        .noctisNumeral(64, .heavy)
                        .foregroundStyle(NoctisAppColor.ink)
                    Text("Recovery")
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                // The center box scales with the ring; text shrinks to fit (R4).
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(recovery.accessibilityLabel)
            if let chip = recovery.chip {
                DeltaChipView(chip: chip)
            }
            VStack(spacing: NoctisSpacing.xxs) {
                Text(recovery.sentence)
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
                Text(recovery.confidence)
                    .noctisFont(13, relativeTo: .footnote)
                    .foregroundStyle(NoctisAppColor.ink3)
                if let note = recovery.heartCapNote {
                    Text(note)
                        .noctisFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.orangeText)
                        .padding(.top, NoctisSpacing.xs)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NoctisSpacing.xs)
    }
}

struct FactorDetailRowView: View {
    let row: FactorDetailRow

    var body: some View {
        NoctisAppCard {
            VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                    Circle()
                        .fill(row.kind.tint)
                        .frame(width: 12, height: 12)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.name)
                                .noctisFont(17, .semibold, relativeTo: .body)
                                .foregroundStyle(NoctisAppColor.ink)
                            NoctisMetric(row.value, size: 17, relativeTo: .body)
                            if let suffix = row.valueSuffix {
                                Text(suffix)
                                    .noctisFont(17, .semibold, relativeTo: .body)
                                    .foregroundStyle(NoctisAppColor.ink)
                            }
                        }
                        Text(row.baseline)
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                        Text(row.sentence)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(.noctisInk2)
                            .padding(.top, 2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: NoctisSpacing.xs)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(row.score)")
                            .noctisFont(22, .semibold, relativeTo: .title3)
                            .foregroundStyle(NoctisAppColor.ink)
                        Text("score")
                            .noctisFont(13, relativeTo: .footnote)
                            .foregroundStyle(.noctisInk3)
                    }
                }
                if let sparkline = row.sparkline {
                    FactorSparkline(content: sparkline, tint: row.kind.tint)
                        .frame(height: FactorSparkline.height)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// A sparkline's paths at one size, built ahead of time.
struct SparklinePaths: Equatable {
    let key: Key
    let band: Path
    let dots: Path
    let line: Path
    let today: Path

    struct Key: Equatable {
        let content: SparklineContent
        let size: CGSize
    }

    static func == (lhs: SparklinePaths, rhs: SparklinePaths) -> Bool { lhs.key == rhs.key }

    static func build(_ key: Key) -> SparklinePaths {
        let content = key.content
        let size = key.size
        let inset: CGFloat = 4
        let plotHeight = size.height - inset * 2
        func y(_ value: Double) -> CGFloat { inset + plotHeight * (1 - CGFloat(value)) }
        // Nights fill the width; today sits one step past the last.
        let steps = CGFloat(content.nights.count)
        let step = (size.width - inset * 2) / max(steps, 1)
        func x(_ index: Int) -> CGFloat { inset + step * CGFloat(index) }

        let bandTop = y(content.band.upperBound)
        let bandBottom = y(content.band.lowerBound)
        let band = Path(roundedRect: CGRect(x: 0, y: bandTop, width: size.width, height: max(bandBottom - bandTop, 1)), cornerRadius: 4)

        var line = Path()
        var dots = Path()
        var drawing = false
        for (index, value) in content.nights.enumerated() {
            guard let value else {
                drawing = false
                continue
            }
            let point = CGPoint(x: x(index), y: y(value))
            if drawing { line.addLine(to: point) } else { line.move(to: point) }
            drawing = true
            dots.addEllipse(in: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3))
        }
        let todayPoint = CGPoint(x: x(content.nights.count), y: y(content.today))
        if drawing { line.addLine(to: todayPoint) }
        return SparklinePaths(
            key: key, band: band, dots: dots, line: line,
            today: Path(ellipseIn: CGRect(x: todayPoint.x - 3, y: todayPoint.y - 3, width: 6, height: 6))
        )
    }
}

/// 14 nights, full row width: your normal range as a track-colored band, a
/// 1pt ink3 line through the nights, and today as a 6pt dot in the
/// factor's color. Drawn from paths resolved when the width or the values
/// change.
struct FactorSparkline: View {
    let content: SparklineContent
    let tint: Color

    static let height: CGFloat = 36
    @State private var size: CGSize = .zero
    @State private var paths: SparklinePaths?

    var body: some View {
        Group {
            if let paths {
                Canvas { context, _ in
                    context.fill(paths.band, with: .color(NoctisAppColor.track))
                    context.fill(paths.dots, with: .color(NoctisAppColor.ink3))
                    context.stroke(paths.line, with: .color(NoctisAppColor.ink3), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                    context.fill(paths.today, with: .color(tint))
                }
            } else {
                Color.clear
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onChange(of: SparklinePaths.Key(content: content, size: size), initial: true) { _, key in
            guard key.size.width > 0, key.size.height > 0 else { return }
            paths = SparklinePaths.build(key)
        }
        .accessibilityHidden(true)
    }
}

struct CalculationCardView: View {
    let paragraphs: [String]
    let modelVersion: String
    @State private var expanded = false

    var body: some View {
        NoctisAppCard {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: NoctisSpacing.sm) {
                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .noctisFont(15, relativeTo: .subheadline)
                            .foregroundStyle(NoctisAppColor.ink2)
                    }
                    Text(modelVersion)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisAppColor.ink3)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, NoctisSpacing.sm)
            } label: {
                Text("How this is calculated")
                    .noctisFont(17, .semibold, relativeTo: .body)
                    .foregroundStyle(NoctisAppColor.ink)
            }
            .tint(NoctisAppColor.ink2)
        }
    }
}
