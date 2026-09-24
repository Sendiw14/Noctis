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
                    segments: recovery.segments.map { NoctisRingSegment(color: $0.kind.tint, weight: $0.weight, fraction: $0.fraction) },
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
            HStack(alignment: .top, spacing: NoctisSpacing.sm) {
                Circle()
                    .fill(row.kind.tint)
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: NoctisSpacing.xxs) {
                    Text(row.value)
                        .noctisFont(17, .semibold, relativeTo: .body)
                        .foregroundStyle(NoctisAppColor.ink)
                    Text(row.baseline)
                        .noctisFont(13, relativeTo: .footnote)
                        .foregroundStyle(NoctisAppColor.ink3)
                    Text(row.sentence)
                        .noctisFont(15, relativeTo: .subheadline)
                        .foregroundStyle(NoctisAppColor.ink2)
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
                        .foregroundStyle(NoctisAppColor.ink3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.value), \(row.baseline), score \(row.score). \(row.sentence)")
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
